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
    | "stuck-alerted"
    | "error";
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
 * Evaluate one bot PR. Never throws for a per-PR API failure — a transient
 * error on one PR must not fail the sweep; it is reported and recorded as
 * `error` so the heartbeat still lands.
 */
export async function reapBotPr(args: {
  octokit: Octokit;
  prNumber: number;
  updatesUsed: number;
  updatesCap: number;
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
      .map((pr) => ({ number: pr.number }));
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
      .map((r) => `- #${r.number} — mergeable_state: \`${r.state}\``)
      .join("\n");
    if (stuck.length > 0) {
      // Body (not comments) carries the current stuck set — always current,
      // no per-sweep comment noise.
      const body = [
        "These `soleur-ai[bot]` PRs have auto-merge armed but are unmergeable for",
        "reasons `update-branch` cannot fix (merge conflict, required review, or",
        "failing checks). They need a human or agent decision; the reaper will",
        "keep them listed here until they merge or close.",
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
            prs: stuck.map((r) => ({ number: r.number, state: r.state })),
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
