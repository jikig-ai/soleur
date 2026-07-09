# Tasks — fix(release): GHCR→zot mirror non-blocking (#6274)

Plan: `knowledge-base/project/plans/2026-07-09-fix-zot-mirror-nonblocking-release-plan.md`
Lane: single-domain (engineering/infra CI). Brand-survival threshold: none.

## Phase 1 — Setup / Preconditions
- [ ] 1.1 Ensure `actionlint` is available (install per repo convention if absent). Do NOT `bash -n` a `.yml`.
- [ ] 1.2 Confirm both mirror steps still lack `continue-on-error` (reusable-release.yml:669, build-inngest-bootstrap-image.yml:240).
- [ ] 1.3 Read the Slack step (reusable-release.yml:765-836) to confirm payload/mrkdwn shape + `released` gate.

## Phase 2 — Core Implementation
### 2.1 reusable-release.yml — mirror step (669-702)
- [ ] 2.1.1 Add `id: zot_mirror` + `continue-on-error: true`.
- [ ] 2.1.2 Change inner shell `set -euo pipefail` → `set -uo pipefail`; add bounded `retry()` helper (3 attempts, 5s/15s backoff).
- [ ] 2.1.3 Wrap `crane copy` (per-tag) + `cosign sign` in `retry`; `set +e`/rc-capture/`set -e` around the guarded block.
- [ ] 2.1.4 On failure: `mirror_status=degraded` → `$GITHUB_OUTPUT`, `::warning::` + `$GITHUB_STEP_SUMMARY`, `exit 0`. On success: `mirror_status=ok`.
### 2.2 reusable-release.yml — Slack step (765-836)
- [ ] 2.2.1 Append a "⚠️ zot mirror degraded — release OK (GHCR primary)…" line to the release message when `steps.zot_mirror.outputs.mirror_status == 'degraded'`; keep valid mrkdwn; default path unchanged.
### 2.3 build-inngest-bootstrap-image.yml — mirror step (240-253)
- [ ] 2.3.1 Add `id: zot_mirror` + `continue-on-error: true`; same `set -uo pipefail` + `retry docker tag`/`retry docker push` + degraded-signal + exit-0. No Slack (documented scope decision — `::warning::` + step summary only).
### 2.4 ADR-096 amendment
- [ ] 2.4.1 Add the non-blocking + `mirror_status` degraded-signal note under the "Loud, no-SSH signal" cold-boot axis; status stays `Adopting`; no new ADR.

## Phase 3 — Testing
- [ ] 3.1 `actionlint` passes on both workflow files (exit 0).
- [ ] 3.2 Create `plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh` (per reusable-release-idempotency.test.sh convention):
  - T1 persistent-fail stub → 3 attempts, `mirror_status=degraded`, `::warning::`, exit 0.
  - T2 transient (fail-then-succeed) → `mirror_status=ok`, exit 0, no `::warning::`.
  - T3 happy path → `mirror_status=ok`, exit 0.
- [ ] 3.3 Run the new test + `plugins/soleur/test/reusable-release-idempotency.test.sh` to confirm no regression.

## Phase 4 — Ship prep
- [ ] 4.1 PR body: `Closes #6274` + `## Changelog` (semver:patch — bug fix). Verify Pre-merge ACs (AC1-AC8).
- [ ] 4.2 File the deferred follow-up issue (live zot mirror-staleness Sentry alert rule) with labels `observability`, `domain/engineering`, `deferred-automation`, `priority/p3-low`; re-eval at ADR-096 Phase-5 cutover.
- [ ] 4.3 Post-merge: verify AC9 on the first release run (`gh run list --workflow web-platform-release.yml` → conclusion `success`; `gh run view <id> --log | grep 'zot mirror'`).
