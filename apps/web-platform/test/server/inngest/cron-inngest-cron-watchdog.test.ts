import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE the ES-module imports below — sets NEXT_PHASE so the
// inngest client's startup-key check short-circuits (same path next build
// uses). Mirrors cron-community-monitor.test.ts.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  EXPECTED_CRON_FUNCTIONS,
  POLL_RECOVERY_GRACE_TICKS,
  RESTART_COOLDOWN_MS,
  classifyRegistry,
  escalatedDefectFnIds,
  manualTriggerEventFor,
  nextDefectStreaks,
  planHeal,
  resolveInngestHost,
  restartAllowed,
  shouldRestart,
  type RegistryFunction,
} from "@/server/inngest/functions/cron-inngest-cron-watchdog";

// Synthesized fixtures only (cq-test-fixtures-synthesized-only) — no captured
// production payloads. The /v1/functions shape mirrors the self-hosted Inngest
// read API: an array of { slug, triggers: [{ cron } | { event }] }. The app id
// is "soleur-runtime", so real slugs are app-prefixed.

function planned(fnId: string, cron = "0 8 * * *"): RegistryFunction {
  return {
    slug: `soleur-runtime-${fnId}`,
    triggers: [{ cron }, { event: `cron/${fnId.replace(/^cron-/, "")}.manual-trigger` }],
  };
}

function eventOnly(fnId: string): RegistryFunction {
  // Registered but cron trigger de-planned (H9b) — only the manual-trigger
  // event trigger survives.
  return {
    slug: `soleur-runtime-${fnId}`,
    triggers: [{ event: `cron/${fnId.replace(/^cron-/, "")}.manual-trigger` }],
  };
}

function fullRegistry(): RegistryFunction[] {
  return EXPECTED_CRON_FUNCTIONS.map((fnId) => planned(fnId));
}

describe("cron-inngest-cron-watchdog — manifest", () => {
  it("manifest is non-empty and includes the two regressed monitors", () => {
    expect(EXPECTED_CRON_FUNCTIONS.length).toBeGreaterThan(0);
    expect(EXPECTED_CRON_FUNCTIONS).toContain("cron-gh-pages-cert-state");
    expect(EXPECTED_CRON_FUNCTIONS).toContain("cron-community-monitor");
  });

  it("manifest entries are unique", () => {
    expect(new Set(EXPECTED_CRON_FUNCTIONS).size).toBe(
      EXPECTED_CRON_FUNCTIONS.length,
    );
  });
});

describe("cron-inngest-cron-watchdog — manualTriggerEventFor", () => {
  it("maps cron-<name> id → cron/<name>.manual-trigger event", () => {
    expect(manualTriggerEventFor("cron-community-monitor")).toBe(
      "cron/community-monitor.manual-trigger",
    );
    expect(manualTriggerEventFor("cron-gh-pages-cert-state")).toBe(
      "cron/gh-pages-cert-state.manual-trigger",
    );
  });
});

describe("cron-inngest-cron-watchdog — classifyRegistry", () => {
  it("all functions present + cron-planned → zero defects (Scenario 1)", () => {
    const results = classifyRegistry(fullRegistry());
    expect(results.every((r) => r.status === "OK")).toBe(true);
    expect(results.filter((r) => r.status !== "OK")).toEqual([]);
  });

  it("function slug absent from registry → MISSING / H9a (Scenario 2)", () => {
    const registry = fullRegistry().filter(
      (f) => !f.slug.endsWith("-cron-gh-pages-cert-state"),
    );
    const results = classifyRegistry(registry);
    const cert = results.find((r) => r.fnId === "cron-gh-pages-cert-state");
    expect(cert?.status).toBe("MISSING");
  });

  it("function present but no cron-type trigger → UNPLANNED / H9b (Scenario 3)", () => {
    const registry = fullRegistry().map((f) =>
      f.slug.endsWith("-cron-community-monitor")
        ? eventOnly("cron-community-monitor")
        : f,
    );
    const results = classifyRegistry(registry);
    const community = results.find((r) => r.fnId === "cron-community-monitor");
    expect(community?.status).toBe("UNPLANNED");
  });

  it("matches bare (non-app-prefixed) slugs too", () => {
    const registry: RegistryFunction[] = [
      { slug: "cron-community-monitor", triggers: [{ cron: "0 8 * * *" }] },
    ];
    const results = classifyRegistry(registry, ["cron-community-monitor"]);
    expect(results[0].status).toBe("OK");
  });

  it("ignores empty-string cron values (treats as no cron trigger)", () => {
    const registry: RegistryFunction[] = [
      { slug: "soleur-runtime-cron-community-monitor", triggers: [{ cron: "" }] },
    ];
    const results = classifyRegistry(registry, ["cron-community-monitor"]);
    expect(results[0].status).toBe("UNPLANNED");
  });
});

describe("cron-inngest-cron-watchdog — planHeal", () => {
  it("UNPLANNED → exactly one manual-trigger event, no missing (Scenario 4)", () => {
    const results = classifyRegistry(
      fullRegistry().map((f) =>
        f.slug.endsWith("-cron-community-monitor")
          ? eventOnly("cron-community-monitor")
          : f,
      ),
    );
    const plan = planHeal(results);
    expect(plan.manualTriggerEvents).toEqual([
      "cron/community-monitor.manual-trigger",
    ]);
    expect(plan.missingFnIds).toEqual([]);
    expect(plan.defectCount).toBe(1);
  });

  it("MISSING → recorded as missing, not a manual-trigger", () => {
    const results = classifyRegistry(
      fullRegistry().filter((f) => !f.slug.endsWith("-cron-gh-pages-cert-state")),
    );
    const plan = planHeal(results);
    expect(plan.missingFnIds).toEqual(["cron-gh-pages-cert-state"]);
    expect(plan.manualTriggerEvents).toEqual([]);
    expect(plan.defectCount).toBe(1);
  });

  it("clean registry → no heal actions, zero defects", () => {
    const plan = planHeal(classifyRegistry(fullRegistry()));
    expect(plan.manualTriggerEvents).toEqual([]);
    expect(plan.missingFnIds).toEqual([]);
    expect(plan.defectCount).toBe(0);
  });
});

describe("cron-inngest-cron-watchdog — restart cooldown (AC6, non-thrashing)", () => {
  const NOW = Date.parse("2026-05-30T12:00:00Z");

  it("restartAllowed: no prior restart → allowed", () => {
    expect(restartAllowed(null, NOW)).toBe(true);
  });

  it("restartAllowed: restart within cooldown window → blocked", () => {
    const recent = new Date(NOW - RESTART_COOLDOWN_MS / 2).toISOString();
    expect(restartAllowed(recent, NOW)).toBe(false);
  });

  it("restartAllowed: restart older than cooldown → allowed", () => {
    const old = new Date(NOW - RESTART_COOLDOWN_MS - 1000).toISOString();
    expect(restartAllowed(old, NOW)).toBe(true);
  });

  it("restartAllowed: unparseable timestamp fails open (allowed)", () => {
    expect(restartAllowed("not-a-date", NOW)).toBe(true);
  });

  it("two consecutive H9a ticks within cooldown → exactly one restart attempt", () => {
    // Tick 1: no prior restart, a function is MISSING → restart.
    const missing = ["cron-gh-pages-cert-state"];
    const tick1At = NOW;
    expect(shouldRestart(missing, null, tick1At)).toBe(true);

    // The watchdog persists last_restart_at = tick1At after restarting.
    const persisted = new Date(tick1At).toISOString();

    // Tick 2 runs one watchdog interval later (4h) — still inside the 6h
    // cooldown → must NOT restart again.
    const tick2At = tick1At + 4 * 60 * 60 * 1000;
    expect(shouldRestart(missing, persisted, tick2At)).toBe(false);
  });

  it("shouldRestart: no restart-trigger functions → never restarts even if allowed", () => {
    expect(shouldRestart([], null, NOW)).toBe(false);
  });

  it("restartAllowed: exactly at the cooldown boundary → allowed (>= semantics)", () => {
    const exactly = new Date(NOW - RESTART_COOLDOWN_MS).toISOString();
    expect(restartAllowed(exactly, NOW)).toBe(true);
  });
});

describe("cron-inngest-cron-watchdog — defect-streak backstop (#4652)", () => {
  it("nextDefectStreaks: increments current defect fns, drops poll-recovered fns", () => {
    const prev = { "cron-community-monitor": 1, "cron-oauth-probe": 3 };
    // community still defective this tick; oauth-probe poll-recovered (not in list).
    const next = nextDefectStreaks(prev, ["cron-community-monitor"]);
    expect(next).toEqual({ "cron-community-monitor": 2 });
  });

  it("nextDefectStreaks: starts a fresh streak at 1 with no prior state", () => {
    expect(nextDefectStreaks(undefined, ["cron-gh-pages-cert-state"])).toEqual({
      "cron-gh-pages-cert-state": 1,
    });
  });

  it("nextDefectStreaks: empty defect set clears all streaks", () => {
    expect(nextDefectStreaks({ "cron-x": 5 }, [])).toEqual({});
  });

  it("nextDefectStreaks: tracks MISSING and UNPLANNED in one unified streak set", () => {
    // defect = MISSING ∪ UNPLANNED — a MISSING fn accrues a streak exactly like
    // an UNPLANNED one, so neither escalates to restart on the first tick.
    const next = nextDefectStreaks(undefined, [
      "cron-gh-pages-cert-state", // MISSING (H9a)
      "cron-community-monitor", // UNPLANNED (H9b)
    ]);
    expect(next).toEqual({
      "cron-gh-pages-cert-state": 1,
      "cron-community-monitor": 1,
    });
  });

  it("escalatedDefectFnIds: only fns at/over the grace threshold escalate", () => {
    const streaks = {
      "cron-community-monitor": POLL_RECOVERY_GRACE_TICKS,
      "cron-oauth-probe": POLL_RECOVERY_GRACE_TICKS - 1,
    };
    expect(escalatedDefectFnIds(streaks)).toEqual(["cron-community-monitor"]);
  });

  it("MISSING (H9a) does NOT escalate on the first tick — polling gets a grace window", () => {
    // Regression guard for the #4652 demotion: pre-#4652 a MISSING fn went
    // straight to the restart path on tick 1. Now it must accrue a streak first.
    const s1 = nextDefectStreaks(undefined, ["cron-gh-pages-cert-state"]);
    expect(escalatedDefectFnIds(s1)).toEqual([]);
    // The grace-th consecutive defective tick (threshold=2) escalates to backstop.
    const s2 = nextDefectStreaks(s1, ["cron-gh-pages-cert-state"]);
    expect(escalatedDefectFnIds(s2)).toEqual(["cron-gh-pages-cert-state"]);
  });

  it("escalation lifecycle: a single defective tick does NOT escalate; the grace-th tick does", () => {
    // Tick 1: defective → streak 1 → not escalated (polling has its grace window).
    const s1 = nextDefectStreaks(undefined, ["cron-community-monitor"]);
    expect(escalatedDefectFnIds(s1)).toEqual([]);
    // Tick 2 (grace=2): still defective → streak 2 → escalates to backstop restart.
    const s2 = nextDefectStreaks(s1, ["cron-community-monitor"]);
    expect(escalatedDefectFnIds(s2)).toEqual(["cron-community-monitor"]);
  });
});

describe("cron-inngest-cron-watchdog — resolveInngestHost", () => {
  it("derives base URL from INNGEST_BASE_URL when set", () => {
    expect(resolveInngestHost("http://127.0.0.1:8288")).toBe(
      "http://127.0.0.1:8288",
    );
    expect(resolveInngestHost("http://host.docker.internal:8288/")).toBe(
      "http://host.docker.internal:8288",
    );
  });

  it("falls back to the dedicated inngest host when unset", () => {
    expect(resolveInngestHost(undefined)).toBe("http://10.0.1.40:8288");
    expect(resolveInngestHost("")).toBe("http://10.0.1.40:8288");
  });

  // Parity guard: the fallback host must equal the INNGEST_BASE_URL that
  // ci-deploy.sh injects into the web-platform container. If that env value
  // changes (port bump, host form), the dormant fallback would silently point
  // at the wrong loopback during a partial-env restart.
  it("INNGEST_HOST_FALLBACK matches the INNGEST_BASE_URL ci-deploy.sh sets", () => {
    const ciDeploy = readFileSync(
      resolve(__dirname, "../../../infra/ci-deploy.sh"),
      "utf8",
    );
    const m = ciDeploy.match(/INNGEST_BASE_URL=(http:\/\/[^\s\\]+)/);
    expect(m).not.toBeNull();
    expect(resolveInngestHost(undefined)).toBe(m![1]);
  });
});
