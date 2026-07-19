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
//      via the GitHub App's `administration:write`+`pages:write` grants (PUT /pages
//      needs BOTH),
//   3. poll GET /pages until state ∈ {approved, issued},
//   4. restore the declared steady state (proxied=true, cname=soleur.ai).
//
// Replay-safety (ADR-077, ADR-033): the toggle+reissue mutation lives in ONE
// step.run (so a step retry is the only thing that re-orders the cert); the poll
// and the DNS-propagation gate suspend via step.sleep (#6698 added the gate's
// `dns-gate-wait-${i}` sleeps, so the poll is NO LONGER the only suspension
// point — the ADR-125 text and this comment were corrected together); restore is
// an UNCONDITIONAL final step PLUS an `onFailure` lifecycle handler (idempotent)
// — a JS `try…finally` is WRONG here because step.sleep suspends via a
// control-flow throw that would run `finally` prematurely at the first
// suspension. That reasoning is unchanged by the added sleeps: there is still no
// `finally`. There is no in-repo `onFailure` precedent; the config key is
// verified against pinned inngest 3.54.2.
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
  emitCertReissueMarker,
  type CertReissueMarker,
  type CertReissuePhase,
} from "@/server/cert-reissue-marker";
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
//
// ‼️ A COUNT CANNOT PROTECT AGAINST A RECORD *TYPE* THAT WAS NEVER IN dns.tf
// (#6698). This asserts the toggle set matches the five records Terraform
// declares, but `listToggleRecords` only queries `type=A` (apex) + `type=CNAME`
// (www) — so an AAAA (or any other type) added to the live zone out-of-band
// would survive the DNS-only flip entirely and this count would still read 5.
// That matters because Let's Encrypt PREFERS AAAA and its IPv4 fallback fires
// only on a network-level failure, never on a proxied AAAA that answers 200 with
// the wrong content — so a surviving AAAA defeats validation at ANY window
// length. Verified 2026-07-19 via `GET /zones/{id}/dns_records?type=AAAA`: zero
// AAAA records in the zone (the AAAA public resolvers return is Cloudflare's
// synthetic proxy answer, which `proxied=false` removes). Broadening this to a
// type-aware assertion is tracked as a follow-up. Compare the parallel drift
// class in 2026-04-03-cloudflare-dns-at-symbol-causes-terraform-drift.md.
export const EXPECTED_TOGGLE_RECORDS = 5;

// Preflight allowlist: only a genuinely-stuck cert is touched. Toggling a
// healthy in-flight order (authorization_pending / dns_changed / new) can
// MANUFACTURE a new bad_authz — hence an allowlist, not a denylist.
//
// Per the Pages REST API docs the terminal FAILURE states are `errored`,
// `bad_authz`, and `authorization_revoked`; `"failed"` is NOT a documented state
// (#6698 / RI-3). A cert stuck in `errored` or `authorization_revoked` was
// previously declined as `not_stuck` and never remediated. `"failed"` is kept
// defensively — it costs nothing and guards against an undocumented value the
// API may still emit.
export const REISSUE_ALLOWED_STATES = [
  "bad_authz",
  "errored",
  "authorization_revoked",
  "failed",
] as const;

// GitHub App installation-token lifetime floor (a handful of admin calls).
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

// Least-privilege scope: the reissue calls GET + PUT /repos/{owner}/{repo}/pages
// (the Pages site-config endpoint). PUT /pages (the cname toggle) requires BOTH
// `administration:write` AND `pages:write` — NEITHER alone is sufficient. Verified
// empirically on the live jikig-ai/soleur installation (#6657): a token with only
// pages:write → 403, only administration:write → 403, both → 204. (GitHub's REST
// docs do not surface the fine-grained requirement for this endpoint, so this was
// confirmed by direct token-minting probes, not the docs.) repositories:["soleur"]
// + a 15-min TTL bound the blast radius to one repo.
const REISSUE_TOKEN_PERMISSIONS: Record<string, string> = {
  administration: "write",
  pages: "write",
};

// ============================ DNS-only window budget =========================
// EVERY millisecond below is public-TLS-outage time. During the DNS-only window
// apex+www serve GitHub's bad_authz certificate directly, so every HTTPS visitor
// to the marketing site gets a browser interstitial and the Cloudflare edge
// (Always-Use-HTTPS, WAF, bot management) is bypassed on those hostnames. The
// cost scales LINEARLY with window length — which is why #6698 did NOT lengthen
// it despite the poll being the suspected culprit.
//
// ‼️ BUDGET THE WHOLE WINDOW, NOT JUST THE POLL. The real wall clock is
// poll + CNAME_SETTLE_MS + the propagation gate. Asserting POLL_MAX_MS alone
// passes while the true outage overruns — it already did, by CNAME_SETTLE_MS.
export const MAX_DNS_ONLY_WINDOW_MS = 15 * 60 * 1000;

const POLL_INTERVAL_MS = 60 * 1000;
const CNAME_SETTLE_MS = 45 * 1000; // between cname:null and re-set

// Propagation gate (#6698). Cloudflare's TTL for proxied records is fixed at
// 300 s, so a proxy-status flip takes ~5-10 min to reach recursive resolvers.
// The gate measures that rather than assuming it: a poll that starts before
// propagation completes is guaranteed-wasted window.
export const DNS_GATE_MAX_ATTEMPTS = 5;
const DNS_GATE_INTERVAL_MS = 30 * 1000;
// The loop skips the trailing sleep, so the budget is (attempts-1)*interval.
const DNS_GATE_BUDGET_MS = (DNS_GATE_MAX_ATTEMPTS - 1) * DNS_GATE_INTERVAL_MS;

// The gate's budget comes OUT of the poll's, not on top of it (#6698 Phase 2.6).
const POLL_BUDGET_MS =
  MAX_DNS_ONLY_WINDOW_MS - CNAME_SETTLE_MS - DNS_GATE_BUDGET_MS;
// Fixed poll count for the replay-safe handler loop (deterministic across
// resumes — NOT a wall-clock bound in the body). The loop skips the trailing
// sleep, so the effective poll window is (MAX_POLLS-1)*POLL_INTERVAL_MS.
const MAX_POLLS = Math.floor(POLL_BUDGET_MS / POLL_INTERVAL_MS) + 1;

/**
 * The REAL public-TLS-outage window: poll + cname settle + propagation gate.
 * Exported so a test asserts the SUM against `MAX_DNS_ONLY_WINDOW_MS` (AC13) —
 * pinning any single component would let the total drift past 15 minutes.
 */
export const TOTAL_DNS_ONLY_WINDOW_MS =
  (MAX_POLLS - 1) * POLL_INTERVAL_MS + CNAME_SETTLE_MS + DNS_GATE_BUDGET_MS;
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
  | "config_missing"
  // #6698: the DNS-only flip never reached public resolvers as GitHub's
  // 185.199.x within budget (or an AAAA survived it). NOT benign — a poll run
  // against an unpropagated zone is guaranteed-wasted outage window.
  | "dns_propagation_failed"
  // #6698: a probe-only fire completed. Benign by construction — it deliberately
  // does NOT remediate, so it must be distinguishable from both `issued` (which
  // would read as "fixed") and `poll_timeout` (which would page).
  | "probe_only_complete";

export interface ReissueResult {
  outcome: ReissueOutcome;
  finalState: string;
  attempts: number;
  elapsedMs: number;
  proxiedStateAtExit: boolean | null;
  cnameAtExit: string | null;
  preconditionResults?: Record<string, boolean>;
  detail: string;
  // Lands in emitTerminal's `extra` → the Sentry payload AND the
  // `public.routine_runs` row written by runLogMiddleware. Without it the
  // operator-facing routine-run history shows a run that "completed" with no
  // indication it was only a probe.
  probeOnly: boolean;
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
 * RAW observations of the post-flip DNS state, read from PUBLIC resolvers
 * (1.1.1.1 / 8.8.8.8) — not the container's resolver, which may be cached or
 * split-horizon. Pure observations only; all policy lives in
 * `checkDnsPropagated`, mirroring the existing
 * `gatherPreconditions` → `checkReissuePreconditions` split.
 */
export interface DnsPropagationInputs {
  /** Apex A-record answers from the public resolvers. */
  resolved4: string[];
  /** Apex AAAA answers. MUST be empty — see checkDnsPropagated. */
  resolved6: string[];
  /** The resolve6 error code (`ENODATA` is the PASS condition), or null. */
  resolve6Error: string | null;
  /**
   * HTTP status of an ACME HTTP-01-shaped probe re-run POST-flip.
   * `gatherPreconditions` already probes this, but at PREFLIGHT while records
   * are still proxied — so it measures the proxied path and says nothing about
   * the DNS-only state. Resolver answers alone only test two resolvers' caches,
   * not what Let's Encrypt will actually reach.
   */
  acmeApexStatus: number;
  acmeWwwStatus: number;
  /** Whether the post-flip ACME response looks like GitHub's, not Cloudflare's. */
  acmeGithubShaped: boolean;
}

export type DnsPropagationVerdict =
  | { status: "propagated"; reason: string }
  | { status: "retry"; reason: string }
  | { status: "failed"; reason: string };

/** GitHub Pages public anycast lives in 185.199.0.0/16. */
function isGitHubPagesV4(addr: string): boolean {
  const octets = addr.split(".");
  return octets.length === 4 && octets[0] === "185" && octets[1] === "199";
}

/**
 * Decide whether the DNS-only flip has reached public resolvers. PURE — no IO,
 * so the four cases are directly unit-testable rather than requiring a fake
 * network (AC8).
 *
 * `retry` means "not yet, and waiting may help". `failed` means "waiting cannot
 * help" and is reserved for the AAAA case: a record that survives the flip will
 * still be there next attempt, so burning the remaining budget on it only
 * lengthens a public TLS outage.
 */
export function checkDnsPropagated(
  inputs: DnsPropagationInputs,
): DnsPropagationVerdict {
  // H-W4 — an AAAA that survives the DNS-only flip is terminal, not transient.
  // Let's Encrypt PREFERS IPv6 and retries over IPv4 only when the IPv6
  // connection fails at the NETWORK level (timeout/refused), and only on the
  // first request of a validation — redirects get no retry. A Cloudflare-proxied
  // AAAA answers successfully with the WRONG content, so there is no fallback at
  // all and validation fails silently at any window length.
  if (inputs.resolved6.length > 0) {
    return {
      status: "failed",
      reason:
        `AAAA still resolves after the DNS-only flip (${inputs.resolved6.join(", ")}) — ` +
        `Let's Encrypt prefers IPv6 and will not fall back, so no window length can succeed. ` +
        `Fix the zone (the toggle set covers only A + CNAME) before remediating.`,
    };
  }

  if (inputs.resolved4.length === 0) {
    return { status: "retry", reason: "no A-record answer yet" };
  }

  const notGitHub = inputs.resolved4.filter((a) => !isGitHubPagesV4(a));
  if (notGitHub.length > 0) {
    return {
      status: "retry",
      reason: `A-records not yet GitHub anycast (${notGitHub.join(", ")}) — still Cloudflare or mid-propagation`,
    };
  }

  // Resolver answers can be right while something still intercepts the challenge
  // path (a residual redirect or CF rule). This is the single most informative
  // observation available, so it gates too.
  if (!inputs.acmeGithubShaped) {
    return {
      status: "retry",
      reason:
        `A-records are GitHub anycast but the ACME probe is not GitHub-shaped ` +
        `(apex=${inputs.acmeApexStatus}, www=${inputs.acmeWwwStatus}) — challenge path may be intercepted`,
    };
  }

  return {
    status: "propagated",
    reason: `public resolvers return GitHub anycast (${inputs.resolved4.join(", ")}), no AAAA, ACME path GitHub-shaped`,
  };
}

/**
 * All live IO is injected so the orchestration is testable without a network.
 * The Inngest handler supplies real implementations (Octokit + CF fetch); the
 * unit tests supply fakes and drive `runReissueSteps` — the SAME function that
 * runs in production (no parallel/dead twin).
 */
export interface ReissueDeps {
  getPages(): Promise<PagesSnapshot>;
  setPagesCname(cname: string | null): Promise<void>;
  listToggleRecords(): Promise<CfDnsRecord[]>;
  setRecordProxied(id: string, proxied: boolean): Promise<boolean>;
  gatherPreconditions(): Promise<PreconditionInputs>;
  /** Raw post-flip DNS observations (#6698). Policy lives in checkDnsPropagated. */
  gatherDnsPropagation(): Promise<DnsPropagationInputs>;
  sleep(ms: number): Promise<void>;
  logger: HandlerArgs["logger"];
}

/**
 * What a `GET /pages` read yields. The full `https_certificate` object is
 * captured (not just `state`) because `description` is the ONLY in-band field
 * that has ever carried Let's Encrypt-side detail — it is the sole candidate
 * signal for separating "window too short" from "LE rate-limiting", which
 * `state` alone cannot distinguish (both stay flat at `bad_authz`).
 */
export interface PagesSnapshot {
  state: string;
  cname: string | null;
  description?: string | null;
  domains?: string[] | null;
  expiresAt?: string | null;
  protectedDomainState?: string | null;
  pendingDomainUnverifiedAt?: string | null;
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
    // Block ONLY on an explicit "on" — NOT on "unknown". Reading always_use_https
    // needs Zone.Zone Settings:Read, which the least-privilege DNS-edit-only token
    // (CF_API_TOKEN_DNS_EDIT) intentionally lacks, so gatherPreconditions coalesces
    // a 403 to "unknown". `acmeApexCarveout`/`acmeWwwCarveout` (the ACME path returns
    // 404, not a 301 redirect) is the AUTHORITATIVE redirect-interception signal —
    // always_use_https="on" would force those to 301 and fail the carve-out check
    // anyway — so an unreadable setting must not block. #6657 live-run: the DNS-only
    // token made this precondition false with `=== "off"` and blocked the remediation.
    alwaysUseHttpsOff: inputs.alwaysUseHttps !== "on",
  };
  const failed = Object.entries(results)
    .filter(([, ok]) => !ok)
    .map(([k]) => k);
  return { ok: failed.length === 0, results, failed };
}

// =============================================================================
// IO orchestration (async, deps-injected)
// =============================================================================

// =============================================================================
// Marker plumbing (#6698)
// =============================================================================

/**
 * Run-scoped correlation context. `runId` and `attempt` are THREADED from
 * `HandlerArgs`, never self-derived: a hardcoded `attempt: 0` would satisfy a
 * type-level assertion while carrying no information, and without `runId` a
 * `--since 30m` Better Stack window is satisfied by rows from any earlier fire.
 */
export interface ReissueRunContext {
  probeOnly: boolean;
  runId: string | null;
  attempt: number | null;
}

export type MarkerEmitter = (
  phase: CertReissuePhase,
  fields?: Partial<CertReissueMarker>,
) => void;

const noopEmitter: MarkerEmitter = () => {};

function makeEmitter(ctx: ReissueRunContext): MarkerEmitter {
  return (phase, fields = {}) =>
    emitCertReissueMarker({
      phase,
      runId: ctx.runId,
      attempt: ctx.attempt,
      probeOnly: ctx.probeOnly,
      ...fields,
    });
}

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

/**
 * Re-order the cert: PUT cname:null → settle → PUT cname:soleur.ai.
 *
 * ‼️ EVERY CALL CONSUMES A LET'S ENCRYPT VALIDATION ATTEMPT. LE allows 5
 * authorization failures per identifier per account per hour, refilling at 1 per
 * 12 min with a compounding daily cap; exceeding it pauses issuance until
 * manually unpaused. GitHub surfaces NONE of this — the cert simply stays
 * `bad_authz`, indistinguishable from every other cause. This is why probe-only
 * mode exists and why it must never reach this function.
 *
 * ‼️ LATENT DOUBLE-FIRE (pre-existing, documented so the next reader can count
 * it): if `restoreState` inside `toggle-reissue`'s catch throws, the whole step
 * throws, `retries: 1` re-runs the ENTIRE toggle+reissue unit, and a SECOND
 * cname re-order consumes a second validation attempt. Nobody has ever counted
 * these, and they are a live contributor to the rate-limit hypothesis. The
 * `cname-put-null` / `cname-put-set` markers make them countable going forward:
 * more than one pair per runId is a double-fire.
 */
export async function reissueViaCnameToggle(
  deps: ReissueDeps,
  emit: MarkerEmitter = noopEmitter,
): Promise<void> {
  emit("cname-put-null", { cname: null });
  await deps.setPagesCname(null);
  await deps.sleep(CNAME_SETTLE_MS);
  emit("cname-put-set", { cname: PAGES_CNAME });
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
export async function restoreState(
  deps: ReissueDeps,
  emit: MarkerEmitter = noopEmitter,
): Promise<void> {
  try {
    await restoreStateInner(deps, emit);
  } catch (err) {
    // ‼️ Emit from the RETHROWING catch too. restoreState is fail-loud, so a
    // marker emitted only after it returns means a throwing restore emits
    // NOTHING — and "restore never attempted" becomes indistinguishable from
    // "restore attempted and failed", which is the worse of the two states and
    // the one that leaves the public site on a broken cert.
    emit("restore", {
      ok: false,
      errorName: (err as Error).name,
      errorDetail: (err as Error).message,
    });
    throw err;
  }
}

async function restoreStateInner(
  deps: ReissueDeps,
  emit: MarkerEmitter,
): Promise<void> {
  const records = await deps.listToggleRecords();
  // Emit on ENTRY with the observed state, before any write.
  emit("restore", {
    ok: null,
    recordCount: records.length,
    proxiedCount: records.filter((r) => r.proxied).length,
    detail: "restore entry",
  });
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
  // Emit on OUTCOME — the converged steady state, proven by the re-read above.
  emit("restore", {
    ok: true,
    recordCount: after.length,
    proxiedCount: after.filter((r) => r.proxied).length,
    cname: pagesAfter.cname,
    detail: "restore converged",
  });
}

// =============================================================================
// Production orchestration (injectable step + deps → directly testable)
// =============================================================================

function emitAndReturn(
  result: ReissueResult,
  logger: HandlerArgs["logger"],
  ctx: ReissueRunContext,
): ReissueResult {
  emitTerminal(result, logger, ctx);
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
  ctx: ReissueRunContext,
): Promise<ReissueResult> {
  const emit = makeEmitter(ctx);
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
      emit("preflight", {
        certState: pages.state,
        cname: pages.cname,
        ok: false,
        detail: gate.reason,
      });
      return {
        status: "not_stuck" as const,
        state: pages.state,
        reason: gate.reason,
      };
    }
    // ‼️ AC11b — probe-only ABORTS LOUDLY on a wrong cname rather than letting
    // `restoreState` silently repair it. restoreState legitimately re-asserts
    // the cname when `pages.cname !== PAGES_CNAME` (a correct, symmetric
    // contract), but on a probe-only fire against the `cname:null` state a prior
    // failed fire left behind, that re-assert would issue a real PUT /pages,
    // re-order the cert, and consume a Let's Encrypt validation attempt — the
    // ONE thing probe-only exists to avoid. Blocking here is the only place that
    // distinguishes "repair" from "probe".
    if (ctx.probeOnly && pages.cname !== PAGES_CNAME) {
      const reason =
        `probe-only refused: live cname=${pages.cname} (expected ${PAGES_CNAME}). ` +
        `Restoring it would issue a real PUT /pages and consume an LE validation ` +
        `attempt. Fix steady state first, then re-probe.`;
      emit("preflight", {
        certState: pages.state,
        cname: pages.cname,
        ok: false,
        detail: reason,
      });
      return {
        status: "blocked" as const,
        state: pages.state,
        results: { probeOnlyCnameSteady: false },
        failed: ["probeOnlyCnameSteady"],
        reason,
      };
    }
    const preCheck = checkReissuePreconditions(await deps.gatherPreconditions());
    emit("preflight", {
      certState: pages.state,
      certDescription: pages.description ?? null,
      cname: pages.cname,
      ok: preCheck.ok,
      detail: preCheck.ok
        ? "preconditions ok"
        : `preconditions failed: ${preCheck.failed.join(", ")}`,
    });
    if (!preCheck.ok) {
      return {
        status: "blocked" as const,
        state: pages.state,
        results: preCheck.results,
        failed: preCheck.failed,
        reason: `preconditions failed: ${preCheck.failed.join(", ")}`,
      };
    }
    return {
      status: "ok" as const,
      state: pages.state,
      results: preCheck.results,
    };
  });

  // ---- PRE-TOGGLE returns. Nothing has been mutated, so no restore is owed. --
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
        probeOnly: ctx.probeOnly,
      },
      logger,
      ctx,
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
        detail: pre.reason,
        probeOnly: ctx.probeOnly,
      },
      logger,
      ctx,
    );
  }

  // ‼️ Capture the pre-flip DNS baseline in its OWN step, BEFORE toggle-reissue.
  // Without a reading of the DNS state before the flip, propagation-delay is
  // indistinguishable from never-propagated. It cannot live inside
  // `toggle-reissue`: a step RETRY would re-read the "pre-flip" baseline AFTER
  // the first flip already happened, producing a misleading baseline on exactly
  // the retry path that most needs a true one.
  await step.run("capture-pre-flip-dns", async () => {
    const dns = await deps.gatherDnsPropagation();
    emit("pre-flip-dns", {
      resolved4: dns.resolved4,
      resolved6: dns.resolved6,
      resolve6Error: dns.resolve6Error,
      acmeApexStatus: dns.acmeApexStatus,
      acmeWwwStatus: dns.acmeWwwStatus,
      acmeGithubShaped: dns.acmeGithubShaped,
      detail: "baseline before the DNS-only flip",
    });
    return dns;
  });

  // Atomic toggle + reissue (ONE step.run): a step retry re-runs the whole
  // mutating unit (bounded by retries:1), never a half-applied window.
  //
  // In probe-only mode this performs the DNS flip but NOT the cname toggle, so
  // it opens the measurement window without consuming an LE validation attempt.
  const toggle = await step.run("toggle-reissue", async () => {
    try {
      const records = await deps.listToggleRecords();
      await setRecordsProxied(deps, records, false);
      emit("flip-dns-only", {
        recordCount: records.length,
        proxiedCount: 0,
        ok: true,
        detail: "toggle set flipped to proxied=false",
      });
      if (!ctx.probeOnly) {
        await reissueViaCnameToggle(deps, emit);
      }
      return { ok: true as const };
    } catch (err) {
      // Restore inside this step so a same-step abort is self-contained.
      await restoreState(deps, emit);
      return {
        ok: false as const,
        message: (err as Error).message,
        httpStatus:
          err instanceof PartialToggleError ? "partial-toggle" : "cname-put",
      };
    }
  });

  // ===========================================================================
  // POST-TOGGLE. From here to the single `return` at the bottom, every exit is
  // preceded by a restore — either the IN-STEP one above (the !toggle.ok path)
  // or the `restore-steady-state` body step below.
  //
  // ‼️ There is exactly ONE post-toggle return site, and it is after the restore
  // step. This is STRUCTURAL, not test-enforced: a universal claim ("no
  // post-toggle return bypasses restore") cannot be proven by driving one path,
  // so the code is shaped to make it true by construction. `onFailure` does NOT
  // fire on a clean early `return` — only on a throw or exhausted retries — so a
  // returned-early post-toggle path would leave the public marketing site on a
  // broken cert indefinitely with nothing to catch it.
  //
  // ‼️ The !toggle.ok path deliberately does NOT get a second body-level
  // restore. It is already safe via the in-step `restoreState` above. Adding one
  // would be idempotent but HARMFUL: if the second restore threw, the body would
  // throw, `onFailure` would fire, and the precise `reissue_failed` diagnostic
  // would be overwritten by a generic restore outcome.
  // ===========================================================================
  let result: ReissueResult;

  if (!toggle.ok) {
    result = {
      outcome: "reissue_failed",
      finalState: pre.state,
      attempts: 0,
      elapsedMs: elapsed(),
      proxiedStateAtExit: null,
      cnameAtExit: null,
      preconditionResults: pre.results,
      detail: `reissue trigger failed (${toggle.httpStatus}): ${toggle.message}`,
      probeOnly: ctx.probeOnly,
    };
  } else {
    // ---- DNS-propagation gate. Fixed-count step names over a constant so the
    // ids are deterministic across replays (inngest hashes step ids with SHA1
    // and matches by hash, not position, so inserting steps before the poll loop
    // does NOT invalidate later steps' memoization — a wall-clock-derived
    // counter is the one thing that would break that).
    let verdict: DnsPropagationVerdict = {
      status: "retry",
      reason: "gate not yet run",
    };
    for (let i = 0; i < DNS_GATE_MAX_ATTEMPTS; i++) {
      verdict = await step.run(`dns-gate-${i}`, async () => {
        const inputs = await deps.gatherDnsPropagation();
        const v = checkDnsPropagated(inputs);
        emit("dns-propagation", {
          pollIndex: i,
          resolved4: inputs.resolved4,
          resolved6: inputs.resolved6,
          resolve6Error: inputs.resolve6Error,
          acmeApexStatus: inputs.acmeApexStatus,
          acmeWwwStatus: inputs.acmeWwwStatus,
          acmeGithubShaped: inputs.acmeGithubShaped,
          ok: v.status === "propagated",
          outcome: v.status,
          detail: v.reason,
          elapsedMs: elapsed(),
        });
        return v;
      });
      // `failed` is terminal (a surviving AAAA will still be there next
      // attempt); `propagated` is done. Only `retry` keeps waiting.
      if (verdict.status !== "retry") break;
      // The fixed count is the upper bound; wall-clock is the real ceiling.
      if (elapsed() + DNS_GATE_INTERVAL_MS >= TOTAL_DNS_ONLY_WINDOW_MS) break;
      if (i < DNS_GATE_MAX_ATTEMPTS - 1) {
        await step.sleep(`dns-gate-wait-${i}`, `${DNS_GATE_INTERVAL_MS}ms`);
      }
    }

    if (verdict.status !== "propagated") {
      result = {
        outcome: "dns_propagation_failed",
        finalState: pre.state,
        attempts: 0,
        elapsedMs: elapsed(),
        proxiedStateAtExit: STEADY_PROXIED,
        cnameAtExit: PAGES_CNAME,
        preconditionResults: pre.results,
        detail: `DNS-only state never propagated: ${verdict.reason}`,
        probeOnly: ctx.probeOnly,
      };
    } else if (ctx.probeOnly) {
      // ‼️ Probe-only runs ZERO polls. The poll exists to watch a cert re-order
      // that probe-only deliberately never triggered, so running it would hold
      // apex+www on GitHub's bad_authz cert for ~12 more minutes for nothing —
      // the exact public-TLS cost that justifies refusing to lengthen the
      // window. Restore as soon as the gate returns a verdict.
      result = {
        outcome: "probe_only_complete",
        finalState: pre.state,
        attempts: 0,
        elapsedMs: elapsed(),
        proxiedStateAtExit: STEADY_PROXIED,
        cnameAtExit: PAGES_CNAME,
        preconditionResults: pre.results,
        detail: `probe-only: ${verdict.reason}`,
        probeOnly: true,
      };
    } else {
      // Poll (step.sleep suspends). Fixed count → deterministic step names.
      let attempts = 0;
      let finalState = "unknown";
      let healthy = false;
      for (let i = 0; i < MAX_POLLS; i++) {
        const pages = await step.run(`poll-${i}`, async () => {
          const p = await deps.getPages();
          // Capture the ENTIRE https_certificate object, not just `state`.
          // `description` is the only in-band field that has ever carried
          // Let's Encrypt-side detail, and an ADVANCING state trajectory
          // (authorization_pending → authorized) versus a FLAT one is the only
          // other available signal for separating "window too short" from
          // "LE is rate-limiting us" — which `state` alone cannot do.
          emit("poll", {
            pollIndex: i,
            certState: p.state,
            certDescription: p.description ?? null,
            certDomains: p.domains ?? null,
            certExpiresAt: p.expiresAt ?? null,
            protectedDomainState: p.protectedDomainState ?? null,
            pendingDomainUnverifiedAt: p.pendingDomainUnverifiedAt ?? null,
            cname: p.cname,
            elapsedMs: elapsed(),
          });
          return p;
        });
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

      result = {
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
        probeOnly: false,
      };
    }

    // Unconditional restore for every toggle-ok path (issued, poll_timeout,
    // dns_propagation_failed, probe_only_complete).
    await step.run("restore-steady-state", () => restoreState(deps, emit));
  }

  return emitAndReturn(result, logger, ctx);
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

  const octokitPages = async (): Promise<PagesSnapshot> => {
    const { Octokit } = await import("@octokit/core");
    const octokit = new Octokit({ auth: installationToken });
    const res = await octokit.request("GET /repos/{owner}/{repo}/pages", {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      request: { signal: AbortSignal.timeout(GITHUB_TIMEOUT_MS) },
    });
    const data = res.data as {
      cname?: string | null;
      protected_domain_state?: string | null;
      pending_domain_unverified_at?: string | null;
      https_certificate?: {
        state?: string;
        description?: string | null;
        domains?: string[] | null;
        expires_at?: string | null;
      };
    };
    // The whole certificate object is carried through — `description` is the only
    // in-band Let's Encrypt-side signal available (RI-7).
    return {
      state: data.https_certificate?.state ?? "unknown",
      cname: data.cname ?? null,
      description: data.https_certificate?.description ?? null,
      domains: data.https_certificate?.domains ?? null,
      expiresAt: data.https_certificate?.expires_at ?? null,
      protectedDomainState: data.protected_domain_state ?? null,
      pendingDomainUnverifiedAt: data.pending_domain_unverified_at ?? null,
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
    // ‼️ REAL implementation, not a stub. The gate's type member, its step, and
    // its fakes can all be present and `tsc`-clean while the production path
    // never runs the gate — the "parallel/dead twin" this file's docstring
    // forbids. AC8b asserts this is constructed here.
    async gatherDnsPropagation(): Promise<DnsPropagationInputs> {
      // `dig` is NOT installed in the app image (Dockerfile installs only
      // ca-certificates git bubblewrap socat qpdf jq), so shelling out would
      // throw at runtime. node:dns's Resolver is core Node, no dependency.
      const { Resolver } = await import("node:dns/promises");
      const resolver = new Resolver({ timeout: CF_TIMEOUT_MS, tries: 2 });
      // PUBLIC resolvers, not the container's — the container's answer may be
      // cached or split-horizon and says nothing about what Let's Encrypt sees.
      resolver.setServers(["1.1.1.1", "8.8.8.8"]);

      let resolved4: string[] = [];
      try {
        resolved4 = await resolver.resolve4(APEX_NAME);
      } catch {
        resolved4 = [];
      }
      let resolved6: string[] = [];
      let resolve6Error: string | null = null;
      try {
        resolved6 = await resolver.resolve6(APEX_NAME);
      } catch (err) {
        // ENODATA / ENOTFOUND is the PASS condition here.
        resolved6 = [];
        resolve6Error = (err as { code?: string }).code ?? "unknown";
      }

      // Re-run the ACME-shaped probe POST-flip. gatherPreconditions already
      // probes this, but at preflight while records are still proxied — so it
      // measures the proxied path, not the DNS-only one.
      const probe = async (
        host: string,
      ): Promise<{ status: number; server: string }> => {
        try {
          const c = new AbortController();
          const t = setTimeout(() => c.abort(), CF_TIMEOUT_MS);
          try {
            const r = await fetch(
              `http://${host}/.well-known/acme-challenge/reissue-propagation-probe`,
              { method: "GET", redirect: "manual", signal: c.signal },
            );
            return { status: r.status, server: r.headers.get("server") ?? "" };
          } finally {
            clearTimeout(t);
          }
        } catch {
          return { status: -1, server: "" };
        }
      };
      const [apex, www] = await Promise.all([
        probe(APEX_NAME),
        probe(WWW_NAME),
      ]);
      // The `Server` header is the actual discriminator: GitHub Pages answers
      // `GitHub.com`, Cloudflare answers `cloudflare`. Status alone does not
      // separate them — CF can proxy through GitHub's own 404.
      const shaped = (s: string) =>
        s.toLowerCase().includes("github") &&
        !s.toLowerCase().includes("cloudflare");

      return {
        resolved4,
        resolved6,
        resolve6Error,
        acmeApexStatus: apex.status,
        acmeWwwStatus: www.status,
        acmeGithubShaped: shaped(apex.server) && shaped(www.server),
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
export const BENIGN_OUTCOMES: ReadonlySet<ReissueOutcome> = new Set([
  "issued",
  "not_stuck",
  "config_missing",
  // A probe-only fire that completed did exactly its job. It must NOT page
  // (that would spuriously alert on a successful run) and must NOT read as
  // `issued` (that would silently look remediated — the false-resolved state
  // #6698 exists to eliminate).
  "probe_only_complete",
]);

function emitTerminal(
  result: ReissueResult,
  logger: HandlerArgs["logger"],
  ctx: ReissueRunContext,
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
    probeOnly: result.probeOnly,
  };

  // ‼️ THE HEADLINE FIX. Emit the terminal marker for EVERY outcome, before the
  // benign/paging split below. Benign outcomes route through `logger.info`, and
  // BOTH gates hold on that path (ProxyLogger.enabled is false outside an
  // executing step; Vector drops pino INFO) — so without this line the `issued`
  // terminal, the very success path #6698 calls "observationally dark", stays
  // dark even after every other marker in this file is added. This is additive:
  // the logger + Sentry calls below are unchanged.
  emitCertReissueMarker({
    phase: "terminal",
    runId: ctx.runId,
    attempt: ctx.attempt,
    probeOnly: result.probeOnly,
    outcome: result.outcome,
    certState: result.finalState,
    cname: result.cnameAtExit,
    elapsedMs: result.elapsedMs,
    ok: BENIGN_OUTCOMES.has(result.outcome),
    detail: result.detail,
  });

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

/**
 * Read `probeOnly` off the triggering event.
 *
 * ‼️ DEFAULT IS PROBE-ONLY (safe default). Remediation requires an EXPLICIT
 * `{"probeOnly": false}`. The asymmetry is deliberate: every remediation fire
 * consumes a Let's Encrypt validation attempt against limits that are hourly and
 * COMPOUNDING, and a fire made without knowing whether DNS even propagated is a
 * blind attempt that deepens rate-limit state while discriminating nothing. A
 * probe costs one short window and answers the question.
 */
export function resolveProbeOnly(event: unknown): boolean {
  const data = (event as { data?: unknown } | undefined)?.data;
  if (typeof data !== "object" || data === null) return true;
  const flag = (data as { probeOnly?: unknown }).probeOnly;
  return typeof flag === "boolean" ? flag : true;
}

export async function cronGhPagesCertReissueHandler({
  step,
  logger,
  event,
  attempt,
  runId,
}: ReissueHandlerArgs): Promise<ReissueResult> {
  const ctx: ReissueRunContext = {
    probeOnly: resolveProbeOnly(event),
    // Threaded from HandlerArgs, never self-derived.
    runId: runId ?? null,
    attempt: attempt ?? null,
  };
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
        probeOnly: ctx.probeOnly,
      },
      logger,
      ctx,
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
  return runReissueSteps(step, deps, logger, ctx);
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
  event,
  runId,
  attempt,
}: {
  error: Error;
  event: unknown;
  step: ReissueStep;
  logger: HandlerArgs["logger"];
  runId?: string;
  attempt?: number;
}): Promise<void> {
  // ‼️ This handler is NOT part of runReissueSteps, so it needs its own emitter.
  // Without markers here a body throw is Sentry-visible but marker-dark —
  // exactly the asymmetry #6698 exists to fix, and indistinguishable from
  // "telemetry is broken". Emitted from BOTH branches of the try/catch below.
  const ctx: ReissueRunContext = {
    probeOnly: resolveProbeOnly(event),
    runId: runId ?? null,
    attempt: attempt ?? null,
  };
  const emit = makeEmitter(ctx);
  const cfToken = process.env.CF_API_TOKEN_DNS_EDIT;
  const zoneId = process.env.CF_ZONE_ID;
  if (!cfToken || !zoneId) {
    emit("onfailure-restore", {
      ok: false,
      outcome: "proxy_restore_failed",
      detail: "onFailure could not restore: CF token/zone missing",
      errorName: error.name,
      errorDetail: error.message,
    });
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
    await step.run("onfailure-restore-steady-state", () =>
      restoreState(deps, emit),
    );
    // Restore succeeded, but the remediation itself did NOT complete (the body
    // threw). Page so a retries-exhausted throw is never silent.
    emit("onfailure-restore", {
      ok: true,
      outcome: "reissue_incomplete_restore_ok",
      detail: `reissue body failed after retries; steady state restored: ${error.message}`,
      errorName: error.name,
      errorDetail: error.message,
    });
    reportSilentFallback(error, {
      feature: SENTRY_FEATURE,
      op: "onfailure-restore",
      message: `reissue body failed after retries; steady state restored: ${error.message}`,
      tags: { outcome: "reissue_incomplete_restore_ok" },
    });
  } catch (restoreErr) {
    // The security-regression brake: restore itself failed.
    emit("onfailure-restore", {
      ok: false,
      outcome: "proxy_restore_failed",
      detail: `onFailure restore FAILED after body error: ${error.message}`,
      errorName: (restoreErr as Error).name,
      errorDetail: (restoreErr as Error).message,
    });
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
