# Tasks — Fail-loud on Sentry POST failures from ci-deploy.sh (D-6, #6475 Item 2)

Plan: `knowledge-base/project/plans/2026-07-18-feat-ci-deploy-sentry-post-fail-followthrough-plan.md`
Lane: single-domain (engineering / CI-infra observability)
Branch: `feat-one-shot-6475-ci-deploy-sentry-fail-loud`

## Phase 0 — Preconditions (verify, do not assume)

- [x] 0.1 `grep -n '|| logger -t "\$LOG_TAG"' apps/web-platform/infra/ci-deploy.sh` — expect 7 "Sentry POST failed" lines (437,517,541,609,635,666,1157); confirm `readonly LOG_TAG="ci-deploy"`.
- [x] 0.2 `grep -n '"ci-deploy"' apps/web-platform/infra/vector.toml` — expect it inside `host_scripts_journald` SYSLOG_IDENTIFIER allowlist (Source 4).
- [x] 0.3 `grep -c 'BETTERSTACK_QUERY_' .github/workflows/scheduled-followthrough-sweeper.yml` ≥ 3 (HOST/USERNAME/PASSWORD already wired — no workflow edit).
- [x] 0.4 Read `scripts/betterstack-query.sh` mode-1 (raw SQL) branch + `$BS_TABLE`/`$BS_TABLE_S3` tokens (needed for AND-scoping; `--grep` is OR-only).
- [x] 0.5 Confirm `scripts/test-all.sh` discovers `scripts/followthroughs/*.test.sh`; confirm the `<NAME>_BQ` mock-override seam (per `hostname-mislabel-web1-6616.test.sh`).

## Phase 1 — Write the probe (RED then GREEN)

- [x] 1.1 Create `scripts/followthroughs/ci-deploy-sentry-post-fail-6475.sh` mirroring `chardevice-wedge-nonrecurrence-5934.sh` (Better Stack query + liveness gate + fail-safe TRANSIENT).
- [x] 1.2 POST-failure query = mode-2 `betterstack-query.sh --since "$WINDOW" --grep "Sentry POST failed" --limit 1000` (auto-UNIONs hot+archive) THEN post-filter output `grep -c 'ci-deploy'` (precedent: `chardevice` `denied_count()`). Window = `CI_DEPLOY_SENTRY_SOAK_WINDOW` (default `7d`). Confirm the `ci-deploy` discriminator's substring form in one real Better Stack row before freezing the post-filter. (Raw-SQL mode-1 with two `LIKE`s is the documented alternative — if used, write the `s3Cluster` UNION yourself.)
- [x] 1.3 Liveness gate: separate `--grep "ci-deploy"` count of ANY ci-deploy rows in window. Zero → `exit 2` (TRANSIENT), never PASS.
- [x] 1.4 Exit map: zero POST-failure + liveness≥1 → `exit 0`; ≥1 POST-failure → `exit 1` (fail-loud, print offending `dt`/`raw`); query/auth/creds/no-liveness → `exit 2`.
- [x] 1.5 Guards: `set -uo pipefail`; NO `: "${VAR:?}"` — use `if [[ -z "${VAR:-}" ]]; then echo TRANSIENT >&2; exit 2; fi`. Honor a `<NAME>_BQ` override for the query-script path (test seam). Validate window `^[0-9]+[hmd]$`.
- [x] 1.6 `chmod +x`.

## Phase 2 — Probe unit tests

- [x] 2.1 Create `scripts/followthroughs/ci-deploy-sentry-post-fail-6475.test.sh` (stub `betterstack-query.sh` via the `<NAME>_BQ` seam; JSONEachRow fixtures; no network/creds).
- [x] 2.2 Cases: POST-failure+liveness→1 (alarm, load-bearing); clean+liveness→0; zero-liveness→2; BQ non-zero→2; empty `BETTERSTACK_QUERY_*`→2 (never 1); invalid window→2.
- [x] 2.3 `bash scripts/test-all.sh` green (or the targeted `bash scripts/followthroughs/ci-deploy-sentry-post-fail-6475.test.sh` exit 0).

## Phase 3 — Enroll #6475 (automatable, no operator/SSH step)

- [x] 3.1 `gh issue edit 6475 --add-label follow-through`.
- [x] 3.2 Add directive to #6475 body (`gh issue edit 6475 --body …`, preserving existing body): `script=scripts/followthroughs/ci-deploy-sentry-post-fail-6475.sh earliest=<merge+7d UTC ISO> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD`.
- [ ] 3.3 PR body uses **`Ref #6475`** (NOT `Closes`). Closure deferred to sweeper on soak PASS.

## Phase 4 — Verify (post-merge, automatable)

- [ ] 4.1 `gh workflow run scheduled-followthrough-sweeper.yml -f dry_run=true` — confirm #6475 directive parsed + probe executed (TRANSIENT before `earliest`).
- [ ] 4.2 Discoverability (no SSH): `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 7d --grep "Sentry POST failed"` returns rows-or-empty.

## Acceptance Criteria — see plan §Acceptance Criteria (AC1–AC9, Pre-merge / Post-merge split)
