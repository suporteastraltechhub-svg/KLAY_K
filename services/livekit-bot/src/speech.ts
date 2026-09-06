import { config } from "./config.js";
import { SpeechQueue, type CooldownMap, type Priority, type SpeechItem } from "./queue.js";

const OPENAI_TTS_URL = "https://api.openai.com/v1/audio/speech";
const DEFAULT_POLL_INTERVAL_MS = 500;

export type TtsFetcher = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;

/**
 * Convert text to a WAV audio Buffer.
 * - "noop": logs `[bot-say] text`, returns an empty Buffer (default).
 * - "openai": POSTs to the OpenAI TTS API and returns the audio bytes.
 * - any other provider: throws.
 * `fetcher` is injectable for tests (defaults to the global fetch).
 * `provider` defaults to `config.ttsProvider` and is overridable for tests.
 */
export async function textToSpeech(
  text: string,
  fetcher: TtsFetcher = fetch,
  provider: string = config.ttsProvider,
): Promise<Buffer> {
  switch (provider) {
    case "noop": {
      console.log(`[bot-say] ${text}`);
      return Buffer.alloc(0);
    }
    case "openai": {
      const apiKey = config.openaiApiKey;
      if (!apiKey) throw new Error('TTS provider "openai" requires env var OPENAI_API_KEY');
      const response = await fetcher(OPENAI_TTS_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          model: config.ttsModel,
          voice: config.ttsVoice,
          input: text,
          response_format: "wav",
        }),
      });
      if (!response.ok) {
        throw new Error(`OpenAI TTS request failed: ${response.status} ${response.statusText}`);
      }
      return Buffer.from(await response.arrayBuffer());
    }
    default: {
      throw new Error(`Unsupported TTS provider: ${provider}`);
    }
  }
}

export interface SpeechQueueManagerOptions {
  cooldownMsByPriority?: CooldownMap;
  maxBacklog?: number;
  pollIntervalMs?: number;
  /** Inject a fake HTTP layer for tests. */
  ttsFetcher?: TtsFetcher;
  /** Observability hook invoked for every item pulled off the queue. */
  onSpeak?: (item: SpeechItem) => void;
}

/**
 * Wraps a SpeechQueue with a setTimeout-chained worker loop. Each tick pulls
 * one eligible item, runs TTS and hands the resulting Buffer to `publishAudio`.
 * TTS/publish errors never crash the loop.
 */
export class SpeechQueueManager {
  private readonly queue: SpeechQueue;
  private readonly publishAudio: (buffer: Buffer) => void | Promise<void>;
  private readonly onSpeak: ((item: SpeechItem) => void) | undefined;
  private readonly pollIntervalMs: number;
  private readonly ttsFetcher: TtsFetcher;

  private timer: NodeJS.Timeout | null = null;
  private running = false;

  constructor(
    publishAudio: (buffer: Buffer) => void | Promise<void>,
    options: SpeechQueueManagerOptions = {},
  ) {
    this.publishAudio = publishAudio;
    this.onSpeak = options.onSpeak;
    this.pollIntervalMs = options.pollIntervalMs ?? DEFAULT_POLL_INTERVAL_MS;
    this.ttsFetcher = options.ttsFetcher ?? fetch;

    const cooldown =
      options.cooldownMsByPriority ??
      ({
        high: config.ttsCooldownMs,
        medium: config.ttsCooldownMs,
        low: config.ttsCooldownMs,
      }) as CooldownMap;

    this.queue = new SpeechQueue(cooldown, options.maxBacklog ?? 50);
  }

  /** Enqueue speech; returns true when the item was accepted. */
  queueSpeech(priority: Priority, text: string, opts: { key?: string } = {}): boolean {
    return this.queue.push({
      priority,
      text,
      key: opts.key,
      timestamp: Date.now(),
    });
  }

  /**
   * Pull one eligible item, synthesize audio and publish it. Returns true when
   * an item was spoken. Cooldown bookkeeping happens inside SpeechQueue.pop().
   */
  async speakNext(): Promise<boolean> {
    const item = this.queue.pop(Date.now());
    if (item === null) return false;
    try {
      this.onSpeak?.(item);
      const audio = await textToSpeech(item.text, this.ttsFetcher);
      await this.publishAudio(audio);
    } catch (error) {
      console.error("[klayk-bot] speakNext failed:", error);
    }
    return true;
  }

  /** Kick off the worker loop. Safe to call more than once. */
  start(): void {
    if (this.running) return;
    this.running = true;
    this.scheduleLoop();
  }

  /** Stop the worker loop; in-flight speakNext completes. */
  stop(): void {
    this.running = false;
    if (this.timer !== null) {
      clearTimeout(this.timer);
      this.timer = null;
    }
  }

  pendingCount(): number {
    return this.queue.total();
  }

  private scheduleLoop(): void {
    if (!this.running) return;
    this.timer = setTimeout(() => {
      void this.tick();
    }, this.nextDelay());
  }

  private async tick(): Promise<void> {
    if (!this.running) return;
    await this.speakNext();
    this.scheduleLoop();
  }

  private nextDelay(): number {
    const next = this.queue.nextSpeakInMs(Date.now());
    if (next === null) return this.pollIntervalMs;
    return Math.max(next, 5);
  }
}