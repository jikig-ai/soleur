import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

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
  it("manifest is non-empty and lists the crons these tests exercise", () => {
    expect(EXPECTED_CRON_FUNCTIONS.length).toBeGreaterThan(0);
    expect(EXPECTED_CRON_FUNCTIONS).toContain("cron-oauth-probe");
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
    expect(manualTriggerEventFor("cron-oauth-probe")).toBe(
      "cron/oauth-probe.manual-trigger",
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
      (f) => !f.slug.endsWith("-cron-oauth-probe"),
    );
    const results = classifyRegistry(registry);
    const probe = results.find((r) => r.fnId === "cron-oauth-probe");
    expect(probe?.status).toBe("MISSING");
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
      fullRegistry().filter((f) => !f.slug.endsWith("-cron-oauth-probe")),
    );
    const plan = planHeal(results);
    expect(plan.missingFnIds).toEqual(["cron-oauth-probe"]);
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
    const missing = ["cron-oauth-probe"];
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
    expect(nextDefectStreaks(undefined, ["cron-oauth-probe"])).toEqual({
      "cron-oauth-probe": 1,
    });
  });

  it("nextDefectStreaks: empty defect set clears all streaks", () => {
    expect(nextDefectStreaks({ "cron-x": 5 }, [])).toEqual({});
  });

  it("nextDefectStreaks: tracks MISSING and UNPLANNED in one unified streak set", () => {
    // defect = MISSING ∪ UNPLANNED — a MISSING fn accrues a streak exactly like
    // an UNPLANNED one, so neither escalates to restart on the first tick.
    const next = nextDefectStreaks(undefined, [
      "cron-oauth-probe", // MISSING (H9a)
      "cron-community-monitor", // UNPLANNED (H9b)
    ]);
    expect(next).toEqual({
      "cron-oauth-probe": 1,
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
    const s1 = nextDefectStreaks(undefined, ["cron-oauth-probe"]);
    expect(escalatedDefectFnIds(s1)).toEqual([]);
    // The grace-th consecutive defective tick (threshold=2) escalates to backstop.
    const s2 = nextDefectStreaks(s1, ["cron-oauth-probe"]);
    expect(escalatedDefectFnIds(s2)).toEqual(["cron-oauth-probe"]);
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

  // Parity guard (#10136: relaxed from "equals every site" to SET MEMBERSHIP). The web-platform container's INNGEST_BASE_URL
  // is now produced by ONE resolver (ci-deploy.sh resolve_inngest_link) whose only two values are the http default and the
  // verified-TLS endpoint; the canary and prod `docker run` sites carry the resolver's expansion, never a literal, and only
  // the first-boot site in cloud-init.yml (which cannot call the resolver) keeps a literal, the http default. The fallback
  // below is used ONLY when INNGEST_BASE_URL is unset in the container, and it stays http: it must be a member of the
  // resolver's value set (a repoint of the host that misses this constant goes red), and the site shapes are pinned so a
  // third value or a literal at a resolver-governed site goes red naming the file.
  const infraFile = (file: string) => readFileSync(resolve(__dirname, "../../../infra", file), "utf8");
  const resolverValues = () => {
    const src = infraFile("ci-deploy.sh");
    const http = src.match(/^INNGEST_LINK_HTTP_URL="([^"]+)"$/m)?.[1];
    const https = src.match(/^INNGEST_LINK_HTTPS_URL="([^"]+)"$/m)?.[1];
    return { http, https };
  };

  it("the resolver produces exactly two values and INNGEST_HOST_FALLBACK (still http) is a member", () => {
    const { http, https } = resolverValues();
    expect(http, "ci-deploy.sh INNGEST_LINK_HTTP_URL").toBeDefined();
    expect(https, "ci-deploy.sh INNGEST_LINK_HTTPS_URL").toBeDefined();
    const set = new Set([http, https]);
    expect([...set].sort()).toEqual(["http://10.0.1.40:8288", "https://10.0.1.40:8443"]);
    const fallback = resolveInngestHost(undefined);
    expect(set.has(fallback), `INNGEST_HOST_FALLBACK ${fallback} must be a resolver value`).toBe(true);
    expect(fallback, "the fallback stays plain http: the soak counts its use rather than hiding it").toBe(http);
  });

  it("every INNGEST_BASE_URL site is the resolver expansion (canary, prod) or a resolver-set literal (first boot)", () => {
    const SITE_RE = /^\s*-e INNGEST_BASE_URL=([^\s\\]+)/gm;
    const { http, https } = resolverValues();
    const members = new Set([http, https]);
    for (const [file, count] of [
      ["ci-deploy.sh", 2],
      ["cloud-init.yml", 1],
    ] as const) {
      const values = [...infraFile(file).matchAll(SITE_RE)].map((m) => m[1]);
      if (file === "ci-deploy.sh") {
        expect(values, `${file} INNGEST_BASE_URL sites`).toEqual(
          Array(count).fill('"$INNGEST_BASE_URL_RESOLVED"'),
        );
      } else {
        expect(values, `${file} INNGEST_BASE_URL sites`).toHaveLength(count);
        for (const v of values) expect(members.has(v), `${file} literal ${v} is a resolver value`).toBe(true);
      }
    }
  });

  // The fallback is only reachable when INNGEST_BASE_URL is UNSET in the container. The closed-world tuple gate
  // (infra/lib/docker-run-tuple.py) must therefore refuse a tuple without it: drop the variable from a COPY of each
  // `docker run` and the gate has to go red with MISSING_REQUIRED naming the tuple.
  it("the tuple gate forbids an unset INNGEST_BASE_URL path (the http fallback is unreachable by construction)", () => {
    const helper = resolve(__dirname, "../../../infra/lib/docker-run-tuple.py");
    const mutations: Array<[string, string, string]> = [
      ["ci-deploy.sh", '      -e INNGEST_BASE_URL="$INNGEST_BASE_URL_RESOLVED" \\\n', "canary"],
      ["ci-deploy.sh", '        -e INNGEST_BASE_URL="$INNGEST_BASE_URL_RESOLVED" \\\n', "prod"],
      ["cloud-init.yml", "      -e INNGEST_BASE_URL=http://10.0.1.40:8288 \\\n", "first-boot"],
    ];
    for (const [file, line, tuple] of mutations) {
      const tmp = mkdtempSync(join(tmpdir(), "inngest-unset-url-"));
      try {
        const infra = join(tmp, "apps", "web-platform", "infra");
        mkdirSync(infra, { recursive: true });
        for (const f of ["ci-deploy.sh", "cloud-init.yml"]) {
          let text = infraFile(f);
          if (f === file) {
            expect(text.includes(line), `${file}: the ${tuple} INNGEST_BASE_URL line moved; update this anchor`).toBe(true);
            text = text.replace(line, "");
          }
          writeFileSync(join(infra, f), text);
        }
        const r = spawnSync("python3", ["-I", helper, "check", "--root", tmp], { encoding: "utf8", timeout: 60_000 });
        expect(r.error, `python3 could not be spawned: ${String(r.error)}`).toBeUndefined();
        expect(r.status, `${tuple}: expected exit 1, got:\n${r.stdout}${r.stderr}`).toBe(1);
        expect(r.stdout).toMatch(new RegExp(`^FAIL MISSING_REQUIRED: -e INNGEST_BASE_URL is required in every tuple.* in ${file.replace(".", "\\.")} ${tuple}`, "m"));
      } finally {
        rmSync(tmp, { recursive: true, force: true });
      }
    }
  });
});
