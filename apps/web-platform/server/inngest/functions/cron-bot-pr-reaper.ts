/**
 * cron-bot-pr-reaper — stale bot-PR sweep (#9274).
 *
 * WHY THIS EXISTS: `app/soleur-ai` cron-artifact PRs (daily digests,
 * architecture-sync, growth-audit, vendor-drift, campaign-calendar) arm
 * SQUASH auto-merge, but GitHub cannot auto-merge a PR whose
 * `mergeable_state` is `"behind"` under the repo's strict up-to-date rules —
 * and nothing updated the branch, so digests 2026-09-27→30 sat unmerged while
 * every monitor stayed green. This sweep is the actor: every 2 h it re-bases
 * eligible bot PRs via `PUT /pulls/{n}/update-branch` so auto-merge can fire.
 *
 * MERGE QUEUE (ADR-270): when `main` carries a `merge_queue` rule the queue
 * makes an armed BEHIND PR current itself (GitHub enqueues it once green) and a
 * resync push only restarts every required check. So the behind arm defers: a
 * `queue` or `unreadable` verdict (fail closed — an unknown answer is never
 * read as "no queue") never reaches update-branch. A PR GitHub still has not
 * enqueued is LOUD instead: past 6 h with terminal checks, or past 24 h
 * whatever its checks, it joins the stuck-alert arm. The verdict is read once
 * per sweep by the memoized `read-merge-queue-rule` step and passed by value.
 *
 * ANTI-LIVELOCK DISCIPLINE (learning 2026-06-02-auto-merge-livelock): a
 * monitor that updates on EVERY `behind` state feeds the loop it watches —
 * each merge re-`behind`s the rest under strict rules, so an uncapped sweep
 * is O(N²) merge commits and floods the runner pool queue-health measures.
 * Bounds: (a) settle-guard — a PR whose head has `queued`/`in_progress` check
 * runs is never updated mid-verdict; (b) `expected_head_sha` CAS — a 422
 * sha-mismatch means the head moved between settle and update, skip quietly;
 * (c) at most `MAX_UPDATES_PER_SWEEP` update-branch calls per fire,
 * oldest-first; (d) a 2-h cadence so one PR is updated at most once per sweep.
 *
 * Alert arm: a bot PR unmergeable for reasons update-branch cannot fix
 * (`dirty` conflict, `blocked` review/check gate, `unstable` red checks) is
 * collected into the dedup-by-title `[ci/bot-pr-reaper]` action-required
 * issue + one aggregated reportSilentFallback — a silent stall is the failure
 * this cron exists to remove, so a stuck PR must be LOUD, not skipped.
 *
 * Only bot-generated fields (PR number, `ci/*` head ref, state enum) reach
 * the issue body / Sentry extras — never attacker-writable fields like PR
 * titles.
 *
 * Population complement (deliberate asymmetry): this sweep covers
 * `user.login == soleur-ai[bot]` + armed auto-merge. The 48h stale-bot-PR
 * watchdog inside cron-cloud-task-heartbeat (#5138) instead keys on head-ref
 * prefixes (ci/, self-healing/auto-, bot-fix/, soleur/inngest-pin-) — a
 * DISARMED bot PR is invisible here but still watched there, and vice versa.
 * sentry_alert.stale_bot_pr is also the interim cover while this function's
 * own monitor sits declared-unrouted (two-PR rule).
 */
import { inngest } from "@/server/inngest/client";
import { delay, withGithubRetry } from "@/server/github-retry";
import {
  ensureDedupIssue,
  findDedupIssue,
  type HandlerArgs,
  mintInstallationToken,
  postSentryHeartbeat,
  redactToken,
  REPO_NAME,
  REPO_OWNER,
} from "./_cron-shared";
import { reportSilentFallback } from "@/server/observability";
import type { Octokit } from "@octokit/core";

const FUNCTION_NAME = "cron-bot-pr-reaper";
const SENTRY_MONITOR_SLUG = "scheduled-bot-pr-reaper";
const BOT_LOGIN = "soleur-ai[bot]";
// ~24 armed bot PRs are open (measured 2026-09-30, oldest 2026-08-04); an
// uncapped first sweep would fire ~24 check-run sets into the runner pool this
// repo's own queue-health monitor measures. Arrival rate is ~1/day, so 5/sweep
// drains the backlog in ~5 sweeps and keeps it drained.
const MAX_UPDATES_PER_SWEEP = 5;
// mergeable_state is lazily computed; "unknown" on first read is normal.
const UNKNOWN_REREAD_DELAY_MS = 15_000;
// mergeable_state "unknown" re-reads sleep 15s serially per PR; a sweep-sized
// backlog of unknowns (~35+) would ride the installation token's
// TOKEN_MIN_LIFETIME_MS edge — cap the sleeps, still-uncapped PRs get a free
// (0ms) second read and defer to the next 2h sweep if still unknown.
const UNKNOWN_REREAD_CAP = 5;
const TOKEN_MIN_LIFETIME_MS = 10 * 60 * 1000;
// Residual (ADR-270 addendum 2026-10-22): the PR list is not base-filtered, so
// the queue verdict is read for `main` only.
const BASE_BRANCH = "main";
// Measured enqueue of an armed BEHIND PR is 9-47 min; past 6 h with terminal
// checks GitHub is not going to enqueue it, so alert (never resync).
const QUEUE_ENQUEUE_GRACE_MS = 6 * 60 * 60 * 1000;
// Hung or never-started checks must not hide a stranded PR forever.
const QUEUE_INFLIGHT_BOUND_MS = 24 * 60 * 60 * 1000;
// GET .../rules/branches defaults to 30 per page (max 100): without an explicit
// size a repo with more rules would truncate silently.
const RULES_PAGE_SIZE = 100;
const STUCK_ISSUE_TITLE =
  "[ci/bot-pr-reaper] bot PRs unmergeable without intervention";
// Producer-specific label first: the `action-required`+`domain/engineering`
// pair alone is high-population and the dedup read is page-1-bounded — a
// standing issue pushed off the page would refile a duplicate every sweep.
// `action-required` stays so the SLA escalation sweep still enrolls it.
const STUCK_ISSUE_LABELS = [
  "ci/bot-pr-reaper",
  "action-required",
  "domain/engineering",
];

// Rebuild a caught error with its message scrubbed — step errors escape to
// Inngest retries and `sentry-correlation` captureException where the
// installation token in an octokit message would be unredacted otherwise.
const redactErr = (err: unknown, token: string): Error => {
  const e = err as { name?: string; message?: unknown };
  const redacted = new Error(
    redactToken(typeof e.message === "string" ? e.message : String(e), token),
  );
  if (typeof e.name === "string") redacted.name = e.name;
  return redacted;
};

type PrListItem = {
  number: number;
  created_at: string;
  draft?: boolean;
  user?: { login?: string } | null;
  auto_merge?: unknown;
};

type PrDetail = {
  number: number;
  mergeable_state?: string;
  head: { sha: string };
};

export type QueueRuleVerdict = "queue" | "none" | "unreadable";

type StuckReason =
  | "queue-stalled"
  | "queue-stalled-checks-running"
  | "queue-rule-unreadable";

type SweepResult = {
  number: number;
  state: string;
  action:
    | "updated"
    | "skipped-checks-in-flight"
    | "skipped-head-moved"
    | "skipped-clean"
    | "skipped-state"
    | "skipped-unknown"
    | "skipped-update-cap"
    | "skipped-queue-owned"
    | "skipped-queue-unknown"
    | "stuck-alerted"
    | "error";
  // Only set on a queue/unknown behind PR that aged past its bound; the
  // dirty/blocked/unstable arm carries none.
  reason?: StuckReason;
};

// Neutral wording only: never "green", never a cause the code cannot know.
const STUCK_REASON_TEXT: Record<StuckReason, string> = {
  "queue-stalled":
    "armed, behind, not enqueued after 6h; checks complete, may include failures",
  "queue-stalled-checks-running":
    "armed, behind, not enqueued after 24h; checks still running",
  "queue-rule-unreadable":
    "armed, behind, merge-queue rule unreadable for over 6h",
};

async function readPrDetail(
  octokit: Octokit,
  prNumber: number,
): Promise<PrDetail> {
  const res = await withGithubRetry(() =>
    octokit.request("GET /repos/{owner}/{repo}/pulls/{pull_number}", {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      pull_number: prNumber,
    }),
  );
  return res.data as PrDetail;
}

async function checksTerminal(
  octokit: Octokit,
  headSha: string,
): Promise<boolean> {
  const res = await withGithubRetry(() =>
    octokit.request(
      "GET /repos/{owner}/{repo}/commits/{ref}/check-runs",
      {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        ref: headSha,
        filter: "latest",
        per_page: 100,
        headers: { "X-GitHub-Api-Version": "2022-11-28" },
      },
    ),
  );
  const runs = (res.data as { check_runs?: Array<{ status?: string }> })
    .check_runs ?? [];
  // Positive predicate: `waiting`/`requested`/`pending` are in-flight too —
  // anything not `completed` must not see an update-branch.
  return runs.every((r) => r.status === "completed");
}

/**
 * Does `main` carry a `merge_queue` ruleset rule? Never throws: every failure
 * (request error, non-list body, a full page without the rule so it may sit on
 * a later page) is `unreadable`, which callers treat as "do not update-branch".
 * The rule is selected by `.type`, never by position (it is not first live).
 */
export async function readMergeQueueRule(
  octokit: Octokit,
): Promise<{ verdict: QueueRuleVerdict; cause?: string }> {
  try {
    const res = await withGithubRetry(() =>
      octokit.request("GET /repos/{owner}/{repo}/rules/branches/{branch}", {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        branch: BASE_BRANCH,
        per_page: RULES_PAGE_SIZE,
        headers: { "X-GitHub-Api-Version": "2022-11-28" },
      }),
    );
    const rules: unknown = res.data;
    if (!Array.isArray(rules)) {
      return { verdict: "unreadable", cause: "rules response was not a list" };
    }
    if (
      rules.some(
        (r) => (r as { type?: unknown } | null)?.type === "merge_queue",
      )
    ) {
      return { verdict: "queue" };
    }
    if (rules.length >= RULES_PAGE_SIZE) {
      return {
        verdict: "unreadable",
        cause: "full rules page without merge_queue; the rule may be on a later page",
      };
    }
    return { verdict: "none" };
  } catch (err) {
    const e = err as { status?: number; message?: unknown };
    const msg = typeof e?.message === "string" ? e.message : String(err);
    return {
      verdict: "unreadable",
      cause: e?.status ? `status ${e.status}: ${msg}` : msg,
    };
  }
}

/**
 * Evaluate one bot PR. Never throws for a per-PR API failure — a transient
 * error on one PR must not fail the sweep; it is reported and recorded as
 * `error` so the heartbeat still lands.
 */
export async function reapBotPr(args: {
  octokit: Octokit;
  prNumber: number;
  updatesUsed: number;
  updatesCap: number;
  // REQUIRED on purpose: an optional/default would fail open (or break
  // silently) at a forgotten call site. Read once per sweep, passed by value.
  queueRule: QueueRuleVerdict;
  // PR creation time: a proxy for arm time (bot PRs are armed at creation).
  createdAt: string;
  nowMs?: number;
  // Sweep-level budget: only the first `cap` unknowns pay the 15s settle wait;
  // the rest re-read immediately (cheap) and skip if still unknown.
  unknownRereadBudget?: { used: number; cap: number };
  unknownRereadDelayMs?: number;
  logger: HandlerArgs["logger"];
}): Promise<SweepResult> {
  const {
    octokit,
    prNumber,
    updatesUsed,
    updatesCap,
    queueRule,
    createdAt,
    nowMs,
    unknownRereadBudget,
    unknownRereadDelayMs = UNKNOWN_REREAD_DELAY_MS,
    logger,
  } = args;

  let detail = await readPrDetail(octokit, prNumber);
  let state = detail.mergeable_state ?? "unknown";
  if (state === "unknown") {
    // Lazily computed — one re-read inside the step, then skip. Past the
    // sweep budget the re-read still happens but without the settle sleep.
    const settled =
      !unknownRereadBudget || unknownRereadBudget.used < unknownRereadBudget.cap;
    if (settled && unknownRereadBudget) unknownRereadBudget.used++;
    await delay(settled ? unknownRereadDelayMs : 0);
    detail = await readPrDetail(octokit, prNumber);
    state = detail.mergeable_state ?? "unknown";
    if (state === "unknown") {
      logger.warn(
        { fn: FUNCTION_NAME, pr: prNumber },
        "mergeable_state still unknown after re-read; skipping",
      );
      return { number: prNumber, state, action: "skipped-unknown" };
    }
  }

  const headSha = detail.head.sha;
  switch (state) {
    case "behind": {
      // FIRST, before the cap and before any check-runs read: a queue/unknown
      // verdict has no side effects inside the grace window and never reaches
      // update-branch (the queue makes the PR current itself).
      if (queueRule !== "none") {
        const unknown = queueRule === "unreadable";
        const age = (nowMs ?? Date.now()) - Date.parse(createdAt);
        // An unparseable timestamp counts as past both bounds: alert, never hide.
        const pastGrace = !Number.isFinite(age) || age > QUEUE_ENQUEUE_GRACE_MS;
        if (!pastGrace) {
          return {
            number: prNumber,
            state,
            action: unknown ? "skipped-queue-unknown" : "skipped-queue-owned",
          };
        }
        const pastInflight =
          !Number.isFinite(age) || age > QUEUE_INFLIGHT_BOUND_MS;
        const terminal = await checksTerminal(octokit, headSha);
        if (!terminal && !pastInflight) {
          return {
            number: prNumber,
            state,
            action: "skipped-checks-in-flight",
          };
        }
        return {
          number: prNumber,
          state,
          action: "stuck-alerted",
          reason: unknown
            ? "queue-rule-unreadable"
            : terminal
              ? "queue-stalled"
              : "queue-stalled-checks-running",
        };
      }
      if (updatesUsed >= updatesCap) {
        return { number: prNumber, state, action: "skipped-update-cap" };
      }
      if (!(await checksTerminal(octokit, headSha))) {
        // Never update-branch under an in-flight verdict — that is the
        // #8683/#4774 churn class.
        return {
          number: prNumber,
          state,
          action: "skipped-checks-in-flight",
        };
      }
      try {
        // The only update-branch writer under apps/web-platform/server; it is
        // reachable only with a "none" queue verdict (ADR-270 addendum).
        await octokit.request(
          "PUT /repos/{owner}/{repo}/pulls/{pull_number}/update-branch",
          {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            pull_number: prNumber,
            // CAS: binds the update to the head the settle-guard verified
            // terminal — a head the guard never saw must not be updated.
            expected_head_sha: headSha,
          },
        );
        return { number: prNumber, state, action: "updated" };
      } catch (err) {
        const e = err as { status?: number; message?: string };
        if (
          e.status === 422 &&
          typeof e.message === "string" &&
          /head/i.test(e.message)
        ) {
          // Head moved mid-sweep; next sweep re-evaluates.
          return {
            number: prNumber,
            state,
            action: "skipped-head-moved",
          };
        }
        throw err;
      }
    }
    case "dirty":
    case "blocked":
    case "unstable":
      // update-branch cannot fix a conflict, a required-review gate, or red
      // checks — route to the alert arm.
      return { number: prNumber, state, action: "stuck-alerted" };
    case "clean":
      return { number: prNumber, state, action: "skipped-clean" };
    case "draft":
    case "has_hooks":
      return { number: prNumber, state, action: "skipped-state" };
    default:
      // Forward-compat: a state outside the documented 8 is never assumed
      // updatable.
      logger.warn(
        { fn: FUNCTION_NAME, pr: prNumber, mergeable_state: state },
        "unrecognized mergeable_state; skipping",
      );
      return { number: prNumber, state, action: "skipped-state" };
  }
}

export async function cronBotPrReaperHandler({
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean; errorSummary?: string }> {
  const installationToken = await step.run(
    "mint-installation-token",
    async () =>
      mintInstallationToken({
        tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
        // Least-privilege for the sweep's exact call set: contents:write is
        // the load-bearing grant (update-branch on behalf of a GitHub App
        // requires contents write on the head repo — same-repo ci/* heads make
        // the repo-scoped grant sufficient); pull_requests:write for the PR
        // surface; issues:write for the dedup tracking issue; checks:read for
        // the settle-guard's check-runs read (an App token 403s without it).
        permissions: {
          contents: "write",
          pull_requests: "write",
          issues: "write",
          checks: "read",
        },
        repositories: [REPO_NAME],
      }),
  );

  // NOT a step: the client instance is not JSON-serializable, and step results
  // memoize across Inngest replays. Construction is a pure in-memory call, so
  // it is safe to rebuild on each replay.
  const { Octokit } = await import("@octokit/core");
  const octokit = new Octokit({ auth: installationToken });

  const botPrs = await step.run("list-open-bot-prs", async () => {
    const res = await withGithubRetry(() =>
      octokit.request("GET /repos/{owner}/{repo}/pulls", {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        state: "open",
        per_page: 100,
        // Oldest-first server-side too: with >100 open PRs, the default
        // created-desc page 1 would starve the oldest armed PRs the cap is
        // meant to drain (mirrors the stale-bot-PR watchdog's ordering).
        sort: "created",
        direction: "asc",
        headers: { "X-GitHub-Api-Version": "2022-11-28" },
      }),
    ).catch((err) => {
      throw redactErr(err, installationToken);
    });
    return (res.data as PrListItem[])
      .filter(
        (pr) =>
          // REST `user.login`, NOT GraphQL `author.login` ("app/soleur-ai") —
          // verified live on #9205.
          pr.user?.login === BOT_LOGIN &&
          pr.auto_merge != null &&
          pr.draft !== true,
      )
      // Oldest-first so the update cap drains the backlog deterministically.
      .sort((a, b) => a.created_at.localeCompare(b.created_at))
      .map((pr) => ({ number: pr.number, created_at: pr.created_at }));
  });

  // Once per sweep, as a memoized step: an in-memory cache is rebuilt on every
  // Inngest replay, so it would not be once-per-sweep. The step returns the
  // verdict only (the installation token can sit in an Octokit error message);
  // an unreadable answer is mirrored to Sentry from inside the step, redacted.
  const queueRule: QueueRuleVerdict =
    botPrs.length === 0
      ? "none"
      : await step.run("read-merge-queue-rule", async () => {
          const { verdict, cause } = await readMergeQueueRule(octokit);
          if (verdict === "unreadable") {
            reportSilentFallback(
              redactErr(new Error(cause ?? "unreadable"), installationToken),
              {
                feature: FUNCTION_NAME,
                op: "merge-queue-rule-unreadable",
                message:
                  "merge-queue rule read failed; behind bot PRs are not update-branched (fail closed)",
                extra: { fn: FUNCTION_NAME },
              },
            );
          }
          return verdict;
        });

  const results: SweepResult[] = [];
  let updatesUsed = 0;
  const unknownRereadBudget = { used: 0, cap: UNKNOWN_REREAD_CAP };
  for (const pr of botPrs) {
    const result = await step.run(`evaluate-pr-${pr.number}`, async () => {
      try {
        return await reapBotPr({
          octokit,
          prNumber: pr.number,
          updatesUsed,
          updatesCap: MAX_UPDATES_PER_SWEEP,
          queueRule,
          createdAt: pr.created_at,
          unknownRereadBudget,
          logger,
        });
      } catch (err) {
        reportSilentFallback(redactErr(err, installationToken), {
          feature: FUNCTION_NAME,
          op: "bot-pr-update-failed",
          message: "bot-PR sweep: per-PR evaluation failed",
          extra: { fn: FUNCTION_NAME, pr: pr.number },
        });
        return {
          number: pr.number,
          state: "unknown",
          action: "error" as const,
        };
      }
    });
    if (result.action === "updated") updatesUsed++;
    results.push(result);
  }

  const stuck = results.filter((r) => r.action === "stuck-alerted");
  const hadError = results.some((r) => r.action === "error");

  await step.run("sync-stuck-issue", async () => {
    const lines = stuck
      .map(
        (r) =>
          `- #${r.number} — mergeable_state: \`${r.state}\`` +
          (r.reason ? ` — ${STUCK_REASON_TEXT[r.reason]}` : ""),
      )
      .join("\n");
    if (stuck.length > 0) {
      // Body (not comments) carries the current stuck set — always current,
      // no per-sweep comment noise.
      const body = [
        "These `soleur-ai[bot]` PRs have auto-merge armed but are not merging.",
        "Either they are unmergeable for reasons `update-branch` cannot fix (merge",
        "conflict, required review, or failing checks), or they are behind and",
        "the merge queue has not enqueued them within the bound shown on their",
        "line (the reaper does not resync those: the queue owns them). They need a",
        "human or agent decision; the reaper will keep them listed here until they",
        "merge or close.",
        "",
        `_Updated ${new Date().toISOString()}_`,
        "",
        lines,
      ].join("\n");
      let dedupIssueNumber: number | undefined;
      try {
        const dedup = await ensureDedupIssue(octokit, {
          title: STUCK_ISSUE_TITLE,
          body,
          labels: STUCK_ISSUE_LABELS,
        });
        dedupIssueNumber = dedup.issueNumber;
        if (!dedup.created && dedup.issueNumber != null) {
          // Refresh the standing issue's body each sweep instead of posting
          // a "still stuck" comment — the body is always authoritative.
          await octokit.request(
            "PATCH /repos/{owner}/{repo}/issues/{issue_number}",
            {
              owner: REPO_OWNER,
              repo: REPO_NAME,
              issue_number: dedup.issueNumber,
              body,
            },
          );
        }
      } catch (err) {
        throw redactErr(err, installationToken);
      }
      reportSilentFallback(
        new Error(
          `${stuck.length} bot PR(s) unmergeable without intervention: ${stuck.map((r) => `#${r.number}`).join(", ")}`,
        ),
        {
          feature: FUNCTION_NAME,
          op: "bot-pr-unmergeable",
          message: "bot PRs stuck in a state update-branch cannot fix",
          extra: {
            fn: FUNCTION_NAME,
            prs: stuck.map((r) => ({
              number: r.number,
              state: r.state,
              reason: r.reason,
            })),
            issueNumber: dedupIssueNumber,
          },
        },
      );
      return;
    }
    // Set drained — self-close the tracking issue if one is open.
    try {
      const match = await findDedupIssue(octokit, {
        title: STUCK_ISSUE_TITLE,
        labels: STUCK_ISSUE_LABELS,
      });
      if (match !== undefined) {
        await octokit.request(
          "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
          {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            issue_number: match,
            body: `No stuck bot PRs at ${new Date().toISOString()} — auto-closing.`,
          },
        );
        await octokit.request(
          "PATCH /repos/{owner}/{repo}/issues/{issue_number}",
          {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            issue_number: match,
            state: "closed",
          },
        );
      }
    } catch (err) {
      throw redactErr(err, installationToken);
    }
  });

  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok: !hadError,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: FUNCTION_NAME,
      logger,
    });
  });

  logger.info(
    {
      fn: FUNCTION_NAME,
      evaluated: results.length,
      queueRule,
      updated: updatesUsed,
      stuck: stuck.length,
      errors: results.filter((r) => r.action === "error").length,
    },
    "bot-PR sweep complete",
  );
  return hadError
    ? {
        ok: false,
        errorSummary: `${results.filter((r) => r.action === "error").length} bot-PR evaluation(s) failed — see Sentry`,
      }
    : { ok: true };
}

export const cronBotPrReaper = inngest.createFunction(
  {
    id: "cron-bot-pr-reaper",
    concurrency: [
      { scope: "fn", limit: 1 },
      // Dedicated account lane (the lane key is the fn id itself): the sweep
      // can hold for minutes on unknown-state settle waits, and sharing
      // `"cron-dispatch"` would let it head-of-line the */5 supabase-watchdog
      // dispatch; `"cron-platform"` would let a 50-min claude-eval hold page
      // this function's 30-min margin as a false "reaper dead".
      { scope: "account", key: '"cron-bot-pr-reaper"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "17 */2 * * *" },
    { event: "cron/bot-pr-reaper.manual-trigger" },
  ],
  cronBotPrReaperHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
