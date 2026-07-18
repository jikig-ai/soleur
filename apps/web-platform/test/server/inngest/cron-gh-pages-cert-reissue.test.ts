// #6657 — cron-gh-pages-cert-reissue unit tests.
//
// Coverage:
//   - Pure orchestration (runReissue) over INJECTED deps: happy path, poll
//     timeout, stuck-state allowlist abort (zero writes), precondition-blocked,
//     partial-toggle / cname-PUT reissue_failed (abort→restore).
//   - restoreState: symmetric {cname, proxied} restore, idempotent, throws on
//     non-convergence (the proxy_restore_failed brake).
//   - onFailure: proves the restore runs via the onFailure lifecycle handler
//     (NOT a JS try…finally) against a stateful Octokit + CF fetch mock.
//   - Source-shape anchors: registration id / event trigger / no cron schedule /
//     onFailure present / scoped token / no finally-spanning-step.sleep.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

// Partial mock so the SUT's REPO_OWNER/REPO_NAME/HandlerArgs survive while the
// onFailure test controls mintInstallationToken (never calls the real GitHub App).
vi.mock("@/server/inngest/functions/_cron-shared", async (importOriginal) => {
  const actual =
    await importOriginal<
      typeof import("@/server/inngest/functions/_cron-shared")
    >();
  return { ...actual, mintInstallationToken: vi.fn(async () => "fake-installation-token") };
});

import {
  runReissue,
  restoreState,
  assertStuckState,
  checkReissuePreconditions,
  setRecordsProxied,
  PartialToggleError,
  cronGhPagesCertReissue,
  cronGhPagesCertReissueOnFailure,
  type ReissueDeps,
  type CfDnsRecord,
  type PreconditionInputs,
} from "@/server/inngest/functions/cron-gh-pages-cert-reissue";

// =============================================================================
// Injected-deps fake
// =============================================================================

const APEX_A_IDS = ["a1", "a2", "a3", "a4"];
const WWW_ID = "w1";

function defaultRecords(proxied: boolean): CfDnsRecord[] {
  return [
    ...APEX_A_IDS.map((id) => ({ id, name: "soleur.ai", type: "A", proxied })),
    { id: WWW_ID, name: "www.soleur.ai", type: "CNAME", proxied },
  ];
}

function healthyPreconditions(): PreconditionInputs {
  return {
    acmeApexStatus: 404,
    acmeWwwStatus: 404,
    caaCount: 0,
    challengeTxtPresent: true,
    alwaysUseHttps: "off",
  };
}

interface FakeConfig {
  stateOverride?: string;
  willIssue?: boolean;
  initialProxied?: boolean;
  initialCname?: string | null;
  preconditions?: PreconditionInputs;
  failToggleOffIds?: string[]; // setRecordProxied(false) returns false
  failToggleOnIds?: string[]; // setRecordProxied(true) returns false
  failCnameOn?: "null" | "set";
}

function makeFake(cfg: FakeConfig = {}) {
  const state = {
    cname: cfg.initialCname === undefined ? "soleur.ai" : cfg.initialCname,
    records: defaultRecords(cfg.initialProxied ?? true),
    reissued: false,
    clock: 0,
    sawNull: false,
  };
  const calls = {
    setRecordProxied: [] as Array<{ id: string; proxied: boolean }>,
    setPagesCname: [] as Array<string | null>,
    getPages: 0,
  };
  const resolveState = () => {
    if (cfg.stateOverride) return cfg.stateOverride;
    if (state.reissued && cfg.willIssue) return "issued";
    return "bad_authz";
  };
  const deps: ReissueDeps = {
    async getPages() {
      calls.getPages += 1;
      return { state: resolveState(), cname: state.cname };
    },
    async setPagesCname(cname) {
      calls.setPagesCname.push(cname);
      if (cfg.failCnameOn === "null" && cname === null)
        throw new Error("PUT /pages cname:null → 403");
      if (cfg.failCnameOn === "set" && cname === "soleur.ai")
        throw new Error("PUT /pages cname:set → 403");
      if (cname === null) state.sawNull = true;
      if (cname === "soleur.ai" && state.sawNull) state.reissued = true;
      state.cname = cname;
    },
    async listToggleRecords() {
      return state.records.map((r) => ({ ...r }));
    },
    async setRecordProxied(id, proxied) {
      calls.setRecordProxied.push({ id, proxied });
      if (proxied === false && cfg.failToggleOffIds?.includes(id)) return false;
      if (proxied === true && cfg.failToggleOnIds?.includes(id)) return false;
      const rec = state.records.find((r) => r.id === id);
      if (rec) rec.proxied = proxied;
      return true;
    },
    async gatherPreconditions() {
      return cfg.preconditions ?? healthyPreconditions();
    },
    sleep: async (ms) => {
      state.clock += ms;
    },
    now: () => state.clock,
    logger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  };
  return { deps, state, calls };
}

// =============================================================================
// Pure helper unit tests
// =============================================================================

describe("assertStuckState — allowlist gate (AC6)", () => {
  it.each([
    ["bad_authz", true],
    ["failed", true],
    ["issued", false],
    ["approved", false],
    ["authorization_pending", false],
    ["dns_changed", false],
    ["new", false],
  ])("state=%s → proceed=%s", (state, proceed) => {
    expect(assertStuckState(state).proceed).toBe(proceed);
  });
});

describe("checkReissuePreconditions", () => {
  it("all healthy → ok", () => {
    expect(checkReissuePreconditions(healthyPreconditions()).ok).toBe(true);
  });
  it("CAA present → fails caaPermissive", () => {
    const r = checkReissuePreconditions({ ...healthyPreconditions(), caaCount: 2 });
    expect(r.ok).toBe(false);
    expect(r.failed).toContain("caaPermissive");
  });
  it("challenge TXT missing → fails", () => {
    const r = checkReissuePreconditions({
      ...healthyPreconditions(),
      challengeTxtPresent: false,
    });
    expect(r.ok).toBe(false);
    expect(r.failed).toContain("challengeTxtPresent");
  });
  it("ACME carve-out regressed (301) → fails", () => {
    const r = checkReissuePreconditions({
      ...healthyPreconditions(),
      acmeApexStatus: 301,
    });
    expect(r.ok).toBe(false);
    expect(r.failed).toContain("acmeApexCarveout");
  });
});

describe("setRecordsProxied — partial-toggle abort", () => {
  it("throws PartialToggleError on the failing record with count", async () => {
    const { deps } = makeFake({ failToggleOffIds: ["a3"] });
    const records = defaultRecords(true);
    await expect(setRecordsProxied(deps, records, false)).rejects.toBeInstanceOf(
      PartialToggleError,
    );
  });
  it("toggles all 5 when none fail", async () => {
    const { deps, calls } = makeFake();
    await setRecordsProxied(deps, defaultRecords(true), false);
    expect(calls.setRecordProxied).toHaveLength(5);
    expect(calls.setRecordProxied.every((c) => c.proxied === false)).toBe(true);
  });
});

// =============================================================================
// runReissue — Test Scenarios 1, 3, 4, 5, 6
// =============================================================================

describe("runReissue — Scenario 1 (happy path)", () => {
  it("bad_authz + healthy → toggle → reissue → issued → restore", async () => {
    const { deps, state, calls } = makeFake({ willIssue: true, initialProxied: true });
    const result = await runReissue(deps);

    expect(result.outcome).toBe("issued");
    expect(result.finalState).toBe("issued");
    // All 5 records end proxied=true (restored).
    expect(state.records.every((r) => r.proxied === true)).toBe(true);
    expect(state.cname).toBe("soleur.ai");
    // Symmetric cname toggle happened (null then re-set).
    expect(calls.setPagesCname).toContain(null);
    expect(calls.setPagesCname).toContain("soleur.ai");
  });
});

describe("runReissue — Scenario 3 (poll timeout)", () => {
  it("never issues → poll_timeout + restore still runs", async () => {
    const { deps, state } = makeFake({ willIssue: false, initialProxied: true });
    const result = await runReissue(deps);

    expect(result.outcome).toBe("poll_timeout");
    expect(result.attempts).toBeGreaterThan(1);
    // Restore reasserts steady state even on the failed path.
    expect(state.records.every((r) => r.proxied === true)).toBe(true);
    expect(state.cname).toBe("soleur.ai");
  });
});

describe("runReissue — Scenario 4 (stuck-state allowlist — zero writes)", () => {
  it.each(["issued", "approved", "authorization_pending", "dns_changed"])(
    "state=%s → not_stuck, ZERO CF/GitHub writes",
    async (stateOverride) => {
      const { deps, calls } = makeFake({ stateOverride });
      const result = await runReissue(deps);

      expect(result.outcome).toBe("not_stuck");
      expect(calls.setRecordProxied).toHaveLength(0);
      expect(calls.setPagesCname).toHaveLength(0);
    },
  );
});

describe("runReissue — Scenario 5 (precondition blocked)", () => {
  it("CAA present → precondition_blocked, no writes", async () => {
    const { deps, calls } = makeFake({
      preconditions: { ...healthyPreconditions(), caaCount: 1 },
    });
    const result = await runReissue(deps);

    expect(result.outcome).toBe("precondition_blocked");
    expect(result.preconditionResults?.caaPermissive).toBe(false);
    expect(calls.setRecordProxied).toHaveLength(0);
    expect(calls.setPagesCname).toHaveLength(0);
  });
});

describe("runReissue — Scenario 6 (reissue_failed → abort→restore)", () => {
  it("partial apex toggle → reissue_failed + restore reasserts proxied=true", async () => {
    const { deps, state, calls } = makeFake({ failToggleOffIds: ["a3"] });
    const result = await runReissue(deps);

    expect(result.outcome).toBe("reissue_failed");
    expect(result.detail).toContain("partial-toggle");
    // Restore ran: every record back to proxied=true.
    expect(state.records.every((r) => r.proxied === true)).toBe(true);
    // The reissue cname toggle never fired (aborted before it).
    expect(calls.setPagesCname).not.toContain(null);
  });

  it("cname:null PUT 403 → reissue_failed (cname-put) + restore", async () => {
    const { deps, state } = makeFake({ failCnameOn: "null" });
    const result = await runReissue(deps);

    expect(result.outcome).toBe("reissue_failed");
    expect(result.detail).toContain("cname-put");
    expect(state.records.every((r) => r.proxied === true)).toBe(true);
  });
});

// =============================================================================
// restoreState — symmetric, idempotent, throws on non-convergence (Scenario 7)
// =============================================================================

describe("restoreState — symmetric {cname, proxied} restore (AC3)", () => {
  it("restores proxied=true on all 5 records AND cname from a mid-window state", async () => {
    const { deps, state, calls } = makeFake({
      initialProxied: false,
      initialCname: null,
    });
    await restoreState(deps);

    expect(state.records.every((r) => r.proxied === true)).toBe(true);
    expect(state.cname).toBe("soleur.ai");
    // All 5 records were re-asserted (not just proxied — cname too).
    expect(
      calls.setRecordProxied.filter((c) => c.proxied === true).length,
    ).toBe(5);
    expect(calls.setPagesCname).toContain("soleur.ai");
  });

  it("idempotent — a second restore issues no further writes when already steady", async () => {
    const { deps, calls } = makeFake({ initialProxied: true, initialCname: "soleur.ai" });
    await restoreState(deps);
    expect(calls.setRecordProxied).toHaveLength(0);
    expect(calls.setPagesCname).toHaveLength(0);
  });

  it("throws when the proxied restore cannot converge (proxy_restore_failed brake)", async () => {
    const { deps } = makeFake({
      initialProxied: false,
      initialCname: null,
      failToggleOnIds: ["a2"],
    });
    await expect(restoreState(deps)).rejects.toThrow(/restore/i);
  });
});

// =============================================================================
// onFailure lifecycle handler — proves restore runs via onFailure (Scenario 2)
// =============================================================================

describe("cronGhPagesCertReissueOnFailure — restores via onFailure, not finally", () => {
  const OLD_ENV = { ...process.env };
  // Stateful CF + Octokit mocks so restoreState's re-list assert converges.
  let recordProxied: Record<string, boolean>;
  let pagesCname: string | null;
  let cfPatchCalls: Array<{ id: string; proxied: boolean }>;
  let pagesPutCalls: Array<string>;

  beforeEach(() => {
    process.env.CF_API_TOKEN_DNS_EDIT = "fake-cf-token";
    process.env.CF_ZONE_ID = "zone123";
    // Mid-window degraded state the onFailure restore must repair.
    recordProxied = { a1: false, a2: false, a3: false, a4: false, w1: false };
    pagesCname = null;
    cfPatchCalls = [];
    pagesPutCalls = [];

    const jsonRes = (status: number, body: unknown) => ({
      ok: status >= 200 && status < 300,
      status,
      json: async () => body,
    });
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string, init?: RequestInit) => {
        const u = String(url);
        if (u.includes("/dns_records?")) {
          const isApex = u.includes("type=A");
          const result = isApex
            ? APEX_A_IDS.map((id) => ({
                id,
                name: "soleur.ai",
                type: "A",
                proxied: recordProxied[id],
              }))
            : [
                {
                  id: WWW_ID,
                  name: "www.soleur.ai",
                  type: "CNAME",
                  proxied: recordProxied[WWW_ID],
                },
              ];
          return jsonRes(200, { success: true, result });
        }
        if (u.includes("/dns_records/")) {
          const id = u.split("/dns_records/")[1];
          const proxied = JSON.parse(String(init?.body ?? "{}")).proxied;
          recordProxied[id] = proxied;
          cfPatchCalls.push({ id, proxied });
          return jsonRes(200, { success: true, result: {} });
        }
        return jsonRes(500, { success: false });
      }),
    );
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.doUnmock("@octokit/core");
    process.env = { ...OLD_ENV };
  });

  it("re-asserts proxied=true on all 5 records + cname on a simulated throw", async () => {
    vi.doMock("@octokit/core", () => ({
      Octokit: class {
        async request(route: string, params: Record<string, unknown>) {
          if (route === "GET /repos/{owner}/{repo}/pages") {
            return {
              data: {
                cname: pagesCname,
                https_certificate: { state: "bad_authz" },
              },
            };
          }
          if (route === "PUT /repos/{owner}/{repo}/pages") {
            pagesCname = (params.cname as string) || null;
            pagesPutCalls.push(String(params.cname ?? ""));
            return { data: {} };
          }
          throw new Error(`unexpected route ${route}`);
        }
      },
    }));

    // A minimal fake step that just runs each callback (no memoization needed).
    const step = {
      run: async <T>(_name: string, cb: () => Promise<T>) => cb(),
    };

    await cronGhPagesCertReissueOnFailure({
      error: new Error("simulated body failure after DNS-only toggle"),
      event: {},
      step,
      logger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    });

    // Every record restored to proxied=true (symmetric, all 5).
    expect(Object.values(recordProxied).every((p) => p === true)).toBe(true);
    expect(cfPatchCalls.filter((c) => c.proxied === true)).toHaveLength(5);
    // cname re-asserted to the declared value.
    expect(pagesCname).toBe("soleur.ai");
    expect(pagesPutCalls).toContain("soleur.ai");
  });
});

// =============================================================================
// Registration + source-shape anchors
// =============================================================================

describe("cronGhPagesCertReissue — registration smoke", () => {
  it("loads without throwing", () => {
    expect(cronGhPagesCertReissue).toBeDefined();
    expect(typeof cronGhPagesCertReissue).toBe("object");
  });
});

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-gh-pages-cert-reissue.ts",
  ),
  "utf-8",
);

describe("source-shape anchors (registration + replay-safety)", () => {
  it.each([
    ['id: FN_ID', "canonical function id via FN_ID const"],
    ['const FN_ID = "cron-gh-pages-cert-reissue"', "canonical id literal"],
    ['event: "cron/gh-pages-cert-reissue.manual-trigger"', "manual-trigger event"],
    ["retries: 1", "single reissue attempt per invocation (AC5)"],
    ['scope: "fn"', "fn-scoped serialization"],
    ['key: \'"cron-platform"\'', "account concurrency lane"],
    ["onFailure: cronGhPagesCertReissueOnFailure", "onFailure lifecycle restore (AC3)"],
    ['administration: "write"', "least-privilege scoped mint (AC4)"],
    ['repositories: [REPO_NAME]', "repo-scoped token (AC4)"],
    ["await step.sleep(", "poll suspends via step.sleep (ADR-077)"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });

  it("declares NO cron: schedule (event-triggered only, AC1)", () => {
    expect(SUT_SOURCE).not.toMatch(/\{\s*cron:\s*"/);
  });

  it("handler body has no try…finally spanning the poll (ADR-077)", () => {
    // Scope to the handler (the cfFetch helper legitimately uses finally for
    // clearTimeout, which is synchronous and does NOT span a step boundary).
    const start = SUT_SOURCE.indexOf(
      "export async function cronGhPagesCertReissueHandler",
    );
    const end = SUT_SOURCE.indexOf(
      "export async function cronGhPagesCertReissueOnFailure",
    );
    expect(start).toBeGreaterThan(-1);
    expect(end).toBeGreaterThan(start);
    const handlerBody = SUT_SOURCE.slice(start, end);
    expect(handlerBody).not.toContain("finally");
    // Positive: the poll loop uses step.sleep and restore is its own step.
    expect(handlerBody).toContain("await step.sleep(");
    expect(handlerBody).toContain('step.run("restore-steady-state"');
  });
});
