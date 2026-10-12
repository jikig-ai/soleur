---
title: "fix: git-data rotate post-apply gate (#10137, #10067) and resume the LUKS cutover (#8211)"
date: 2026-10-12
slug: git-data-rotate-post-apply-gate-and-cutover-resume
branch: feat-one-shot-git-data-luks-cutover-8211
issue: 10137
# SUPERSEDED 2026-10-12: Phase 2 and closes: moved to PR #10155 (see ## Review reconciliation); this PR must not close #10137/#10067
closes: "#10137, #10067"
refs: "#8211, #8209, #8609, #8573, #9943, #10138, #6897, #8551, #10136, #9438"
lane: cross-domain
type: fix
brand_survival_threshold: aggregate pattern
---

# fix: git-data rotate post-apply gate and resume the LUKS cutover

## Enhancement Summary

**Deepened on:** 2026-10-12
**Sections enhanced:** Scope Check (rebuilt to the 4.12 schema), Observability (5-field schema), Risks (new), halt-gate results
**Method:** mechanical halt gates 4.6-4.12 run against this plan, plus targeted code reads (no broad agent fan-out: the plan is a CI assert plus documents, and the CTO and CLO were already consulted at plan time)

### Halt-gate results

| Gate | Result |
|---|---|
| 4.6 User-Brand Impact | PASS (aggregate pattern, concrete artifact and vector) |
| 4.7 Observability | was prose-only; now carries the 5-field schema; probe is `grep -c` (allowlisted verb, well under 15 s, literal expected output `1`) |
| 4.8 PAT-shaped variable | PASS (no hits) |
| 4.9 UI wireframe | not triggered (no UI-surface file) |
| 4.10 Encryption posture | not triggered (no `.tf`/migration/cloud-init in the file lists; no new store or connection) |
| 4.11 Guard Contract | `python3 scripts/lint-guard-contract.py` PASS (1 entry, 9 rows); assembly names the chokepoint and both entering dispatch targets, rows are design-derived |
| 4.12 Scope Check | was missing the three required subsections; rebuilt, 10 asks all mapped, 3 inferred rows each justified |

### New considerations discovered

- **The fix is necessary, not sufficient, for the flip gate.** `.github/workflows/git-data-cutover.yml` (d6 reader, near line 272) requires the `git_data_host_replace` JOB to conclude `success` AND the "rotate confirm token" step to conclude `success`. Run 38140050880 failed at the assert, so the steps after it (boot poll, pin_load redeploy, summary) have never run to completion on the rotate path. The re-dispatch after this merge will exercise them for the first time; the work phase must read those steps for rotate-specific assumptions (they were written against the plain replace) and record any finding on #10137 rather than widening this PR.
- **Step name stays byte-identical** (`Terraform apply (git-data-host -replace) — both-volumes-preserved assert`). The cutover reader keys on the job name and the rotate-confirm step name, not this one, but a rename buys nothing and widens the hunk.
- **No precedent for a mode-aware post-apply assert.** The registry, inngest and web jobs carry unconditional `VOL_DELETES` loops (different resources, no rotate arm). The pattern is novel; reviewers should scrutinize PA1-PA10 rather than assume a sibling.
- `tests/scripts/test-infra-privileged-tier-census.sh` mentions a step named `Terraform apply (git-data-host -replace)` at a different job position (web-platform workflow census); AC3 re-runs it, since the call edit changes that step's body but not its name.
- The `plan_gate_assert_numeric` call in the new function must be given every counter it reads, or a jq failure reads as 0 (the same hole the plan-time gate closes at its end).
- #9943: the check cannot live in `git-data-flag-precheck.sh` (credential census, prd-token isolation); CTO F6 revised accordingly. The liveness precheck needs the git-data Better Stack table pin; the design must say which exact query it runs so the probe cannot read the shared default table (the runbook records that the default table returns zero rows for this host).

## Overview

Resume the git-data LUKS cutover (#8211; runbook `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`; ADR-239) as far as it can go without a production write. Four ordered deliverables:

1. **Live flip-precondition report** (read-only operational report, a task, not code).
2. **Fix #10137** (closes #10067 as the same defect): the post-apply assert of the `git_data_host_replace` job fails on the rotate arm's intended `-replace` of `hcloud_volume.git_data_luks`. Extract the assert into a sourced, tested function.
3. **K1 non-main run census addendum** for #8209/#8609: a NEW legal-audit file, reviewed by `soleur:legal:clo`; no existing legal document is edited.
4. **Design documents only**: the wipe-body PR, the rollback rehearsal, and #9943 (machine-enforce the heartbeat precondition).

State at planning time (2026-10-12): the store serves from the LUKS mapper since boot; real modes (`proof|flip|rollback|unfreeze|redeploy`) are built; host-key pinning, pin-fault paging, the host liveness heartbeat, rung-2 boot rehearsal evidence and the posture exceptions (renewed to 2026-11-12) are merged. No real cutover has run. No workflow dispatch, terraform apply or production write is part of this plan.

## Research Insights

### Premise Validation (Phase 0.6)

Checked by `gh` and `git grep` against `origin/main` state in this worktree:

- Issues #8211, #10137, #10067, #8209, #9943, #10138, #10136, #8551: all OPEN (premises hold; nothing already resolved).
- PRs 10133, 10086, 7390: all OPEN; each edits `.github/workflows/apply-web-platform-infra.yml` (hunks at line 660, 2955 and 4898 respectively; the post-apply block is ~3943-4075, so no textual overlap today).
- `tests/scripts/lib/git-data-host-replace-gate.sh` EXISTS (315 lines, function `git_data_host_replace_gate <plan> [replace|rotate]`, plan-time gate). The brief's "extract into" means ADD a second function to it, not create the file. `tests/scripts/test-git-data-host-replace-gate.sh` exists (566 lines, anti-vacuity floor 55).
- `verdict=liveness_unproven` (named in #9943) does not exist anywhere in the repo: #9943 is a build, not a fix.
- The wipe body does not exist on main (deleted in #8189, commit 7fb9c5b399; the pre-#8189 `old_volume_wipe` is recoverable from that parent commit).
- ADR corpus check for mechanisms: ADR-239 (Retention end for the plaintext volume; "The wipe branch needs a rehearsal of its own") and ADR-220 D6 already fix the wipe's shape (the wipe PR destroys the volume itself, never mounts it, carries its own rung-2 rehearsal). Nothing proposed here sits in a rejected-alternatives table.
- Brief figures (51,876 non-main runs, 0 fork, 0 unresolved) are claims to re-derive, not facts.

### Property List (Phase 0.6b)

- P1. After a rotate apply, the post-apply assert passes when the LUKS volume was replaced as intended and fails if it was not replaced.
- P2. In both modes, a plan that deletes/forgets the plaintext volume `hcloud_volume.git_data` fails the post-apply assert.
- P3. In plain replace mode, a plan that deletes/replaces the LUKS volume fails the assert.
- P4. An empty, unreadable or mode-less input never passes.
- P5. The assert's decision logic is the same bytes the test suite exercises.
- P6. K1 census numbers are re-derived today, with counts and run ids only, and recorded without strengthening the legal disposition.
- P7. Each design (wipe, rollback rehearsal, #9943) states its interlocks so the later build PR cannot re-open an already-ruled fork.

### Cut List

- A new standalone gate file for the post-apply assert (cut): the existing sourced lib already hosts the plan-time gate and its harness; a second function there reuses the preamble and fixtures.
- Editing the existing #8209/#8609 records to add a pointer (cut): CLO Q3 ruling; deferred until after the 2026-10-24 re-ruling.
- Executing any design (cut): the brief makes them documents.
- A new ADR (cut): no architectural decision is made; the wipe design applies ADR-239 as written. If the wipe design changes the volume-destroy sequencing the wipe-build PR amends ADR-239 (noted in the design doc).
- A `git_data_luks` skip with no positive assertion (cut, see F1): replaced by a positive replace assertion.

### Learnings and file paths applied

- `tests/scripts/lib/plan-gate-preamble.sh` (`plan_gate_assert_readable|classifiable|numeric`): fail-closed preamble to reuse.
- `tests/scripts/lib/gate-suite-harness.sh`: shared harness.
- `plugins/soleur/test/terraform-target-parity.test.ts` (rotate set parity at ~2086-2180; `extractJobBlock(wf, "git_data_host_replace")` splits lines containing `EXTRA_`): the new call line must not contain `EXTRA_`, `-target` or `-replace` tokens, or the parity extraction changes.
- `tests/scripts/test-infra-privileged-tier-census.sh` greps the workflow for post-apply tokens; re-run it.
- Output discipline from the gate header: print counters, verdicts and addresses only, never `.change.before/after`.

## Research Reconciliation: Brief vs Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "Extract the loop into tests/scripts/lib/git-data-host-replace-gate.sh" | File exists and hosts the plan-time gate | Add `git_data_post_apply_gate` to it (CTO F2: whole post-apply block, not the loop alone) |
| "Skip git_data_luks in rotate mode" | The plan-time gate already REQUIRES `["delete","create"]` for it in rotate | Post-apply asserts the replace positively instead of skipping (CTO F1) |
| "empty resource_changes must not pass" | Preamble rejects a missing array; `[]` yields zero deletes and would pass the volume loop; only the NIC/attachment create asserts would incidentally fail it | Explicit `length > 0` check (CTO F3) |
| #9943: enforce in the flip precheck | `git-data-flag-precheck.sh` is bound to `DOPPLER_TOKEN_PRD` only; Better Stack creds are in `prd_terraform`; the credential census pins one credential per step | New dedicated script (CTO F6 revised) |
| "wipe-body PR (body deleted from main)" | Confirmed (#8189) | Design restores the canary idea, not the old code |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Re-verify flip preconditions against LIVE state (not runbook text)" [brief] | Phase 1 / flip-preconditions-report.md | mapped |
| 2 | "Fix #10137 (close #10067 as the same defect)" [brief] | Phase 2 / workflow + lib + test edits | mapped |
| 3 | "Extract the loop into tests/scripts/lib/git-data-host-replace-gate.sh, pass APPLY_TARGET in" [brief] | Phase 2 function contract (CTO F2 widened the extraction to the whole post-apply block) | mapped |
| 4 | "add three rows to tests/scripts/test-git-data-host-replace-gate.sh (plaintext deleted under rotate; LUKS deleted under plain replace; empty resource_changes must not pass)" [brief] | Phase 2 rows PA1-PA3 | mapped |
| 5 | "Keep plugins/soleur/test/terraform-target-parity.test.ts green. No workflow dispatch in this PR." [brief] | Phase 2 AC3, AC8 | mapped |
| 6 | "plan for rebase conflicts, do not touch their branches" [brief] | Phase 2 rebase-conflict plan | mapped |
| 7 | "K1 non-main run census for #8209 ... re-derive read-only, counts and run ids only" [brief] | Phase 3 | mapped |
| 8 | "Edit no existing legal document before the CLO ruling ... the addendum goes in a new file" [brief] | Phase 3 steps 6-9, AC6 | mapped |
| 9 | "Design only (documents, no execution): the wipe-body PR ..., the rollback rehearsal, and #9943" [brief] | Phase 4.1-4.3 | mapped |
| 10 | "Owner-gated, NOT in scope (list as remaining only)" [brief] | section Owner-gated and remaining | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.github/workflows/apply-web-platform-infra.yml` edit | "Fix #10137 (close #10067 as the same defect)" | asked |
| `tests/scripts/lib/git-data-host-replace-gate.sh` function | "Extract the loop into tests/scripts/lib/git-data-host-replace-gate.sh" | asked |
| `tests/scripts/test-git-data-host-replace-gate.sh` rows PA1-PA3 | "add three rows to tests/scripts/test-git-data-host-replace-gate.sh" | asked |
| rows PA4-PA12 (must-PASS, duplicate-entry, dispatch pin, output sentinel) | asks 3-4 only name three rows | inferred - justification: the Guard Contract (plan Phase 2.12) requires must-PASS rows and a dispatch-pin row or the guard is satisfiable by a stub |
| Positive LUKS-replaced assertion under rotate (instead of a bare skip) | "In rotate mode skip git_data_luks in the post-apply delete/forget loop" | inferred - justification: CTO F1; a bare skip would pass a rotate that never replaced the volume |
| Extraction widened to NIC and attachment asserts | "Extract the loop" | inferred - justification: CTO F2; the block is one contiguous hunk, cheaper to rebase and puts those asserts under test |
| `plugins/soleur/test/terraform-target-parity.test.ts` (only if extraction breaks) | "Keep plugins/soleur/test/terraform-target-parity.test.ts green" | asked |
| `flip-preconditions-report.md` | "Report each verified or not; never infer." | asked |
| K1 addendum under knowledge-base/legal/audits/ | "a new file under the knowledge-base legal-audit area" | asked |
| `design-wipe-body-pr.md`, `design-rollback-rehearsal.md`, `design-9943-liveness-precheck.md` | "Design only (documents, no execution)" | asked |
| `decision-challenges.md` and `tasks.md` | "record `Ruled by CTO agent, <date>: <decision> - <rationale>` in a `| Item | Class | Ruling |` table" | asked |

### Split Assessment

- Subsystems touched: 4 - `.github`, `tests`, `plugins` (conditional), `knowledge-base`
- Planned files: 12 (3 edits + 1 conditional edit + 8 new documents/evidence files) | Estimated changed lines: ~700 (code ~250, documents ~450)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the `plugins` root is touched only if the parity extraction breaks; documents live in new files and cannot conflict with the code hunk. If review prefers, the seam is "Phase 2 first, documents after" with no rework.

## Open Code-Review Overlap

None. (Checked all open `code-review` issues' bodies for: `apply-web-platform-infra.yml`, `git-data-host-replace-gate.sh`, `test-git-data-host-replace-gate.sh`, `terraform-target-parity.test.ts`, `git-data-flag-precheck.sh`, `git-data-cutover.yml`; zero matches.)

## Implementation Phases

### Phase 1 - Live flip-precondition report (task, read-only, no code)

Output: `knowledge-base/project/specs/feat-one-shot-git-data-luks-cutover-8211/flip-preconditions-report.md`. One row per precondition: `VERIFIED` (with the command, the run id or timestamp read, and the literal result) or `NOT VERIFIED` (with why). Never infer from runbook text or from a merged PR. Values (tokens, DSNs, the pin's key material) are never printed; the pin fingerprint may be recorded as `SHA256:` prefix-8 only if already public in a step summary.

| # | Precondition | Live read | Pass condition |
|---|---|---|---|
| 1.1 | `git_data_ssh_client=present` on the DEPLOYED build | `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 30m --grep git_data_ssh_client=` (widen `--since` to the last restart if empty; read the deployed version from the web-platform release run so "deployed build" is tied to a sha) | a row with `git_data_ssh_client=present` dated after the deployed build's start; empty = NOT VERIFIED |
| 1.2 | pin present in `prd` | `doppler secrets --only-names --json -p soleur -c prd \| jq -e 'has("GIT_DATA_SSH_HOST_KEY")'` (names only; confirm exact secret name from `git-data-flag-precheck.sh` first); then a Better Stack read `--grep 'git_data_pin=present fp='` for the loaded fingerprint | name present AND a post-redeploy `git_data_pin=present` line; absence = NOT VERIFIED |
| 1.3 | live pin-fault Sentry rule (rule 1310055) | `scripts/sentry-alert-live-fidelity.sh` (needs `SENTRY_ACTIONS_RO_TOKEN`), or the latest `scheduled-sentry-alert-drift.yml` / `apply-sentry-infra.yml` run via `gh run list --workflow ... --limit 1 --json conclusion,createdAt,databaseId` then its summary for `sentry_alert live fidelity: PASS`; assert rule enabled, `in` set = `host_key_mismatch,pin_absent,pin_invalid,ssh_client_absent`, issue-owner email action | PASS read from a run no older than 24 h, or a fresh live script run; a stale run = NOT VERIFIED |
| 1.4 | host liveness heartbeat | heartbeat status read of `soleur-git-data-host-prd` (use the status path in runbook "Liveness heartbeat" step 7 without putting a token in argv) AND the latest `stage=liveness` `state=ok` event and the current host's `boot_complete` via `scripts/betterstack-query.sh` with the git-data table pin (`t520508_soleur_git_data_prd_logs` UNION archive, `host_name=soleur-git-data`) | status `up`, newest `state=ok` event age < 15 min, and its timestamp > `boot_complete` timestamp; the three timestamps are recorded |
| 1.5 | (context, not a gate) `d6_replace_stale` | `gh run list --workflow apply-web-platform-infra.yml` for a successful rotate | expected NOT satisfied: run 38140050880 concluded failure; this is why Phase 2 exists |

Notes: all four reads are owner-authorized read-only reads by the standing brief; if a credential is unavailable in the session, record `NOT VERIFIED: credential unavailable` and stop that row (do not substitute). Each Better Stack query is bounded (`--since`, LIMIT) per `hr-never-run-commands-with-unbounded-output`. The report also lists, as "remaining", the owner-gated items (below).

### Phase 2 - Fix #10137 (closes #10067)

**Files to Edit**

- `.github/workflows/apply-web-platform-infra.yml` - in the `git_data_host_replace` job, step `Terraform apply (git-data-host -replace) — both-volumes-preserved assert` (starts ~3943): keep the `terraform apply` + failure-recovery block unchanged; replace the post-apply `for VOL`, `NIC_CREATES` and `for ATT` blocks (~4038-4065) with one sourced call. Add `APPLY_TARGET: ${{ inputs.apply_target }}` to the step `env:`. Keep the step NAME byte-identical: the flip gate (`git-data-cutover.yml` d6 / rotate-confirm logic) and other tests may key on step names, and a rename widens the rebase-conflict surface. Run `git grep -n "both-volumes-preserved"` first to list consumers.
- `tests/scripts/lib/git-data-host-replace-gate.sh` - add `git_data_post_apply_gate <tfplan.json> <apply_target>` (see contract below); update the header's Usage block.
- `tests/scripts/test-git-data-host-replace-gate.sh` - add the rows below; raise the anti-vacuity floor from 55 to (55 + number of new assertions) and update the message text.
- `plugins/soleur/test/terraform-target-parity.test.ts` - only if a new assertion is wanted that the workflow step calls the function (preferred: put that dispatch pin in the shell suite; touch this file only if the existing extraction breaks). It must stay green either way.

**Function contract (CTO F1-F3)**

```bash
# Usage: git_data_post_apply_gate <tfplan.json> <apply_target>   # 0 = PASS, 1 = ABORT
# apply_target must be exactly git-data-host-replace or git-data-host-rotate; anything else
# (including empty) refuses.
```

Logic, in order, each refusing with a counter/address-only message (never `.change.before|after`):

1. `plan_gate_assert_readable` + `plan_gate_assert_classifiable` (existing preamble), then explicit `(.resource_changes | length) > 0` (an empty array refuses with its own message; do not rely on later create asserts).
2. `apply_target` is one of the two literals; else refuse (wiring fault).
3. Plaintext `hcloud_volume.git_data`: 0 entries whose actions include `delete` or `forget` - BOTH modes. An address absent from `resource_changes` counts as 0 (the canonical plan omits untargeted volumes; requiring presence would redden the canonical PASS fixture).
4. LUKS `hcloud_volume.git_data_luks`: under `git-data-host-replace` 0 delete/forget (absent is valid). Under `git-data-host-rotate` the entry MUST be present with exactly `delete` AND `create` (positive replace assertion; a bare skip would pass a rotate that never replaced the volume).
5. `hcloud_server_network.git_data` has a `create`; `hcloud_volume_attachment.git_data` and `hcloud_volume_attachment.git_data_luks` each have a `create` (moved verbatim from the workflow, same wording of the existing error text so log-greps keep working).
6. Counters are passed through `plan_gate_assert_numeric` before use (a jq failure must not read as 0).

Workflow call (one contiguous hunk, no `EXTRA_`/`-target`/`-replace` tokens on the line):

```bash
source "${GITHUB_WORKSPACE}/tests/scripts/lib/git-data-host-replace-gate.sh"
git_data_post_apply_gate tfplan.json "${APPLY_TARGET}" || exit 1
```

The `fp=` (host-key fingerprint) tail of the step stays outside the function.

**Test rows (shell suite, all synthesized fixtures)**

| Row | Mode | Fixture | Expect |
|---|---|---|---|
| PA1 (brief row 1) | rotate | plaintext `hcloud_volume.git_data` `["delete","create"]` + a valid rotate set | rc 1 |
| PA2 (brief row 2) | replace | `hcloud_volume.git_data_luks` `["delete","create"]` + valid replace set | rc 1 |
| PA3 (brief row 3) | both | `{"resource_changes":[]}` | rc 1 each, with the explicit empty message |
| PA4 | rotate | canonical rotate: LUKS `["delete","create"]`, NIC + both attachments create, plaintext absent | rc 0 (must-PASS, differs from the replace canonical) |
| PA5 | replace | canonical replace: volumes absent | rc 0 |
| PA6 | replace | plaintext as explicit `["no-op"]` and LUKS `["no-op"]` | rc 0 (must-PASS, non-canonical shape) |
| PA7 | rotate | LUKS `["delete"]` only (no create) and LUKS absent | rc 1 each |
| PA8 | both | NIC create missing; each attachment create missing (3 sub-rows) | rc 1 |
| PA9 | n/a | apply_target empty / `git-data-host-create` / `workspaces-luks-cutover` | rc 1 |
| PA10 | rotate | duplicate-address second `hcloud_volume.git_data` entry with `["delete"]` after a compliant no-op first entry | rc 1 |
| PA11 | n/a | output discipline: plant a sentinel in `.change.before` and assert it is absent from stdout | rc 0/1 as the fixture dictates, sentinel never printed |
| PA12 | n/a | dispatch pin: the workflow's apply step contains the sourced call with `"${APPLY_TARGET}"` (grep the workflow job block) | present |

Run: `bash tests/scripts/test-git-data-host-replace-gate.sh`, `bash tests/scripts/test-infra-privileged-tier-census.sh`, `bun test plugins/soleur/test/terraform-target-parity.test.ts` (use the repo's runner invocation), `shellcheck` on both shell files, and the `terraform-target-parity` job-block extraction for `git_data_host_replace`.

**Rebase-conflict plan (PRs 10133, 10086, 7390)**

- Their hunks (line ~660, ~2955, ~4898) do not overlap the ~3943-4075 region today. The change here is one contiguous hunk replacing ~28 lines with ~3, plus one `env:` line, so it is the cheapest shape to rebase either way.
- Do NOT touch their branches. Whichever PR merges second rebases onto main. Before pushing: `git fetch origin main && git merge origin/main` (merge, not force-push), re-run the three commands above. If `git diff origin/main -- .github/workflows/apply-web-platform-infra.yml` shows main moved inside the step, re-read the step from main and reapply the call hunk by hand; never resolve with "ours".
- Line numbers in this plan are anchors only; locate by the step name and the `for VOL in hcloud_volume.git_data` text (`cq-cite-content-anchor-not-line-number`).
- No workflow dispatch in this PR. Mark the PR body `Closes #10137` and `Closes #10067`; note that the rotate re-dispatch (`apply_target=git-data-host-rotate`, `confirm=ROTATE-GIT-DATA`) is owner-gated and happens only after this merges.

### Phase 3 - K1 non-main run census addendum (#8209 / #8609)

Output: NEW file `knowledge-base/legal/audits/2026-10-12-8209-k1-nonmain-run-census-addendum.md` (the legal-audit area; verified directory exists and holds the 8209/8609 records). No existing legal document is edited (CLO Q3).

Method (CTO F4; CLO Q1-Q4; reuses the 8209 L1(b)-(c) commands unchanged):

1. Derive the workflow set from the repository with the WIDER #8609 K1 pattern (a superset of the #8209 L1(a) set): `grep -rlE 'secrets\.(DOPPLER_TOKEN[A-Z0-9_]*|WEBHOOK_DEPLOY_SECRET|CF_ACCESS_CLIENT_(ID|SECRET))\b|toJSON\(secrets\)' .github/workflows/`. Also count the #8209 L1(a) subset so the result stays comparable with 51,876. Registry push credential secret names are added from the repo at census time, as the 8609 record says.
2. Per workflow, `gh api repos/jikig-ai/soleur/actions/workflows/<wf>/runs --paginate --jq` selecting `head_branch != "main"`, emitting run id, branch, event, created_at, fork flag, actor login. Output goes to `$K1_DIR` outside the repository under NEW filenames (never overwrite a cited file). Bound pagination progress with counts per workflow; this is a large read (tens of thousands of rows), so write TSV to `$K1_DIR` and print only `wc -l` and aggregates.
3. L1(c): for each run, resolve `head_sha` and count files under `.github/workflows/` in that commit (by SHA, so deleted branches resolve); a 404 is "not resolvable", counted separately. "0 unresolved" is recorded only if this step was actually run; otherwise "not run".
4. No log body is read or downloaded (`gh run view --log`, `.../logs` are out of scope).
5. Record: census date; coverage window `[date - 90d, date]`; total; per workflow; per actor; fork/non-fork split; workflow-touching subset; unresolved count; run ids (the full id list lives in the `$K1_DIR` file, cited by filename; the addendum carries the ids of any non-clean row and a content hash of the list); the delta against the brief's 51,876 / 0 / 0 stated as superseded by today's re-derivation with the reasons (new runs accrue; retention expires old ones). Never force-match.
6. Disposition language (CLO): `K1 CLEAN within [census date - 90d, census date]` only; the part of the exposure window before the horizon is INCONCLUSIVE for good; L2-L5, K0, K2-K4 stay INCONCLUSIVE; K4 cannot be measured by Jikigai; the limb row reads "INCONCLUSIVE, partially run: CLEAN within window"; the phrases "no evidence", "no indication of misuse", "no unauthorized use" and any claim that the reachability disposition was strengthened are forbidden; the closing re-pull after R6 stays recorded as owed.
7. Frontmatter: `type: clo-attestation`, `status: SIGNED-OFF PROVISIONAL (CLO-agent-attested, Soleur-as-tenant-zero v1, <date>)`, `issue: 8209` and `8609`, `art_33_triggered`/`art_34_triggered` set to the finding (not copied), `open_limbs`, operator veto retained; cites code and run files by name, not by line. Wording conditioned on merge ("fires on the merge of PR #N").
8. Non-clean branch (CLO Q4): a fork run, an unattributable run, or a workflow-touching run that reached a `prd`-resolving token starts a FRESH 72 h Art. 33(1) clock from awareness; the addendum records the awareness timestamp and run ids only, sets `art_33_triggered` accordingly, and the session notifies the owner immediately (the controller decides and sends); it does not wait for the 2026-10-24 re-ruling. A purely unresolved run (commit gone) is INCONCLUSIVE with a count, escalated only if it names a `prd`-resolving workflow on a non-allowlisted actor.
9. `soleur:legal:clo` reviews and signs the file as the last step of the phase; the file is not committed before the CLO has seen the actual counts. A pointer in the 8209/8609 records is deferred to after the CLO re-ruling (#8551 / #10136 track the wording).

### Phase 4 - Design documents (no execution)

Three files under `knowledge-base/project/specs/feat-one-shot-git-data-luks-cutover-8211/`:

**4.1 `design-wipe-body-pr.md`** (CTO F5; ADR-239 Retention end; #10138 decision 1). A new `mode=wipe` in `.github/workflows/git-data-cutover.yml`: one job behind the `web-platform-infra-apply` reviewer-gated environment, `confirm` token plus a typed `volume_id` input that must equal the volume id on the Hetzner object (106867358 per ADR-239 at the time of writing; re-read, never trust the doc). Same-session sequence, fail-closed at every step: (a) re-read a fresh `boot_complete` for the CURRENT host (LUKS serving, `plaintext_volume=present plaintext_empty=yes served_repos=0` fields as the runbook defines them); (b) over the existing SSH bridge, in the same job, assert the store root is the LUKS mapper (`probe=store-on-mapper`), that the plaintext device is NOT mounted read-write and has no open handles, its device/UUID/label match the volume's Hetzner attachment, and emptiness (the residue count the boot step already computes; non-empty means STOP and route to the CLO, never wipe); (c) only then the ID-pinned Hetzner `DELETE /volumes/<id>` (Hetzner refuses while attached, so the detach and delete are separate recorded API calls); (d) read back 404 as the end event, written as evidence; (e) same PR removes `hcloud_volume.git_data`, its attachment and the cloud-init plaintext branch from Terraform, with the destroy-guard updated so the removal is the ONLY permitted destroy; (f) the render branch with empty `git_data_volume_id` carries its own rung-2 rehearsal declared under `RUNG2_VAR_DIVERGENCE` (ADR-239); (g) payload hash-binding follows the two-PR sequence in `git-data-rung2-rehearsal.md`. Interlocks listed, with the reordering mutation (identity read moved before the freeze/boot read must red a test that observes inside the window). Also lists: pre-reqs (flip done, soak, #8573/#8609/#8209 chain, CLO date 2026-11-12), the owner-named-command gate, the ADR-239 amendment the build PR must carry, and the #8571 copy-mode dependency.

**4.2 `design-rollback-rehearsal.md`** (runbook "Before the first flip"). Flip-then-rollback rehearsal sequence on the real mechanisms (`flip` -> redeploy -> `rollback` -> readback `git_data_store=disabled` -> unfreeze), the erasure probe after rollback with a synthetic canary id through the CI root key AND an app-path signal (pin-fault rule state plus an `erasure_outcome` event for a canary id), the evidence template to record in the runbook (run URLs; "not yet run" is replaced only by a real run), abort criteria, the blast radius table row it uses (freeze window), what a dry run can and cannot prove, and the authorization (owner-named command per step; a menu answer is not authorization).

**4.3 `design-9943-liveness-precheck.md`** (CTO F6, revised). New `apps/web-platform/infra/git-data-liveness-precheck.sh` + `git-data-liveness-precheck.test.sh`; a separate step in `git-data-cutover.yml` bound ONLY to `DOPPLER_TOKEN` (`prd_terraform`), `mode=flip` only, ordered after the flag precheck and before freeze; emits `verdict=liveness_unproven` (exit 5) unless the `soleur-git-data-host-prd` heartbeat reads `up` AND a `stage=liveness state=ok` event exists later than the current host's `boot_complete` and is under 15 minutes old; API error, empty or unparseable result refuses; reuses `BETTERSTACK_API_TOKEN_READONLY` + the existing query credentials (no new secret); credential-census entry and the workflow header credential list updated in the build PR; test rows (heartbeat down, paused, no event, stale event, event older than boot_complete, API error, query empty, happy path) with stubs; a mutation row that reorders the freshness check after the host read. The build PR edits `git-data-cutover.yml`, which carries the no-admin-merge restriction (the issue says so); runbook item 2 of the preconditions is updated from "the only control" to "enforced by".

## Guard Contract

### Guard 1 — git_data_post_apply_gate (post-apply preservation assert, rotate-aware)

**Property.** After a git-data replace or rotate apply, the saved plan shows the plaintext volume untouched in both modes and the LUKS volume untouched under replace but replaced (delete and create) under rotate, with the NIC and both store attachments created, and nothing passes on an empty, unreadable or mode-less input.

**Assembly.** The chokepoint is the single function `git_data_post_apply_gate` sourced by the one apply step of the `git_data_host_replace` job; that job is entered by BOTH `apply_target=git-data-host-replace` and `apply_target=git-data-host-rotate` (the job `if:`), so one call site covers both modes. The inputs it quantifies over: the two volume addresses, `hcloud_server_network.git_data`, the two `hcloud_volume_attachment.git_data*` addresses, every entry of `.resource_changes[]` (duplicates by address included), and the `apply_target` literal. Sibling surfaces explicitly outside it: the plan-time gate `git_data_host_replace_gate` (already grades rotate), the registry/inngest/web post-apply loops (different resources), and `hcloud_volume.git_data_luks` handling in `git-data-cutover.yml`'s `d6_replace_stale` reader. The step's `APPLY_TARGET` env and the plan step's `inputs.apply_target` must be the same source; the dispatch pin (PA12) asserts the former.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Plaintext volume `["delete","create"]` under rotate | RED (PA1) |
| 2 | LUKS volume `["delete","create"]` under replace | RED (PA2) |
| 3 | `{"resource_changes":[]}` in both modes | RED (PA3) |
| 4 | LUKS `["delete"]` only, and LUKS absent, under rotate | RED (PA7) |
| 5 | apply_target empty or another dispatch target | RED (PA9) |
| 6 | Second duplicate `hcloud_volume.git_data` entry with delete after a compliant first entry | RED (PA10) |
| 7 | Remove the sourced call from the workflow step (own dispatch) | RED (PA12) |
| 8 | Reorder: evaluate the mode switch after the volume loop so a rotate-skipped LUKS check also skips the plaintext check | RED (PA1 observes the plaintext check inside the rotate branch) |
| 9 | Weaken the empty check to the preamble only | RED (PA3) |

**Harness rows.** (a) Delete one PA row from the suite: the raised anti-vacuity floor goes RED. (b) Must-PASS non-canonical: PA6 (explicit no-op entries) and PA4 (rotate shape differs from the replace canonical). (c) A suite that reports `0 passed, 0 failed` exits non-zero via the floor.

**Anchor.** No stored value is compared; the guard grades a plan document produced in the same job. The plan-time gate is the independent authority for the rotate set; the parity test pins the job's -target/-replace set against it.

## Domain Review

**Domains relevant:** Engineering (infrastructure), Legal

### Engineering

**Status:** reviewed
**Assessment:** CTO rulings F1-F6 recorded in `decision-challenges.md` (post-apply assert extraction and positive rotate assertion, fail-closed on empty/unknown input, wipe as a `mode=wipe` in the cutover workflow, #9943 as a dedicated precheck script bound to the `prd_terraform` token).

### Legal

**Status:** reviewed
**Assessment:** CLO framing for the K1 addendum (wording limits, clo-attestation PROVISIONAL, new file only, non-clean branch triggers a fresh Art. 33 clock) is incorporated in Phase 3. The addendum itself is reviewed and signed by `soleur:legal:clo` after the counts exist.

No Product/UX surface: no UI files in the lists (mechanical UI override: none match).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly; a gate that wrongly refuses blocks the cutover chain (the flip stays unreachable, so the LUKS store keeps serving as today); a gate that wrongly passes cannot cause or prevent a destroy (revised 2026-10-12: the post-apply gate only detects after the apply; the destroy authority is the plan-time gate, see `## Review reconciliation`), so the failure mode is the wrongly-refusing gate that turns an already-applied rotate red (#10137).

**If this leaks, the user's data is exposed via:** no new exposure vector: the gate prints counters and addresses only (PA11 holds the `.change.before/after` sentinel); the census records counts and run ids only, never a log body or secret value.

**Brand-survival threshold:** aggregate pattern. Reason: this PR changes a CI assert and adds documents; the user-visible destructive step (the wipe) and the flip are design-only here and stay owner-gated. A `single-user incident` threshold applies to three later PRs (revised 2026-10-12): the rollback-rehearsal build PR, the first real `flip`, and the wipe-build PR; each must carry CPO sign-off.

## Observability

The change touches `.github/workflows/` and `tests/scripts/` (CI assert only; no application server code). The signal is the existing job verdict plus `::error::` annotations that name the address and action count.

```yaml
liveness_signal:
  what: the git_data_host_replace job's post-apply step reports the assert result (annotation names address + action count) and the Dispatch summary step turns a missing verdict red
  cadence: per dispatch of apply_target git-data-host-replace or git-data-host-rotate (owner-gated, rare)
  alert_target: GitHub Actions run conclusion read by git-data-cutover.yml d6_replace_stale and the failed-run notification path
  configured_in: .github/workflows/apply-web-platform-infra.yml (git_data_host_replace job) and tests/scripts/lib/git-data-host-replace-gate.sh
error_reporting:
  destination: GitHub Actions ::error:: annotations on the run, no values printed
  fail_loud: the function returns 1 and the step runs exit 1; an unknown apply_target or empty plan refuses rather than passing
failure_modes:
  - mode: rotate that did not replace the LUKS volume, or any delete of the plaintext volume
    detection: git_data_post_apply_gate counters read from the saved tfplan.json
    alert_route: step failure, run conclusion failure, annotation
  - mode: empty or unreadable plan document
    detection: plan_gate_assert_readable plus the explicit length check
    alert_route: step failure with the explicit empty message
  - mode: call removed from the workflow step (guard silently dropped)
    detection: dispatch pin row PA12 in the shell suite run by CI
    alert_route: CI failure on the PR that removes it
logs:
  where: GitHub Actions run log (public repo; counters and addresses only)
  retention: 90 days (repository Actions retention)
discoverability_test:
  command: grep -c 'git_data_post_apply_gate tfplan.json' .github/workflows/apply-web-platform-infra.yml
  expected_output: 1
```

## Encryption Posture, ADR, C4, IaC

- Encryption posture: no new store or connection (docs and a CI assert). Skipped.
- ADR/C4: no architectural decision is made; the designs apply ADR-239/ADR-220 as written. The wipe-build PR amends ADR-239 (noted in 4.1). The `c4-count-parity` test is unaffected (no model file is touched); `bash plugins/soleur/test/c4-count-parity.test.sh` is run once at work time to confirm.
- IaC: no new infrastructure; the workflow edit is the existing apply path. No `terraform apply` or dispatch here.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| A rebase onto a moved main drops or duplicates the call hunk | Merge origin/main before push; reread the step from main; re-run the three test commands (Phase 2) |
| New rows raise the anti-vacuity floor wrongly | Floor is a count floor, set to 55 + new assertions; deleting a row reds it (harness row a) |
| The post-apply gate rejects a legitimate rotate because terraform reports the LUKS volume with an action order or extra action (for example `["create","delete"]` for create-before-destroy) | Match on the set of actions (index of both `delete` and `create`), mirroring the plan-time gate's own `lvr` predicate; read that predicate before writing the function and reuse its jq |
| Census output is large and slow | Write TSV to `$K1_DIR`, print aggregates only, run in background with Monitor |
| Census finds a non-clean row | CLO Q4 branch: fresh Art. 33(1) clock, immediate owner notice, no wait for 2026-10-24 |

## Owner-gated and remaining (NOT in scope; listed only)

1. `HCLOUD_TOKEN`, then `CF_API_TOKEN_R2`, then `TF_STATE_AWS_*` rotation (#8209).
2. G2 probes; G1 last.
3. Windowed prd write credential (#8573, #8609).
4. Rotate re-dispatch (`apply_target=git-data-host-rotate`, `confirm=ROTATE-GIT-DATA`) only after this fix merges; the owner names the command.
5. Flip-then-rollback rehearsal (designed in 4.2); `flip`; the wipe (#10138; designed in 4.1).
6. After flip: 7-day soak, ADR-068 to `accepted`, close #6897.
7. Decision dates: CLO re-ruling 2026-10-24; plaintext-volume retention 2026-11-12 (a second slip returns to the CLO per ADR-239 Amendment 2026-10-12).
8. Build PRs that follow the designs: wipe body, rollback-rehearsal dispatch, #9943 precheck.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1. `bash tests/scripts/test-git-data-host-replace-gate.sh` exits 0; rows PA1-PA12 present; the anti-vacuity floor is raised by the count of new assertions and no existing row is removed.
- [ ] AC2. In the workflow, the post-apply `for VOL`/NIC/attachment blocks are gone from the step and replaced by the sourced call with `"${APPLY_TARGET}"`; step name unchanged; `APPLY_TARGET: ${{ inputs.apply_target }}` in the step `env:`.
- [ ] AC3. `plugins/soleur/test/terraform-target-parity.test.ts` and `tests/scripts/test-infra-privileged-tier-census.sh` pass; `shellcheck` is clean on both shell files.
- [ ] AC4. `python3 scripts/lint-guard-contract.py` passes on this plan.
- [ ] AC5. `knowledge-base/project/specs/feat-one-shot-git-data-luks-cutover-8211/flip-preconditions-report.md` exists with one VERIFIED / NOT VERIFIED row per precondition, each citing the command and the literal value read; no secret value appears.
- [ ] AC6. The K1 addendum exists at the new path; `git diff --stat origin/main` shows NO modification to any existing file under `knowledge-base/legal/`; it uses only the CLO-permitted phrasing and records the delta against 51,876; CLO review result is recorded in it.
- [ ] AC7. The three design files exist and each lists interlocks, preconditions and the owner-named-command gate; no execution occurred.
- [ ] AC8. PR body carries `Closes #10137` and `Closes #10067`; no workflow was dispatched; no file outside this plan's lists was changed; AGENTS.rules.md, `.mcp.json`, `git-data-gc.sh`, `.gc-cursor` and the PR #9466 worktree are untouched; the branches of PRs 10133, 10086, 7390 are untouched.

### Post-merge (owner)

- [ ] AC9. Owner-gated actions in the list above proceed only on a named command; none is performed by this PR.

## Test Scenarios

- Rotate with the LUKS volume replaced and plaintext untouched: PASS. Same plan under plain replace: ABORT.
- Plain replace with canonical omission of both volumes: PASS.
- Any plan with `resource_changes: []`: ABORT with the explicit message.
- A synthetic rotate where the old LUKS volume was never replaced: ABORT.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty or placeholder fails deepen-plan Phase 4.6; this one declares the threshold.
- Keep the new workflow line free of the tokens `EXTRA_`, `-target` and `-replace`: the parity test's `extractJobBlock` splits on `EXTRA_` and regex-scans `-target`/`-replace`.
- Absence-by-omission is the canonical replace plan shape: never require a volume address to be present in replace mode.
- Do not print `.change.before`/`.after` (old user_data embeds the old host private key and this lands in a public log).
- Census output files live outside the repo; the addendum cites them by new filename and hash, never by pasting rows of actors beyond counts and run ids.
- The `$K1_DIR` census is a long paginated read; run it as a bounded background command with `Monitor`, not a foreground poll.

## Review reconciliation (2026-10-12)

This section is appended after review. The text above is left as written; where it conflicts with this section, this section wins.

### Phase 2 is SUPERSEDED by PR #10155

- Phase 2 (the post-apply gate) and `closes: "#10137, #10067"` no longer apply to this PR. The code change was reverted from this branch (commit `fa58f3388e`); the implementation is preserved at `d2a1d0e766`.
- Open sibling PR #10155 (`feat-one-shot-10137-rotate-arm-volume-assert`, same author, reviewed, at ship) carries the same fix with the same three required rows. The posture-assert rows and pins were hardened there instead. This PR is now documents and designs only and must NOT say `Closes #10137` or `Closes #10067`. #10155 closes only #10137 (`gh pr view 10155 --json closingIssuesReferences` returns #10137 alone); #10067 ("fix: git-data-host-rotate asserts both volumes on the rotate path", same defect) is NOT closed by it. To-do for the ship step: when #10155 merges, close #10067 by hand with a comment linking #10155. AC8 above (PR body carries `Closes #10137`) is withdrawn.

### Stale statements corrected

- "The steps after the assert have never run to completion on the rotate path": wrong. In rotate run `38140050880` the assert step failed, but `Poll for the git-data boot-completion signal (replace)`, `Load the rotated git-data pin (same-version redeploy)` and `Dispatch summary` concluded `success` (`Post-replace readiness note (non-SSH)` was skipped). The "read those steps for rotate-specific assumptions" instruction is therefore partly obsolete.
- Phase 1 row 1.5 "(context, not a gate)" for `d6_replace_stale`: wrong. The cutover precheck ends with `fail d6_replace_stale ...`, so it is a hard gate for a flip dispatch (see `flip-preconditions-report.md` row 1.5; tracker #10166). The Enhancement Summary note on the d6 reader ("near line 272") is a line-number citation and is stale; locate it by the `d6_replace_stale` content anchor.
- "PRs 10133, 10086, 7390: all OPEN": PRs 10133 and 10086 are MERGED; 7390 is still open.
- The apply step `Terraform apply (git-data-host -replace) — both-volumes-preserved assert` starts near line 4014 of `apply-web-platform-infra.yml`, not ~3943.

### User-Brand Impact, re-read

- The post-apply gate only DETECTS after the apply: it re-grades the saved plan after `terraform apply` has run, so a wrongly-passing post-apply gate can neither cause nor prevent a destroy. The destroy authority is the plan-time `git_data_host_replace_gate`, which refuses before apply. The real failure mode of the old assert was a wrongly-refusing gate that turned an already-applied rotate red, which is #10137.
- The K1 non-main run census addendum (`knowledge-base/legal/audits/2026-10-12-8209-k1-nonmain-run-census-addendum.md`) is a posture-bearing artifact. It stays `aggregate pattern` (an attribution-only result, internal record, no user data path) and its "K1 CLEAN" label is an attribution result, not a no-incident finding.
- `single-user incident` applies to three later PRs, not to this documents-only PR: the rollback-rehearsal build PR (its flag-on window is a real production flip), the first real `flip`, and the wipe-build PR. Each must carry CPO sign-off.
- Hard precondition row for the first real flip: #10166 (the d6 reader accepts a plain replace, skips a newer failed rotate, and accepts a `plan_only=true` rotate). Until it is settled the human gate is the only control that a rotate really completed.
- Blast radius of a rotate re-dispatch: it triggers a same-version fleet redeploy (web-1 restart about 75 s per the runbook), which the User-Brand text above does not mention.

### Pre-existing P1 hazard (data-integrity review): rotate precondition can destroy the only copy

The rotate precondition `Rotate precondition — served store measured empty` reads only the latest `stage=boot_complete` row for the git-data host: no time bound, not tied to the current server creation, and it does not read `GIT_DATA_STORE_ENABLED`, the `GIT_DATA_LUKS_CUTOVER_AT` stamp or the freeze sentinel. After the first flip, users replicate repositories to git-data without a reboot, so the row still says `served_repos=0`; a `git-data-host-rotate` dispatch would pass that precondition and the plan-time gate (exact delete+create) and destroy the LUKS volume while the plaintext volume is empty by construction, losing every replicated repository. It is latent today (flag false, flip not done).

Precondition for ever re-dispatching rotate: never after the flip; require the flag false AND the stamp absent (or a recorded rollback newer than the stamp) AND the boot row at or after the current server's creation. The runbook "D6 rotate" section must say "never after the flip". This needs its own tracked issue; it is NOT filed here.

### To file

Only the first item was filed (#10175); the other two are not left as to-dos of this PR.

- The rotate-precondition hazard above (own tracked issue; do not widen #10155 or #10166). FILED 2026-10-13 as #10175 (no open issue covered it, verified by `gh issue list --search`).
- Rule id and status printed by `scripts/sentry-alert-live-fidelity.sh`, so rule 1310055 can be read headlessly: NOT filed from this PR. It stays a proposal, recorded in `flip-preconditions-report.md` row 1.3.
- A mode-aware readiness note in `apply-web-platform-infra.yml`: under rotate the LUKS volume is replaced, but `Post-replace readiness note` still says "both volumes preserved". NOT filed from this PR: it belongs to PR #10155, which owns the post-apply and rotate-arm changes in that workflow.
