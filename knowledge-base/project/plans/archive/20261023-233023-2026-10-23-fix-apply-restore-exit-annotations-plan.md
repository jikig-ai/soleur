---
title: "fix: apply workflow restore-step annotations for exits 2, 5 and 78"
type: fix
date: 2026-10-23
slug: apply-restore-exit-annotations
branch: feat-one-shot-9757-item2-apply-annotations
issue: 9757
closes: none
priority: p3-low
domain: engineering
brand_survival_threshold: none
lane: single-domain
---

# fix: apply workflow restore-step annotations for exits 2, 5 and 78

## Overview

Item 2 of umbrella #9757. The registry restore engine (`scripts/registry-restore-from-ghcr.sh`) gained a second
cause for exits 2 and 5 when PR #10525 moved its crane logins onto stdin (a login that fails locally on the
runner now exits 2 for the GHCR login and 5 for the sink login), and exit 78 (traced invocation refused) is a
documented engine code. Two surfaces still describe the older meanings, and neither enumerates 78:

1. the apply workflow's restore step (`registry_store_restore` job, step "Restore production's pinned image set
   from GHCR", the `case "$rc" in` block), where 78 falls into the `*)` arm whose text calls it "a defect worth
   filing";
2. the D10 gate's A2 arm in `scripts/registry-pull-path-health.sh` (`case "$restore_rc" in`), same gap.

The fix rewrites the arms for 2 and 5 to name both causes, adds an explicit 78 arm in both places, updates the
runbook rows that currently say "the apply workflow's restore step has no arm for 78", and adds the first tests
that pin the enumeration (today nothing does, which is how the arms went stale unnoticed).

Merging fires the production apply (the workflow's own file is in its `push: paths` filter). That is an
operator-class authorization handled at ship time, not here (see `decision-challenges.md`, last row).

## Enhancement Summary

**Deepened on:** 2026-10-23. **Passes:** mechanical halts (user-brand, observability, PAT, scope, guard-contract lint) all green; architecture-strategist (blast radius of the production apply), test-design-reviewer (dry-ran W9, the gate loop and G18b), plus the earlier CTO, DHH, Kieran and simplicity passes recorded in `decision-challenges.md`.

### Key improvements from deepening

1. W9's arm regex was unsatisfiable for exit 0 and exit 78 on a correct workflow (the success arm has no `::error::` text); code 0 is now special-cased and the token pins are anchored phrases.
2. The gate-loop assertion is scoped to the `A2 ABORT` line, and the failing-first evidence is pinned to the negative `unenumerated` assertion because the positive `exit 78` match is vacuous on main.
3. The affected-paths edge for the wiring suite is now expected to be owed (verified: the array lists neither the workflow nor the engine).
4. Two more lints read the workflow file and join the verification list; sibling PRs and worktrees editing the same workflow are an explicit byte-baseline risk.
5. The `[skip-web-platform-apply]` kill switch exists for the merge push; it is offered inside the single operator question, never used unasked.

### New considerations discovered

- The edited restore step never executes on the merge push (the job needs the dispatch-only recut job); the merge triggers only `preflight` and `apply`, serialized behind the shared `terraform-apply-web-platform-host` concurrency group.
- No consumer parses the restore annotation text (`notify-apply-failure` reads the failing step name from the jobs API).

## Research Reconciliation - Spec vs. Codebase

| Claim in the brief / umbrella line | Reality on `origin/main` (05b06e6807) | Plan response |
|---|---|---|
| Workflow annotations "around lines 3660-3690" | Correct: the restore step's `case "$rc"` is at ~3679-3694 in `.github/workflows/apply-web-platform-infra.yml` | Re-locate by content (`Restore production's pinned image set from GHCR`), never by line |
| Gate arms "around lines 575-585" | `scripts/registry-pull-path-health.sh` A2 `case "$restore_rc"` is at ~572-585 (arms 1-6 and `*`) | Edit by content |
| Annotations "still describe the old failure meaning" | Confirmed for 2 and 5 only: PR #10525 added the local-login-failed cause (`die 2` at the ghcr.io login, `die 5` at the sink login) | Rewrite both arms in both places |
| Exit 78 "lands in the unenumerated-exit arm" | Confirmed in both places. 78 is the xtrace refusal at engine lines ~99-105 (`case "$-" in *x*`), header row at ~80 | Add `78)` arms; the runbook row for 78 already exists and says the workflow lacks an arm |
| "Editing the workflow fires the production apply" | Confirmed: `on.push.paths` lists `.github/workflows/apply-web-platform-infra.yml` | Operator-class row; one plain question at ship |
| Implicit: the edit fits the workflow | It does NOT fit as-is: the file is 489,845 bytes against a 490,000-byte gate (`plugins/soleur/test/workflow-file-size.test.ts`), 155 bytes of headroom | Relocate prose to the rationale runbook, net size <= 0 (CTO ruling F2) |
| Implicit: a test pins the annotations | No test pins the restore step's arms; `test-registry-pull-path-health.sh` loops `for code in 2 3 4 5 6` asserting only `rc != 0`, which the unenumerated arm also satisfies | New enumeration tests (below) |
| Engine header "enumerates every exit code" | Header lists 0,2,3,4,5,6,78 but the engine also `die 1`s on input faults; the workflow has no `1)` arm | Out of scope by CTO ruling F1; tracked as #10932 |

## Research Insights

**Premise Validation (Phase 0.6).** Checked: #9757 is open (the item 2 line is the last unticked box, "Added
2026-10-19 (found in PR #10525's review)"); PR #10525 merged as ee47f544f4; the cited files and symbols exist on
`origin/main` (`abort A2` arms, exit 78 sentinel at gate line ~113-118 and engine line ~99-105, the restore step).
ADR corpus grep for the mechanism (annotation-per-exit-code): ADR-169 (what authorizes destroying the sole pull
path) defines A2; ADR-231 section 2 sets the comment-relocation convention used here; neither rejects this
approach. Stale: the issue text says the gate's "exit 78 sentinel" is at ~113-118 and arms at ~575-585 - line
numbers have drifted by a few lines, content matches.

**Property List (Phase 0.6b).**

1. P1: an operator reading the restore step's `::error::` for exit 2 or 5 is told both causes and which line to read first.
2. P2: exit 78 from the restore engine is named as a trace refusal, not reported as an unenumerated defect, in the workflow and in the gate.
3. P3: the enumerated set cannot silently drift again (a code added to the engine header with no arm turns a test red).
4. P4: the edit keeps the workflow under its byte gate.
5. P5: the runbook and the annotations agree.

**Cut List.** Candidate mechanisms named in the ask: none beyond the annotation edits. Cut by this plan (not built):
a new standalone suite for the workflow arms (the wiring suite already has `_step_body` and is registered); a
per-code assertion loop (CTO F3: one aggregate keeps `EXPECTED_ASSERTIONS` deterministic); raising the byte gate
(F2); an exit-1 arm (F1, #10932); touching the engine file (it is in the xtrace baseline and the ask names only the
two annotation surfaces).

**Institutional learnings applied** (from the learnings sweep):

- `2026-09-19-a-sibling-merge-took-the-apply-workflow-over-githubs-byte-limit...`: a comment-only edit can cross the byte limit; measure `wc -c` before and after, and check no sibling worktree edits the same file.
- `2026-07-30-the-comment-that-named-a-cause-was-the-cause-of-the-misdiagnosis`: cause-naming prose gets read as a finding - the new arms must say "either of two causes, read the engine line", never assert one.
- `2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice...`: assert the reason string, not only rc; include a remove-the-observer mutation.
- `2026-08-09-my-suites-were-hermetic-so-they-certified-a-gate-reached-through-a-dead-read`: the suites stub the engine; the real `run:` body is only exercised by reading it, which is what the new wiring row does.
- `2026-09-04-i-shipped-the-defect-class-my-guard-existed-to-forbid`: for credential-binding scripts test the property (no value in a trace), not just the exit code - this plan does not touch that path, but must not weaken it.

**Local conventions.** Comments between `case` labels are fine in bash (the existing `DO NOT reinstate` comment
already sits between arms); the pinned `EXPECTED_ASSERTIONS` in the wiring suite moves with every row.

## Open Code-Review Overlap

None. Queried open `code-review` issues against every planned file path (workflow, gate, three suites, two
runbooks); no body names any of them.

## Proposed Solution

### Establishing the current meaning (evidence)

| Exit | Emitted by (engine) | Current meaning | Stale text found |
|---|---|---|---|
| 2 | GHCR resolve/signature read failures (NOTFOUND, DENIED, NETWORK) AND the `crane auth login ghcr.io` command failing locally (`die 2`, engine ~602) | Source unavailable, OR the runner-side login command failed (crane without `--password-stdin`, missing crane, unwritable `DOCKER_CONFIG`) | Workflow arm 2 and gate arm 2 say only "GHCR could not be read" and point at `packages: read`/GHCR status |
| 5 | Absent/empty sink credential; DENIED from the sink at digest/copy/readback; AND the `crane auth login <sink>` command failing locally (`die 5`, engine ~593) | Credential unusable OR the sink login command failed locally; a merely wrong credential only surfaces later, at digest/copy | Workflow arm 5 sends every exit 5 to "measure htpasswd_push_matches first", wrong for a local login failure; gate arm 5 says only "could not authenticate to the throwaway" |
| 78 | Engine xtrace refusal (`case "$-" in *x*`, one of `DOPPLER_TOKEN` / `GHCR_TOKEN` / `ZOT_PUSH_TOKEN` set), before any network call | Traced invocation only; nothing written; remove the trace | No arm in either place; workflow `*)` text calls it "a defect worth filing" |

### Annotation text (design; exact wording is final at implementation but the content rules are binding)

Workflow restore step (`case "$rc"`), after relocation of the long comments:

- `2)` ... SOURCE unavailable, or the runner's ghcr.io login command failed. Read the engine's own `::error::` line above first: "login command ... failed locally" is runner tooling (crane version, `DOCKER_CONFIG`), not GHCR; otherwise check `packages: read` and GHCR status. NOT proof the images were deleted. The store is EMPTY. Runbook pointer.
- `5)` ... CREDENTIAL unusable. Read the engine's `::error::` line first. "login command ... failed locally" is runner tooling; fix that, rotating changes nothing. Otherwise the sink rejected the credential: retrying will not clear it and do NOT rotate `ZOT_PUSH_*` first; MEASURE FIRST, no SSH, keep the existing `doppler run ... betterstack-query.sh --grep SOLEUR_ZOT_DISK` command and `htpasswd_push_matches` on the NEWEST `boot_id`, scoped to this cause only.
- `78)` (new) ... TRACED INVOCATION. The engine refused to run under xtrace with a credential in the environment, before any network call; this attempt wrote nothing, so the store is unchanged from before it (empty after a rebuild). Retry only after removing the trace (`bash -x`, `set -x`, `SHELLOPTS`, `BASH_ENV`). Do not mention `BASH_XTRACEFD`: it redirects a trace and never sets `$-` to contain `x`, so it is not a cause of this refusal (review finding). No reachability prose in the workflow arm. 78 never enters the exit-3 backoff loop (the loop continues only on `rc == 3`); no new test pins that, since the loop is not edited.
- `*)` unchanged (follow-up #10932 owns the exit-1 wording).
- Each arm stays ONE `echo` line beginning `::error::restore FAILED exit N` (the test extracts it by that label; a comment or a neighbouring arm cannot supply a token). The 78 arm must not use the `*)` wording.
- Also in the same step, three comments go stale when the 78 arm lands and are fixed within the byte budget: "all six ::error:: arms below" (above the `set +e` block), "Only exit 3 retries. 2/4/5/6 are ..." (above the retry loop), and "Six enumerated exit codes consumed as a single boolean" (above the `case`). Reword to count-free text.

Gate A2 (`scripts/registry-pull-path-health.sh`), no byte limit but same content rules:

- `2)` source unavailable OR the ghcr.io login command failed on the runner; either way the rehearsal never restored anything; still "Refusing to destroy the only remaining copy".
- `5)` EITHER the throwaway rejected the rehearsal credential OR the sink login command failed locally (the engine's own line says which; do not assert a cause). The credential is generated in this job (`steps.throwaway.outputs`), so neither is a production-credential signal; nothing destroyed.
- `78)` (new) the engine refused to run traced with a live credential before any network call; the rehearsal never ran so the pass condition was not established; harness/invocation fault, nothing destroyed; remove the trace and re-dispatch. One-line code comment only (not a paragraph): the gate's own refusal checks `REGISTRY_PUSH_ACCESS_TOKEN`/`ZOT_PUSH_TOKEN`, the engine's wider set adds `GHCR_TOKEN`/`DOPPLER_TOKEN`, so this arm is defense in depth.

### Byte budget (CTO ruling F2)

File is 489,845 bytes; gate 490,000. Estimated growth: arm 2 about +210 B, arm 5 about +50 B, arm 78 about +370 B
(about +630 B), plus the three stale-comment rewordings (about neutral). Funding, in order, stopping when net <= 0:

1. Move the 7-line `DO NOT reinstate "rotate ZOT_PUSH_*"` comment (643 B) verbatim into a new `###` subsection under `## registry_store_restore` in `apply-web-platform-infra-job-rationale.md`; leave a one-line stub keeping the `DO NOT reinstate "rotate ZOT_PUSH_*"` text (about 150 B). The stub's pointer must NOT use the `# Rationale: <runbook> §<id>` form: `workflow-file-size.test.ts` collects every such line and requires the set to equal the runbook's level-two headings, so a second pointer line reds it. Use plain wording ("see the registry_store_restore section of the rationale runbook"). Saves about 490 B.
2. Move the `DOPPLER_TOKEN, not DOPPLER_TOKEN_PRD` history comment (about 980 B measured by the reviewers, in the step's `env:` block; grep confirmed no test or other file anchors its text) the same way (same no-`# Rationale:` stub rule), leaving a one-line stub (about 120 B). Saves about 860 B. Reviewers split on whether to move this one at all (DHH: leave it alone; simplicity: it is the only move the budget needs); it stays a fallback, used only if step 1 plus rewording does not reach net <= 0.
3. Only if still above 0: shorten arm wording; never raise the gate.

Do not add a `##` heading to the rationale runbook (the pointer-equals-headings test in `workflow-file-size.test.ts`
would fail); `###` is safe.

### Tests (planned first; see Test Scenarios and Guard Contract)

1. `tests/scripts/test-registry-d10-workflow-wiring.sh` (+1 assertion, `EXPECTED_ASSERTIONS` 23 -> 24; W10 was folded into W9 on review):
   - W9, one aggregate assertion with one shared arm-extraction helper: (a) derive the code list from the engine header table with the pattern `^#[[:space:]]+[0-9]+[[:space:]]+[A-Za-z]` applied up to the first non-comment line (measured by the reviewer: it yields exactly 0, 2, 3, 4, 5, 6, 78 and does not match prose such as `#   1. as a REHEARSAL`; the whitespace-after-digits requirement is load-bearing), floor >= 7 codes, code 0 included (the workflow has a `0)` arm); (b) extract the restore step body with `_step_body "Restore production's pinned image set from GHCR"` (comment-stripped, safe with the apostrophe); (c) for every derived code require ONE explicit arm line located before the `*)` arm (line numbers taken from the same comment-stripped body): for codes other than 0 it must match `^[[:space:]]*<n>\)[[:space:]]+echo .*::error::restore FAILED exit <n>`; code 0 is special-cased to `^[[:space:]]*0\)[[:space:]]+echo` followed by a space because its success arm prints `restore: ...` and can carry no `::error::` text (deepen-plan dry run: the single combined regex matched 0 for code 0 and for 78, so a literal implementation would be RED forever on a correct workflow); code 0 still counts toward the >= 7 floor; (d) in the same assertion, on the arm lines only: arms 2 and 5 contain `failed locally`, arm 78 contains `traced invocation` (case-insensitive match; the design text writes it in capitals), and no explicit arm contains `unenumerated` (anchored phrases, not bare `locally`/`trace`, per `cq-assert-anchor-not-bare-token`). W9 emits exactly one `_report` on every path, including an empty step body or an empty header. The failure message lists the missing codes or arms. A comment above W9 records that exit 1 is deliberately outside the population (#10932) so nobody "fixes" it by adding 1.
   - Dropped on review (simplicity, DHH, Kieran converged): the `rc != 3` retry pin (the loop is not edited) and the separate W10.
2. `tests/scripts/test-registry-pull-path-health.sh`: change the A2 loop from `2 3 4 5 6` to `2 3 4 5 6 78`; per code assert rc != 0 AND the `A2 ABORT` line of the output contains `exit $code` AND does not contain `unenumerated` (grep that line only, e.g. `grep -E 'A2 ABORT.*exit 78'`, so restore-stub output, which the gate also prints to stdout through its `sed` tail, cannot satisfy or poison the check). On current main the positive `exit 78` match is vacuous because the `*)` text itself reads `an unenumerated exit 78`; only the negative `unenumerated` assertion discriminates, so the failing-first evidence cites that one. The list stays hand-written (the battery sandbox has the engine, but P3 is claimed for the workflow side only; the gate loop is the explicit mirror). No separate prose-meaning row for the gate (dropped on review).
3. `tests/scripts/test-registry-gate-mutation-battery.sh`: one new row "G18b A2 exit-78 arm moved to another number" (anchor: the unique head of the `78)` arm, i.e. the text `78) abort A2 "the rehearsal failed with exit 78` (indentation excluded); replacement: same with 77) so 78 falls into the `*)` arm). It must end RED, and it does so only through the negative `unenumerated` assertion (rc and `exit 78` still match on `*)`), which is also the instrument check: dropping that assertion must let G18b survive. The pre-flight requires the anchor to resolve exactly once in the gate, so the planned one-line comment above the arm must not repeat the anchor text, and the row can only be added after the 78 arm exists. The battery asserts a dispatch floor of 66 (currently 62 `mutate` rows), so +1 row is safe; check `scripts/suite-durations-heavy.tsv` for whether the measured weight needs a refresh.

Failing-test-first order: write the tests, run them against unmodified main files (W9 must name `78` as missing; the gate loop must fail for 78 on the `unenumerated` assertion; the battery row is only meaningful once the 78 arm exists), then make the edits.

### Runbook (same PR, CTO F4)

`knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md`, "Restore exit codes" table: rewrite
only the 78 row's last sentence (drop "has no arm for 78 ... ignore that arm's defect wording"; say the restore step and
gate A2 both name 78). Rows 2 and 5 already describe the local-login-failed cause (verified by two reviewers), so they are NOT edited. `apply-web-platform-infra-job-rationale.md`:
add the relocated prose as `### Why the exit-5 annotation must not say "rotate"` (and the DOPPLER_TOKEN history
subsection) under `## registry_store_restore`.

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` - restore step `case "$rc"` arms 2, 5, new 78; relocate two comments; net bytes <= 0. Locate by the step name.
- `scripts/registry-pull-path-health.sh` - A2 `case "$restore_rc"` arms 2, 5, new 78.
- `tests/scripts/test-registry-d10-workflow-wiring.sh` - W9, `EXPECTED_ASSERTIONS` (23 -> 24, re-measured).
- `tests/scripts/test-registry-pull-path-health.sh` - A2 loop (adds 78) with the `exit N` and no-`unenumerated` assertions.
- `tests/scripts/test-registry-gate-mutation-battery.sh` - row G18b.
- `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md` - row 78 only.
- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md` - relocated prose under `## registry_store_restore` (`###` only).
- Conditional, only if the named check reports it (each is a derived-state sync): `scripts/lib/test-affected-paths.sh` (add the workflow and engine paths to `AFFECTED_TESTS_SCRIPTS_REGISTRY_D10_WORKFLOW_WIRING_PATHS` if the affected-selection query does not already select the wiring suite for a diff touching them; this arms every PR-gated battery on the PR, so measure first); `scripts/lint-shell-trace-credential-refusal.baseline.txt` (the gate script is listed there although it carries the refusal; run `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` after the edit and delete the entry only if the lint says so); `plugins/soleur/test/fixture-relative-assert.baseline.txt` (counts for the gate suite and gate script; run that lint after the edit).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9757-item2-apply-annotations/decision-challenges.md` (planning artifact, exists)
- `knowledge-base/project/specs/feat-one-shot-9757-item2-apply-annotations/tasks.md` (planning artifact)

No files under `apps/**` are touched. The engine file `scripts/registry-restore-from-ghcr.sh` is NOT edited
(it is the source of truth being described; editing it would also force the xtrace-baseline drawdown).

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Four technical forks (exit-1 scope, byte funding, test strategy, annotation wording) ruled by the
CTO agent on 2026-10-23, recorded verbatim in `decision-challenges.md`. No architectural decision is made (an
annotation realignment on an existing surface), so no ADR or C4 change; ADR-231 section 2 (relocation) and ADR-169
(A2 authorizes the destroy) are followed, not amended. No product, legal, finance, marketing, sales, ops or support
implication; no UI surface (Product/UX gate not triggered; mechanical override scanned: no `components/**`,
`app/**` or other UI-surface path in the file lists).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly; the reader is the operator during a registry recut, after the store is destroyed. A wrong annotation could send them to rotate a credential for what is really a runner-tooling fault, turning a possibly-transient rejection into a permanent one until the host is replaced. The change reduces that risk; the existing "do NOT rotate first" guard stays at the edit site.
- **If this leaks, the user's data is exposed via:** no vector; the diff adds `::error::` strings and tests. No credential value is printed, interpolated or logged; the engine and its xtrace refusal are untouched.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** annotation text and test rows only; exit codes, retry logic and the xtrace refusal are unchanged, so no user data path moves.

`threshold: none, reason: the diff changes operator-facing error text and tests for an engine that is not edited; no credential, data path or exit code changes.`

## Observability

```yaml
liveness_signal:
  what: the restore step's ::error:: annotation for exits 2, 5 and 78 (operator-facing, in the Actions run summary and annotations)
  cadence: per apply_target=registry-luks-recut dispatch and per restore-job run
  alert_target: the dispatching operator via the run's failure annotation; notify-apply-failure on job failure
  configured_in: .github/workflows/apply-web-platform-infra.yml (registry_store_restore, step "Restore production's pinned image set from GHCR")
error_reporting:
  destination: GitHub Actions ::error:: annotation (no Sentry path exists for a failed runner step)
  fail_loud: the step exits with the engine's rc; each enumerated code prints one named ::error:: line
failure_modes:
  - mode: engine exits 78 and the workflow reports it as an unenumerated defect
    detection: tests/scripts/test-registry-d10-workflow-wiring.sh W9 (header-derived enumeration) fails in CI
    alert_route: PR check failure
  - mode: workflow grows past the byte gate and GitHub silently refuses to start the run
    detection: plugins/soleur/test/workflow-file-size.test.ts fails in CI
    alert_route: PR check failure
logs:
  where: GitHub Actions run log for the registry_store_restore job
  retention: GitHub's default Actions log retention
discoverability_test:
  command: grep -c "restore FAILED exit 78" .github/workflows/apply-web-platform-infra.yml
  expected_output: 1
```

## Guard Contract

### Guard 1 - restore-step exit-code enumeration (wiring suite W9)

**Property.** Every exit code the restore engine's header table documents has one explicit arm line in the workflow's restore step (not a comment, not the `*)` fallthrough), and the arms for 2, 5 and 78 carry their meaning tokens.

**Assembly.** The population is the engine header table in `scripts/registry-restore-from-ghcr.sh` (derived with the whitespace-after-digits pattern, floor >= 7; it documents codes the engine can emit EXCEPT exit 1, which is deliberately outside it, #10932); the consumer is the single `case "$rc" in` block of the `Restore production's pinned image set from GHCR` step in `.github/workflows/apply-web-platform-infra.yml`. Chokepoints: the header parser, the step-body extractor (`_step_body`, comment-stripped), the shared arm-extraction helper. The gate's A2 `case` is a second consumer, covered by Guard 2 with a hand-written list; there is no third consumer (the callers of the engine are the restore step, the gate and the suites).

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `78)` arm from the workflow case | RED (W9 names 78 missing) |
| 2 | Rename the step so `_step_body` returns empty (the guard's own dispatch) | RED (extractor-empty branch), never "0 checked, pass" |
| 3 | Add a row `#  7  EXAMPLE` to the engine header table after the compliant rows, with no workflow arm | RED (W9 names 7 missing; a check that stops at the first member would pass) |
| 4 | Put the `78)` text only inside a comment line | RED (comment-stripped body has no arm) |
| 5 | Move `78)` after `*)` so it is unreachable | RED (arm must precede `*)`) |
| 6 | Keep the `78)` label but give it the `*)` wording (`unenumerated`) | RED (token check inside the same assertion) |

Run rows 1, 3 and 6 in a scratch copy of the tree and paste the result; rows 2, 4, 5 are implied by the same helper and run only if the helper changes shape.

**Harness rows.** (a) Neutering `_report` to `return 0` is caught by the exact `EXPECTED_ASSERTIONS` pin (RED). (b) Must-PASS non-canonical input: a scratch workflow copy with the arms in a different order (2,5,78,3,4,6) and different wording that still has every explicit arm before `*)` must PASS.

**Scratch seam.** The wiring suite hard-codes `WORKFLOW` and reads the engine from `ROOT`, with no override. Scratch runs therefore copy the minimum tree the suite reads: the suite file, `.github/workflows/apply-web-platform-infra.yml`, `.github/actions/`, `scripts/derive-app-domain-base.sh` and `scripts/registry-restore-from-ghcr.sh` (W2b, W4 and W7 read the actions directory and the derive script), under `tests/scripts/` and run from there. No source override is added to the suite (an unrequested mechanism).

**Anchor.** The population comes from the engine file and the consumer from the workflow; one commit can edit both, so integrity is bounded by the independent `workflow-file-size` gate and by review, and the header floor (>= 7) plus the explicit-arm requirement stop a count-only weakening.

### Guard 2 - gate A2 enumeration (suite loop + battery row G18b)

**Property.** For every restore exit code in `2 3 4 5 6 78`, the gate aborts with a message naming `exit N` and never the `unenumerated` fallthrough.

**Assembly.** `scripts/registry-pull-path-health.sh` A2 `case "$restore_rc"`; consumers of the message: the suite loop and the battery. Chokepoint: `abort A2`. The loop list is hand-written, so this guard's drift protection is the explicit mirror of Guard 1's population, not a derivation.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Battery G18b: renumber the 78 arm to 77 | RED (suite sees `unenumerated`) |
| 2 | Existing G18: `if (( restore_rc > 100 ))` so every failure is ignored | RED (rc check) |
| 3 | Delete the `5)` arm after a compliant `78)` exists | RED (suite sees `unenumerated` for 5; a second member after a compliant first) |

**Harness rows.** Must-PASS non-canonical: the loop's assertions are scoped to the gate's own `A2 ABORT` line (the stub's output is printed too, through the gate's `sed` tail, but is excluded by that scoping), so the must-PASS input is the real gate with the `78)` wording reworded but still naming `exit 78` - it must stay GREEN. RED: remove the `unenumerated` negative assertion in a scratch copy of the suite and confirm G18b then survives (the battery's `unexpectedly_caught` accounting reports it).

**Anchor.** The battery pre-flight requires every anchor to resolve exactly once in the gate source; moving the 78 head breaks the anchor loudly rather than silently.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "update the apply workflow's restore-step annotations for exits 2, 5 and 78 so they describe the current failure meaning" | Proposed Solution - workflow arms 2, 5, 78; Files to Edit 1 | mapped |
| 2 | "make exit 78 an enumerated exit instead of landing in the unenumerated-exit arm" | `78)` arms in workflow and gate; Guards 1 and 2 | mapped |
| 3 | "scripts/registry-pull-path-health.sh (around lines 575-585)" | A2 arms 2, 5, 78; Files to Edit 2 | mapped |
| 4 | "Check which workflow-size or lint tests ... constrain the edit, and plan the failing test first." | Byte budget; Tests; Failing-test-first order | mapped |
| 5 | "PR body uses `Ref #9757` only (never a closing keyword); merge via the merge queue (`gh pr merge --squash --auto`), never --admin" | Acceptance Criteria (PR hygiene) | mapped |
| 6 | "the pipeline must ask the operator exactly ONE plain delegation question for explicit go-ahead on that production apply before the PR is marked ready or the merge is armed" | decision-challenges.md last row; Acceptance Criteria (Operator authorization) | mapped |
| 7 | "do not read or print secrets; no live credentialed probes; umbrella #9757 stays open. Do not touch apps/** other than what the two named files require." | Files to Edit (no apps/**); Acceptance Criteria | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Workflow arms 2, 5, 78 | "update the apply workflow's restore-step annotations for exits 2, 5 and 78" | asked |
| Gate A2 arms 2, 5, 78 | "scripts/registry-pull-path-health.sh (around lines 575-585)" | asked |
| Byte relocation of two comments | "Check which workflow-size or lint tests ... constrain the edit" | asked |
| Wiring-suite row W9 | "plan the failing test first" | asked |
| Gate suite loop extension | "plan the failing test first" | asked |
| Battery row G18b | "plan the failing test first" | asked |
| Runbook row 78 | "annotations ... describe the current failure meaning" | inferred - the runbook's 78 row states the workflow has no 78 arm and tells operators to ignore the arm's wording; leaving it is a contradiction the next reader trips on (P5) |
| Rationale-runbook `###` subsection | "Check which workflow-size or lint tests ... constrain the edit" | asked (the relocation precedent, ADR-231 section 2) |
| Conditional sync edits (affected-paths, baselines) | "plan the failing test first" | inferred - derived-state gates (affected-selection census, xtrace baseline, fixture-relative baseline) go red if the new rows or the edited script are not reflected; each is run, not assumed |
| Follow-up issue #10932 for exit 1 | "make exit 78 an enumerated exit" | inferred - CTO F1 scoped exit 1 out; a deferral without a tracking issue is invisible |

### Split Assessment

- Subsystems touched: 3 - `.github/workflows`, `scripts` + `tests/scripts`, `knowledge-base/engineering/operations/runbooks`
- Planned files: 7 core + up to 3 conditional | Estimated changed lines: ~220
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [x] The restore step's `case "$rc"` has explicit `2)`, `5)` and `78)` arms; 2 and 5 name both causes and tell the operator to read the engine's own `::error::` line first; the rejected-credential cause keeps "do NOT rotate ZOT_PUSH_* first" and the measure-first command; 78 says traced invocation, nothing written, remove the trace before re-running. Evidence: `awk` over the step body shows the three arms (`.github/workflows/apply-web-platform-infra.yml`, step "Restore production's pinned image set from GHCR").
- [x] Gate A2 has `78)` and updated `2)`/`5)` arms (`scripts/registry-pull-path-health.sh`, `case "$restore_rc"`).
- [x] `wc -c .github/workflows/apply-web-platform-infra.yml` after the edit is <= 489,845 (net size not increased; re-measure against the merge-base after the last sync with `origin/main`) and `bun test plugins/soleur/test/workflow-file-size.test.ts` passes, including the rationale-pointer test (no new `##` heading in the rationale runbook, and the workflow gains no new `# Rationale: <runbook> §<id>` line).
- [ ] Failing-first evidence: the new W9 row and the gate loop's 78 row are shown RED against unmodified main files before the edits (pasted in the PR body), then GREEN.
- [x] `bash tests/scripts/test-registry-d10-workflow-wiring.sh` passes with `EXPECTED_ASSERTIONS` bumped to the measured count (23 -> 24, re-measured not guessed); `bash tests/scripts/test-registry-pull-path-health.sh` passes; `bash tests/scripts/test-registry-gate-mutation-battery.sh` passes with G18b caught (and its anchor resolving exactly once).
- [x] Guard 1 rows 1, 3 and 6 and Guard 2 rows 1 and 3 are run against a scratch copy (tree subset named in Guard 1 "Scratch seam") and shown RED; the Guard 1 must-PASS reordered-arms row is shown GREEN (results in the PR body).
- [x] Runbook `registry-luks-recut-6929.md` row 78 agrees with the annotations (rows 2 and 5 already do and are unedited); the phrase "has no arm for 78" no longer appears in it (`grep -c "no arm for 78"` is 0).
- [x] The derived-state checks were run and any needed sync edits made: affected-selection for the wiring suite on a diff touching the workflow and engine paths (deepen-plan verified `AFFECTED_TESTS_SCRIPTS_REGISTRY_D10_WORKFLOW_WIRING_PATHS` at `scripts/lib/test-affected-paths.sh` lists neither path, so adding both is EXPECTED to be owed: without it a later PR that deletes the 78 arm would not select W9); `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main`; the fixture-relative-assert lint; and, because both read this workflow file, `python3 scripts/lint-workflow-run-body-syntax.py` and `python3 scripts/lint-workflow-errexit-capture.py` (invoked as CI invokes them). **Measured at work time:** the affected selector already selects the wiring suite for a workflow-only and for an engine-only diff (`--print-selection --paths=...`), so the expected `test-affected-paths.sh` edit was NOT owed and was not made; the trace-credential lint, run-body-syntax lint, errexit-capture lint and fixture-relative ratchet are clean.
- [x] `scripts/registry-restore-from-ghcr.sh` and everything under `apps/**` are unchanged (`git diff --stat origin/main...HEAD` shows neither (merge-base form, so a sibling merge cannot flip it)).
- [ ] The PR body's FIRST line answers "does merging THIS alone mutate production?": yes - the merge fires the production apply of the web-platform root once, with no Terraform diff expected (workflow-file edit only). The body also contains `Ref #9757` and no closing keyword; #9757 is not closed; the PR links #10932 as the exit-1 follow-up.
- [x] No secret read or printed; no live credentialed probe run.

### Post-merge (operator-visible, automated where possible)

- [ ] The production apply that the merge fires completes (watch the run to its conclusion; the apply has no Terraform diff from this change, so a green no-op is expected).
- [ ] Merge only via `gh pr merge --squash --auto` (merge queue), never `--admin`, and only after the single operator go-ahead below.

### Operator authorization (the only operator question)

- [ ] Before the PR is marked ready or the merge is armed, ask exactly one plain question: "Merging this PR runs the production infrastructure apply once, because it edits the apply workflow's own file. Should I go ahead and arm the merge?" If the operator would rather not run the apply but still wants the merge, the one alternative is a squash-commit body carrying `[skip-web-platform-apply]` on its own line (the `preflight` job skips `apply` on it, and `notify-apply-failure` stays quiet on a skip); never use it without that answer. Record the answer in `decision-challenges.md`. No answer: the PR stays draft, the merge is not armed.

## Test Scenarios

- Given the engine header lists `0 2 3 4 5 6 78`, when W9 runs on current main, then it reports 78 missing from the restore case (unit, shell; RED first).
- Given a restore stub exiting 78, when the gate runs, then rc != 0, the output contains `exit 78`, and it does not contain `unenumerated` (unit; RED first).
- Given the exit-2 and exit-5 arms, when W9 runs, then each carries `locally`; the 78 arm carries `trace`; no explicit arm carries `unenumerated` (unit).
- Given the 78 arm is renumbered to 77 in a scratch gate, when the battery runs, then G18b is caught (integration, mutation).
- Given the edited workflow, when `workflow-file-size.test.ts` runs, then the file is <= 490,000 bytes and pointers equal headings (unit).
- Given a workflow copy whose arms are ordered differently but satisfy the contract, then W9 passes (must-PASS non-canonical, scratch).

## Dependencies & Risks

- **Production apply on merge** (operator class, above). Editing the workflow cannot avoid it; there is no `paths-ignore` carve-out and adding one would be a different change.
- **Byte gate**: 155 bytes of headroom; the plan is net <= 0 by relocation. Risk: a sibling worktree grows the file first - re-measure `wc -c` on the merge-base before pushing, and again after the final sync with `origin/main`.
- **Arming the PR-gated batteries**: editing the gate or `scripts/lib/test-affected-paths.sh` arms the ~860 s registry battery on the PR (CI time only). Accepted.
- **Wording honesty**: the 78 note in the gate must not claim it is routinely reachable; it is defense in depth (the gate's own refusal covers `ZOT_PUSH_TOKEN`; the engine also guards `GHCR_TOKEN`/`DOPPLER_TOKEN`).
- **Siblings editing the same workflow** (deepen-plan found #10928 at -132 B, #10678 at +62 B, a stale #7390 at +604 B, and worktrees such as `fix-apply-infra-workflow-size`): merge order moves the baseline, so re-measure `wc -c` after the last sync and check that no sibling's relocation collides with the two comment blocks this plan moves. The apply also queues behind any in-flight run holding the `terraform-apply-web-platform-host` concurrency group; check for one immediately before arming the merge.
- **CODEOWNERS** lists this workflow (`/.github/workflows/apply-web-platform-infra.yml @deruelle`); expect the merge to need that review.
- **Exit 1** remains unenumerated in the workflow by ruling; #10932 tracks it and the `*)` text stays as is.

## References & Research

- Umbrella: #9757 (item 2). Origin: PR #10525 review (ee47f544f4). Follow-up filed: #10932.
- Rulings: `knowledge-base/project/specs/feat-one-shot-9757-item2-apply-annotations/decision-challenges.md`.
- Engine: `scripts/registry-restore-from-ghcr.sh` (header exit table, `die` sites). Gate: `scripts/registry-pull-path-health.sh`. Runbooks: `registry-luks-recut-6929.md`, `apply-web-platform-infra-job-rationale.md`. Gates: `plugins/soleur/test/workflow-file-size.test.ts`, `tests/scripts/test-registry-d10-workflow-wiring.sh`, `tests/scripts/test-registry-gate-mutation-battery.sh`.
- Precedent: ADR-231 section 2 (comment relocation), ADR-169 (A2 authorizes the destroy).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6; this one is filled (threshold none with scope-out reason).
- `_step_body` matches the step by name prefix with an apostrophe in it; confirm the awk `index()` match returns non-empty before trusting W9 (the vacuity floor).
- `EXPECTED_ASSERTIONS` must be re-measured after adding rows, never guessed (`2026-08-09` learning recorded a guessed floor that was wrong).
- Comments sit between `case` arms in this step already; moving the `DO NOT reinstate` comment must leave the stub with the exact `DO NOT reinstate "rotate ZOT_PUSH_*"` text so the guard stays visible at the edit site.


## Amendment 2026-10-23 (review fix round 1)

The shipped W9 is a BEHAVIOURAL guard, not the text parse this plan describes: it runs the restore step's real `run:` body with the tools and the engine stubbed, once per code, and asserts step status, emitted annotation and engine call count. Reason and ruling: `decision-challenges.md` row "F3 amended". Consequences for the text above: EXPECTED_ASSERTIONS is 34 (W9 plus nine step-mutation controls plus one engine control), the battery rows are G26-G29 (not G18b) with dispatch floor 70, the gate suite and W9 share `tests/scripts/lib/restore-engine-header.sh`, and exit 1 is always exercised but never compared (header-vs-emit comparison drops 1 on both sides).
