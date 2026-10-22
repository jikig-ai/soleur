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

## Overview

Ship one small PR that makes a silently cancelled, path-filtered production apply run loud: a secret-free
`workflow_run` follower that reconciles the two apply workflows ("Apply deploy-pipeline-fix" and
"Apply web-platform infra (Doppler/Cloudflare/BetterStack/GitHub-App/Inngest/firewall)") and files one
deduplicated `apply-delivery-gap` issue naming each undelivered push SHA and run URL. It is detection only:
no apply, no dispatch, no `terraform`, no state read, no host read, no secrets. The binding design is the
CTO ruling of 2026-10-22 recorded on issues #10033 and #8167 (read in full in this session); it is not
re-litigated here. Neither issue closes when this ships: every reference is `Ref`, never a closing keyword.

Deliverables (one PR, tracker #9454):

1. `.github/workflows/apply-delivery-gap-follower.yml` - thin wrapper: trigger, permissions, concurrency,
   sparse checkout of the script, one `run:` line.
2. `scripts/apply-delivery-gap.sh` - all logic, with `--self-test` and `--fixture-dir <abs dir>` (read JSON
   from a directory instead of calling `gh`, record writes instead of making them).
3. `plugins/soleur/test/apply-delivery-gap-follower.test.sh` + `plugins/soleur/test/fixtures/apply-delivery-gap/`
   - RED-first suite: the ten named scenarios, the recorded-incident replays, a workflow-wiring leg, and an
   always-on mutation battery over a sandbox copy of the script.
4. A section in `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-red-run.md`
   (gap issue -> decision table -> dispatch command -> verification -> flip-evidence count recipe).
5. An ADR-270 addendum recording the detection-only decision, the flip evidence bar and the residuals.

## Research Reconciliation - Spec vs. Codebase

| Spec / ruling claim | Reality (verified in this session) | Plan response |
|---|---|---|
| Candidates = "last ~50 runs ... conclusion cancelled" | `GET .../runs?status=&event=&branch=` are SEARCH params; learning 2026-09-24 measured them stale while the UNFILTERED list was current. | CTO F1: read the unfiltered list (`per_page=100`, manual `page=N` loop to the 7-day cutoff, 10-page hard stop = `run_window_truncated`), filter client-side. Live volume: infra ~10 runs/day (100 runs span ~10.5 days), so a 7-day window can approach one page. |
| Evicted runs are "cancelled 1-3 s after creation with zero jobs" | Run `37964350917` was created 17:10:14Z, cancelled 17:13:44Z (3.5 min), yet has `total_count: 0` jobs; `38144232116` was cancelled 1 s after creation. | Class comes from the jobs count, never from timing. |
| Kill switch is "the deploy-fix kill switch ... copy the workflow's own regex" | `apply-deploy-pipeline-fix.yml:235` uses `[skip-deploy-fix-apply]`; **`apply-web-platform-infra.yml:280-295` has its own `[skip-web-platform-apply]`** (same bash `=~` form, preflight job). A kill-switched push concludes `success` with its `apply` job skipped. | CTO F12: per-workflow marker table, each regex copied verbatim from its own workflow, used ONLY to drop CANDIDATES. A watched workflow with no table entry fails the suite. The brief's "deploy-fix only" is extended to the infra marker because a deliberately skipped infra push is otherwise a false page. |
| Delivered iff "a run of W exists with conclusion success ... a workflow_dispatch success counts" | `apply-web-platform-infra.yml` has ~17 dispatch `apply_target` values; its `apply` job runs only on `push` or `manual-rerun`. A green `entrypoint_audit` / `vector_redeliver` / `plan_only` dispatch is `success` at main HEAD without any apply. Real delivering dispatch `37976212395` has jobs `[preflight success, apply success]`. | CTO F11: the delivering run must also have its job named `apply` with `conclusion == success` (jobs read, memoised per run id, through the fail-loud chokepoint). This replaces the earlier success-side kill-switch regex (F2) with one rule that also covers kill switches, other dispatch targets, `plan_only` and a skipped preflight. |
| "A success of the OTHER workflow does not count" | Both workflows share `concurrency.group: terraform-apply-web-platform-host`, `cancel-in-progress: false` (verified). One pending slot per group is what evicts. | Success set is built per workflow key. The follower's group is its own literal. |
| Exact trigger names | `name: Apply deploy-pipeline-fix` (:68) and `name: Apply web-platform infra (Doppler/Cloudflare/BetterStack/GitHub-App/Inngest/firewall)` (:14). `workflow_run.workflows` matches `name:`, not the filename. | Wiring leg parses the live apply files and asserts the follower's `workflows:` list AND the script's `WATCHED` table equal their `name:` strings; failure text names all copies. |
| Draft PR #10879 | Open, draft, empty. | Work lands on this branch; PR body uses `Ref` only. |
| Open PRs on touched files | Only draft #8626 touches `.github/CODEOWNERS`. #10744 and #7390 touch `scripts/lib/test-affected-paths.sh` and `scripts/suite-shard-legs.tsv`. None touches ADR-270, the runbook or any new path. | None of those four files is edited (constraint; CTO F10). See "Suite classification" below for the consequence. |

## Research Insights

**Premise Validation (Phase 0.6).** Checked: #10033 and #8167 OPEN (the CTO ruling comments exist verbatim); #9454 OPEN;
PR #10879 draft and empty; both workflow `name:` strings and the shared concurrency literal; the kill-switch regexes in
BOTH workflows; ADR-270 exists (861 lines, latest addendum 2026-10-22); the runbook exists (102 lines) with no
`apply-delivery-gap` text; `gh label list` has `action-required`, `priority/p0-critical`, `priority/p1-high` and NOT
`apply-delivery-gap` (the script creates it with `gh label create --force` plus explicit `--color` and `--description`,
for that one label only). ADR corpus grep for the mechanism: ADR-270 owns the merge-queue/post-merge-gate family; no
ADR rejects a detection-only follower. Run `37964350917` (deploy-fix, push, main, cancelled, 0 jobs, head `48d5144c`),
`37964762496` (head `d7dfd05a`), `38144232116` (head `568dfade`, cancelled 1 s after creation) and the delivering dispatch
`37976212395` (head `79482dab`, 2026-10-09T18:51:43Z) were fetched read-only; `compare 48d5144c...d7dfd05a` = `ahead`,
`compare X...X` = `identical`, `compare <unknown>...X` = HTTP 404. Run-list items carry `head_commit.message`,
`run_attempt`, `run_started_at`, `created_at`. All `gh api` forms prescribed below were run live (query strings in the URL,
never `-f`).

**Property List (Phase 0.6b).**
P1. A push to `main` that matched an apply workflow's path filter and was cancelled becomes visible as a labelled, action-required issue within one completed apply run.
P2. A candidate stops being reported only when a later run of the same workflow actually applied (its `apply` job succeeded) at the candidate or a descendant.
P3. The follower never closes the issue or reports "no gap" on a partial or failed read.
P4. One open issue exists at a time; rows are keyed (workflow, SHA); refreshing it is idempotent and re-asserts `action-required`.
P5. The follower cannot mutate production: no secrets, no environment, no state/host read, no dispatch.
P6. The flip decision has a countable evidence trail (SHAs and row ages).

**Cut List (Phase 0.6b).**

- Re-dispatch / auto-retry of the cancelled apply; single-workflow merge; #8167 option 2 (poll for the sibling) -> ruling: DEFERRED / rejected.
- Third copy of the trigger-file list -> covered by "a push run exists only because the path filter matched".
- A second `degraded` issue (codeql-gate style) -> CTO F5; the 12 h `scheduled-terraform-drift` cron is the backstop.
- Stateful history (reading the previous body back) -> CTO F7.
- `DRY_RUN`, an `APPLY_DELIVERY_GAP_NOW` env override, a `$GITHUB_STEP_SUMMARY` duplicate, a compare-result memo, a `shim/gh` directory, the H2 harness row, `TRIGGER_HEAD_SHA` / `TRIGGER_CONCLUSION` -> plan-review (DHH, code-simplicity, CTO devex): each maps to no property. Fixtures carry a `now` file; fixture mode runs under a `PATH` with no `gh`.
- A Sentry cron monitor -> would move the C4-parity counts and adds a vendor edge to a detector whose liveness is its own workflow run.
- CODEOWNERS rows for the script/test/fixtures -> draft #8626 edits the file; CTO F10.
- A mutant per constant and per log line (stale caps, notice emit, classification, filter-per-field) -> plain assertions in the scenarios kill the same regressions; the battery keeps the guards the brief named plus the ones the P0 findings created.

**Institutional learnings applied** (under `knowledge-base/project/learnings/`):

- `2026-09-24-an-empty-api-search-is-not-evidence-of-absence-...md` - unfiltered list as the source (F1); keep early-exit pipelines out of assignments under `pipefail`.
- `2026-10-05-gh-api-f-flag-404s-on-get-query-params.md` - GET params live in the URL.
- `2026-03-24-gh-api-paginate-concatenated-arrays.md`, `2026-07-19-a-mutation-battery-that-passes-can-still-leave-the-central-mechanism-untestable.md`, `2026-07-23-gh-run-list-truncation-reports-false-all-settled.md` - multi-page fixture shape; a read ending exactly on a page boundary is the truncation signature.
- `2026-09-25-gh-stub-must-mirror-real-cli-flags.md` - fixture mode is argv-free; the "no gh was called" row runs with a `PATH` that has no `gh`.
- `2026-09-24-the-reaper-assumed-every-run-it-cancelled-would-be-replaced.md` - re-read state immediately before acting; assertion floors from the first green run.
- `2026-10-06-a-line-anchored-extractor-cannot-see-a-prefixed-assignment.md` - spell lookups `X=$(gh ...) || { fail_loud ...; }`.
- `2026-07-02-gha-run-default-shell-has-pipefail-guard-grep-substitutions.md` - the `run:` block only calls the script; the script guards its own `grep` substitutions.
- `2026-09-20-the-gate-i-built-to-resolve-a-run-could-be-redirected-by-one-env-var.md` - no env var may override the API base or repo slug beyond validated `GH_REPO`; `--fixture-dir` is argv-only and the workflow `run:` passes no arguments (wiring-asserted); the page-size/max-page test overrides are honoured only in fixture mode.
- `security-issues/2026-07-01-two-stage-privileged-workflow-split-and-its-review-traps.md` - `workflow_run.workflows` matches `name:`; decisions read ONLY API data scoped to `main`; the single event value (`TRIGGER_RUN_ID`) is used for a membership check, never for a decision about content.
- `best-practices/2026-07-05-cross-pipeline-serialization-via-shared-job-level-concurrency-group.md` - one pending slot per group, newest evicts: the follower's own group may evict an older pending reconcile harmlessly (every reconcile is a full stateless read).
- Sharp-edges catalogue (Phase 6.5 pass): run records are the guard's input, so their lifetime was measured (deploy-fix list: 100 runs back to July; infra: 100 runs ~10.5 days; step lists strip at ~170 days, far beyond the 7-day window; a re-run keeps `created_at` and flips status, which F14 handles); a `str`-keyed heading edit hazard does not apply (file rewritten whole); every prescribed command below was executed once read-only (list-runs page, jobs count/names, compare identical/ahead/404, `gh issue list --label`, the repo lints).

**Platform behaviour this design does not depend on (stated risk).** Whether GitHub emits `workflow_run: completed` for a
run cancelled while still pending in a concurrency group is not evidenced in the repo (a probe against the CI workflow's
cancelled runs was inconclusive). The design does not need it: every completed run of either watched workflow (including the
evictor's own completion) triggers a full reconcile that re-reads the cancelled run, so detection is at worst delayed to the
evictor's completion (up to the 59 min apply ceiling), and the 12 h drift cron remains the backstop. The first natural
occurrence is observed in the post-merge observation; nothing is forced (no apply dispatch).

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
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1   (same pin as codeql-main-alert-gate.yml)
        with: { persist-credentials: false, sparse-checkout: scripts/apply-delivery-gap.sh, sparse-checkout-cone-mode: false }
      - env:
          GH_TOKEN: ${{ github.token }}
          GH_REPO: ${{ github.repository }}
          TRIGGER_RUN_ID: ${{ github.event.workflow_run.id }}
        run: bash scripts/apply-delivery-gap.sh
```

- No `ref:` on checkout: a `workflow_run` run defaults to the default branch's latest commit ("checkout of main only"). No `workflow_run.head_*` value is used anywhere.
- `TRIGGER_RUN_ID` (`^[0-9]+$`, CTO F16) is used for ONE membership check (the triggering run is present in the read and `completed`), never for a decision about content. It is the only `github.event.*` value in the file.
- The YAML text avoids the words `terraform`, `secrets.`, `environment:` and the dispatch spellings even in comments (the suite greps raw text and prints why on failure, quoting the allowed phrasing "the apply group"). The apply group literal is never written in the file.

### Script algorithm (`scripts/apply-delivery-gap.sh`)

Constants: `WATCHED` rows `key|file|display name|kill-switch-regex` (deploy-fix: `[skip-deploy-fix-apply]`; infra: `[skip-web-platform-apply]`; each copied verbatim from its own workflow's preflight); `WINDOW_DAYS=7`; `PAGE_SIZE=100`; `MAX_PAGES=10` (a comment records the live volume: infra ~10 runs/day); stale caps `waiting` 60 min, `queued|pending|requested|in_progress` 90 min; `LABEL=apply-delivery-gap`; `TITLE='infra: apply delivery gap - trigger-file change not applied'`.

Inputs: env `GH_REPO` (validated `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`), `GH_TOKEN` (consumed by `gh` only, never read or printed), `TRIGGER_RUN_ID` (digits or empty; empty skips the membership check); argv `--self-test` | `--fixture-dir <absolute dir>` (the `assert_fixture_dir` guard copied from `codeql-main-alert-gate.sh`). In fixture mode only: `now` comes from `<dir>/now`, and `APPLY_DELIVERY_GAP_PAGE_SIZE` / `APPLY_DELIVERY_GAP_MAX_PAGES` may shrink the paging constants so truncation is testable without 1,000-run fixtures; fixture mode never sleeps. Exit: 0 reconcile complete (a filed gap is a green run - the issue is the page); 1 any `::error::apply_delivery_gap_<reason>`; 2 rejected input (before any call).

Reads are `timeout 60 gh ...` with status read explicitly through ONE wrapper `api_get`, so a failure is `fail_loud <reason>` -> `exit 1`; no `|| true` and no `2>&1` on a data read; stderr is captured into a variable to classify an HTTP status and is never echoed. Real and fixture paths are structurally identical up to `api_get`. Bash discipline under `set -euo pipefail`: counters use `n=$((n+1))` (never `((n++))`), `grep -c`/`jq -e` empty results are guarded, no here-string `read` of a possibly empty variable is treated as a row.

Steps, in order:

1. **Read runs (F1).** Per watched workflow: `gh api "repos/$R/actions/workflows/$FILE/runs?per_page=100&page=$p"`, p = 1..MAX_PAGES (runs are created-desc; the fixture asserts strictly descending order); stop when a page has < PAGE_SIZE runs or its last run is older than the cutoff; a full page whose last run is still inside the window at page MAX_PAGES -> `run_window_truncated` (page MAX_PAGES with exactly PAGE_SIZE runs whose oldest is beyond the cutoff is accepted). Validate `.workflow_runs` is an array and each run has numeric `id`, 40-hex `head_sha`, ISO `created_at`, else `malformed_response`. Normalise to `{id, event, branch, status, conclusion, sha, created, updated, msg}`; the URL is rebuilt as `https://github.com/$R/actions/runs/$id`. The message is fetched per candidate with `jq -r --arg id ...` into a bash variable and matched with the copied bash `=~` (never re-implemented in jq, never through `@tsv`, so real newlines survive).
2. **Trigger visibility (F16).** If `TRIGGER_RUN_ID` is set, assert that run id is present in the read with `status == completed`; retry the whole read up to 3 times, 5 s apart; then `::error::apply_delivery_gap_trigger_run_not_visible`, exit 1.
3. **Candidates.** `event == push`, `head_branch == main`, `status == completed`, `conclusion == cancelled`, `created >= now - 7d`, and not carrying its OWN workflow's marker (logged `dropped killswitch`). A watched key with no marker entry is a suite failure (S4).
4. **Delivery (per candidate S on workflow W, runs of W in `created` ascending order).**
   a. *Delivered* iff a run R of the SAME W has `status completed`, `conclusion success`, `head_branch main`, `created >= S.created`, AND (`R.sha == S.sha` or `compare S.sha...R.sha?per_page=1` `.status` in `identical|ahead`), AND the jobs of R (`GET actions/runs/<id>/jobs?per_page=100`, memoised per run id, read only for runs that pass the ancestry test) contain a job named `apply` with `conclusion == success` (F11: `skipped` is not success). `workflow_dispatch` successes count only through this same rule. The sibling's runs are never consulted. HTTP 404 from compare = "not a descendant" plus `::warning::apply_delivery_gap_compare_unresolvable sha=<sha7>`; any other failure -> `compare_failed` (F17).
   b. else *Deferred* iff a same-W run with `status` in `queued|pending|requested|waiting|in_progress`, `head_branch main`, `created >= S.created`, not stale (`waiting` 60 min, the rest 90 min from `created_at`) and (`sha == S.sha` or compare ahead/identical) exists - unconditionally, with no kill-switch leg (F8'); one `::notice::apply_delivery_gap_deferred workflow=<key> sha=<sha7>` per deferred candidate.
   c. else *Undelivered* -> a row.
5. **Classify rows** with `GET repos/$R/actions/runs/$id/jobs?per_page=1` `.total_count`: `0` = `evicted-before-start` (p1), `>= 1` = `cancelled-mid-run` (p0, state possibly partial). Failure -> `jobs_read_failed`; non-integer -> `malformed_response`.
6. **Reconcile the issue.** `ISSUES=$(gh issue list --label apply-delivery-gap --state open --json number,title --limit 100) || fail_loud issue_list_failed` (same run, immediately before the write; lowest number wins, warn on more than one). `gh label create apply-delivery-gap --force --color <c> --description <d>` runs before BOTH arms (a human-deleted label can never wedge the edit arm). Then exactly one of:
   - rows non-empty, no issue: `gh issue create --title TITLE --body-file F --label apply-delivery-gap --label action-required --label priority/p1-high [--label priority/p0-critical when any row is mid-run]`.
   - rows non-empty, issue open: ONE `gh issue edit N --body-file F --add-label apply-delivery-gap,action-required,priority/p1-high[,priority/p0-critical]` (idempotent, so a stripped `action-required` is re-added on every refresh; p0 is add-only, F4; there is no `--remove-label` anywhere).
   - rows empty, issue open, read complete, deferred empty AND no non-stale run of EITHER watched workflow in flight (F3, F14): `gh issue close N --reason completed|"not planned" --comment <text>`: reason `completed` iff `delivered >= 1`, else `not planned` with the sentence "no cancelled push remains inside the 7-day window, delivery not verified" (F13). With `delivered >= 1` the comment lists each delivered candidate: workflow, sha7, delivering run id, and minutes from cancel to delivery (this is the durable row-age evidence).
   - otherwise: leave the issue untouched; log the reason.
   Write failures -> `issue_write_failed` / `label_failed`.
7. **Trace (F7).** One `::notice title=apply-delivery-gap::row workflow=<key> sha=<40hex> class=<c>` per row per reconcile, plus `::notice::apply_delivery_gap_summary workflows_read=2 candidates=N rows=N deferred=N delivered=N dropped=N mid_run=N inflight=N issue=<none|#N|created|edited|closed>`. `workflows_read=2` is the anti-vacuity witness the suite asserts.

Failure reasons (each pinned by a scenario): `bad_input`, `runs_list_failed`, `run_window_truncated`, `malformed_response`, `trigger_run_not_visible`, `jobs_read_failed`, `compare_failed`, `issue_list_failed`, `label_failed`, `issue_write_failed`.

**Issue body** (a pure function of the current read; public-safe: workflow display name, 40-hex SHA, run URL, class, integer minutes, printed commands, this run's URL and a UTC time - no commit message, actor, log or secret). Order, top to bottom: (1) a three-line "Do this" block: paste the command in your row; the issue resolves itself on the next reconcile; if it does not, read the run and the runbook section. For a `cancelled-mid-run` row: "do NOT dispatch before reading the run - state is possibly partial". (2) the table:

| Workflow | Push SHA | Run | Class | Minutes since cancel | Next step (printed here, never executed by this workflow) |
|---|---|---|---|---|---|

Next-step cell, deploy-fix: ``gh workflow run apply-deploy-pipeline-fix.yml --ref main -f reason='apply-delivery-gap <sha7>'``; infra: ``gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun -f reason='apply-delivery-gap <sha7>'``. (3) footer: "last reconciled <UTC time> by <this run URL>", the 7-day window, "escalate when a row passes 60 minutes", "a push carrying its own workflow's skip marker never appears here", the runbook path, and the drift-cron backstop. The body references no issue number and contains no closing keyword.

## Files to Create

- `.github/workflows/apply-delivery-gap-follower.yml`
- `scripts/apply-delivery-gap.sh`
- `plugins/soleur/test/apply-delivery-gap-follower.test.sh`
- `plugins/soleur/test/fixtures/apply-delivery-gap/base/` (empty world: `runs.deploy-fix.json`, `runs.infra.json`, `issues.json`, `now`) and one small directory per scenario named in the brief, each holding ONLY the files it overrides (`runs.<key>[.<page>|.r<attempt>].json`, `jobs.<runid>.json`, `compare.<S>.<R>.json`, `issues.json`, `now`): `cancelled-zero-jobs`, `cancelled-then-later-success-descendant`, `cancelled-with-jobs`, `cancelled-killswitch`, `success-only`, `non-push-or-non-main`, `inflight-descendant`, `api-failure`, `dedup`, `sibling-success-does-not-count`, `delivery-requires-apply-job`, `replay-37964350917`, `replay-37964762496`, `replay-38144232116`, `replay-incident-delivered`. Variants of those worlds (the failure-injection matrix, truncation, re-run, trigger visibility) are built inline by `mkrun`/`mkjobs`/`mkcompare` helpers in the suite and by `fail.<call>` marker files created in the sandbox, not committed.
- `knowledge-base/project/specs/feat-one-shot-apply-delivery-gap-follower/tasks.md`, `.../decision-challenges.md`

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-red-run.md` - add `## An apply delivery gap issue (label apply-delivery-gap)`: (a) a decision table copied from the existing "Do NOT fire this on these" format with three rows - `evicted-before-start` (dispatch the printed command), `cancelled-mid-run` with a green re-dispatch (read the run, then dispatch, verify), `cancelled-mid-run` with a red re-dispatch (use the heartbeat-sweep section above first); (b) verification (the issue closes itself on the next reconcile; for deploy-fix rows also `scripts/check-deploy-script-parity.sh`); (c) when closing a new gap issue by hand, remove a stale `priority/p0-critical` if the new gap is not mid-run (F4: the follower never removes it); (d) the flip-evidence count recipe - read-only `gh issue list --label apply-delivery-gap --state all --json number,createdAt,body,comments` plus the `::notice row` run-log lines (about 90 days of retention, so count issue comments too); row ages come from the close comment's "minutes from cancel to delivery"; (e) the stale-gap note (a gap untouched for 7 days ages out of the issue; the drift cron reports it). No remote-shell fallback (`hr-no-ssh-fallback-in-runbooks`).
- `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` - `### Addendum 2026-10-23 (#9454; Ref #10033, #8167): the apply delivery gap follower is detection only`, placed after the 2026-10-22 addendum and before `## Cost Impacts`.

Not edited, by constraint: `.github/CODEOWNERS` (draft #8626), `scripts/lib/test-affected-paths.sh` and `scripts/suite-shard-legs.tsv` (open PRs #10744 and #7390), any AGENTS rule line, `.claude/rule-weakening-acks.txt`, both apply workflow files, #9482 / #10245 / #5840 artefacts.

### Suite classification (consequence of the constraint above)

The repo's orphan census (`scripts/lint-orphan-test-suites.sh`) marks a registered suite whose edges cannot be derived as UNCLASSIFIED and goes RED. `plugins/soleur/test/codeql-main-alert-gate*.test.sh` classify as `edge:derived` (verified with `bash scripts/test-all.sh --affected --print-affected-set`) because the suite names its SUT by repo-relative literal paths. This suite therefore names `scripts/apply-delivery-gap.sh`, `.github/workflows/apply-delivery-gap-follower.yml`, and both apply workflow files as repo-relative literals. Phase 1 gate: run `--print-affected-set | grep apply-delivery-gap` and `bash scripts/lint-orphan-test-suites.sh`. If it still reports UNCLASSIFIED, the declaration belongs in `scripts/lib/test-affected-paths.sh`, which this change may not touch while #10744 / #7390 are open: the fallback order is (1) make the dependency literal-derivable, (2) rebase onto the merge of those PRs and add the declaration, (3) report the blocker in the PR body rather than weaken the census. Local `--affected` may degrade to the full battery; the substitute gate is the suite itself, the repo workflow linters, the ratchets and CI's full battery. No `suite-shard-legs.tsv` row is added (default weight applies).

## Implementation Phases (RED first - `cq-write-failing-tests-before`)

**Phase 0 - RED.** Create the fixture tree and the suite; the script does not exist yet, so every scenario fails (record the red count in the commit message). Write first: the instrument self-test (a `pass`/`fail` pair that must both record) and the vacuity row H1 (a stub SUT that exits 0 and prints nothing must RED the suite).

**Phase 1 - the script, scenario by scenario to GREEN.** Order: input/fixture-dir guards -> runs read, paging, truncation -> trigger visibility -> candidate filter -> delivery predicate (ancestry, then apply-job leg) -> deferral -> classification -> issue reconcile -> trace -> `--self-test`. After each step run only the pinned scenario ids. Classification gate (see above).

**Phase 2 - the workflow + wiring leg.**

**Phase 3 - the mutation battery** (default suite, F9; each mutant re-runs only its pinned scenarios; a mutant that does not land or does not redden fails the suite; the declared count is asserted). Record the battery's wall time in the PR body; ceiling 90 s.

**Phase 4 - docs.** Runbook section, ADR-270 addendum, `decision-challenges.md`.

**Phase 5 - verify (all offline).** `bash plugins/soleur/test/apply-delivery-gap-follower.test.sh`; `bash scripts/apply-delivery-gap.sh --self-test`; `bash scripts/lint-workflows.sh .github/workflows/apply-delivery-gap-follower.yml`; `actionlint` and `shellcheck scripts/apply-delivery-gap.sh`; `python3 scripts/lint-workflow-issue-write-scope.py`; `python3 scripts/lint-workflow-step-env-refs.py`; `python3 scripts/lint-workflow-local-action-checkout.py`; `bash scripts/alarm-issue-filing-guard.test.sh`; `bash scripts/lint-orphan-test-suites.sh`; `bash plugins/soleur/test/c4-count-parity.test.sh`; `python3 scripts/lint-guard-contract.py <this plan>`; `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (the gate's own invocation, not a hand-listed set); `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch feat-one-shot-apply-delivery-gap-follower`; `npx markdownlint-cli2 <plan> <tasks.md> <runbook>`; the secret scan over the fixture tree (the 40-hex SHAs and run ids are public identifiers).

**Merge.** This PR touches `.github/workflows/`: no agent `--admin` fallback; merge only through the merge queue. PR body: `Ref #9454`, `Ref #10033`, `Ref #8167` - no closing keyword adjacent to any issue number (also none in commit messages).

## Test Scenarios

Harness: `run_case <scenario> [tweaks]` copies `base/` then the scenario overlay into a fresh sandbox under `/var/tmp`, runs the SUT with `--fixture-dir`, and captures stdout, stderr, rc and `out/actions.log` (one line per recorded write: `label-create`, `issue-create`, `issue-edit`, `issue-close`, with flags and body file). Fixtures are SYNTHESIZED reduced records (only fields the script reads; invented messages; no actors, no emails; an `example-org/example-repo` slug). The replay fixtures reuse the public incident run ids, head SHAs and timestamps from the issue record (identifiers of public Actions runs, not payload captures) - a stated departure from invented ids because the ask is to replay those ids. Assertions floors use `-lt` minimums plus a per-case "ran at least one assertion" guard (no exact-count constant to bump).

| # | Scenario (named fixture dir in bold) | Assert |
|---|---|---|
| S1 | **cancelled-zero-jobs** | exactly 1 row, `evicted-before-start`; one `label-create` then `issue-create` with labels apply-delivery-gap, action-required, priority/p1-high and NOT p0; one `::notice row` line; body begins with the "Do this" block and ends with the last-reconciled footer |
| S2 | **cancelled-then-later-success-descendant** (+ prior open issue) | 0 rows; an unrelated EARLIER non-descendant success (compare `behind`) precedes the delivering one so a first-success-wins stub fails; `issue-close --reason completed` once; close comment lists sha7, delivering run id and minutes from cancel to delivery; no create/edit |
| S3 | **cancelled-with-jobs** | `cancelled-mid-run`; `priority/p0-critical` added; body carries "do NOT dispatch before reading the run" |
| S4 | **cancelled-killswitch** | deploy-fix push with `[skip-deploy-fix-apply]` on its own line (also in the middle line of a multi-line message): dropped; infra push with `[skip-web-platform-apply]`: dropped; the deploy-fix marker inside an infra push: NOT dropped; a marker mid-line: NOT dropped; 1 qualifying row beside them so "drop everything" fails; every WATCHED key has a marker table entry |
| S5 | **success-only** | no candidates; no jobs/compare call recorded; summary `workflows_read=2`; with an open issue and nothing in flight the close is `--reason "not planned"` with the aged-out sentence; with no issue no write |
| S6 | **non-push-or-non-main** | cancelled `workflow_dispatch`, cancelled push on a non-main branch, cancelled `schedule`, a cancelled push 8 days old: 0 rows; one qualifying candidate beside them: exactly 1 row |
| S7 | **inflight-descendant** | `in_progress`, `queued`, `pending` and a fresh `waiting` descendant each defer (a `deferred` notice, 0 rows, an open issue is NOT closed); `waiting` at 61 min and `queued` at 91 min do not defer; an in-flight run of the OTHER workflow does not defer the row but does block the close (F14) |
| S8 | **api-failure** (matrix: loop over injected failures) | runs list p1, runs list p2, jobs (classification), jobs (apply-job leg), compare 5xx, issue list, issue edit, label create, malformed body -> each exits 1 with its own `::error::apply_delivery_gap_<reason>`, an open issue present in the fixture and NO `issue-close`/write recorded, stdout never says "no gap"; compare 404 -> warning, row stays, rc 0; trigger run invisible after 3 attempts -> `trigger_run_not_visible`; trigger run `in_progress` on attempt 1 and `completed` on attempt 2 (via `runs.<key>.r2.json`) -> proceeds |
| S9 | **dedup** | open issue with a stale 1-row body and `action-required` stripped + two candidates: exactly 1 `issue-edit` (body + `--add-label` including `action-required`), 0 creates, `label-create` before it, no `--remove-label` anywhere; the same input again -> again exactly 1 edit and the same row set; two open issues -> lowest number edited, warning; open issue already carrying p0 with only p1 rows -> edit still has no remove |
| S10 | **sibling-success-does-not-count** | deploy-fix candidate with an infra apply-success at a descendant -> row remains; infra candidate with a deploy-fix apply-success -> row remains |
| S11 | **delivery-requires-apply-job** | a later push success whose `apply` job is `skipped` does not deliver; a later dispatch success with only an `entrypoint_audit`-shaped job set does not deliver; a later dispatch success with `[preflight success, apply success]` delivers; a later success whose `apply` is `success` but run-level conclusion is not success cannot occur (run must be success) |
| S12 | (inline) re-run of cancelled S in flight | S is no longer a candidate; an open issue is NOT closed while it runs (F14); closes on the next read after it completes |
| S13 | (inline) truncation boundary | with page size 2 / max pages 3: 3 full pages inside the window -> `run_window_truncated`; page 3 full but oldest beyond the cutoff -> accepted |
| R1-R3 | **replay-37964350917**, **replay-37964762496**, **replay-38144232116** (one data-driven loop) | each: exactly 1 row, workflow deploy-fix, class `evicted-before-start`, URL contains the run id, sha as recorded |
| R4 | **replay-incident-delivered** | R1+R2 fixtures plus dispatch success `37976212395` (head `79482dab`, `apply` success, compare `ahead` for both) -> 0 rows and a close |
| H1/H3/H4/H5 | harness | (H1) a stub SUT that exits 0 with no output REDs the suite; (H3) must-PASS non-canonical inputs: 3 pages, reversed workflow order, a candidate on page 2; (H4) fixture mode runs under a `PATH` with no `gh` (a stray call fails loudly); (H5) `--self-test` prints `apply-delivery-gap self-test: ok` offline in under 5 s, and is three pure checks: both kill-switch regexes, the compare-status mapping, the jobs-count class + apply-job leg |
| W | workflow wiring | parsed YAML (read `doc.get('on', doc.get(True))`: PyYAML parses a bare `on:` key as boolean `True`; assert the result equals `{'workflow_run'}` and is non-empty): `types: [completed]`, `branches: [main]`; `workflows:` and the script's `WATCHED` names equal the live apply files' `name:` strings (failure text names all copies: the apply workflow, the follower's `workflows:`, the script's `WATCHED`); every watched file exists; `permissions` exactly `{contents: read, actions: read, issues: write}` with no job-level block; concurrency group literal differs from the apply files' group and `cancel-in-progress: false`; the same kill-switch literals appear in the script and in each apply workflow's preflight; grep: no `secrets.`, `environment:`, `terraform`, `workflow_dispatch`, `gh workflow run`, `/dispatches` (failure text explains why and quotes "the apply group"); no `github.event.` text except the one `TRIGGER_RUN_ID` env value; every `uses:` is a 40-hex pin; checkout has no `ref:`; the `run:` line is exactly `bash scripts/apply-delivery-gap.sh`; `timeout-minutes` set; anti-vacuity floor on parsed steps; chokepoint greps on the script (no bare `gh api` / `gh issue list` outside `api_get`/the lookup spelling, no `|| true` or `2>&1` on a data read, no `--remove-label`) |

**Mutation battery (single table - the Guard Contract entries below cite these ids; they add no further tests).** Each row is `id | edit on a sandbox copy of the script | pinned scenarios`:

| id | Mutation | Pinned |
|---|---|---|
| M1 | delivery accepts `behind` as descendant (direction flipped) | S2, R4 |
| M2 | success set not scoped to the candidate's workflow (sibling counts) | S10 |
| M3 | `fail_loud` returns instead of exiting (a failed read is tolerated and the close arm is reached) | S8 |
| M4 | kill-switch candidate drop removed | S4 |
| M5 | infra row uses the deploy-fix marker (marker table mis-wired) | S4 |
| M6 | `apply` job-name leg dropped from the delivery predicate | S11 |
| M7 | `skipped` accepted as `success` for the `apply` job | S11 |
| M8 | close arm ignores `deferred` | S7 |
| M9 | close arm ignores in-flight runs of the other workflow / a re-run | S7, S12 |
| M10 | truncation guard removed | S13 |
| M11 | `action-required` not re-asserted on refresh | S9 |
| M12 | compare HTTP 404 read as "delivered" | S8 |
| M13 | trigger-run visibility assertion removed | S8 |
| Y1 | (workflow YAML mutant) add a job-level `permissions` widening to `contents: write` | W |
| Y2 | (workflow YAML mutant) set the concurrency group to the apply group literal | W |

`MUTANT_FLOOR` is asserted equal to the table length (15 incl. Y1/Y2). Other regressions (stale caps, classification, filters, trace output, close-comment text) are killed by direct assertions in S1-S7, not by mutants.

## Guard Contract

### Guard 1 - close and "no gap" only on a complete read

**Property.** The follower closes an issue or reports "no gap" only when every API read of the reconcile returned a complete, well-formed answer, nothing is deferred and nothing relevant is in flight.

**Assembly.** The close arm is one function. Every read - runs pages for both watched workflows (incl. the truncation stop and the trigger-visibility retry), jobs per row and per delivering candidate, compare per (candidate, run) pair, the issue list - flows through the single `api_get` -> `fail_loud` -> `exit 1` chokepoint; the suite greps the script for any bare `gh api` / `gh issue list` outside it, for `|| true` / `2>&1` on a read, and for `--remove-label`. Plural reads (two workflows, N pages, M compares) are quantified over every member, not the first. Writes (`issue create/edit/close`, `label create`) are the only other `gh` call sites and each has its own named reason.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | M3: `fail_loud` returns instead of exiting while an open issue is present | RED (S8: a recorded close) |
| 2 | M10: truncation guard removed | RED (S13) |
| 3 | M8: close arm ignores `deferred` | RED (S7) |
| 4 | M9: close arm ignores in-flight runs / a re-run | RED (S7, S12) |
| 5 | M13: trigger-run visibility assertion removed | RED (S8) |
| 6 | the S8 failure loop covers the SECOND workflow's page 2 and a compare read after a compliant first (second members after a compliant first) | RED if either is tolerated |

**Harness rows.** H1 (a stub SUT that exits 0 with no output REDs the suite) and H3 (must-PASS non-canonical worlds: 3 pages, reversed workflow order, page-2 candidate) so a guard that rejects everything cannot pass; S5 asserts `workflows_read=2` so a loop over zero workflows cannot pass.

**Anchor.** The completeness rule is structural (the chokepoint) and the page cap and window are constants whose weakening is visible in the same diff as the S13 legs that pin them (a lowered `MAX_PAGES` reds the "accepted" leg, a raised one reds the "rejected" leg).

### Guard 2 - the delivery predicate

**Property.** A candidate push is "delivered" only when a run of the SAME workflow, created at or after it, whose head is the candidate or a git descendant, actually ran its `apply` job to success; any other run leaves it undelivered.

**Assembly.** One predicate function evaluated for every (candidate, same-workflow run) pair over the single per-workflow normalised run list (the sibling's list is a different variable the predicate never receives). Legs, in order: same workflow key; `conclusion == success`; `created >= S.created`; ancestry (`sha` equality or `compare` status in `identical|ahead`; 404 = not a descendant); the `apply` job leg (name `apply`, `conclusion == success`). Deferral reuses the status/ancestry legs with the in-flight status set and the stale caps.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | M1: accept set becomes `behind` | RED (S2, R4) |
| 2 | M2: success set not scoped to W | RED (S10) |
| 3 | M6: `apply` job leg dropped | RED (S11) |
| 4 | M7: `skipped` accepted as success | RED (S11) |
| 5 | M12: compare 404 read as delivered | RED (S8) |
| 6 | delivery iterates only the FIRST success run instead of all (S2 carries an earlier non-descendant success) | RED (S2) |

**Harness rows.** S2's earlier non-descendant success defeats a first-success-wins stub; must-PASS inputs differ from the canonical: a dispatch success with a different commit message, a success whose head equals S, the R4 real shape.

**Anchor.** The compared value is live git ancestry from the API (`compare`) and the live job list; nothing in this change can edit either. (The `created >= S.created` leg is kept because the brief states it; it is observationally redundant with ancestry on real data, so it has no mutant.)

### Guard 3 - candidate filter and kill-switch drop

**Property.** Only cancelled `push` runs on `main` inside the 7-day window are candidates, and a push carrying its own workflow's skip marker is never reported.

**Assembly.** One candidate-selection function over each workflow's normalised list; filters: event, branch, status/conclusion, window, and the per-workflow marker table (`=~` copied verbatim from each workflow's preflight; message read into a bash variable per candidate, never through jq/`@tsv`).

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | M4: kill-switch drop removed | RED (S4) |
| 2 | M5: infra row uses the deploy-fix marker | RED (S4) |
| 3 | a watched key with no marker entry (add a third WATCHED row in the sandbox copy) | RED (S4 table-completeness check) |
| 4 | event / branch / window filters each dropped (S6 asserts directly; four non-candidates beside one qualifying) | RED (S6) |
| 5 | marker accepted mid-line (regex unanchored) | RED (S4 mid-line leg) |
| 6 | classification inverted (jobs 0 <-> >= 1) | RED (S1, S3 direct assertions) |

**Harness rows.** S6 and S4 each include one qualifying candidate beside the non-candidates so "ignore everything" fails; message fixtures include a marker on a middle line of a multi-line message (must drop) and mid-line (must not).

**Anchor.** Each marker regex is compared against the live apply workflow's preflight by the wiring leg (the same literal must appear in both files), so editing only one side reds the suite.

### Guard 4 - workflow shape (no write path to production)

**Property.** The follower workflow cannot hold secrets, enter an environment, run `terraform`, dispatch anything, or share the apply concurrency group, and its permission set is exactly three scopes.

**Assembly.** The single workflow file, checked on its parsed form AND by raw-text grep (a comment can hide a grep hit and a parser can miss a string); every `uses:`, every `permissions` block (workflow and job level), every `env:` mapping, every `run:` body.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Y1: job-level `permissions` widening (a second permissions site after a compliant workflow-level one) | RED |
| 2 | Y2: concurrency group set to the apply group literal | RED |
| 3 | add `secrets.X` / `environment:` / `workflow_dispatch:` / an unpinned `uses:` | RED (raw-text grep and parsed checks assert directly; not separate mutants) |

**Harness rows.** The wiring leg reads the real file and has an anti-vacuity floor (parsed steps >= 2, parsed `on` non-empty). Must-PASS: the real file.

**Anchor.** The apply workflows' `name:` strings, kill-switch literals and concurrency literal are read live from their files (outside this change's diff).

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-270 (not a new ADR): it extends the existing merge-queue / post-merge-gate family with a detection-only apply-delivery follower. Task: add the `### Addendum 2026-10-23` section via the `architecture` skill conventions. Content, honestly sized (one decision paragraph plus a short residual list): the decision (detect and file, no fix); why the two fixes stay deferred (the single-workflow merge changes the sole serializer of lock-less R2 state; a re-dispatch follower writes production and must honour two kill switches; option 2 "poll for the sibling" is rejected because evicted runs have zero jobs); the flip evidence bar (3 or more distinct SHAs in 30 days, or a row aged past 1 h with real deploy impact, plus a green operator-reviewed rehearsal on a disposable group and state key) and how it is counted (run-log notices, close comments, runbook recipe); the refinement "the ruling's `last ~50` became an unfiltered read to a 7-day cutoff, 10-page ceiling"; and the residuals that change an operator's behaviour: an untouched gap older than 7 days ages out of the issue (the close comment says so; the drift cron is the backstop); detection can be delayed to the evictor's completion; a red run is the only signal of a failed read; `CODEOWNERS` rows for the script, test and fixtures to be added after #8626 merges. ADR status unchanged. Not deferred to a follow-up.

### C4 views

No C4 change. Read in full: `model.c4` (996 lines), `views.c4` (131), `spec.c4` (54). External human actors: none new (the founder already reads GitHub issues through `founder -> github`). External systems: GitHub is modelled (`github = system "GitHub"`) and the follower is GitHub-internal (a GitHub-to-GitHub relationship cannot be drawn: LikeC4 rejects self-relations, same note as `views.c4` line ~12). Data stores: none (stateless; the issue is the page). Actor-to-surface access relationships: unchanged. Derived cardinalities: no `actions/sentry-heartbeat` use and no monitor slug, so the `github -> sentry` counts do not move; `bash plugins/soleur/test/c4-count-parity.test.sh` is green on the base commit and is re-run in Phase 5.

### Sequencing

The ADR addendum describes the shipped (detection) state; no soak-gated activation.

## User-Brand Impact

- **If this lands broken, the user experiences:** either nothing changes from today (a cancelled `ci-deploy.sh` apply stays silent and production deploys keep rolling back until someone notices - the ~4 h blocked-deploy incident of 2026-10-09, #9871) or one spurious `action-required` issue naming a push that was in fact applied.
- **If this leaks, the user's workflow is exposed via:** nothing beyond what the public Actions UI already shows - workflow names, 40-hex SHAs, run URLs and minute counts reach a public issue body; the follower holds no secret and reads no commit message into any output.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** a missed apply degrades deploy reliability for all users until noticed but is recoverable by a dispatch and bounded by the 12 h drift backstop; it is not a single-user irreversible incident, so no per-PR CPO sign-off is added.

## Observability

```yaml
liveness_signal:
  what: "workflow_run of apply-delivery-gap-follower.yml on every completed run of the two apply workflows, ending in a ::notice apply_delivery_gap_summary line with workflows_read=2"
  cadence: "per completed apply run (event-driven); the 12 h scheduled-terraform-drift cron is the independent backstop"
  alert_target: "an open action-required GitHub issue (harvested by the operator digest) for a gap; a red Actions run for a failed read"
  configured_in: ".github/workflows/apply-delivery-gap-follower.yml and scripts/apply-delivery-gap.sh"
error_reporting:
  destination: "GitHub Actions annotations on the follower run (no Sentry: no application runtime, no new vendor edge)"
  fail_loud: "exit 1 plus ::error::apply_delivery_gap_<reason> with a distinct reason per failure class"
failure_modes:
  - mode: "an API read fails, a runs page is truncated, or the triggering run is not visible"
    detection: "::error::apply_delivery_gap_runs_list_failed | jobs_read_failed | compare_failed | issue_list_failed | malformed_response | run_window_truncated | trigger_run_not_visible, red run, issue never closed"
    alert_route: "red follower run on main (visible in the Actions list); the drift cron backstops within 12 h"
  - mode: "the issue write fails"
    detection: "::error::apply_delivery_gap_issue_write_failed | label_failed"
    alert_route: "red follower run; the next apply completion retries the full reconcile"
  - mode: "the follower never fires (a watched workflow is renamed, or the platform skips workflow_run for a pending-cancelled run)"
    detection: "the suite's wiring leg compares the follower's workflows list and the script's WATCHED table to the live name strings and reds on a rename; for the platform case the evictor's own completion still triggers the reconcile"
    alert_route: "CI red on the PR that renames; otherwise the drift cron"
  - mode: "a gap exists but is older than 7 days"
    detection: "ages out of the issue by design; the close comment says delivery is not verified"
    alert_route: "scheduled-terraform-drift (12 h) reports the resulting drift"
logs:
  where: "Actions run logs of apply-delivery-gap-follower.yml (::notice row lines, deferred notices, summary line)"
  retention: "GitHub default Actions log retention (90 days); close comments on the issue are permanent"
discoverability_test:
  command: bash scripts/apply-delivery-gap.sh --self-test
  expected_output: "apply-delivery-gap self-test: ok"
```

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The binding design is the CTO ruling of 2026-10-22. This planning run additionally obtained CTO rulings on the implementation forks F1-F17 (recorded in `decision-challenges.md`) via the `soleur:engineering:cto` agent, and a plan-review panel (DHH, Kieran, code-simplicity, CTO devex lens) whose mechanical findings were applied; no operator question was asked. No other domain (legal, finance, marketing, sales, support, operations, product) has an implication: no UI surface, no personal data, no new vendor, no pricing or brand content. Product/UX gate: NONE (no UI-surface file in the Files lists). GDPR gate: not triggered (no schema, auth, API route or `.sql` file; the public issue body carries only SHAs, run URLs and workflow names; no learnings or specs are read).

**Brainstorm-recommended specialists:** none (no brainstorm; one-shot path).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "ONE small PR that ships ONLY the detect-and-file apply-delivery-gap follower" | Overview deliverables 1-5; Cut List | mapped |
| 2 | "new workflow `.github/workflows/apply-delivery-gap-follower.yml` on `workflow_run` types [completed] for the two workflows" | Trigger and wiring; W | mapped |
| 3 | "Permissions exactly `contents: read`, `actions: read`, `issues: write`. No `secrets.*`, no `environment:`, no Doppler, no `terraform`, no workflow dispatch." | Trigger and wiring; Guard 4; W | mapped |
| 4 | "Its own concurrency group (NOT `terraform-apply-web-platform-host`), `cancel-in-progress: false`." | Trigger and wiring; W | mapped |
| 5 | "All actions SHA-pinned; every `github.event.*` value routed through `env:`; SHAs validated `^[0-9a-f]{40}$`; checkout of main only." | Trigger and wiring (one event value, via env); script step 1 SHA validation; W | mapped |
| 6 | "Logic lives in `scripts/apply-delivery-gap.sh` (with `--self-test` and `--fixture-dir <d>`" | Script algorithm; H5 | mapped |
| 7 | "Stateless reconcile per run: candidates = last ~50 runs of each watched workflow on main with event push and conclusion cancelled, within 7 days" | Script steps 1 and 3 (F1 refinement) | mapped |
| 8 | "Classify via the jobs API: zero jobs = `evicted-before-start` (p1), one or more jobs = `cancelled-mid-run` (p0, state possibly partial)." | Script step 5; S1, S3 | mapped |
| 9 | "Drop pushes whose head commit message matches the deploy-fix kill switch `[skip-deploy-fix-apply]` (deploy-fix watcher only; copy the workflow's own regex)." | Script step 3; Guard 3; S4 (extended to the infra workflow's own marker, F12) | mapped |
| 10 | "A candidate S on workflow W is delivered iff a run of W exists with conclusion success, created at or after S, and head_sha equal to or descended from S (use the compare API: identical or ahead); a workflow_dispatch success counts; a success of the OTHER workflow does not." | Script step 4a; Guard 2; S2, S10, S11, R4 | mapped |
| 11 | "Defer if a descendant run of W is queued/pending/waiting/in_progress (a `waiting` run older than 60 min does not defer)." | Script step 4b; S7 | mapped |
| 12 | "Close arm only when the undelivered set is empty AND every API call succeeded." | Script step 6; Guard 1; S8, S12 | mapped |
| 13 | "One issue found by LABEL `apply-delivery-gap` (create idempotently), title ..., labels ..., re-assert action-required on every refresh, body = a table of rows keyed (workflow, SHA)" | Script step 6 + body; S1, S9 | mapped |
| 14 | "Fail loud on any API/list failure with a distinct `::error::apply_delivery_gap_<reason>` and never close or report \"no gap\" on a partial read." | Failure reasons list; S8 | mapped |
| 15 | "The existing 12 h drift cron (`scheduled-terraform-drift.yml`) stays the backstop; do not duplicate it" | Cut List; Observability | mapped |
| 16 | "add a short section to `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-red-run.md` mapping gap issue to dispatch command to verification" | Files to Edit | mapped |
| 17 | "a one-paragraph ADR-270 addendum recording the detection-only decision and the flip evidence bar" | ADR section | mapped |
| 18 | "Single-workflow merge and re-dispatch follower stay DEFERRED; do not implement them." | Cut List; ADR section (tracked by open #10033 and #8167, which do not close) | mapped |
| 19 | "`plugins/soleur/test/apply-delivery-gap-follower.test.sh` plus fixtures under `plugins/soleur/test/fixtures/apply-delivery-gap/`: cancelled-zero-jobs; cancelled-then-later-success-descendant ..." | Files to Create (every named fixture dir is committed); Test Scenarios | mapped |
| 20 | "Replay offline the three recorded incident run ids ... each yields exactly one row with the right class." | R1-R3 | mapped |
| 21 | "Mutation-verify the guards you add (delivery predicate direction, sibling-does-not-count, close-only-on-complete-read, kill-switch drop) on a sandbox copy." | Mutation battery M1-M13, Y1-Y2; Guard Contract | mapped |
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
| Deferral held for the close arm; stale caps; in-flight blocks close (F3, F14, F15, F8') | "Defer if a descendant run of W is queued/pending/waiting/in_progress" | inferred - justification: closing under an in-flight or re-running descendant claims "no gap" early, and an uncapped defer hides a gap forever; CTO F3/F14/F15/F8' |
| Close reason + close comment contents (F13) | "Close arm only when the undelivered set is empty" | inferred - justification: a silent age-out must not read as delivered, and the comment is the only durable row-age record for the flip bar; CTO F13 |
| p0 add-only (F4) | "(+ priority/p0-critical for any mid-run row)" | inferred - justification: protects a human escalation; CTO F4 |
| `TRIGGER_RUN_ID` visibility check (F16) | "every `github.event.*` value routed through `env:`" | inferred - justification: a lagging read would miss the very first detection; CTO F16 |
| compare 404 = not a descendant (F17) | "use the compare API: identical or ahead" | inferred - justification: one unresolvable SHA must not wedge refresh/close for 7 days; CTO F17 |
| Run-log notices (F7) | "the flip evidence bar (3 or more distinct SHAs in 30 days ...)" | inferred - justification: the stateless body leaves no countable trail otherwise; CTO F7 |
| Always-on mutation battery (F9) | "Mutation-verify the guards you add ... on a sandbox copy." | asked (default-suite placement inferred - justification: an opt-in battery rots; CTO F9) |
| Mutants M5-M13 beyond the four named | "Mutation-verify the guards you add" | inferred - justification: the added guards (marker table, apply-job leg, in-flight, truncation, 404, trigger visibility) are guards too; each has a pinned scenario |
| Wiring parse + two YAML mutants | "Assert by grep of the YAML that the workflow has no secrets/environment/terraform/dispatch" | asked (the parse and two mutants inferred - justification: a grep alone is satisfied by a stub; Guard 4) |
| Omit CODEOWNERS / `test-affected-paths.sh` / `suite-shard-legs.tsv` | "or files under another open PR" | asked |

### Split Assessment

- Subsystems touched: 4 - `.github`, `scripts`, `plugins`, `knowledge-base`
- Planned files: ~45 (about 30 are small committed fixture JSON files in the ten named + replay directories) | Estimated changed lines: ~1,600 (script ~450, suite ~450, fixtures ~350, YAML ~70, docs ~150, plan/spec artefacts excluded)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - over threshold, but ask 1 mandates ONE PR and no seam yields independently shippable halves (the workflow without the script is inert, the script without the workflow detects nothing, the runbook and ADR describe both); the fixture directories are the brief's own explicit request (ask 19), trimmed from the first draft by plan-review (builders replace the variant fixtures).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash plugins/soleur/test/apply-delivery-gap-follower.test.sh` exits 0 (minimum assertion floor met, every case ran at least one assertion) with every mutant landed and red (0 survivors, `MUTANT_FLOOR` equal to the table length). RED was observed first (Phase 0).
- [ ] `bash scripts/apply-delivery-gap.sh --self-test` prints `apply-delivery-gap self-test: ok` offline in under 5 s with `PATH=/usr/local/bin:/usr/bin:/bin`.
- [ ] R1, R2, R3 each yield exactly one row with class `evicted-before-start`; R4 yields zero rows and a close with `--reason completed`.
- [ ] The workflow file: triggers only `workflow_run` on the two exact `name:` strings, `types: [completed]`, `branches: [main]`; permissions exactly `contents: read`, `actions: read`, `issues: write`; concurrency group `apply-delivery-gap-follower`, `cancel-in-progress: false`; no `secrets.`, `environment:`, `terraform`, dispatch spelling; every action SHA-pinned; passes the linters listed in Phase 5.
- [ ] No `::error::` text echoes API stderr; every failure class has a distinct `apply_delivery_gap_<reason>` and a pinned scenario.
- [ ] The suite is registered and classified: `bash scripts/lint-orphan-test-suites.sh` is green, or the blocker is reported in the PR body per "Suite classification".
- [ ] The runbook section and the ADR-270 addendum exist; the addendum records the flip bar and the residuals; no remote-shell instruction anywhere.
- [ ] `lint-guard-contract.py` passes on this plan; `lint-infra-no-human-steps.py --changed --base origin/main` passes; `technical-ruling-gate.sh --branch ...` passes; markdownlint is clean on the plan, `tasks.md` and the runbook.
- [ ] No closing keyword adjacent to #10033 / #8167 / #9454 in the PR body or any commit; the body lists `Ref #9454`, `Ref #10033`, `Ref #8167`.
- [ ] `git diff --name-only origin/main...HEAD` contains none of: `.github/CODEOWNERS`, `scripts/lib/test-affected-paths.sh`, `scripts/suite-shard-legs.tsv`, either apply workflow, any AGENTS file, `.claude/rule-weakening-acks.txt`.

### Post-merge (observation, not a merge or ship gate)

- After the next natural completion of either apply workflow on main, `gh run list --workflow apply-delivery-gap-follower.yml --limit 3 --json conclusion,headSha,event` shows the follower ran (event `workflow_run`) and its log carries `apply_delivery_gap_summary workflows_read=2` with no `::error::apply_delivery_gap_`. No apply is dispatched to force this; the deterministic proof is the suite.

## Dependencies & Risks

- **Event delivery for pending-cancelled runs** is unverified (see Research Insights); mitigated by design and by the drift cron.
- **Suite classification** may need a declaration in a file under open PRs (#10744, #7390); ordered fallbacks are in "Suite classification".
- **GitHub API cost**: one reconcile makes about 2-4 list reads, a jobs read per row and per delivering candidate, a compare per (row, later success/in-flight) pair and 1-4 issue calls; the 10-page ceiling bounds a pathological window at 20 list calls.
- **Self-eviction**: a third pending follower run cancels the older pending one; harmless (every run is a full stateless read).
- **First-run caveat**: `workflow_run` workflows run only from the default branch's copy of the file, so the follower is inert until the PR merges; there is no pre-merge live run (by design: no dispatch trigger; fixture mode is the test seam).
- **Run records' lifetime**: a deleted or re-run cancelled run leaves no candidate; F13's close comment words this honestly.
- **Public issue content**: SHAs, run URLs, workflow names, integer minutes and a UTC time only.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty fails `deepen-plan` Phase 4.6; it is filled here (`aggregate pattern`).
- Do not give the follower a `workflow_dispatch` trigger "for testing": the ruling and the structural suite forbid it.
- The YAML must not contain the words `terraform`, `secrets.`, `environment:` or the dispatch spellings even in comments - the suite greps the raw text.
- Avoid `closes|fixes|resolves` near any issue number in the PR body, commits, runbook and ADR text for this change.
- `gh api` GET parameters go in the literal query string, never `-f/-F` (learning 2026-10-05).
- PyYAML reads a bare `on:` key as boolean `True`; the wiring leg must read `doc.get('on', doc.get(True))`.
- A diff-scope AC uses `origin/main...HEAD` (three dots), never the moving tip.
