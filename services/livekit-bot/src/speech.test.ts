import { test } from "node:test";
import assert from "node:assert/strict";
import type { TtsFetcher } from "./speech.js";

// config.ts snapshots env at import time; set it before loading speech.js.
process.env.BOT_TTS_PROVIDER = "openai";
process.env.BOT_TTS_MODEL = "gpt-4o-mini-tts";
process.env.BOT_TTS_VOICE = "alloy";
process.env.OPENAI_API_KEY = "test-openai-key";

const { textToSpeech, SpeechQueueManager } = await import("./speech.js");

const wavBytes = new Uint8Array([0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4]);

function fakeFetcher(): TtsFetcher & { calls: Array<[string | URL | Request, RequestInit | undefined]> } {
  const calls: Array<[string | URL | Request, RequestInit | undefined]> = [];
  const fn: TtsFetcher = async (url, init) => {
    calls.push([url, init]);
    return new Response(new Uint8Array(wavBytes), { status: 200 });
  };
  return Object.assign(fn, { calls });
}

test('noop provider logs the text and returns an empty buffer', async () => {
  const logged: string[] = [];
  const original = console.log;
  console.log = (msg: unknown) => logged.push(String(msg));
  try {
    const buffer = await textToSpeech("Bom dia!", fetch, "noop");
    assert.equal(buffer.length, 0);
    assert.equal(logged.length, 1);
    assert.equal(logged[0], "[bot-say] Bom dia!");
  } finally {
    console.log = original;
  }
});

test('openai provider posts to /v1/audio/speech and returns the wav bytes', async () => {
  const fetcher = fakeFetcher();
  const audio = await textToSpeech("Olá KLAY K!", fetcher, "openai");
  assert.deepEqual(new Uint8Array(audio), wavBytes);
  assert.equal(fetcher.calls.length, 1);
  const [url, init] = fetcher.calls[0] as [string, RequestInit];
  assert.equal(url, "https://api.openai.com/v1/audio/speech");
  assert.equal(init.method, "POST");
  const headers = init.headers as Record<string, string>;
  assert.equal(headers.Authorization, "Bearer test-openai-key");
  const body = JSON.parse(init.body as string) as Record<string, string>;
  assert.equal(body.input, "Olá KLAY K!");
  assert.equal(body.voice, "alloy");
  assert.equal(body.model, "gpt-4o-mini-tts");
  assert.equal(body.response_format, "wav");
});

test("openai provider surfaces HTTP failures", async () => {
  const failing: TtsFetcher = async () => new Response("nope", { status: 500, statusText: "Server Error" });
  await assert.rejects(
    () => textToSpeech("oi", failing, "openai"),
    /OpenAI TTS request failed: 500 Server Error/,
  );
});

test("unsupported provider throws", async () => {
  await assert.rejects(() => textToSpeech("oi", fetch, "elevenlabs"), /Unsupported TTS provider: elevenlabs/);
});

test("SpeechQueueManager wires queue -> TTS -> publishAudio", async () => {
  const published: Buffer[] = [];
  const spoken: string[] = [];
  const manager = new SpeechQueueManager(
    (buffer) => {
      published.push(buffer);
    },
    {
      cooldownMsByPriority: { high: 0, medium: 0, low: 0 },
      pollIntervalMs: 5,
      ttsFetcher: async () => new Response(new Uint8Array(Buffer.from("audio"))),
      onSpeak: (item) => spoken.push(item.text),
    },
  );
  // no key -> no dedupe, both accepted
  assert.equal(manager.queueSpeech("medium", "Oi!"), true);
  assert.equal(manager.queueSpeech("medium", "Oi! de novo"), true);
  assert.equal(manager.pendingCount(), 2);
  assert.equal(await manager.speakNext(), true);
  assert.equal(spoken.length, 1);
  assert.equal(published.length, 1);
  assert.deepEqual(new Uint8Array(published[0]), new Uint8Array(Buffer.from("audio")));
  assert.equal(manager.pendingCount(), 1);
  manager.stop();
});

test("SpeechQueueManager dedupes queueSpeech by key", () => {
  const manager = new SpeechQueueManager(() => undefined, {
    cooldownMsByPriority: { high: 0, medium: 0, low: 0 },
  });
  assert.equal(manager.queueSpeech("low", "mensagem", { key: "chat-1" }), true);
  assert.equal(manager.queueSpeech("low", "mensagem duplicada", { key: "chat-1" }), false);
  manager.stop();
});