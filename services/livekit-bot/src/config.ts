import { z } from "zod";

const TRUE_VALUES = new Set(["1", "true", "yes", "on"]);

function envBool(value: string | undefined): boolean {
  if (value === undefined || value === "") return false;
  return TRUE_VALUES.has(value.toLowerCase());
}

/** Server-side secrets/identifiers. Values come exclusively from the environment. */
export interface AppConfig {
  livekitUrl: string;
  livekitApiKey: string;
  livekitApiSecret: string;
  supabaseUrl: string;
  supabaseAnonKey: string;
  supabaseServiceRoleKey: string;
  openaiApiKey?: string;
  botName: string;
  ttsProvider: "noop" | "openai";
  ttsModel: string;
  ttsVoice: string;
  ttsCooldownMs: number;
  publishAudio: boolean;
  monitorRooms: string[];
  livePollMs: number;
  announcementPollMs: number;
}

const stringSchema = z.string().min(1);

const numberSchema = z.coerce.number().finite();

/**
 * Build the application config strictly from env vars. No defaults for
 * secrets; secrets stay empty/undefined when not provided.
 */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const ttsProvider = z
    .union([z.literal("noop"), z.literal("openai")])
    .catch("noop")
    .parse(env.BOT_TTS_PROVIDER ?? "");

  const monitorRooms = (env.BOT_MONITOR_ROOMS ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);

  const rawCooldown = numberSchema
    .catch(NaN)
    .parse(env.BOT_TTS_COOLDOWN_MS ?? "4000");
  const ttsCooldownMs = Number.isFinite(rawCooldown) && rawCooldown > 0 ? rawCooldown : 4000;

  const rawPoll = numberSchema.catch(NaN).parse(env.BOT_LIVE_POLL_MS ?? "15000");
  const livePollMs = Number.isFinite(rawPoll) && rawPoll > 0 ? rawPoll : 15000;

  const rawAnnouncementPoll = numberSchema
    .catch(NaN)
    .parse(env.BOT_ANNOUNCEMENT_POLL_MS ?? "5000");
  const announcementPollMs =
    Number.isFinite(rawAnnouncementPoll) && rawAnnouncementPoll > 0
      ? rawAnnouncementPoll
      : 5000;

  return {
    livekitUrl: stringSchema.catch("").parse(env.LIVEKIT_URL ?? ""),
    livekitApiKey: stringSchema.catch("").parse(env.LIVEKIT_API_KEY ?? ""),
    livekitApiSecret: stringSchema.catch("").parse(env.LIVEKIT_API_SECRET ?? ""),
    supabaseUrl: stringSchema.catch("").parse(env.SUPABASE_URL ?? ""),
    supabaseAnonKey: stringSchema.catch("").parse(env.SUPABASE_ANON_KEY ?? ""),
    supabaseServiceRoleKey: stringSchema.catch("").parse(env.SUPABASE_SERVICE_ROLE_KEY ?? ""),
    openaiApiKey: env.OPENAI_API_KEY?.trim() ? env.OPENAI_API_KEY : undefined,
    botName: (env.BOT_NAME ?? "KLAY K Bot").trim() || "KLAY K Bot",
    ttsProvider,
    ttsModel: (env.BOT_TTS_MODEL ?? "gpt-4o-mini-tts").trim() || "gpt-4o-mini-tts",
    ttsVoice: (env.BOT_TTS_VOICE ?? "alloy").trim() || "alloy",
    ttsCooldownMs,
    publishAudio: envBool(env.BOT_PUBLISH_AUDIO),
    monitorRooms,
    livePollMs,
    announcementPollMs,
  };
}

/** Secrets required by the bot entry point. Throw lists names only, never values. */
export function assertServerSecrets(
  cfg: Pick<AppConfig, "livekitUrl" | "livekitApiKey" | "livekitApiSecret">,
): void {
  const missing: string[] = [];
  if (!cfg.livekitUrl) missing.push("LIVEKIT_URL");
  if (!cfg.livekitApiKey) missing.push("LIVEKIT_API_KEY");
  if (!cfg.livekitApiSecret) missing.push("LIVEKIT_API_SECRET");
  if (missing.length > 0) {
    throw new Error(
      `[config] Missing required server-side env vars: ${missing.join(", ")}. ` +
        "Secrets must be provided via the server environment, never hardcoded.",
    );
  }
}

/** Read once at import time. Bulk of the bot reads from this. */
export const config: AppConfig = loadConfig();