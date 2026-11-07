---
title: "ci: S4 PR3b — make affected-index-ratchet required, ship oracle-review-required, and bound accept-row growth"
type: feat
date: 2026-11-07
slug: ci-s4-pr3b-required-ratchet-context
branch: feat-one-shot-10859-pr3b-required-context
issue: 10859
lane: cross-domain
brand_survival_threshold: none
---

# ci: S4 PR3b — required ratchet, oracle review, accept-row growth bound

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed). There is no spec.md for this branch.

## Overview

Issue #10859 (OPEN, labels `priority/p3-low`, `type/chore`, `domain/engineering`, `meta/machinery`) is the PR3b stage of the S4 affected-index series (#10448, #9729, ADR-276). All entry conditions are discharged: the #10865 observation window certified PASS on 2026-11-07 (probe retired by PR #12296), the canary and ceilings were ruled satisfied, the rename-carry design dissolved under strict zero, the cumulative baseline check reads 0 added lines (re-verified today; the file is deleted on `origin/main`), and the budget owner's go-ahead was recorded on the issue 2026-11-07 — the merge cite is that comment, which is the go-ahead receipt.

One commit ships three deliverables the batched CTO rulings of 2026-11-06 bound together:

1. **Required-context flip** — delete the job-level `continue-on-error` on `affected-index-ratchet` in `.github/workflows/ci.yml` and enroll the name in every required-context registry: `scripts/required-checks.txt`, `scripts/ci-required-ruleset-canonical-required-status-checks.json`, `infra/github/ruleset-ci-required.tf`, the count pin in `tests/scripts/test-audit-ruleset-bypass.sh` (T-rsc-7 literal 10→12), the `admin-merge-ready` fixtures, and `scripts/pr-fanout-ledger.txt`, with the committed bot-synthetic unreachability assertion. `scripts/probe-merge-group-coverage.sh` runs green before merge.
2. **`oracle-review-required`** — a new required context in the same commit (ruling (a)). New ci.yml job driven by `scripts/ci-oracle-review.sh`: on `pull_request`, a diff touching the oracle surface requires an APPROVED review by `deruelle` bound to the head SHA, or PR author `deruelle` (GitHub bars self-approval); on `merge_group`, per-member context success via the cla-verify enumeration machinery. Fail-closed on API failure.
3. **Accept-row growth bound** — ruling (b): the ratchet marker gains `accept=<n>`; new diff-scoped verdicts `accept-unattributed` and `accept-bad-kind` — every pair whose accept row-set differs base→HEAD must attribute to the diff (path touched, ref file touched, or oracle touched), and every added row must carry one of the six typed reason kinds.

## Problem Statement / Motivation

Today the `affected-index-ratchet` job is advisory: `continue-on-error: true`, absent from every required set. A red ratchet on a PR changes nothing — the merge gate does not read it — so a suite that names an undeclared tracked path can merge, and the audit's strict-zero property erodes one unreviewed PR at a time. PR3a deliberately shipped dark to observe; the window has now certified the job (1,197 units measured, p95 237 s under the final 240/285 ceilings, mean billed 3.47 min/unit) and the owner authorized the flip.

Two residuals the rulings bound to the same commit: (a) no required human review exists for the check's own oracle — a CODEOWNERS entry routes review but enforces nothing, and an accept row on a file the suite really reads is a false negative no automated control can see; (b) accept-file growth was notice-only — nothing stops a mid-window PR from adding rows that exempt real reads.

## Proposed Solution

One PR, one atomic edit set. The paired-edit contract (ADR-032) forbids staging: at no commit may a required name lack a producing job or any registry disagree with another, so the job changes, the registries, the pins, the fixtures, the driver, the verdicts and the docs land together.

## Technical Approach

### Workstream A — required-context flip and enrollment

- `.github/workflows/ci.yml`: delete `continue-on-error: true` from `affected-index-ratchet` (line ~521); update the header comment at line ~22 that names it "the one ADVISORY job". The job's `if: github.event_name == 'pull_request' || github.event_name == 'merge_group'` stays — it is the merge_group producer the coverage probe requires. `continue-on-error` and `required` are mutually destructive (a required job that cannot fail the run is decorative), so the deletion rides the same commit as the enrollment — never staged.
- `scripts/required-checks.txt`: add `affected-index-ratchet` and `oracle-review-required`, each with a #6049-convention disposition comment: both are CONTENT-SCOPED, sound-by-UNREACHABILITY — the composite action's `ALLOWED_PATHS = {knowledge-base/project/weakness-digest.md}` intersects neither the oracle path set nor the audit's read surface, so no bot PR can reach either gate's guarded surface. The unreachability is pinned by the new committed assertion below, not by prose.
- `scripts/ci-required-ruleset-canonical-required-status-checks.json`: two `{context, integration_id: 15368}` rows.
- `infra/github/ruleset-ci-required.tf`: two `required_check` blocks with dated history comments naming this issue and the disposition; the merge triggers `apply-github-infra.yml`, a whole-payload replace — verify `bypass_actors` and `conditions` unchanged by a read before and after (learning `2026-04-03-github-ruleset-put-replaces-entire-payload.md`).
- `tests/scripts/test-audit-ruleset-bypass.sh`: T-rsc-7 literal `10` → `12` plus the dated count-history comment (kept a literal deliberately — deriving it would make the assertion tautological).
- `plugins/soleur/test/fixtures/admin-merge-ready/`: `rules-branches-main.json` gains both contexts (15368); `check-runs.json` gains a completed/success run per new name on the fixture head SHA; `README.md` gains the dated recapture note; `admin-merge-ready.test.sh`'s "13 required contexts … 66 check runs" header comment is updated.
- `scripts/pr-fanout-ledger.txt`: ci.yml row — dated `+1` clause for `oracle-review-required` (`yaml.safe_load(ci.yml)['jobs']` 21 → 22) naming its consequence (a required context is not a foldable advisory lint; it cannot ride `lint-bot-statuses` because it must report independently, and it cannot fold into `oracle-index-check` because that leg exists only to validate the lane's manifest on oracle-only diffs while the review gate must fire on every PR and enumerate queue members on merge_group) — plus a wording touch-up where the ratchet clause still says "advisory until PR3b".
- `scripts/ci-push-dedupe.test.sh` `UNGATED_PINNED` and `scripts/ci-draft-light.test.sh` `LIGHT_PINNED`: add `oracle-review-required` in the hand-sorted positions (after `oracle-selection`, before `pr-selection`). `affected-index-ratchet` is already in both.
- `scripts/ci-pr-affected-replay.py` `ALWAYS_RUN_JOBS`: add `oracle-review-required` — it runs on every pull_request/merge_group like the ratchet, and the replay's historical-run classification must not read a red from it as `unclassified-job`.
- `scripts/ci-oracle-lane-suites.txt`: register `scripts/ci-oracle-review` in the oracle-validation manifest — the declared T3 membership criterion ("every registration whose SUT is the oracle/selector machinery") covers the review-gate driver once PR3b makes it part of the oracle control surface; the alternative, a committed exclusion note with reason, is rejected because the lane must validate the gate that guards the oracle on exactly the diffs the lane admits.

**Draft-light participation — re-examined as the issue requires.** Measured: ~3.4 billed min/run, ~2,250 min/week on draft pushes (+11% per draft push), inside the spend the owner accepted in #12129. Ruled (technical, recorded in `decision-challenges.md`): `affected-index-ratchet` and `oracle-review-required` stay OUT of the draft-light gated set — a required context must still report on drafts (the ready_for_review arm re-runs regardless, but a gated required job shows `Expected` on every draft push and the observation record shows drafts are the population where oracle diffs actually occur — oracle-repair drafts are the lane's stated workload). The lever exists for the four heavy families; a 3.4-min job does not meet its complexity price (a `needs:` edge plus an `if:` term on a required gate, where a gate that skips is a gate that does not report).

### Workstream B — `oracle-review-required` context and driver `scripts/ci-oracle-review.sh`

Job shape (ci.yml): `if: github.event_name == 'pull_request' || github.event_name == 'merge_group'`, `timeout-minutes: 5`, `permissions: contents: read, pull-requests: read`, `fetch-depth: 2`, env-only inputs, no `needs:` (parallel root; a required context adds no declared-path length).

Driver contract:

- **pull_request arm.** Classify the diff against the oracle surface: `git diff --name-only <merge-ref>^1 <merge-ref>` intersected with `RATCHET_ORACLE` — extracted at runtime from the **base** copy of `scripts/ci-pr-affected-replay.py` (`git show <base>:scripts/ci-pr-affected-replay.py` imported by a pinned python one-liner that prints the tuple), so the list has one source of truth and a PR cannot shrink the list that judges it ("parity-pinned" by construction; the suite pins the extraction against `RATCHET_ORACLE` in both directions). The driver itself is base-sourced on pull_request (`git show <base>:scripts/ci-oracle-review.sh` into `$RUNNER_TEMP`; when the base lacks the file — every pre-PR3b base — the check runs the HEAD copy but classification still uses the base `RATCHET_ORACLE`, and the base-missing case is covered by the author/approval arms, never a silent pass).
  - Oracle diff ∧ author==`deruelle` → PASS (self-approval is barred by GitHub; without this arm owner-authored oracle PRs deadlock).
  - Oracle diff ∧ ≥1 APPROVED review by `deruelle` whose `commit_id` equals the PR head SHA → PASS. Reviews are read via `gh api repos/{repo}/pulls/{n}/reviews` (paginate, fail-closed over the read bound); a review on any earlier SHA does not bind the head.
  - Otherwise → FAIL with the verdict line naming the missing control.
  - No oracle diff → PASS (a required context must report success when its gate is untriggered).
- **merge_group arm.** No diff classification — the batch's diff is not the review surface. Enumerate queue members via the cla-verify machinery (the `MQ_QUERY` entries(first:100) enumeration + anchor binding of `merge-queue-cla-verify.sh:89-181`, copied with a byte-equality parity pin in the suite — the O-DOCPARITY precedent), then for each member require the latest `oracle-review-required` check-run on the member's queued head (`headRefOid`) — github-actions app id 15368, highest check-run `id` wins — to be `completed/success`. Zero members, truncation, an unbindable anchor, or a missing/red member context is a failure, never a pass.
- **Fail-closed on API failure** per the ruling: any `gh api` non-zero, unpaginated page bound hit, or unparseable shape is a FAIL verdict naming the class — never a green.
- Output: one `SOLEUR_ORACLE_REVIEW event=<e> oracle_diff=<0|1> author=<login> approved=<0|1> members=<n> verdict=<pass|fail> reason=<token>` line, literals only (no paths, SHAs or review URLs in annotations — the ci-oracle-lane annotation contract).

RATCHET_ORACLE gains `scripts/ci-oracle-review.sh` and `scripts/ci-oracle-review.test.sh` — the check's own machinery is itself oracle surface, so a diff weakening the review gate cannot self-approve quietly.

### Workstream C — accept-row growth bound (ruling b)

- `scripts/ci-pr-affected-replay.py`:
  - `ratchet_marker` gains ` accept=<n>` — `n` = the count of parsed accept data rows (non-comment, non-blank lines, `*` rows included) — after `baseline=<n>`. Docstring grammar at :162 updated in the same edit.
  - In `ratchet_run`, after `ratchet_base` resolves the base SHA, read the **base** accept file through the same confined reader; diff each pair's row-set base→HEAD. Every pair whose row-set differs must attribute to the diff — `path ∈ touched` OR `ref_files(pair) ∩ touched ≠ ∅` OR oracle touched — else finding `accept-unattributed` (exit 1). Every row present on the head side whose (suite,path,anchor,ordinal) key is absent from base OR whose reason differs must carry one of the six typed kinds — `message`, `JSDoc/comment`, `PR-body string`, `help/menu text`, `data row not fed to a read loop`, `code line in a file read only as text` (canonical list at runbook `ci-pr-affected-activation.md` line ~244) — else finding `accept-bad-kind` (exit 1). Diff-scoped by design: legacy non-conforming rows (`fixture:`-prefixed and free-form reasons in today's 3,000+ rows) are never re-litigated; only the delta is judged.
  - `RATCHET_REMEDY_NEW`'s line "no required review exists in this repository's ruleset" is rewritten — `oracle-review-required` is that required review now.
- Consumers of the marker grammar, same commit: `plugins/soleur/test/ci-pr-affected-replay.test.sh` `rt_marker` (grammar pin extended to ` accept=[0-9]+`), the docstring, and the runbook's marker documentation. The ci.yml reason extractor (`sed 's/^SOLEUR_PR_AFFECTED_RATCHET exit=[0-9]* reason=\([a-z0-9-]*\) .*/\1/p'`) tolerates the trailing field already (`.*` tail); the step comment is updated to name the field. The ruling's cited consumer `scripts/followthroughs/ratchet-observation-window-10865.sh` `MARKER_RE` is gone — the probe was retired 2026-11-07 (PR #12296); the surviving grammar consumers are the three above.
- New suite `scripts/ci-oracle-review.test.sh` covering the driver (stub `gh`: oracle-diff arms, author arm, approved-SHA binding including stale-SHA rejection, merge_group member enumeration incl. hasNextPage die, missing-context fail, API-failure fail-closed, annotation-literal grammar). Registered per the machinery below.

### Registration and the recursive ratchet tax

The new suite names repo paths; every registered suite's named paths become audit pairs. In the same commit:

- `scripts/test-all.sh`: `run_suite "scripts/ci-oracle-review" bash scripts/ci-oracle-review.test.sh` (the `--enumerate` label `scripts/ci-oracle-review`).
- `scripts/suite-shard-legs.tsv`: regenerated via `scripts/regenerate-shard-manifest.py`, never hand-edited.
- `scripts/lib/test-affected-paths.sh`: `AFFECTED_*_PATHS` edges for the paths the suite executes/reads (`scripts/ci-oracle-review.sh`, `.test.sh`, `merge-queue-cla-verify.sh` as parity source, `ci-pr-affected-replay.py`); named-but-unread paths get anchor-keyed accept rows in `scripts/ci-pr-affected-audit.accept.tsv` with one of the six typed kinds (the same kinds this PR begins enforcing — eating our own cooking).
- The PR must keep the advisory ratchet green on its own diff — the merge_group run of this very PR is the first run where a red ratchet is a gate failure.

## Research Insights

- **Relevant files** (verified on this branch): `.github/workflows/ci.yml` (`affected-index-ratchet` job ~519-569, `continue-on-error` :521, header :22, reason extractor :547); `scripts/required-checks.txt` (#6049 disposition convention, 10 CI names); `scripts/ci-required-ruleset-canonical-required-status-checks.json` (10 rows, all 15368); `infra/github/ruleset-ci-required.tf` (10 `required_check` blocks + merge_queue block + hard precondition note); `tests/scripts/test-audit-ruleset-bypass.sh` (T-rsc-7 literal `10` :718, T-rsc-9 canonical↔TF parity, CANONICAL_RSC fixture :525); `plugins/soleur/test/fixtures/admin-merge-ready/` (rules-branches-main.json 11 CI+2 CLA, check-runs.json 66 runs, README); `scripts/pr-fanout-ledger.txt` (ci.yml row jobs=21); `scripts/ci-push-dedupe.test.sh` `UNGATED_PINNED` :144; `scripts/ci-draft-light.test.sh` `LIGHT_PINNED` :110; `scripts/ci-pr-affected-replay.py` (`RATCHET_ORACLE` :1757, `ALWAYS_RUN_JOBS` :199, `ratchet_marker` :1951, `ratchet_run` :1994, `judge_rules` :1590, `RATCHET_REMEDY_NEW` :1763); `plugins/soleur/test/ci-pr-affected-replay.test.sh` (`rt_marker` :2332); `scripts/merge-queue-cla-verify.sh` (enumeration :89-181); `scripts/probe-merge-group-coverage.sh` (offline producer probe); `.github/actions/bot-pr-with-synthetic-checks/action.yml` (`ALLOWED_PATHS` :230 = `{knowledge-base/project/weakness-digest.md}`); `scripts/ci-oracle-lane-suites.txt` (manifest + sentinel); `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` (advisory wording :163-179, observation log :269-284, six kinds :244); `ADR-276` (`### Stage status`, amendment convention).
- **Institutional learnings:** `2026-03-20-github-required-checks-skip-ci-synthetic-status.md` and `2026-03-23-skip-ci-blocks-auto-merge-on-scheduled-prs.md` (required name ⇒ synthetic pair); `2026-04-03-github-ruleset-put-replaces-entire-payload.md` (verify bypass_actors/conditions pre+post apply); `2026-06-30-github-merge-queue-adoption-wire-all-ruleset-producers.md` (every required context needs a merge_group producer — the probe is the gate); `2026-03-19-github-ruleset-stale-bypass-actors.md`; `2026-05-11-plan-review-caught-git-log-union-trap-and-cross-module-field-assumption.md`; sharp edges — "non-required did not mean decoupled" (`continue-on-error` is what decouples, and it is mutually destructive with `required` — delete in the same change) and "a fail-closed change is not done until its most natural repair is also refused" (the driver must not pass on `gh` misuse flags, missing env, or empty enumerations).
- **Premise Validation (Phase 0.6):** #10859 OPEN with the 2026-11-07 go-ahead comment as the last comment — held. #10865 closed; probe retired — the ruling's cited `MARKER_RE` consumer no longer exists (substituted per Workstream C). `scripts/ci-pr-affected-audit.baseline.tsv` absent on `origin/main`; cumulative check re-verified today = 0 added lines. Cited machinery all present: `RATCHET_ORACLE`, `judge_rules`, `merge-queue-cla-verify.sh:89-181` enumeration, `ALLOWED_PATHS`, `probe-merge-group-coverage.sh`, `rt_marker` pin. Collision precheck: only own draft PR #12329; foreign `test-all.sh` runs on a sibling worktree noted. ADR-corpus mechanism check: the review-gate mechanism was itself ruled in the 2026-11-06 comment (literal ruleset arm inexpressible — `require_code_owner_review` is not path-scoped — and written acceptance leaves the residual uncontrolled).
- **Property List (Phase 0.6b):** (P1) a suite naming an undeclared tracked path cannot merge; (P2) an oracle-surface diff cannot merge without a bound owner-review act or owner authorship; (P3) accept-row growth must attribute provenance and carry a typed kind; (P4) every required name exists in all registries with a merge_group producer, mechanically pinned; (P5) a bot PR's synthetic green is provably unreachable by the surfaces both gates read.
- **Cut List (Phase 0.6b):** (a) literal ruleset `require_code_owner_review` — property P2, already rejected by the ruling (not path-scoped); (b) a separate `oracle-review` workflow — P2 covered by the ci.yml job the ruling names, and a second producer would trip the coverage probe's exactly-one-producer rule; (c) a new shared enumeration lib extracted from `merge-queue-cla-verify.sh` — property "member enumeration correctness" is already covered by a parity-pinned copy (O-DOCPARITY precedent) at lower blast radius; (d) `WALL_DISCHARGE_ISSUE=12129` probe amendment — already landed (#12258) and then retired with the probe.
- **Value-proposition measurement (0.6c):** this PR claims no saving; it adds cost (~3.4 billed min/run for the ratchet, seconds for the review job) — the spend was measured and owner-accepted in #12129 and the 2026-11-06 comment. Numbers carried: p95 237 s / max 317 s over 1,197 units; ~4,400 min/week, ~2,250 on drafts.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| "the probe `MARKER_RE` (`ratchet-observation-window-10865.sh:161`)" (ruling b) | file deleted on main by PR #12296 after the window certified PASS | marker consumers reduced to replay docstring, `rt_marker` pin, ci.yml extractor (tolerant), runbook — updated in Workstream C |
| "PR 12300 touches adjacent ci.yml/ruleset surface" (scope context) | its files are `ci-oracle-lane.sh`, `ci-oracle-lane.test.sh`, ADR-276 — not ci.yml or the ruleset | overlap is ADR-276 append + RATCHET_ORACLE membership (lane files already inside it); rebase-order note in Sibling PR Overlap |
| "canonical JSON, count pin" | T-rsc-7 is a hand-maintained literal (`10`), not a derived count | literal → `12` with the dated history comment, per the file's own convention |
| "admin-merge-ready fixtures" | fixture keeps a deliberate CodeQL/57789 negative row; "13 contexts" comment | add both names at 15368 + green runs; do not disturb the CodeQL negative row |

## Implementation Phases

### Phase 1 — driver + verdicts (the check that must exist before it is required)

- `scripts/ci-oracle-review.sh` + `scripts/ci-oracle-review.test.sh`; replay `ratchet_run` accept-diff + `accept=` marker + `accept-unattributed`/`accept-bad-kind` findings; replay suite rows (`rt_marker` grammar, verdict mutation rows); registration (test-all.sh, suite-shard-legs via generator, edges + accept rows, manifest membership).
- Success: `bash scripts/ci-oracle-review.test.sh` green; `python3 -I scripts/ci-pr-affected-replay.py ratchet` green on this branch; suite census/arm re-tiles pass.

### Phase 2 — enrollment (the paired-edit commit)

- ci.yml (`continue-on-error` deletion + `oracle-review-required` job + header comment), required-checks.txt, canonical JSON, ruleset TF, T-rsc-7, fixtures, ledger, UNGATED/LIGHT pins, ALWAYS_RUN_JOBS, unreachability assertion test.
- Success: `bash tests/scripts/test-audit-ruleset-bypass.sh`, `bash plugins/soleur/test/required-checks-canonical-parity.test.sh`, `bash plugins/soleur/scripts/admin-merge-ready.test.sh`, `bash plugins/soleur/test/pr-fanout-ledger.test.sh`, `bash scripts/ci-push-dedupe.test.sh`, `bash scripts/ci-draft-light.test.sh`, `bash plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh`, `bash scripts/probe-merge-group-coverage.sh` all green.

### Phase 3 — docs + ADR + observation

- Runbook rewrite (advisory→required, oracle-review section, marker grammar, observation-log line for the first required run's check-list rendering), ADR-276 dated amendment, `RATCHET_REMEDY_NEW` text, ledger wording.
- Success: runbook's "Until PR3b the job is advisory" gone; ADR Stage-status line appended; `grep -c 'no required review exists' scripts/ci-pr-affected-replay.py knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` = 0 outside history quotes.

### Phase 4 — pre-ready verification

- Full relevant battery (`test-all.sh --affected` resolves to the full battery here — `test-affected-paths.sh` is a runner trigger); `git diff 45f0b096ffabf94d1b9abc49ef9a039648f4b758 origin/main -- scripts/ci-pr-affected-audit.baseline.tsv` re-run = 0 added lines; `scripts/probe-merge-group-coverage.sh` output quoted in the PR body; first real `pull_request` run's check-list rendering (both contexts present, `affected-index-ratchet` required and green, `oracle-review-required` green via author/approval arm) recorded in the runbook observation log in the same PR or the immediate follow-up comment.

## Alternative Approaches Considered

| Alternative | Why rejected |
|---|---|
| Ruleset `require_code_owner_review` | Ruled inexpressible 2026-11-06: not path-scoped; `* @deruelle` would force review on every PR |
| Written owner acceptance of the review residual | Leaves residual 5(a) permanently uncontrolled — ruled against |
| Two PRs (flip, then oracle-review) | The owner named one PR3b commit; splitting also violates the paired-edit contract's spirit (a required ratchet with no oracle control is the hole the rulings closed) |
| Extract the member enumeration into `scripts/lib/` shared by both drivers | Higher blast radius on a live production script; parity-pinned copy is the repo's own O-DOCPARITY precedent |
| Gate the two checks on draft pushes | A required context that skips does not report; cost (~3.4 min) inside accepted spend — ruled in decision-challenges.md |

## User-Brand Impact

- **If this lands broken, the user experiences:** a merge-queue or PR check wedge — a required context that never reports leaves every entry pending (the 2026-06-30 deadlock class), or a false-failing `oracle-review-required` blocks owner-authored oracle repairs; blast radius is this repository's engineering flow, not product end-users.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no data exposure surface — the driver reads PR review/file metadata (already repo-internal) and writes a check-run conclusion; a mis-scoped permission (`checks: write`) is deliberately NOT granted.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the harm class is a wedged internal merge gate with a committed break-glass runbook (admin merge + revert recipe), not a user-facing incident; a `threshold: none` matches the PR3a ruling for the same machinery.

## Observability

```yaml
liveness_signal:
  what:            the two required contexts themselves — `affected-index-ratchet` and `oracle-review-required` report on every pull_request and merge_group run; an absent context pends the queue entry (self-signaling, the opposite of a silent dark surface)
  cadence:         per CI run
  alert_target:    merge-queue stall surface — `merge-queue-stall-check.yml` already names the workflow whose merge_group run never reported
  configured_in:   .github/workflows/ci.yml + infra/github/ruleset-ci-required.tf
error_reporting:
  destination:     the check-run conclusion + `::error title=...::` annotation on the run; fail-closed by construction
  fail_loud:       a red required context on the PR check list / queue ejection with the driver's `reason=<token>` line
failure_modes:
  - mode:          oracle-review API/enumeration failure (gh api error, pagination bound, unbindable anchor)
    detection:     check-run FAIL with `reason=<api|pagination|anchor|member-context>` token
    alert_route:   PR check list + queue ejection — the author sees it on the merge path
  - mode:          ratchet red after the flip (new pair, stale-accept, accept-unattributed, accept-bad-kind)
    detection:     required-context failure + `::error title=affected-index-ratchet::exit=<1|2> reason=<token>`
    alert_route:   PR check list — blocks merge by design; break-glass = admin merge + the runbook's revert recipe
logs:
  where:           job log + `GITHUB_STEP_SUMMARY` marker/summary blocks (SOLEUR_PR_AFFECTED_RATCHET, SOLEUR_ORACLE_REVIEW)
  retention:       GitHub run-log retention (90 days)
discoverability_test:
  command:         bash scripts/probe-merge-group-coverage.sh
  expected_output: merge-group-coverage=OK
```

## Encryption Posture

```yaml
at_rest:
  - store:             none introduced — a GitHub ruleset amendment is configuration, not a persistent data store; Terraform state for this root already lives in the existing encrypted backend this root uses
    mechanism:         no store to encrypt — the resource is a ruleset object at GitHub
    evidence:          infra/github/ruleset-ci-required.tf declares no volume/bucket/table/queue/cache/sink
    defends_against:   nothing — no new store exists whose contents could be read
    does_not_defend:   the ruleset's required-context list — its integrity is carried by the canonical-JSON parity gates and the pre-apply by-value gate, not by encryption
    disclosed_as:      GitHub branch-protection configuration in repo IaC — no data classification applies
    live_verification: terraform plan diff reviewed by apply-github-infra.yml's pre-apply gate before apply
in_transit:
  - connection:        oracle-review driver (GH runner) -> api.github.com (PR reviews, files, queue enumeration, check-runs)
    enforced_at:       scripts/ci-oracle-review.sh gh api calls
    tls:               https (TLS 1.2+ via gh CLI)
    cert_verification: on
    does_not_defend:   a compromised GITHUB_TOKEN itself (token scope is the bound: contents:read + pull-requests:read)
    disclosed_as:      not-publicly-claimed
```

## Task Design

```yaml
tasks:
  - task:            oracle-review-required (required check context)
    trigger:         pull_request and merge_group events on ci.yml
    services:        reads GitHub REST (PR reviews, files, merge-queue entries, check-runs); writes its own check-run conclusion via job exit status
    next:            nothing — a terminal verdict; a red blocks the merge path only
    human_reentry:   approve the PR as deruelle / re-push (new head SHA re-binds review) / admin-merge break-glass per runbook
    dedupe:          verdict is bound to the exact head SHA (commit_id match) and, on merge_group, to queue position + headCommit.oid — a stale approval or stale member context cannot satisfy it
    source_dedupe:   not a ticket source
```

## Guard Contract

### Guard 1 — required-context enrollment parity

**Property.** Every name in the CI Required ruleset's required-status-check set exists in all five registries and has exactly one merge_group producer.

**Assembly.** The four file registries (required-checks.txt, canonical JSON, ruleset TF, fixture set) plus live apply — chokepoints: `required-checks-canonical-parity.test.sh` Test 1 (file↔canonical both directions), T-rsc-7 literal + T-rsc-9 (canonical↔TF), `probe-merge-group-coverage.sh` (producer existence, event-`if:` grammar), the daily live↔canonical audit.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add the context to the JSON but not required-checks.txt | RED (parity Test 1 ⊇ arm) |
| 2 | Enroll a name with no merge_group producer (job `if:` excludes merge_group) | RED (probe-merge-group-coverage) |
| 3 | Enroll both names in JSON/TF but leave T-rsc-7 literal at 10 | RED (count literal is the acknowledgement) |
| 4 | Harness: drop the new `oracle-review-required` row from canonical AND the TF in the same fixture — suite must still fail (anti-vacuity: the guard reads the files, not a hand list) | RED |
| 5 | Must-PASS non-canonical: the 12-context set with CodeQL still absent and all 15368 | PASS |

**Anchor.** `probe-merge-group-coverage.sh` reads the canonical JSON + workflow files, and `apply-github-infra.yml` re-verifies the live ruleset against the TF — a diff weakening both in one PR would still fail the live audit's `removed` arm; the count literal requires a deliberate human bump.

### Guard 2 — oracle-review-required

**Property.** An oracle-surface diff merges only after a bound owner-review act (APPROVED review by deruelle on the head SHA) or owner authorship; never on an unverifiable read.

**Assembly.** `scripts/ci-oracle-review.sh` (both event arms) + its base-sourced RATCHET_ORACLE extraction + the member enumeration copy; chokepoint is the single driver — both events route through it.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Oracle-path diff, no deruelle approval, author != deruelle | RED |
| 2 | Approval present but bound to a stale head SHA | RED |
| 3 | Merge_group member enumeration returns zero members / hasNextPage / member context missing | RED (no vacuous pass) |
| 4 | `gh api` exits non-zero on any read | RED (fail-closed) |
| 5 | Driver skips itself: PR edits `scripts/ci-oracle-review.sh` to shrink the oracle list — base-sourced list still classifies the diff oracle-touching | RED-without-review |
| 6 | Must-PASS: non-oracle diff; oracle diff + deruelle approval on head SHA; oracle diff + author=deruelle | PASS |
| 7 | Harness: stub `gh` emits a malformed reviews payload | RED |

**Anchor.** The classification list is read from the base commit's replay file at runtime — a PR editing the list cannot shrink the surface that judges it.

### Guard 3 — accept-row growth verdicts

**Property.** Every accept row-set change attributes to the diff and every added row carries a typed kind.

**Assembly.** `ratchet_run`'s base→HEAD accept row-set comparison — chokepoint is the one code path that already loads both images (ratchet_base + load_accept); kinds pinned to the runbook's canonical six.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add an accept row with no touched path/ref/oracle | RED (accept-unattributed) |
| 2 | Add a row attributing correctly but reason `false-positive: vibes` | RED (accept-bad-kind) |
| 3 | Add a second unattributed row after a compliant first | RED (second-member — a loop that stops at the first is the defect) |
| 4 | Marker emitted without ` accept=` field | RED (rt_marker grammar pin) |
| 5 | Harness: base accept file unreadable mid-comparison | exit 2 (infra), never a pass |
| 6 | Must-PASS: a row added with a typed kind whose ref file the diff also touched | PASS |

**Anchor.** The verdict reads the base image through `ratchet_base` on the confined reader — the same trusted path the baseline reads, not the PR's tree copy.

### Guard 4 — bot-synthetic unreachability

**Property.** No bot-PR-writable path intersects the surfaces either new required context reads.

**Assembly.** `.github/actions/bot-pr-with-synthetic-checks/action.yml` `ALLOWED_PATHS` (the chokepoint every bot write flows through) vs `RATCHET_ORACLE` (for oracle-review-required) and the audit's read surface — the files whose content the audit reads, exposed under `--all-refs` (for affected-index-ratchet; `knowledge-base/project/weakness-digest.md` is named by gap pairs and a data file, so disjointness is re-derived, not assumed — if the assertion fails, the remedy is reproducing the gate in the action's Phase-4 preflight, per the #6049 convention, never widening ALLOWED_PATHS to overlap).

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a RATCHET_ORACLE member to ALLOWED_PATHS in the fixture | RED |
| 2 | Point the assertion at a synthetic ALL_PATHS list disjoint by construction | RED (harness — the test parses the real action.yml + real oracle list) |
| 3 | Add a second ALLOWED_PATHS member that lands inside the audit read surface | RED |
| 4 | Must-PASS: current real ALLOWED_PATHS vs current surfaces | PASS |

**Anchor.** The assertion reads the action's own file and the replay's own tuple — two artifacts a weakening PR would have to edit together, and editing either is an oracle diff requiring review (Guard 2 — the layers hold each other).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "delete the job-level continue-on-error of affected-index-ratchet" | Phase 2 ci.yml edit | mapped |
| 2 | "add the name to scripts/required-checks.txt, the canonical JSON, infra/github/ruleset-ci-required.tf, the count pin, the admin-merge-ready fixtures, tests/scripts/test-audit-ruleset-bypass.sh and scripts/pr-fanout-ledger.txt" | Phase 2 edit set | mapped |
| 3 | "with the bot-synthetic unreachability assertion" | Guard 4 + Phase 2 assertion test | mapped |
| 4 | "run scripts/probe-merge-group-coverage.sh before merging" | Phase 4 + AC | mapped |
| 5 | "re-examine draft-light participation with the measured draft-push minutes" | Workstream A ruling + decision-challenges.md | mapped |
| 6 | "a new required context oracle-review-required ships in the PR3b commit (ci.yml + scripts/required-checks.txt + canonical JSON + infra/github/ruleset-ci-required.tf). Driver scripts/ci-oracle-review.sh" | Workstream B | mapped |
| 7 | "on merge_group, per-member context success via the cla-verify enumeration machinery" | merge_group arm | mapped |
| 8 | "marker gains accept=<n> … new diff-scoped verdicts accept-unattributed/accept-bad-kind" | Workstream C | mapped |
| 9 | "record the first real PR3b run's check-list rendering in the runbook observation log" | Phase 3/4 + AC | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|---|---|---|
| New suite `scripts/ci-oracle-review.test.sh` + registration chain (test-all.sh, shard-legs, edges, accept rows, manifest) | — | inferred — justification: every driver in this repo ships a registered suite, and registering is what feeds the audit the pairs this PR's own ratchet must drain |
| `ALWAYS_RUN_JOBS`/`UNGATED_PINNED`/`LIGHT_PINNED` membership | — | inferred — justification: the classification suites redden on an unpinned new job (G-UNCLASSIFIED); the pins are the enrollment's mechanical consequence |
| admin-merge-ready `check-runs.json` + README edits | "the admin-merge-ready fixtures" | asked |
| base-sourced driver + base RATCHET_ORACLE extraction | — | inferred — justification: oracle-lane precedent — a PR must never rewrite the classifier that judges it |
| RATCHET_ORACLE gaining the two new files | — | inferred — justification: the review gate is part of the oracle surface it guards |
| `RATCHET_REMEDY_NEW` + runbook advisory-text rewrite | — | inferred — justification: both texts assert "no required review exists", which this PR falsifies |

### Split Assessment

- Subsystems touched: 5 — `.github`, `scripts`, `infra`, `plugins/soleur`, `tests` (+ `knowledge-base` docs)
- Planned files: ~24 | Estimated changed lines: ~1,400 (dominated by the new driver + suite)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — over two thresholds, but the paired-edit contract (ADR-032) requires atomicity: at no commit may a required name lack a producer or a registry disagree; the owner named one commit. The alternative split lands the required flip without its oracle control, re-opening the residual the rulings closed.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** Merge-governance architecture change: two new required contexts, a new fail-closed gate over the oracle surface, and a trust-boundary edit (the merge gate's composition). Blast radius is the repo's merge path — a missing producer wedges the queue (committed probe is the guard); a false-positive review gate blocks owner repairs (author arm is the release valve); a whole-payload ruleset apply is the irreversible step (pre/post verification is the receipt). (Leader-spawn fan-out unavailable in this harness — inline assessment against the same checklist.)

No other domain's assessment question matches: no UI surface (Product/UX override: zero `components/**/*.tsx`/`app/**/page.tsx`/`layout.tsx` in Files to Create/Edit → NONE), no regulated-data surface (Legal/GDPR skip — the driver reads PR review metadata, not session-derived data; no LLM; no new distribution surface), no vendor/procurement (Operations), no marketing/sales/finance/support surface.

## Architecture Decision (ADR/C4)

### ADR

- Amend `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md` — append a dated amendment recording: PR3b landed (ratchet required; `continue-on-error` removed), item-9 dispositions ((a) oracle control shipped as `oracle-review-required`; (b) accept-growth bound shipped — `accept=<n>` + two verdicts; (c) verified clean at merge; (d) rename-carry dissolved; (e) canary+ceilings satisfied; window leg discharged via #12129; (f) go-ahead receipt comment), and the `### Stage status` line update. Append-only, dated, no edit of earlier text — the same-file sibling is open PR #12300's lane-activation amendment; keep both.

### C4 views

Enumerated against all three model files (`model.c4`, `views.c4`, `spec.c4`): (a) external human actors — `deruelle` as PR reviewer is already covered by the `founder` actor's approval edges (e.g. `founder -> github` approval relationships at model.c4:583-584); the new check consumes the SAME approval act, it adds no actor; (b) external systems — GitHub Actions/API is the existing `github` element; no new vendor; (c) containers/data-stores — none added (a check-run is GitHub-side state, already modeled by the CI edges); (d) access relationships — the review-requirement is a property of an existing edge, not a new edge. **No C4 edit required** — the enumeration, not a keyword grep, is the basis.

### Sequencing

The ADR text describes the post-merge state (required set = 12) and lands in the same commit as the flip — no `adopting` lag.

## Files to Edit

- `.github/workflows/ci.yml` (drop `continue-on-error`; add `oracle-review-required` job; header comment; extractor comment)
- `scripts/required-checks.txt` (two names + per-name #6049 dispositions)
- `scripts/ci-required-ruleset-canonical-required-status-checks.json` (two rows, 15368)
- `infra/github/ruleset-ci-required.tf` (two `required_check` blocks + dated comments)
- `tests/scripts/test-audit-ruleset-bypass.sh` (T-rsc-7 literal 10→12 + history comment)
- `plugins/soleur/test/fixtures/admin-merge-ready/rules-branches-main.json`, `check-runs.json`, `README.md`
- `plugins/soleur/scripts/admin-merge-ready.test.sh` (header counts comment)
- `scripts/pr-fanout-ledger.txt` (ci.yml row 21→22 dated clause + advisory-wording touch-up)
- `scripts/ci-push-dedupe.test.sh` (`UNGATED_PINNED`), `scripts/ci-draft-light.test.sh` (`LIGHT_PINNED`)
- `scripts/ci-pr-affected-replay.py` (marker `accept=`, accept-diff verdicts, docstring, RATCHET_REMEDY_NEW, RATCHET_ORACLE +2, ALWAYS_RUN_JOBS +1)
- `plugins/soleur/test/ci-pr-affected-replay.test.sh` (`rt_marker` grammar, verdict rows, census re-pins/arm re-tile)
- `scripts/lib/test-affected-paths.sh` (edges for the new suite/driver)
- `scripts/ci-pr-affected-audit.accept.tsv` (anchor-keyed rows for the new suite's named-but-unread paths — as the ratchet demands; every row carries one of the six typed kinds)
- `scripts/test-all.sh` (`run_suite` line)
- `scripts/suite-shard-legs.tsv` (via `scripts/regenerate-shard-manifest.py` only)
- `scripts/ci-oracle-lane-suites.txt` (manifest membership row)
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md` (append-only)

Glob check: every path above verified with `git ls-files` on this branch (all exist; the two Create paths below are new).

## Files to Create

- `scripts/ci-oracle-review.sh` (the driver)
- `scripts/ci-oracle-review.test.sh` (its suite)
- `knowledge-base/project/specs/feat-one-shot-10859-pr3b-required-context/{tasks.md,decision-challenges.md}` (pipeline artifacts)

Explicitly NOT edited (pinned by AC): `scripts/merge-queue-cla-verify.sh` (copied-by-parity, not modified), `.github/actions/bot-pr-with-synthetic-checks/action.yml` (unless the Guard-4 assertion fails — then Phase-4 preflight work enters via the recorded branch, still no ALLOWED_PATHS widening), `apps/web-platform/server/inngest/functions/_cron-safe-commit.ts` (`SYNTHETIC_CHECK_NAMES` verbatim-pinned at 6 — the re-vendor path runs real CI and must never gain these names), `scripts/ci-required-ruleset-canonical-bypass-actors.json`, `CI_PR_AFFECTED`, the activation lock, PR D (#10414).

## Sibling PR Overlap

Verified `gh pr list --state open` × files on 2026-11-07 (46 PRs): **#12300** (oracle fast-lane activation) — ADR-276 append collision + it edits `ci-oracle-lane.*` (already inside RATCHET_ORACLE, so post-merge those diffs need owner review — intended). **#12295** (duplicate-YAML-key guard) — edits `required-checks.txt` (comment + members line), `pr-fanout-ledger.txt` (pr-quality-guards row), `ci-pr-affected-audit.accept.tsv`, CODEOWNERS: textual-merge risk on the two shared files; whichever lands second rebases. **#7390** (WIP) — ci.yml + test-affected-paths.sh + suite-shard-legs.tsv + test-all.sh: regenerate shard-legs on the rebased tree if it lands first. **#9640, #6778** (WIP) — test-all.sh run_suite region. Re-run this sweep at Phase 4.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (≤200) searched with `jq --arg path` over every file in `## Files to Edit`/`## Files to Create`: no open issue names any of them (ran 2026-11-07).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `git grep -n 'continue-on-error' -- .github/workflows/ci.yml` shows no occurrence inside the `affected-index-ratchet` job extent; the `oracle-review-required` job exists with `if:` covering pull_request and merge_group and `permissions:` limited to `contents: read, pull-requests: read`.
- [ ] `jq 'length'` of the canonical JSON = 12; `jq -r '.[].context'` sorted equals the `context` set grepped from `infra/github/ruleset-ci-required.tf` and the CI-subset of `scripts/required-checks.txt` (T-rsc-9 + parity Test 1 pass locally).
- [ ] `bash tests/scripts/test-audit-ruleset-bypass.sh` green with the T-rsc-7 literal at 12.
- [ ] `bash plugins/soleur/test/required-checks-canonical-parity.test.sh`, `plugins/soleur/scripts/admin-merge-ready.test.sh`, `plugins/soleur/test/pr-fanout-ledger.test.sh`, `scripts/ci-push-dedupe.test.sh`, `scripts/ci-draft-light.test.sh`, `plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` all green.
- [ ] `bash scripts/probe-merge-group-coverage.sh` prints `merge-group-coverage=OK contexts=12` and exit 0; the output is quoted in the PR body.
- [ ] `python3 -I scripts/ci-pr-affected-replay.py ratchet` exits 0 on this branch with marker `SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass live=<n> baseline=0 accept=<n>` — every pair the new suite names is drained (edge or accept row) in this commit.
- [ ] `bash scripts/ci-oracle-review.test.sh` green — mutation rows: oracle-diff-no-approval RED; stale-SHA approval RED; member-enumeration zero/hasNextPage/missing-context RED; `gh` failure RED; non-oracle diff PASS; deruelle-author and bound-approval PASS.
- [ ] The unreachability assertion test parses ALLOWED_PATHS from the real `action.yml` and `RATCHET_ORACLE` from the real replay file; both intersections are empty on this tree (or the action Phase-4 preflight reproduction shipped instead, per Guard 4's recorded branch).
- [ ] `grep -c 'no required review exists' scripts/ci-pr-affected-replay.py` = 0 (the stale remedy line is rewritten); runbook contains no present-tense "advisory" claim about `affected-index-ratchet` outside dated history.
- [ ] `SYNTHETIC_CHECK_NAMES` in `_cron-safe-commit.ts` unchanged (the verbatim-list test stays green without edit).
- [ ] ADR-276 carries a dated amendment + Stage-status line; the diff to the file is append-only.
- [ ] `git diff 45f0b096ffabf94d1b9abc49ef9a039648f4b758 origin/main -- scripts/ci-pr-affected-audit.baseline.tsv` re-run immediately before merge: `grep -c '^+[^+]'` = 0.

### Post-merge (operator)

- [ ] `apply-github-infra.yml` ran and its verify step shows the live ruleset's required_status_checks = the 12 names; `bypass_actors` and `conditions` read unchanged before and after (whole-payload replace receipt, recorded as a PR comment).
- [ ] First real `pull_request` run post-flip: both contexts present on the check list; `affected-index-ratchet` concluded `success` as a required check; `oracle-review-required` green via the author/approval arm; rendering recorded in the runbook observation log.
- [ ] `gh issue close 10859` with a comment citing this PR and the go-ahead receipt comment of 2026-11-07. (PR body uses `Closes #10859` — the merge IS the remediation; no post-merge step remains once the apply verifies.)
- [ ] Automation: not feasible for the ruleset post-apply read only in the sense that it is already automated — `apply-github-infra.yml`'s own verify step performs it; the operator step is reading its output, which `gh run view` covers.

## Test Scenarios

- Given a PR whose diff touches `scripts/ci-pr-affected-audit.accept.tsv` and no other oracle input, when `ci-oracle-review.sh` runs on pull_request with no deruelle approval and author `alice`, then exit non-zero with `reason=review-required` (unit, stub `gh`).
- Given the same diff with an APPROVED review by `deruelle` whose `commit_id` is an earlier head SHA, then exit non-zero `reason=stale-approval` (unit).
- Given a merge_group event whose enumeration returns a member missing the `oracle-review-required` context, then exit non-zero `reason=member-context` (unit).
- Given an accept file whose base→HEAD diff adds a row for a pair whose path and refs are untouched and no oracle file moved, then `ratchet` exits 1 `reason=accept-unattributed` (unit, replay suite).
- Given an added row with reason `false-positive: whatever`, then `reason=accept-bad-kind` (unit).
- Given `ALLOWED_PATHS` mutated to include an oracle path in the fixture, then the unreachability assertion fails (unit).
- Given the real tree, when `bash scripts/probe-merge-group-coverage.sh`, then `merge-group-coverage=OK` with both new producers found exactly once each (integration).
- Given a `gh` stub emitting truncated JSON, then the driver fails closed `reason=api` (unit).

## Success Metrics

- 12 required contexts enrolled, each with exactly one merge_group producer (probe output).
- Zero PRs merge an oracle diff without a bound review act or owner authorship after flip.
- Accept rows added without attribution/kind: zero — the two verdicts fire, measurable because the marker carries `accept=<n>` on every run.

## Dependencies & Risks

- **R1 — transitional queue membership:** a PR queued before this merge whose head lacks `oracle-review-required` makes the merge_group arm fail that batch. Mitigation: merge when the queue is shallow; break-glass = re-push the member (new head produces the context) or admin merge + runbook entry. Low likelihood — the queue drains fast and this PR is likely the only entry.
- **R2 — whole-payload ruleset replace:** the apply replaces the full ruleset. Mitigation: canonical↔TF parity is enforced pre-merge (T-rsc-9); pre/post `bypass_actors`+`conditions` read is the post-merge AC.
- **R3 — self-reference:** this PR is itself an oracle diff (ci.yml, replay.py, accept file). It needs `deruelle` approval or `deruelle` authorship to satisfy its own new gate — the author arm exists for exactly this; recorded.
- **R4 — new suite named-path pairs:** the suite's strings become audit pairs; any undrained pair reds the ratchet on this PR's own merge run. Mitigation: Phase 1 drains in the same commit; AC requires `ratchet` exit 0 on this branch.
- **R5 — driver base-sourcing gap:** a pre-PR3b base lacks the driver; the HEAD copy runs with the BASE oracle list — a PR editing the driver still classifies oracle-touching under the base list. The remaining hole (a malicious driver hiding a NON-oracle-path review requirement) is bounded by Guard 2 row 5 + the fact that editing the driver is itself oracle-touching.
- **R6 — `fixture:`-kind legacy rows:** the six-kind set excludes `fixture` as a kind even though 100+ legacy rows use it. Only added rows are judged; if implementation finds `fixture` is genuinely needed as a new kind, the kind set is the amendment surface (recorded — the ruling says "six", matching the runbook list verbatim).

## Enhancement Summary

Deepen-plan pass, 2026-11-07 (single-agent environment — no Task-spawn
available; the per-section research and review-agent fan-outs were executed
inline by the planning agent against the live tree):

- **Gate verification:** all mechanical halt gates verified green —
  `lint-guard-contract.py` RC=0 (4 guard entries; `**Assembly.**` split to its
  own line and `**Mutation matrix.**` labels added where they were missing),
  Encryption Posture `at_rest` given a real no-store entry instead of `[]`,
  Scope Check unfenced-count = 1 with all three subsections and a
  `Recommendation:` line, UBI/Observability/Task-Design/PAT scans clean.
- **Consumer enumeration:** every file that pins the required-context set or
  the advisory state was enumerated by grep against the live tree — the count
  pins (T-rsc-7 literal, parity `-ge 10`, merge-group-coverage
  `contexts=12 producers=11` literals + `MIN_CONTEXTS_DEFAULT`), the
  wallclock-bounds `unbound`-finding contract, the fixtures, and the
  replay-suite `row_wf_*` advisory pins are all in Files to Edit.
- **Re-examination recorded:** draft-light participation ruled (stay ungated;
  measured ~2,250 billed min/wk on drafts vs a needs-edge stall class or a
  fabricated green — decision-challenges.md row 1).

## References & Research

- Issue: #10859 (body + comments through the 2026-11-07 go-ahead); rulings comment 2026-11-06; addendum 2026-10-23.
- Archived plan: `knowledge-base/project/plans/archive/20261023-144502-2026-10-22-feat-s4-affected-index-pr3-required-ratchet-plan.md` §PR3b; retire plan `archive/20261107-124733-…-retire-ratchet-observation-window-probe-plan.md`.
- Runbook: `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`; followthrough-convention.md.
- ADR-276 (amendments: PR3a, oracle lane, items 5-9); ADR-032 (paired-edit ABI); ADR-270 (queue machinery); ADR-139/#6882 (ALLOWED_PATHS ∩ SCAN_DIRS re-derivation rule); ADR-276 Option R (draft-light `test` red by design).
- Machinery: `scripts/ci-pr-affected-replay.py` (:1590, :1752-1768, :1951, :1994); `scripts/merge-queue-cla-verify.sh` :89-181; `scripts/probe-merge-group-coverage.sh`; `.github/workflows/merge-queue-cla-synthetics.yml` (verified-synthetic precedent); `scripts/ci-oracle-lane.sh` (base-sourced driver + output grammar precedent).
