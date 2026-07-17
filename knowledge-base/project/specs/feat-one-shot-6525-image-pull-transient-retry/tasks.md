# Tasks — fix: image-pull transient retry (#6525)

Plan: `knowledge-base/project/plans/2026-07-17-fix-image-pull-transient-retry-plan.md`
Lane: single-domain (engineering / infra) — no spec.md preexisted; lane set from work scope.

## Phase 1 — RED (write failing tests first) — `apps/web-platform/infra/ci-deploy.test.sh`

- [ ] 1.1 Add `_pull_result_is_transient` classifier positive tests: assert return 0 for each fleet-real transient stderr reused verbatim from `ci-deploy.test.sh:3555-3600` (`network is unreachable`, `read: connection reset by peer`, `EOF`, `no such host`, `connection refused`, `i/o timeout`, `TLS handshake timeout`, `temporary failure`).
- [ ] 1.2 Add classifier negative tests: assert non-zero for an auth string (`denied: requested access to the resource is denied`) and a manifest string (`manifest unknown`) — must not swallow higher-precedence classes.
- [ ] 1.3 Assert `pull_failure_event` still tags `pull_result=network` for a transient stderr after the refactor (grouping value unchanged).
- [ ] 1.4 Add a transient mock arm (`MOCK_GHCR_PULL_TRANSIENT_COUNT_FILE` countdown emitting a network-class stderr) next to the `:340-362` deny machinery.
- [ ] 1.5 Test — transient retry RECOVERS: count=1 + `PULL_TRANSIENT_RETRY_SLEEPS="0 0"` ⇒ 2 GHCR pulls, `transient_recovered` event (`op:image-pull-recovery`), NO `pull_failure_event`, success.
- [ ] 1.6 Test — transient retry EXHAUSTS: transient every pull + `PULL_TRANSIENT_RETRY_SLEEPS="0 0"` ⇒ exactly 3 GHCR pulls, `pull_failure_event` with `pull_result=network` + `recovery_stage=transient_exhausted`, failure, NO recovery event.
- [ ] 1.7 Test — manifest/unknown stderr ⇒ exactly 1 GHCR pull (no retry), `pull_result=manifest_unknown`, empty `recovery_stage` (regression guard).
- [ ] 1.8 Grep guard — `pull_failure_event` network arm calls `_pull_result_is_transient` (single source of truth), mirroring `:3423-3427`.
- [ ] 1.9 Confirm #6400 AC1/AC2/AC14 + AC4 remain (do not edit except to add the shared mock arm).

## Phase 2 — GREEN (source) — `apps/web-platform/infra/ci-deploy.sh`

- [ ] 2.1 Add `_pull_result_is_transient` beside `_pull_result_is_auth_denied` (`~:533`) with the anti-drift doc comment. Regex: `timeout|timed out|i/o timeout|temporary failure|no route|connection refused|connection reset|network is unreachable|no such host|tls handshake timeout|\bEOF\b` (case-insensitive).
- [ ] 2.2 Rewire `pull_failure_event`'s network arm (`:549`) to call `_pull_result_is_transient`; keep precedence auth → manifest_unknown → transient → pull_failed; keep emitted tag value `network`.
- [ ] 2.3 In `_ghcr_pull_or_recover` (`:1376-1397`) add the bounded transient loop: `local -a _sleeps=( ${PULL_TRANSIENT_RETRY_SLEEPS:-2 4} )`; loop `docker pull`; on success with `attempt>0` emit `pull_auth_recovery_event … transient_recovered`; auth branch = existing #6400 recovery verbatim and `return` from inside (never loop); transient branch = `sleep "${_sleeps[$attempt]}"` + `attempt++` + continue while `attempt<max`; else set `RECOVERY_STAGE=transient_exhausted` (when `attempt>0`) and `return 1`.
- [ ] 2.4 Comment the one-level-retry decision (zot stays immediate-fallback; caller does not retry) and the ≤6 s added-wall-clock bound.

## Phase 3 — Verify

- [ ] 3.1 `bash apps/web-platform/infra/ci-deploy.test.sh` fully green (incl. #5145 drift guard `:2890-2972`).
- [ ] 3.2 `shellcheck apps/web-platform/infra/ci-deploy.sh` — no new findings (if wired).
- [ ] 3.3 Document worst-case added wall-clock (≤6 s/leg, ≤12 s total) in the PR body.

## Ship

- [ ] S.1 PR body uses `Ref #6525` (not `Closes`) — soak-gated close.
- [ ] S.2 Note automatic delivery via `apply-deploy-pipeline-fix.yml` on merge (no operator SSH).
