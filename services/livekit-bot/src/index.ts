import "dotenv/config";
import { assertServerSecrets, config } from "./config.js";
import { LiveEventBot } from "./bot.service.js";

async function main(): Promise<void> {
  assertServerSecrets(config);
  console.log(`[klayk-bot] starting (provider=${config.ttsProvider}, rooms=${config.monitorRooms.length}, publishAudio=${config.publishAudio})`);

  const bot = new LiveEventBot();
  await bot.start();

  let stopping = false;
  const shutdown = async (signal: string): Promise<void> => {
    if (stopping) return;
    stopping = true;
    console.log(`[klayk-bot] ${signal} received, shutting down...`);
    try {
      await bot.stop();
    } catch (error) {
      console.error("[klayk-bot] shutdown error:", error);
      process.exitCode = 1;
    }
    process.exit();
  };

  process.on("SIGINT", () => void shutdown("SIGINT"));
  process.on("SIGTERM", () => void shutdown("SIGTERM"));
}

main().catch((error: unknown) => {
  console.error("[klayk-bot] fatal:", error instanceof Error ? error.message : error);
  process.exit(1);
});