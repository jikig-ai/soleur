import { stat, statfs } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createProbeOctokit } from "@/server/github/probe-octokit";
import { generateInstallationToken } from "@/server/github-app";
import {
  reportSilentFallback,
  warnSilentFallback,
  mirrorWarnWithDebounce,
} from "@/server/observability";
import { redactGithubSourcedText } from "@/lib/safety/redaction-allowlist";
import { emitClaudeCostMarker } from "@/server/claude-cost-marker";
import { emitCronTier2Deferred } from "@/server/cron-liveness-marker";
import type { SpawnResult } from "./_cron-claude-eval-substrate";
import type { Octokit } from "@octokit/core";

export const REPO_OWNER = "jikig-ai";
export const REPO_NAME = "soleur";

/**
 * Base dir for a cron's ephemeral git-clone workspace. In prod, ci-deploy.sh
 * sets CRON_WORKSPACE_ROOT=/workspaces (the roomy /mnt/data volume) so the
 * --depth=1 clone of the ~100 MB soleur tree does not exhaust the 256 MB /tmp
 * tmpfs (#4684/#4689). Unset/whitespace → os.tmpdir() preserves local/CI/test
 * behavior. Every cron that clones the repo (the substrate's
 * setupEphemeralWorkspace AND the handlers with their own inline clone) MUST
 * route its mkdtemp parent through this helper — the env var alone is inert if
 * the code keeps calling tmpdir() directly. The `soleur-${cronName}-` prefix
 * keeps cron dirs distinct from the UUID user-workspace dirs under /workspaces.
 */
export function resolveCronWorkspaceRoot(): string {
  return process.env.CRON_WORKSPACE_ROOT?.trim() || tmpdir();
}

// --- Deploy-lease drain coordination (#5669 / ADR-078) ----------------------
//
// Every merge that redeploys soleur-web-platform stops + swaps the container
// (ci-deploy.sh `docker stop --time=12 soleur-web-platform`), which kills any
// in-flight cron `claude` child — the `:706` "spawn cwd … no longer exists"
// symptom. ci-deploy.sh now drains: it pauses *new* cron starts and waits for
// the in-flight child before swapping. The pause is a lease FILE written at
// `${CRON_WORKSPACE_ROOT}/.deploy-lease` (host /mnt/data/workspaces/.deploy-lease
// == container /workspaces/.deploy-lease — the same host-mounted volume both the
// old and new container see). A FRESH lease means a deploy is mid-swap; the cron
// substrate defers (see setupEphemeralWorkspace) so the imminent stop cannot
// kill it. The host-side `cron_in_flight` drain loop does the actual *waiting*;
// this lease only closes the START-race (a new run launching claude into the
// about-to-die container while the loop drains the current one).
//
// CTO ruling (ADR-078): lease over native `inngest pause`/`resume` — the lease
// is verifiable from code (a unit test), gates ONLY the cron substrate (not all
// server-global event-driven functions), and its failure mode is fail-SAFE (a
// cron skips one fire) rather than fail-DANGEROUS (pause killing the in-flight
// child is the very incident this fixes).
export const DEPLOY_LEASE_BASENAME = ".deploy-lease";

// TTL fail-open. A lease older than this is treated as ABSENT so a deploy that
// was SIGKILLed mid-drain (untrappable; host OOM/reboot) cannot dark every cron
// indefinitely — the worst case degrades to "ignore a stale lease", never
// "silent total cron outage". Must exceed the host drain wall-clock
// (CRON_DRAIN_TIMEOUT = 4200s, the MAX per-function maxTurnDurationMs) plus
// swap overhead; default 90 min. Env-overridable (no Doppler secret — pure
// timing knob, mirrors CRON_WORKSPACE_ROOT).
export const DEPLOY_LEASE_MAX_AGE_MS: number = (() => {
  const raw = process.env.DEPLOY_LEASE_MAX_AGE_MS;
  const n = raw ? Number.parseInt(raw, 10) : Number.NaN;
  return Number.isFinite(n) && n > 0 ? n : 90 * 60 * 1000;
})();

export function resolveDeployLeasePath(): string {
  return join(resolveCronWorkspaceRoot(), DEPLOY_LEASE_BASENAME);
}

/**
 * Returns the lease age in ms when a FRESH deploy lease exists (a deploy is
 * mid-swap → the caller should defer), else `null` (no lease, or a stale lease
 * past the TTL that is fail-open ignored). Pure read; never throws — any stat
 * error (absent file, permissions) collapses to `null` so a probe failure can
 * never block a cron.
 */
export async function deployLeaseAgeMsIfFresh(
  nowMs: number = Date.now(),
  leasePath: string = resolveDeployLeasePath(),
  maxAgeMs: number = DEPLOY_LEASE_MAX_AGE_MS,
): Promise<number | null> {
  try {
    const st = await stat(leasePath);
    const ageMs = nowMs - st.mtimeMs;
    if (ageMs < 0) return 0; // clock skew between host writer and container → treat as fresh
    if (ageMs > maxAgeMs) return null; // stale → fail-open (ignore a crashed deploy's lease)
    return ageMs;
  } catch {
    return null; // absent / unreadable → proceed normally
  }
}

/**
 * Thrown by setupEphemeralWorkspace when a fresh deploy lease is present. A
 * distinct class (not a bare Error) so the deferral is queryable in
 * Sentry/Better Stack and is never confused with a real setup failure. Inngest
 * `retries: 1` re-dispatches the run; the retry normally lands after the bounded
 * deploy completes (worst case: the cron skips this one fire — fail-safe).
 */
export class DeployInProgressError extends Error {
  readonly cronName: string;
  readonly leaseAgeMs: number;
  constructor(cronName: string, leaseAgeMs: number) {
    super(
      `[${cronName}] deploy in progress (lease age ${leaseAgeMs}ms) — deferring cron start so the container swap cannot kill claude (#5669)`,
    );
    this.name = "DeployInProgressError";
    this.cronName = cronName;
    this.leaseAgeMs = leaseAgeMs;
  }
}

// Free MB available to an UNPRIVILEGED caller — `bavail`, not `bfree`, matches
// what the 1001 container user actually gets. Single source of truth for the
// disk-free arithmetic shared by the pre-clone guard below and cron-workspace-gc;
// a divergence here (e.g. someone "fixing" one copy to `bfree`) would silently
// skew disk accounting in one cron but not the other.
export function freeMb(stats: { bavail: number; bsize: number }): number {
  return Math.floor((stats.bavail * stats.bsize) / (1024 * 1024));
}

// Soft floor for the pre-clone free-space guard: the soleur tree is ~100 MB and
// grows every content PR; warn under 256 MB free so the operator sees the
// squeeze BEFORE ENOSPC kills the clone. Tunable via CRON_WORKSPACE_MIN_FREE_MB
// (NaN/0 → this default). Non-fatal.
export const DEFAULT_CRON_WORKSPACE_MIN_FREE_MB = 256;

/**
 * Non-fatal pre-clone free-space guard. statfs the cron workspace root and emit
 * a non-paging WARN if free space is below the floor, so the operator sees the
 * squeeze in Sentry BEFORE a `git clone` ENOSPCs (#4684/#4689). MUST NEVER throw
 * — a wrong floor or a statfs probe error must never block a clone that would
 * otherwise succeed. Call once after mkdtemp and before the clone, from EVERY
 * cron that clones the repo (the substrate's setupEphemeralWorkspace AND the
 * handlers with their own inline clone), so the observability is not half-applied.
 * Uses `bavail` (blocks free to an unprivileged caller — what the 1001 container
 * user actually gets), not `bfree`.
 */
export async function warnIfCronWorkspaceLowOnDisk(
  ephemeralRoot: string,
  cronName: string,
): Promise<void> {
  try {
    const stats = await statfs(ephemeralRoot);
    const freeMbValue = freeMb(stats);
    const floorMb =
      Number(process.env.CRON_WORKSPACE_MIN_FREE_MB) ||
      DEFAULT_CRON_WORKSPACE_MIN_FREE_MB;
    if (freeMbValue < floorMb) {
      warnSilentFallback(
        new Error(
          `cron workspace root low on disk: ${freeMbValue} MB free < ${floorMb} MB floor at ${ephemeralRoot} — git clone may ENOSPC`,
        ),
        {
          feature: cronName,
          op: "cron-workspace-low-disk",
          message: "Cron ephemeral workspace low on free disk before clone",
          extra: { fn: cronName, ephemeralRoot, freeMb: freeMbValue, floorMb },
        },
      );
    }
  } catch (err) {
    // statfs failure is itself non-fatal — never block a clone on a probe error.
    reportSilentFallback(err, {
      feature: cronName,
      op: "cron-workspace-statfs-failed",
      message: "Could not statfs cron workspace root (non-fatal)",
      extra: { fn: cronName, ephemeralRoot },
    });
  }
}

export const SENTRY_DOMAIN_RE = /^[a-z0-9.-]+\.sentry\.io$/i;
export const SENTRY_PROJECT_RE = /^\d+$/;
export const SENTRY_PUBLIC_KEY_RE = /^[a-f0-9]{32}$/;

export interface HandlerArgs {
  event?: { data?: Record<string, unknown> };
  step: { run<T>(name: string, cb: () => Promise<T>): Promise<T> };
  logger: {
    info: (...a: unknown[]) => void;
    warn: (...a: unknown[]) => void;
    error: (...a: unknown[]) => void;
  };
  // Inngest's zero-indexed retry attempt and (optional) max attempt count from
  // the function context (BaseContext.attempt / .maxAttempts). Optional so every
  // other cron handler — and the existing tests — that pass neither keep
  // compiling and behave as before (attempt=0/maxAttempts=1 → final attempt).
  // Read by retry-aware handlers (e.g. cron-stale-deferred-scope-outs) to gate
  // the Sentry error heartbeat on the FINAL attempt rather than paging on a
  // transient that the retry recovers.
  attempt?: number;
  maxAttempts?: number;
  // Inngest run id (ctx.runId), threaded to routine_run_progress live-state (#5766)
  runId?: string;
}

export function redactToken(s: string, token: string): string {
  if (!token) return s;
  return s.replaceAll(token, "[REDACTED-INSTALLATION-TOKEN]");
}

export function buildAuthenticatedCloneUrl(token: string): string {
  return `https://x-access-token:${token}@github.com/${REPO_OWNER}/${REPO_NAME}.git`;
}

// Least-privilege permission subset for a restored/contained cron's GH_TOKEN
// (#5046). A leaked token carrying THIS set can push commits, file/close issues,
// and open/comment PRs on soleur — but cannot dispatch workflows (actions),
// edit rulesets/branch protection (administration), or write check-runs (checks).
// Paired with `repositories: ["soleur"]` it is bounded to a single-user incident.
// `pull_requests:write` is REQUIRED for `gh pr create` (contents:write covers the
// push, NOT opening the PR → 403 without it). The GitHub App install-time manifest
// is the hard ceiling — this can only narrow within it. Opt-in per cron at the
// mint call site (NOT a blanket default — the workflow-dispatch / pages / ruleset
// crons legitimately need actions/pages/administration and pass no scope → full
// grant). See knowledge-base/.../2026-06-09-feat-tier2-cron-egress-firewall-plan.md §1.3.
export const DEFAULT_CRON_TOKEN_PERMISSIONS: Record<string, string> = {
  contents: "write",
  issues: "write",
  pull_requests: "write",
};

// Issue-creator preset (#5046 PR-2, narrowed at review): the restored audit
// crons clone (contents:read suffices for the x-access-token clone) and file
// issues/labels (issues:write covers labels) — they never push or open PRs,
// so write capability is denied at the TOKEN layer too, not solely by the
// containment hook (defense-in-depth: if sub-agent hook inheritance ever
// fails, contents:write would otherwise be a push primitive to the public
// auto-deploying repo).
export const ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS: Record<string, string> = {
  contents: "read",
  issues: "write",
};

export async function mintInstallationToken(opts: {
  tokenMinLifetimeMs: number;
  // Optional least-privilege scope. Omitted → full installation grant (the
  // unchanged behavior for every non-narrowed cron). generateInstallationToken
  // folds the scope into its cache key so a narrowed cron token never collides
  // with the broad token the interactive/agent callers mint for the same
  // installation id (#5046).
  permissions?: Record<string, string>;
  repositories?: string[];
}): Promise<string> {
  const octokit = await createProbeOctokit();
  const { data: installation } = await octokit.request(
    "GET /repos/{owner}/{repo}/installation",
    { owner: REPO_OWNER, repo: REPO_NAME },
  );
  return generateInstallationToken(installation.id, {
    minRemainingMs: opts.tokenMinLifetimeMs,
    permissions: opts.permissions,
    repositories: opts.repositories,
  });
}

const SENTRY_HEARTBEAT_TIMEOUT_MS = 10_000;
// #5728 — bounded retry on the heartbeat POST. A transient 5xx / network drop /
// timeout of the OK check-in previously left a silent `missed` (the 2026-06-13→
// 06-21 H3 class). Retry only the RETRYABLE classes; a 4xx is a permanent
// bad-slug/DSN error and retrying it only burns the margin. The TOTAL wall-clock
// is hard-bounded (each attempt's per-call timeout is clamped to the remaining
// budget) so the heartbeat can never push the run past the 60-min Sentry check-in
// margin (re-creating H1). After the bounded attempts exhaust, fall through to
// the terminal reportSilentFallback (durable trace; cq-silent-fallback-must-mirror-to-sentry).
const SENTRY_HEARTBEAT_MAX_ATTEMPTS = 3;
const SENTRY_HEARTBEAT_TOTAL_BUDGET_MS = 25_000;
// Backoff applied BEFORE attempt i (index 0 = first attempt, never waited).
const SENTRY_HEARTBEAT_BACKOFF_MS = [0, 250, 750];

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

export async function postSentryHeartbeat(args: {
  ok: boolean;
  sentryMonitorSlug: string;
  cronName: string;
  logger: HandlerArgs["logger"];
}): Promise<void> {
  const { ok, sentryMonitorSlug, cronName, logger } = args;

  if (ok) {
    try {
      const dir = "/var/lib/inngest/cron-fires";
      const { mkdir, writeFile } = await import("node:fs/promises");
      await mkdir(dir, { recursive: true });
      await writeFile(
        `${dir}/${sentryMonitorSlug}.json`,
        JSON.stringify({ last_ok_at: new Date().toISOString(), slug: sentryMonitorSlug }),
      );
    } catch {
      // Best-effort; do not block heartbeat on file-write failure
    }
  }
  const domain = process.env.SENTRY_INGEST_DOMAIN;
  const projectId = process.env.SENTRY_PROJECT_ID;
  const publicKey = process.env.SENTRY_PUBLIC_KEY;
  if (!domain || !projectId || !publicKey) {
    // #4861 — was a silent `logger.info` + return; a blank heartbeat env then
    // paged nowhere. Keep the pino log (stdout → Better Stack) AND additionally
    // route through the DEBOUNCED warn wrapper: it lands via the @sentry/nextjs
    // SDK (SENTRY_DSN — a DIFFERENT, populated var from these three ingest vars),
    // so the skip is loud even when the ingest env is blank. This is strictly
    // additive — the pino line stays (existing behavior), the Sentry mirror is
    // new. Keep the early return — the change is observability, not control flow
    // (cq-silent-fallback-must-mirror-to-sentry). Debounce keyed on (cronName,
    // op) so ~45 crons sharing this env do not flood on a shared misconfig.
    logger.info({ fn: cronName }, "Sentry env unset — skipping heartbeat");
    mirrorWarnWithDebounce(
      new Error(`Sentry heartbeat env unset — heartbeat skipped for ${cronName}`),
      {
        feature: "cron-sentry-heartbeat",
        op: "heartbeat-env-unset",
        message: "Sentry heartbeat env unset — skipping heartbeat",
        tags: { cron: cronName },
      },
      cronName,
      "heartbeat-env-unset",
    );
    return;
  }
  if (
    !SENTRY_DOMAIN_RE.test(domain) ||
    !SENTRY_PROJECT_RE.test(projectId) ||
    !SENTRY_PUBLIC_KEY_RE.test(publicKey)
  ) {
    // Additive (see unset branch above): keep the pino warn line, add the
    // debounced Sentry mirror so a malformed heartbeat env is never silent.
    logger.warn({ fn: cronName }, "Sentry env malformed — skipping heartbeat");
    mirrorWarnWithDebounce(
      new Error(`Sentry heartbeat env malformed — heartbeat skipped for ${cronName}`),
      {
        feature: "cron-sentry-heartbeat",
        op: "heartbeat-env-malformed",
        message: "Sentry heartbeat env malformed — skipping heartbeat",
        tags: { cron: cronName },
      },
      cronName,
      "heartbeat-env-malformed",
    );
    return;
  }
  const status = ok ? "ok" : "error";
  const url = `https://${domain}/api/${projectId}/cron/${sentryMonitorSlug}/${publicKey}/?status=${status}`;

  // Bounded-retry delivery (#5728). Retry on 5xx / network / timeout; NEVER on a
  // 4xx (permanent). Total wall-clock is clamped by SENTRY_HEARTBEAT_TOTAL_BUDGET_MS.
  const start = Date.now();
  let lastError: Error | null = null;
  let lastHttpStatus: number | null = null;

  for (let attempt = 0; attempt < SENTRY_HEARTBEAT_MAX_ATTEMPTS; attempt++) {
    if (attempt > 0) {
      // Index 0 is never slept on (guarded here), so the backoff lookup lives
      // inside the retry branch — the "attempt 0 is immediate" invariant reads
      // straight off the control flow.
      const backoff = SENTRY_HEARTBEAT_BACKOFF_MS[attempt] ?? 750;
      const remainingBeforeBackoff = SENTRY_HEARTBEAT_TOTAL_BUDGET_MS - (Date.now() - start);
      if (remainingBeforeBackoff <= backoff) break; // no budget left to retry
      await sleep(backoff);
    }
    const remaining = SENTRY_HEARTBEAT_TOTAL_BUDGET_MS - (Date.now() - start);
    if (remaining <= 0) break;
    const perAttemptTimeout = Math.min(SENTRY_HEARTBEAT_TIMEOUT_MS, remaining);
    try {
      const resp = await fetch(url, {
        method: "POST",
        signal: AbortSignal.timeout(perAttemptTimeout),
      });
      if (resp.ok) return; // delivered
      lastHttpStatus = resp.status;
      lastError = null;
      // 4xx is permanent (bad slug / DSN) — do not retry; fall through to fallback.
      if (resp.status >= 400 && resp.status < 500) break;
      // 5xx (and any other non-2xx) → retryable.
    } catch (err) {
      // Network failure / AbortSignal timeout → retryable.
      lastError = err as Error;
      lastHttpStatus = null;
    }
  }

  // All bounded attempts exhausted (or hit a non-retryable 4xx) — durable trace.
  const fallbackError =
    lastError ??
    new Error(
      `Sentry Crons heartbeat POST returned non-2xx (status ${lastHttpStatus ?? "unknown"})`,
    );
  reportSilentFallback(fallbackError, {
    feature: "cron-sentry-heartbeat",
    op: "fetch",
    message: "Sentry Crons heartbeat POST failed after bounded retries",
    extra: {
      fn: cronName,
      status,
      httpStatus: lastHttpStatus,
      aborted: lastError?.name === "TimeoutError",
    },
  });
}

// ---------------------------------------------------------------------------
// #5728 — memoization-safe final-attempt heartbeat for the output-aware cohort.
// ---------------------------------------------------------------------------
// A throw inside a catch-less inner try (claude-eval → verify-output →
// safe-commit-pr → sentry-heartbeat) previously propagated out of the function,
// so the single end-of-run `sentry-heartbeat` step never ran → Sentry saw NO
// check-in → `missed` (NOT `error`). This shared helper makes a throw produce a
// loud terminal `?status=error` ("the cron RAN and failed"), distinct from
// "never fired", while preserving retry-memoization correctness. It is the
// vetted shape the output-aware producer cohort adopts (mirrors the inline
// precedent in cron-stale-deferred-scope-outs.ts:358,397-433).
//
// Contract:
//   - `heartbeatOk` is the output-aware verdict (issue present ⇒ green). An
//     output-PRESENT run stays GREEN even if a trailing persistence step threw —
//     the digest exists; the persistence failure self-reports separately. So the
//     posted status is simply `heartbeatOk`.
//   - `threw` is whether the guarded body threw. A genuine failure is
//     `threw && !heartbeatOk`.
//   - On a genuine failure on a NON-final attempt: SKIP the whole heartbeat
//     step (a completed step.run is memoized across the Inngest retry, so an
//     executed-but-silent step would replay and never emit the recovered `ok`)
//     and return { retry: true } — the caller MUST rethrow to trigger the retry.
//   - Otherwise post exactly ONE authoritative heartbeat as the genuine last
//     step. `onBeforeHeartbeat` (optional) runs ONLY on this post path — used by
//     producers that file a silence-hole fallback issue when red, ordered before
//     the heartbeat so the heartbeat stays last and is never double-signalled.
//
// DeployInProgressError MUST be excluded by the caller BEFORE invoking this
// helper (rethrow bare, no heartbeat — the ADR-078 fail-safe deploy defer).
export async function finalizeOutputAwareHeartbeat(args: {
  step: HandlerArgs["step"];
  heartbeatOk: boolean;
  threw: boolean;
  attempt?: number;
  maxAttempts?: number;
  sentryMonitorSlug: string;
  cronName: string;
  logger: HandlerArgs["logger"];
  onBeforeHeartbeat?: () => Promise<void>;
  /**
   * Can a REPLAY plausibly recover this failure? (#6714, ADR-126.)
   *
   * This helper conflated two independent questions: "what colour do we post"
   * and "is a retry capable of fixing it". For a producer whose ephemeral
   * workspace is destroyed in its own `finally`, the second answer is always
   * NO — `setup-workspace` is memoized, so a replay reads back a path that has
   * already been `rm -rf`'d and `safeCommitAndPr` hits its `workspace-lost`
   * guard unconditionally. That guard is not silent: it comments "PR withheld:
   * safe-commit failed at stage `workspace-lost`" onto the operator's issue
   * with a runbook pointer, so a guaranteed-useless replay actively misleads a
   * non-technical operator.
   *
   * Passing `false` lets such a caller report an honest RED colour without
   * buying a replay that cannot succeed. OMITTED (undefined) preserves the
   * existing behavior exactly, so the other 7 cohort callers are unchanged.
   */
  retryEligible?: boolean;
}): Promise<{ retry: boolean }> {
  const {
    step,
    heartbeatOk,
    threw,
    attempt,
    maxAttempts,
    sentryMonitorSlug,
    cronName,
    logger,
    onBeforeHeartbeat,
    retryEligible,
  } = args;
  // retries:1 → 2 attempts (index 0 and 1); final attempt is index 1. Callers
  // passing neither read attempt=0/maxAttempts=1 → isFinalAttempt=true (legacy
  // behavior). maxAttempts is OPTIONAL on Inngest's BaseContext, so a missing
  // value collapses to always-final → every failed attempt posts error: degrades
  // to OVER-paging (the original bug), never to masking a failure with false ok.
  const isFinalAttempt = (attempt ?? 0) >= ((maxAttempts ?? 1) - 1);
  // `retryEligible !== false` (not a truthiness test) so OMITTING the field is
  // indistinguishable from today's behavior for the 7 callers that do not pass it.
  const failed = threw && !heartbeatOk && retryEligible !== false;
  if (failed && !isFinalAttempt) {
    logger.warn(
      { fn: cronName, attempt: attempt ?? 0, isFinalAttempt },
      `${cronName} failed on a non-final attempt — skipping the heartbeat step (memoization-safe) and retrying`,
    );
    return { retry: true };
  }
  if (onBeforeHeartbeat) await onBeforeHeartbeat();
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({ ok: heartbeatOk, sentryMonitorSlug, cronName, logger });
  });
  return { retry: false };
}

// ---------------------------------------------------------------------------
// Discord webhook write boundary (#5080 — hr-write-boundary-sentinel-sweep)
// ---------------------------------------------------------------------------
// Shared helper for Discord write sites: mentions are suppressed at the
// API level by construction (allowed_mentions parse:[] — sed-stripping is
// bypassable, see 2026-03-05 learning), and the webhook URL is never logged
// or interpolated into errors (fetch rejections are rethrown redacted).
// All in-repo cron Discord writes route through here (weekly-analytics
// notify-kpi-miss migrated in #5122).
const DISCORD_WEBHOOK_TIMEOUT_MS = 10_000;

export async function postDiscordWebhook(args: {
  webhookUrl: string;
  content: string;
  username?: string;
}): Promise<{ ok: boolean; status: number }> {
  try {
    const resp = await fetch(args.webhookUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        content: args.content,
        ...(args.username ? { username: args.username } : {}),
        allowed_mentions: { parse: [] },
      }),
      signal: AbortSignal.timeout(DISCORD_WEBHOOK_TIMEOUT_MS),
    });
    return { ok: resp.ok, status: resp.status };
  } catch (err) {
    // Rethrow redacted: undici's URL-parse/network TypeErrors embed the full
    // webhook URL (a write credential) in e.message — never let it reach a
    // logger or Sentry payload (the "never logged" guarantee above).
    const e = err as Error;
    throw new Error(`Discord webhook fetch failed (${e.name})`);
  }
}

// ---------------------------------------------------------------------------
// Shared transport for the direct Anthropic Messages API call sites (#5186).
// cron-weekly-release-digest (curateViaAnthropic) and cron-compound-promote
// (anthropic-cluster step) duplicated this fetch + headers + non-ok-throw +
// content-extraction shape. This helper owns ONLY the transport; it returns the
// raw { text, stopReason } and makes NO decision about what an empty / truncated
// / refused / shape-invalid response means — each caller keeps its own
// stop_reason guard, empty-content guard, shape validation, logger.warn, and
// reportSilentFallback at the call site (transport-only / postDiscordWebhook
// model, NOT postSentryHeartbeat's swallow-and-report). The model is an arg, so
// no "claude-…" literal lands in functions/ (model-tiers.ts RAW_MODEL_LITERAL
// guard). timeoutMs is optional: the digest passes 60_000; compound passes none
// (it has no request timeout today — behavior parity, do not add one).
// Typed non-ok error for the shared Anthropic transport (#5674). Carries the
// HTTP status AND a bounded, redaction-scrubbed body excerpt so a caller (the
// credit-probe canary) can classify the failure (e.g. /credit balance is too
// low/i) WITHOUT the body ever reaching a logger/Sentry payload unscrubbed.
// `.message` keeps the legacy `Anthropic API ${status}` PREFIX so the two
// pre-existing callers (cron-compound-promote, cron-weekly-release-digest) and
// their tests — which only read `.message` / match that substring — stay
// backward-compatible (hr-type-widening-cross-consumer-grep).
export class AnthropicApiError extends Error {
  readonly status: number;
  readonly bodyExcerpt?: string;
  constructor(status: number, bodyExcerpt?: string) {
    super(`Anthropic API ${status}${bodyExcerpt ? `: ${bodyExcerpt}` : ""}`);
    this.name = "AnthropicApiError";
    this.status = status;
    this.bodyExcerpt = bodyExcerpt;
  }
}

export async function postAnthropicMessage(args: {
  apiKey: string;
  model: string;
  maxTokens: number;
  messages: Array<{ role: "user"; content: string }>;
  timeoutMs?: number;
  outputConfig?: { format: { type: "json_schema"; schema: unknown } };
  // #cost-attribution (plan Phase 2, choke point #3): the caller's cron name.
  // When set, a `cron:<name>` SOLEUR_CLAUDE_COST marker is emitted from the ok
  // response's `usage`/`model` — closing per-cron attribution for the HTTP-
  // transport crons that `spawnClaudeEval` misses (compound-promote real spend,
  // credit-probe canary). Optional so the two existing callers/tests that omit
  // it stay compiling.
  markerSource?: string;
}): Promise<{ text: string; stopReason?: string }> {
  let resp: Response;
  try {
    resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": args.apiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model: args.model,
        max_tokens: args.maxTokens,
        messages: args.messages,
        ...(args.outputConfig ? { output_config: args.outputConfig } : {}),
      }),
      signal: args.timeoutMs != null ? AbortSignal.timeout(args.timeoutMs) : undefined,
    });
  } catch (err) {
    // Rethrow redacted: a network/abort error from fetch could in principle
    // carry request context — never let the x-api-key reach a logger/Sentry
    // payload. Mirrors postDiscordWebhook's redact-then-throw (the URL-credential
    // sibling above).
    const e = err as Error;
    throw new Error(`Anthropic API request failed (${e.name})`);
  }
  if (!resp.ok) {
    // #5674: surface a BOUNDED, redaction-scrubbed body excerpt on a non-ok
    // response so the credit-probe canary can classify the failure (the body is
    // where "Credit balance is too low" lives). `.message` keeps the legacy
    // `Anthropic API ${status}` prefix for the two existing callers/tests.
    let rawBody = "";
    try {
      rawBody = await resp.text();
    } catch {
      // Body unreadable (already consumed / stream error) — status alone still
      // throws a typed error; the canary falls back to the status-only branch.
    }
    throw new AnthropicApiError(
      resp.status,
      formatTailForSentry(rawBody)?.slice(0, 600),
    );
  }

  const data = (await resp.json()) as {
    content?: Array<{ text?: string }>;
    stop_reason?: string;
    model?: string;
    usage?: {
      input_tokens?: number;
      output_tokens?: number;
      cache_read_input_tokens?: number;
      cache_creation_input_tokens?: number;
    };
  };

  // #cost-attribution (plan Phase 2, choke point #3): surface the response
  // `usage`/`model` the transport otherwise discards. `/v1/messages` does NOT
  // return `total_cost_usd`, so cost rides as null (tokens-only — acceptable per
  // plan; the Phase-3 Admin daily report is the authoritative $ reconciliation).
  // Fail-open — emitClaudeCostMarker never throws.
  if (args.markerSource) {
    emitClaudeCostMarker({
      source: `cron:${args.markerSource}`,
      id: args.markerSource,
      model: data.model ?? args.model ?? null,
      cost_usd: null,
      input_tokens: data.usage?.input_tokens ?? null,
      output_tokens: data.usage?.output_tokens ?? null,
      cache_read_input_tokens: data.usage?.cache_read_input_tokens ?? null,
      cache_creation_input_tokens: data.usage?.cache_creation_input_tokens ?? null,
      capture_status: "ok",
    });
  }

  return { text: data.content?.[0]?.text ?? "", stopReason: data.stop_reason };
}

// #cost-attribution (plan Phase 3). GET transport for the Anthropic Admin Cost
// & Usage API (`/v1/organizations/cost_report`, `/usage_report/messages`). Read-
// only org-billing metadata. MUST mirror postAnthropicMessage's two redaction
// properties (security F1): the network-catch rethrow carries neither the admin
// key nor request context, and the non-ok body excerpt routes through
// `formatTailForSentry`. `AnthropicApiError.status` lets the cost-report cron
// classify 401/403 (bad admin key) as fatal vs 429/5xx (transient → retry).
export async function getAnthropicAdminReport(args: {
  adminKey: string;
  path: string;
  query: Record<string, string | string[]>;
  timeoutMs?: number;
}): Promise<unknown> {
  const url = new URL(`https://api.anthropic.com${args.path}`);
  for (const [key, value] of Object.entries(args.query)) {
    if (Array.isArray(value)) {
      for (const item of value) url.searchParams.append(key, item);
    } else {
      url.searchParams.set(key, value);
    }
  }
  let resp: Response;
  try {
    resp = await fetch(url, {
      method: "GET",
      headers: {
        "x-api-key": args.adminKey,
        "anthropic-version": "2023-06-01",
      },
      signal:
        args.timeoutMs != null ? AbortSignal.timeout(args.timeoutMs) : undefined,
    });
  } catch (err) {
    // Rethrow redacted (security F1): a network/abort error could carry request
    // context — never let the admin key reach a logger/Sentry payload. Mirrors
    // postAnthropicMessage's redact-then-throw.
    const e = err as Error;
    throw new Error(`Anthropic Admin API request failed (${e.name})`);
  }
  if (!resp.ok) {
    let rawBody = "";
    try {
      rawBody = await resp.text();
    } catch {
      // Body unreadable — status alone still throws a typed, classifiable error.
    }
    throw new AnthropicApiError(
      resp.status,
      formatTailForSentry(rawBody)?.slice(0, 600),
    );
  }
  return (await resp.json()) as unknown;
}

// ---------------------------------------------------------------------------
// Tier-2 deferral guard (#5018 — hook-primary cron containment, D6)
// ---------------------------------------------------------------------------
// These claude-spawning crons need Bash that cannot be expressed as a finite
// allowlist for the containment hook (cron-bash-allowlist-hook.mjs), so under the
// v3.1 overlay (sandbox off + deny-by-default hook) they would fail-closed.
// Letting them spawn → fail-closed → emit a weekly FAILED `[Scheduled]` issue +
// RED Sentry monitor is an alert STORM that masks real regressions (panel P1-A).
// Instead each such handler calls deferIfTier2Cron as its FIRST step: it posts an
// honest on-schedule check-in (ok — the function DID run on time) and
// early-returns WITHOUT spawning claude and WITHOUT creating an output issue. The
// work-output verify is SKIPPED, not faked → NOT a silent green. Visible
// degradation = the cron's weekly output issue stops appearing (enumerated in the
// Tier-2 follow-up issue, founder-readable). Tier-2 (egress firewall + least-priv
// token) removes a cron from this set to restore it. roadmap-review (#5004) is
// ABSENT — it is the validated Tier-1 cron (finite allowlist in CRON_BASH_ALLOWLISTS).
// #5046 PR-2 restored cron-agent-native-audit + cron-legal-audit: the
// relax-minimal hook (Task/Skill allow, every Bash layer intact) unblocks
// exactly the two crons whose ONLY denied construct was the Task catch-all.
// #5199 restored cron-ux-audit: the FIRST cron with an mcp__* allowance — a
// file-driven per-cron `mcp__playwright__*` relaxation + URL-origin guard +
// session-secret read-deny (see CRON_MCP_ALLOWLISTS / cron-bash-allowlist-hook).
// Each restored cron carries a finite CRON_BASH_ALLOWLISTS entry and mints a
// narrowed token (issue-creators mint ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS).
// #5199 restored the SEVEN `mergeMode:"auto"` PR-flow crons
// (campaign-calendar, competitive-analysis, growth-audit, seo-aeo-audit,
// content-generator, growth-execution, community-monitor) — the PR-5200
// stale-bot-PR watchdog (issue #5138) landed, removing the gate. Each carries a
// finite, evidence-gated CRON_BASH_ALLOWLISTS entry and mints
// DEFAULT_CRON_TOKEN_PERMISSIONS (contents/issues/pull_requests:write — they
// push + open PRs via safeCommitAndPr) scoped to [REPO_NAME].
// #5199 (this PR — the FINAL restore) restored cron-bug-fixer, the last cron in
// this set. Its blocker was that its `bot-fix/*` head pattern was OUTSIDE the
// #5138/#5200 watchdog's scan; this PR added `bot-fix/*` to BOT_PR_HEAD_PREFIXES
// (atomic — watchdog FIRST, then un-defer) so the silent-auto-merge-disarm class
// is now covered. bug-fixer's commit lives in the fix-issue SKILL (not
// safeCommitAndPr), so its CRON_BASH_ALLOWLISTS entry carries git/gh-pr
// persistence verbs and it mints DEFAULT_CRON_TOKEN_PERMISSIONS scoped to
// [REPO_NAME].
// **TIER2_DEFERRED_CRONS is now EMPTY — the Tier-2 boundary is fully restored
// and #5199 is closed.** deferIfTier2Cron stays as a defensive no-op (an empty
// set short-circuits has() to false), so the handler call sites need no edit.
export const TIER2_DEFERRED_CRONS: ReadonlySet<string> = new Set([]);

export async function deferIfTier2Cron(args: {
  cronName: string;
  sentryMonitorSlug: string;
  step: HandlerArgs["step"];
  logger: HandlerArgs["logger"];
}): Promise<boolean> {
  const { cronName, sentryMonitorSlug, step, logger } = args;
  if (!TIER2_DEFERRED_CRONS.has(cronName)) return false;
  logger.warn(
    { fn: cronName, status: "tier-2-deferred" },
    `${cronName} is Tier-2-deferred (#5018/#5046): the containment hook denies its bash ` +
      `constructs; restoration needs per-construct allowlist refinement or non-GitHub ` +
      `egress coverage (see TIER2_DEFERRED_CRONS). Skipping claude spawn this run.`,
  );
  // #6714 marker 4 — this branch posts a GREEN check-in and skips the spawn, so
  // in Sentry it is INDISTINGUISHABLE from a healthy run. That blind spot hid 4
  // of the 41 gap days (2026-06-09 → 06-12). Emitted before the heartbeat so the
  // defer is on the record even if the check-in POST itself fails.
  emitCronTier2Deferred({ cron: cronName });
  await step.run("tier2-deferred-heartbeat", async () => {
    await postSentryHeartbeat({ ok: true, sentryMonitorSlug, cronName, logger });
  });
  return true;
}

// ---------------------------------------------------------------------------
// Output-verification helper — closes the silent-no-op gap (#4689/#4686/#4684).
//
// A scheduled producer can exit 0 without producing its `scheduled-<task>`
// output (e.g. the spawned claude exhausts --max-turns before the final
// "create the issue" step, or its `gh issue create` dead-ends). The
// exit-code-only heartbeat (`ok: spawnResult.ok`) then stayed GREEN while the
// producer went quiet — the silent-failure gap that let four producers go
// dark unnoticed until the separate cron-cloud-task-heartbeat watchdog's
// issue-count caught it (weeks later).
//
// "Produced output" = a `scheduled-<task>`-labeled issue CREATED OR UPDATED in
// the run window. The update case matters: cron-campaign-calendar's comment-bump
// path ("Do NOT create a new issue" — on a quiet day it comments a heartbeat note
// on the existing calendar issue instead of creating one; its handler documents
// that verifyScheduledIssueCreated "counts via updated_at"). Filtering on
// updated_at (via the GitHub `since` param) credits that comment-bump as output,
// so a quiet-day run does NOT false-red. (community-monitor's former in-prompt
// dedup rule was another such consumer, but #6143 removed it — campaign-calendar
// is now the SOLE path relying on the updated_at crediting, which is why the
// `since`/updated_at filter below stays load-bearing rather than being tightened
// to created_at. cron-shared.test.ts test-enforces this coupling via the
// campaign-calendar marker assertion.) Within a producer's ~50-min run window
// only the producer itself touches its own labeled issues (daily-triage runs at a
// different hour), so updated_at moving == the producer did something.
//
// Callers gate their Sentry heartbeat on this result so a quiet producer turns
// its OWN per-function monitor red, with no dependency on the watchdog. Reuses
// the watchdog's read shape (GET /repos/{owner}/{repo}/issues — see
// cron-cloud-task-heartbeat.ts) for parity. Read-only: never creates or
// mutates an issue.
//
// The octokit is injectable purely so unit tests can drive the read shape
// without the App-JWT mint path; production callers omit it and the helper
// mints a probe client itself.
export async function verifyScheduledIssueCreated(args: {
  label: string;
  sinceIso: string;
  octokit?: Awaited<ReturnType<typeof createProbeOctokit>>;
}): Promise<boolean> {
  const { label, sinceIso, octokit } = args;
  const sinceMs = new Date(sinceIso).getTime();
  if (Number.isNaN(sinceMs)) {
    // A NaN lower bound makes every `>=` comparison false and would silently
    // red-flag a healthy producer. Surface the bad input loudly instead.
    throw new Error(
      `verifyScheduledIssueCreated: invalid sinceIso "${sinceIso}"`,
    );
  }

  const client = octokit ?? (await createProbeOctokit());
  const res = await client.request("GET /repos/{owner}/{repo}/issues", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    labels: label,
    state: "all",
    // `since` filters by updated_at server-side (create OR comment in window).
    since: sinceIso,
    sort: "updated",
    direction: "desc",
    per_page: 5,
    headers: { "X-GitHub-Api-Version": "2022-11-28" },
  });

  // Belt-and-suspenders client-side guard (the server `since` is inclusive and
  // authoritative; this defends against a stub/mock that ignores `since`).
  const issues = res.data as Array<{ updated_at: string }>;
  return issues.some(
    (issue) => new Date(issue.updated_at).getTime() >= sinceMs,
  );
}

// ---------------------------------------------------------------------------
// Cohort digest-title date pin (#6143) — platform-injected run-date sentinel.
//
// Every "always-create digest" cron files an issue titled `[Scheduled] <task> -
// <date>`. The code-level same-date dedup key is `runStartedAt.slice(0,10)`
// (host UTC, captured in the handler), but the title date was previously derived
// by the spawned eval from its OWN container clock. Across a UTC-midnight boundary
// the two could diverge, so isRealScheduledDigest's exact-title match could MISS
// (→ duplicate) or OVER-suppress. injectRunDate replaces the `{{RUN_DATE}}`
// sentinel in each cohort prompt at spawn time with runStartedAt.slice(0,10), so
// the ISSUE-TITLE date is PINNED byte-identical to the dedup key (both read the
// same `step.run("run-started-at")`-memoized runStartedAt, so they agree across
// Inngest replays/retries).
//
// THROWS if the sentinel is absent so a forgotten wiring is loud (a literal
// "{{RUN_DATE}}" title would silently defeat both dedup and the output-aware
// verify). Pins the issue-TITLE date ONLY — the sole input to the dedup key;
// secondary agent-derived dates (digest FILE names, publish_date frontmatter,
// audit-report paths) stay agent-derived. `{{RUN_DATE}}` is collision-free (no
// `{{` token exists in any cohort prompt). `.replaceAll` is available (tsconfig
// ES2022; already used above in this file).
// ---------------------------------------------------------------------------
export const RUN_DATE_SENTINEL = "{{RUN_DATE}}";

export function injectRunDate(prompt: string, runStartedAt: string): string {
  if (!prompt.includes(RUN_DATE_SENTINEL)) {
    throw new Error(`injectRunDate: prompt is missing ${RUN_DATE_SENTINEL}`);
  }
  return prompt.replaceAll(RUN_DATE_SENTINEL, runStartedAt.slice(0, 10));
}

// ---------------------------------------------------------------------------
// Producer-side date-dedup (#5751) — "does a REAL `${label}` digest already
// exist for <date>?" so a second serialized invocation (the 08:00 cron + an
// operator manual-trigger, or a doubled delivery) does NOT file a duplicate
// full digest. Distinct from BOTH siblings:
//   - verifyScheduledIssueCreated reads the RUN WINDOW (updated_at >= a single
//     invocation's runStartedAt) for the heartbeat; this reads the whole day.
//   - ensureScheduledAuditIssue's title-dedup INTENTIONALLY counts FAILED/audit
//     stubs (to avoid double-auditing); this read EXCLUDES them so a same-day
//     recovery still files the real digest (zero-digest guard, P1).
//
// Fresh LIST/REST index (GET /issues?labels=…), NOT the in-prompt
// `gh issue list --search '… in:title'`: the search index lags minutes behind
// the primary index, so the second invocation's search did not see the first's
// issue (the #5751 H-C miss). concurrency:{scope:"fn",limit:1} serializes the
// two invocations, so the second's LIST read runs after the first's create.
//
// FAIL-OPEN (P1): a duplicate digest is a single-operator paper-cut; a MISSED
// digest blinds the only community-health signal. On any read error we report
// and return false (→ caller spawns), mirroring resolveOutputAwareOk's
// verify-throw fallback. The octokit is injectable purely for unit tests.
// ---------------------------------------------------------------------------

// Single-sourced contract strings (#5751 review). The stub-exclusion predicate
// (isRealScheduledDigest) and the producers that MINT these shapes must move
// together — independent drift silently breaks the zero-digest guard (a digest
// whose title/body no longer matches gets misclassified, suppressing the real
// one). The community-monitor handler passes SCHEDULED_DIGEST_TITLE_PREFIX as
// its ensureScheduledAuditIssue `titlePrefix`; ensureScheduledAuditIssue mints
// the audit body from AUDIT_SELF_REPORT_BODY_PREFIX.
//
// #5786 — the matcher is now per-cron parametrized. Each of the 7 dedup-sweep
// crons passes its OWN `titlePrefix`, a per-cron string literal that MUST stay
// byte-identical to that handler's three co-located copies (the prompt digest
// title, the `dedup-digest-check` titlePrefix, and the `ensureScheduledAuditIssue`
// titlePrefix). These are NOT single-sourced via a shared const — keep them in
// lockstep on any rename. Drift is fail-OPEN (a mismatch makes the anchor miss →
// a duplicate digest, never a missed/zero digest), so it is a maintenance nit,
// not a zero-digest hazard. Community-monitor passes SCHEDULED_DIGEST_TITLE_PREFIX
// explicitly (byte-identical to the old behavior).
// `titleSuffix` is "" for the 6 always-create crons + community-monitor, and
// " (heartbeat)" for campaign-calendar (its STEP 2.5 producer digest carries a
// trailing ` (heartbeat)` suffix that the exact anchor must accept; its bare
// FAILED-audit fallback title — no suffix — is correctly rejected by the
// title check, so the body-exclusion arm is redundant-but-harmless there).
export const SCHEDULED_DIGEST_TITLE_PREFIX = "[Scheduled] Community Monitor -";
export const AUDIT_SELF_REPORT_BODY_PREFIX = "Automated FAILED self-report";

/**
 * Pure predicate: is `issue` a REAL scheduled digest for `date` (YYYY-MM-DD)?
 * Positive title-shape anchor: ONLY the exact canonical digest title for `date`
 * (`${titlePrefix} ${date}${titleSuffix}`) counts. This excludes a
 * coincidental-date issue (e.g. `Investigate community drop <date>`) and an
 * LLM-drifted `… - FAILED - <date>` title — both of which an `endsWith(date)`
 * check would misclassify as a real digest and suppress the genuine one. The
 * handler-level audit fallback files the BYTE-IDENTICAL `${titlePrefix} ${date}`
 * title (no suffix), so it is excluded by body.
 *
 * @param titlePrefix per-cron canonical prefix (= its ensureScheduledAuditIssue
 *   titlePrefix); pass SCHEDULED_DIGEST_TITLE_PREFIX for community-monitor.
 * @param titleSuffix "" for the always-create crons + community-monitor;
 *   " (heartbeat)" for campaign-calendar's suffixed producer digest.
 */
export function isRealScheduledDigest(
  issue: { title?: string | null; body?: string | null },
  date: string,
  titlePrefix: string,
  titleSuffix = "",
): boolean {
  const title = (issue.title ?? "").trim();
  // Positive anchor: ONLY the exact canonical digest title for THIS date counts.
  // Excludes coincidental-date issues and the no-platform `- FAILED` title.
  // Fail-OPEN on title drift: a slightly-different title → no dedup → a duplicate
  // (paper-cut), never zero-digest.
  if (title !== `${titlePrefix} ${date}${titleSuffix}`) return false;
  // Audit fallback files the BYTE-IDENTICAL title → exclude it by body.
  if ((issue.body ?? "").startsWith(AUDIT_SELF_REPORT_BODY_PREFIX)) return false;
  return true;
}

/**
 * Is `path` present on the repo's DEFAULT BRANCH? (#6714 Phase 3.4.)
 *
 * The date-dedup above asserts only that a labelled *issue* exists — which is
 * exactly the wrong artifact. Observed failure shape: run 1 files a genuine
 * digest issue but never lands the commit; run 2 dedups on that issue and posts
 * GREEN with no artifact. This is the cheap contents read that lets the caller
 * tell the two apart before short-circuiting.
 *
 * FAIL-CLOSED-FOR-DEDUP, deliberately: any error (including the 404 that means
 * "not committed") returns `false`, i.e. "not proven committed", so the caller
 * spawns. That matches the sibling dedup read's fail-open-to-spawning stance —
 * a duplicate digest is a paper cut, a missing digest is the bug this closes.
 */
export async function digestCommittedOnDefaultBranch(args: {
  path: string;
  cronName: string;
  octokit?: Awaited<ReturnType<typeof createProbeOctokit>>;
}): Promise<boolean> {
  const { path, cronName, octokit } = args;
  try {
    const client = octokit ?? (await createProbeOctokit());
    await client.request("GET /repos/{owner}/{repo}/contents/{path}", {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      path,
      ref: "main",
      headers: { "X-GitHub-Api-Version": "2022-11-28" },
    });
    return true;
  } catch (err) {
    // A 404 is the EXPECTED negative (no digest committed) and must stay quiet —
    // mirroring it to Sentry would page daily on the healthy first-run path. Any
    // other status is a genuine read fault; it is reported, and it also returns
    // false, so the run spawns rather than silently deduping on an unknown.
    const status = (err as { status?: number }).status;
    if (status !== 404) {
      reportSilentFallback(err, {
        feature: cronName,
        op: "digest-commit-read-failed",
        message: `Could not read ${path} on the default branch (treating as NOT committed → will spawn)`,
        extra: { fn: cronName, path },
      });
    }
    return false;
  }
}

export async function digestIssueExistsForDate(args: {
  label: string;
  date: string;
  cronName: string;
  titlePrefix: string;
  titleSuffix?: string;
  octokit?: Awaited<ReturnType<typeof createProbeOctokit>>;
}): Promise<boolean> {
  const { label, date, cronName, titlePrefix, titleSuffix = "", octokit } = args;
  try {
    const client = octokit ?? (await createProbeOctokit());
    // Explicit sort:created desc + per_page:10 so today's issue is guaranteed on
    // page 1 (matches ensureScheduledAuditIssue's dedup read shape).
    const res = await client.request("GET /repos/{owner}/{repo}/issues", {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      state: "all",
      labels: label,
      sort: "created",
      direction: "desc",
      per_page: 10,
      headers: { "X-GitHub-Api-Version": "2022-11-28" },
    });
    const issues = res.data as Array<{ title?: string | null; body?: string | null }>;
    return issues.some((i) => isRealScheduledDigest(i, date, titlePrefix, titleSuffix));
  } catch (err) {
    // Fail-OPEN: a transient GitHub error must not become a missed digest.
    reportSilentFallback(err, {
      feature: cronName,
      op: "digest-dedup-read-failed",
      message: `Could not read ${label} digests for date-dedup (failing OPEN → will spawn)`,
      extra: { fn: cronName, label, date },
    });
    return false;
  }
}

// ---------------------------------------------------------------------------
// Output-aware heartbeat resolver — the value each always-create producer
// feeds to postSentryHeartbeat instead of the bare spawn exit code.
//
// For an output-producer, the OUTPUT (the `scheduled-<task>` issue in the run
// window) IS the success contract — not the claude exit code. So output is
// checked FIRST and overrides the exit code. A claude run can produce its issue
// and still exit non-zero on a trailing best-effort step (e.g. a conditional
// `git push`/PR after the issue is filed, or hitting --max-turns after the
// output step); that is a healthy run, not a monitor-red event. (Observed:
// competitive-analysis created issue #4747 yet exited non-zero — the old
// `if (!spawnOk) return false` short-circuit false-red'd it before checking
// output. #4714 follow-up.)
//
// Semantics:
//   - issue PRESENT in window → ok:true (green), regardless of exit code. If
//     the spawn ALSO exited non-zero, emit a non-paging WARN
//     (`scheduled-output-nonzero-exit`) so the trailing failure is visible
//     without paging — output succeeded.
//   - issue ABSENT + spawn ok  → ok:false + `scheduled-output-missing` (the
//     silent-no-op this whole mechanism targets).
//   - issue ABSENT + spawn failed → ok:false (the spawn error is already
//     reported upstream; no output AND a hard exit is unambiguously red).
//   - verify THREW             → fall back to the spawn exit code (do not
//     red-flag a possibly-successful run on a GitHub-list hiccup) +
//     `verify-output-failed` event so the inconclusive check is visible.
//
// Used by the always-create spawn producers (roadmap, content, competitive);
// strategy-review is pure-TS and legitimately creates zero issues on an
// all-clean run, so it keeps its errors-based heartbeat.
export async function resolveOutputAwareOk(args: {
  spawnOk: boolean;
  label: string;
  runStartedAt: string;
  cronName: string;
  octokit?: Awaited<ReturnType<typeof createProbeOctokit>>;
  // Bounded redacted stderr tail from the claude-eval spawn; folded into the
  // scheduled-output-missing Sentry event so a non-zero exit is self-diagnosing
  // (app stdout is not shipped to the log warehouse).
  stderrTail?: string;
  // Raw spawn exit code, surfaced in the scheduled-output-missing extra so a
  // turn-exhaustion exit can be distinguished from a hard failure without SSH
  // (#4684/#4689). Optional — sites that do not hold the SpawnResult omit it.
  exitCode?: number | null;
  // Bounded redacted stdout tail from the claude-eval spawn. `claude --print`
  // writes its max-turns notice to stdout, not stderr — folding it into the
  // scheduled-output-missing extra makes a turn-exhaustion exit self-diagnosing
  // without SSH (app stdout is not shipped to the log warehouse). #4773.
  stdoutTail?: string;
}): Promise<boolean> {
  const {
    spawnOk,
    label,
    runStartedAt,
    cronName,
    octokit,
    stderrTail,
    exitCode,
    stdoutTail,
  } = args;

  let issueCreated: boolean;
  try {
    issueCreated = await verifyScheduledIssueCreated({
      label,
      sinceIso: runStartedAt,
      octokit,
    });
  } catch (err) {
    reportSilentFallback(err, {
      feature: cronName,
      op: "verify-output-failed",
      message: `Could not verify ${label} output (heartbeat left at spawn result)`,
      extra: { fn: cronName, label, runStartedAt },
    });
    // Inconclusive — fall back to the spawn exit code rather than red-flagging
    // a possibly-successful run on a transient GitHub-list failure.
    return spawnOk;
  }

  if (issueCreated) {
    // Output is the success contract. A non-zero exit AFTER producing output is
    // a non-paging warning, not a red monitor.
    if (!spawnOk) {
      warnSilentFallback(
        new Error(
          `${cronName} produced its "${label}" issue but the claude-eval spawn exited non-zero (trailing best-effort step or max-turns after output)`,
        ),
        {
          feature: cronName,
          op: "scheduled-output-nonzero-exit",
          message: "Producer created its output issue despite a non-zero spawn exit",
          extra: { fn: cronName, label, runStartedAt },
        },
      );
    }
    return true;
  }

  // No output. Distinguish "exited cleanly but produced nothing" (the silent
  // no-op) from "spawn hard-failed" (already reported upstream) for the event
  // op, but both are red.
  reportSilentFallback(
    new Error(
      spawnOk
        ? `${cronName} exited 0 but created no "${label}" issue in the run window (since ${runStartedAt})`
        : `${cronName} spawn exited non-zero AND created no "${label}" issue in the run window (since ${runStartedAt})`,
    ),
    {
      feature: cronName,
      op: "scheduled-output-missing",
      message: "Scheduled producer produced no output issue",
      extra: {
        fn: cronName,
        label,
        runStartedAt,
        spawnOk,
        // Raw spawn exit code — distinguishes a turn-exhaustion exit from a hard
        // failure at a glance, alongside the stderr tail below.
        exitCode,
        // The claude-eval stderr tail is the diagnostic payload — without it the
        // non-zero-exit reason lives only in app stdout, which is not shipped.
        // #5674 F1: route through the canonical MULTI-secret scrubber (was
        // redactToken-only at the substrate → an sk-ant-… in a crash stack
        // reached this durable Sentry extra unscrubbed). formatTailForSentry
        // applies redactGithubSourcedText + the 4000-char bound.
        stderrTail: formatTailForSentry(stderrTail),
        // The stdout tail carries the `claude --print` max-turns notice (written
        // to stdout, not stderr) — same diagnostic role as stderrTail. #4773.
        stdoutTail: formatTailForSentry(stdoutTail),
      },
    },
  );
  return false;
}

// ---------------------------------------------------------------------------
// Eval failure-reason capture + classify-fatal heartbeat (#5674).
//
// Two observability bugs the 2026-06-29 credit-exhaustion incident exposed:
//   (1) the captured stdout/stderr tail (where "Credit balance is too low"
//       actually lives) was DROPPED at the Sentry-extra layer of the 4 masked
//       best-effort crons — only { exitCode, durationMs } reached Sentry;
//   (2) those 4 crons posted a GREEN check-in regardless of WHY claude exited
//       non-zero, so a credit-exhausted run was indistinguishable from a clean
//       no-artifact run at the monitor level.
//
// The fix is classify-fatal (NOT flip-all): a non-zero exit whose tail matches a
// FATAL class (credit exhausted / auth revoked / spawn fault / timeout) flips the
// monitor RED and records the scrubbed reason; a BENIGN non-zero exit (max-turns,
// clean no-artifact) stays GREEN (liveness) but still surfaces the reason. This
// reconciles the 2026-06-01 #4730/#4727 decision that decoupled the heartbeat
// from spawnResult.ok precisely because `claude --print` exits non-zero on
// healthy max-turns runs (flip-all would reintroduce that daily false-page).
// ---------------------------------------------------------------------------

// Sentry-extra readability bound for spawn tails. The durable Sentry event holds
// more than the 500-char GitHub-issue body (formatTailForIssue), so a fuller tail
// is available for triage. Single source of truth for the Sentry-tail bound.
const SENTRY_TAIL_CHARS = 4000;

/**
 * Multi-secret scrubber + bounded slice for any spawn tail (or Anthropic error
 * body excerpt) bound for a DURABLE Sentry extra. The eval substrate only applies
 * `redactToken` (installation token); a crash stack can still spill `sk-ant-…` /
 * other allowlisted-env secrets, so EVERY new Sentry tail sink MUST route through
 * here — the single source of truth so the 8 output-aware + 4 best-effort sites
 * cannot drift on redaction discipline (#5674 F1, hr-write-boundary-sentinel-sweep).
 * Scrub BEFORE slice so a secret straddling the boundary is still caught; returns
 * `undefined` for empty/absent input so callers can omit the key entirely.
 */
export function formatTailForSentry(tail?: string): string | undefined {
  const scrubbed = redactGithubSourcedText(tail ?? "").slice(-SENTRY_TAIL_CHARS);
  return scrubbed || undefined;
}

// Single source of truth for the FATAL-class claude-eval / Anthropic failure
// markers — the classes that MUST flip a best-effort cron monitor RED. Shared by
// resolveBestEffortEvalOk AND the cron-anthropic-credit-probe canary so the
// credit/auth pattern cannot drift (#5674 R1). Keep this set SMALL, centralized,
// and fixture-pinned against the real incident tail: classify-by-string-match is
// brittle to Anthropic copy changes, so an UNMATCHED non-zero exit degrades to
// benign-but-recorded (green + reason in Sentry), never a silent drop.
export const ANTHROPIC_CREDIT_EXHAUSTED_RE = /credit balance is too low/i;
export const ANTHROPIC_AUTH_FAILURE_RE =
  /invalid x-api-key|authentication_error|\binvalid api key\b/i;
// Spawn-fault markers in a captured tail (the child never really ran).
const SPAWN_FAULT_RE = /\b(ENOENT|EACCES|EPERM)\b/;

export type EvalFatalClass =
  | "credit-exhausted"
  | "auth-failure"
  | "spawn-fault"
  | "timeout";

/**
 * Classify a non-zero claude-eval spawn result as FATAL (must page) or benign.
 * Pure + tail-driven so it is unit-testable against the real incident stdout.
 */
export function classifyEvalFatal(
  spawnResult: Pick<
    SpawnResult,
    "exitCode" | "abortedByTimeout" | "stdoutTail" | "stderrTail"
  >,
): { fatal: boolean; fatalClass?: EvalFatalClass; reason?: string } {
  if (spawnResult.abortedByTimeout) {
    return {
      fatal: true,
      fatalClass: "timeout",
      reason: "claude-eval aborted by timeout (50-min budget exceeded)",
    };
  }
  // exitCode === -1 is the substrate's spawn-error sentinel (child never started).
  if (spawnResult.exitCode === -1) {
    return {
      fatal: true,
      fatalClass: "spawn-fault",
      reason: "claude-eval spawn fault (child process failed to start)",
    };
  }
  const tail = `${spawnResult.stdoutTail ?? ""}\n${spawnResult.stderrTail ?? ""}`;
  if (ANTHROPIC_CREDIT_EXHAUSTED_RE.test(tail)) {
    return {
      fatal: true,
      fatalClass: "credit-exhausted",
      reason: "Anthropic credit balance is too low (operator API credit exhausted)",
    };
  }
  if (ANTHROPIC_AUTH_FAILURE_RE.test(tail)) {
    return {
      fatal: true,
      fatalClass: "auth-failure",
      reason: "Anthropic API authentication failure (invalid/revoked operator key)",
    };
  }
  if (SPAWN_FAULT_RE.test(tail)) {
    return {
      fatal: true,
      fatalClass: "spawn-fault",
      reason: "claude-eval spawn fault (ENOENT/EACCES in tail)",
    };
  }
  return { fatal: false };
}

// The contract BOTH eval-heartbeat resolvers emit so all eval crons get equal
// routine_runs / Sentry fidelity through one shape. `errorSummary` (scrubbed,
// when present) is what the run-log middleware records on a returned ok:false;
// `sentryExtra` carries the scrubbed tails the handler folds into its Sentry event.
export interface EvalHeartbeatDecision {
  ok: boolean;
  errorSummary?: string;
  sentryExtra: Record<string, unknown>;
}

/**
 * Best-effort claude-eval heartbeat resolver (classify-fatal). For crons where
 * the OUTPUT is not a queryable GitHub issue (the 4 "masked" crons), this decides
 * the monitor color from the spawn tail rather than the bare exit code:
 *   - clean exit (ok)            → ok:true, no reason
 *   - FATAL non-zero             → ok:false + scrubbed reason (monitor red + routine_runs.failed)
 *   - BENIGN non-zero (default)  → ok:true + reason in sentryExtra (green liveness, queryable, no page)
 * The scrubbed tails are always in `sentryExtra` so even a green run is self-diagnosing.
 */
export function resolveBestEffortEvalOk(
  spawnResult: Pick<
    SpawnResult,
    "ok" | "exitCode" | "abortedByTimeout" | "durationMs" | "stdoutTail" | "stderrTail"
  >,
): EvalHeartbeatDecision {
  const sentryExtra: Record<string, unknown> = {
    exitCode: spawnResult.exitCode,
    durationMs: spawnResult.durationMs,
    abortedByTimeout: spawnResult.abortedByTimeout,
    stdoutTail: formatTailForSentry(spawnResult.stdoutTail),
    stderrTail: formatTailForSentry(spawnResult.stderrTail),
  };

  if (spawnResult.ok) {
    return { ok: true, sentryExtra };
  }

  const fatal = classifyEvalFatal(spawnResult);
  if (fatal.fatal) {
    return {
      ok: false,
      errorSummary: fatal.reason,
      sentryExtra: { ...sentryExtra, fatalClass: fatal.fatalClass },
    };
  }

  // Benign non-zero (max-turns / clean no-artifact) — the #4730 carve-out (R1):
  // stays GREEN, but the reason rides along in sentryExtra so a chronically-broken
  // -but-live cron is diff-able week over week without paging.
  return {
    ok: true,
    errorSummary: `claude-eval exited non-zero (benign, no artifact this cycle): exit ${spawnResult.exitCode}`,
    sentryExtra: { ...sentryExtra, fatalClass: "benign" },
  };
}

// ---------------------------------------------------------------------------
// Handler-level silence-hole fallback (#4960, generalized #4978).
//
// When the output-aware heartbeat (resolveOutputAwareOk) finds NO labeled issue
// in the run window — the prompt's "create the audit issue" step never ran
// (mid-eval crash / upstream API 500 / max-turns kill) — the handler ITSELF
// files a self-reporting FAILED `${titlePrefix} <date>` issue so the run is
// never silent and the cron-cloud-task-heartbeat watchdog stays green. It lives
// ABOVE the prompt, surviving any termination that bypasses the in-prompt steps.
//
// Extracted VERBATIM from cron-content-generator (PR #4975, fired in prod via
// #4982) and parameterized by { label, titlePrefix, cronName } so all 8
// always-create producers share ONE security-vetted redaction path instead of
// 8 drifting copies.
// ---------------------------------------------------------------------------

// GitHub-issue-body readability bound for the spawn tails. Tighter than the
// 4000-char Sentry extra (resolveOutputAwareOk) — the issue body is for
// at-a-glance triage, the full tail already lives in the Sentry event.
const DEFAULT_AUDIT_TAIL_CHARS = 500;

// The spawn tails are token-redacted by the eval substrate (redactToken), but
// that strips ONLY the installation token — a crash stack can still spill other
// allowlisted-env secrets (e.g. ANTHROPIC_API_KEY / sk-ant-…). Route through the
// canonical multi-secret scrubber before it lands in a GitHub issue body, and
// neutralize backtick/pipe/newline so untrusted eval output cannot break out of
// the inline-code table cell into rendered markdown (image-autofetch / banner
// injection). Mirrors the github-sourced-text redaction discipline.
export function formatTailForIssue(tail: string | undefined): string {
  const scrubbed = redactGithubSourcedText(tail ?? "").slice(
    -DEFAULT_AUDIT_TAIL_CHARS,
  );
  if (!scrubbed) return "(empty)";
  return scrubbed
    .replace(/[\r\n]+/g, " ")
    // Escape pre-existing backslashes BEFORE introducing our own `\|` escape,
    // so an input like `\|` cannot produce an ambiguous escape sequence
    // (js/incomplete-sanitization). Order is load-bearing.
    .replace(/\\/g, "\\\\")
    .replace(/\|/g, "\\|")
    .replace(/`/g, "ʼ");
}

export async function ensureScheduledAuditIssue(args: {
  label: string;
  titlePrefix: string;
  cronName: string;
  runStartedAt: string;
  spawnResult: Pick<
    SpawnResult,
    "exitCode" | "signal" | "abortedByTimeout" | "durationMs" | "stdoutTail" | "stderrTail"
  >;
  installationToken?: string;
  octokit?: Octokit;
}): Promise<{ created: boolean }> {
  const {
    label,
    titlePrefix,
    cronName,
    runStartedAt,
    spawnResult,
    installationToken,
    octokit,
  } = args;

  // Replay-stable UTC date anchor (NOT `new Date()`, which would drift across
  // the retries:1 replay and defeat the title-dedup below).
  const date = runStartedAt.slice(0, 10);
  // titlePrefix ends in ` -` (no trailing space); the single-space join yields
  // the byte-identical `${prefix} <date>` form the prompt emits on success.
  const title = `${titlePrefix} ${date}`;

  let client = octokit;
  if (!client) {
    if (!installationToken) {
      throw new Error(
        "ensureScheduledAuditIssue: need octokit or installationToken",
      );
    }
    const { Octokit: OctokitCtor } = await import("@octokit/core");
    client = new OctokitCtor({ auth: installationToken }) as unknown as Octokit;
  }

  // Dedup: a transient failure that re-runs this path could file a second
  // FAILED issue. Skip the create if today's audit issue already exists
  // (success or fallback). Explicit `sort: created, direction: desc` so today's
  // issue is guaranteed on page 1 — do NOT rely on GitHub's unspecified default
  // sort for dedup correctness (a busy label could otherwise page today's issue
  // out and double-file). per_page:10 covers ≥1 week of any wired producer's
  // cadence (daily through monthly) — ample to keep today's issue on page 1.
  // This dedup is load-bearing (not belt-and-suspenders): on a
  // verify-throw + spawn-nonzero run the gate fires even though the prompt's
  // issue may exist — the same-title dedup is what prevents a spurious second.
  const existing = (await client.request("GET /repos/{owner}/{repo}/issues", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    state: "all",
    labels: label,
    sort: "created",
    direction: "desc",
    per_page: 10,
    headers: { "X-GitHub-Api-Version": "2022-11-28" },
  })) as { data: Array<{ title: string }> };
  if (existing.data.some((i) => i.title.startsWith(title))) {
    return { created: false };
  }

  // Self-diagnosing body — the cron's own redacted spawn tail + timing, so the
  // failure is triageable without SSH (app stdout is not shipped to Better
  // Stack). The tails are already token-redacted by the eval substrate.
  const body =
    `${AUDIT_SELF_REPORT_BODY_PREFIX} from \`${cronName}\`.\n\n` +
    `This run terminated WITHOUT producing a \`${label}\` ` +
    `audit issue via the prompt (mid-eval crash / upstream API error / ` +
    `max-turns kill). The handler-level fallback (#4960) filed this issue so ` +
    `the run is not silent and the \`cron-cloud-task-heartbeat\` watchdog ` +
    `stays green.\n\n` +
    `| Signal | Value |\n| --- | --- |\n` +
    `| fn | \`${cronName}\` |\n` +
    `| runStartedAt | \`${runStartedAt}\` |\n` +
    `| exitCode | \`${spawnResult.exitCode}\` |\n` +
    `| signal | \`${spawnResult.signal}\` |\n` +
    `| abortedByTimeout | \`${spawnResult.abortedByTimeout}\` |\n` +
    `| durationMs | \`${spawnResult.durationMs}\` |\n` +
    `| stdoutTail | \`${formatTailForIssue(spawnResult.stdoutTail)}\` |\n` +
    `| stderrTail | \`${formatTailForIssue(spawnResult.stderrTail)}\` |\n\n` +
    `Triage: \`knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md\` (H2).`;

  await client.request("POST /repos/{owner}/{repo}/issues", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    title,
    body,
    labels: [label],
  });
  return { created: true };
}

/**
 * Stable-title, open-issue dedup sibling of `ensureScheduledAuditIssue`, for a
 * STANDING condition (e.g. content starvation) rather than a dated per-run audit
 * stub. Reuses that helper's read shape verbatim — `GET .../issues` with
 * `labels`, `sort: created, direction: desc, per_page: 10` — but:
 *   - matches the EXACT title (a standing alert has one canonical title, no
 *     date suffix — a persisting condition files ONE issue, not one per run), and
 *   - scopes the dedup read to `state: "open"` so an auto-CLOSED prior alert
 *     never suppresses a fresh occurrence after a recovery (the standing-alert
 *     lifecycle: fire → auto-close on recovery → re-fire on the next drought).
 *
 * Caller passes a ready Octokit (this helper does no minting) — the starvation
 * check runs inside a failure-isolated try/catch and reuses the handler's token.
 */
export async function ensureDedupIssue(
  client: Octokit,
  args: { title: string; body: string; labels: string[] },
): Promise<{ created: boolean; issueNumber?: number }> {
  const { title, body, labels } = args;
  const existing = (await client.request("GET /repos/{owner}/{repo}/issues", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    state: "open",
    labels: labels.join(","),
    sort: "created",
    direction: "desc",
    per_page: 10,
    headers: { "X-GitHub-Api-Version": "2022-11-28" },
  })) as { data: Array<{ title: string; number: number }> };
  const match = existing.data.find((i) => i.title === title);
  if (match) return { created: false, issueNumber: match.number };

  const created = (await client.request("POST /repos/{owner}/{repo}/issues", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    title,
    body,
    labels,
  })) as { data: { number: number } };
  return { created: true, issueNumber: created.data.number };
}
