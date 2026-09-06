import {
  createClient,
  type RealtimeChannel,
  type RealtimePostgresChangesPayload,
  REALTIME_SUBSCRIBE_STATES,
  type SupabaseClient,
} from "@supabase/supabase-js";
import { config } from "./config.js";
import { allocationPolicy, priorityForEvent, textForEvent } from "./events.js";
import type { Priority } from "./queue.js";
import type { BotSettingsCache } from "./settings.js";

/**
 * Row shapes coming over the wire. Index signatures let the generic
 * realtime payload types stay assignable while typed fields stay readable.
 */
export interface LiveEventRow {
  [key: string]: unknown;
  id: string;
  live_id: string | null;
  event_type: string;
  user_id: string | null;
  username: string | null;
  metadata: Record<string, unknown> | null;
  created_at?: string | null;
}

export interface LiveChatRow {
  [key: string]: unknown;
  id: string;
  live_id: string;
  user_id: string;
  message: string;
  created_at?: string | null;
}

/** Route speech for a room to the owning queue. Returns whether accepted. */
export type SpeechRouter = (
  room: string,
  priority: Priority,
  text: string,
  opts?: { key?: string },
) => boolean;

export interface RealtimeWatcherOptions {
  supabaseUrl?: string;
  supabaseServiceRoleKey?: string;
  botName?: string;
  /** Live set of rooms the bot is tracking (kept up to date externally). */
  getMonitoredRooms: () => ReadonlySet<string>;
  feed: SpeechRouter;
  /** Per-live settings used to gate speech (bot on/off, comment reading). */
  settings?: BotSettingsCache;
}

const ROOM_CACHE_TTL_MS = 60_000;
const EVENTS_CHANNEL = "klayk:events";

/** Current realtime-js's subscribe() is sync and reports state via callback. */
function subscribeUntilSubscribed(channel: RealtimeChannel): Promise<REALTIME_SUBSCRIBE_STATES> {
  return new Promise<REALTIME_SUBSCRIBE_STATES>((resolve) => {
    channel.subscribe((status) => {
      if (status === REALTIME_SUBSCRIBE_STATES.SUBSCRIBED || status === REALTIME_SUBSCRIBE_STATES.TIMED_OUT || status === REALTIME_SUBSCRIBE_STATES.CHANNEL_ERROR || status === REALTIME_SUBSCRIBE_STATES.CLOSED) {
        resolve(status);
      }
    });
  });
}

/**
 * Watches Supabase Realtime for new `live_events` / `live_chat` rows and pushes
 * eligible speech into a queue via the injected router. Chat spam is handled by
 * the queue's per-priority cooldown + key dedupe.
 */
export class RealtimeWatcher {
  private readonly client: SupabaseClient;
  private readonly channels: RealtimeChannel[] = [];
  private readonly roomByLive = new Map<string, { room: string; at: number }>();
  private readonly botName: string;
  private readonly getMonitoredRooms: () => ReadonlySet<string>;
  private readonly feed: SpeechRouter;
  private readonly settings: BotSettingsCache | undefined;

  constructor(options: RealtimeWatcherOptions) {
    this.client = createClient(
      options.supabaseUrl ?? config.supabaseUrl,
      options.supabaseServiceRoleKey ?? config.supabaseServiceRoleKey,
    );
    this.botName = options.botName ?? config.botName;
    this.getMonitoredRooms = options.getMonitoredRooms;
    this.feed = options.feed;
    this.settings = options.settings;
  }

  /** Robust to a missing/unusable Supabase config: logs instead of throwing. */
  async start(): Promise<void> {
    if (!config.supabaseUrl || !config.supabaseServiceRoleKey) {
      console.warn("[klayk-bot] SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY missing — realtime disabled");
      return;
    }
    const channel = this.client.channel(EVENTS_CHANNEL);
    channel.on(
      "postgres_changes",
      { event: "INSERT", schema: "public", table: "live_events" },
      (payload: RealtimePostgresChangesPayload<LiveEventRow>) => {
        void this.handleEvent(payload);
      },
    );
    channel.on(
      "postgres_changes",
      { event: "INSERT", schema: "public", table: "live_chat" },
      (payload: RealtimePostgresChangesPayload<LiveChatRow>) => {
        void this.handleChat(payload);
      },
    );
    const status = await subscribeUntilSubscribed(channel);
    this.channels.push(channel);
    if (status !== "SUBSCRIBED") {
      console.warn(`[klayk-bot] realtime channel not subscribed (state=${status as string})`);
      return;
    }
    console.log("[klayk-bot] realtime watching live_events + live_chat");
  }

  async stop(): Promise<void> {
    for (const channel of this.channels) {
      try {
        await this.client.removeChannel(channel);
      } catch (error) {
        console.warn("[klayk-bot] failed to remove realtime channel:", error);
      }
    }
    this.channels.length = 0;
  }

  private async handleEvent(payload: RealtimePostgresChangesPayload<LiveEventRow>): Promise<void> {
    if (payload.eventType !== "INSERT") return;
    const row: LiveEventRow = payload.new;
    if (typeof row.event_type !== "string") return;
    const room = await this.roomForLive(row.live_id);
    if (room === null || !this.getMonitoredRooms().has(room)) return;
    if (typeof row.live_id === "string" && !(await this.botDesiredFor(row.live_id))) return;
    const priority = priorityForEvent(row.event_type);
    const key = typeof row.id === "string" && row.id.length > 0 ? `event-${row.id}` : undefined;
    allocationPolicy(
      (item) =>
        this.feed(room, item.priority, item.text, {
          key: item.key,
        }),
      { priority, text: textForEvent(row), key, timestamp: Date.now() },
    );
  }

  private async handleChat(payload: RealtimePostgresChangesPayload<LiveChatRow>): Promise<void> {
    if (payload.eventType !== "INSERT") return;
    const row: LiveChatRow = payload.new;
    if (typeof row.message !== "string") return;
    const message = row.message.trim();
    if (message.length < 2) return; // too short to say
    if (this.fromBot(row)) return; // never repeat ourselves
    const room = await this.roomForLive(row.live_id);
    if (room === null || !this.getMonitoredRooms().has(room)) return;
    if (typeof row.live_id === "string" && !(await this.botDesiredFor(row.live_id, true))) {
      return;
    }
    const key = typeof row.id === "string" && row.id.length > 0 ? `chat-${row.id}` : undefined;
    this.feed(room, "low", message, { key });
  }

  /** Whether the bot should speak for a live, honoring per-live settings. */
  private async botDesiredFor(liveId: string, needComments = false): Promise<boolean> {
    if (this.settings === undefined) return true; // legacy: always speak
    const s = await this.settings.resolve(liveId);
    if (!s.enabled) return false;
    return !needComments || s.commentsEnabled;
  }

  private fromBot(row: LiveChatRow): boolean {
    if (typeof row.username !== "string") return false;
    return row.username.trim().toLowerCase() === this.botName.toLowerCase();
  }

  /** Map a live row id to its room_name (cached), null when unknown. */
  private async roomForLive(liveId: string | null): Promise<string | null> {
    if (typeof liveId !== "string" || liveId.length === 0) return null;
    const cached = this.roomByLive.get(liveId);
    const now = Date.now();
    if (cached !== undefined && now - cached.at < ROOM_CACHE_TTL_MS) return cached.room;
    const { data, error } = await this.client
      .from("lives")
      .select("room_name")
      .eq("id", liveId)
      .maybeSingle();
    const room = error === null && data !== null ? data.room_name : "";
    this.roomByLive.set(liveId, { room, at: now });
    return room.length > 0 ? room : null;
  }
}