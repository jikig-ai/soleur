// #6657 — Event-triggered GitHub Pages cert `bad_authz` remediation.
//
// The soleur.ai GitHub Pages custom-domain TLS cert periodically wedges in ACME
// state `bad_authz`. Root cause (LIKELY): the apex A-records + www CNAME are
// Cloudflare-PROXIED (orange cloud), so GitHub/Let's Encrypt's domain-config /
// HTTP-01 validation sees CF anycast IPs instead of GitHub's 185.199.x origins
// and the authorization never completes. This routine performs the
// postmortem-proven recovery (learning 2026-02-16-github-pages-cloudflare-wiring):
//   1. flip apex+www to DNS-only (proxied=false) so GitHub sees its own IPs,
//   2. re-order the cert by toggling the Pages custom domain (cname:null → re-set)
//      via the GitHub App's `administration:write` grant,
//   3. poll GET /pages until state ∈ {approved, issued},
//   4. restore the declared steady state (proxied=true, cname=soleur.ai).
//
// Replay-safety (ADR-077, ADR-033): the toggle+reissue mutation lives in ONE
// step.run (so a step retry is the only thing that re-orders the cert); the poll
// uses step.sleep (the only suspension point); restore is an UNCONDITIONAL final
// step PLUS an `onFailure` lifecycle handler (idempotent) — a JS `try…finally`
// is WRONG here because step.sleep suspends via a control-flow throw that would
// run `finally` prematurely at the first poll pass. There is no in-repo
// `onFailure` precedent; the config key is verified against pinned inngest 3.54.2.
// The read-only preflight lives in its OWN preceding step so the atomic mutating
// step holds an HTTP connection only for the toggle→settle→reset window (the
// Inngest executor callback goes through CF's ~100s origin-response timeout).
//
// AP-001 exception: this is an off-Terraform live-infra mutation (transient,
// self-reverting, single-attempt, human-gated). Registered as AP-019 in
// principles-register.md and governed by ADR-125.
//
// v1 = manual-trigger only (POST /api/internal/trigger-cron). Self-heal
// auto-invoke + a drift/apply freeze-lock are deferred to a flag-gated v2
// (CTO ruling 2026-07-18: no runtime freeze-lock substrate exists; v1 accepts
// the documented residual race behind the P0 backstop).

import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import {
  REPO_OWNER,
  REPO_NAME,
  mintInstallationToken,
  type HandlerArgs,
} from "./_cron-shared";

// =============================================================================
// Constants
// =============================================================================

const FN_ID = "cron-gh-pages-cert-reissue";
const SENTRY_FEATURE = "cron-gh-pages-cert-reissue";

// The declared steady state (dns.tf: cloudflare_record.github_pages + .www).
// Restore always targets THIS — it is what Terraform owns, so re-asserting it is
// correct and drift-free. The onFailure path has no in-memory capture, so it
// restores to these declared constants (idempotent with the happy-path restore).
// Exported so the test suite pins against the same literals (no drift).
export const APEX_NAME = "soleur.ai";
export const WWW_NAME = "www.soleur.ai";
export const PAGES_CNAME = "soleur.ai";
const STEADY_PROXIED = true;

// The toggle set is exactly the 4 apex A-records + the www CNAME (dns.tf). A
// restore that sees FEWER than this many records has hit a Cloudflare read
// failure (listToggleRecords coalesces nothing to []) and MUST fail loud rather
// than "restore" a subset and leave origins exposed. See restoreState.
export const EXPECTED_TOGGLE_RECORDS = 5;

// Preflight allowlist: only a genuinely-stuck cert is touched. Toggling a
// healthy in-flight order (authorization_pending / dns_changed / new) can
// MANUFACTURE a new bad_authz — hence an allowlist, not a denylist.
const REISSUE_ALLOWED_STATES = ["bad_authz", "failed"] as const;

// GitHub App installation-token lifetime floor (a handful of admin calls).
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

// Least-privilege scope: PUT /repos/{owner}/{repo}/pages requires `administration`
// (the Pages site-config endpoint; `pages:write` is insufficient for the
// custom-domain toggle). repositories:["soleur"] + a 15-min TTL bound the blast
// radius to one repo.
const REISSUE_TOKEN_PERMISSIONS: Record<string, string> = {
  administration: "write",
};

// Bounds. The poll cap keeps the DNS-only (unprotected) window short.
const POLL_INTERVAL_MS = 60 * 1000;
const POLL_MAX_MS = 15 * 60 * 1000;
// Fixed poll count for the replay-safe handler loop (deterministic across
// resumes — NOT a wall-clock bound in the body). The loop skips the trailing
// sleep, so the effective poll window is (MAX_POLLS-1)*POLL_INTERVAL_MS ≈ 14 min.
const MAX_POLLS = Math.floor(POLL_MAX_MS / POLL_INTERVAL_MS);
const CNAME_SETTLE_MS = 45 * 1000; // between cname:null and re-set
const CF_TIMEOUT_MS = 10 * 1000;
// Octokit has no default request timeout; bound the GitHub leg so a slow API
// call cannot blow the ~100s CF origin-response budget inside the atomic step.
const GITHUB_TIMEOUT_MS = 15 * 1000;

const CF_API_BASE = "https://api.cloudflare.com/client/v4";

// =============================================================================
// Types
// =============================================================================

export type ReissueOutcome =
  | "issued"
  | "poll_timeout"
  | "reissue_failed"
  | "proxy_restore_failed"
  | "precondition_blocked"
  | "not_stuck"
  | "config_missing";

export interface ReissueResult {
  outcome: ReissueOutcome;
  finalState: string;
  attempts: number;
  elapsedMs: number;
  proxiedStateAtExit: boolean | null;
  cnameAtExit: string | null;
  preconditionResults?: Record<string, boolean>;
  detail: string;
}

/** A single Cloudflare DNS record we toggle (apex A-record or the www CNAME). */
export interface CfDnsRecord {
  id: string;
  name: string;
  type: string;
  proxied: boolean;
}

export interface PreconditionInputs {
  acmeApexStatus: number;
  acmeWwwStatus: number;
  caaCount: number;
  challengeTxtPresent: boolean;
  alwaysUseHttps: string;
}

/**
 * All live IO is injected so the orchestration is testable without a network.
 * The Inngest handler supplies real implementations (Octokit + CF fetch); the
 * unit tests supply fakes and drive `runReissueSteps` — the SAME function that
 * runs in production (no parallel/dead twin).
 */
export interface ReissueDeps {
  getPages(): Promise<{ state: string; cname: string | null }>;
  setPagesCname(cname: string | null): Promise<void>;
  listToggleRecords(): Promise<CfDnsRecord[]>;
  setRecordProxied(id: string, proxied: boolean): Promise<boolean>;
  gatherPreconditions(): Promise<PreconditionInputs>;
  sleep(ms: number): Promise<void>;
  logger: HandlerArgs["logger"];
}

/** The Inngest step primitive the orchestration needs (run + sleep). Injectable
 * so `runReissueSteps` is drivable by a fake step in tests. */
export interface ReissueStep {
  run<T>(name: string, cb: () => Promise<T>): Promise<T>;
  sleep(name: string, duration: string): Promise<void>;
}

// =============================================================================
// Pure helpers
// =============================================================================

/**
 * Preflight allowlist gate. Returns proceed=true ONLY for a genuinely-stuck
 * cert; never for a healthy (issued/approved) or in-flight intermediate state.
 */
export function assertStuckState(state: string): {
  proceed: boolean;
  reason: string;
} {
  if ((REISSUE_ALLOWED_STATES as readonly string[]).includes(state)) {
    return { proceed: true, reason: `state=${state} is reissue-eligible` };
  }
  return {
    proceed: false,
    reason: `state=${state} not in [${REISSUE_ALLOWED_STATES.join(", ")}] — refusing to toggle`,
  };
}

/**
 * Evaluate the auto-fixable preconditions. A broken precondition the routine
 * CANNOT fix (CAA appeared, verification TXT missing, ACME carve-out regressed,
 * always_use_https re-enabled) means a cname toggle would just re-fail — skip.
 */
export function checkReissuePreconditions(inputs: PreconditionInputs): {
  ok: boolean;
  results: Record<string, boolean>;
  failed: string[];
} {
  const results: Record<string, boolean> = {
    acmeApexCarveout: inputs.acmeApexStatus === 404,
    acmeWwwCarveout: inputs.acmeWwwStatus === 404,
    caaPermissive: inputs.caaCount === 0,
    challengeTxtPresent: inputs.challengeTxtPresent === true,
    alwaysUseHttpsOff: inputs.alwaysUseHttps === "off",
  };
  const failed = Object.entries(results)
    .filter(([, ok]) => !ok)
    .map(([k]) => k);
  return { ok: failed.length === 0, results, failed };
}

// =============================================================================
// IO orchestration (async, deps-injected)
// =============================================================================

/**
 * Toggle every apex A-record + the www CNAME to `proxied`. On ANY partial
 * failure, throws PartialToggleError so the caller aborts→restores rather than
 * leaving a half-open window.
 */
export class PartialToggleError extends Error {
  readonly recordsToggled: number;
  readonly totalRecords: number;
  constructor(recordsToggled: number, totalRecords: number) {
    super(
      `partial CF proxy toggle: ${recordsToggled}/${totalRecords} records set`,
    );
    this.name = "PartialToggleError";
    this.recordsToggled = recordsToggled;
    this.totalRecords = totalRecords;
  }
}

export async function setRecordsProxied(
  deps: ReissueDeps,
  records: CfDnsRecord[],
  proxied: boolean,
): Promise<void> {
  let toggled = 0;
  for (const rec of records) {
    const ok = await deps.setRecordProxied(rec.id, proxied);
    if (!ok) {
      throw new PartialToggleError(toggled, records.length);
    }
    toggled += 1;
  }
}

/** Re-order the cert: PUT cname:null → settle → PUT cname:soleur.ai. */
export async function reissueViaCnameToggle(deps: ReissueDeps): Promise<void> {
  await deps.setPagesCname(null);
  await deps.sleep(CNAME_SETTLE_MS);
  await deps.setPagesCname(PAGES_CNAME);
}

/**
 * Restore the declared steady state: proxied=true on all toggle records +
 * cname=soleur.ai. Idempotent — safe to run from BOTH the happy-path final step
 * and the onFailure handler. FAIL-LOUD:
 *   - a short record read (Cloudflare GET failure → fewer than the expected 5
 *     records) throws, so a partial/empty list cannot "restore" a subset and
 *     silently leave origins exposed (the alert never fires on a swallowed read);
 *   - the final re-read convergence assert throws if a PATCH returned success but
 *     did not stick (records still proxied=false, or cname didn't persist).
 * A failed restore is a security regression, not a swallow — it throws so the
 * caller (or onFailure) pages proxy_restore_failed.
 */
export async function restoreState(deps: ReissueDeps): Promise<void> {
  const records = await deps.listToggleRecords();
  if (records.length < EXPECTED_TOGGLE_RECORDS) {
    throw new Error(
      `restore: read only ${records.length}/${EXPECTED_TOGGLE_RECORDS} toggle records ` +
        `(Cloudflare read failure?) — refusing to restore a subset`,
    );
  }
  for (const rec of records) {
    if (rec.proxied !== STEADY_PROXIED) {
      const ok = await deps.setRecordProxied(rec.id, STEADY_PROXIED);
      if (!ok) {
        throw new Error(`restore: failed to set proxied on record ${rec.id}`);
      }
    }
  }
  const pages = await deps.getPages();
  if (pages.cname !== PAGES_CNAME) {
    await deps.setPagesCname(PAGES_CNAME);
  }
  // Assert the live state converged (catches a write that returned true but did
  // not stick — the origin-exposure case a per-record throw cannot see).
  const after = await deps.listToggleRecords();
  if (after.length < EXPECTED_TOGGLE_RECORDS) {
    throw new Error(
      `restore-assert: re-read only ${after.length}/${EXPECTED_TOGGLE_RECORDS} records`,
    );
  }
  const stillWrong = after.filter((r) => r.proxied !== STEADY_PROXIED);
  const pagesAfter = await deps.getPages();
  if (stillWrong.length > 0 || pagesAfter.cname !== PAGES_CNAME) {
    throw new Error(
      `restore-assert failed: ${stillWrong.length} record(s) not proxied; cname=${pagesAfter.cname}`,
    );
  }
}

// =============================================================================
// Production orchestration (injectable step + deps → directly testable)
// =============================================================================

function emitAndReturn(
  result: ReissueResult,
  logger: HandlerArgs["logger"],
): ReissueResult {
  emitTerminal(result, logger);
  return result;
}

/**
 * The full v1 remediation, mapped onto Inngest steps. THIS is the production
 * control flow (the handler only mints the token + builds live deps, then calls
 * this). Tests drive it with a fake `step` + fake `deps`, so the code that ships
 * is the code that is tested — there is no parallel twin.
 *
 * Step structure (ADR-077): read-only preflight in its own step → atomic
 * toggle+reissue in ONE step → step.sleep poll → unconditional restore step.
 */
export async function runReissueSteps(
  step: ReissueStep,
  deps: ReissueDeps,
  logger: HandlerArgs["logger"],
): Promise<ReissueResult> {
  // Memoized start stamp so elapsedMs is correct across replays (Date.now() in
  // the body would re-stamp on every resume and measure only the final pass).
  const startedAt = await step.run("mark-start", async () => Date.now());
  const elapsed = () => Date.now() - startedAt;

  // Read-only preflight (own step; a retry of the mutation step below does not
  // re-run these probes). Splitting it out also keeps the ~10-25s of ACME/DNS/CF
  // read probes OUT of the atomic step's held-connection budget.
  const pre = await step.run("preflight", async () => {
    const pages = await deps.getPages();
    const gate = assertStuckState(pages.state);
    if (!gate.proceed) {
      return { status: "not_stuck" as const, state: pages.state, reason: gate.reason };
    }
    const preCheck = checkReissuePreconditions(await deps.gatherPreconditions());
    if (!preCheck.ok) {
      return {
        status: "blocked" as const,
        state: pages.state,
        results: preCheck.results,
        failed: preCheck.failed,
      };
    }
    return { status: "ok" as const, state: pages.state, results: preCheck.results };
  });

  if (pre.status === "not_stuck") {
    return emitAndReturn(
      {
        outcome: "not_stuck",
        finalState: pre.state,
        attempts: 0,
        elapsedMs: elapsed(),
        proxiedStateAtExit: null,
        cnameAtExit: null,
        detail: pre.reason,
      },
      logger,
    );
  }
  if (pre.status === "blocked") {
    return emitAndReturn(
      {
        outcome: "precondition_blocked",
        finalState: pre.state,
        attempts: 0,
        elapsedMs: elapsed(),
        proxiedStateAtExit: null,
        cnameAtExit: null,
        preconditionResults: pre.results,
        detail: `preconditions failed: ${pre.failed.join(", ")}`,
      },
      logger,
    );
  }

  // Atomic toggle + reissue (ONE step.run): a step retry re-runs the whole
  // mutating unit (bounded by retries:1), never a half-applied window.
  const toggle = await step.run("toggle-reissue", async () => {
    try {
      const records = await deps.listToggleRecords();
      await setRecordsProxied(deps, records, false);
      await reissueViaCnameToggle(deps);
      return { ok: true as const };
    } catch (err) {
      // Restore inside this step so a same-step abort is self-contained.
      await restoreState(deps);
      return {
        ok: false as const,
        message: (err as Error).message,
        httpStatus:
          err instanceof PartialToggleError ? "partial-toggle" : "cname-put",
      };
    }
  });

  if (!toggle.ok) {
    return emitAndReturn(
      {
        outcome: "reissue_failed",
        finalState: pre.state,
        attempts: 0,
        elapsedMs: elapsed(),
        proxiedStateAtExit: null,
        cnameAtExit: null,
        preconditionResults: pre.results,
        detail: `reissue trigger failed (${toggle.httpStatus}): ${toggle.message}`,
      },
      logger,
    );
  }

  // Poll (step.sleep is the only suspension point). Fixed count → deterministic
  // step names across replays.
  let attempts = 0;
  let finalState = "unknown";
  let healthy = false;
  for (let i = 0; i < MAX_POLLS; i++) {
    const pages = await step.run(`poll-${i}`, () => deps.getPages());
    attempts += 1;
    finalState = pages.state;
    if (pages.state === "approved" || pages.state === "issued") {
      healthy = true;
      break;
    }
    if (i < MAX_POLLS - 1) {
      await step.sleep(`poll-wait-${i}`, `${POLL_INTERVAL_MS}ms`);
    }
  }

  // Unconditional final restore step.
  await step.run("restore-steady-state", () => restoreState(deps));

  return emitAndReturn(
    {
      outcome: healthy ? "issued" : "poll_timeout",
      finalState,
      attempts,
      elapsedMs: elapsed(),
      proxiedStateAtExit: STEADY_PROXIED,
      cnameAtExit: PAGES_CNAME,
      preconditionResults: pre.results,
      detail: healthy
        ? `cert reissued: state=${finalState} after ${attempts} poll(s)`
        : `poll cap reached; final state=${finalState}`,
    },
    logger,
  );
}

// =============================================================================
// Live-IO dep construction (Octokit + Cloudflare fetch), mirroring
// cf-cache-purge.ts (Bearer + AbortController) + cron-gh-pages-cert-state.ts.
// =============================================================================

async function cfFetch(
  path: string,
  init: RequestInit & { token: string },
): Promise<{ ok: boolean; status: number; body: unknown }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), CF_TIMEOUT_MS);
  try {
    const { token, ...rest } = init;
    const res = await fetch(`${CF_API_BASE}${path}`, {
      ...rest,
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        ...(rest.headers ?? {}),
      },
      signal: controller.signal,
    });
    let body: unknown = null;
    try {
      body = await res.json();
    } catch {
      // non-JSON error body; ok stays false below
    }
    const success =
      typeof body === "object" &&
      body !== null &&
      (body as { success?: boolean }).success === true;
    return { ok: res.ok && success, status: res.status, body };
  } finally {
    clearTimeout(timer);
  }
}

function buildLiveDeps(args: {
  installationToken: string;
  cfToken: string;
  zoneId: string;
  logger: HandlerArgs["logger"];
}): ReissueDeps {
  const { installationToken, cfToken, zoneId, logger } = args;

  const octokitPages = async (): Promise<{
    state: string;
    cname: string | null;
  }> => {
    const { Octokit } = await import("@octokit/core");
    const octokit = new Octokit({ auth: installationToken });
    const res = await octokit.request("GET /repos/{owner}/{repo}/pages", {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      request: { signal: AbortSignal.timeout(GITHUB_TIMEOUT_MS) },
    });
    const data = res.data as {
      cname?: string | null;
      https_certificate?: { state?: string };
    };
    return {
      state: data.https_certificate?.state ?? "unknown",
      cname: data.cname ?? null,
    };
  };

  return {
    getPages: octokitPages,
    async setPagesCname(cname) {
      const { Octokit } = await import("@octokit/core");
      const octokit = new Octokit({ auth: installationToken });
      await octokit.request("PUT /repos/{owner}/{repo}/pages", {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        cname: cname ?? "",
        request: { signal: AbortSignal.timeout(GITHUB_TIMEOUT_MS) },
      });
    },
    async listToggleRecords() {
      const records: CfDnsRecord[] = [];
      for (const [name, type] of [
        [APEX_NAME, "A"],
        [WWW_NAME, "CNAME"],
      ] as const) {
        const res = await cfFetch(
          `/zones/${zoneId}/dns_records?name=${encodeURIComponent(name)}&type=${type}`,
          { method: "GET", token: cfToken },
        );
        // FAIL LOUD on a read failure — coalescing a failed GET to [] would let
        // restore "succeed" over a subset and leave origins exposed silently.
        if (!res.ok) {
          reportSilentFallback(
            new Error(`CF list dns_records failed: status=${res.status}`),
            {
              feature: SENTRY_FEATURE,
              op: "list-toggle-records",
              extra: { name, type, status: res.status },
            },
          );
          throw new Error(
            `CF list dns_records failed for ${name}/${type}: status=${res.status}`,
          );
        }
        const result = (res.body as { result?: CfDnsRecord[] })?.result ?? [];
        for (const r of result) {
          records.push({
            id: r.id,
            name: r.name,
            type: r.type,
            proxied: r.proxied,
          });
        }
      }
      return records;
    },
    async setRecordProxied(id, proxied) {
      const res = await cfFetch(`/zones/${zoneId}/dns_records/${id}`, {
        method: "PATCH",
        token: cfToken,
        body: JSON.stringify({ proxied }),
      });
      if (!res.ok) {
        reportSilentFallback(
          new Error(`CF PATCH proxied=${proxied} failed: status=${res.status}`),
          {
            feature: SENTRY_FEATURE,
            op: "set-record-proxied",
            extra: { recordId: id, proxied, status: res.status },
          },
        );
      }
      return res.ok;
    },
    async gatherPreconditions() {
      const dns = await import("node:dns/promises");
      const probeAcme = async (host: string): Promise<number> => {
        try {
          const c = new AbortController();
          const t = setTimeout(() => c.abort(), CF_TIMEOUT_MS);
          try {
            const r = await fetch(
              `http://${host}/.well-known/acme-challenge/reissue-preflight-probe`,
              { method: "GET", redirect: "manual", signal: c.signal },
            );
            return r.status;
          } finally {
            clearTimeout(t);
          }
        } catch {
          return -1;
        }
      };
      const [acmeApexStatus, acmeWwwStatus] = await Promise.all([
        probeAcme(APEX_NAME),
        probeAcme(WWW_NAME),
      ]);
      let caaCount = 0;
      try {
        caaCount = (await dns.resolveCaa(APEX_NAME)).length;
      } catch {
        caaCount = 0; // NODATA → no CAA restriction (permissive)
      }
      let challengeTxtPresent = false;
      try {
        const txt = await dns.resolveTxt(
          `_github-pages-challenge-${REPO_OWNER}.${APEX_NAME}`,
        );
        challengeTxtPresent = txt.length > 0;
      } catch {
        challengeTxtPresent = false;
      }
      let alwaysUseHttps = "unknown";
      try {
        const res = await cfFetch(
          `/zones/${zoneId}/settings/always_use_https`,
          { method: "GET", token: cfToken },
        );
        alwaysUseHttps =
          (res.body as { result?: { value?: string } })?.result?.value ??
          "unknown";
      } catch {
        alwaysUseHttps = "unknown";
      }
      return {
        acmeApexStatus,
        acmeWwwStatus,
        caaCount,
        challengeTxtPresent,
        alwaysUseHttps,
      };
    },
    sleep: (ms) => new Promise((r) => setTimeout(r, ms)),
    logger,
  };
}

// =============================================================================
// Terminal observability
// =============================================================================

// Benign terminal outcomes: a healthy cert (issued), a correct decline
// (not_stuck), or a not-yet-provisioned token (config_missing — the token IaC
// has not been applied). These are logged, NOT paged. Every OTHER outcome is a
// genuine remediation failure and mirrors to Sentry (→ the feature-scoped alert).
const BENIGN_OUTCOMES: ReadonlySet<ReissueOutcome> = new Set([
  "issued",
  "not_stuck",
  "config_missing",
]);

function emitTerminal(
  result: ReissueResult,
  logger: HandlerArgs["logger"],
): void {
  const extra = {
    outcome: result.outcome,
    finalState: result.finalState,
    attempts: result.attempts,
    elapsedMs: result.elapsedMs,
    proxiedStateAtExit: result.proxiedStateAtExit,
    cnameAtExit: result.cnameAtExit,
    preconditionResults: result.preconditionResults,
    detail: result.detail,
  };
  if (BENIGN_OUTCOMES.has(result.outcome)) {
    const log = result.outcome === "config_missing" ? logger.warn : logger.info;
    log({ fn: FN_ID, ...extra }, `reissue outcome=${result.outcome}`);
    return;
  }
  // Every remediation-failure terminal path mirrors to Sentry (fail-loud → the
  // gh-pages-cert-reissue-failed issue-alert fires on the `feature` tag).
  reportSilentFallback(new Error(`reissue outcome=${result.outcome}`), {
    feature: SENTRY_FEATURE,
    op: "reissue-terminal",
    message: result.detail,
    extra,
    tags: { outcome: result.outcome },
  });
}

// =============================================================================
// Handler (replay-safe: mutation in one step, poll via step.sleep, final
// restore step, onFailure handler)
// =============================================================================

/** The handler needs `step.sleep` (the poll suspension point); HandlerArgs only
 * types `step.run`, so widen it locally without mutating the shared type. */
interface ReissueHandlerArgs extends Omit<HandlerArgs, "step"> {
  step: ReissueStep;
}

export async function cronGhPagesCertReissueHandler({
  step,
  logger,
}: ReissueHandlerArgs): Promise<ReissueResult> {
  const cfToken = process.env.CF_API_TOKEN_DNS_EDIT;
  const zoneId = process.env.CF_ZONE_ID;
  if (!cfToken || !zoneId) {
    // Benign config-not-ready state: the DNS-edit token IaC has not been applied
    // yet (out-of-band JIT apply). Warn, do NOT page — nothing was mutated.
    return emitAndReturn(
      {
        outcome: "config_missing",
        finalState: "unknown",
        attempts: 0,
        elapsedMs: 0,
        proxiedStateAtExit: null,
        cnameAtExit: null,
        preconditionResults: {
          cfTokenPresent: !!cfToken,
          zoneIdPresent: !!zoneId,
        },
        detail:
          "CF_API_TOKEN_DNS_EDIT or CF_ZONE_ID not set — token IaC not yet applied",
      },
      logger,
    );
  }

  const installationToken = await step.run("mint-installation-token", () =>
    mintInstallationToken({
      tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
      permissions: REISSUE_TOKEN_PERMISSIONS,
      repositories: [REPO_NAME],
    }),
  );

  const deps = buildLiveDeps({ installationToken, cfToken, zoneId, logger });
  return runReissueSteps(step, deps, logger);
}

/**
 * onFailure: runs ONLY after retries are exhausted / the body threw (e.g. a
 * persistent Octokit error during the poll loop). The body's final restore step
 * does NOT run on a throw, so this idempotently re-asserts the declared steady
 * state. It ALWAYS pages: a body throw means the cert is still bad_authz AND the
 * DNS-only window was open — the founder must know even when the restore
 * succeeds (reissue_incomplete_restore_ok) and especially when it fails
 * (proxy_restore_failed: origin IPs exposed AND/OR the custom domain unset).
 */
export async function cronGhPagesCertReissueOnFailure({
  error,
  step,
  logger,
}: {
  error: Error;
  event: unknown;
  step: ReissueStep;
  logger: HandlerArgs["logger"];
}): Promise<void> {
  const cfToken = process.env.CF_API_TOKEN_DNS_EDIT;
  const zoneId = process.env.CF_ZONE_ID;
  if (!cfToken || !zoneId) {
    reportSilentFallback(error, {
      feature: SENTRY_FEATURE,
      op: "onfailure-restore",
      message: "onFailure could not restore: CF token/zone missing",
      tags: { outcome: "proxy_restore_failed" },
    });
    return;
  }
  try {
    const installationToken = await step.run("onfailure-mint-token", () =>
      mintInstallationToken({
        tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
        permissions: REISSUE_TOKEN_PERMISSIONS,
        repositories: [REPO_NAME],
      }),
    );
    const deps = buildLiveDeps({ installationToken, cfToken, zoneId, logger });
    await step.run("onfailure-restore-steady-state", () => restoreState(deps));
    // Restore succeeded, but the remediation itself did NOT complete (the body
    // threw). Page so a retries-exhausted throw is never silent.
    reportSilentFallback(error, {
      feature: SENTRY_FEATURE,
      op: "onfailure-restore",
      message: `reissue body failed after retries; steady state restored: ${error.message}`,
      tags: { outcome: "reissue_incomplete_restore_ok" },
    });
  } catch (restoreErr) {
    // The security-regression brake: restore itself failed.
    reportSilentFallback(restoreErr, {
      feature: SENTRY_FEATURE,
      op: "onfailure-restore",
      message: `onFailure restore FAILED after body error: ${error.message}`,
      tags: { outcome: "proxy_restore_failed" },
    });
  }
}

// =============================================================================
// Registration
// =============================================================================

export const cronGhPagesCertReissue = inngest.createFunction(
  {
    id: FN_ID,
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
    onFailure: cronGhPagesCertReissueOnFailure as unknown as Parameters<
      typeof inngest.createFunction
    >[0]["onFailure"],
  },
  [{ event: "cron/gh-pages-cert-reissue.manual-trigger" }],
  cronGhPagesCertReissueHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
