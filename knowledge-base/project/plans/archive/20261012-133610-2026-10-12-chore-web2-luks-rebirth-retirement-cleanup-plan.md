---
title: "chore: retire the web-2 LUKS rebirth and web-host reboot machinery and close #9372 (PR 2, cleanup)"
date: 2026-10-12
slug: web2-luks-rebirth-retirement-cleanup
branch: feat-one-shot-9372-web2-luks-cleanup-pr2
issue: 9372
closes: 9372
type: chore
priority: p2-medium
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# chore: retire the web-2 LUKS rebirth and web-host reboot machinery and close #9372 (PR 2, cleanup)

Draft PR: #10083. Branch `feat-one-shot-9372-web2-luks-cleanup-pr2`. Detail level: MORE.

Spec lacks a valid `lane:` (no `spec.md` exists for this branch), so `lane: cross-domain` is the fail-closed default (TR2).

## Enhancement Summary

**Deepened on:** 2026-10-12. **Agents used:** learnings-researcher, CTO (four binding rulings), DHH, Kieran, code-simplicity (plan-review), architecture-strategist, security-sentinel, deployment-verification-agent. Halt gates 4.6 (user-brand), 4.7 (observability), 4.8 (PAT), 4.10 (encryption posture: not applicable), 4.11 (guard contract, lint green), 4.12 (scope check) pass; 4.55 (downtime) does not fire (no offline-inducing operation).

**Key improvements.**

1. The merge fires TWO push-apply workflows (`apply-deploy-pipeline-fix.yml` lists `server.tf` in its `paths:`), and the first is already red on main (#10003); the post-merge judgment is baseline-relative with an explicit NO-GO, and the log discriminator was corrected after a read-only run showed the caret-notation escapes defeat a naive sed.
2. A comment-only `.tf` proof must be heredoc-aware (a `#` line inside a heredoc is `user_data`), and the byte-equality baseline is the merge base, not the moving tip.
3. The credential-free `discoverability_test` avoids a repo-global ratchet bump; the live grader is evidence, not a gate.
4. One security control is preserved (a Guard 3 row: the marker token has exactly one holder) because the deleted suites carried it; one is knowingly dropped and disclosed (the `actions/reboot` exact-set census).
5. Records: ADR-263 uses its own blockquote supersession convention; the stale present-tense dispatch commands in two runbooks get RETIRED banners; wider stale-sentence sites are listed.
6. Overclaims removed: "no dispatchable path" is scoped to the rebirth and reboot workflows (`web_host_replace` remains), and the PR body no longer says the merge does not mutate production.

## Overview

Third and last change of the web-2 LUKS-at-boot closeout (#9372). The ledger flip (#9941 and its follow-up, merged 2026-10-10 and 2026-10-11) and the technical-ruling routing change (83851c9e) are on main. web-2 is graded: the #6931 grader reports PASS today (5 distinct green days of probe rows, no non-green row, newest row fresh). The single-use rebirth workflow and the dispatch-only reboot workflow have done their work and have no remaining use, so this change:

1. retires both workflows with every script, suite, gate, fixture and registration that exists only for them (24 files, about 7,400 lines deleted), moving every ratchet that counted them;
2. corrects the stale present-tense wording in `.tf`, `lb-weight-gate.sh`, workflow comments and runbooks (comments only: no HCL value, no resource, no rename);
3. records the retirement: ADR-263 (frontmatter `adopting` to `accepted` with a dated note, plus an addendum tail line), an ADR-241 dated line, the credential-tier runbook rows, the rebirth runbook rows 4 and 5, three `model.c4` edge sentences with a regenerated JSON, and one learning;
4. closes #9372 (`Closes #9372` in the PR body only) and leaves #9642 open for a manual closure with run IDs after merge.

This change dispatches no workflow, makes no hand-run infrastructure change and writes no secret. The merge itself fires the push-triggered apply (analysis below).

## Premise Validation (Phase 0.6, run 2026-10-12)

| Premise in the brief | Checked with | Result |
|---|---|---|
| origin/main carries the three merges; ledger row `hcloud_volume.workspaces` is `luks`, `live_verification: available`, floor 3, no exception | `python3 scripts/lint-encryption-posture.py --repo-sweep` | held: "22 stores, 10 connections, 0 unledgered, 0 failing checks -> PASS" (four exception-expiry warnings dated 2026-10-22 concern other rows) |
| #9372 and #9642 OPEN; #9572, #9984, #9948, #9949 open on purpose | `gh issue view` | held (all OPEN); #6931 is CLOSED (its follow-through finished) |
| the follow-through grader still passes | `SOLEUR_FT_EARLIEST=2026-10-10T20:10:00Z doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/web2-luks-live-6931.sh` (read-only) | held: PASS, 5 distinct days, readiness row 107 h old, newest probe row fresh (boot dd08ac9d) |
| the brief's scope is "the two workflows with their tests and registrations" | git grep census of every reference, plus the runbook's literal deletion list | STALE as worded: the workflows call 7 scripts and 2 gates whose suites a tombstone row ties to them. See Research Reconciliation and CTO ruling 1 |
| `_SUITE_BOUNDS` carries entries for the retired suites | read `apps/web-platform/infra/run-registered-suites.sh` | held for one entry only (`web2-luks-rebirth-workflow.test.sh=900`); `web-host-reboot-workflow.test.sh` has none |
| the parity census count must be re-derived | read `plugins/soleur/test/terraform-target-parity.test.ts` | it is `MAIN_ROOT_TF_WORKFLOWS` (5 entries) and a hard-coded `expect(found.length).toBe(4)`; the count after the change is re-derived by running the suite, not copied |
| model.c4 counts move | ran `plugins/soleur/test/c4-count-parity.test.sh` (13 pass); grepped both workflows for `actions/sentry-heartbeat`, `monitor-slug:`, `api.resend.com`, `notify-ops-email` (0 hits each) | no embedded count moves; only three edge sentences name the retired workflows |
| editing `.tf` files fires the push-triggered apply | read `on.push.paths` of `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` | held, and broader: ANY change under `apps/web-platform/infra/**` fires `apply-web-platform-infra.yml` (this PR's deletions of two `infra/*.test.sh` suites and its tsv edits already match), and `apply-deploy-pipeline-fix.yml` lists `apps/web-platform/infra/server.tf` in its `paths:`, so the `server.tf` comment edit fires BOTH. See Apply-gate analysis |
| "Known pre-existing red on main: deploy-script-tests" | `gh run list --workflow apply-web-platform-infra.yml` | a second, different pre-existing red exists: the push apply has failed on every infra-touching push since 2026-10-11T22:20Z (`terraform_data.egress_gateway` and `egress_gateway_web2` remote-exec provisioners, tracked as #10003). It is not caused by this change and masks it |

No ADR in the corpus proposes a mechanism this plan contradicts: the mechanism (retire together with the tombstone) is the one ADR-263's 2026-10-08 addendum and runbook row 5 prescribe.

## Research Reconciliation: brief vs codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "Retire the two workflows with their tests and registrations" | `scripts/web-host-reboot.test.sh` carries a TOMBSTONE row (hard RED when `scripts/web2-rebirth.sh` or `-never-pooled.sh` is gone while any `web-host-reboot*` file remains); the ADR-263 2026-10-08 addendum says the cleanup PR retires the rebirth restart step together with web-host-reboot "(closing row 5 of the rebirth runbook)"; no live caller of any `web2-rebirth*.sh` or `web-host-reboot*.sh` exists | CTO ruling 1 (2026-10-12): delete the full runbook row-5 list (24 files). Recorded as a disclosed reading of "with their tests", with the CTO's dissent and the flip condition, in the PR body and `decision-challenges.md` |
| "comments: workspaces-luks.tf, server.tf, lb-weight-gate.sh" | stale wording confirmed in `workspaces-luks.tf` (two sites), `server.tf` (four sites) and `lb-weight-gate.sh` (two sites); the CTO's own grep (pattern rebirth/reborn only) missed `lb-weight-gate.sh` ("plaintext-but-empty until its live conversion" and "exists only after web-2's live LUKS conversion") | edit all three files; the brief's list governs, the CTO's "do not touch lb-weight-gate.sh" reading was a pattern miss |
| "(runbook row 5) correct two comments the retirement change left stale" | `workspaces-luks-fresh-boot.tf` CONSUMERS comment names only the verify workflow and the sweeper, which is CORRECT once the rebirth workflow is deleted; the stale holder claim is in `workspaces-luks-verify.yml` (CUSTODY comment: "The ONE other holder is the single-use web-2 rebirth workflow"); the `workspaces-luks-header-web.tf` sentence "the HALT lets a first create through" contradicts ADR-263's 2026-10-06 supersession | edit the verify-workflow comment; verify and correct the header-web sentence against `tests/scripts/lib/destroy-guard-filter-web-platform.jq` before wording it; leave the fresh-boot CONSUMERS comment unless the re-read disagrees |
| "model.c4 plus regenerate" | three edge sentences name the workflows (doppler->hetzner, github->hetzner, github->betterstack); no count moves | edit the three sentences, run `bash scripts/regenerate-c4-model.sh`, then `bash plugins/soleur/test/c4-count-parity.test.sh` |
| "scripts/suite-shard-legs.tsv, scripts/suite-durations.tsv" | the infra pair (`apps/web-platform/infra/suite-shard-legs.tsv`, `suite-durations.tsv`) also carries both workflow suites; the runbook forbids hand edits | regenerate both groups with `python3 scripts/regenerate-shard-manifest.py --group light --incremental --write` and `--group infra --incremental --write` |
| "PROMOTED_FILES" | one entry (`web-host-reboot-workflow.test.sh`) plus a 10-line rationale comment that names two deleted suites | drop the entry and the stale comment paragraph; re-derive the deferred ledger figure by running the suite |

## Research Insights

**Property List (what this change must make true).**

- P1. After merge no dispatchable workflow exists that runs the single-use rebirth (the volume delete, `terraform state rm`, replace sequence) or the web-host reboot; `web_host_replace` is unchanged and still carries web-2's volume forward, so a volume re-birth, a passphrase-loss recovery or an escrow redo now needs a new workflow in a new reviewed PR (and ADR-263 first).
- P2. After merge the live web-2 evidence chain is untouched and still green: `scripts/lib/web2-luks-rows.sh`, `.github/workflows/workspaces-luks-verify.yml` (comment edit only), `scripts/followthroughs/web2-luks-live-6931.sh`, the ledger row and `--repo-sweep`.
- P3. Every repo-wide ratchet and census that counted the retired files moves in the same commit, so CI is green without a follow-up.
- P4. No comment, ADR sentence or runbook line states in the present tense that web-2 is plaintext, awaiting a rebirth, or that a rebirth/reboot workflow can be dispatched; history is preserved append-only.
- P5. This diff adds no Terraform change (comments and deletions only); the push-triggered applies it fires re-run only what is already planned on main, including the #10003 egress replacement that is failing today.
- P6. #9372 closes and #9642 is closable with evidence; the PR files no new issue.

**Cut List (mechanisms considered and removed before research).**

| Mechanism | Property it would buy | Why cut |
|---|---|---|
| a permanent "retirement census" guard (a committed suite that fails if a rebirth file returns) | P1 | a second rebirth needs "a new reviewed pin and PR" by the classifier's own `refuse:already_reborn` design; a guard against re-adding a file is a guard against a reviewed PR. The throwaway residual-zero census (Phase 1) is enough |
| renaming the local `plaintext_workspaces_hosts` to a truthful name | P4 | CTO ruling 4: the ledger `evidence` anchor, workspaces-luks.test.sh Guard B4 and `lint-encryption-posture.test.sh` pin the name and its adjacency; cosmetic gain, three guards to move |
| editing `scripts/lib/web2-luks-rows.sh` to drop the `noop` tolerance of `w2l_ready_verdict` that existed for the rebirth ready-poll | P4 | the grader (`web2-luks-live-6931.sh`) still calls `w2l_ready_verdict`; the lib is shared with the live verify workflow; no property needs it |
| deleting `web-host-reboot.md` | P4 | CTO ruling 2: ADR-263, ADR-241 and the rebirth runbook link to it and it holds the forensic reasoning; a RETIRED banner buys P4 at no link cost |
| removing the Tier-B GitHub secrets or environment reviewers these workflows used | P1 | the same environment and secrets serve live workflows; changing them is a production-mutating act outside this PR |

**CTO rulings (2026-10-12, binding; spawned per hr-technical-fork-is-not-an-operator-question).**

1. Scope: option B, the full runbook row-5 list (24 files) plus four places not on the brief (`run-registered-suites.sh` bound, `guard-vacuity-floor.test.sh` PROMOTED_FILES and comment, `.claude/hooks/grep-q-pipe-guard.test.sh` exempt row, two comments in `workspaces-luks-verify.yml` and `inngest-provision-rehearsal.yml`). Flip condition: any live caller of a deleted script that a post-deletion `git grep` still finds.
2. `web-host-reboot.md`: keep with a RETIRED banner, append-only otherwise; remove it from `AFFECTED_SCRIPTS_WEB_HOST_REBOOT_PATHS`; re-derive the kb-consumers baseline with `--write-baseline`. Flip condition: if the baseline generator keeps the row and the drift check reddens, delete the file and amend the ADR-263 addendum.
3. `terraform-target-parity.test.ts` G2: option A. Drop the `toContain("scripts/web2-rebirth.sh")` line and the real-content control block, retitle the test, keep the `> 400` floor and the `naming > 0` row, add one scratch control (verb present, no sole-copy name). No other tracked script runs `terraform state rm`, so option B is impossible. Expected population about 530; the suite run confirms.
4. `.tf` edits: comments only, no rename, no value change. Do not touch any line between `resource "hcloud_volume" "workspaces" {` and its `for_each = local.plaintext_workspaces_hosts` line, nor the same pair for the attachment; never edit inside a heredoc, `cloud-init.yml` or a `.tmpl`.
The earlier ruling (CTO agent, 2026-10-11) on #9642 stands: moot and retrospective for this cleanup.

**Institutional learnings applied** (all under `knowledge-base/project/learnings/`, with the subdirectory shown where one exists; paths verified with `find`):

- `2026-10-11-deleting-a-never-wired-gate-the-comments-i-rewrote-were-the-defects.md`: the replacement prose is where defects land; delete the whole claim or re-derive it against what survives, never swap the subject of a kept predicate. Comment edits get the same review as code.
- `2026-10-11-the-fix-landed-green-and-left-its-own-pin-red.md`: re-count landed totals; do not invent floor arithmetic.
- `2026-10-11-a-control-that-fails-early-proves-nothing-about-the-checks-after-it.md`: assert each scratch mutant landed before reading its verdict (applies to the G2 scratch control).
- `2026-10-11-two-pr-rule-monitor-routing-recipe.md`: derive the `.tf` delta locally; run `pipeline-tally.sh init` in a fresh worktree before the first `gate` call.
- `2026-09-24-followthrough-retirement-headers-underenumerate-touch-points.md` and `2026-05-09-retirement-cleanup-grep-must-scan-full-class-not-named-id.md`: a `RETIREMENT:` header lists 3 of 5 sites; census the whole retired class, including tsv manifests and runbook prose.
- `2026-09-27-a-retirement-census-by-name-missed-the-consumer-that-pinned-the-id.md`: also grep opaque identifiers and run the repo's census guards against the planned deletion.
- `2026-10-05-a-guard-built-from-spellings-needed-an-allowlist-and-the-affected-run-saw-two-ratchets-my-targeted-tests-could-not.md` and `2026-10-04-a-new-suite-is-invisible-to-repo-ratchets-until-tracked-and-my-fix-moved-the-event-behind-a-hang.md`: file-selected runs cannot see repo-wide ratchets, and `guard-vacuity-floor` enumerates with `git ls-files`, so stage deletions (`git rm`) before running the ratchets.
- `best-practices/2026-07-11-cron-egress-sentinel-needs-runbook-row-and-infra-glob-fires-apply.md` and `test-failures/2026-10-06-a-lints-required-ness-belongs-to-its-job-and-auto-apply-on-merge-is-a-per-workflow-paths-fact.md`: "not a `.tf` file" does not mean "no apply"; read the workflow's own `paths:` block.
- `2026-07-26-cloud-init-comment-is-a-live-host-input-and-an-unreadable-vendor-limit-decays.md`: a comment inside a `templatefile` source or heredoc changes `user_data`; edit only plain HCL `#` lines.
- `test-failures/2026-10-09-a-deleted-deferral-row-took-three-tripwires-with-it-and-my-battery-driver-lost-its-first-edit.md`: record the swept-file and population counts before and after any deletion.
- `2026-06-16-infra-test-orphan-suites-and-node-options-env-file-clobber.md`: infra suites run only through named registrations; deleting a suite means deleting its registration or CI goes red.
- `2026-07-17-workflow-env-gate-references-unprovisioned-environment-auto-approves.md`: deleting a dispatch workflow leaves its `environment:` (`web-platform-infra-apply`) in place; it is shared with live workflows and is not touched.
- `2026-08-17-an-empty-read-is-three-states-and-my-guard-shipped-two-fail-opens.md`: related background for the learning's content-level emptiness requirement.
- ADR addendum lint: `lint-infra-no-human-steps.py` flags prose that pairs a human actor with reboot or power-off imperatives; the retirement line is worded neutrally ("the workflow was deleted").

**Open Code-Review Overlap.** Open `code-review` issues naming files this plan edits: #2197 (server.tf, billing doc), #7942 (infra-validation.yml, scripts/test-all.sh), #8659 (scripts/test-all.sh), #8735 (infra-validation.yml), #8800 (scripts/lib/test-affected-paths.sh). Disposition: **acknowledge** all five. Each concerns a different defect (a billing type, an unrun mutation battery, EXIT-trap leakage in 33 suites, a cancelled-job email, a census sandbox write-through); this PR only deletes lines or comments in those files. #8659 benefits marginally (fewer suites) but is not closed by it. None remains hidden: they stay open.

## Network-outage hypothesis check (Phase 1.4)

The brief names no SSH, firewall or timeout symptom as the thing being fixed. The push apply's current failure (`terraform_data.egress_gateway_web2` remote-exec, #10003) is a pre-existing, separately tracked condition that this plan reads and does not diagnose; no network hypothesis is proposed here. Gate not fired.

## Apply-gate analysis (do first; goes into the PR body)

**Does merging THIS alone mutate production? This diff adds no Terraform change, but the merge fires push-applies that re-run what main already plans.** Both plans are identical to main's current plan (comment-only `.tf` edits plus deletions of test files); the apply that fails today (#10003) will again run its existing egress gateway replacement against production, exactly as it has on every infra-touching push since 2026-10-11T22:20Z. The PR body's first line states exactly that, not "does not mutate production" (`hr-menu-option-ack-not-prod-write-auth`: for a push-triggered apply the merge click is the per-command authorization, so the answer must be explicit and true). `[skip-web-platform-apply]` is not used: it would suppress an apply that is already planned on main and would also hide the evidence this plan reads from the merge run.

**Which workflows fire (read from each workflow's own `on.push.paths`, 2026-10-12).**

1. `apply-web-platform-infra.yml`: paths include `apps/web-platform/infra/**`. This PR deletes `apps/web-platform/infra/web-host-reboot-workflow.test.sh` and `web2-luks-rebirth-workflow.test.sh` and edits `run-registered-suites.sh`, `nic-wait-gate.test.sh`, `workspaces-luks-verify-workflow.test.sh`, both infra tsv files and four `.tf`/`.sh` comment sites, so it fires even if every `.tf` edit were dropped.
2. `apply-deploy-pipeline-fix.yml`: its 33 trigger paths include `apps/web-platform/infra/server.tf` and none of the other edited infra files (verified by listing its `paths:`). The `server.tf` comment edit therefore fires it. Precedent measured by that workflow's own header (run 31636951749, 2026-08-12): a push whose paths-filter intersection is exactly `server.tf` plans "No changes" and ends "Apply complete! Resources: 0 added, 0 changed, 0 destroyed"; `server.tf` is in the workflow's `paths:` but in none of the 24 hashed `triggers_replace` of `terraform_data.deploy_pipeline_fix`, so nothing is pushed to a host. The last six runs of this workflow on main all concluded `success`.
3. Dropping the `server.tf` comment edits would avoid firing (2) but leaves the false present-tense comments the brief asks to mark; the plan keeps them and proves (2) is inert instead.

**Why a comment-only edit is inert, with the checks that prove it.**

1. `host_scripts_content_hash` is the sha256 of the `host_script_files` list only. Neither any `*.tf` file nor `lb-weight-gate.sh` is in it, and no `filesha256` or `file()` reads a `.tf` file or `lb-weight-gate.sh`. Re-grep in Phase 0.
2. `user_data` is under `ignore_changes` on the live hosts; no edited line sits inside a `templatefile` source, a heredoc, `cloud-init*.yml` or a `.tmpl`.
3. Mechanical proof, run in Phase 4: strip HCL `#` and `//` comments and blank lines OUTSIDE heredocs from the MERGE-BASE version (`git show "$(git merge-base origin/main HEAD)":<file>`) and from the working file for each edited `.tf`, and require byte-equal output; AND extract every heredoc body (`<<TAG` / `<<-TAG` to `TAG`) and every `templatefile(` source argument from both versions and require those raw, UNSTRIPPED, to be byte-equal (a `#` line inside a heredoc is `user_data` content, not a comment, and a stripper that removes it would pass a real change). An inline script kept in the session scratchpad and quoted in the PR body, with a self-test that it goes RED on a planted one-character edit inside a heredoc and GREEN on a planted comment edit outside one. Plus `terraform fmt -check` and `terraform validate` on the root. The merge base, not the moving `origin/main` tip, is the comparison point (a sibling merge that touches the same file must not read as this PR's change).
4. The adjacency pairs pinned by `workspaces-luks.test.sh` Guard B4 and `lint-encryption-posture.test.sh` stay byte-identical (diff those hunks).

**Baseline is already red for an unrelated reason.** `apply-web-platform-infra.yml` has concluded `failure` on every infra-touching push since 2026-10-11T22:20Z at `Terraform apply (SSH-provisioned resources, over the bridge)`: its plan line is `Plan: 2 to add, 0 to change, 2 to destroy.` (the two `terraform_data` egress gateway resources, replaced each run) and the errors are remote-exec failures on `terraform_data.egress_gateway` (server.tf) and `terraform_data.egress_gateway_web2`, tracked as #10003. Last green run: 38172628025 (2026-10-11T20:32Z). The merge run will therefore also conclude `failure`.

**Discriminator (verified 2026-10-12 against baseline run 38204104938; read from the FULL job log, because `--log-failed` omits the plan lines).**

```bash
JID=$(gh run view <run-id> --json jobs --jq '.jobs[]|select(.name=="apply")|.databaseId')
gh run view <run-id> --job "$JID" --log | sed -E 's/(\x1b|\^\[)\[[0-9;]*m//g' | sed 's/^[^\t]*\t[^\t]*\t//' | grep -E 'Plan: [0-9]+ to add|Error: |with terraform_data\.[a-z_0-9]+'
```

The log prints colour escapes as the literal caret notation `^[[31m` (two characters for ESC), so the first sed strips BOTH the real byte and the caret form; a sed that strips only the real byte leaves the `Plan:` line wrapped in `^[[1m...^[[0m` and the grep matches nothing (measured). Self-test before relying on it: against baseline run 38204104938 it prints exactly one `Plan:` line and two `Error:`/`with terraform_data.*` pairs (`egress_gateway`, `egress_gateway_web2`).

GO means all of: (1) the run exists and is `completed` (poll up to 10 minutes after the merge: the push-triggered runs appear seconds late, and both apply workflows share the concurrency group `terraform-apply-web-platform-host` with `cancel-in-progress: false`, so a later main push can supersede a pending run; a `cancelled` run is re-measured on the next main SHA that touches the same paths, never read as pass or fail); (2) the `Plan:` count and the `with terraform_data.*` set are a subset of the baseline's; (3) every `Error:` is attributable to `terraform_data.egress_gateway` or `egress_gateway_web2`; or the run is green (a fix of #10003 landing first must not fail this criterion). NO-GO (a finding, filed or commented, never a pass): an `Error:` that is not one of those two, a `Plan:` line naming a resource outside them, an absent `Plan:` line (an earlier failure such as init), or a nonzero change count outside the baseline. The baseline is the newest main push run that touched `apps/web-platform/infra/**`, re-measured immediately before the merge. For `apply-deploy-pipeline-fix.yml` the evidence is `No changes. Your infrastructure matches the configuration.` followed by `Apply complete! Resources: 0 added, 0 changed, 0 destroyed.` on a log line that starts with the `apply` step prefix and a timestamp (the file's header comments quote the same sentence, so a bare grep false-positives).

**No `[skip-web-platform-apply]` marker and no hand-run apply.** Neither is needed or authorized; the owner's go-ahead is not requested because nothing production-mutating is run by this change.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Retire .github/workflows/web2-luks-rebirth.yml and .github/workflows/web-host-reboot.yml with their tests and registrations" [brief] | Phase 2 (deletions), Phase 3 (registrations) | mapped |
| 2 | "parity census (re-derive the count, do not copy it)" [brief] | Phase 3 item T1 | mapped |
| 3 | "scripts/suite-shard-legs.tsv, scripts/suite-durations.tsv, guard-vacuity-floor PROMOTED_FILES, model.c4 plus `bash scripts/regenerate-c4-model.sh` (then plugins/soleur/test/c4-count-parity.test.sh), \_SUITE\_BOUNDS" [brief] | Phase 3 items T5 to T9, Phase 5 item R6 | mapped |
| 4 | "Append a retirement line to the ADR-263 addendum tail (after the 2026-10-11 addendum). Add a dated \"done\" line to runbook web2-luks-rebirth-9372.md rows 4 and 5." [brief] | Phase 5 items R1, R3 | mapped |
| 5 | "Mark the stale present-tense comments: apps/web-platform/infra/workspaces-luks.tf ... server.tf ... lb-weight-gate.sh." [brief] | Phase 4 | mapped |
| 6 | "do the apply-gate analysis first and say so in the PR body" [brief] | section Apply-gate analysis; Phase 0 item 0.4; Phase 6 PR body | mapped |
| 7 | "PR body: `Closes #9372` (body only, never the title). Run plugins/soleur/skills/ship/scripts/auto-close-scan.sh on the title, body and commit messages first. Keep #9642 open until its manual closure." [brief] | Phase 6 | mapped |
| 8 | "flip `adopting` to `accepted` in PR 2 with a dated note" [brief] | Phase 5 item R2 | mapped |
| 9 | "PR 2 also owes one learning with three future requirements: content-level emptiness evidence, a second gate after the evidence step, and a credential-parity check." [brief] | Phase 5 item R8 | mapped |
| 10 | "Record \"Ruled by CTO agent, 2026-10-11\" in the PR body. Close #9642 by hand with the run IDs after PR 2 merges." [brief] | Phase 6 (PR body), Phase 7 (closure) | mapped |
| 11 | "After merge and postmerge verification: comment the final state on #9372, claiming nothing beyond the graded rows ... then close it if the keyword did not." [brief] | Phase 7 | mapped |
| 12 | "Before the first push, run plugin-root-anchoring, harness-parity-tree, the three ratchet linters ... and the skill-body budget against the merge base." [brief] | Phase 6 item 6.1 | mapped |
| 13 | "Net-issue-flow: PR 2 should close at least as many issues as it files." [brief] | Phase 7; PR files zero issues | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Deleting the 7 scripts, their suites, the two gates and the fixtures | "Retire .github/workflows/web2-luks-rebirth.yml and .github/workflows/web-host-reboot.yml with their tests and registrations" | inferred - justification: the workflows' run bodies are the only callers of those scripts, and `scripts/web-host-reboot.test.sh` carries a tombstone row that is hard RED on a half retirement (ADR-263 2026-10-08 addendum, runbook row 5). CTO ruling 1 |
| Four registrations the brief did not name (`run-registered-suites.sh` bound, `.claude/hooks/grep-q-pipe-guard.test.sh` row, the verify-workflow and rehearsal comments) | "with their tests and registrations" | asked (CTO ruling 1 enumerated them) |
| RETIRED banner on `web-host-reboot.md` | "Retire ... web-host-reboot.yml ... with their tests and registrations" | inferred - justification: the runbook documents a dispatch that no longer exists; a banner keeps three inbound links alive (CTO ruling 2) |
| G2 test rewrite in `terraform-target-parity.test.ts` | "parity census (re-derive the count, do not copy it)" | inferred - justification: the G2 test asserts `scripts/web2-rebirth.sh` is in its population and uses it as the only real-content control, so it goes RED on the deletion (CTO ruling 3) |
| `nic-wait-gate.test.sh`, `workspaces-luks-verify-workflow.test.sh` READERS, fixture-relative baseline, `test-affected-paths.sh` blocks, `infra-validation.yml` path entries | "with their tests and registrations" | asked |
| ADR-241 dated line and `infra-credential-tiers-8209.md` rows | "Retire ... with their tests and registrations" | inferred - justification: the row-5 addendum lists them and both name the retired job as a live Tier-B consumer, which would be a false inventory |
| `betterstack-log-query.md`, `web-host-birth.md`, `web-host-replace.md` dated marks | "Mark the stale present-tense comments" | inferred - justification: each names a deleted script or a conversion that "has not run yet" in present tense |
| Comment edits in `workspaces-luks-verify.yml`, `inngest-provision-rehearsal.yml`, `infra-validation.yml` | "Mark the stale present-tense comments" | asked |
| Throwaway residual-zero census (session scratchpad, not committed) | "CI's repo-wide ratchets cannot be seen by file-selected local runs." | inferred - justification: it is the failing test written first (cq-write-failing-tests-before) and the CTO's flip-condition check |
| `server.tf` comment sites beyond the `plaintext_workspaces_hosts` local (the volume and attachment comments, the cron-egress "birth-frozen until the #9372 rebirth" block) | "server.tf (the plaintext_workspaces_hosts local and its comments)" | asked (the comments of that local's resources); the cron-egress block is inferred - justification: it states the rebirth as future in the present tense, and is edited only if the re-read shows the tense is wrong |
| `workspaces-luks-header-web.tf` sentence | "Mark the stale present-tense comments" | inferred - justification: runbook row 5 names it as left stale by the retirement change; edited only if `destroy-guard-filter-web-platform.jq` contradicts it |
| T3 Guard 3 census row (marker token has one holder) | "Mark the stale present-tense comments" and the CUSTODY claim it rewrites | inferred - justification: the deleted suites S21/S21b pinned that custody, and the rewritten comment claims "this job is the holder" which nothing else would enforce (security review, 2026-10-12) |
| `cron-egress-blocked.md`, `apply-web-platform-infra-job-rationale.md` dated marks, runbook RETIRED banners | "Add a dated \"done\" line to runbook web2-luks-rebirth-9372.md rows 4 and 5" | inferred - justification: dispatch commands for deleted workflows would 404 an agent that follows them (architecture review); marks are conditional on the sentence being false at read time |
| `## Rollback` section | "Net-issue-flow" and "CI's repo-wide ratchets cannot be seen by file-selected local runs" | inferred - justification: a revert fires both applies again and is hard RED on a half state, so the recipe is run once in a scratch worktree before it is needed |
| Learning file, `decision-challenges.md` | "PR 2 also owes one learning with three future requirements" | asked (learning); inferred for decision-challenges (the pipeline's channel for a ruling that read a brief narrower than the fix) |

### Split Assessment

- Subsystems touched: 6 - `.github`, `apps/web-platform`, `scripts`, `tests`, `plugins/soleur`, `knowledge-base`
- Planned files: 24 deleted + about 38 edited + 1 created | Estimated changed lines: about 7,400 deleted, about 400 added or edited
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. All three thresholds trip, and a split is not viable on its seam: the tombstone row in `scripts/web-host-reboot.test.sh` makes the web-host-reboot retirement and the rebirth retirement one indivisible change (a half retirement is hard RED by design), and the records half (ADR, runbooks, learning) states the retirement as a fact, so landing it first would record something not yet merged and landing it second would leave 24 dead files carrying present-tense docs. About 95 percent of the line estimate is deleted text in files with no remaining caller.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO agent (2026-10-12) ruled four forks (scope B, banner not delete, G2 option A, comments-only with adjacency pins). Brand-survival threshold none; the only user-facing risk is deleting something the live web-2 evidence chain needs, which the Property List P2 and the Phase 0 baselines guard. Legal, finance, marketing, sales, support and product have no implication: no register, notice, policy or customer-facing text changes (Article 30 and compliance-posture were handled in the ledger-flip PR; this PR only checks that no legal record states a present-tense plaintext fact via `git grep` over `knowledge-base/legal`). Operations: runbooks edited append-only; the Tier-B secrets and the `web-platform-infra-apply` environment are shared with live workflows and untouched.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly: no user-facing route, component or data path changes. A CI-only breakage (a red ratchet) delays other merges; a mistaken deletion of the live evidence chain (`web2-luks-rows.sh`, the verify workflow) would silently stop the daily web-2 probe and the `web2_marker` leg, which gates web-2 ever receiving user weight.
- **If this leaks, the user's data is exposed via:** no new exposure vector. The change removes dispatch-only capability and edits comments, ADR text and registrations; it adds no secret, no credential path and no network edge. Deleting `web2-rebirth.sh` removes the one script that ran `terraform state rm` against web-2 state.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, not `aggregate pattern`: the diff is subtractive, web-2 holds no user data and serves no traffic (weight 0), and the property most at risk (the live evidence chain) is untouched and re-graded in Phase 0 and Phase 7.

threshold: none, reason: the diff touches sensitive paths (`apps/web-platform/infra/*.tf`, workflow files) by comment and deletion only, with no resource, value, credential or trust-boundary change; the plan proves this with a comment-stripped byte-equality check and a post-merge plan-log read.

## Architecture Decision (ADR/C4)

Detection fires: the change records a retirement and flips an ADR status, which a future engineer would otherwise find undocumented. Both are deliverables of THIS plan, not follow-ups.

### ADR

- **Amend ADR-263** (`knowledge-base/engineering/architecture/decisions/ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md`), append-only: (a) frontmatter `status: adopting` to `status: accepted`; (b) under `## Status`, one dated marker after the existing "Superseded 2026-10-08" quote: "Accepted 2026-10-12 (#9372): the grader criterion above is met (PASS 2026-10-10 and on re-read 2026-10-12); the claim boundary of the 2026-10-11 addendum stands (formatted/opened plus green probes; reopen not graded; recovery and emptiness not claimed)"; (c) one addendum "2026-10-12 (#9372, retirement)" appended after the 2026-10-11 addendum tail: the rebirth workflow, the web-host-reboot workflow, 7 scripts, 2 gates, 9 suites and the fixtures are deleted; the single-use property now holds by absence; the tombstone retires with them; the 2026-10-11 addendum's "Status. Unchanged ... left to the ADR owner" is superseded by a dated pointer. This is a mechanical status flip (the ADR states its own criterion; the grader was run and cited), so no ruling was needed.
- **ADR-241**: append one dated line under "2026-10-07 (#9372): `web-host-reboot.yml::reboot` is a new Tier-B consumer" recording that the consumer is retired (never rewrite the dated body).

### C4 views

Read all three model files (`model.c4`, `views.c4`, `spec.c4`) in the work phase before concluding. Enumeration against this change: (a) external human actors: none added or removed; (b) external systems/vendors: Hetzner and Better Stack stay (other workflows use them); (c) containers/data stores: none touched; (d) actor-to-surface access relationships: none change. Edits are edge descriptions only: `doppler -> hetzner` (the rebirth sentence), `github -> hetzner` (the web-host-reboot write sentence), `github -> betterstack` (the `observe` job sentence). Then `bash scripts/regenerate-c4-model.sh` (commit the regenerated `model.likec4.json`), then `bash plugins/soleur/test/c4-count-parity.test.sh` (13 pass at baseline; no embedded count moves because neither workflow uses `actions/sentry-heartbeat`, `monitor-slug:`, `api.resend.com` or `notify-ops-email`), then `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`.

### Sequencing

The ADR describes the post-merge state and is written in the same PR; there is no adopting-until-later gap.

## Observability

```yaml
liveness_signal:
  what: "the #6931 grader (PASS on probe rows) plus the daily workspaces-luks-verify.yml web2_marker leg and its Sentry cron monitor sentry_cron_monitor.workspaces_luks_verify_web2"
  cadence: "daily (verify leg and sweeper), unchanged by this change"
  alert_target: "ci/luks-verify issue plus Sentry Crons check-in, unchanged"
  configured_in: ".github/workflows/workspaces-luks-verify.yml and apps/web-platform/infra/sentry/cron-monitors.tf (neither is edited except one comment)"

error_reporting:
  destination: "GitHub Actions run conclusion plus the notify-apply-failure job of apply-web-platform-infra.yml; Sentry Crons for the verify leg"
  fail_loud: "a red required check on this PR; a failed push-apply run on the merge SHA whose log names the failing resource"

failure_modes:
  - mode: "a ratchet or census still counts a deleted file (CI red)"
    detection: "the required test and infra-validation checks on PR 10083; local scripts/pre-push-ratchet-lane.sh receipt"
    alert_route: "PR check status, then the engineer fixing the registration"
  - mode: "the merge's push-apply shows a diff beyond the two known egress provisioners"
    detection: "bounded read of the apply run log on the merge SHA (command in the Apply-gate analysis); a Plan:/replace line naming any other resource"
    alert_route: "notify-apply-failure email and the postmerge check; findings go to #10003 or a new issue"
  - mode: "the live web-2 evidence chain regresses after merge"
    detection: "the grader re-run in Phase 7 and the next daily web2_marker run"
    alert_route: "ci/luks-verify issue and Sentry Crons"

logs:
  where: "GitHub Actions run logs (apply and verify workflows); Better Stack Logs source for web-2 probe rows (read with scripts/betterstack-query.sh)"
  retention: "GitHub Actions default run-log retention; Better Stack source retention as configured, unchanged"

discoverability_test:
  command: grep -c '"live_verification": "available"' scripts/encryption-posture-ledger.json
  expected_output: "3"
```

The probe is deliberately credential-free (a declared credential would move the repo-global `BASELINE_DECLARED_PROBES` ratchet for no benefit to a deletion PR) and it reads the ledger the store this change must not disturb is recorded in; it runs in well under a second. Correction at ship (2026-10-12): the first draft used `python3 scripts/lint-encryption-posture.py --repo-sweep`, stated as "about 3 seconds"; measured 39.5 s here, which exceeds Check 10's 15 s sandbox cap (timeout, rc=124), so it was replaced. The full sweep stays as evidence (preflight Check 12, PASS, 0 failing checks), not as the probe. The live check is the #6931 grader, run as evidence in Phase 0 and Phase 7 (it needs Doppler read credentials) and never as an acceptance gate.

## Encryption Posture

Not applicable: the plan introduces no persistent store and no new cross-component connection, and the ledger row `hcloud_volume.workspaces` is already `luks` with `live_verification: available`. `.tf` files are in Files to Edit by comment only; the AC `python3 scripts/lint-encryption-posture.py --repo-sweep` must stay `0 failing checks` (it is the proof that the comment edits did not move the content anchor).

## Guard Contract

One existing guard is edited in a way that adds a new assertion (the G2 scratch control in `terraform-target-parity.test.ts`). The other guard edits are removals of rows that counted deleted files; they add no assertion.

### Guard 1 - G2 verb-present-no-sole-copy scratch control

**Property.** A tracked script that runs `terraform state rm` on a non-sole-copy address (here the web-2 pinned form) is legal, while the same verb on a sole-copy address is RED.

**Assembly.** The G2 scanner is `g2ScriptHits` over `g2TrackedScripts()` (the `git ls-files` population under `.github/actions/`, `.github/scripts/`, `scripts/`, `apps/*/infra/`), using `G2_STATE_VERBS` (the `state-rm` row) and `g2Named` (the sole-copy address matcher). The scratch control must flow through the same two functions the population scan uses, not a re-implemented regex. One chokepoint: `g2ScriptHits`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | in the scratch control, replace the web-2 pinned address with `hcloud_volume.inngest_redis_luks` | RED (the existing mutation row and the new control's own negative must both fire) |
| 2 | empty `G2_STATE_VERBS` (the guard's own dispatch reports no verb) | RED (the new control asserts the `state-rm` row exists and matches the scratch string, so a verb-less scanner cannot pass) |
| 3 | add a second scratch script line after the compliant one that names a sole-copy address | RED (hits must equal the single expected hit, not "at least one") |

**Harness rows.** Edit the suite, not the guard: change the control's expected `[]` to `["x"]` and require the suite to go RED (a harness that ignores the expectation passes everything). Must-PASS input that is not the canonical: `terraform state rm 'hcloud_volume.workspaces["web-2"]'` embedded in a longer shell line with a leading `cd x &&` and a trailing comment, expected `[]`. Each scratch mutant is asserted to have landed (changed text) before its verdict is read (learning 2026-10-11-a-control-that-fails-early).

**Anchor.** The control compares scanner output to a literal in the same file, so one diff could weaken both; the real-tree anchors are the population floor (`> 400`) and the `naming > 0` row, and the PR body records the post-deletion population so a reviewer can check it against `git ls-files` independently.

### Guard 2 - the marker token has exactly one workflow holder

**Property.** `secrets.DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER` is bound in `workspaces-luks-verify.yml` and in no other workflow file.

**Assembly.** The census in Guard 3 of `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` over every `.github/workflows/*.yml` and `.github/actions/**` file, by occurrence of the secret name in a code line (comments stripped), through the suite's existing plant helper; chokepoint: the one census routine.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | plant a second workflow file that binds the token in a step `env:` | RED |
| 2 | empty the census's file list (the guard's own dispatch scans nothing) | RED (a floor on files scanned) |
| 3 | plant a third workflow after the compliant first plant | RED (both reported, not just the first) |

**Harness rows.** Edit the suite so the census expects zero holders and require RED; must-PASS input that is not the canonical: the real tree with the token named only in a comment of a second workflow.

**Anchor.** The census compares to the one real holder in the tree; a diff that adds a holder must also edit the suite's expected set, which a reviewer reads in the same hunk.

## Infrastructure (IaC)

The plan introduces no new infrastructure and no provisioning step; every step is either a repo edit or a read-only `gh`/Better Stack/Hetzner read. `### Terraform changes`: none (comments only; the proof is in the Apply-gate analysis). `### Apply path`: the existing push-triggered apply fires on merge; no hand apply. `### Host fan-out`: not applicable (no `terraform_data` SSH provisioner is added or changed; the two failing provisioners are #10003's). `### Distinctness / drift safeguards`: unchanged. `### Vendor-tier reality check`: not applicable.

## Implementation Phases

### Phase 0: Re-verify before any write (read-only)

- 0.1 `git fetch origin main`; confirm #9372, #9642 OPEN and #6931 CLOSED (`gh issue view`); `git log origin/main` still carries the three merges.
- 0.2 Re-run the grader (command in Premise Validation) and `python3 scripts/lint-encryption-posture.py --repo-sweep`. Stop and report on #9372 if either is not green.
- 0.3 Record the BEFORE numbers into the session scratchpad: `bash plugins/soleur/test/c4-count-parity.test.sh` (13 pass); the `terraform-target-parity.test.ts` main-root census (`found.length` 4); the G2 population size; row counts of the four tsv files (`wc -l`); `bash scripts/test-affected-kb-consumers.test.sh` baseline size (row count of `scripts/test-affected-kb-consumers.baseline.txt`); `git ls-files | wc -l`. Re-derive the deferred-ledger figure in `scripts/guard-vacuity-floor.test.sh`.
- 0.4 Apply-gate prerequisites: re-read `on.push.paths` of `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml`; re-grep that no `filesha256`/`file()` covers a `.tf` file or `lb-weight-gate.sh`; re-read the last 3 apply runs and confirm the failing resources are still only the two egress provisioners (#10003); re-read `apply-deploy-pipeline-fix.yml`'s hashed `triggers_replace` set on the merge base immediately before the first push (a concurrent PR that adds `server.tf` to it would void the "inert" proof); resolve what `server.tf` line ~77 ("byte-compares ... against the sha256 of THIS") hashes before calling any `server.tf` edit inert; read-only check of runbook closing row 3 (re-capture of web-2's SSH host-key pin; re-enable of the push-apply workflows): if done, R3 marks it done, if not, it stays open and the #9372 close-out comment says so; grep the group users of `terraform-apply-web-platform-host` and `web-1-swap` for comments naming the retired workflows.
- 0.5 Read all three `.c4` model files; read the stale-wording sites in full (list in Phase 4).
- 0.6 No baseline run of the ratchet lane: run it once, at the end (Phase 6.1); only if a member is red, measure `origin/main` in a detached worktree to attribute it. `pipeline-tally.sh init` in this worktree before the first `gate` call (learning 2026-10-11-two-pr-rule).

### Phase 1: The failing test first (cq-write-failing-tests-before)

- 1.1 Run the AC1 census command now, before any deletion: it lists the full reference set (RED) and is the CTO's flip-condition check. After Phase 3 it must print only the allowed remnants (GREEN). The command is one line, quoted verbatim in AC1 and in the PR body; no script is kept. Allowed remnants, each a reason and not a convenience: (a) the grader header's pointer to the KEPT runbook `web2-luks-rebirth-9372.md` (`scripts/followthroughs/web2-luks-live-6931.sh`); (b) `plugins/soleur/test/web-host-escrow-preflight-census.test.ts`, whose synthetic job key `web_host_rebirth_fixture` is a fixture name unrelated to the deleted files and whose `TEST_FLOOR` pins its declared test count (renaming it would move that floor for no benefit); (c) `plugins/soleur/test/preflight-discoverability-test.test.ts`, whose `BASELINE_DECLARED_PROBES` comments are the historical record of earlier declaring plans.

### Phase 2: Delete the retired files (`git rm`, so ratchets that use `git ls-files` see the deletion)

The 24 files listed under Files to Delete. Order: workflows and infra suites first, scripts next, `tests/scripts` last.

### Phase 3: Registrations and ratchets (T1 to T13, each by content anchor)

- T1 `plugins/soleur/test/terraform-target-parity.test.ts`: drop `"web2-luks-rebirth.yml"` and its 3-line comment from `MAIN_ROOT_TF_WORKFLOWS`; delete the `describe("web2-luks-rebirth.yml: the five-target set (#9372)"` block and the comment above it; change `expect(found.length).toBe(4)` to `toBe(3)` (the independent floor next to the existing set-equality assertion against `MAIN_ROOT_TF_WORKFLOWS`; run the suite to confirm 3 before committing, do not copy the number from this plan); rewrite the G2 test per CTO ruling 3 and the Guard Contract; update the `// (it retires after use ...)` comment.
- T2 `apps/web-platform/infra/nic-wait-gate.test.sh`: remove the `*/web2-luks-rebirth.yml)` case arm, the `rebirth-targets.txt` plumbing and the three rebirth `assert` rows with their comment, leaving the generic `*)` arm; record the "extractor is not blind" floor's measured count (`WEB1_DIRECT`) before and after `git rm` (the rebirth workflow's targets go to a separate file, so the floor should not move; if it does, set it to the new live count and state why) and keep `UNGATED == 0`; update the neighbouring comment that says "the ONE other direct target".
- T3 `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh`: remove `"scripts/web2-rebirth-emptiness.sh"`, `"scripts/web2-rebirth-never-pooled.sh"`, `"scripts/web2-rebirth-ready-poll.sh"`, `"scripts/web-host-reboot-evidence.sh"` from `READERS`; check whether any row requires each READERS entry to exist or any writer/holder count and move it with the comment edit in Phase 4. Then add ONE census row to the same suite's Guard 3 (the deleted suites' S21/S21b pinned where `DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER` is bound; the remaining census matches the marker KEY, not the secret name, so nothing would stop a second workflow binding the token): `secrets.DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER` appears in exactly one workflow file, `workspaces-luks-verify.yml`, with the suite's existing plant helper driving it RED (Guard 2 of the Guard Contract).
- T4 `.claude/hooks/grep-q-pipe-guard.test.sh`: remove the `scripts/web2-rebirth-recovery-check.test.sh | cryptsetup | exempt` row; run the suite and confirm its table-population floor still holds (re-derive, do not copy).
- T5 `scripts/test-all.sh`: remove the `run_suite` lines for `scripts/web2-rebirth`, `-emptiness`, `-never-pooled`, `-recovery-check`, `scripts/web-host-reboot`, `tests/scripts/web-host-rebirth-gate`, `tests/scripts/web2-rebirth-classify` and their two comment blocks.
- T6 `scripts/lib/test-affected-paths.sh`: delete the arrays `AFFECTED_SCRIPTS_WEB2_REBIRTH_RECOVERY_CHECK_PATHS` and `AFFECTED_SCRIPTS_WEB_HOST_REBOOT_PATHS` with their comments. They appear only at their definitions (the per-suite mapping is derived from the suite label, not registered by name), plus one prose mention in the rebirth runbook that R3 leaves as history; confirm with `git grep` before and after.
- T7 `scripts/guard-vacuity-floor.test.sh`: remove `apps/web-platform/infra/web-host-reboot-workflow.test.sh` from `PROMOTED_FILES` and the rationale comment paragraph naming it and `scripts/web-host-reboot.test.sh`; run the suite and record the deferred-ledger figure (the comment says 47 to 48; do not assert a number, re-derive it).
- T8 `apps/web-platform/infra/run-registered-suites.sh`: remove `"apps/web-platform/infra/web2-luks-rebirth-workflow.test.sh=900"` and its 2-line comment.
- T9 tsv manifests: `python3 scripts/regenerate-shard-manifest.py --group light --incremental --write` and `--group infra --incremental --write`; the diff must show only removed rows: 7 light labels (the `run_suite` labels of Phase 3 item T5) in each of the two light files and 2 infra suites in each of the two infra files, so 18 rows in total (re-count the removed lines with `git diff --numstat`; a different number is a finding). The generator is the only writer.
- T10 `plugins/soleur/test/fixture-relative-assert.baseline.txt`: remove the 4 rows for deleted files (`web2-luks-rebirth-workflow.test.sh`, `web2-rebirth-recovery-check.sh`, `.test.sh`, `web2-rebirth.test.sh`); the ratchet lane (Phase 6.1) runs `fixture-relative-assert` once.
- T11 `scripts/test-affected-kb-consumers.baseline.txt`: the row `scripts/guard-vacuity-floor<TAB>.../web-host-reboot.md` names `guard-vacuity-floor` as the consumer, not the reboot suite, so first record WHY it exists (`bash scripts/test-affected-kb-consumers.test.sh` output and the suite's own text) before deciding; run the suite after the deletions and apply `--write-baseline` only if it reports the row stale, with a diff of removals only. The runbook stays (banner), so the row may stay valid.
- T12 `.github/workflows/infra-validation.yml`: remove the "(#9372) web-host-reboot-workflow.test.sh" comment block and its three `paths:` entries (PR list). This file is itself in `MAIN_ROOT_TF_WORKFLOWS`; its edit is comment-and-path only.
- T13 sweep for any registration this list missed: re-run the Phase 1 census, plus `git grep -n -E 'AFFECTED_SCRIPTS_WEB(2)?_(HOST_)?RE(BIRTH|BOOT)'` and a search of `scripts/*.txt`, `scripts/*.tsv`, `plugins/soleur/test/*.baseline.txt`, `.github/` for each deleted basename WITHOUT extension.

### Phase 4: Stale wording (comments only; edit by content anchor, never by line number)

- `apps/web-platform/infra/workspaces-luks.tf`: the "(once reborn, #9372)" clause in the HCL header block and the paragraph beginning "web-2's volume is plaintext ONLY until its single-use rebirth". Replacement states the dated fact: web-2's volume was born raw on 2026-10-06 and formats LUKS at first boot (rebirth retired 2026-10-12, ADR-263); "LUKS-backed at boot" is graded by the #6931 PASS of 2026-10-10 and claims formatted/opened plus green probes only.
- `apps/web-platform/infra/server.tf`: (a) the `locals` comment above `plaintext_workspaces_hosts` ("Only the hosts listed here still own a per-host plaintext volume") - state that the local keys the per-host volume that web-2 formats LUKS at first boot, and that the name is historical and pinned (ledger anchor, Guard B4); (b) the `hcloud_volume.workspaces` comments "per-host plaintext volume (web-2 only ...)", "once it is reborn raw" and "The live web-2 volume is converted by the gated rebirth, never by this block"; (c) the cron-egress comment block "birth-frozen until the #9372 rebirth" (re-read it: the factual claim about which artifacts a RUNNING web-2 gets must stay true; reword only the tense of the rebirth reference); (d) the `workspaces_volume_id` / pooling comments that call web-2 plaintext. Constraints: CTO ruling 4 verbatim.
- `apps/web-platform/infra/lb-weight-gate.sh`: the header lines "The WORKSPACES_LUKS marker is what keeps a plaintext web-2 from being pooled: it exists only after web-2's live LUKS conversion (#9372, ADR-263) and a soak" and the B.6-B.10 block "web-2's for_each volume is plaintext-but-empty until its live conversion". Keep the gate semantics: the marker still fences pooling and is shape-only (#9358). Run `lb-weight-gate.test.sh` and `lb-weight-gate-with-marker.test.sh`; check neither pins comment text.
- `apps/web-platform/infra/workspaces-luks-header-web.tf`: read `tests/scripts/lib/destroy-guard-filter-web-platform.jq` first; correct "the HALT lets a first create through" only if the filter now counts a web-class create (ADR-263 2026-10-06 supersession says it does); no value edit.
- `.github/workflows/workspaces-luks-verify.yml` (CUSTODY comment): rewrite the whole paragraph through its end, not one sentence: drop the "ONE other holder is the single-use web-2 rebirth workflow" claim AND the clause that names `scripts/web2-rebirth-never-pooled.sh` and the census that allow-lists it; the token's holder is this job, enforced by the Guard 3 row of T3; check the later "reborn" mention near the end of the file against T3's READERS change; the sweeper reads (per the fresh-boot CONSUMERS comment, which stays). `.github/workflows/inngest-provision-rehearsal.yml`: the "web-host-reboot.yml's #9372 job" comparison: reword to a past-tense reference.
- Proof (all `.tf` files edited): the comment-stripped byte-equality check against `origin/main`, `terraform fmt -check`, `terraform validate`, then `bash apps/web-platform/infra/workspaces-luks.test.sh`, `fresh-boot-parity.test.sh`, `lb-weight-gate.test.sh`, `lb-weight-gate-with-marker.test.sh`, `workspaces-luks-verify-workflow.test.sh`, `bash scripts/lint-encryption-posture.test.sh` (47/47 at baseline), and the full `apps/web-platform/infra` registered set via `bash apps/web-platform/infra/run-registered-suites.sh` (bounded).

### Phase 5: Records

- R1 `knowledge-base/engineering/architecture/decisions/ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md`: append ONE addendum "2026-10-12 (#9372, retirement)" after the 2026-10-11 addendum tail. It states: the rebirth workflow, its `terraform state rm` script and the web-host-reboot workflow are deleted; `web_host_replace` is unchanged; a volume re-birth, a passphrase-loss recovery (#9948) or an escrow redo (#9949) now needs a new workflow in a new reviewed PR, ADR-263 amended first; the claim boundary of the 2026-10-11 addendum stands; the 2026-10-11 "Status. Unchanged" paragraph is superseded. Per this ADR's convention, also add a short blockquote `> Superseded 2026-10-12 (#9372), in part: ...` under each stale present-tense paragraph (the Status paragraph and the "Live conversion" section, which still says that until the rebirth runs a plain replace re-attaches the ext4 volume and that the workflow file is deleted after use). Append-only: no sentence is rewritten.
- R2 same file: frontmatter `status: accepted` and one dated "Accepted 2026-10-12" note under `## Status` (after the existing "Superseded 2026-10-08" quote). Check any ADR index or lint that reads `status:` (`grep -rn 'ADR-263' knowledge-base/engineering/architecture --include=*.md -l`, the `adr-ordinals` check) and that `lint-infra-no-human-steps.py --changed --base origin/main` passes on the new prose.
- R3 `knowledge-base/engineering/operations/runbooks/web2-luks-rebirth-9372.md`: dated `[Done 2026-10-12 (#9372)]` line on row 4 (directive `earliest=2026-10-10T20:10:00Z` set; #6931 closed after PASS) and row 5 (the deletion list landed in this PR; cite the PR number once known), row 3 per the Phase 0.4 read; a RETIRED banner at the top of the file ("the workflow this runbook dispatches is deleted; the dispatch commands below return 404; history only"), with the original status line left as written. The section "The reboot and its evidence: a separate workflow (2026-10-07)" stays (append-only) and carries the same pointer; the row-5 addendum's "delete the section" and "dated line inside the 2026-10-07 ADR-263 addendum" are met by the banner and the 2026-10-12 tail addendum instead (disclosed deviations, with CTO ruling 2).
- R4 `knowledge-base/engineering/operations/runbooks/web-host-reboot.md`: RETIRED banner at the top (what was removed, where the record lives, "do not dispatch: the `gh workflow run web-host-reboot.yml` commands below reference a deleted workflow"); body append-only.
- R5 `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md` dated line; `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` rows for `web-host-reboot.yml::reboot` and `::observe` marked retired plus a dated note (rows kept, not deleted, so the history of the tier inventory stays readable).
- R6 `knowledge-base/engineering/architecture/diagrams/model.c4` three edge sentences, `bash scripts/regenerate-c4-model.sh`, `model.likec4.json` committed, then the tests in the C4 section.
- R7 one dated sentence each, append-only, only where the existing sentence is false at read time (read each file for every pending-rebirth mention, not only the first): `betterstack-log-query.md` (names `scripts/web2-rebirth-emptiness.sh` as a live reader), `web-host-replace.md` (the link line AND the lines near its start and middle that say a plain replace of web-2 is not safe before the volume rebirth or that the conversion is #9372), `web-host-birth.md` (the same link line), `cron-egress-blocked.md` ("birth-frozen until the #9372 rebirth"), `apply-web-platform-infra-job-rationale.md` (names the rebirth workflow). Other ADRs that say web-2 is converted "by rebirth only" or that the conversion is pending (ADR-096, ADR-119, ADR-143, ADR-148) are accepted point-in-time records: list them in the PR body as untouched history.
- R8 learning `knowledge-base/project/learnings/2026-10-12-<slug>.md` (title chosen at write time; one lesson per file, headline sentence form like its siblings): the evidence step of a destructive single-use workflow measured a coarse bound (used bytes under 1 GiB, spread under 64 MiB) and called it emptiness. Three requirements for any future workflow that deletes a volume on evidence: (1) content-level emptiness evidence (read what is on the device, not how many bytes are used; the observed level of about 16 MB is consistent with an ext4 volume's own metadata but was never compared with an independent empty reference (a hypothesis, not a measurement; cite the runbook's recorded min 15.6 MB, max 16.0 MB over 169 h)); (2) a second gate AFTER the evidence step (the environment approval is a job-level gate that precedes the evidence step, so an apply dispatch's PASS flowed into the delete with nobody reading the numbers); (3) a credential-parity check before the first real dispatch (the live control ran under Doppler read credentials while the workflow used the repo `BETTERSTACK_QUERY_*` secrets). Cite: #9642 (ruled moot for this cleanup by the CTO agent on 2026-10-11 because the single use already happened and the workflow is deleted), the 2026-10-06 runs 37508997529 and 37516716515, and that the real rebirth ran without these three. Check it against the existing sibling learnings for overlap before writing (the 2026-08-17 "an empty read is three states" and 2026-10-11 "a control that fails early" files).
- R9 `knowledge-base/project/specs/feat-one-shot-9372-web2-luks-cleanup-pr2/` is created by the planning phase (tasks.md, decision-challenges.md); the work phase appends to `session-state.md` only if needed.

### Phase 6: Local gates, commit, PR

- 6.1 Commit locally first (item 6.3: the ratchet lane merges COMMITTED HEAD with origin/main in a scratch worktree, so staged or uncommitted edits are invisible to it), then, before the first push, run the repo-wide ratchets that file-selected runs cannot see: `bash scripts/pre-push-ratchet-lane.sh` (members include `plugin-root-anchor-debt`, `fixture-relative-assert`, `fixture-dir-operand-assert`, `fixture-cd-containment`, `skill-body-budget` against the merge base, `rule-bodies`, `test-affected-kb-consumers`; run it once, here); `harness-parity-tree` (`plugins/soleur/test/harness-parity-tree.test.ts`, run the way the repo's test script runs `plugins/soleur/test`); the two ratchet linters the lane does not run (`python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`; `python3 scripts/lint-window-closure-assertion.py --allowlist scripts/lint-window-closure-assertion.allowlist.txt`; the third, `fixture-relative-assert`, is a lane member). Resolve the exact argv from each linter's own `--help` or from the ratchet lane's member table; do not guess flags. Run each CI gate with ITS OWN invocation, never a hand-listed path set: `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (it scans every changed doc, including the learning, the ADR addenda and the runbooks), `python3 scripts/lint-guard-contract.py <plan>`, `npx markdownlint-cli2` over the changed `.md` files. If a repo-global ratchet moves, measure `origin/main` in a detached worktree before attributing the move.
- 6.2 Re-run the affected plugin and script suites named above: `plugins/soleur/test/terraform-target-parity.test.ts` (vitest or bun, as the repo's test script specifies), `scripts/guard-vacuity-floor.test.sh`, `scripts/test-affected-kb-consumers.test.sh`, `plugins/soleur/test/c4-count-parity.test.sh`, `tests/scripts/test-infra-privileged-tier-census.sh`, `tests/scripts/test-git-data-root-token-census.sh`, `apps/web-platform/infra/nic-wait-gate.test.sh`, and `TEST_GROUP=affected` for the whole selection if the repo documents that entry point.
- 6.3 Commit in two or three logical commits (retirement of code and registrations; comments; records), each ending with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. No commit message or the PR title carries a closing keyword.
- 6.4 PR body (ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`). First line: "This diff adds no Terraform change; merging fires `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml`, which re-run what main already plans, including the egress replacement that is failing today (#10003)." Then a "Residual grants and dropped coverage" block: the secrets and environment the retired workflows used and that stay (the `web-platform-infra-apply` environment keeps five workflows; `DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER` keeps one consumer, still read/write until #9358; `DOPPLER_TOKEN_INFRA_PRIVILEGED`, `DOPPLER_TOKEN` and `BETTERSTACK_QUERY_*` are consumed elsewhere), the before and after output of `tests/scripts/test-infra-privileged-tier-census.sh` and `tests/scripts/test-git-data-root-token-census.sh` run after `git rm`, and the coverage knowingly dropped with its suites (the exact-set census of Hetzner request call sites in `scripts/web-host-reboot.test.sh`; the single remaining caller is `inngest-provision-rehearsal.yml`, and no writer script remains to add a second). Then: `Closes #9372`; `Ref #9642` (never `Closes`: #9642 closes after merge with a comment with run IDs); the line "Ruled by CTO agent, 2026-10-11" for #9642 and "Ruled by CTO agent, 2026-10-12" for the four scope forks, with the CTO's dissent on scope and its flip condition; the Apply-gate analysis paragraph (including the pre-existing #10003 red and the discriminator command); the three before/after count tables (census, G2 population, tsv rows); the disclosure that the retirement list is wider than the brief's wording and why (tombstone row). Run `bash plugins/soleur/skills/ship/scripts/auto-close-scan.sh <file>` on the title, the body and each commit message (write each to a scratch file); the only expected match is `Closes #9372` in the body.
- 6.5 `gh pr merge --squash --auto` when ready; a BEHIND reading is expected and is not a reason to sync the branch; watch with Monitor, never `run_in_background` (hr-monitor-not-run-in-background-for-polling).

### Phase 7: After merge (soleur:postmerge, then close-out)

- 7.1 Verify on the merge SHA (AC14 for how to obtain and validate it; an empty `mergeCommit` before an auto-merge lands selects nothing and reads as "not yet", never as success): required checks green; BOTH push-apply runs judged per the Apply-gate analysis (`gh run list --workflow <file> --commit <full-sha>`); both workflow files absent from the tree (AC14); the repo sweep and the grader re-run once as evidence. The next scheduled `scheduled-terraform-drift.yml` run is advisory only: it is cron-driven with no bound on when it fires, and dispatching it is a workflow dispatch that needs the owner's go-ahead naming the command, so it is not a gate here.
- 7.2 Comment the final state on #9372 (even if the keyword already closed it), claiming only the graded rows: quote the grader output verbatim with a UTC timestamp (formatted/opened plus green probes; the day count is whatever it prints at that time), link `ADR-263` at the merge SHA for the flip to accepted, and state that the `apply-web-platform-infra.yml` merge run is red per #10003 and baseline-equal, not green. State plainly that reopen after a host restart is not graded, and that passphrase-loss recovery (#9948), the re-escrow step (#9949), the state restore substrate (#7992) and emptiness evidence are not claimed. Then close #9372 if the keyword did not (`hr-before-asserting-github-issue-status`: read state first).
- 7.3 Close #9642 by hand: comment with the rebirth run IDs (37508997529, 37516716515, 2026-10-06), the grader sweeper run 38083925201 (2026-10-10), the CTO ruling "moot/retrospective, 2026-10-11", this PR number and the learning path (its three requirements are the durable outcome), then `gh issue close 9642 --reason "not planned"` (the question became moot, it was not answered; the comment cites only the ruling, the run IDs and the learning).
- 7.4 Leave #9572, #9984, #9948, #9949 and #10003 open; add no new issue. Net issue flow: closes 2 (#9372, #9642), files 0.

## Files to Delete (24)

```
.github/workflows/web2-luks-rebirth.yml
.github/workflows/web-host-reboot.yml
apps/web-platform/infra/web2-luks-rebirth-workflow.test.sh
apps/web-platform/infra/web-host-reboot-workflow.test.sh
scripts/web2-rebirth.sh
scripts/web2-rebirth.test.sh
scripts/web2-rebirth-emptiness.sh
scripts/web2-rebirth-emptiness.test.sh
scripts/web2-rebirth-never-pooled.sh
scripts/web2-rebirth-never-pooled.test.sh
scripts/web2-rebirth-ready-poll.sh
scripts/web2-rebirth-recovery-check.sh
scripts/web2-rebirth-recovery-check.test.sh
scripts/web-host-reboot.sh
scripts/web-host-reboot-evidence.sh
scripts/web-host-reboot.test.sh
tests/scripts/lib/web-host-rebirth-gate.sh
tests/scripts/lib/web2-rebirth-classify.sh
tests/scripts/test-web-host-rebirth-gate.sh
tests/scripts/test-web2-rebirth-classify.sh
tests/scripts/fixtures/web-host-rebirth/passphrase-create-password-only.json
tests/scripts/fixtures/web-host-rebirth/post.json
tests/scripts/fixtures/web-host-rebirth/pre.json
tests/scripts/fixtures/web-host-rebirth/resume.json
```

Verified by `git ls-files` (24 paths, 7,438 lines). Kept on purpose: `scripts/lib/web2-luks-rows.sh`, `scripts/followthroughs/web2-luks-live-6931.sh` (+ test), `scripts/followthroughs/web-host-replace-rebirth-6969.sh` (a different, July dispatch), `scripts/web-host-escrow-preflight.sh`, `tests/scripts/lib/destroy-guard-filter-web-platform.jq` and `stock-preflight-gate.sh` (shared).

## Files to Edit

Code and registrations: `plugins/soleur/test/terraform-target-parity.test.ts`, `apps/web-platform/infra/nic-wait-gate.test.sh`, `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh`, `.claude/hooks/grep-q-pipe-guard.test.sh`, `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/guard-vacuity-floor.test.sh`, `apps/web-platform/infra/run-registered-suites.sh`, `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv`, `apps/web-platform/infra/suite-shard-legs.tsv`, `apps/web-platform/infra/suite-durations.tsv`, `plugins/soleur/test/fixture-relative-assert.baseline.txt`, `scripts/test-affected-kb-consumers.baseline.txt` (only if stale), `.github/workflows/infra-validation.yml`.

Comments (no value change): `apps/web-platform/infra/workspaces-luks.tf`, `apps/web-platform/infra/server.tf`, `apps/web-platform/infra/lb-weight-gate.sh`, `apps/web-platform/infra/workspaces-luks-header-web.tf` (after reading the jq filter), `.github/workflows/workspaces-luks-verify.yml`, `.github/workflows/inngest-provision-rehearsal.yml`.

Records: `knowledge-base/engineering/architecture/decisions/ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md`, `ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`, `knowledge-base/engineering/architecture/diagrams/model.c4`, `model.likec4.json` (generated), `knowledge-base/engineering/operations/runbooks/{web2-luks-rebirth-9372,web-host-reboot,infra-credential-tiers-8209,betterstack-log-query,web-host-birth,web-host-replace,cron-egress-blocked,apply-web-platform-infra-job-rationale}.md` (the last four conditionally, per R7).

## Files to Create

`knowledge-base/project/learnings/2026-10-12-<slug>.md` (R8). In the planning phase only: `knowledge-base/project/specs/feat-one-shot-9372-web2-luks-cleanup-pr2/tasks.md` and `decision-challenges.md`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1. `git ls-files` lists none of the 24 deleted paths, and `git grep -n -i -E 'web2[-_]rebirth|web-host[-_]reboot|web_host_rebirth|web-host-rebirth|web2-luks-rebirth' -- . ':!knowledge-base' ':!plugins/soleur/test/preflight-discoverability-test.test.ts' ':!plugins/soleur/test/web-host-escrow-preflight-census.test.ts'` prints only the grader header's pointer to the kept runbook `web2-luks-rebirth-9372.md` (allowed remnants (b) and (c) of Phase 1.1 are excluded by the pathspec, each for a stated reason). The command is quoted verbatim in the PR body so anyone can re-run it.
- [ ] AC2. `plugins/soleur/test/terraform-target-parity.test.ts` passes; its main-root census asserts the count the suite derives after the edit (3 expected) and `MAIN_ROOT_TF_WORKFLOWS` has 4 entries; the G2 test passes with the population floor `> 400` and the scratch control; the PR body states the measured population before and after.
- [ ] AC3. All four tsv manifests changed by `regenerate-shard-manifest.py --incremental --write` only (diff = removed rows); `bash scripts/guard-vacuity-floor.test.sh` passes with `PROMOTED_FILES` and its comment free of both deleted suites; `bash scripts/test-affected-kb-consumers.test.sh` and `bash plugins/soleur/test/fixture-relative-assert.test.sh` pass with baselines shrunk only by deleted-file rows.
- [ ] AC4. `bash apps/web-platform/infra/nic-wait-gate.test.sh` and `bash apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` pass; `UNGATED` is 0 and the "extractor is not blind" floor is unchanged.
- [ ] AC5. Each edited `.tf` file is byte-equal to its MERGE-BASE version (`git merge-base origin/main HEAD`, not the moving tip) after stripping `#` and `//` comments and blank lines; `terraform fmt -check` and `terraform validate` pass on the root; `workspaces-luks.test.sh`, `fresh-boot-parity.test.sh`, `lb-weight-gate.test.sh` and `lb-weight-gate-with-marker.test.sh` pass; the pinned adjacency hunks (`resource "hcloud_volume" "workspaces"` to its `for_each`, and the attachment pair) are unchanged in `git diff`.
- [ ] AC6. `python3 scripts/lint-encryption-posture.py --repo-sweep` reports `0 failing checks` and `bash scripts/lint-encryption-posture.test.sh` is green (both are repo-deterministic; the sweep carries a date horizon: four unrelated exceptions expire 2026-10-22 and turn every PR red from that date, so a merge or re-run after it must be read against that, not against this diff). The #6931 grader (`SOLEUR_FT_EARLIEST=2026-10-10T20:10:00Z`, under Doppler) is run in Phase 0 and Phase 7 and its output quoted as evidence; it depends on live Better Stack rows and is not an acceptance gate.
- [ ] AC7. No residual present-tense claim: `git grep -n -i -E 'plaintext ONLY until|once (it is )?reborn|until its (single-use )?rebirth|plaintext-but-empty|lets a first create through|gated rebirth|live (LUKS )?conversion|birth-frozen until' -- apps/web-platform/infra .github scripts` prints nothing except lines that already carry a dated past-tense reference (state each kept line and why in the PR body); every remaining "plaintext" mention in `server.tf`/`workspaces-luks.tf` describes web-1's destroyed volume or the historical anchor name.
- [ ] AC7b. `git grep -n -i -E 'rebirth|reborn|until it runs|gh workflow run web2-luks-rebirth|gh workflow run web-host-reboot' -- knowledge-base/engineering/operations` prints only lines that sit under a dated RETIRED/Done/Superseded marker or are the runbooks' own preserved history (state the count and the disposition in the PR body); no unmarked present-tense dispatch instruction remains.
- [ ] AC8. ADR-263 frontmatter reads `status: accepted`; the Status section carries one dated "Accepted 2026-10-12" note; the addendum tail is a single 2026-10-12 entry that records the retirement and the supersession of the 2026-10-11 "Status. Unchanged" paragraph; no earlier sentence is rewritten (`git diff` shows added blockquote markers, the addendum and the single frontmatter line).
- [ ] AC8b. `git grep -n -i -E 'rebirth|reborn|plaintext|adopting|not yet (run|live)' -- knowledge-base/legal` hit count and disposition are stated in the PR body; any future-tense or conditional sentence about web-2's volume that this PR's ADR flip would make stale is routed to the CLO agent for append-only wording (none is expected: the ledger-flip PR superseded them, record `knowledge-base/legal/audits/2026-10-counsel-review-9372.md`).
- [ ] AC9. `bash scripts/regenerate-c4-model.sh` produces no further diff after the committed regeneration; `bash plugins/soleur/test/c4-count-parity.test.sh` passes (13); the C4 syntax and render tests pass.
- [ ] AC10. Runbook `web2-luks-rebirth-9372.md` rows 4 and 5 carry dated "done" lines; `web-host-reboot.md` carries the RETIRED banner; the learning file exists with the three requirements (content-level emptiness evidence, a second gate after the evidence step, a credential-parity check).
- [ ] AC11. `scripts/pre-push-ratchet-lane.sh` prints `RATCHET_LANE verdict=PASS`; `harness-parity-tree`, the three ratchet linters and the skill-body budget against the merge base pass; the required checks on the PR are green. The known pre-existing reds (`deploy-script-tests` Inngest pin; the #10003 push-apply failure) are named in the PR body and are not required checks.
- [ ] AC12. The PR body carries `Closes #9372`, `Ref #9642`, both "Ruled by CTO agent" lines, the Apply-gate analysis and the scope disclosure; `auto-close-scan.sh` over the title, body and every commit message returns exactly the one `Closes #9372` match (body only). Read from: scratch files fed to the scanner.

### Post-merge (operator-free, run by the agent)

- [ ] AC13. Both push-apply runs on the merge SHA meet the GO conditions of the Apply-gate analysis (baseline-relative for `apply-web-platform-infra.yml`, `No changes` plus `0 added, 0 changed, 0 destroyed` for `apply-deploy-pipeline-fix.yml`); any NO-GO is filed or commented, not ignored.
- [ ] AC14. On the merge SHA both workflow files are absent: first assert the SHA resolves (`gh api repos/jikig-ai/soleur/commits/<sha> --jq .sha` prints 40 hex characters; the SHA comes from `gh pr view 10083 --json state,mergeCommit` only once `state` is `MERGED`, and a short SHA makes `gh run list --commit` silently return nothing), then `gh api 'repos/jikig-ai/soleur/contents/.github/workflows/web2-luks-rebirth.yml?ref=<sha>'` returns a 404 whose body says `Not Found` (a bad ref says `No commit found for the ref`, hence the first assertion), with a positive control that the same call at the merge-base SHA returns 200. The listing `state` string GitHub shows for a deleted workflow is not asserted. The grader and the repo sweep are re-run once as evidence (Phase 7.2).
- [ ] AC15. The final comment on #9372 claims only the graded rows and states what is not claimed; #9372 is CLOSED; #9642 is CLOSED with the run IDs, ruling and learning path.

## Test Scenarios

- Given the 24 files are removed, when the Phase 1 census runs, then it prints nothing (unit; the failing-first test).
- Given `MAIN_ROOT_TF_WORKFLOWS` loses one entry, when `terraform-target-parity.test.ts` runs, then the census equals the derived workflow set and the suite reports the derived count (unit).
- Given `scripts/web2-rebirth.sh` is gone, when the G2 test runs, then the population floor and `naming > 0` rows hold and the scratch control returns `[]` for the web-2 pinned form and a hit for `hcloud_volume.inngest_redis_luks` (unit; mutation rows per the Guard Contract).
- Given only comments changed in the edited `.tf` files, when comments and blank lines are stripped from both sides, then the files are byte-equal (unit; scratch script quoted in the PR body).
- Given a suite or registration still names a deleted file, when `pre-push-ratchet-lane.sh` and `run-registered-suites.sh` run, then they fail naming it (integration; this is how a missed registration shows).
- Given the push-apply fires on the merge SHA, when its log is read with the discriminator, then only the two known egress provisioners fail (integration; read-only).
- Given the retirement landed, when the grader and `--repo-sweep` re-run, then both PASS (integration, read-only, credential-gated).
- Regression: none for a bug; the regression class guarded is "a retirement that leaves a tombstone, census or baseline red".

## Rollback

The change is subtractive, so rollback is a revert PR: `git revert <merge-sha>` restores the 24 files, the registrations and the baselines together (they are one commit group). A revert touches `apps/web-platform/infra/**` and `server.tf`, so it fires both push-apply workflows again: judge them with the same discriminator. Run the revert in a scratch detached worktree first and execute the gates the revert PR must pass (the ratchet lane and `terraform-target-parity.test.ts`, which re-adds the census entry and the tombstone coupling), then write the recipe into the PR body. Restoring a single deleted file without its registrations is not a rollback: the tombstone row and the census counts are hard RED on a half state.

## Risks and Sharp Edges

- **Hidden consumer of a deleted script.** The CTO's flip condition: any live caller found by the post-deletion census reverses ruling 1 for that script. Mitigation: the census runs without the file extension and without `knowledge-base` (history stays untouched there).
- **Ratchets that only see the committed tree.** `guard-vacuity-floor` enumerates with `git ls-files`: run it after `git rm`/commit, not before. File-selected runs hide repo-wide ratchets (the 2026-10-05 learning): use the ratchet lane.
- **A kept comment that claims what the code no longer proves.** Per the 2026-10-11 deleting-a-gate learning, review every rewritten sentence as code: each must be true of the tree after this PR (re-derive dates, run IDs and counts; do not copy them from this plan). In particular, do not write "LUKS-backed at boot" or "survives a reboot" anywhere; the graded claim is formatted/opened plus green probes.
- **The ADR-263 status flip is to `accepted`, not a claim of recovery or reopen.** The 2026-10-11 addendum's claim boundary must be cited, not widened.
- **The merge's push-apply will be red for an unrelated reason (#10003).** Say so in the PR body before the reviewer sees the red run; read the log with the discriminator rather than assuming.
- **`terraform-target-parity.test.ts` hard-codes `found.length`.** The set-equality assertion already derives the expected set, so keep a literal count as the independent floor and confirm it by running the suite (not copied from this plan).
- **A plan whose `## User-Brand Impact` section is empty or omits the threshold fails deepen-plan Phase 4.6.** It is filled above (`none`, with the sensitive-path scope-out line).
- **Do not edit inside a heredoc, `cloud-init*.yml` or `.tmpl`** to "fix" a stale word: that is a live `user_data` input (learning 2026-07-26).
- Commit messages and the PR title must not contain `Closes|Fixes|Resolves #N`; `Closes #9372` lives in the body only.

## Non-Goals

- No workflow dispatch, no hand `terraform apply`, no Doppler or GitHub-secret write, no change to the `web-platform-infra-apply` environment or its reviewers.
- No rename of `plaintext_workspaces_hosts`, no edit of `scripts/lib/web2-luks-rows.sh`, no edit of the ledger row or the legal registers (done in the ledger-flip PR).
- Not closed here and not re-filed: #9572 (HALT widening and the `random_password.workspaces_luks_web` import measurement, carried by #9948), #9984 (linter gaps), #9948 and #9949 (passphrase-loss recovery, re-escrow), #10003 (egress gateway provisioner). Each already has its own tracker; this PR adds none.

## References

ADR-263 (2026-10-05, 2026-10-07, 2026-10-08, 2026-10-11 addenda), ADR-241, ADR-140; runbook `knowledge-base/engineering/operations/runbooks/web2-luks-rebirth-9372.md` (Closing checklist rows 4 and 5, row-5 addendum); `knowledge-base/legal/audits/2026-10-counsel-review-9372.md`; `knowledge-base/project/plans/2026-10-10-feat-web2-luks-ledger-flip-and-article-30-closeout-plan.md`; `knowledge-base/project/specs/feat-one-shot-9372-web2-luks-ledger-closeout/`; `plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md`; issues #9372, #9642, #9572, #9984, #9948, #9949, #10003, #6931; sweeper run 38083925201; rebirth runs 37508997529 and 37516716515.
