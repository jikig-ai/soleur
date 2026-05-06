import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Migration-shape tests for 038 + 039 (disk-IO fix).
//
// File-parse tests, not live-DB tests. They pin the SQL contract for the
// two surgical migrations that reduce prod Supabase Disk IO Budget burn:
//
//   038_slow_user_concurrency_slots_sweep.sql
//     Slows pg_cron `user_concurrency_slots_sweep` from `* * * * *`
//     (1,440 runs/day) to `*/15 * * * *` (96 runs/day). The 120-second
//     `last_heartbeat_at` freshness threshold (declared in 029) is
//     independent of sweep cadence.
//
//   039_drop_messages_from_realtime_publication.sql
//     Drops `public.messages` from the `supabase_realtime` publication.
//     `public.conversations` MUST remain — `apps/web-platform/hooks/
//     use-conversations.ts:238` subscribes to it.
//
// Plan: 2026-05-06-fix-supabase-disk-io-cron-realtime-plan.md.
// Issue: #3358.

const MIG_DIR = path.join(__dirname, "../../supabase/migrations");
const stripComments = (sql: string) => sql.replace(/--[^\n]*/g, "");

describe("migration 038_slow_user_concurrency_slots_sweep", () => {
  const executable = stripComments(
    readFileSync(path.join(MIG_DIR, "038_slow_user_concurrency_slots_sweep.sql"), "utf8"),
  );

  it("unschedules the existing job by name (idempotent guard)", () => {
    expect(executable).toMatch(/cron\.unschedule\s*\(\s*'user_concurrency_slots_sweep'\s*\)/i);
  });

  it("re-schedules at 15-minute cadence", () => {
    expect(executable).toMatch(
      /cron\.schedule\s*\(\s*'user_concurrency_slots_sweep'\s*,\s*'\*\/15\s+\*\s+\*\s+\*\s+\*'/i,
    );
  });

  // Kieran #5: pin the DELETE predicate byte-shape so a future edit cannot
  // change the load-bearing freshness condition while still passing the
  // schedule + threshold assertions above.
  it("preserves the DELETE predicate body unchanged from migration 029", () => {
    expect(executable).toMatch(
      /delete\s+from\s+public\.user_concurrency_slots\s+where\s+last_heartbeat_at\s*<\s*now\(\)\s*-\s*interval\s+'120\s+seconds'/i,
    );
  });
});

describe("migration 039_drop_messages_from_realtime_publication", () => {
  const executable = stripComments(
    readFileSync(path.join(MIG_DIR, "039_drop_messages_from_realtime_publication.sql"), "utf8"),
  );

  it("drops public.messages from supabase_realtime", () => {
    expect(executable).toMatch(
      /ALTER\s+PUBLICATION\s+supabase_realtime\s+DROP\s+TABLE\s+public\.messages/i,
    );
  });

  it("does NOT drop public.conversations (must remain in publication)", () => {
    expect(executable).not.toMatch(
      /ALTER\s+PUBLICATION\s+supabase_realtime\s+DROP\s+TABLE\s+public\.conversations/i,
    );
  });

  it("guards on publication membership before dropping (idempotent)", () => {
    expect(executable).toMatch(/pg_publication_tables/i);
    expect(executable).toMatch(/IF\s+EXISTS\s*\(/i);
  });
});
