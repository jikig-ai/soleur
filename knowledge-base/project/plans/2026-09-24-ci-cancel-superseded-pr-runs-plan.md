---
title: "ci: cancel superseded GitHub Actions runs when a PR gets new commits"
date: 2026-09-24
slug: ci-cancel-superseded-pr-runs
branch: feat-one-shot-cancel-superseded-pr-runs
issue: none
closes: none
pr: 8669
type: enhancement
priority: p2
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# ci: cancel superseded GitHub Actions runs when a PR gets new commits

## Overview

The spec lacks a valid `lane:`, so it defaulted to cross-domain (TR2 fail-closed).

Add one small pull_request-triggered workflow that, on every new push to a same-repo PR, finds
that PR's still-running or still-queued workflow runs whose commit is no longer the PR head and
cancels them, so superseded runs stop holding runners and the shared dev-Supabase mutex.

The selection logic lives in a bash + `jq` script under `.github/scripts/` with a pure `select`
mode, so it is fixture-tested offline by a new suite under `.github/scripts/test/` (auto-discovered
by `run-all.sh`, which the required `guard-script-fixture-tests` check runs on every PR).

No existing workflow's `concurrency:` block changes. `tenant-integration.yml` and
`vendor-pin-verify.yml` keep `cancel-in-progress: false`: that setting guards a **same-SHA**
cancellation (#5585 R3), and this workflow never cancels a run whose `head_sha` equals the PR's
current head, by construction.

## Problem Statement / Motivation

On 2026-09-23 the operator cancelled 17 queued or in-progress runs by hand. Every one had a
`head_sha` that was no longer its PR's head. They came from `tenant-integration.yml`,
`vendor-pin-verify.yml`, `infra-validation.yml`, `constraint-gates.yml`, `cla-evidence.yml`,
`cla.yml` ("CLA Assistant"), and CodeQL default-setup `dynamic` runs.

Per-workflow `concurrency: cancel-in-progress` cannot fix this class:

- CodeQL default setup has no YAML file to put a `concurrency:` block in.
- `tenant-integration.yml` / `vendor-pin-verify.yml` deliberately run `cancel-in-progress: false`,
  because a group-keyed cancel also fires on a same-SHA re-trigger and fails the required gate on
  the head SHA.
- `cla.yml` / `cla-evidence.yml` run on privileged `pull_request_target`, and the ledger records a
  decision to leave that run shape alone.
- `constraint-gates.yml` has its body parity-locked to the constraint-scaffold template, which
  carries no concurrency block.

PR #8566 (merged 2026-09-22) added per-PR concurrency blocks to five other workflows. The
2026-09-23 incident happened after it, in the workflows it could not reach. A reaper keyed on
`head_sha` reaches them without changing their files.

## Research Reconciliation — Spec vs. Codebase

| Claim (brief / ledger / research) | Reality (verified) | Plan response |
|---|---|---|
| tenant-integration competes for "the one shared dev-Supabase concurrency group" | The job-level group is per ref: `group: dev-supabase-${{ github.ref }}` (`tenant-integration.yml`, the `concurrency:` block above `cancel-in-progress: false`). What serializes runs across refs is the DB advisory lock in `scripts/dev-suite-mutex.sh`, held by a background `psql`. Release has two paths. (1) On a **graceful** `POST …/cancel`, GitHub still runs `if: always()` steps ([docs: status check functions — `always()` runs even when cancelled](https://docs.github.com/en/actions/reference/workflows-and-actions/expressions#always)), so the job's `Release dev-suite mutex` step (`if: always()`) runs and releases it. (2) If the step does not run (force-cancel, a runner kill, or the step itself failing), `dev-suite-mutex.sh`'s header documents the socket-death path: the holder's next chunked `pg_sleep(10)` result write fails and the xact lock releases within about 10-20 s. The tenant-integration comment above the release step says the step "cannot run" on cancellation, which contradicts (1). That is unverified either way until AC10 observes it. | Use `/cancel`, never `/force-cancel` (so path 1 is available). Cancelling a superseded in-progress run frees the cross-ref DB mutex (immediately via path 1, or within about 10-20 s via path 2) and the per-ref group slot the new head's run waits on. This is the largest win. AC10 records which path fired. |
| Ledger row `infra-validation.yml`: "no cancel: plan holds a backend state lock" (same wording for `apply-sentry-infra.yml`) | Every R2 backend sets `use_lockfile = false` (`apps/web-platform/infra/main.tf`, `apps/web-platform/infra/sentry/main.tf`, `infra/github/main.tf`, `apps/cla-evidence/infra/main.tf`, …: "R2 has no S3 conditional writes"). The PR-arm plan also runs `-refresh=false`. So no state lock exists for a cancel to strand. | Correct both ledger reasons to the true one: these workflows carry no qualifying self-cancel block. The `cancel` column stays `no`. The external reaper cancels them safely. |
| Ledger row `tenant-integration.yml`: "a mid-run cancel leaves fixture residue" | `apps/web-platform/scripts/run-migrations.sh` applies each migration with `psql --single-transaction --set ON_ERROR_STOP=1`, so a kill in the middle of an apply rolls back. Suite rows are scoped per run (fresh `randomUUID` grantees and delegations, per the tenant-integration comment). The same interruption already happens on every `timeout-minutes: 15` kill, and it happened 17 times during the manual cancel on 2026-09-23. | Record it as a named residual in the ADR-216 addendum: an interrupted suite may leave per-run test rows. Nothing to build. The per-ref drift probe already attributes drift. |
| Learnings research: "ADR-061 amendment documents mid-run-cancel residue" | False. `grep -i cancel` on ADR-061 finds no cancel text. Its only "residue" line is about re-applying an edited migration. | Disregarded. |
| Learnings research: "post synthetic statuses for required checks on cancelled runs" | Required checks are evaluated on the PR **head** SHA. This workflow only cancels runs on non-head SHAs, so their contexts never gate the PR. | Not needed. Stated in the ADR addendum so a reviewer does not re-raise it. |
| `pull_request_target` runs might carry `head_branch=main` / the base SHA | Checked live on #8666 and #8669: CLA Assistant and `cla-evidence` runs have `head_branch=<PR branch>`, `head_sha=<PR head>`, `pull_requests=[N]`. | Match them by `head_branch` + `head_repository.full_name`, the same way as `pull_request` runs. |
| CodeQL `dynamic` runs are addressable by PR | Checked live: `event=dynamic`, `head_branch=refs/pull/<N>/head`, `pull_requests=[]`, with two paths: `dynamic/github-code-scanning/codeql` and `dynamic/github-code-quality/codeql`. `GET /actions/runs?branch=refs/pull/8597/head` returns them (total=18). | Query the second branch key. Restrict `dynamic` to those two path prefixes (fail-closed, see Decisions). |
| The `status` filter is an enum the API validates | Checked live: `GET /actions/runs?branch=main&status=bogus` returns `{"total_count":0,"workflow_runs":[]}` with **no 422**. A misspelled status therefore selects nothing, silently (`hr-github-api-endpoints-with-enum`). | Do not query by `status=` at all: 2 unfiltered list calls (one per branch key), with status filtered in jq (rule 9). The summary still reports `listed=`. |

## Research Insights

**Premise Validation.** The cited predecessor, PR #8566 ("ci: collapse superseded PR workflow
runs"), is merged (2026-09-22T15:58:32Z). The files it touched are not the ones in the 2026-09-23
incident, so the gap this plan fills is real. There is no tracking issue. The draft PR #8669 is the
vehicle (`issue: none`). No existing workflow calls `/actions/runs/{id}/cancel` or `gh run cancel`.
`scheduled-actions-queue-health.yml` only *names* zombie cancellation as an operator hygiene step.
The live API shapes in the reconciliation table were probed on 2026-09-24.

**Property List (Phase 0.6b).**

- P1: when a same-repo PR gets a new head, its runs on older SHAs stop holding runners, the
  `dev-supabase-<ref>` group slot, and the dev-suite DB mutex, without an operator.
- P2: no run whose `head_sha` equals the PR's current head is ever cancelled, so the required
  gates on the head SHA are untouched (preserves #5585 R3).
- P3: no run outside this PR's PR-scoped events is ever cancelled. That excludes runs on the
  default branch and runs from `push`, `schedule`, `workflow_run`, `workflow_dispatch` and
  `merge_group`, runs of other PRs, and runs of fork branches that share the name.
- P4: a run triggered by an older push cannot cancel the runs of a newer push (race safety).
- P5: fork PRs and permission refusals degrade to a visible skip, not a red failure.
- P6: every execution states what it did: `listed` / `cancelled` / `skipped` (with reasons) /
  `failed`.

**Cut List.**

- Changing `cancel-in-progress` on tenant-integration / vendor-pin-verify → P1. That would cancel
  same-SHA runs (violates P2), and the brief forbids it. Cut.
- A `pull_request_target` trigger to reach forks → P1 for forks. That is a privileged trigger for a
  marginal gain: fork runs need maintainer approval anyway. P5 covers forks with a skip. Cut.
- A third-party action (`styfle/cancel-workflow-action`, `workflow_id: all`) → P1. It has no event
  filter (violates P3), it cannot see `refs/pull/N/head` CodeQL runs, and its own README points to
  native `concurrency:`. Plain `gh api` is about 30 lines. Cut (Wrapper-vs-curl check).
- Synthetic statuses for cancelled contexts → no property (non-head SHAs never gate). Cut.
- (Reversed at plan review.) `requested` was first cut as marginal. It is now included in rule 9's
  jq status set at zero cost, because listing no longer queries by status.

**Relevant files.**

- `scripts/pr-fanout-ledger.txt` + `plugins/soleur/test/pr-fanout-ledger.test.sh`: every
  workflow firing on PR `synchronize` needs a TAB-separated 5-column row. Test ids: A1 (row
  exists), A3 (jobs ceiling), A4 (paths), A4b (cancel=yes needs a `true` / ternary form **and** a
  group keyed on `github.event.pull_request.number` or `github.ref` … **and** no per-run token),
  A4c (only accepted spellings), A5 (consequence of at least 4 words; a `cancel=no` row must say
  `no cancel: <reason>`), and A6 (ternary groups match `ci.yml`). The new row is
  `cancel-superseded-pr-runs.yml	1	no	yes	<consequence>`.
- `.github/scripts/test/run-all.sh`: globs `test-*.sh`, must be **bash-only** (it gates every PR
  and runs on `merge_group`), `MIN_SUITES=12` floor ("Raise it when suites are added"), exit
  contract 0 / 1 / 128+N.
- Template for a `gh`-stubbed suite: `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`
  writes a stub to `$BIN/gh` (`cat > "$BIN/gh" <<'STUB'`) and prepends `$BIN` to `PATH`.
- Workflow lints that run in `ci.yml` and apply to any new workflow: actionlint via
  `scripts/lint-workflows.sh` (#7002 hang guard), `scripts/lint-workflow-step-env-refs.py` (a
  `run:` reading a variable nothing sets), `scripts/lint-workflow-errexit-capture.py`,
  `scripts/lint-orphan-test-suites.sh` (the `.github/scripts/test/` glob counts as a registration),
  and `scripts/lint-workflow-install-sites.sh` (not triggered: no installs).
- `plugins/soleur/test/ci-concurrency-key.test.sh` is scoped to `ci.yml` only (`CI_YML=`), so it is
  not affected.
- `plugins/soleur/test/c4-count-parity.test.sh` derives counts of heartbeat workflows, Resend
  emitters and monitor slugs. The new workflow adds none of these, so no count moves.
- Action pin to reuse: `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`
  (the same pin as in `tenant-integration.yml` and `pr-auto-close-scanner.yml`).
- Sibling shape: `pr-auto-close-scanner.yml` uses `runs-on: ubuntu-latest`, `timeout-minutes: 5`,
  and `group: pr-auto-close-scanner-${{ github.event.pull_request.number }}` with
  `cancel-in-progress: true`.

**Institutional learnings applied.**

- `2026-04-15-gh-jq-does-not-forward-arg-to-jq.md`: `gh --jq` does not forward `--arg`. The
  `select` stage therefore runs as standalone `jq --arg …` over the collected JSON, never as
  `gh api --jq` with arguments.
- ADR-216 (+ addendum 2026-09-14): growing the PR fan-out requires a ledger row that names its
  consequence. This workflow adds 1 job per PR push, in exchange for reaping N stale ones.
- `hr-github-api-endpoints-with-enum`: the silent zero on a bad status, verified above.
- `hr-github-app-auth-not-pat`: the workflow authenticates with the job's own `GITHUB_TOKEN`
  (`GH_TOKEN: ${{ github.token }}`), not a PAT and not a secret.

**External / marketplace.** functional-discovery found no community skill or agent.
`styfle/cancel-workflow-action` (981★) is the nearest pattern: branch + different SHA +
not-completed + created-before-self. It lacks an event filter and CodeQL coverage, and it is
self-deprecated in favour of `concurrency:`. This plan borrows its created-before-self race guard
(see Decisions).

## Proposed Solution

### Files to Create

1. `.github/workflows/cancel-superseded-pr-runs.yml`

   ```yaml
   name: Cancel superseded PR runs
   on:
     pull_request:
       types: [synchronize, reopened]
   permissions:
     actions: write        # list + cancel runs
     contents: read        # actions/checkout of .github/scripts
     pull-requests: read   # live PR head re-check (race guard)
   concurrency:
     group: cancel-superseded-pr-runs-${{ github.event.pull_request.number }}
     cancel-in-progress: true
   jobs:
     cancel-superseded:
       # Fork PRs and Dependabot-triggered runs get a read-only GITHUB_TOKEN: skip the job
       # (concludes `skipped`, never red). Dependabot opens same-repo PRs here (#8033, #8032).
       if: >-
         github.event.pull_request.head.repo.full_name == github.repository &&
         github.actor != 'dependabot[bot]'
       runs-on: ubuntu-latest
       timeout-minutes: 5
       steps:
         - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
           with:
             sparse-checkout: .github/scripts
             persist-credentials: false
         - name: Cancel this PR's runs on superseded head SHAs
           env:
             GH_TOKEN: ${{ github.token }}
             REPO: ${{ github.repository }}
             PR_NUMBER: ${{ github.event.pull_request.number }}
             EVENT_HEAD_SHA: ${{ github.event.pull_request.head.sha }}
             HEAD_REF: ${{ github.event.pull_request.head.ref }}
             HEAD_REPO: ${{ github.event.pull_request.head.repo.full_name }}
             DEFAULT_BRANCH: ${{ github.event.repository.default_branch }}
             SELF_RUN_ID: ${{ github.run_id }}
           run: bash .github/scripts/cancel-superseded-pr-runs.sh
   ```

   `head.ref` is controlled by the PR author. It reaches the script **only** through `env:` and is
   never interpolated into `run:` (the workflow-injection rule). The header comment must explain
   why `cancel-in-progress: false` elsewhere is unaffected (same-SHA vs. different-SHA). It must
   also carry the `scripts/pr-fanout-ledger.txt` pointer paragraph that siblings carry
   (`dependency-review.yml` lines 22-23 shape).

2. `.github/scripts/cancel-superseded-pr-runs.sh` (`set -euo pipefail`, bash + `jq` + `gh` only)

   - **`select` mode** (`cancel-superseded-pr-runs.sh select`): pure, no network. It reads a JSON
     array of run objects on stdin and takes its context from env (`HEAD_SHA`, `HEAD_REF`,
     `HEAD_REPO`, `PR_NUMBER`, `SELF_RUN_ID`, `SELF_CREATED_AT`, `DEFAULT_BRANCH`). It is
     implemented as **one standalone `jq -r` program**, with `--arg` for strings and
     `--argjson self_id "$SELF_RUN_ID"`, so the id comparison is numeric-to-numeric; a string
     `"123" != 123` would make rule 1 silently never fire. Output is **`@tsv`**, one row per run:
     `[decision, id, reason, event, name]`. `@tsv` escapes tab and newline inside fields, so a
     crafted workflow name cannot forge an extra row. Rules are evaluated in order, first match
     wins:

     | # | Condition | Decision / reason |
     |---|---|---|
     | 0 | `SELF_CREATED_AT` fails `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`, or `HEAD_SHA` fails `^[0-9a-f]{40}$` | `skip bad-context`, for every run |
     | 1 | any of `.id`, `.head_sha`, `.created_at`, `.event`, `.status` is null or missing; `(.path // "")` is used wherever `.path` is read | `skip malformed` |
     | 2 | `.id == $self_id` | `skip self` |
     | 3 | `.event` ∉ {`pull_request`, `pull_request_target`, `dynamic`} | `skip event` (push, schedule, workflow_run, workflow_dispatch, merge_group, issue_comment, …) |
     | 4 | `(.head_branch // "")` ∈ {`DEFAULT_BRANCH`, `refs/heads/<DEFAULT_BRANCH>`} | `skip default-branch` |
     | 5 | `.event == "dynamic"` and `(.path // "")` starts with neither `dynamic/github-code-scanning/` nor `dynamic/github-code-quality/` | `skip dynamic-path` (for example `dynamic/dependabot/dependabot-updates`, observed live) |
     | 6 | `.event == "dynamic"` and `.head_branch != "refs/pull/<N>/head"` | `skip branch` |
     | 7 | `.event` ∈ {pull_request, pull_request_target} and `.head_branch != HEAD_REF` | `skip branch` |
     | 8 | `.event` ∈ {pull_request, pull_request_target} and `(.head_repository.full_name // "") != HEAD_REPO` | `skip repo` |
     | 9 | `.status` ∉ {queued, in_progress, waiting, pending, requested} | `skip status` |
     | 10 | `.head_sha == HEAD_SHA` | `skip current-head` |
     | 11 | `.created_at >= SELF_CREATED_AT` (ISO-8601 Z strings compare lexicographically, and rule 0 guarantees the shape) | `skip too-new` |
     | 12 | otherwise | `cancel superseded` |

     Rule 4 comes *before* the branch rules, so it is reachable. A same-repo PR opened **from**
     `main` into another base has `HEAD_REF == DEFAULT_BRANCH`. Rule 7 would pass it, and without
     rule 4 its PR runs, whose `head_branch` is `main`, would be reaped, violating P3. Rule 1 is why rule 0 alone
     is not enough: a `"null"` `created_at` on a *run* would sort above an ISO self timestamp
     (`"n" > "2"`) and be skipped `too-new` (safe), but a null `head_sha` would pass rule 10's
     `!=`. Rule 1 makes every null fail closed in one place.

   - **default (run) mode**:
     1. Validate that the required env is non-empty. If not: `::error::` and exit 2.
     2. **Race guard A (newest-push check):** read
        `live=$(gh api "repos/$REPO/pulls/$PR_NUMBER" --jq .head.sha)` up to **3 times, 5 s
        apart**, stopping as soon as `live == EVENT_HEAD_SHA`. The retry absorbs API lag: the
        `synchronize` event can fire before the pulls endpoint reflects the new head. If it still
        differs after 3 reads, print
        `cancel-superseded-pr-runs: pr=#N event-head=<7> live-head=<7> — superseded by a newer push; the newer run reaps`
        and exit 0. Validate `live` against `^[0-9a-f]{40}$`; on mismatch, `::error::` and exit 2.
        Then set `HEAD_SHA=$live`.
     3. **Race guard B input:** `SELF_CREATED_AT=$(gh api "repos/$REPO/actions/runs/$SELF_RUN_ID" --jq .created_at)`.
        Validate it against the rule-0 ISO-8601 regex. On mismatch (including the literal string
        `null`), `::error::` and exit 2 before any listing. Rule 0 is the second line of defence
        for the same property.
     4. **List: 2 calls, one per branch key, no `status=` query filter.** Filtering status in jq
        removes the silent-zero hazard of a mistyped `status=` enum, which the API accepts
        without a 422 (verified above). For `branch` in (`$HEAD_REF`, `refs/pull/$PR_NUMBER/head`),
        run
        `gh api --paginate "repos/$REPO/actions/runs?branch=<urlencoded>&per_page=100" --jq '.workflow_runs[]'`
        and append the NDJSON to a temp file. URL-encode with `jq -rn --arg b "$branch" '$b|@uri'`.
        Then `jq -s 'unique_by(.id)'`. Rule 9 in `select` does the status filtering. Cost: one page
        per 100 runs the branch has ever had. That is bounded by the PR's lifetime pushes × about
        25 workflows, typically 1-5 pages, and far below `GITHUB_TOKEN`'s 1,000 requests/hour. No
        page cap: the oldest queued runs are exactly the zombies this workflow exists for.

        After listing, print `X-RateLimit-Remaining` once: read it from a final
        `gh api -i rate_limit` header, or `gh api rate_limit --jq .resources.core.remaining`. It is
        a diagnostic line in the log and the summary.

        A failed list call: `::error::` naming the branch, then exit 1, with no cancels. A partial
        listing is not a clean result. Classify the failure with the cancel classifier below, so a
        rate limit reads `failed:rate-limited`.
     5. Pipe the array to `select`.
     6. **Re-check the head immediately before the cancel loop.** Read the live head once more
        (single read, no retry). If it no longer equals `HEAD_SHA`, print
        `… head moved during listing (<7> -> <7>) — cancelling nothing; the newer run reaps` and
        exit 0 **without cancelling anything**. This covers A→B→A: a stale selection computed
        against B must not reap A's fresh runs.
     7. **Cancel, graceful only:** `POST …/actions/runs/{id}/cancel` and **never**
        `…/force-cancel`. A graceful cancel still runs `if: always()` steps; force-cancel skips
        them. That is load-bearing for tenant-integration's `Release dev-suite mutex` and
        `Re-probe dev-vs-main migration drift` steps. Invocation:
        `if resp=$(gh api -i -X POST "repos/$REPO/actions/runs/$id/cancel" 2>"$errf"); then … else … fi`.
        The `if` form is errexit-safe: `scripts/lint-shell-capture-exit.py` rejects a bare
        `x=$(cmd)` whose non-zero exit is a normal outcome. Classify by the status line
        `^HTTP/[0-9.]+ ([0-9]{3})` (verified 2026-09-24, gh 2.101.0: `HTTP/2.0 409 Conflict` as the
        first line of `-i` output). If there is none, fall back to stderr's `\(HTTP ([0-9]{3})\)`.

        | Response | Outcome |
        |---|---|
        | `202` | `cancelled` |
        | `409` / `404` | skipped `gone` (the run finished, was cancelled concurrently, or was deleted) |
        | `429`, or `403` whose body/stderr mentions `rate limit` | `failed:rate-limited` + `::error::` |
        | `403` whose stderr contains `Resource not accessible by integration` **and** `event == dynamic` | skipped `refused` + `::warning::` (AC10 measures whether this happens) |
        | `403` with `Resource not accessible by integration` on a `pull_request` / `pull_request_target` run | `failed:refused` + `::error::` (the token lost `actions: write`; this must be red, not a green check full of warnings) |
        | any other `403`, or anything else | `failed` + `::error::` |

        Before interpolating API-derived strings (workflow `name`, `display_title`) into
        `::warning::` / `::error::`, strip CR/LF with `${v//[$'\n\r']/}`. `display_title` is a PR
        title, so a crafted `\n::notice::` could otherwise spoof an annotation.
     8. **Summary (P6):** one line to stdout **and** to `$GITHUB_STEP_SUMMARY` (when set):
        `cancel-superseded-pr-runs: pr=#<N> head=<sha7> listed=<L> cancelled=<C> skipped=<S> failed=<F> reasons=<reason:count,...> ratelimit_remaining=<R>`,
        followed by one line per cancelled run (`id`, workflow name, event, `head_sha[0:7]`).
     9. Exit 1 if `failed > 0`, else 0.

   - Temp files: create them with `mktemp` and remove them with a `trap … EXIT` that the script
     owns. `scripts/lint-trap-tempfile-ownership.py` runs in `ci.yml`, so run it locally.
   - The 5 s retry sleep must be injectable (`CSPR_HEAD_RETRY_SLEEP`, default `5`) so the suite
     runs with `0`.

3. `.github/scripts/test/test-cancel-superseded-pr-runs.sh`: a bash-only fixture suite
   (`set -uo pipefail`, `PASS`/`FAIL` counters, a non-zero exit on any failure, and a
   minimum-assertions floor so `0 passed, 0 failed` is not green). Two layers:
   - **Selection layer:** run fixtures are synthesized inline with `jq -n` (no real run ids, per
     `cq-test-fixtures-synthesized-only`) and fed to `select`. The suite asserts the exact
     decision **and** reason per run, for **both sides of every rule** (see Test Scenarios).
   - **Orchestration layer:** a PATH-stubbed `gh`, modelled on
     `test-bump-inngest-bootstrap-pin.sh`, serves canned responses per URL, supports a
     per-call-index head sequence for the pulls endpoint, and records every invocation to a log.
     For errors it mirrors the real split measured above: the status line in `-i` output, the JSON
     body on stdout, `gh: … (HTTP NNN)` on stderr, and exit 1.

### Files to Edit

1. `scripts/pr-fanout-ledger.txt`
   - Add a row (TAB-separated). Suggested consequence text:
     `cancel-superseded-pr-runs.yml	1	no	yes	reaps this PR's queued/in-progress pull_request, pull_request_target and CodeQL-dynamic runs whose head SHA is no longer the PR head, freeing runners and the dev-Supabase mutex for the new head (never same-SHA, never main or push/schedule/dispatch); superseded runs of itself cancel per PR`
   - Correct the stale reasons on the `infra-validation.yml` and `apply-sentry-infra.yml` rows. Both say "plan holds a backend state lock", which is false
     (`use_lockfile = false` on every R2 backend). Replace with the true reason, keeping the
     literal `no cancel:` phrase that A5 requires. For example:
     `no cancel: the plan job's per-PR group carries no cancel-in-progress (R2 backends run use_lockfile=false, so no state lock is held); superseded PR runs are reaped by cancel-superseded-pr-runs.yml`.
     `apply-sentry-infra.yml` must keep its "sentry-destroy-required … ADR-032 ABI" lead text.
   - Header comment: add one paragraph after the `cancel =` definition. It says the column scores
     only a workflow's **own** concurrency. Superseded runs of every row (except fork PRs) are
     additionally reaped by `cancel-superseded-pr-runs.yml` by `head_sha`, which never touches a
     same-SHA run.
2. `.github/scripts/test/run-all.sh`: `MIN_SUITES=12` → `13`, and extend the provenance sentence
   ("… 13 suites, 2026-09-24, with test-cancel-superseded-pr-runs.sh").
3. `knowledge-base/engineering/architecture/decisions/ADR-216-machinery-ledger-and-filing-time-lever.md`:
   add `### Addendum 2026-09-24 — superseded runs are reaped by head SHA, across workflows`
   (see Architecture Decision below).

## Technical Considerations

### Decisions (technical forks resolved, not operator questions)

- **In-progress runs are cancelled for every allowlisted event, including tenant-integration and
  infra-validation.** The two "unsafe to cancel" ledger claims do not hold up. There is no state
  lock (`use_lockfile = false`), migrations apply `--single-transaction`, and the DB mutex
  is released by the job's own `if: always()` release step on a graceful cancel, or within about
  10-20 s by socket death otherwise (see the reconciliation table; AC10 observes which). The cancel
  is always the graceful `/cancel`, never `/force-cancel`. The in-progress tenant-integration run is the one holding the
  resource that delays other PRs, so excluding it would drop P1's main target. Residual: per-run
  test rows from an interrupted suite. This is the same state a timeout kill already produces, and
  the ADR addendum names it.
- **Race guards A + B together, and not either one alone.** Guard A (the live head equals the event
  head) stops a stale reaper from acting at all. Guard B (`created_at < self.created_at`) closes
  the TOCTOU window between guard A and the listing: a run for a push that lands *after* guard A
  was created after this run started, so it is skipped. The workflow-level
  `concurrency: cancel-in-progress: true` per PR also kills older reapers that are still queued.
  functional-discovery suggested dropping the created-before-self check. That is rejected, because
  it is exactly the guard for P4.
- **List by branch only (2 calls), filter status in jq.** This came out of plan review. A
  `status=` query parameter is an enum the API does not validate (a typo returns 0 runs with no
  422), and 4 statuses × 2 branches is 8 calls against 2. Rule 9 carries the status set, and a test
  pins it. It includes `requested`.
- **Graceful `/cancel` only, never `/force-cancel`.** `always()` steps (the mutex release, the
  post-section drift probe) must keep their chance to run.
- **Head re-read immediately before cancelling.** Guard A plus guard B leave one window: a push
  after the listing, where the selection was computed against a head that has since moved (A→B→A).
  Re-reading once more before the loop, and cancelling nothing if it moved, closes it.
- **`dynamic` is restricted to the two CodeQL path prefixes.** It is an allowlist, so an unknown
  future dynamic producer on `refs/pull/N/head` (for example a Copilot agent session) is
  `skip dynamic-path`, not cancelled.
- **Events are an allowlist**, not the brief's denylist. `push`, `schedule`, `workflow_run`,
  `workflow_dispatch` and also `merge_group` and `issue_comment` all fall through to `skip event`.
- **Branch matching also compares `head_repository.full_name`**. A fork branch with the same name
  as ours cannot match.
- **`pull_request`, not `pull_request_target`**. Fork PRs are skipped at the job `if:` (it concludes
  `skipped`). Same-repo PR authors already have push access, so running the PR's own copy of the
  script with `actions: write` grants nothing new.
- **No `paths:` filter**. The reaper must run on every PR push, because what it cancels is decided
  by other workflows' runs, not by this diff.

### Attack surface

- Token: the job's `GITHUB_TOKEN` scoped to `actions: write, contents: read, pull-requests: read`.
  No secrets, no Doppler.
- Untrusted input: `head.ref` (PR-author-chosen) goes only through `env:`, and the script passes
  it to `jq --arg` and URL-encodes it with `@uri`. It never reaches `eval` or an unquoted
  expansion.
- Fork PRs never run the job, and first-time-contributor runs need approval anyway.

### Performance

Per push: 2 PR/run reads + 8 list calls (+ pagination) + N cancels. That is well inside
`GITHUB_TOKEN`'s 1,000 requests/hour/repo. One `ubuntu-latest` job, about 20-40 s.

**Residual:** the reaper queues for a hosted runner like everything else. In a deep queue it starts
late, but it still reaps whatever has not finished.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-216** with `### Addendum 2026-09-24 — superseded runs are reaped by head SHA, across
workflows`. Decision: the fan-out ledger's `cancel` column scores self-cancellation. A single
repo-wide reaper (`cancel-superseded-pr-runs.yml`) handles cross-workflow supersession by
`head_sha`. The invariant every PR workflow now lives under is that **a run on a non-head SHA of a
same-repo PR may be cancelled at any point**. Same-SHA runs are never cancelled, which is why #5585
R3 still holds. Record the rejected alternatives (per-workflow `cancel-in-progress` flips, a
third-party action, `pull_request_target`, synthetic statuses) and the named residual
(per-run test rows from an interrupted tenant-integration suite). An addendum rather than a new
ADR: the ledger header already cites ADR-216 as its home.

### C4 views

No C4 impact. All three files were checked
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):

- (a) external human actors: none added. The operator was already the one cancelling by hand.
- (b) external systems: only GitHub's Actions REST API, which is already the `github` system
  element.
- (c) containers / data stores: none.
- (d) access relationships: none change.

`model.c4`'s derived cardinalities ("check-ins from N workflows", monitor and Resend counts) are
unaffected: no heartbeat, no Resend, no monitor slug. The work phase MUST back this by running
`bash plugins/soleur/test/c4-count-parity.test.sh` green.

### Sequencing

The ADR addendum ships in this PR.

## User-Brand Impact

- **If this lands broken, the user experiences:** the operator-founder's PRs wait longer for
  required checks, or, in the worst case, a head-SHA required run gets cancelled and shows a red
  required gate until "Re-run". No end-user product surface is involved.
- **If this leaks, the user's workflow is exposed via:** nothing new. The job holds only its own
  `GITHUB_TOKEN` (actions write on this repo). It reads no secrets and runs only for same-repo
  PRs, whose authors already have write access.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: CI-hygiene workflow on the GitHub Actions control plane; touches no product runtime, user data, credentials, or sensitive workflow path (the filename matches none of preflight Check 6's workflow tokens).`

## Observability

```yaml
liveness_signal:
  what: "one `Cancel superseded PR runs` check run per same-repo PR synchronize/reopened, visible on the PR's checks list and via the Actions workflow page"
  cadence: "per PR push"
  alert_target: "the PR author (red non-required check on the PR) — the operator reads PR checks as part of ship"
  configured_in: ".github/workflows/cancel-superseded-pr-runs.yml"

error_reporting:
  destination: "GitHub Actions check run + $GITHUB_STEP_SUMMARY on the PR"
  fail_loud: "`::error::` annotation and a red check when a list call fails or any cancel returns a status other than 202/409/403; the summary line `cancel-superseded-pr-runs: … failed=<F>` states the count"

failure_modes:
  - mode: "listing fails (GitHub API 5xx / auth)"
    detection: "script exits 1 with `::error::` naming branch+status; check run red on the PR"
    alert_route: "PR checks list (non-required, so it never blocks merge)"
  - mode: "token cannot cancel a run class (e.g. CodeQL dynamic returns 403)"
    detection: "`::warning::` per refused run + `refused:<n>` in the summary reasons"
    alert_route: "PR check annotations; recurring refusals are a follow-up to drop that class"
  - mode: "selection regression cancels a head-SHA run"
    detection: "fixture suite `.github/scripts/test/test-cancel-superseded-pr-runs.sh` (required via guard-script-fixture-tests) pins `skip current-head` (S10); at runtime the summary lists every cancelled run's head_sha[0:7], which must never equal `head=`"
    alert_route: "required check red on the offending PR before merge"
  - mode: "listing silently returns nothing (bad branch key / encoding)"
    detection: "suite O5 asserts the exact 2 list URLs (no status= filter, so no enum typo class); summary prints `listed=` and `ratelimit_remaining=`"
    alert_route: "required check red on the offending PR"

logs:
  where: "GitHub Actions run logs + step summary for the workflow `Cancel superseded PR runs`"
  retention: "repository Actions log retention (default 90 days)"

discoverability_test:
  command: "curl -s https://api.github.com/repos/jikig-ai/soleur/actions/workflows/cancel-superseded-pr-runs.yml"
  expected_output: "\"state\": \"active\""
```

## Guard Contract

The deliverable is a destructive actor (it cancels runs), so its safety envelope is written as a
guard with a design-derived mutation matrix. The fixture suite is the instrument that checks it.

### Guard 1 — reaper never cancels a current-head, foreign, or newer run

**Property.** Every cancel POST the script issues targets a run whose event is in
{pull_request, pull_request_target, dynamic CodeQL}, whose branch key and head repository are this
PR's, whose `head_sha` differs from the PR head read **immediately before the cancel loop**, and
whose `created_at` is earlier than the reaper's own run.

**Assembly.** There is exactly one chokepoint: every cancel is issued by the run-mode loop, which
iterates only over `select` output rows whose first field is `cancel`, and that loop is gated by
the pre-cancel head re-read. `select` is the only producer of `cancel` rows (one jq program). Its
inputs are the 2 list calls, deduped, plus the env context validated in run-mode steps 1-3.
Nothing else in the script, and nothing in the workflow, calls `…/cancel`. Suite O13 asserts that
every logged cancel URL comes from a `select` row id, and that no `force-cancel` appears.

**Mutation matrix:**

| # | Mutation (derived from the property, not the code) | Expected |
|---|---|---|
| 1 | Rule 10 compares `!=` instead of `==` (the current head becomes cancellable) | RED (S10) |
| 2 | **Dispatch:** `select` replaced by `cat >/dev/null`, so the loop sees 0 rows, cancels nothing and exits 0 | RED (assertion floor + S1..S12 expect rows) |
| 3 | **Second member:** the jq program ends in `first(...)` or `limit(1; …)`, so only the first row is decided | RED (S12 expects 4 rows in order) |
| 4 | **Order/window (reorder, not delete):** the pre-cancel head re-read is moved *before* the listing, which is the same code, but the window it guards is now uncovered | RED (O4: head moves between list and cancel) |
| 5 | Rule 4 moved after rule 7 (the default-branch skip becomes unreachable) | RED (S4) |
| 6 | Rule 0's regex loosened to `.+`, so `"null"` passes and guard B fails open | RED (S0a) |
| 7 | `--argjson self_id` → `--arg self_id` (rule 2 never matches) | RED (S2) |
| 8 | The cancel URL changed to `/force-cancel` | RED (O13) |

**Harness rows.** Suite edits that must drive it RED: (a) the `gh` stub stops logging calls, so
O5/O13 must fail on an empty log rather than pass vacuously; (b) the PASS/FAIL counter is never
incremented, so the floor fires. Must-PASS non-canonical input: H7 (extra fields, reordered keys,
2-page pagination). It must stay GREEN, proving the suite does not reject everything.

**Anchor.** The suite, the script and the workflow change in one diff, so a weakening that edits
both a rule and its fixture passes the suite. The outside anchor is the required
`guard-script-fixture-tests` check plus CODEOWNERS review of the workflow (`/.github/workflows/ @deruelle`). `.github/scripts/` has no CODEOWNERS row, a gap this plan acknowledges and does not widen. The
`.github/workflows/` change also makes the PR UNTRUSTED-CI, so it merges only through required
checks (AC11), never by admin override.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `.github/workflows/cancel-superseded-pr-runs.yml` exists with exactly the triggers
  `pull_request: types: [synchronize, reopened]`, and top-level `permissions:` of exactly
  `{actions: write, contents: read, pull-requests: read}`. Checked with
  `python3 -c 'import yaml,sys; d=yaml.safe_load(open(".github/workflows/cancel-superseded-pr-runs.yml")); print(d[True], d["permissions"])'`
  (PyYAML parses the `on:` key as `True`).
- [ ] AC2: the job `if:` is `github.event.pull_request.head.repo.full_name == github.repository &&
  github.actor != 'dependabot[bot]'`, and every `uses:` is SHA-pinned (`grep -nE 'uses: [^@]+@[0-9a-f]{40}' …` matches every `uses:`
  line).
- [ ] AC3: no `${{ github.event.pull_request.head.ref }}` (or any `github.event.*` expression)
  appears inside a `run:` body. They appear only under `env:`.
- [ ] AC4: `bash .github/scripts/test/test-cancel-superseded-pr-runs.sh` exits 0, with its
  assertion floor met, and `bash .github/scripts/test/run-all.sh` exits 0 with `MIN_SUITES=13`.
- [ ] AC5: `bash plugins/soleur/test/pr-fanout-ledger.test.sh` exits 0. A1 / A3 / A4 / A4b /
  A4c / A5 pass for the new row (`cancel=yes`), and for the edited `infra-validation.yml` /
  `apply-sentry-infra.yml` rows.
- [ ] AC6: the workflow lints are clean: `bash scripts/lint-workflows.sh`,
  `python3 scripts/lint-workflow-step-env-refs.py`, `python3 scripts/lint-workflow-errexit-capture.py`,
  `python3 scripts/lint-trap-tempfile-ownership.py`, and `bash scripts/lint-orphan-test-suites.sh`.
  Use the invocation forms `ci.yml` uses, verified at work time.
- [ ] AC7: `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0 (this backs "no C4 impact").
- [ ] AC8: the ADR-216 addendum exists
  (`grep -n '^### Addendum 2026-09-24' knowledge-base/engineering/architecture/decisions/ADR-216-*.md`
  returns 1 line).
- [ ] AC9: `git diff origin/main...HEAD --stat -- .github/workflows/` lists **only**
  `cancel-superseded-pr-runs.yml`. No other workflow file changes, so the `cancel-in-progress` of
  tenant-integration / vendor-pin-verify is byte-identical.
- [ ] AC10 (live, on this PR): push a second commit to #8669 while the first commit's runs are
  still queued or in progress. The new workflow runs from the PR's own file. Its log shows
  `cancelled=<C>` with C ≥ 1. Then
  `gh api "repos/jikig-ai/soleur/actions/runs?branch=feat-one-shot-cancel-superseded-pr-runs&status=cancelled&per_page=50" --jq '.workflow_runs[].head_sha' | sort -u`
  shows only superseded SHAs, never the new head. No run on the new head concludes `cancelled`.
  Record whether CodeQL `dynamic` cancels returned 202 or 403 (`reasons=`), and paste the summary
  line into the PR body. The first commit's diff touches no isolation surface, so tenant-integration's
  heavy job is skipped and the mutex path is not exercised by AC10. The mutex-release path (1 vs 2
  in the reconciliation table) is recorded opportunistically: the first time the reaper cancels an
  in-progress `Tenant integration` run, read that run's `Release dev-suite mutex` step conclusion
  with `gh run view <id> --json jobs --jq '.jobs[].steps[] | select(.name=="Release dev-suite mutex") | .conclusion'`
  and note it on the ADR-216 addendum. Also: `grep -c force-cancel .github/scripts/cancel-superseded-pr-runs.sh`
  prints `0`.
- [ ] AC11: the PR merges through the normal required-checks path. `.github/workflows` changes make
  it UNTRUSTED-CI for admin merge, so **never `gh pr merge --admin`**.

### Post-merge

- [ ] AC12: `curl -s https://api.github.com/repos/jikig-ai/soleur/actions/workflows/cancel-superseded-pr-runs.yml`
  prints `"state": "active"`.
- [ ] AC13: on the next same-repo PR synchronize after merge,
  `gh run list --workflow cancel-superseded-pr-runs.yml --limit 3 --json conclusion,event` shows a
  `success` conclusion with `event: pull_request`.

## Test Scenarios

**Selection layer** (`select`). Fixtures are synthesized with `jq -n`. Every case asserts
**decision and reason**. Each rule has a row that fires it *and* a row that sits one field away
and must pass through to the next rule (a "one-sided" rule is untested on its other side).

| # | Rule | Fires (expected) | Passes through (expected) |
|---|---|---|---|
| S0a | 0 | `SELF_CREATED_AT="null"` → every run `skip bad-context` | valid ISO → normal decisions |
| S0b | 0 | `SELF_CREATED_AT=""` → `skip bad-context` | — |
| S0c | 0 | `HEAD_SHA` 39 hex chars, or uppercase → `skip bad-context` | 40 lowercase hex → normal |
| S1 | 1 | one row each for `id`, `head_sha`, `created_at`, `event`, `status` null or absent → `skip malformed` (never `cancel`) | all present → continues |
| S1p | 1 / 5 | `dynamic` with `path` absent → `skip dynamic-path` via `(.path // "")`, not a jq error | `pull_request` with `path` absent → still decided by rules 7-12 |
| S2 | 2 | `.id == self_id` with a numeric id from `--argjson` → `skip self` | an id differing by 1 → continues (H5 proves that `--arg` would break it) |
| S3 | 3 | `push`, `schedule`, `workflow_run`, `workflow_dispatch`, `merge_group`, `issue_comment` (one row each; same branch, superseded SHA) → `skip event` | `pull_request`, `pull_request_target`, `dynamic` → continue |
| S4 | 4 | **Reachable form:** `HEAD_REF=main` (a same-repo PR opened *from* `main`), a `pull_request` run with `head_branch=main`, superseded SHA → `skip default-branch` | same fixture with `DEFAULT_BRANCH=trunk` → `cancel superseded` |
| S4r | 4 | `head_branch=refs/heads/main` → `skip default-branch` | — |
| S5 | 5 | `dynamic` + `dynamic/dependabot/dependabot-updates` → `skip dynamic-path`; `dynamic/copilot-swe-agent/x` → `skip dynamic-path` | `dynamic/github-code-scanning/codeql` and `dynamic/github-code-quality/codeql` → continue to `cancel superseded` |
| S5b | 5 | prefix trap: `dynamic/github-code-scanning-evil/x` → `skip dynamic-path` (the prefix includes the trailing `/`) | — |
| S6 | 6 | `dynamic` on `refs/pull/<OTHER>/head` → `skip branch` | `refs/pull/<N>/head` → continue |
| S6b | 6 | `dynamic` on `refs/pull/<N>0/head` (N=12 vs 120; exact match, not prefix) → `skip branch` | — |
| S7 | 7 | `pull_request` with a different `head_branch` → `skip branch` | same branch → continue |
| S8 | 8 | same `head_branch`, fork `head_repository.full_name` → `skip repo`; `head_repository` absent → `skip repo` | same repo → continue |
| S8t | 8 | `pull_request_target` from a fork with a same-named branch → `skip repo` | same-repo `pull_request_target` (the CLA shape, `pull_requests=[N]`) → `cancel superseded` |
| S9 | 9 | `completed`, `action_required` → `skip status` | `queued`, `in_progress`, `waiting`, `pending`, `requested` → `cancel superseded` (one row each) |
| S10 | 10 | the current head SHA in each of the five statuses → `skip current-head` (**P2**) | SHA differing in the last char → `cancel` |
| S11 | 11 | `created_at == SELF_CREATED_AT` → `skip too-new`; `created_at` 1 s later → `skip too-new` (**P4**) | 1 s earlier → `cancel superseded` |
| S12 | order | **second-member row:** `[cancellable, head-SHA, cancellable, self]` → exactly `cancel, skip current-head, cancel, skip self`. This proves the program does not stop at the first member | — |
| S13 | output | a run whose `name` contains a TAB and a newline → still exactly one output row, escaped (`@tsv`) | — |

**Orchestration layer** (stubbed `gh`, with `CSPR_HEAD_RETRY_SLEEP=0`):

| # | Scenario | Expected |
|---|---|---|
| O1 | the pulls endpoint returns the old head 3 times | exit 0, a "superseded by a newer push" line, **3** pulls reads in the log, **zero** list and cancel calls |
| O2 | the pulls endpoint returns old, old, then the event head (API lag) | proceeds; 3 pulls reads before the list |
| O3 | **A→B→A:** event head A; guard-A reads return A; the list returns runs for B (older) and for a first A push; the pre-cancel re-read returns A | only the B runs are cancelled; the first-A runs are `skip current-head` |
| O4 | **head moves during listing:** guard-A reads A; the pre-cancel re-read returns C | exit 0, "head moved during listing", **zero** cancel calls |
| O5 | the list call set | exactly 2 list URLs: `branch=<HEAD_REF urlencoded>` and `branch=refs%2Fpull%2F<N>%2Fhead`, **neither** carrying `status=` (sorted-set compare against the log) |
| O6 | the same run returned by both branch queries | cancelled once (dedupe) |
| O7 | cancel responses 202 / 409 / 404 | `cancelled` / `gone` / `gone`, exit 0 |
| O8 | 403 + `Resource not accessible by integration` on a `dynamic` run | skipped `refused`, `::warning::`, exit 0 |
| O9 | 403 + `Resource not accessible by integration` on a `pull_request` run | `failed:refused`, `::error::`, exit 1 |
| O10 | 429; and 403 with `API rate limit exceeded` | `failed:rate-limited`, exit 1 |
| O11 | 500 | `failed`, exit 1 |
| O12 | a list call failure (500 on page 1) | `::error::`, exit 1, **zero** cancel calls |
| O13 | the cancel URL shape | every cancel call ends in `/cancel`; **no** call contains `force-cancel` |
| O14 | `GITHUB_STEP_SUMMARY` set / unset | the summary line (with `ratelimit_remaining=`) is written / stdout only, no error |
| O15 | missing env (`PR_NUMBER=`); self `created_at` returns `null`; live head `null` | exit 2 with `::error::`, zero list calls |

**Harness rows** (the suite must not be satisfiable by a vacuous `select` or a vacuous stub).
Run each once at work time and record the result in the PR body:

- H1: swap `select` for `cat >/dev/null`. The suite goes RED on the assertion floor.
- H2: flip rule 10 to `!=`. RED on S10.
- H3: delete rule 11. RED on S11. Delete rule 0. RED on S0a.
- H4: move rule 4 after rule 7. RED on S4.
- H5: change `--argjson self_id` to `--arg self_id`. RED on S2.
- H6: remove the pre-cancel head re-read. RED on O4.
- H7: must-PASS non-canonical input. Run objects with extra unknown fields, a different key
  order, and `per_page` paging split across 2 pages still produce identical decisions.

## Success Metrics

- After merge, superseded-SHA runs of same-repo PRs no longer need operator cancellation. The
  hygiene-step count in `scheduled-actions-queue-health.yml` output for superseded runs trends to 0.
- The median wait of `tenant-integration-required` on isolation-surface PRs with rapid pushes
  drops, because the old run no longer holds the `dev-supabase-<ref>` slot.

## Dependencies & Risks

- **CodeQL `dynamic` cancellation may be refused (403) for `GITHUB_TOKEN`.** Unknown until AC10.
  It is handled as `skip refused` + `::warning::`, never red. If it is always refused, a follow-up
  can drop the `dynamic` arm of rule 3, but only after a measured AC10 result.
- **Hosted-runner queueing delays the reaper itself.** Accepted; it still reaps late.
- **Per-run test-row residue from an interrupted tenant-integration suite.** Accepted and named in
  the ADR addendum (the same state a `timeout-minutes` kill produces).
- **A PR that is one push behind at execution time is a no-op** (guard A, plus the pre-cancel
  re-read). A newer reaper handles it.
- **Named residual: runs for old SHAs that GitHub creates late** (CodeQL `dynamic` runs, and
  re-runs of old runs, whose `created_at` is later than the reaper's) are skipped `too-new` by
  rule 11. They are only reaped by the next push's reaper. This is a gap in coverage, not in
  safety.
- **A same-repo PR opened *from* the default branch** is reaped of nothing (rule 4 skips every
  run on `main`). This fails safe by design.
- **The tenant-integration comment says the release step "cannot run" on cancellation.** GitHub
  docs say `always()` steps run when a run is cancelled. Whichever is true, the socket-death path
  still releases the lock within about 10-20 s. The discrepancy is recorded for AC10, not fixed
  here (that file stays untouched, per AC9).

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Flip `cancel-in-progress: true` on tenant-integration / vendor-pin-verify | Cancels same-SHA re-triggers and fails the head-SHA required gate (#5585 R3). The brief forbids it. |
| Add `concurrency:` blocks to cla / cla-evidence / constraint-gates / infra-validation | Privileged-trigger run shape is kept on purpose, `constraint-gates` is parity-locked to its template, and CodeQL dynamic has no file. |
| `styfle/cancel-workflow-action` with `workflow_id: all` | No event filter (would cancel push / dispatch runs on the branch), no `refs/pull/N/head` coverage, self-deprecated, and a third-party action holding `actions: write`. |
| `pull_request_target` trigger (reaches forks) | Privileged trigger for a marginal gain. Fork runs already need approval. |
| Post synthetic statuses for cancelled contexts | Non-head SHAs never gate the PR. |

No deferrals, so no tracking issues are needed.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed (partial)
**Assessment:** CI-hygiene workflow on the GitHub Actions control plane. The risks are the
selection correctness (P2 / P3 / P4) and the cancellation safety of in-progress stateful runs,
both resolved in Decisions.

The CTO and spec-flow findings reached this plan as a consolidated list relayed by the pipeline
lead: unfiltered 2-call listing, a pre-cancel head re-read with A→B→A, graceful cancel only,
Dependabot skip, null fail-closed with `--argjson` and `@tsv`, a reachable default-branch rule,
and one-sided rule scenarios. All of them are applied above.

The scoped advisor consult ran directly. It contributed the guard-B fail-open on a `"null"`
timestamp, status-line classification, and 403 narrowed to dynamic runs. All applied.

No other domain is relevant: no user-facing surface, data, legal, or cost surface is touched
beyond one ubuntu-latest job per PR push.

## Open Code-Review Overlap

None. Checked 2026-09-24: the open `code-review` issues (up to 200) were searched with
`jq … contains($path)` for every planned path: the new workflow, the script, the test,
`scripts/pr-fanout-ledger.txt`, `.github/scripts/test/run-all.sh`, and `ADR-216`. No matches.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits
  the threshold will fail `deepen-plan` Phase 4.6. It is filled here (`none` + reason).
- `gh api --jq` does not accept `--arg`. All selection runs through standalone `jq`.
- `GET /actions/runs?status=<typo>` returns 0 runs with no error, which is why listing never
  passes `status=` (status is filtered in jq, rule 9).
- Never `POST …/force-cancel`: it skips `if: always()` steps, including tenant-integration's mutex
  release. Suite O13 pins that no call contains `force-cancel`.
- `gh api` error shape, **verified 2026-09-24 with gh 2.101.0** by POSTing cancel to an already
  completed run (a no-op: 409), and to run id 1 (404):
  - rc=1.
  - **stdout** carries the JSON body, e.g.
    `{"message":"Cannot cancel a workflow run that is completed.",…,"status":"409"}`.
  - **stderr** carries `gh: Cannot cancel a workflow run that is completed. (HTTP 409)` (and
    `gh: Not Found (HTTP 404)` for the 404).

  Parse the status from stderr's `\(HTTP ([0-9]{3})\)`, falling back to the body's `.status`.
  Treat 404 like 409 (`gone`). The stub in the orchestration test must emit exactly this split:
  body on stdout, `gh: … (HTTP NNN)` on stderr, and exit 1.
- The workflow runs from the PR's own copy on `pull_request`, so AC10 exercises the real file
  before merge.
- Never `gh pr merge --admin` on this PR (UNTRUSTED-CI: `.github/workflows` changed).
