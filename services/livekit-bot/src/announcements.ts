import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { config } from "./config.js";
import type { Priority } from "./queue.js";
import { BotSettingsCache } from "./settings.js";

/** Route a phrase into the room's queue manager. */
type AnnouncementRouter = (room: string, priority: Priority, text: string, key?: string) => boolean;

/** Resolve a live_id to its monitored room_name, or null when not tracked. */
type RoomResolver = (liveId: string) => string | null;

interface AnnouncementRow {
  id?: string | null;
  live_id?: string | null;
  message?: string | null;
  interval_seconds?: number | null;
  enabled?: boolean | null;
}

const DEFAULT_INTERVAL_MS = 120_000;

/** Pure: whether `intervalSeconds` has elapsed since `lastSpokenAt` (ms). */
export function announcementDue(
  lastSpokenAt: number,
  now: number,
  intervalSeconds: number,
): boolean {
  const intervalMs = (Number.isFinite(intervalSeconds) && intervalSeconds > 0
    ? intervalSeconds
    : DEFAULT_INTERVAL_MS / 1000) * 1000;
  return now - lastSpokenAt >= intervalMs;
}

/**
 * Periodically announces each enabled announcement configured by the live
 * creator, without repeating the same announcement more often than its
 * configured interval. Only speaks for lives where the bot is on and
 * announcements are enabled (per `live_bot_settings`).
 */
export class AnnouncementLoop {
  private readonly client: SupabaseClient;
  private readonly settings: BotSettingsCache;
  private readonly roomForLive: RoomResolver;
  private readonly feed: AnnouncementRouter;
  /** live_id -> last spoken per announcement id. */
  private readonly lastSpoken = new Map<string, Map<string, number>>();
  private timer: NodeJS.Timeout | null = null;

  constructor(options: {
    settings: BotSettingsCache;
    roomForLive: RoomResolver;
    feed: AnnouncementRouter;
  }) {
    this.settings = options.settings;
    this.roomForLive = options.roomForLive;
    this.feed = options.feed;
    this.client = createClient(config.supabaseUrl, config.supabaseServiceRoleKey);
  }

  /** Starts the periodic poll; a no-op without a usable Supabase config. */
  start(intervalMs: number): void {
    if (!config.supabaseUrl || !config.supabaseServiceRoleKey) {
      console.warn("[klayk-bot] supabase missing — announcement loop disabled");
      return;
    }
    this.timer = setInterval(() => {
      void this.poll();
    }, intervalMs);
    void this.poll();
  }

  stop(): void {
    if (this.timer !== null) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  private async poll(): Promise<void> {
    try {
      const { data, error } = await this.client
        .from("live_bot_announcements")
        .select("id, live_id, message, interval_seconds, enabled")
        .eq("enabled", true);
      if (error !== null) {
        console.error("[klayk-bot] announcement poll failed:", error.message);
        return;
      }
      const rows = (data ?? []) as AnnouncementRow[];
      const byLive = new Map<string, AnnouncementRow[]>();
      for (const row of rows) {
        if (typeof row.live_id !== "string") continue;
        const list = byLive.get(row.live_id) ?? [];
        list.push(row);
        byLive.set(row.live_id, list);
      }

      for (const [liveId, announcements] of byLive) {
        const room = this.roomForLive(liveId);
        if (room === null) break; // not monitored / no room
        const bot = await this.settings.resolve(liveId);
        if (!bot.enabled || !bot.announcementsEnabled) continue;
        const now = Date.now();
        for (const a of announcements) {
          if (a.enabled !== true) continue;
          const text = typeof a.message === "string" ? a.message.trim() : "";
          if (text.length < 2) continue;
          if (typeof a.id !== "string") continue;
          const interval = typeof a.interval_seconds === "number" ? a.interval_seconds : DEFAULT_INTERVAL_MS / 1000;
          const last = this.lastSpoken.get(liveId)?.get(a.id) ?? 0;
          if (!announcementDue(last, now, interval)) continue;
          this.lastSpokenFor(liveId).set(a.id, now);
          // Announcements are low-priority filler (never cut off gifts/joins).
          this.feed(room, "low", text, `announcement-${a.id}`);
        }
      }
    } catch (err) {
      console.error("[klayk-bot] announcement poll error:", err);
    }
  }

  private lastSpokenFor(liveId: string): Map<string, number> {
    let m = this.lastSpoken.get(liveId);
    if (m === undefined) {
      m = new Map();
      this.lastSpoken.set(liveId, m);
    }
    return m;
  }
}
