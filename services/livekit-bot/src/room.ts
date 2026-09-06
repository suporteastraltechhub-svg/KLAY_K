import * as rtc from "@livekit/rtc-node";
import { AccessToken } from "livekit-server-sdk";
import { config } from "./config.js";
import { goodbye, welcome } from "./events.js";
import { SpeechQueueManager } from "./speech.js";

const BOT_IDENTITY = "klayk-bot";
const FRAME_TARGET_MS = 20;

/** WAV slice decoded to raw PCM samples (16-bit little-endian, mono). */
interface ParsedWav {
  sampleRate: number;
  channels: number;
  pcm: Int16Array;
}

function parseWav(buffer: Buffer): ParsedWav | null {
  if (buffer.length < 44) return null;
  if (
    buffer.toString("ascii", 0, 4) !== "RIFF" ||
    buffer.toString("ascii", 8, 12) !== "WAVE"
  ) {
    return null;
  }
  let fmt: { audioFormat: number; channels: number; sampleRate: number; bitsPerSample: number } | null = null;
  let data: Buffer | null = null;
  let offset = 12;
  while (offset + 8 <= buffer.length) {
    const id = buffer.toString("ascii", offset, offset + 4);
    const size = buffer.readUInt32LE(offset + 4);
    if (id === "fmt " && fmt === null && size >= 16) {
      fmt = {
        audioFormat: buffer.readUInt16LE(offset + 8),
        channels: buffer.readUInt16LE(offset + 10),
        sampleRate: buffer.readUInt32LE(offset + 12),
        bitsPerSample: buffer.readUInt16LE(offset + 22),
      };
    } else if (id === "data" && data === null) {
      const start = offset + 8;
      const end = Math.min(start + size, buffer.length);
      data = buffer.subarray(start, end);
    }
    offset += 8 + size + (size % 2);
  }
  if (fmt === null || data === null) return null;
  // Only 16-bit PCM is supported (OpenAI TTS wav output).
  if (fmt.audioFormat !== 1 || fmt.bitsPerSample !== 16 || fmt.channels !== 1) return null;
  const pcm = new Int16Array(data.byteLength / 2);
  for (let i = 0; i < pcm.length; i += 1) {
    pcm[i] = data.readInt16LE(i * 2);
  }
  return { sampleRate: fmt.sampleRate, channels: fmt.channels, pcm };
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * One bot participant inside a LiveKit room. Owns its own SpeechQueueManager so
 * audio is always published back into the room where the phrase originated.
 */
export class BotRoom {
  readonly queue: SpeechQueueManager;
  private readonly room = new rtc.Room();
  private audioSource: rtc.AudioSource | null = null;
  private audioTrack: rtc.LocalAudioTrack | null = null;

  private constructor(readonly roomName: string) {
    this.queue = new SpeechQueueManager((audio) => this.publishAudio(audio));
    // Critical: without start() the worker loop never polls the queue and the
    // bot stays muted even though events are enqueued correctly.
    this.queue.start();
  }

  static async join(roomName: string): Promise<BotRoom> {
    const instance = new BotRoom(roomName);
    await instance.connect();
    return instance;
  }

  private async connect(): Promise<void> {
    const token = await buildToken(this.roomName);
    this.room.on(rtc.RoomEvent.ParticipantConnected, (participant) => {
      const name = (participant.name ?? participant.identity ?? "Participante").trim() || "Participante";
      this.queue.queueSpeech("medium", welcome(name), { key: `join-${participant.identity}` });
    });
    this.room.on(rtc.RoomEvent.ParticipantDisconnected, (participant) => {
      const name = (participant.name ?? participant.identity ?? "Participante").trim() || "Participante";
      this.queue.queueSpeech("low", goodbye(name), { key: `left-${participant.identity}` });
    });
    this.room.on(rtc.RoomEvent.DataReceived, (payload, _participant, _kind, topic) => {
      const text = new TextDecoder().decode(payload).trim();
      if (text.length < 2) return;
      this.queue.queueSpeech("low", text, { key: topic && topic.length > 0 ? `data-${topic}` : undefined });
    });
    await this.room.connect(config.livekitUrl, token);
    console.log(`[klayk-bot] joined room "${this.roomName}"`);
  }

  /**
   * Publish a TTS Buffer (WAV, 16-bit PCM mono) into the room as an audio track.
   * Gated by config.publishAudio; every failure is caught — never crashes the worker.
   */
  async publishAudio(buffer: Buffer): Promise<void> {
    if (!config.publishAudio) {
      console.log(
        `[klayk-bot] audio skipped (BOT_PUBLISH_AUDIO=false), ${buffer.length} bytes for "${this.roomName}"`,
      );
      return;
    }
    const wav = parseWav(buffer);
    if (wav === null) {
      console.warn(`[klayk-bot] ignoring unparseable/empty audio for "${this.roomName}"`);
      return;
    }
    const local = this.room.localParticipant;
    if (local === undefined) return;

    try {
      if (this.audioSource === null || this.audioSource.sampleRate !== wav.sampleRate) {
        await this.teardownAudio();
        this.audioSource = new rtc.AudioSource(wav.sampleRate, wav.channels);
        this.audioTrack = rtc.LocalAudioTrack.createAudioTrack("klayk-bot-audio", this.audioSource);
        await local.publishTrack(
          this.audioTrack,
          new rtc.TrackPublishOptions({ source: rtc.TrackSource.SOURCE_MICROPHONE }),
        );
      }
      const samplesPerFrame = Math.max(1, Math.round((wav.sampleRate * FRAME_TARGET_MS) / 1000));
      for (let offset = 0; offset < wav.pcm.length; offset += samplesPerFrame) {
        const chunk = wav.pcm.subarray(offset, offset + samplesPerFrame);
        if (chunk.length === 0) break;
        const frame = new rtc.AudioFrame(chunk, wav.sampleRate, wav.channels, chunk.length);
        await this.audioSource.captureFrame(frame);
        // Pace playback so short utterances aren't dumped at once.
        await sleep((chunk.length / wav.sampleRate) * 1000);
      }
    } catch (error) {
      console.error(`[klayk-bot] publishAudio failed in "${this.roomName}":`, error);
    }
  }

  /** Send a text data message with topic `bot:speech` to the room. */
  async publishDataMessage(text: string): Promise<void> {
    const local = this.room.localParticipant;
    if (local === undefined) return;
    await local.publishData(new TextEncoder().encode(text), {
      reliable: true,
      topic: "bot:speech",
    });
  }

  async leave(): Promise<void> {
    try {
      await this.teardownAudio();
    } catch (error) {
      console.error(`[klayk-bot] audio teardown failed for "${this.roomName}":`, error);
    }
    try {
      await this.room.disconnect();
    } catch (error) {
      console.error(`[klayk-bot] disconnect failed for "${this.roomName}":`, error);
    }
    this.queue.stop();
  }

  private async teardownAudio(): Promise<void> {
    if (this.audioTrack !== null) {
      await this.audioTrack.close(true);
      this.audioTrack = null;
    }
    if (this.audioSource !== null) {
      try {
        await this.audioSource.close();
      } catch {
        // already closed
      }
      this.audioSource = null;
    }
  }
}

async function buildToken(roomName: string): Promise<string> {
  const token = new AccessToken(config.livekitApiKey, config.livekitApiSecret, {
    identity: BOT_IDENTITY,
    name: config.botName,
    ttl: 3600,
  });
  token.addGrant({
    roomJoin: true,
    room: roomName,
    canPublish: true,
    canPublishData: true,
    canSubscribe: true,
  });
  return await token.toJwt();
}