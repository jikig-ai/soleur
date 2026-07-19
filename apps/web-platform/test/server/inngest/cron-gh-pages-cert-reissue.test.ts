// #6657 — cron-gh-pages-cert-reissue unit tests.
//
// Coverage:
//   - Pure helpers (assertStuckState, checkReissuePreconditions, setRecordsProxied).
//   - The PRODUCTION orchestration `runReissueSteps` driven with a fake step +
//     fake deps (no parallel/dead twin): happy, approved, poll timeout, stuck-state
//     allowlist abort, precondition-blocked, reissue_failed (partial-toggle +
//     cname-PUT), restore-on-timeout, settle-sleep window.
//   - restoreState fail-loud: symmetric restore, idempotent, short-read throw,
//     early per-record throw, AND the final re-read convergence brake
//     (write-returns-true-but-doesn't-stick).
//   - The handler config_missing benign path.
//   - onFailure: restore runs via the lifecycle handler (not JS finally); pages on
//     BOTH restore-ok (reissue_incomplete_restore_ok) and restore-fail
//     (proxy_restore_failed, incl. a Cloudflare read failure).
//   - Source/registration anchors, incl. a quote-agnostic no-cron check and an
//     allowlist-event parity assert.

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

// Spy on reportSilentFallback so the onFailure paging assertions can inspect tags.
vi.mock("@/server/observability", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("@/server/observability")>();
  return { ...actual, reportSilentFallback: vi.fn() };
});

import { reportSilentFallback } from "@/server/observability";
import { manualTriggerEventFor } from "@/server/inngest/cron-manifest";
import {
  runReissueSteps,
  cronGhPagesCertReissueHandler,
  restoreState,
  assertStuckState,
  checkReissuePreconditions,
  setRecordsProxied,
  PartialToggleError,
  cronGhPagesCertReissue,
  cronGhPagesCertReissueOnFailure,
  EXPECTED_TOGGLE_RECORDS,
  // #6698
  checkDnsPropagated,
  resolveProbeOnly,
  BENIGN_OUTCOMES,
  REISSUE_ALLOWED_STATES,
  MAX_DNS_ONLY_WINDOW_MS,
  TOTAL_DNS_ONLY_WINDOW_MS,
  DNS_GATE_MAX_ATTEMPTS,
  type ReissueDeps,
  type ReissueStep,
  type CfDnsRecord,
  type PreconditionInputs,
  type DnsPropagationInputs,
  type ReissueRunContext,
} from "@/server/inngest/functions/cron-gh-pages-cert-reissue";

const reportSilentFallbackMock = vi.mocked(reportSilentFallback);

// =============================================================================
// Fakes
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

/** A fake step that just runs each callback and records the step names. */
function makeStep(): ReissueStep & { calls: string[] } {
  const calls: string[] = [];
  return {
    async run<T>(name: string, cb: () => Promise<T>) {
      calls.push(name);
      return cb();
    },
    async sleep(name: string) {
      calls.push(`sleep:${name}`);
    },
    calls,
  };
}

interface FakeConfig {
  stateOverride?: string;
  issuedState?: "issued" | "approved"; // the healthy state the poll observes
  willIssue?: boolean;
  initialProxied?: boolean;
  initialCname?: string | null;
  preconditions?: PreconditionInputs;
  failToggleOffIds?: string[];
  failToggleOnIds?: string[];
  failCnameOn?: "null" | "set";
  writeDoesNotStick?: boolean; // setRecordProxied returns true but does not mutate
  listCount?: number; // force listToggleRecords to return this many records
  dnsPropagation?: Partial<DnsPropagationInputs>; // #6698 gate observations
}

/**
 * A fully-propagated DNS-only reading: GitHub anycast on A, no AAAA, ACME path
 * GitHub-shaped. This is the DEFAULT for the fake so the pre-existing
 * remediation scenarios still reach the poll loop — the gate is additive, not a
 * behavior change for an already-healthy zone.
 */
function propagatedDns(): DnsPropagationInputs {
  return {
    resolved4: [
      "185.199.108.153",
      "185.199.109.153",
      "185.199.110.153",
      "185.199.111.153",
    ],
    resolved6: [],
    resolve6Error: "ENODATA",
    acmeApexStatus: 404,
    acmeWwwStatus: 404,
    acmeGithubShaped: true,
  };
}

/**
 * Run context for the pre-existing scenarios: REMEDIATION mode (probeOnly
 * false), with a known runId/attempt so AC5 can assert the values propagate
 * rather than merely typecheck.
 */
function remediationCtx(): ReissueRunContext {
  return { probeOnly: false, runId: "run-test", attempt: 0 };
}

function makeFake(cfg: FakeConfig = {}) {
  const state = {
    cname: cfg.initialCname === undefined ? "soleur.ai" : cfg.initialCname,
    records: defaultRecords(cfg.initialProxied ?? true),
    reissued: false,
    sawNull: false,
  };
  const calls = {
    setRecordProxied: [] as Array<{ id: string; proxied: boolean }>,
    setPagesCname: [] as Array<string | null>,
    sleep: [] as number[],
    getPages: 0,
    gatherDnsPropagation: 0,
  };
  const resolveState = () => {
    if (cfg.stateOverride) return cfg.stateOverride;
    if (state.reissued && cfg.willIssue) return cfg.issuedState ?? "issued";
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
      const all = state.records.map((r) => ({ ...r }));
      if (cfg.listCount !== undefined) return all.slice(0, cfg.listCount);
      return all;
    },
    async setRecordProxied(id, proxied) {
      calls.setRecordProxied.push({ id, proxied });
      if (proxied === false && cfg.failToggleOffIds?.includes(id)) return false;
      if (proxied === true && cfg.failToggleOnIds?.includes(id)) return false;
      if (!cfg.writeDoesNotStick) {
        const rec = state.records.find((r) => r.id === id);
        if (rec) rec.proxied = proxied;
      }
      return true; // returns success even when writeDoesNotStick (the brake case)
    },
    async gatherPreconditions() {
      return cfg.preconditions ?? healthyPreconditions();
    },
    async gatherDnsPropagation() {
      calls.gatherDnsPropagation += 1;
      return { ...propagatedDns(), ...(cfg.dnsPropagation ?? {}) };
    },
    sleep: async (ms) => {
      calls.sleep.push(ms);
    },
    logger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  };
  return { deps, state, calls };
}

beforeEach(() => {
  reportSilentFallbackMock.mockClear();
});

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
  it("always_use_https unreadable ('unknown', DNS-only token 403) → does NOT block (#6657)", () => {
    // The least-privilege DNS-edit-only token cannot read the zone setting, so
    // gatherPreconditions returns "unknown"; the ACME carve-out check is the
    // authoritative signal, so an unreadable setting must not block.
    const r = checkReissuePreconditions({ ...healthyPreconditions(), alwaysUseHttps: "unknown" });
    expect(r.ok).toBe(true);
    expect(r.results.alwaysUseHttpsOff).toBe(true);
  });
  it("always_use_https explicitly 'on' → blocks alwaysUseHttpsOff", () => {
    const r = checkReissuePreconditions({ ...healthyPreconditions(), alwaysUseHttps: "on" });
    expect(r.ok).toBe(false);
    expect(r.failed).toContain("alwaysUseHttpsOff");
  });
});

describe("setRecordsProxied — partial-toggle abort", () => {
  it("throws PartialToggleError on the failing record", async () => {
    const { deps } = makeFake({ failToggleOffIds: ["a3"] });
    await expect(
      setRecordsProxied(deps, defaultRecords(true), false),
    ).rejects.toBeInstanceOf(PartialToggleError);
  });
  it("toggles all 5 when none fail", async () => {
    const { deps, calls } = makeFake();
    await setRecordsProxied(deps, defaultRecords(true), false);
    expect(calls.setRecordProxied).toHaveLength(5);
    expect(calls.setRecordProxied.every((c) => c.proxied === false)).toBe(true);
  });
});

// =============================================================================
// runReissueSteps — the PRODUCTION orchestration (fake step + fake deps)
// =============================================================================

describe("runReissueSteps — Scenario 1 (happy path, issued)", () => {
  it("bad_authz + healthy → toggle → reissue → issued → restore", async () => {
    const { deps, state, calls } = makeFake({ willIssue: true });
    const result = await runReissueSteps(makeStep(), deps, deps.logger, remediationCtx());

    expect(result.outcome).toBe("issued");
    expect(result.finalState).toBe("issued");
    expect(state.records.every((r) => r.proxied === true)).toBe(true);
    expect(state.cname).toBe("soleur.ai");
    expect(calls.setPagesCname).toContain(null);
    expect(calls.setPagesCname).toContain("soleur.ai");
    // Settle window fired between the two cname PUTs (SURV-A guard).
    expect(calls.sleep).toContain(45 * 1000);
  });
});

describe("runReissueSteps — Scenario 1b (approved is also healthy)", () => {
  it("poll observing state=approved → outcome issued (SURV-B guard)", async () => {
    const { deps } = makeFake({ willIssue: true, issuedState: "approved" });
    const result = await runReissueSteps(makeStep(), deps, deps.logger, remediationCtx());
    expect(result.outcome).toBe("issued");
    expect(result.finalState).toBe("approved");
  });
});

describe("runReissueSteps — Scenario 3 (poll timeout)", () => {
  it("never issues → poll_timeout + restore still runs", async () => {
    const { deps, state } = makeFake({ willIssue: false });
    const result = await runReissueSteps(makeStep(), deps, deps.logger, remediationCtx());

    expect(result.outcome).toBe("poll_timeout");
    expect(result.attempts).toBeGreaterThan(1);
    expect(state.records.every((r) => r.proxied === true)).toBe(true);
    expect(state.cname).toBe("soleur.ai");
  });
});

describe("runReissueSteps — Scenario 4 (stuck-state allowlist — zero writes)", () => {
  it.each(["issued", "approved", "authorization_pending", "dns_changed"])(
    "state=%s → not_stuck, ZERO CF/GitHub writes",
    async (stateOverride) => {
      const { deps, calls } = makeFake({ stateOverride });
      const result = await runReissueSteps(makeStep(), deps, deps.logger, remediationCtx());

      expect(result.outcome).toBe("not_stuck");
      expect(calls.setRecordProxied).toHaveLength(0);
      expect(calls.setPagesCname).toHaveLength(0);
    },
  );
});

describe("runReissueSteps — Scenario 5 (precondition blocked)", () => {
  it("CAA present → precondition_blocked, no writes", async () => {
    const { deps, calls } = makeFake({
      preconditions: { ...healthyPreconditions(), caaCount: 1 },
    });
    const result = await runReissueSteps(makeStep(), deps, deps.logger, remediationCtx());

    expect(result.outcome).toBe("precondition_blocked");
    expect(result.preconditionResults?.caaPermissive).toBe(false);
    expect(calls.setRecordProxied).toHaveLength(0);
    expect(calls.setPagesCname).toHaveLength(0);
  });
});

describe("runReissueSteps — Scenario 6 (reissue_failed → abort→restore)", () => {
  it("partial apex toggle → reissue_failed + restore reasserts proxied=true", async () => {
    const { deps, state, calls } = makeFake({ failToggleOffIds: ["a3"] });
    const result = await runReissueSteps(makeStep(), deps, deps.logger, remediationCtx());

    expect(result.outcome).toBe("reissue_failed");
    expect(result.detail).toContain("partial-toggle");
    expect(state.records.every((r) => r.proxied === true)).toBe(true);
    expect(calls.setPagesCname).not.toContain(null); // aborted before the cname dance
  });

  it("cname:null PUT 403 → reissue_failed (cname-put) + restore", async () => {
    const { deps, state } = makeFake({ failCnameOn: "null" });
    const result = await runReissueSteps(makeStep(), deps, deps.logger, remediationCtx());

    expect(result.outcome).toBe("reissue_failed");
    expect(result.detail).toContain("cname-put");
    expect(state.records.every((r) => r.proxied === true)).toBe(true);
  });
});

// =============================================================================
// restoreState — fail-loud (Sec P1 + Test-design P2)
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
    expect(
      calls.setRecordProxied.filter((c) => c.proxied === true).length,
    ).toBe(5);
    expect(calls.setPagesCname).toContain("soleur.ai");
  });

  it("idempotent — a second restore issues no writes when already steady", async () => {
    const { deps, calls } = makeFake({ initialProxied: true, initialCname: "soleur.ai" });
    await restoreState(deps);
    expect(calls.setRecordProxied).toHaveLength(0);
    expect(calls.setPagesCname).toHaveLength(0);
  });

  it("throws when a proxied restore PATCH reports failure (per-record brake)", async () => {
    const { deps } = makeFake({
      initialProxied: false,
      initialCname: null,
      failToggleOnIds: ["a2"],
    });
    await expect(restoreState(deps)).rejects.toThrow(/restore/i);
  });

  it("throws when a PATCH returns success but the write does NOT stick (convergence brake)", async () => {
    // setRecordProxied returns true, but the record stays proxied=false → the
    // final re-read assert must catch the still-exposed origin.
    const { deps } = makeFake({
      initialProxied: false,
      initialCname: "soleur.ai",
      writeDoesNotStick: true,
    });
    await expect(restoreState(deps)).rejects.toThrow(/restore-assert failed/);
  });

  it("throws on a short record read (Cloudflare read failure → subset)", async () => {
    const { deps } = makeFake({ initialProxied: false, listCount: 3 });
    await expect(restoreState(deps)).rejects.toThrow(
      new RegExp(`only 3/${EXPECTED_TOGGLE_RECORDS}`),
    );
  });
});

// =============================================================================
// Handler config_missing benign path
// =============================================================================

describe("cronGhPagesCertReissueHandler — config_missing (token not provisioned)", () => {
  const OLD = { ...process.env };
  afterEach(() => {
    process.env = { ...OLD };
  });
  it("returns config_missing (benign) and does NOT page when CF token unset", async () => {
    delete process.env.CF_API_TOKEN_DNS_EDIT;
    delete process.env.CF_ZONE_ID;
    const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };
    const result = await cronGhPagesCertReissueHandler({
      step: makeStep(),
      logger,
    });
    expect(result.outcome).toBe("config_missing");
    // Warned, not paged.
    expect(logger.warn).toHaveBeenCalled();
    expect(reportSilentFallbackMock).not.toHaveBeenCalled();
  });
});

// =============================================================================
// onFailure lifecycle handler — restore via onFailure, and it ALWAYS pages
// =============================================================================

describe("cronGhPagesCertReissueOnFailure — stateful CF + Octokit mocks", () => {
  const OLD_ENV = { ...process.env };
  let recordProxied: Record<string, boolean>;
  let pagesCname: string | null;
  let cfListStatus: number; // let a test force a CF read failure
  let cfPatchCalls: Array<{ id: string; proxied: boolean }>;
  let pagesPutCalls: Array<string>;

  beforeEach(() => {
    process.env.CF_API_TOKEN_DNS_EDIT = "fake-cf-token";
    process.env.CF_ZONE_ID = "zone123";
    recordProxied = { a1: false, a2: false, a3: false, a4: false, w1: false };
    pagesCname = null;
    cfListStatus = 200;
    cfPatchCalls = [];
    pagesPutCalls = [];

    const jsonRes = (status: number, body: unknown, ok = status < 300) => ({
      ok,
      status,
      json: async () => body,
    });
    vi.stubGlobal(
      "fetch",
      vi.fn(async (url: string, init?: RequestInit) => {
        const u = String(url);
        if (u.includes("/dns_records?")) {
          if (cfListStatus >= 400) return jsonRes(cfListStatus, { success: false });
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

  function mockOctokit() {
    vi.doMock("@octokit/core", () => ({
      Octokit: class {
        async request(route: string, params: Record<string, unknown>) {
          if (route === "GET /repos/{owner}/{repo}/pages") {
            return {
              data: { cname: pagesCname, https_certificate: { state: "bad_authz" } },
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
  }

  it("restore succeeds → re-asserts proxied=true + cname AND pages reissue_incomplete_restore_ok", async () => {
    mockOctokit();
    await cronGhPagesCertReissueOnFailure({
      error: new Error("simulated body failure after DNS-only toggle"),
      event: {},
      step: makeStep(),
      logger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    });

    expect(Object.values(recordProxied).every((p) => p === true)).toBe(true);
    expect(cfPatchCalls.filter((c) => c.proxied === true)).toHaveLength(5);
    expect(pagesCname).toBe("soleur.ai");
    expect(pagesPutCalls).toContain("soleur.ai");
    // A retries-exhausted throw pages even when restore succeeds (Obs P1).
    expect(reportSilentFallbackMock).toHaveBeenCalled();
    const tags = reportSilentFallbackMock.mock.calls.map((c) => c[1]?.tags?.outcome);
    expect(tags).toContain("reissue_incomplete_restore_ok");
  });

  it("Cloudflare read failure during restore → pages proxy_restore_failed (fail-loud, not silent)", async () => {
    mockOctokit();
    cfListStatus = 503; // the GET dns_records fails → listToggleRecords throws
    await cronGhPagesCertReissueOnFailure({
      error: new Error("body failure"),
      event: {},
      step: makeStep(),
      logger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    });
    const tags = reportSilentFallbackMock.mock.calls.map((c) => c[1]?.tags?.outcome);
    expect(tags).toContain("proxy_restore_failed");
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
  it("manual-trigger event matches the allowlist derivation (parity)", () => {
    // The registration literal must equal what the manifest derives, or the
    // trigger-cron allowlist would never match the registered event.
    expect(manualTriggerEventFor("cron-gh-pages-cert-reissue")).toBe(
      "cron/gh-pages-cert-reissue.manual-trigger",
    );
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
    ['pages: "write"', "scoped mint: pages (AC4) — PUT /pages needs BOTH admin+pages"],
    ['administration: "write"', "scoped mint: administration (AC4) — PUT /pages needs BOTH admin+pages"],
    ["repositories: [REPO_NAME]", "repo-scoped token (AC4)"],
    ["await step.sleep(", "poll suspends via step.sleep (ADR-077)"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });

  it("registration declares NO cron: schedule — quote-agnostic (AC1)", () => {
    // Slice the createFunction call and assert no `cron:` trigger KEY appears
    // (regardless of the value's quote style — the old /\{\s*cron:\s*"/ regex
    // only caught double-quoted schedules and false-failed on comments).
    const start = SUT_SOURCE.indexOf("inngest.createFunction(");
    const reg = SUT_SOURCE.slice(start);
    expect(start).toBeGreaterThan(-1);
    expect(reg).not.toMatch(/\bcron\s*:/); // no cron trigger key
    expect(reg).toContain('event: "cron/gh-pages-cert-reissue.manual-trigger"');
  });

  it("orchestration has no try…finally spanning a step boundary (ADR-077)", () => {
    // cfFetch legitimately uses finally for clearTimeout (synchronous, no step
    // boundary) — scope to runReissueSteps, the replay-safety-critical function.
    const start = SUT_SOURCE.indexOf("export async function runReissueSteps");
    const end = SUT_SOURCE.indexOf("async function cfFetch");
    expect(start).toBeGreaterThan(-1);
    expect(end).toBeGreaterThan(start);
    const body = SUT_SOURCE.slice(start, end);
    expect(body).not.toContain("finally");
    expect(body).toContain("await step.sleep(");
    expect(body).toContain('step.run("restore-steady-state"');
  });
});
