import { test } from "node:test";
import assert from "node:assert/strict";
import {
  welcome,
  goodbye,
  gift,
  follow,
  liveStarted,
  liveEnded,
  like,
  share,
  priorityForEvent,
  textForEvent,
  allocationPolicy,
  type LiveEventForSpeech,
} from "./events.js";
import type { Priority } from "./queue.js";

test("PT-BR templates produce the exact required phrases", () => {
  assert.equal(welcome("Maria"), "Seja muito bem-vindo, Maria! 👋");
  assert.equal(goodbye("João"), "Até mais, João! 👋");
  assert.equal(gift("Ana", "Coração", 5), "🎁 Ana enviou Coração x5!");
  assert.equal(follow("Pedro"), "❤️ Pedro começou a seguir a live!");
  assert.equal(liveStarted(), "🔴 A live começou! Seja bem-vindo ao KLAY K!");
  assert.equal(liveEnded(), "A live terminou. Obrigado por acompanhar!");
});

test("priorityForEvent follows the KLAY K mapping", () => {
  const expected: Record<string, Priority> = {
    GIFT_RECEIVED: "high",
    LIVE_STARTED: "high",
    USER_JOINED: "medium",
    FOLLOW: "medium",
    LIVE_ENDED: "medium",
    CHAT_MESSAGE: "low",
    USER_LEFT: "low",
    LIKE: "low",
    SHARE: "low",
  };
  for (const [eventType, priority] of Object.entries(expected)) {
    assert.equal(priorityForEvent(eventType), priority, eventType);
  }
  assert.equal(priorityForEvent("UNKNOWN_EVENT"), "low");
});

function evt(partial: Partial<LiveEventForSpeech> & { event_type: string }): LiveEventForSpeech {
  return {
    id: "id-1",
    live_id: "live-1",
    user_id: null,
    username: null,
    metadata: {},
    ...partial,
  };
}

test("textForEvent renders each event type", () => {
  assert.equal(
    textForEvent(evt({ event_type: "GIFT_RECEIVED", username: "Ana", metadata: { gift_name: "Coração", gift_amount: 3 } })),
    "🎁 Ana enviou Coração x3!",
  );
  assert.equal(
    textForEvent(evt({ event_type: "GIFT_RECEIVED", username: "Ana", metadata: { giftName: "Rosa", amount: 1 } })),
    "🎁 Ana enviou Rosa x1!",
  );
  assert.equal(textForEvent(evt({ event_type: "USER_JOINED", username: "Carlos" })), "Seja muito bem-vindo, Carlos! 👋");
  assert.equal(textForEvent(evt({ event_type: "USER_LEFT", username: "Carlos" })), "Até mais, Carlos! 👋");
  assert.equal(textForEvent(evt({ event_type: "FOLLOW", username: "Bia" })), "❤️ Bia começou a seguir a live!");
  assert.equal(textForEvent(evt({ event_type: "LIKE", username: "Bia" })), "👍 Bia curtiu a live!");
  assert.equal(textForEvent(evt({ event_type: "SHARE", username: "Bia" })), "🔗 Bia compartilhou a live!");
  assert.equal(textForEvent(evt({ event_type: "LIVE_STARTED" })), "🔴 A live começou! Seja bem-vindo ao KLAY K!");
  assert.equal(textForEvent(evt({ event_type: "LIVE_ENDED" })), "A live terminou. Obrigado por acompanhar!");
});

test("textForEvent falls back to metadata/unknown names", () => {
  const e = evt({ event_type: "USER_JOINED", metadata: { username: "Débora" } });
  assert.equal(textForEvent(e), "Seja muito bem-vindo, Débora! 👋");
  const e2 = evt({ event_type: "USER_JOINED" });
  assert.equal(textForEvent(e2).includes("Alguém"), true);
});

test("allocationPolicy delegates to the queue push and returns its verdict", () => {
  const captured: unknown[] = [];
  const fakePush = (item: { priority: Priority; text: string; key?: string; timestamp: number }) => {
    captured.push(item);
    return true;
  };
  const accepted = allocationPolicy(fakePush, { priority: "high", text: "ola", timestamp: 5 });
  assert.equal(accepted, true);
  assert.deepEqual(captured, [{ priority: "high", text: "ola", timestamp: 5 }]);
  const rejected = allocationPolicy(() => false, { priority: "low", text: "x", timestamp: 6 });
  assert.equal(rejected, false);
});