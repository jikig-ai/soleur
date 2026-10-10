# Tasks: argv-bearer sweep S4 (push-triggered production-class files)

Plan: knowledge-base/project/plans/2026-10-09-fix-argv-bearer-sweep-s4-push-triggered-production-class-plan.md
Rules for every task: no credential value is printed, echoed or compared in the clear; no git stash and no process pattern-kill; no `rm` on a variable path (`git ls-files -z` with `tar --null`);
poll with Monitor, never `run_in_background`; edit and `git commit` in separate Bash calls (gitleaks scans the index first); baseline E regenerated only after the merge-from-main commit exists.
PR carries `Ref #9597` and `Ref #7797` (never `Closes`). S5 is out of scope. Do not run `test-all.sh` locally.

## Phase 0: Gates, measure, replay, then RED

- 0.0 Record the lead's notice and choices (kill-switch option, D4 sparse-checkout default, D3 inline exceptions) in the decision file before any edit; keep the CPO assessment for the PR draft.
- 0.1 `git fetch origin main`; read `gh pr view 9877 --json files` and its diff; merge main if anything touching S4 files landed. Re-run the census: baseline E 17/42, S4 13 files / 31 sites, 20 `-hmac` sites.
- 0.2 Derive the coupled-suite list (`git grep -l` each S4 file name and step string across `apps/web-platform/{infra,test,scripts}`, `plugins/soleur/test`, `scripts`, `tests`, `.github/scripts/test`); run every hit read-only on a scratch conversion outside the worktree; compare to the "Stub holders" table; `cutover-inngest-workflow.test.sh` is run, not edited.
- 0.3 Replay every converted call's non-credential arguments and real body (SQL payload, Resend bodies, mint `scope_body`) through the library's `_bc_tail_ok`; zero refusals; record the count.
- 0.4 Credential-shape counts (value-free): Cloudflare Access pair, `HCLOUD_TOKEN_READONLY`/`HCLOUD_TOKEN`, `SUPABASE_ACCESS_TOKEN`, `RESEND_API_KEY`, webhook key (non-empty only).
- 0.5 `docker run` the `soleur-s3-runner` image (`/var/tmp/s3-inner.sh`; rebuild if missing): record bash, curl, git, python3 versions; measure the D7 `GIT_CONFIG_COUNT` header against a local bare remote.
- 0.6 Verify by grep and read: inngest-health `secret_unset` routing, `listener_state` consumers, `PRE_FRAME_STATUS` consumers, every `verdict=redeploy_*` consumer; record the revert trigger.
- 0.7 Write the RED rows (stage S4 skeleton, lint fixtures, suite edits); run `plugins/soleur/test/c4-count-parity.test.sh`; record RED counts.

## Phase 1: lint extension and battery scaffolding (commit 1)

- 1.1 `scripts/lint-workflow-local-action-checkout.py`: script consumers derived from the tree (Guard 3); fixtures and rows in `scripts/lint-workflow-local-action-checkout.test.sh`; floor re-derived.
- 1.2 `tests/scripts/test-argv-bearer-sweep.sh`: stage S4 skeleton (controls, derived populations, manifests).

## Phase 2: composites and `track.sh` (commit 2)

- 2.1 `mint-infra-app-token/action.yml`: library, keep every census needle line, revoke without `2>&1`.
- 2.2 `track.sh`: library by `BASH_SOURCE` after the xtrace refusal, `bc_ok_var` presence loop, reuse `redeploy_credential_absent`.
- 2.3 `tests/scripts/test-dispatch-web-redeploy.sh` (P2 reads stdin) and `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh` (anchor, `GITHUB_WORKSPACE`).

## Phase 3: dispatch-only and self-fire workflows (commit 3)

- 3.1 `restart-inngest-server.yml` (single `MAX_POLLS=`/`POLL_INTERVAL=` lines kept; pre-guard before the poll).
- 3.2 `deploy-inngest-image.yml` (sparse checkout first step).
- 3.3 `apply-inngest-rls.yml` (pre-guard to `secret_unset`, drop `2>/dev/null`, keep `/v1/projects/` and `identity_mismatch`).
- 3.4 `apply-github-infra.yml` Revoke step (keep URL, `DELETE`, `if`, env).

## Phase 4: `apply-deploy-pipeline-fix.yml` (commit 4)

- 4.1 Seven sites (pre_frame to `secret_unavailable`; `webhook_liveness` to `probe_error`; alive, redeploy, journald red); keep `id: webhook_liveness` and the `if:` lines the mutation harness anchors on.
- 4.2 Run `infra-config-gate.test.sh` and `ship-deploy-pipeline-fix-gate.test.ts` read-only.

## Phase 5: `web-platform-release.yml` (commit 5)

- 5.1 Sparse checkout as first step of `deploy` and `release-outcome` (before the ordering guard, no `ref:`, no differing `if:`).
- 5.2 Five sites; keep "Deploy via webhook" name, `WEB_HOST_PRIVATE_IPS`, Resend literals, `IN_FLIGHT_CEILING_S`; replace the two "no checkout" comments.
- 5.3 `scripts/lint-workflow-step-env-refs.test.sh` (`GITHUB_WORKSPACE` in `envargs` and the mirror arm). 5.4 File stays under 490,000 bytes.

## Phase 6: infra scripts and two suites (commit 6, infra path)

- 6.1 `push-infra-config.sh` (xtrace refusal, library by `BASH_SOURCE`, sign the payload file, `bc_curl` with `--data-binary @file`; no new `"x_b64":` string).
- 6.2 `infra-config-verify.sh` (xtrace refusal, inline wrapper, canonical snippet, pre-guard) with `infra-config-verify.test.sh` (stub, `ALLOWED`, control copy) and `infra-config-repush-mutation.test.sh` (S3 anchor).
- 6.3 `verify-tunnel-ingress-origin.sh` (canonical snippet at `HMAC=`); `python3` symlink in the battery's `VT_STUBS`.
- 6.4 `github-app-key-status.sh` (library by `BASH_SOURCE`, exit 3 on an unusable credential).

## Phase 7: held-back sites (commit 7, infra path)

- 7.1 `scheduled-inngest-health.yml` `probe` (library inside the `fail_mode` arm, `::error::` on source failure, pre-guard to `secret_unset`) and one `cp` line in `inngest-dedicated-host-classify.test.sh`.
- 7.2 `workspaces-luks-cutover.yml` Hetzner read (inline wrapper) and two stub arms in `workspaces-luks-cutover-workflow.test.sh`.

## Phase 8: `bump-inngest-bootstrap-pin.sh` (commit 8)

- 8.1 Remote without userinfo plus a per-command `GIT_CONFIG_*` header; shape guard and marker; suite rows (`g2.script:token-from-env` rewritten, no-token-in-recorded-argv row).

## Phase 9: battery completion, docs, ADR, lint docstring (commit 9)

- 9.1 Finish stage S4 (Guards 1 and 2); update the S3-stage manifest and held-back expectations 1:1; set `EXPECTED_TESTS` to the realized count. 9.2 `scripts/lib/test-affected-paths.sh` edges.
- 9.3 Lint docstring paragraphs. 9.4 Amend ADR-280 (D11). 9.5 Runbook rows quoting the old form (grep).

## Phase 10: verification, gates, baseline-only commit, tracking

- 10.1 Every changed shell suite on `ubuntu:24.04` with equal row counts. 10.2 Mutation-check Guards 1 to 3 (landed per `diff -q`, unmutated control first). 10.3 Revert recipe dry-run in a scratch tree through every gate (both kill-switch lines).
- 10.4 Pre-push gates (Rule E explicit-path and repo-wide, battery, grep-q-pipe-guard, supabase-deprecated-endpoints, orphan-test-suites, guard-vacuity-floor, fixture-env-adoption, fixture ratchets, skill-body budget, rule-bodies, gitleaks, errexit-capture, run-body-syntax, workflow-file-size, c4-count-parity).
- 10.5 `git merge origin/main`; regenerate baseline E; drop 13 ceiling rows; update A and D baselines; expect E = 4 files / 11 sites. 10.6 PR body contract. 10.7 File the follow-through and the decision-challenge issue; comment on #9597 and #9757.

## Phase 11: lead notice, review, ship, post-merge

- 11.1 Stop before ship with a factual `<stop>BLOCKED: ...</stop>` lead notice (infra paths, workflows fired, kill-switch choices, revert plan, no dispatch planned).
- 11.2 Review (report-only seats under `/var/tmp`, fix-round capped, trailer). 11.3 `soleur:archive-kb` after ship Phase 6, before merge. 11.4 `gh pr merge --squash --auto`; never sync an armed BEHIND PR.
- 11.5 Post-merge: `deploy-arm.sh find --wait <full sha>` then `served` from a detached `origin/main` worktree; the 13 verification rows of the plan; `postmerge`.
