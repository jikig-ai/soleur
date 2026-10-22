---
title: "fix(cron): bot-PR reaper stops update-branching armed BEHIND PRs on a merge-queue repo"
date: 2026-10-22
slug: fix-reaper-skip-queue-owned-behind-prs
branch: feat-one-shot-reaper-queue-owned-behind
issue: 9454
type: fix
lane: cross-domain
requires_cpo_signoff: false
---

# fix(cron): bot-PR reaper stops update-branching armed BEHIND PRs on a merge-queue repo

Ref #9454 (merge-queue epic tracker). Spec lacks a valid `lane:` (no spec.md for this branch) - defaulted to `cross-domain` (fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-22. **Gates run:** 4.6 user-brand (pass: threshold none with sensitive-path reason), 4.7 observability (pass: five fields, allowlisted `curl` probe, literal `merge_queue`), 4.8 PAT sweep (0 hits), 4.9 UI wireframe (no UI surface), 4.10 encryption posture (no store or connection), 4.11 guard contract (`lint-guard-contract.py`: 1 entry, green), 4.12 scope check (one live section, no `unmapped`, no `status: BLOCKED`).
**Verification passes:** live-resolved rule ids, issue states and endpoint semantics (below). Fan-out limited to the available panel: the weekly Anthropic API limit resets 2026-10-25 02:00 Europe/Paris, so no 40-agent sweep was launched; plan-review ran DHH, Kieran and code-simplicity, and the CTO ruled twice.

### Key improvements from review and deepening
1. 24 h second bound (T6): an armed BEHIND queue/unknown PR with hung or queued checks no longer escapes the alert.
2. Replay-simulating handler test (memoizing fake `step.run`) makes the "once per sweep" claim enforceable; the plain fake runs each callback once and cannot see replay defects.
3. Guard Contract cut from nine rows to seven; the fragile repo-wide source-walk test is replaced by a call-site comment plus an exact-literal `rg -c` check (AC8).
4. First-sweep alert-flood risk measured: 0 armed bot PRs now.

### New considerations discovered
- `withGithubRetry` retries only a cause-chain `fetch failed` / undici code, not a plain `status: 500`; the "network" rejection test needs fake timers (1 s + 2 s real sleeps otherwise).
- The rules endpoint defaults to `per_page=30` (max 100), so omitting `per_page` would truncate silently on a repo with more than 30 rules; the plan passes 100 and treats a full page without the rule as unreadable.

## Overview

`cron-bot-pr-reaper` (Inngest, every 2 h) re-bases armed `soleur-ai[bot]` PRs whose `mergeable_state` is `behind` with
`PUT /pulls/{n}/update-branch`. Since the queue adoption (ADR-270, 2026-10-04) `main` carries a `merge_queue` ruleset rule:
the queue builds its own projected state, GitHub enqueues an armed BEHIND PR once it is green (measured 9 to 47 minutes after
arming, no push needed), and a resync push restarts every required check for nothing. The agent-side writers were closed in
PR #10655 (`sync-pr-behind.sh` standalone, `--step`, the pre-merge hook); the reaper is the one remaining writer
(`apps/web-platform/server/` has exactly one `update-branch` call site, `cron-bot-pr-reaper.ts`).

The fix makes the reaper's `behind` arm defer to the queue:

1. One memoized `step.run("read-merge-queue-rule")` per sweep (taken whenever the sweep has at least one armed bot PR, not only when one is `behind`; the state is unknown until each PR is read) reads `GET /repos/{owner}/{repo}/rules/branches/main?per_page=100`
   and returns a JSON-safe verdict `queue | none | unreadable` (fail closed: any failure, non-list body, or a full page with
   no `merge_queue` rule is `unreadable`).
2. `reapBotPr` takes the verdict by value. In the `behind` arm, before any other work: verdict `none` keeps today's path
   unchanged; `queue` returns `skipped-queue-owned`; `unreadable` returns `skipped-queue-unknown`. Neither ever calls update-branch.
3. Bounded alert instead of a fallback sync (CTO rulings T1, T6): a queue-or-unknown behind PR older than 6 h since `created_at`
   with terminal checks, or older than 24 h whatever its check status, is routed into the existing `stuck-alerted` dedup-issue arm with a
   neutral reason line, so a PR GitHub never enqueues is LOUD (the 2026-09-27 incident class) without re-adding the resync the queue exists to remove.
4. The `dirty`/`blocked`/`unstable` alert arm, the `clean`/`draft`/`has_hooks` arms and the no-queue update path are unchanged.

## Research Reconciliation - Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "cache the rules read once per sweep" | Inngest re-invokes the handler per `step.run`; an in-memory cache object (like `unknownRereadBudget`) is rebuilt on every replay, so it is not once-per-sweep (learning 2026-07-19 wall-clock/replay) | Memoized dedicated step returning a JSON-safe verdict, passed by value (T2) |
| "reading the rule fail-closed ... same stance as `queue_wait`" | `queue_wait_eval` selects `.type == "merge_queue"` over 100 rules/page, retries twice, empty/non-numeric = unreadable | Mirror it in TS: select by `.type`, per_page 100, a full page without the rule is unreadable (T4); `withGithubRetry` supplies the retry |
| "base hard-coded to main ... P3 residuals in sync-pr-behind.sh" | Bash, different subsystem; base fix needs `qw_snapshot`'s strict regex and every mock in `sync-pr-behind.test.sh` to change | Not folded; tracked #10832 (T5) |
| "armed-green-never-enqueued ... bounded fallback or alert" | The 48h stale-bot-PR watchdog (`cron-cloud-task-heartbeat.ts`) only warns and only covers four head-ref prefixes; the reaper acts on any armed bot PR | Alert in the reaper's own arm at 6 h (checks terminal) or 24 h (any checks) (T1, T6) |

## Research Insights

**Premise Validation.** #9454 is OPEN (merge-queue epic). Cited paths exist on this branch's base: the reaper (509 lines), its
test (499 lines), `sync-pr-behind.sh` (`queue_wait_eval` at the rules read), `merge-queue-dequeue.md` ("Armed and green but
never enqueued"). The live ruleset lists `merge_queue` as the second rule (not first), confirming select-by-type. ADR-270 addenda
2026-10-07 (enqueue while BEHIND is measured to work under the strict policy), 2026-10-09 and 2026-10-20 (residual 6: base is
`main`; PR #10655 body: "`cron-bot-pr-reaper` still calls `update-branch` on armed bot PRs") are the governing decisions; no ADR
rejects the mechanism. `gh api repos/jikig-ai/soleur/rules/branches/main?per_page=100` answers unauthenticated on this public repo.
Nothing cited is stale.

**Backlog measurement (first-sweep alert flood check, review finding).** `gh pr list --state open --json ... ` on 2026-10-22: 4 open `soleur-ai` PRs, 0 with auto-merge armed, 0 armed-and-BEHIND. The 6 h `created_at` bound therefore cannot alert a standing backlog on the first post-deploy sweep (the ~24-PR backlog the file header cites from 2026-09-30 is gone). Re-run the same count in the work phase before merge; a non-zero armed-BEHIND set older than 6 h would be alerted once, as a single dedup issue, on the first sweep.

**Property List.**
1. A queue repo's armed BEHIND bot PR is never update-branched by the reaper.
2. An unknown answer to "does main have a queue" is never read as "no queue" (fail closed).
3. The rules are read once per sweep, not once per PR, and only when there is an armed bot PR to judge.
4. A bot PR the queue never enqueues does not rot silently.
5. Repos without a queue, and the dirty/blocked/unstable arm, behave exactly as today.

**Cut List.** (mechanism -> property -> what already covers it)
- Bounded update-branch fallback after N hours -> property 4 -> the 6 h / 24 h age-bounded alert covers it without a push (T1, T6, CTO).
- Per-PR rules read -> property 3 -> the memoized sweep-level step.
- A `base.ref` guard -> accepted residual (T3).
- Dropping the no-queue update path (DHH: this repo's `main` always has the rule) -> operator-stated direction "keep the update-branch path for repos without a queue" is kept (T7); the verdict is a runtime read, and the rule has been reverted once before (2026-06-30 deadlock kill-switch, `ruleset-ci-required.tf`).
- A repo-wide source-walk "single update-branch writer" test -> property none of the five; replaced by a comment at the call site and one ADR sentence (T8).
- Folding the `sync-pr-behind.sh` helpers -> out of the reaper's files (T5, #10832).
- A new Sentry monitor/alert resource -> `scheduled-bot-pr-reaper` monitor and the `[ci/bot-pr-reaper]` dedup issue already exist.

**Institutional learnings applied.**
- `2026-06-02-auto-merge-livelock-fast-moving-main.md` (2026-10-07 section): under a `merge_queue` rule the sync is unnecessary.
- `2026-07-19-a-wall-clock-break-in-a-replayed-body-...md` and `2026-06-12-inngest-cron-heartbeat-gate-on-final-attempt-and-step-memoization.md`:
  in-memory state in a replayed body is not once-per-run; a fake `step.run` that runs each callback once cannot see replay defects, so the verdict is a memoized step result passed by value.
- `2026-06-30-merge-queue-iac-provider-schema-probe-and-positional-rule-readers.md`: read rules by `.type`, never by position.
- `2026-07-23-live-api-fail-closed-guard-counts-degraded-200-as-empty-...md`: a degraded 200 (non-list body) is unreadable, not empty.
- `2026-10-12-the-consumer-test-set-its-own-inputs-and-the-stub-answered-any-argv.md`: the octokit stub must reject unknown routes (it already throws) and assert the rules call's params.

**Deepen-pass verification (live, 2026-10-22).**
- `gh issue view`: #10655 MERGED, #10832 OPEN, #9454 OPEN, #9274 CLOSED (the original reaper issue), #9869 CLOSED. All rule ids the plan cites (`cq-write-failing-tests-before`, `cq-union-widening-grep-three-patterns`, `hr-type-widening-cross-consumer-grep`, `cq-test-fixtures-synthesized-only`) resolve to active ids in `AGENTS.rules.md`.
- `rg -n "update-branch" apps/web-platform/server`: the only route literal is the reaper's `PUT .../pulls/{pull_number}/update-branch` (reaper line 225); other hits are prose (`execution-placement.ts:82` reason string, which stays true because the no-queue path remains, and `routine-metadata.ts:52`, edited here).
- `apps/web-platform/server/github-retry.ts`: `withGithubRetry` = 3 attempts, 1 s then 2 s backoff, retrying only when the cause chain carries `fetch failed` / an undici code (a plain `status: 500` or `403` is NOT retried, so a rules-read failure fails fast into `unreadable`).
- docs.github.com "Get rules for a branch": `per_page` default 30, max 100. The page lists no fine-grained permission for the endpoint; the endpoint answers unauthenticated on this public repo (measured), and an installation token is a superset of that access. If the live token were nevertheless refused, the result is `unreadable`: safe (no update-branch) and loud (Sentry event, alert after 6 h) - AC14 verifies it post-deploy.
- Inngest memoization: `reapBotPr`'s `updatesUsed` counter is rebuilt from memoized `evaluate-pr-N` results after replay, so it was already replay-safe; only the new verdict needed the step form.

**CLI/endpoint verification (#2566 gate).** `gh api "repos/jikig-ai/soleur/rules/branches/main?per_page=100"` run 2026-10-22 returned five rules
(`required_status_checks`, `merge_queue`, `required_status_checks`, `deletion`, `non_fast_forward`). The endpoint needs only
repository Metadata read; the reaper's minted token already holds `contents: write`, so no grant change (the mint-grant test stays as is).

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` bodies checked for the reaper, its test, `routine-metadata.ts`, ADR-270 and `sync-pr-behind.sh`: no match.)

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly - the reaper acts only on `soleur-ai[bot]` cron-artifact PRs
(daily digests, architecture-sync, growth-audit). The worst outcome is a bot PR that is not auto-rebased and sits unmerged until
the 6 h alert files the `[ci/bot-pr-reaper]` issue; the inverse regression (still update-branching on a queue repo) only costs CI minutes.
**If this leaks, the user's data / workflow / money is exposed via:** no vector - no new credential, grant, input from PR titles, or
user data path; only bot-generated fields (PR number, state enum, `reason` enum) reach the issue body and Sentry extras, as today.
**Brand-survival threshold:** none

threshold: none, reason: the diff touches `apps/web-platform/server/` (sensitive-path regex) but only changes which GitHub API call a bot-PR sweep makes; it adds one read of public repository rules with the existing token grants, no user data, auth, billing or credential surface.

## Architecture Decision (ADR/C4)

### ADR
Amend ADR-270 with `### Addendum 2026-10-22 (#9454): the bot-PR reaper defers to the queue` (no new ordinal), four bullets: (1) the reaper joins the armed-BEHIND refusal family (today exactly one `update-branch` call site under `apps/web-platform/server/`), superseding the 2026-10-20 note that it sits outside the family; (2) alert-not-update: 6 h from `created_at` with terminal checks, 24 h whatever the check status, neutral reason text, and why the 48h watchdog (warn-only, four head-ref prefixes) and a bounded fallback sync were rejected; (3) fail closed on an unreadable or truncated rules read, read once per sweep through a memoized step; (4) accepted residuals: non-main base (T3), `created_at` over-approximates arm age for a re-armed PR, `blocked`-while-checks-pending alerts are pre-existing noise, no-queue path retained although this repo's `main` has the rule. This is a task in Phase 4, not a follow-up issue.

### C4 views
No C4 change. Checked against `spec.c4` (element kinds, read in full), `views.c4` (every `include` list, which already carries `github` and the `api` container) and `model.c4`
(enumerated by endpoint, not by the feature noun: every `api -> github`, `github -> ...` and `engine/webapp -> github` edge, lines 536-568, 645, 704-728):
(a) external human actors - none added; (b) external systems - GitHub is already modeled; the `api -> github` edge (line 714) describes the audited App-token client's issue/Pages/diagram-editor operations and
already omits the reaper's PR reads and writes (pre-existing, not widened by one more read of `GET .../rules/branches/main`), and no element names the reaper or update-branch, so nothing is falsified;
(c) data stores - none touched; (d) actor-surface access relationships - unchanged. `bash plugins/soleur/test/c4-count-parity.test.sh` run on this base: `ALL TESTS PASSED`.

### Sequencing
The addendum describes the shipped behaviour; it lands in the same PR as the code.

## Implementation Phases

Constants and shapes (all in `cron-bot-pr-reaper.ts`):

```ts
const BASE_BRANCH = "main";                       // residual T3: PR list is not base-filtered
const QUEUE_ENQUEUE_GRACE_MS = 6 * 60 * 60 * 1000; // measured enqueue 9-47 min; 6 h with terminal checks (T1)
const QUEUE_INFLIGHT_BOUND_MS = 24 * 60 * 60 * 1000; // alert regardless of check status (T6)
const RULES_PAGE_SIZE = 100;
export type QueueRuleVerdict = "queue" | "none" | "unreadable";
export async function readMergeQueueRule(octokit: Octokit): Promise<{ verdict: QueueRuleVerdict; cause?: string }>;
// SweepResult gains: actions "skipped-queue-owned" | "skipped-queue-unknown"; optional reason?: "queue-stalled" | "queue-stalled-checks-running" | "queue-rule-unreadable"
// reapBotPr args gain: queueRule: QueueRuleVerdict (required), createdAt: string, nowMs?: number
```

### Phase 1 - RED (tests first, `cq-write-failing-tests-before`)
Extend `apps/web-platform/test/server/inngest/cron-bot-pr-reaper.test.ts`; run `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-bot-pr-reaper.test.ts` and confirm the new tests fail for the right reason (missing export / update-branch still called), not an import error.
See Test Scenarios. `octokitStub` gains a `rules?: unknown` option whose default is a synthesized NON-queue list (so the existing behind tests keep meaning "no queue"), serves `GET /repos/{owner}/{repo}/rules/branches/{branch}`, and records params in `calls`. The four existing handler `mockImplementation`s (filters/oldest-first, stuck-PRs, per-PR-failure, update-cap) each gain the same route: without it the read is `unreadable` (the stub throws on unknown routes), which turns their update assertions into skips and, in the two tests that assert `reportSilentFallback` `toHaveBeenCalledTimes(1)`, makes the count 2 for the wrong reason. Existing direct `reapBotPr` calls gain `queueRule: "none"` and an old `createdAt`. Rejection cases in `readMergeQueueRule` tests use plain `Error`/status objects (non-retryable); a `fetch failed` TypeError would sleep 1 s + 2 s inside `withGithubRetry`, so that case uses `vi.useFakeTimers()` + `advanceTimersByTimeAsync` or is left out.

### Phase 2 - GREEN: `readMergeQueueRule` + `reapBotPr`
- `readMergeQueueRule`: `withGithubRetry(() => octokit.request("GET /repos/{owner}/{repo}/rules/branches/{branch}", { owner, repo, branch: BASE_BRANCH, per_page: RULES_PAGE_SIZE, headers: { "X-GitHub-Api-Version": "2022-11-28" } }))`. Never throws: catch -> `{ verdict: "unreadable", cause }`. Non-array body -> unreadable. `rules.some((r) => r?.type === "merge_queue")` -> `queue`. `rules.length >= RULES_PAGE_SIZE` without the rule -> unreadable ("full page, rule may be on a later page"). Otherwise `none`.
- `reapBotPr` behind arm, FIRST statements (before the cap and before `checksTerminal`, so a queue verdict has no side effects and no check-runs read inside the grace window):
  `if (queueRule !== "none")`: `age = (nowMs ?? Date.now()) - Date.parse(createdAt)`; an unparseable timestamp (`!Number.isFinite(age)`) counts as past both bounds (alerts, never hides). Age <= 6 h: return `skipped-queue-owned` / `skipped-queue-unknown`. Past 6 h: `checksTerminal` true -> `{ action: "stuck-alerted", reason: queue-stalled | queue-rule-unreadable }`; false and age <= 24 h -> `skipped-checks-in-flight`; false and age > 24 h -> `stuck-alerted` with `queue-stalled-checks-running` (or `queue-rule-unreadable`). Then fall to the existing code only for `none`. Add a one-line comment at the update-branch PUT: "the only update-branch writer under apps/web-platform/server (T8)".

### Phase 3 - GREEN: handler wiring
- `list-open-bot-prs` maps `{ number, created_at }` (JSON-safe).
- After the list: `const queueRule = botPrs.length === 0 ? "none" : await step.run("read-merge-queue-rule", ...)`. Inside the step: call `readMergeQueueRule`; on `unreadable` call `reportSilentFallback(redactErr(new Error(cause), token), { feature: FUNCTION_NAME, op: "merge-queue-rule-unreadable", message: "merge-queue rule read failed; behind bot PRs are not update-branched (fail closed)", extra: { fn: FUNCTION_NAME } })` once; return only the verdict string.
- Pass `queueRule`, `createdAt: pr.created_at` to `reapBotPr`.
- `sync-stuck-issue`: the body intro stops claiming only "update-branch cannot fix" and names both cohorts; each stuck line appends a neutral reason text when present (`armed, behind, not enqueued after 6h; checks complete, may include failures` / `armed, behind, not enqueued after 24h; checks still running` / `armed, behind, merge-queue rule unreadable for over 6h`; never "green", never a cause the code cannot know); the Sentry `prs` extra carries `reason`. The `stuck` filter (`action === "stuck-alerted"`) is unchanged, so the dedup/self-close logic is untouched.
- Final `logger.info` gains `queueRule` so the effect is visible in run logs (the per-PR actions already sit in `results`).
- Update the file header comment (add the queue paragraph, fix "every 2 h it re-bases eligible bot PRs") and `routine-metadata.ts` `cron-bot-pr-reaper.description` (10-160 chars, currently says it update-branches behind PRs): `Sweeps armed soleur-ai[bot] PRs every 2h; update-branches settle-guarded behind ones (cap 5) unless the merge queue owns them; files a stuck-PR issue (#9274).` (158 chars, measured).

### Phase 4 - ADR addendum
Add the ADR-270 addendum (see Architecture Decision). Do not edit any AGENTS rule line, `AGENTS.rules.md`, or `.claude/rule-weakening-acks.txt`.

### Phase 5 - Verify, ship, post-merge
`vitest` for the reaper file plus `routine-metadata-parity`, `function-registry-count`, `execution-placement` and `cron-safe-commit-parity` tests; `tsc --noEmit`; type-widening sweep per `cq-union-widening-grep-three-patterns` / `hr-type-widening-cross-consumer-grep`: `rg -n "SweepResult|stuck-alerted|skipped-update-cap|reapBotPr\(|action ===" apps/ plugins/` (the union is local to the file and the test file is the only other `reapBotPr` caller - re-confirm at work time); `bash plugins/soleur/test/c4-count-parity.test.sh`. Then `soleur:ship` (see Post-Merge).

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-bot-pr-reaper.ts` - read step, `readMergeQueueRule`, behind-arm deferral, alert-body reason, header comment.
- `apps/web-platform/test/server/inngest/cron-bot-pr-reaper.test.ts` - new tests (RED first), updated stubs/call sites.
- `apps/web-platform/server/inngest/routine-metadata.ts` - one description string (otherwise the operator UI states the old behaviour).
- `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` - addendum.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-reaper-queue-owned-behind/decision-challenges.md` (done at plan time), `tasks.md`.

## Guard Contract

The deferral is a fail-closed gate on a mutating call, so it carries a contract.

### Guard 1 - reaper queue-deferral gate

**Property.** The reaper never issues `PUT .../update-branch` for a PR while `main`'s merge-queue rule is present or unknown, and a PR in that state that stays armed and BEHIND past its bound is alerted, not updated.

**Assembly.** The writers are every `update-branch` call site under `apps/web-platform/server/` (today exactly one, the behind arm of `reapBotPr`, marked by a comment; the ADR addendum states the count), the single verdict chokepoint `readMergeQueueRule` feeding it, and the per-PR `evaluate-pr-N` steps that consume the verdict by value; the verdict is produced once by the `read-merge-queue-rule` step, so the quantifier is "every evaluated PR", not "the first". Every test asserts the recorded call list (rules request params, absence of check-runs and update-branch requests), not only the returned action.

**Mutation matrix.**

| # | Edit to the implementation | Must redden |
|---|---|---|
| M1 | delete the `queueRule !== "none"` branch (behind arm updates unconditionally) | queue and unreadable no-update tests |
| M2 | REORDER: move the queue branch after the cap check / `checksTerminal` (verdict no longer precedes side effects) | "queue + cap reached reads skipped-queue-owned" and "no check-runs read inside the 6 h window" tests |
| M3 | map `unreadable` to `none` (fail open), or drop the full-page truncation arm | unreadable no-update test; 100-rules-without-merge_queue test |
| M4 | read the rules per PR instead of once per sweep (a second member after a compliant first) | handler test: 3 behind PRs -> exactly 1 rules call |
| M5 | select the rule by position (`rules[0].type`) | merge_queue-not-first and merge_queue-at-index-99 tests |
| M6 | own dispatch: replace the `read-merge-queue-rule` step by an in-memory cache, or hard-wire the verdict to `none` | replay-simulating handler test (a memoizing fake `step.run`, handler invoked twice: still exactly 1 rules call) and the "rules route is called when a bot PR exists, never when none" test |
| M7 | invert a bound comparison, or let a NaN age pass as inside the window | past-6 h / past-24 h alert tests and the garbage-`created_at` alert test |

**Harness rows.** (a) Suite edit: make the octokit stub answer every route (drop its `unexpected route` throw) -> M3/M4/M6 must still redden because they assert call counts. (b) Must-PASS non-canonical inputs: a synthesized rules list of five unrelated rule types with no `merge_queue` (verdict `none`, update proceeds) and a list with `merge_queue` at index 99 of 100 (verdict `queue`); a guard that rejects everything cannot pass these.

**Anchor.** No stored value is compared (no hash, floor or manifest).

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor check-in for the sweep (existing) plus the "bot-PR sweep complete" log line, which now carries queueRule
  cadence: every 2h at :17; a dead reaper pages inside about 2.5h
  alert_target: Sentry cron monitor alert for scheduled-bot-pr-reaper
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (resource scheduled_bot_pr_reaper); apps/web-platform/server/inngest/functions/cron-bot-pr-reaper.ts (postSentryHeartbeat)
error_reporting:
  destination: Sentry through reportSilentFallback, feature cron-bot-pr-reaper
  fail_loud: an unreadable rule read emits op merge-queue-rule-unreadable once per sweep and the PR is alerted after 6h; a stuck or stalled set files the [ci/bot-pr-reaper] action-required issue and op bot-pr-unmergeable
failure_modes:
  - mode: merge-queue rule read fails (403, 5xx, non-list body, truncated page)
    detection: Sentry event op merge-queue-rule-unreadable (once per sweep); sweep log queueRule=unreadable
    alert_route: Sentry issue; behind PRs older than 6h reach the dedup issue with the unreadable reason
  - mode: armed BEHIND bot PR never enqueued by GitHub
    detection: after 6h with terminal checks the PR is stuck-alerted with reason queue-stalled
    alert_route: [ci/bot-pr-reaper] action-required issue plus Sentry op bot-pr-unmergeable
  - mode: regression - reaper update-branches on a queue repo
    detection: unit tests M1/M2 in CI; at runtime the sweep log shows updated>0 together with queueRule=queue
    alert_route: CI check failure blocks the PR
logs:
  where: Inngest run output (structured logger.info) and Sentry events for feature cron-bot-pr-reaper
  retention: Inngest run-history and Sentry project retention as configured for the platform
discoverability_test:
  command: curl -fsS --max-time 10 "https://api.github.com/repos/jikig-ai/soleur/rules/branches/main?per_page=100"
  expected_output: merge_queue
```

Field RUM and the soak/follow-through enrollment do not apply (no browser surface; no time-gated close criterion beyond the 6 h in-code bound). Blind-surface probe (2.9.2): a cron worker - the in-surface signal is the sweep's own log line and the Sentry `op` tags above, emitted from the worker itself.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "skip with a distinct action (e.g. `skipped-queue-owned`) when main has a merge_queue rule" [brief] | Phase 2 behind arm, `skipped-queue-owned` | mapped |
| 2 | "reading the rule fail-closed (unknown answer = do not update; same stance as sync-pr-behind.sh `queue_wait`)" [brief] | Phase 2 `readMergeQueueRule`, `skipped-queue-unknown` | mapped |
| 3 | "cache the rules read once per sweep" [brief] | Phase 3 memoized `read-merge-queue-rule` step (T2) | mapped |
| 4 | "keep the update-branch path for repos without a queue" [brief] | Phase 2 verdict `none` path unchanged | mapped |
| 5 | "keep the dirty/blocked/unstable alert arm unchanged" [brief] | Phase 3 (stuck filter unchanged; only body text/reason added) | mapped |
| 6 | "Decide in the plan whether an armed-green-never-enqueued PR still needs a bounded fallback" [brief] | T1 ruling: 6 h age-bounded alert, no fallback | mapped |
| 7 | "Extend `apps/web-platform/test/server/inngest/cron-bot-pr-reaper.test.ts` (RED first)" [brief] | Phase 1 | mapped |
| 8 | "Also fold in ONLY if trivially cheap and in the same files: the other known P3 residuals in `plugins/soleur/scripts/sync-pr-behind.sh`" [brief] | T5 | descoped - justification: bash in a different subsystem, fixture mocks and the snapshot regex change with it, so it fails both "trivially cheap" and "same files"; tracked #10832 |
| 9 | "do not edit `.claude/rule-weakening-acks.txt` or any AGENTS rule line" and "Do not touch #9482, #10245, #5840" [brief] | Phase 4 constraint; Acceptance Criteria | mapped |
| 10 | "if subagent/review seats fail, run the panel that is available and disclose degraded coverage in the PR body" [brief] | Ship phase / Acceptance Criteria | mapped |
| 11 | "use `Ref #N` only (no closes/fixes/resolves)", merge via `with_lock merge-main`, "wait for it", "Finish with soleur:postmerge" [brief] | Post-Merge section | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `cron-bot-pr-reaper.ts` edits | asks 1-6 | asked |
| `cron-bot-pr-reaper.test.ts` edits | ask 7 | asked |
| `routine-metadata.ts` description | - | inferred - justification: the operator-facing description states the old unconditional update-branch behaviour and would be false after the change; `routine-metadata-parity` pins its length |
| ADR-270 addendum | - | inferred - justification: plan skill Phase 2.10 makes the ADR addendum a deliverable of any plan that extends an existing ADR decision family (the reaper joins the 2026-10-09/2026-10-20 refusal family) |
| 6 h age-bounded alert arm | ask 6 ("or should be alerted instead") | asked |
| `decision-challenges.md` | "Persist every decision as a row of the `| Item | Class | Ruling |` table" [brief] | asked |

### Split Assessment

- Subsystems touched: 2 - `apps/web-platform`, `knowledge-base`
- Planned files: 5 | Estimated changed lines: about 230
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1 RED-first (work-skill gate, not a CI check): the first commit contains only test changes and the reaper test run on it fails on behaviour (a queue verdict still reaches update-branch); the implementation commit follows.
- [ ] AC2 `vitest run test/server/inngest/cron-bot-pr-reaper.test.ts` green, including the scenarios under Test Scenarios; `tsc --noEmit` clean; `routine-metadata-parity`, `function-registry-count`, `execution-placement`, `cron-safe-commit-parity` green.
- [ ] AC3 Behind arm: verdict `queue` and `unreadable` never produce an update-branch request and (inside the grace) no check-runs request; verdict `none` keeps today's path: the existing none-path tests pass unchanged apart from the added args and still assert `expected_head_sha`.
- [ ] AC4 The rules request carries `branch: "main"` and `per_page: 100`; a merge_queue rule at any position is found; 100 rules without it is `unreadable`.
- [ ] AC5 One rules read per sweep for N behind PRs, zero reads when there is no bot PR; the grant-mint test still passes unchanged.
- [ ] AC6 Past 6 h (and for an unparseable `created_at`), a queue/unknown behind PR with terminal checks yields `stuck-alerted` with a neutral reason, files/refreshes the `[ci/bot-pr-reaper]` issue, and emits `bot-pr-unmergeable`; with checks in flight it yields `skipped-checks-in-flight` until 24 h and `stuck-alerted` (`queue-stalled-checks-running`) after.
- [ ] AC7 `unreadable` emits exactly one `merge-queue-rule-unreadable` Sentry call per sweep with the token redacted; `dirty`/`blocked`/`unstable` still `stuck-alerted` under every verdict.
- [ ] AC8 The update-branch PUT carries the single-writer comment, and `rg -c "PUT /repos/\{owner\}/\{repo\}/pulls/\{pull_number\}/update-branch" apps/web-platform/server` reports exactly one hit (the reaper); the other `update-branch` mentions under `apps/web-platform/server/` are prose (reaper comments, the `execution-placement.ts` reason string, the `routine-metadata.ts` description).
- [ ] AC9 `git diff origin/main...HEAD --name-only` contains none of `AGENTS.md`, `AGENTS.rules.md`, `.claude/rule-weakening-acks.txt`, `plugins/soleur/scripts/sync-pr-behind.sh`; no mention of closing #9482, #10245, #5840 anywhere in commits/PR body.
- [ ] AC10 ADR-270 addendum present (dated 2026-10-22, names the T1-T4 rulings and residuals); `bash plugins/soleur/test/c4-count-parity.test.sh` still passes.
- [ ] AC11 PR body: `Ref #9454` and `Ref #10832` only, a `## Changelog` section, `Reviewed-Coverage:` line disclosing any review seat lost to the weekly API limit, ends with the Claude Code generated-with line; commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; files added by explicit path (never `git add -A`); identity Jean Deruelle.

### Post-merge (operator-free)
- [ ] AC12 Merge via `plugins/soleur/scripts/lib/session-state.sh with_lock merge-main 600 -- gh pr merge <N> --squash --auto`; wait for this PR's own post-merge push run on `main` to finish green (it is the check that matters).
- [ ] AC13 `soleur:postmerge`: deploy-arm served == CONTAINS and `/health` supabase connected.
- [ ] AC14 After the first scheduled sweep following deploy (cadence 2 h at :17, so wait up to about 2 h; or fire `cron/bot-pr-reaper.manual-trigger` through `soleur:trigger-cron`, which is `confirm`-class), Sentry shows no `merge-queue-rule-unreadable` event for feature `cron-bot-pr-reaper` (query the Sentry events API, not the dashboard); if the installation token turns out unable to read repository rules, the failure is safe (no update-branch) and loud (that event), and the fix is a permission/grant decision, not a revert.

## Domain Review

**Domains relevant:** Engineering

### Engineering
**Status:** reviewed
**Assessment:** CTO ruled T1-T4 (see `decision-challenges.md`): alert-not-update at 6 h from `created_at`, memoized verdict step with Sentry mirror and a distinct unknown action, no base-ref guard, truncation is unreadable. Cross-cutting: infra/ruleset unchanged; no new token grants.

No Product/UX surface (no `components/`, `app/**/page.tsx` or layout file), no legal/data surface (GDPR gate does not fire: no schema, auth, API route or personal-data path), no IaC (no new infrastructure, secret or vendor).

## Test Scenarios

`reapBotPr` unit tests (all via the route-dispatching `octokitStub`; assert call lists, not just actions):
1. behind + `queue` + terminal checks + `createdAt` 1 h old -> `skipped-queue-owned`; no update-branch call; no check-runs call.
2. behind + `queue` + `updatesUsed >= updatesCap` -> still `skipped-queue-owned` (verdict precedes the cap).
3. behind + `unreadable` -> `skipped-queue-unknown`; no update call.
4. behind + `none` -> `updated` with `expected_head_sha` (existing test, new args); 422 head-moved and in-flight tests keep their meaning under `none`.
5. behind + `queue`, `createdAt` 7 h old (injected `nowMs`), terminal checks -> `stuck-alerted`, `reason: "queue-stalled"`; same with `unreadable` -> `queue-rule-unreadable`; in-flight checks at 7 h -> `skipped-checks-in-flight`, at 25 h -> `stuck-alerted` with `queue-stalled-checks-running`; garbage `createdAt` -> alerts.
6. `dirty|blocked|unstable` x `queue|none|unreadable` (it.each) -> `stuck-alerted`, no update; `clean|draft|has_hooks` unchanged.

`readMergeQueueRule` tests: merge_queue second of five -> `queue`; five unrelated rules -> `none`; merge_queue at index 99 of 100 -> `queue`; 100 unrelated -> `unreadable`; request rejects (403 / 500 as plain errors) -> `unreadable` with a cause string; non-array body -> `unreadable`; request params are `branch: "main"`, `per_page: 100`.

Handler sweep tests: three behind PRs + queue rules -> zero update-branch calls and exactly one rules call, `ok: true`; same PRs + no-queue rules -> today's updates (oldest-first, cap 5) and exactly one rules call; rules read throws -> zero updates, one `merge-queue-rule-unreadable` Sentry call (token scrubbed), heartbeat still posted; no bot PRs -> zero rules calls; a stalled queue PR (list `created_at` 7 h old) -> dedup issue created with the reason line and `bot-pr-unmergeable` extra carrying `reason`; a `dirty` PR under a queue verdict still files the issue. A replay-simulating case: a `step.run` fake that memoizes by step name and a handler invoked twice with the same memo -> the rules route is hit exactly once (an in-memory cache would hit it twice). The stalled-queue case also asserts the issue-body reason line, `reason` inside the Sentry `prs[]` extra and `issueNumber`. Source-shape anchors: `"merge_queue"`, `rules/branches`, `read-merge-queue-rule`.

## Sharp Edges

- `queueRule` is a REQUIRED arg of `reapBotPr` on purpose: an optional/default would make a forgotten call site either fail open or break silently. All existing direct-call tests and four handler stubs must be updated in the RED phase; a handler stub missing the rules route makes the read `unreadable` (the stub throws on unknown routes), which both reddens the test and proves the fail-closed path.
- Do not put the verdict in an in-memory object shared across `evaluate-pr-N` steps (replay rebuilds it); do not return the Octokit error or its message out of the step (the installation token can sit in it) - return the verdict only and report from inside the step with `redactErr`.
- Inside the 6 h window the queue arm must not read check-runs (no wasted request, no behavioural coupling to an in-flight verdict); between 6 h and 24 h in-flight checks suppress the alert (they may still be producing the verdict), after 24 h they no longer do - a hung or never-started check must not hide a stranded PR (T6).
- The existing `blocked` -> `stuck-alerted` behaviour fires on an armed PR still waiting on required checks regardless of age; that is pre-existing and deliberately unchanged here (recorded in the ADR addendum as a residual), not a regression of this PR.
- `created_at` is a proxy for arm time (bot PRs are armed at creation); a re-armed PR alerts early, the cheap direction (T1 dissent).
- Test fixtures are synthesized rule lists; never paste a live token or a live full ruleset payload (`cq-test-fixtures-synthesized-only`).
- A plan whose `## User-Brand Impact` section is empty, contains only filler text, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `none` with the sensitive-path reason.

## Post-Merge Pipeline

Ship per the brief: PR body uses `Ref #9454` / `Ref #10832` only; merge with `with_lock merge-main 600 -- gh pr merge <N> --squash --auto`; after the merge poll the PR's post-merge push run on `main` to completion; finish with `soleur:postmerge`. The weekly Anthropic API limit resets 2026-10-25 02:00 Europe/Paris: any review seat lost to it is named in the PR body's `Reviewed-Coverage:` line (degraded coverage disclosed, available panel still run).
