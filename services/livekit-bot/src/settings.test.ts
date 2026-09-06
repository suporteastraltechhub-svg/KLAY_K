import { test } from "node:test";
import assert from "node:assert/strict";
import { legacyDefaults, parseSettingsRow } from "./settings.js";

test("legacy defaults: bot speaks as before when a live is never configured", () => {
  const s = legacyDefaults("live-1");
  assert.equal(s.liveId, "live-1");
  assert.equal(s.enabled, true);
  assert.equal(s.commentsEnabled, true);
  assert.equal(s.announcementsEnabled, true);
  assert.equal(s.announcementsIntervalSeconds, 120);
});

test("null row keeps legacy defaults", () => {
  const s = parseSettingsRow("live-1", null);
  assert.equal(s.enabled, true);
});

test("parses a configured row faithfully", () => {
  const s = parseSettingsRow("live-1", {
    live_id: "live-1",
    enabled: true,
    comments_enabled: false,
    announcements_enabled: true,
    announcements_interval_seconds: 300,
    voice_settings: { voice_type: "female" },
  });
  assert.equal(s.enabled, true);
  assert.equal(s.commentsEnabled, false);
  assert.equal(s.announcementsEnabled, true);
  assert.equal(s.announcementsIntervalSeconds, 300);
  assert.deepEqual(s.voiceSettings, { voice_type: "female" });
});

test("falls back to legacy defaults for a partially empty row", () => {
  const s = parseSettingsRow("live-1", { live_id: "live-1", enabled: false });
  assert.equal(s.enabled, false);
  assert.equal(s.commentsEnabled, true); // unset -> legacy default
  assert.equal(s.announcementsEnabled, true);
});
