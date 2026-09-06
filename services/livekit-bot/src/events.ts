import type { Priority } from "./queue.js";

/** PT-BR message templates — the exact spoken phrases for KLAY K. */
export function welcome(name: string): string {
  return `Seja muito bem-vindo, ${name}! 👋`;
}

export function goodbye(name: string): string {
  return `Até mais, ${name}! 👋`;
}

export function gift(sender: string, giftName: string, amount: number): string {
  return `🎁 ${sender} enviou ${giftName} x${amount}!`;
}

export function follow(name: string): string {
  return `❤️ ${name} começou a seguir a live!`;
}

export function liveStarted(): string {
  return "🔴 A live começou! Seja bem-vindo ao KLAY K!";
}

export function liveEnded(): string {
  return "A live terminou. Obrigado por acompanhar!";
}

/** Extra spoken lines for events without a fixed exact phrase. */
export function like(name: string): string {
  return `👍 ${name} curtiu a live!`;
}

export function share(name: string): string {
  return `🔗 ${name} compartilhou a live!`;
}

const PRIORITY_BY_EVENT: Record<string, Priority> = {
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

export function priorityForEvent(eventType: string): Priority {
  return PRIORITY_BY_EVENT[eventType] ?? "low";
}

/** Shape of the `live_events` row relevant for speech. */
export interface LiveEventForSpeech {
  id?: string;
  live_id: string | null;
  event_type: string;
  user_id: string | null;
  username: string | null;
  metadata?: Record<string, unknown> | null;
}

function str(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function num(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function nameOf(e: LiveEventForSpeech): string {
  return str(e.username) ?? str(e.metadata?.username) ?? "Alguém";
}

/** Build the PT-BR text spoken for a `live_events` row. */
export function textForEvent(e: LiveEventForSpeech): string {
  const name = nameOf(e);
  switch (e.event_type) {
    case "GIFT_RECEIVED": {
      const sender = str(e.metadata?.sender) ?? name;
      const giftName = str(e.metadata?.gift_name) ?? str(e.metadata?.giftName) ?? "presente";
      const amount = num(e.metadata?.gift_amount) ?? num(e.metadata?.amount) ?? 1;
      return gift(sender, giftName, amount);
    }
    case "LIVE_STARTED":
      return liveStarted();
    case "LIVE_ENDED":
      return liveEnded();
    case "USER_JOINED":
      return welcome(name);
    case "USER_LEFT":
      return goodbye(name);
    case "FOLLOW":
      return follow(name);
    case "LIKE":
      return like(name);
    case "SHARE":
      return share(name);
    default:
      return `${name} enviou um evento ${e.event_type}.`;
  }
}

/**
 * Allocation helper: hands the item to the queue, which already drops
 * duplicate keys, respects the backlog limit and per-priority cooldowns.
 * Returns true when the item was accepted for speech.
 */
export function allocationPolicy(
  push: (item: {
    priority: Priority;
    text: string;
    key?: string;
    timestamp: number;
  }) => boolean,
  item: {
    priority: Priority;
    text: string;
    key?: string;
    timestamp: number;
  },
): boolean {
  return push(item);
}