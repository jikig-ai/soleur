# Tasks: retire the web-2 LUKS rebirth and web-host reboot machinery and close #9372 (PR 2, cleanup)

Plan: `knowledge-base/project/plans/2026-10-12-chore-web2-luks-rebirth-retirement-cleanup-plan.md`

Branch `feat-one-shot-9372-web2-luks-cleanup-pr2`, draft PR #10083. Brand-survival threshold: none. Single PR (tombstone row makes the split non-viable).

## Phase 0: Re-verify (read-only)

- 0.1 `git fetch origin main`; confirm #9372 and #9642 OPEN, #6931 CLOSED.
- 0.2 Grader (`SOLEUR_FT_EARLIEST=2026-10-10T20:10:00Z doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/web2-luks-live-6931.sh`) and `python3 scripts/lint-encryption-posture.py --repo-sweep`. Stop and report on #9372 if either is not green.
- 0.3 Record BEFORE numbers in the scratchpad: c4-count-parity (13 pass), main-root census count, G2 population, tsv row counts, kb-consumers baseline size, guard-vacuity deferred-ledger figure.
- 0.4 Apply-gate prerequisites: `on.push.paths` of both apply workflows; re-grep that no `filesha256`/`file()` covers a `.tf` file or `lb-weight-gate.sh`; last 3 apply runs still fail only on the two egress provisioners (#10003).
- 0.5 Read the three `.c4` model files and every stale-wording site in full.
- 0.6 `pipeline-tally.sh init`; no baseline ratchet-lane run (it runs once, in 6.1).

## Phase 1: Failing test first

- 1.1 Run the one-line AC1 census command RED before any deletion (allowed remnants named in the plan's Phase 1.1).

## Phase 2: Delete (`git rm`)

- 2.1 Workflows and infra suites (4 files).
- 2.2 `scripts/web2-rebirth*` (9 files) and `scripts/web-host-reboot*` (3 files).
- 2.3 `tests/scripts` gates, suites and fixtures (8 files).

## Phase 3: Registrations and ratchets

- 3.1 `terraform-target-parity.test.ts`: `MAIN_ROOT_TF_WORKFLOWS`, rebirth describe block, derived census count, G2 rewrite with scratch control (Guard Contract).
- 3.2 `nic-wait-gate.test.sh` rebirth rows; `workspaces-luks-verify-workflow.test.sh` READERS; `.claude/hooks/grep-q-pipe-guard.test.sh` row.
- 3.3 `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/guard-vacuity-floor.test.sh`, `run-registered-suites.sh` bound.
- 3.4 `regenerate-shard-manifest.py --group light|infra --incremental --write`; fixture-relative baseline; kb-consumers baseline (`--write-baseline` only if stale).
- 3.5 `infra-validation.yml` comment block and three path entries.
- 3.6 Re-run the census; extension-less basename sweep over `.github/`, `scripts/*.txt`, `*.tsv`, baselines.

## Phase 4: Stale wording (comments only)

- 4.1 `workspaces-luks.tf` (two sites), `server.tf` (four sites), `lb-weight-gate.sh` (two sites), `workspaces-luks-header-web.tf` (after reading the jq filter), `workspaces-luks-verify.yml` CUSTODY comment, `inngest-provision-rehearsal.yml` comment.
- 4.2 Proof: comment-stripped byte-equality against `origin/main` for each `.tf`; `terraform fmt -check`; `terraform validate`; the infra suites named in the plan; `lint-encryption-posture` suite and `--repo-sweep`.

## Phase 5: Records

- 5.1 ADR-263: frontmatter `accepted`, one dated Status note, one 2026-10-12 retirement addendum (which also supersedes the 2026-10-11 "Status. Unchanged" paragraph).
- 5.2 ADR-241 dated line; `infra-credential-tiers-8209.md` rows marked retired.
- 5.3 Runbook `web2-luks-rebirth-9372.md` rows 4 and 5 done lines, status correction; `web-host-reboot.md` RETIRED banner; dated marks in `betterstack-log-query.md`, `web-host-birth.md`, `web-host-replace.md`.
- 5.4 `model.c4` three edge sentences; `bash scripts/regenerate-c4-model.sh`; c4-count-parity, c4-code-syntax, c4-render.
- 5.5 Learning with the three requirements (content-level emptiness evidence, a second gate after the evidence step, a credential-parity check).

## Phase 6: Gates, commit, PR

- 6.1 Commit locally (6.3), then `bash scripts/pre-push-ratchet-lane.sh` (it merges committed HEAD), harness-parity-tree, the two linters the lane does not run, `lint-infra-no-human-steps.py --changed --base origin/main`; all before the first push.
- 6.2 Affected suites named in the plan (terraform-target-parity, guard-vacuity-floor, kb-consumers, c4-count-parity, tier census, token census, nic-wait-gate).
- 6.3 Local commits (done before 6.1) with the Claude attribution line; no closing keyword in any title or commit message.
- 6.4 PR body: `Closes #9372`, `Ref #9642`, both "Ruled by CTO agent" lines, apply-gate analysis, count tables, scope disclosure; `auto-close-scan.sh` on title, body and each commit message.
- 6.5 `gh pr merge --squash --auto`; BEHIND is expected; watch with Monitor.

## Phase 7: After merge

- 7.1 Postmerge: required checks, push-apply log discriminator, workflows no longer active, grader and `--repo-sweep` PASS.
- 7.2 Final comment on #9372 (graded rows only; reopen, recovery and emptiness not claimed); close if the keyword did not.
- 7.3 Close #9642 by hand with run IDs 37508997529, 37516716515, sweeper run 38083925201, the ruling, this PR and the learning path.
- 7.4 File no new issue; leave #9572, #9984, #9948, #9949, #10003 open.
