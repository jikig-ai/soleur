---
title: "git-data rotate arm: both-volumes-preserved assert fails on the intended LUKS replace and blocks the flip gate"
date: 2026-10-12
slug: git-data-rotate-arm-volume-assert
branch: feat-one-shot-10137-rotate-arm-volume-assert
issue: 10137
closes: 10137
type: fix
priority: p1
domain: engineering
lane: single-domain
brand_survival_threshold: aggregate pattern
---

## Enhancement Summary

**Deepened on:** 2026-10-12 (proportionate pass: this is a four-file CI-assertion fix, so the fan-out of every available agent was not run; the gates, live checks and the CTO ruling below are what was applied).
**Sections enhanced:** Research Insights, Observability, Phase 3, Sharp Edges.

### Key Improvements
1. The `discoverability_test` command was changed from the whole gate suite to a one-line wiring probe: a suite-shaped command in a new block is a Phase 4.7 reject (Check 10 runs under a 15 s cap). Measured 2026-10-12: the suite takes 5.7 s wall, so it would fit the cap, but the detection regex is over-inclusive and the probe is the smaller honest signal.
2. Phase 3 now records why the helper-based mode derivation is safe under `set -euo pipefail` in the apply step.
3. Live-checked every cited issue (below).

### New Considerations Discovered
- The apply step runs in a different shell step from the plan step, so `GATE_MODE` is not in scope there; the helper plus `APPLY_TARGET` env is the single-mapping answer (CTO ruling), not `$GITHUB_ENV`.

## Overview

The post-apply backstop in the git-data replace job treats the LUKS store volume as always preserved, so the rotate dispatch, which replaces that volume on purpose, fails its own job after a successful apply. This plan makes the backstop mode-aware and moves it out of inline workflow bash into the shared, unit-tested gate library `tests/scripts/lib/git-data-host-replace-gate.sh`.

PR body must carry `Closes #10137` and `Ref #6897` (also `Ref #8211` as the issue states). No dispatch, apply, Doppler write, volume wipe or destroy is part of this task; re-dispatch of `apply_target=git-data-host-rotate` (`confirm=ROTATE-GIT-DATA`) waits for the operator to name the command.

## Research Insights

**Premise Validation (2026-10-12).** Issue #10137 is OPEN with no closing PR (`gh issue view 10137`). The cited workflow step exists on this branch at `.github/workflows/apply-web-platform-infra.yml` (job `git_data_host_replace`, step "Terraform apply (git-data-host -replace) - both-volumes-preserved assert"), and its inline `for VOL in hcloud_volume.git_data hcloud_volume.git_data_luks` loop is the failing assertion. `tests/scripts/lib/git-data-host-replace-gate.sh` and its suite already exist (the issue says "extract into" that file: it holds the pre-apply plan gate today, so the extraction adds a second function beside `git_data_host_replace_gate`, it does not create the file). ADR-239 `## Amendment 2026-10-12` already records #10137 as the blocker and is not edited here. The ADR corpus holds no rejected alternative for a mode-aware post-apply backstop. Baselines measured 2026-10-12 on this branch: `bash tests/scripts/test-git-data-host-replace-gate.sh` reports 56 passed, 0 failed (floor 55); `bun test test/terraform-target-parity.test.ts` from `plugins/soleur` reports 281 pass, 0 fail; `python3 scripts/lint-encryption-posture.py --repo-sweep` reports "21 stores, 10 connections, 0 unledgered, 0 failing checks -> PASS".

**Flip-gate coupling (read from `.github/workflows/git-data-cutover.yml`, lines 262-282).** `d6_replace_stale` selects a run whose job concluded success and whose step named like "rotate confirm token" concluded success. That step is "Validate dispatch inputs (rotate confirm token)" in the replace job and must keep its name. The failed run 38140050880 (2026-10-11) cannot be repaired by this PR; a new rotate run is operator-named and out of scope.

**Property List.**
1. A rotate dispatch whose plan replaces `hcloud_volume.git_data_luks` as intended passes the post-apply backstop.
2. Under rotate, a delete/forget of the plaintext `hcloud_volume.git_data` still fails the job.
3. Under plain replace, a delete/forget of either volume fails the job.
4. A plan that cannot be read, cannot be classified, carries no private NIC create or lacks either store-attachment create (including empty or null `resource_changes`) fails.
5. An unknown or empty mode fails closed.

**Cut List.** (a) A positive post-apply assertion that the LUKS volume shows delete+create under rotate: buys property 1's inverse, but the pre-apply gate already requires `luks_volume_rotated == 1` on the same saved plan; cut (CTO ruling, `decision-challenges.md`). (b) A second inline target-to-mode map inside the library: buys nothing the plan step's `GATE_MODE` does not already buy; cut in favour of one helper. (c) A bare "at least one resource_changes entry" count: weaker than the positive NIC/attachment creates; cut.

**Live citation check (2026-10-12, `gh issue view`).** #8211 OPEN (git-data cutover rebuild), #6897 OPEN (encryption-posture lower-severity items), #8209 OPEN, #8609 OPEN, #8573 OPEN (the flip chain named in the issue), #8571 OPEN (copy mode; the wipe-related ticket the issue's text points at), #8189 CLOSED (root-key arm already in the gate), #7226 CLOSED (host-key pin arm already in the gate). Each state matches how the plan uses it.

**Deepen-pass gate results.** 4.6 User-Brand Impact present with a valid threshold. 4.7 Observability: all five fields present; the block is NEW in this plan, so the #8412 conditions apply and were satisfied (verb `grep` on the allowlist; probe finishes in milliseconds; `expected_output` is the literal `1`). 4.8 PAT-shaped variables: none. 4.9 UI wireframe: no UI surface. 4.10 Encryption Posture: skipped, no `.tf`, migration, cloud-init or compose file is edited and no store or connection is introduced; `python3 scripts/lint-encryption-posture.py --repo-sweep` still run as an AC. 4.11 Guard Contract: `python3 scripts/lint-guard-contract.py` on this plan scanned 1 file, 1 guard entry, no failures. 4.12 Scope Check present with mapped asks. Downtime gate 4.55: no serving surface is touched; the change grades a saved plan after an already-authorized apply.

**Implementation realism.** The apply step runs `set -euo pipefail`: `GATE_MODE=$(git_data_gate_mode "$APPLY_TARGET") || { echo ...; exit 1; }` is safe under errexit, and inside `if ! git_data_host_post_apply_assert ...; then` errexit is suspended for the function body, which is why every internal `jq` result keeps the explicit `!= "0"` fail-closed comparison and `|| return 1` on the preamble calls. The lib already sources `plan-gate-preamble.sh` (guarded by `declare -F`) and `git-data-root-key-arm-gate.sh`, so the apply step needs only one `source` line. `tfplan.json` is written by the plan step in the same `INFRA_DIR` working directory the apply step uses, so the relative path is unchanged.

**Institutional notes.** `plan-gate-preamble.sh` header: `plan_gate_assert_readable` and `plan_gate_assert_classifiable` pass `{"resource_changes":[]}`, and `null | length` is 0 in jq, so presence must come from positive assertions; a gate's return code must be checked by the caller (`if ! fn; then exit 1`), because a bare call under `set +e` fails open. Gate suites use `gate_mutate_and_check` / `gate_mutate_layered` from `tests/scripts/lib/gate-suite-harness.sh` for non-vacuity.

## Research Reconciliation - Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| "Extract the loop into `tests/scripts/lib/git-data-host-replace-gate.sh`" | The file exists and is the pre-apply destroy-guard (315 lines, sourced by the plan step). | Add `git_data_host_post_apply_assert` and `git_data_gate_mode` to it; do not touch `git_data_host_replace_gate`. |
| "pass `APPLY_TARGET` into the step" | The apply step has no `apply_target` input today; `GATE_MODE` is derived in the plan step, a different step. | Add `env: APPLY_TARGET: ${{ inputs.apply_target }}` to the apply step and derive the mode with `git_data_gate_mode "$APPLY_TARGET"` (fail closed). Function takes the mode (CTO ruling). |
| "the post-apply delete/forget loop" | The inline block also holds the NIC create and both attachment-create assertions, which are what reject an empty plan. | Extract the whole block (CTO ruling), so the empty-plan row is testable. |
| "Keep `terraform-target-parity.test.ts` green" | The test extracts the job block, filters on `-target=`/`-replace=` text and `EXTRA_` lines, and requires `git_data_host_replace_gate tfplan.json "$GATE_MODE"`. | New workflow text adds no `-target=`/`-replace=`/`EXTRA_` strings and leaves the plan step untouched; add sibling assertions for the new step. |

## Implementation Phases

### Phase 1 - Tests first (RED)

Edit `tests/scripts/test-git-data-host-replace-gate.sh`, appending a "post-apply backstop" section before the anti-vacuity floor. Fixtures reuse `PASS_SET`, `ROT_PASS_SET`, `rc_obj`, `write_plan`.

- PA1 replace + `PASS_SET` (volumes absent by omission) -> PASS.
- PA2 rotate + `ROT_PASS_SET` (LUKS volume delete+create; the #10137 repro) -> PASS. Must-PASS row that is not the canonical.
- PA3 (issue row 1) rotate + `ROT_PASS_SET` + plaintext `hcloud_volume.git_data` delete -> ABORT; assert output names `hcloud_volume.git_data` and not only a nonzero rc.
- PA4 (issue row 2) replace + `PASS_SET` + `hcloud_volume.git_data_luks` delete -> ABORT; output names `hcloud_volume.git_data_luks`. Also replace + `ROT_PASS_SET` -> ABORT (a rotate plan graded as replace).
- PA5 (issue row 3) `{"resource_changes":[]}` in replace and in rotate -> ABORT, output names the missing NIC create. Variants: `resource_changes` null and key absent -> ABORT (readable arm). Entry with empty actions -> ABORT (classifiable arm).
- PA6 NIC create missing -> ABORT; plaintext attachment create missing -> ABORT; LUKS attachment create missing -> ABORT (each with the otherwise-passing set).
- PA7 mode "", "bogus", "REPLACE" -> ABORT with the wiring-fault message. `git_data_gate_mode` maps `git-data-host-replace` -> replace, `git-data-host-rotate` -> rotate, anything else (empty, `git-data-host-create`, `web-host-replace`) -> rc 1 and no stdout.
- Forget action on a preserved volume counts the same as delete (one row).
- Mutation rows via `gate_mutate_and_check` against the new function: see Guard Contract.
- Raise the anti-vacuity floor from 55 by the number of added assertions (floor, not equality; set it to the count measured after Phase 2 minus the HK13 skip allowance, as the existing comment prescribes).

Edit `plugins/soleur/test/terraform-target-parity.test.ts` in the git-data describe: the apply step block sets `APPLY_TARGET: ${{ inputs.apply_target }}` in `env`, sources `git-data-host-replace-gate.sh`, calls `git_data_host_post_apply_assert` under `if !` with an `exit 1` arm, derives the mode through `git_data_gate_mode "$APPLY_TARGET"`, and no longer contains the inline `for VOL in hcloud_volume.git_data` loop.

### Phase 2 - Library (GREEN)

In `tests/scripts/lib/git-data-host-replace-gate.sh`, below `git_data_host_replace_gate`:

- `git_data_gate_mode <apply_target>`: `case` mapping above; `*) return 1`.
- `git_data_host_post_apply_assert <plan_json> <mode>`: builds the preserved-volume set structurally per mode (`replace`: `hcloud_volume.git_data` + `hcloud_volume.git_data_luks`; `rotate`: `hcloud_volume.git_data` only; `*)`: print `git_data_host_post_apply_assert: unknown mode '<m>' - wiring fault, refusing`, return 1); then `plan_gate_assert_readable` and `plan_gate_assert_classifiable` with `|| return 1`; then the preserved-volume loop (same jq as today, `!= "0"` form so an empty jq result fails closed); then the NIC create assertion and the two attachment-create assertions, every failure message carrying the address and the original "should have been caught by the guard" wording. Output discipline: addresses and counts only, never `.change.before/after`. Mode-aware success line (replace: "both data volumes preserved"; rotate: "plaintext volume preserved; LUKS volume replaced as intended by the rotate arm").
- Update the file header usage block and the comment on `git_data_host_replace_gate` that says the asserts live inside the function: add a short pointer that the post-apply backstop lives beside it.

### Phase 3 - Workflow wiring

In `.github/workflows/apply-web-platform-infra.yml`, step id `apply` in job `git_data_host_replace` (~line 4012):

- Add `APPLY_TARGET: ${{ inputs.apply_target }}` to `env`.
- Rename the step display name to "Terraform apply (git-data-host -replace) - preserved-volumes assert" (the old name is false under rotate); grep confirmed nothing else keys on the old name (only a synthetic fixture in `tests/scripts/test-infra-privileged-tier-census.sh`, which does not read the workflow). Keep `id: apply` untouched: the poll step and Dispatch summary read `steps.apply.outcome`.
- Replace the inline jq loops with: source the lib (`shellcheck source=` directive kept), `GATE_MODE=$(git_data_gate_mode "$APPLY_TARGET") || { echo "::error::..."; exit 1; }`, `if ! git_data_host_post_apply_assert tfplan.json "$GATE_MODE"; then echo "::error::..."; exit 1; fi`. The `terraform apply` call and its mid-replace recovery annotation stay byte-identical. The fingerprint tail (`#7226`) stays.
- Update the step comment: rotate legitimately replaces the LUKS volume; the plaintext volume is asserted preserved in both modes.
- Do not add any `-target=`, `-replace=` or `EXTRA_` text to the job block. The plan step, the `GATE_MODE` derivation and the rotate-confirm step are untouched.

### Phase 4 - Verify (local only)

Run: `bash tests/scripts/test-git-data-host-replace-gate.sh`; `cd plugins/soleur && bun test test/terraform-target-parity.test.ts`; `bash tests/scripts/test-git-data-root-key-arm.sh`; `bash tests/scripts/test-git-data-boot-signal-poll.sh`; `bash tests/scripts/test-plan-gate-preamble.sh`; `bash tests/scripts/test-infra-privileged-tier-census.sh`; `shellcheck` on the lib; `actionlint` if available; `python3 scripts/lint-encryption-posture.py --repo-sweep` from the worktree (expected PASS, unchanged: no `.tf` file is touched). Replay the issue's repro offline by writing a synthetic rotate plan fixture and running the function: this is a local jq run, not a dispatch.

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` (apply step of job `git_data_host_replace`)
- `tests/scripts/lib/git-data-host-replace-gate.sh`
- `tests/scripts/test-git-data-host-replace-gate.sh`
- `plugins/soleur/test/terraform-target-parity.test.ts`

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10137-rotate-arm-volume-assert/tasks.md` and `decision-challenges.md` (planning artifacts only).

No docs, legal text, ADR or C4 file is edited. No ledger sentence is added; if a later PR adds one it must state measured / policy / inherited and date any past measurement. Nothing in this change claims reopen, passphrase-loss recovery, re-escrow, a state-restore substrate, or emptiness for web-2.

## Open Code-Review Overlap

None. (Queried open `code-review` issues for each file in Files to Edit on 2026-10-12; no body names any of them.)

## Architecture Decision (ADR/C4)

Skipped: a bug fix inside an existing assertion, no ownership, substrate, trust-boundary or ADR-reversal change. A reader of ADR-239 and the C4 model would not be misled after this ships; the ADR amendment already names #10137 as the fix. Recorded in `decision-challenges.md`.

## Infrastructure (IaC)

No new infrastructure and no `.tf` change. Apply path: not applicable; the change affects only how an already-authorized dispatch grades its saved plan after apply. Host fan-out: the edited step is in the single git-data job; no fleet sibling carries this assertion (registry/inngest/web-host jobs have their own volume asserts, unchanged).

## User-Brand Impact

- **If this lands broken, the user experiences:** either a rotate that still reports failure and keeps the flip chain (#8209, #8609, #8573) blocked, or, worse, a backstop that no longer fails when a data volume is deleted, so a plaintext-store or replace-mode LUKS-store loss goes unflagged. No user-facing page changes.
- **If this leaks, the user's data is exposed via:** no exposure vector is added; the function prints addresses and counts only, never `.change.before/after` (a replace plan's before-values can carry old user_data).
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** the backstop is the second of two layers (the pre-apply gate also forbids a plaintext-volume action in both modes), so a single defect does not alone lose user data, which keeps it below `single-user incident`.

## Observability

```yaml
liveness_signal:
  what: the job concludes success on a valid rotate and failure on a volume delete (the step exit code is the signal)
  cadence: per dispatch
  alert_target: GitHub Actions job conclusion plus the existing Dispatch summary step
  configured_in: .github/workflows/apply-web-platform-infra.yml (job git_data_host_replace)
error_reporting:
  destination: GitHub Actions error annotation from the step
  fail_loud: "::error::" annotation naming the address and the delete/forget count, then exit 1
failure_modes:
  - mode: preserved volume shows delete/forget in the applied plan
    detection: post-apply assert fails the step
    alert_route: red job plus annotation
  - mode: mode derivation fails (unknown apply_target)
    detection: git_data_gate_mode returns 1, step exits 1 with annotation
    alert_route: red job plus annotation
  - mode: plan JSON unreadable or empty
    detection: readable arm or missing NIC/attachment create
    alert_route: red job plus annotation
logs:
  where: GitHub Actions run log (public repo; the gate prints no before/after values)
  retention: GitHub default (90 days)
discoverability_test:
  command: grep -c "git_data_host_post_apply_assert tfplan.json" .github/workflows/apply-web-platform-infra.yml
  expected_output: "1"
```

## Guard Contract

### Guard 1 - git_data_host_post_apply_assert

**Property.** After a git-data replace or rotate apply, the saved plan shows no delete/forget on any volume that the dispatch mode must preserve, and shows the private NIC and both store attachments re-created, and anything the function cannot read or classify fails.

**Assembly.** One chokepoint: the function `git_data_host_post_apply_assert` in `tests/scripts/lib/git-data-host-replace-gate.sh`, called from exactly one workflow site (step `apply` of job `git_data_host_replace`, which serves both `git-data-host-replace` and `git-data-host-rotate`). The quantified members are the per-mode preserved-volume array, the NIC address, and both attachment addresses; the mode comes from `git_data_gate_mode`, the single mapping from `apply_target`. The plan step's inline `GATE_MODE` derivation is a second mapping site that this PR leaves in place; a parity test row asserts both map the same two targets. Other jobs (registry, inngest, web-host) have separate asserts and are out of the property.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Rotate arm preserved set emptied (plaintext volume dropped from the rotate set), plan has plaintext delete | PA3 fixture passes the neutered gate, so `gate_mutate_and_check` reports the arm load-bearing (suite stays green only because the mutant is caught) |
| 2 | Replace arm preserved set loses the LUKS volume, plan has LUKS delete | PA4 fixture passes the neutered gate: caught |
| 3 | NIC-create assertion neutered | empty-plan row PA5 passes the neutered gate: caught |
| 4 | One attachment-create assertion neutered after a compliant first (second-member row) | PA6 attachment fixture passes the neutered gate: caught |
| 5 | The `*)` mode arm turned into a permissive default | PA7 passes the neutered gate: caught |
| 6 | The readable/classifiable calls deleted (the guard's own dispatch) | null / absent / empty-actions fixtures pass the neutered gate: caught; plus the anti-vacuity floor must fire if the whole section is deleted |
| 7 | Reorder: the preserved-volume loop moved after an early `return 0` | PA3/PA4 must go RED in the suite itself (observed inside the function, not after return) |

**Harness rows.** Edit to the suite: delete the PA3 call and the anti-vacuity floor must fall under its threshold and fail the suite. Must-PASS non-canonical inputs: PA2 (rotate plan with LUKS delete+create) and a replace plan with a preserved volume explicitly present as `no-op` (differs from the canonical omitted shape). A guard that rejects everything would fail both.

**Anchor.** The pre-apply gate `git_data_host_replace_gate`, run on the same saved `tfplan.json` before `terraform apply`, is the independent control; this backstop is a belt-and-suspenders re-read of the same document, not an integrity anchor for a stored value.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "in rotate mode skip hcloud_volume.git_data_luks in the post-apply delete/forget loop and keep asserting the plaintext hcloud_volume.git_data" | Phase 2 preserved-volume set (rotate) | mapped |
| 2 | "in plain replace mode keep both volumes asserted preserved" | Phase 2 preserved-volume set (replace) | mapped |
| 3 | "Extract the post-apply loop into tests/scripts/lib/git-data-host-replace-gate.sh, pass APPLY_TARGET into the step" | Phase 2, Phase 3 | mapped |
| 4 | "add three matrix rows in tests/scripts/test-git-data-host-replace-gate.sh (plaintext deleted under rotate; LUKS deleted under plain replace; empty resource_changes must not pass)" | Phase 1 PA3, PA4, PA5 | mapped |
| 5 | "Keep plugins/soleur/test/terraform-target-parity.test.ts green." | Phase 1 (added assertions) and Phase 4 | mapped |
| 6 | "NO workflow dispatch, terraform apply, Doppler write, volume wipe or destroy" | Phase 4 runs local jq/bash only | mapped |
| 7 | "Run lint from a worktree: python3 scripts/lint-encryption-posture.py --repo-sweep" | Phase 4 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Preserved-volume set per mode | "skip hcloud_volume.git_data_luks ... keep asserting the plaintext" | asked |
| Extract whole block incl. NIC/attachment asserts | "Extract the post-apply loop" | inferred - justification: the empty-resource_changes row cannot be tested or satisfied by a volume loop alone; CTO ruling 2026-10-12 |
| `git_data_gate_mode` helper | "pass APPLY_TARGET into the step" | inferred - justification: a lib helper keeps one mapping instead of a second inline case; CTO ruling 2026-10-12 |
| Extra rows PA6, PA7, null/absent/empty-actions variants, mutation rows | "add three matrix rows" | inferred - justification: the three named rows plus fail-closed mode arm (CTO ruling) and Guard Contract matrix (plan gate 2.12) |
| Step display-name rename | "both-volumes-preserved assert fails" | inferred - justification: the old name is false under rotate; nothing keys on it (grep) |

### Split Assessment

- Subsystems touched: 3 - `.github/workflows`, `tests/scripts`, `plugins/soleur/test`
- Planned files: 4 | Estimated changed lines: ~330
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `git_data_host_post_apply_assert` and `git_data_gate_mode` exist in `tests/scripts/lib/git-data-host-replace-gate.sh`; the workflow apply step calls them and the inline `for VOL in hcloud_volume.git_data` loop is gone (`grep -c 'for VOL in' .github/workflows/apply-web-platform-infra.yml` shows no match inside job `git_data_host_replace`).
- [ ] Rotate + plan with LUKS delete+create passes; rotate + plaintext delete fails; replace + LUKS delete fails; replace + plaintext delete fails; empty, null and absent `resource_changes` fail in both modes; unknown/empty mode fails.
- [ ] `bash tests/scripts/test-git-data-host-replace-gate.sh` exits 0 with a raised anti-vacuity floor; each Guard Contract mutation row is exercised by a row that fails when the arm is neutered.
- [ ] `cd plugins/soleur && bun test test/terraform-target-parity.test.ts` is green, including the new apply-step assertions; the plan step, `GATE_MODE` derivation and "Validate dispatch inputs (rotate confirm token)" step are byte-unchanged (`git diff` shows no hunk in them).
- [ ] The apply step's `terraform apply` invocation and mid-replace recovery annotation are byte-unchanged; `id: apply` retained.
- [ ] `python3 scripts/lint-encryption-posture.py --repo-sweep` run from the worktree reports PASS.
- [ ] `git diff --stat main` lists only the four Files to Edit plus files under `knowledge-base/project/{plans,specs}/`.
- [ ] No `gh workflow run`, `terraform apply`, `doppler secrets set`, volume wipe or destroy was executed (transcript check).
- [ ] PR body contains `Closes #10137` and `Ref #6897`, and states that a fresh rotate dispatch is not part of the PR and needs the operator to name the command.

## Test Scenarios

- Given a rotate plan that replaces the LUKS volume, when the post-apply assert runs in rotate mode, then it exits 0.
- Given the same plan graded as replace, then it exits 1 naming `hcloud_volume.git_data_luks`.
- Given `{"resource_changes":[]}`, then both modes exit 1 naming the missing NIC create.
- Given `apply_target=git-data-host-create`, then `git_data_gate_mode` returns 1 and the step exits before grading.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: CI-assertion fix on existing infrastructure grading; no user-facing surface, no legal text, no ledger sentence.

## Sharp Edges

- A `## User-Brand Impact` section that is empty or placeholder fails deepen-plan; this plan fills it.
- The parity test filters job-block lines on `EXTRA_`, `-target=` and `-replace=`; any new comment or code in the job containing those strings changes what it extracts. Keep the new step text free of them.
- Under `set -e`, a bare `git_data_host_post_apply_assert ...` inside the step is fail-open when errexit is suspended; always `if ! ...; then exit 1; fi`.
- A `jq` failure yields an empty string; keep the `!= "0"` comparison form so empty fails closed, and keep counters validated with `plan_gate_assert_numeric` where arithmetic is used.
- The flip gate keys on the step name matching "rotate confirm token"; do not rename it.
- The Observability probe greps the call text `git_data_host_post_apply_assert tfplan.json`; keep exactly one such call line in the workflow (comments must name the function without the `tfplan.json` suffix) or the expected count of `1` drifts.
- Do not claim that this PR fixes the flip: it removes the false failure only. The flip gate still needs a successful rotate run, which is operator-named.

## Amendment 2026-10-12 (review, #10155)

Two design-validity seats (simplicity, architecture) converged that the second apply_target-to-mode mapping (`git_data_gate_mode`, the apply step's `APPLY_TARGET` env, PA8 and a substring parity test) was avoidable. Ruled by CTO agent, 2026-10-12: the plan step publishes the mode its gate accepted as a `gate_mode` step output and the apply step reads it through `env: GATE_MODE: ${{ steps.plan.outputs.gate_mode }}`; the post-apply mode is then by construction the mode the saved plan was graded under, and an absent output reaches the assert's unknown-mode arm and refuses. The Phase 2/3 text above that names `git_data_gate_mode` and `APPLY_TARGET` describes the pre-review design and is superseded by this section. The mid-replace annotation and the readiness note were also made mode-aware (AP-021: a CI message names only a cause the job measured).
