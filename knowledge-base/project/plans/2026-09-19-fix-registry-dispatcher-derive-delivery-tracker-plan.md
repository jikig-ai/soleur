---
title: "fix: registry-host-replace dispatcher derives the delivered change and its tracker from the push instead of hard-coding #7555/#7556"
date: 2026-09-19
slug: fix-registry-dispatcher-derive-delivery-tracker
branch: feat-one-shot-8279-dispatcher-derive-tracker
issue: 8279
closes: [8279]
type: fix
priority: p3-low
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
---

## Overview

`.github/workflows/registry-host-replace-dispatch.yml` fires on every push to `main` whose rendered `cloud-init-registry.yml` bytes differ, but three of its operator-facing strings are frozen to the change that introduced it: the dispatch `reason` names `#7555 / ADR-190 — zot HTTP deadlines`, the refusal artifact asserts `the #7555 deadline change is NOT live`, and both the refusal artifact and the failed-apply comment post to issue #7556. Every later delivery therefore records its verdict on a tracker that is not waiting for it, with a sentence about a change it did not carry. This plan derives the delivered change from the push itself and posts each verdict where the delivery is actually tracked.

The delivery on 2026-09-18 (PR #8272, `err_redact_rev` for #7960) is the measured instance: had its preflight refused, the refusal would have landed on #7556 (the #7555 zot-deadline soak) saying the deadline change was not live, while #7960 — the tracker actually waiting — got nothing. PR #8272's plan worked around it with an operator-posted pointer comment.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed); no `spec.md` exists for this branch because the pipeline entered at `plan`.

## Problem Statement / Motivation

The dispatcher's whole purpose (ADR-169 amendment 2026-08-16) is that a merged `cloud-init-registry.yml` change never sits inert and unowned. Its refusal artifact exists so "a refusal must never be only a red run nobody owns" (learning 2026-08-17). Both properties are only as good as WHERE the artifact lands and WHAT it says:

- **Wrong tracker.** `gh issue comment 7556` at two sites (the failed-apply comment in the poll step and the refusal artifact step). #7556 is a soak follow-through for one specific change; it will close when that soak passes, after which every future refusal posts to a closed issue.
- **False text.** `the #7555 deadline change is NOT live` is a claim about a change that has been live since 2026-08-19 (run 32280053575). For any later delivery the sentence is false, and the dispatch `reason` recorded in the apply's audit trail (`(#7555 / ADR-190 — zot HTTP deadlines)`) misattributes which change the host is carrying.
- **Stale verification pointer.** `Verification is enrolled on #7556 and runs from Better Stack` and `#7556 remains the authority` describe the #7555 soak, not the delivery in hand.

Hard-coding the introducing issue is the same class as learning 2026-08-16 ("every number I inherited was stale"): the number looked established because it arrived with the mechanism.

## Proposed Solution

Three changes, one new helper, one new test suite.

### 1. A derivation helper: `scripts/registry-delivery-change.sh`

A read-only bash helper that answers "which merged change(s) does this run deliver?" from the same inputs the delta gate already has — the delivery watermark (`BEFORE_SHA`, head of the last successful run) and `github.sha` (`AFTER_SHA`). It prints `key=value` lines that the workflow appends to `$GITHUB_OUTPUT`:

```text
range=proven|unproven          # proven ancestor range / degraded to [after] only
range_note=<why unproven>      # empty when proven
commits=<sha> <sha>            # candidate commits (oldest -> newest) that touched the path in range
prs=<n> <n>                    # unique PR numbers attributed to those commits, oldest -> newest
unattributed=<sha>             # candidates with no PR (direct push, no "(#N)" suffix)
summary=PR #8272 (fix(7960): give the registry heartbeat a positive Phase-B delivery field …); PR #…
```

Algorithm (each numbered arm is a test case in `tests/scripts/test-registry-delivery-change.sh`):

1. `--before` empty (no watermark) → candidates = `[after]`, `range=unproven`, note `no watermark`.
2. `GET repos/{r}/compare/{before}...{after}` **with no paging parameters** — the 250-commit cap in step 3 is the contract only when neither `page` nor `per_page` is passed; adding `per_page` switches the endpoint to 30-per-page pagination and `.commits` silently becomes page 1 (Kieran P1-8). rc≠0, or `.status` not in `ahead|identical` → candidates = `[after]`, `range=unproven`, note names the status/rc. `identical` (measured: `status=identical, total_commits=0, commits=[]`) is a proven range with zero commits and falls through to step 4's empty-intersection arm — no third enum value.
3. `.total_commits > 250` → candidates = `[after]`, `range=unproven`, note `compare .commits capped at 250`. (The compare API returns at most 250 commits without paging params; the delta gate already treats its 300-file cap the same way — as unproven, never as "nothing".)
4. Range set = `.commits[].sha`. Path-touching set = `GET repos/{r}/commits?sha={after}&path={path}&per_page=100` `.[].sha` (explicit `per_page=100`; the default is 30). Candidates = path-touching ∩ range, ordered oldest→newest. **Empty intersection on a proven range** (the gate's ≥300-file arm when the config was in fact untouched; a manual re-fire to recover a dark host; this PR's own registration push) → `range=proven`, `range_note=no commit in range touched <path>`, `commits=`, `prs=` EMPTY, `summary=the cloud-init-registry.yml user_data at <after7> (unchanged since the delivery watermark <before7>)`. It does NOT fall back to `[after]`: attributing to whatever merged last would post "PR #N is NOT live" on a PR that never touched the config (spec-flow P1-4). The workflow's targets are then the `tracker` input or the issue-create fallback. **This arm also absorbs a manual re-fire at the watermark SHA** (`identical`, reachable on `workflow_dispatch` where `deliver=true` is unconditional): the summary names the SHA and the watermark, never a PR (Kieran P1-4/P1-5).
5. Cap candidates at a named constant `MAX_LOOKUPS=10` (not a flag): keep the newest 10, note the truncation. Bounds API calls on a pathological range; `per_page=100` on the path listing is the outer bound.
6. Per candidate, through one function `resolve_pr_for_sha` (the shape the three existing single-SHA resolvers could later adopt — CTO advisory): `GET repos/{r}/commits/{sha}/pulls` → `.[0].number // empty` (verbatim from `reusable-release.yml`; for a default-branch commit the endpoint returns the PR that introduced it, so a merged-preference defends against a case the API excludes); validate `^[0-9]+$`. Empty → fall back to the squash-subject suffix `grep -oP '\(#\K\d+(?=\))'` on the commit's first message line (verbatim from `.github/workflows/reusable-release.yml`); still empty → `unattributed`. The subject comes from the `commits?path=` response (`.commit.message` first line) or, on the `[after]`-only arms, from `GET repos/{r}/commits/{after}`. The subject is the first message line with CR/LF stripped, verbatim (a squash subject keeps its `(#N)` suffix — truthful, and no cosmetic strip). Rebase-merged PRs carry no `(#N)`, so on that method attribution rests on `/pulls` alone — T1's fixture subject carries NO suffix so the `/pulls` path is proven by itself.
7. Dedupe `prs` preserving first-seen order (a merge-commit PR contributes several branch commits that all resolve to one PR; `commits?path=` applies history simplification and omits the merge commit itself, so the subject shown is the newest BRANCH commit's, not the PR title — measured on #6326, do not "fix" it). `summary` = one `PR #N (<subject of the newest commit attributed to N>)` per PR, then one `commit <sha7> (<subject>)` per unattributed commit, joined by `; `. If everything is unattributed and the range is unproven the summary still names the SHA, so no arm produces an empty description.

Exit contract: **0 on every arm the API can produce** — a derivation failure degrades to `[after]`-only with `range=unproven`; it never blocks the delivery and never fails the job. Exit 2 on usage errors (missing `--repo`/`--after`); exit 1 with a `::error::` naming the seam when `REGISTRY_DELIVERY_GH_CMD` is set under `GITHUB_ACTIONS` — the same production-path guard and exit `scripts/registry-replace-preflight.sh` applies to `REGISTRY_PREFLIGHT_RUNS_CMD`. No other seams. A hung API call is bounded by the workflow step's own `timeout-minutes: 5`, not by the helper.

Verified against the live API on 2026-09-19 (this plan's Research Insights): `GET commits/f5ad4639…/pulls` returns `{number: 8272, merged_at: 2026-09-18T13:46:53Z}`; `GET commits?sha=f5ad4639…&path=apps/web-platform/infra/cloud-init-registry.yml` returns `f5ad4639 (#8272), 96f5b6eb (#7954), 173f7889 (#7552), …` newest first; the compare between the last two successful dispatcher runs (`a57cdb77…f5ad4639`) is `status=ahead, total_commits=21` of which exactly one touched the path — so the intersection is what selects `#8272` out of 21 unrelated merges, and one of those 21 (`f10aab24`, a `soleur-ai[bot]` direct push) has no `(#N)` suffix, which is why the `unattributed` arm is real and not theoretical.

### 2. The workflow derives, then names and posts

Edits to `.github/workflows/registry-host-replace-dispatch.yml` (cite content anchors, not line numbers, when implementing). The design principle across all of them: **one derivation step, one posting site, and every sentence branches on a step outcome the run actually measured.**

- **`workflow_dispatch` input `tracker`** (`type: string`, `required: false`, `default: ''`), description: `"Issue or PR number to record this delivery's verdict on (e.g. 8272 — the PR whose refusal you are re-firing). Digits only; omit to let the run derive it."` Read via `${{ inputs.tracker || '' }}` into `env:`; a leading `#` is stripped (the operator copies `#8272` from every other surface), then validated with `[[ "$TRACKER" =~ ^[0-9]+$ ]]`; anything else is dropped with a `::warning::`.
- **`permissions:`** add `pull-requests: write` beside the existing `issues: write`, and rewrite the existing `issues: write` WHY comment (it says "posts with `gh issue comment`", which stops being true) to name the two writes that remain: `gh api … /issues/{n}/comments -X POST` and the `gh issue create` fallback. New WHY comment for the PR scope: PR comments are served from `/repos/{o}/{r}/issues/{n}/comments` but governed by `pull-requests: write` (learning 2026-08-17 §"the REST path lies about the scope"; `scripts/lint-workflow-issue-write-scope.py` `has_pr_write` docstring). `issues: write` stays for the `tracker` input naming an issue and for the no-target fallback below.
- **Gate step (`id: gate`)** — the `gh run list` watermark lookup moves ABOVE the `if [[ "$EVENT_NAME" == "workflow_dispatch" ]]` early exit, and the gate emits `watermark=${BEFORE_SHA}` the moment a SHA resolves, before its own compare. The helper re-proves ancestry with its own compare, so the gate does not pre-classify. **Two consequences, both load-bearing (spec-flow P0-1 / P1-3):** (a) the manual arm now gets a watermark — on a re-fire `github.sha` is whatever `main` is at, typically NOT the refused change (run 35215010502 re-fired at `a57cdb77`, eight days and many merges after the `96f5b6eb` change it delivered), so an `[after]`-only derivation there would attribute the delivery to an unrelated PR, the very defect this plan removes; (b) the diverged/behind and compare-failure arms hand the helper a real watermark and it classifies them itself (`range_note=compare status diverged` / `compare rc=22`), instead of the gate withholding it and the artifact reading "no watermark" for a compare that failed. The manual arm's `deliver=true` stays unconditional; a failed lookup emits no watermark and still delivers (the preflight still gates, with `--manual`). The gate's other exit arms are unchanged.
- **New step `id: change` — "Name the change this run delivers"**, after the gate and before the preflight, `if: always()`, `continue-on-error: true`, `timeout-minutes: 5`, `env: GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}`, `BEFORE: ${{ steps.gate.outputs.watermark }}`, `AFTER: ${{ github.sha }}`, `TRACKER: ${{ inputs.tracker || '' }}` (every value bound through `env:`, none inline in `run:`). `set -euo pipefail`; it runs `bash scripts/registry-delivery-change.sh --repo "$GITHUB_REPOSITORY" --after "$AFTER" --before "$BEFORE" --path apps/web-platform/infra/cloud-init-registry.yml`, appends the `key=value` lines to `$GITHUB_OUTPUT` with plain `echo` (the helper guarantees one line per key; `GITHUB_OUTPUT` splits on the first `=` and treats `%` as literal), then computes `targets=` = derived `prs` ∪ validated `TRACKER`, deduplicated (a `tracker` equal to a derived PR must not double-post), and prints the block to `$GITHUB_STEP_SUMMARY` — every run, including `deliver=false` registration runs, is a free live probe of the derivation. **The job never depends on this step succeeding:** `continue-on-error: true` keeps the step's *conclusion* `success` (so the preflight's implicit `success()` is unaffected) while `steps.change.outcome` records `failure`; `timeout-minutes: 5` bounds a hung API call and is one budget, not thirteen. There is NO in-step fallback block: the two consumers default instead — `SUMMARY="${SUMMARY:-the cloud-init-registry.yml user_data at ${MERGE_SHA:0:7}}"`, `TARGETS="${TARGETS:-$TRACKER}"` — which also covers the step being killed by its timeout, which an in-step block cannot (simplicity + DHH, both panels). **Why `always()`:** the refusal step needs `summary`/`targets` on the arm where the GATE failed. **Why `continue-on-error`:** later steps carry an implicit `success()`, so without it a failure here would skip the preflight and make a naive refusal step say "preflight declined" for a preflight that never ran; without `GH_TOKEN` every `gh api` would fail and every run would silently degrade (spec-flow P1-5).
- **Dispatch step** — the reason on the push arm becomes `Delivering the cloud-init-registry.yml user_data merged at ${MERGE_SHA} — ${SUMMARY}. Inert until this replace runs; the store volume is preserved.`; the manual arm appends ` — ${SUMMARY}`. `SUMMARY` is bound via `env:` with the empty-default above; `apply-web-platform-infra.yml` consumes `reason` only through `REASON: ${{ inputs.reason }}` (its header: "Untrusted-input handling"). The step-summary sentence `Verification is enrolled on #7556 and runs from Better Stack — no dashboard, no SSH.` becomes `Post-replace verification is the follow-through enrolled on the delivering change's own tracker (scripts/followthroughs/); this run observes only the apply's conclusion (next step). Delivering: ${SUMMARY}.`
- **Poll step** gains `id: poll` and **stops writing to the tracker**. It emits `apply_run=<id>` and `apply_conclusion=<concl|unverified>` to `$GITHUB_OUTPUT` on every arm, keeps its `::warning::` UNVERIFIED arms and its `::error::` + `exit 1` on a non-success conclusion, and its `#7556 remains the authority` text becomes `the delivering change's own follow-through remains the authority`. The single tracker write for this arm moves to the refusal step (spec-flow P0-2: with the poll posting AND the refusal step firing on the same failure, every target received two contradictory comments — "the host may be dark" then "the host still runs its previous user_data").
- **Refusal step** — renamed "Record the delivery verdict on its tracker(s)" and made the **sole posting site**. It binds `steps.gate.outcome`, `steps.preflight.outcome`, `steps.dispatch.outcome`, `steps.poll.outcome`, `steps.poll.outputs.apply_run`, `steps.poll.outputs.apply_conclusion`, `steps.change.outputs.*` and `job.status` via `env:` and composes `WHAT`/`WHY`/`STATE` from **the one step that failed** (the steps are serially gated, so at most one can be `failure`; `change` is excluded — it cannot fail the job). Four arms:
  - `job.status == cancelled` → `Delivery CANCELLED mid-run` (existing wording; STATE: "whether the replace was dispatched is visible in the run — read it before re-firing").
  - `poll == failure` → `Apply FAILED: registry-host-replace run ${apply_run} concluded ${apply_conclusion}`; STATE: "the registry host may be DARK and has no SSH; the store volume is preserved; recovery is a re-dispatch". No "NOT live" sentence — the replace ran.
  - `preflight == failure` or `dispatch == failure` → `Delivery REFUSED (${FAILED_STEP})` where `FAILED_STEP` names the step; STATE: not-live sentence (same remediation for both — one arm, Kieran/simplicity merge).
  - `gate == failure` → `Delivery UNDETERMINED` (existing wording); STATE: not-live sentence.
  - The not-live sentence, when `prs` is non-empty: `The registry host still runs its previous user_data, so the cloud-init-registry.yml change(s) in ${SUMMARY} are NOT live` (plural-safe for coalesced ranges; a comment-only PR in the range reads truthfully because its rendered change is still the same "not live"); when `range_note` is non-empty it gains ` (attribution unproven: ${RANGE_NOTE})`. When `prs` is EMPTY on a proven range (nothing in range touched the config — includes a re-fire at the watermark SHA), it is instead `The registry host's user_data is unchanged since the delivery watermark ${WATERMARK7}; this run was not applied.` — the bytes ARE live, and saying otherwise would be the false-text defect in a new arm.
  - Every body ends with the re-fire instruction WITH the tracker substituted (CTO advisory — the comment is the only place the operator learns the input exists): `` Re-fire with `gh workflow run registry-host-replace-dispatch.yml -f reason='<why>' -f tracker=${FIRST_TARGET}` once the refusing predicate is resolved `` (on the no-target arm: `-f tracker=<the issue you are tracking this under>`), followed by the existing P1/P5 predicate notes. The same substituted command is echoed to `$GITHUB_STEP_SUMMARY`, since the red run on the Actions tab is the other place the operator lands.
  - One `MARKER="<!-- registry-delivery run=${GITHUB_RUN_ID} kind=${KIND} -->"` (`KIND` ∈ `cancelled|apply-failed|refused|undetermined`), defined once and appended to every body — it is what the Success Metrics grep keys on. **No pre-post comment listing and no dedupe** (DHH + simplicity, both panels): the only path that could duplicate is `gh run rerun` of a failed job, which no runbook prescribes (the documented recovery is `workflow_dispatch`, a new run id), and a duplicate comment is recoverable where a missing artifact is not. Posting loop over `$TARGETS` via `gh api -X POST "repos/${GITHUB_REPOSITORY}/issues/${n}/comments" -f body="$BODY"` (valid for issues and PRs; `cla-evidence.yml`). A failed post → `::error::` naming that target; the loop continues; the step exits 1 at the end if any post failed.
  - **Empty `$TARGETS`** (no PR derivable and no `tracker` — reachable: `main`'s ruleset does not require PRs, `soleur-ai[bot]` pushes directly, and the proven-range-no-touch arm below deliberately yields no PR) → `gh issue create --title "registry-host-replace delivery at ${MERGE_SHA:0:7} needs an owner: ${WHAT}" --body "$BODY" --label domain/engineering --label type/chore --label priority/p1-high --label action-required` (all four labels verified to exist 2026-09-19; **`action-required` is load-bearing, not decoration** — `plugins/soleur/skills/operator-digest/SKILL.md` §4 harvests ONLY issues carrying it and uses priority merely to sort survivors, the exact precedent `scheduled-inngest-health.yml` records beside its own `gh issue create`; CTO advisory, verified), no pre-create search (same reasoning as the comments); a failed create → `::error::` + `exit 1`. This is the one arm that adds a mechanism, and it is what keeps "never only a red run nobody owns" true on every path.
- **Comments** at the poll step (`that is #7556's job, from the warehouse`, `This step FILES on #7556`) are rewritten to describe the delivering tracker and the move of the write. A short STEP MAP comment block goes at the top of `jobs:` (gate → change → preflight → dispatch → poll → verdict, one line each naming what it emits) so the next editor finds where a string lives without reading the whole file (CTO advisory). The header provenance `Delivery dispatcher for registry-host user_data changes (#7555, ADR-190)` is history, not a per-delivery claim, and stays.

**Residual, recorded (spec-flow P2-12):** the poll's two UNVERIFIED arms (no run identified within the window / no conclusion within the window) `exit 0` today, so the job is green, nothing posts, and the run becomes the next watermark. That is unchanged here — the `::warning::` stays and the delivering PR is named in the step summary — and is filed as a deferral rather than widened into this fix.

### 3. Test suite and registration

`tests/scripts/test-registry-delivery-change.sh` in the shape of `tests/scripts/test-registry-replace-preflight.sh`: a `gh` stub (`$TMP/gh.sh`) that dispatches on its argv (`compare/`, `commits?`, `/pulls`, `commits/<sha>`) and answers from `STUB_*` env vars; `run_sut` with `env -u GITHUB_ACTIONS`; an inline anti-vacuity floor on the assertion count (the preflight suite's `-lt 26` shape, re-derived from a green run of this suite); every fixture synthesized (`cq-test-fixtures-synthesized-only`). Registered in `scripts/test-all.sh` directly under the `tests/scripts/registry-replace-preflight` line — `tests/scripts/` is NOT auto-globbed (the runner's own comment there), so an unregistered suite runs in zero runners.

## Research Reconciliation — Spec vs. Codebase

| Issue-body claim | Reality (verified 2026-09-19) | Plan response |
|---|---|---|
| "fires on every push to main that changes the rendered user_data" | True, plus the registration path for the workflow file itself; the delta gate compares against a delivery WATERMARK (last successful run), not `github.event.before`, so a run's range can span many merges (measured: 21 commits between the last two successful runs) | Derive from the watermark range ∩ path-touching commits, not from `github.sha` alone; `github.sha`-only is the fallback arm |
| "PR number via `gh pr list --search <sha> --state merged`" | The repo's three existing resolvers use `gh api repos/{r}/commits/{sha}/pulls` with a `(#N)` subject fallback (`reusable-release.yml`, `post-merge-monitor.yml`, `fix-constraints-stage-b.yml`); `pr list --search` is search-index-backed and lags merges | Adopt the `commits/{sha}/pulls` precedent verbatim; `--search` not used |
| "post to the PR that changed the bytes" | `gh issue comment` cannot be assumed to address a PR; `gh api -X POST repos/{r}/issues/{n}/comments` addresses both, and PR comments are governed by `pull-requests: write` (learning 2026-08-17) | Use the `gh api` form; add `pull-requests: write` |
| "(or a configurable tracker)" | No `type: number` input precedent in the repo; optional inputs are read as `${{ inputs.x \|\| '' }}` | `tracker` as an optional string input, digit-validated in bash |
| "Workaround in use: PR #8272's delivery posts a pointer comment on #7960" | The pointer was an operator step in PR #8272's plan (`…-phase-b-delivery-field-plan.md`, "If the dispatcher refuses on P3 … post a pointer comment on #7960"), not code; nothing in the tree implements it | Nothing to remove; this plan replaces the operator step with the derived target |
| (implicit) a PR always exists for a push to `main` | `main`'s ruleset requires status checks, non-fast-forward and no deletion — NOT a PR; `f10aab24` in the measured range is a `soleur-ai[bot]` direct push with no `(#N)` | The `unattributed` arm and the issue-create fallback are real, not defensive |

## Technical Considerations

- **Fail direction.** The helper is on the path between the gate and the preflight; it must never convert a deliverable push into a red run, and never convert a refusal into a silent one. Hence: exit 0 on every API arm, `if: always()`, fallback outputs in the step, and the refusal step's own create-fallback when nothing is derivable.
- **`if: always()` semantics.** Under `always()` the step runs after a failed gate (wanted); because it cannot fail, the implicit `success()` on the preflight/dispatch steps is unaffected, and `job.status` in the refusal step keeps its current meaning. A run cancelled while PENDING runs no steps at all (unchanged, covered by the watermark's subsumption argument in the file).
- **Step outputs from a failed gate.** `$GITHUB_OUTPUT` lines written before a step's `exit 1` are still exposed as `steps.gate.outputs.*`; the helper nonetheless tolerates an empty `--before` so nothing depends on that.
- **Attribution under coalescing.** When an evicted delivery is subsumed by a successor, the range carries several path-touching commits; the summary names all of them and the artifact posts to each PR. That is the truthful shape: each PR's change is what is (not) live.
- **API budget.** Two calls on the proven arm (compare, path-listing) plus one `pulls` call per candidate, capped at 10; the gate already makes the compare call, so the helper's compare is a second read of the same range — accepted for the helper's testability and independence from the gate's internal variables (an output-passing alternative is in Alternatives).
- **Untrusted text.** Commit subjects and PR titles enter the reason, the step summary and comment bodies. Every consumer step binds them through `env:` (`SUMMARY: ${{ steps.change.outputs.summary }}`, `TARGETS: …`, `RANGE: …`, `RANGE_NOTE: …`) and expands `$SUMMARY` inside `run:` — never `${{ steps.change.outputs.summary }}` inline in a `run:` body, which is the script-injection shape the repo's `apply-web-platform-infra.yml` header forbids. The helper writes `summary=` as a single line (first message line only, CR/LF stripped; PR titles are ≤ 256 chars, so no cap); plain `echo` into `$GITHUB_OUTPUT` is safe for a one-line value. Bodies go via `-f body=` (JSON-encoded by `gh`); the reason goes via `gh workflow run -f reason=` (an input value, consumed downstream through an env var). No `eval`, no unquoted expansion. An AC greps that no `run:` body in the workflow contains `steps.change.outputs`.
- **Guards this touches.** `scripts/alarm-issue-filing-guard.test.sh` scans `gh issue (create|comment|close|edit)`: the poll's `gh issue comment 7556` drops out of its scanned population and the refusal step stays in it via `gh issue create` (84 → 83, floor 40), under `always() && job.status != 'success'` (no violation; baseline stays ≤ 11). Its `no-status-fn` rule is exactly why the poll step's write moved rather than being kept beside a second one: one gated site is auditable, two are a coordination problem. `scripts/lint-workflow-issue-write-scope.py`: the file keeps `issues: write`, so the `gh issue create` and the `gh api … issues … -X POST` writes are in scope and clean. `actionlint` for the YAML; `bash -n` for the helper and the test.
- **What this does not change.** The delta gate's predicates, the preflight, the poll's run selection and deadlines, the refusal step's `always() && job.status != 'success'` gate, the concurrency group, `timeout-minutes` — re-derived from the SUM of every deadline on the path, as the file's own comment mandates: P3 wait 2100 s + apply poll 1500 s + the `change` step's own `timeout-minutes: 5` (300 s) = 3900 s = 65 min, plus the measured ~74 s of checkout/gate/predicates, under the existing 70-minute ceiling. The 5-minute step budget is one number, not thirteen per-call ones (Kieran P1-3).

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Inline the derivation in the gate step (no helper) | The gate's `run:` block is already ~150 lines with five exit arms; the derivation has seven arms of its own and would be untestable offline. The repo's precedent for a testable workflow decision is a `scripts/*.sh` helper with a `tests/scripts/test-*.sh` suite (`registry-replace-preflight.sh`). |
| Pass the gate's `cmp_json` to the helper instead of re-fetching | Couples the helper to the gate's internal variable and makes the `[after]`-only arms (gate failed, no `cmp_json`) a second code path in YAML. One extra read of an already-cached compare is cheaper than a second YAML-side branch. |
| `gh pr list --search <sha> --state merged` (the issue's wording) | Search-index-backed and lags a merge by seconds to minutes — exactly the window this workflow runs in. `commits/{sha}/pulls` is the repo's three-times-used precedent and is authoritative at merge time (verified on `f5ad4639` 3 s after merge by run 35352234356's timing). |
| Post to the issues the PR `Closes`/`Ref`s instead of the PR | The closing issue is closed at merge, so the comment lands on a closed issue nobody reopens; the PR is the artifact that links both ways and that the author is subscribed to. The `tracker` input covers the case where an issue is the right place (a follow-through that stays open, like #7960 did). |
| A third-party action (`jwalton/gh-find-current-pr`, `8BitJonny/gh-get-current-pr`) | Neither covers the range∩path case or the `(#N)` fallback; adds a supply-chain pin the repo gates (`hr-third-party-content-grep-on-undertaking`, `vendor-pin-verify.yml`) for ~40 lines of bash. Functional-discovery agent recommended inline. |
| Repo variable `vars.REGISTRY_DELIVERY_TRACKER` as the no-PR fallback | A second hard-coded number by another name — the defect class this plan removes. Creating an owned issue is the repo's alarm shape. |
| A composite action `.github/actions/resolve-delivering-pr/` shared with the three existing resolvers | Deferred: worth it at a fifth caller, and the existing three are single-SHA resolvers without the range∩path shape. Tracked as a deferral (see Deferrals). |
| `if: !cancelled()` instead of `always()` on the `change` and refusal steps (advisor consult) | Rejected. The file's `always()` on the refusal step is a documented load-bearing choice: a `timeout-minutes` cancellation has STARTED the job, and `always()` is what lets the artifact file inside the grace window — that is the CANCELLED arm's whole purpose. Eviction under `cancel-in-progress: false` only ever cancels a PENDING run, which executes no steps, so the advisor's "false refusal posted to the real PR from an evicted run" cannot occur (the workflow's concurrency comment records exactly this split). |
| Compose the verdict body in a second helper `scripts/registry-delivery-verdict.sh` with its own test rows (CTO advisory) | Surfaced as Taste, not applied here: it is a structural preference that runs against the simplification panel's direction in the same review; recorded in `decision-challenges.md` for the operator. |
| Per-call `timeout` inside the helper + `REGISTRY_DELIVERY_GH_TIMEOUT` seam; `--max-lookups` flag; 400-char summary cap; `(#N)` suffix strip; merged-entry preference in `/pulls`; `range=identical` enum; in-step fallback outputs; pre-post comment listing + pre-create title search | Cut at plan-review (DHH + code-simplicity fired on the same scope): each defended against a case that does not occur or that an existing line already covers (step `timeout-minutes`, consumer defaults, the API's own contract). |
| Pass `range_proven=` from the gate instead of the helper re-fetching the compare (advisor consult) | Not adopted: the helper needs the range's COMMIT SET to intersect with the path listing, not just the boolean, and the gate has no commit set to hand over without exporting `cmp_json`. One extra read of a cached compare is the cheaper coupling. |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — this is operator-facing CI. The operator experiences a delivery refusal posted to no tracker or to the wrong PR, which is the "merged registry change sits inert, unowned" class (#7555) that the dispatcher exists to remove; a broken derivation that made the job red would additionally block every delivery until re-fired manually. The never-fail contract on the `change` step and the create-fallback on the refusal step are the mitigations.
- **If this leaks, the user's data is exposed via:** nothing — the only new data in motion is public repository metadata (PR numbers, commit subjects) posted back to the same repository.
- **Brand-survival threshold:** `none` — no customer-facing surface is touched; `.github/workflows/registry-host-replace-dispatch.yml` and `scripts/` do not match the preflight sensitive-path regex.

## Observability

```yaml
liveness_signal:
  what: "the dispatcher run itself (one per push that touches cloud-init-registry.yml or the workflow file) — the `change` step prints `range=` and `summary=` to the step summary on EVERY run, including deliver=false registration runs"
  cadence: per-run
  alert_target: "the delivering PR(s) / the `tracker` input / a created issue (refusal, failed apply); the Actions run (red) when nothing can be posted"
  configured_in: .github/workflows/registry-host-replace-dispatch.yml

error_reporting:
  destination: "GitHub Actions annotations (::warning:: on every degraded derivation arm, ::error:: on every failed post) plus the posted artifact itself"
  fail_loud: "refusal step exits 1 with `could not post the delivery-refusal artifact to <targets>` — the run is red and the ::error:: names the target that failed"

failure_modes:
  - mode: "derivation degrades to the [after]-only arm (no watermark, diverged, compare unreadable, >250 commits, no path touch in range)"
    detection: "`range=unproven` + `range_note=` in the step summary; the refusal artifact carries `(attribution unproven: …)`"
    alert_route: "the artifact reader (PR author / tracker watcher); never a page — delivery is unaffected"
  - mode: "no PR derivable and no tracker input on a refusal"
    detection: "refusal step creates an issue titled `registry-host-replace delivery at <sha7> needs an owner: <WHAT>` with priority/p1-high"
    alert_route: "the operator digest — harvested because the issue carries `action-required` (the digest filters on that label; p1 only orders it)"
  - mode: "a post to a derived target fails (deleted PR, scope regression)"
    detection: "::error:: naming the target; exit 1; red run on main"
    alert_route: "unchanged residual from the current workflow — the red run is the artifact of last resort (learning 2026-08-17)"

logs:
  where: "the Actions run log + $GITHUB_STEP_SUMMARY of run registry-host-replace-dispatch.yml"
  retention: "90 days (GitHub run retention, the same bound the watermark already lives under)"

discoverability_test:
  command: bash tests/scripts/test-registry-delivery-change.sh
  expected_output: "=== Results: N/N passed, 0 failed === (N >= 12) — every derivation arm exercised against a synthesized gh stub, no credentials"
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `scripts/registry-delivery-change.sh` exists, is executable, `bash -n` clean, and `bash scripts/registry-delivery-change.sh` with no args exits 2 with a usage line naming `--repo` and `--after`.
- [ ] AC2 — `bash tests/scripts/test-registry-delivery-change.sh` prints `=== Results: N/N passed, 0 failed ===` with N ≥ 12, and `grep -c 'run_suite "tests/scripts/registry-delivery-change"' scripts/test-all.sh` returns 1.
- [ ] AC3 — `grep -vE '^\s*#' .github/workflows/registry-host-replace-dispatch.yml | grep -cE '\b(7555|7556)\b'` returns 0 (today: 7; no non-comment line names either number; the header provenance comment is the only survivor).
- [ ] AC4 — `grep -cE '^\s*pull-requests:\s*write' .github/workflows/registry-host-replace-dispatch.yml` returns 1 and `grep -cE '^\s*issues:\s*write' …` still returns 1.
- [ ] AC5a — the `change` step declares `continue-on-error: true`, `timeout-minutes: 5`, and binds `GH_TOKEN`, `BEFORE`, `AFTER`, `TRACKER` under `env:`: `python3 -c 'import yaml; d=yaml.safe_load(open(".github/workflows/registry-host-replace-dispatch.yml")); c=[x for x in d["jobs"]["dispatch-replace"]["steps"] if x.get("id")=="change"][0]; print(c["continue-on-error"], c["timeout-minutes"], sorted(k for k in c["env"] if k in ("GH_TOKEN","BEFORE","AFTER","TRACKER")))'` prints `True 5 ['AFTER', 'BEFORE', 'GH_TOKEN', 'TRACKER']`.
- [ ] AC5b — the two consumers default the derived values: `grep -cE '\$\{SUMMARY:-' .github/workflows/registry-host-replace-dispatch.yml` ≥ 2 (dispatch step and refusal step) and `grep -cE '\$\{TARGETS:-' …` ≥ 1.
- [ ] AC5c — in the gate's `run:` body the line writing `watermark=` precedes the line testing `"$EVENT_NAME" == "workflow_dispatch"`: `python3 -c 'import yaml; d=yaml.safe_load(open(".github/workflows/registry-host-replace-dispatch.yml")); g=[x for x in d["jobs"]["dispatch-replace"]["steps"] if x.get("id")=="gate"][0]["run"].splitlines(); w=next(i for i,l in enumerate(g) if "watermark=" in l and not l.strip().startswith("#")); e=next(i for i,l in enumerate(g) if "== \"workflow_dispatch\"" in l and not l.strip().startswith("#")); print(w<e)'` prints `True`.
- [ ] AC5 — step shape, read with PyYAML (the interpreter the alarm guard already uses; `yq`/`actionlint` are not on the dev box): `python3 -c 'import yaml; d=yaml.safe_load(open(".github/workflows/registry-host-replace-dispatch.yml")); s=d["jobs"]["dispatch-replace"]["steps"]; ids=[x.get("id") for x in s]; print(ids); c=[x for x in s if x.get("id")=="change"][0]; print(c["if"])'` prints an id list in which `gate` precedes `change` precedes `preflight` precedes `dispatch`, and the second line is exactly `always()`.
- [ ] AC6 — `workflow_dispatch` declares `tracker` with `required: false` and `reason` unchanged: `python3 -c 'import yaml; d=yaml.safe_load(open(".github/workflows/registry-host-replace-dispatch.yml")); i=d[True]["workflow_dispatch"]["inputs"]; print(i["tracker"]["required"], i["reason"]["required"])'` prints `False True` (PyYAML parses the bare `on:` key as boolean `True`).
- [ ] AC7 — every `run:` body in the workflow parses as bash: `python3 -c 'import yaml,subprocess,sys; d=yaml.safe_load(open(".github/workflows/registry-host-replace-dispatch.yml")); bad=[x.get("name") for j in d["jobs"].values() for x in j["steps"] if x.get("run") and subprocess.run(["bash","-n"],input=x["run"],text=True,capture_output=True).returncode]; print(bad); sys.exit(1 if bad else 0)'` prints `[]` and exits 0. (CI's `actionlint` step asserts termination only, per its own comment in `ci.yml`; findings are #7042's job, so this AC does not gate on them.)
- [ ] AC8 — `bash scripts/alarm-issue-filing-guard.test.sh` passes with `(walked … issue-filing steps, ≤11 violations)`; `python3 scripts/lint-workflow-issue-write-scope.py` exits 0.
- [ ] AC9 — the refusal step's body: `grep -c 'are NOT live' .github/workflows/registry-host-replace-dispatch.yml` ≥ 1 and the same line references `${SUMMARY}` (`grep -cE 'SUMMARY.*are NOT live' …` ≥ 1); `grep -c 'unchanged since the delivery watermark' …` ≥ 1 (the proven-no-touch sentence); `grep -vE '^\s*#' … | grep -c 'deadline change'` = 0.
- [ ] AC10 — the refusal step contains a `gh issue create` under the empty-targets arm, passes `--label action-required`, and every `--label` it passes exists: `for l in domain/engineering type/chore priority/p1-high action-required; do gh label list --limit 300 --json name --jq '.[].name' | grep -qx "$l" || echo "MISSING $l"; done` prints nothing.
- [ ] AC11a — no `run:` body interpolates the derived text as an expression: `grep -vE '^\s*#' .github/workflows/registry-host-replace-dispatch.yml | grep -c 'steps.change.outputs'` equals `grep -vE '^\s*#' … | grep -cE '^\s+[A-Z_]+: \$\{\{ steps\.change\.outputs'` (every occurrence is an `env:` binding).
- [ ] AC11b — the run marker is defined once and reused: `grep -c 'MARKER="<!-- registry-delivery run=\${GITHUB_RUN_ID}' .github/workflows/registry-host-replace-dispatch.yml` = 1 and `grep -cE '\$\{?MARKER\}?' …` ≥ 3 (definition, comment body, issue body). No comment listing: `grep -c 'comments?per_page=100' …` = 0.
- [ ] AC11 — exactly one tracker-comment write site, in the refusal step, using the issue/PR-agnostic form: `grep -cE 'gh api -X POST "repos/\$\{GITHUB_REPOSITORY\}/issues/\$\{?n\}?/comments"' .github/workflows/registry-host-replace-dispatch.yml` = 1; `grep -vE '^\s*#' … | grep -c 'gh issue comment'` = 0 (comment-stripped — the `permissions:` WHY comment is rewritten too, but the AC must not depend on prose); and the poll step's `run:` body (PyYAML, `id == "poll"`) contains no `gh api -X POST` and no `gh issue`, but does write `apply_run=` and `apply_conclusion=` to `$GITHUB_OUTPUT`.
- [ ] AC11c — the refusal step binds every outcome it branches on: its `env:` includes `${{ steps.gate.outcome }}`, `${{ steps.preflight.outcome }}`, `${{ steps.dispatch.outcome }}`, `${{ steps.poll.outcome }}` (grep each literal, count ≥ 1); its `run:` body contains the literals `Apply FAILED`, `Delivery REFUSED`, `Delivery UNDETERMINED`, `Delivery CANCELLED` and `-f tracker=` (the substituted re-fire instruction).
- [ ] AC12 — the repo's touched-shard battery is green: `bash scripts/test-all.sh` runs the `tests/scripts/registry-delivery-change`, `scripts/alarm-issue-filing-guard`, `scripts/lint-workflow-issue-write-scope`, `scripts/lint-workflow-issue-write-scope-live` and `plugins/soleur/test/c4-count-parity` suites without failure.
- [ ] AC13 — the diff is a subset of: `.github/workflows/registry-host-replace-dispatch.yml`, `scripts/registry-delivery-change.sh`, `tests/scripts/test-registry-delivery-change.sh`, `scripts/test-all.sh`, `knowledge-base/INDEX.md`, `knowledge-base/project/plans/2026-09-19-fix-registry-dispatcher-derive-delivery-tracker-plan.md`, `knowledge-base/project/specs/feat-one-shot-8279-dispatcher-derive-tracker/**`, `knowledge-base/project/learnings/**` (the pipeline's own writes included, per the diff-scope sharp edge).

### Post-merge (automated by the merge itself)

- [ ] AC14 — merging fires the dispatcher on its registration path (the workflow file is a push trigger). That run's `change` step summary must show `range=proven`; IF no config-touching PR merged between the watermark and this merge (the expected case), `range_note=no commit in range touched apps/web-platform/infra/cloud-init-registry.yml`, `prs=` empty, `summary=` naming this merge SHA and the watermark, and `deliver=false`; IF one did, `prs=` names that PR and the run delivers it (a real delivery this PR merely coalesces). Either way the run concludes `success`. Read with `gh run list --workflow=registry-host-replace-dispatch.yml --limit 1 --json databaseId,conclusion` then `gh run view <id> --log | grep -E 'range=|summary='`. Automation: the `/ship` post-merge verification reads the run; no operator step.

## Test Scenarios

`tests/scripts/test-registry-delivery-change.sh` — `gh` stub dispatches on argv; each row names the STUB_* inputs it sets and the assertion on stdout/rc.

| # | Arm | Stub | Assert |
|---|---|---|---|
| T1 (control) | proven range, one path touch, PR via `/pulls`; subject carries NO `(#N)` suffix (rebase-merge shape) and contains `=`, `%`, backticks and `"` | compare `ahead`, 3 commits; `commits?path=` returns 1 in-range sha; `/pulls` → `[{number:8272,merged_at:…}]` | rc 0; `range=proven`; `prs=8272`; `summary` starts `PR #8272 (` and preserves the characters verbatim on one line |
| T2 | two path touches, two PRs | 2 in-range shas; pulls 7954 then 8272 | `prs=7954 8272` (oldest→newest); both in summary |
| T3 (coalesced) | after is a registration-only push; the path touch is an EARLIER commit in range | compare 4 commits; path list returns only the earlier sha | `prs=` names the earlier commit's PR, NOT after's |
| T4 (must-PASS, non-canonical) | no `--before` | `/commits/<after>` subject + `/pulls` | rc 0; `range=unproven`; `range_note=no watermark`; `prs=<after's PR>` |
| T4b (manual re-fire shape) | `--before` = watermark, after = HEAD many commits later, the path touch is mid-range | | `prs=` names the mid-range PR, NOT after's — the arm that made the gate's watermark hoist necessary |
| T5 | compare `diverged` | | rc 0; unproven; `commits=<after>` only |
| T6 | compare rc≠0 (stub `STUB_COMPARE_RC=22`) | | rc 0; unproven; note names rc; `prs` from after's `/pulls` |
| T7 | `/pulls` → `[]`, subject ends `(#7954)` | | `prs=7954` (subject fallback) |
| T8 | `/pulls` → `[]`, no `(#N)` | | `prs=` empty; `unattributed=<sha>`; summary `commit <sha7> (<subject>)` |
| T10 | `total_commits=251` | | unproven; note mentions 250; `[after]` only |
| T11 | proven range, path list returns shas NOT in range | | `range=proven`; `prs=` EMPTY; `commits=` EMPTY; note `no commit in range touched`; summary names `<after7>` and `<before7>` |
| T12 | `GITHUB_ACTIONS=true` with `REGISTRY_DELIVERY_GH_CMD` set | | rc 1, `::error::` names the seam — mirrors the preflight's production guard |
| T13 | merge-commit PR: 2 in-range shas both → PR 9001 | | `prs=9001` once; summary has one `PR #9001` |
| T14 | 12 in-range path touches | | exactly 10 `/pulls` calls (stub call counter; `MAX_LOOKUPS`); note mentions the cap |
| T15 | `identical` compare (`status=identical`, `commits=[]`) | | `range=proven`; `prs=` EMPTY; summary names `<after7>` and the watermark — same arm as T11 |
| T16 | a subject with a CR/LF inside the first message line | | `summary=` is one line, CR/LF stripped |

Mutation rows (each must turn a named row red; written before the helper):

- remove the range intersection (use the path list unfiltered) → T11 reds;
- fall back to `[after]` on the proven-no-touch arm → T11 and T15 red;
- drop the `(#N)` subject fallback → T7 reds;
- add `?per_page=100` to the compare call → T10 reds (the 250 cap is the no-paging contract);
- make a compare failure `exit 1` → T6 reds;
- harness row: delete T1's `pass` call → the suite's anti-vacuity floor reds the run.

Workflow-level (not unit-testable offline; covered by AC3-AC11 greps + AC14's live registration run).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change confined to a CI workflow and its helper script; engineering assessment question ("significant architectural decisions … beyond normal implementation") does not fire: the dispatcher's authorization model (ADR-169 amendment) is unchanged, only where its verdict is recorded and how it is worded.

## Architecture Decision (ADR/C4)

Not detected. The decision ADR-169's amendment records — "merge to `main` authorizes a volume-preserving replace, judged by a delta gate plus a read-only preflight" — is untouched; this plan changes the artifact's target and text, not who authorizes what. No ADR is created or amended. C4: all three model files (`model.c4`, `views.c4`, `spec.c4`) were checked for the actors and systems this touches — GitHub Actions (already modeled as the CI runner), the GitHub API (the same system, read and written today), no new external actor, no new store, no changed access relationship — and `plugins/soleur/test/c4-count-parity.test.sh` is in AC12's battery as the count-parity backstop (the dispatcher adds no monitor, heartbeat or workflow count).

## Open Code-Review Overlap

- #7942 (`Two mutation batteries in plugins/soleur/test/ are named *.mutation.sh and run in no gate`) names `scripts/test-all.sh` — **Acknowledge:** it concerns the naming/registration of two existing `plugins/soleur/test/*.mutation.sh` batteries, not the `tests/scripts/` registration this plan adds; this plan's suite registers by explicit `run_suite` line, which is the form #7942 asks for. The scope-out stays open.
- No open code-review issue names `.github/workflows/registry-host-replace-dispatch.yml`, `scripts/registry-replace-preflight.sh` or `tests/scripts/test-registry-replace-preflight.sh`.

Related open issues on the same workflow, not code-review: #7582 (the delta gate misses a zot digest bump — a different predicate, untouched here) and #8044 (whether replace-class dispatches should be two-party — orthogonal to where the verdict is recorded).

## Deferrals

- The poll step's UNVERIFIED arms (no apply run identified in the window / no conclusion in the window) exit 0 with a `::warning::` only, so nothing posts and the run becomes the next watermark — the last P4 dead end. Re-evaluate when a live run hits either arm, or fold into #8044 (two-party dispatch) if that lands first. Filed at ship time as a `deferred-scope-out` issue.

- Shared merge-SHA → PR resolution (four inline copies after this PR: `reusable-release.yml`, `post-merge-monitor.yml`, `fix-constraints-stage-b.yml`, and `resolve_pr_for_sha` in the new helper). The helper's function is the shape the others could adopt — the deferral is "extract `resolve_pr_for_sha` to `scripts/lib/` and adopt in the three callers", a move rather than a design. Re-evaluate the next time any of the three is edited (CTO advisory: "a fifth caller" is a passive trigger). Filed at ship time as a `deferred-scope-out` issue with milestone `Post-MVP / Later` if not already tracked.

## Success Metrics

- The next refusal or failed apply on a delivery that is not #7555's posts on that delivery's PR (or its `tracker`), with a summary naming the PR and its subject — observable on the next P3 refusal, which ADR-169 records as the modal outcome of a merge that touches `apps/web-platform/**`.
- Zero comments from this workflow on #7556 after merge (`gh issue view 7556 --json comments --jq '[.comments[] | select(.body | test("Delivery (REFUSED|CANCELLED|UNDETERMINED)"))] | length'` stops growing).

## Dependencies & Risks

- **Risk:** a derivation arm that fails the job. Mitigation: exit-0 contract + step-level fallback + T5/T6/T10/T11 rows.
- **Risk:** `pull-requests: write` is a scope widening. It is the minimal scope for the target the issue asks for; the token remains `secrets.GITHUB_TOKEN` (no PAT, `hr-github-app-auth-not-pat` unaffected).
- **Risk:** the compare re-read doubles one API call per run. Negligible against the poll loop's per-15 s `gh run list`.
- **Risk:** a PR subject containing markdown or `#N` references produces auto-links in the comment. Accepted — it is the PR's own subject.
- **Dependency:** none new. `gh`, `jq`, `grep -P` are on `ubuntu-24.04` runners and already used by this workflow and its siblings.

## References & Research

- Issue #8279; PR #8272 and its plan `knowledge-base/project/plans/2026-09-18-fix-registry-heartbeat-phase-b-delivery-field-plan.md` (the measured wrong-tracker case and the operator workaround).
- ADR-169 `knowledge-base/engineering/architecture/decisions/ADR-169-what-authorizes-destroying-the-sole-pull-path.md` §Amendment 2026-08-16; ADR-190.
- `.github/workflows/reusable-release.yml` (`commits/{sha}/pulls` + `(#N)` fallback + integer validation), `.github/workflows/post-merge-monitor.yml`, `.github/workflows/cla-evidence.yml` (`gh api -X POST … /issues/{n}/comments`).
- `scripts/registry-replace-preflight.sh` + `tests/scripts/test-registry-replace-preflight.sh` (seam + stub shape), `scripts/test-all.sh` registration comment on `tests/scripts/`.
- `scripts/lint-workflow-issue-write-scope.py` (`has_pr_write` docstring), `scripts/alarm-issue-filing-guard.test.sh`.
- Learnings: `knowledge-base/project/learnings/2026-08-17-the-artifact-that-proves-a-refusal-happened-could-not-be-written.md`, `knowledge-base/project/learnings/2026-08-16-every-number-i-inherited-was-stale-and-the-panel-found-the-defect-class-inside-my-fix.md`, `knowledge-base/project/learnings/best-practices/2026-07-13-watchdog-excluded-mode-shares-issue-class-untruthful-comment.md`, `knowledge-base/project/learnings/best-practices/2026-07-02-gha-run-default-shell-has-pipefail-guard-grep-substitutions.md`, `knowledge-base/project/learnings/2026-08-13-making-a-red-gate-green-arms-everything-it-was-silently-gating.md`.

## Research Insights

**Premise Validation (Phase 0.6).** #8279 is OPEN, `closedByPullRequestsReferences: []`. #7555 CLOSED (delivered 2026-08-19); #7556 OPEN (soak follow-through, sweeper commenting daily); #7960 CLOSED 2026-09-18 by the sweeper's PASS after PR #8272's delivery; PR #8272 MERGED at `f5ad4639` 2026-09-18T13:46:53Z. All nine hard-coded sites in the workflow were read directly (reason, step summary, poll warning, poll comment, refusal text, refusal comment target, refusal error, and two comments). The workaround the issue names is an operator step in #8272's plan, not code. ADR corpus grep for the mechanism (`commits/.*/pulls`, "delivering PR", "comment target") returns nothing — no ADR rejects deriving the tracker from the push; ADR-169's amendment names #7556 only as the #7555 soak's verifier.

**Property List (Phase 0.6b).**
- P1 The dispatch `reason` names the change(s) this run actually delivers.
- P2 The refusal/failure artifact states truthfully which change(s) are not live, and says when its attribution is unproven.
- P3 The artifact lands where the delivery is tracked: the delivering PR(s), and/or a tracker the re-firing operator names.
- P4 A refusal is never only a red run nobody owns — on every arm, including "no PR derivable" (existing invariant, preserved).
- P5 The manual re-fire arm can name its tracker.
- P6 The run's verification pointer does not claim an enrolment that belongs to a different change.

**Mechanisms → properties.** Helper + `change` step (P1, P2, P3, P6); `tracker` input (P5, P3 on manual); issue-create fallback (P4 on the no-PR arm); `pull-requests: write` (P3 — the PR target is otherwise unwritable, the exact silent-`|| true` class of 2026-08-17). Existing repo mechanisms checked (grepped `.github/workflows/`, `scripts/`, `plugins/soleur/skills`): three single-SHA PR resolvers exist and are adopted, none covers P3's range∩path shape; no existing mechanism covers P4 on the no-PR arm.

**Cut List.** `gh pr list --search <sha>` (issue's wording) → replaced by the precedent endpoint; a repo-variable fallback tracker → cut (re-introduces a constant); a `workflow_run` observer for the derivation step → cut (the step cannot fail, so there is nothing to observe); rendering per-PR byte-level attribution (which PR changed the RENDERED bytes) → cut: the gate already proves the range as a whole changes rendered bytes, and per-commit stripped-render comparison would add N file fetches to answer a question the artifact does not need — the summary says "the cloud-init-registry.yml changes merged in PR #A, #B are not live", which is true for a comment-only PR too.

**Verified API contracts (2026-09-19, live).** `gh issue view 8272` resolves a PR (issue commands accept PR numbers for reads; writes are routed through `gh api` regardless). `GET commits/f5ad4639…/pulls` → `[{number:8272, state:closed, merged_at:…}]`. `GET commits?sha=f5ad4639…&path=<CFG>&per_page=5` → `f5ad4639 (#8272), 96f5b6eb (#7954), 173f7889 (#7552), 19bbdb76 (#7514), 07cf8ebc (#7444)`. Compare `a57cdb77…f5ad4639` → `status=ahead, total_commits=21, files=137`; the 21 include `f10aab24` (`soleur-ai[bot]`, no `(#N)`). Repo merge settings: squash, merge-commit and rebase all allowed (`squash_merge_commit_title=COMMIT_OR_PR_TITLE`), so the helper must not assume squash. **Merge-commit PRs, measured on #6326 (merge commit `cbd6c948`, branch commit `766199ed`):** `commits?sha=&path=` applies git history simplification and returns the BRANCH commit (`766199ed`, 1 parent), never the merge commit; the compare range `cbd6c948~1...cbd6c948` lists BOTH (`766199ed`, `cbd6c948`); `commits/766199ed/pulls` resolves to `#6326 merged_at=2026-07-10`. So the intersection selects the branch commit, `/pulls` attributes it correctly, and step 7's dedupe collapses a multi-commit branch to one PR — the merge-commit method needs no special arm. `compare/X...X` returns `status=identical, total_commits=0, commits=[]` (measured), which is why `identical` needs no arm of its own — it is a proven range with an empty intersection. `main` ruleset: `required_status_checks`, `deletion`, `non_fast_forward` — no pull-request requirement. Labels `domain/engineering`, `type/chore`, `priority/p1-high`, `action-required` exist. `apply-web-platform-infra.yml` consumes `reason` via `REASON: ${{ inputs.reason }}` env only (header: "Untrusted-input handling").

**Dispatcher run history (for AC14 and the summary shape):** 31976455167 push failure (2026-08-16, the missing-scope refusal), 31978045577 manual success, 32280053575 push success (2026-08-19), 34373737714 push failure (2026-09-09, P3 refusal for #7954), 35215010502 manual success (2026-09-17), 35352234356 push success (2026-09-18, #8272). Watermark today = `f5ad4639`.

**Institutional learnings applied.** 2026-08-17 (artifact step: no `|| true`, scope must match the target, timeout must exceed internal deadlines — the new step adds seconds); 2026-08-16 (inherited numbers are stale by default — the fix removes the constant rather than refreshing it); 2026-07-13 (an excluded-mode output is empty — the `change` step writes every output on every arm, and the refusal step's wording branches on `range=`); 2026-07-02 (GHA `run:` has `pipefail` — every `grep`/`jq` substitution in the new step is `|| var=""`-guarded); 2026-08-13 (turning an arm green arms downstream steps — enumerated: the only newly-reachable action is the issue-create fallback, gated on the refusal step's existing condition).

**CLAUDE.md / AGENTS conventions.** `cq-test-fixtures-synthesized-only` (all stub JSON synthesized); `hr-github-app-auth-not-pat` (token unchanged); `cq-cite-content-anchor-not-line-number` (implementation cites the strings above, not line numbers); `hr-verify-repo-capability-claim-before-assert` (every "the repo does X" claim above was grepped and the file named).

**SpecFlow (Phase 3) and advisor (Phase 4.5) findings, disposition.** Applied: watermark emitted before the manual early-exit (P0-1/P1-3 → gate edit, T4b, AC5c); single posting site with outcome-driven wording (P0-2/P1-6 → poll emits outputs only, refusal composes `WHAT` from step outcomes, AC11/AC11c); proven-range-no-touch yields no PR (P1-4 → helper step 4, T11); `GH_TOKEN` + `continue-on-error` + step `timeout-minutes` on the `change` step (P1-5 → AC5a); plural not-live sentence (P2-8); target dedupe (P2-9); `--before` via `env:` (P2-10); run marker (advisor; the dedupe half was later cut at plan-review); `env:`-only binding of derived text (advisor → AC11a, T1/T16). Applied then cut at plan-review: subject suffix strip (P2-11). Recorded as residual/deferred: UNVERIFIED poll arms (P2-12). Rejected with reasons in Alternatives: `!cancelled()` on the artifact steps; passing `range_proven=` instead of re-fetching the compare.

**Plan-review panel (DHH, Kieran, code-simplicity, CTO-devex), disposition.** Both simplification reviewers fired on the same scope, so those mechanisms were CUT rather than fixed: comment-listing dedupe + pre-create title search (marker kept), `range=identical` enum (folded into the proven-empty arm with one truthful sentence), `--max-lookups` flag (constant), per-call timeout + seam (step `timeout-minutes: 5`), 400-char cap, `(#N)` suffix strip, merged-entry preference (`.[0].number` verbatim from precedent), in-step fallback block (consumer defaults), heredoc `GITHUB_OUTPUT` write (plain echo), T9/T15-old/T17-T20 rows, five refusal arms → four. Kieran's correctness fixes applied: AC9 plural, AC11 comment-strip + `permissions:` WHY rewrite, timeout re-derivation (65 min < 70), compare called without paging params + T10 mutation, exit contract names the seam refusal, `MARKER` defined once, 84 → 83 scanned, merge-commit subject note, rebase-merge row in T1, AC11a `-c`, c4-count-parity in AC12, header cited by content, anti-vacuity floor named. CTO applied (factual): `action-required` label on the fallback issue (verified against `operator-digest/SKILL.md` §4 and `scheduled-inngest-health.yml`), the re-fire instruction carries `-f tracker=<N>` substituted, input description rewritten, `#` stripped from `tracker`, `resolve_pr_for_sha` as a named function, deferral trigger reworded, STEP MAP comment. CTO surfaced as Taste (not applied): a second `registry-delivery-verdict.sh` helper for body composition — see `knowledge-base/project/specs/feat-one-shot-8279-dispatcher-derive-tracker/decision-challenges.md`. DHH's cut of the mutation rows and of the YAML-shape ACs was applied partially: rows trimmed to those that name a real arm; ACs 5/5a/5c/6/11a-c kept because each pins a property a reviewer cannot see in a diff (step order, `always()`, the watermark hoist, injection-free binding).

**Research decision (Phase 1.6):** strong local context (three in-repo resolvers, a sibling helper+test pair, live-verified API shapes); no external research run. Community discovery (1.5): stack is GitHub Actions + bash, covered. Functional overlap (1.5b): no community overlap; inline recommended; three in-repo precedents named.

**Skill description budget (1.8):** no `SKILL.md` `description:` edit is candidate — skipped.
