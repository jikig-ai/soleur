---
title: "git-data: retire the plaintext arms from the host replace/birth/rotate gates (PR-1), then blank git_data_volume_id (PR-2)"
date: 2026-10-28
slug: chore-retire-plaintext-arms-git-data-host-gates
branch: feat-one-shot-11194-retire-plaintext-arms
issue: 11194
closes: none (PR-1 and PR-2 both use `Ref #11194`; the issue is closed by the owner after the real dispatch)
type: chore
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-10-28
**Method:** the plan was already built on four research agents, a CTO ruling set (A-E, F1-F3), CPO/CLO consults and a five-agent plan review; deepen-plan re-ran every halt gate mechanically and re-verified the load-bearing claims against the tree instead of fanning out a second round of generic agents (the surface is one repo's bash+jq gates, with no external framework to research).

### Gate results

- 4.6 User-Brand Impact present, threshold `single-user incident`: pass. 4.7 Observability: all five fields present, command's first token `python3`, no SSH, finishes well under 15 s, literal `0`: pass (command run at plan time, printed `3` pre-change). 4.8 PAT-shaped variables: none. 4.9 UI wireframe: no UI surface, skipped. 4.10 Encryption Posture: triggered by the `.tf` comment edit, section added above. 4.11 Guard Contract: `lint-guard-contract.py` reports 4 entries, matrices carry the labeled `**Mutation matrix.**` field. 4.12 Scope Check: all asks mapped, no unjustified `inferred` row. 4.13 Task Design: no new autonomous task surface, skipped. 4.5 network-outage and 4.55 downtime halts: neither trigger fires (no SSH/timeout work; PR-1 changes no serving resource, and the host replace is an owner dispatch outside this plan).

### Verified at deepen time

- Rung-2 hash set (`git_data_rung2_bound_files`): `cloud-init-git-data.yml`, `modules/git-data-userdata/main.tf` and its `file()` payloads; `git-data.tf`, the gate libs and the readiness-gate lib are outside it, so PR-1 and PR-2 leave rung-2 evidence valid.
- `plan_only` is a `workflow_dispatch` input documented for the replace routes; the create job honors it only in later steps, so the interlock runs unconditionally there.
- #11194, #10296 and #11433 are OPEN; no open PR other than this branch's draft names #11194.

### New considerations carried into the plan

- Two independent reviewers found the same trap (a gate-green dispatch into a FATAL boot between PR-1 and PR-2): the interlock (Guard 4) is the fix.
- `test-git-data-wipe-wedge.sh` is a second consumer of the replace gate's fixtures (P0 caught by architecture review).
- Several mutation rows were equivalent mutants or bash-version-dependent and were cut or re-anchored.

## Overview

The plaintext git-data volume (`hcloud_volume.git_data`, id 106867358) and its attachment were destroyed at the
provider on 2026-10-27 and left the HCL and state. The git-data host replace, rotate and birth gates still demand
both addresses, and three workflow `-target` lines still name them, so every dispatch of those routes fails closed
and the only remediation lever for the host that stores every connected user's source code is dead.

**Delivery is two PRs, by CTO ruling (forks A3 and F1-F3, recorded in `decision-challenges.md`).**

- **PR-1 (this branch)** retires the plaintext arms from the replace gate (both modes), the post-apply assert, the
  birth gate, the three `-target` lines, the parity constants, the fixtures and the floors; updates every
  runbook/ADR/C4/ledger line that says the routes are disabled; and adds one small fail-closed **plaintext-id
  interlock** to both dispatch jobs (see Phase 3.3) so that, between PR-1 and PR-2, a dispatch cannot pass the now
  plaintext-free gate and boot the new host into the bootstrap's `plaintext_unverified` FATAL. PR-1 changes no
  rendered `user_data`.
- **PR-2 (separate branch off `main`)** is the one-hunk `git_data_volume_id = ""` edit in
  `apps/web-platform/infra/git-data.tf` plus removal of the `SOLEUR-DEBT` marker. It changes `user_data`, so
  `hcloud_server.git_data` plans a ForceNew replace at the owner's dispatch. It satisfies the PR-1 interlock.

Both PRs use `Ref #11194`, never `Closes`: the issue stays open as the tracker for the owner's real dispatch and is
closed by the owner after it. Neither PR dispatches anything, arms auto-merge, merges, or writes to Doppler; the
owner's explicit "DO NOT MERGE" overrides the pipeline's default auto-merge step (`wg-after-marking-a-pr-ready-run-gh-pr-merge`).

**Does merging PR-1 alone mutate production? No.** Both push-triggered apply workflows
(`apply-web-platform-infra.yml`, `apply-deploy-pipeline-fix.yml`) fire on `apps/web-platform/infra/**`, but the
git-data resources are `OPERATOR_APPLIED_EXCLUSIONS` (in no per-merge `-target` set), the only
`apps/web-platform/infra/` edit is comments in `git-data.tf`, and the edited `git_data_host_replace` /
`git_data_host_create` jobs are `workflow_dispatch`-only. `apply-deploy-pipeline-fix.yml`'s untargeted post-apply
plan only feeds `tests/scripts/lib/git-data-wedge-gate.sh`, which already refuses any plan that re-creates the
retired addresses; it stays as the pre-existing fail-closed tripwire for untargeted plans. **PR-2 alone does not
mutate production either** (same exclusion; the replace job is dispatch-only), but it makes the live host's
`user_data` diverge from HCL until the owner's dispatch, so `scheduled-terraform-drift.yml` files a drift issue. The
PR-1 body's first line states "merging this PR alone changes no production resource".

## Research Insights

### Premise Validation (Phase 0.6)

- #11194 is OPEN (milestone Phase 4: Validate + Scale), no closing PR. Epic #8211 OPEN. Collision pre-check: the only open PR naming #11194 is this branch's own draft PR #11432.
- Cited artifacts confirmed on `origin/main`: both gate files, `git_data_host_post_apply_assert`, the three workflow `-target` lines (replace job `-target='hcloud_volume_attachment.git_data'`; create job `-target='hcloud_volume.git_data'` and `-target='hcloud_volume_attachment.git_data'`), the three parity constants, and the `SOLEUR-DEBT` marker above `module "git_data_userdata"`.
- Stale premise found: the issue says "three jobs" carry the lines; it is two jobs (replace, create); the rotate selector reuses the replace job.
- Mechanism vs ADR corpus: ADR-239 Amendment 2026-10-26 item 4 names exactly two ways to end #11194 (`id = ""` or a bootstrap that treats a missing device as absent). The bootstrap option edits a hash-bound rung-2 payload (see Cut List). The ADR also fixes the owner order (merge, then dispatch within ~24 h) and forbids merging a `user_data`-changing PR before the dispatch.
- The empty-id render branch has never booted: the rung-2 rehearsal root passes a non-empty id, and #10296 (PR-R) was never built (`RUNG2_PLAINTEXT_VOLUME` appears only in archived specs). Availability risk only (the LUKS volume is preserved by the replace gate).
- Pre-change measurements (plan-time): 3 `hcloud_volume(_attachment).git_data'` target lines in the workflow; 10 hits of `plaintext_attachment_recreated|git_data_volume_destroyed` in the replace gate.

### Property List and Cut List (Phase 0.6b)

Properties the issue is really buying:

1. P1: a correct scoped replace/rotate/birth plan (host + NIC + LUKS attachment + firewall + host key + pin) passes its gate with no plaintext addresses present.
2. P2: the gates stay fail-closed: any positive action on either retired address, and any destroy of the LUKS volume, passphrase or attachment, is still refused in every mode.
3. P3: workflow `-target` lines, gate allow-sets, parity constants and fixtures agree (no stale count passes by accident).
4. P4: no document tells an operator the routes are disabled or "void" once they are not.
5. P5 (PR-2): the replace target renders `plaintext_volume=absent`.
6. P6: between PR-1 and PR-2 no dispatch can apply a plan that boots into `plaintext_unverified`.

Cut List (mechanism → property → what already covers it):

- Bootstrap treats a nonexistent device as absent → P5 → `git_data_volume_id = ""` already selects `plaintext_volume=absent` in the unchanged bootstrap; the bootstrap edit is hash-bound (invalidates rung-2 evidence, needs a paid rehearsal) and weakens the #10138 property that a missing device never reads as "no plaintext volume". Cut (CTO fork A).
- New named jq tripwire counter for the retired addresses → P2 → `out_of_scope` (positive-action filter, retired addresses left out of every allow-set) already refuses them; fixture rows instead (CTO fork C).
- Removing the dead plaintext arm from `cloud-init-git-data.yml`/`git-data-bootstrap.sh` → none of P1-P6 → hash-bound; deferred to #11433.
- Art. 30 register pointer retarget and the model.c4 issue-number wording → P4 only marginally → cut from PR-1 (plan review, simplicity + DHH); model.c4 is reworded to point at ADR-239 (no issue numbers); the register pointer is retargeted by the PR that removes the arm (#11433 body says so).
- Retiring `git-data-wedge-gate.sh` / wipe-mode machinery → none → it still refuses plans that re-create the retired addresses (harmless, fail-closed); out of the issue's scope.
- Verbs `update`/`forget` in the retired-address rows → P2 → `out_of_scope` is one filter over positive actions; `create` and `delete` per address per gate exercise both allow-set membership and the destroy arms (DHH P2).

### Institutional learnings applied

- Floors move by exact recount at the call sites (ADR-193; `2026-10-26-a-guard-whose-rows-were-hand-written-per-instance-...`): generate retired-address rows from an array.
- A mutation battery only covers what it mutates (`2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`): re-aim the battery at every surviving arm; equivalent mutants (a backstop shadowed by `out_of_scope`) get a layered row or no row.
- `terraform-target-parity.test.ts` parses only `terraform_data.*` targets one-directionally; a `-target` matching nothing exits 0 silently (`2026-06-17-terraform-target-parity-test-guards-only-terraform-data-subset.md`): check non-`terraform_data` targets by hand against the `.tf` files.
- Sweep by subject, not phrasing (`2026-10-27-a-record-pr-for-a-destroy-needs-a-claim-limit-before-the-first-sentence.md`): docs edits must not claim more than the read-back measured.
- A guard over HCL text must lex it (comments, brace depth, duplicates) (sharp-edges, #8667): the plaintext-id interlock's extractor is fixtured accordingly.

### Key paths (content anchors)

- Gates: `tests/scripts/lib/git-data-host-replace-gate.sh` (`def allow:`, counters `git_data_volume_destroyed`, `plaintext_attachment_recreated`, `git_data_host_post_apply_assert` `vols=` per mode, the attachment loop); `tests/scripts/lib/git-data-host-birth-gate.sh` (`_GIT_DATA_BIRTH_ALLOW`, `volume_destroys`, `volume_updates`, entailed loop, presence loop).
- Workflow: `.github/workflows/apply-web-platform-infra.yml` jobs `git_data_host_replace` and `git_data_host_create`; the replace job has a `plan_only` dispatch input (plan + the path's own gate, stops before any apply).
- Parity: `plugins/soleur/test/terraform-target-parity.test.ts` (`GIT_DATA_REPLACE_TARGETS`, `GIT_DATA_PRESERVED_VOLUMES`, `GIT_DATA_BIRTH_TARGET_BASES`, `OPERATOR_APPLIED_EXCLUSIONS`, `TEST_FLOOR`).
- Second consumer of the replace gate's fixtures: `tests/scripts/test-git-data-wipe-wedge.sh` (its `PASS_SET` carries `VA_REPLACE`, its control row H2 and the SANCTIONED check require the real replace gate to PASS that plan): a full edit, not comment-only.
- Interlock home: `tests/scripts/lib/git-data-birth-readiness-gate.sh` (already sourced by both dispatch jobs; not in the rung-2 hash set) and its suite `tests/scripts/test-git-data-birth-readiness-gate.sh`.
- Rung-2 hash input set: `git_data_rung2_bound_files` = `cloud-init-git-data.yml` + `modules/git-data-userdata/main.tf` + its `file()` payloads. `git-data.tf` and the gate files are NOT bound, so PR-1 and PR-2 leave rung-2 evidence valid.
- Per-merge/drift: git-data resources are `OPERATOR_APPLIED_EXCLUSIONS`; `scheduled-terraform-drift.yml` runs an untargeted `terraform plan -detailed-exitcode` and files `infra: drift detected in web-platform` (report-only).

## Research Reconciliation — Spec vs. Codebase

| Issue / brief claim | Reality | Plan response |
|---|---|---|
| "the three `-target` lines" in "three jobs" | Two jobs: replace (1 line), create (2 lines); rotate reuses replace | Edit exactly those three lines; assert via parity |
| Prose counts in gates/parity/workflow ("5-member", "eighteen", "twenty", "seventeen", "15 presence members") | Already stale/inconsistent | Delete the number words rather than re-count them (AC-8) |
| "`id = ""` or a bootstrap that treats a nonexistent device as absent" (ADR item 4) | Bootstrap path is hash-bound and weakens #10138 | Take `""`, in PR-2 (CTO A3) |
| Scope (2)/(3) "in this change" | `""` changes `user_data`; ADR item 4 forbids merging such a PR before the dispatch | Split into PR-2; both PRs `Ref` |
| "`test-git-data-wipe-wedge.sh`: comment only" (first draft) | Its `PASS_SET` includes the retired attachment and rows H2/SANCTIONED need the real gate to PASS it | Full fixture edit + floor recount (architecture review P0) |
| Ledger row `hcloud_volume.rehearsal` reevaluate_when: "#11194 retires the plaintext arm from the cloud-init template" | Neither PR touches the template/bootstrap | Retarget the text to #11433, keep `expires_on` 2026-12-31 |
| Gates are the only brake on a dispatch in the window (stale gates) | After PR-1 they pass while `git-data.tf` still renders a deleted device | PR-1 adds the plaintext-id interlock (CTO F1) |

## Open Code-Review Overlap

- #11388 (alert-guards drift guards, touches `apply-web-platform-infra.yml`): Acknowledge. Different concern; no shared lines.
- #10112 (#9786 residuals incl. "unused rehearsal volume", touches `scripts/encryption-posture-ledger.json`): Acknowledge. The rehearsal-volume residual is the row #11433 will retire; this plan only retargets its `reevaluate_when` text.

## User-Brand Impact

**If this lands broken, the user experiences:** a later owner-dispatched git-data host replace/rotate either refuses forever (no recovery lever while push/pull and the Art. 17 bare-repo erasure path are down) or, worse, is graded by a widened allow-set and a LUKS-store destroy or passphrase rotation reaches an apply, stranding the at-rest data behind connected users' repositories; or a dispatch in the PR-1/PR-2 window replaces the live host into a FATAL boot.

**If this leaks, the user's workflow is exposed via:** the gates print counters and addresses only (never `.change.before/.after`); this change must not add any output of plan values (the HK12/PA8 sentinel rows stay and keep passing, the new interlock prints no HCL value beyond the literal's emptiness verdict). No secret or credential path changes.

**Brand-survival threshold:** single-user incident

`requires_cpo_signoff: true`. CPO signed off at plan time (2026-10-28) on three conditions, all carried as ACs: (1) negative fixtures prove LUKS volume/attachment/passphrase destroys stay refused and the parity pins are a drift test, with explicit named backstops rather than omission alone; (2) the interim state is written in runbook and ADR, PR-1 says `Ref`, PR-2 has a tracked issue; (3) a verification path exists since nothing is dispatched (the owner-run `plan_only` dispatch, CTO F3). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "retire the plaintext arms from tests/scripts/lib/git-data-host-replace-gate.sh and git-data-host-birth-gate.sh, `git_data_host_post_apply_assert`, the three `-target` lines in .github/workflows/apply-web-platform-infra.yml, their parity constants (GIT_DATA_REPLACE_TARGETS, GIT_DATA_BIRTH_TARGET_BASES, GIT_DATA_PRESERVED_VOLUMES) and test fixtures" [brief] | PR-1 Phases 1-4 | mapped |
| 2 | "make the replace target `git_data_volume_id = \"\"` ... decide whether this is done in the same PR via git-data.tf or as a bootstrap that treats a nonexistent device as absent, keeping the gates fail-closed" [brief] | PR-2 (CTO A3: separate small PR; bootstrap option cut) plus the PR-1 interlock | mapped |
| 3 | "remove the SOLEUR-DEBT marker at the module call in git-data.tf" [brief] | PR-2 (PR-1 only rewords the marker's trigger text) | mapped |
| 4 | "also update the runbook lines that say the replace route is disabled" [brief] | PR-1 Phase 5 | mapped |
| 5 | "DO NOT MERGE. Do not arm auto-merge, do not run `gh pr merge`, do not dispatch git-data-host-replace, git-data-cutover.yml, apply-web-platform-infra.yml or flip.sh, and do not write to Doppler." [brief] | Overview; AC-15; Phase 7 | mapped |
| 6 | "Stop after review passes and the PR is open and ready (CI green), then report the PR URL" [brief] | Phase 7 (both PR URLs reported) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Gate/post-apply/workflow/parity/fixture edits (incl. `test-git-data-wipe-wedge.sh` fixtures) | "retire the plaintext arms from tests/scripts/lib/git-data-host-replace-gate.sh and git-data-host-birth-gate.sh" | asked |
| Floor recounts (suite floors, parity `TEST_FLOOR`) | "their parity constants ... and test fixtures" | asked (the floors are the fixtures' anti-vacuity contract; ADR-193) |
| Retired-address refusal rows | "keeping the gates fail-closed" | asked |
| Runbook/`git-data.tf` comment/wipe-wedge comment/workflow prose edits | "update the runbook lines that say the replace route is disabled" | asked |
| Plaintext-id interlock in both dispatch jobs (Phase 3.3) | "keeping the gates fail-closed" | inferred — justification: removing the stale gates removes the only automatic brake on a dispatch that would destroy the live host into a FATAL boot; two independent plan reviewers and the CTO (F1) ruled it required |
| ADR-239 new dated amendment, model.c4 + regenerated `model.likec4.json` | — | inferred — justification: wg-architecture-decision-is-a-plan-deliverable; model.c4 states "routes are disabled until #11194", falsified by PR-1; `c4-model-freshness` byte-diffs the JSON |
| Ledger `reevaluate_when` retarget | — | inferred — justification: it names #11194 as removing the bootstrap arm, which neither PR does; a dangling clock rots |
| Tracking issue #11433 (bootstrap arm) | — | inferred — justification: wg-when-deferring-a-capability-create-a for the hash-bound arm cut by CTO fork E |
| PR-2 branch | "make the replace target `git_data_volume_id = \"\"`" | asked |

### Split Assessment

- Subsystems touched: 6 — `tests/scripts`, `plugins/soleur/test`, `.github/workflows`, `knowledge-base`, `scripts`, `apps/web-platform/infra` (comments only)
- Planned files: ~20 | Estimated changed lines: ~900 (mostly fixtures and prose)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR for the gate retirement, because the parity test enforces workflow == gate allow-set == constant == fixtures in lockstep, so any split inside it would leave `main` red. The only split is the CTO-ruled PR-2 (`git-data.tf` literal), a different blast radius (it changes `user_data`).

## Architecture Decision (ADR/C4)

### ADR

Append a short dated **Amendment 2026-10-28** to `ADR-239-git-data-serves-from-luks-at-birth.md` via `soleur:architecture` (earlier text, including item 4, unedited): the replace, rotate and create gates no longer demand the retired plaintext addresses; the routes are gated by the plaintext-id interlock until `git_data_volume_id` is blanked (PR-2); #11433 holds the dead bootstrap arm; the claim limit of Amendment 2026-10-27 is unchanged and the volume is already destroyed. No new ADR: this extends ADR-239. Written as final-state facts; the PR-1/PR-2 sequencing lives in the PR bodies and the runbook.

### C4 views

READ in full before editing: `model.c4`, `views.c4`, `spec.c4` (done at plan time for the git-data elements). Actors/systems/relationships checked and already modeled: `platform.infra.gitDataStore`, `github -> gitDataStore` (root SSH, ADR-220), `hetzner -> gitDataStore` (probe), `gitDataStore -> sentry` (boot fatals), `doppler`, `hetzner`; no new actor, system, store or access relationship. The only falsified text is the `gitDataStore` description sentences "The bootstrap's plaintext arm stays until #11194 ... the host replace, rotate and create routes are disabled until #11194". Reword that sentence to point at ADR-239 Amendment 2026-10-28 (no issue numbers), then regenerate with `bash scripts/regenerate-c4-model.sh` and run `plugins/soleur/test/c4-model-freshness.test.sh` and `c4-count-parity.test.sh` (the C4 vitest pair runs in CI).

### Sequencing

The ADR amendment lands in PR-1 describing the post-PR-2 target state; it is not deferred.

## Implementation Phases (PR-1)

Order is test-first (`cq-write-failing-tests-before`): fixtures and parity pins first (RED against current code), then code.

### Phase 1 — Fixtures and parity pins (RED)

1.1 `tests/scripts/test-git-data-host-replace-gate.sh`: drop `VA_REPLACE` (and `hcloud_volume_attachment.git_data`) from `PASS_SET`/`ROT_PASS_SET`; delete T11 (plaintext attachment stripped), T2/T16 and R5 (plaintext volume delete/forget; superseded by the generated retired-address rows), the PA3/PA3b/PA3c/PA4b plaintext rows and PM1; re-aim PM2/PM5 `sed` anchors at the new post-apply lines; PA6 loses the plaintext-attachment row; PA1/PA1b/PA2 message anchors updated; PA8 volume-arm sentinel row moves to replace mode and the LUKS volume (its `hcloud_volume.git_data shows 1` anchor disappears), the PA8 attachment sentinel row and PM4 use the LUKS attachment only. Keep every LUKS row (T3, T4, T5, T6, T12, PA4, PA4c, PA3c-LUKS).
1.2 Retired-address rows, generated from one array (`RETIRED_ADDRS=(hcloud_volume.git_data hcloud_volume_attachment.git_data)`) × `create` and `delete` × replace, rotate, birth, each pinned to the arm text it must produce (replace/rotate: `out_of_scope=1`; birth `create`: the `out_of_scope` ABORT text, birth `delete`: the generic destroy arm text), each paired with a `no-op` control of the same plan that must PASS (so "ABORT" cannot come from an unrelated failure).
1.3 `tests/scripts/test-git-data-host-birth-gate.sh`: remove the two addresses from `entailed_four`/`rest_members`/`happy_changes`, retitle the "full twenty-two-address" PASS (no number word), narrow the volume destroy/update checks to the LUKS volume and anchor the LUKS destroy row on the named arm's own text ("DATA VOLUME") because the generic `destroys` arm also lists the offender.
1.4 `tests/scripts/test-git-data-wipe-wedge.sh`: drop `VA_REPLACE` from `PASS_SET` (control row H2 and the SANCTIONED check must still PASS the real replace gate); F1/F2 fixtures keep refusing through the replace gate's `out_of_scope`; update the header comment; recount its floor.
1.5 `plugins/soleur/test/terraform-target-parity.test.ts`: remove the retired addresses from `GIT_DATA_REPLACE_TARGETS` and `GIT_DATA_BIRTH_TARGET_BASES`; replace `GIT_DATA_PRESERVED_VOLUMES` and its test with a retired-addresses-absent assertion over every `-target`/`-replace` line of both jobs (the allow-set half is already enforced by the existing allow == targets == constant equality); entailed count follows the list length (derive, do not hard-code); remove the two `OPERATOR_APPLIED_EXCLUSIONS` entries (verify no test asserts exclusions still exist); add the wire pin for the plaintext-id interlock step in BOTH jobs (Phase 3.3).
1.6 `tests/scripts/test-git-data-birth-readiness-gate.sh`: add the interlock's must-PASS / must-ABORT fixtures (Guard 4).
1.7 Run the suites; confirm they are RED for the right reason.

### Phase 2 — Replace gate and post-apply assert

2.1 `git-data-host-replace-gate.sh`: remove `hcloud_volume_attachment.git_data` from `def allow:`, delete the `git_data_volume_destroyed` and `plaintext_attachment_recreated` counters, their extraction, `plan_gate_assert_numeric` args, echo fields, PASS condition terms (`gvd`, `patt`), and rewrite PASS/ABORT strings and header comments that name the plaintext volume, "BOTH volume attachments" or a member count. Keep `luks_volume_destroyed`, `luks_passphrase_touched` and `luks_attachment_recreated`.
2.2 `git_data_host_post_apply_assert`: drop the per-mode `vols` array; replace mode asserts the LUKS volume has no delete/forget via a plain `if [[ "$mode" == replace ]]` loop body over one volume, rotate asserts none (the pre-apply gate owns `luks_volume_rotated`); drop the plaintext attachment from the `for att in` loop; update the echo strings. Rotate keeps asserting the NIC and the LUKS attachment creates, which carry the empty-plan refusal.

### Phase 3 — Birth gate, workflow and interlock

3.1 `git-data-host-birth-gate.sh`: remove both addresses from `_GIT_DATA_BIRTH_ALLOW`, the entailed loop (`hcloud_volume_attachment.git_data`) and the presence loop (`hcloud_volume.git_data`); narrow `volume_destroys`/`volume_updates` selectors, the offender jq and the ABORT text (the line calling `hcloud_volume.git_data` "the plaintext store") to `hcloud_volume.git_data_luks`; delete number words ("twenty-two-address", "seventeen", "three ENTAILED", "all 15 presence members") and fix comments.
<!-- lint-infra-ignore start -->
3.2 `.github/workflows/apply-web-platform-infra.yml`: delete the three `-target` lines; fix the operator-facing text in the replace job: the rotate-abort `::error::` ("plaintext volume ... is still preserved"), the post-apply comment block and apply-failure annotations ("BOTH data volumes", "BOTH store attachments", "BOTH volumes are preserved"), the job-header target list comment (incl. the `git-data.tf:275` anchor) and the create job's "twenty -targets" prose. `scripts/test-all.sh` run_suite comment ("5-target, preserves BOTH data volumes") likewise. No dispatch-input edits.
<!-- lint-infra-ignore end -->
3.3 **Plaintext-id interlock (CTO F1).** New function `git_data_plaintext_id_interlock <path-to-git-data.tf>` in `tests/scripts/lib/git-data-birth-readiness-gate.sh`: extracts the `module "git_data_userdata"` block by brace depth, ignoring comment lines, requires exactly one top-level `git_data_volume_id` assignment inside it and that its value is the empty string; ABORTs on a non-empty value, a missing block, an unparsable block, zero or more than one assignment. Wired as a step before the plan step in `git_data_host_replace` (skipped when `inputs.plan_only == true`, so the F3 verification path is not blocked) and in `git_data_host_create` (unconditional: the `plan_only` input is documented for the replace routes only, and a create has no verification mode the interlock must leave open); the step prints only the verdict and the line number, never a value other than "empty"/"non-empty". PR-2 satisfies it; it stays afterward as a regression guard. Not hash-bound (the lib is outside `git_data_rung2_bound_files`; assert this in the PR).

### Phase 4 — Floors and counters (same commit as the rows they follow)

4.1 Floors count different units: the replace/birth/wipe-wedge suites floor the suite's own runtime `passes + fails`; the parity file's `TEST_FLOOR` floors `test(` declarations by that file's own regex. For each, record the observed count before (measured at the merge base) and after the change, keep the same slack the old floor had (replace: floor 101 vs 102 observed; birth: 135 vs 135), and set the new floor to the new observed count minus that slack. Show both numbers in the PR body (ADR-193: never lower a floor to fit a total without the arithmetic).
4.2 `grep -n "git-data-host-\|git-data-wipe-wedge" scripts/*.tsv tests/scripts/test-infra-privileged-tier-census.sh`; adjust only what a hit shows moved.
4.3 Every surviving arm (allow-set membership, entailed loop, presence loop, `luks_*` terms, post-apply `if`/loops, mode guard, the interlock) has a `gate_mutate_and_check` row whose `sed` changes the copy (the helper refuses a byte-identical mutant); the Guard Contract matrices are the spec for these rows.

### Phase 5 — Docs, ADR, C4, ledger

5.1 Runbooks, written as final-state facts: `git-data-birth.md` banner; `apply-web-platform-infra-job-rationale.md` §git_data_host_replace banner; `git-data-luks-cutover-5274.md` three "Routes disabled until #11194" banners and the "If the git-data host is lost (until #11194)" section. New wording: gates no longer demand the retired addresses; the replace, rotate and create routes refuse while `git-data.tf` carries a non-empty `git_data_volume_id` (the interlock); blank it with the one-hunk change, merge, and dispatch in one sitting (about 24 h, ADR-239 item 4); the `infra: drift detected in web-platform` issue is closed only by the dispatch's first clean drift run; before any real dispatch run `plan_only` (verification below); the owner records on #11194 acceptance of the unrehearsed empty-id boot (#10296 status) before the real dispatch. Anchored edits (line-anchored regex; compare the heading list before/after).
5.2 `ADR-239` Amendment 2026-10-28. `apps/web-platform/infra/git-data.tf`: rewrite the "DISABLED from the Option B merge until #11194" header comment and reword the `SOLEUR-DEBT:` marker's trigger to point at PR-2 (comment-only; rendered bytes unchanged; the marker itself is deleted by PR-2). `tests/scripts/test-git-data-wipe-wedge.sh` comment at "routes are disabled from the merge until #11194".
5.3 `scripts/encryption-posture-ledger.json` row `hcloud_volume.rehearsal`: reword `reevaluate_when` and the justification parenthetical to point at #11433; leave `expires_on` 2026-12-31; run `python3 scripts/lint-encryption-posture.py`.
5.4 `model.c4` description + `scripts/regenerate-c4-model.sh`.

### Phase 6 — PR-2 (separate worktree/branch off `main`)

6.1 `apps/web-platform/infra/git-data.tf`: `git_data_volume_id = ""`, delete the `SOLEUR-DEBT:` marker line and the "is a LITERAL (the retired plaintext volume)" comment line. Update the `git_data_volume_id` variable description in `modules/git-data-userdata/variables.tf` only if it is wrong for the empty case (a description edit is not a rendered-byte change; verify with the suites, not by assumption).
6.2 Run the infra suites that read the module call; fix only what is red.
6.3 PR-2 body: `Ref #11194`; first line "merging this PR alone changes no production resource"; the PR changes `user_data` so `hcloud_server.git_data` plans a replace at the dispatch and `scheduled-terraform-drift.yml` files a drift issue until then; the empty-id branch is unrehearsed (coverage: `git-data-bootstrap-store-verify.test.sh`, `git-data-store-device-census.test.sh`, the cloud-init empty-id guard; data risk nil because the LUKS volume is preserved, availability risk only); #10296 status; merge only after PR-1; run `plan_only` before any real dispatch; the real dispatch is tracked by the open #11194. No claim of end-to-end proof: `plan_only` stops before apply, so it does not exercise boot.
6.4 The pipeline leaves PR-2 ready with CI green (the replace job is `workflow_dispatch`-only, so merging it cannot replace the host) and merges/dispatches nothing.

### Phase 7 — Verify, review, hand off

7.1 Local: the suites, `plugins/soleur/test/c4-*.sh`, the lint scripts below; push; CI green on both PRs.
7.2 `soleur:review` (includes `user-impact-reviewer`, `security-sentinel`, `test-design-reviewer`, `observability-coverage-reviewer`); resolve findings in-branch.
7.3 Mark both PRs ready; do not merge, arm auto-merge, dispatch or write Doppler. Report both URLs.

**Owner verification path (both PR bodies and the runbook).** After PR-1 merges, run `apply_target=git-data-host-replace` with `plan_only=true` and paste the result on #11194: the plan step grades a REAL scoped plan with the plaintext-free gate and stops before any apply (the interlock is skipped under `plan_only`). After PR-2 merges, run it again before the real dispatch: now the interlock passes and the plan shows the new module wiring.

## Files to Edit (PR-1)

- `tests/scripts/lib/git-data-host-replace-gate.sh`
- `tests/scripts/lib/git-data-host-birth-gate.sh`
- `tests/scripts/lib/git-data-birth-readiness-gate.sh` (new interlock function)
- `tests/scripts/test-git-data-host-replace-gate.sh`
- `tests/scripts/test-git-data-host-birth-gate.sh`
- `tests/scripts/test-git-data-wipe-wedge.sh` (fixtures, floor and comment)
- `tests/scripts/test-git-data-birth-readiness-gate.sh` (interlock fixtures)
- `plugins/soleur/test/terraform-target-parity.test.ts`
- `.github/workflows/apply-web-platform-infra.yml`
- `scripts/test-all.sh` (run_suite comment only)
- `apps/web-platform/infra/git-data.tf` (comments only; rendered bytes unchanged)
- `scripts/encryption-posture-ledger.json`
- `knowledge-base/engineering/architecture/diagrams/model.c4`, `model.likec4.json` (generated)
- `knowledge-base/engineering/architecture/decisions/ADR-239-git-data-serves-from-luks-at-birth.md`
- `knowledge-base/engineering/operations/runbooks/git-data-birth.md`, `apply-web-platform-infra-job-rationale.md`, `git-data-luks-cutover-5274.md`
- Conditional on the Phase 4.2 grep: `tests/scripts/test-infra-privileged-tier-census.sh`, `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv`

Files to create: `knowledge-base/project/specs/feat-one-shot-11194-retire-plaintext-arms/{tasks.md,decision-challenges.md}` (this planning pass). PR-2 edits: `apps/web-platform/infra/git-data.tf` (and a variable description only if wrong).

Glob check (`git ls-files`): every path above resolved to a tracked file at plan time; `.github/CODEOWNERS` already covers both gate files (`@deruelle`).

## Guard Contract

### Guard 1 — replace gate stays fail-closed after the plaintext arms leave

**Property.** In replace and rotate mode, `git_data_host_replace_gate` passes only the exact scoped plan and refuses any positive action on the retired addresses and any destroy or rotation of the LUKS volume, passphrase or attachment outside the rotate set.

**Assembly.** The jq `def allow:` list (single chokepoint: `out_of_scope` filters on it), the positive requirement `luks_attachment_recreated`, the PASS conjunction line, the `plan_gate_assert_numeric` argument list, both mode arms, and the workflow `git_data_host_replace` `-target`/`-replace` lines that must equal the allow-set (pinned by the parity test, so a re-added target line reds there). Members are not today's address list: the retired set is the array `RETIRED_ADDRS` in the suite and each row generator quantifies over it.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `hcloud_volume_attachment.git_data` to `def allow:` | RED (the retired-address `create` row must ABORT and now passes) |
| 2 | Replace the PASS conjunction's `oos -eq 0` with true (the guard's own dispatch) | RED |
| 3 | Re-add `hcloud_volume.git_data` as a second retired member after the compliant attachment removal | RED |
| 4 | Drop the `luks_attachment_recreated` positive requirement from the PASS conjunction | RED (T12, LUKS attachment stripped) |
| 5 | Re-add `-target='hcloud_volume_attachment.git_data'` to the replace job | RED (parity retired-absent assertion) |

Harness rows: neuter `gate_mutate_and_check`'s byte-identical refusal in a copy and one PM row must go red; must-PASS non-canonical inputs: the same plan with the volumes as explicit `no-op` and a data-source `read`, and the retired-address `no-op` controls. The named backstops `luks_volume_destroyed`/`luks_passphrase_touched` are shadowed by `out_of_scope` in replace mode (equivalent mutants), so they get a behavioural row each (T3, T5) and no deletion-mutation row; in rotate mode the rotate-set requirements `lvr/lpr/lkp` have rows R3-R6. Anchor: the stored value compared here is the `def allow:` list vs the workflow targets and the constant; one diff cannot move all three consistently without the parity test seeing it, and CODEOWNERS (`@deruelle`) reviews both gate files.

### Guard 2 — birth gate stays fail-closed

**Property.** `git_data_host_birth_gate` passes only a plan creating exactly one `hcloud_server.git_data` with its two entailed members created and every presence member create-or-no-op, and refuses any positive action on the retired addresses, any LUKS volume destroy/update and any LUKS passphrase orphan mint.

**Assembly.** `_GIT_DATA_BIRTH_ALLOW`, the entailed loop, the presence loop, `volume_destroys`, `volume_updates`, `luks_orphan_mint`, `luks_passphrase_touched`, `out_of_scope`, the generic `destroys` arm; mirrored by the workflow's `git_data_host_create` `-target` list and `GIT_DATA_BIRTH_TARGET_BASES` (parity partition equation, re-added target lines red there).

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `hcloud_volume.git_data` to `_GIT_DATA_BIRTH_ALLOW` | RED |
| 2 | Empty the entailed loop (the guard's own dispatch) | RED (a plan with a missing NIC must stop passing) |
| 3 | Remove only `hcloud_volume_attachment.git_data_luks` from the entailed loop after the compliant first removal | RED |
| 4 | Widen the `volume_destroys` selector away from the LUKS volume | RED (the LUKS delete row, anchored on the arm's own "DATA VOLUME" text) |
| 5 | Re-add `-target='hcloud_volume.git_data'` to the create job | RED (parity) |

Harness rows: dropping a presence row from the fixture builder (`rest_members`) reds the anti-vacuity floor; a must-PASS plan with `no-op` presence members differs from the canonical. Anchor: parity test plus CODEOWNERS.

### Guard 3 — post-apply assert with a one-volume preserved set

**Property.** `git_data_host_post_apply_assert` refuses an unknown mode, an unreadable/unclassifiable/empty plan, a missing NIC or LUKS attachment create, and (replace) any LUKS volume delete/forget.

**Assembly.** The `case "$mode"` arm, the replace-only LUKS volume check, the NIC check, the `for att in` loop (now the LUKS attachment), the two preamble calls.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Make the replace-only volume check a no-op | RED (PM2: LUKS delete in replace passes) |
| 2 | Make the unknown-mode arm a permissive default (PM5) | RED |
| 3 | Turn the NIC create assertion into `if false` (PM3, the empty-plan guard's first member) | RED |
| 4 | Turn the attachment create assertion into `if false` (PM4, second member after a compliant first) | RED |

Harness rows: empty `resource_changes` in rotate still ABORTs on the NIC create; must-PASS: rotate with LUKS delete+create. Anchor: the pre-apply gate grades the same plan (belt and suspenders; detective, not preventive, by design). (The bash-version-dependent empty-array guard was cut: CI runs bash 5, so it could never go red.)

### Guard 4 — plaintext-id interlock

**Property.** A `git-data-host-replace`/`-rotate`/`-create` dispatch that is not `plan_only` is refused while the `module "git_data_userdata"` call in `git-data.tf` renders a non-empty `git_data_volume_id`.

**Assembly.** The function `git_data_plaintext_id_interlock`, its two workflow steps (replace job incl. rotate, create job) and their `if:` conditions, the HCL text of the module block (brace depth, comment lines, duplicate assignments); the parity test pins both steps.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture: `git_data_volume_id = "106867358"` in the module block | RED (ABORT) |
| 2 | Fixture: block missing / unparsable / zero assignments (the guard's own dispatch: an extractor that finds nothing must ABORT, not pass) | RED |
| 3 | Fixture: a commented `# git_data_volume_id = ""` above a real non-empty literal; and an empty literal followed by a second non-empty assignment | RED |
| 4 | Remove the step from the create job only (second member after a compliant replace job) | RED (parity wire pin) |
| 5 | Drop the `plan_only` exemption in the replace job | RED (parity pin; the F3 verification path would be blocked) |

Harness rows: must-PASS: `git_data_volume_id = ""` with trailing comment, with extra whitespace, and a non-empty literal in a different module block (e.g. the rehearsal-style call) that must not be read. Anchor: the file read is the checkout the plan runs on (same file the apply plans); weakening requires editing the function, both steps and the parity pin in one diff, and CODEOWNERS covers `git-data-host-*` libs.

## Observability

```yaml
liveness_signal:
  what: CI test status of the gate suites and the dispatch jobs' own destroy-guard and interlock step verdict lines
  cadence: per-PR (test-all.sh legs) and per owner dispatch
  alert_target: required GitHub check on the PR; Actions annotation on the dispatched run
  configured_in: scripts/test-all.sh (run_suite lines for the git-data gate suites) and .github/workflows/apply-web-platform-infra.yml (git_data_host_replace, git_data_host_create)
error_reporting:
  destination: GitHub Actions annotations (::error::) from the gate wrappers; no Sentry (CI-only surface, no server code)
  fail_loud: gate prints "ABORT"/"HOLD" with the counter or verdict line and exits 1 before any apply
failure_modes:
  - mode: stale retired address left in an allow-set or target list
    detection: terraform-target-parity.test.ts retired-absent assertion plus the retired-address fixture rows
    alert_route: required CI check red on the PR
  - mode: widened gate admits a LUKS destroy at dispatch
    detection: LUKS destroy/rotation fixture rows; the dispatch plan step aborts before apply
    alert_route: Actions annotation on the dispatched run; owner reads the run
  - mode: dispatch while git-data.tf still renders a deleted plaintext device
    detection: plaintext-id interlock step aborts before plan
    alert_route: Actions annotation on the dispatched run
  - mode: anti-vacuity floor lowered to match a shrunken suite
    detection: floor arithmetic in the PR body, checked by review
    alert_route: review finding (test-design-reviewer)
logs:
  where: GitHub Actions run logs for the PR checks and the dispatch
  retention: 90 days (repository default)
discoverability_test:
  command: python3 -c "print(len(__import__('re').findall(r'hcloud_volume(?:_attachment)?[.]git_data\x27', open('.github/workflows/apply-web-platform-infra.yml').read())))"
  expected_output: 0
```

## Encryption Posture

This change introduces no persistent store and no new cross-component connection; it retires gate machinery around an existing, already-declared store. The posture of the one store the retired gates guarded is restated so the review can see it did not move.

```yaml
at_rest:
  - store: hcloud_volume.git_data_luks (the serving git-data store; unchanged by this plan)
    mechanism: luks
    evidence: scripts/encryption-posture-ledger.json row hcloud_volume.git_data_luks, which cites the luksFormat/luksOpen calls and the /dev/mapper/git-data fstab line in cloud-init-git-data.yml; the gates keep luks_volume_destroyed, luks_passphrase_touched and luks_attachment_recreated as named LUKS backstops
    defends_against: a seized, RMA'd or snapshot-imaged block volume is unreadable without the Doppler-held passphrase
    does_not_defend: a leaked credential, an app-layer read on the unlocked host, exfiltration via a compromised git-data process; also, this plan does not measure what the provider retained of the deleted plaintext volume (ADR-239 Amendment 2026-10-27 claim limit)
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:no per-volume host posture probe exists yet; tracked #6897
  - store: hcloud_volume.rehearsal (rung-2 rehearsal root, plaintext mirror; row text retargeted only)
    mechanism: plaintext-exception
    evidence: scripts/encryption-posture-ledger.json row hcloud_volume.rehearsal (existing exception, expires_on 2026-12-31)
    defends_against: nothing at the volume layer
    does_not_defend: at-rest recovery of the detached rehearsal device; acceptable only because it is created empty and destroyed empty by the workflow teardown
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:no user data ever reaches a rehearsal host
in_transit:
  - connection: none added or changed (the plaintext-id interlock reads a checked-out file; the gates read a local plan JSON)
    tls: not applicable, no network connection introduced
    cert_verification: on (unchanged for every existing connection)
    does_not_defend: not applicable, nothing in transit is added; existing connections keep their ADR-220 posture
    disclosed_as: not-publicly-claimed
exception:
  - store: hcloud_volume.rehearsal
    justification: byte-for-byte mirror of the retired plaintext declaration so the rung-2 rehearsal boots what production would boot; the template arm it mirrors stays until the hash-bound removal
    tracking_issue: "#11433"
    reevaluate_when: "#11433 removes the dead plaintext arm from the cloud-init template and bootstrap, or the GIT_DATA_STORE_ENABLED cutover completes"
    expires_on: 2026-12-31
```

## Domain Review

**Domains relevant:** Engineering, Product (sign-off only), Legal (no edit)

### Engineering

**Status:** reviewed
**Assessment:** CTO ruled forks A-E and, after plan review, F1-F3 (2026-10-28): A3 split (PR-2 carries `""`); B (opening PR-2 ready is acceptable; #10296 enforcement is a tracked deferral; owner records acceptance of the unrehearsed boot before dispatch); C1; D (accept the drift issue, merge and dispatch in one sitting); E (defer the hash-bound arm to #11433); F1 plaintext-id interlock in PR-1, exempt under `plan_only`; F2 both PRs `Ref #11194`, PR-2 left ready with CI green (the replace job is dispatch-only); F3 owner-run `plan_only` dispatch as the verification path.

### Product

**Status:** reviewed (CPO sign-off, no UI)
**Assessment:** Signed off on the framing with three conditions (negative LUKS fixtures and drift-test parity; interim state documented and `Ref`-only; a verification path). All carried as ACs. No UX gate: no UI-surface file in Files to Edit.

### Legal

**Status:** reviewed (CLO consulted)
**Assessment:** No `docs/legal/**` edit, no retention/erasure claim change; the dated DPD 10.3(b) refresh (bound 2026-11-03, outer 2026-11-11) is untouched. Ruled by CLO agent, 2026-10-28: an Art. 30 register pointer-only retarget needs no CLO-owned PR when limited to the issue number as an append-only `Superseded` marker; it is moved to the PR that removes the arm (#11433), whose body says the hash-bound arm may outlast 2026-11-11 and that no legal claim depends on its removal date.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| `""` in this PR | Changes `user_data`: plans a host replace and files a drift issue at merge, against ADR-239 item 4 (CTO A) |
| Bootstrap treats a nonexistent device as absent | Hash-bound payload: invalidates rung-2 evidence, needs a paid rehearsal; weakens #10138 (CTO A) |
| Prose-only warning for the PR-1/PR-2 window | An irreversible host destroy would depend on merge timing and a runbook line (CTO F1) |
| Named tripwire counter for the retired addresses | Redundant with `out_of_scope` (CTO C) |
| Build #10296's evidence-key HOLD here | Forces a paid rehearsal before any replace: a money/priority call for the owner (CTO B) |
| Remove the dead bootstrap arm now | Hash-bound; tracked as #11433 |

## Acceptance Criteria

### Functional

- [ ] AC-1 The replace, birth, wipe-wedge and birth-readiness suites exit 0 with their anti-vacuity floors satisfied; each new floor follows Phase 4.1 (observed before/after and kept slack shown in the PR body).
- [ ] AC-2 `bun test plugins/soleur/test/terraform-target-parity.test.ts` passes; `GIT_DATA_PRESERVED_VOLUMES` is gone; neither retired address appears in any `-target`/`-replace` line of either job (asserted); both jobs carry the interlock step (asserted); entailed/presence/target counts are derived from the lists, not hard-coded.
- [ ] AC-3 The `discoverability_test.command` above prints `0` (measured pre-change at plan time: `3`); `grep -c "plaintext_attachment_recreated\|git_data_volume_destroyed" tests/scripts/lib/git-data-host-replace-gate.sh` prints `0` (pre-change `10`; `grep` exits 1 on a zero count, so assert the printed count, not the rc).
- [ ] AC-4 Retired-address rows exist for `create` and `delete` on both addresses in replace, rotate and birth, generated from one array, each pinned to its arm text and paired with a `no-op` control that PASSes.
- [ ] AC-5 LUKS negative fixtures still pass: LUKS volume delete/replace, passphrase rotation, passphrase-key update, LUKS attachment stripped each ABORT (replace); the rotate set passes only when volume + passphrase + key all move.
- [ ] AC-6 `git_data_host_post_apply_assert`: replace asserts the LUKS volume preserved, rotate asserts none; empty/garbage plans ABORT on the NIC create in both modes (PA5 rows).
- [ ] AC-7 No gate output prints `.change.before/.after` values (HK12 and PA8 sentinel rows pass, PA8 volume row re-aimed at the LUKS volume in replace mode); the interlock prints only a verdict.
- [ ] AC-8 Number words are deleted, not re-counted: `grep -nE "twenty|eighteen|seventeen|5-member|15 presence|BOTH (data )?(volumes|store attachments)"` over the touched gates, suites, parity file, `scripts/test-all.sh` comment and the two jobs' blocks returns only hits justified in the PR body (retired-address rows legitimately mention "plaintext").
- [ ] AC-9 Docs: none of the three runbooks, the `git-data.tf` header comment, `test-git-data-wipe-wedge.sh`, the workflow operator text or model.c4 says the routes are disabled or void; each states the interlock condition and the dispatch sequence; ADR-239 has Amendment 2026-10-28 appended with earlier text unedited (heading list before/after compared); the unrehearsed empty-id boot and #10296 are named in the runbook.
- [ ] AC-10 `python3 scripts/lint-encryption-posture.py` passes with the retargeted `reevaluate_when` (`expires_on` unchanged); `bash plugins/soleur/test/c4-model-freshness.test.sh` and `c4-count-parity.test.sh` pass.
- [ ] AC-11 PR-1 body says `Ref #11194` (not `Closes`), links #11433, #10296 and PR-2, opens with "merging this PR alone changes no production resource", and names the owner's `plan_only` verification step.
- [ ] AC-12 PR-2 (separate branch) contains the `git_data_volume_id = ""` edit and marker removal and nothing else except what Phase 6.1-6.2 proves necessary; body per Phase 6.3; `Ref #11194`.
- [ ] AC-13 `python3 scripts/lint-guard-contract.py` over this plan reports 4 entries and passes.
- [ ] AC-14 PR-1 changes no rendered `user_data`: `git diff origin/main...HEAD -- apps/web-platform/infra/git-data.tf` shows only comment lines (every `+`/`-` content line starts with optional whitespace and `#`).
- [ ] AC-15 The interlock function is not in `git_data_rung2_bound_files` (asserted by running the rung-2 hash gate suite unchanged) and the interlock step is skipped under `plan_only` in the replace job.

### Non-functional / constraints

- [ ] AC-16 Nothing dispatched, merged, auto-merge-armed or written to Doppler by the pipeline; both PRs end at "ready, CI green". The owner's explicit instruction overrides the `ship` default auto-merge step.
- [ ] AC-17 Review ran with `user-impact-reviewer`; every finding fixed in-branch or filed with a tracking issue.

## Test Scenarios

- Given the canonical scoped replace plan with no plaintext addresses, when the gate runs in replace and in rotate mode, then PASS.
- Given the canonical plan plus a `create` or `delete` on `hcloud_volume.git_data` or `hcloud_volume_attachment.git_data`, when any gate runs, then ABORT on the pinned arm; the same plan with the address as `no-op` PASSes.
- Given a replace plan with the LUKS volume `delete`, then ABORT; given a rotate plan with all three LUKS members moving, then PASS.
- Given `git_data_host_post_apply_assert plan rotate` on `{"resource_changes":[]}`, then ABORT naming the missing NIC create.
- Given `git-data.tf` with `git_data_volume_id = "106867358"` in the module block, when the interlock runs (not `plan_only`), then ABORT; with `= ""` it passes; a commented empty literal above a non-empty one aborts.
- Given the workflow with a retired `-target` line re-added to either job, or the interlock step removed from the create job, when the parity test runs, then RED.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6; this one is filled (threshold `single-user incident`).
- `git_data_host_post_apply_assert` is detective only (reads the saved plan after apply). Do not describe it as preventing anything.
- `plan_only` stops before apply: it proves the gate grades a real plan, not that the host boots. Do not claim end-to-end proof; the issue stays open until the real dispatch.
- The birth gate's generic `destroys` arm runs before `out_of_scope` and also lists LUKS offenders: pin each retired-address row to the arm text it must produce, or a row can go green for the wrong reason.
- `terraform-target-parity.test.ts` does not parse non-`terraform_data` targets in the reverse direction; verify the remaining `-target` addresses exist in the `.tf` files by hand (`grep -n 'resource "hcloud_volume_attachment" "git_data_luks"' apps/web-platform/infra/*.tf`).
- PR-1 must not change rendered `user_data`: do not touch `module "git_data_userdata"` arguments, the template, the bootstrap or any `file()` payload (rung-2 hash and ADR-239 item 4).
- Never `Closes #11194` in either PR; GitHub would close the issue before the host is replaced.
- The SOLEUR-DEBT marker stays in PR-1 (harvest-debt reads its trigger text, which PR-1 rewords); PR-2 deletes it.
- A bash-version-dependent guard (empty-array expansion) cannot be driven red on CI's bash 5; do not add one just to carry a mutation row.

## Dependencies & Risks

- PR-2 is only useful after PR-1 merges (the old gates would refuse the plaintext-free plan otherwise); PR-1 alone is safe because of the interlock.
- Risk: a recount error lowers an anti-vacuity floor too far (mitigated by Phase 4.1 arithmetic and generator rows).
- Risk: forgetting `model.likec4.json` regeneration reddens `c4-model-freshness` (AC-10).
- Risk: the interlock's HCL extractor is a text parser; fixtured for comments, duplicates and a missing block (Guard 4), fail-closed on any parse doubt.
- Residual: the empty-id render has never booted on a real host; availability risk only; owner accepts at dispatch (CTO B).
- Deferrals tracked: #11433 (bootstrap/cloud-init arm; also carries the Art. 30 register pointer retarget), #10296 (empty-id rehearsal; existing).
