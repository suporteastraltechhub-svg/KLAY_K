import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { config } from "./config.js";
import { allocationPolicy } from "./events.js";
import type { Priority } from "./queue.js";
import { RealtimeWatcher } from "./realtime.js";
import { BotRoom } from "./room.js";
import { AnnouncementLoop } from "./announcements.js";
import { BotSettingsCache } from "./settings.js";

interface LiveRow {
  id?: string | null;
  room_name: string;
}

/**
 * Ties room participation + Supabase realtime together. Rooms come from
 * BOT_MONITOR_ROOMS and/or a poll of `lives where status = 'live'`.
 */
export class LiveEventBot {
  /** Rooms the bot is currently joined to / allowed to speak in. */
  private readonly monitored = new Set<string>(config.monitorRooms);
  private readonly rooms = new Map<string, BotRoom>();
  private readonly liveToRoom = new Map<string, string>();
  private readonly settingsCache = new BotSettingsCache();
  private announcements: AnnouncementLoop | null = null;
  private realtime: RealtimeWatcher | null = null;
  private pollTimer: NodeJS.Timeout | null = null;
  private supabase: SupabaseClient | null = null;

  async start(): Promise<void> {
    for (const room of config.monitorRooms) {
      await this.ensureRoom(room);
    }
    this.realtime = new RealtimeWatcher({
      botName: config.botName,
      getMonitoredRooms: () => this.monitored,
      feed: (room, priority, text, opts) => this.dispatch(room, priority, text, opts?.key),
      settings: this.settingsCache,
    });
    await this.realtime.start();
    this.announcements = new AnnouncementLoop({
      settings: this.settingsCache,
      roomForLive: (liveId) => this.liveToRoom.get(liveId) ?? null,
      feed: (room, priority, text, key) => this.dispatch(room, priority, text, key),
    });
    this.announcements.start(config.announcementPollMs);
    this.pollTimer = setInterval(() => {
      void this.pollLiveRooms();
    }, config.livePollMs);
    await this.pollLiveRooms();
  }

  async stop(): Promise<void> {
    if (this.pollTimer !== null) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
    if (this.announcements !== null) {
      this.announcements.stop();
      this.announcements = null;
    }
    if (this.realtime !== null) {
      await this.realtime.stop();
      this.realtime = null;
    }
    await Promise.all([...this.rooms.values()].map((room) => room.leave()));
    this.rooms.clear();
    if (this.supabase !== null) {
      try {
        await this.supabase.removeAllChannels();
      } catch {
        // already torn down
      }
      this.supabase = null;
    }
  }

  /** Start the bot in a specific room; no-op if already joined. */
  async ensureRoom(roomName: string): Promise<void> {
    if (this.rooms.has(roomName)) return;
    const botRoom = await BotRoom.join(roomName);
    this.rooms.set(roomName, botRoom);
    this.monitored.add(roomName);
  }

  /** Route a phrase to the room's own queue manager. */
  private dispatch(room: string, priority: Priority, text: string, key?: string): boolean {
    const botRoom = this.rooms.get(room);
    if (botRoom === undefined) return false;
    return allocationPolicy(
      (item) => botRoom.queue.queueSpeech(item.priority, item.text, { key: item.key }),
      { priority, text, key, timestamp: Date.now() },
    );
  }

  private async pollLiveRooms(): Promise<void> {
    if (!config.supabaseUrl || !config.supabaseServiceRoleKey) {
      if (config.monitorRooms.length === 0) {
        console.warn("[klayk-bot] no BOT_MONITOR_ROOMS and no supabase config — nothing to join");
      }
      return;
    }
    try {
      const supabase = this.supabase ?? (this.supabase = createClient(config.supabaseUrl, config.supabaseServiceRoleKey));
      const { data, error } = await supabase
        .from("lives")
        .select("id, room_name")
        .eq("status", "live");
      if (error !== null) {
        console.error("[klayk-bot] live poll failed:", error.message);
        return;
      }
      const rows = (data ?? []) as LiveRow[];
      for (const row of rows) {
        if (typeof row.id === "string" && row.id.length > 0) {
          this.liveToRoom.set(row.id, row.room_name);
        }
        await this.ensureRoom(row.room_name);
      }
    } catch (err) {
      console.error("[klayk-bot] live poll error:", err);
    }
  }
}