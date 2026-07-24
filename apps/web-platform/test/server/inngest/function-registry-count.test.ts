import { readdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE ES-module imports — sets NEXT_PHASE so importing the
// watchdog (which transitively loads the inngest client) does not throw on the
// missing INNGEST_SIGNING_KEY in the test env. Mirrors cron-community-monitor.test.ts.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import { EXPECTED_CRON_FUNCTIONS } from "@/server/inngest/functions/cron-inngest-cron-watchdog";

const ROUTE_PATH = resolve(
  __dirname,
  "../../../app/api/inngest/route.ts",
);
const FUNCTIONS_DIR = resolve(
  __dirname,
  "../../../server/inngest/functions",
);
const CRON_MONITORS_TF = resolve(
  __dirname,
  "../../../infra/sentry/cron-monitors.tf",
);
const routeSrc = readFileSync(ROUTE_PATH, "utf8");
const tfSrc = readFileSync(CRON_MONITORS_TF, "utf8");

function extractRouteArrayEntries(): string[] {
  return [...routeSrc.matchAll(/^\s+(\w+),$/gm)].map((m) => m[1]);
}

function listCronFiles(): string[] {
  return readdirSync(FUNCTIONS_DIR)
    .filter((f) => f.startsWith("cron-") && f.endsWith(".ts") && !f.startsWith("_"))
    .map((f) => f.replace(/\.ts$/, ""));
}

function extractSentryMonitorSlugs(): Map<string, string> {
  const slugs = new Map<string, string>();
  for (const file of listCronFiles()) {
    const src = readFileSync(resolve(FUNCTIONS_DIR, `${file}.ts`), "utf8");
    const m = src.match(/SENTRY_MONITOR_SLUG\s*=\s*"([^"]+)"/);
    if (m) slugs.set(file, m[1]);
  }
  return slugs;
}

function extractTfMonitorNames(): Set<string> {
  return new Set([...tfSrc.matchAll(/name\s*=\s*"([^"]+)"/g)].map((m) => m[1]));
}

const KNOWN_UNMONITORED_SLUGS = new Set([
  "scheduled-campaign-calendar",
  "scheduled-cloud-task-heartbeat",
  // scheduled-content-generator REMOVED from exemption (#4684): it is a real
  // output producer (creates a scheduled-content-generator issue every run) and
  // now has a sentry_cron_monitor in cron-monitors.tf. Its prior exemption is
  // exactly why its post-migration silence went unalerted at the per-function
  // layer — the monitor it checked into did not exist.
  "scheduled-content-publisher",
  "scheduled-growth-audit",
  "scheduled-growth-execution",
  "scheduled-linkedin-token-check",
  "scheduled-membership-health",
  "scheduled-nag-4216-readiness",
  "scheduled-plausible-goals",
  "scheduled-rule-prune",
  "scheduled-ruleset-bypass-audit",
  "scheduled-seo-aeo-audit",
  "scheduled-weekly-analytics",
  // New (never a GHA workflow). Findings alert via reportSilentFallback Sentry
  // issues, not a cron monitor; tf monitor deferred with the TR9 batch (#4476).
  "cron-workspace-sync-health",
  // #6031 (ADR-088 arm-b) — the GHCR minter cron is DISABLED (App installation
  // tokens can't pull the private repo-linked packages; pending GitHub support).
  // Its handler no-ops under GHCR_MINTER_DISABLED=true, so the sentry monitor was
  // removed; the slug is exempt here until the cron is re-enabled or removed.
  "scheduled-ghcr-token-minter",
]);

const NON_INNGEST_MONITORS = new Set([
  "scheduled-terraform-drift",
  // #6549 item 2: GHA-fired (scheduled-terraform-drift.yml → heartbeat-live-reconcile
  // job) — the source-vs-live Better Stack heartbeat reconcile. Its final
  // sentry-heartbeat step pings the check-in; there is no Inngest cron function, so
  // it maps to no SENTRY_MONITOR_SLUG — same class as scheduled-terraform-drift.
  "scheduled-heartbeat-reconcile",
  // #3366: GHA-fired executor (scheduled-supabase-advisor-scan.yml) posts the
  // heartbeat at the end of the run; the cron-supabase-advisor-scan.ts
  // dispatcher declares no SENTRY_MONITOR_SLUG (it only dispatches and holds no
  // Supabase PAT), so this monitor maps to no Inngest slug — same class as
  // scheduled-terraform-drift.
  "scheduled-supabase-advisor-scan",
  // #5872: GHA-fired executor (scheduled-domain-model-drift.yml) POSTs the
  // heartbeat; the cron-domain-model-drift.ts dispatcher declares no
  // SENTRY_MONITOR_SLUG, so this monitor maps to no Inngest slug — same class
  // as scheduled-terraform-drift.
  "scheduled-domain-model-drift",
  "scheduled-realtime-probe",
  // #5046 PR-2: HOST-systemd-fired (cron-egress-resolve.timer pings the
  // check-in from cron-egress-resolve.sh) — not an Inngest function and not
  // a GHA workflow; same "no cron-*.ts counterpart" class as the GHA pair.
  "cron-egress-resolve",
  // #6291: GHA-fired (scheduled-zot-restart-loop.yml) — a bash-pipeline infra
  // cron (Better Stack Logs recurrence alarm) in ADR-033 I7's uncontained
  // class, deliberately NOT an Inngest function; its final sentry-heartbeat
  // step pings the check-in. Same class as scheduled-realtime-probe.
  "scheduled-zot-restart-loop",
  // #6374: GHA-fired (scheduled-inngest-health.yml, on.schedule '*/15') — the
  // EXTERNAL inngest health watchdog. It MUST be external to Inngest (a
  // self-hosted inngest cron cannot detect inngest being down — the #5542 blind
  // spot), so it has no cron-*.ts counterpart and declares no SENTRY_MONITOR_SLUG
  // const; its final sentry-heartbeat step pings the check-in. Same class as
  // scheduled-realtime-probe / scheduled-zot-restart-loop.
  "scheduled-inngest-health",
]);

describe("Inngest function registry — drift guards", () => {
  const routeEntries = extractRouteArrayEntries();
  const cronFiles = listCronFiles();
  const slugMap = extractSentryMonitorSlugs();
  const tfMonitors = extractTfMonitorNames();

  // Vacuous-pass guards: if regex extraction returns 0, downstream
  // subset/containment assertions pass trivially.
  it("extraction sanity: helpers return non-empty results", () => {
    expect(routeEntries.length).toBeGreaterThan(0);
    expect(cronFiles.length).toBeGreaterThan(0);
    expect(slugMap.size).toBeGreaterThan(0);
    expect(tfMonitors.size).toBeGreaterThan(0);
  });

  // UPDATE this number when adding/removing Inngest functions.
  it("(a) route.ts functions array has expected count", () => {
    expect(routeEntries.length).toBe(67);
  });

  // EVENT functions are invisible to the cron-glob guards (b)/(e) — they only
  // sweep cron-*.ts files. emailOnReceived (email/inbound.received pipeline,
  // feat-operator-inbox-delegation) landed UNREGISTERED in Phase 4; without
  // this explicit presence assertion a future route.ts refactor could drop it
  // again and every inbound email would silently queue unprocessed (plan AC6).
  it("(a2) emailOnReceived event function is registered in route.ts", () => {
    expect(routeEntries).toContain("emailOnReceived");
  });

  it("(b) every cron-*.ts file is registered in route.ts functions array", () => {
    const routeSet = new Set(routeEntries.map((e) => e.toLowerCase()));

    const missing: string[] = [];
    for (const file of cronFiles) {
      const parts = file.split("-");
      const camel = parts[0] + parts.slice(1).map((p) => p[0].toUpperCase() + p.slice(1)).join("");
      if (!routeSet.has(camel.toLowerCase())) {
        missing.push(`${file} (expected identifier ~${camel})`);
      }
    }
    expect(missing).toEqual([]);
  });

  it("(c) every SENTRY_MONITOR_SLUG has a cron-monitors.tf resource (or is explicitly exempt)", () => {
    const unmonitored: string[] = [];
    for (const [file, slug] of slugMap) {
      if (!tfMonitors.has(slug) && !KNOWN_UNMONITORED_SLUGS.has(slug)) {
        unmonitored.push(`${file}: ${slug}`);
      }
    }
    expect(unmonitored).toEqual([]);
  });

  it("(c2) every cron-monitors.tf resource name maps to a registered cron function or GHA workflow", () => {
    const slugValues = new Set(slugMap.values());
    const phantom: string[] = [];
    for (const name of tfMonitors) {
      if (!slugValues.has(name) && !NON_INNGEST_MONITORS.has(name)) {
        phantom.push(name);
      }
    }
    expect(phantom).toEqual([]);
  });

  it("(d) KNOWN_UNMONITORED_SLUGS contains no stale entries", () => {
    const actualSlugs = new Set(slugMap.values());
    const stale = [...KNOWN_UNMONITORED_SLUGS].filter((s) => !actualSlugs.has(s));
    expect(stale).toEqual([]);
  });

  // The watchdog (cron-inngest-cron-watchdog) classifies a fixed EXPECTED_CRON_
  // FUNCTIONS manifest against the running /v1/functions registry. If a new
  // cron-*.ts file lands but the manifest is not updated, the watchdog would
  // silently stop monitoring it — this parity guard forces the two in lockstep.
  it("(e) watchdog EXPECTED_CRON_FUNCTIONS matches the cron-*.ts file set", () => {
    expect(new Set(EXPECTED_CRON_FUNCTIONS)).toEqual(new Set(cronFiles));
  });

  // (f)/(f2) — the `-target=` allowlist parity guards — are deliberately GONE.
  // apply-sentry-infra.yml now plans the sentry root FULL, so the plan universe is
  // `state UNION config` and `declared ≡ applied` by construction: there is no
  // target list for a .tf resource to be missing from (f), and no target that can
  // name a non-existent resource (f2). Both could only be restated as a set
  // compared against itself — assertions incapable of going red. The failure they
  // guarded (a declared monitor silently never created) is now structurally
  // impossible rather than test-enforced. Do NOT reintroduce them without first
  // reintroducing `-target=`.

  // #5159: serve() must pin serveHost to the canonical public origin so EVERY
  // registration (boot, --poll-interval sync, loopback re-register PUT) reports
  // the public serve URL. Without this, a loopback PUT registers
  // http://127.0.0.1:3000 — accepted (HTTP 200) but never cron-planned (the
  // 2026-06-11 AC15 failure, surfaced by #5178's inngest_register_http=200 +
  // inngest_crons:{} diagnostic).
  //
  // serveHost MUST be the HARDCODED canonical origin gated on NODE_ENV, NOT
  // process.env.NEXT_PUBLIC_APP_URL: #5182 used NEXT_PUBLIC_APP_URL and was a
  // silent no-op because Next.js build-inlines process.env.NEXT_PUBLIC_* at
  // BUILD time and that var is not a Docker build ARG (→ inlined `undefined`).
  // Hardcoding matches the security-motivated server/cf-cache-purge.ts
  // convention (`const APP_ORIGIN = "https://app.soleur.ai"`).
  it("(g) route.ts pins serveHost to the hardcoded prod origin gated on NODE_ENV (#5159)", () => {
    // The canonical origin is a string literal gated on NODE_ENV === production.
    expect(routeSrc).toMatch(
      /const SERVE_HOST\s*=\s*[\s\S]*process\.env\.NODE_ENV\s*===\s*["']production["'][\s\S]*["']https:\/\/app\.soleur\.ai["']/,
    );
    expect(routeSrc).toMatch(/serveHost:\s*SERVE_HOST/);
    expect(routeSrc).toMatch(/servePath:\s*["']\/api\/inngest["']/);
    // Must NOT derive serveHost from NEXT_PUBLIC_APP_URL — that build-inlines as
    // undefined in the prod container (the #5182 no-op regression class).
    expect(routeSrc).not.toMatch(/SERVE_HOST\s*=\s*process\.env\.NEXT_PUBLIC_APP_URL/);
  });
});
