/**
 * Pure in-memory speech scheduling.
 *
 * Priority order: high (gifts, live start) -> medium (joins, follows) -> low
 * (chat, likes). Per-priority cooldowns throttle spam: only the first message
 * inside each cooldown window is spoken.
 */

export type Priority = "high" | "medium" | "low";

export const PRIORITIES: readonly Priority[] = ["high", "medium", "low"] as const;

/** Numeric rank: high = 0 (spoken first). */
export const PRIORITY_RANK: Record<Priority, number> = {
  high: 0,
  medium: 1,
  low: 2,
} as const;

export interface SpeechItem {
  priority: Priority;
  text: string;
  /** Optional dedupe identity (e.g. event id, chat row id). */
  key?: string;
  /** Unix ms timestamp the item was created/pushed. */
  timestamp: number;
}

export type CooldownMap = Record<Priority, number>;

export const DEFAULT_COOLDOWN_MS: CooldownMap = {
  high: 5000,
  medium: 4500,
  low: 4000,
} as const;

export function cooldownElapsedFor(
  priority: Priority,
  lastSpokeAt: Record<Priority, number>,
  now: number,
  cooldownMsByPriority: CooldownMap,
): boolean {
  const last = lastSpokeAt[priority];
  if (last <= 0) return true;
  return now - last >= cooldownMsByPriority[priority];
}

/** Milliseconds until `priority` may speak again (0 when already eligible). */
export function msUntilEligible(
  priority: Priority,
  lastSpokeAt: Record<Priority, number>,
  now: number,
  cooldownMsByPriority: CooldownMap,
): number {
  const last = lastSpokeAt[priority];
  if (last <= 0) return 0;
  const remaining = cooldownMsByPriority[priority] - (now - last);
  return remaining > 0 ? remaining : 0;
}

export class SpeechQueue {
  private readonly queues: Record<Priority, SpeechItem[]>;
  private readonly keys = new Set<string>();
  private readonly lastSpokeAt: Record<Priority, number> = {
    high: 0,
    medium: 0,
    low: 0,
  };

  constructor(
    private readonly cooldownMsByPriority: CooldownMap = { ...DEFAULT_COOLDOWN_MS },
    private readonly maxBacklog: number = 50,
  ) {
    this.queues = { high: [], medium: [], low: [] };
  }

  /**
   * Try to enqueue an item. Rejected (returns false) when:
   *  - a duplicate `key` is already queued/spoken-tracked,
   *  - the backlog is full,
   *  - the item's priority is still inside its cooldown window.
   */
  push(item: SpeechItem): boolean {
    if (item.key !== undefined && this.keys.has(item.key)) return false;
    if (this.total() >= this.maxBacklog) return false;
    if (!cooldownElapsedFor(item.priority, this.lastSpokeAt, item.timestamp, this.cooldownMsByPriority)) {
      return false;
    }
    this.queues[item.priority].push(item);
    if (item.key !== undefined) this.keys.add(item.key);
    return true;
  }

  /**
   * Pop the highest-priority item whose priority cooldown has elapsed.
   * Marks the priority's `lastSpokeAt` to `now`.
   */
  pop(now: number): SpeechItem | null {
    for (const priority of PRIORITIES) {
      const items = this.queues[priority];
      if (items.length === 0) continue;
      if (!cooldownElapsedFor(priority, this.lastSpokeAt, now, this.cooldownMsByPriority)) continue;
      const item = items.shift() as SpeechItem;
      this.lastSpokeAt[priority] = now;
      if (item.key !== undefined) this.keys.delete(item.key);
      return item;
    }
    return null;
  }

  /** Highest-priority queued item without popping (does not touch cooldowns). */
  peek(): SpeechItem | null {
    for (const priority of PRIORITIES) {
      const items = this.queues[priority];
      if (items.length > 0) return items[0] as SpeechItem;
    }
    return null;
  }

  /**
   * 0 when an eligible item exists, otherwise ms until the earliest priority
   * cooldown elapses, or null when the queue is empty.
   */
  nextSpeakInMs(now: number): number | null {
    for (const priority of PRIORITIES) {
      const items = this.queues[priority];
      if (items.length === 0) continue;
      if (cooldownElapsedFor(priority, this.lastSpokeAt, now, this.cooldownMsByPriority)) return 0;
    }
    let earliest: number | null = null;
    for (const priority of PRIORITIES) {
      const items = this.queues[priority];
      if (items.length === 0) continue;
      const remaining = msUntilEligible(priority, this.lastSpokeAt, now, this.cooldownMsByPriority);
      if (remaining > 0 && (earliest === null || remaining < earliest)) earliest = remaining;
    }
    return earliest;
  }

  sizeOf(priority: Priority): number {
    return this.queues[priority].length;
  }

  total(): number {
    return PRIORITIES.reduce((acc, p) => acc + this.queues[p].length, 0);
  }

  isEmpty(): boolean {
    return this.total() === 0;
  }

  /** Drop all queued items (+ dedupe keys). Cooldown timers are preserved. */
  clear(): void {
    for (const priority of PRIORITIES) {
      this.queues[priority] = [];
    }
    this.keys.clear();
  }
}