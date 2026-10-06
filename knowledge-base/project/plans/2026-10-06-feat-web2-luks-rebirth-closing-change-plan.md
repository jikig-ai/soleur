---
title: "infra: land the closing change for the web-2 LUKS rebirth"
date: 2026-10-06
slug: web2-luks-rebirth-closing-change
branch: feat-one-shot-9372-web2-luks-closing-change
issue: 9372
type: feat
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# infra: land the closing change for the web-2 LUKS rebirth

## Enhancement Summary

**Deepened on:** 2026-10-06
**Sections enhanced:** Scope Check (conformed to the Ask Mapping / Provenance / Split schema), Observability (literal `expected_output`), Encryption Posture (added), Guard Contract (re-checked by lint), Research Insights (live verification)
**Inputs:** plan-review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow), CTO and CLO rulings, repo-research and learnings passes, offline scratch-copy measurements.

### Key improvements

1. Halt gates run mechanically: `## User-Brand Impact` valid (`single-user incident`); `## Observability` has all five fields, the probe is `bash scripts/web2-rebirth.sh flip-precondition yes` (allowlisted verb, no SSH, finishes well inside the 15 s cap) with the literal `MET`; PAT regex sweep clean; no UI surface, no network-outage trigger; `lint-guard-contract.py` green; exactly one unfenced `## Scope Check`.
2. The Scope Check now carries a Split Assessment that exceeds two thresholds (6 subsystem roots, about 1,700 lines mostly deleted) and records why a single PR is kept (the brief requires one PR; the records assert the code state beside them).
3. Live checks: #6897, #6931, #9372, #9377 are OPEN and #9481 is MERGED (`gh issue view`); the 17 non-`knowledge-base/project` paths naming `web-escrow-create` were re-counted; `origin/main` is `49d06d60a6`; the only rule ID cited, `cq-write-failing-tests-before`, exists in `AGENTS.md`; the parity baseline is 284 pass.

### New considerations discovered

- The `scheduled-followthrough-sweeper` skips a directive whose `earliest` is in the future and, at window close, only comments on an open tracker, so the real expiry enforcement stays with `lint-encryption-posture.py`; the pre-set date is advisory, not a second gate.
- Merging fires a live push-apply (both workflows `active`); the drift run cited in AC10b is the read-only evidence that state already holds both web-class pair entries.
- The ledger-flip blockers (linter binding regex, secret-pair co-location, shared web-1 row) were verified on a scratch copy; none required a repository change to find.

## Overview

The rebirth workflow for the live web-2 standby (`web2-luks-rebirth.yml`, #9372) is merged and inert. Its first applying
dispatch is blocked by a flip precondition that only a separate change can satisfy: retire the single-use escrow-create
workflow with every coupled artifact, and make the rotation halt count a `create` of the web-class passphrase pair. This plan
covers that change, the records that move with it, and the follow-through directive date. It runs nothing: no dispatch (plan-only
or real), no apply, no secret write, no token mint, no Hetzner write. Each of those needs a separate approval from the owner.

Four items were asked. Three are planned as asked. The fourth, flipping the `hcloud_volume.workspaces` ledger row and the
Article 30 / compliance-posture sentences, is **deliberately not in this PR**: it would assert LUKS for a volume that is still
ext4, the approved parent plan and runbook place it after the graded reboot proof, the legal review rules against it, and the
repository's own encryption-posture linter fails the flip today (measured below). It is recorded as a User-Challenge in
`knowledge-base/project/specs/feat-one-shot-9372-web2-luks-closing-change/decision-challenges.md` so the owner can overrule it,
and the prerequisites that make the later flip possible are filed as tracked work.

## Research Insights

**Premise validation (Phase 0.6).** #9372 is OPEN with no closing PR; #6931 is OPEN. `origin/main` is at `49d06d60a6` and the
branch is one empty init commit ahead of it. Every file named by the brief and by the 2026-10-04 retirement checklist comment on
#9372 exists on `main` (`git grep -l 'web-escrow-create'` returns 17 non-archive paths, enumerated under Files). The rebirth
workflow and its suites are present and green. The proposed mechanisms were checked against the ADR corpus: ADR-263 (D9 and the
2026-10-05 addendum) already records "single-use, retires with #9372" for the escrow-create workflow, so nothing here is a
rejected alternative. Stale or contradicted premises found:

- The brief and the 2026-10-04 checklist (item 7) say the census count goes "back to 3". Measured: the main-root census is 5
  today (`apply-web-platform-infra`, `apply-deploy-pipeline-fix`, `scheduled-terraform-drift`, escrow-create, rebirth); this change
  makes it 4. It reaches 3 only when the rebirth workflow itself retires. The rebirth runbook's closing row 5 says "census 5 to 4"
  and is therefore also stale after this change (it becomes 4 to 3).
- The runbook's "Before the first dispatch" item 2 says both push-apply workflows are paused. Measured today: both report `active`.
  This diff touches `apps/web-platform/infra/**` and `.github/workflows/apply-web-platform-infra.yml`, so merging it fires a routine
  push-apply with no Terraform diff. It does not touch `*.tf` or any `apply-deploy-pipeline-fix` trigger file.
- Brief item 3 (ledger flip now) contradicts the parent plan ("After the apply"), the runbook closing row 2 and the CPO/CLO
  conditions ("no cell says LUKS-backed at boot before the graded reboot proof").

**Measured offline, in a scratch copy of the tree (no repository file changed, nothing contacted).**

- Counting `create` only at the web-class pair via a new address list makes `luks_passphrase_rotations` read 2 over
  `tests/scripts/fixtures/web-host-rebirth/passphrase-create.json`, and `bash scripts/web2-rebirth.sh flip-precondition yes`
  then prints `flip precondition: MET` once the escrow-create workflow file is absent.
- That narrow flip breaks exactly four rows of `tests/scripts/test-destroy-guard-counter-web-platform.sh` (T64d, T64e, T64j,
  T64m). Counting `create` at all six addresses instead breaks six (it also reds T60d and T60h, the inngest first-create rows).
- With the escrow-create files removed and the narrow flip applied, `test-web-host-rebirth-gate.sh` (80 assertions),
  `scripts/web2-rebirth.test.sh` (120 world scenarios) and `web2-luks-rebirth-workflow.test.sh` (84 assertions) stay green.
- Baseline `bun test test/terraform-target-parity.test.ts` (run from `plugins/soleur`) is 284 pass, 0 fail.
- A ledger copy with `hcloud_volume.workspaces` set to `luks` fails `python3 scripts/lint-encryption-posture.py`: `attachment_binds_volume`
  requires the literal `volume_id = hcloud_volume.workspaces.id` but `server.tf` has `hcloud_volume.workspaces[each.key].id`, and
  `file_has_secret_pair` requires a `random_password` + `doppler_secret` pair in the attachment's file (`server.tf` has none; the
  web-class pair is in `workspaces-luks-header-web.tf`). The ledger row's own evidence text says #9372 splits the row per host
  "before any flip" because the same row covers web-1's superseded plaintext backstop.

**Rulings carried into this plan (2026-10-06).** CTO: scope B (create counted at the web-class pair only, matched through
`luks_passphrase_base` so a for_each-indexed rebirth address also counts; keep the counter name), no other jq-filter consumer is
affected, rewrite the HALT text, rewrite (not just delete) the runbook Step 0a, and the ledger flip is blocked on a linter change
plus a per-host row split. CLO: leave the ledger row, `exception` block and the Article 30 / compliance-posture sentences untouched
(they are already event-conditional and carry no stale date); a pre-dispatch retirement moves nothing in Article 30; the
2026-10-15 decision date stands and the owner may extend the exception citing #6931. Parent-plan rulings (CPO APPROVE-WITH-CONDITIONS,
CLO no blocker with conditions, CTO) are unchanged and apply.

**Institutional learnings applied.** A retirement must sweep the mechanism that produces each registration, not only the files
(`2026-09-19` generated-artifact learnings); a guard's header names what its test must assert (`2026-07-22`); `destroy_count`-only
guards are blind to non-delete verbs, so the HALT is graded on all counters (`2026-07-03`); closed-set follow-through paths must be
exercised through the real sweeper entry, not a mock (`2026-10-05`); a suite that never executes a step proves nothing
(`2026-10-04`). The CTO and agent research cited several speculative targets (a CODEOWNERS entry, a ledger "escrow milestone" field);
all were checked and do not exist.

**Property List (Phase 0.6b).**

1. P1 — the apply path of `web2-luks-rebirth.yml` can proceed once this change is on `main` (`flip-precondition` reads met) and
   not before it.
2. P2 — after the flip, a plan that CREATES `random_password.workspaces_luks_web` or `doppler_secret.workspaces_luks_web_key`
   (a lost state entry would overwrite the live passphrase) halts the per-merge apply, non-ackably, in any index/module spelling.
3. P3 — nothing that retired is still referenced: no workflow, suite, registration, parity constant, C4 clause or runbook step
   names `apply-web-escrow-create` as a live thing, and every removal is mirrored in the guards that enumerate it.
4. P4 — no record claims web-2 is encrypted, rebuilt or that the rebirth ran; the ledger, Article 30 and compliance-posture are
   byte-unchanged until the graded reboot proof.
5. P5 — the #6931 follow-through directive carries a date consistent with the 2026-10-15 decision date and the 2026-10-22
   exception expiry, edited only after merge.
6. P6 — the later ledger flip is unblocked: its prerequisites are written down and tracked.

**Cut List.**

| Mechanism | Property | What already covers it, or why cut |
|---|---|---|
| Counting `create` at all six HALT addresses | P2 | Issue #9372 names "those two addresses"; the inngest first-create has its own recut route; widening reds T60d/T60h for no stated need. Filed as a follow-up instead |
| Flipping the ledger row, floor 2 to 3, and Article 30 / compliance-posture sentences in this PR | (asked) | Would be a false attestation today; blocked by the linter; CLO ruling. Deferred with a User-Challenge record and tracked prerequisites |
| Extending the exception's `expires_on` in the ledger | P4 | An owner decision on the 2026-10-15 decision date, citing #6931; not asked, not authorized here |
| A `.tf` edit (the stale CONSUMERS comment on `DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER`; the `workspaces-luks-header-web.tf` comment that says the HALT "lets a first create through", which this change makes false for the web-class pair) | none | A `.tf` edit touches the push-apply path filter (and `server.tf`-class files wake the pipeline-fix apply). Both comments are recorded as known-stale in runbook row 5 and corrected in the later retirement change |
| Retiring the rebirth workflow, its gate and suites | none | They are needed for the dispatch; runbook row 5 retires them after use |
| A new linter capability for for_each-indexed bindings | P6 | A security-gate redesign (ADR-140); filed as a prerequisite, not built here |

## Research Reconciliation — Spec vs. Codebase

| Brief / checklist claim | Reality (measured) | Plan response |
|---|---|---|
| Flip the ledger row to `luks`, `live_verification: available`, floor 2 to 3, update Article 30 sentences, in this PR | Parent plan, runbook row 2 and CLO say after the graded reboot proof; linter fails the flip; row covers web-1's plaintext backstop | Not done; User-Challenge recorded; prerequisites filed; AC asserts the ledger, Article 30 and compliance-posture are unchanged |
| Census count "back to 3" (checklist item 7) | Census is 5 now, 4 after this change, 3 after the rebirth workflow retires | Set the count to 4; fix the runbook row 5 wording to "4 to 3" |
| "Update `earliest=` to the plan's value for the decision date" | The plan states a formula (rebirth + 3 days) and no literal; the live directive on #6931 reads `earliest=2026-10-26T00:00:00Z`, which is after the exception expires (2026-10-22) | `earliest=2026-10-18T00:00:00Z` = decision date 2026-10-15 + 3 days; the window then closes 2026-10-22 (earliest + 4 days), the expiry date. The directive lives only in the issue body, so the repo change is the script header comment and the edit happens after merge |
| `scripts/web-escrow-create-names*` helper(s) | Exactly one file, `scripts/web-escrow-create-names.sh` | Delete it |
| Both push-apply workflows paused (runbook item 2) | Both `active` | Merge fires a routine push-apply (no Terraform diff). Sharp Edge: the owner pauses both and waits for idle before any dispatch |
| Step 0a "delete" (checklist item 9) | Step 0a also carries still-valid content: the R2 credential mint dependency, the live-preflight gate, the push-apply enable window, the "no creation route now" fact | Rewrite into Step 0 (CTO ruling); list what was re-homed in the PR body |
| Issue comment: counts `create` "at those two addresses" | The filter counts six addresses for update/delete/forget | New web-class-only list for the create arm |

## Open Code-Review Overlap

None. (Checked: `gh issue list --label code-review --state open` bodies searched for each path under Files; no match.)

## Files to Delete

- `.github/workflows/apply-web-escrow-create.yml`
- `apps/web-platform/infra/web-escrow-create-workflow.test.sh`
- `scripts/web-escrow-create-names.sh`

## Files to Edit

Anchors are content anchors, not line numbers.

| File | Edit |
|---|---|
| `tests/scripts/lib/destroy-guard-filter-web-platform.jq` | Add `def luks_passphrase_create_halt_addrs` (`random_password.workspaces_luks_web`, `doppler_secret.workspaces_luks_web_key`). In `luks_passphrase_rotations` add an arm: `create` in the verb set AND the base address (via `luks_passphrase_base`) is in that list. Rewrite the comments that call a first create legal (the block above `undecidable_entries` and the in-counter comment); name the two scopes (create halts at the web-class pair; stays legal at the other four, and why) |
| `tests/scripts/test-destroy-guard-counter-web-platform.sh` | Tests first. T64d becomes a must-HALT (web-class first-create fixture reads `2:1`). T64e and T64j: create expected 1 at the two web-class addresses (and their index/module spellings) and 0 at the other four. T64m: first-create now exits 1, and the baseline plan still falls through. T64g and T60i: drop the vacuous `first create` token (it also occurs in an untouched HALT line) and require distinctive tokens from the first emission only (`CREATE` and a phrase unique to the retired-route sentence); keep the T60i anchor `LUKS passphrase resource(s) (inngest or workspaces` and add `CREATE` to its verb loop. `_wl_shape_check` takes the create-want from a test-side literal `WL_CREATE_HALT` list of the two web-class addresses (never from the filter, or mutations 2 and 3 are vacuous); `_luks_addrs` (derived) stays for the T64g grep only. Reword the stale comments and the T64m title ("falls through on a first create"). Keep T60d (inngest first-create stays legal). Add rows per Guard 1 |
| `.github/workflows/apply-web-platform-infra.yml` | HALT block only: first `::error::` line names CREATE for the two web-class addresses; replace the sentence "For a not-yet-formatted web-class volume the first create is the only legal verb" (now false) with the CTO-approved sentence naming the retired route AND the recovery route for a lost pair entry: a reviewed import of the existing entry into state, merged with the kill-switch line, never a re-create. Net about +400 bytes of 5,119 headroom; `workflow-file-size.test.ts` must stay green. No other line |
| `plugins/soleur/test/terraform-target-parity.test.ts` | Remove the `apply-web-escrow-create.yml` entry and its comment from `MAIN_ROOT_TF_WORKFLOWS`; reword the rebirth entry's comment; `expect(found.length).toBe(5)` becomes 4. Remove `EXEMPT_PAIR_WORKFLOW` and its doc comment; in the "NO other workflow FILE" row drop the exemption (rename the test, drop the "exempt file must exist" assertion and the `f !== EXEMPT_PAIR_WORKFLOW` filter); delete the row "the exempt workflow file reaches the pair only in the create-only shape" and any helper left unused by it |
| `scripts/guard-vacuity-floor.test.sh` | Remove the `web-escrow-create-workflow.test.sh` paragraph and its alternative in the last `PROMOTED_FILES` regex |
| `apps/web-platform/infra/run-registered-suites.sh` | Remove the `#9377` comment paragraph and the `web-escrow-create-workflow.test.sh=900` bound |
| `apps/web-platform/infra/suite-durations.tsv`, `apps/web-platform/infra/suite-shard-legs.tsv` | Remove the suite's row in each (prefer `scripts/regenerate-shard-manifest.py --group infra --incremental --write` over hand edits; the `# n=` leg count stays unchanged; `.github/scripts/test/test-infra-suite-registration.sh` and `test-infra-suite-registration-mutations.sh` validate the result) |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | `doppler -> hetzner` edge: replace the clause "and apply-web-escrow-create.yml (#9481) plans no changes against them" with a retirement clause (no workflow creates them now). Regenerate `model.likec4.json` with `plugins/soleur/scripts/render-c4-model.sh` via `scripts/regenerate-c4-model.sh` (never hand-edit) |
| `knowledge-base/engineering/architecture/decisions/ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md` | Append ONE superseded/retirement blockquote after the D9 "First-create legality ends" paragraph, in the existing `> **Superseded DATE (#N), in part:**` style and conditioned on merge ("from the merge of this PR"): the line "A first create ... is legal under `luks_passphrase_rotations`" is superseded for the web-class pair; the escrow-create workflow is retired. The rebirth addendum's own retirement paragraph stays true and is not edited. Status stays `adopting`; the rebirth is not claimed |
| `knowledge-base/engineering/operations/runbooks/web-host-birth.md`, `web-host-replace.md` | Delete the "Step 0a" subsection and the inline "Step 0a" references (outcome-table rows, the NOTE paragraph, the replace Step 0 prose). Re-home into Step 0 only what is not specific to the retired workflow: the live preflight must print `escrow-split-contract:live-ok` before any host dispatch; the R2 credential mint stays tracked on #9377; the push-apply enable window; the sentence that losing the passphrase pair or escrow bucket has no automated creation route and needs a reviewed change. List what was re-homed in the PR body |
| `knowledge-base/engineering/operations/runbooks/web2-luks-rebirth-9372.md` | "Before the first dispatch": item 1 gets a landed marker (conditioned on merge) plus the verification command; item 2 gets the order and commands (wait for the merge-fired push-apply on the merge SHA to finish green with "No changes", then `gh workflow disable` both, then dispatch; after re-enable, name how skipped diffs are applied). Closing row 2: record the prerequisites (per-host row split, linter binding change) and that it stays after the proof. Row 4: note the pre-set date, the go/no-go (dispatch by 2026-10-15 so the soak fits the window that closes 2026-10-22; a later dispatch re-sets `earliest` as a mandatory step of that dispatch, or the exception is extended). Row 5: census "4 to 3", the `web2-rebirth.test.sh` rows this change adds, and the two known-stale `.tf` comments. Row 6: reword the criterion to "dispatched and provisioned with proof pending, or extended citing #6931" (the ledger flip cannot be in review before the proof, which cannot pass before about 2026-10-18), and name who prepares the extension (the engineer, by 2026-10-14) |
| `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md` | Dated marker on the "`create` stays legal" sentence in the widened-HALT section |
| `scripts/followthroughs/web2-luks-live-6931.sh` | Header enrollment comment only: document the pre-set `earliest=2026-10-18T00:00:00Z` and that #9372 re-sets it from the actual rebirth time. No behavior change |
| `scripts/web2-rebirth.sh` | Strings only: the header comment line and the `NOT met` failure text describe a regression after this change ("the escrow-create workflow file is present again, or the rotation HALT no longer counts a create of the web-class pair"); keep the `flip precondition NOT met` prefix the suite greps, and keep the absent-file check itself. If `web2-luks-rebirth-workflow.test.sh` asserts the step name in `web2-luks-rebirth.yml`, leave that name alone |
| `scripts/web2-rebirth.test.sh` | One added row: run `flip-precondition yes` against the REAL repository tree (real jq filter, real fixture, real file system) and require `MET`. Rename the stale flip_case rows ("create exempt today") and add a sandbox flip_case `real absent` that reads MET. Existing stubbed rows stay |

Not edited (checked): `tests/scripts/fixtures/web-host-rebirth/passphrase-create.json`, `.github/workflows/web2-luks-rebirth.yml` (its flip step name keeps naming the retired workflow, allowlisted below), `knowledge-base/legal/**` (the `2026-10-counsel-review-9377.md`
audit stays as a historical record), `scripts/encryption-posture-ledger.json`, every `*.tf`.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9372-web2-luks-closing-change/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-9372-web2-luks-closing-change/decision-challenges.md` (the ledger-flip User-Challenge)

## Implementation Phases

Tests first (`cq-write-failing-tests-before`): Phase 1 reds the suite before the filter changes.

**Phase 1 — flip rows, RED.** Edit the five destroy-guard rows and add the Guard 1 rows; run
`bash tests/scripts/test-destroy-guard-counter-web-platform.sh` and confirm the new rows are RED on the unmodified filter.

**Phase 2 — the filter and the HALT text.** Edit the jq (new list, new arm, comments). Edit the apply HALT block. Re-run the suite
green; run `plugins/soleur/test/workflow-file-size.test.ts`.

**Phase 3 — retirement.** Delete the three files; edit the registrations (suite bounds, both TSVs, vacuity-floor), the parity
test; run the parity test and `bash scripts/guard-vacuity-floor.test.sh`.

**Phase 4 — records.** C4 clause + regenerate JSON (then `c4-model-freshness`, `c4-count-parity`, `c4-canonical`), ADR-263
markers, three runbooks plus the rationale marker, the follow-through script header, `decision-challenges.md`.

**Phase 5 — real-tree flip row.** Add the two `web2-rebirth.test.sh` rows; run the rebirth suites.

**Phase 6 — straggler sweep and gates.** `git grep -n 'apply-web-escrow-create\|web-escrow-create'` outside
`knowledge-base/project/{plans,learnings,specs}` and the legal audit returns only the dated retirement markers; run the full set
under Acceptance Criteria; `lint-guard-contract.py`; `lint-infra-no-human-steps.py` on this plan; markdown lint.

**Phase 7 — tracking issue (before PR ready).** File one issue: the ledger-flip prerequisites (per-host split of the
`hcloud_volume.workspaces` row, `lint-encryption-posture.py` accepting `[each.key]` bindings and a sibling-file secret pair,
Article 30 / compliance-posture supersession, floor 2 to 3), blocked-by the graded reboot proof, with a checklist line to widen the
`create` HALT to the remaining four passphrase addresses once their creation routes are retired. Milestone from `knowledge-base/product/roadmap.md`.

**Post-merge (agent-executable, stated in the PR body).** Confirm the push-apply run on the merge SHA is green and its plan read "No changes"; then re-read #6931's body, replace only the `earliest=` value on the single
`soleur:followthrough` directive with `2026-10-18T00:00:00Z` (assert exactly one directive and one match), `gh issue edit 6931
--body-file`, then verify by re-reading. Comment on #9372 with the retirement status, the deferred item 3 and the filed issues.
`Ref #9372`, never `Closes`.

## Guard Contract

### Guard 1 — the rotation HALT counts a create of the web-class passphrase pair

**Property.** After this change a plan that creates `random_password.workspaces_luks_web` or `doppler_secret.workspaces_luks_web_key`
makes `luks_passphrase_rotations` non-zero, in every index and module-prefix spelling, so the per-merge apply halts with no
`[ack-destroy]` path, while a `create` at the other four listed addresses and a `no-op` at all six still score zero.

**Assembly.** One counter in `tests/scripts/lib/destroy-guard-filter-web-platform.jq` (`luks_passphrase_rotations`), reached by three
consumers: the per-merge `apply` job HALT in `.github/workflows/apply-web-platform-infra.yml` (reads the counter by name and prints the
operator text), `scripts/web2-rebirth.sh flip-precondition` (reads it over the tracked fixture), and the destroy-guard suite. One new
address list (`luks_passphrase_create_halt_addrs`) and one new verb arm; both flow through `luks_passphrase_base`, the single
normalizer. The per-shape rows enumerate the SIX base addresses (derived from `luks_passphrase_addrs`), but the expected create-want comes from a
test-side literal list of the two web-class addresses, never from the filter, so emptying or truncating the filter's list reds a row.
The HALT text assertions (T60i, T64g) read the first emitted `::error::` line, comment-stripped. Retirement fallout rides the same
guard set: the parity test's census row (`found` equals the list minus `infra-validation.yml`, count 4) and its "NO other workflow FILE"
row (now with no exemption; directory-derived, so a new workflow file is in scope) are the existing guards for "nothing else reaches the
pair"; removing `EXEMPT_PAIR_WORKFLOW` is covered by mutation rows 8 and 9 below.

**Mutation matrix:**

| # | Mutation (on a sandbox copy) | Expected |
|---|---|---|
| 1 | Delete the new `create` arm from the counter | RED: T64d (first-create must halt), T64e, the real-tree flip row |
| 2 | Empty `luks_passphrase_create_halt_addrs` (the guard's own dispatch reports zero checked) | RED: T64e per-address row; the real-tree flip row reads 0 not 2 |
| 3 | Drop `doppler_secret.workspaces_luks_web_key` from the list after the first member (a second member after a compliant first) | RED: the per-address row for that address |
| 4 | Make the arm match the raw `.address` instead of `luks_passphrase_base` | RED: T64j (indexed and module-prefixed spellings of a create) |
| 5 | Widen the arm to all six addresses | RED: the must-stay-legal rows (T60d inngest first-create; web-1 pair create reads 0) |
| 6 | Reorder: evaluate the new arm only when the verb set is exactly `["create"]` (a `create` plus `delete`, or `create` plus `update`, form) | RED: the `["create","delete"]` and `["delete","create"]` shape rows still need 1 |
| 7 | Revert the HALT text to the old "first create is the only legal verb" sentence | RED: T64g / T60i (CREATE and the retired-route sentence are required) |
| 8 | Add a new workflow file that `-target`s `random_password.workspaces_luks_web` (a second member after the compliant files) | RED: the parity "NO other workflow FILE" row |
| 9 | Restore the census count to 5, or re-add `apply-web-escrow-create.yml` to `MAIN_ROOT_TF_WORKFLOWS` | RED: `found.length` / the version-parity read of a missing file |

**Harness rows.** (a) Edit the suite, not the guard: change the web-class first-create fixture's actions from `["create"]` to
`["no-op"]` and require T64d to RED (a must-HALT row that passes on a no-op is vacuous); (b) must-PASS inputs that are not the
canonical: a plan with `["create"]` at `random_password.inngest_redis_luks` and at `random_password.workspaces_luks` reads 0 (the
documented narrower scope), and a `["no-op"]` at both web-class addresses reads 0; (c) an anti-vacuity floor: the destroy-guard
suite's own assertion floor (currently 105) is raised by the number of rows added, so a suite that silently skips them REDs.

**Anchor.** The list is a stored set compared against the plan, but it is not a hash: the weakening that would pass is deleting the
arm and the rows in one diff. The outside anchor is the real-tree flip row in `web2-rebirth.test.sh` plus `flip-precondition`
itself, which runs the real filter against the tracked fixture on every dispatch, and the parity row that pins the apply job as the
only job allowed to reach the pair. Set identity, not a count: rows enumerate the two named addresses.

## Architecture Decision (ADR/C4)

### ADR

No new decision: ADR-263 already decides "single-use, retires with #9372". This change **amends ADR-263** (dated markers, a
deliverable of this plan, not a follow-up): the D9 statement that a first create of the web-class pair is legal under the HALT is
superseded for that pair as of this change; the escrow-create workflow's retirement is recorded; the rebirth addendum's retirement
paragraph notes that the flip precondition can now read met. Conditional wording throughout; status stays `adopting`; the
rebirth is not claimed as having run.

### C4 views

All three of `model.c4`, `views.c4`, `spec.c4` were read. Enumerated for this change: (a) external human actors: none added or
changed (the owner and agents already modeled); (b) external systems: Doppler, Hetzner, Cloudflare R2, GitHub, Better Stack, all
already modeled; no vendor added; (c) data stores: the escrow bucket and the Doppler config are named in the existing
`doppler -> hetzner` and `hetzner -> cloudflare` edges, unchanged; (d) actor/surface access relationships: unchanged. The one
falsified element is the `doppler -> hetzner` edge description, whose clause says the retired workflow "plans no changes against"
the escrow resources; it is rewritten (Container view prose only, no element, tag or `view include` change). `views.c4` and
`spec.c4` contain no reference. Counts embedded in edge prose are guarded by `c4-count-parity`: the escrow-create workflow uses no
Sentry heartbeat and is not among the counted slugs, so no count moves; verified by running `plugins/soleur/test/c4-count-parity.test.sh`.
After editing, regenerate `model.likec4.json` and run `c4-model-freshness`, `c4-canonical`, and the web-platform c4 tests.

### Sequencing

All in this PR. The ADR records the target state with the rebirth pending.

## Observability

```yaml
liveness_signal:
  what: the per-merge apply job's LUKS HALT annotation (`::error::terraform plan would UPDATE, DELETE or FORGET ... CREATE`) on a plan that creates a web-class passphrase address; and the `flip precondition:` line of every rebirth dispatch
  cadence: every push-apply run (per merge to main touching apps/web-platform/infra/**) and every rebirth dispatch
  alert_target: layer 6 (workflow run log `::error::` annotation) and the `notify-apply-failure` ops email from the existing `apply-web-platform-infra` failure routing; there is no Sentry event or issue for a HALT
  configured_in: .github/workflows/apply-web-platform-infra.yml (apply job HALT) and scripts/web2-rebirth.sh (flip-precondition)
error_reporting:
  destination: GitHub Actions run annotations and workflow run log (layer 6) plus the `notify-apply-failure` ops email; the standing signal after a skipped merge is the `scheduled-terraform-drift` Sentry monitor check-in and its action-required issue
  fail_loud: yes, `exit 1` before the destroy_count sum, not reachable by `[ack-destroy]`
failure_modes:
  - mode: a create of the web-class pair is planned after the flip (state lost an entry)
    detection: `::error::terraform plan would CREATE ...` annotation in the apply workflow run log (layer 6), luks_passphrase_rotations >= 1
    alert_route: layer 6 `::error::` plus the `notify-apply-failure` ops email on the first red merge; `[skip-web-platform-apply]` makes later merges skip silently, so the persistence detector is the `scheduled-terraform-drift` Sentry monitor and its action-required issue
  - mode: the flip is reverted or neutered
    detection: `::error::flip precondition NOT met` in the workflow run log (layer 6) on an apply dispatch (a plan_only dispatch prints a `PENDING` line at rc 0), and the destroy-guard suite and real-tree row RED in CI
    alert_route: CI RED on the PR (the required check); an apply dispatch refuses before any write
  - mode: the arm over-counts and wedges routine merges
    detection: `::error::terraform plan would CREATE ...` fires on a plan with no web-class passphrase create (workflow run log, layer 6); the suite's must-PASS rows RED first
    alert_route: layer 6 `::error::` plus the `notify-apply-failure` ops email; `[skip-web-platform-apply]` unwedge
logs:
  where: GitHub Actions run log and step summary
  retention: Actions default
discoverability_test:
  command: bash scripts/web2-rebirth.sh flip-precondition yes
  expected_output: MET
```

## Encryption Posture

This change introduces no persistent store and no connection; it is recorded because the plan names the web-2 volume and its
passphrase. Nothing about the store changes.

```yaml
at_rest:
  - store: hcloud_volume.workspaces["web-2"]
    mechanism: plaintext-exception (unchanged: the live volume is ext4 and empty until the rebirth dispatch, then luks guest-side per ADR-263)
    evidence: scripts/encryption-posture-ledger.json, the hcloud_volume.workspaces row (left byte-unchanged by this change)
    defends_against: nothing at the volume layer today
    does_not_defend: a seized or snapshot-imaged disk exposes any data resident on the volume (web-2 holds none); a leaked passphrase held in Doppler and Terraform state
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:until the post-proof ledger flip (tracked in the issue filed by this change)
in_transit:
  - connection: none added or changed
    tls: not applicable to this change (no connection is introduced)
    cert_verification: on (unchanged)
    does_not_defend: not applicable to this change
    disclosed_as: not-publicly-claimed
exception:
  justification: the live web-2 volume is ext4 and empty; the existing ledger exception stands unchanged
  tracking_issue: "#6897"
  reevaluate_when: the rebirth completes and the post-proof ledger flip lands, or 2026-10-22 arrives first
  expires_on: 2026-10-22
```

## User-Brand Impact

**If this lands broken, the user experiences:** nothing visible directly, because web-2 serves no traffic and holds no user data. The failure modes are an over-counting HALT that wedges routine merges (a stuck deploy for every user until the unwedge) or a flip that is silently inert, which leaves a lost state entry free to overwrite the live web-class passphrase so that a later, data-bearing web-2 cannot open its volume.

**If this leaks, the user's workspace data is exposed via:** no new exposure vector. The change removes a creation path for the passphrase and escrow resources; it reads no secret value (the retired reader used names only) and writes none. The ledger and legal records are deliberately not made to over-claim encryption, so a seized-disk exposure is not misdescribed.

**Brand-survival threshold:** single-user incident

(Carried forward from the 2026-10-05 parent plan, CPO APPROVE-WITH-CONDITIONS; its conditions about not over-claiming "LUKS-backed at boot" are the reason item 3 is deferred. `soleur:engineering:review:user-impact-reviewer` runs at review time.)

## Domain Review

**Domains relevant:** engineering, legal, operations

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Scope B for the jq flip; HALT text and tests re-baselined; no other consumer of the filter is affected; runbook Step 0a rewritten rather than deleted; ledger flip blocked on a linter change and a per-host row split (confirmed by measurement).

### Legal (CLO)

**Status:** reviewed
**Assessment:** Leave the ledger row, the exception block and Article 30 / compliance-posture untouched pre-dispatch; nothing in them moves with a retirement change; the decision date 2026-10-15 stands; the post-proof flip splits the row per host first. Draft material for the owner's veto, not legal advice. The ship-time Counsel-Review gate does not fire (no `knowledge-base/legal/**` edit).

### Operations (COO)

**Status:** reviewed (carried from CTO assessment; runbook-only edits)
**Assessment:** Three runbooks and one rationale marker change; no vendor, cost or account change. The merge fires a routine push-apply (both workflows active today); the owner pauses both and waits for idle before any dispatch.

No Product/UX surface: no new user-facing file, no UI path in Files to Edit.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Retire `.github/workflows/apply-web-escrow-create.yml`: delete it plus its test (`apps/web-platform/infra/web-escrow-create-workflow.test.sh`), `scripts/web-escrow-create-names*` helper(s), and every reference the plan lists (central MAIN_ROOT_TF_WORKFLOWS list, runbooks `web-host-birth.md` / `web-host-replace.md` Step 0a, ADR-263, model.c4 edge text, tests that require the workflow to exist)" [brief] | Files to Delete (3); Files to Edit rows for the parity test, vacuity floor, suite bounds, both TSVs, `model.c4`, ADR-263, both runbooks; Phases 3 and 4 | mapped |
| 2 | "Flip the rotation HALT `create` exemption in `tests/scripts/lib/destroy-guard-filter-web-platform.jq` so the rebirth workflow's `flip-precondition` step reads \"met\"; keep its tests and fixtures green" [brief] | Files to Edit rows for the jq, the destroy-guard suite, the apply HALT text; Phases 1 and 2; Guard 1 | mapped |
| 3 | "Flip the `hcloud_volume.workspaces` ledger row to `luks` with `live_verification: available` and `live_coverage_floor` 2 -> 3, and update the Article 30 / compliance-posture sentences ONLY where the plan says they move with this change (do not claim the rebirth happened; it has not been dispatched)" [brief] | Not implemented; `decision-challenges.md`; tracking issue; runbook row 2 | descoped — justification: the parent plan, the runbook and the CLO place the flip after the graded reboot proof, it would assert LUKS for a volume that is still ext4, and `lint-encryption-posture.py` fails it today; recorded as a User-Challenge for the owner to overrule. Article 30 / compliance-posture: the plan says none of those sentences move with this change |
| 4 | "Update the follow-through directive on issue #6931 (`scripts/followthroughs/web2-luks-live-6931.sh`, `earliest=`) to the plan's value for the decision date 2026-10-15 (exception expires 2026-10-22); edit the issue body only after the PR merges, and say so in the PR" [brief] | Files to Edit row for the script header; Post-merge step; AC12 | mapped |
| 5 | "Run the relevant infra test suites (web2-luks-rebirth-workflow.test.sh, the destroy-guard filter tests, followthrough tests) and the full ship gates" [brief] | Acceptance Criteria AC3 to AC6, AC10b | mapped |
| 6 | "do NOT dispatch `web2-luks-rebirth.yml` (plan_only or real), do NOT write Doppler secrets, do NOT mint tokens, do NOT run any Terraform apply or Hetzner write" [brief] | Overview; AC9 | mapped |
| 7 | "Use `Ref #9372` in the PR body, not `Closes`" [brief] | AC10; Post-merge step | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Delete the workflow, its suite and `scripts/web-escrow-create-names.sh` | "delete it plus its test (`apps/web-platform/infra/web-escrow-create-workflow.test.sh`), `scripts/web-escrow-create-names*` helper(s)" | asked |
| `terraform-target-parity.test.ts`, `guard-vacuity-floor.test.sh`, `run-registered-suites.sh`, both TSVs | "central MAIN_ROOT_TF_WORKFLOWS list ... tests that require the workflow to exist" (asks 1) | asked |
| `model.c4` clause and regenerated `model.likec4.json` | "model.c4 edge text" | asked |
| ADR-263 superseded blockquote | "ADR-263" | asked |
| `web-host-birth.md` and `web-host-replace.md` Step 0a removal and Step 0 re-homing | "runbooks `web-host-birth.md` / `web-host-replace.md` Step 0a" | asked |
| jq arm, `luks_passphrase_create_halt_addrs`, destroy-guard rows | "Flip the rotation HALT `create` exemption" | asked |
| Apply-workflow HALT text | "keep its tests and fixtures green" (the HALT text is asserted by T60i and T64g and would otherwise be false) | inferred — justification: the old sentence ("the first create is the only legal verb") becomes false and two suite rows pin the wording; leaving it misleads whoever hits the HALT |
| Real-tree `flip-precondition` row and renamed stale rows in `web2-rebirth.test.sh`; `web2-rebirth.sh` message strings | "so the rebirth workflow's `flip-precondition` step reads \"met\"" | inferred — justification: the existing rows stub the filter, so nothing proves the real tree reads MET; the failure text would otherwise tell a dispatcher to do what is already done |
| `web2-luks-live-6931.sh` header comment, post-merge issue edit | "Update the follow-through directive on issue #6931 ... `earliest=`" | asked |
| Runbook `web2-luks-rebirth-9372.md` rows (items 1 and 2, rows 2, 4, 5, 6) | the runbook's "Before the first dispatch" item 1 and "Closing checklist" (the brief's own citation of the runbook) | inferred — justification: the runbook is the dispatcher's checklist; after this change its item 1 is true, row 5's census count is wrong, and row 6's criterion cannot be met |
| Rationale-runbook dated marker | "every reference the plan lists" | inferred — justification: it states that a `create` stays legal, which this change makes false for the web-class pair |
| `decision-challenges.md` and the one tracking issue | "do not claim the rebirth happened; it has not been dispatched" | inferred — justification: the deferral of ask 3 must reach the owner and carry its prerequisites, per the deferral-tracking rule |
| `tasks.md` | — | inferred — justification: pipeline contract consumed by the work phase |

### Split Assessment

- Subsystems touched: 6 — `.github`, `apps/web-platform`, `plugins/soleur`, `scripts`, `tests`, `knowledge-base`
- Planned files: 26 (3 deleted, 21 edited, 2 specs created) | Estimated changed lines: about 1,700, most of them deleted lines (the retired workflow 402, its suite 819, the names reader 54)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — the seam would be code and guards (jq, tests, parity, registrations) versus records (ADR, C4, runbooks); declined, single PR kept: the brief requires "one PR", the records assert the code state they sit beside, and splitting would leave a window in which the parity census, the registrations or the runbooks name a deleted workflow

## Acceptance Criteria

### Pre-merge

- [ ] AC1 — The three files are deleted; `git grep -n 'apply-web-escrow-create\|web-escrow-create'` outside `knowledge-base/project/{plans,learnings,specs}` returns only this allowlist, each on purpose: the dated retirement marker in ADR-263 and its older D9 text, the rebirth runbook, the `model.c4` clause and its generated `model.likec4.json`, `scripts/web2-rebirth.sh` (the absent-file check and its message), `scripts/web2-rebirth.test.sh`, `.github/workflows/web2-luks-rebirth.yml` (flip step name) and `knowledge-base/legal/audits/2026-10-counsel-review-9377.md`. `git grep -n 'Step 0a' -- knowledge-base/engineering/operations/runbooks/web-host-birth.md knowledge-base/engineering/operations/runbooks/web-host-replace.md` returns nothing.
- [ ] AC2 — `jq -f tests/scripts/lib/destroy-guard-filter-web-platform.jq < tests/scripts/fixtures/web-host-rebirth/passphrase-create.json | jq .luks_passphrase_rotations` prints `2`, and `bash scripts/web2-rebirth.sh flip-precondition yes` prints `flip precondition: MET` (run with `GITHUB_OUTPUT` unset).
- [ ] AC3 — `bash tests/scripts/test-destroy-guard-counter-web-platform.sh` is green with the re-baselined rows, T60d (inngest first-create) still green, and the assertion floor raised by the rows added.
- [ ] AC4 — `bash tests/scripts/test-web-host-rebirth-gate.sh`, `bash scripts/web2-rebirth.test.sh`, `bash apps/web-platform/infra/web2-luks-rebirth-workflow.test.sh` and `bash scripts/followthroughs/web2-luks-live-6931.test.sh` are green.
- [ ] AC5 — From `plugins/soleur`: `bun test test/terraform-target-parity.test.ts test/workflow-file-size.test.ts test/stock-preflight-coverage.test.ts` is green; the census asserts 4.
- [ ] AC6 — `bash .github/scripts/test/test-infra-suite-registration.sh`, `bash .github/scripts/test/test-infra-suite-registration-mutations.sh`, `bash scripts/guard-vacuity-floor.test.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`, `bash plugins/soleur/test/c4-model-freshness.test.sh`, `bash scripts/check-adr-ordinals.sh`, `python3 scripts/lint-guard-contract.py` and `python3 scripts/lint-encryption-posture.py` pass.
- [ ] AC7 — `git diff origin/main -- scripts/encryption-posture-ledger.json knowledge-base/legal/` is empty (the deferral is real, not silent).
- [ ] AC8 — `git diff --name-only origin/main...HEAD` lists no `*.tf` and none of the `apply-deploy-pipeline-fix.yml` trigger files.
- [ ] AC9 — The diff contains no workflow dispatch, no Terraform apply, no Doppler secret write and no token mint (review of commands run and of every script added).
- [ ] AC10 — `decision-challenges.md` records the ledger-flip User-Challenge and the PR body LEADS with it (the owner's overrule channel); the one tracking issue exists with a milestone; the PR body says the #6931 directive is edited after merge, uses `Ref #9372`, lists what was re-homed from Step 0a, and contains no line that is exactly the push-apply kill-switch token (its matcher is line-anchored).
- [ ] AC10b — The most recent `scheduled-terraform-drift` run on `main` is cited in the PR body with a green conclusion (read-only evidence that state holds both web-class pair entries, so the new arm does not fire on the merge-fired apply).
- [ ] AC11 — No sentence in any edited file says web-2 is LUKS-backed, reborn or encrypted in the past or present tense (grep the diff for `LUKS-backed`, `reborn`, `has been converted`).

### Post-merge

- [ ] AC12a — The push-apply run on the merge SHA is green and its plan reads "No changes"; only then are both push-apply workflows paused for any dispatch (owner's separate approval).
- [ ] AC12 — The `earliest=` value on #6931's single `soleur:followthrough` directive reads `2026-10-18T00:00:00Z` (`gh issue view 6931 --json body --jq .body | grep -F 'earliest=2026-10-18T00:00:00Z'`), the label `follow-through` is still present, and the rest of the body is byte-identical.

## Test Scenarios

1. Given the web-class first-create fixture, when the filter runs, then `luks_passphrase_rotations` is 2 and the apply HALT exits 1.
2. Given `["create"]` at `random_password.inngest_redis_luks`, when the filter runs, then 0 (still legal).
3. Given `["create"]` at `random_password.workspaces_luks_web["web-2"]`, when the filter runs, then 1.
4. Given the escrow-create workflow file present in a sandbox, when `flip-precondition yes` runs, then `NOT met`; absent, then `MET`.
5. Given a new workflow file that `-target`s the pair, when the parity suite runs, then RED.
6. Given the retired suite's name in `PROMOTED_FILES`, when `guard-vacuity-floor.test.sh` runs, then RED (a stale entry is not silently tolerated).

## Dependencies & Risks

- **Merge fires a push-apply.** Both push-apply workflows are `active`; the diff touches their path filters. No Terraform diff is expected (no `*.tf`), so the plan should read "No changes". If it does not, treat that as a finding, not noise. The rebirth runbook's "pause both and wait for idle" still precedes any dispatch.
- **Byte budget.** `apply-web-platform-infra.yml` is 484,881 bytes against a 490,000 gate; the HALT edit adds about 300.
- **The create arm is web-class only.** The other four addresses keep a legal first create (inngest recut route; web-1 pair already created, no flow found). Widening is filed, not done.
- **Pre-set `earliest`.** With `2026-10-18` the follow-through goes RED at 2026-10-22 if no rebirth soak is evidenced. That is intended (it coincides with the exception expiry); if the owner extends the exception instead, the directive is re-set (runbook row 4).
- **Deferral risk.** The exception on `hcloud_volume.workspaces` still expires 2026-10-22. The decision date 2026-10-15 is the owner's: dispatch has run and the post-proof flip is in review, or the exception is extended citing #6931. Nothing in this PR extends it.
- **A late rebirth cannot fit the window.** The soak needs a readiness row at least 3 days old and the window closes 2026-10-22, so a dispatch after about 2026-10-15 reports FAIL on a rebirth that is merely late. The runbook carries the go/no-go and makes the `earliest` re-set (or an exception extension) a mandatory step of any later dispatch.
- **No creation route after the flip.** The HALT now blocks a web-class create with no acknowledgement path and the creation workflow is gone; the recovery for a lost pair entry is a reviewed import of the existing entry into state, stated in the HALT text and runbook Step 0.
- **Cross-session:** none known; no sibling worktree is read or touched.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty, `TBD` or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `single-user incident`.
- Do not edit `scripts/encryption-posture-ledger.json` in this PR: a `luks` row for `hcloud_volume.workspaces` fails the linter today and would be false for the live ext4 volume and web-1's backstop.
- Do not hand-edit `model.likec4.json`; regenerate. The freshness gate compares bytes to a pinned `likec4@1.50.0` render (npx downloads it on first use).
- Removing `EXEMPT_PAIR_WORKFLOW` can leave `stripShellLineComments`/`readdirSync` imports or helpers unused; remove only what the deleted row alone used, then run the parity suite.
- The suite floors: raise the destroy-guard assertion floor by exactly the rows added; a floor lower than the real count passes a suite that skipped rows.
- `cmd_flip_precondition` keeps its absent-file check on purpose: it is what stops a restored escrow workflow from being dispatched past the flip.
- Edit the #6931 issue body only after the PR merges (hard instruction). Do it as a read-modify-write that asserts one directive and one match; never paste the whole body from memory.
- `apply-deploy-pipeline-fix.yml` runs the same jq filter but reads only other counters (`host_creates`, `reboot_updates`, `non_terraform_data_deletes`), so the new arm cannot affect it; say so in the PR body.
- Run `lint-infra-no-human-steps.py` on this plan and on every runbook edit: do not pair a human actor with an infrastructure verb in new prose.

## Review-Phase Amendments (2026-10-06)

Recorded by the review phase; the sections above stay as the dated plan. Where they conflict, this section wins.

1. **Create arm narrowed to the passphrase alone** (CTO re-ruling, new evidence). Only a create of `random_password.workspaces_luks_web`
   counts; a create of `doppler_secret.workspaces_luks_web_key` alone restores the same state-held value and stays legal (a missing
   copy is itself an incident, and the HALT left no route that applies the repair). AC2 therefore reads `1`, not `2`; the flip
   precondition runs over `passphrase-create-password-only.json` and requires exactly 1; the must-stay-legal rows cover five addresses.
2. **Recovery wording retracted.** "A reviewed import of the existing entry" is not a verified route: two review seats measured in a
   local-state sandbox (random provider 3.9.0/3.9.1) that the import plans `special = true -> false`, a forced replacement. The HALT text,
   ADR-263 marker and runbooks now say there is no documented or verified automated recovery and the owner decides. The follow-up
   measurement is a checkbox on #9572.
3. **Scope of "no workflow creates them"** is the passphrase pair only; the push-apply still creates the escrow config, bucket and name
   secrets, and a create there is not halted.
4. **Floors** are exact: destroy-guard 107, `web2-rebirth.test.sh` 123 scenarios.
