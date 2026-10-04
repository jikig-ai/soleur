# Tasks: #8609 R-step 3 — deliver the isolated-key read token to web-1

Plan: knowledge-base/project/plans/2026-10-03-chore-8609-r3-deliver-github-app-read-token-to-web-1-plan.md
PR: #9452 (draft). Reference `Refs #8609`, never `Closes`. No hand dispatch. Stop before R4.

## Phase 0 — Pre-merge baseline (read-only)

- [x] 0.1 Confirm origin/main literal is `generation=0` at apps/web-platform/infra/server.tf (derive N; bump is N+1)
- [x] 0.2 Confirm Tier-B name `GITHUB_APP_RUNTIME_DOPPLER_TOKEN` exists (`doppler secrets --only-names`, no value read)
- [x] 0.3 Capture web-1 /etc/default/soleur-doppler-token sha256 via the signed infra-config-status GET (digest only); baseline 69cc2b49f20aacc357189bf381c9c60fa026e1d3d985f622c9e9a107274589fd (2026-10-03); record in PR body
- [x] 0.4 Confirm no running/queued run of apply-web-platform-infra.yml or apply-deploy-pipeline-fix.yml, and no auto-merge PR touching apps/web-platform/infra/**

## Phase 1 — The one-line edit (work phase)

- [x] 1.1 sed the literal `=0` -> `=1` at server.tf:2041; assert grep -c == 1 and diff is 1 insertion/1 deletion
- [x] 1.2 Commit `chore(8609): deliver the soleur-github-app read token to web-1 (generation 1)`; no `[skip-deploy-fix-apply]`; stage only server.tf (o13-path-test.txt is untracked scratch)
- [x] 1.3 Run tier census test, ship-deploy-pipeline-fix-gate and terraform-target-parity tests

## Phase 2 — PR

- [ ] 2.1 Update PR #9452: title, `Refs #8609` body, baseline digest, #9348 no-conflict note, three-workflows-fire note, rollback, STOP-before-R4
- [ ] 2.2 Mark ready, merge via normal path after checks; skip ship's generic post-merge workflow_dispatch

## Phase 3 — Post-merge verification (read-only)

- [ ] 3.1 Resolve merge SHA
- [ ] 3.2 Find apply-deploy-pipeline-fix run with headSha == merge SHA (empty = wait); Monitor to completion sized for the web-1-swap queue; conclusion success (not cancelled) AND the apply job not skipped
- [ ] 3.3 Anchored log match `##[notice]source=tier_b.*github_app_runtime_token=delivered`, `tier-2 byte compare ACTIVE`, Verify infra-config apply succeeded step success (not skipped)
- [ ] 3.4 Signed read: digest differs from baseline, status ok, changed true; comment digests on #9452 and #8609 (do not close)
- [ ] 3.5 /health status ok; report-only github-app-key-status.sh read of the auto-release (not R4's verdict)
- [ ] 3.6 STOP; report to operator; R4 needs its own ack; note the auto-triggered release tag
