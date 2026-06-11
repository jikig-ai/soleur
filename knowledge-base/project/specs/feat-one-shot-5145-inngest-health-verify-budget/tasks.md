# Tasks — fix(infra): verify_inngest_health cron-plan budget (#5145)

Plan: `knowledge-base/project/plans/2026-06-11-fix-inngest-health-verify-cron-plan-budget-plan.md`
Lane: cross-domain (spec lacks valid `lane:` — defaulted fail-closed)

## Phase 1 — RED: static assertions in ci-deploy.test.sh

- [ ] 1.1 Add cron-budget pin assertion (inline `TOTAL/PASS/FAIL` style per `ci-deploy.test.sh:2031-2040`): greps `$DEPLOY_SCRIPT` for `local cron_max_attempts=40` AND `seq 1 "$cron_max_attempts"`; comment cites #5145 + both regression classes (shared-budget collapse, silent down-tuning)
- [ ] 1.2 Add cross-file drift guard: extract `${1:-10}`, `${2:-3}`, `cron_max_attempts=40` from `$DEPLOY_SCRIPT` and `MAX_POLLS=` / `POLL_INTERVAL=` from `$SCRIPT_DIR/../../../.github/workflows/restart-inngest-server.yml`
  - [ ] 1.2.1 Validate every extracted value is a non-empty integer; loud FAIL naming both files otherwise (this is also the RED path)
  - [ ] 1.2.2 Assert `MAX_POLLS*POLL_INTERVAL >= (health_attempts + cron_attempts) * (interval + 5) + 60`; inline comments justify `+5` (per-attempt `curl --max-time 5` tail) and `+60` (systemd restart step + client curl overhead)
- [ ] 1.3 Run `bash apps/web-platform/infra/ci-deploy.test.sh` — expect 83 total, exactly 2 failing (clean FAIL, no abort), baseline 81 green

## Phase 2 — GREEN: ci-deploy.sh contract change

- [ ] 2.1 Add `local cron_max_attempts=40` after `local interval` (constant, NOT positional); rationale comment MUST contain literal `--poll-interval 60` (AC4), the two-poll-cycle derivation, #5145, and why constant-not-positional
- [ ] 2.2 Switch second (`/v1/functions`) loop to `seq 1 "$cron_max_attempts"`; update its three log lines (`attempt $i/$cron_max_attempts`, terminal line). First loop untouched
- [ ] 2.3 Extend function doc comment (`:191-200`) to mention the separate cron-loop budget
- [ ] 2.4 Rewrite `:856-866` deploy-arm comment: delete "~30s retry budget covers the window" claim; state poll-cycle invariant; cite #5145
- [ ] 2.5 Verify call sites `:366` / `:867` stay byte-identical (arg-less — wiring grep at `ci-deploy.test.sh:2007`)

## Phase 3 — restart workflow client window

- [ ] 3.1 In `Verify restart completion` run block: define `MAX_POLLS=100`, `POLL_INTERVAL=5`; replace `seq 1 30`, every `Attempt $i/30` (6 as of writing — sweep all), both `sleep 5`, and `within 150s` (`:107`) → `within $((MAX_POLLS * POLL_INTERVAL))s`
- [ ] 3.2 Update header comment (`:2`) if it names the old window; add cross-reference to the ci-deploy.test.sh drift guard (#5145)
- [ ] 3.3 `actionlint .github/workflows/restart-inngest-server.yml` + `bash -n` on extracted run snippet (never on the .yml)

## Phase 4 — verify

- [ ] 4.1 `bash apps/web-platform/infra/ci-deploy.test.sh` → 83/83, 0 failed (AC6)
- [ ] 4.2 Run AC1–AC5 grep battery from the plan (use `[ "$(grep -c ...)" = "0" ]` form for negative greps)
- [ ] 4.3 PR body: `Ref #5145` (NOT Closes — AC8)

## Post-merge (automated)

- [ ] 5.1 Poll `apply-deploy-pipeline-fix.yml` run for merge SHA → `conclusion: success` (AC9; workflow self-verifies host delivery per #4804)
- [ ] 5.2 `gh issue close 5145` with PR + run URLs after 5.1 (AC10)
