---
title: "chore(registry): stop describing the LUKS store volume as plaintext, and add its NFR at-rest row"
type: chore
date: 2026-09-22
slug: chore-registry-luks-plaintext-doc-sweep
branch: feat-one-shot-8535-registry-plaintext-sweep
issue: 8535
closes: 8535
pr: 8568
priority: p3-low
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# Registry store volume: correct stale "plaintext / recut unfired" claims and add the NFR at-rest row

## Enhancement Summary

**Deepened on:** 2026-09-22. This was a proportionate pass for a correction sweep: halts, attribution checks and mechanical verify passes, without the full 40-agent fan-out. The operator scoped this as "not a feature", and plan-review already ran a 4-agent panel.

1. **Halt gates.**
   - 4.6 User-Brand Impact: pass. The threshold is `none`, with a scope-out line for the sensitive `apps/*/infra/` and `.github/workflows/` paths.
   - 4.7 Observability: restored the full 5-field block, which the plan-review cut had reduced below the schema. The failure-mode detection now uses AC4(a) instead of the push apply, which cannot observe registry resources.
   - 4.10 Encryption Posture: restored the `at_rest` fields. Triggered by the `.tf` edit.
   - 4.8 PAT: no match. 4.9 UI: no UI surface. 4.11 Guard: no guard deliverable. 4.5 and 4.55: not triggered, because the `.tf` edit is comment-only and no resource is replaced.
2. **Attribution verified on `origin/main`.**
   - The restore-leg fix is PR #7430 (`4aef468c80`, 2026-08-10T23:27:34Z), now cited instead of "#7287's closing comment".
   - PR #8423 is `1817308001`. PR #8456 is `69b08a4ee5`, and it touches `cloud-init-registry.yml`, the ledger and the recut runbook.
   - All cited rule ids are active in AGENTS.md.
3. **The pre-dispatch check in D7 is grounded in the runbook's existing triage schema.** Arm A is `store_luks` plus `luks_open_arm=`. Arm B is `store_escrow=`, whose values `fail_passphrase` and `fail_header` were verified in the triage tables. That avoids inventing field values.
4. **Verify-the-negative pass.** Checked the plan's negative claims:
   - "no test pins the edited strings": confirmed by `git grep`.
   - "no file links to the old anchor": confirmed once the plan itself is excluded.
   - "push apply cannot touch the registry": confirmed by the `OPERATOR_APPLIED_EXCLUSIONS` block and the registry `-target`s living only inside `registry-*` dispatch jobs.

## Overview

The zot registry's store volume (`hcloud_volume.registry`) has been guest-side LUKS since the recut on
2026-08-10, and the encryption-posture ledger already records it as live-verified. Seven repo files still
describe that volume in the present tense as plaintext, or describe the recut as not yet run, and the NFR
register has no at-rest row for it. This plan corrects those files and adds the register row.

This is a correction sweep: prose, comments and emitted text only, plus one register row and one
ledger prose refresh. **No gate logic, no Terraform expression, no probe control flow changes.**

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Reality (measured 2026-09-22 on `origin/main` @ `816aebbd21`, branch 0 behind) | Plan response |
|---|---|---|
| Item 7 has one stale phrase (the `volume_provisioned=0` `::error::` line) | Two more registry-plaintext claims sit in the same file: the `apply_target` dispatch **description** (the text a non-technical operator reads in the dropdown label) says `registry-host-replace` "preserves the volume and darks the registry", and the `registry_luks_recut` step comment says replacing the host alone "preserves the plaintext volume and hits the blkid FATAL". | Fold both in. The Acceptance grep runs over the whole file, so they would fail it anyway. |
| Item 1 lists 5 phrases | The same runbook's inventory section also says a host replace "is the unfired-recut fatal (#7287) this runbook exists inside". The issue's second grep (`never been fired\|recut is UNFIRED\|…`) does not match `unfired-recut`. | Fold in; widen the plan's AC grep to include `unfired`. |
| Item 3 has 1 phrase (header) | The same workflow's `ZERO TERRAFORM (AC6)` block also says an untargeted apply would carry a pending replace "into the unfired-recut fatal (#7287)". | Fold in, past tense. |
| Item 2 has 5 phrases | Its header also cites the ledger as recording `live_verification: "unavailable:no zot-host at-rest posture probe yet"`. The ledger reads `available` since PR #8423 (merged 2026-09-21). | Correct in place with the others. |
| Item 8: add a row "sourced from the ledger row" whose evidence carries the delivered launch gate + escrow re-test | The ledger row itself still says the launch gate "reaches the host only on the next replace", says the escrow re-test is pending, and says #8417's broken `store_probe_rc` "cannot be decoded until the next registry-host replace delivers the fix". That replace happened 2026-09-22T00:30:15Z (run 35672138112); #8417 is CLOSED; #8408's delivery comment records `store_escrow=ok` at 00:50:02Z. | Refresh those clauses in the ledger row in the same PR, so the register row can be sourced from it without the two disagreeing. See Decision D2. |
| Item 4 edit "`registry_rationale_strip` renders byte-identical" | The stale lines are **HCL comments** inside `resource "hcloud_server" "registry"`, above `user_data =`. They are not part of the `templatefile()` argument, so they never enter the rendered payload at all. `registry_rationale_strip` strips `#` lines from the *cloud-init template's* output. | The operator's render `cmp` still runs, but it is weak on its own. `registry-userdata-budget.sh` renders `cloud-init-registry.yml` through a synthetic root and never parses the edited lines. AC4(a) adds the load-bearing proof: the diff is empty after stripping comments. |
| Not listed by the issue | `plugins/soleur/test/terraform-target-parity.test.ts` doc comment on the `registry-luks-recut` describe block: "Replacing the host alone preserves the still-plaintext store volume …". | Fold in (one comment, zero behaviour). It is a registry current-state claim of the same class, found by the repo-wide sweep. |

Premise validation: #8535 OPEN. #7287 CLOSED 2026-08-12. #7340 CLOSED. #6929 CLOSED. #8417 CLOSED. #7377 OPEN (it holds the live re-enrolment checkbox for the blocker probe). #8408 OPEN (enrolled, awaiting the 8386 probe's V7 human read). #8386 OPEN. PR #8456 MERGED 2026-09-22T00:21Z. PR #8423 MERGED 2026-09-21. The recut run 31437037877 (dispatched 2026-08-10T22:08:43Z; the `registry_luks_recut` job ran 22:15:33Z → 22:18:26Z) shows `registry_luks_recut: success` and `registry_store_restore: failure` (overall `failure`, disclosed in ADR-184 and on #7287). Post-recut `registry_host_replace` runs: 31639782781 (2026-08-12), 35489418603 (2026-09-20, boot `b3ec6c3b`), 35672138112 (2026-09-22, 00:29:06Z → 00:30:54Z, boot `5639cc07`), all with the store volume preserved. Every file cited exists on `origin/main`.

## Research Insights

**Relevant paths (anchors, verified on `origin/main`).**

- Ledger row: `scripts/encryption-posture-ledger.json` → `.stores[] | select(.store=="hcloud_volume.registry")` (currently `stores[8]`). Lint: `scripts/lint-encryption-posture.py --repo-sweep`, which reads only the ledger and the Terraform/templates, never the seven prose files. Baseline: `19 stores, 10 connections, 0 unledgered, 0 failing checks -> PASS`.
- Register: `knowledge-base/engineering/architecture/nfr-register.md` `### NFR-027: Encryption At-Rest`. It has 4 rows. The `Compute` row is the LUKS precedent to mirror in shape.
- User_data render: `zot-registry.tf` `locals { registry_rationale_strip = … }` and `user_data = base64gzip(replace(templatefile("${path.module}/cloud-init-registry.yml", {…}), local.registry_rationale_strip, ""))`. There is **no** `ignore_changes = [user_data]`. Baseline render: raw 171,413 B, stripped 52,847 B, stored 18,024 B, cap 32,768 B.
- Push-apply scope: `apply-web-platform-infra.yml` is `on.push.paths: apps/web-platform/infra/**`, `-target`-scoped. The registry is under the `OPERATOR_APPLIED_EXCLUSIONS (CTO ruling 2026-07-06)` block.
- Byte gate: `plugins/soleur/test/workflow-file-size.test.ts` (490,000). The file is currently 482,443 B.
- Tests touching edited files: `tests/scripts/test-registry-luks-recut-gate.sh` (baseline `37 passed, 0 failed`) sources the gate library. `plugins/soleur/test/terraform-target-parity.test.ts` reads the workflow job block, and its doc comment is edited. No test pins the edited `::error::`, dispatch-description or PASS-`echo` strings: `git grep` found no hit for `still-plaintext device and FATAL`, `darks the registry` or `plaintext ext4 volume` outside the files being edited.
- The blocker probe has no test and no live directive. Its only consumers are ADR-172 (prose), a learning, and `scripts/lint-shell-trace-credential-refusal.baseline.txt`, which lists the path only, so a line change does not move it.

**Institutional learnings applied.**

- `knowledge-base/project/learnings/2026-06-02-verify-terraform-target-set-not-header-prose.md`: header prose drifts, and machine-readable state is the authority. That is why D2 refreshes the ledger (the authority) before the register copies from it.
- `knowledge-base/project/learnings/2026-02-14-sed-insertion-fails-silently-on-missing-pattern.md`: do each edit with an exact-match tool (the Edit tool, or a Python `replace` guarded by `count == 1`), never a bulk `sed`. Re-run the AC1–AC3 greps afterwards.
- `knowledge-base/project/learnings/2026-06-02-test-class-assertion-sweep-must-use-bare-token-not-bracketed.md` and `2026-02-22-model-id-update-patterns.md`: sweep greps need variant spellings. That is why AC1 adds `unfired`, `zero live executions`, `blocked today` and `PROVISIONING EVENT`, and AC2 covers both `still-plaintext` and `still plaintext`.
- Plan sharp-edges applied: a diff-scope AC lists pipeline-written files (AC9). A correction plan needs provenance for *added* claims, not only absence greps (AC9). An infra diff answers "does merging this alone mutate production" (Sharp Edges). `discoverability_test.command` stays free of shell metacharacters.

**Scoped advisor consult (plan Step 4.5).** Two changes, both applied:
- (1) The render `cmp` is not proof on its own. That became AC4(a), the comment-stripped diff.
- (2) The inverted host-replace advice must be conditional and must explain the failed restore leg. That became D4's added paragraph.

**CLAUDE.md / AGENTS.md conventions.** `cq-cite-content-anchor-not-line-number` (new prose cites anchors). `hr-always-read-a-file-before-editing-it`. `hr-never-git-add-a-in-user-repo-agents` (stage exact paths).

**Premise validation.** The paragraph after the reconciliation table covers it. Every cited issue, PR and run was probed with `gh`. None of the premises is stale. One is incomplete: the ledger still said the #8408/#8417 work was pending (Decision D2).

**Property list (Phase 0.6b).**

- P1: No file in the repo's live (non-archive, non-dated-record) surfaces states in the present tense that `hcloud_volume.registry` is plaintext, or that the recut has not run.
- P2: The operator guidance those sentences justified (`registry-host-replace` darks the registry) is replaced by guidance true for a LUKS volume.
- P3: Emitted runtime text (`::error::`, the dispatch label, the probe PASS `echo`) states the current posture.
- P4: The NFR register carries a `hcloud_volume.registry` at-rest row that agrees with the ledger.
- P5: No behaviour changes. That covers rendered `user_data`, gate predicates, probe exit contract, and workflow size under the gate.

**Cut list.** Nothing proposed by the ask was cut. The issue names no new mechanism, only corrections. Considered and not adopted:
- Re-anchoring the blocker probe on `store_luks`. That is P2-adjacent, and #7377 owns it.
- A new lint to forbid "still-plaintext" prose. Nothing in P1–P5 needs a standing guard. The existing encryption-posture lint and the AC greps cover this change.

## Decisions

- **D1. History is written as history, not deleted.** Every stale sentence is rewritten into dated past tense ("until the 2026-08-10 recut …") with the run id. The operator guidance it justified is inverted where it is now wrong. Rewriting the sentence to a new present-tense claim with no date would repeat the defect the next time the state changes. The exception is the dated `## Addendum — 2026-08-06` in the recut runbook: addenda are append-only, so it gets an inline bracketed annotation, per the issue.
- **D2. The ledger row is refreshed, narrowly.** The issue says to source the register row from the ledger. The ledger row says three things are pending that have since been delivered. Only those clauses change: the `does_not_defend` "until a registry replace delivers …" clauses, the `evidence` #8417 sentence, and `retrieved_on` → `2026-09-22`. `mechanism`, `defends_against`, `disclosed_as` and `live_verification` stay as they are. `does_not_defend` stays non-empty and concrete (leaked credential, app-layer read on the unlocked host, compromised zot process), because `lint-encryption-posture.py` requires that. The honesty note that `store_luks=yes` means "sits on LUKS", not "can still unlock", stays. The escrow re-test now covers the unlock half daily, and the note says so.
- **D3. The blocker probe's logic is untouched.** Operator constraint: item 2 is corrected in place, not annotated. That applies to its prose and its `echo` text. Swapping its issue-state proxy onto the live `store_luks` signal is #7377's open checkbox and is out of scope here. The header says so, so a reader does not mistake the proxy for the measurement.
- **D4 (superseded in part by D7). The recut/host-replace distinction stays.** It is still true: a host replace preserves the volume, so it cannot *perform a recut*. What changes is the reason given, the callout ("this reverses", now "this has reversed"), and the lapsed "both levers are unavailable" note. That note becomes dated history. The replacement wording follows D6/D7 (mechanism in the decision section, a pre-dispatch check, dated history in one block).
- **D6. Emitted text and dispatch-visible labels carry mechanism, not posture** (CTO review). The `apply_target` dropdown, the `::error::` line and the runbook's decision section state what stays true whatever the volume's state: a host replace *keeps* the volume, so it cannot re-encrypt or empty the store; a recut replaces it. They do not assert "the volume is LUKS". That would be false again the moment the refuse arm fires (`not_luks` / `fail_header` route to a recut), and every state change would need this sweep again. Current posture lives in one place, the ledger row, and the NFR row copies it. Dated history (the 2026-08-10 recut, the failed restore leg, "both levers unavailable 2026-08-04 → 2026-08-10") goes into one dated block in the runbook, linked once from the decision section.
- **D7. The runbook's decision heading is renamed** (CTO review). `## Do NOT use registry-host-replace for this` becomes `## registry-host-replace cannot perform a recut (it is the boot-problem lever)`. Headings are what gets read first during an outage. No file links to the old anchor (`git grep -n -i 'do-not-use-registry' -- ':!knowledge-base/project/plans'` returns 0 hits). The section links to `registry-host-replace-dispatch.md`. It also gains one **pre-dispatch** check: read the newest `SOLEUR_ZOT_DISK` row (the query the triage section already gives); if `store_luks` is not `yes` (Arm A, `luks_open_arm=` names why) or `store_escrow=` is `fail_passphrase`/`fail_header` (Arm B), stop and use the `registry_store_not_luks` triage table (its `fail_passphrase` row already forbids a host restart or replace). This supersedes D4's post-replace-only wording.
- **D5. Byte budget.** `apply-web-platform-infra.yml` is 482,443 B; the edits are rewordings of similar length. The gate is `plugins/soleur/test/workflow-file-size.test.ts` (490,000 B); re-measure with `wc -c` and record the figure in the PR body.

## Files to Edit

1. `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md`
   - `## Do NOT use registry-host-replace for this`: replace "The volume is currently unencrypted, and the new boot code refuses to mount an unencrypted volume — by design, so it can never silently wipe your data. The result is that the registry **goes dark** and stays dark." with: host-replace keeps the volume, so it cannot recut. The volume has been LUKS since the recut of 2026-08-10 (run 31437037877), so a replace takes the boot code's reuse arm. The boot code **still** refuses any volume that is neither blank nor LUKS, by design, so it can never silently wipe data (keep that statement verbatim in substance). Before the recut that refusal is what darked the registry.
   - Callout: "After a successful recut this reverses" becomes "This reversed on 2026-08-10". Cite the green post-recut replaces 35489418603 (2026-09-20) and 35672138112 (2026-09-22), store preserved, `store_luks=yes` on the new boot. "applies only while the volume is still unencrypted" becomes past tense. The "**Until then, `registry-host-replace` is blocked too** (verified 2026-08-04 …)" paragraph is re-labelled as history (2026-08-04 → 2026-08-10), keeping its run link. The #7278 pointer stays. Per D6/D7: rename the heading, state mechanism, add the pre-dispatch check and the `registry-host-replace-dispatch.md` link, and move the dated material (the 2026-08-04 blocked-lever note, the 2026-08-10 recut run and its failed `registry_store_restore` leg, a doppler-token defect fixed by PR #7430, merged 2026-08-10T23:27:34Z (commit `4aef468c80`)) into one `> **History (dated)**` block.
   - `## If it stops` → "It refused the volume": "(It is **not** available before one: while the volume is still plaintext, that dispatch aborts `out_of_scope=2`)" becomes past tense: it was not available before the first recut.
   - Inventory section: "which is the unfired-recut fatal (#7287) this runbook exists inside" becomes past tense, dated.
   - `## Addendum — 2026-08-06`: **annotate only**. Append after "…hits the `blkid` FATAL refuse." an inline `*[Annotated 2026-09-22, #8535: the circularity is broken — the recut fired 2026-08-10 and the volume is LUKS, so a replace now reopens it.]*`. The sentence itself is not rewritten.
   - `## Before the FIRST-EVER fire: cold-vehicle re-verification (REQUIRED)`: add one dated line under the heading: "First fired 2026-08-10 (run 31437037877); this section is the checklist for a future recut." The "shipped with zero live executions" sentences stay (true of the ship event).
   - Addendum 2026-08-06: the annotation also covers the surrounding "blocked today by a circularity" sentence and the #7278 bullet's "BLOCKED ON A PROVISIONING EVENT" framing (one annotation line after the paragraph, one after the bullet). The text itself is not rewritten.
   - **Leave alone:** "onto an unencrypted path would pass the gate." (sentinel launch gate) and the `not_luks` triage row ("The store is plaintext or blank"). Both are conditional arms added by PR #8456.
2. `scripts/followthroughs/registry-luks-blocker-6929.sh`: **correct in place, no annotation blocks.**
   - Lines 2–3 purpose line: "are blocked until the LUKS recut blocker lands" becomes "were blocked until the LUKS recut landed. It landed 2026-08-10 (run 31437037877); #7287 and this probe's tracker #7340 are both CLOSED."
   - `WHAT THIS EXISTS TO STOP` paragraph: "a replace performed BEFORE the LUKS recut has been applied opens `/dev/mapper/registry` against a still-plaintext ext4 volume" becomes the past-tense "…opened … against the then-plaintext ext4 volume".
   - Anchor block: "The recut has never been fired (the runbook says so verbatim: …), so the volume is plausibly still plaintext and a replace is plausibly still fatal" becomes "At authoring the recut had never been fired … It fired 2026-08-10 (run 31437037877)." "#7287 tracks firing it and is open." becomes "#7287 tracked firing it; it closed 2026-08-12."
   - Proxy paragraph: "scripts/encryption-posture-ledger.json records as `live_verification: "unavailable:no zot-host at-rest posture probe yet"`" becomes: the direct signal now exists (`scripts/followthroughs/registry-luks-live-8386.sh` grades `SOLEUR_ZOT_DISK` `store_luks=yes`; the ledger row reads `available` since PR #8423). Moving this probe onto that signal is #7377's open checkbox. Until then this file remains an issue-state proxy.
   - `WHAT THIS EXISTS TO STOP` paragraph's "#7278 / ADR-172 records three actions as BLOCKED ON A PROVISIONING EVENT" becomes "recorded" (past tense). The PASS output that lists them for re-evaluation stays.
   - PASS `echo` (runtime output): "replace no longer opens /dev/mapper/registry against a plaintext ext4 volume." becomes "replace reopens the LUKS store volume (cloud-init's reuse arm) instead of refusing it." Keep the six-space indent and the following "VERIFY BEFORE ACTING" lines.
   - **Keep:** "\"the plaintext-volume blocker is gone\" and closing #7340" (the hypothetical fail-open text) and the quote of #6895's title.
   - `DEP_ISSUE`, the exit contract, the `gh` calls and every other `echo` stay unchanged.
3. `.github/workflows/registry-zot-inventory.yml` (comments only)
   - Header: "which today opens /dev/mapper/registry against a still-plaintext ext4 volume (the LUKS recut is UNFIRED — #7287). This workflow is the entire set of useful work on the near side of that deadlock" becomes past tense: until the 2026-08-10 recut, that replace opened … a plaintext ext4 volume (#7287, closed). This workflow *was* the useful work on the near side of that deadlock. It stays the read-only measurement lever.
   - `ZERO TERRAFORM (AC6)`: "already carries a PENDING REPLACE in state … into the unfired-recut fatal (#7287)" is dated "at authoring (pre-recut)".
4. `apps/web-platform/infra/zot-registry.tf`: an HCL comment only, inside `resource "hcloud_server" "registry"` above `user_data =`.
   - "It does NOT make the replace safe: the live volume is still plaintext ext4, so a fresh host boots into cloud-init-registry.yml's `refusing-non-luks-device` FATAL and comes up dark. That is #6929's recut." becomes: before the 2026-08-10 recut (#6929) a fresh host also hit `refusing-non-luks-device` against the then-plaintext volume. The volume is LUKS now, so that arm no longer fires, but the stock risk above is unchanged. Keep "Improving the odds of one step is not authorization."
   - **Verification (operator constraint, pre-merge):** `bash apps/web-platform/infra/registry-userdata-budget.sh <scratch>/before.yml` on the pre-edit tree, the same to `after.yml` post-edit, then `cmp before.yml after.yml` must exit 0. Also record `sha256sum` of both. Also run `terraform fmt -check apps/web-platform/infra/zot-registry.tf`. Baseline measured at plan time: stripped 52,847 B, stored 18,024 B.
   - Leave line ~655 ("a populated plaintext ext4 the registry-host-replace preserve-path kept") alone: it describes the refuse arm's trigger, a conditional.
5. `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md` (`## registry_luks_recut`)
   - "The live volume is still PLAINTEXT ext4, i.e. in that third arm." becomes: it was plaintext ext4 (the third arm) until this job's first fire on 2026-08-10 (run 31437037877). It is crypto_LUKS now (the reuse arm).
   - "So `registry-host-replace` MUST NOT be used for this: it PRESERVES the volume, so the replaced host boots against the still-plaintext device, refuses it, and DARKS THE REGISTRY." becomes: `registry-host-replace` cannot *perform a recut*, because it PRESERVES the volume. Before 2026-08-10 the preserved device was plaintext, and the replaced host refused it and darked the registry. Today it reopens the LUKS volume, which makes host-replace the right lever for an ordinary boot problem and still the wrong one for a recut. "Forgetting the `-replace` on the volume does the same" becomes "…is likewise not a recut".
6. `tests/scripts/lib/registry-luks-recut-gate.sh`: the header comment (lines ~11–22) only, with the same two corrections as item 5. **No jq, no counter, no function body changes.** The interior comments that name the "registry-host-replace footgun" (PRESERVE-STORE arm, `volume_provisioned` counter) describe *what a recut plan must not look like* and stay.
7. `.github/workflows/apply-web-platform-infra.yml`
   - `apply_target` `description:` (≈L260–261): "do NOT use registry-host-replace for that — it preserves the volume and darks the registry." becomes "registry-host-replace keeps the volume, so it cannot recut (it is the boot-problem lever; see registry-host-replace-dispatch.md)." Keep it in the folded `>-` scalar, at similar length.
   - `registry_luks_recut` step comment (≈L3516–3518): "replacing the host alone preserves the plaintext volume and hits the blkid FATAL" becomes "…preserves the volume, which is a host replace, not a recut".
   - Destroy-guard abort `::error::` (≈L3587): "That is the registry-host-replace footgun: the host would boot cloud-init against the still-plaintext device and FATAL." becomes "A plan that keeps the volume is a host replace: it cannot re-encrypt or empty the store." (D6: mechanism only) Keep "Re-dispatch with all three -replace flags (…)" unchanged.
   - Leave every inngest/workspaces/git-data `plaintext` hit alone (other volumes; #6897/#6894 own them).
   - `wc -c` after: ≤ 482,700 B target, < 490,000 B hard.
8. `knowledge-base/engineering/architecture/nfr-register.md` (`### NFR-027: Encryption At-Rest`)
   - Add a row after `Compute`: `| Container Registry (zot) store volume | Implemented | LUKS (cryptsetup) | … |`. Evidence is sourced field by field from the ledger row `stores[] | select(.store=="hcloud_volume.registry")`:
     - the mechanism: guest-side luks2 on the raw `hcloud_volume.registry`, mapper `/dev/mapper/registry` mounted at `/var/lib/zot`, key `random_password.registry_luks` + `doppler_secret.registry_luks_key`, apparatus in `cloud-init-registry.yml` (content anchors, not line numbers)
     - the recut: 2026-08-10, run 31437037877 (`registry_luks_recut` job completed 22:18:26Z)
     - live verification: `available` (PR #8423), via `SOLEUR_ZOT_DISK` `store_luks=yes` graded by `scripts/followthroughs/registry-luks-live-8386.sh`, first on boot `b3ec6c3b` (2026-09-20)
     - PR #8456 delivered on boot `5639cc07` (replace 2026-09-22T00:30:15Z, run 35672138112): the fail-closed zot launch gate (the LUKS-filesystem sentinel mount), the daily escrow re-test (`store_escrow=ok` first observed 00:50:02Z), and the `registry_store_not_luks` standing alert
     - `does_not_defend` in brief (leaked credential, app-layer read on the unlocked host, compromised zot)
     - disclosed: not-publicly-claimed
   - Update the `**System-Level Status:**` line from "3 of 4 rows Implemented — Supabase PostgreSQL, Agent Runtime, Compute" to "4 of 5 rows Implemented — …, Container Registry (zot) store volume".
9. `scripts/encryption-posture-ledger.json`: the `hcloud_volume.registry` row, prose fields only (Decision D2)
   - `at_rest.does_not_defend`: replace "until a registry replace delivers the #8408 launch gate, the reboot window …", "is CODE-DECLARED as of #8408 and reaches the host only on the next replace", "Graded, but not PREVENTED until the gate is live" and "likewise graded … once the replace delivers the escrow re-test" with the delivered state (boot `5639cc07`, 2026-09-22T00:30:15Z, run 35672138112). Keep the three concrete non-defences.
   - `at_rest.evidence`: the "store_probe_rc emits a PID … cannot be decoded until the next registry-host replace delivers the fix" sentence becomes "fixed (#8417 closed; `store_probe_rc=cs0.bk0` on boot 5639cc07)". The "store_luks=yes means sits on, not can-unlock" honesty note stays, and gains "the unlock half is now re-tested daily by the escrow re-test (#8408)".
   - `at_rest.retrieved_on`: `2026-09-20` becomes `2026-09-22`.
   - `jq . scripts/encryption-posture-ledger.json >/dev/null` must pass, and so must the lint.
10. `plugins/soleur/test/terraform-target-parity.test.ts`: the doc comment above `describe("registry-luks-recut dispatch -target/-replace set (#6929)"` only. "preserves the still-plaintext store volume, so cloud-init hits the `blkid` else->FATAL arm and DARKS the registry" becomes "preserves the store volume (a host replace, not a recut; before the 2026-08-10 recut that meant the plaintext volume hit the `blkid` FATAL arm)".

## Files to Create

None (plan and tasks artifacts only).

## Out of Scope / Non-Goals

- ADR-096 dated amendments and ADR-172's Context section. They are decision-time history, and ADR-172 already carries a "Superseded 2026-08-11" block. The optional ADR-172 pointer is not needed.
- `test-registry-luks-recut-gate.sh`, `registry-heartbeat-poll.sh`, the cloud-init refuse arm, `registry-luks.test.sh`, and the gate library's interior "footgun" comments. They describe conditional or refuse-arm behaviour.
- `encryption-posture-audit-2026-07-23.md`: already corrected, append-only.
- Legal docs and the superseded plaintext volumes of other stores: #6897.
- Re-anchoring the blocker probe on the live signal: #7377 (open checkbox). No new issue needed.
- Adding a `zotRegistry` row to the NFR register's `### Container Classification` table. That table cites `c4-model.md`'s container count, a separate reconciliation. NFR-027's new row names the container in its own words.
- `model.c4`'s `zotRegistry` "LIVE-VERIFIED as of 2026-09-20" is accurate and unchanged.

## Open Code-Review Overlap

1 open scope-out touches these files: #7098 (audit the 56 `run:` bodies whose `set` omits `-e`, including `apply-web-platform-infra.yml`). **Acknowledge:** that issue is about errexit semantics in `run:` bodies. This plan changes no `set` line and no control flow, only one `echo` string and two comments.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The one runtime-reachable change is `::error::`/`echo` text on abort and PASS paths. The failure that matters is an operator who is still told `registry-host-replace` "darks the registry" and avoids the correct lever during a registry boot incident, which prolongs a pull-path outage for every deploy.
- **If this leaks, the user's data is exposed via:** no new exposure. No secret, key or config value is touched. The ledger and register cite only resource addresses, run ids and boot-id prefixes that are already public in the repo and issue comments. The new NFR row and prose add no device alias (the ledger row already carries one; it is not copied).
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the diff touches .github/workflows and apps/web-platform/infra/*.tf, but only comments, a dispatch-label string and abort/PASS echo text; no Terraform expression, gate predicate or rendered user_data byte changes (proved by the before/after render cmp).`

## Observability

The change adds no runtime path. This block names the existing registry signals that the corrected text now describes, and the probe that guards this diff. Deepen-plan Phase 4.7 requires the full 5-field schema because the diff touches `apps/web-platform/infra/`.

```yaml
liveness_signal:
  what: SOLEUR_ZOT_DISK heartbeat rows carrying store_luks=yes and store_escrow=ok (existing; unchanged by this PR)
  cadence: every 5 min (heartbeat); daily escrow re-test
  alert_target: Better Stack alert registry_store_not_luks (pages the operator)
  configured_in: apps/web-platform/infra/cloud-init-registry.yml (emitter, anchor "store_luks=yes means") + the registry_store_not_luks logtail alert delivered by PR #8456
error_reporting:
  destination: Better Stack logs + the registry_store_not_luks alert; the edited registry-luks-recut ::error:: lines surface in the GitHub Actions log of a destroy-guard abort
  fail_loud: "::error::registry-luks-recut destroy-guard ABORTED" (prefix unchanged by this PR)
failure_modes:
  - mode: the comment-only zot-registry.tf edit alters the rendered user_data, so the next registry-* dispatch replaces the host with different config
    detection: AC4(a) comment-stripped diff against the merge-base (pre-merge, deterministic)
    alert_route: blocks the PR at work/review time
  - mode: the ledger prose edit breaks the schema or a lint check
    detection: lint-encryption-posture.py --repo-sweep in CI (required test aggregate)
    alert_route: red required check on the PR
  - mode: the workflow grows past the 490,000 B gate
    detection: plugins/soleur/test/workflow-file-size.test.ts in the test aggregate
    alert_route: red required check on the PR
logs:
  where: Better Stack (SOLEUR_ZOT_DISK source); GitHub Actions run logs
  retention: Better Stack plan retention; Actions logs 90 days
discoverability_test:
  command: python3 scripts/lint-encryption-posture.py --repo-sweep
  expected_output: "PASS"
```

## Encryption Posture

This plan introduces no store and no connection. The block below mirrors the ledger row `hcloud_volume.registry` after D2. The ledger is the authority. If the two ever disagree, the ledger wins, and `lint-encryption-posture.py` validates only the ledger.

```yaml
at_rest:
  - store: hcloud_volume.registry
    mechanism: luks
    evidence: implied by device_binding (hcloud_volume.registry -> hcloud_volume_attachment.registry -> mapper registry); apparatus apps/web-platform/infra/cloud-init-registry.yml anchors "cryptsetup luksFormat --batch-mode --type luks2" and "cryptsetup luksOpen --key-file - \"$DEV\" registry"; key random_password.registry_luks + doppler_secret.registry_luks_key (zot-registry.tf)
    defends_against: a seized/RMA'd or snapshot-imaged Hetzner block volume; OCI blobs and cosign signatures are unreadable without the Doppler-held passphrase
    does_not_defend: a leaked credential (Doppler token or passphrase), an app-layer read on the unlocked live registry host, or exfiltration through a compromised zot process
    disclosed_as: not-publicly-claimed
    live_verification: available
in_transit: []   # no new connection
```

No `exception` block: the mechanism is not `plaintext-exception`, and nothing sets `cert_verification: off`.

## Acceptance Criteria

- [ ] **AC1** (stale-claim sweep; the issue's two greps, widened): run `grep -niE 'plaintext|unencrypted|never been fired|recut is UNFIRED|unfired|#7287 tracks firing|#7287.*is open|zero live executions|blocked today|PROVISIONING EVENT|darks? (the|THE) REGISTRY'` over files 1–7 and 10. Each remaining hit must fall in one of these classes:
  - (a) dated or past-tense history, including the `History (dated)` block and the annotated addendum;
  - (b) a conditional or refuse-arm description: the `not_luks` triage row, the sentinel "unencrypted path would pass the gate" sentence, `zot-registry.tf`'s `blkid` discriminator note, and the gate library's PRESERVE-STORE comments;
  - (c) the two retained quotes in the blocker script;
  - (d) a non-registry volume: inngest AOF, workspaces, git-data.

  The work phase commits the post-edit hit list, with one class per line, to `knowledge-base/project/specs/feat-one-shot-8535-registry-plaintext-sweep/ac1-hits.txt`. Review diffs the live grep against it, so an unclassified new hit fails.
- [ ] **AC2**: `grep -nE 'still-plaintext|still plaintext|currently unencrypted'` over files 1–7 and 10 returns only the one addendum sentence in file 1. The next line must be followed by the `[Annotated 2026-09-22, #8535` marker.
- [ ] **AC3**: `wc -c .github/workflows/apply-web-platform-infra.yml` is below 490,000, and `workflow-file-size.test.ts` passes. Record the figure in the PR body.
- [ ] **AC4** (operator constraint, pre-merge): the `zot-registry.tf` edit cannot change the rendered `user_data`. Check it in three steps:
  - (a) This is the load-bearing check. Run `B=$(git merge-base origin/main HEAD); diff <(git show "$B":apps/web-platform/infra/zot-registry.tf | grep -vE '^[[:space:]]*#') <(grep -vE '^[[:space:]]*#' apps/web-platform/infra/zot-registry.tf)`. It must print nothing and exit 0. HCL discards `#` comments at parse, so identical non-comment lines mean an identical config.
  - (b) This is the operator's requested check, weak on its own. Render with `registry-userdata-budget.sh` before and after the edit; `cmp` must exit 0. Record one line in the PR body. The script reads only the strip regex and the `zot_image_amd64` pin from `zot-registry.tf` and never parses the edited lines. It proves the template and the strip are untouched.
  - (c) CI's `terraform fmt` stays green.
- [ ] **AC5**: the `nfr-register.md` NFR-027 row reads `Container Registry (zot) store volume | Implemented | LUKS (cryptsetup)`.
  - Its evidence names `hcloud_volume.registry`, `/dev/mapper/registry`, `live_verification: available`, the escrow re-test and launch gate on boot `5639cc07`, and `not-publicly-claimed`.
  - Each fact agrees with the refreshed ledger row, `jq '.stores[] | select(.store=="hcloud_volume.registry")' scripts/encryption-posture-ledger.json`.
  - The System-Level Status line reads "4 of 5".
- [ ] **AC6**: the ledger row no longer contains `reaches the host only on the next replace`, `not PREVENTED until the gate is live`, or `cannot be decoded until the next registry-host replace`.
  - The edit is exact-string only, with no `jq` rewrite. `git diff --numstat scripts/encryption-posture-ledger.json` must read `3	3`, covering `does_not_defend`, `evidence` and `retrieved_on`.
  - `python3 scripts/lint-encryption-posture.py --repo-sweep` prints `PASS`.
- [ ] **AC7**: the blocker script behaves exactly as before. `bash -n` passes. The diff touches only `#` lines and the one PASS `echo` string; `DEP_ISSUE`, the `gh` calls and the exit codes are unchanged.
- [ ] **AC8**: the gate library diff touches comments only, and `bash tests/scripts/test-registry-luks-recut-gate.sh` passes (baseline 37/37). `terraform-target-parity.test.ts` passes after its doc-comment edit.
- [ ] **AC9**: every new dated fact carries its run id, issue number or PR number inline. That is the source of truth for it: run ids from `gh run view <id> --json jobs`, boot and escrow facts from #8408's 2026-09-22T06:56:58Z comment, `available` from PR #8423, and the restore-leg fix from PR #7430 (`4aef468c80`). The diff scope is the 10 listed files, plus the pipeline-written artifacts: this plan, `specs/feat-one-shot-8535-registry-plaintext-sweep/{tasks,session-state,ac1-hits}.*`, and any regenerated `knowledge-base/INDEX.md`. CI (markdownlint via lefthook, the encryption-posture lint, `test`) is green.

## Test Scenarios

The ACs are the scenarios. AC4 is the render and comment-diff check, AC6 the lint, AC3 the size gate, AC8 the suites and AC1/AC2 the greps. There is no separate list.

## Implementation Order

1. Before any edit: render `before.yml` (AC4(b) baseline) and record `wc -c` of the workflow.
2. Edit files 1–7 and 10 (prose/comments/echo). Edit file 9 (ledger), then file 8 (register row, copied from the refreshed ledger row).
3. Render `after.yml`, `cmp`, `wc -c`, lint, the four test commands, markdownlint.
4. Commit, push to the draft PR #8568. The PR body carries `Closes #8535`, the AC4(b) `cmp` result and the `wc -c` figure.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is an engineering docs, comment and emitted-text correction on an existing infrastructure surface. There is no product/UI surface (no file matches the UI-surface globs), no legal-doc edit (#6897 owns those), and no new store, vendor or cost.

## Sharp Edges

- **Does merging this alone mutate production? No.** `apply-web-platform-infra.yml` fires on push to main for `apps/web-platform/infra/**`, so this merge will start an apply run. That run is `-target`-scoped. Every registry resource is an `OPERATOR_APPLIED_EXCLUSION` (ADR-096, the block at the workflow's `OPERATOR_APPLIED_EXCLUSIONS (CTO ruling 2026-07-06)` anchor), so `hcloud_server.registry` cannot be touched by a push apply at all. Only the `registry-*` dispatches `-replace` it. AC4(a) additionally proves the next such dispatch sees an identical `user_data`, and that the drift detector sees no new diff. The PR body's first line says this.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
- `zot-registry.tf` has **no** `lifecycle.ignore_changes = [user_data]`. Any byte change to the rendered user_data replaces the sole registry host on the next push-triggered apply. The edit must stay inside `#` HCL comment lines *above* `user_data =`. Never touch a line inside the `templatefile(...)` argument map, where HCL comments are also safe but the `cmp` is the only proof.
- `apply-web-platform-infra.yml`'s `apply_target` description is a folded `>-` scalar. Keep the edit inside it at the same indentation, or the YAML parse changes the dropdown label.
- The blocker script is re-enrollable via #7377. Its PASS text is what an operator reads, so it must describe the LUKS state without implying the proxy is a measurement. Keep the "VERIFY BEFORE ACTING" lines.
- Cite content anchors, not line numbers, in any new prose (`cq-cite-content-anchor-not-line-number`). The line numbers in this plan are navigation aids for the implementer only.

## Plan Review (2026-09-22)

Panel: DHH, Kieran, code-simplicity and CTO (devex). All findings were applied as Mechanical except these two, which were adopted as correctness or devex fixes of an operator-facing text:

- D6: emitted text states mechanism, not posture. The `::error::` wording the plan proposed was false in the refuse-arm case where a recut is the remedy.
- D7: the heading is renamed and a pre-dispatch check is added.

Neither drops scope the operator requested, and both correct text the issue already scoped in. Applied: recut timestamp corrected to the job's completion time; AC4(a) diffs against the merge-base, not a moving `origin/main`; the missed file-1 sites (first-fire section, addendum "blocked today", "PROVISIONING EVENT"); AC1 made falsifiable with a committed classified hit list; the escrow time aligned to the observed 00:50:02Z; the false "alias withheld" claim fixed; an exact-string ledger edit with a `3	3` numstat. Cut: the self-imposed byte target, the sha256s, the AC for `terraform fmt`/markdownlint that CI already runs, and the Observability, Encryption Posture and Test Scenarios filler.
