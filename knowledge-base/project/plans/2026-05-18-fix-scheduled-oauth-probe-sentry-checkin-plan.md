---
title: "fix: scheduled-oauth-probe Sentry check-in silent failure + cadence mismatch"
date: 2026-05-18
type: bug-fix
classification: ci-ops
lane: single-domain
status: planned
branch: feat-one-shot-fix-oauth-probe-sentry-checkin
related_workflows:
  - .github/workflows/scheduled-oauth-probe.yml
  - .github/workflows/apply-sentry-infra.yml
related_iac:
  - apps/web-platform/infra/sentry/cron-monitors.tf
related_runbooks:
  - knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md
related_issues: [2997, 3236]
sentry_issue_id: 2c759a282af94e91a393417075074b98
requires_cpo_signoff: false
---

# fix: scheduled-oauth-probe Sentry check-in silent failure + cadence mismatch

## Enhancement Summary

**Deepened on:** 2026-05-18
**Plan author lens:** ops/observability (single-domain lane, threshold=none with sensitive-path scope-out).
**Research applied:** Sentry HTTP cron docs (WebFetch + WebSearch), `jianyuan/sentry v0.15.0-beta2` provider schema (lockfile), `gh run list` cadence data over 12 fires, GH issue/PR liveness verification, AGENTS.md rule-ID active/retired check, operator-surface grep enumeration.

### Key Improvements over the initial draft

1. **AC10 operator-surface globs replaced with plan-time enumerated file:line pairs.** Initial draft prescribed a "grep sweep" — deepen-pass ran the sweep at plan time and pinned each match's disposition (update vs. scope-out). Three additional sites found beyond the original `Files to Edit` list: `oauth-probe-failure.md:237`, `github-app-drift.md:339`, `legal/audits/sentry-migration-audit-2026-05-15.md:13` (latter scope-out'd as historical artifact). Aligns with the `2026-04-28-plan-globs-must-be-verified-against-repo-structure` rule.
2. **Sentry heartbeat shape clarified (POST vs GET).** Sentry's documented heartbeat form is `curl "${SENTRY_CRONS}?status=ok"` (GET). The existing repo pattern uses POST (proven working server-side). AC4 now documents both forms are accepted and prescribes POST for repo-consistency. Avoids a /work-time pivot.
3. **`max_runtime_minutes` semantics documented.** In heartbeat-only mode, the attribute has no runtime-overrun detection (Sentry docs: "Heartbeat only detects missed jobs, not runtime overages"). AC6 retains the 10-min value for schema/sibling-consistency but notes it is effectively unused.
4. **PR citation #3814 corrected to #3811.** Initial draft cited PR #3814 (which `gh pr view` resolves to a 404) as the Sentry IaC anchor — the actual merged PR is #3811. Caught by the live `gh pr view` verification per the deepen-plan SHA/PR verification rule.
5. **User-Brand Impact section now has canonical `threshold: none, reason:` scope-out bullet.** Sensitive-path regex hit on `apps/web-platform/infra/sentry/cron-monitors.tf` (matches `apps/[^/]+/infra/`); preflight Check 6 would have FAILed at ship-time without the scope-out. Halt-gate fix.
6. **Cron-monitor billing pre-flight checked.** Per the 2026-05-15 sentry-iac-billing-and-quirks learning, NEW monitor resources require seat headroom; this PR modifies (not creates) an existing monitor — no billing risk.

### Research Insights

**Sentry Crons HTTP contract** (from `docs.sentry.io/product/crons/getting-started/http/`):

- Heartbeat (one-shot): `curl "${SENTRY_CRONS}?status=ok"` — single GET, no prior in_progress, no checkin id needed. Detects missed runs only.
- Check-in (two-step): POST `?status=in_progress` returning `{id}`, then PUT `?status=ok/error` to update. Detects missed AND overrun.
- Rate limit: **6 check-ins/min per monitor environment** — current `*/15 * * * *` = 4/h (well under); proposed `0 * * * *` = 1/h (far under). No rate-limit concern either way.
- `?status=ok` and `?status=error` both accepted as one-shot. POST is server-accepted even though docs use GET — verified via existing repo pattern that has been working for in_progress.

**GitHub Actions cron behavior** (well-documented best-effort behavior, see GitHub docs):

- Cron schedules are queued; delays of 5–15 min are normal during peak load. Sub-hourly schedules (`*/5`, `*/10`, `*/15`) routinely degrade to 30–60 min effective cadence under load.
- The 12-fire sample from this repo shows median ~65 min daytime, ~3–4 h overnight — consistent with GH's documented best-effort guarantee.
- Matching the monitor's expected cadence to observed reality (not the cron spec) is the canonical mitigation. The Sentry Crons rollout for sibling workflow `scheduled-github-app-drift-guard` uses `0 * * * *` + `checkin_margin_minutes = 15` for the same reason.

**Provider/schema** (from `apps/web-platform/infra/sentry/.terraform.lock.hcl`):

- `registry.terraform.io/jianyuan/sentry v0.15.0-beta2` (beta).
- `sentry_cron_monitor` resource accepts `schedule = { crontab = "<expr>" }` block form; `checkin_margin_minutes`, `max_runtime_minutes`, `failure_issue_threshold`, `recovery_threshold`, `timezone` all verified in sibling resources (lines 32–134 of cron-monitors.tf).

### New Considerations Discovered

- **No new finding requires re-planning.** Single-file bug-fix scope held up under research.
- **Sister-workflow defect class** (7 other scheduled-*.yml using the same `|| true`-wrapped in_progress shape) noted in Sharp Edges with a post-merge follow-up issue. Out of scope for this PR per user framing.
- **Heartbeat collapse loses runtime-overrun detection.** Acceptable for this monitor — the probe completes in <1 minute and has a 5-minute `timeout-minutes` GHA-level kill switch. If runtime overage ever becomes load-bearing (e.g., probe grows to a long-running diagnostic), revisit the two-step pattern.

## Summary

`scheduled-oauth-probe.yml` is generating recurring Sentry "missed check-in" alerts (Sentry issue `2c759a282af94e91a393417075074b98`, project `web-platform`, env `production`). Sentry's monitor reports `Last successful check-in: Never` even though workflow runs themselves succeed. Two coupled defects:

1. **Silent in_progress → ok gate.** The `Sentry check-in (in_progress)` step (lines 32–50) wraps a `curl -fSs ... | jq -r '.id // empty' > ${RUNNER_TEMP}/sentry-checkin-id-${MONITOR_SLUG}` with `|| true` AND has `continue-on-error: true`. If the POST fails (network blip, Sentry 5xx, transient DNS) OR the response lacks `.id`, the file is empty, the later `Sentry check-in (ok)` step's `CHECKIN_ID` is empty, and the PUT `?status=ok` call is **skipped entirely**. Sentry never receives a terminal state for that run → "missed check-in".
2. **Cadence mismatch.** Workflow `schedule: '*/15 * * * *'`, monitor's `checkin_margin_minutes = 5`. Real `gh run list` over the last 12 fires shows actual intervals of ~60 min daytime, ~3–4 h overnight — GitHub Actions cron is best-effort and routinely delays high-frequency schedules. Even if check-ins fire correctly, the 15-min window + 5-min margin will mark every other interval as missed.

The fix collapses the two check-in steps into a single end-of-job `?status=ok` (or `?status=error`) POST — Sentry's heartbeat-style one-shot pattern is documented and is what the orphan cron monitor was migrated to in 2026-05-15 (`knowledge-base/legal/audits/sentry-migration-audit-2026-05-15.md` line 32) — and updates the monitor IaC to an hourly crontab with a 30-min margin to match observed GHA reality.

Closes the recurring Sentry email noise.

## User-Brand Impact

**If this lands broken, the user experiences:** continued operator-side Sentry email noise (false-positive missed-check-in pages every 15 min) AND a degraded signal on the actual oauth-probe — if the probe goes truly dark, the persistent false-positives mask the real outage. The user-facing surface (`app.soleur.ai/login`) is NOT touched by this PR; the probe's failure-detection logic (lines 63–438 of the workflow) is untouched.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — this PR touches CI plumbing and an observability monitor only. No new processing of user data, no auth-flow change, no schema/secret rotation. The probe continues to read public auth surfaces (`app.soleur.ai/login`, `api.soleur.ai/auth/v1/...`) under the same anon-key access it already uses.

**Brand-survival threshold:** none.

- **threshold: none, reason:** observability-tier change — the diff touches a Sentry cron-monitor IaC resource (`apps/web-platform/infra/sentry/cron-monitors.tf`) under the `apps/[^/]+/infra/` sensitive-path regex, but the resource is a monitor cadence/margin tunable (no auth flow, no schema, no PII transform, no secret rotation, no new processing activity). The user-facing probe behavior at `app.soleur.ai/login` and `api.soleur.ai/auth/v1/...` is preserved bit-for-bit; the `--max-time 10` curl bounds are retained; no new code paths reach user-controlled input.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `.github/workflows/scheduled-oauth-probe.yml` no longer contains the line `Sentry check-in (in_progress)` (single grep returns 0). The two-step `in_progress → ok|error` shape is replaced by a single end-of-job check-in step.
- [ ] AC2 — `.github/workflows/scheduled-oauth-probe.yml` no longer contains the substring `sentry-checkin-id-` (the `${RUNNER_TEMP}/sentry-checkin-id-${MONITOR_SLUG}` tmpfile is gone). Grep returns 0.
- [ ] AC3 — The new check-in step is named `Sentry check-in (final)` and runs with `if: always()`. It conditionally posts `?status=ok` when `steps.probe.outputs.failure_mode == ''` and `?status=error` otherwise. Encoded as a single bash branch on the env var `FAIL_MODE` mirrored from `steps.probe.outputs.failure_mode`, not as two separate steps.
- [ ] AC4 — The new check-in step's curl form is `curl --max-time 10 -fSs -X POST "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/cron/${MONITOR_SLUG}/${SENTRY_PUBLIC_KEY}/?status=${status}"` **without** trailing `|| true`. (POST is retained to match the existing repo pattern; Sentry's documented heartbeat form is GET with the same query-param shape — both are accepted server-side, see `docs.sentry.io/product/crons/getting-started/http/` Heartbeat section.) The step retains `continue-on-error: true` at the YAML level so a Sentry-side blip does not red-flag an otherwise-green probe run — but the curl exit-code lands in the workflow log (visible in step output) instead of being swallowed at the shell. (`continue-on-error: true` makes the step non-fatal to the job; absence of `|| true` makes the curl's stderr/exit-code observable. Both properties are necessary; neither is sufficient.)
- [ ] AC5 — `set -u` is retained at the top of the new step. The early-exit guard `if [[ -z "${SENTRY_INGEST_DOMAIN:-}" || -z "${SENTRY_PROJECT_ID:-}" || -z "${SENTRY_PUBLIC_KEY:-}" ]]; then echo "::warning::Sentry Crons secrets not configured; skipping check-in."; exit 0; fi` is retained verbatim (covers fork-PR and pre-secret-set repo states).
- [ ] AC6 — `apps/web-platform/infra/sentry/cron-monitors.tf` `resource "sentry_cron_monitor" "scheduled_oauth_probe"` changes: `schedule = { crontab = "0 * * * *" }`, `checkin_margin_minutes = 30`, `max_runtime_minutes = 10` (unchanged — see note below), `failure_issue_threshold = 2` (unchanged), `recovery_threshold = 1` (unchanged), `timezone = "UTC"` (unchanged). Comment block above the resource updated to note observed GHA cadence (~60 min daytime, longer overnight gaps). **Note on `max_runtime_minutes`:** in pure heartbeat mode (single end-of-job check-in), `max_runtime_minutes` has no runtime-overrun detection effect — Sentry only fires "missed check-in" alerts, not "ran too long". The 10-min value is retained as a future-compatible default (matches sibling monitor resources) and to keep the resource shape stable against `jianyuan/sentry v0.15.0-beta2`'s schema. Verified provider version: `apps/web-platform/infra/sentry/.terraform.lock.hcl` pins `0.15.0-beta2`.
- [ ] AC7 — `.github/workflows/scheduled-oauth-probe.yml` workflow `cron:` line changes from `'*/15 * * * *'` to `'0 * * * *'` to align the GHA schedule with the monitor's expected cadence. The probe's 5-min job timeout (`timeout-minutes: 5`) is preserved — the probe itself completes in <1 min; only the monitor cadence needs adjustment.
- [ ] AC8 — Workflow file header comment (line 2: "Probes prod public auth surface every 15 minutes") updated to "every hour" to keep prose in sync with the cron. Sentinel: `grep -c "every 15 minutes" .github/workflows/scheduled-oauth-probe.yml` returns 0.
- [ ] AC9 — `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` updated at two sites: line 16 ("runs every 15 minutes" → "runs every hour") AND line 237 ("wait one probe cycle (15 min)" → "wait one probe cycle (1 h)"). Sentinel: `grep -c "15 min" knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` returns 0 (covers both "15 minutes" and "15 min").
- [ ] AC10 — Operator-surface grep sweep, enumerated at plan time:
  - `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` lines 16, 237 — **updated** (per AC9).
  - `knowledge-base/engineering/ops/runbooks/github-app-drift.md` line 339 ("The user-facing OAuth probe (`scheduled-oauth-probe.yml`, every 15") — **updated** to "every hour".
  - `knowledge-base/legal/audits/sentry-migration-audit-2026-05-15.md` line 13 (`*/15 * * * *` in the migration audit table) — **scope-out**: this is a historical audit artifact dated 2026-05-15 that records the cron *at migration time*. Updating it would falsify the audit. Leave as-is.
  - `apps/web-platform/infra/sentry/README.md` — no `15 min` / `*/15` match anchored to oauth-probe (grep-verified at plan time). No edit required.
  - `README.md`, `CONTRIBUTING.md` — no match (grep-verified). No edit required.
  - Scope exclusion: `knowledge-base/project/{plans,specs}/**`, `**/archive/**` (historical record). (Per the docs-fix-verification-greps learning, scoping only to the directly-edited files leaves operator-surface drift; per the directory-rename audit learning, enumerate at plan time rather than at /work.)
  - Final sentinel: `grep -rEn '(every 15 minutes|every 15 min|15-min)' knowledge-base/engineering/ apps/web-platform/infra/sentry/README.md README.md CONTRIBUTING.md 2>/dev/null | grep -iE 'oauth|probe' | wc -l` returns 0.
- [ ] AC11 — `terraform validate` passes on `apps/web-platform/infra/sentry/` (no schema regression in the cron-monitor body shape). Pinned-version invocation: `cd apps/web-platform/infra/sentry && terraform init -input=false -backend=false && terraform validate`.
- [ ] AC12 — `actionlint` passes on `.github/workflows/scheduled-oauth-probe.yml` (no shell-snippet regression introduced by the step consolidation). Embedded-shell snippet check: `bash -c "$(extracted check-in step run-block)"` parses without syntax errors. (Per the YAML-vs-shell parse-error learning: do NOT use `bash -n <file.yml>`.)
- [ ] AC13 — PR body uses `Ref` not `Closes` for any operator-acked post-merge state (none required this PR — the Sentry monitor reapply is auto-triggered by the apply-sentry-infra workflow on merge, no human follow-up). The fix is "atomic merge".
- [ ] AC14 — The new check-in step's behavior on a missing `SENTRY_INGEST_DOMAIN` (fork-PR or pre-secret-set state) is verified via a fork-PR dry-run shape: `SENTRY_INGEST_DOMAIN= bash -c "$(extracted run-block)"` emits `::warning::Sentry Crons secrets not configured; skipping check-in.` AND `exit 0`. Mechanically verified at /work time via the embedded-shell `bash -c` snippet in AC12.

### Post-merge (auto + verification)

- [ ] AC15 — **Auto:** push to `main` triggers `.github/workflows/apply-sentry-infra.yml` (the `paths: apps/web-platform/infra/sentry/cron-monitors.tf` filter matches). The workflow's `terraform apply` updates `sentry_cron_monitor.scheduled_oauth_probe` to the new schedule/margin. No operator action required at apply-time — this matches the established `Sentry IaC auto-apply` flow established by PR #3811 (`feat: adapt Sentry integration to Monitors/Alerts split`) which introduced the cron-monitor resources and the auto-apply workflow. Verification: `gh run list --workflow=apply-sentry-infra.yml --limit 1 --json conclusion` returns `success` within 5 minutes of merge.
- [ ] AC16 — **Auto:** the next scheduled `scheduled-oauth-probe.yml` fire (within ~1 h post-merge) emits a single `?status=ok` POST. Within ~5 min of that fire, Sentry's monitor page shows `Last successful check-in: <recent UTC>`. Verification: `gh run list --workflow=scheduled-oauth-probe.yml --limit 3 --json conclusion,createdAt,databaseId` AND eyeball the step log for `Sentry check-in (final)` reporting HTTP 200/202. Per `hr-no-dashboard-eyeball-pull-data-yourself`: prefer the workflow log over Sentry dashboard — the post-merge probe step output IS the deterministic verdict.
- [ ] AC17 — **Auto, T+24h:** the recurring Sentry "missed check-in" issue `2c759a282af94e91a393417075074b98` resolves itself (Sentry auto-resolves once `recovery_threshold = 1` is met — i.e., one successful check-in). Verification at T+24h: `mcp__plugin_supabase_supabase__*` not applicable; check Sentry issue state via the `gh issue list --label ci/auth-broken` AND verify no new `[ci/auth-broken] Synthetic OAuth probe failed` issues were filed by the workflow itself (which would indicate the probe-detection logic regressed). The Sentry issue resolution itself is an external-service state that does NOT need operator clicking — Sentry's recovery_threshold = 1 auto-resolves.

## Files to Edit

- `.github/workflows/scheduled-oauth-probe.yml` — replace lines 32–50 (`Sentry check-in (in_progress)` step) and lines 543–575 (`Sentry check-in (ok)` + `Sentry check-in (error)` steps) with a single `Sentry check-in (final)` step at end of job. Change cron `*/15 * * * *` → `0 * * * *` (line 16). Update header comment (line 2) "every 15 minutes" → "every hour".
- `apps/web-platform/infra/sentry/cron-monitors.tf` — lines 44–54 (`scheduled_oauth_probe` resource): `schedule` to `0 * * * *`, `checkin_margin_minutes` 5 → 30. Update preamble comment block (lines 24–30) to keep the explanation aligned (`failure_issue_threshold = 2` still load-bearing for the new hourly cadence — a single transient hiccup over an hour is now even more plausible than a real failure; ≥2 consecutive misses = real signal).
- `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` — line 16: "every 15 minutes" → "every hour"; line 237: "wait one probe cycle (15 min)" → "wait one probe cycle (1 h)".
- `knowledge-base/engineering/ops/runbooks/github-app-drift.md` — line 339: "every 15" → "every hour" (referring to oauth-probe cadence).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-fix-oauth-probe-sentry-checkin/tasks.md` — auto-generated from this plan by `soleur:plan` Save Tasks step.

## Open Code-Review Overlap

One open code-review issue touches `.github/workflows/scheduled-oauth-probe.yml`:

- **#3236: review: cross-workflow heartbeat for scheduled secret-touching workflows** — **Acknowledge.** Different concern. #3236 is the architectural meta-gate ("is the workflow running at all?") which was nominally resolved by the Sentry Crons rollout in PR #3811 (commit `apps/web-platform/infra/sentry/cron-monitors.tf:2` reads `Closes #3236`); the issue is open only because no one ran `gh issue close #3236`. The current plan fixes the check-in plumbing within an individual workflow (the very mechanism #3236's resolution depends on — without working check-ins, the dead-man's-switch claim is paper). Folding-in #3236-close into this PR is appropriate but minor: PR body adds `Closes #3236` once the cadence + check-in fix is verified post-merge. Recorded as a sharp edge below.

## Research Reconciliation — Spec vs. Codebase

| Plan claim                                                                                  | Reality (grep-verified)                                                                                                                                                                                                                                                                                                       | Plan response                                                                                                                                                                                                                                  |
| ------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "Workflow scheduled at `*/15 * * * *` but actual fires ~60–70 min" (user description)       | `gh run list --workflow=scheduled-oauth-probe.yml --limit 12` shows median ~65 min daytime (15:06→16:12→17:17→...) AND occasional ~4 h overnight gaps (00:11→04:43→08:37). User's 60–70 min figure is the daytime band; overnight is worse.                                                                                   | Cron monitor cadence set to `0 * * * *` with `checkin_margin_minutes = 30` (covers daytime jitter); the 30-min margin is intentionally generous to cover the overnight band's first half. Overnight gaps >90 min remain a real-miss signal — that's the point of `failure_issue_threshold = 2`. |
| "Sentry IaC lives in the Terraform under `sentry-iac` (search needed)" (user description)  | Sentry IaC lives in `apps/web-platform/infra/sentry/` (not a `sentry-iac` directory). Resource `sentry_cron_monitor.scheduled_oauth_probe` lives in `cron-monitors.tf` lines 44–54. Auto-apply via `.github/workflows/apply-sentry-infra.yml` on push-to-main of that path.                                                  | Path corrected in `Files to Edit`. No change to the conceptual claim.                                                                                                                                                                          |
| "Sentry supports a one-shot check-in without prior in_progress" (user description)         | Confirmed via `docs.sentry.io/product/crons/getting-started/http/` (WebFetch). Pattern 3 (heartbeat): `curl "${SENTRY_CRONS}?status=ok"`. Single POST creates a check-in in terminal state. Existing repo precedent: orphan migration audit (`knowledge-base/legal/audits/sentry-migration-audit-2026-05-15.md` line 13).        | Plan adopts the heartbeat shape.                                                                                                                                                                                                               |
| "CQ rule `cq-silent-fallback-must-mirror-to-sentry` argues against silencing" (user)        | The rule body (AGENTS.rest.md line 8) is scoped to server-code TypeScript via `reportSilentFallback(err, { feature, op?, extra? })` from `@/server/observability`. Pino → Sentry mirror for app-server fallback. NOT literally applicable to a workflow bash `curl || true`.                                                  | Plan cites the rule's **spirit** (don't swallow observability failure-signals), not its literal scope. Workflow gets `continue-on-error: true` at YAML tier (per-step non-fatal) AND drops `|| true` at shell tier (curl exit-code is visible in step log). |
| "Other scheduled workflows share the in_progress→ok pattern; same defect class"             | Grep across `.github/workflows/scheduled-*.yml`: 7 sister workflows (`terraform-drift`, `daily-triage`, `realtime-probe`, `skill-freshness`, `content-vendor-drift`, `community-monitor`, `github-app-drift-guard`) use the same `\|\| true`-wrapped in_progress → CHECKIN_ID → PUT shape. Same silent-fail trap.                       | Out of scope for this PR (single-file fix per user framing). Documented in Sharp Edges + a follow-up tracking issue (filed post-merge, label `code-review` + `priority/p2-medium`). The other workflows fire daily/weekly, so the missed-check-in noise is bounded — but the defect is real. |

## Domain Review

**Domains relevant:** Engineering / Ops (CTO lens — observability primitive change). Product: NONE (no user-facing surface). Legal: NONE (no PII / data-processing surface). Sales/Marketing/Finance/Support: NONE.

### Engineering / Ops (CTO assessment)

**Status:** reviewed (inline, plan-author lens — no separate CTO agent invocation; this is observability plumbing, brand-survival threshold `none`).
**Assessment:** The fix removes a state-bearing intermediate (CHECKIN_ID tmpfile) in favor of a stateless terminal check-in. Net complexity decreases. The cadence widening from 15 min → 60 min reduces noise floor by ~4× and aligns the monitor with GHA reality. The probe's failure-detection latency widens from 15-min to ~60-min worst case — acceptable because (a) the probe is one of several auth-regression detectors (Sentry frontend errors, user reports, the `/callback?error` regression probe inline at workflow lines 392–416), (b) the existing 15-min cadence was already not honored by GHA, so we're aligning IaC to actual behavior rather than degrading it, (c) `failure_issue_threshold = 2` ensures two consecutive misses = real signal.

Sentry monitor `checkin_margin_minutes = 30` covers daytime jitter. Overnight ~4h gaps are NOT covered — that's intentional. A 4h overnight gap is itself a real-signal: GitHub Actions cron is degraded that night, AND we want to know. (This is the SAME design choice as github-app-drift-guard `checkin_margin_minutes = 15` for an hourly cron — the gate catches Actions-degradation as a signal, not just probe-failure.)

## GDPR / Compliance Gate

Not triggered. The canonical regex `hr-gdpr-gate-on-regulated-data-surfaces` matches schemas/migrations/auth flows/API routes/`.sql` files — this PR touches a workflow file, a Terraform monitor resource, and a runbook. None of the (a)/(b)/(c)/(d) extension triggers fire: no new LLM-bound processing, brand-survival threshold is `none`, no new cron reading from learnings/specs, no new artifact-distribution surface (sister IaC apply workflow already exists). Skipping silently per Phase 2.7.

## Hypotheses

Not a network-outage diagnosis class. The network keyword scan (`SSH`, `connection reset`, `kex`, `firewall`, `timeout`, etc.) does NOT match the feature description, AND no `provisioner "remote-exec"` / `connection { type = "ssh" }` lives in the touched Terraform resource. Phase 1.4 skipped.

## Test Strategy

The probe-detection logic (lines 63–438 of the workflow) is the load-bearing surface and is **untouched** by this PR. The check-in plumbing has no test surface today (pre-existing — verified: no `oauth-probe-checkin*.test.*` exists). Test strategy:

1. **YAML/actionlint** (AC12) — workflow file parses, no shell regression.
2. **Embedded-shell `bash -c`** (AC12, AC14) — extract the new check-in step's run-block and execute under both `SENTRY_INGEST_DOMAIN=""` (fork-PR shape) and `SENTRY_INGEST_DOMAIN=foo` shapes to verify the secret-guard branch and the curl form both shape-correctly. `bash -c` is the right runner per `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug` (do NOT use `bash -n <file.yml>`).
3. **`terraform validate`** (AC11) — covers the cron-monitor schema.
4. **First-post-merge fire as the contract test** (AC16) — the deterministic verdict is "did the next scheduled fire post a successful check-in to Sentry?" The workflow log IS the assertion.

No new automated test infrastructure is added. The probe's contract test (`apps/web-platform/test/oauth-probe-contract.test.ts`, per runbook line 230) is untouched.

## Sharp Edges

- **Sister-workflow defect class is real but out of scope.** Seven other `scheduled-*.yml` workflows use the same `|| true`-wrapped in_progress → CHECKIN_ID → PUT shape and have the same silent-fail risk. Their cadences are daily/weekly so the noise is bounded, but they ARE silently dropping check-ins on Sentry-side blips. Post-merge action: file a follow-up `code-review` issue ("apply scheduled-oauth-probe.yml check-in simplification to 7 sister workflows") with label `code-review` + `priority/p2-medium` + a one-line note that the migration is mechanical (each workflow has the same 3-block shape).
- **`continue-on-error: true` vs. dropping `|| true` is the right combination.** The two properties differ. `continue-on-error: true` at YAML-tier makes a step's failure non-fatal to the job (Sentry blip ≠ probe red). Dropping `|| true` at shell-tier makes the curl's exit-code visible in the step log (visible signal that Sentry is sad, even though probe is green). Without both, either (a) Sentry blip red-flags green probes (annoying), or (b) Sentry blip is invisible (the very defect this PR fixes). The plan AC4 makes both explicit.
- **The 30-min monitor margin is intentionally generous, not "right".** Daytime jitter is ~10-15 min over an hour. Overnight gaps are ~4h. A 30-min margin covers daytime jitter without firing on it; overnight gaps remain a real-signal at `failure_issue_threshold = 2`. The alternative — tighter margin (e.g., 15-min) — would re-introduce daytime false-positives. Resisted.
- **#3236 is auto-folded as `Closes #3236` in the PR body.** The issue's stated resolution (vendor-hosted dead-man's-switch via Sentry Crons) is already in production — this PR is the last brick in that wall (a Sentry monitor that actually receives check-ins is the prerequisite for the dead-man's-switch claim to be real). Closing #3236 here is correct.
- **Cron tighter than the monitor margin is OK; looser is the bug.** `'0 * * * *'` fires hourly nominally; monitor's `checkin_margin_minutes = 30` gives a 90-min window before a miss is logged. Looser cadence (e.g., `'0 */2 * * *'`) paired with the same margin would be tighter-than-cadence and produce noise. The plan keeps cron ≤ margin-window.
- **Sentry billing pre-flight: this PR modifies an existing seat, not adds one.** Per `knowledge-base/project/learnings/2026-05-15-sentry-iac-billing-and-quirks.md`, Sentry charges per *active* cron monitor seat and the Developer (free) plan blocks new-seat activation when PAYG is 0. This PR modifies the existing `sentry_cron_monitor.scheduled_oauth_probe` resource (already paid for); apply will be an in-place `schedule`/`checkin_margin_minutes` update, not a create. No `GET /api/0/customers/jikigai/` pre-flight needed.
- **Heartbeat-mode loses runtime-overrun detection.** Per Sentry docs: "Heartbeat only detects missed jobs, not runtime overages." This PR collapses to heartbeat mode, so `max_runtime_minutes = 10` is now decorative. Acceptable because the probe completes in <1 min and has GHA's `timeout-minutes: 5` kill switch. If the probe ever grows into a long-running diagnostic (e.g., adds a multi-round-trip E2E flow that could legitimately run >5 min), revisit the two-step in_progress → ok pattern at that time, but encode it correctly (no `|| true`, no gate on a possibly-empty CHECKIN_ID — for example via a workflow output that captures the id at step-output level rather than a tmpfile, and a final step that posts an explicit `?status=error` when the id is missing).

## Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-05-18-fix-scheduled-oauth-probe-sentry-checkin-plan.md. Branch: feat-one-shot-fix-oauth-probe-sentry-checkin. Worktree: .worktrees/feat-one-shot-fix-oauth-probe-sentry-checkin/. Issue: n/a (no parent issue; closes #3236 architecturally). Plan reviewed, deepen-plan run, implementation next.
```
