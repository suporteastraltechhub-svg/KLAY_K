import { test } from "node:test";
import assert from "node:assert/strict";
import { SpeechQueue, DEFAULT_COOLDOWN_MS, PRIORITY_RANK, msUntilEligible } from "./queue.js";

const T = 1_000_000; // arbitrary base timestamp

function item(priority: "high" | "medium" | "low", text: string, timestamp: number, key?: string) {
  return { priority, text, timestamp, ...(key !== undefined ? { key } : {}) };
}

test("priority rank: high=0, medium=1, low=2", () => {
  assert.equal(PRIORITY_RANK.high, 0);
  assert.equal(PRIORITY_RANK.medium, 1);
  assert.equal(PRIORITY_RANK.low, 2);
});

test("pops highest priority first (FIFO within priority)", () => {
  const q = new SpeechQueue();
  const highCd = DEFAULT_COOLDOWN_MS.high;
  q.push(item("low", "chat", T));
  q.push(item("high", "gift", T));
  q.push(item("medium", "join", T));
  q.push(item("high", "gift2", T + 1));
  // each pop advances past the previous priority's cooldown window
  assert.deepEqual(q.pop(T), item("high", "gift", T));
  assert.deepEqual(q.pop(T + highCd), item("high", "gift2", T + 1));
  assert.deepEqual(q.pop(T + highCd + 1), item("medium", "join", T));
  assert.deepEqual(q.pop(T + highCd + 2), item("low", "chat", T));
  assert.equal(q.pop(T + highCd + 3), null);
});

test("per-priority cooldown: same priority silenced until window elapses", () => {
  const q = new SpeechQueue();
  assert.equal(q.push(item("low", "first", T)), true);
  assert.deepEqual(q.pop(T), item("low", "first", T));
  // second low message pushed right after -> rejected by push-time cooldown
  assert.equal(q.push(item("low", "spam", T + 1)), false);
  // nothing left queued
  assert.equal(q.isEmpty(), true);
});

test("pop respects cooldown and skips to an eligible lower priority", () => {
  const q = new SpeechQueue();
  q.push(item("high", "gift", T));
  assert.deepEqual(q.pop(T), item("high", "gift", T)); // high spoken at T, cooling down
  assert.equal(q.push(item("high", "gift2", T + 1)), false); // high still on cooldown
  // low has never spoken -> eligible even though high was spoken recently
  assert.equal(q.push(item("low", "chat", T + 100)), true);
  assert.deepEqual(q.pop(T + 200), item("low", "chat", T + 100));
  assert.equal(q.pop(T + 300), null);
});

test("pop returns null while all queued priorities are on cooldown", () => {
  const q = new SpeechQueue();
  const highCd = DEFAULT_COOLDOWN_MS.high;
  q.push(item("high", "gift1", T));
  q.push(item("high", "gift2", T + 1));
  q.pop(T + 100); // gift1 spoken -> high cooling until T + 100 + highCd
  q.push(item("low", "chat", T + 101)); // low never spoken -> accepted
  assert.equal(q.nextSpeakInMs(T + 101), 0); // low is eligible
  q.pop(T + 101); // low spoken -> low cooling until T + 101 + lowCd
  // both high and low are now on cooldown, gift2 remains queued
  assert.equal(q.pop(T + 102), null);
  assert.equal(q.nextSpeakInMs(T + 105), highCd - 5);
  // once the high window elapses, the queued gift2 is spoken
  assert.deepEqual(q.pop(T + 100 + highCd), item("high", "gift2", T + 1));
});

test("dedupe by key drops duplicates, also across pushes", () => {
  const q = new SpeechQueue();
  assert.equal(q.push(item("high", "gift", T, "evt-1")), true);
  assert.equal(q.push(item("high", "gift-dup", T, "evt-1")), false);
  assert.equal(q.total(), 1);
  assert.deepEqual(q.pop(T), item("high", "gift", T, "evt-1"));
  // key released after pop, reusable
  assert.equal(q.push(item("low", "again", T + 100, "evt-1")), true);
});

test("backlog limit rejects items beyond maxBacklog", () => {
  const q = new SpeechQueue({ ...DEFAULT_COOLDOWN_MS }, 2);
  assert.equal(q.push(item("low", "a", T)), true);
  assert.equal(q.push(item("low", "b", T)), true);
  assert.equal(q.push(item("medium", "c", T)), false);
  assert.equal(q.total(), 2);
  assert.deepEqual(q.pop(T), item("low", "a", T));
  assert.equal(q.push(item("medium", "c", T + 1)), true);
});

test("nextSpeakInMs: 0 when eligible, positive on cooldown, null when empty", () => {
  const q = new SpeechQueue();
  assert.equal(q.nextSpeakInMs(T), null);
  assert.equal(q.push(item("low", "first", T)), true);
  assert.equal(q.nextSpeakInMs(T), 0);
  q.pop(T);
  assert.equal(q.push(item("low", "second", T + 10)), false); // on cooldown, never queued
  // queue is now empty after pop -> null again
  assert.equal(q.nextSpeakInMs(T + 10), null);
});

test("nextSpeakInMs reflects the earliest cooldown across priorities", () => {
  const q = new SpeechQueue();
  const highCd = DEFAULT_COOLDOWN_MS.high;
  q.push(item("high", "gift", T));
  q.push(item("high", "gift2", T + 1)); // accepted: high had never spoken at push time
  q.pop(T + 100); // gift spoken at T+100; gift2 stays queued while high cools down
  // low never spoke; add a low item so an eligible branch exists, then consume it
  q.push(item("low", "chat", T + 101));
  assert.equal(q.nextSpeakInMs(T + 101), 0); // low eligible
  q.pop(T + 101); // low spoken; high still cooling, gift2 pending
  assert.equal(msUntilEligible("high", { high: T + 100, medium: 0, low: T + 101 }, T + 102, DEFAULT_COOLDOWN_MS), highCd - 2);
  // earliest remaining is the high cooldown (low queue now empty)
  assert.equal(q.nextSpeakInMs(T + 102), highCd - 2);
});

test("clear() drops queued items (cooldown state preserved)", () => {
  const q = new SpeechQueue();
  q.push(item("high", "gift", T));
  q.clear();
  assert.equal(q.isEmpty(), true);
  assert.equal(q.total(), 0);
  assert.equal(q.pop(T + 1000), null);
  // cooldown preserved: a fresh low is fine, a fresh high is on cooldown from nothing? lastSpokeAt high=0 -> ok
  assert.equal(q.push(item("low", "chat", T + 1000)), true);
});

test("queue accepts items again once cooldown elapses", () => {
  const q = new SpeechQueue();
  const lowCd = DEFAULT_COOLDOWN_MS.low;
  q.push(item("low", "first", T));
  q.pop(T);
  assert.equal(q.push(item("low", "second", T + lowCd - 1)), false);
  assert.equal(q.push(item("low", "second", T + lowCd)), true);
  assert.deepEqual(q.pop(T + lowCd), item("low", "second", T + lowCd));
});