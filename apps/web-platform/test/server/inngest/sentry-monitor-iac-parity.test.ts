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

// Per ADR-033's prefix table, oneshot-* functions must declare NO monitor
// slug (a crontab monitor pages MISSED forever after the single fire).
// The one historical deviation is grandfathered here; new entries require
// the same deliberate decision this list makes visible.
const ONESHOT_SLUG_EXEMPTIONS = new Set(["oneshot-gdpr-gate-50d-eval"]);

// Cron slugs whose sentry_cron_monitor was intentionally REMOVED because the
// cron is DISABLED via a kill-switch (#6031 — the GHCR minter: App installation
// tokens can't pull the private packages, ADR-088 arm-b). The handler keeps its
// SENTRY_MONITOR_SLUG const for easy re-enable, but heartbeats never fire (it
// no-ops under GHCR_MINTER_DISABLED=true), so there is no dropped-check-in risk.
// Remove this exemption when the monitor + cron are restored.
const DISABLED_CRON_SLUG_EXEMPTIONS = new Set(["scheduled-ghcr-token-minter"]);

// Slugs assigned via SENTRY_MONITOR_SLUG consts in cron/event handlers.
// The literal-extraction regex is deliberately narrow (double-quoted
// kebab-case value on the declaration line) — a dynamically-computed slug
// would evade it, but no handler does that and the convention is enforced
// by this file's existence.
const SLUG_RE = /SENTRY_MONITOR_SLUG\s*=\s*"([a-z0-9-]+)"/g;

function nonOneshotFiles(): string[] {
  // Per ADR-033's prefix table, oneshot-* functions get NO Sentry cron
  // monitor — a crontab-scheduled monitor would page MISSED on every
  // period after the single fire. Their errors route via
  // reportSilentFallback instead.
  return readdirSync(FUNCTIONS_DIR).filter(
    (f) => f.endsWith(".ts") && !f.startsWith("oneshot-"),
  );
}

function codeSlugs(): string[] {
  const slugs = new Set<string>();
  for (const file of nonOneshotFiles()) {
    const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
    for (const m of src.matchAll(SLUG_RE)) {
      slugs.add(m[1]);
    }
  }
  return [...slugs].sort();
}

function iacMonitorNames(): Set<string> {
  const tf = readFileSync(MONITORS_TF, "utf-8");
  const names = new Set<string>();
  // cron-monitors.tf carries ONLY sentry_cron_monitor resources (uptime
  // monitors and issue alerts live in sibling files), so a top-level name
  // attr IS a monitor slug — the resource-count pin below enforces that
  // assumption mechanically.
  for (const m of tf.matchAll(/^\s*name\s*=\s*"([a-z0-9-]+)"/gm)) {
    names.add(m[1]);
  }
  return names;
}

function iacResourceCount(): number {
  const tf = readFileSync(MONITORS_TF, "utf-8");
  return [...tf.matchAll(/^resource "sentry_cron_monitor" /gm)].length;
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

  it("per-producer anti-vacuity: every heartbeating handler yields an extracted slug", () => {
    // The global floor above has slack, so a SINGLE new cron whose slug
    // declaration evades SLUG_RE (typed annotation, template literal,
    // renamed const) would pass both it and the parity check while
    // heartbeating into the void. Pin extraction per producer: any file
    // that calls postSentryHeartbeat must yield >= 1 slug.
    const silent = nonOneshotFiles().filter((file) => {
      // _-prefixed files are shared helper modules (one of them DEFINES
      // postSentryHeartbeat), not heartbeat producers.
      if (file.startsWith("_")) return false;
      const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
      if (!src.includes("postSentryHeartbeat")) return false;
      return [...src.matchAll(SLUG_RE)].length === 0;
    });
    expect(
      silent,
      `handler(s) call postSentryHeartbeat but SLUG_RE extracted no slug — ` +
        `declare the canonical \`const SENTRY_MONITOR_SLUG = "<kebab>"\` shape ` +
        `(or fix SLUG_RE if the convention changed): ${silent.join(", ")}`,
    ).toEqual([]);
  });

  it("oneshot-* files declare no monitor slug (ADR-033 prefix table) outside the exempt list", () => {
    const offenders: string[] = [];
    for (const file of readdirSync(FUNCTIONS_DIR)) {
      if (!file.startsWith("oneshot-") || !file.endsWith(".ts")) continue;
      const src = readFileSync(join(FUNCTIONS_DIR, file), "utf-8");
      for (const m of src.matchAll(SLUG_RE)) {
        if (!ONESHOT_SLUG_EXEMPTIONS.has(m[1])) {
          offenders.push(`${file} -> ${m[1]}`);
        }
      }
    }
    expect(
      offenders,
      `oneshot functions must not declare SENTRY_MONITOR_SLUG (a crontab ` +
        `monitor false-alerts on a non-recurring fn; check-ins to an ` +
        `un-provisioned slug are void). Route errors via reportSilentFallback ` +
        `instead, or add a deliberate exemption: ${offenders.join(", ")}`,
    ).toEqual([]);
  });

  it("tf name-attr extraction is pinned to the resource count (no prose/foreign-resource leak)", () => {
    expect(iacMonitorNames().size).toBe(iacResourceCount());
  });

  it("every code slug has a sentry_cron_monitor resource in cron-monitors.tf", () => {
    const names = iacMonitorNames();
    const missing = codeSlugs().filter(
      (s) => !names.has(s) && !DISABLED_CRON_SLUG_EXEMPTIONS.has(s),
    );
    expect(
      missing,
      `Inngest handlers heartbeat to monitor slug(s) with no IaC resource — ` +
        `check-ins are silently dropped and a dead cron pages nowhere. Add a ` +
        `sentry_cron_monitor block to apps/web-platform/infra/sentry/` +
        `cron-monitors.tf for: ${missing.join(", ")}`,
    ).toEqual([]);
  });
});
