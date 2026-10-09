# Tasks: decouple the zot claim from ci-deploy.sh and take the fan-out HMAC key off argv (#9799 items 2 and 3)

Plan: knowledge-base/project/plans/2026-10-09-chore-decouple-zot-claim-from-ci-deploy-and-hmac-key-off-argv-plan.md
Draft PR: #9805 (Ref #9799, Ref #9597; no close-keyword)

## Phase 0: Baseline (read-only)

- 0.1 Run `python3 scripts/lint-shell-trace-credential-refusal.py` (plain and `--changed`) on `apps/web-platform/infra/ci-deploy.sh`; expect OK, 0 baselined.
- 0.2 Run `zot-image-staleness.test.sh` (expect 15/0) and `zot-image-staleness-mutation.test.sh` (expect 18/18).
- 0.3 Run `ci-deploy.test.sh`; record the row total (expect 502) before touching `CI_DEPLOY_ASSERT_FLOOR`.

## Phase 1: RED tests first

- 1.1 `ci-deploy.test.sh`: add T-9799 rows beside T-9795-1/-2 (synthetic secrets only).
  - 1.1.1 Byte-identity matrix: 6 secrets x 3 commands = 18 comparisons vs `openssl dgst -sha256 -hmac`; assert exactly 18 ran, all 64-hex.
  - 1.1.2 No secret on any argv (python3/openssl/curl shadow functions); openssl never invoked.
  - 1.1.3 Empty secret and `null` secret: rc 1, curl never called.
  - 1.1.4 python3 unavailable (shadow returns 127): rc 1, curl never called.
  - 1.1.5 Malformed signature from a shadow python3: rc 1, curl never called.
  - 1.1.6 Source census: no `openssl dgst` in the file; canonical snippet present once.
  - 1.1.7 Key present only in the python3 call's environment.
- 1.2 `zot-image-staleness.test.sh`: add check 11 (ci-deploy.sh exists, zero `CLAIM_RE` matches); confirm RED against the current comment.
- 1.3 `zot-image-staleness-mutation.test.sh`: add cases (current-version claim in ci-deploy.sh; ci-deploy.sh removed; check 11 deleted -> rc 2; stale claim in cloud-init only; coherent bump GREEN with `cmp` of ci-deploy.sh against pristine); retarget `m_l`, `m_q`, `m_p`.

## Phase 2: GREEN

- 2.1 `ci-deploy.sh` `fan_out_to_peers`: canonical python3 snippet, 64-hex shape guard with `FANOUT:` log + `return 1`, replace the "Known remaining site" comment. Keep the hunk minimal.
- 2.2 `ci-deploy.sh`: drop the `zot vX.Y.Z` token from the comment above `_docker_login_failure_class`, point at the sidecar register.
- 2.3 `zot-image-staleness.test.sh`: `CLAIM_RE` hoist, followers and required locations = `ci-deploy.test.sh` + `cloud-init-registry.yml`, `MIN_ASSERTIONS` 16, header comment.
- 2.4 `zot-image.provenance.md`: recovery steps 1-2 (conditional marker requirement), register row 1 location text, trigger-file policy sentence.
- 2.5 Raise `CI_DEPLOY_ASSERT_FLOOR` to the measured total with a dated history comment.
- 2.6 Dry-run the sidecar revert recipe in a scratch detached worktree.

## Phase 3: Mutation proof

- 3.1 Hand-apply Guard 2 rows 1-5 and Guard 1 rows 1-4 to scratch copies; confirm each reddens for the stated reason; record the table for the PR body.

## Phase 4: Gates

- 4.1 Lint (plain and `--changed`), `check-deploy-script-parity.sh --self-test` and its `.test.sh` (no live arm), staleness gate (16/0), battery, `ci-deploy.test.sh`.
- 4.2 `git diff --name-only origin/main...HEAD` excludes `cloud-init-registry.yml`, `zot-registry.tf`, `variables.tf`, `server.tf`, `.github/workflows/*`.

## Phase 5: Ship

- 5.1 Commit bodies and the squash body carry `[skip-web-platform-apply]` and `[skip-deploy-fix-apply]` alone on their own lines (form of f911a789); never `[ack-destroy]`.
- 5.2 PR body: `Ref #9799`, `Ref #9597`, delivery waits for the next sanctioned apply (tracker item 1), no close-keyword next to either number, ends with the Claude Code attribution line.
- 5.3 Merge through the normal merge queue; do not sync a queued PR. After merge, one comment on #9597 (S4 `ci-deploy.sh` row done).
