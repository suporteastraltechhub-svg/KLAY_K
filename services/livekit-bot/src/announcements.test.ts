import { test } from "node:test";
import assert from "node:assert/strict";
import { announcementDue } from "./announcements.js";

test("announcement is due when interval has elapsed", () => {
  assert.equal(announcementDue(0, 10_000, 120), true);
  assert.equal(announcementDue(10_000, 130_000, 120), true);
});

test("announcement is not due before the interval elapses", () => {
  assert.equal(announcementDue(10_000, 100_000, 120), false);
});

test("invalid interval falls back to default (120s)", () => {
  // 60s elapsed < 120s default -> not due yet
  assert.equal(announcementDue(10_000, 70_000, 0), false);
  // 200s elapsed > 120s default -> due
  assert.equal(announcementDue(10_000, 210_000, -5), true);
  assert.equal(announcementDue(10_000, 210_000, Number.NaN), true);
});
