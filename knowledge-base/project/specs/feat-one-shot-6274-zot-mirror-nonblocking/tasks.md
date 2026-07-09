# Tasks — fix(release): GHCR→zot mirror non-blocking (#6274)

Plan: `knowledge-base/project/plans/2026-07-09-fix-zot-mirror-nonblocking-release-plan.md`
Lane: single-domain (engineering/infra CI). Brand-survival threshold: none.

## Phase 1 — Setup / Preconditions
- [x] 1.1 Ensure `actionlint` is available (install per repo convention if absent). Do NOT `bash -n` a `.yml`. — actionlint 1.7.7 present.
- [x] 1.2 Confirm both mirror steps still lack `continue-on-error` (reusable-release.yml:669, build-inngest-bootstrap-image.yml:240). — confirmed on origin/main.
- [x] 1.3 Read the Slack step (reusable-release.yml:765-836) to confirm payload/mrkdwn shape + `released` gate.

## Phase 2 — Core Implementation
### 2.1 reusable-release.yml — mirror step (669-702)
- [x] 2.1.1 Add `id: zot_mirror` + `continue-on-error: true`.
- [x] 2.1.2 Change inner shell `set -euo pipefail` → `set -uo pipefail`; add bounded `retry()` helper (3 attempts, 5s/15s backoff).
- [x] 2.1.3 Wrap `crane copy` (per-tag) + `cosign sign` in `retry`; `|| degraded "$?"` guarded exit-0.
- [x] 2.1.4 On failure: `mirror_status=degraded` → `$GITHUB_OUTPUT`, `::warning::` + `$GITHUB_STEP_SUMMARY`, `exit 0`. On success: `mirror_status=ok`.
### 2.2 reusable-release.yml — Slack step (765-836)
- [x] 2.2.1 Append a "⚠️ zot mirror degraded — release OK (GHCR primary)…" line to the release message when `steps.zot_mirror.outputs.mirror_status == 'degraded'`; keep valid mrkdwn; default path unchanged.
### 2.3 build-inngest-bootstrap-image.yml — mirror step (240-253)
- [x] 2.3.1 Add `id: zot_mirror` + `continue-on-error: true`; same `set -uo pipefail` + `retry docker tag`/`retry docker push` + degraded-signal + exit-0. No Slack (documented scope decision — `::warning::` + step summary only).
### 2.4 ADR-096 amendment
- [x] 2.4.1 Add the non-blocking + `mirror_status` degraded-signal note under the "Loud, no-SSH signal" cold-boot axis; status stays `Adopting`; no new ADR.

## Phase 3 — Testing
- [x] 3.1 `actionlint` on both files — baseline-equivalent (0 new shellcheck notes, 0 error-severity; main already exits 1 on pre-existing style notes and CI does not run actionlint). Plan's literal "exit 0" was a stale precondition.
- [x] 3.2 Created `plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh` (per reusable-release-idempotency.test.sh convention): T1 persistent→3 attempts+degraded+::warning::+exit0; T2 transient→ok; T3 happy→ok. 3/3 pass.
- [x] 3.3 Ran new test (3/3) + reusable-release-idempotency.test.sh (26/26, T7 Slack contract) + reusable-release-caller-permissions.test.sh (4/4) — no regression. infra-lint CI-mode (`--changed --base origin/main`) exit 0 on 4 changed files.

## Phase 4 — Ship prep
- [ ] 4.1 PR body: `Closes #6274` + `## Changelog` (semver:patch — bug fix). Verify Pre-merge ACs (AC1-AC8). [ship]
- [ ] 4.2 File the deferred follow-up issue (live zot mirror-staleness Sentry alert rule) with labels `observability`, `domain/engineering`, `deferred-automation`, `priority/p3-low`; re-eval at ADR-096 Phase-5 cutover. [ship self-audit]
- [ ] 4.3 Post-merge: verify AC9 on the first release run (`gh run list --workflow web-platform-release.yml` → conclusion `success`; `gh run view <id> --log | grep 'zot mirror'`). [post-merge]
