// 2026-06-11 — self-discovering parity guard: every SENTRY_MONITOR_SLUG an
// Inngest cron heartbeats to MUST have a matching sentry_cron_monitor
// resource in infra/sentry/cron-monitors.tf.
//
// Why: Sentry's check-in API silently tolerates unknown monitor slugs, so a
// cron whose monitor was never added to IaC heartbeats into the void — a
// dead cron in that state pages nowhere (missed-check-in detection never
// arms). PR #5133's AC12 verification found 13 of 36 code slugs in exactly
// this state; this guard makes the gap structural-impossible for new crons
// (the same readdirSync pattern as cron-safe-commit-parity.test.ts, per
// learning 2026-06-07-self-discovering-parity-guard-for-cross-producer-drift).
//
// Direction is one-way (code → IaC): the tf file legitimately carries
// monitors with no Inngest slug (GHA-fired workflows like
// scheduled-terraform-drift, host-timer beacons like cron-egress-resolve).

import { readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";

const FUNCTIONS_DIR = resolve(__dirname, "../../../server/inngest/functions");
const MONITORS_TF = resolve(
  __dirname,
  "../../../infra/sentry/cron-monitors.tf",
);

// Slugs assigned via SENTRY_MONITOR_SLUG consts in cron/event handlers.
// The literal-extraction regex is deliberately narrow (double-quoted
// kebab-case value on the declaration line) — a dynamically-computed slug
// would evade it, but no handler does that and the convention is enforced
// by this file's existence.
function codeSlugs(): string[] {
  const slugs = new Set<string>();
  for (const file of readdirSync(FUNCTIONS_DIR)) {
    if (!file.endsWith(".ts")) continue;
    // Per ADR-033's prefix table, oneshot-* functions get NO Sentry cron
    // monitor — a crontab-scheduled monitor would page MISSED on every
    // period after the single fire. Their errors route via
    // reportSilentFallback instead. (oneshot-gdpr-gate-50d-eval declares a
    // slug anyway — a documented known deviation whose check-ins are void
    // by design; see oneshot-4650-monitor-close.ts's header note.)
    if (file.startsWith("oneshot-")) continue;
    const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
    for (const m of src.matchAll(
      /SENTRY_MONITOR_SLUG\s*=\s*"([a-z0-9-]+)"/g,
    )) {
      slugs.add(m[1]);
    }
  }
  return [...slugs].sort();
}

function iacMonitorNames(): Set<string> {
  const tf = readFileSync(MONITORS_TF, "utf-8");
  const names = new Set<string>();
  for (const m of tf.matchAll(/^\s*name\s*=\s*"([a-z0-9-]+)"/gm)) {
    names.add(m[1]);
  }
  return names;
}

describe("Sentry cron-monitor IaC parity", () => {
  it("discovers a sane slug universe (anti-vacuity: the extractor must find the known cohort)", () => {
    const slugs = codeSlugs();
    // Floor, not exact count — new crons grow the set. If this fails LOW,
    // the extraction regex broke (a refactor of the const shape), which
    // would otherwise make the parity assertion below vacuously green.
    expect(slugs.length).toBeGreaterThanOrEqual(30);
    expect(slugs).toContain("scheduled-rule-prune");
    expect(slugs).toContain("scheduled-weekly-analytics");
  });

  it("every code slug has a sentry_cron_monitor resource in cron-monitors.tf", () => {
    const names = iacMonitorNames();
    const missing = codeSlugs().filter((s) => !names.has(s));
    expect(
      missing,
      `Inngest handlers heartbeat to monitor slug(s) with no IaC resource — ` +
        `check-ins are silently dropped and a dead cron pages nowhere. Add a ` +
        `sentry_cron_monitor block to apps/web-platform/infra/sentry/` +
        `cron-monitors.tf for: ${missing.join(", ")}`,
    ).toEqual([]);
  });
});
