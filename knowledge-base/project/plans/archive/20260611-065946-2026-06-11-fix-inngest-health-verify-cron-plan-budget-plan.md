---
title: "fix(infra): give verify_inngest_health's cron-plan loop its own budget (120s) so healthy inngest deploys stop recording inngest_health_failed"
type: fix
date: 2026-06-11
issue: 5145
lane: cross-domain
brand_survival_threshold: none
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan introduces NO new infrastructure. All systemctl/restart
     mentions below are DESCRIPTIVE of existing ci-deploy.sh behavior, not prescribed
     operator steps. Prod delivery is fully automated via the existing
     apply-deploy-pipeline-fix.yml auto-apply on merge (HTTPS webhook target, self-verifying
     per #4804). Zero operator steps; both post-merge ACs are gh-CLI automated. -->

# fix(infra): verify_inngest_health cron-plan budget — 30s shorter than post-restart registry re-sync

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-06-11
**Agents used:** repo-research-analyst, learnings-researcher, DHH/Kieran/code-simplicity plan-review, architecture-strategist, test-design-reviewer, observability-coverage-reviewer, spec-flow-analyzer, verify-the-negative + self-audit sweeps (all attribution claims `gh`-verified live; all behavioral negative claims grep-confirmed against source).

### Key improvements from the deepen pass

1. **Client window re-derived from the true worst case** — `MAX_POLLS=140` (700s): verify tail-case 400s (`curl --max-time 5` per attempt) + `TimeoutStopSec=180` hung-stop budget (`inngest-bootstrap.sh:178`) + 60s margin = 640s required. Earlier drafts (300s, 500s) certified windows the server could structurally outrun.
2. **CI enforcement topology fixed** — `infra-validation.yml` does NOT trigger on `restart-inngest-server.yml` edits (`on.pull_request.paths` = `apps/*/infra/**` only), so the cross-file drift guard could never fire on client-side drift; the workflow path is added to the paths filter in the same PR.
3. **Delivery AC converted from proxy to invariant (AC11)** — auto-apply run success + per-file `sha256` comparison from `/hooks/infra-config-status` against the merged file (the state endpoint already serves per-file hashes; run-success alone can read a stale green state, the #4804 class).
4. **Merge-ordering side effect named** — this PR edits `restart-inngest-server.yml`, whose push trigger is path-scoped to itself: the merge dispatches a REAL prod inngest restart concurrently with the auto-apply, racing the old 30s budget. That run may legitimately go red; the post-merge sequence re-dispatches the workflow after delivery is verified (AC12) as the live end-to-end check.
5. **Stale-success race closed in the poll loop** — first poll after the 202 can read the PREVIOUS green inngest state before the new run writes `running`; a `start_ts >= TRIGGER_TS - 60` freshness guard (schema field already exists, `ci-deploy.sh:70-72`) is added while every literal in that block is being touched anyway.
6. **Observability citation corrected** — ci-deploy's `logger -t` lines run under `webhook.service` at user.notice priority; Vector's journald sources filter by unit (`inngest-server.service`) and priority (0-4/0-2), so these lines are NOT shipped to Better Stack. The no-SSH surface is deploy-state + Sentry cron monitors; per-attempt diagnostics depth is deferred with a tracking issue.

## Overview

`verify_inngest_health()` in `apps/web-platform/infra/ci-deploy.sh:201` gates both the `restart inngest` action (`:367`) and the `deploy inngest` path (`:868`) on two probes that **share** one budget (`max_attempts=10`, `interval=3` ≈ 30s each):

1. `/health` — process liveness (fast: server answers as soon as it boots).
2. `/v1/functions` must contain a `"cron":` trigger — cron-plan integrity (#4650 H9b).

The inngest server runs with `--poll-interval 60` (`apps/web-platform/infra/inngest-bootstrap.sh:162`). When the immediate post-restart SDK sync races the web-platform container, the registry only populates on the **next 60s poll cycle** — structurally beyond the 30s cron-plan budget. Result: a healthy deploy writes `exit_code: 1, reason: inngest_health_failed` into deploy-state, which `/hooks/deploy-status` then serves as a permanent false negative (observed on the 2026-06-11 `deploy inngest v1.1.13`, the PR #5131 remediation deploy).

**Fix:** give the cron-plan loop its own internal budget constant (`40 × 3s = 120s` nominal ≈ two poll cycles) while keeping the fast `/health` loop untouched, and raise the one client-side poller whose window the new server-side worst case would outrun (`.github/workflows/restart-inngest-server.yml`, currently 30 × 5s = 150s — must exceed verify tail-case 400s incl. the `curl --max-time 5` per attempt, plus the unit's `TimeoutStopSec=180` hung-stop budget that can precede the verify).

`ci-deploy.sh` is a `terraform_data.deploy_pipeline_fix` trigger file: the merge to `main` auto-fires `.github/workflows/apply-deploy-pipeline-fix.yml` (paths filter `:66`), which pushes the file to the prod host over HTTPS and **self-verifies delivery** via the infra-config-status endpoint (#4804). No operator step.

## Premise Validation

Checked 2026-06-11: issue #5145 is OPEN with zero `closedByPullRequestsReferences`; ref PR #5131 is MERGED (2026-06-11T00:46Z); `verify_inngest_health` exists at `ci-deploy.sh:201` with the shared `${1:-10}`/`${2:-3}` budget exactly as the issue describes; both call sites (`:367`, `:868`) are arg-less. The `apply-deploy-pipeline-fix.yml` paths filter includes `apps/web-platform/infra/ci-deploy.sh`. No stale premises.

## Research Reconciliation — Issue vs. Codebase

| Issue claim | Reality | Plan response |
| --- | --- | --- |
| "Sentry monitor `cron-egress-resolve` checked in at 05:18:57Z proving the registry synced and crons fire" | `cron-egress-resolve` is a **systemd timer** firing every 1 min (`apps/web-platform/infra/sentry/cron-monitors.tf:552-565`), not an Inngest cron — its check-in does not by itself prove Inngest registry sync | Treat the check-in as corroborative only. The load-bearing driver is structural: `--poll-interval 60` (`inngest-bootstrap.sh:162`) ≥ the 30s budget, plus the observed deploy-state payload (`exit_code:1` with `inngest_server: active`). The fix direction is unchanged. |
| "widen the /v1/functions cron-plan loop budget (e.g. max_attempts=30)" | 30 × 3s = 90s covers 1.5 poll cycles; a restart landing just after a poll tick plus sync latency can exceed it | Use 40 × 3s = 120s (two full poll cycles), per learning `2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md` (derive from measured worst case, not a round number). |
| "Single file: apps/web-platform/infra/ci-deploy.sh" | `restart-inngest-server.yml:60-107` polls deploy-status with a 30 × 5s = **150s client window**; new server-side restart worst case = hung-stop up to 180s (`TimeoutStopSec=180`, `inngest-bootstrap.sh:178`) + 50 attempts × (3s sleep + up to 5s `curl --max-time`) = **up to ~580s** — the client would time out on exactly the slow-resync case this fix tolerates | Widen the client poll to 140 × 5s = 700s in the same PR (≥ 400 + 180 + 60 = 640s required). Also extend `ci-deploy.test.sh` (static budget assertions), add the workflow to `infra-validation.yml` paths (drift guard cannot otherwise fire on client-side edits), and add the missing `inngest_health_failed` runbook taxonomy row. 5 files total. |
| ci-deploy.sh comment `:864-866`: "The post-restart SDK sync populates the registry immediately (not waiting for the 60s poll), so the existing ~30s retry budget covers the window." | Disproven by the 2026-06-11 deploy — the immediate sync can race; the poll cycle is the real ceiling | Rewrite the comment to state the actual invariant and cite #5145. |

## Proposed Solution

Inside `verify_inngest_health()` only (no call-site changes — see Sharp Edges):

```bash
# apps/web-platform/infra/ci-deploy.sh:201
verify_inngest_health() {
  local max_attempts="${1:-10}"        # /health loop — unchanged
  local interval="${2:-3}"             # shared sleep cadence — unchanged
  # #5145: the cron-plan loop needs its own, wider budget. The server runs
  # with --poll-interval 60 (inngest-bootstrap.sh); when the immediate
  # post-restart SDK sync races the web-platform container, the registry
  # only populates on the next 60s poll. 40 x 3s = 120s nominal covers two
  # full poll cycles. The /health loop stays fast: a dead process should
  # still fail in ~30s. Plain constant, NOT a positional default — the
  # call sites must stay arg-less (ci-deploy.test.sh wiring grep), so a
  # third parameter would be a knob nobody is allowed to turn.
  local cron_max_attempts=40
  ...
  for i in $(seq 1 "$cron_max_attempts"); do   # second loop only
    ...
  done
}
```

- Log lines in the cron loop reference `$cron_max_attempts` instead of `$max_attempts` (attempt counters and the terminal failure line).
- Rewrite the stale `deploy inngest` comment block (`ci-deploy.sh:856-866`) to drop "the existing ~30s retry budget covers the window" and state: registry re-sync may wait for the 60s poll cycle; the cron-plan loop budget (120s nominal) covers two cycles (#5145). The new function rationale comment MUST contain the literal string `--poll-interval 60` (AC4 greps for it — the existing `:857` mention line-wraps before the "60" and does NOT match).

In `.github/workflows/restart-inngest-server.yml` (Verify restart completion step):

- Hoist the budget into shell variables at the top of the `run:` block — `MAX_POLLS=140`, `POLL_INTERVAL=5` (700s client window ≥ 580s server worst case + 60s margin; worst case = 180s `TimeoutStopSec` hung-stop + 400s verify tail) — and replace every literal: `seq 1 30` → `seq 1 "$MAX_POLLS"`, every `Attempt $i/30` (6 occurrences as of writing — AC5 verifies none remain, do not trust the count), both `sleep 5` → `sleep "$POLL_INTERVAL"`, and the terminal message computed as `$((MAX_POLLS * POLL_INTERVAL))s` (replaces "within 150s" at `:107`). This removes the literal-drift class entirely.
- **Freshness guard (stale-success race):** capture `TRIGGER_TS=$(date +%s)` in the trigger step (export via `$GITHUB_ENV`); in the verify loop, before honoring ANY terminal state (`exit_code` 0 or ≥1 with `component=inngest`), require `start_ts >= TRIGGER_TS - 60` (60s skew tolerance — host writes `start_ts` with its own clock, `ci-deploy.sh:70-72`; the field is schema-stable and already consumed by `web-platform-release.yml:357,444`). A stale state logs `Attempt $i/$MAX_POLLS: state predates this trigger — waiting` and keeps polling. Without this, the first poll after the 202 can read the PREVIOUS green inngest state before the new run writes `running` (`write_state` happens only after webhook exec + flock, `ci-deploy.sh:340-353`) — a silent false success in the exact loop this plan rewrites.
- Update the file-header comment (`:2`) if it names the old window.

In `.github/workflows/infra-validation.yml`:

- Add `.github/workflows/restart-inngest-server.yml` to `on.pull_request.paths` (currently `apps/*/infra/**`, `infra/**`, and itself — verified 2026-06-11). Without this, a future PR editing only the restart workflow (e.g., re-lowering `MAX_POLLS`) never runs `ci-deploy.test.sh`, and the cross-file drift guard below can never fire on client-side drift. The `deploy-script-tests` job has no `if:` gate, so the paths addition is the complete fix.

In `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`:

- Add the missing `inngest_health_failed` row to the Reason Taxonomy table (`:43-67`): `inngest_health_failed | 1 | /health unreachable OR no cron-triggered function in registry after the cron-plan budget; if Sentry cron monitors are green this is the #5145 slow-resync signature — re-dispatch restart-inngest-server.yml after confirming host delivery`. The plan's failure-mode 1 routes responders to this runbook; today the table has no row for the reason they'd be holding.

In `apps/web-platform/infra/ci-deploy.test.sh` (use `[[:space:]]`, not `\s`, matching the file's grep dialect at `:1837`/`:2007`/`:2032`):

- Add a static-grep assertion pinning the cron-loop budget, following the inline `TOTAL/PASS/FAIL` precedent at `:2031-2040` (#5062 FD-200 guard), with a comment naming #5145 and the regression classes (shared-budget collapse AND silent down-tuning — the exact-value pin catches `40` being reverted toward `10`, which the drift guard below cannot). Four checks in one block:
  1. `local cron_max_attempts=40` present (exact-value pin);
  2. `seq 1 "$cron_max_attempts"` present — and pinning the `seq` FORM is itself load-bearing: a refactor to a C-style `for ((...))` loop would escape the seq mock and blow the 5-min CI timeout (say so in the comment);
  3. **relative ordering** proves the cron budget drives the SECOND loop, not a swapped pair: `line(seq 1 "$max_attempts") < line(seq 1 "$cron_max_attempts") < line(/v1/functions curl)` via `grep -n` (ordering, never absolute line numbers — precedent `:2005-2017`);
  4. both verify probes still carry `--max-time 5` (`grep -c 'curl -sf --max-time 5' inside the function region returns 2`) — the drift guard's `+5` term is derived from this value; without the pin, retuning `--max-time` silently invalidates the arithmetic.
- Add a cross-file drift guard: extract the values **generically by shape, not literal value** — `cron_max_attempts=([0-9]+)`, `\$\{1:-([0-9]+)\}`, `\$\{2:-([0-9]+)\}` from `$DEPLOY_SCRIPT`; `MAX_POLLS=([0-9]+)`, `POLL_INTERVAL=([0-9]+)` from `$SCRIPT_DIR/../../../.github/workflows/restart-inngest-server.yml` (a legitimate retune must re-run the inequality with the new value, not die as "unparseable"; exact-value pinning is the pin assertion's job). Then assert `MAX_POLLS × POLL_INTERVAL ≥ (health_attempts + cron_attempts) × (interval + 5) + 180 + 60`. Inline comments: `+5` = per-attempt `curl --max-time 5` tail (source: the `--max-time 5` pin above; sleep-only arithmetic undercounts the true worst case 2.6×); `+180` = `TimeoutStopSec=180` hung-stop budget the systemd restart can consume BEFORE the verify starts (`inngest-bootstrap.sh:178`); `+60` = handoff/flock/client-curl margin. Hardening requirements:
  - every `$(grep ...)` extraction carries `|| true` (the suite runs `set -euo pipefail`; a no-match grep exits 1 and would abort the suite at the assignment — precedent `:1833`);
  - every extracted value is validated `[[ "$v" =~ ^[0-9]+$ ]]` BEFORE any arithmetic — with a bare variable, `$((cron_attempts * 5))` on an empty string evaluates to **0 silently** and the inequality passes for the wrong reason;
  - assert exactly ONE assignment match for `MAX_POLLS=` and `POLL_INTERVAL=` in the workflow (a duplicate assignment would make `head -1` extraction silently ambiguous);
  - the FAIL message prints all five extracted values plus both sides of the inequality (precedent: the wiring test's `(verify=$DI_VERIFY_LINE fail=... success=...)` at `:2016`), naming both files.

  This is the same invariant class as the wrapper-1800s == `IN_FLIGHT_CEILING_S` runtime assert in `web-platform-release.yml:321-324`.

### Alternative Approaches Considered

| Approach | Verdict |
| --- | --- |
| Issue's alt: retry the whole verify once after a 60–120s delay before terminal failure | Rejected — re-runs the /health loop pointlessly, adds a second code path through `final_write_state`, and the per-loop budget achieves the same coverage with one mechanism |
| Pass wider budget as call-site args (`verify_inngest_health 10 3 40`) | Rejected — breaks the static wiring test at `ci-deploy.test.sh:2007` which greps `^[[:space:]]*verify_inngest_health[[:space:]]*$`; internal constant keeps both call sites arg-less |
| New `${3:-40}` positional default (plan v1) | Rejected at plan-review (DHH P1) — a parameter the Sharp Edges forbid anyone from passing is dead flexibility; plain `local cron_max_attempts=40` constant is simpler and simplifies the test regex |
| Read `--poll-interval` dynamically from the systemd unit file | Rejected — YAGNI; the value is pinned in `inngest-bootstrap.sh` and asserted by `inngest.test.sh:156`; a comment cross-reference suffices (same verdict for adding a third extraction file to the drift guard — disproportionate machinery) |
| Distinct `inngest_cron_plan_failed` reason for the second loop (deploy-state would self-identify the #5145 class) | Rejected — widens the reason enum, requiring a consumer sweep across every deploy-state reader (workflows, runbooks, postmerge skill); the runbook taxonomy row (Files to Edit #5) delivers the same operator disambiguation ("reason + Sentry green = slow-resync") without the enum change |
| Ship per-attempt verify diagnostics over HTTPS (add `webhook_journal_tail` via the existing `service_journal_tail` helper to `cat-deploy-state.sh`) | **Deferred with tracking issue** (created at plan time — see References) — ci-deploy's `logger -t` lines are NOT shipped to Better Stack (webhook.service unit + user.notice priority fall outside Vector's journald filters), so attempt-level diagnosis is SSH-only today; the terminal signal (deploy-state reason) suffices for this fix, and the state-schema addition deserves its own consumer sweep |

One deferral (tracking issue filed per the deferral gate); everything else in scope.

## Technical Considerations

- **Defense relaxation, new ceiling named** (per learning `2026-05-05-defense-relaxation-must-name-new-ceiling.md`): the old 30s cron-plan budget bounded time-to-detect a genuinely de-planned registry (H9b). New time to a terminal `inngest_health_failed` on the restart path: nominal ~30s health + 120s cron ≈ **150s** (was ~60s); hung-but-listening-server tail (every `curl --max-time 5` consumed): 50 × 8s = **400s** (was 160s). The failure is still terminal and recorded; independently, the Sentry cron monitors (`apps/web-platform/infra/sentry/cron-monitors.tf`) catch genuinely dead crons via missed check-ins regardless of deploy-state.
- **Wall-clock headroom:** `ci-deploy-wrapper.sh` caps the script at 1800s; the verify adds ≤ 270s tail-case over the old budget — ample. `web-platform-release.yml`'s `STATUS_POLL == HEALTH_POLL == IN_FLIGHT_CEILING_S == 1800` drift guard is untouched (that path deploys web-platform; `verify_inngest_health` never runs there).
- **Healthy-path latency unchanged:** both loops exit on first success; a healthy deploy still verifies in seconds. Only failing/slow-resync paths pay the wider budget.
- **`set -e` discipline:** keep `|| true` after every curl probe; never toggle `set -e` inside the function (learning `2026-05-27-bash-set-e-leaks-from-functions-use-or-true.md` — toggling kills the caller's `VERIFY_RC=$?` capture).
- **Probe vantage:** `/v1/functions` is loopback-gated (learning `2026-05-31-inngest-v1-loopback-gated-and-halt-on-stale-premise.md`); the probe stays in ci-deploy.sh on the host — do not relocate it.
- **Test harness reality:** `create_mock_seq` (`ci-deploy.test.sh:73-79`) makes every loop single-iteration, so budget *values* are untestable at runtime — static source-grep assertions are the established convention (precedents at `:1830-1846`, `:2005-2017`, `:2031-2040`). `sleep` is real; the seq mock is what keeps the suite inside `infra-validation.yml`'s 5-minute job timeout — do not weaken it.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — this is operator-facing deploy tooling. The operator/agent experiences either continued false-negative deploy states (fix ineffective) or, if the budget logic were inverted, a hung verify loop bounded by the wrapper's 1800s cap.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — the change moves retry-loop integers and log text in a root-owned deploy script and a CI workflow; no user data, secrets, or request paths are touched.
- **Brand-survival threshold:** `none`
- Scope-out override: `threshold: none, reason: ci-deploy.sh is operator-only deploy plumbing — the diff changes retry budgets and comments, never touches user data, auth, or any user-reachable surface; worst case is a ~90s-slower failure report on an already-failing deploy.`

## Observability

```yaml
liveness_signal:
  what: "terminal deploy outcome in deploy-state served by /hooks/deploy-status (the no-SSH layer); INNGEST_HEALTH / INNGEST_CRON_PLAN logger lines exist per attempt but are LOCAL-ONLY journald under webhook.service — Vector's journald sources filter by unit (inngest-server.service) and priority (0-4 / CRIT), so these user.notice lines are NOT shipped to Better Stack (verified against vector.toml sources 1-3, 2026-06-11; HTTPS attempt-level tail deferred via tracking issue)"
  cadence: "per deploy/restart invocation"
  alert_target: "restart-inngest-server.yml job failure (GitHub Actions); Sentry cron monitors (cron-monitors.tf) independently alert on genuinely dead cron plans via missed check-ins"
  configured_in: "apps/web-platform/infra/ci-deploy.sh:201; apps/web-platform/infra/hooks.json.tmpl (deploy-status hook); apps/web-platform/infra/sentry/cron-monitors.tf"

error_reporting:
  destination: "deploy-state file (reason=inngest_health_failed) read via HTTPS /hooks/deploy-status (HMAC + CF Access, creds in Doppler prd_terraform)"
  fail_loud: "verify returns 1 -> final_write_state 1 inngest_health_failed -> script exit 1 -> restart workflow ::error:: + job failure"

failure_modes:
  - mode: "registry re-sync exceeds even 120s (healthy but very slow) — the false-negative class is narrowed, not eliminated; the plan says so honestly"
    detection: "deploy-status shows exit_code=1 reason=inngest_health_failed while Sentry cron monitors stay green (the #5145 signature)"
    alert_route: "restart-inngest-server.yml failure annotation; postmerge/deploy-status-debugging.md runbook (taxonomy row added by this PR — Files to Edit #5)"
  - mode: "cron genuinely de-planned after restart (H9b)"
    detection: "deploy-status inngest_health_failed within ~150s nominal (400s hung-server tail) AND Sentry cron monitors begin missing check-ins"
    alert_route: "Sentry cron monitor alerts (infra/sentry/cron-monitors.tf)"
  - mode: "client poll window outruns server verify (regression this plan guards against)"
    detection: "ci-deploy.test.sh cross-file drift guard fails in CI (infra-validation.yml deploy-script-tests job)"
    alert_route: "PR check failure pre-merge"

logs:
  where: "ci-deploy logger lines: LOCAL journald under webhook.service only (not shipped — see liveness_signal); no-SSH operator surfaces are deploy-state JSON via /hooks/deploy-status and GitHub Actions step logs for the workflow side"
  retention: "host journald rotation; GitHub Actions 90-day log retention"

discoverability_test:
  command: "WEBHOOK_SECRET=$(doppler secrets get WEBHOOK_DEPLOY_SECRET --project soleur --config prd_terraform --plain); curl -s --max-time 10 -H \"X-Signature-256: sha256=$(printf '' | openssl dgst -sha256 -hmac \"$WEBHOOK_SECRET\" | sed 's/.*= //')\" -H \"CF-Access-Client-Id: $(doppler secrets get CF_ACCESS_CLIENT_ID --project soleur --config prd_terraform --plain)\" -H \"CF-Access-Client-Secret: $(doppler secrets get CF_ACCESS_CLIENT_SECRET --project soleur --config prd_terraform --plain)\" https://deploy.soleur.ai/hooks/deploy-status"
  expected_output: "JSON with exit_code/reason/component fields (canonical call pattern: plugins/soleur/skills/postmerge/references/deploy-status-debugging.md:5-24)"
```

## Files to Edit

1. `apps/web-platform/infra/ci-deploy.sh` — add `local cron_max_attempts=40` constant; switch the second (`/v1/functions`) loop and its log lines to it; extend the function doc comment (`:191-200`); rewrite the stale `:856-866` deploy-arm comment.
2. `apps/web-platform/infra/ci-deploy.test.sh` — two new static assertions (cron budget pin block + cross-file client/server budget drift guard).
3. `.github/workflows/restart-inngest-server.yml` — `MAX_POLLS=140` / `POLL_INTERVAL=5` variables replacing all `30`/`/30`/`150s` literals in the Verify restart completion step; `TRIGGER_TS` freshness guard; header comment update.
4. `.github/workflows/infra-validation.yml` — add `.github/workflows/restart-inngest-server.yml` to `on.pull_request.paths` so the drift guard fires on client-side edits.
5. `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` — add the `inngest_health_failed` Reason Taxonomy row.

## Files to Create

None.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (200-issue window, checked 2026-06-11; re-checked after deepen-plan expanded the list to 5 files) contains no issue body referencing any of the five files.

## Implementation Phases

### Phase 1 — RED: static assertions in ci-deploy.test.sh

1. Add the cron-budget pin assertion block exactly as specified in Proposed Solution (4 checks: exact-value pin, `seq` form pin, relative-ordering second-loop proof, `--max-time 5` probe pin). Inline `TOTAL/PASS/FAIL` style per `:2031-2040`; `[[:space:]]` dialect; comment cites #5145 and names the regression classes.
2. Add the cross-file drift guard exactly as specified in Proposed Solution: generic-by-shape numeric extraction with `|| true` on every grep, `[[ "$v" =~ ^[0-9]+$ ]]` validation BEFORE arithmetic (empty string in `$((v * 5))` evaluates to 0 silently — the inequality would pass for the wrong reason), exactly-one-assignment checks for `MAX_POLLS=`/`POLL_INTERVAL=`, inequality `MAX_POLLS*POLL_INTERVAL >= (health + cron) * (interval + 5) + 180 + 60`, FAIL message printing all five values + both sides + both file names. The integer-validation FAIL is also the RED path while the values don't exist yet.
3. Run `bash apps/web-platform/infra/ci-deploy.test.sh` — the two new assertion blocks FAIL cleanly (no abort), everything else stays green (baseline 81/81 verified 2026-06-11).

### Phase 2 — GREEN: ci-deploy.sh contract change

1. Add `local cron_max_attempts=40` after `local interval`, with the rationale comment containing the literal `--poll-interval 60` (AC4 greps it), the two-cycle derivation, #5145, and why it is a constant rather than a positional (call sites must stay arg-less).
2. Change the second loop to `seq 1 "$cron_max_attempts"` and its three log lines (`attempt $i/$cron_max_attempts`, terminal failure line) accordingly. First loop untouched.
3. Extend the function doc comment (`:191-200`) to mention the separate cron-loop budget.
4. Rewrite `:856-866`: delete "The post-restart SDK sync populates the registry immediately … ~30s retry budget covers the window"; state the poll-cycle invariant, cite #5145, and state explicitly that the deploy-time gate is "≥1 cron-triggered function registered" (a deliberate weak-form proxy — all-crons/execution coverage is owned by the Sentry cron monitors in `cron-monitors.tf`).
5. Call sites at `:366` and `:867` stay byte-identical (arg-less).

### Phase 3 — restart workflow client window + freshness guard

1. In the `Verify restart completion` `run:` block: define `MAX_POLLS=140`, `POLL_INTERVAL=5` up top; replace `seq 1 30` → `seq 1 "$MAX_POLLS"`, every `Attempt $i/30` → `Attempt $i/$MAX_POLLS` (6 occurrences as of writing — sweep all, AC5 verifies), both `sleep 5` → `sleep "$POLL_INTERVAL"`, and the terminal `within 150s` (`:107`) → `within $((MAX_POLLS * POLL_INTERVAL))s`.
2. Add the `TRIGGER_TS` freshness guard per Proposed Solution: capture in the trigger step (`$GITHUB_ENV`), require `start_ts >= TRIGGER_TS - 60` before honoring any terminal inngest state; stale state logs and keeps polling.
3. Update the header comment (`:2`) if it names the old window; add a one-line cross-reference: "window must exceed ci-deploy.sh verify worst case (incl. TimeoutStopSec hung-stop) — drift-guarded by ci-deploy.test.sh (#5145)".
4. `actionlint .github/workflows/restart-inngest-server.yml` (installed at `~/.local/bin/actionlint`, verified 2026-06-11) and `bash -n` on the extracted `run:` snippet (never `bash -n` on the .yml itself).

### Phase 3.5 — CI trigger coverage + runbook row

1. Add `.github/workflows/restart-inngest-server.yml` to `infra-validation.yml` `on.pull_request.paths` (one line — the `deploy-script-tests` job is ungated, so this completes the drift-guard enforcement topology).
2. Add the `inngest_health_failed` row to the Reason Taxonomy table in `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` per Files to Edit #5.

### Phase 4 — verify

1. `bash apps/web-platform/infra/ci-deploy.test.sh` → all pass, 0 failed (baseline 81 + new assertion blocks).
2. Run the AC grep battery below.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1: budget constant present and drives the second loop — `grep -cE '^\s*local cron_max_attempts=40\b' apps/web-platform/infra/ci-deploy.sh` returns `1` AND `grep -cE 'seq 1 "\$cron_max_attempts"' apps/web-platform/infra/ci-deploy.sh` returns `1`. (Also enforced at runtime by the Phase 1 pin assertion — the AC is the PR-review-time spot check, the test is the durable guard.)
- [x] AC2: /health loop untouched — `grep -cE '^\s*local max_attempts="\$\{1:-10\}"' apps/web-platform/infra/ci-deploy.sh` returns `1` AND `grep -cE '^\s*local interval="\$\{2:-3\}"' apps/web-platform/infra/ci-deploy.sh` returns `1`.
- [x] AC3: call sites remain arg-less — `grep -cE '^[[:space:]]*verify_inngest_health[[:space:]]*$' apps/web-platform/infra/ci-deploy.sh` returns `2` (preserves the `ci-deploy.test.sh:2007` wiring test).
- [x] AC4: stale claim gone, real driver documented — `[ "$(grep -c 'retry budget covers the window' apps/web-platform/infra/ci-deploy.sh)" = "0" ]` AND `grep -c -- '--poll-interval 60' apps/web-platform/infra/ci-deploy.sh` returns ≥ `1` (the new function rationale comment; note: `grep -c 'poll-interval 60'` returns 0 on the pre-edit file — the existing `:857` mention line-wraps before "60", so the new comment is the only expected match).
- [x] AC5: workflow literals replaced — `grep -cE 'MAX_POLLS=140' .github/workflows/restart-inngest-server.yml` returns `1` AND `[ "$(grep -cE 'seq 1 30|\$i/30|within 150s' .github/workflows/restart-inngest-server.yml)" = "0" ]`. (Use the `[ "$(...)" = "0" ]` form — `grep -c` exits 1 on zero matches, which aborts `set -e` AC batteries.)
- [x] AC6: freshness guard present — `grep -cE 'TRIGGER_TS' .github/workflows/restart-inngest-server.yml` returns ≥ `2` (capture in trigger step + comparison in verify loop).
- [x] AC7: `bash apps/web-platform/infra/ci-deploy.test.sh` exits 0 with `0 failed` and a total ≥ `83` (baseline 81 verified 2026-06-11 + the two new assertion blocks; exact count depends on per-check TOTAL increments).
- [x] AC8: `actionlint .github/workflows/restart-inngest-server.yml` exits 0 AND `actionlint .github/workflows/infra-validation.yml` exits 0; `grep -c 'restart-inngest-server.yml' .github/workflows/infra-validation.yml` returns ≥ `1` (paths-filter addition).
- [x] AC9: runbook row present — `grep -c 'inngest_health_failed' plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` returns ≥ `1`.
- [ ] AC10: PR body uses `Ref #5145` (NOT `Closes` — the prod fix lands via post-merge auto-apply; closure is gated on AC12).

### Post-merge (automated — no operator steps)

- [ ] AC11: host delivery verified as an **invariant, not a proxy** — (a) `apply-deploy-pipeline-fix.yml` run for the merge commit concludes `success` (`gh run list --workflow=apply-deploy-pipeline-fix.yml --branch main --limit 1 --json conclusion,headSha`), AND (b) the per-file hash served by the infra-config-status endpoint matches the merged file: `jq -r '.files[] | select(.file=="/usr/local/bin/ci-deploy.sh") | .sha256'` from the status payload equals `sha256sum apps/web-platform/infra/ci-deploy.sh` at the merge SHA. Run-success alone can read a stale green state (the #4804 class); the hash comparison is the delivery invariant. Automation: `gh` CLI + the canonical infra-config-status curl (same auth pattern as deploy-status).
- [ ] AC12: live end-to-end verification — the merge push itself dispatches `restart-inngest-server.yml` (its push trigger is path-scoped to itself), racing the auto-apply against the OLD host script; that run MAY legitimately fail and is not a regression signal. After AC11 passes, re-dispatch once: `gh workflow run restart-inngest-server.yml && gh run watch` → green run proves the widened budget live (restart + verify + fresh-state poll all on the new code). Then `gh issue close 5145 --comment "Fixed by <PR url>; auto-apply run <run url> verified host delivery (sha256 match); re-dispatched restart run <run url> green."`. Automation: `gh` CLI.

## Test Scenarios

Existing (must stay green, all in `ci-deploy.test.sh`):

- restart inngest with default mocks → `success` (cron-present registry mock at `:277`).
- restart inngest with `MOCK_CURL_INNGEST_HEALTH_FAIL=1` → `inngest_health_failed` (`:1978`).
- restart inngest with `MOCK_CURL_INNGEST_FUNCTIONS_NOCRON=1` → `inngest_health_failed` (#4650 AC9, `:1986`).
- deploy-inngest wiring order test (`:2005-2017`) — verify line precedes fail/success lines, call sites arg-less.

New (Phase 1):

- Static pin block: `local cron_max_attempts=40` exists, the `seq` form drives the SECOND loop (relative-ordering proof), and both probes carry `--max-time 5` (fails on shared-budget regression, silent down-tuning, loop swap, or curl-tail retune that would invalidate the drift-guard arithmetic).
- Static cross-file drift guard: restart workflow client window (`MAX_POLLS × POLL_INTERVAL` = 700s) ≥ verify tail-case (`(10+40) × (3+5)` = 400s) + `TimeoutStopSec` hung-stop (180s) + margin (60s) = 640s — fails if either side's budget drifts unilaterally; fails loudly (not aborts) on unparseable extraction.

## Dependencies & Risks

- **Risk — slower H9b detection:** terminal failure on a genuinely de-planned registry now takes ~150s nominal / 400s hung-server tail (was ~60s / 160s). Mitigated: still terminal, still recorded, and Sentry cron monitors alert on missed check-ins independently of deploy-state. (Defense-relaxation ceiling named per learning `2026-05-05-defense-relaxation-must-name-new-ceiling.md`.)
- **Risk — trace-order test drift:** inserting lines in ci-deploy.sh can shift line-number-based assertions (learnings `2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md`, `2026-05-11-pre-run-assertion-mock-stdout-trace-pollution.md`). The wiring test at `:2005-2017` uses relative ordering (verify < fail < success), not absolute numbers — safe — but run the full suite (AC7) to confirm.
- **Risk — auto-apply false success:** historically the webhook 202 masked frozen hosts for 12 days (learning `2026-06-02-deploy-pipeline-fix-false-success-202-trigger-and-forget-and-chicken-egg-freeze.md`). #4804 made the apply workflow self-verify via infra-config-status, but run-success is still freshness-unanchored (it can read a stale green state) — AC11 therefore adds the per-file sha256 comparison as the delivery invariant.
- **Risk — merge-ordering side effect (named, expected):** the merge push dispatches a REAL prod inngest restart (`restart-inngest-server.yml` push trigger is path-scoped to itself) concurrently with the auto-apply; that restart reaches the host in seconds while delivery of the widened budget takes minutes, so the run may reproduce the #5145 false negative one last time. This is expected, not a regression — the `wg-after-a-pr-merges-to-main-verify-all` gate must treat it as such; AC12's post-delivery re-dispatch is the authoritative green.
- **Risk — longer flock-held window:** the verify can now hold the FD-200 deploy lock up to ~400s (was ~160s tail-case), widening the window in which a concurrent webhook invocation loses `flock -n` and writes terminal `lock_contention` over the winner's in-progress state (`ci-deploy.sh:342-347`). Pre-existing single-slot-state race, ~2.5× wider; accepted — restart frequency is low (watchdog + rare operator dispatch) and the canonical recovery is re-dispatch after the in-flight run finishes. The `-1` (running) poll arm also doesn't discriminate component — likewise pre-existing, out of scope.
- **Dependency:** none new. No new infra, no new secrets, no schema, no vendor surface.

## Sharp Edges (for /work)

- **Never add args at the call sites.** `ci-deploy.test.sh:2007` greps `^[[:space:]]*verify_inngest_health[[:space:]]*$`; an arg-carrying call site silently breaks the #4652 AC3 wiring test. The new budget lives only as the `local cron_max_attempts=40` internal constant (deliberately NOT a positional parameter — plan-review rejected dead flexibility).
- **Budget values are runtime-untestable.** `create_mock_seq` collapses every `seq` to one iteration; only static source-greps can pin budgets. Do not try to exercise 40 attempts in tests (real `sleep` would blow the 5-min CI job).
- **Keep `|| true` after curl; never toggle `set -e` inside the function** — it leaks to caller scope and kills `VERIFY_RC=$?` capture (function header comment `:198-200` + learning `2026-05-27-bash-set-e-leaks-from-functions-use-or-true.md`).
- **`/v1/functions` is loopback-gated** — the probe is only valid from the host itself; do not move or replicate it (learning `2026-05-31-inngest-v1-loopback-gated-and-halt-on-stale-premise.md`).
- **A plan whose `## User-Brand Impact` section is empty or placeholder fails deepen-plan Phase 4.6** — section above is complete with a `threshold: none` scope-out reason.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (retry-budget integers in a deploy script, a CI workflow poll window, and shell-test assertions). No UI surface, no user data, no pricing/legal/marketing/support implications. Product/UX Gate: NONE (no file in Files to Edit matches any UI-surface glob).

## References & Research

- Issue #5145 (this fix) — `Ref` in PR body, closed post-merge per AC12.
- Deferral tracking issue #5148 — HTTPS attempt-level verify diagnostics via `cat-deploy-state.sh` `webhook_journal_tail` (created at plan time).
- PR #5131 — the v1.1.13 deploy that surfaced the false negative; merged 2026-06-11T00:46Z.
- `apps/web-platform/infra/ci-deploy.sh:191-246, 355-377, 856-878` — function, restart arm, deploy arm.
- `apps/web-platform/infra/inngest-bootstrap.sh:147-162` — `--poll-interval 60` ExecStart (asserted by `inngest.test.sh:156`).
- `.github/workflows/restart-inngest-server.yml:52-110` — client-side poll loop.
- `.github/workflows/apply-deploy-pipeline-fix.yml:62-80` — auto-apply paths filter; `:340-377` self-verification (#4804).
- `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` — canonical no-SSH deploy-status read.
- Learnings applied: `2026-05-07-deploy-poll-ceiling-must-track-realistic-deploy-window.md`, `2026-05-30-inngest-cron-desync-regression-needs-runtime-self-heal-not-ci-guard.md` (origin of the cron-plan probe; budget was sized before `--poll-interval` existed), `2026-05-27-bash-set-e-leaks-from-functions-use-or-true.md`, `2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md`, `2026-06-02-deploy-pipeline-fix-false-success-202-trigger-and-forget-and-chicken-egg-freeze.md`, `2026-05-05-defense-relaxation-must-name-new-ceiling.md`, `2026-05-31-inngest-v1-loopback-gated-and-halt-on-stale-premise.md`.
