import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { config } from "./config.js";

/**
 * Per-live Live Bot settings as persisted in `live_bot_settings`.
 *
 * Missing row (live never configured) -> legacy defaults that preserve the
 * bot's existing behavior: everything effectively on. The owner can then turn
 * the bot OFF explicitly from the in-app panel, which writes these fields.
 */
export interface BotSettings {
  liveId: string;
  enabled: boolean;
  commentsEnabled: boolean;
  announcementsEnabled: boolean;
  announcementsIntervalSeconds: number;
  voiceSettings: Record<string, unknown>;
}

const LEGACY_DEFAULTS: Omit<BotSettings, "liveId"> = {
  enabled: true,
  commentsEnabled: true,
  announcementsEnabled: true,
  announcementsIntervalSeconds: 120,
  voiceSettings: {},
};

interface SettingsRow {
  live_id?: string | null;
  enabled?: boolean | null;
  comments_enabled?: boolean | null;
  announcements_enabled?: boolean | null;
  announcements_interval_seconds?: number | null;
  voice_settings?: Record<string, unknown> | null;
}

function bool(v: unknown, fallback: boolean): boolean {
  return typeof v === "boolean" ? v : fallback;
}

function num(v: unknown, fallback: number): number {
  return typeof v === "number" && Number.isFinite(v) ? v : fallback;
}

/** Legacy behaviour when a live never wrote settings: bot speaks as before. */
export function legacyDefaults(liveId: string): BotSettings {
  return { liveId, ...LEGACY_DEFAULTS };
}

/** Pure mapping of a `live_bot_settings` row into a BotSettings object. */
export function parseSettingsRow(liveId: string, row: SettingsRow | null): BotSettings {
  if (row === null) return legacyDefaults(liveId);
  return {
    liveId,
    enabled: bool(row.enabled, LEGACY_DEFAULTS.enabled),
    commentsEnabled: bool(row.comments_enabled, LEGACY_DEFAULTS.commentsEnabled),
    announcementsEnabled: bool(row.announcements_enabled, LEGACY_DEFAULTS.announcementsEnabled),
    announcementsIntervalSeconds: num(
      row.announcements_interval_seconds,
      LEGACY_DEFAULTS.announcementsIntervalSeconds,
    ),
    voiceSettings: row.voice_settings ?? {},
  };
}

/**
 * Small in-memory cache of per-live bot settings. Defaults to legacy behavior
 * (bot speaks) for lives that have never written a settings row, so enabling
 * the new settings-aware features does not silently change existing lives.
 */
export class BotSettingsCache {
  private readonly cache = new Map<string, BotSettings>();
  private client: SupabaseClient | null = null;

  /** Refresh an individual live (from the panel/bot writes). */
  async refresh(liveId: string): Promise<BotSettings> {
    const settings = await this.fetch(liveId);
    this.cache.set(liveId, settings);
    return settings;
  }

  /** Current cached settings for a live (legacy defaults when uncached). */
  get(liveId: string): BotSettings {
    return this.cache.get(liveId) ?? legacyDefaults(liveId);
  }

  /** Get settings for a live, fetching on cache miss. */
  async resolve(liveId: string): Promise<BotSettings> {
    const cached = this.cache.get(liveId);
    if (cached !== undefined) return cached;
    return this.refresh(liveId);
  }

  /** Remove a live that ended / left monitoring. */
  invalidate(liveId: string): void {
    this.cache.delete(liveId);
  }

  private async fetch(liveId: string): Promise<BotSettings> {
    if (!config.supabaseUrl || !config.supabaseServiceRoleKey) {
      return legacyDefaults(liveId);
    }
    try {
      const supabase = this.client ?? (this.client = createClient(config.supabaseUrl, config.supabaseServiceRoleKey));
      const { data, error } = await supabase
        .from("live_bot_settings")
        .select(
          "live_id, enabled, comments_enabled, announcements_enabled, announcements_interval_seconds, voice_settings",
        )
        .eq("live_id", liveId)
        .maybeSingle();
      if (error !== null || data === null) {
        return legacyDefaults(liveId);
      }
      return parseSettingsRow(liveId, data as SettingsRow);
    } catch {
      return legacyDefaults(liveId);
    }
  }
}
