# Tasks: feat-one-shot-git-data-luks-cutover-8211

Plan: knowledge-base/project/plans/2026-10-12-fix-git-data-rotate-post-apply-gate-and-cutover-resume-plan.md

## Phase 1 - Live flip-precondition report (read-only)

- 1.1 Read `git_data_ssh_client=present` on the deployed build (Better Stack) and tie it to the deployed sha
- 1.2 Confirm the pin secret name present in prd (names only) and a post-redeploy `git_data_pin=present` line
- 1.3 Confirm pin-fault Sentry rule 1310055 live (fidelity script or latest drift run, under 24 h)
- 1.4 Re-read heartbeat: status up, newest state=ok under 15 min, later than boot_complete
- 1.5 Write flip-preconditions-report.md (VERIFIED / NOT VERIFIED per row; list owner-gated remainder)

## Phase 2 - Fix #10137 / #10067

> SUPERSEDED 2026-10-12: the Phase 2 code change was reverted (fa58f3388e; kept at d2a1d0e766) in favour of PR #10155, which owns #10137; do not implement 2.1-2.5 here and do not add Closes #10137/#10067 to this PR.

- 2.1 Write RED rows PA1-PA12 in tests/scripts/test-git-data-host-replace-gate.sh (tests first)
- 2.2 Add `git_data_post_apply_gate` to tests/scripts/lib/git-data-host-replace-gate.sh
- 2.3 Replace the post-apply blocks in apply-web-platform-infra.yml with the sourced call; add APPLY_TARGET env; keep step name
- 2.4 Raise the anti-vacuity floor; run the shell suite, tier census suite, terraform-target-parity test, shellcheck
- 2.4b Read the d6 reader (git-data-cutover.yml) and the post-assert replace steps for rotate-specific assumptions; record findings on #10137 only
- 2.4c Reuse the plan-time gate's rotate LUKS jq predicate (action-set match, not order) in the new function
- 2.5 Merge origin/main before push; do not touch PRs 10133/10086/7390; PR body Closes #10137, Closes #10067; no dispatch

## Phase 3 - K1 census addendum

- 3.1 Derive the workflow set (wider K1 pattern + L1(a) subset count)
- 3.2 Run the read-only non-main census into $K1_DIR (new filenames); counts and run ids only
- 3.3 Resolve workflow-touching subset by SHA; count unresolved
- 3.4 Write knowledge-base/legal/audits/2026-10-12-8209-k1-nonmain-run-census-addendum.md
- 3.5 soleur:legal:clo reviews and signs; confirm no existing legal file changed

## Phase 4 - Designs (documents only)

- 4.1 design-wipe-body-pr.md
- 4.2 design-rollback-rehearsal.md
- 4.3 design-9943-liveness-precheck.md
