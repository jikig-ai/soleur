---
title: "docs: LUKS epic #9927 - Guard 1 live red-proof, flip-token record reconciliation, Guard 1 CI wall time"
date: 2026-11-04
slug: luks-guard1-redproof-and-flip-token-record
branch: feat-one-shot-luks-guard1-redproof-flip-token-design
issue: 9927
type: docs
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# docs: LUKS epic #9927 - Guard 1 live red-proof, flip-token record reconciliation, Guard 1 CI wall time

Spec lacks valid lane: - defaulted to cross-domain (TR2 fail-closed). No `spec.md` exists for this branch.

## Enhancement Summary

**Deepened on:** 2026-11-04
**Sections enhanced:** Research Insights (deepen-pass findings), Phase 1 (hook behavior), citations
**Research agents used:** CTO (forks F1, F2), CPO (conditional sign-off), learnings-researcher, code-simplicity-reviewer (plan review); direct repo/`gh` verification of the deepen-plan gates.

### Key Improvements
1. The red-proof path was re-routed after finding `CI_DRAFT_LIGHT=on` skips `test-scripts` on any draft push (a draft would show skipped, not red); the full battery comes from a `workflow_dispatch` of `ci.yml` on the throwaway branch.
2. The throwaway PR targets a disposable base, not main, because the "CI Required" ruleset carries two bypass actors (confirmed in `infra/github/ruleset-ci-required.tf`).
3. The flip-token item is reduced to a pointer plus a grep-derived ledger, because ADR-282 already carries the design (2026-10-30), the build (2026-11-01) and the access pin (2026-11-02).

### New Considerations Discovered
- `post-dispatch-watch-gate.sh` does not block `gh workflow run`; it nags until a Monitor is armed, which Phase 1 step 7 already does.
- The pre-commit gate may refuse the throwaway commit; any bypass needs a recorded CTO ruling (decision-challenges row T4).

## Overview

Resume the open sole-copy LUKS epic. The epic (#9927) stays open: the PR body says `Ref #9927`, never `Closes`. The CTO ruled on 2026-11-04 that no act in this run is delegable, so nothing is merge-armed beyond ship's own auto-merge of this branch's PR, and no owner-reserved hold is touched.

Three bounded deliverables:

1. **AC1 live red-proof of Guard 1.** Show in CI, not only locally, that deleting `delete_protection = true` on `hcloud_volume.inngest_redis_luks` turns `test-scripts (3/8)` and the required `test` aggregator red. This is a CI act performed during `soleur:work`; no file of it is committed on this branch.
2. **One ADR-282 addendum** (committed on this branch) that (a) reconciles the flip-token design record with the three addenda that already exist, adding only a derived ledger of who reads and writes `INNGEST_CUTOVER_FLIP` under which Doppler token plus the item 8 ordering constraint, and (b) records the Guard 1 CI wall time with both sources.
3. **One comment on #9927** with the red-proof evidence, and one with the "I checked" lines (or both in a single comment; see Phase 4).

## Research Reconciliation - Spec vs. Codebase

| Brief claim | Reality (checked 2026-11-04 on `origin/main` 8cc167c2e3) | Plan response |
|---|---|---|
| "Flip-token design record for item 4 ... the design must say where the flip write moves" | The design already exists: ADR-282 `Addendum - 2026-10-30 (#9927 item 4, the flip-token design)` (CTO ruling: boot token `doppler_service_token.inngest` becomes `read`; a new root-only 0600 `/etc/default/inngest-flip` read/write token, read only by the cutover-flip unit, carries the `flag_set` write). `Addendum - 2026-11-01 (... the flip-token build record)` records the build (merged as #11815, undelivered until the owner-gated host replace). `Addendum - 2026-11-02 (#11831, #11820)` adds the access-level pin and the silence alarm (#11831 is a closed issue delivered by PR #11854; #11820 is an open issue). The #9927 body's Operator Hold "flip-token design" is therefore technically discharged. | Do NOT restate the design. The addendum points at the three addenda, says the hold is discharged by 2026-10-30, and adds only what none of them contain: a grep-derived ledger of every `INNGEST_CUTOVER_FLIP` reader and writer by token, host versus CI, and the item 8 ordering constraint (CTO ruling F2, option A). |
| "arm, rollback, resume, reflush and luks-cutover ops in cutover-inngest.yml still consume DOPPLER_TOKEN_INNGEST_ARM; the host-replace preflight reads INNGEST_CUTOVER_FLIP with it" | Confirmed: `.github/workflows/cutover-inngest.yml:164` wires `DOPPLER_TOKEN_INNGEST_ARM` for those five ops; `scripts/cutover-inngest.sh` writes `armed` (~2732) and `rollback` (~3238) under it; `.github/workflows/apply-web-platform-infra.yml` ~1946-1962 reads the flag with it. | This is the item 8 finding for the "I checked" comment and the ledger. No revoke, scope-down or deletion here. |
| "a throwaway DRAFT PR ... watch the required test-scripts (3/8) check go red" | `CI_DRAFT_LIGHT` is `on` (repo variable, set 2026-10-11). `ci.yml` `draft-light` (line ~263) marks every `pull_request` push to a DRAFT light unless the action is `ready_for_review`; `test-scripts` carries `needs.draft-light.outputs.light != 'true'`, so on a draft it is SKIPPED (not red) and `test` is red by design ("draft: full battery owed at ready"). Also: `test-scripts (3/8)` is not itself a required context; the required context is the `test` aggregator that lists `test-scripts` in `needs:`. | CTO ruling F1: dispatch `ci.yml` on the throwaway branch (`workflow_dispatch` skips `draft-light`, so the full battery runs), fall back to the documented ready path, then to a local mutation run. See Phase 1. |
| "the throwaway branch must not touch .github/** or scripts/**" and "apply-web-platform-infra.yml triggers on push to main only" | Confirmed by reading every workflow's `on:` block (Phase 1 step 1 reruns it): every `push:` trigger is `branches: [main]`; no workflow runs a mutating job on a non-main push. `pull_request` triggers that match an `apps/web-platform/infra/**` diff: `ci.yml`, `infra-validation.yml` (read-only validate/plan), `check-inngest-bootstrap-build.yml`, `validate-vector-config.yml`, `zot-image-mirror.yml`, `sentry-audit-gate.yml` (the last four are path-filtered and do not match a change to `inngest-redis-luks.tf`). | The throwaway commit touches exactly one line in `apps/web-platform/infra/inngest-redis-luks.tf` (line 168 on `origin/main`). |
| (implicit) a PR into main titled "DO NOT MERGE" is safe because the required `test` goes red | CPO advisory 2026-11-04: the "CI Required" ruleset has bypass actors (organization admin; a repository role in `pull_request` bypass mode). A red `test` does not make a PR into main unmergeable, and a merge to main would trigger the push-to-main production apply that lifts delete protection on the sole copy. | Open the throwaway PR against a DISPOSABLE BASE branch cut from `origin/main`, never against main (decision-challenges row F1d). A merge into the base cannot reach main. |
| "ci.yml green on main (30 of 30 recent runs)" | `gh run list --workflow ci.yml --branch main -L 30` returned 30 `success` at plan time (latest run 41899697667, 2026-11-04T19:43:31Z, head 8cc167c2e3). | Re-derive at work time (Phase 0) before writing the line; do not copy this number. |
| "the infra runner's own manifest records 72 s" | `apps/web-platform/infra/suite-durations.tsv` row `apps/web-platform/infra/inngest-luks-sole-copy.test.sh 72000 measured` (group=infra, generated-at 2026-11-02T23:31:43Z from the eight run ids in its header). Guard 1 is ALSO weighted in the light manifest `scripts/suite-durations.tsv` as `apps/web-platform/infra/inngest-luks-sole-copy 1251 floor`, the default placeholder, not a measurement, and it is the manifest the `test-scripts` shard balancer reads. | Cite the 72 s row with its group and generation date. Do not cite 1,251 ms as a wall time; it is not recorded anywhere in this run (taste row T1 in decision-challenges.md). |

## Research Insights

**Premise Validation (Phase 0.6).** Checked: #9927 is OPEN (title "infra: Inngest LUKS key-loss residuals deferred from #9879 ..."); no open PR names #9927 (`gh pr list --state open --search 9927` empty); `collision-precheck.sh 9927` reported no PR hit and four foreign `test-all.sh` processes in sibling worktrees (`feat-one-shot-12065-12066-codeql-filer-converge`, `feat-one-shot-10390-ci-hygiene-batch`), which only matters for the local 40 s run (it may run slower under contention; record the contention note with the number). `delete_protection = true` exists at `apps/web-platform/infra/inngest-redis-luks.tf:168` (single match in that file). Guard 1 is registered at `scripts/test-all.sh:6753` and mapped to leg 3 in `scripts/suite-shard-legs.tsv:81`. ADR corpus grep for the proposed mechanisms: ADR-282 addenda 2026-10-30, 2026-11-01, 2026-11-02, 2026-11-03 already cover the flip-token design, build, access pin and Guard 1 registration; the `Rejected alternative` (separate Doppler config for the flag) is recorded in 2026-10-30 and is NOT reopened. Stale: the brief's framing that the flip-token design is still owed.

**Property List (Phase 0.6b).**
- P1. A weakened sole-copy pin turns a merge-blocking CI context red on a real branch, not only in the local suite.
- P2. The ADR says once, without contradicting earlier addenda, where the `INNGEST_CUTOVER_FLIP` write lives per token.
- P3. The reader/writer ledger is derived from the repo and carries the item 8 ordering constraint, so the arm-write token cannot be revoked before its consumers move.
- P4. Guard 1's cost in CI is on record with sources and the right scope for each number.
- P5. #9927 carries the evidence and the checks; it stays open.

**Cut List (Phase 0.6b).**
- Re-describing the flip-token split in the new addendum -> P2 -> already covered by ADR-282 2026-10-30 and 2026-11-01 (pointer only).
- A CI-side design for where `op=arm|rollback|resume|reflush|luks-cutover` and the apply preflight move at item 8 time (CTO option B) -> P3 -> cut by ruling F2: no owner or trigger yet, the separate-config alternative is already recorded as rejected, and it would go stale before item 8 starts.
- A new ADR ordinal -> none needed (an addendum amends nothing; ADR-282 status stays `accepted`).
- A `model.c4` edit -> the `doppler -> inngest` edge (line 918) already states the credential split and is owner-clause-gated on the replace; this run changes no fact it carries.
- A PR into `main` for the red-proof -> P1 -> a disposable-base PR buys the same CI evidence without the merge hazard (F1d).
- A `ready_for_review` toggle as the primary path -> P1 -> `workflow_dispatch` reaches the same full battery without changing PR state (F1).
- A Guard Contract section: this plan authors no guard (Guard 1 exists and is only exercised); skipped silently per Phase 2.12.

**Applicable learnings (read, paths under `knowledge-base/project/learnings/`).**
- `workflow-issues/2026-11-03-draft-prs-fail-the-test-aggregate-by-design-and-ceiling-raises-ship-alone.md`: on a draft, `test` is red by design; the `ready_for_review` run is the real battery. Do not read a draft's red as Guard 1.
- `2026-08-04-a-proof-of-red-pinned-to-a-moving-ref-consumes-its-own-fix.md`: pin the red-proof to an immutable SHA (the base branch is cut from a named `origin/main` SHA recorded in the evidence).
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`: name the failing case, so the red is attributable to the property and not to an unrelated failure.
- `2026-10-18-a-record-pr-said-measured-where-the-evidence-was-printed.md` and `2026-09-14-the-sweep-that-retired-false-sentences-wrote-new-ones-from-my-own-issue-comment.md`: use the strength word the evidence supports; re-derive every "I checked" claim from `gh`/command output, never from an earlier comment or this plan.
- `2026-10-15-the-flip-pr-ran-the-verification-and-left-the-sentence-saying-it-was-never-run.md`: sweep by claim subject, not by file list (Phase 3 sweeps ADR-282 for sentences the addendum falsifies, for example the 2026-11-03 line that the CI wall time "is recorded in a follow-up append").

**Deepen-pass findings (2026-11-04).**
- Gates run mechanically on this plan: 4.6 User-Brand Impact present, threshold `single-user incident`; 4.7 Observability skipped (every Files-to-Edit path is under `knowledge-base/`, pure docs); 4.8 PAT-shaped regex returned no hit; 4.9 no UI surface; 4.10 Encryption Posture skipped (this branch edits no `.tf`/cloud-init/migration file and introduces no store or connection; the throwaway edits an existing attribute on a branch that never merges); 4.11 Guard Contract skipped (no guard is authored); 4.12 exactly one unfenced `## Scope Check`, one `Recommendation:` line, no `status: BLOCKED`; 4.13 no new autonomous task (no workflow, function or timer is created; `workflow_dispatch` runs an existing workflow once).
- Rule IDs cited in the plan body all resolve as active in `AGENTS.rules.md`: `cq-cite-content-anchor-not-line-number`, `hr-dispatch-async-must-arm-watch`, `hr-monitor-not-run-in-background-for-polling`.
- Issue/PR citations checked live: #9927 OPEN; #11815 MERGED (2026-11-02T03:57:14Z, "split the Inngest host Doppler token into a read boot token and a read/write flip token"); #11831 is an ISSUE, CLOSED ("pin token access level in the Inngest replace gate"), delivered by PR #11854 (`dd09b31d69`); #11820 is an OPEN issue (silence alert follow-up); #9879 is the deferring PR.
- Verify-the-negative sweep: "every `push:` trigger is main-only" confirmed by parsing all 30-odd workflow files (no tags, no non-main branches); "`test-scripts` is not a required context" confirmed in `infra/github/ruleset-ci-required.tf` (required: `test`, `dependency-review`, `e2e`, ...); "a draft push skips `test-scripts`" confirmed at the `draft-light` job and the `needs.draft-light.outputs.light != 'true'` term on `test-scripts`.
- No label is prescribed; no new ADR ordinal; no external SHA or version is cited.

## Open Code-Review Overlap

None. Open `code-review` issues were queried (200 limit) against `ADR-282-sole-copy-luks-volume-protection-set`, `inngest-luks-sole-copy.test.sh` and `inngest-redis-luks.tf`; no body names any of them.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "open a throwaway DRAFT PR titled \"DO NOT MERGE\" (never armed, never merged) on its own branch that deletes `delete_protection = true` on `hcloud_volume.inngest_redis_luks` under apps/web-platform/infra/, and watch the required `test-scripts (3/8)` check go red" | Phase 1 (steps 1-8) | mapped |
| 2 | "Before the first push read the `on:` blocks ... the throwaway branch must not touch .github/** or scripts/**" | Phase 1 step 1 and AC2 | mapped |
| 3 | "Record the red run URL as a comment on #9927. Leave the throwaway PR as a draft for ship or the owner to close." | Phase 4 comment A; Phase 5 close handoff | mapped |
| 4 | "Fallback if the PR cannot be opened: a local mutation run of the suite, labelled as covering the suite going red, not the CI leg." | Phase 1 fallback ladder (D) | mapped |
| 5 | "Write it as an ADR-282 addendum (check the existing ADR-282 addenda first, including any from the earlier flip-token work, so nothing is duplicated). Design only" | Phase 3 (addendum, pointer plus ledger) | mapped |
| 6 | "In that same ADR-282 touch, add the Guard 1 CI wall time (local run about 40 s, 89 of 89 cases, test-scripts 3/8; the infra runner's own manifest records 72 s), citing both sources." | Phase 3 wall-time paragraph | mapped |
| 7 | "Post one comment on #9927 with the \"I checked\" lines: ci.yml green on main (30 of 30 recent runs), test-all.sh registers inngest-luks-sole-copy.test.sh, and the item 8 finding that the arm ops are not yet retired." | Phase 4 comment B | mapped |
| 8 | "Make the plan say clearly how the red-proof PR stays isolated from this branch's PR (separate branch, draft, never armed) and where the red run URL is recorded." | `## Isolation of the red-proof PR` below | mapped |
| 9 | "Do NOT in this run: revoke, scope down or delete doppler_service_token.inngest_arm_write ... remove the G2e pin ... dispatch or authorize apply_target=inngest-host-replace; close #9927; sign the A6 owner sentence; decide the off-project ciphertext copy." | `## Out of scope (constraints)` and AC10 | mapped (constraint) |
| 10 | "Persist every decision as a row of the `| Item | Class | Ruling |` table in knowledge-base/project/specs/<branch>/decision-challenges.md" | `decision-challenges.md` (created) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 0 preflight (re-derive premises) | "ci.yml green on main (30 of 30 recent runs)" (asks 7) | asked |
| Phase 1 red-proof | asks 1-4 | asked |
| Disposable base branch | "on its own branch", "never armed, never merged" (asks 1) | inferred - justification: the CPO advisory found the ruleset has bypass actors, so a PR into main with a red `test` is mergeable by an admin; a base other than main is the only structural block on "never merged" |
| Dispatch of `ci.yml` on the branch | "watch the required `test-scripts (3/8)` check go red" (asks 1) | inferred - justification: `CI_DRAFT_LIGHT=on` skips `test-scripts` on a draft, so the asked-for observation is impossible on the draft push alone (CTO ruling F1) |
| Phase 2 ledger greps | "check the existing ADR-282 addenda first ... so nothing is duplicated" (asks 5) | inferred - justification: the ledger is the only content the existing addenda lack, and CTO ruling F2b requires it be grep-derived rather than copied |
| Phase 3 ADR-282 addendum | asks 5, 6 | asked |
| Phase 4 comments | asks 3, 7 | asked |
| Phase 5 close handoff | "Leave the throwaway PR as a draft for ship or the owner to close." (asks 3) | asked |
| `decision-challenges.md` | ask 10 | asked |

### Split Assessment

- Subsystems touched: 1 (`knowledge-base/engineering/architecture/decisions/` plus plan/spec artifacts); the red-proof touches a separate throwaway branch only
- Planned files: 4 on this branch | Estimated changed lines: about 120
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Isolation of the red-proof PR

The throwaway never shares a branch, base or fate with this branch's PR.

| Property | Mechanism |
|---|---|
| Separate branch | Head `redproof-luks-guard1-head-20261104`, created in its own git worktree; this branch (`feat-one-shot-luks-guard1-redproof-flip-token-design`) is never checked out there and never contains the deleted line. |
| Cannot reach main | PR base is a disposable branch `redproof-luks-guard1-base-20261104`, cut from a recorded `origin/main` SHA. A merge of the throwaway lands in the base only; the push-to-main production apply cannot fire. |
| Draft, titled "DO NOT MERGE" | `gh pr create --draft --base redproof-luks-guard1-base-20261104 --title "DO NOT MERGE: red-proof of ADR-282 Guard 1 (throwaway)"`; body names it throwaway, cites `Ref #9927`, and carries no `Closes`. |
| Never armed | No `gh pr merge` in any form (not `--auto`, not `--admin`). `gh pr view <n> --json autoMergeRequest` is checked `null` at record time and at close. |
| Touches nothing but the one line | `git diff --name-status <base>...HEAD` is exactly `M apps/web-platform/infra/inngest-redis-luks.tf` with one deletion; a grep of the name list for `^\.github/|^scripts/` returns empty. |
| Does not enter this branch's PR | This branch's PR body mentions the throwaway only as a link; ship is told the throwaway number so it can close it; `Closes`/`Fixes` appears nowhere. |
| Where the red run URL lives | One comment on #9927 (Phase 4 comment A): PR number, base branch, base SHA, head SHA, run URL, `test-scripts (3/8)` job URL, failing-case text, `test` conclusion, other shards' conclusions, a green 3/8 baseline on the same base SHA, close-by statement. |
| Close-by | The throwaway stays an OPEN DRAFT after work (the brief's instruction). One owner for its lifetime: this branch's PR body carries a line `Throwaway red-proof PR #N (base <name>, head <name>): close it and delete both branches`, and work adds a final task for ship to execute that line (`gh pr close <n>`, then delete the base and head branches); the owner may do it earlier. Comment A states the same and names the owner of the close. |

## Implementation Phases

### Phase 0 - Preflight (re-derive, do not copy)

0.1 `git fetch origin main`; record the `origin/main` SHA to be used as the base. `gh issue view 9927 --json state` is OPEN.
0.2 `gh run list --workflow ci.yml --branch main -L 30 --json conclusion --jq 'group_by(.conclusion)|map({c:.[0].conclusion,n:length})'` -> record the count (expect `success` 30; if not 30, the "I checked" line says what it actually is).
0.3 `grep -n 'inngest-luks-sole-copy' scripts/test-all.sh scripts/suite-shard-legs.tsv` -> the `run_suite` line and the leg-3 row.
0.4 `gh variable list` shows `CI_DRAFT_LIGHT`; record its value (it decides whether the dispatch path is needed; if it is off the plain draft push already runs `test-scripts`).
0.5 Re-run the `on:` block reader over `.github/workflows/*.yml` (push triggers and pull_request path filters) and keep its output for the comment.

### Phase 1 - AC1 red-proof (separate worktree; no commit on this branch)

1. **Read the `on:` blocks before the first push** (Phase 0.5 output): `apply-web-platform-infra.yml` push is `branches: [main]`; all other push triggers are main-only.
2. Cut the disposable base: `git push origin <origin-main-SHA>:refs/heads/redproof-luks-guard1-base-20261104`.
3. `git worktree add -b redproof-luks-guard1-head-20261104 <repo>/.worktrees/redproof-luks-guard1-head-20261104 <origin-main-SHA>` (plain `git worktree add`; the shared stash stack is never used).
4. In that worktree: confirm `grep -c '^[[:space:]]*delete_protection[[:space:]]*=[[:space:]]*true[[:space:]]*$' apps/web-platform/infra/inngest-redis-luks.tf` is `1`, delete that one line, and check the diff is one file, one deletion, with no `.github/` or `scripts/` path.
5. Commit: try a plain `git commit` first, with a CLA-signed author. The pre-commit gate (`lefthook.yml`, `scripts/test-all.sh --affected --affected-scope=staged`) may itself refuse the change because Guard 1 goes red. If it does, record that output as the LOCAL-hook leg, and do NOT choose a way around it silently: no repo rule sanctions `--no-verify` or git plumbing for this (the bypass preflight in `guardrails.sh` records, not blocks, a bypass flag). Spawn `soleur:engineering:cto` with the refusal output and "do NOT use AskUserQuestion" for the technical fork (a recorded bypass on a throwaway worktree versus fallback D), and record its ruling as a new decision-challenges row before committing. The point of the exercise is the CI net independent of the local hook (ADR-183: no local run is the merge gate).
6. Push the head branch; `gh pr create --draft --base redproof-luks-guard1-base-20261104 ...` (CTO F1d: a non-main base; `ci.yml`'s `pull_request` trigger carries no branch filter, so it runs; if the PR cannot be opened for any reason, skip it and keep only the pushed head branch for the dispatch, which needs no PR).
7. Dispatch and watch (primary path C): `gh workflow run ci.yml --ref redproof-luks-guard1-head-20261104`, then arm a watch with the Monitor tool (`hr-dispatch-async-must-arm-watch`, `hr-monitor-not-run-in-background-for-polling`) on `gh run list --workflow ci.yml --branch redproof-luks-guard1-head-20261104`; `gh workflow run` prints no run id, so obtain it with `gh run list --workflow ci.yml --event workflow_dispatch --branch redproof-luks-guard1-head-20261104 -L 1 --json databaseId,headSha,status` and pin that id. Opening the PR also fires a separate `pull_request` run on the same SHA (`test` red by design, `test-scripts` skipped); never read that one as the proof. A hook that blocks the dispatch is not bypassed: go to fallback A.
8. Read the evidence (CTO F1b): `gh run view <id> --json jobs` for `test-scripts (3/8)` (conclusion `failure`) and its sibling shards and `test`; `gh run view <id> --log-failed` for the Guard 1 case text (`FAIL:` plus `VOL_DELETE_PROTECTION`, "does not carry delete_protection = true as one code line"); a green `test-scripts (3/8)` on the base SHA from the main run list as the baseline; the Guard 1 per-suite elapsed time if the log prints it (feeds Phase 3). Ideally 3/8 is the only red shard.

**Fallback ladder (CTO ruling F1).** A = the documented ready path (`ci-head-verdict.sh ready-count`, `gh pr ready`, `wait-ready-run`, then `gh pr ready --undo` immediately after the run concludes; per `ship/references/ready-run-wait.md`; PreToolUse hooks that gate `gh pr ready` are honored, not bypassed). D = a local mutation run of Guard 1 on a scratch copy, labelled "covers the suite going red, not the CI leg"; AC1 is NOT discharged on D alone. B (open non-draft) is rejected.

**Hazards named.** The push of a branch cannot trigger a mutating workflow (every push trigger is main-only). Opening the PR is not side-effect free; accepted side effects: `infra-validation.yml` runs (read-only validate/plan); `board-status-sync.yml` writes the PR to the org Project board on `opened`, `ready_for_review` and `converted_to_draft` (remove the item when closing if it persists); `cla.yml` and `cla-evidence.yml` (`pull_request_target`) run; `claude-code-review.yml`, `secret-scan.yml` and `pr-quality-guards.yml` run (cost only); `cleanup-unmerged-bot-branches.yml` runs on close. The `ci.yml` rulesets' required contexts do not apply to a non-main base, so the PR's own check list is informational. If the commit needs a bypass, the CTO ruling in step 5 governs and the incident record is expected and named in the PR body.

### Phase 2 - Derive the INNGEST_CUTOVER_FLIP ledger (work time, from the repo)

Run, from the worktree, and keep the raw output for the addendum table (CTO ruling F2b):
- `git grep -n INNGEST_CUTOVER_FLIP -- .github scripts apps/web-platform/infra plugins`
- `git grep -n 'DOPPLER_TOKEN_INNGEST_ARM\|inngest_arm_write\|inngest-arm-write'`
- `git grep -n 'flag_set\|/etc/default/inngest-flip\|inngest_flip'`
- `git grep -n 'doppler_service_token.inngest\b'`

Classify each hit: reader or writer; host or CI; token (`boot` read-only, `flip` read/write, `arm_write`, `DOPPLER_TOKEN_TF`, other). Cite `file:line` per row (content anchors in prose, per `cq-cite-content-anchor-not-line-number`, with the path; line numbers only inside the evidence table with the run date). Any consumer the greps find that the brief omits (`inngest-server-flip-guard.sh`, `inngest-bootstrap.sh`, `hooks.json.tmpl`, `scripts/followthroughs/inngest-*.sh`, `scripts/inngest-gate-witness-classify.sh`, `inngest-host.tf`) is classed and, where it uses the arm-write token, flagged "move first at item 8".

### Phase 3 - ADR-282 addendum (the committed deliverable)

Append one section to `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md` headed `## Addendum - 2026-11-04 (#9927 item 4 reconciliation, Guard 1 CI wall time)`. Nothing above is edited except the dated `Superseded` style marker (below). Status stays `accepted`; no new ordinal. Content, in order:

1. Opening paragraph in the repo's addendum voice: appended, status unchanged, docs only, no token minted, no Doppler or Hetzner write, nothing dispatched.
2. **Flip-token design: already recorded.** Two or three sentences pointing at the 2026-10-30, 2026-11-01 and 2026-11-02 addenda, stating that the design the Operator Hold "flip-token design for item 4" asks for is recorded in the 2026-10-30 addendum (whether the hold is closed is the owner's call, and the #9927 body is not edited), and that the on-host flip write lives in `/etc/default/inngest-flip`, read only by the cutover-flip unit. `Ruled by CTO agent, 2026-11-04: option A, reconciliation with ledger and no CI-side design - ...` (cite the decision-challenges row). Do not copy the design text.
3. **Ledger table** (Phase 2 output): who reads or writes `INNGEST_CUTOVER_FLIP`, by token, host versus CI, with the grep that found it and the date. Strength words per `2026-10-18-...measured...`: "printed by grep on 2026-11-04", not "verified".
4. **Ordering constraint (not a design).** The item 8 retirement PR precedes any revoke, scope-down or deletion of `doppler_service_token.inngest_arm_write`: the `arm`, `rollback`, `resume`, `reflush` and `luks-cutover` ops of `cutover-inngest.yml` and the host-replace preflight in `apply-web-platform-infra.yml` are the consumers to move first. #11815 delivers the host side only and changes no CI consumer, so the arm-write token stays live through the owner-gated replace. Where the CI-side flag writes and the preflight read go at item 8 time is NOT decided here (the 2026-10-30 rejected alternative stays rejected-but-available).
5. **Guard 1 CI wall time.** `apps/web-platform/infra/inngest-luks-sole-copy.test.sh` (the suite behind `test-scripts (3/8)`): local run about 40 s, 89 of 89 cases (source: one timed local run in this work phase, command and printed summary line quoted; the 2026-11-03 addendum already states "89 of 89 cases in about 40 s (the infra runner's own manifest records 72 s)" without paths, so the delta this addendum adds is the two source paths with scopes and the CI-run number or "not printed"); infra runner manifest 72 s (source: `apps/web-platform/infra/suite-durations.tsv`, group=infra, `72000 measured`, generated 2026-11-02T23:31:43Z from the run ids in its header; this is a different runner, the `deploy-script-tests` glob that also covers the suite, and is not the test-scripts job). The two numbers are different machines and are not averaged. If the red-proof job log prints a per-suite elapsed for Guard 1, add it as a third labelled number; otherwise say it was not printed.
6. **Red-proof result** (one short paragraph, linking the #9927 comment URL): head SHA, run URL, the failing case, and which legs ran (CI dispatch, ready path or local only). Written after Phase 1 completes; if Phase 1 only reaches D, the paragraph says "suite-red coverage, not the CI leg" and the 2026-11-03 line is left as it was.
7. **Sweep.** `grep -n 'recorded in a follow-up append\|wall time on the CI runner' ` in the ADR: add a dated `Superseded` marker under the 2026-11-03 sentence "The wall time on the CI runner is recorded in a follow-up append once the first run on the branch has finished" pointing at the new addendum, following the file's existing marker style.
8. `Ref #9927` only; no `Closes`.

Verification of the file: markdown lint (`bash scripts/markdown-lint.sh <file>`), `python3 scripts/lint-infra-no-human-steps.py <file>` (the lefthook gate over staged files; avoid "owner runs"/"operator applies" phrasing, write "the owner-gated replace"), and the ADR ordinals check (`adr-ordinals`; no new ordinal is introduced).

### Phase 4 - Comments on #9927

- **Comment A (red-proof record):** the Isolation table's last row, filled with real values; ends with the explicit close-by statement. Posted as soon as Phase 1 step 8 is done.
- **Comment B ("I checked" lines):** exactly the three asked lines, each re-derived in Phase 0 and carrying the command or run id: (1) `ci.yml` on main: N of N recent runs `success` (from Phase 0.2, not copied); (2) `scripts/test-all.sh` registers `inngest-luks-sole-copy.test.sh` (the `run_suite` line, plus the leg-3 row of `scripts/suite-shard-legs.tsv`); (3) item 8 finding: the arm, rollback, resume, reflush and luks-cutover ops in `.github/workflows/cutover-inngest.yml` still consume `DOPPLER_TOKEN_INNGEST_ARM` and the host-replace preflight in `.github/workflows/apply-web-platform-infra.yml` reads `INNGEST_CUTOVER_FLIP` with it; they are not yet retired, so the arm-write token is not touched and a prerequisite retirement PR comes first. A and B may be one comment if posted together; the brief asks for "one comment" for the checks, so B stays its own single comment.
- Neither comment contains a secret value, a token name beyond the Doppler resource names already public in the repo, or an instruction to the owner.

### Phase 5 - Close handoff

Put the line `Throwaway red-proof PR #N (base <name>, head <name>): close it and delete both branches` in this branch's PR body (plain text, never `Closes`). `soleur:ship` has no built-in step for it, so work makes it an explicit final task: after this branch's PR is created, close the throwaway PR (`gh pr close <n>`) and delete the base and head branches and the head worktree, re-checking `isDraft` true and `autoMergeRequest` null first. If the session ends first, the owner may do the same. The throwaway stays a draft until then.

## Architecture Decision (ADR/C4)

### ADR
ADR-282 is amended by an appended addendum (the work of Phase 3); it is the plan's own deliverable, not a deferred issue. It records a reconciliation and a ledger and changes no decision, so there is no new ordinal.

### C4 views
No C4 change. Checked against all three model files (`knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4`, `spec.c4`): external actors (the owner, Hetzner, Doppler, GitHub Actions) and the `doppler -> inngest` edge (`model.c4` line 918) already model the credential split ("CREDENTIAL SPLIT (ADR-282 addendum 2026-10-30 ...)"), with a removal clause gated on the owner-gated replace; no new store, vendor or access relationship is introduced; the item 8 arm-write token is not part of any edge and the ordering constraint is a sequencing record. Work-time check: `bash plugins/soleur/test/c4-count-parity.test.sh` stays green (no count moves) and the work phase re-reads the three files for the same actors before concluding.

### Sequencing
The addendum is authored now; its red-proof paragraph is the only part that waits on Phase 1.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly (docs and a throwaway CI run). The indirect failure is false assurance: a record claiming Guard 1 reddens a required context when it does not, so a later PR that weakens the sole-copy volume's protection merges green and the Inngest queue state, which holds user jobs, is exposed to deletion.
**If this leaks, the user's workflow is exposed via:** the throwaway PR's diff, if ever merged into main, which would run the push-to-main infra apply and lift `delete_protection` on the sole-copy volume. Mitigated structurally by the disposable base (a merge cannot reach main), plus draft, title, no arming and an explicit close task. No secret, token value or user data is read or written by this plan.
**Brand-survival threshold:** single-user incident

CPO conditional sign-off 2026-11-04 (advisory, recorded in decision-challenges row F1d): SIGN-OFF conditional on the disposable base branch and a close-by statement; both are in this plan. `soleur:engineering:review:user-impact-reviewer` runs at review time. Threshold carried from ADR-282's frontmatter.

## Domain Review

**Domains relevant:** engineering (infrastructure/CI), product (CPO, trust)

### Engineering (CTO)
**Status:** reviewed
**Assessment:** Rulings F1, F1b, F2, F2b recorded in `decision-challenges.md` (primary red-proof path is a `workflow_dispatch` of `ci.yml`; addendum is a reconciliation plus a grep-derived ledger, no CI-side design).

### Product (CPO)
**Status:** reviewed
**Assessment:** Conditional sign-off: open the throwaway against a disposable base, record PR number and base in the #9927 comment with a close-by statement, label each timing with where it was measured, derive the ledger from code. All four adopted (F1d, Phase 3 item 5, Phase 2).

No Product/UX Gate: no user-facing surface and no file under `components/**`, `app/**/page.tsx` or `app/**/layout.tsx`.

## Infrastructure (IaC)

Skipped: no infrastructure is introduced, edited or applied. The throwaway edits a Terraform attribute on a branch that cannot reach main and runs no `terraform` command; the `apply_target=inngest-host-replace` path is out of scope.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1. The red-proof evidence exists in #9927 comment A: run URL and `test-scripts (3/8)` job URL with conclusion `failure` (`gh run view <id> --json jobs --jq '.jobs[]|select(.name|test("test-scripts \\(3/8\\)"))|.conclusion'` prints `failure`), head SHA, a diff of exactly one deleted `delete_protection = true` line in `apps/web-platform/infra/inngest-redis-luks.tf`, the Guard 1 failing-case text (`grep -c 'does not carry delete_protection = true' <log>` is at least 1), the `test` aggregator conclusion, the other shards' conclusions and a green 3/8 baseline. If only the local mutation leg ran, the comment and the addendum say "suite-red coverage, not the CI leg" and AC1 is reported as NOT discharged.
- [ ] AC2. Before the first push the `on:` blocks were read, and the throwaway diff touches nothing under `.github/` or `scripts/` (`git diff --name-only <base>...<head> | grep -E '^(\.github|scripts)/'` prints nothing).
- [ ] AC3. The throwaway PR is a draft titled "DO NOT MERGE ...", its base is `redproof-luks-guard1-base-20261104` (not main), `gh pr view <n> --json isDraft,baseRefName,autoMergeRequest` shows `true`, `redproof-luks-guard1-base-20261104` and `null`.
- [ ] AC4. ADR-282 has exactly one new section `## Addendum - 2026-11-04`; `git diff origin/main -- <adr>` shows additions only, plus the single dated `Superseded` marker under the 2026-11-03 wall-time sentence; the status line still says `accepted`; no new ADR file exists.
- [ ] AC5. The addendum points at the three earlier addenda by their dated headings (`grep -c 'Addendum - 2026-10-30' <new section>` at least 1) and carries no numbered copy of the 2026-10-30 Decision list (reviewer check at review time).
- [ ] AC6. The ledger rows are grep-derived: every row cites `file` and the token, and a re-run of the four Phase 2 greps adds no `INNGEST_CUTOVER_FLIP` consumer file that is absent from the table.
- [ ] AC7. The wall-time paragraph cites BOTH sources by path: the timed local run (command and printed line) and `apps/web-platform/infra/suite-durations.tsv` (`72000 measured`, group infra, generation date), keeps them as separate numbers, and does not present 1,251 ms as a wall time.
- [ ] AC8. #9927 has comment B with the three "I checked" lines, each carrying the command or run id it was derived from; the counts in it equal the Phase 0 output.
- [ ] AC9. `decision-challenges.md` exists and any fork decided during work (for example the Phase 1 step 5 bypass question) has its own row.
- [ ] AC10. Not touched: `doppler_service_token.inngest_arm_write` (no edit to `inngest-arm-write-token.tf` or any `.tf`), the G2e pin in `plugins/soleur/test/terraform-target-parity.test.ts`, no `apply_target=inngest-host-replace` dispatch, #9927 still OPEN after the PR merges, no A6 record under `knowledge-base/legal/audits/`, no off-project copy decision. Check: `git diff --name-only origin/main...HEAD | grep -E '\.tf$|^\.github/|^scripts/|^plugins/'` prints nothing (ship's archive step may move the plan and specs files, so only these paths are asserted).
- [ ] AC11. PR body uses `Ref #9927`, never `Closes`/`Fixes`, and names the throwaway PR number and both throwaway branches as plain text.
- [ ] AC12. `bash scripts/markdown-lint.sh` and `python3 scripts/lint-infra-no-human-steps.py` over the ADR, plan and tasks files exit 0; `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0.

### Post-merge (operator)
- None. The throwaway PR close and branch deletion are agent steps in ship's cleanup (Phase 5), not an owner checklist item; if ship does not close it, the owner may, with no deadline beyond what comment A states.

## Test Scenarios

- Given the mutated head (one line deleted), when `ci.yml` is dispatched on it, then `test-scripts (3/8)` concludes `failure`, its log contains the `VOL_DELETE_PROTECTION` message, and `test` concludes `failure`.
- Given the same base SHA unmutated, then `test-scripts (3/8)` was `success` on the main run for that SHA (baseline; excludes an unrelated red).
- Given a draft PR push only (no dispatch), then `test-scripts` is `skipped` and `test` is red with "draft: full battery owed at ready": this is NOT the red-proof and must not be cited as one.
- Given a hook that blocks the dispatch, then the plan goes to fallback A and records the block; it is never bypassed.
- Given the ready path is used, then `gh pr ready --undo` runs as soon as the run concludes and `isDraft` is re-read `true`.
- Given Phase 1 only reaches D, then the addendum and the comment say "suite-red coverage, not the CI leg" and AC1 is reported undischarged.

## Out of scope (constraints from the brief)

Not done in this run, each stays as it stands: revoking, scoping down or deleting `doppler_service_token.inngest_arm_write` (item 8; a prerequisite retirement PR comes first); removing the G2e pin (waits until 2026-11-17 or the next host replace, then folds into Guard 1 unless AC1 shows a gap, which this run reports as a fact in comment A and the addendum); dispatching or authorizing `apply_target=inngest-host-replace`; closing #9927; the A6 owner sentence; the off-project ciphertext copy; any C4 edit; any `.github/**` or `scripts/**` edit.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one is filled.
- `test-scripts (3/8)` is a shard of a required aggregate, not a required context itself; say "the required `test` aggregator" when asserting the merge-blocking property.
- A draft push SKIPS `test-scripts`; never cite a draft's red `test` as the proof.
- The 40 s and 72 s numbers come from different runners; do not average them or call either "the CI wall time of test-scripts (3/8)" unless the red-proof job log printed it.
- `lint-infra-no-human-steps.py` rejects a human-actor token paired with an infrastructure imperative; word the ordering constraint as a sequencing fact ("the retirement PR precedes any revoke"), not as an instruction to a person.
- The throwaway commit may be refused by the local pre-commit gate; that is evidence, not a failure. Do not bypass it without a recorded CTO ruling (Phase 1 step 5).
- Do not use `Closes #9927` anywhere (PR body, commit messages); `Ref #9927`.
