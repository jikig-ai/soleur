# Tasks — fix: image-pull transient retry (#6525)

Plan: `knowledge-base/project/plans/2026-07-17-fix-image-pull-transient-retry-plan.md`
Lane: single-domain (engineering / infra) — no spec.md preexisted; lane set from work scope.

## Phase 1 — RED (write failing tests first) — `apps/web-platform/infra/ci-deploy.test.sh`

- [x] 1.1 Add `_pull_result_is_transient` classifier positive tests: assert return 0 for each fleet-real transient stderr from `ci-deploy.test.sh:3555-3600` (`network is unreachable`, `read: connection reset by peer`, `EOF`, `no such host`, `connection refused`, `i/o timeout`, `TLS handshake timeout`, `temporary failure`) PLUS deepen-research additions (`context deadline exceeded`, `received unexpected HTTP status: 503`, `request canceled while waiting for connection`, `server misbehaving`).
- [x] 1.2 Add classifier negative tests: assert non-zero for an auth string (`denied: requested access to the resource is denied`) and manifest strings (`manifest unknown`, `no such manifest` — note `no such` shared prefix with transient `no such host`) — must not swallow higher-precedence classes.
- [x] 1.3 Assert `pull_failure_event` still tags `pull_result=network` for a transient stderr after the refactor (grouping value unchanged).
- [x] 1.4 Add a transient mock arm (`MOCK_GHCR_PULL_TRANSIENT_COUNT_FILE` countdown emitting a network-class stderr) next to the `:340-362` deny machinery.
- [x] 1.5 Test — transient retry RECOVERS: count=1 + `PULL_TRANSIENT_RETRY_SLEEPS="0 0"` ⇒ 2 GHCR pulls, `transient_recovered` event (`op:image-pull-recovery`), NO `pull_failure_event`, success.
- [x] 1.6 Test — transient retry EXHAUSTS: transient every pull + `PULL_TRANSIENT_RETRY_SLEEPS="0 0"` ⇒ exactly 3 GHCR pulls, `pull_failure_event` with `pull_result=network` + `recovery_stage=transient_exhausted`, failure, NO recovery event.
- [x] 1.7 Test — manifest/unknown stderr ⇒ exactly 1 GHCR pull (no retry), `pull_result=manifest_unknown`, empty `recovery_stage` (regression guard).
- [x] 1.8 Test (deepen GAP-7) — mixed transient→manifest tail: transient once then manifest stderr ⇒ 2 GHCR pulls, `pull_result=manifest_unknown`, `recovery_stage` EMPTY (NOT `transient_exhausted`).
- [x] 1.9 Grep guard — `pull_failure_event` network arm calls `_pull_result_is_transient` (single source of truth), mirroring `:3423-3427`.
- [x] 1.10 Confirm #6400 AC1/AC2/AC14 + AC4 remain (do not edit except to add the shared mock arm); auth-`recovered` vs transient-`recovered` labels stay disjoint.

## Phase 2 — GREEN (source) — `apps/web-platform/infra/ci-deploy.sh`

- [x] 2.1 Add `_pull_result_is_transient` beside `_pull_result_is_auth_denied` (`~:533`) with the anti-drift doc comment. Regex (case-insensitive): `context deadline exceeded|timeout|timed out|temporary failure|no route|connection refused|connection reset|network is unreachable|no such host|server misbehaving|request canceled while waiting|received unexpected http status: 5|\bEOF\b` (verified non-overlapping with auth + manifest tokens).
- [x] 2.2 Rewire `pull_failure_event`'s network arm (`:549`) to call `_pull_result_is_transient`; keep precedence auth → manifest_unknown → transient → pull_failed; keep emitted tag value `network`. (Note: widens the `network` set — see 3.3.)
- [x] 2.3 In `_ghcr_pull_or_recover` (`:1376-1397`) add the bounded transient loop per the EXPLICIT skeleton in the plan (Phase 2.3): `# shellcheck disable=SC2206` + `local -a _sleeps=( ${PULL_TRANSIENT_RETRY_SLEEPS:-2 4} )`; loop `docker pull`; success with `attempt>0` emit `pull_auth_recovery_event … transient_recovered` + `return 0`; auth branch = #6400 recovery VERBATIM (its inner `pull_auth_recovery_event … recovered; return 0` stays inside) then `return 1`, NEVER loops; transient branch = `sleep "${_sleeps[$attempt]}"` + `attempt++` + continue while `attempt<max`; transient-exhausted arm (transient && attempt==max) sets `RECOVERY_STAGE=transient_exhausted` + `return 1`; else (manifest/unknown) `return 1` with EMPTY recovery_stage (no false exhausted tag — deepen GAP-7).
- [x] 2.4 Comment the one-level-retry decision (zot stays immediate-fallback; caller does not retry), the disjoint-label invariant (attempt increments only on transient arm), the gate-omits-manifest-arm rationale (deepen GAP-5b), and the ≤6 s added-wall-clock bound.

## Phase 3 — Verify

- [x] 3.1 `bash apps/web-platform/infra/ci-deploy.test.sh` fully green (incl. #5145 drift guard `:2890-2972`).
- [x] 3.2 `shellcheck apps/web-platform/infra/ci-deploy.sh` — no new findings (inline `# shellcheck disable=SC2206` on the array line).
- [x] 3.3 Reclassification safety (deepen L1): grep `infra/sentry/` + soak scripts (`zot-soak-6122.sh`, `*op-contract*`) for `pull_result` — confirm no alert/soak keys on `pull_result=pull_failed` or the narrow pre-widening `network` set.
- [ ] 3.4 Document worst-case added wall-clock (≤6 s/leg, ≤12 s total) in the PR body.

## Ship

- [ ] S.1 PR body uses `Ref #6525` (not `Closes`) — soak-gated close.
- [ ] S.2 Note automatic delivery via `apply-deploy-pipeline-fix.yml` on merge (no operator SSH).
