---
title: "infra: detect-and-file follower for undelivered apply runs (apply delivery gap)"
date: 2026-10-23
slug: apply-delivery-gap-follower
branch: feat-one-shot-apply-delivery-gap-follower
issue: 10033
refs: [9454, 10033, 8167]
type: feat
priority: p1-high
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# infra: detect-and-file follower for undelivered apply runs (apply delivery gap)

Spec lacks valid `lane:` (no spec.md on this branch) - defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-23. **Agents used:** CTO (rulings F1-F20, five rounds), plan-review panel (DHH, Kieran, code-simplicity, CTO devex), deepen panel (architecture-strategist, security-sentinel, spec-flow-analyzer, observability-coverage-reviewer, test-design-reviewer, framework-docs-researcher), learnings-researcher, functional-discovery (no overlap; nothing to install).

### Key improvements over the first draft

1. **Delivery requires the delivering run's `apply` job to have succeeded** (F11). A green non-apply dispatch, a kill-switched push or a skipped preflight at a descendant can no longer falsely deliver and close a real gap (found against the live files: the infra `apply` job runs only on push or `manual-rerun`).
2. **Per-workflow kill-switch markers** (F12): the infra workflow has its own `[skip-web-platform-apply]`.
3. **Read-class failures page a human** (F5'): a distinct `apply-delivery-gap-degraded` issue, because a red run has no actor and the operator digest reads only `action-required` issues. Transient failures are retried inside `api_get` before they count.
4. **Identity of the gap issue is bot author + exact title** (F20/F18), not the label alone, so a mislabelled human issue is never overwritten or closed and a deleted label cannot orphan the issue. The body is bounded (F19).
5. **Close arm hardened** (F3/F13'/F14): closes only on a complete read with nothing in flight, and only when something was actually delivered; an aged-out gap is left open with one comment.
6. **Test architecture**: the fixture seam is a `gh` shim on `PATH` (so the real `api_get` code path runs and the exact read set is asserted, including that no search parameter is ever sent); the mutation battery is hygienic (pristine control, return-code discrimination, anchor-once, sub-case pins).

### New considerations discovered

- Whether `workflow_run: completed` fires for a run cancelled while still pending in a concurrency group is UNVERIFIED in the GitHub docs (fires "regardless of the conclusion"; the pending-cancel case is not documented). The design does not depend on it.
- `created_at` stability across re-runs and run-list ordering are not documented. The design sorts client-side, stops paging only when a whole page is older than the cutoff, and does not rely on `created_at` for correctness (ancestry and the `apply` job leg decide delivery).
- Live base rate: deploy-fix has had 4 cancelled PUSH runs in 40 days (2026-09-14, 2026-10-09 x2, 2026-10-11); no cancelled infra runs in the last 100. Two cancelled `workflow_dispatch` recoveries exist on 2026-10-11 (the operator's own delivering dispatch can be cancelled).

## Overview

Ship one small PR that makes a silently cancelled, path-filtered production apply run loud: a secret-free `workflow_run`
follower that reconciles the two apply workflows ("Apply deploy-pipeline-fix" and "Apply web-platform infra
(Doppler/Cloudflare/BetterStack/GitHub-App/Inngest/firewall)") and files one deduplicated `apply-delivery-gap` issue
naming each undelivered push SHA and run URL. It is detection only: no apply, no dispatch, no `terraform`, no state or host
read, no secrets. The binding design is the CTO ruling of 2026-10-22 recorded on issues #10033 and #8167 (read in full in
this session); it is not re-litigated here. Neither issue closes when this ships: every reference is `Ref`, never a closing keyword.

Deliverables (one PR, tracker #9454):

1. `.github/workflows/apply-delivery-gap-follower.yml` - thin wrapper: trigger, permissions, concurrency, sparse checkout of the script, one `run:` line.
2. `scripts/apply-delivery-gap.sh` - all logic, with `--self-test` and `--fixture-dir <abs dir>` (the directory supplies a `gh` shim and fixture JSON instead of the real CLI).
3. `plugins/soleur/test/apply-delivery-gap-follower.test.sh` + `plugins/soleur/test/fixtures/apply-delivery-gap/` - RED-first suite: the named scenarios, the recorded-incident replays, a workflow-wiring leg, and an always-on mutation battery over sandbox copies of the script.
4. A section in `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-red-run.md` (gap issue -> decision table -> dispatch command -> verification -> degraded issue -> flip-evidence recipe).
5. An ADR-270 addendum recording the detection-only decision, the flip evidence bar and the residuals.

## Research Reconciliation - Spec vs. Codebase

| Spec / ruling claim | Reality (verified in this session) | Plan response |
|---|---|---|
| Candidates = "last ~50 runs ... conclusion cancelled" | `GET .../runs?status=&event=&branch=` are SEARCH params; learning 2026-09-24 measured them stale while the UNFILTERED list was current. Live volume: infra ~10 runs/day (100 runs span ~10.5 days). | CTO F1: unfiltered list (`per_page=100`, manual `page=N`, 10-page hard stop = `run_window_truncated`), client-side filtering; the suite asserts the exact read URLs carry no search parameter. |
| Evicted runs are "cancelled 1-3 s after creation with zero jobs" | `37964350917` was created 17:10:14Z, cancelled 17:13:44Z (3.5 min) yet has `total_count: 0` jobs. | Class comes from the jobs count (binding), never from timing. |
| Kill switch is "the deploy-fix kill switch ... copy the workflow's own regex" | deploy-fix: `[skip-deploy-fix-apply]` (:235). **infra has its own `[skip-web-platform-apply]` (:280-295).** | CTO F12: per-workflow marker table, each regex copied verbatim, used only to drop CANDIDATES; a watched workflow without an entry fails the suite. |
| Delivered iff "a run of W exists with conclusion success ... a workflow_dispatch success counts" | infra `apply` runs only `if: preflight.skip != 'true' && (push \|\| manual-rerun)`; ~17 other dispatch `apply_target` jobs end `success` without any apply. The real delivering dispatch `37976212395` has jobs `[preflight success, apply success]`. | CTO F11: the delivering run also needs its job named `apply` to have `conclusion == success` (jobs read only for runs that pass the ancestry test, memoised); this replaces the first draft's success-side regex. |
| "A success of the OTHER workflow does not count" | Both workflows share `terraform-apply-web-platform-host`, `cancel-in-progress: false`. | Success set is per workflow key; the follower's group is its own literal. |
| Exact trigger names | `Apply deploy-pipeline-fix` (:68); `Apply web-platform infra (Doppler/Cloudflare/BetterStack/GitHub-App/Inngest/firewall)` (:14). `workflow_run.workflows` matches `name:`. | Wiring leg compares the follower's `workflows:` AND the script's `WATCHED` table to the live `name:` strings. |
| In-flight "cap" (first draft: 90 min, "59 min ceiling") | The 59 min figure is infra only. deploy-fix `apply` has `timeout-minutes: 90` plus a job-level `web-1-swap` queue (release deploys drain up to ~70 min). | CTO F15': per-workflow caps (deploy-fix 150, infra 120; `waiting` 60 as briefed); a test parses each workflow's `apply` timeout and asserts the cap exceeds it. |
| Draft PR #10879 | Open, draft, empty. | Work lands on this branch; PR body uses `Ref` only. |
| Open PRs on touched files | Draft #8626: `.github/CODEOWNERS`. #10744 and #7390: `scripts/lib/test-affected-paths.sh`, `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv`. None touches ADR-270, the runbook or any new path. | None of those files is edited; see "Suite classification". |

## Research Insights

**Premise Validation (Phase 0.6).** Checked: #10033 and #8167 OPEN (the CTO ruling comments exist verbatim); #9454 OPEN; PR #10879
draft and empty; both workflow `name:` strings, both kill-switch regexes, both `apply` job names/conditions/timeouts and the shared
concurrency literal; ADR-270 exists (861 lines, latest addendum 2026-10-22); the runbook exists (102 lines) with no
`apply-delivery-gap` text; `gh label list` has `action-required`, `priority/p0-critical`, `priority/p1-high` and neither
`apply-delivery-gap` nor `apply-delivery-gap-degraded` (the script creates the two it owns, without `--force`, treating "already
exists" as success). ADR corpus grep for the mechanism: ADR-270 owns the merge-queue/post-merge-gate family and ADR-006 records the
lock-less R2 backend; no ADR rejects a detection-only follower. Read-only live facts: `37964350917`, `37964762496`, `38144232116`
are deploy-fix/push/main/cancelled/0 jobs (heads `48d5144c`, `d7dfd05a`, `568dfade`); dispatch `37976212395` (head `79482dab`,
2026-10-09T18:51:43Z) delivered with jobs `[preflight, apply]` both success; `compare 48d5144c...d7dfd05a` = `ahead`, `X...X` =
`identical`, the reverse = `behind`, an unknown SHA = HTTP 404 (JSON body on stdout, `gh: Not Found (HTTP 404)` on stderr, rc 1);
run-list items carry `head_commit.message`, `run_attempt`, `run_started_at`; the pinned checkout
`actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5` resolves to tag `v4.3.1`, is 40 characters and is used 167 times across `.github/workflows`.

**Property List (Phase 0.6b).**
P1. A push to `main` that matched an apply workflow's path filter and was cancelled becomes visible as a labelled, action-required issue within one completed apply run.
P2. A candidate stops being reported only when a later run of the same workflow actually applied (its `apply` job succeeded) at the candidate or a descendant.
P3. The follower never closes the issue or reports "no gap" on a partial or failed read, and a blind follower pages a human.
P4. One open gap issue exists at a time; rows are keyed (workflow, SHA); refreshing it is idempotent and re-asserts `action-required`.
P5. The follower cannot mutate production: no secrets, no environment, no state/host read, no dispatch.
P6. The flip decision has a countable evidence trail (SHAs and row ages).

**Cut List (Phase 0.6b).**

- Re-dispatch / auto-retry of the cancelled apply; single-workflow merge; #8167 option 2 (poll for the sibling) -> ruling: DEFERRED / rejected.
- A `schedule:` trigger as a second detection path -> duplicates the 12 h `scheduled-terraform-drift` cron and conflicts with the briefed `workflow_run`-only trigger; recorded in the ADR addendum as a rejected alternative.
- Third copy of the trigger-file list -> covered by "a push run exists only because the path filter matched".
- Stateful history (reading the previous body back) -> CTO F7.
- An acknowledgement label/marker per SHA ("I handled this another way") -> new mechanism beyond the brief; the runbook gives the safe moves instead (a revert commit delivers by descendant; closing by hand).
- `DRY_RUN`, an env `NOW` override, a `$GITHUB_STEP_SUMMARY` duplicate, a compare-result memo, `TRIGGER_HEAD_SHA` / `TRIGGER_CONCLUSION`, the H2 harness row -> plan-review: each maps to no property.
- A Sentry cron monitor -> would move the C4-parity counts and adds a vendor edge to a detector whose liveness is its own workflow run.
- CODEOWNERS rows, `test-affected-paths.sh` / `suite-shard-legs.tsv` / `suite-durations.tsv` edits -> files under open PRs (CTO F10; "Suite classification").
- A per-candidate `unverified` row class -> CTO F5' chose the degraded issue instead.
- A mutant per constant or log line (stale caps, classification, filters, trace output) -> plain assertions in the scenarios kill the same regressions.

**Institutional learnings applied** (under `knowledge-base/project/learnings/`):

- `2026-09-24-an-empty-api-search-is-not-evidence-of-absence-...md` - unfiltered list as the source (F1); keep early-exit pipelines out of assignments under `pipefail`.
- `2026-10-05-gh-api-f-flag-404s-on-get-query-params.md` - GET params live in the URL.
- `2026-03-24-gh-api-paginate-concatenated-arrays.md`, `2026-07-19-a-mutation-battery-that-passes-can-still-leave-the-central-mechanism-untestable.md`, `2026-07-23-gh-run-list-truncation-reports-false-all-settled.md` - multi-page fixture shape; a read ending exactly on a page boundary is the truncation signature.
- `2026-09-25-gh-stub-must-mirror-real-cli-flags.md` - the shim refuses (exit 64) any argv it was not written for and the suite asserts its refusal log is empty.
- `2026-09-24-the-reaper-assumed-every-run-it-cancelled-would-be-replaced.md` - re-read state immediately before acting; assertion floors from the first green run.
- `2026-10-06-a-line-anchored-extractor-cannot-see-a-prefixed-assignment.md` - spell lookups `X=$(gh ...) || { fail_loud ...; }`.
- `2026-07-02-gha-run-default-shell-has-pipefail-guard-grep-substitutions.md` - the `run:` block only calls the script; the script guards its own `grep` substitutions.
- `2026-09-20-the-gate-i-built-to-resolve-a-run-could-be-redirected-by-one-env-var.md` - no env var may override the API base or repo slug beyond validated `GH_REPO`; `--fixture-dir` is argv-only, the workflow passes no arguments, the test-only overrides are ignored outside fixture mode (tested).
- `security-issues/2026-07-01-two-stage-privileged-workflow-split-and-its-review-traps.md` - `workflow_run.workflows` matches `name:`; decisions read ONLY API data scoped to `main`; the one event value is a membership check.
- `best-practices/2026-07-05-cross-pipeline-serialization-via-shared-job-level-concurrency-group.md` - one pending slot per group, newest evicts; harmless for a stateless reconciler.
- Sharp-edges catalogue (Phase 6.5): run records are the guard's input, so their lifetime was measured; every prescribed command was executed once read-only; ACs use three-dot diffs.

**Platform behaviour this design does not depend on (UNVERIFIED, stated risk).** The GitHub docs say `workflow_run` fires
"regardless of the conclusion" but do not say whether a run cancelled while PENDING in a concurrency group emits `completed`; a
probe against the CI workflow's cancelled runs was inconclusive. The design does not need it: every completed run of either watched
workflow (including the evictor's own completion) triggers a full reconcile that re-reads the cancelled run, so detection is at worst
delayed to the evictor's completion, and the 12 h drift cron remains the backstop. Also UNVERIFIED in the docs and therefore not
relied on: that `GITHUB_TOKEN` with `issues: write` suffices for `gh label create` / `gh issue edit --add-label` (widely used; a failure
is loud and pages through `issue_write_failed`), run-list ordering, and `created_at` stability across re-runs. The first natural
occurrence is observed post-merge; nothing is forced (no apply dispatch).

## Open Code-Review Overlap

None for the files this plan edits or creates. Two open code-review issues mention `apply-web-platform-infra.yml` (#9705, #7098); this plan does not edit that file. #3321 mentions `.github/CODEOWNERS`, which this plan does not edit. Acknowledge, no action.

## Proposed Solution

### Trigger and wiring (workflow YAML)

```yaml
name: Apply Delivery Gap Follower
on:
  workflow_run:
    workflows:
      - "Apply deploy-pipeline-fix"
      - "Apply web-platform infra (Doppler/Cloudflare/BetterStack/GitHub-App/Inngest/firewall)"
    types: [completed]
    branches: [main]
concurrency:
  group: apply-delivery-gap-follower        # NOT the apply group
  cancel-in-progress: false
permissions:
  contents: read
  actions: read
  issues: write
jobs:
  follow:
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1 (40-char SHA, same pin as codeql-main-alert-gate.yml)
        with: { persist-credentials: false, sparse-checkout: scripts/apply-delivery-gap.sh, sparse-checkout-cone-mode: false }
      - env:
          GH_TOKEN: ${{ github.token }}
          GH_REPO: ${{ github.repository }}
          GITHUB_RUN_ID: ${{ github.run_id }}
          TRIGGER_RUN_ID: ${{ github.event.workflow_run.id }}
        run: bash scripts/apply-delivery-gap.sh
```

- No `ref:` on checkout: a `workflow_run` run defaults to the default branch's latest commit ("checkout of main only", confirmed in the docs: `GITHUB_SHA` for `workflow_run` is the last commit on the default branch). No `workflow_run.head_*` value is used anywhere.
- `TRIGGER_RUN_ID` (`^[0-9]+$`, CTO F16) is used for ONE membership check and is the only `github.event.*` value in the file. The watched workflows are triggered only by `push` and `workflow_dispatch` (no `pull_request*`), so no fork-controlled run can fire the follower; the wiring leg asserts both watched files' parsed `on` keys are a subset of `{push, workflow_dispatch}` so a later `pull_request` trigger reds the suite instead of silently widening the privileged surface.
- The YAML text avoids the words `terraform`, `secrets.`, `environment:` and the dispatch spellings even in comments (the suite greps raw text and prints why on failure, quoting the allowed phrasing "the apply group"). The apply group literal is never written in the file.

### Script algorithm (`scripts/apply-delivery-gap.sh`)

Constants: `WATCHED` rows `key|file|display name|kill-switch-regex|stale-cap-minutes` (deploy-fix: `[skip-deploy-fix-apply]`, 150; infra: `[skip-web-platform-apply]`, 120; regexes copied verbatim from each workflow's preflight); `WINDOW_DAYS=7`; `PAGE_SIZE=100`; `MAX_PAGES=10` (a comment records the live volume); `waiting` stale cap 60 min; `READ_BUDGET=150`; `LABEL=apply-delivery-gap`; `DEGRADED_LABEL=apply-delivery-gap-degraded`; `TITLE='infra: apply delivery gap - trigger-file change not applied'`; `DEGRADED_TITLE='infra: apply delivery gap follower degraded'`.

Entry order: (1) parse argv - `--self-test` is dispatched FIRST, before any env validation, needs no repo, token or network, reads only itself and writes only to a `mktemp -d` that an EXIT trap removes; any unknown argv -> exit 2 with `::error::apply_delivery_gap_bad_input`; (2) `unset GH_HOST GH_ENTERPRISE_TOKEN GH_DEBUG GITHUB_API_URL`; (3) validate `GH_REPO` (`^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`), `TRIGGER_RUN_ID` (digits or empty), `GITHUB_RUN_ID` (digits or empty); (4) `--fixture-dir <abs dir>`: the `assert_fixture_dir` guard copied from `codeql-main-alert-gate.sh`, requires `<dir>/bin/gh` to be executable, prepends `<dir>/bin` to `PATH`, reads `now` from `<dir>/now`, and ONLY in this mode honours `APPLY_DELIVERY_GAP_PAGE_SIZE` / `APPLY_DELIVERY_GAP_MAX_PAGES` and skips every sleep. So the real code path (including `api_get`'s return-code and stderr handling) runs against a `gh` shim; the real CLI is never reached in fixture mode and the test-only overrides are inert in live mode. Exit codes: 0 reconcile complete (a filed gap is a green run - the issue is the page); 1 any read/write failure; 2 rejected input. Every non-zero exit prints a named `::error::apply_delivery_gap_<reason>`.

Reads go through ONE wrapper `api_get` = `timeout 60 gh ...` with status read explicitly, `fail_loud <reason>` -> `exit 1` on failure, no `|| true` and no `2>&1` on a read. stderr is captured into a variable for classification only (anchored `\(HTTP [0-9]{3}\)$`) and is never echoed. Transient failures (HTTP 5xx, 429, 403 rate-limit, network, `timeout` rc 124) are retried up to 3 attempts with 2 s then 4 s backoff (no sleep in fixture mode); 404 and 422 are never retried. The budget counter (`READ_BUDGET`) counts jobs and compare reads (memoised per run id / per pair); exceeding it is `api_budget_exceeded`. Real and fixture paths are identical above `gh`. Bash discipline under `set -euo pipefail`: counters use `n=$((n+1))`; `grep -c`/`jq -e` empty results are guarded; ids go through `--arg ... | tonumber`; every jq field read has a `//` default (a null `conclusion` on an in-flight run must not abort); epoch maths use `jq fromdateiso8601`, never string comparison.

Output hygiene rule (script header): no value from jq reaches `echo`, `printf`, an annotation or the issue body unless it passed a validator (`^[0-9a-f]{40}$`, `^[0-9]+$`, an ISO timestamp, or membership in a closed enum - status, conclusion, class, workflow key). The "this run" URL is built from validated `GH_REPO` and a digits-checked `GITHUB_RUN_ID`, never from `GITHUB_SERVER_URL`. Branch names, titles, actors and commit messages are never printed (the message is read into a bash variable only for the `=~` match, per candidate, with `jq -r --arg id ... '... .head_commit.message // ""'`, so real newlines survive and `null` is safe).

Steps:

1. **Read runs (F1).** Per watched workflow: `gh api "repos/$R/actions/workflows/$FILE/runs?per_page=100&page=$p"`, p = 1..MAX_PAGES. Runs are sorted client-side by `created` desc then `id` and de-duplicated by id (a page shift between page reads can repeat a boundary run; ties share a second). Stop when a page has < PAGE_SIZE runs or EVERY run on it is older than the cutoff; a full page at page MAX_PAGES that still has an in-window run -> `run_window_truncated` (page MAX_PAGES full with everything beyond the cutoff is accepted). Strict shape validation applies only to runs that matter (candidates, in-window successes and in-flight runs: numeric `id`, 40-hex `head_sha`, ISO `created_at`, closed-enum `status`/`conclusion`); a malformed irrelevant record is skipped with one aggregate `::warning::`; a non-array `.workflow_runs` is `malformed_response`. Normalised record: `{id, event, branch, status, conclusion, sha, created, started, updated}`; the URL is rebuilt as `https://github.com/$R/actions/runs/$id`.
2. **Trigger visibility (F16).** If `TRIGGER_RUN_ID` is set, assert that run is present with `status == completed`; re-read up to 3 times, 5 s apart; then `trigger_run_not_visible` (exit 1).
3. **Candidates.** `event == push`, `head_branch == main`, `status == completed`, `conclusion == cancelled`, `created >= now - 7d`, and not carrying its OWN workflow's marker (logged `dropped killswitch workflow=<key> sha=<sha7>`). Other conclusions (`failure`, `startup_failure`, `timed_out`) are never candidates: they are owned by `notify-apply-failure` and the drift cron (ADR residual).
4. **Delivery (per candidate S on workflow W, same-W runs in `created` ascending order).**
   a. *Delivered* iff a run R of the SAME W has `status completed`, `conclusion success`, `head_branch main`, `created >= S.created`, AND (`R.sha == S.sha` or `compare S.sha...R.sha?per_page=1` `.status` in `identical|ahead`; `behind` and `diverged` are not descendants), AND R's jobs (`GET actions/runs/<id>/jobs?per_page=100`, memoised, read only after the ancestry test passes) contain a job named `apply` with `conclusion == success` (F11; `skipped` is not success). All qualifying R are considered in order and the first that passes every leg wins. HTTP 404 from compare = "not a descendant" + `::warning::apply_delivery_gap_compare_unresolvable sha=<sha7>` (F17); any other failure -> `compare_failed`. Delivery minutes = `R.updated - S.updated`, clamped to >= 0.
   b. else *Deferred* iff a same-W run with `status` in `queued|pending|requested|waiting|in_progress`, `head_branch main`, `created >= S.created`, not stale, and (`sha == S.sha` or ancestry via compare) exists - unconditionally (F8'); stale = `waiting` older than 60 min from `created_at`, or any other status older than the workflow's cap (`queued|pending|requested` from `created_at`, `in_progress` from `run_started_at` falling back to `created_at`); one `::notice::apply_delivery_gap_deferred workflow=<key> sha=<sha7>` per deferred candidate.
   c. else *Undelivered* -> a row.
5. **Classify rows** with `GET repos/$R/actions/runs/$id/jobs?per_page=1` `.total_count`: `0` = `evicted-before-start` (p1), `>= 1` = `cancelled-mid-run` (p0, state possibly partial; conservative - a preflight-only run is over-classified p0, recorded as a residual). Each row also records the latest later same-workflow run's conclusion and URL when one exists (a failed evictor is not an eviction).
6. **Reconcile the issue.**
   - Lookup (F20/F18): `ISSUES=$(gh issue list --author app/github-actions --state open --json number,title,labels --limit 100) || fail_loud issue_list_failed`, filtered in jq by `title == TITLE`; the author login string is verified at implementation. Several matches: refresh the lowest, close the extras `--reason "not planned"` with a pointer to the survivor. A label-only human issue is ignored. Read in the same run, immediately before the write.
   - `gh label create <name> --color <c> --description <d>` for the labels this script owns (`apply-delivery-gap`, `apply-delivery-gap-degraded`) before the arms; an "already exists" failure is success; any other failure is `label_failed`. Shared labels (`action-required`, `priority/p1-high`, `priority/p0-critical`) are repo conventions.
   - rows non-empty, no issue: `gh issue create --title TITLE --body-file F --label apply-delivery-gap --label action-required --label priority/p1-high [--label priority/p0-critical when any row is mid-run]`.
   - rows non-empty, issue open: ONE `gh issue edit N --body-file F --add-label apply-delivery-gap,action-required[,priority/p0-critical]` (F4': `priority/p1-high` is added at CREATE only; p0 is add-only; there is no `--remove-label` anywhere in the script).
   - rows empty, read complete, and NO non-stale run of EITHER watched workflow in flight (this subsumes the deferred set and the re-run case, F3/F14), issue open: if `delivered >= 1`, `gh issue close N --reason completed --comment <for each delivered candidate: workflow, sha7, delivering run id, minutes from cancel to delivery>`; if `delivered == 0` do NOT close - add ONE comment guarded by the marker `<!-- apply-delivery-gap:aged-out -->` ("no cancelled push remains inside the 7-day window; verify delivery and close this issue by hand", F13').
   - otherwise leave the issue untouched and log why.
   - Write calls (`issue create/edit/close/comment`, label create) are retried once after 10 s (no sleep in fixture mode) before `issue_write_failed`.
7. **Degraded path (F5').** `fail_loud` for the read-class reasons (`runs_list_failed`, `run_window_truncated`, `malformed_response`, `trigger_run_not_visible`, `jobs_read_failed`, `compare_failed`, `api_budget_exceeded`) first runs a best-effort upsert of ONE issue titled `DEGRADED_TITLE` (identity: bot author + exact title; labels `apply-delivery-gap-degraded` + `action-required`; body = the reason slug and this run's URL only; one comment per repeat) and then exits 1; the upsert is skipped for `issue_list_failed`, `issue_write_failed`, `label_failed` (the issue API itself failed) and a failing upsert exits 1 with `degraded_upsert_failed`. It never touches the gap issue and never prints "no gap". The next fully complete reconcile closes the degraded issue (`--reason completed`).
8. **Trace (F7).** One `::notice title=apply-delivery-gap::row workflow=<key> sha=<40hex> class=<c>` per row per reconcile plus `::notice::apply_delivery_gap_summary mode=live|fixture workflows_read=2 candidates=N rows=N deferred=N delivered=N dropped=N mid_run=N inflight=N issue=<none|#N|created|edited|closed|aged-out-comment>`. `workflows_read=2` is the anti-vacuity witness.

Failure reasons (each pinned by a scenario; the suite asserts the set of `apply_delivery_gap_[a-z_]+` literals in the script equals the set the scenarios assert): `bad_input`, `runs_list_failed`, `run_window_truncated`, `malformed_response`, `trigger_run_not_visible`, `jobs_read_failed`, `compare_failed`, `api_budget_exceeded`, `issue_list_failed`, `label_failed`, `issue_write_failed`, `degraded_upsert_failed`.

**Issue body** (a pure function of the current read; public-safe). Order, top to bottom: (1) a "Do this" block: ONE printed command per workflow that has rows (a dispatch at main HEAD covers every listed SHA of that workflow; it applies `main`, not the candidate); "the issue resolves itself when the next reconcile sees the push delivered"; for any `cancelled-mid-run` row "do NOT dispatch before reading the run - state is possibly partial"; "closing this issue is not an acknowledgement - a new one is filed while rows remain"; "comment, do not edit - the body is rewritten on every refresh". (2) the table, capped at 40 rows newest first (+ one line "+K more undelivered pushes not shown; see the run log notices"; the rendered body is asserted under 60,000 bytes before writing; the close arm uses the FULL row set):

| Workflow | Push SHA | Run | Class | Minutes since cancel | Later run of this workflow |
|---|---|---|---|---|---|

(3) footer: "last reconciled <UTC time> by <this run URL>" (minutes are approximate and clamped to >= 0), the 7-day window, "a row listed for more than 60 minutes warrants escalation", "a push carrying its own workflow's skip marker never appears here", the runbook path, and the drift-cron backstop. Printed commands, in a fenced block, deploy-fix: ``gh workflow run apply-deploy-pipeline-fix.yml --ref main -f reason='apply-delivery-gap <sha7>'``; infra: ``gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun -f reason='apply-delivery-gap <sha7>'``. The body references no issue number and contains no closing keyword.

## Files to Create

- `.github/workflows/apply-delivery-gap-follower.yml`
- `scripts/apply-delivery-gap.sh`
- `plugins/soleur/test/apply-delivery-gap-follower.test.sh`
- `plugins/soleur/test/fixtures/apply-delivery-gap/shim/gh` (the `gh` shim: serves `runs.<key>[.<page>|.r<attempt>].json`, `jobs.<runid>.json`, `compare.<S>.<R>.json`, `issues.json` with a `--limit`/`--author`/`--json` model of the real CLI, models the real 404 shape - JSON body on stdout, `gh: Not Found (HTTP 404)` on stderr, rc 1 - honours `fail.<call>` injectors and `.rc/.err` fixtures, appends every read (path + query) to `out/reads.log` and every write to `out/actions.log`, and exits 64 with a refusal log entry on any argv it was not written for)
- `plugins/soleur/test/fixtures/apply-delivery-gap/base/` (empty world: `runs.deploy-fix.json`, `runs.infra.json`, `issues.json`, `now`) and one small directory per named scenario, each holding ONLY the files it overrides: `cancelled-zero-jobs`, `cancelled-then-later-success-descendant`, `cancelled-with-jobs`, `cancelled-killswitch`, `success-only`, `non-push-or-non-main`, `inflight-descendant`, `api-failure`, `dedup`, `sibling-success-does-not-count`, `delivery-requires-apply-job`, `replay-37964350917`, `replay-37964762496`, `replay-38144232116`, `replay-incident-delivered`. Variants of those worlds are built inline by `mkrun`/`mkjobs`/`mkcompare` helpers in the suite and by `fail.<call>` marker files created in the sandbox, not committed.
- `knowledge-base/project/specs/feat-one-shot-apply-delivery-gap-follower/tasks.md`, `.../decision-challenges.md`

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-red-run.md` - add `## An apply delivery gap issue (label apply-delivery-gap)`: (a) a decision table in the existing "Do NOT fire this on these" format: `evicted-before-start` (dispatch the printed command from `main`); `cancelled-mid-run` (read the run first; if the re-dispatch is red use the heartbeat-sweep section above); a row whose "Later run" column shows a FAILED run (read that run first); a kill-switch commit sits between the row and HEAD (the printed dispatch applies HEAD including the skipped change - decide first); a push you cancelled on purpose because it was bad (a revert commit touching the trigger paths delivers by descendant; an operator-cancelled mid-run push correctly stays p0); (b) verification (the issue closes itself on the next reconcile; for deploy-fix rows also `scripts/check-deploy-script-parity.sh`); (c) closing is not an acknowledgement (a new issue is filed while rows remain); an aged-out issue (the follower's marker comment) is closed by hand after verifying delivery with the parity check; remove a stale `priority/p0-critical` by hand if the new gap is not mid-run; (d) the degraded issue: what each `::error::apply_delivery_gap_<reason>` means and the no-remote-shell next step (`gh run rerun <run-id> --failed` is safe: every reconcile is a full stateless read); (e) the flip-evidence count recipe - read-only `gh issue list --author app/github-actions --state all --json number,createdAt,title,body,comments` plus the `::notice row` log lines (about 90 days of retention, so count issue comments too), counted per DISTINCT SHA (the same SHA can appear in several issues) with the evidence unit defined as the SHA; row ages come from the close comment's "minutes from cancel to delivery"; (f) a dispatch from a non-main ref applies that branch to production and leaves the gap open - always `--ref main`. No remote-shell fallback (`hr-no-ssh-fallback-in-runbooks`).
- `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` - `### Addendum 2026-10-23 (#9454; Ref #10033, #8167): the apply delivery gap follower is detection only`, after the 2026-10-22 addendum and before `## Cost Impacts`.

Not edited, by constraint: `.github/CODEOWNERS` (draft #8626), `scripts/lib/test-affected-paths.sh`, `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` (open PRs #10744 and #7390), any AGENTS rule line, `.claude/rule-weakening-acks.txt`, both apply workflow files, #9482 / #10245 / #5840 artefacts.

### Suite classification (consequence of the constraint above)

The repo's orphan census (`scripts/lint-orphan-test-suites.sh`) marks a registered suite whose edges cannot be derived as UNCLASSIFIED and goes RED. `plugins/soleur/test/codeql-main-alert-gate*.test.sh` classify as `edge:derived` (verified with `bash scripts/test-all.sh --affected --print-affected-set`) because the suite names its SUT by repo-relative literal paths. This suite therefore names `scripts/apply-delivery-gap.sh`, `.github/workflows/apply-delivery-gap-follower.yml`, and both apply workflow files as repo-relative literals. Phase 1 gate: run `--print-affected-set | grep apply-delivery-gap` and `bash scripts/lint-orphan-test-suites.sh`. If it still reports UNCLASSIFIED, the declaration belongs in `scripts/lib/test-affected-paths.sh`, which this change may not touch while #10744 / #7390 are open: fallback order (1) make the dependency literal-derivable, (2) rebase onto the merge of those PRs and add the declaration, (3) report the blocker in the PR body rather than weaken the census. Local `--affected` may degrade to the full battery; the substitute gate is the suite itself, the repo workflow linters, the ratchets and CI's full battery. No `suite-shard-legs.tsv` / `suite-durations.tsv` row is added (default weight applies); the battery's wall time is recorded in the PR body.

## Implementation Phases (RED first - `cq-write-failing-tests-before`)

**Phase 0 - RED.** Create the fixture tree, the shim and the suite; the script does not exist yet, so every scenario fails (record the red count in the commit message). Write first: the instrument self-test (a `pass`/`fail` pair that must both record) and the vacuity row H1 (a stub SUT that exits 0 and prints nothing must RED the suite).

**Phase 1 - the script, scenario by scenario to GREEN.** Order: `--self-test` + input/fixture-dir guards -> `api_get` (retries, status classification, budget) -> runs read, paging, truncation -> trigger visibility -> candidate filter -> delivery predicate (ancestry, then apply-job leg) -> deferral -> classification -> issue reconcile + degraded path -> trace. After each step run only the pinned scenario ids. Classification gate (see above).

**Phase 2 - the workflow + wiring leg.**

**Phase 3 - the mutation battery** (default suite, F9). Hygiene: a pristine control run per pinned set must pass; only a case-runner rc of 1 (an assertion failed) counts as "caught" - rc 124/127/2 are reported as "instrument error"; each sed anchor must match exactly once and inside the target function (not just "the file changed"); mutate COPIES (the path is passed by env); each run under `timeout -k`; pins are sub-case ids so a mutant is killed for its own reason; mutants may run in parallel (`xargs -P`) from per-mutant sandboxes. Record the battery's wall time in the PR body; ceiling 90 s.

**Phase 4 - docs.** Runbook section, ADR-270 addendum, `decision-challenges.md`.

**Phase 5 - verify (all offline).** `bash plugins/soleur/test/apply-delivery-gap-follower.test.sh`; `bash scripts/apply-delivery-gap.sh --self-test`; the exact discoverability command under `env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/tmp timeout 15s bash -c 'bash scripts/apply-delivery-gap.sh --self-test'` from a read-only copy; `bash scripts/lint-workflows.sh .github/workflows/apply-delivery-gap-follower.yml`; `actionlint` and `shellcheck scripts/apply-delivery-gap.sh`; `python3 scripts/lint-workflow-issue-write-scope.py`; `python3 scripts/lint-workflow-step-env-refs.py`; `python3 scripts/lint-workflow-local-action-checkout.py`; `bash scripts/alarm-issue-filing-guard.test.sh`; `bash scripts/lint-orphan-test-suites.sh`; `bash plugins/soleur/test/c4-count-parity.test.sh`; `python3 scripts/lint-guard-contract.py <this plan>`; `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`; `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch feat-one-shot-apply-delivery-gap-follower`; `npx markdownlint-cli2 <plan> <tasks.md> <runbook>`; the secret scan over the fixture tree (SHAs and run ids are public identifiers). **Live read-only rehearsal (uncommitted):** snapshot one live runs page per workflow, the jobs of any in-window cancelled push and the relevant compares into a throwaway `/var/tmp` fixture directory and run the script with `--fixture-dir`, recording the rows it would file; state the expected first-reconcile result in the PR body. **Merge-time check:** list cancelled push runs inside the 7-day window of both workflows (none at planning time on 2026-10-22); any present will page on the first reconcile.

**Merge.** This PR touches `.github/workflows/`: no agent `--admin` fallback; merge only through the merge queue. PR body: `Ref #9454`, `Ref #10033`, `Ref #8167` - no closing keyword adjacent to any issue number (also none in commit messages).

## Test Scenarios

Harness: `run_case <scenario> [tweaks]` copies `base/`, the scenario overlay and the shim (as `bin/gh`) into a fresh sandbox under `/var/tmp` (cleaned by an EXIT/INT/TERM trap), runs the SUT with `--fixture-dir`, and captures stdout, stderr, rc, `out/reads.log`, `out/actions.log` and the shim's refusal log (asserted empty in every case). Fixtures are SYNTHESIZED reduced records (only fields the script reads; invented messages; no actors, no emails; an `example-org/example-repo` slug). The replay fixtures reuse the public incident run ids, head SHAs and timestamps from the issue record (identifiers of public Actions runs, not payload captures) - a stated departure from invented ids because the ask is to replay those ids; the p0 class fixture is purely synthetic (every live cancelled run has zero jobs). Floors are a per-case table recorded from the first green run (`-lt` minimums) plus "every case ran at least one assertion".

| # | Scenario (named fixture dir in bold) | Assert |
|---|---|---|
| S1 | **cancelled-zero-jobs** | exactly 1 row, `evicted-before-start`; `reads.log` contains exactly the modeled reads (`runs?per_page=100&page=1` per workflow, jobs `per_page=1`, the issue list) and NO `status=`, `event=`, `branch=` or `created=` parameter; a `label-create` then one `issue-create` with labels apply-delivery-gap, action-required, priority/p1-high and NOT p0; one `::notice row` line; body per row contains the 40-hex SHA, run URL, class and the printed command with the right file name and sha7; the printed commands match `^gh workflow run [a-z0-9.-]+\.yml --ref main( -f [a-z_]+=[a-z-]+)* -f reason='apply-delivery-gap [0-9a-f]{7}'$` and are cross-checked against the live workflow files (file exists, `reason` is a required dispatch input, `manual-rerun` is an `apply_target` option) |
| S2 | **cancelled-then-later-success-descendant** (+ prior open issue) | 0 rows; an unrelated EARLIER non-descendant success (compare `behind`) precedes the delivering one; `issue-close --reason completed` once; close comment lists sha7, delivering run id and minutes (clamped >= 0); no create/edit |
| S2b | (inline) non-descendant statuses | later successes with compare `behind` and `diverged` leave the row in place; `identical` and `ahead` deliver |
| S3 | **cancelled-with-jobs** | `cancelled-mid-run`; `priority/p0-critical` added; body carries "do NOT dispatch before reading the run" |
| S3c | (inline) failed later run | a later same-workflow `failure` run is shown in the row's "Later run" cell with its URL |
| S4 | **cancelled-killswitch** | deploy-fix push with `[skip-deploy-fix-apply]` on its own line (and on the middle line of a multi-line message): dropped; infra push with `[skip-web-platform-apply]`: dropped; the deploy-fix marker inside an infra push: NOT dropped; marker mid-line and marker with a CRLF terminator: NOT dropped; `head_commit: null`: not dropped, no crash; one qualifying row beside them; every WATCHED key has a marker entry; a cancelled S then a later push S2 carrying the marker -> the row for S remains |
| S5 | **success-only** | no candidates; no jobs/compare read; `workflows_read=2`; with an open issue and nothing in flight, `delivered == 0` -> NO close, exactly one marker comment, and a second reconcile adds no second comment; with no issue no write |
| S6 | **non-push-or-non-main** | cancelled `workflow_dispatch`, cancelled push on a non-main branch, cancelled `schedule`, a cancelled push 8 days old, runs concluded `failure`/`startup_failure`/`timed_out`: 0 rows; one qualifying candidate beside them: exactly 1 row; a cancelled push plus a cancelled dispatch on the same SHA (the 2026-09-14 and 2026-10-11 shapes) -> exactly 1 row |
| S7 | **inflight-descendant** | `in_progress`, `queued`, `pending` and a fresh `waiting` descendant each defer (a `deferred` notice, 0 rows, an open issue is NOT closed); `waiting` at 61 min, infra `queued` at 121 min and deploy-fix `queued` at 151 min do not defer; a deploy-fix `in_progress` run 100 min after `run_started_at` still defers; an in-flight run of the OTHER workflow does not defer the row but blocks the close; a test parses each workflow's `apply` `timeout-minutes` and asserts the cap exceeds it |
| S8 | **api-failure** (matrix over injected failures) | runs list p1, runs list p2 (second workflow), jobs (classification), jobs (apply-job leg), compare 5xx, compare 403-with-"404"-in-the-text (hostile stderr -> `compare_failed`, NOT "not a descendant"), issue list, issue edit, label create, and ONE case per malformed check (`.workflow_runs` not an array, `head_sha` not 40-hex, `created_at` not ISO, jobs `total_count` not an integer, compare without `status`) -> each: rc EXACTLY 1, its own `::error::apply_delivery_gap_<reason>` as the last output line, no `apply_delivery_gap_summary`, no `issue=closed`, an open issue present in the fixture and NO close/gap-issue write; read-class reasons record a degraded upsert (label `apply-delivery-gap-degraded` + `action-required`, body = slug + run URL only) and issue-class reasons do not; compare 404 (JSON body on stdout, `(HTTP 404)` on stderr) -> warning, row stays, rc 0; a transient 502 on the first call and success on the second -> green and acts, three failures -> the named error; the 151st compare/jobs read -> `api_budget_exceeded`; trigger run `in_progress` on attempt 1 and `completed` on attempt 2 (`runs.<key>.r2.json`) -> proceeds, invisible after 3 -> `trigger_run_not_visible`; a degraded issue is closed by the next complete reconcile; bad argv / bad `GH_REPO` -> rc 2 with `bad_input` |
| S9 | **dedup** | open bot-authored issue with the exact title, a stale 1-row body and `action-required` stripped + two candidates: exactly 1 `issue-edit` (body + `--add-label` including `action-required` and `apply-delivery-gap`, NOT p1), 0 creates, no `--remove-label` anywhere; the same input again -> again exactly 1 edit and the same row set; the label removed from the open issue -> the SAME issue is edited, no create; a human-authored issue with the same title or the label -> never edited or closed and a fresh issue is created; two matching bot issues -> lowest refreshed, extras closed `--reason "not planned"` with a pointer; only a CLOSED issue exists -> a new issue is created; open issue already carrying p0 with only p1 rows -> the edit has no remove |
| S10 | **sibling-success-does-not-count** | deploy-fix candidate with an infra apply-success at a descendant AND at the SAME sha (both workflows fire on one push) -> row remains; infra candidate with a deploy-fix success -> row remains |
| S11 | **delivery-requires-apply-job** | a later push success whose `apply` job is `skipped` does not deliver; a later dispatch success with only an `entrypoint_audit`-shaped job set (+ `notify-apply-failure` success) does not deliver; a later dispatch success with `[preflight success, apply success]` delivers |
| S12 | (inline) re-run of cancelled S in flight | S is no longer a candidate; an open issue is NOT closed while it runs; closes (reason completed only if delivered >= 1) after it completes |
| S13 | (inline) truncation boundary | page size 2 / max pages 3: 3 full pages inside the window -> `run_window_truncated`; page 3 full but entirely beyond the cutoff -> accepted; a run repeated across pages 1 and 2 and same-second ties -> one row |
| S14 | (inline) body bounds | 200 cancelled candidates -> body < 65,536 bytes, "+K more" line present, an `issue-create`, and the close arm still sees all 200 |
| S15 | (inline) poisoned fixture | message, branch and title containing `\r\n::error::x`, `@octocat`, `[a](http://evil)`, `<img src=x>` and a long string beside a candidate -> none of those substrings in stdout, stderr or the body, rc 0 |
| S16 | (inline) clock skew | `updated_at` later than `now` -> minutes 0, never negative; delivery before cancel -> 0 |
| S17 | (inline) test-only overrides are inert in live mode | `APPLY_DELIVERY_GAP_PAGE_SIZE` / `_MAX_PAGES` set without `--fixture-dir` -> constants stay 100 / 10 and `now` comes from `date`; summary `mode=live` |
| R1-R3 | **replay-37964350917**, **replay-37964762496**, **replay-38144232116** (one data-driven loop) | each: exactly 1 row, workflow deploy-fix, class `evicted-before-start`, URL contains the run id, sha as recorded |
| R4 | **replay-incident-delivered** | R1+R2 fixtures plus dispatch success `37976212395` (head `79482dab`, `apply` success, compare `ahead` for both) -> 0 rows and a close with `--reason completed` |
| H1/H3/H4/H5 | harness | (H1) a stub SUT that exits 0 with no output REDs the suite; (H3) must-PASS non-canonical inputs: 3 pages, reversed workflow order, a candidate on page 2; (H4) the shim refuses any unmodeled argv with exit 64 and the refusal log is empty in every case; (H5) `--self-test` prints `apply_delivery_gap_self_test=ok` in the Check-10 sandbox shape (`env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/tmp`, read-only repo copy, no `GH_REPO`/`GH_TOKEN`, target under 5 s, hard cap 15 s) and is three pure checks: both kill-switch regexes, the compare-status mapping (`identical\|ahead` yes; `behind\|diverged` no), the jobs-count class + `apply` job leg |
| W | workflow wiring | parsed YAML (read `doc.get('on', doc.get(True))`: PyYAML parses a bare `on:` as boolean `True`; assert the result equals `{'workflow_run'}` and is non-empty): `types: [completed]`, `branches: [main]`; `workflows:` and the script's `WATCHED` names equal the live apply files' `name:` strings (failure text names all three copies: the apply workflow, the follower's `workflows:`, the script's `WATCHED`); every watched file exists; both watched files' parsed `on` keys are a subset of `{push, workflow_dispatch}`; `permissions` exactly `{contents: read, actions: read, issues: write}` with no job-level block; concurrency group differs from the apply files' group and `cancel-in-progress: false`; the same kill-switch literals appear in the script and in each apply workflow's preflight; grep: no `secrets.`, `environment:`, `terraform`, `workflow_dispatch`, `gh workflow run`, `/dispatches` (failure text explains why and quotes "the apply group"); no `github.event.` text except the one `TRIGGER_RUN_ID` env value; every `uses:` is a 40-hex pin; checkout has no `ref:`; the `run:` line is exactly `bash scripts/apply-delivery-gap.sh`; `timeout-minutes` set; anti-vacuity floor on parsed steps; chokepoint greps on the script (no bare `gh api` / `gh issue list` outside `api_get` and the lookup spelling, no `\|\| true` or `2>&1` on a data read, no `--remove-label`, no fixture env read outside the fixture branch) |

**Mutation battery (single table - the Guard Contract entries below cite these ids; they add no further tests).** Each row is `id | edit on a sandbox COPY of the script | pinned sub-cases`:

| id | Mutation | Pinned |
|---|---|---|
| M1 | delivery accept set widened to include `behind` (direction) | S2, S2b, R4 |
| M2 | success set not scoped to the candidate's workflow (sibling counts) | S10 |
| M3 | `fail_loud` returns instead of exiting (tolerated failed read) | S8 (rc == 1, last line, no summary) |
| M4 | kill-switch candidate drop removed | S4 |
| M5 | infra row uses the deploy-fix marker | S4 |
| M6 | `apply` job-name leg dropped from the delivery predicate | S11 |
| M7 | `skipped` accepted as `success` for the `apply` job | S11 |
| M8 | close arm ignores in-flight runs (other workflow / re-run / deferred) | S7, S12 |
| M9 | truncation guard removed | S13 |
| M10 | `action-required` not re-asserted on refresh | S9 |
| M11 | compare HTTP 404 read as delivered | S8 (compare 404) |
| M12 | trigger-run visibility assertion removed | S8 (trigger) |
| M13 | only the FIRST later success is considered (first-success-wins) | S2 |
| M14 | kill-switch regex unanchored | S4 (mid-line) |
| M15 | runs URL gains `&status=cancelled` | S1 (reads.log) |
| M16 | return-code check dropped in the live branch of `api_get` | S8 |
| M17 | close when `delivered == 0` | S5 |
| M18 | close arm computed from the 40 rendered rows instead of the full set | S14 |
| M19 | degraded upsert touches the gap issue | S8 (degraded) |
| M20 | issue identity drops the exact-title check (author/label only) | S9 |
| Y1 | (workflow YAML mutant) job-level `permissions` widening to `contents: write` | W |
| Y2 | (workflow YAML mutant) concurrency group set to the apply group literal | W |

`MUTANT_FLOOR` is asserted equal to the table length (22). Documented equivalent/unreachable edits, kept honest rather than hidden: dropping `identical` from the accept set is unreachable on real data (`sha ==` short-circuits first) and is covered through the `--self-test` mapping; the `created >= S.created` leg is redundant with ancestry on real data (it prunes calls) and has no mutant. Other regressions (stale caps, classification, per-field filters, trace output, close-comment text, body contents) are killed by direct assertions in S1-S7, not by mutants.

## Guard Contract

### Guard 1 - close and "no gap" only on a complete read; a blind follower pages

**Property.** The follower closes an issue or reports "no gap" only when every API read of the reconcile returned a complete, well-formed answer and nothing relevant is in flight; a failed read never silently ends a run.

**Assembly.** The close arm is one function. Every read - runs pages for both watched workflows (incl. the truncation stop and the trigger-visibility retry), jobs per row and per delivering candidate, compare per (candidate, run) pair, the issue list - flows through the single `api_get` -> `fail_loud` -> `exit 1` chokepoint (which also owns the transient retry and the read budget); the suite greps the script for any bare `gh api` / `gh issue list` outside it, for `|| true` / `2>&1` on a read, and for `--remove-label`. Plural reads (two workflows, N pages, M compares) are quantified over every member, not the first. Writes (`issue create/edit/close/comment`, `label create`) are the only other `gh` call sites and each has its own named reason; the degraded upsert is a third family with its own lookup identity.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | M3: `fail_loud` returns instead of exiting while an open issue is present | RED (S8) |
| 2 | M16: return-code check dropped in the live branch of `api_get` | RED (S8) |
| 3 | M9: truncation guard removed | RED (S13) |
| 4 | M8: close arm ignores in-flight runs / a re-run | RED (S7, S12) |
| 5 | M12: trigger-run visibility assertion removed | RED (S8) |
| 6 | M19: degraded upsert touches the gap issue (second member after a compliant first) | RED (S8) |

**Harness rows.** H1 (a stub SUT that exits 0 with no output REDs the suite), H3 (must-PASS non-canonical worlds) and H4 (an unmodeled argv or a search parameter in a read URL fails loudly) so a guard that rejects everything, or a SUT-internal recorder, cannot pass; S5 asserts `workflows_read=2` so a loop over zero workflows cannot pass.

**Anchor.** The completeness rule is structural (the chokepoint) and the page cap and window are constants whose weakening is visible in the same diff as the S13 legs that pin them (a lowered `MAX_PAGES` reds the "accepted" leg, a raised one reds the "rejected" leg).

### Guard 2 - the delivery predicate

**Property.** A candidate push is "delivered" only when a run of the SAME workflow, created at or after it, whose head is the candidate or a git descendant, actually ran its `apply` job to success; any other run leaves it undelivered.

**Assembly.** One predicate function evaluated for every (candidate, same-workflow run) pair over the single per-workflow normalised run list (the sibling's list is a different variable the predicate never receives). Legs, in order: same workflow key; `conclusion == success`; `created >= S.created`; ancestry (`sha` equality or `compare` status in `identical|ahead`; 404 = not a descendant); the `apply` job leg (name `apply`, `conclusion == success`). Deferral reuses the status/ancestry legs with the in-flight status set and the per-workflow stale caps.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | M1: accept set widened to include `behind` | RED (S2, S2b, R4) |
| 2 | M2: success set not scoped to W | RED (S10) |
| 3 | M6: `apply` job leg dropped | RED (S11) |
| 4 | M7: `skipped` accepted as success | RED (S11) |
| 5 | M11: compare 404 read as delivered | RED (S8) |
| 6 | M13: only the first later success considered | RED (S2) |

**Harness rows.** S2's earlier non-descendant success defeats first-success-wins; S2b fixtures carry all four compare statuses; must-PASS inputs differ from the canonical: a dispatch success with a different commit message, a success whose head equals S, the R4 real shape; S11 includes a `notify-apply-failure` success beside a skipped `apply` so a substring match on "apply" fails.

**Anchor.** The compared values are live git ancestry (`compare`) and the live job list from the API; nothing in this change can edit either.

### Guard 3 - candidate filter and kill-switch drop

**Property.** Only cancelled `push` runs on `main` inside the 7-day window are candidates, and a push carrying its own workflow's skip marker is never reported.

**Assembly.** One candidate-selection function over each workflow's normalised list; filters: event, branch, status/conclusion, window, and the per-workflow marker table (`=~` copied verbatim from each workflow's preflight; the message is read into a bash variable per candidate, never through `@tsv`).

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | M4: kill-switch drop removed | RED (S4) |
| 2 | M5: infra row uses the deploy-fix marker | RED (S4) |
| 3 | a watched key with no marker entry (a third WATCHED row in the sandbox copy) | RED (S4 table-completeness check) |
| 4 | M14: marker regex unanchored (mid-line accepted) | RED (S4) |
| 5 | event / branch / window filters each dropped (direct S6 assertions: four non-candidates beside one qualifying) | RED (S6) |
| 6 | classification inverted (jobs 0 <-> >= 1) | RED (S1, S3 direct assertions) |

**Harness rows.** S6 and S4 each include one qualifying candidate beside the non-candidates so "ignore everything" fails; message fixtures include a marker on a middle line (must drop), mid-line and CRLF-terminated (must not).

**Anchor.** Each marker regex is compared against the live apply workflow's preflight by the wiring leg (the same literal must appear in both files), so editing only one side reds the suite.

### Guard 4 - workflow shape (no write path to production)

**Property.** The follower workflow cannot hold secrets, enter an environment, run `terraform`, dispatch anything, or share the apply concurrency group, and its permission set is exactly three scopes.

**Assembly.** The single workflow file, checked on its parsed form AND by raw-text grep (a comment can hide a grep hit and a parser can miss a string); every `uses:`, every `permissions` block (workflow and job level), every `env:` mapping, every `run:` body; plus the watched files' `on` keys (the premise that no fork-controlled run can fire the follower).

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Y1: job-level `permissions` widening (a second permissions site after a compliant workflow-level one) | RED |
| 2 | Y2: concurrency group set to the apply group literal | RED |
| 3 | add `secrets.X` / `environment:` / `workflow_dispatch:` / an unpinned `uses:` / a `pull_request` trigger on a watched file | RED (raw-text grep and parsed checks assert directly; not separate mutants) |

**Harness rows.** The wiring leg reads the real file and has an anti-vacuity floor (parsed steps >= 2, parsed `on` non-empty). Must-PASS: the real file.

**Anchor.** The apply workflows' `name:` strings, kill-switch literals, `on` keys, `apply` timeouts and concurrency literal are read live from their files (outside this change's diff).

## Architecture Decision (ADR/C4)

### ADR

<!-- lint-infra-ignore start: describes the content of an ADR addendum; prescribes no operator step -->

Amend ADR-270 (not a new ADR): it extends the existing merge-queue / post-merge-gate family with a detection-only apply-delivery follower. Task: add the `### Addendum 2026-10-23` section via the `architecture` skill conventions. Open with three sentences of context (the queue raises the push rate and a concurrency group keeps one pending run so the older one is evicted; the R2 backend has no lock - ADR-006 - so that group is the sole serializer; the sibling workflow's `-target` set excludes the deploy-fix resources so a sibling success is not delivery). Then: the decision (detect and file, no fix); why the two fixes stay deferred (the single-workflow merge changes the sole serializer of lock-less R2 state; a re-dispatch follower writes production and must honour two kill switches; option 2 "poll for the sibling" is rejected because evicted runs have zero jobs; a `schedule:` backstop is rejected because it would duplicate the 12 h drift cron); the flip evidence bar (3 or more distinct SHAs in 30 days, or a row aged past 1 h with real deploy impact, plus a green operator-reviewed rehearsal on a disposable group and state key), the evidence unit (the SHA) and how it is counted; the refinements to the ruling (the `last ~50` became an unfiltered read to a 7-day cutoff with a 10-page ceiling; delivery needs the `apply` job to succeed; the infra workflow's own skip marker; per-workflow stale caps; a degraded issue for a blind follower); and the residuals that change an operator's behaviour: an untouched gap older than 7 days ages out and the issue is left open with a comment; `failure`/`timed_out` runs are owned by `notify-apply-failure` and the drift cron; a preflight-only cancelled run is classed p0 (conservative); a disabled follower workflow is silent; detection can be delayed to the evictor's completion; CODEOWNERS rows for the script, test and fixtures and the test-affected-paths declaration (if needed) follow after #8626 / #10744 / #7390 merge. ADR status unchanged. Not deferred to a follow-up.

<!-- lint-infra-ignore end -->

### C4 views

No C4 change. Read in full: `model.c4` (996 lines), `views.c4` (131), `spec.c4` (54). External human actors: none new (the founder already reads GitHub issues through `founder -> github`). External systems: GitHub is modelled (`github = system "GitHub"`) and the follower is GitHub-internal (a GitHub-to-GitHub relationship cannot be drawn: LikeC4 rejects self-relations, same note as `views.c4` line ~12). Data stores: none (stateless; the issue is the page). Actor-to-surface access relationships: unchanged. Derived cardinalities: no `actions/sentry-heartbeat` use and no monitor slug, so the `github -> sentry` counts do not move; `bash plugins/soleur/test/c4-count-parity.test.sh` is green on the base commit and is re-run in Phase 5.

### Sequencing

The ADR addendum describes the shipped (detection) state; no soak-gated activation.

## User-Brand Impact

- **If this lands broken, the user experiences:** either nothing changes from today (a cancelled `ci-deploy.sh` apply stays silent and production deploys keep rolling back until someone notices - the ~4 h blocked-deploy incident of 2026-10-09, #9871) or one spurious `action-required` issue naming a push that was in fact applied.
- **If this leaks, the user's workflow is exposed via:** nothing beyond what the public Actions UI already shows - workflow names, 40-hex SHAs, run URLs and minute counts reach a public issue body; the follower holds no secret and prints no commit message, branch name or actor into any output.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** a missed apply degrades deploy reliability for all users until noticed but is recoverable by a dispatch and bounded by the 12 h drift backstop; it is not a single-user irreversible incident, so no per-PR CPO sign-off is added.

## Observability

```yaml
liveness_signal:
  what: "workflow_run of apply-delivery-gap-follower.yml on every completed run of the two apply workflows, ending in a ::notice apply_delivery_gap_summary line with workflows_read=2"
  cadence: "per completed apply run (event-driven); the 12 h scheduled-terraform-drift cron is the independent backstop"
  alert_target: "an open action-required gap issue for a gap, and an open action-required apply-delivery-gap-degraded issue for a failed read (both harvested by the operator digest); the red Actions run is the trace, not the page"
  configured_in: ".github/workflows/apply-delivery-gap-follower.yml and scripts/apply-delivery-gap.sh"
error_reporting:
  destination: "GitHub Actions annotations on the follower run (workflow run log) plus the degraded issue; no Sentry (no application runtime, no new vendor edge)"
  fail_loud: "exit 1 plus ::error::apply_delivery_gap_<reason> with a distinct reason per failure class, as the last line of the run log"
failure_modes:
  - mode: "an API read fails, a runs page is truncated, the read budget is exceeded, or the triggering run is not visible"
    detection: "::error::apply_delivery_gap_runs_list_failed | jobs_read_failed | compare_failed | malformed_response | run_window_truncated | trigger_run_not_visible | api_budget_exceeded in the workflow run log (transient 5xx/429 are retried first); issue never closed"
    alert_route: "apply-delivery-gap-degraded issue (action-required, harvested by the operator digest) plus the red follower run; the runbook maps each reason to a next step; the drift cron backstops within 12 h"
  - mode: "the issue API itself fails"
    detection: "::error::apply_delivery_gap_issue_list_failed | issue_write_failed | label_failed | degraded_upsert_failed in the workflow run log (writes retried once)"
    alert_route: "red follower run (workflow run log); no issue can be written by construction, so the drift cron is the backstop and the next apply completion retries the full reconcile"
  - mode: "the follower never fires (a watched workflow is renamed, the platform skips workflow_run for a pending-cancelled run, or the workflow is disabled in the UI)"
    detection: "the suite's wiring leg REDs in CI (workflow run log, ::error:: from the suite) when a watched workflow is renamed; the evictor's own completion still triggers the reconcile for the platform case; a disabled workflow is a documented residual (ADR addendum) - the cadence is per apply run so absence is undetectable"
    alert_route: "CI red on the PR that renames; otherwise the drift cron (12 h)"
  - mode: "a gap exists but is older than 7 days"
    detection: "ages out of the candidate set; the follower leaves the open issue in place with one marker comment (the ::notice summary line in the workflow run log shows issue=aged-out-comment)"
    alert_route: "the open action-required issue stays in the operator digest until closed by hand; scheduled-terraform-drift (12 h) reports the resulting drift"
logs:
  where: "Actions run logs of apply-delivery-gap-follower.yml (::notice row lines, deferred notices, summary line)"
  retention: "GitHub default Actions log retention (90 days); close comments on the issue are permanent"
discoverability_test:
  command: bash scripts/apply-delivery-gap.sh --self-test
  expected_output: "apply_delivery_gap_self_test=ok"
```

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The binding design is the CTO ruling of 2026-10-22. This planning run additionally obtained CTO rulings on the implementation forks F1-F20 (recorded in `decision-challenges.md`) via the `soleur:engineering:cto` agent, a plan-review panel (DHH, Kieran, code-simplicity, CTO devex lens) and a deepen panel (architecture, security, spec-flow, observability, test-design, docs research) whose mechanical findings were applied; no operator question was asked. No other domain (legal, finance, marketing, sales, support, operations, product) has an implication: no UI surface, no personal data, no new vendor, no pricing or brand content. Product/UX gate: NONE (no UI-surface file in the Files lists). GDPR gate: not triggered (no schema, auth, API route or `.sql` file; the public issue body carries only SHAs, run URLs and workflow names; no learnings or specs are read).

**Brainstorm-recommended specialists:** none (no brainstorm; one-shot path).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "ONE small PR that ships ONLY the detect-and-file apply-delivery-gap follower" | Overview deliverables 1-5; Cut List | mapped |
| 2 | "new workflow `.github/workflows/apply-delivery-gap-follower.yml` on `workflow_run` types [completed] for the two workflows" | Trigger and wiring; W | mapped |
| 3 | "Permissions exactly `contents: read`, `actions: read`, `issues: write`. No `secrets.*`, no `environment:`, no Doppler, no `terraform`, no workflow dispatch." | Trigger and wiring; Guard 4; W | mapped |
| 4 | "Its own concurrency group (NOT `terraform-apply-web-platform-host`), `cancel-in-progress: false`." | Trigger and wiring; W | mapped |
| 5 | "All actions SHA-pinned; every `github.event.*` value routed through `env:`; SHAs validated `^[0-9a-f]{40}$`; checkout of main only." | Trigger and wiring (one event value, via env); Script output-hygiene rule; W | mapped |
| 6 | "Logic lives in `scripts/apply-delivery-gap.sh` (with `--self-test` and `--fixture-dir <d>` to read JSON instead of calling gh)" | Script algorithm (fixture dir supplies a `gh` shim and JSON); H5 | mapped |
| 7 | "Stateless reconcile per run: candidates = last ~50 runs of each watched workflow on main with event push and conclusion cancelled, within 7 days" | Script steps 1 and 3 (F1 refinement) | mapped |
| 8 | "Classify via the jobs API: zero jobs = `evicted-before-start` (p1), one or more jobs = `cancelled-mid-run` (p0, state possibly partial)." | Script step 5; S1, S3 | mapped |
| 9 | "Drop pushes whose head commit message matches the deploy-fix kill switch `[skip-deploy-fix-apply]` (deploy-fix watcher only; copy the workflow's own regex)." | Script step 3; Guard 3; S4 (extended to the infra workflow's own marker, F12) | mapped |
| 10 | "A candidate S on workflow W is delivered iff a run of W exists with conclusion success, created at or after S, and head_sha equal to or descended from S (use the compare API: identical or ahead); a workflow_dispatch success counts; a success of the OTHER workflow does not." | Script step 4a; Guard 2; S2, S2b, S10, S11, R4 | mapped |
| 11 | "Defer if a descendant run of W is queued/pending/waiting/in_progress (a `waiting` run older than 60 min does not defer)." | Script step 4b; S7 | mapped |
| 12 | "Close arm only when the undelivered set is empty AND every API call succeeded." | Script step 6; Guard 1; S5, S8, S12 | mapped |
| 13 | "One issue found by LABEL `apply-delivery-gap` (create idempotently), title ..., labels ..., re-assert action-required on every refresh, body = a table of rows keyed (workflow, SHA)" | Script step 6 + body; S1, S9 (identity is bot author + exact title, label re-asserted: F20) | mapped |
| 14 | "Fail loud on any API/list failure with a distinct `::error::apply_delivery_gap_<reason>` and never close or report \"no gap\" on a partial read." | Failure reasons list; Script step 7; S8 | mapped |
| 15 | "The existing 12 h drift cron (`scheduled-terraform-drift.yml`) stays the backstop; do not duplicate it" | Cut List; Observability | mapped |
| 16 | "add a short section to `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-red-run.md` mapping gap issue to dispatch command to verification" | Files to Edit | mapped |
| 17 | "a one-paragraph ADR-270 addendum recording the detection-only decision and the flip evidence bar" | ADR section | mapped |
| 18 | "Single-workflow merge and re-dispatch follower stay DEFERRED; do not implement them." | Cut List; ADR section (tracked by open #10033 and #8167, which do not close) | mapped |
| 19 | "`plugins/soleur/test/apply-delivery-gap-follower.test.sh` plus fixtures under `plugins/soleur/test/fixtures/apply-delivery-gap/`: cancelled-zero-jobs; cancelled-then-later-success-descendant ..." | Files to Create (every named fixture dir is committed); Test Scenarios | mapped |
| 20 | "Replay offline the three recorded incident run ids ... each yields exactly one row with the right class." | R1-R3 | mapped |
| 21 | "Mutation-verify the guards you add (delivery predicate direction, sibling-does-not-count, close-only-on-complete-read, kill-switch drop) on a sandbox copy." | Mutation battery M1-M20, Y1-Y2; Guard Contract | mapped |
| 22 | "this PR touches `.github/workflows/`, so it has no agent `--admin` fallback; merge only via the queue" | Phase 5 Merge | mapped |
| 23 | "Do not touch #9482, #10245, #5840, any AGENTS rule line, `.claude/rule-weakening-acks.txt`, or files under another open PR." | Files to Edit (not-edited list); Suite classification | mapped |
| 24 | "use `Ref #10033` and `Ref #8167` only, never a closing keyword adjacent to either" | Overview; Phase 5 Merge; body avoids issue numbers | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Workflow YAML, script, test, fixtures, runbook section, ADR addendum | asks 1-6, 16, 17, 19 | asked |
| Unfiltered paginated read instead of a status-filtered "last ~50" (F1) | "candidates = last ~50 runs of each watched workflow on main with event push and conclusion cancelled, within 7 days" | inferred - justification: search params are measured stale (learning 2026-09-24) and a stale read hides the candidate; CTO F1 |
| `apply` job leg in the delivery predicate (F11) | "delivered iff a run of W exists with conclusion success" | inferred - justification: a green non-apply dispatch or kill-switched push at a descendant would falsely deliver (infra `apply` runs only on push/`manual-rerun`; verified in the live file); CTO F11 |
| Infra workflow's own kill-switch marker (F12) | "deploy-fix watcher only; copy the workflow's own regex" | inferred - justification: a deliberately skipped infra push is otherwise a false page; CTO F12 |
| Close only with nothing in flight; no close when delivered == 0 (F3, F13', F14) | "Close arm only when the undelivered set is empty AND every API call succeeded." | inferred - justification: closing under an in-flight or re-running descendant, or after a silent age-out, claims "no gap" early; CTO F3/F13'/F14 |
| Deferral stale caps per workflow (F15') and unconditional deferral (F8') | "Defer if a descendant run of W is queued/pending/waiting/in_progress" | inferred - justification: an uncapped defer hides a gap forever and a uniform cap misjudges a 90-minute deploy-fix apply; CTO F15'/F8' |
| Labels: p1 at create only, p0 add-only (F4') | "(+ priority/p0-critical for any mid-run row)" | inferred - justification: protects a human downgrade/escalation; CTO F4' |
| Issue identity = bot author + exact title; extras closed (F18, F20) | "One issue found by LABEL `apply-delivery-gap`" | inferred - justification: label-only lookup lets a mislabelled human issue be overwritten and a deleted label orphan the issue; CTO F18/F20 |
| Body cap 40 rows, 150-read budget (F19) | "body = a table of rows keyed (workflow, SHA)" | inferred - justification: GitHub caps a body at 65,536 characters and the token at 1,000 requests/hour; CTO F19 |
| Degraded issue for read-class failures (F5') | "Fail loud on any API/list failure with a distinct `::error::apply_delivery_gap_<reason>`" | inferred - justification: a red run has no actor and the digest reads only issues; CTO F5' (the brief's fail-loud intent) |
| `TRIGGER_RUN_ID` visibility check (F16) | "every `github.event.*` value routed through `env:`" | inferred - justification: a lagging read would miss the very first detection; CTO F16 |
| compare 404 = not a descendant (F17) | "use the compare API: identical or ahead" | inferred - justification: one unresolvable SHA must not wedge refresh/close for 7 days; CTO F17 |
| Transient-failure retries, write retry | "Fail loud on any API/list failure" | inferred - justification: a single 502 must not become a missed detection that persists until the next apply event |
| Run-log notices (F7) | "the flip evidence bar (3 or more distinct SHAs in 30 days ...)" | inferred - justification: the stateless body leaves no countable trail otherwise; CTO F7 |
| Always-on mutation battery (F9) and mutants M5-M20 | "Mutation-verify the guards you add ... on a sandbox copy." | asked (default-suite placement inferred - justification: an opt-in battery rots; CTO F9; the extra mutants cover guards the review findings created) |
| `gh` shim on PATH for fixture mode | "`--fixture-dir <d>` to read JSON instead of calling gh" | asked (mechanism inferred - justification: a SUT-internal fixture reader makes the recorded writes self-fulfilling and hides the real `api_get` path; test-design review) |
| Wiring parse + two YAML mutants | "Assert by grep of the YAML that the workflow has no secrets/environment/terraform/dispatch" | asked (the parse and two mutants inferred - justification: a grep alone is satisfied by a stub; Guard 4) |
| Omit CODEOWNERS / `test-affected-paths.sh` / `suite-shard-legs.tsv` / `suite-durations.tsv` | "or files under another open PR" | asked |

### Split Assessment

- Subsystems touched: 4 - `.github`, `scripts`, `plugins`, `knowledge-base`
- Planned files: ~48 (about 33 are small committed fixture JSON files plus the shim in the named + replay directories) | Estimated changed lines: ~1,900 (script ~550, suite ~650, shim ~120, fixtures ~350, YAML ~70, docs ~160; plan/spec artefacts excluded)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - over threshold, but ask 1 mandates ONE PR and no seam yields independently shippable halves (the workflow without the script is inert, the script without the workflow detects nothing, the runbook and ADR describe both); the fixture directories are the brief's own explicit request (ask 19), and the review-driven hardening (degraded path, identity, bounds) sits inside the same script.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `bash plugins/soleur/test/apply-delivery-gap-follower.test.sh` exits 0 (per-case assertion floors met, every case ran at least one assertion) with every mutant landed, controlled and red (0 survivors, `MUTANT_FLOOR` equal to the table length). RED was observed first (Phase 0).
- [x] `bash scripts/apply-delivery-gap.sh --self-test` prints `apply_delivery_gap_self_test=ok` offline with `PATH=/usr/local/bin:/usr/bin:/bin`, no `GH_REPO`/`GH_TOKEN`, under the 15 s Check-10 cap (target 5 s).
- [x] R1, R2, R3 each yield exactly one row with class `evicted-before-start`; R4 yields zero rows and a close with `--reason completed`.
- [x] The workflow file: triggers only `workflow_run` on the two exact `name:` strings, `types: [completed]`, `branches: [main]`; permissions exactly `contents: read`, `actions: read`, `issues: write`; concurrency group `apply-delivery-gap-follower`, `cancel-in-progress: false`; no `secrets.`, `environment:`, `terraform`, dispatch spelling; every action SHA-pinned; passes the linters listed in Phase 5.
- [x] No `::error::` text echoes API stderr; every failure class has a distinct `apply_delivery_gap_<reason>` and a pinned scenario; read-class failures record a degraded upsert and never touch the gap issue.
- [x] The suite is registered and classified: `bash scripts/lint-orphan-test-suites.sh` is green, or the blocker is reported in the PR body per "Suite classification".
- [x] The runbook section and the ADR-270 addendum exist; the addendum records the flip bar, the evidence unit and the residuals; no remote-shell instruction anywhere.
- [x] `lint-guard-contract.py` passes on this plan; `lint-infra-no-human-steps.py --changed --base origin/main` passes; `technical-ruling-gate.sh --branch ...` passes; markdownlint is clean on the plan, `tasks.md` and the runbook.
- [x] No closing keyword adjacent to #10033 / #8167 / #9454 in the PR body or any commit; the body lists `Ref #9454`, `Ref #10033`, `Ref #8167`.
- [x] `git diff --name-only origin/main...HEAD` contains none of: `.github/CODEOWNERS`, `scripts/lib/test-affected-paths.sh`, `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv`, either apply workflow, any AGENTS file, `.claude/rule-weakening-acks.txt`.

### Post-merge (observation, not a merge or ship gate)

- After the next natural completion of either apply workflow on main, `gh run list --workflow apply-delivery-gap-follower.yml --limit 3 --json conclusion,headSha,event` shows the follower ran (event `workflow_run`) and its log carries `apply_delivery_gap_summary mode=live workflows_read=2` with no `::error::apply_delivery_gap_`. No apply is dispatched to force this; the deterministic proof is the suite.

## Dependencies & Risks

- **Event delivery for pending-cancelled runs** is unverified (see Research Insights); mitigated by design and by the drift cron.
- **Write arms are first exercised by a real gap** (no pre-merge live run exists by design; the token's `issues: write` sufficiency is documented only indirectly); a failure is loud (`issue_write_failed`, red run, drift cron) and the Phase 5 rehearsal covers the read side with live JSON.
- **Suite classification** may need a declaration in a file under open PRs (#10744, #7390); ordered fallbacks are in "Suite classification".
- **GitHub API cost**: bounded by `READ_BUDGET=150` compare+jobs reads, the 10-page ceiling (20 list calls) and a handful of issue calls.
- **Self-eviction**: a third pending follower run cancels the older pending one; harmless (every run is a full stateless read).
- **First-run caveat**: `workflow_run` workflows run only from the default branch's copy of the file, so the follower is inert until the PR merges; fixture mode is the test seam.
- **Run records' lifetime**: a deleted or re-run cancelled run leaves no candidate; the aged-out comment words this honestly.
- **Public issue content**: SHAs, run URLs, workflow names, integer minutes and a UTC time only; an undelivered firewall/infra change SHA in a public issue is the same information the public Actions UI shows.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty fails `deepen-plan` Phase 4.6; it is filled here (`aggregate pattern`).
- Do not give the follower a `workflow_dispatch` trigger "for testing": the ruling and the structural suite forbid it; fixture mode is the test seam.
- The YAML must not contain the words `terraform`, `secrets.`, `environment:` or the dispatch spellings even in comments - the suite greps the raw text.
- Avoid `closes|fixes|resolves` near any issue number in the PR body, commits, runbook and ADR text for this change.
- `gh api` GET parameters go in the literal query string, never `-f/-F` (learning 2026-10-05), and never include a search parameter (`status=`, `event=`, `branch=`, `created=`).
- PyYAML reads a bare `on:` key as boolean `True`; the wiring leg must read `doc.get('on', doc.get(True))`.
- A diff-scope AC uses `origin/main...HEAD` (three dots), never the moving tip.
- An equivalent mutant (an edit no scenario can observe) fails the "0 survivors" bar by construction: label it (above) instead of pinning it.
