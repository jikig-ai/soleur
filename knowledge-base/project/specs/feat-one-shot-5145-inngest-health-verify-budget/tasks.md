# Tasks — fix(infra): verify_inngest_health cron-plan budget (#5145)

Plan: `knowledge-base/project/plans/2026-06-11-fix-inngest-health-verify-cron-plan-budget-plan.md` (deepened 2026-06-11 — this file reflects the post-deepen contract)
Lane: cross-domain (spec lacks valid `lane:` — defaulted fail-closed)

## Phase 1 — RED: static assertions in ci-deploy.test.sh (use `[[:space:]]`, never `\s`)

- [ ] 1.1 Cron-budget pin block (inline `TOTAL/PASS/FAIL` per `ci-deploy.test.sh:2031-2040`; comment cites #5145 + regression classes): four checks —
  - [ ] 1.1.1 `local cron_max_attempts=40` present (exact-value pin; catches silent down-tuning)
  - [ ] 1.1.2 `seq 1 "$cron_max_attempts"` present (the `seq` FORM is load-bearing — a C-style `for ((...))` refactor escapes the seq mock and blows the 5-min CI timeout; say so in the comment)
  - [ ] 1.1.3 relative ordering proves the cron budget drives the SECOND loop: `line(seq 1 "$max_attempts") < line(seq 1 "$cron_max_attempts") < line(/v1/functions curl)` via `grep -n` (ordering, never absolute line numbers)
  - [ ] 1.1.4 both verify probes still carry `curl -sf --max-time 5` (count = 2 in function region — the drift guard's `+5` derives from this)
- [ ] 1.2 Cross-file drift guard:
  - [ ] 1.2.1 extract generically by shape (`cron_max_attempts=([0-9]+)`, `\$\{1:-([0-9]+)\}`, `\$\{2:-([0-9]+)\}` from `$DEPLOY_SCRIPT`; `MAX_POLLS=([0-9]+)`, `POLL_INTERVAL=([0-9]+)` from `$SCRIPT_DIR/../../../.github/workflows/restart-inngest-server.yml`) — NOT literal values; a retune must re-run the inequality, not die as unparseable
  - [ ] 1.2.2 every `$(grep ...)` carries `|| true` (suite runs `set -euo pipefail`; precedent `:1833`); every value validated `[[ "$v" =~ ^[0-9]+$ ]]` BEFORE arithmetic (empty string in `$((v * 5))` silently evaluates 0 — inequality would pass wrongly); validation FAIL is the RED path
  - [ ] 1.2.3 assert exactly ONE assignment match each for `MAX_POLLS=` / `POLL_INTERVAL=` in the workflow
  - [ ] 1.2.4 inequality: `MAX_POLLS*POLL_INTERVAL >= (health + cron) * (interval + 5) + 180 + 60` — inline comments: `+5` = per-attempt `curl --max-time 5` tail (source: 1.1.4 pin); `+180` = `TimeoutStopSec=180` hung-stop before verify (`inngest-bootstrap.sh:178`); `+60` = handoff/flock/client-curl margin
  - [ ] 1.2.5 FAIL message prints all five extracted values + both sides of the inequality + both file names (precedent `:2016`)
- [ ] 1.3 Run `bash apps/web-platform/infra/ci-deploy.test.sh` — both new blocks FAIL cleanly (no abort), baseline 81 stays green

## Phase 2 — GREEN: ci-deploy.sh contract change

- [ ] 2.1 Add `local cron_max_attempts=40` after `local interval` (constant, NOT positional); rationale comment MUST contain literal `--poll-interval 60` (AC4), the two-poll-cycle derivation, #5145, and why constant-not-positional (call sites must stay arg-less)
- [ ] 2.2 Switch second (`/v1/functions`) loop to `seq 1 "$cron_max_attempts"`; update its three log lines (`attempt $i/$cron_max_attempts`, terminal line). First loop untouched
- [ ] 2.3 Extend function doc comment (`:191-200`) for the separate cron-loop budget
- [ ] 2.4 Rewrite `:856-866`: delete "~30s retry budget covers the window"; state poll-cycle invariant; cite #5145; state the gate is "≥1 cron-triggered function registered" (deliberate weak-form proxy — full coverage owned by Sentry cron monitors, `cron-monitors.tf`)
- [ ] 2.5 Verify call sites `:366` / `:367` area and `:867` stay byte-identical arg-less (wiring grep at `ci-deploy.test.sh:2007`)

## Phase 3 — restart workflow client window + freshness guard

- [ ] 3.1 `Verify restart completion` run block: define `MAX_POLLS=140`, `POLL_INTERVAL=5` (700s ≥ 580s worst + 60s margin); replace `seq 1 30`, every `Attempt $i/30` (6 as of writing — sweep all), both `sleep 5`, and `within 150s` (`:107`) → `within $((MAX_POLLS * POLL_INTERVAL))s`
- [ ] 3.2 Freshness guard: `TRIGGER_TS=$(date +%s)` in trigger step (via `$GITHUB_ENV`); verify loop requires `start_ts >= TRIGGER_TS - 60` (60s clock-skew tolerance; field is schema-stable, `ci-deploy.sh:70-72`) before honoring ANY terminal inngest state; stale state logs `state predates this trigger — waiting` and keeps polling
- [ ] 3.3 Header comment (`:2`) update + cross-reference to the ci-deploy.test.sh drift guard (#5145, incl. TimeoutStopSec rationale)
- [ ] 3.4 `actionlint .github/workflows/restart-inngest-server.yml` + `bash -n` on extracted run snippet (never on the .yml)

## Phase 3.5 — CI trigger coverage + runbook row

- [ ] 3.5.1 Add `.github/workflows/restart-inngest-server.yml` to `infra-validation.yml` `on.pull_request.paths` (drift guard cannot otherwise fire on client-side edits; `deploy-script-tests` job is ungated so this completes the topology)
- [ ] 3.5.2 Add `inngest_health_failed` row to the Reason Taxonomy in `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` (`:43-67`): exit 1; /health unreachable OR no cron trigger after budget; Sentry-green = #5145 slow-resync signature

## Phase 4 — verify

- [ ] 4.1 `bash apps/web-platform/infra/ci-deploy.test.sh` → 0 failed, total ≥ 83 (AC7)
- [ ] 4.2 Run AC1–AC9 grep battery from the plan (use `[ "$(grep -c ...)" = "0" ]` form for negative greps — `grep -c` exits 1 on zero matches)
- [ ] 4.3 PR body: `Ref #5145` (NOT Closes — AC10); mention deferral issue #5148

## Post-merge (automated)

- [ ] 5.1 AC11: `apply-deploy-pipeline-fix.yml` run for merge SHA `conclusion: success` AND infra-config-status per-file sha256 for `/usr/local/bin/ci-deploy.sh` equals `sha256sum apps/web-platform/infra/ci-deploy.sh` at merge SHA (invariant, not proxy — #4804 class)
- [ ] 5.2 AC12: the merge-push-triggered restart run MAY go red against the old host script (expected, not a regression); after 5.1, `gh workflow run restart-inngest-server.yml && gh run watch` → green; then `gh issue close 5145` with PR + run URLs
