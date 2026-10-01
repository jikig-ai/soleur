---
title: "feat(infra): PR B — converge Terraform, code and records after web-1's plaintext /workspaces wipe (#6604 step 7)"
date: 2026-10-01
slug: feat-workspaces-plaintext-wipe-pr-b-convergence
branch: feat-one-shot-6604-plaintext-wipe-pr-b
issue: 6604
closes: []
refs: [6604, 6588, 6931, 6897, 9163, 9286, 9348, 5274, 8625, 6964]
type: feat
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
draft_pr: 9348
---

# feat(infra): PR B — the convergence PR after web-1's plaintext /workspaces wipe

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No `spec.md` exists for this branch.)

## Enhancement Summary

**Deepened on:** 2026-10-01
**Sections enhanced:** Decisions (D1), Operator Holds, Technical Approach §A/§B/§E, Resume After the
Hold (release check rewritten), Guard Contract B1/B3/B4, Observability, User-Brand Impact, Acceptance
Criteria.
**Agents used (deepen round):** a verify-the-negative sweep, terraform-architect, security-sentinel,
user-impact-reviewer, test-design-reviewer, observability-coverage-reviewer — on top of the plan
phase's CTO, CLO, CPO, spec-flow, DHH, Kieran, code-simplicity, architecture-strategist, gdpr-gate and
the ADR-083 advisor. The skill's "run every agent" fan-out was narrowed to the reviewers that bear on
an infra/legal-records plan that had already been through a ten-agent pass; the narrowing is disclosed
here rather than implied away.
**Halt gates:** 4.6 User-Brand Impact pass; 4.7 Observability pass (probe verb `grep`, literal `"1"`);
4.8 PAT none; 4.9 no UI surface; 4.10 Encryption Posture pass; 4.11 Guard Contract lint green (4
entries). 4.55 Downtime: not triggered — no reboot, replace or lock; the only in-place change is a
`delete_protection` flag on a volume (no detach).

### Key improvements

1. **D1 verified end to end.** `delete_protection` is an optional bool on `hcloud_volume` in the pinned
   provider 1.63.0 (`terraform providers schema`), and the narrowing + sentinel conditional validates
   and evaluates correctly (`terraform_data` stand-ins: web-1 → `"retired-6604"`, web-2 → its id, a
   `-target` through web-1 plans `No changes`). Terraform-architect traced every apply path: only the
   SSH stage carries the in-place update; no gate aborts on it; the recut `-replace` plan-fails as
   intended; nothing detaches.
2. **The release check binds to what gated the act.** Run ids are bound to workflow file, `main` and
   `workflow_dispatch`; the host step's own row parser (step conclusion) is the gate; greps are scoped
   to the emitting step; every check prints `FAIL <name>` and the block exits non-zero; status flips are
   proven to be additions, in order.
3. **Guard-5 coverage that the strip would have lost is named:** F6 (the only row exercising the real
   `_plaintext_*` mapping), F7, F11, S5, S6, plus the fixtures G5d needs.
4. **The tombstone refuses any non-`0` value** (`assert_mode_exclusive` counts only the string `1`, so
   `true` or `" 1"` would have fallen through to the L3 cutover body).
5. **Post-merge apply is gated by a read-only drift plan** listing exactly the expected changes, because
   the SSH stage that delivers the protection runs `-auto-approve` with no destroy-guard.

### New considerations discovered

- The SSH stage is skipped green when `CI_SSH_ACCESS_TOKEN_ID` is absent: AC-H5 reads the step
  conclusion and its `Modifications complete` line, not the saved plan.
- Removing `prevent_destroy` while `delete_protection` stays on would detach the mounted volume before
  failing the delete — an ordering trap for #6931.
- After the wipe job goes, the `cutover` job still falls back to a write token; filed as a pre-existing
  item rather than widened here.
- If D prints `plaintext_only>0`, workspace ids reach a public Actions log; the resume step deletes
  that run's logs after evidence capture.

## Overview

PR B of #6604 runbook step 7, specified in §E of the archived step-7 plan
(`knowledge-base/project/plans/archive/20260930-100517-2026-09-28-feat-workspaces-plaintext-volume-wipe-plan.md`,
"PR B — convergence (diff prepared before D, evidence filled after)") and the ADR-119 addendum of
2026-09-28. PR A (#9163) and its identity fix-forward (#9286, merge `59abf6a76c`) shipped the
single-use wipe mode, the gated `wipe` job and the single-use state-forget workflow. This PR is the
other half of that design. It:

1. narrows `hcloud_volume.workspaces` / `hcloud_volume_attachment.workspaces` to every host **except
   web-1** (web-2 keeps volume `106466179`), and passes web-1's `workspaces_volume_id` the sentinel
   literal `"retired-6604"`;
2. protects the sole-copy LUKS volume `106443278` in Terraform: `prevent_destroy = true` and
   `delete_protection = true` on `hcloud_volume.workspaces_luks`;
3. deletes `.github/workflows/workspaces-plaintext-forget.yml` and the single-use wipe code (the
   `CONFIRM_WIPE` mode body, `wipe_plaintext()` and its helpers, the `wipe` job and its
   preflight/rehearsal wiring, the wipe rows of `workspaces-luks-wipe.test.sh` and of loopback
   Session W), while **keeping** the Guard-5 rollback refusal (the `PLAINTEXT_WIPE_*` marker witness and
   the physical witness via `_plaintext_record_status`) and the dead-man fire guard, with their tests;
4. re-scopes the `hcloud_volume.workspaces` encryption-posture exception to the web-2 instance
   (tracking #6931, `expires_on: 2026-12-29`; the current row expires 2026-10-22);
5. completes the records: the Art. 5(2) destruction record, the ADR-119 addendum and its
   `adopting → accepted` flip, the CLO-attested legal-register sweep (Art. 30 PA-1/PA-2, the #6588
   counsel review, the NFR register — never `docs/legal/**`), `expenses.md`, the apply-job rationale,
   `model.c4`, runbook step 7, and the #6931 / #6897 comments.

**Evidence does not exist yet.** The destructive dispatch D and the state forget have not run; each is
authorized separately, per command, outside this pipeline. Every field only D or the forget can supply
is a `PENDING-EVIDENCE(<field>)` marker, never an invented value, and this PR is held as a draft until
those markers are gone (`## Operator Holds`). Evidence that already exists is cited: rehearsal run
`36769782488` and same-day baseline run `36770448813` (both read 2026-10-01; see Research Insights).

**Does merging PR B alone mutate production?** Two ways, both deliberate: the routine container
release (`web-platform-release.yml`, `apps/web-platform/**`), and — once the post-merge `manual-rerun`
apply runs — one in-place `delete_protection` update on `hcloud_volume.workspaces_luks` (it is in the
SSH stage's `-target` closure through `terraform_data.workspaces_boot_unlock_install`). The push
applies that `server.tf` would trigger (`apply-web-platform-infra.yml`, `apply-deploy-pipeline-fix.yml`)
are disabled from before D until after this merge. The PR body's first line states this.

## Decisions

- **D1 — Protect the sole copy in Terraform, not in a gate.** `prevent_destroy = true` +
  `delete_protection = true` on `hcloud_volume.workspaces_luks`. `prevent_destroy` makes every plan
  that would destroy or replace it fail (the recut `-replace`, a ForceNew edit reaching it through the
  SSH stage's unguarded `-auto-approve` apply); `delete_protection` makes Hetzner refuse a delete from
  the console, API or CLI until someone holding a write token lifts it. Both are accident guards, not
  access controls: a reviewed PR can remove them, and Guard B4 runs in `infra-validation`'s
  deploy-script-tests, which is not a required check — removing them stays a reviewed decision. #6931 deferred `prevent_destroy` only because it collides with the recut
  `-replace` — whose premise ("the live plaintext keeps serving") is false after step 7. No
  recut-gate edit is needed. (Revised from a plan-v1 recut-gate refusal after the CTO showed the
  volume IS in a push-apply closure.)
- **D2 — Tombstone, not deletion, for `CONFIRM_WIPE`.** Keep the variable declared and counted in
  `assert_mode_exclusive`; its block becomes a refusal (`outcome=wipe_retired`, own row, `trap - EXIT`,
  `die`, no `emit_drift`). Six lines; a stray value can never fall through to the L3 cutover body.
- **D3 — `git mv` the wipe suite to `workspaces-luks-rollback-refusal.test.sh`** and strip it to the
  Guard-5 rows (rename and strip in two commits so `git log --follow` survives the similarity drop).
- **D4 — Evidence lives in the destruction record and the ADR-119 addendum.** Registers, runbooks,
  `expenses.md` and C4 state the change in the past tense, carry only the date marker, and link the
  record. One marker vocabulary, one grep (AC-H3).
- **D5 — `Ref #6604`, not `Closes`, at merge** (UC-1 in `decision-challenges.md`; CPO concurred): the
  follow-through sweeper closes it.
- **D6 — PR B is merge-ready before D.** Once the forget has run, the push-apply pause cannot end
  until PR B merges (re-enabling with config still listing web-1 would plan a fresh plaintext volume),
  so review, QA, compound and the draft-time CLO pass all finish first.

## Operator Holds

**HOLD — PR B ships as a DRAFT and is NOT marked ready, and NOT merged, until all four hold:**

1. Volume `105149570` is **proven zeroed and deleted**: a D run (`workspaces-luks-cutover.yml`,
   `wipe_plaintext=true dry_run=false`) printed the host row `result=wiped` (or `already_wiped_detached`)
   for `105149570`, AND either that run's "Detach and delete the plaintext volume (Hetzner API)" step
   concluded `success` (it fails unless the final `GET` is a presence-proven `404`) or — when D died
   after the `DELETE` and a re-dispatch is refused at preflight as "already deleted" — the forget run's
   `gone` step concluded `success` (its own presence-proven `404` + empty name lookup).
2. `workspaces-plaintext-forget.yml` has a named run that reported `forgot=2` or `forgot=1`, or
   `already_forgotten` **traced** to an earlier named forget run that removed the addresses. A
   `cancelled` run is re-dispatched (idempotent). An `already_forgotten` no forget run explains means
   something else wrote the state: halt and escalate; do not fill the record.
3. Every `PENDING-EVIDENCE(` marker is replaced from those runs' own output (AC-H3), the CLO has
   attested at that commit, the destruction record reads `status: complete`, and only then ADR-119
   reads `status: accepted` (both commit SHAs cited in the PR body — a squash merge erases the order).
   A field the as-run arm cannot produce is filled `n/a (<arm>, run <id>)` — e.g. no detach action id
   on `arm=detached` — never left as a marker and never invented.
4. PR B's `infra-validation` is re-run after the forget and is green. Its web-platform plan is **red
   by design** until the forget removes `["web-1"]` from state (a `-refresh=false` plan of the narrowed
   `for_each` against state still holding web-1 plans a destroy that `prevent_destroy` refuses —
   reproduced on Terraform 1.10.5, archived plan §"Terraform ordering"). `infra-validation` is not a
   required check on `main`, so this is a hold item, not a mechanical block.

`soleur:ship` honors this hold: in this pipeline it pushes the draft, adds the existing `blocked`
label to #9348 (operator-visible; draft state is the mechanical block), and STOPS. It never runs
`gh pr ready` or `gh pr merge`. Releasing the hold is Resume step 5's release check.

**The resume path stays on `main` until PR B merges.** D and the forget are dispatched from `main`
(the `workspaces-luks-cutover` environment's deployment policy is main-only), so they always run
`main`'s wipe mode and forget workflow, never this branch's deletions. Every resume arm —
re-dispatching D (`arm=re_zero`, `arm=detached`) or the forget (`already_forgotten`) — stays available
for exactly as long as PR B is unmerged. Merging before conditions 1–2 deletes the only code that can
finish an interrupted D or forget; recovery would need a **partial** revert PR (no operator-local apply
exists). A plain `git revert` of PR B's squash commit is wrong: it would also strip the sole-copy
protections this PR adds — `prevent_destroy` and `delete_protection` on `hcloud_volume.workspaces_luks`,
and `prevent_destroy` on `hcloud_volume_attachment.workspaces_luks` — and the next SSH-stage apply
(`-auto-approve`, no destroy-guard) would turn Hetzner delete protection OFF on the sole copy. The
recovery PR restores only the wipe mode and its `wipe` job and inputs, `workspaces-plaintext-forget.yml`
and `server.tf`'s web-1 `for_each` membership and volume id; it leaves `workspaces-luks.tf`'s protections
and the hard-retired recut job untouched, and Guard B4 stays green on it.

**A fix-forward to the wipe code during the hold must be re-derived here** (Resume step 1).

**Maximum pause after the forget: 48 h.** After the forget, the abandon branch no longer applies —
merging PR B is the only exit from the pause (re-enabling with config still listing web-1 would plan a
fresh plaintext volume). If PR B is not merged within 48 h of the forget run, post an escalation comment
on #6604 naming what blocks it. Both this bound and the 2026-10-15 bound below are enrolled as a
follow-through, not left in prose (next paragraph).

**Expected false positive in the window.** Between the forget and this merge, `main`'s config still
lists web-1, so `scheduled-terraform-drift.yml` reports `+create` of the two web-1 workspaces addresses
and may file a drift issue. That is the window's expected state; never "fix" it — close it with a
pointer to this PR once Resume step 6 shows the drift run green.

**Abandon / expiry branch.** If step 7 is abandoned (D halts before the delete and is not re-run), or
D has not run by **2026-10-15**: end the pause per the runbook, keep PR B as a draft (or close it,
keeping the branch), and land a separate docs PR that **extends** the existing `hcloud_volume.workspaces`
row's `expires_on` with a justification naming the pending wipe — never the web-2 re-scope, which would
leave web-1's still-existing plaintext unledgered — and sweeps the registers that quote
`expires_on: 2026-10-22` (Art. 30 PA-1 (g)(17), PA-2 (g)(21), the 6588 `accepted_residual`). If the
date passes with the copy still in place, the registers say the exception expired (the 8248 trigger
(2) precedent). The 2026-10-22 expiry otherwise fails `lint-encryption-posture.py` repo-wide. Comment on
#6604 and #6897. If PR B later conflicts on that JSON row, PR B's re-scope wins.

**Follow-through: the hold's two time bounds.** `soleur:ship` files, with the draft, one tracker issue
labelled `follow-through` (`followthrough-convention.md`) carrying:

```text
<!-- soleur:followthrough
  script=scripts/followthroughs/workspaces-plaintext-hold-9348.sh
  earliest=2026-10-15T00:00:00Z
  secrets=GH_TOKEN
-->
```

Its probe is notify-only while the hold stands, and reads only `gh`:

- **exit 0 (close)** — #9348 is merged;
- **exit 5 (ACTION REQUIRED)** — #9348 is open on or after 2026-10-15 (the abandon/expiry decision is
  due), or the latest `workspaces-plaintext-forget.yml` run on `main` concluded `success` more than 48 h
  before the sweep and #9348 is still unmerged (the post-forget bound), or #9348 was closed unmerged;
- **exit 2 (NOT YET)** otherwise; **exit 3 (CANNOT ESTABLISH)** when `gh` fails.

The `earliest=2026-10-15` gate means the 48 h bound is enforced by the sweep only from that date; before
it, the Resume session's own clock carries it (Resume step 5 names the forget run's
`updated_at`). The tracker is #9380. The probe script and its suite ship to `main` in their own PR (#9381),
not in this draft: the sweeper runs probes from `main`, so a probe inside this PR would only
reach `main` after the hold had already cleared. A closed-unmerged #9348 reads exit 5 (confirm
the abandon branch's ledger-extension PR merged, then close the tracker by hand).

**No step here is a production write.** This PR's own work touches no host, Hetzner object or
Terraform state. D, the forget, and the post-merge re-enable + `manual-rerun` apply are the go-ahead
set authorized separately, per command, as the step-7 runbook records.

## Research Reconciliation — Spec vs. Codebase

| Brief / §E claim | Reality (measured 2026-10-01) | Plan response |
|---|---|---|
| PR body: `Closes #6604`, `Closes #6588` at final merge | #6604 carries `follow-through`; `.claude/hooks/pre-merge-auto-close-scan.sh` (follow-through label gate) denies a close keyword against it, and the sweeper `scripts/followthroughs/workspaces-luks-soak-6604.sh` is its designed closer (ADR-119 `accepted` ∧ zero `op:workspaces-luks-drift` over 7 d ∧ heartbeat span). #6588 has no such label. | D5. |
| The sweeper closes #6604 when ADR-119 flips | Its 2026-09-29/30 runs FAIL on drift events emitted by the refused rehearsal (`wipe_target_label_mismatch`, run 36710773788) that #9286 fixed. Its Sentry query has no level filter, so any refused rehearsal or refused D restarts the 7-day window. | Not fixed here; AC-H6 is worded against the window; the tombstone never emits drift. |
| "Remove the CONFIRM_WIPE mode" | A full removal lets a stray `CONFIRM_WIPE=1` fall through to the L3 cutover body (PR A's Guard 1 row 12); `workspaces-luks-staging.test.sh` T4h-c pins that `assert_mode_exclusive` counts it. | D2. |
| `workspaces-luks-wipe.test.sh` is single-use | It holds the only stubbed coverage of Guard 5 (G5, G5b-*, G5c, G5d-*) and G1-W, the writer row for `PLAINTEXT_DEV`; loopback Session W holds the only real-device Guard-5 rows (LW-P2, LW-P3, LW-P4). | D3; Session W becomes Session G5 (LW-P2/P3/P4 kept, P3/P4 re-seeded with a `dd` zero instead of LW1). |
| Update `test-workspaces-luks-cutover-gate.sh` Q4 if the code moves | Q4 sources `workspaces-cutover.sh` and stubs `_plaintext_dev_type`/`_plaintext_blkid_bin` around the real `arm_dead_man` + `_plaintext_record_status`; all stay, same names, same file. | No edit; AC: green unchanged at `EXPECTED_ASSERTIONS=34`. |
| Delete protection: `delete_protection = true` in PR B, or a recut-gate refusal (§E) | `hcloud_volume.workspaces_luks.id` feeds `terraform_data.workspaces_boot_unlock_install` (precondition + writers), which `apply-web-platform-infra.yml`'s SSH stage targets with `-auto-approve` and no destroy-guard. So the volume is in a push-apply closure: a config change to it IS delivered, and a ForceNew edit would replace the sole copy unguarded. | D1. |
| Sentinel `"retired-6604"` keeps web-1 renderable | `cloud-init.yml` runs `mount … \|\| soleur-boot-emit workspaces_mount fatal \|\| true`: a rebuilt web-1 emits the fatal event and **keeps booting** on an empty `/mnt/data` (fails loud, not closed). Unreachable while the replace path refuses web-1 ("LUKS-pinned host") and `user_data` is `ignore_changes`. | Stated as such in UBI and the destruction record. |
| `expenses.md` LUKS row id `106406962` | The live LUKS volume on server 123931471 is `106443278` (read-only GET 2026-09-28, archived plan; the first provision was re-cut under #6812/#6855). | Corrected in the same edit. |
| `luks-monitor.test.sh` needs no change | It pins the outcome vocabulary (`… dry_run wipe_aborted refused_plaintext_wiped …`) and the literal `'result=cutover_aborted outcome=${outcome}${mode}${abnormal}${fields}${detail}'` (CTO census). | Files to Edit; vocabulary swaps `wipe_aborted` → `wipe_retired`; the pattern follows the `cleanup()` edit. |

## Research Insights

### Premise validation (Phase 0.6)

- **#6604** OPEN (`follow-through`, `needs-attention`, p1). **#6588** OPEN (p0, no `follow-through`).
  **#6931** OPEN (web-2 fresh-boot LUKS + topology reconciliation; owned the deferred
  `prevent_destroy`). **#6897** OPEN (item 1 also names `hcloud_volume.git_data`, out of scope).
  **#9123** CLOSED by #9179 (boot unlock; fstab names the mapper). **#9163**, **#9286** MERGED;
  **#9348** this draft. Durability owners: **#5274**, **#8625**, **#6964** OPEN.
- **Rehearsal run `36769782488`** (`success`, 2026-09-30T20:02Z, `workflow_dispatch` at `59abf6a76c`):
  `result=rehearsal_ok arm=first_wipe volume_id=105149570 uuid=d42ede00-4ec4-48c6-9b83-f15ff3f69082
  target=/dev/sdb backing=/dev/sdc size=21474836480 serial=ok label=none plaintext_dev=/dev/sdb
  plaintext_fs_uuid=4cc6a724-f3b7-4c96-b607-af174f82169d holders=0 dependents=0 device_units=7
  hdr_bytes=16777216 hdr_sha256=ac3447ec…c60dc98f discard_gran=4096 discard_max=1073741824
  write_zeroes_max=2147483136 scheduler=none magic=53ef io_max=8:16_rbps=150000000_wbps=150000000_…
  plaintext_only=0`; its evidence rows carry `last_mount=Mon Jul 20 22:42:07 2026` and
  `last_write=Thu Jul 23 09:40:34 2026` (no timezone printed; inside cutover run 29995956562's window,
  beside its `WORKSPACES_COUNT=8` persist at 09:40:33Z — cite that log line, the run concluded
  `failure`). **Baseline run `36770448813`** (`success`, 2026-09-30T20:07Z):
  `ready=true workspace_count=9 expected=8`. The work phase copies values from the run logs
  (`gh run view <id> --log`), never from this summary.
- `infra-validation`'s plan job is **not** among `main`'s required status checks (ruleset read
  2026-10-01). Labels `blocked`, `semver:patch`, `app:web-platform` exist.
- `apply-web-platform-infra.yml` 483,707 bytes (this PR only shrinks it, via stale-text edits).
- No live plan or spec outside `archive/` prescribes `wipe_plaintext` or the forget workflow.

### Property List (Phase 0.6b)

- **P1** web-1 owns no plaintext workspaces volume in Terraform config or state, and no apply can
  re-create one for it.
- **P2** web-2's plaintext volume is the only remaining `hcloud_volume.workspaces` instance, still
  `prevent_destroy`, still an honestly-scoped, unexpired posture exception.
- **P3** No code path remains that can zero, detach or delete a workspaces volume, and a stray
  `CONFIRM_WIPE=1` can neither wipe nor fall through to a cutover.
- **P4** ROLLBACK and the dead-man fire stay refused for ever on web-1 (marker + physical witness),
  with their tests intact.
- **P5** The sole-copy LUKS volume `106443278` cannot be destroyed or replaced by any Terraform plan,
  nor deleted through the Hetzner API/console/CLI without first lifting its protection.
- **P6** The records say what happened, with real evidence, in the right order: CLO attestation →
  destruction record complete → ADR-119 accepted; nothing invented.
- **P7** PR B cannot merge before D and the forget conclude, and D/forget stay resumable until it does.

### Cut List (Phase 0.6b and plan review)

- **A CI check that fails while `PENDING-EVIDENCE(` markers exist** → P7 is bought by the draft, the
  hold and AC-H3; a red-by-design required check would mask every other regression on this branch.
- **A recut-gate `sole_copy_targeted` clause (plan v1)** → `prevent_destroy` (D1) refuses every destroy
  path at plan time, id-agnostic; a hard-coded id in a gate stops protecting on re-provision.
- **Retiring the `workspaces-luks-recut` apply target** → `prevent_destroy` makes it plan-fail for the
  live volume; removing a dispatch arm is #6931's topology work.
- **A new `pending-evidence` status value for the destruction record** → nothing reads it; the record
  stays `template` until `complete`, and the markers + AC-H3 carry the state.
- **A new loopback row LW-G5b** → LW-P3 already proves "zeroed recorded plaintext → gone" on real
  devices; it is re-seeded with `dd`.
- **Guard rows asserting absent inputs/delivery lines** → the Hetzner-write census and the exact job
  set cover P3; an input with no consuming job does nothing.
- **Moving Guard-5 rows into `workspaces-luks-freeze.test.sh`** → `git mv` keeps fixtures and history.
- **Rewriting Q4**, **changing the soak script**, **editing the three backstop loops in
  `apply-web-platform-infra.yml`** (after PR B those addresses can appear only as a `create`, which the
  loops still catch).
- **A watchdog cron for a long-disabled apply workflow** → D6 makes the pause hours long by
  construction (offered as T-2 in `decision-challenges.md`).

### Relevant files (content anchors)

- `apps/web-platform/infra/server.tf` — `resource "hcloud_volume" "workspaces"` /
  `resource "hcloud_volume_attachment" "workspaces"` (`for_each = var.web_hosts`, `prevent_destroy`);
  `hcloud_server.web`'s `workspaces_volume_id = hcloud_volume.workspaces[each.key].id` (comment
  `#6604 — pin /mnt/data to THIS host's workspaces volume`). `placement-group.tf`'s two historical
  `moved` blocks stay (a stale `moved { to = vol["web-1"] }` validates to `No changes`).
- `apps/web-platform/infra/workspaces-luks.tf` — `resource "hcloud_volume" "workspaces_luks"` (no
  `lifecycle`, no `delete_protection` today), `terraform_data.workspaces_boot_unlock_install`
  (precondition + writers interpolating `hcloud_volume.workspaces_luks.id`), and the "The live hazard
  is the OPPOSITE of ambiguity" comment.
- `apps/web-platform/infra/workspaces-cutover.sh` — KEEP: `_plaintext_dev_valid`,
  `_plaintext_blkid_bin`, `_plaintext_blkid_type`, `_plaintext_dev_type`, `_plaintext_record_status`,
  `_plaintext_gone`, `_plaintext_record_fields`, `_plaintext_gone_fields`, `_plaintext_gone_msg`,
  `_plaintext_gone_outcome`, `rollback()`'s first-line refusal, `assert_rollback_not_post_cutover`,
  `_rollback_refuse`, `arm_dead_man`'s `gone_guard`, `persist_state PLAINTEXT_DEV` (rollback
  rehearsal step), `assert_mode_exclusive`, `_deadman_row` (defined well before `trap cleanup EXIT`).
  REMOVE: the `# CONFIRM_WIPE — retire web-1's retained plaintext` section through the end of
  `wipe_plaintext()` (`WIPE_*` globals and seams, `_wv`, `emit_wipe`, `emit_wipe_evidence`,
  `_wipe_refuse`, `_wipe_shred_hdrs`, `_wipe_assert_no_dependents`, `_wipe_readback`, `WIPE_IO_GATE`,
  `wipe_plaintext`), the mode block's body, `cleanup()`'s `CONFIRM_WIPE` arm with its
  `_wipe_shred_hdrs` call and the `mode`/`begun` locals and uses, and the closing comment that points
  at the mode. Census every removed helper for non-wipe callers first (`_same_dev`,
  `load_escrow_creds`, `ensure_aws`, `read_key` are shared and stay).
- `.github/workflows/workspaces-luks-cutover.yml` — REMOVE: inputs `wipe_plaintext`,
  `expected_plaintext_volume_id`; env `PLAINTEXT_VOLUME_NAME`/`PLAINTEXT_VOLUME_ID` (and
  `LUKS_VOLUME_ID`/web-1 ids only if no surviving step reads them); preflight's wipe exclusion and
  confirm branch, the `api` classification step and its `api_state`/`size_bytes` outputs; `cutover`'s
  job-level `if:`, its `CONFIRM_WIPE`/`PIN`/`PLAINTEXT_SIZE_BYTES` env and `.env` lines, the
  rehearsal-summary block, the summary's WIPE arm and the `::error::` text naming `mode=wipe`; the whole
  `wipe` job; the header's step-7 block. `cutover`'s `environment:` expression stays byte-identical
  and the first `environment:` line (H17).
- Tests: `workspaces-luks-cutover-workflow.test.sh` (`WF_MIN_ASSERTIONS=189`, job set, `CUT_IF`, wipe
  wiring, forget parity, R-CENSUS), `workspaces-luks-freeze.test.sh` T43 (4 → 3 exit-0 paths and its
  label), `workspaces-luks-staging.test.sh` T4h-c (unchanged), `workspaces-luks.test.sh`
  (`assert_holds`/`assert_mutation`), `luks-monitor.test.sh` (outcome vocabulary + cleanup row
  pattern), `tests/scripts/test-infra-privileged-tier-census.sh` (comments; row 11 is a synthesized
  fixture), `scripts/guard-vacuity-floor.test.sh` (drop the forget suite from the last
  `PROMOTED_FILES` assignment — the "every PROMOTED_FILES entry is still floor-bearing" row fails on a
  deleted file), `plugins/soleur/test/fixture-relative-assert.baseline.txt` (loopback count 18),
  `plugins/soleur/test/terraform-target-parity.test.ts` (discovers workflows; comment only).
- Stale-premise text (the "LIVE plaintext /mnt/data" class): `tests/scripts/lib/workspaces-luks-recut-gate.sh`,
  `tests/scripts/lib/workspaces-luks-cutover-gate.sh` and `tests/scripts/lib/inngest-volume-recut-gate.sh`
  headers/comments,
  `tests/scripts/lib/web-host-replace-gate.sh` header, `apply-web-platform-infra.yml` (the web-1
  refusal's "DECISIVELY … PLAINTEXT volume" text and the recut/cutover messages saying "live plaintext"),
  `apply-deploy-pipeline-fix.yml` (the `hcloud_volume.workspaces["web-1"]` comment), the header of
  `tests/scripts/test-workspaces-luks-cutover-gate.sh`, every "NO prevent_destroy" comment (AC-B6) incl.
  `web-host-replace-gate.sh` ~122-124 ("the LUKS volume has NO prevent_destroy … ONLY guards"), the
  `workspaces-luks-recut` job header (~4570-4581) and the `confirm` input description (~78) that still
  lists `workspaces-luks-recut` as a usable destructive target, ADR-148
  (one dated note). Text only; no logic. The `workspaces-luks-recut` arm's
  `-replace='hcloud_volume.workspaces_luks'` (`apply-web-platform-infra.yml` ~4691) stays in place and
  now plan-fails on `prevent_destroy` for the live volume — the intended effect (D1); runbook Sequence 0
  says so, so the `Instance cannot be destroyed` error is read as the guard, not a defect.
- Records: `knowledge-base/legal/audits/workspaces-plaintext-destruction-record.md` (`status: template`;
  its checklist: CLO-attested recoverability, `complete` before the ADR flip), ADR-119 (`status:
  adopting`), ADR-241 D2 note, `article-30-register.md` PA-1 (g)(17) / PA-2 (g)(21),
  `audits/2026-07-counsel-review-6588.md` (banner, `status:`, `accepted_residual`,
  `re_evaluation_triggers` (1)/(2), §A3.5, §A3.6), `nfr-register.md` Compute row, `expenses.md` rows
  "Hetzner Volume (20 GB)" and "(workspaces-luks, 20 GB)", `apply-web-platform-infra-job-rationale.md`,
  `model.c4` + `model.likec4.json`, runbook `workspaces-luks-cutover-6604.md`.

### Institutional learnings applied

- `2026-09-27-a-status-flip-sweep-must-include-the-legal-registers-that-state-the-mechanism.md`.
- `2026-09-27-a-correction-from-today-to-until-extends-the-claim-backwards.md` — bound both ends.
- `2026-09-27-a-retirement-census-by-name-missed-the-consumer-that-pinned-the-id.md` — the census also
  greps `105149570`, the volume name and the typed tokens (three gate-test fixtures use the id only as
  a synthesized "other volume").
- `2026-09-30-the-wipe-guard-read-a-label-no-artifact-ever-wrote.md` — Guard 5 reads `PLAINTEXT_DEV`;
  its writer row (G1-W → G5-W) survives with it.
- `2026-09-28-an-ssh-drop-without-a-pty-is-sigpipe-and-my-cleanup-trap-read-it-as-success.md` — the
  tombstone writes its own row and drops the EXIT trap, like `_rollback_refuse`.
- Plan sharp edges applied: a second apply workflow can reach a resource (`apply-deploy-pipeline-fix.yml`
  also triggers on `server.tf`); removing an emit site can dark a filter (no Sentry rule keys on a
  `wipe_*` slug — `sentry_alert.workspaces_luks_drift` keys on the op); `discoverability_test` carries no
  shell metacharacters; markdownlint the plan and tasks before the summary.

### Functional discovery

No community artifact overlaps (functional-discovery, 3/3 registries). Build in-house.

## Technical Approach

### A. Terraform (`server.tf`, `workspaces-luks.tf`)

```hcl
# apps/web-platform/infra/server.tf
locals {
  # #6604 step 7 — web-1's plaintext workspaces volume (105149570) was zeroed, read back, detached and
  # deleted, and its two addresses were forgotten from state (ADR-119 addendum; destruction record).
  # Only the hosts listed here still own a per-host plaintext volume.
  plaintext_workspaces_hosts = { for k, v in var.web_hosts : k => v if k != "web-1" }
}
resource "hcloud_volume" "workspaces" {
  for_each = local.plaintext_workspaces_hosts
  # name/size/location/format/labels/lifecycle UNCHANGED (the name expression stays byte-identical)
}
resource "hcloud_volume_attachment" "workspaces" {
  for_each = local.plaintext_workspaces_hosts
  # unchanged
}
# hcloud_server.web templatefile argument:
    workspaces_volume_id = contains(keys(local.plaintext_workspaces_hosts), each.key) ? hcloud_volume.workspaces[each.key].id : "retired-6604"

# apps/web-platform/infra/workspaces-luks.tf — resource "hcloud_volume" "workspaces_luks"
  delete_protection = true
  lifecycle {
    prevent_destroy = true   # #6604 step 7: the sole copy of every workspace; the recut -replace is retired
  }
```

- HCL reports only the selected arm's diagnostics, so the missing `["web-1"]` index is never an
  error (CTO-verified for the CI-pinned 1.10.5). The edge `hcloud_server.web → hcloud_volume.workspaces`
  stays resource-level: a `-target` through web-1 pulls web-2's volume in as a no-op. `user_data` is
  `ignore_changes` and `workspaces_volume_id`'s only consumer is the one `templatefile` call, so neither
  server diffs. Not the LUKS id: that would add nothing and couple the sentinel to the sole copy.
- `prevent_destroy` changes no plan by itself; `delete_protection` plans one in-place update on
  `hcloud_volume.workspaces_luks`, delivered by the post-merge `manual-rerun` apply's SSH stage. The
  destroy-guard filter does not count volume updates (#6919/T55), so it does not halt.
- Comments updated at both resources and at the `#6604 — pin /mnt/data` comment.

### B. Script (`workspaces-cutover.sh`)

Delete the wipe section; keep the KEEP set verbatim. The mode block becomes (same position: after
CLEAN_STRAY, before the L3 gates):

```bash
# CONFIRM_WIPE — RETIRED (#6604 step 7). Nothing in this repo delivers it; a stray CONFIRM_WIPE=1 must
# neither wipe nor fall through to the L3 cutover body below. assert_mode_exclusive still counts it, so a
# mixed dispatch is refused there first. ANY value other than unset/0 is refused (assert_mode_exclusive
# counts only the string "1", so `true` or " 1" would otherwise fall through to L3).
# No emit_drift: a stray value must not restart the #6604 sweeper.
if [ "${CONFIRM_WIPE:-0}" != "0" ]; then
  _deadman_row "result=cutover_aborted outcome=wipe_retired"
  trap - EXIT
  die "CONFIRM_WIPE is retired: web-1's plaintext volume was wiped and deleted (#6604 step 7) and the mode was removed. Nothing was touched."
fi
```

- `cleanup()`: delete the `CONFIRM_WIPE` arm and its `_wipe_shred_hdrs` line, and in the SAME edit
  remove the `mode`/`begun` locals AND their `${mode}`/`${begun}` uses in the final `_deadman_row`
  (under `set -u` a dangling `${mode}` kills the EXIT trap and loses every abort's outcome row). Add a
  row: an abort through `cleanup()` emits exactly one outcome row, with no `mode=` field.
- The tombstone never sets `RUN_COMPLETE=1` and never `exit 0`s; the `RUN_COMPLETE` header comment
  (which lists "the CONFIRM_WIPE end") and T43's label follow.
- `arm_dead_man`'s "the wipe refuses while any dead-man is armed (W7)" and the closing "cutover body
  complete … The WIPE is a SEPARATE environment-gated dispatch" text become historical.

### C. Workflow (`workspaces-luks-cutover.yml`)

Remove the wipe wiring listed under Relevant files; `cutover` returns to no job-level `if:`; the
`dry_run` description loses its `wipe_plaintext` clause. Roughly 600 lines shrink; no step is added.

### D. Delete the forget workflow and its suite

`git rm .github/workflows/workspaces-plaintext-forget.yml apps/web-platform/infra/workspaces-plaintext-forget-workflow.test.sh`;
drop the suite from `scripts/guard-vacuity-floor.test.sh`'s last `PROMOTED_FILES` assignment and its
comment block; update the census, parity and ADR-241 text that names it as live.

### E. Tests

- **Rollback-refusal suite** (D3): commit 1 `git mv workspaces-luks-wipe.test.sh
  workspaces-luks-rollback-refusal.test.sh`; commit 2 strips the wipe rows. **KEEP:** G1-W (→ G5-W),
  G5, G5b-*, G5c, G5d-*, and the Guard-5 rows that sit in the static/census region just before the C1
  census — **F6** (the only row exercising the REAL `_plaintext_blkid_type` / `_plaintext_dev_type` /
  `_plaintext_record_status` mapping: `blkid_error_<rc>`, `blkid_absent`, `absent`), **F7** (the
  dead-man fire uses a fixed-path blkid, not PATH), **F11** (`PLAINTEXT_DEV` persisted before
  `arm_dead_man`), **S6**, and **S5** re-scoped to the two `_plaintext_*` seams (`-eq 2`). **KEEP the
  fixtures they need:** `harness_selftest`, `harness_blockdev` / `$TGT_BLK` (G5d arms with it and uses
  it as `G5D_EXPECT_DEV`), the unprivileged-refusal line, `$DM`, `$PIN`, the scratch dir (rename
  `WIPE_SCRATCH` in ONE edit — a half-done rename aborts the suite under `set -u`). **DROP:** `LUKS_BLK`,
  `WIPE_STUBS`, the tripwires, `run_wipe`, P*/S1–S4/W*/M*/C* rows. Guard B1's rows use the harness's
  `run_case` with the kept MAIN_PREFIX extraction (its base env sets no `CONFIRM_WIPE`). Pin the floor
  at the exact measured count (the suite's literal floor is `-lt`, so only an exact pin makes H2 bite).
- **Loopback** — Session W → "Session G5 — the real Guard-5 witness": keep the LUKS loop + mapper +
  recorded ext4 plaintext loop setup and LW-P2/LW-P3/LW-P4; re-seed P3/P4's zeroed device with
  `dd if=/dev/zero of=<loop device> bs=1M count=1 oflag=direct conv=fsync` (the device, not the backing
  file, so `blkid -p` reads no stale cache) instead of LW1 — assert `dev_magic`=53ef before, the `dd`
  rc, and an independent `blkid -p` rc 2 after; refuse unless `losetup -nO BACK-FILE` of the target is
  under `$TMPROOT` (the suite runs as root); LW-P4 needs no re-seed; trim Session W's required-binary
  list (`blkdiscard`, `systemd-run`, `dumpe2fs`, `debugfs` — a missing binary there counts as a FAILURE); delete LW1/LW1a/LW-P1/LW2/LW4/LW5/LW5c/LW6/LW7/LW8;
  rename `run_wipe_real` (no `CONFIRM_WIPE=1`). Re-measure `fixture-relative-assert.baseline.txt`.
- **Workflow suite** — jobs exactly `{preflight, cutover}`; `cutover` has no job-level `if:`; R-CENSUS
  becomes "no Hetzner write verb (`actions/detach`, `-X DELETE`/`DELETE /volumes`, labels `PUT`) in
  any step of the file", with a step-count floor; delete the wipe-wiring, api-body, T5 wipe-rehearsal
  and forget-parity rows; re-pin `WF_MIN_ASSERTIONS`.
- **Freeze T43**: 3 intentional exit-0 paths. **Staging T4h-c**: add `has '^EMIT_DRIFT clean_stray_mode_conflict$'`
  (today it asserts only `died`). **luks-monitor**: drop `wipe_aborted` from the closed-vocabulary
  loop; its pattern `outcome=${o}([;[:space:]]|$)` does not match the tombstone's literal
  `outcome=wipe_retired"`, so either widen the pattern to allow a closing quote or keep `wipe_retired`
  out of that list and pin the tombstone row in the rollback-refusal suite; the `${mode}` row pattern
  follows the `cleanup()` edit.
- **`workspaces-luks.test.sh`**: Guard B4 rows (`assert_holds` + `assert_mutation`). The predicates take
  a `server.tf` argument (the suite's `$TF` is `workspaces-luks.tf`); mutations of a `for_each` line use
  range-scoped sed (`/^resource "hcloud_volume_attachment" "workspaces"/,/^}/s/…/`) and assert the diff
  landed inside that block, because a file-wide `s///` rewrites both resources; H1 needs a helper that
  runs `assert_holds` on a sed-transformed copy; the new `lifecycle {}` must not carry `ignore_changes`
  (A9 greps the whole file); raise the minimum-cardinality floor (currently 26) by the rows added.
- **Workflow census (B3)**: scan each step as a whole (`json.dumps(step)`: `run`, `env`, `with`,
  `uses`), accept a quoted method (`hapi "DELETE"`), `--request=DELETE` and `hcloud volume
  (delete|detach)`, match within the step not per line; pin the step count exactly against an
  independent `grep -cE '^\s+(run|uses):'`.

### F. Records (D4)

**Fill now** from the run logs: target identity (`volume_id`, `size`, `target` ≠ `backing`,
`label=none`, `plaintext_dev`, fs UUID, `holders=0 dependents=0 device_units=7`), W8 capability fields,
`magic=53ef`, `io_max` (150000000 bytes/s — correct the template's "150M"), live header `uuid`,
`hdr_bytes`, `hdr_sha256`, W4 passed, `plaintext_only=0` (a new `plaintext_only_count` field; a
non-zero value at D is dispositioned by count before `complete`), provenance `last_mount`/`last_write`,
the copy's workspace count `8` (cutover log line), and the baseline `workspace_count=9 expected=8` —
each labelled "at rehearsal 36769782488 (2026-09-30)", never "at wipe time". **Mark PENDING:** D run
id(s) (several if `re_zero`/`detached` arms ran), the `result=wiped` row and its times, the read-back
result, the signature-after-zero row and the recoverability row (the template pre-fills both — they
become markers), detach action id, `204`/`404`, server volumes after, forget run id + `forgot=`, state
diff, approver (GitHub handle) + quoted go-ahead (`PENDING-EVIDENCE(go-ahead-rehearsal-match)` in case
it cites a later rehearsal), post-dispatch verify run, zero-complete and delete UTC times.

- **Destruction record**: stays `status: template` until `complete`; "What this file is" is marked
  superseded once fields are filled; "The act" moves to the past tense at `complete`; the deleted
  workflows and functions are cited by name at `59abf6a76c`, never by path on `main`. It states the
  sentinel consequence, and the durability limits (no backup or snapshot of `106443278`; escrow covers
  key loss, not data loss; console/API/CLI deletion is refused only while `delete_protection` holds;
  hardware loss stays open — #5274 / #8625). The "Other copies" row qualifies `git_data` (holds no
  repository per the #8634 record). Trigger (2) disposition: the copy was frozen 2026-07-23, before
  the first arm's-length onboarding on 2026-08-06, so the Art. 17 count is bounded to the owners of the
  8 frozen workspaces.
- **ADR-119**: `## Addendum (PENDING-EVIDENCE(D-date)): the plaintext backstop is retired (#6604 step 7,
  PR B)` — the as-run facts by reference to the record, the AP-009 basis (a superseded copy;
  `plaintext_only=0` at the rehearsal, so no workspace existed only there) and the accepted drop to a
  single copy with no backup (#5274/#8625), the tombstone, the kept Guard 5, D1, the sweeper/drift
  note, and that the gates naming `hcloud_volume(_attachment).workspaces["web-1"]` as must-be-untouched
  (`inngest-volume-recut-gate.sh`, `workspaces-luks-cutover-gate.sh`, `workspaces-luks-recut-gate.sh`,
  the post-apply loops) now pass vacuously on those names — safety holds through their
  `out_of_scope`/`resource_deletes` catch-alls and the loops' `create` verb; their comments are
  corrected (text only), and the web-1 birth gate fails closed on a rebirth. `status:` flips only in Hold step 3.
- **Legal registers (CLO wording constraints):** PA-1 (g)(17) and PA-2 (g)(21) in-cell correction +
  `**Superseded PENDING-EVIDENCE(D-date) (#6604)**`: "retained, attached and unmounted, from the
  2026-07-23 cutover (run 29995956562)", then, conditionally, "this marker takes effect only after the
  wipe dispatch D concludes with `delete_issued=true`: zero completed PENDING-EVIDENCE(zero-complete-UTC),
  read-back PENDING-EVIDENCE(readback), deleted PENDING-EVIDENCE(delete-UTC) (destruction record)" — a
  pending fact is never stated in the past tense without its marker.
  Name `hcloud_volume.workspaces["web-1"]` / Hetzner `105149570` — never "`hcloud_volume.workspaces` no
  longer exists" (web-2's instance remains, #6931). The stale "pending a soak blocked on #6808" clause
  reads "as recorded 2026-08-02; #6808 closed 2026-08-06; soak passed 2026-09-24". Erasure wording,
  carried as the wording proposed for attestation behind PENDING-EVIDENCE(recoverability-clo-attestation):
  "logically zeroed, verified by read-back; physical media reclamation per the Hetzner DPA" — never
  "erased" or "physically destroyed". Facts that fire only on merge (the narrowing, the deleted code,
  the Terraform protection, the ledger re-scope) read "on the merge of PR #9348"; the protection reads
  "Terraform declares …; effective after the SSH-stage apply".
- **Counsel review 6588**: superseded markers on the CURRENT DISPOSITION banner, §A3.5 and §A3.6, each
  conditional on D; `status:` kept verbatim until the evidence-fill commit, the post-attestation wording
  held in a `status_on_attestation_6604:` key that opens with PENDING-EVIDENCE(clo-attestation-6604)
  (ship's convention sets SIGNED-OFF only on a DISCHARGED attestation); `superseded_by` gains an
  appended, marked clause; a dated addendum; frontmatter `residual_cured:` (opens with a marker) scoped
  "DC-1 (web-1 retained copy, volume 105149570) only" (triggers (2)–(5) and the claim-decay trigger
  stand) and an `addendum_2026_10_01` pointer (the sibling `addendum_2026_09_21` shape);
  `accepted_residual` kept as history.
- **NFR register** Compute row's last sentence; **`expenses.md`** — the plaintext row stays `active`
  ("TO BE RETIRED by #6604 step 7 …", it still bills) until the deletion is evidenced, then `retired`;
  the LUKS row's id corrected, its "RAW/empty" text superseded 2026-10-01 (the cutover ran 2026-07-23),
  and its transition note resolved conditionally (replacement, no net-new, after D); **rationale runbook**, **`workspaces-luks.tf` comment**,
  **`model.c4`** (three descriptions, past tense) + `bash scripts/regenerate-c4-model.sh`.
- **Runbook**: step 7 → "RETIRED by PR #9348, once D and the forget have run" + a pointer to the
  destruction record + "the procedure as run is in git history at `59abf6a76c`" (proved by the release
  check's two `git diff --quiet` rows) + a read-only probe of the retired end state; Sequence 0 states that `prevent_destroy` now refuses the recut for the live
  volume; a dated "web-1 lost" note (attach `106443278` to a replacement host in the same location via
  the #6964 path; `prevent_destroy` is lifted only through a reviewed PR); the abort-triage
  `wipe_aborted` row → a `wipe_retired` row; the step-7 verdict table removed
  (its slugs no longer exist).
- **CLO audit file** `knowledge-base/legal/audits/2026-10-counsel-review-6604.md`: created in this
  pipeline with `status: BLOCKED (evidence pending)` and the per-artifact review of the draft; re-attested
  at Resume step 3 to `SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)` with
  `attests_at_commit:`, per-artifact verdicts (record, PA-1 (g)(17), PA-2 (g)(21), the 6588 addendum and
  keys, the ledger re-scope), the NFR row read for consistency, and a negative attestation that AC-B9's
  diff is empty. Any draft-time verdict reads BLOCKED, never SIGNED-OFF.

## Implementation Phases

1. **RED first** (`cq-write-failing-tests-before`): Guard B1–B4 rows against the current tree; record
   each RED reason (no `wipe_retired`; a `wipe` job present; `for_each = var.web_hosts`; no
   `prevent_destroy` on `workspaces_luks`).
2. **Code removal + tombstone** (B, C, D); `bash -n`, `shellcheck`, `actionlint` per file.
3. **Tests** (E); run every suite in AC-B1..B7; pin floors to measured counts.
4. **Terraform** (A); `terraform fmt -check`, `terraform validate`.
5. **Records + C4 + stale-premise sweep** (F); C4 suites green; draft-time CLO audit file.
6. **Ship to the hold**: push; PR body (`## PR Body (draft while held)`) with the base SHA and the
   resume prompt; `blocked` label; stop.

## Resume After the Hold

Run in a later session once Hold 1 and 2 are true; each command is an authorized go-ahead item or a
read-only check.

1. Capture `base=$(git merge-base HEAD origin/main)` (also printed in the PR body as the draft base
   SHA), then merge `origin/main`. If `git diff "$base"..origin/main -- apps/web-platform/infra/workspaces-cutover.sh .github/workflows/workspaces-luks-cutover.yml apps/web-platform/infra/workspaces-luks-wipe.test.sh apps/web-platform/infra/workspaces-luks-loopback.test.sh apps/web-platform/infra/workspaces-luks-cutover-workflow.test.sh`
   is non-empty, port each hunk deliberately (the stripped `git mv` likely falls below git's
   rename-similarity threshold, so a `main`-side edit to the old test surfaces as a modify/delete
   conflict whose "take deletion" loses it), diff every KEEP function body between the two SHAs, and
   re-run AC-B1..B3.
2. Read evidence (read-only): `gh run view <D-run> --log`, `gh run view <forget-run> --log`, the
   post-dispatch `workspaces-luks-verify.yml` run, and
   `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since "$(gh api repos/jikig-ai/soleur/actions/runs/<D-run>/attempts/1 --jq .run_started_at)" --grep SOLEUR_WORKSPACES_LUKS_WIPE --limit 500`
   (the window starts at D's start, an ISO-Z timestamp; a fixed `--since 1d` returns nothing, without
   error, once the fill runs more than a day after D). Replace every marker (Hold 3's
   `n/a (<arm>, run <id>)` rule).
3. CLO re-attests at that commit (`2026-10-counsel-review-6604.md` → SIGNED-OFF). Then destruction
   record → `status: complete`; commit. Then ADR-119 → `status: accepted`; commit.
4. Final PR body: `Ref #6604`, `Closes #6588` (the closing comment accounts for each #6588 acceptance
   criterion: web-2 → #6931, `git_data` → #6897); post the issue comments (`## Issue Comments`).
5. Re-run PR B's `infra-validation`; require green. Then the release check — it exits non-zero and
   names every failed check; proceed only on exit 0:

   ```bash
   # inputs: D=<dispatch run that printed the wiped row> F=<forget run>; R=jikig-ai/soleur
   rc=0; R=jikig-ai/soleur
   chk() { if "${@:2}"; then echo "ok $1"; else echo "FAIL $1"; rc=1; fi; }
   step() { gh run view "$1" --json jobs --jq ".jobs[] | select(.name==\"$2\") | .steps[] | select(.name==\"$3\") | .conclusion"; }
   # `gh run view --log` lines are `<job>\t<step>\t<ts> <message>`, and current gh prints `UNKNOWN STEP`
   # in the step column (verified on rehearsal 36769782488), so the log greps anchor on the JOB column;
   # step attribution comes from the `--json jobs` step-conclusion rows, which use the API step names.
   WIPED_RE=$'^wipe\t[^\t]*\t[^ ]+ SOLEUR_WORKSPACES_LUKS_WIPE feature=workspaces-luks op=workspaces-luks-wipe result=(wiped|already_wiped_detached) arm=[a-z_]+ volume_id=105149570( |$)'
   FORGOT_RE=$'^forget\t[^\t]*\t[^ ]+ (forgot [12] address\\(es\\): hcloud_volume|already_forgotten: neither web-1 plaintext address is in the state \\(serial [0-9]+\\))'
   # fixtures (synthesized lines in the real log shape): the regexes must match these, and must not
   # match the workflow's own echoed `run:` source, which gh prints with an ANSI prefix after the timestamp
   fx_w=$'wipe\tUNKNOWN STEP\t2000-01-01T00:00:00.0000000Z SOLEUR_WORKSPACES_LUKS_WIPE feature=workspaces-luks op=workspaces-luks-wipe result=wiped arm=first_wipe volume_id=105149570 bytes=1'
   fx_f=$'forget\tUNKNOWN STEP\t2000-01-01T00:00:00.0000000Z forgot 2 address(es): hcloud_volume.workspaces["web-1"] hcloud_volume_attachment.workspaces["web-1"] (serial 1 -> 2, lineage unchanged)'
   fx_src=$'wipe\tUNKNOWN STEP\t2000-01-01T00:00:00.0000000Z \e[36;1m  ROW_RE=\'^SOLEUR_WORKSPACES_LUKS_WIPE feature=workspaces-luks op=workspaces-luks-wipe result=(wiped|already_wiped_detached) arm=[a-z_]+ volume_id=105149570 \''
   chk "fixture: wiped-row regex matches the log shape" test "$(printf '%s\n' "$fx_w" | grep -cE "$WIPED_RE")" = 1
   chk "fixture: forget regex matches the log shape" test "$(printf '%s\n' "$fx_f" | grep -cE "$FORGOT_RE")" = 1
   chk "fixture: echoed run: source never counts" test "$(printf '%s\n' "$fx_src" | grep -cE "$WIPED_RE")" = 0
   # bind the run ids to the right workflow, branch and event (operator-typed ids are otherwise unchecked)
   chk "D is the cutover workflow on main" test "$(gh api repos/$R/actions/runs/$D --jq '[.path,.head_branch,.event]|join(" ")')" = ".github/workflows/workspaces-luks-cutover.yml main workflow_dispatch"
   chk "F is the forget workflow on main" test "$(gh api repos/$R/actions/runs/$F --jq '[.path,.head_branch,.event]|join(" ")')" = ".github/workflows/workspaces-plaintext-forget.yml main workflow_dispatch"
   # the records cite 59abf6a76c as "the procedure as run": prove D and F ran that code
   git fetch -q origin main
   Dsha=$(gh api repos/$R/actions/runs/$D --jq .head_sha); Fsha=$(gh api repos/$R/actions/runs/$F --jq .head_sha)
   chk "D ran the cited code (59abf6a76c)" git diff --quiet 59abf6a76c "$Dsha" -- apps/web-platform/infra/workspaces-cutover.sh .github/workflows/workspaces-luks-cutover.yml
   chk "F ran the cited code (59abf6a76c)" git diff --quiet 59abf6a76c "$Fsha" -- .github/workflows/workspaces-plaintext-forget.yml
   # the host step's own exactly-one, pin- and api_state-matched row parser is the gate; read its conclusion
   chk "host wipe step green" test "$(step "$D" wipe 'Run the plaintext wipe on web-1')" = success
   chk "one wiped row, from the wipe job" test "$(gh run view "$D" --log | grep -cE "$WIPED_RE")" = 1
   # deletion: the D API step, or (D died after DELETE) the forget's presence-proven gone step
   chk "volume deleted" sh -c "[ \"\$(gh run view $D --json jobs --jq '.jobs[]|select(.name==\"wipe\")|.steps[]|select(.name==\"Detach and delete the plaintext volume (Hetzner API)\")|.conclusion')\" = success ] || gh run view $F --json jobs --jq '.jobs[].steps[]|select(.name|startswith(\"Prove the pinned volume is gone\"))|.conclusion' | grep -qx success"
   chk "forget step green" test "$(gh run view "$F" --json jobs --jq '.jobs[].steps[] | select(.name=="Forget the retired plaintext addresses") | .conclusion')" = success
   chk "forget output, from the forget job" test "$(gh run view "$F" --log | grep -cE "$FORGOT_RE")" -ge 1   # already_forgotten must also be traced (Hold 2)
   chk "no markers in tree" test -z "$(git grep -n 'PENDING-EVIDENCE(' HEAD -- . ':!knowledge-base/project/')"
   chk "no markers in PR body" test "$(gh pr view 9348 --json body -q .body | grep -c 'PENDING-EVIDENCE(')" = 0
   rec=$(git log -1 --format=%H -G'^status: complete$' -- knowledge-base/legal/audits/workspaces-plaintext-destruction-record.md)
   adr=$(git log -1 --format=%H -G'^status: accepted$' -- knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md)
   chk "record flip is an addition" sh -c "git show $rec:knowledge-base/legal/audits/workspaces-plaintext-destruction-record.md | grep -qx 'status: complete'"
   chk "ADR flip is an addition" sh -c "git show $adr:knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md | grep -qx 'status: accepted'"
   chk "record before ADR (branch history, pre-squash)" sh -c "[ -n '$rec' ] && [ -n '$adr' ] && [ '$rec' != '$adr' ] && git merge-base --is-ancestor $rec $adr"
   echo "forget run updated_at (the 48 h bound runs from here): $(gh api repos/$R/actions/runs/$F --jq .updated_at)"
   exit $rc
   ```

   The `--json jobs` step names are those of the workflows on `main` at the runs' SHAs (the two
   `git diff --quiet` rows prove those are `59abf6a76c`'s); if renamed, re-read them before trusting a
   `FAIL`. The log greps no longer depend on step names; the three fixture rows prove their regexes
   against the real line shape before any live row is read. The work phase dry-runs this block's syntax with `bash -n`. If D printed
   `plaintext_only>0`, its `plaintext_only_name` rows put workspace ids into a public Actions log: after
   the evidence is captured, delete that run's logs (`gh api -X DELETE repos/$R/actions/runs/$D/logs`,
   a go-ahead item) and record it in the CLO audit. Then `gh pr edit 9348 --remove-label blocked`,
   `gh pr ready 9348`, merge.
6. Post-merge, first a read-only gate: dispatch `scheduled-terraform-drift.yml` and require its plan to
   list exactly the `delete_protection` in-place update on `hcloud_volume.workspaces_luks` plus the
   changes enumerated from `git log <pause-sha>..main -- apps/web-platform/infra` (the SSH stage that
   delivers the update runs `-auto-approve` with no destroy-guard, and it would carry any change merged
   during the pause — a `server_type` edit reboots web-1). Halt on anything else. Then, only after
   `git merge-base --is-ancestor <merge-sha> origin/main` (until then
   `scheduled-terraform-drift.yml` reporting `+create` of the two web-1 addresses is the EXPECTED window
   state — never "fix" it): `gh workflow enable apply-web-platform-infra.yml`,
   `gh workflow enable apply-deploy-pipeline-fix.yml`,
   `gh workflow run apply-web-platform-infra.yml -f reason='#6604 post-PR-B apply'` (its plan names no
   `hcloud_volume(_attachment).workspaces["web-1"]` address, and one in-place update of
   `hcloud_volume.workspaces_luks` for `delete_protection` — it is NOT in the saved plan's `Plan:` line;
   require the step "Terraform apply (SSH-provisioned resources, over the bridge)" to conclude `success`
   (it is skipped green when `ssh_token_gate` finds `CI_SSH_ACCESS_TOKEN_ID` absent) and its log to
   show `hcloud_volume.workspaces_luks: Modifications complete`); `apply-deploy-pipeline-fix.yml` too if
   `git log <pause-sha>..main` (the `main` SHA when the pause began, recorded in the D go-ahead) touched
   its `paths:`; then `scheduled-terraform-drift.yml` green. The `delete_protection` update lands with the
   first `apply`-job run after the re-enable, push or `manual-rerun`, whichever comes first; the drift
   gate above makes either order safe. Then the soak-side probe, read-only, which must print two `ok`
   rows before the #6604 soak follow-through may PASS (a resume session that dies after the merge must
   not leave either workflow `disabled_manually` while the sweeper closes #6604):

   ```bash
   for wf in apply-web-platform-infra.yml apply-deploy-pipeline-fix.yml; do
     st=$(gh api "repos/jikig-ai/soleur/actions/workflows/$wf" --jq .state)
     if [ "$st" = active ]; then echo "ok $wf active"; else echo "FAIL $wf state=$st"; fi
   done
   ```

   `scripts/followthroughs/workspaces-luks-soak-6604.sh` does not read either workflow's state
   (checked 2026-10-01). The same two reads belong in it as PASS preconditions, so a FAIL row keeps
   #6604 open; until that probe change lands, this block is part of AC-H5 and is run before the
   sweeper's first sweep after the merge.

## Files to Edit

- `apps/web-platform/infra/server.tf` — local, both `for_each`s, web-1 sentinel, comments.
- `apps/web-platform/infra/workspaces-luks.tf` — `delete_protection` + `prevent_destroy` on
  `hcloud_volume.workspaces_luks`; the "live hazard" comment.
- `apps/web-platform/infra/workspaces-cutover.sh` — remove the wipe; tombstone; `cleanup()`; comments.
- `.github/workflows/workspaces-luks-cutover.yml` — remove the wipe wiring.
- `apps/web-platform/infra/workspaces-luks-cutover-workflow.test.sh`, `workspaces-luks-loopback.test.sh`,
  `workspaces-luks-freeze.test.sh`, `workspaces-luks.test.sh`, `luks-monitor.test.sh`.
- `tests/scripts/test-infra-privileged-tier-census.sh`, `scripts/guard-vacuity-floor.test.sh`,
  `plugins/soleur/test/fixture-relative-assert.baseline.txt`, `plugins/soleur/test/terraform-target-parity.test.ts` (comment).
- Stale-premise text: `tests/scripts/lib/workspaces-luks-recut-gate.sh`, `tests/scripts/lib/inngest-volume-recut-gate.sh`,
  `tests/scripts/lib/workspaces-luks-cutover-gate.sh`, `tests/scripts/lib/web-host-replace-gate.sh`,
  `.github/workflows/apply-web-platform-infra.yml`, `.github/workflows/apply-deploy-pipeline-fix.yml`,
  `knowledge-base/engineering/architecture/decisions/ADR-148-web-host-replacement-is-a-distinct-gated-dispatch.md`,
  `knowledge-base/engineering/architecture/decisions/ADR-143-active-active-web-ingress-drain-gated-host-lifecycle.md`
  (dated §Consequences addendum, review fix).
- `scripts/encryption-posture-ledger.json` — `hcloud_volume.workspaces` row re-scoped to web-2 in its
  prose fields only: `store` stays byte-exact `hcloud_volume.workspaces` (`lint-encryption-posture.py`
  matches it against resource addresses), `device_binding.mapper` stays as is (resolved only for `luks`
  rows), evidence becomes a content anchor instead of `server.tf:1569`, `tracking_issue: "#6931"`,
  `expires_on: 2026-12-29`.
- `knowledge-base/legal/audits/workspaces-plaintext-destruction-record.md`,
  `knowledge-base/legal/article-30-register.md`, `knowledge-base/legal/audits/2026-07-counsel-review-6588.md`.
- `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md`,
  `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`,
  `knowledge-base/engineering/architecture/nfr-register.md`.
- `knowledge-base/operations/expenses.md`.
- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`,
  `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md`.
- `knowledge-base/engineering/architecture/diagrams/model.c4`, `model.likec4.json` (regenerated).

**Pre-existing, filed not fixed (security P2-2, `wg-when-an-audit-identifies-pre-existing`):** after
the `wipe` job goes, no step of `workspaces-luks-cutover.yml` needs a Hetzner write token, yet the
`cutover` job's `LUKS_DEV` resolution still falls back from `HCLOUD_TOKEN_READONLY` to `HCLOUD_TOKEN`
(Doppler `prd_terraform` holds no read-only token yet — ADR-241's O-steps). The work phase files one
issue: require the read-only token only once it is provisioned, narrow the census allowance, and check
(read-only) whether `DOPPLER_TOKEN_INFRA_PRIVILEGED` is scoped to the `workspaces-luks-cutover`
environment and is now unused. Milestone per the roadmap; referenced in the PR body.

## Files to Create

- `apps/web-platform/infra/workspaces-luks-rollback-refusal.test.sh` — by `git mv` (D3).
- `knowledge-base/legal/audits/2026-10-counsel-review-6604.md` — the CLO audit (BLOCKED → SIGNED-OFF).
- `knowledge-base/project/specs/feat-one-shot-6604-plaintext-wipe-pr-b/decision-challenges.md` (exists).

## Files to Delete

- `.github/workflows/workspaces-plaintext-forget.yml`
- `apps/web-platform/infra/workspaces-plaintext-forget-workflow.test.sh`

## Open Code-Review Overlap

1 open scope-out touches these files (87 open `code-review` issues scanned 2026-10-01 against every path
in Files to Edit/Create/Delete):

- **#2197** (billing `SubscriptionStatus` type / throttle doc / Sentry breadcrumb policy) names
  `apps/web-platform/infra/server.tf`. **Acknowledge** — an unrelated region; this PR edits only the two
  workspaces `for_each`s, one `locals` map and one `templatefile` argument there.

## Infrastructure (IaC)

### Terraform changes

`server.tf` (a `locals` map, two `for_each`s, one `templatefile` argument) and `workspaces-luks.tf`
(`delete_protection = true`, `lifecycle { prevent_destroy = true }`). No provider, variable, secret or
new resource. No `removed {}`/`moved {}`: the two `["web-1"]` addresses leave state through the forget
run's `terraform state rm`, which is why this PR's plan is red until then.

### Apply path

Nothing applies on merge: both push-apply workflows are disabled from before D until after it. The
first `apply`-job run after the re-enable — the post-merge `manual-rerun` of
`apply-web-platform-infra.yml` (Resume step 6), or a push if one lands first — applies `main`: no
`hcloud_volume(_attachment).workspaces["web-1"]` address, no change to web-2's volume, one in-place
`delete_protection` update on `hcloud_volume.workspaces_luks` (SSH stage, through
`terraform_data.workspaces_boot_unlock_install`). No `-replace`, no host re-provision, no reboot; expected
downtime zero (the merge fires only the routine container release).

### Distinctness / drift safeguards

- `prevent_destroy` stays on `hcloud_volume.workspaces` (web-2) and is added to `hcloud_volume.workspaces_luks`.
- Guard B4 pins the narrowing, the sentinel and both protections.
- `scheduled-terraform-drift.yml` is the post-merge check: green, no workspaces web-1 address, no
  pending `delete_protection` update.

### Vendor-tier reality check

Hetzner volume `delete_protection` is a free attribute (`POST /volumes/{id}/actions/change_protection`);
Hetzner bills a deleted volume to the hour; no snapshot exists to clean up.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-119** (no new ADR): the dated addendum (§F) records the as-run retirement, the tombstone,
the kept Guard 5, D1 (Terraform protection of the sole copy, superseding the deferral of its
`prevent_destroy` to #6931 and retiring the recut `-replace` for the live volume) and the durability
limits; then `status: accepted` (Hold 3). **ADR-241** D2: the forget note gains "(deleted by #6604 PR B
after its one run)". **ADR-148**: one dated note that the web-1 refusal's "plaintext by-id pin" reason
is superseded (web-1 now receives the sentinel); the refusal stands on its other grounds; and a web-1
host-replace plan now fails closed on the LUKS volume's and attachment's `prevent_destroy`, so a
deliberate replacement needs a PR that relaxes it. **ADR-143**: a dated addendum to §Consequences —
`hcloud_volume.workspaces_luks` now carries `prevent_destroy` (the #6931 deferral is superseded), and
its "absent from the push `-target` allow-list" interim guard was never sufficient: the volume is in
the SSH stage's `-auto-approve` closure through `terraform_data.workspaces_boot_unlock_install`.

### C4 views

All three files read (`model.c4`, `views.c4`, `spec.c4`). Actors and systems involved — `github`
(system), `hetzner` (container "Compute"), `cloudflare` (system), `workspacesVolume` (database) — are
modeled and stay; no external human actor, no new system, no access relationship changes. Description
edits only: `workspacesVolume` (the retained plaintext copy is gone; the LUKS volume is the sole copy,
delete-protected), `hetzner -> cloudflare` (the W5 header download happened during step 7 and is
retired), `github -> hetzner` (the `wipe` job's detach/delete and the forget workflow ran once and are
deleted). `views.c4` unchanged. Validation: `c4-code-syntax`, `c4-render`, `c4-canonical` (byte-diff of
the regenerated `model.likec4.json`) and `plugins/soleur/test/c4-count-parity.test.sh` (edge-prose
cardinalities, e.g. a workflow count on `github -> hetzner`).

### Sequencing

The addendum is written now; the status flip waits for the evidence (Hold 3). Neither is deferred.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Delete `CONFIRM_WIPE` entirely | A stray value would reach the L3 cutover body; T4h-c would need rewriting. The tombstone is six lines. |
| Move Guard-5 rows into `workspaces-luks-freeze.test.sh` | Re-plumbs `TGT_BLK`/`LUKS_BLK`/`G5D_*` into a 1,660-line suite; `git mv` keeps them and their history. |
| A recut-gate `sole_copy_targeted` refusal for `106443278` (plan v1) | Covers one path, hard-codes an id; `prevent_destroy` covers every plan, id-agnostic. |
| A Hetzner API `change_protection` call for `106443278` | A production write outside Terraform; `delete_protection = true` in config delivers the same through the post-merge apply. |
| Split the `server.tf` narrowing into its own PR, or replace the forget with `removed {}` (advisor) | `removed {}` cannot take instance keys, and `moved`+`removed` makes every `-target`ed plan fail until an untargeted apply this root never runs (archived plan, reproduced on 1.10.5); the pause covers the window and D6 keeps it to hours. |
| Mark PR B ready and rely on `infra-validation` red | Not a required check; only the draft and the hold block a premature merge. |
| `Closes #6604` in the final body | Denied by the follow-through merge gate; bypassing it skips the soak (D5). |
| Flip ADR-119 to `accepted` in the draft | Breaks the record-first order and, merged early, would let the sweeper close #6604 on no evidence. |

## User-Brand Impact

- **If this lands broken, the user experiences:** every user's workspaces unreachable on
  app.soleur.ai (web-1 is the sole origin) if a KEEP-set regression lets a later `rollback=true`
  dispatch or a dead-man fire unmount the LUKS mapper — after step 7 there is no plaintext copy to
  remount.
- **If this lands broken, the user experiences:** permanent loss of every workspace if volume
  `106443278` is destroyed (a recut `-replace`, a ForceNew edit through the SSH stage's unguarded
  apply, or a console/API/CLI delete). `prevent_destroy` + `delete_protection` close those paths;
  hardware loss stays open — there is no backup or snapshot (#5274, #8625), stated in the ADR addendum.
- **If this lands broken, the user experiences:** an interrupted wipe that can never be finished —
  a partly-zeroed plaintext copy of every workspace left attached to web-1 — if PR B merges before D
  concludes (the merge deletes the only resume code). The hold prevents it.
- **If this lands broken, the user experiences:** no fix of any kind reaching app.soleur.ai if PR B
  merges after D but before the forget — every push apply then fails on `prevent_destroy` until the
  state is reconciled, and the forget workflow is already deleted (a partial revert PR that keeps the
  sole-copy protections is the only route; `## Operator Holds`).
- **If this lands broken, the user experiences:** a full outage if web-1 is ever rebuilt — the
  sentinel makes its first boot emit `workspaces_mount fatal` and keep booting on an empty
  `/mnt/data` (`ci-deploy.sh` has no mapper check, so writes would land on the root disk and be shadowed
  once the mapper mounts). Unreachable while the replace path refuses web-1; the #9179 fstab writer
  (`workspaces_boot_unlock_fstab_writer`) comments out every pre-existing `/mnt/data` line, so the
  sentinel line cannot shadow it; a web-1 rebirth is the existing residual tracked in #6964, and the
  runbook gains a dated "web-1 lost" note (attach `106443278` to a replacement host in hel1; lift
  `prevent_destroy` only through a reviewed PR).
- **If this lands broken, the user experiences:** a fresh, empty plaintext volume attached to web-1
  after the next apply if the narrowing regresses (Guard B4).
- **If this leaks, the user's data is exposed via:** a public record (ADR, register, PR body,
  destruction record) naming workspace ids, user names or commit-author emails — every personal-data
  field is a COUNT only; `plaintext_only_name` rows are never copied; the approver is a GitHub handle.
- **If this leaks, the user's data is exposed via:** a record asserting erasure that did not happen —
  every unmeasured field is a `PENDING-EVIDENCE(` marker, the hold blocks merge until each is replaced
  from the run's own output, and erasure is worded "logically zeroed, verified by read-back".
- **Brand-survival threshold:** `single-user incident`

CPO sign-off: **granted with conditions** (Domain Review). `soleur:engineering:review:user-impact-reviewer`
runs at review time.

## Observability

Layers per `hr-observability-layer-citation`: **workflow run log** (layer 6), **vector → Better Stack**
(layer 3, the `luks-monitor` tag via `_deadman_row`), **Sentry** via `emit_drift`
(`sentry_alert.workspaces_luks_drift`, keyed on the op).

```yaml
liveness_signal:
  what: the SOLEUR_WORKSPACES_LUKS_DEADMAN result=cutover_aborted outcome=wipe_retired row (tombstone), the kept outcome=refused_plaintext_wiped / refused_plaintext_record_gone rows, and the dead-man fire's result=fail reason=refused_plaintext_* rows (Guard 5)
  cadence: per dispatch of workspaces-luks-cutover.yml (rollback, or a stray CONFIRM_WIPE); the dead-man fire only if a freeze ever arms one again
  alert_target: the failed-run notification to the dispatcher (layer 6); Sentry workspaces-luks-drift for every Guard-5 refusal
  configured_in: apps/web-platform/infra/workspaces-cutover.sh (tombstone block, _rollback_refuse, rollback(), arm_dead_man gone_guard); apps/web-platform/infra/vector.toml (luks-monitor SYSLOG_IDENTIFIER)

error_reporting:
  destination: Sentry via emit_drift -> workspaces_luks_emit (Guard-5 refusals); the workflow run log for the tombstone (deliberately no Sentry event)
  fail_loud: the tombstone writes its outcome row, drops the EXIT trap and dies non-zero before any mutation; Guard-5 refusals emit_drift, write one outcome row and die before any umount/close/stop

failure_modes:
  - mode: a later edit removes or weakens Guard 5 and a rollback unmounts the sole copy
    detection: workspaces-luks-rollback-refusal.test.sh G5/G5b/G5c/G5d rows and loopback Session G5 (infra-validation deploy-script-tests, layer 6)
    alert_route: red CI on the PR that makes the edit
  - mode: a stray CONFIRM_WIPE=1 reaches the host
    detection: the outcome=wipe_retired row in the workflow run log (layer 6) and on the luks-monitor tag (layer 3)
    alert_route: failed run to the dispatcher
  - mode: a plan would destroy or replace the sole-copy LUKS volume
    detection: terraform plan fails with Instance cannot be destroyed (prevent_destroy) in the run log of whichever apply or infra-validation job planned it (layer 6)
    alert_route: failed run; nothing applied
  - mode: a push apply plans a fresh plaintext volume for web-1 (narrowing regressed, or merged before the forget)
    detection: Guard B4 in workspaces-luks.test.sh (CI, layer 6); scheduled-terraform-drift.yml workflow run log (layer 6) naming hcloud_volume.workspaces["web-1"], plus its drift issue
    alert_route: red CI; the drift issue
  - mode: the apply workflows stay disabled because PR B is not resumed, or after its merge
    detection: scheduled-terraform-drift.yml workflow run log (layer 6) reports every unapplied infra merge; Resume step 6 reads gh workflow view --json state for both; the 48 h post-forget bound and the abandon branch's 2026-10-15 decision point
    alert_route: the drift issue; the #6604 escalation comment
  - mode: delete_protection on 106443278 not applied, or lifted outside Terraform
    detection: scheduled-terraform-drift.yml workflow run log (layer 6) shows a pending delete_protection update; AC-H5's read-only GET reads protection.delete
    alert_route: the drift issue; the AC-H5 check in the resume session
  - mode: a rebuilt web-1 boots on the sentinel (unreachable while the replace path refuses web-1)
    detection: soleur-boot-emit workspaces_mount fatal from cloud-init.yml (the host boot-emit sink, layer 3) and the web-1 Better Stack uptime monitor
    alert_route: the boot-emit Sentry/Better Stack route; recovery per #6964

logs:
  where: workflow run logs (workspaces-luks-cutover.yml, apply-web-platform-infra.yml); web-1 syslog tag luks-monitor -> vector -> Better Stack
  retention: Actions logs 90 days; Better Stack per the source's retention

discoverability_test:
  command: grep -c -e 'result=cutover_aborted outcome=wipe_retired"' apps/web-platform/infra/workspaces-cutover.sh
  expected_output: "1"
```

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.workspaces (web-2 instance only, volume 106466179, after this PR)
    mechanism: plaintext-exception
    evidence: apps/web-platform/infra/server.tf — resource "hcloud_volume" "workspaces" (format = "ext4", for_each = local.plaintext_workspaces_hosts, no LUKS apparatus)
    defends_against: nothing at the volume layer; the volume is intended to be empty (web-2 carries serving-weight 0; contents unprobed, #6931)
    does_not_defend: any workspace data written to web-2 before its fresh-boot guest-side LUKS path (#6931) lands
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:no probe reads web-2's volume contents; tracked #6931
  - store: hcloud_volume.workspaces_luks (web-1 /workspaces, volume 106443278 — the sole copy after step 7)
    mechanism: luks
    evidence: unchanged ledger row (device_binding to the workspaces mapper); this PR adds delete_protection and prevent_destroy (workspaces-luks.tf)
    defends_against: a seized, RMA'd or snapshot-imaged Hetzner block volume
    does_not_defend: an app-layer read on the unlocked live host, a leaked WORKSPACES_LUKS_KEY, root on web-1, or the loss of the volume itself (no second copy, no backup — #5274/#8625)
    disclosed_as: docs/legal/privacy-policy.md (the LUKS clause re-scoped by #6938; unchanged here)
    live_verification: available
in_transit: []   # this PR adds and changes no connection; it REMOVES the wipe job's runner -> api.hetzner.cloud write path
exception:
  justification: web-2's per-host workspaces volume stays plaintext because the fresh-host guest-side LUKS path is deferred; it takes no traffic (serving-weight 0) and is intended to be empty, though no probe reads its contents
  tracking_issue: "#6931"
  reevaluate_when: web-2 gains the fresh-boot LUKS path (#6931) or takes any serving weight
  expires_on: 2026-12-29
```

## Guard Contract

Each matrix row is a case in the named suite.

### Guard B1 — a retired `CONFIRM_WIPE` never wipes and never falls through

**Property.** A `workspaces-cutover.sh` run with `CONFIRM_WIPE=1` (with `DRY_RUN=0` or `1`) performs no
host mutation, emits no drift event, exits non-zero, and never reaches the L3 cutover body, with
exactly one `outcome=wipe_retired` row; a non-`0|1` value (`true`, `" 1"`) is refused, never ignored.

**Assembly.** The main body between `trap cleanup EXIT` and `step "L3 gates` (the MAIN_PREFIX
extraction, run through the harness `run_case` with `echo FELL_THROUGH_TO_L3` appended):
`assert_mode_exclusive` (counts `CONFIRM_WIPE` by the string `1` only — it does not validate), the
ROLLBACK block, the CLEAN_STRAY block, the tombstone (fires on any value other than unset/`0`).

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | delete the tombstone block from the prefix | RED — `FELL_THROUGH_TO_L3` printed, no `wipe_retired` row |
| 2 | the tombstone ends `RUN_COMPLETE=1; exit 0` instead of `die` (precondition holds, property fails) | RED — rc 0 |
| 3 | the tombstone calls `emit_drift` | RED — `has '^EMIT_DRIFT'` |
| 4 | drop `trap - EXIT` | RED — `cleanup()` adds a second `result=cutover_aborted` row (exactly one required) |
| 5 | gate the tombstone on `DRY_RUN=1` (the `DRY_RUN=0` case is the second member) | RED — the `DRY_RUN=0` row falls through |
| 6 | the tombstone tests `= "1"` instead of `!= "0"` | RED — the `CONFIRM_WIPE=true` and `CONFIRM_WIPE=" 1"` rows fall through |
| 7 | `assert_mode_exclusive` stops counting `CONFIRM_WIPE` | RED (staging T4h-c) |
| H1 | must-PASS: `CONFIRM_WIPE` unset reaches `FELL_THROUGH_TO_L3` | GREEN |
| H2 | harness: the MAIN_PREFIX extraction is empty or fails `bash -n` | RED (instrument row) |

### Guard B2 — Guard 5 survives the removal

**Property.** Once `PLAINTEXT_WIPE_BEGUN` or `PLAINTEXT_WIPED` is persisted, or `/mnt/data` is on the
mapper with the recorded `PLAINTEXT_DEV` not an intact ext4, no ROLLBACK run, `cleanup()` rollback or
dead-man fire performs `umount`, `cryptsetup close` or `docker stop`, regardless of
`ROLLBACK_ACK_LUKS_WRITES`.

**Assembly.** Three entry points, one predicate: `assert_rollback_not_post_cutover` (ROLLBACK mode),
`rollback()`'s first line (every caller, incl. `cleanup()`), the `gone_guard` baked into the dead-man
fire; all read `_plaintext_gone` / `_plaintext_record_status`; the record is written by the
rollback-rehearsal step. Rows are the existing G5, G5b-*, G5c, G5d-*, G1-W, F6, F7, F11, S5 (re-scoped),
S6 (moved, not rewritten) plus loopback LW-P2/P3/P4.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | move the check after the `ROLLBACK_ACK_LUKS_WRITES` short-circuit (REORDER) | RED (G5 ack=1 row) |
| 2 | key the marker witness on `PLAINTEXT_WIPED` only | RED (BEGUN-only row) |
| 3 | delete `rollback()`'s first-line refusal (second entry point, first compliant) | RED (G5c) |
| 4 | delete the marker clause from `gone_guard` | RED (G5d, executed fire) |
| 5 | the rollback-rehearsal step stops persisting `PLAINTEXT_DEV` | RED (G5-W) |
| H1 | must-PASS: mapper mounted, record intact ext4, no marker → NOT refused | GREEN (G5b-H1, LW-P2) |
| H2 | harness: the G5 section's calls deleted | RED (the literal `-lt` floor at the measured count) |

### Guard B3 — no destructive Hetzner path remains in the cutover workflow

**Property.** No step of `workspaces-luks-cutover.yml` can detach, delete or relabel a volume, and the
file's jobs are exactly `{preflight, cutover}`.

**Assembly.** Every job and every step `run:` in the file — the census walks all of them, not one job,
and matches HTTP method tokens (`DELETE`, `PUT`, `POST`) near `/volumes` and
`/actions/(detach|attach|change_protection)`, not only a `curl -X` spelling.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | add `hapi DELETE "/volumes/${PIN}"` (the deleted code's own verbatim shape) to the `cutover` run step | RED |
| 2 | add `hapi POST "/volumes/${PIN}/actions/detach"` to `preflight` (second member, `cutover` compliant) | RED |
| 3 | re-add a job named `wipe` | RED (job set) |
| 4 | re-add a job-level `if:` to `cutover` | RED |
| 5 | own dispatch: the census scans fewer steps than the independent count | RED (exact step floor) |
| H1 | must-PASS: the read-only `LUKS_DEV` resolution GET in `cutover` | GREEN (a GET is not a write) |

### Guard B4 — the Terraform pins: web-1 has no plaintext volume, the sole copy cannot be destroyed

**Property.** In `server.tf` both workspaces `for_each`s range over a map that excludes `web-1` and
web-1's `workspaces_volume_id` is `"retired-6604"`; in `workspaces-luks.tf`
`hcloud_volume.workspaces_luks` carries `delete_protection = true` and `prevent_destroy = true`.

**Assembly.** The three resource blocks and the `hcloud_server.web` templatefile argument, located by
content anchor inside the block (never column 0), plus the `local.plaintext_workspaces_hosts`
definition.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | `for_each = var.web_hosts` on the volume (range-scoped sed) | RED |
| 2 | the same on the attachment only, volume compliant (second member; diff asserted inside that block) | RED |
| 3 | the local filters `k != "web-2"` instead of `"web-1"` | RED |
| 4 | `workspaces_volume_id = hcloud_volume.workspaces[each.key].id` (sentinel reverted) | RED |
| 5 | `prevent_destroy = false` (token present, property false) | RED |
| 6 | `delete_protection = false` | RED |
| 7 | own dispatch: a resource block renamed so it is not found | RED (block-absent guard, never a pass) |
| H1 | must-PASS: the same lines with extra spacing and a trailing comment | GREEN |

## Acceptance Criteria

### Pre-merge (this pipeline — draft)

- [ ] **AC-B1** Guard B1 rows green in `workspaces-luks-rollback-refusal.test.sh`; T4h-c green unchanged.
- [ ] **AC-B2** Guard B2: the moved G5/G5b/G5c/G5d/G5-W rows green (floor at the measured count);
      loopback Session G5 green under `sudo` in CI; `tests/scripts/test-workspaces-luks-cutover-gate.sh`
      green unchanged (`EXPECTED_ASSERTIONS=34`); a `cleanup()` abort emits exactly one outcome row
      with no `mode=`.
- [ ] **AC-B3** Guard B3 green; `workspaces-luks-cutover-workflow.test.sh` re-pinned; H17 green
      unchanged; `actionlint` clean.
- [ ] **AC-B4** Guard B4 green in `workspaces-luks.test.sh`.
- [ ] **AC-B5** `git grep -nE '(^|[^A-Za-z0-9_])(wipe_plaintext|emit_wipe|WIPE_IO_GATE|_wipe_[a-z]+|expected_plaintext_volume_id)|workspaces-plaintext-forget' -- apps/web-platform/infra/workspaces-cutover.sh .github/workflows/`
      returns only comment lines that say they are historical (production files only — test files
      legitimately name the retired tokens in their negative rows), and `grep -c CONFIRM_WIPE
      apps/web-platform/infra/workspaces-cutover.sh` equals the count measured after the edit
      (declaration, `assert_mode_exclusive`, tombstone, comments).
- [ ] **AC-B6** `git grep -n -i -e 'live plaintext' -e 'NO prevent_destroy' -- .github tests apps/web-platform/infra`
      returns only lines that say they are historical (known hits today:
      `apply-web-platform-infra.yml` ~4405, `web-host-replace-gate.sh` ~60/124,
      `workspaces-luks-recut-gate.sh` ~18/53/176, `workspaces-luks-cutover-gate.sh` ~36/137,
      `inngest-volume-recut-gate.sh` ~254, the header of `tests/scripts/test-workspaces-luks-cutover-gate.sh`
      — text only; that suite's `EXPECTED_ASSERTIONS=34` does not move).
- [ ] **AC-B7** Green: `workspaces-luks-freeze.test.sh` (T43 = 3), `-staging`, `-verify`,
      `-g4-mutation`, `luks-monitor.test.sh`, `web-1-swap-concurrency-parity.test.sh`,
      `test-infra-privileged-tier-census.sh`, `test-destroy-guard-counter-web-platform.sh`,
      `test-workspaces-luks-recut-gate.sh`, `scripts/guard-vacuity-floor.test.sh`, `fixture-relative-assert`,
      `terraform-target-parity.test.ts`, `scripts/lint-encryption-posture.py` (re-scoped row),
      `c4-code-syntax`, `c4-render`, `c4-canonical`, `c4-count-parity`, `terraform fmt -check` +
      `validate`, `scripts/lint-infra-no-human-steps.py --changed`.
- [ ] **AC-B8** Records carry real values for every field the rehearsal, baseline and cutover logs
      supply and a `PENDING-EVIDENCE(<field>)` marker for every other; counts only for personal data;
      the destruction record stays `status: template`, ADR-119 `status: adopting`, the CLO audit file
      `status: BLOCKED (evidence pending)`.
- [ ] **AC-B9** `git diff --name-only origin/main...HEAD -- docs/legal/ plugins/soleur/docs/pages/legal/ knowledge-base/legal/audits/2026-09-counsel-review-8248.md`
      is empty.
- [ ] **AC-B10** PR #9348 stays draft with the `blocked` label; body carries `Ref #6604`, `Ref #6588`,
      labels `semver:patch` + `app:web-platform`, the merge-alone answer on its first line, the base SHA,
      the hold and the resume prompt.

### Hold release (later session)

- [ ] **AC-H1** Hold 1 holds (the wiped row; the deletion step or the forget's gone step `success`).
- [ ] **AC-H2** Hold 2 holds (`forgot=2`/`1`, or a traced `already_forgotten`).
- [ ] **AC-H3** `git grep -n 'PENDING-EVIDENCE(' HEAD -- . ':!knowledge-base/project/'` returns
      nothing, the PR body and issue-comment drafts carry no marker, the CLO audit reads SIGNED-OFF at
      `attests_at_commit`, and the record's `complete` commit precedes ADR-119's `accepted` commit.
- [ ] **AC-H4** PR B `infra-validation` re-run after the forget is green; its plan names no
      `hcloud_volume(_attachment).workspaces["web-1"]` address and no change to `["web-2"]`.
- [ ] **AC-H5** Post-merge: the pre-apply drift plan matched the expected set (Resume step 6); both
      apply workflows `active`; `manual-rerun` apply green; the merge's `web-platform-release.yml` run
      green and a fresh `workspaces-luks-verify.yml` run reads `ready=true` with `workspace_count` ≥ the
      same-day baseline; `protection.delete == true` on `106443278`, read with
      `doppler run -p soleur -c prd_terraform -- sh -c 'curl -sS -H "Authorization: Bearer $HCLOUD_TOKEN" https://api.hetzner.cloud/v1/volumes/106443278' | jq .volume.protection.delete`
      (`sh -c` so the token expands inside Doppler's environment, a GET only); `scheduled-terraform-drift.yml` green.
- [ ] **AC-H6** #6588 closed by the merge; the sweeper closes #6604 on its first run that is both after
      the merge and ≥ 7 days after the last `op:workspaces-luks-drift` event; #6931 and #6897 comments
      posted.

## Domain Review

**Domains relevant:** Engineering, Legal, Product

### Engineering

**Status:** reviewed
**Assessment:** CTO approved with changes. Verified safe: the HCL conditional on 1.10.5, the tombstone,
the hold sequence, the `git mv` (two commits). Blocking findings, both folded: (BF-1) the plan-v1 premise
that no apply reaches `hcloud_volume.workspaces_luks` was false — it is in the SSH stage's `-auto-approve`
closure through `terraform_data.workspaces_boot_unlock_install` — so D1 adds `prevent_destroy` +
`delete_protection` and drops the recut-gate clause; (BF-2) `luks-monitor.test.sh` pins `wipe_aborted`
and the `cleanup()` row pattern. Also folded: the sentinel fails loud, not closed; the stale-premise text
sweep; leave the `name` expression unchanged; the merge-before-forget wedge as a UBI line.

### Legal

**Status:** reviewed
**Assessment:** CLO: approve with B1–B6 folded; the draft cannot be attested (BLOCKED, evidence pending)
and SIGNED-OFF is possible only at the evidence-fill commit. No published legal sentence mentions the
retained copy; AC-B9 is correct. Folded: template rows that pre-assert results become markers;
present-tense template text superseded; the full 6588 audit sweep (banner, `status:`, §A3.5, §A3.6,
addendum key, `residual_cured` scoped to DC-1); the CLO attestation step and audit file; the expiry
extension sweeps the registers; never "`hcloud_volume.workspaces` no longer exists"; the wording
constraints in §F. `Closes #6588` is defensible with a closing comment that accounts for each acceptance
criterion. `soleur:gdpr-gate` (Phase 2.7, triggered by the threshold): the canonical regex matches no
path in this plan and none of the five v1 checks fire (no schema, FK, vendor or Art. 9 surface); the
Art. 5(2)/17 evidence is the destruction record, counts only.

### Product/UX Gate

**Tier:** none (no UI surface in Files to Edit/Create)
**Decision:** reviewed — CPO sign-off **granted with conditions**, all folded: mechanical hold release
(release check + `blocked` label), a `plaintext_only_count` field, the durability limits stated in the
ADR addendum and #6931 comment, a time-boxed Terraform protection (now delivered in this PR — D1), and
three added failure modes (merge after D before the forget; a rebuilt web-1 on the sentinel; hardware
loss of the sole copy).
**Agents invoked:** soleur:product:cpo, soleur:product:spec-flow-analyzer
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

- SpecFlow (4 P0, 4 P1, 4 P2), all folded: Hold 1/2 alternate evidence and `n/a` fill rules (D dies
  after `DELETE`; `forgot=1`; traced `already_forgotten`; cancelled forget); finish review before D
  (D6); the `cleanup()` `mode` local must go with its uses; an abandon/expiry branch; base-SHA diff on
  resume; AC-H6 against the drift window; tombstone emits no drift; post-merge enable ordering.
- Plan review (DHH, Kieran, code-simplicity, architecture-strategist): guard matrices trimmed to the
  rows that discriminate; LW-G5b, the `pending-evidence` status value and the absent-input rows cut;
  evidence concentrated in the record (D4); decisions lifted into `## Decisions`.
- Advisor consult (ADR-083): regenerate the deletion from fresh `main` on resume rather than resolving
  conflicts wholesale; the `removed {}` / split suggestion rejected on the archived measurements.

## Test Scenarios

- Given `CONFIRM_WIPE=1 DRY_RUN=1` and no other mode, when the script runs, then one
  `outcome=wipe_retired` row, rc ≠ 0, no `L3 gates` line, no `EMIT_DRIFT`, no `umount`/`docker stop`.
- Given `CONFIRM_WIPE=true` (or `" 1"`), then the tombstone refuses — never a fall-through to L3.
- Given `CONFIRM_WIPE=1 DRY_RUN=0`, then the same single `wipe_retired` row and rc ≠ 0.
- Given `CONFIRM_WIPE=1 ROLLBACK=1`, then `assert_mode_exclusive` refuses first.
- Given `PLAINTEXT_WIPED` persisted and `ROLLBACK_ACK_LUKS_WRITES=1`, when ROLLBACK runs, then
  `outcome=refused_plaintext_wiped mode=rollback why=marker` and no teardown call.
- Given real devices with the mapper mounted and the recorded plaintext loop's first MiB zeroed by `dd`,
  then `_plaintext_gone` returns 0 with `why=plaintext_dev_gone` (LW-P3).
- Given a `cleanup()` abort on the dry-run path, then exactly one outcome row and no `mode=` field.
- Given `server.tf` with `for_each = var.web_hosts` on either workspaces resource, or
  `workspaces-luks.tf` without `prevent_destroy`/`delete_protection`, then `workspaces-luks.test.sh` is RED.
- Given the workflow file, then its jobs are exactly `{preflight, cutover}` and no step carries a
  Hetzner write verb.

## PR Body (draft while held)

```markdown
Merging this PR alone changes production only through the routine container release and, at the first apply-job run after the re-enable (the post-merge manual-rerun, or a push), one delete_protection update on the sole-copy LUKS volume; both push-apply workflows are paused until after it merges.

**PR B — #6604 step 7 convergence (DRAFT — held).**

Ref #6604
Ref #6588

**HELD as draft until:** (1) volume 105149570 is proven zeroed and deleted; (2) the forget ran
(`forgot=2`/`1`, or a traced `already_forgotten`); (3) every `PENDING-EVIDENCE(` marker is filled, the
CLO has attested, and the destruction record is `complete` before ADR-119 flips to `accepted`; (4)
`infra-validation` is re-run green after the forget (red until then by design). Draft base SHA: <sha>.

**Time bounds (follow-through #9380, `earliest=2026-10-15T00:00:00Z`).** If D has not run by
2026-10-15, the abandon/expiry branch applies. After the forget, this PR must merge within 48 h.
**Resume:** `knowledge-base/project/plans/2026-10-01-feat-workspaces-plaintext-wipe-pr-b-convergence-plan.md`,
`## Resume After the Hold`.

Final merge body: `Ref #6604` (the follow-through sweeper closes it) and `Closes #6588`.

**Sole-copy protection.** Terraform declares `prevent_destroy = true` + `delete_protection = true` on
`hcloud_volume.workspaces_luks` (volume 106443278) and `prevent_destroy = true` on its attachment: every
Terraform plan that would destroy or replace either fails (a web-1 host replace now needs a PR that
relaxes it). Hetzner refuses a console/API/CLI delete only after the post-merge SSH-stage apply delivers
the protection, and until someone holding a write token lifts it. The `workspaces-luks-recut` job is
hard-retired (its first step exits 1); a recut needs a new PR. Recovery from a premature merge is a
**partial** revert that keeps these protections (`## Operator Holds`). Hardware loss stays open (#5274, #8625).

**Evidence already in hand.** Rehearsal run 36769782488 (`result=rehearsal_ok arm=first_wipe
volume_id=105149570 target=/dev/sdb plaintext_dev=/dev/sdb
plaintext_fs_uuid=4cc6a724-f3b7-4c96-b607-af174f82169d holders=0 dependents=0 plaintext_only=0`);
baseline run 36770448813 (`ready=true workspace_count=9 expected=8`).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

Labels: `semver:patch`, `app:web-platform`, `blocked`.

## Issue Comments (posted in Resume step 4)

- **#6931:** after #6604 step 7 volume `106443278` holds the only copy of every workspace. PR B added
  `prevent_destroy` and `delete_protection` to `hcloud_volume.workspaces_luks` and `prevent_destroy` to
  its attachment (superseding this issue's deferral of `prevent_destroy`), and hard-retired the
  `workspaces-luks-recut` job (its first step exits 1). **Ordering trap:** to lift the protection, lift
  `delete_protection` first, in its own reviewed apply; removing `prevent_destroy` while
  `delete_protection` stays on makes a destroy apply detach the mounted volume and then fail the delete
  (`terraform-provider-hcloud` v1.63.0 `internal/volume/resource.go` `resourceVolumeDelete` detaches
  before it deletes) — an outage. There is no backup
  or snapshot; escrow covers key loss, not data loss; hardware loss stays open (#5274/#8625). The
  re-scoped `hcloud_volume.workspaces` posture exception (web-2 only, `expires_on: 2026-12-29`) now
  tracks here, and retiring or re-scoping the `workspaces-luks-recut` apply target is part of this
  issue's topology work.
- **#6897:** item 1 — web-1's `hcloud_volume.workspaces` instance is retired (destruction record);
  web-2's instance moved to #6931; `hcloud_volume.git_data` untouched and still open here.
- **#6604 + #6588** (one template): the evidence summary by reference to the destruction record, and
  a note that the sweeper's 2026-09-29/30 FAILs were the refused rehearsals' drift events.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6.
- **The hold is defined once, in `## Operator Holds`;** every other section points there.
- **`model.likec4.json` is generated** (`bash scripts/regenerate-c4-model.sh`); a direct edit fails
  `c4-canonical`.
- **Never copy `plaintext_only_name` evidence rows** (workspace ids) into any record; counts only.
- **`prevent_destroy` on `workspaces_luks` makes any plan that touches a ForceNew attribute of it fail**
  — including a future `var.web_hosts["web-1"].location` edit. That is the point; #6931 owns lifting it
  deliberately. **Ordering trap for #6931** (recorded in the resource comment and the #6931 comment;
  verified in source by the review: `terraform-provider-hcloud` v1.63.0, the version the lockfile pins,
  `internal/volume/resource.go` `resourceVolumeDelete` calls `Volume.Detach` when the volume has a
  server and only then `Volume.Delete`, without checking protection first): if `prevent_destroy` is removed while
  `delete_protection` stays on, a destroy apply detaches the mounted volume and then fails the delete —
  an outage. Lift `delete_protection` first, in its own reviewed apply.
- **Run markdownlint on the plan and `tasks.md`** before the session summary.
