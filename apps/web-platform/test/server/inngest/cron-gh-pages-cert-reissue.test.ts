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

// Capture every emitted marker (#6698). PARTIAL mock so CERT_REISSUE_PHASES and
// the types survive — the SUT imports `emitCertReissueMarker` from this module,
// so overriding the export does intercept its calls. Also keeps the real pino
// marker stream out of the test runner's stdout.
const { markerSpy } = vi.hoisted(() => ({ markerSpy: vi.fn() }));
vi.mock("@/server/cert-reissue-marker", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("@/server/cert-reissue-marker")>();
  return { ...actual, emitCertReissueMarker: markerSpy };
});

import { reportSilentFallback } from "@/server/observability";
import { CERT_REISSUE_PHASES } from "@/server/cert-reissue-marker";
import type { CertReissueMarker } from "@/server/cert-reissue-marker";
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
  buildLiveDeps,
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
    resolve4Error: null,
    acmeApexStatus: 404,
    acmeWwwStatus: 404,
    acmeApexServer: "GitHub.com",
    acmeWwwServer: "GitHub.com",
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
  markerSpy.mockClear();
});

/** Every marker emitted so far, in order. */
function emittedMarkers(): CertReissueMarker[] {
  return markerSpy.mock.calls.map((c) => c[0] as CertReissueMarker);
}
function emittedPhases(): string[] {
  return emittedMarkers().map((m) => m.phase);
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
    await restoreState(deps, () => {});

    expect(state.records.every((r) => r.proxied === true)).toBe(true);
    expect(state.cname).toBe("soleur.ai");
    expect(
      calls.setRecordProxied.filter((c) => c.proxied === true).length,
    ).toBe(5);
    expect(calls.setPagesCname).toContain("soleur.ai");
  });

  it("idempotent — a second restore issues no writes when already steady", async () => {
    const { deps, calls } = makeFake({ initialProxied: true, initialCname: "soleur.ai" });
    await restoreState(deps, () => {});
    expect(calls.setRecordProxied).toHaveLength(0);
    expect(calls.setPagesCname).toHaveLength(0);
  });

  it("throws when a proxied restore PATCH reports failure (per-record brake)", async () => {
    const { deps } = makeFake({
      initialProxied: false,
      initialCname: null,
      failToggleOnIds: ["a2"],
    });
    await expect(restoreState(deps, () => {})).rejects.toThrow(/restore/i);
  });

  it("throws when a PATCH returns success but the write does NOT stick (convergence brake)", async () => {
    // setRecordProxied returns true, but the record stays proxied=false → the
    // final re-read assert must catch the still-exposed origin.
    const { deps } = makeFake({
      initialProxied: false,
      initialCname: "soleur.ai",
      writeDoesNotStick: true,
    });
    await expect(restoreState(deps, () => {})).rejects.toThrow(/restore-assert failed/);
  });

  it("throws on a short record read (Cloudflare read failure → subset)", async () => {
    const { deps } = makeFake({ initialProxied: false, listCount: 3 });
    await expect(restoreState(deps, () => {})).rejects.toThrow(
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

// =============================================================================
// #6698 — telemetry, probe-only mode, and the DNS-propagation gate
// =============================================================================

function probeCtx(): ReissueRunContext {
  return { probeOnly: true, runId: "run-probe", attempt: 1 };
}

describe("#6698 checkDnsPropagated — pure verdict function (AC8)", () => {
  const base: DnsPropagationInputs = {
    resolved4: ["185.199.108.153", "185.199.111.153"],
    resolved6: [],
    resolve6Error: "ENODATA",
    resolve4Error: null,
    acmeApexStatus: 404,
    acmeWwwStatus: 404,
    acmeApexServer: "GitHub.com",
    acmeWwwServer: "GitHub.com",
  };

  it("all-185.199.x + no AAAA + GitHub-shaped ACME → propagated", () => {
    expect(checkDnsPropagated(base).status).toBe("propagated");
  });

  it("Cloudflare answers → retry (propagation may still be in flight)", () => {
    const v = checkDnsPropagated({
      ...base,
      resolved4: ["188.114.96.2", "188.114.97.2"],
    });
    expect(v.status).toBe("retry");
    expect(v.reason).toMatch(/188\.114\.96\.2/);
  });

  it("AAAA present WITH stale Cloudflare A-records → retry, not terminal", () => {
    // Measured in production (runId 01KXXR3BBF, 2026-07-19): the public
    // resolvers flap between the new GitHub answer and the still-cached
    // Cloudflare one for the whole propagation window, and a tick landing on
    // the stale answer returns Cloudflare's A-records AND its synthetic AAAA
    // together. The zone provably has zero AAAA records, so treating that as a
    // surviving AAAA aborts a healthy remediation on a transient read.
    const v = checkDnsPropagated({
      ...base,
      resolved4: ["188.114.96.1", "188.114.97.1"],
      resolved6: ["2a06:98c1:3121::1", "2a06:98c1:3120::1"],
      resolve6Error: null,
    });
    expect(v.status).toBe("retry");
    expect(v.reason).toMatch(/pre-flip cached answer/);
  });

  it("AAAA present with NO A-record answer → retry (cannot confirm post-flip state)", () => {
    const v = checkDnsPropagated({
      ...base,
      resolved4: [],
      resolved6: ["2a06:98c1:3121::1"],
      resolve6Error: null,
    });
    expect(v.status).toBe("retry");
  });

  it("AAAA present → failed, NOT retry (H-W4 is terminal, waiting cannot help)", () => {
    // Let's Encrypt prefers IPv6 and will not fall back from a proxied AAAA that
    // answers 200 with the wrong content, so no window length can succeed. A
    // `retry` here would burn the remaining budget lengthening a public TLS
    // outage for an outcome that cannot change.
    // A-records CONVERGED to GitHub anycast (base fixture) AND an AAAA still
    // answers — that is the real H-W4 condition, and it stays terminal.
    const v = checkDnsPropagated({
      ...base,
      resolved6: ["2a06:98c1:3120::2"],
      resolve6Error: null,
    });
    expect(v.status).toBe("failed");
    expect(v.reason).toMatch(/prefers IPv6/);
    expect(v.reason).toMatch(/converged to GitHub anycast/);
  });

  it("A-records right but ACME not GitHub-shaped → retry (challenge intercepted)", () => {
    const v = checkDnsPropagated({ ...base, acmeApexServer: "cloudflare" });
    expect(v.status).toBe("retry");
    expect(v.reason).toMatch(/not GitHub-shaped/);
  });

  it("inconclusive AAAA lookup (resolver timeout) → retry, NOT propagated", () => {
    // Fails OPEN if the gate treats every resolve6 error as "no AAAA":
    // gatherDnsPropagation coalesces ETIMEOUT/ESERVFAIL/ECONNREFUSED to an
    // empty array exactly like a genuine ENODATA. A live proxied AAAA whose
    // lookup timed out (while the A lookup answered from a warm cache) would
    // then read as propagated, burn a Let's Encrypt validation attempt against
    // a zone that cannot validate, and surface as an indistinguishable
    // poll_timeout.
    for (const code of ["ETIMEOUT", "ESERVFAIL", "ECONNREFUSED", "unknown"]) {
      const v = checkDnsPropagated({
        ...base,
        resolved6: [],
        resolve6Error: code,
      });
      expect(v.status, code).toBe("retry");
      expect(v.reason, code).toMatch(/inconclusive/);
    }
  });

  it("ENODATA / ENOTFOUND are the genuine no-AAAA PASS conditions", () => {
    // Non-vacuity for the guard above: the two codes that really mean "this
    // name has no AAAA" must still reach propagated.
    for (const code of ["ENODATA", "ENOTFOUND"]) {
      expect(
        checkDnsPropagated({ ...base, resolved6: [], resolve6Error: code })
          .status,
        code,
      ).toBe("propagated");
    }
    expect(
      checkDnsPropagated({ ...base, resolved6: [], resolve6Error: null }).status,
    ).toBe("propagated");
  });

  it("no A answer yet → retry", () => {
    expect(checkDnsPropagated({ ...base, resolved4: [] }).status).toBe("retry");
  });

  it("a 185.199.x-PREFIXED but non-GitHub octet does not pass by string prefix", () => {
    // Guards the /16 check against a naive `startsWith("185.199.")`.
    const v = checkDnsPropagated({ ...base, resolved4: ["185.1990.1.1"] });
    expect(v.status).toBe("retry");
  });
});

describe("#6698 resolveProbeOnly — safe default (AC20/AC23)", () => {
  it.each([
    ["absent data", undefined, true],
    ["empty data", {}, true],
    ["non-object data", "nope", true],
    ["explicit true", { probeOnly: true }, true],
    ["explicit false", { probeOnly: false }, false],
    ["non-boolean flag", { probeOnly: "false" }, true],
  ])("%s → probeOnly=%s", (_label, data, expected) => {
    expect(resolveProbeOnly({ data })).toBe(expected);
  });

  it("defaults to probe-only for a bare event with no data at all", () => {
    // Remediation consumes an LE validation attempt against hourly, COMPOUNDING
    // limits, so the default must never remediate.
    expect(resolveProbeOnly({})).toBe(true);
    expect(resolveProbeOnly(undefined)).toBe(true);
  });
});

describe("#6698 probe-only mode", () => {
  it("makes ZERO reissueViaCnameToggle calls — no cname:null PUT (AC11)", async () => {
    const { deps, calls } = makeFake();
    const result = await runReissueSteps(
      makeStep(),
      deps,
      deps.logger,
      probeCtx(),
    );
    expect(result.outcome).toBe("probe_only_complete");
    // Assert on the ABSENCE OF THE `null` ARGUMENT, not on setPagesCname call
    // count: restoreState legitimately re-asserts the cname when it drifted, so
    // a call-count assertion would be false in a reachable state and would
    // pressure someone into making restore conditional on !probeOnly — a direct
    // regression of the symmetric-restore contract.
    expect(calls.setPagesCname).not.toContain(null);
    // And no settle sleep, which only reissueViaCnameToggle performs.
    expect(calls.sleep).not.toContain(45 * 1000);
  });

  it("runs ZERO poll steps (AC11c)", async () => {
    const { deps } = makeFake();
    const step = makeStep();
    await runReissueSteps(step, deps, deps.logger, probeCtx());
    expect(step.calls.filter((c) => c.startsWith("poll-"))).toHaveLength(0);
    expect(emittedPhases()).not.toContain("poll");
  });

  it("still flips DNS and still restores (it pays the window, so it must measure)", async () => {
    const { deps, state, calls } = makeFake();
    await runReissueSteps(makeStep(), deps, deps.logger, probeCtx());
    expect(calls.setRecordProxied.some((c) => c.proxied === false)).toBe(true);
    expect(state.records.every((r) => r.proxied === true)).toBe(true);
  });

  it("aborts loudly in preflight when the live cname is already wrong (AC11b)", async () => {
    // A probe against the `cname:null` state a prior failed fire left behind
    // would otherwise reach restoreState's cname re-assert, issue a real
    // PUT /pages, re-order the cert and consume an LE attempt — the one thing
    // probe-only exists to avoid.
    const { deps, calls } = makeFake({ initialCname: null });
    const result = await runReissueSteps(
      makeStep(),
      deps,
      deps.logger,
      probeCtx(),
    );
    expect(result.outcome).toBe("precondition_blocked");
    expect(result.detail).toMatch(/probe-only refused/);
    // Nothing was mutated at all.
    expect(calls.setPagesCname).toHaveLength(0);
    expect(calls.setRecordProxied).toHaveLength(0);
  });

  it("probe_only_complete is benign (does not page) and is not reachable in remediation", async () => {
    expect(BENIGN_OUTCOMES.has("probe_only_complete")).toBe(true);
    const { deps } = makeFake({ willIssue: true });
    const remediation = await runReissueSteps(
      makeStep(),
      deps,
      deps.logger,
      remediationCtx(),
    );
    expect(remediation.outcome).not.toBe("probe_only_complete");
    expect(remediation.probeOnly).toBe(false);
  });

  it("`issued` is unreachable in probe-only mode", async () => {
    const { deps } = makeFake({ willIssue: true });
    const result = await runReissueSteps(
      makeStep(),
      deps,
      deps.logger,
      probeCtx(),
    );
    expect(result.outcome).not.toBe("issued");
    expect(result.probeOnly).toBe(true);
  });
});

describe("#6698 DNS-propagation gate", () => {
  it("AAAA present → dns_propagation_failed, and restore STILL runs (AC9)", async () => {
    const { deps, state } = makeFake({
      dnsPropagation: { resolved6: ["2a06:98c1:3120::2"], resolve6Error: null },
    });
    const step = makeStep();
    const result = await runReissueSteps(
      step,
      deps,
      deps.logger,
      remediationCtx(),
    );
    expect(result.outcome).toBe("dns_propagation_failed");
    expect(step.calls).toContain("restore-steady-state");
    expect(state.records.every((r) => r.proxied === true)).toBe(true);
  });

  it("dns_propagation_failed is NOT benign — it pages (AC12)", () => {
    expect(BENIGN_OUTCOMES.has("dns_propagation_failed")).toBe(false);
  });

  it("a CONFIRMED AAAA skips the poll entirely (no wasted outage window)", async () => {
    const { deps } = makeFake({
      dnsPropagation: { resolved6: ["2a06:98c1:3120::2"], resolve6Error: null },
    });
    const step = makeStep();
    await runReissueSteps(step, deps, deps.logger, remediationCtx());
    expect(step.calls.filter((c) => c.startsWith("poll-"))).toHaveLength(0);
  });

  it("gate EXHAUSTION still polls — slow propagation is not a fault", async () => {
    // Cloudflare's proxied TTL is a fixed 300s, so "not yet propagated within
    // the gate budget" is an ordinary observation. Aborting on it would make
    // dns_propagation_failed the DEFAULT outcome of a correct remediation and
    // page on every fire.
    const { deps } = makeFake({
      willIssue: false,
      dnsPropagation: { resolved4: ["188.114.96.2"] }, // never converges
    });
    const step = makeStep();
    const result = await runReissueSteps(
      step,
      deps,
      deps.logger,
      remediationCtx(),
    );
    expect(result.outcome).toBe("poll_timeout");
    expect(step.calls.filter((c) => c.startsWith("poll-")).length).toBeGreaterThan(0);
    // ...but it must be recorded, so a poll_timeout is never later misread as
    // "DNS was known good".
    const unconfirmed = emittedMarkers().filter(
      (m) => m.phase === "dns-propagation" && m.outcome === "unconfirmed",
    );
    expect(unconfirmed).toHaveLength(1);
  });

  it("retries up to the fixed attempt cap with deterministic step names (AC10)", async () => {
    const { deps } = makeFake({
      dnsPropagation: { resolved4: ["188.114.96.2"] }, // never converges
    });
    const step = makeStep();
    await runReissueSteps(step, deps, deps.logger, remediationCtx());
    const gateSteps = step.calls.filter((c) => c.startsWith("dns-gate-"));
    // Fixed-count names over a constant — a wall-clock-derived counter would
    // produce non-deterministic ids and break inngest replay memoization.
    expect(gateSteps.length).toBeLessThanOrEqual(DNS_GATE_MAX_ATTEMPTS * 2);
    expect(step.calls).toContain("dns-gate-0");
    expect(gateSteps.every((c) => /^dns-gate-(wait-)?\d+$/.test(c))).toBe(true);
  });

  it("stops at the FIRST attempt on a terminal AAAA verdict (no wasted retries)", async () => {
    const { deps } = makeFake({
      dnsPropagation: { resolved6: ["2a06:98c1:3120::2"], resolve6Error: null },
    });
    const step = makeStep();
    await runReissueSteps(step, deps, deps.logger, remediationCtx());
    expect(
      step.calls.filter((c) => /^dns-gate-\d+$/.test(c)),
    ).toHaveLength(1);
  });
});

describe("#6698 step ordering and restore invariant", () => {
  it("orders capture-pre-flip-dns → toggle-reissue → dns-gate → poll → restore (AC10)", async () => {
    const { deps } = makeFake({ willIssue: true });
    const step = makeStep();
    await runReissueSteps(step, deps, deps.logger, remediationCtx());
    const idx = (needle: string) =>
      step.calls.findIndex((c) => c.startsWith(needle));
    expect(idx("capture-pre-flip-dns")).toBeGreaterThanOrEqual(0);
    expect(idx("capture-pre-flip-dns")).toBeLessThan(idx("toggle-reissue"));
    expect(idx("toggle-reissue")).toBeLessThan(idx("dns-gate-"));
    expect(idx("dns-gate-")).toBeLessThan(idx("poll-"));
    expect(idx("poll-")).toBeLessThan(idx("restore-steady-state"));
  });

  it("pre-flip baseline is captured BEFORE the flip, in its own step", async () => {
    const { deps } = makeFake({ willIssue: true });
    const step = makeStep();
    await runReissueSteps(step, deps, deps.logger, remediationCtx());
    // Emitting it inside toggle-reissue would mean a step RETRY re-reads the
    // "pre-flip" baseline AFTER the first flip — a misleading baseline on
    // exactly the retry path that most needs a true one.
    const phases = emittedPhases();
    expect(phases.indexOf("pre-flip-dns")).toBeLessThan(
      phases.indexOf("flip-dns-only"),
    );
  });

  it("restore runs on EVERY toggle-ok terminal (issued, timeout, gate-fail, probe)", async () => {
    const cases: Array<[string, FakeConfig, ReissueRunContext]> = [
      ["issued", { willIssue: true }, remediationCtx()],
      ["poll_timeout", { willIssue: false }, remediationCtx()],
      [
        "dns_propagation_failed",
        {
          dnsPropagation: {
            resolved6: ["2a06:98c1:3120::2"],
            resolve6Error: null,
          },
        },
        remediationCtx(),
      ],
      ["probe_only_complete", {}, probeCtx()],
    ];
    for (const [label, cfg, ctx] of cases) {
      const { deps, state } = makeFake(cfg);
      const step = makeStep();
      const result = await runReissueSteps(step, deps, deps.logger, ctx);
      expect(result.outcome, label).toBe(label);
      expect(step.calls, label).toContain("restore-steady-state");
      expect(state.records.every((r) => r.proxied === true), label).toBe(true);
    }
  });

  it("reissue_failed restores IN-STEP and gains no second body-level restore (AC9)", async () => {
    // A second body restore would be idempotent but harmful: if it threw, the
    // body would throw, onFailure would fire, and the precise reissue_failed
    // diagnostic would be overwritten by a generic restore outcome.
    const { deps, state } = makeFake({ failCnameOn: "null" });
    const step = makeStep();
    const result = await runReissueSteps(
      step,
      deps,
      deps.logger,
      remediationCtx(),
    );
    expect(result.outcome).toBe("reissue_failed");
    expect(step.calls).not.toContain("restore-steady-state");
    // ...but the in-step restore DID converge the steady state.
    expect(state.records.every((r) => r.proxied === true)).toBe(true);
    expect(state.cname).toBe("soleur.ai");
  });

  it("a non-benign outcome actually pages via reportSilentFallback", async () => {
    // The structural test above proves the shape; this proves the consequence.
    // Without it, a post-toggle return that bypasses emitAndReturn would remove
    // the page for reissue_failed and no test would notice.
    reportSilentFallbackMock.mockClear();
    const { deps } = makeFake({ failCnameOn: "null" });
    const result = await runReissueSteps(
      makeStep(),
      deps,
      deps.logger,
      remediationCtx(),
    );
    expect(result.outcome).toBe("reissue_failed");
    expect(result.ok).toBe(false);
    expect(reportSilentFallbackMock).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ tags: { outcome: "reissue_failed" } }),
    );
  });

  it("reports the CONVERGED state on reissue_failed, not null", () => {
    // The in-step restore ran and is convergence-asserted. `null` on a paging
    // outcome reads as "unknown", and the first question an operator asks is
    // whether the marketing site is still exposed.
    return (async () => {
      const { deps } = makeFake({ failCnameOn: "null" });
      const r = await runReissueSteps(
        makeStep(),
        deps,
        deps.logger,
        remediationCtx(),
      );
      expect(r.proxiedStateAtExit).toBe(true);
      expect(r.cnameAtExit).toBe("soleur.ai");
    })();
  });

  it("has exactly ONE post-toggle return site, after restore (AC9, structural)", () => {
    const src = readFileSync(
      resolve(
        __dirname,
        "../../../server/inngest/functions/cron-gh-pages-cert-reissue.ts",
      ),
      "utf8",
    );
    const start = src.indexOf("// POST-TOGGLE.");
    expect(start).toBeGreaterThan(-1);
    const end = src.indexOf("// Live-IO dep construction", start);
    expect(end).toBeGreaterThan(start);
    const tail = src.slice(start, end);
    // The invariant is STRUCTURAL: a universal "no post-toggle return bypasses
    // restore" cannot be proven by driving one path, so the code is shaped so
    // it holds by construction.
    //
    // Anchor on the FUNCTION-EXIT indentation (exactly two spaces). A bare
    // `\s*return` also matches `return p;` / `return v;` inside the poll and
    // gate step CALLBACKS, which are not function exits at all — that anchor
    // would report 3 and say nothing about the invariant.
    // Band 2-4 spaces, not exactly 2: a `return result;` at 4-space indent
    // INSIDE the `if (!toggle.ok) { … }` block is a post-toggle exit that skips
    // emitAndReturn entirely — no terminal marker, no reportSilentFallback, so
    // the paging path for that failure class dies silently. An exactly-2 anchor
    // counts 1 and the deep-return non-vacuity check still passes, so the
    // violation lives in the gap between the two anchors.
    const exitReturns = tail.match(/^ {2,4}return\s/gm) ?? [];
    expect(exitReturns).toHaveLength(1);
    // ...and the single exit is the one that runs terminal observability.
    expect(tail).toMatch(/^ {2}return emitAndReturn\(/m);
    // Non-vacuity: the callback returns DO exist at deeper indentation, so the
    // anchor above is discriminating rather than matching nothing.
    expect(tail.match(/^ {6,}return\s/gm)?.length ?? 0).toBeGreaterThan(0);
  });
});

describe("#6698 marker coverage and correlation", () => {
  it("emits a terminal marker for BENIGN outcomes too (AC3)", async () => {
    // The headline defect: emitTerminal routes benign outcomes through
    // logger.info, and both gates hold there (ProxyLogger disabled outside an
    // executing step; Vector drops pino INFO). Without a marker inside
    // emitTerminal the `issued` success path stays dark.
    for (const [cfg, expected] of [
      [{ willIssue: true }, "issued"],
      [{ stateOverride: "issued" }, "not_stuck"],
    ] as Array<[FakeConfig, string]>) {
      markerSpy.mockClear();
      const { deps } = makeFake(cfg);
      const result = await runReissueSteps(
        makeStep(),
        deps,
        deps.logger,
        remediationCtx(),
      );
      expect(result.outcome).toBe(expected);
      const terminal = emittedMarkers().filter((m) => m.phase === "terminal");
      expect(terminal, expected).toHaveLength(1);
      expect(terminal[0].outcome).toBe(expected);
    }
  });

  it("covers every phase in the exported union across both entry points (AC4)", async () => {
    const seen = new Set<string>();

    // Remediation run: everything except onfailure-restore.
    const a = makeFake({ willIssue: true });
    await runReissueSteps(makeStep(), a.deps, a.deps.logger, remediationCtx());
    emittedPhases().forEach((p) => seen.add(p));

    // onFailure is NOT part of runReissueSteps, so it needs its own drive.
    markerSpy.mockClear();
    const prevToken = process.env.CF_API_TOKEN_DNS_EDIT;
    const prevZone = process.env.CF_ZONE_ID;
    process.env.CF_API_TOKEN_DNS_EDIT = "";
    process.env.CF_ZONE_ID = "";
    try {
      await cronGhPagesCertReissueOnFailure({
        error: new Error("body threw"),
        event: {},
        step: makeStep(),
        logger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
      });
    } finally {
      if (prevToken === undefined) delete process.env.CF_API_TOKEN_DNS_EDIT;
      else process.env.CF_API_TOKEN_DNS_EDIT = prevToken;
      if (prevZone === undefined) delete process.env.CF_ZONE_ID;
      else process.env.CF_ZONE_ID = prevZone;
    }
    emittedPhases().forEach((p) => seen.add(p));

    // Compare the OBSERVED phase set against the exported union — not a grep
    // count, so a new phase without an emit site fails here.
    for (const phase of CERT_REISSUE_PHASES) {
      expect(Array.from(seen), `phase ${phase} has no emit site`).toContain(
        phase,
      );
    }
  });

  it("propagates the runId and attempt VALUES into every marker (AC5)", async () => {
    const { deps } = makeFake({ willIssue: true });
    await runReissueSteps(makeStep(), deps, deps.logger, {
      probeOnly: false,
      runId: "run-XYZ",
      attempt: 3,
    });
    const markers = emittedMarkers();
    expect(markers.length).toBeGreaterThan(0);
    // A type-level check alone would pass against a hardcoded `attempt: 0`.
    for (const m of markers) {
      expect(m.runId).toBe("run-XYZ");
      expect(m.attempt).toBe(3);
    }
  });

  it("stamps probeOnly on EVERY marker, not just the terminal one", async () => {
    const { deps } = makeFake();
    await runReissueSteps(makeStep(), deps, deps.logger, probeCtx());
    // A row read out of context must never be misreadable as remediation.
    expect(emittedMarkers().every((m) => m.probeOnly === true)).toBe(true);
  });

  it("emits once per real execution, bounded (AC6)", async () => {
    const { deps } = makeFake({ willIssue: false });
    await runReissueSteps(makeStep(), deps, deps.logger, remediationCtx());
    const polls = emittedMarkers().filter((m) => m.phase === "poll");
    // Bounded, not pinned to an exact count — an exact assertion flakes.
    expect(polls.length).toBeGreaterThan(0);
    expect(polls.length).toBeLessThanOrEqual(MAX_DNS_ONLY_WINDOW_MS / 60_000);
    // Poll markers must be emitted INSIDE the step callback, so each carries its
    // own index rather than repeating one value.
    expect(new Set(polls.map((m) => m.pollIndex)).size).toBe(polls.length);
  });

  it("captures the full https_certificate object in poll markers (RI-7)", async () => {
    const { deps } = makeFake({ willIssue: false });
    const original = deps.getPages.bind(deps);
    deps.getPages = async () => ({
      ...(await original()),
      description: "LE said something useful",
      domains: ["soleur.ai"],
      expiresAt: "2026-08-16",
      protectedDomainState: "verified",
    });
    await runReissueSteps(makeStep(), deps, deps.logger, remediationCtx());
    const poll = emittedMarkers().find((m) => m.phase === "poll");
    // `description` is the ONLY in-band field that has ever carried Let's
    // Encrypt-side detail — the sole candidate for separating "window too short"
    // from "rate limited", which `state` alone cannot do.
    expect(poll?.certDescription).toBe("LE said something useful");
    expect(poll?.certExpiresAt).toBe("2026-08-16");
    expect(poll?.protectedDomainState).toBe("verified");
  });

  it("emits a restore marker on entry AND on a THROWING restore (Phase 1.7)", async () => {
    // A marker emitted only after restoreState returns means a throwing restore
    // emits nothing, making "never attempted" indistinguishable from
    // "attempted and failed" — the worse of the two states.
    const { deps } = makeFake({ listCount: 3 });
    await expect(restoreState(deps, (phase, fields) =>
      markerSpy({ phase, ...fields }),
    )).rejects.toThrow(/only 3\//);
    const restores = emittedMarkers().filter((m) => m.phase === "restore");
    expect(restores.length).toBeGreaterThanOrEqual(2);
    expect(restores.some((m) => m.ok === false)).toBe(true);
  });
});

describe("#6698 onFailure envelope", () => {
  // Inngest registers onFailure as a SEPARATE function triggered by
  // `inngest/function.failed`, whose payload wraps the original event:
  //   { name, data: { function_id, run_id, error, event: <originalEvent> } }
  // Every prior onFailure test passed `event: {}` — a shape production never
  // produces — which is exactly why the payload bug shipped.
  function failureEvent(originalData: unknown, runId = "run-FAILED") {
    return {
      name: "inngest/function.failed",
      data: {
        function_id: "cron-gh-pages-cert-reissue",
        run_id: runId,
        error: { name: "Error", message: "boom" },
        event: { data: originalData },
      },
    };
  }

  async function driveOnFailure(event: unknown) {
    const prevToken = process.env.CF_API_TOKEN_DNS_EDIT;
    const prevZone = process.env.CF_ZONE_ID;
    process.env.CF_API_TOKEN_DNS_EDIT = "";
    process.env.CF_ZONE_ID = "";
    try {
      await cronGhPagesCertReissueOnFailure({
        error: new Error("body threw"),
        event,
        step: makeStep(),
        logger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
      });
    } finally {
      if (prevToken === undefined) delete process.env.CF_API_TOKEN_DNS_EDIT;
      else process.env.CF_API_TOKEN_DNS_EDIT = prevToken;
      if (prevZone === undefined) delete process.env.CF_ZONE_ID;
      else process.env.CF_ZONE_ID = prevZone;
    }
  }

  it("reads probeOnly from the WRAPPED original event, not the envelope", async () => {
    // An operator's {"probeOnly": false} remediation that then threw would
    // otherwise be recorded as a PROBE — inverting the one field whose contract
    // is that a row can never be misread as a remediation fire, and corrupting
    // the Let's Encrypt validation-attempt accounting.
    await driveOnFailure(failureEvent({ probeOnly: false }));
    const markers = emittedMarkers().filter(
      (m) => m.phase === "onfailure-restore",
    );
    expect(markers.length).toBeGreaterThan(0);
    expect(markers.every((m) => m.probeOnly === false)).toBe(true);
  });

  it("attributes markers to the FAILED run, not the failure handler's run", async () => {
    markerSpy.mockClear();
    await driveOnFailure(failureEvent({ probeOnly: false }, "run-ORIGINAL"));
    const markers = emittedMarkers().filter(
      (m) => m.phase === "onfailure-restore",
    );
    // Without this the onfailure markers are un-joinable to the run they
    // describe, defeating the whole point of the runId field.
    expect(markers.every((m) => m.runId === "run-ORIGINAL")).toBe(true);
  });

  it("still defaults to probe-only when the wrapped event carries no flag", async () => {
    markerSpy.mockClear();
    await driveOnFailure(failureEvent({}));
    const markers = emittedMarkers().filter(
      (m) => m.phase === "onfailure-restore",
    );
    expect(markers.every((m) => m.probeOnly === true)).toBe(true);
  });
});

describe("emitTerminal must CALL the logger method, not extract it", () => {
  // A plain `{ info: vi.fn() }` fake cannot catch this class: object-literal
  // methods have no `this` dependency, so an extracted reference works fine
  // against the fake and throws only in production. This fake mirrors inngest's
  // real ProxyLogger, whose info()/warn() begin `if (!this.enabled) return;`.
  class ProxyLoggerLike {
    enabled = true;
    calls: Array<[unknown, unknown]> = [];
    info(...args: unknown[]) {
      if (!this.enabled) return;
      this.calls.push([args[0], args[1]]);
    }
    warn(...args: unknown[]) {
      if (!this.enabled) return;
      this.calls.push([args[0], args[1]]);
    }
    error(...args: unknown[]) {
      if (!this.enabled) return;
      this.calls.push([args[0], args[1]]);
    }
  }

  it("does not throw on a BENIGN terminal (issued / not_stuck / probe_only_complete)", async () => {
    // Observed in production on the first post-deploy fire: extracting the
    // method produced `Cannot read properties of undefined (reading 'enabled')`,
    // which escaped the handler, exhausted retries and fired onFailure — so a
    // SUCCESSFUL remediation was recorded as reissue_incomplete_restore_ok.
    for (const [cfg, ctx, expected] of [
      [{ willIssue: true }, remediationCtx(), "issued"],
      [{ stateOverride: "issued" }, remediationCtx(), "not_stuck"],
      [{}, probeCtx(), "probe_only_complete"],
    ] as Array<[FakeConfig, ReissueRunContext, string]>) {
      const { deps } = makeFake(cfg);
      const proxyLogger = new ProxyLoggerLike();
      deps.logger = proxyLogger as unknown as ReissueDeps["logger"];

      const result = await runReissueSteps(
        makeStep(),
        deps,
        deps.logger,
        ctx,
      );

      expect(result.outcome, expected).toBe(expected);
      // The benign branch must have actually logged through the bound method.
      expect(proxyLogger.calls.length, expected).toBeGreaterThan(0);
      const [payload, msg] = proxyLogger.calls[proxyLogger.calls.length - 1];
      expect(msg).toBe(`reissue outcome=${expected}`);
      expect(payload).toMatchObject({ outcome: expected });
    }
  });

  it("config_missing routes to warn, still bound", async () => {
    const proxyLogger = new ProxyLoggerLike();
    const prevToken = process.env.CF_API_TOKEN_DNS_EDIT;
    const prevZone = process.env.CF_ZONE_ID;
    process.env.CF_API_TOKEN_DNS_EDIT = "";
    process.env.CF_ZONE_ID = "";
    try {
      const result = await cronGhPagesCertReissueHandler({
        step: makeStep(),
        logger: proxyLogger as unknown as ReissueDeps["logger"],
      } as unknown as Parameters<typeof cronGhPagesCertReissueHandler>[0]);
      expect(result.outcome).toBe("config_missing");
      expect(proxyLogger.calls.length).toBeGreaterThan(0);
    } finally {
      if (prevToken === undefined) delete process.env.CF_API_TOKEN_DNS_EDIT;
      else process.env.CF_API_TOKEN_DNS_EDIT = prevToken;
      if (prevZone === undefined) delete process.env.CF_ZONE_ID;
      else process.env.CF_ZONE_ID = prevZone;
    }
  });
});

describe("#6698 routine_runs projection", () => {
  it("sets ok/errorSummary so runLogMiddleware can distinguish outcomes", async () => {
    // run-log.ts projects EXACTLY { ok?, errorSummary? } off the return value.
    // Without them every outcome — a probe that never attempted the fix, and
    // the deliberately-paging dns_propagation_failed — writes an identical
    // status='completed', error_summary=null row. That row is WORM.
    const benign = await runReissueSteps(
      makeStep(),
      makeFake({ willIssue: true }).deps,
      makeFake().deps.logger,
      remediationCtx(),
    );
    expect(benign.outcome).toBe("issued");
    expect(benign.ok).toBe(true);
    expect(benign.errorSummary).toBeUndefined();

    const probe = await runReissueSteps(
      makeStep(),
      makeFake().deps,
      makeFake().deps.logger,
      probeCtx(),
    );
    expect(probe.outcome).toBe("probe_only_complete");
    expect(probe.ok).toBe(true);
    expect(probe.probeOnly).toBe(true);

    const paging = await runReissueSteps(
      makeStep(),
      makeFake({
        dnsPropagation: {
          resolved6: ["2a06:98c1:3120::2"],
          resolve6Error: null,
        },
      }).deps,
      makeFake().deps.logger,
      remediationCtx(),
    );
    expect(paging.outcome).toBe("dns_propagation_failed");
    expect(paging.ok).toBe(false);
    expect(paging.errorSummary).toContain("dns_propagation_failed");
  });
});

describe("#6698 window budget and allowlist", () => {
  it("the TOTAL window (poll + settle + gate) stays within 15 minutes (AC13)", () => {
    // Asserting POLL_MAX_MS alone passed while the real public-TLS-outage window
    // overran — it already did, by CNAME_SETTLE_MS (45s).
    expect(TOTAL_DNS_ONLY_WINDOW_MS).toBeLessThanOrEqual(MAX_DNS_ONLY_WINDOW_MS);
    expect(MAX_DNS_ONLY_WINDOW_MS).toBe(15 * 60 * 1000);
    // Non-vacuity: the total must actually include all three components, so it
    // has to exceed the poll budget alone.
    expect(TOTAL_DNS_ONLY_WINDOW_MS).toBeGreaterThan(10 * 60 * 1000);
    // ‼️ The <= assertion above is algebraically TAUTOLOGICAL: MAX_POLLS is
    // derived by flooring the poll budget, so the sum can never exceed the max
    // for ANY constant values. The real risk is someone adding a new sleep to
    // the window and forgetting to add it to the total — so assert the total
    // actually ACCOUNTS FOR each declared component.
    expect(TOTAL_DNS_ONLY_WINDOW_MS).toBeGreaterThanOrEqual(
      45_000 + (DNS_GATE_MAX_ATTEMPTS - 1) * 30_000,
    );
  });

  it("the gate budget exceeds one full Cloudflare proxied-TTL rollover", () => {
    // CF's proxied TTL is a fixed, non-editable 300s. A gate that gives up
    // sooner times out before the event it waits for can occur, making "not
    // propagated" the default observation of a correct remediation.
    const gateBudgetMs = (DNS_GATE_MAX_ATTEMPTS - 1) * 30_000;
    expect(gateBudgetMs).toBeGreaterThanOrEqual(300_000);
  });

  it("widens the allowlist to the documented terminal failure states (AC16b)", () => {
    // `errored` and `authorization_revoked` are documented terminal failures a
    // cert can wedge in; both were previously declined as not_stuck and never
    // remediated.
    expect(assertStuckState("errored").proceed).toBe(true);
    expect(assertStuckState("authorization_revoked").proceed).toBe(true);
    expect(assertStuckState("bad_authz").proceed).toBe(true);
    // Healthy and in-flight states are still refused — toggling a healthy
    // in-flight order can MANUFACTURE a new bad_authz.
    for (const s of [
      "issued",
      "approved",
      "authorized",
      "authorization_pending",
      "dns_changed",
      "new",
      "uploaded",
    ]) {
      expect(assertStuckState(s).proceed, s).toBe(false);
    }
    expect(REISSUE_ALLOWED_STATES).toContain("errored");
  });
});

describe("#6698 live deps are real, not a dead twin (AC8b)", () => {
  it("buildLiveDeps constructs a real gatherDnsPropagation", () => {
    const deps = buildLiveDeps({
      installationToken: "t",
      cfToken: "c",
      zoneId: "z",
      logger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    });
    expect(typeof deps.gatherDnsPropagation).toBe("function");
    // Non-vacuity: prove it is the REAL resolver-based implementation, not a
    // stub returning empty observations. A stub would satisfy the type member,
    // the gate step, and every fake-driven test while production never gates.
    const src = deps.gatherDnsPropagation.toString();
    expect(src).toContain("setServers");
    expect(src).toContain("resolve6");
  });
});
