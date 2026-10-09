# Tasks: zot pin bump + docker.pkg.github.com hosts-file deny, one registry-host replace

Plan: `knowledge-base/project/plans/2026-10-08-chore-zot-pin-v2-1-22-and-docker-pkg-github-deny-registry-replace-plan.md`
Branch: `feat-one-shot-9252-zot-pin-bump-ghcr-deny` | PR 9795 | Issues: Ref #9252, Ref #9390

## Phase 0 - Preconditions (read-only)

- 0.1 Confirm branch, fetch `origin/main`, tree has only the stray `.mcp.json` change (never `git add -A`).
- 0.2 Re-read live state: three workflow states, `gh release list -R project-zot/zot --limit 3`, `gh pr view 9783 --json state`.

## Phase 1 - Rotate previous-known-good, resolve digests

- 1.1 Rotate `## Previous known-good pin` to the v2.1.20 refs, tag-less (`zot-linux-<arch>@sha256:`), both arches, dated; add v2.1.20 release tag, T, C.
- 1.2 Resolve BOTH arch digests at the target tag (`crane digest`); confirm they differ.
- 1.3 Edit `zot_image_amd64`, `zot_image_arm64` in `zot-registry.tf` and `## Current pin` together.
- 1.4 Commit A; push the branch.

## Phase 2 - Anchors, claims, breaking-change scan

- 2.1 Re-diff the four upstream anchors (source at the tags); update the config-compatibility table.
- 2.2 Step 3b: list `!:`/BREAKING commits between tags; re-measure #4363 (two-repo HEAD/mount, both pinned digests); answer the one shared-layer question; apply the STOP rule (testable items only); add one scan line to the sidecar's Bump procedure; record `hydrateBlobOnRead` NOT ADOPTED in the sidecar.
- 2.3 Re-measure 200-or-401 and gc-404 with the exact `config.json` (synthetic users, bcrypt htpasswd); zero 403 or STOP.
- 2.4 Update the three `zot vX.Y.Z` comment sites in `cloud-init-registry.yml`, the `ci-deploy.sh` claim block and the `ci-deploy.test.sh` 401-fixture comment (version + measurement date; staleness check 7 reads all three). Reword `scripts/followthroughs/zot-fill-rate-7341.sh` (zot#4235 closed, fixed by #4236 in v2.1.21+); list `reusable-release.yml:1070` and that script in the sidecar claim register as unregistered claims.
- 2.6 Re-stamp capture date; `zot-image-staleness.test.sh` exit 0; `zot-image-staleness-mutation.test.sh` green.

## Phase 3 - Publish boot asset before the bump merges

- 3.1 `gh workflow run zot-image-mirror.yml --ref feat-one-shot-9252-zot-pin-bump-ghcr-deny`; watch to completion.
- 3.2 Read PUBLISHED_T from the run; derive C from the manifest `.config.digest`.
- 3.3 Pin `zot_mirror_asset_sha256_amd64` and `zot_config_digest_amd64`; commit B; push.
- 3.4 `GH_TOKEN="$(gh auth token)" bash scripts/registry-replace-preflight.sh --check-asset` prints `verdict=CLEAR predicate=P6`.
- 3.1b Only the dispatch's `publish` job matters here; its `rehearse` and the PR's `rehearse` plus staleness check 7 are expected RED until the final commit.
- 3.5 PR `rehearse` x3 green (reproduces T and C). Hard gate: do not mark ready before this and before T differs from the v2.1.20 value.

## Phase 4 - Hosts-file deny at every site (tests first)

- 4.1 RED: update `web-ghcr-deny.test.sh`, `zot-image-fetch.test.sh` (R5, R10 counts), `cloud-init-ghcr-seed-login.test.sh` to expect `ghcr.io pkg-containers.githubusercontent.com docker.pkg.github.com`; add the guard-contract mutation rows (drop from assert only, fourth name in copy A, reorder in copy B, zero rendered entries).
- 4.2 GREEN: edit copy R (`cloud-init-registry.yml`), copy A (`cloud-init.yml`), copy B (`server.tf` `ghcr_deny_sh` and `ghcr_deny_assert_sh`).
- 4.3 Sweep `git grep` for any other deny literal; disposition each (cron-egress / Sentry hits are #9275, untouched).
- 4.4 Size/render gates (AC8 list): `registry-userdata-budget.sh --json` (headroom > 10 kB), `registry-userdata-budget.test.sh`, `registry-render-delta.test.sh`, `registry-boot-guard.test.sh`, `cloud-init-user-data-size.test.ts`, `ci-deploy.test.sh`.
- 4.5 Render-diff proof, HEAD vs `origin/main`: only pin-derived values and the deny line differ.

## Phase 5 - Docs

- 5.1 ADR-096 dated amendment line (deny names three hosts).
- 5.2 Record the 2026-10-08 `active` workflow observation in the PR body (not in ADR-169 / the runbook).
- 5.3 Sidecar tables and `## Why` complete; floor stays v2.1.19.

## Phase 6 - Ship

- 6.1 One branch commit message BODY (not the subject) with `[skip-web-platform-apply]` and `[skip-deploy-fix-apply]` on their own lines; none with `[ack-destroy]`; trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- 6.2 `python3 scripts/lint-guard-contract.py`, `python3 scripts/lint-infra-no-human-steps.py <plan>`.
- 6.3 PR body: `Ref #9252`, `Ref #9390`, delivery model, rollback values, Generated-with-Claude-Code line. Mark ready; enqueue; do not sync a queued PR; no `.github/workflows` change so the normal merge path applies.
- 6.4 Local read-only preflight (`doppler run -p soleur -c prd_terraform -- bash scripts/registry-replace-preflight.sh`) before enqueue; attach the verdict line.

## Phase 7 - Delivery and verification (pipeline-fired; agent reads)

- 7.1 Watch the dispatcher run for the merge SHA; do not fire a second dispatch. On any red gate: stop, record run URL / verdict kind / predicate on PR 9795 and #9390, report (never `--manual` for P1 without an explicit go, never `[ack-destroy]`, no plain web-host-replace, no web-2 rebirth, no web-1 / git-data targets).
- 7.1b If a push apply runs anyway: read-only, record the run URL, do not cancel or re-fire, report. If no ok telemetry row within 60 min of the apply's conclusion: stop and report.
- 7.1c Pre-enqueue (6.x): `git log origin/main..HEAD --format=%B | grep -x '\[skip-web-platform-apply\]'` and the same for `[skip-deploy-fix-apply]`.
- 7.2 Verify via `betterstack-query.sh --grep SOLEUR_ZOT_DISK`: `zot_image_fetch=ok`, final D12, `ghcr_blocked=1`, `state_status=running` (`ghcr_blocked` covers ghcr.io only; the third name is proven by R10 + the render diff).
- 7.3 Confirm the push-apply runs for the merge SHA show preflight skip=true (AC14).
- 7.3b 24 h soak: `zot_restarts=0`, no error/fatal `zot_last_err`, next release `crane copy` inside its window; report failures, no auto-revert.
- 7.4 Close #9390 with evidence (state the limit: no per-name telemetry); leave #9252 open (PR 9783); file the running-host delivery tracking issue.

## Failure branches (see plan `## Failure Branches`)

- F.1 Mirror dispatch red / T differs from rebuild (STOP before pinning) / dispatch `rehearse` red (tell pin mismatch from boot failure).
- F.2 Queue ejection: fix on branch, re-run greps and render diff, re-confirm AC6, re-enqueue; never sync a queued PR.
- F.3 No dispatcher run within 10 min of the merge SHA: stop and report, no manual dispatch. `deliver=false`: post `watermark=` lines, stop; recovery only on an explicit go.
- F.4 Hold other infra PRs out of the queue until AC13 is green; confirm both marker lines via `gh pr view 9795 --json commits`.
- F.5 Measure web gzip size vs `WEB_GZIP_BUDGET` (23,800) before/after copy A; raise in this PR if within ~30 B.
- F.6 Revert commit (if ever) carries the same two marker lines; re-fire and rollback are explicit-go-only.
