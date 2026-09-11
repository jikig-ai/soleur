// PR #4457 — Stale deferred-scope-out sweep migrated to Inngest.
//
// Migrated from the GHA scheduled-stale-deferred-scope-outs workflow
// (deleted in the same PR). The work properly belongs in Inngest: it
// benefits from step.run memoization (per-issue progress survives Inngest
// replays) and the rest of the cron substrate (Sentry tagging via the
// inngest sentry-correlation middleware, reportSilentFallback mirroring).
//
// ADR-033 invariants (only load-bearing entries cited; sibling
// cron-github-app-drift-guard.ts uses the same convention):
//   I5 — Deterministic step.run return shape: {closed, skipped, total}.
//        Per-issue side effects (gh issue comment / close) live inside the
//        sweep step so replays memoize the aggregate counters; the per-call
//        gh-API write idempotency comes from GitHub's "already closed" tolerance.
//   I7 — Replay-safety: GH search `is:open` filter + close-is-no-op
//        semantics on retry + in-loop `state === "closed"` defensive guard
//        (GH Search has a ~30s eventual-consistency window where just-closed
//        issues may still surface; the guard short-circuits the comment/close
//        sequence in that window) + per-issue GET-before-POST comment
//        idempotency guard (issue #5231: skips the POST if COMMENT_BODY is
//        already present, preventing double-comment on Inngest replay).
//
// POLICY CARRIED VERBATIM FROM THE GHA WORKFLOW:
//   - Cutoff: 90 days since last issue activity.
//   - Kill switch: `do-not-autoclose` label exempts an issue.
//   - Comment body: references PR #4452 (the original scope-out drain PR)
//     and the review-todo-structure runbook for re-evaluation triggers.
//
// DRY-RUN MODE: invoke via Inngest event `cron/stale-deferred-scope-outs.manual-trigger`
// with payload `{ data: { dry_run: true } }` — lists stale candidates
// without commenting or closing. Operators can fire from the Inngest
// dashboard or via `inngest.send({ name: "...", data: { dry_run: true } })`.
//
// NAME NOTE: Inngest function id is "cron-stale-deferred-scope-outs"
// (TR9 / ADR-033 convention).

import type { Octokit } from "@octokit/core";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import { withGithubRetry } from "@/server/github-retry";
import {
  createProbeOctokit,
  PROBE_ISSUE_OWNER,
  PROBE_ISSUE_REPO,
} from "@/server/github/probe-octokit";
import {
  AUDIT_SELF_REPORT_BODY_PREFIX,
  postSentryHeartbeat,
  type HandlerArgs,
} from "./_cron-shared";
import { RUN_REPORT_TITLE_PREFIX, sweepableRunReports } from "./_cron-run-reports";

// 90 days, expressed in ms — matches `date -u -d '90 days ago'` from the
// original bash workflow.
const STALE_WINDOW_MS = 90 * 24 * 60 * 60 * 1000;

// Label sentinels.
//
// The sweep targets a SET of labels, not one. GITHUB SEARCH SYNTAX IS THE TRAP,
// and the wrong form fails SILENTLY: multiple `label:` qualifiers are ANDed,
// while comma-separated values inside ONE qualifier are ORed. Mapping this list
// and joining with a space would yield
//     label:"deferred-scope-out" label:"meta/machinery"
// which matches only issues carrying BOTH -- zero. The sweep would then return
// {total: 0, closed: 0}, post an `ok` Sentry heartbeat, and log "Auto-closed 0
// stale issues", which is byte-identical to a clean run. buildSearchQuery()
// below emits the comma-joined form and is unit-tested on the STRING itself,
// not merely on the sweep result, because only the string distinguishes them.
const TARGET_LABELS = ["deferred-scope-out", "meta/machinery"] as const;

// Kill switches. `keep-open` is NEW here: the label already exists in this repo
// and was simply unhonoured by this sweeper. It carries a DIFFERENT meaning in
// .github/workflows/codeql-to-issues.yml ("tracks something other than the alert
// state", closed with --reason completed). Adopting it here as a general
// never-auto-close pin is fine, but two sweepers now read one label with two
// definitions, and that is written down rather than left to be rediscovered.
const KILLSWITCH_LABELS = ["do-not-autoclose", "keep-open"] as const;

// Never auto-close something a user might receive. Free to check:
// fetchCandidates already materialises the labels array, so this costs no
// extra request.
const PRODUCT_FACING_LABELS = [
  "domain/product",
  "type/feature",
  "action-required",
  "priority/p0-critical",
  "priority/p1-high",
] as const;

// A close cap DISTINCT from SEARCH_MAX_RESULTS. That 200 bounds CANDIDATES, not
// CLOSES -- without a separate cap one fire could close 200 issues. The unswept
// remainder is returned as `deferred` so it is visible in the run log rather
// than silently dropped.
const MAX_CLOSES_PER_RUN = 25;

// PER-LABEL, not one shared budget. buildSearchQuery emits a single
// `sort:updated-asc` query, and from MACHINERY_SWEEP_NOT_BEFORE the backfilled
// machinery cohort dominates oldest-first ordering -- 57% of the backlog is
// already past the 90-day window -- so a single shared cap would hand the whole
// 25/run budget to machinery every day and starve `deferred-scope-out`, this
// function's original and only job until now. The starvation would also be
// INVISIBLE: `deferred` was one integer with no per-label breakdown, and one
// Sentry monitor covers both arms, so a starved arm and a healthy one look the
// same. Splitting the cap costs one Record and makes the split observable.
const MAX_CLOSES_PER_LABEL: Record<string, number> = {
  "deferred-scope-out": 15,
  "meta/machinery": 10,
};

// The machinery arm cannot fire before this date.
//
// An earlier draft argued the first live sweep was safe "because the
// meta/machinery label is brand-new". That argument is FALSE. The label is new;
// the ISSUES ARE NOT. This sweeper's only age signal is `updated_at`, so label
// novelty confers zero age protection, and 57% of the backlog is already older
// than the 90-day window. Both branches of the unexamined question were bad: if
// applying a label does not bump updated_at, the first fire after merge closes
// up to the cap; if it does, the whole backfilled cohort becomes eligible on the
// SAME day 90 days out -- a thundering herd, larger by then, when nobody is
// watching. This gate costs zero API calls, is trivially unit-testable, expires
// by itself, and guarantees a full month with the new digest first.
const MACHINERY_SWEEP_NOT_BEFORE = "2026-10-10";
const MACHINERY_LABEL = "meta/machinery";

// Known automation logins. Used ALONGSIDE user.type === "Bot", never instead of
// it: an agent authenticating with a PAT posts as the human user, so the type
// check is what makes the guard fail toward skipping, and this list only trims
// false "human" readings from actors that post as themselves.
const KNOWN_AUTOMATION_ACTORS: readonly string[] = [
  "github-actions[bot]",
  "soleur-ai[bot]",
  "dependabot[bot]",
];

// Search caps — bash workflow used `--limit 200`, mirrored here. Sorted
// oldest-first via `sort:updated-asc` so each daily fire makes steady
// progress on the tail of the backlog.
// GH's /search/issues caps at 100 items/page, so reaching the 200-item
// ceiling REQUIRES two requests (page=1, page=2). The bash precedent's
// `gh ... --limit 200` opaquely paginated under the hood.
const SEARCH_PER_PAGE = 100;
const SEARCH_MAX_RESULTS = 200;

// Sentry Crons heartbeat — mirrors cron-github-app-drift-guard substrate.
// Slug matches the Terraform sentry_cron_monitor.scheduled_stale_deferred_scope_outs
// resource `name` field for historical/check-in continuity.
const SENTRY_MONITOR_SLUG = "scheduled-stale-deferred-scope-outs";

/**
 * Auto-close comment body — heredoc verbatim from the GHA workflow. Refers
 * to PR #4452 (the scope-out drain PR that introduced this sweep) and the
 * review-todo-structure runbook so re-filers know what re-evaluation
 * trigger to attach.
 */
// Stable idempotency sentinel appended to every auto-close comment. The
// GET-before-POST guard (issue #5231) matches on THIS marker via substring
// `includes`, NOT full-body equality. Exact `=== COMMENT_BODY` is brittle:
// GitHub may return stored comment bodies with CRLF line endings (our body is
// `\n`-joined), and the prose below is copy-edited over time — either divergence
// would silently break the match and re-POST, defeating the guard. The marker
// is an HTML comment so it renders invisibly on the rendered issue.
const COMMENT_MARKER = "<!-- soleur:auto-close-stale-scope-out -->";
const COMMENT_BODY = [
  "Auto-closing: this issue has been open with no activity for 90+ days.",
  "",
  "If the concern is still relevant, re-file with an updated re-evaluation trigger",
  "(date / counter / event-grep / dependency — see `plugins/soleur/skills/review/references/review-todo-structure.md`).",
  "Open-ended scope-outs accumulate into the backlog this auto-close exists to drain.",
  "",
  "See PR #4452 for rationale; apply the `do-not-autoclose` label to exempt.",
  "",
  COMMENT_MARKER,
].join("\n");

// =============================================================================
// Sweep — pure logic, isolated for testability
// =============================================================================

interface SweepResult {
  total: number;
  closed: number;
  skipped: number;
  /** Per-arm close counts, so a starved arm is visible rather than inferred. */
  closedByLabel: Record<string, number>;
  /** Per-arm deferrals, same reason. */
  deferredByLabel: Record<string, number>;
  /**
   * Candidates left unswept because a close cap was reached. Returned
   * rather than dropped so a capped run is visible in the log instead of
   * reading like a run that simply found less work.
   */
  deferred: number;
  dryRun: boolean;
  /** #8076 — the run-report arm's own counters (separate step, separate cap). */
  runReports?: RunReportSweepResult;
}

// #8076 — the run-report arm's result shape. Kept separate from the scope-out
// counters so a starved or capped arm is visible per arm, and `skippedByReason`
// makes every guard's firing countable (a guard that never fires is a guard
// that cannot be driven red).
export interface RunReportSweepResult {
  total: number;
  closed: number;
  skipped: number;
  deferred: number;
  closedByLabel: Record<string, number>;
  skippedByReason: Record<string, number>;
  dryRun: boolean;
}

interface SweepCandidate {
  number: number;
  title: string;
  updatedAt: string;
  state: string;
  labels: Array<{ name: string }>;
  /**
   * Captured from the search response, which already carries it. This is what
   * makes the human-triage guard cheap: when `comments === 0` there is no
   * comment to fetch AND no COMMENT_MARKER can exist, so BOTH the triage GET
   * and the idempotency GET are skippable on one signal. 331 of 1,457 open
   * issues have zero comments, and machinery findings skew heavily that way.
   */
  comments: number;
}

interface SearchResponseItem {
  number?: number;
  title?: string;
  updated_at?: string;
  state?: string;
  labels?: Array<{ name?: string }>;
  comments?: number;
}

/**
 * Build the search query. Exported for its own unit test: the ONLY thing that
 * distinguishes the correct comma-joined form from the ANDed form that matches
 * nothing is the string itself. Asserting on the sweep RESULT cannot tell a
 * correct empty run from a query that can never match.
 */
export function buildSearchQuery(args: {
  owner: string;
  repo: string;
  cutoffIso: string;
  labels: readonly string[];
}): string {
  const { owner, repo, cutoffIso, labels } = args;
  // ONE qualifier, comma-joined => OR. Never `labels.map(l => `label:"${l}"`)`.
  const labelQualifier = `label:${labels.map((l) => `"${l}"`).join(",")}`;
  return `repo:${owner}/${repo} is:issue is:open ${labelQualifier} updated:<${cutoffIso} sort:updated-asc`;
}

async function fetchCandidates(args: {
  octokit: Octokit;
  cutoffIso: string;
  labels: readonly string[];
}): Promise<SweepCandidate[]> {
  const { octokit, cutoffIso } = args;
  // GH /search/issues caps at 100 items/page; reaching the 200-item ceiling
  // requires two requests. Loop short-circuits on either the cap (return)
  // or a short page (break).
  const owner = PROBE_ISSUE_OWNER;
  const repo = PROBE_ISSUE_REPO;
  const q = buildSearchQuery({ owner, repo, cutoffIso, labels: args.labels });
  const candidates: SweepCandidate[] = [];
  for (let page = 1; page <= 2; page++) {
    // Wrap in withGithubRetry so a single transient api.github.com connect
    // timeout (which octokit surfaces as a RequestError) is absorbed in-step
    // rather than escalating to an error-level Sentry mirror. fetchCandidates
    // is OUTSIDE the per-issue try, so a bare timeout here would otherwise
    // abort the whole sweep (Sentry 448a4173…).
    const res = await withGithubRetry(() =>
      octokit.request("GET /search/issues", {
        q,
        per_page: SEARCH_PER_PAGE,
        page,
      }),
    );
    const items = (res.data?.items ?? []) as SearchResponseItem[];
    for (const item of items) {
      if (typeof item.number !== "number") continue;
      candidates.push({
        number: item.number,
        title: typeof item.title === "string" ? item.title : "",
        updatedAt: typeof item.updated_at === "string" ? item.updated_at : "",
        state: typeof item.state === "string" ? item.state : "open",
        labels: Array.isArray(item.labels)
          ? item.labels
              .filter((l): l is { name: string } => typeof l?.name === "string")
              .map((l) => ({ name: l.name }))
          : [],
        comments: typeof item.comments === "number" ? item.comments : 0,
      });
      if (candidates.length >= SEARCH_MAX_RESULTS) return candidates;
    }
    if (items.length < SEARCH_PER_PAGE) break;
  }
  return candidates;
}

/**
 * The sweep core. Exported for unit tests; the inngest-wrapped handler
 * below feeds it a real octokit + a logger.
 *
 * Returns counters. Side effects:
 *   - Posts a comment on each non-kill-switched candidate (unless dry-run).
 *   - Closes each commented issue (unless dry-run).
 *
 * Per-issue try/catch is intentional: a single 410 (issue archived) or
 * 422 (invalid state transition) from gh should NOT abort the rest of
 * the sweep. The error is mirrored to Sentry via reportSilentFallback
 * and the counter advances.
 */
export async function sweepStaleScopeOuts(args: {
  octokit: Octokit;
  now: Date;
  dryRun: boolean;
  logger: HandlerArgs["logger"];
}): Promise<SweepResult> {
  const { octokit, now, dryRun, logger } = args;
  const owner = PROBE_ISSUE_OWNER;
  const repo = PROBE_ISSUE_REPO;

  const cutoffMs = now.getTime() - STALE_WINDOW_MS;
  const cutoffIso = new Date(cutoffMs).toISOString().slice(0, 10); // YYYY-MM-DD
  logger.info(
    {
      fn: "cron-stale-deferred-scope-outs",
      cutoff: cutoffIso,
      dryRun,
    },
    "stale-deferred-scope-out sweep starting",
  );

  // The machinery arm is gated by date, not by label novelty (see
  // MACHINERY_SWEEP_NOT_BEFORE). Before that date the sweep runs exactly as it
  // did before this change: deferred-scope-out only.
  const machineryArmed = now.toISOString().slice(0, 10) >= MACHINERY_SWEEP_NOT_BEFORE;
  const activeLabels = machineryArmed
    ? TARGET_LABELS
    : TARGET_LABELS.filter((l) => l !== MACHINERY_LABEL);
  const candidates = await fetchCandidates({
    octokit,
    cutoffIso,
    labels: activeLabels,
  });

  // NON-ZERO-CANDIDATE FLOOR. A run finding zero candidates across a
  // 600+-issue labelled population is a defect -- almost certainly the ANDed
  // query shape -- not a success. Reported loudly rather than heartbeating `ok`
  // on a query that can never match.
  if (candidates.length === 0) {
    logger.warn(
      {
        fn: "cron-stale-deferred-scope-outs",
        query: buildSearchQuery({
          owner: PROBE_ISSUE_OWNER,
          repo: PROBE_ISSUE_REPO,
          cutoffIso,
          labels: activeLabels,
        }),
      },
      "SOLEUR_SWEEP_ZERO_CANDIDATES: zero candidates across the labelled population — verify the query shape before reading this as a clean run",
    );
  }

  let deferred = 0;
  const closedByLabel: Record<string, number> = {};
  const deferredByLabel: Record<string, number> = {};
  let closed = 0;
  let skipped = 0;

  for (const candidate of candidates) {
    const num = candidate.number;

    // Replay-safety (I7): the search `is:open` filter is eventually
    // consistent (~30s lag); on Inngest retry, a just-closed issue may
    // briefly resurface. Short-circuit here so we never re-comment a
    // closed issue.
    if (candidate.state === "closed") continue;

    const names = candidate.labels.map((l) => l.name);

    const killSwitch = KILLSWITCH_LABELS.find((k) => names.includes(k));
    if (killSwitch) {
      logger.info(
        { fn: "cron-stale-deferred-scope-outs", number: num, title: candidate.title, reason: killSwitch },
        `SKIP #${num} (${killSwitch})`,
      );
      skipped += 1;
      continue;
    }

    // Never auto-close something a user might receive.
    const productLabel = PRODUCT_FACING_LABELS.find((k) => names.includes(k));
    if (productLabel) {
      logger.info(
        { fn: "cron-stale-deferred-scope-outs", number: num, reason: productLabel },
        `SKIP #${num} (product-facing: ${productLabel})`,
      );
      skipped += 1;
      continue;
    }

    // Close cap, PER LABEL and checked BEFORE any write so it bounds writes
    // rather than reads. The overall cap still applies as a backstop.
    const arm = names.includes(MACHINERY_LABEL) ? MACHINERY_LABEL : "deferred-scope-out";
    const armCap = MAX_CLOSES_PER_LABEL[arm] ?? MAX_CLOSES_PER_RUN;
    if (closed >= MAX_CLOSES_PER_RUN || (closedByLabel[arm] ?? 0) >= armCap) {
      deferred += 1;
      deferredByLabel[arm] = (deferredByLabel[arm] ?? 0) + 1;
      continue;
    }

    logger.info(
      {
        fn: "cron-stale-deferred-scope-outs",
        number: num,
        updatedAt: candidate.updatedAt,
        title: candidate.title,
      },
      `CANDIDATE #${num}`,
    );

    // HUMAN-TRIAGE GUARD, and it is hoisted ABOVE the dry-run short-circuit
    // deliberately. In the pre-change shape the comment GET sat on the WRITE
    // path, below `if (dryRun) continue`, so a dry-run could not exercise this
    // class at all -- which would make "dry-run first" a safety step that does
    // not test the guard it exists to rehearse.
    //
    // AUTHORSHIP ASYMMETRY FAVOURS US. A GitHub App posting via an installation
    // token appears as `type: "Bot"`, while an agent using a PAT posts as the
    // human user -- so agent comments read as human and fail toward SKIPPING.
    // Determining this from user.type plus a known-automation allowlist, rather
    // than the allowlist alone, is what keeps the failure in that direction.
    //
    // Cheap by construction: `comments === 0` means there is nothing to fetch,
    // and it also means no COMMENT_MARKER can exist, so the idempotency GET
    // below is skippable on the same signal.
    let humanTriaged = false;
    let alreadyCommentedPrefetch: boolean | null = null;
    if (candidate.comments > 0) {
      try {
        const triageRes = await withGithubRetry(() =>
          octokit.request(
            "GET /repos/{owner}/{repo}/issues/{issue_number}/comments",
            { owner, repo, issue_number: num, per_page: 100 },
          ),
        );
        const body = triageRes.data as Array<{
          body?: string;
          user?: { type?: string; login?: string };
        }>;
        alreadyCommentedPrefetch = body.some(
          (c) => c.body?.includes(COMMENT_MARKER) ?? false,
        );
        humanTriaged = body.some((c) => {
          const t = c.user?.type;
          const login = c.user?.login ?? "";
          if (t === "Bot") return false;
          if (KNOWN_AUTOMATION_ACTORS.includes(login)) return false;
          return true;
        });
      } catch (err) {
        // FAIL TOWARD SKIPPING when authorship cannot be determined, with its
        // OWN op discriminator so this is not an alert storm indistinguishable
        // from write failures.
        reportSilentFallback(err as Error, {
          feature: "cron-stale-deferred-scope-outs",
          op: "triage_authorship_indeterminate",
          message: "could not determine comment authorship; skipping toward safety",
          extra: { fn: "cron-stale-deferred-scope-outs", number: num },
        });
        skipped += 1;
        continue;
      }
    }
    if (humanTriaged) {
      logger.info(
        { fn: "cron-stale-deferred-scope-outs", number: num, reason: "human-triaged" },
        `SKIP #${num} (human-triaged)`,
      );
      skipped += 1;
      continue;
    }

    if (dryRun) continue;

    try {
      // Idempotency guard (issue #5231): a prior attempt (Inngest retry after a
      // mid-sweep throw, or the GH-search eventual-consistency window) may have
      // already posted the auto-close comment; skip the POST if the COMMENT_MARKER
      // sentinel is already present. This is a runtime read-back guard, not an
      // Inngest step-memoization barrier — concurrent sweeps are prevented by the
      // fn-scoped `concurrency.limit: 1` above; this guard covers sequential
      // retries. The GET is wrapped in withGithubRetry to absorb transient connect
      // timeouts (same rationale as the search call in fetchCandidates).
      // per_page: 100 (not the default 10): this endpoint returns comments
      // oldest-first, so the just-posted auto-close comment lands LAST — a tight
      // page size would paginate it out of view on a chatty issue and re-POST.
      // 100 covers any realistic 90-day-stale scope-out (a >100-comment thread
      // reaching auto-close is out of scope).
      const commentsRes = await withGithubRetry(() =>
        octokit.request(
          "GET /repos/{owner}/{repo}/issues/{issue_number}/comments",
          {
            owner,
            repo,
            issue_number: num,
            per_page: 100,
          },
        ),
      );
      const alreadyCommented = (
        commentsRes.data as Array<{ body?: string }>
      ).some((c) => c.body?.includes(COMMENT_MARKER) ?? false);

      // CROSS-GENERATION DEFECT, fixed here. If an operator REOPENS an
      // auto-closed issue and it later goes quiet, this sweeper re-closes it 90
      // days on -- and the guard above finds COMMENT_MARKER already present, so
      // it skips the comment. That second auto-close is therefore SILENT: no
      // explanation, no reopen instructions, nothing in the timeline but a state
      // change, firing precisely on an issue a human already said they cared
      // about.
      //
      // THE DISCRIMINATOR IS THE MARKER'S AGE, not the issue's state. Every
      // candidate reaching here is `state: "open"` by construction -- the search
      // filters `is:open` and the loop short-circuits closed issues above -- so
      // testing the state distinguishes nothing and would re-POST on every
      // replay retry, destroying the guard it means to preserve.
      //
      // A marker newer than the stale cutoff means this sweep already ran
      // moments ago and the close has not landed yet: a replay retry, so SKIP.
      // A marker OLDER than the cutoff means a previous generation closed this
      // issue at least one full quiet window ago and a human has since reopened
      // it: a genuine second generation, so POST the explanation again.
      //
      // Missing/unparseable `created_at` fails toward SKIPPING, preserving the
      // original replay-safety behaviour rather than risking a duplicate.
      const markerAges = (
        commentsRes.data as Array<{ body?: string; created_at?: string }>
      )
        .filter((c) => c.body?.includes(COMMENT_MARKER) ?? false)
        .map((c) => Date.parse(c.created_at ?? ""))
        .filter((t) => Number.isFinite(t));
      const newestMarkerAt = markerAges.length ? Math.max(...markerAges) : null;
      const priorGeneration =
        newestMarkerAt !== null && newestMarkerAt < Date.parse(cutoffIso);
      const skipComment = alreadyCommented && !priorGeneration;

      // The comment POST and close PATCH are SEPARATE withGithubRetry wrappers
      // (NOT one around both): wrapping both together would re-POST the comment
      // on a close-timeout retry. A non-retryable 403 is rethrown on attempt 1
      // straight into the catch below, preserving the issue_write_403 discriminator.
      if (!skipComment) {
        await withGithubRetry(() =>
          octokit.request(
            "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
            {
              owner,
              repo,
              issue_number: num,
              body: COMMENT_BODY,
            },
          ),
        );
      }
      await withGithubRetry(() =>
        octokit.request("PATCH /repos/{owner}/{repo}/issues/{issue_number}", {
          owner,
          repo,
          issue_number: num,
          state: "closed",
          state_reason: "not_planned",
        }),
      );
      closed += 1;
      closedByLabel[arm] = (closedByLabel[arm] ?? 0) + 1;
    } catch (err) {
      // Discriminate the issues:write-missing 403 so the operator can
      // alert-route on it directly (see #4189). Same blind spot as the
      // drift-guard + oauth-probe: createProbeOctokit() is installation-scoped
      // and 403s on issue writes when the App lacks issues:write.
      const op =
        (err as { status?: number }).status === 403
          ? "issue_write_403"
          : "comment-and-close";
      reportSilentFallback(err as Error, {
        feature: "cron-stale-deferred-scope-outs",
        op,
        message: "comment-or-close failed for one issue; sweep continues",
        extra: {
          fn: "cron-stale-deferred-scope-outs",
          number: num,
        },
      });
      // Counter does NOT advance on failure — surfaces in the final
      // total vs. closed delta so operators can spot persistent errors.
    }
  }

  return {
    total: candidates.length,
    closed,
    skipped,
    deferred,
    closedByLabel,
    deferredByLabel,
    dryRun,
  };
}


// =============================================================================
// #8076 — the run-report arm
// =============================================================================
//
// Ten crons MUST file a `[Scheduled] …` issue per run (their handlers verify
// run completion by its existence — `_cron-run-reports.ts`). Those SUCCESS
// reports had no lifecycle at all: 43 open community digests, last bulk-closed
// by a person on 2026-07-27, and daily triage had labelled 21 of them
// `priority/p1-high`. This arm closes SUCCESS run-reports older than each
// row's literal `closeAfterDays`, with `state_reason: "completed"` (a report
// that ran is complete, not "not planned"), and NEVER:
//   - a FAILED report — the handler-filed fallback (#4960) carries the NORMAL
//     title and marks failure by body prefix (`AUDIT_SELF_REPORT_BODY_PREFIX`),
//     the prompt-path misconfiguration issue by a `FAILED` title; both guarded;
//   - a finding that merely borrowed the label — the query is
//     `author:app/soleur-ai` and the title must carry RUN_REPORT_TITLE_PREFIX,
//     which is what closes the file-and-vanish path a label-only hook exit
//     would otherwise leave open (ADR-216 addendum);
//   - a human-touched one (non-bot comment), `action-required`, or either
//     kill-switch label;
//   - campaign-calendar's standing issue or legal-audit's per-gap findings —
//     rows with `closeAfterDays: null` are never queried.
// The query is `created:<cutoff`, not `updated:` — triage labelling bumps
// updated_at. PRODUCT_FACING_LABELS is deliberately NOT consulted here:
// priority/type/domain on a run-report are daily-triage noise (#8027 wore
// p1-high), and `action-required` is checked explicitly.
//
// Coupling: the close bumps updated_at, which `verifyScheduledIssueCreated`
// used to credit as producer output; it now refuses CLOSED issues (see
// _cron-shared.ts), so this arm can run at 12:00Z beside any producer.

const RUN_REPORT_COMMENT_MARKER = "<!-- soleur:auto-close-run-report -->";
const RUN_REPORT_COMMENT_BODY = [
  "Auto-closing: this scheduled run-report is older than its cron's retention window.",
  "",
  "It is a SUCCESS report (a liveness token + audit trail), not a finding; the",
  "digest file it links is committed under knowledge-base/. FAILED reports and",
  "reports a person has commented on are never auto-closed. Apply `keep-open`",
  "to exempt one. See ADR-216 (2026-09-11 addendum) and #8076.",
  "",
  RUN_REPORT_COMMENT_MARKER,
].join("\n");
const MAX_RUN_REPORT_CLOSES_PER_RUN = 25;

function buildRunReportQuery(args: { owner: string; repo: string; label: string; cutoffIso: string }): string {
  const { owner, repo, label, cutoffIso } = args;
  return `repo:${owner}/${repo} is:issue is:open author:app/soleur-ai label:"${label}" created:<${cutoffIso} sort:created-asc`;
}

interface RunReportCandidate extends SweepCandidate {
  createdAt: string;
  body: string;
  authorLogin: string;
}

export async function sweepRunReports(args: {
  octokit: Octokit;
  now: Date;
  dryRun: boolean;
  logger: HandlerArgs["logger"];
}): Promise<RunReportSweepResult> {
  const { octokit, now, dryRun, logger } = args;
  const owner = PROBE_ISSUE_OWNER;
  const repo = PROBE_ISSUE_REPO;
  const closedByLabel: Record<string, number> = {};
  const skippedByReason: Record<string, number> = {};
  const skip = (reason: string, num: number, label: string) => {
    skippedByReason[reason] = (skippedByReason[reason] ?? 0) + 1;
    logger.info(
      { fn: "cron-stale-deferred-scope-outs", arm: "run-reports", number: num, label, reason },
      `SKIP #${num} (${reason})`,
    );
  };
  let total = 0;
  let closed = 0;
  let skipped = 0;
  let deferred = 0;

  for (const row of sweepableRunReports()) {
    const cutoffMs = now.getTime() - row.closeAfterDays * 24 * 60 * 60 * 1000;
    const cutoffIso = new Date(cutoffMs).toISOString().slice(0, 10);
    const q = buildRunReportQuery({ owner, repo, label: row.label, cutoffIso });
    const res = await withGithubRetry(() =>
      octokit.request("GET /search/issues", { q, per_page: SEARCH_PER_PAGE, page: 1 }),
    );
    const items = (res.data?.items ?? []) as Array<
      SearchResponseItem & { created_at?: string; body?: string; user?: { login?: string } }
    >;
    const candidates: RunReportCandidate[] = [];
    for (const item of items) {
      if (typeof item.number !== "number") continue;
      candidates.push({
        number: item.number,
        title: typeof item.title === "string" ? item.title : "",
        updatedAt: typeof item.updated_at === "string" ? item.updated_at : "",
        createdAt: typeof item.created_at === "string" ? item.created_at : "",
        state: typeof item.state === "string" ? item.state : "open",
        body: typeof item.body === "string" ? item.body : "",
        authorLogin: typeof item.user?.login === "string" ? item.user.login : "",
        labels: Array.isArray(item.labels)
          ? item.labels
              .filter((l): l is { name: string } => typeof l?.name === "string")
              .map((l) => ({ name: l.name }))
          : [],
        comments: typeof item.comments === "number" ? item.comments : 0,
      });
    }
    total += candidates.length;

    for (const c of candidates) {
      const num = c.number;
      const names = c.labels.map((l) => l.name);
      // Guards, in order, every one failing toward SKIP.
      if (!c.title.startsWith(RUN_REPORT_TITLE_PREFIX)) { skip("not-run-report-shape", num, row.label); skipped += 1; continue; }
      const createdMs = Date.parse(c.createdAt);
      if (!Number.isFinite(createdMs) || createdMs >= cutoffMs) { skip("too-young", num, row.label); skipped += 1; continue; }
      const killSwitch = KILLSWITCH_LABELS.find((k) => names.includes(k));
      if (killSwitch) { skip(killSwitch, num, row.label); skipped += 1; continue; }
      if (names.includes("action-required")) { skip("action-required", num, row.label); skipped += 1; continue; }
      if (c.body.startsWith(AUDIT_SELF_REPORT_BODY_PREFIX) || /\bFAILED\b/.test(c.title)) {
        skip("failed-report", num, row.label); skipped += 1; continue;
      }
      if (c.state !== "open") { skip("not-open", num, row.label); skipped += 1; continue; }

      // One comments GET answers both the human-triage guard and the marker
      // idempotency check (same shape as the scope-out arm, L422-465).
      let humanTriaged = false;
      let alreadyCommented = false;
      if (c.comments > 0) {
        try {
          const commentsRes = await withGithubRetry(() =>
            octokit.request("GET /repos/{owner}/{repo}/issues/{issue_number}/comments", {
              owner, repo, issue_number: num, per_page: 100,
            }),
          );
          const body = commentsRes.data as Array<{ body?: string; user?: { type?: string; login?: string } }>;
          alreadyCommented = body.some((x) => x.body?.includes(RUN_REPORT_COMMENT_MARKER) ?? false);
          humanTriaged = body.some((x) => {
            if (x.user?.type === "Bot") return false;
            if (KNOWN_AUTOMATION_ACTORS.includes(x.user?.login ?? "")) return false;
            return true;
          });
        } catch (err) {
          reportSilentFallback(err as Error, {
            feature: "cron-stale-deferred-scope-outs",
            op: "run-report-triage-read",
            message: "could not read comments; skipping (fail toward skip)",
            extra: { fn: "cron-stale-deferred-scope-outs", number: num },
          });
          skip("triage-read-failed", num, row.label); skipped += 1; continue;
        }
      }
      if (humanTriaged) { skip("human-triaged", num, row.label); skipped += 1; continue; }

      if (closed >= MAX_RUN_REPORT_CLOSES_PER_RUN) { deferred += 1; continue; }
      if (dryRun) continue;

      try {
        // Marker present → skip the POST only; still PATCH. The two writes are
        // separate withGithubRetry wrappers (a failed PATCH must not leave a
        // permanently-commented-never-closed issue).
        if (!alreadyCommented) {
          await withGithubRetry(() =>
            octokit.request("POST /repos/{owner}/{repo}/issues/{issue_number}/comments", {
              owner, repo, issue_number: num, body: RUN_REPORT_COMMENT_BODY,
            }),
          );
        }
        await withGithubRetry(() =>
          octokit.request("PATCH /repos/{owner}/{repo}/issues/{issue_number}", {
            owner, repo, issue_number: num, state: "closed", state_reason: "completed",
          }),
        );
        closed += 1;
        closedByLabel[row.label] = (closedByLabel[row.label] ?? 0) + 1;
      } catch (err) {
        const op = (err as { status?: number }).status === 403 ? "issue_write_403" : "run-report-comment-and-close";
        reportSilentFallback(err as Error, {
          feature: "cron-stale-deferred-scope-outs",
          op,
          message: "run-report comment-or-close failed for one issue; sweep continues",
          extra: { fn: "cron-stale-deferred-scope-outs", number: num },
        });
      }
    }
  }

  logger.info(
    { fn: "cron-stale-deferred-scope-outs", arm: "run-reports", total, closed, skipped, deferred, closedByLabel, skippedByReason, dryRun },
    "run-report sweep finished",
  );
  return { total, closed, skipped, deferred, closedByLabel, skippedByReason, dryRun };
}

// =============================================================================
// Handler entry point
// =============================================================================

export async function cronStaleDeferredScopeOutsHandler({
  step,
  logger,
  event,
  attempt,
  maxAttempts,
}: HandlerArgs): Promise<SweepResult> {
  // dry_run lives on the event payload for manual-trigger fires. The cron
  // trigger has no event.data, so dryRun is false by default.
  const dryRun = event?.data?.dry_run === true;

  // Retry-aware heartbeat gating (Sentry incident 5468023, "page before retry").
  // Inngest delivers a zero-indexed `attempt` and optional `maxAttempts`
  // (retries:1 → 2 attempts, 0 and 1 → maxAttempts 2; final attempt is index 1).
  // Callers/tests passing neither (legacy shape) read attempt=0/maxAttempts=1 →
  // isFinalAttempt=true → identical to the pre-fix behavior (error on failure).
  // Fail-safe direction: `maxAttempts` is OPTIONAL on Inngest's BaseContext, so
  // if a fire ever omits it the `?? 1` collapses isFinalAttempt to always-true →
  // every failed attempt pages. That degrades to OVER-paging (the original bug),
  // never to masking a real failure with a false `ok` — the safe way to fail.
  const isFinalAttempt = (attempt ?? 0) >= ((maxAttempts ?? 1) - 1);

  let result: SweepResult = {
    total: 0,
    closed: 0,
    skipped: 0,
    deferred: 0,
    closedByLabel: {},
    deferredByLabel: {},
    dryRun,
  };
  let sweepFailed = false;

  try {
    result = await step.run(
      "sweep-stale-deferred-scope-outs",
      async (): Promise<SweepResult> => {
        const octokit = await createProbeOctokit();
        return sweepStaleScopeOuts({
          octokit: octokit as unknown as Octokit,
          now: new Date(),
          dryRun,
          logger,
        });
      },
    );
  } catch (err) {
    sweepFailed = true;
    reportSilentFallback(err as Error, {
      feature: "cron-stale-deferred-scope-outs",
      op: "sweep",
      message: "stale-deferred-scope-out sweep threw",
      extra: {
        fn: "cron-stale-deferred-scope-outs",
        dryRun,
        attempt: attempt ?? 0,
        isFinalAttempt,
      },
    });
    // Heartbeat decision happens below; we do NOT rethrow yet.
  }

  // #8076 — the run-report arm runs in its OWN step so a search fault here does
  // not replay the (already memoized) scope-out step on the Inngest retry, and
  // shares the sweepFailed path so the heartbeat stays honest.
  try {
    const runReports = await step.run(
      "sweep-run-reports",
      async (): Promise<RunReportSweepResult> => {
        const octokit = await createProbeOctokit();
        return sweepRunReports({
          octokit: octokit as unknown as Octokit,
          now: new Date(),
          dryRun,
          logger,
        });
      },
    );
    result = { ...result, runReports };
  } catch (err) {
    sweepFailed = true;
    reportSilentFallback(err as Error, {
      feature: "cron-stale-deferred-scope-outs",
      op: "sweep-run-reports",
      message: "run-report sweep threw",
      extra: {
        fn: "cron-stale-deferred-scope-outs",
        dryRun,
        attempt: attempt ?? 0,
        isFinalAttempt,
      },
    });
  }

  if (sweepFailed && !isFinalAttempt) {
    // The only throwing paths are createProbeOctokit() and GET /search/issues
    // (per-issue write 403s are caught in-sweep and never set sweepFailed). On a
    // NON-final attempt those are almost always a transient GitHub blip
    // (401-after-budget / 403 secondary-rate-limit / 429 / 5xx) that Inngest's
    // retries:1 recovers. Posting status=error here is the bug we are fixing; we
    // skip the heartbeat step ENTIRELY (not just the POST) — a completed
    // step.run is memoized across the retry, so an executed-but-silent step would
    // replay and never emit the recovered `ok`. Forensics are preserved by the
    // reportSilentFallback above (Layer 2: pino→Sentry error-level event — it
    // captures at error level, but it is NOT a monitor check-in, so it does not
    // page); if the retry never runs at all, the absent check-in trips the Sentry
    // missed-check-in alert within the 30-min schedule-anchored margin (Layer 1).
    // Rethrow to trigger the retry.
    throw new Error(
      "stale-deferred-scope-out sweep failed on a non-final attempt; retrying",
    );
  }

  // Sentry heartbeat — single end-of-job POST mirroring drift-guard substrate.
  // Reached only on success OR the final failed attempt, so the status it posts
  // is authoritative. Env-unset / malformed → graceful skip (heartbeat is an
  // OPTIONAL second-net; missing it must not stop the function from completing).
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok: !sweepFailed,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: "cron-stale-deferred-scope-outs",
      logger,
    });
  });

  if (sweepFailed) {
    // Final-attempt failure: the heartbeat reported status=error above. Throwing
    // here surfaces the persistent failure (Inngest has no retries left).
    throw new Error("stale-deferred-scope-out sweep failed; see Sentry");
  }

  if ((attempt ?? 0) > 0) {
    // Recovered on a retry — a transient flapped on a prior attempt. Emit a WARN
    // so a recurring daily flap is queryable as a trend instead of looking
    // identical to a clean attempt-0 run (the failed attempt posted no heartbeat).
    logger.warn(
      {
        fn: "cron-stale-deferred-scope-outs",
        recovered_after_attempts: attempt,
      },
      "stale-deferred-scope-out sweep recovered after a transient fault on a prior attempt",
    );
  }

  logger.info(
    {
      fn: "cron-stale-deferred-scope-outs",
      ...result,
    },
    `Auto-closed ${result.closed} stale issues (${TARGET_LABELS.map((l) => `${l}=${result.closedByLabel[l] ?? 0}`).join(" ")}); ${result.skipped} skipped, ${result.deferred} deferred (${TARGET_LABELS.map((l) => `${l}=${result.deferredByLabel[l] ?? 0}`).join(" ")})`,
  );

  return result;
}

// =============================================================================
// Registration
// =============================================================================

// Twin triggers (mirror cron-github-app-drift-guard): cron at 12:00 UTC
// daily (matches the original GHA workflow's `0 12 * * *` schedule) plus
// an event-triggered manual fire so operators can dry-run or kick the
// sweep on demand without a separate function.
export const cronStaleDeferredScopeOuts = inngest.createFunction(
  {
    id: "cron-stale-deferred-scope-outs",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 12 * * *" },
    { event: "cron/stale-deferred-scope-outs.manual-trigger" },
  ],
  cronStaleDeferredScopeOutsHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);

// Test surface — exported only for vitest.
export const __TESTING__ = {
  TARGET_LABELS,
  KILLSWITCH_LABELS,
  PRODUCT_FACING_LABELS,
  MAX_CLOSES_PER_RUN,
  MAX_CLOSES_PER_LABEL,
  MACHINERY_SWEEP_NOT_BEFORE,
  MACHINERY_LABEL,
  buildSearchQuery,
  COMMENT_BODY,
  COMMENT_MARKER,
  sweepStaleScopeOuts,
  RUN_REPORT_COMMENT_MARKER,
  MAX_RUN_REPORT_CLOSES_PER_RUN,
  sweepRunReports,
};
