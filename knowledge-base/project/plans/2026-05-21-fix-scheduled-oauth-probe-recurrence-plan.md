---
title: "fix: scheduled-oauth-probe recurring Sentry missed check-in — durable structural fix via Inngest cron migration"
date: 2026-05-21
type: bug-fix
classification: ci-ops
lane: cross-domain
status: superseded
superseded_by_pr: 4207
superseded_summary: |
  Scope-reduced at /work-time per operator decision. The durable Inngest
  cron migration described below was deferred to tracking issue #4211 in
  favor of an immediate-relief margin bump: PR #4207 bumps
  `checkin_margin_minutes` 30 → 360 on `scheduled_oauth_probe` and
  180 → 360 on `scheduled_github_app_drift_guard`. Diagnosis below
  (GHA hourly cron drift to ~150-min median / 293-min max gaps) remains
  the authoritative root-cause analysis for the follow-up migration.
followup_issue: 4211
branch: feat-one-shot-fix-scheduled-oauth-probe-recurrence
related_workflows:
  - .github/workflows/scheduled-oauth-probe.yml
  - .github/workflows/scheduled-github-app-drift-guard.yml
related_iac:
  - apps/web-platform/infra/sentry/cron-monitors.tf
related_runbooks:
  - knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md
related_issues: [2997, 3236]
sentry_issue_id: a94c4ec23f654101a7fc4491b16a560c
prior_plan: knowledge-base/project/plans/2026-05-18-fix-scheduled-oauth-probe-sentry-checkin-plan.md
prior_learning: knowledge-base/project/learnings/2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md
prior_prs: [3964, 3971]
requires_cpo_signoff: false
---

# fix: scheduled-oauth-probe recurring Sentry missed check-in — durable structural fix via Inngest cron migration

## Enhancement Summary

**Deepened on:** 2026-05-21
**Plan author lens:** ops/observability (cross-domain lane — substrate migration touches Inngest runtime + Sentry monitor IaC + operator runbooks + workflow deletion).
**Gates passed:** Phase 4.6 (User-Brand Impact: present, threshold=none with valid scope-out for sensitive-path diff), Phase 4.7 (Observability: present, 5-field schema, no SSH in discoverability_test, no placeholder values), Phase 4.8 (no PAT-shape variables).
**Research applied:** post-merge `gh run list` cadence analysis (49 fires, 4-day window) confirming substrate-cadence regression; live grep of Inngest sibling functions (`cron-daily-triage.ts`, `cron-follow-through-monitor.ts`) for the canonical heartbeat shape; live `gh pr view` / `gh issue view` verification of every cited PR/issue number (#3964, #3971, #3985, #4062, #3940, #3203, #3236); live `gh label list` for every prescribed label.

### Key Improvements over the initial draft

1. **Test path corrected to `apps/web-platform/test/server/inngest/cron-oauth-probe.test.ts`.** Initial draft said `test/inngest/`. Sibling cron tests live at `test/server/inngest/cron-{daily-triage,follow-through-monitor}.test.ts` — verified at deepen time. AC19 updated.
2. **AC5 Resend integration de-fabricated.** Initial draft cited `apps/web-platform/server/email/send-ops-notification.ts` as the helper. Verified at deepen time: no such file exists; `notify-ops-email` lives only as the GHA composite action at `.github/actions/notify-ops-email/action.yml`. AC5 rewritten with the verbatim Resend payload from the composite action body (lines 33-44) and notes "extract to a helper at /work-time only if ≥2 callers warrant it." Paraphrase-without-verification fix at deepen time.
3. **AC8 registry path concretized from live read.** `apps/web-platform/app/api/inngest/route.ts` confirmed at deepen time as the canonical Inngest function registry (lines 21-22 + 37). Original `(or equivalent — Phase 0.1 verifies)` softening removed; the path is now verified.
4. **`reportSilentFallback` import path confirmed.** Lives at `apps/web-platform/server/observability.ts:138` per live grep. AC7 references it correctly; no AC drift.
5. **Closes #3236 dropped from PR body plan.** `gh issue view 3236 --json state` returns `CLOSED` (already closed by PR #3811 per `apps/web-platform/infra/sentry/cron-monitors.tf:2` per the May 18 plan's own Open Code-Review Overlap section). The May 18 plan proposed re-closing as a `Closes #3236`; deepen-pass corrects: only `Closes #3203` remains. AC21 + Resume Prompt updated.
6. **AC20 cron-no-byok-lease-sweep glob verified.** Test at `apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts:39` reads `globSync("server/inngest/functions/cron-*.ts", ...)`. New `cron-oauth-probe.ts` auto-extends; `expect.soft` reports per-shape failures. AC20 path corrected and re-run command added (`./node_modules/.bin/vitest run`, NOT `bun test`, per the May 20 `bun test` learning).
7. **AC22 verification path strengthened from `inngest send` event over `curl /api/v0/functions`.** Initial draft's `curl https://inngest.soleur.ai/api/v0/functions` introspection endpoint assumed unauthenticated access — likely CF-Access-gated. Replaced with `inngest send cron/oauth-probe.manual-trigger` using the existing `INNGEST_EVENT_KEY` Doppler secret (HMAC-signed, designed for CI use). Aligns with `hr-no-dashboard-eyeball-pull-data-yourself` and `hr-observability-as-plan-quality-gate` (no SSH in discoverability_test).
8. **PR #3948 citation reconciled.** Plan body references "PR #3948" as TR9 PR-1; `gh pr view 3948` returned nothing. The real PR is **#3985** (`feat(runtime): migrate scheduled-daily-triage to Inngest cron (TR9 PR-1)`, MERGED 2026-05-18T15:00:40Z). #3948 is the *issue* (TR9 umbrella tracking the migration). Same disambiguation applies to #4062 (the issue) vs #4063 — corrected: #4062 is the merged PR (`feat(runtime): TR9 PR-2 — migrate scheduled-follow-through to Inngest cron`); there is no #4063. Plan body Section "Summary" + "Hypotheses H4" + "Research Reconciliation" rows all use #3985 + #4062 going forward.
9. **`scheduled-oauth-probe.yml` cron-substrate degradation evidence.** Original plan claimed "median 150-min gaps post-#3964"; deepen-pass re-ran `gh run list --workflow=scheduled-oauth-probe.yml --limit 50` and computed the full distribution at plan time:
    - **Pre-#3964 (16-17 May, 24 fires):** median 65 min, max 255 min (one overnight), 0/24 daytime samples >2 h.
    - **Post-#3964 (18-21 May, 25 fires):** median 150 min, max 293 min, 18/23 daytime samples >2 h.
    - Sister `scheduled-github-app-drift-guard` (same `0 * * * *` cron): max 307 min in same window.
   The post-#3964 distribution is **strictly worse than pre**, which surprised the May 18 plan author (whose mental model expected ~60-min daytime). The root cause is a substrate change in GitHub-hosted runner pool capacity over the May 18-21 window, not a code change in #3964; #3964's fix to the silent-fail half is correct and necessary.
10. **Sister-workflow follow-up issue (AC25) re-classified as `code-review` per same-top-level-dir criterion.** May 18 plan's session-error explicitly notes that `cross-cutting-refactor` does NOT apply when files live in the same top-level dir (`.github/workflows/`). Sister workflow migration to Inngest cron (different code paths, different runbook) is a plain tracking issue — confirmed at deepen time that all three prescribed labels (`code-review`, `priority/p2-medium`, `domain/engineering`) exist via `gh label list --limit 200`.

### Research Insights

**GHA cron substrate ceiling, verified at plan time:**

The fundamental constraint is that GitHub-hosted runner cron is **best-effort with no SLA**. From `docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#schedule`: "The shortest interval you can run scheduled workflows is once every 5 minutes. Scheduled workflows may be delayed during periods of high loads of GitHub Actions workflow runs. High load times include the start of every hour. To decrease the chance of delay, schedule your workflow to run at a different time of the hour." Combined with the observed `gh run list` data above, any sub-daily-cadence monitor on GHA cron will produce false-positive missed-check-ins if its margin is tighter than the runner-pool variance — which currently sits at ~5h max. The structural fix (Inngest substrate) is the only durable answer; further margin-bumping degenerates the monitor to "useless if the probe goes truly dark for under 5 hours."

**Inngest cron firing precedent (cron-daily-triage.ts, cron-follow-through-monitor.ts):**

- Concurrency-key pattern: `[{ scope: "fn", limit: 1 }, { scope: "account", key: '"cron-platform"', limit: 1 }]`. The literal-string-in-string `'"cron-platform"'` is load-bearing per the F7 Architecture invariant (prevents cron-* fan-out OOM). The new `cron-oauth-probe` MUST mirror this verbatim.
- `retries: 1` is the established default for cron-* fns. Probe is idempotent (GET-only HTTP checks), so retry-on-failure is safe.
- Manual-trigger event `cron/<fn-id>.manual-trigger` is the convention; operators trigger via `inngest send cron/oauth-probe.manual-trigger`.
- Sentry heartbeat slug `scheduled-oauth-probe` is identical to the existing monitor's `name` field in `cron-monitors.tf:65` — historical check-in continuity preserved (Sentry monitor IDs don't change when slug stays identical, so the existing `failure_issue_threshold = 2 → 1` change is the only Sentry-side state mutation needed).

**Comparable substrate-failure mode coverage (from #4116):**

The Inngest substrate has its own observability tier: `inngest-heartbeat.service` (systemd timer, 60s period, posts to Better Stack). Per the #4116 learning, this heartbeat was silently broken for 16h before #4116 surfaced; the *current* state (as of merge of b07d09fc on 2026-05-20) is `User=deploy` with explicit reconciliation on no-op redeploys (PR #4205). The cron-oauth-probe function inherits this observability tier; it does NOT add a new substrate-down detection mechanism beyond what `cron-daily-triage` and `cron-follow-through-monitor` already provide. If the Hetzner VM goes down, three Sentry monitors (daily-triage, follow-through, oauth-probe) AND Better Stack will all fire simultaneously — the substrate-down inference is cross-monitor correlation, same as today.

**`oauth-probe-contract.test.ts` migration impact analysis:**

Quick read of `apps/web-platform/test/oauth-probe-contract.test.ts` is required at /work Phase 0.1 to determine whether the test imports from the workflow file directly. If it does (e.g., via `readFileSync('.github/workflows/scheduled-oauth-probe.yml')`), AC9 (workflow deletion) breaks the test. **Mitigation:** refactor the load-bearing sentinel strings (`redirect_uri is not associated`, `Application suspended`, the authenticity_token regex) into a shared module at `apps/web-platform/server/inngest/functions/oauth-probe-sentinels.ts` that BOTH the test and the new function consume. This is a one-time extraction and IS in-scope for this PR (not deferred). Sentinel: post-implementation, the test file's imports include the new sentinels module AND not the deleted workflow file.

### New Considerations Discovered

- **The May 18 plan's PR/issue citation drift (PR #3948 vs issue #3948, PR #4063 vs PR #4062) is a recurring pattern** in plans that paraphrase TR9 sequencing from memory. Deepen-pass propagates corrections to `tasks.md` per the deepen-plan SKILL's "propagate the correction" gate.
- **The Resend POST going inline (vs through a shared helper) is a deliberate de-scoping**. Extracting the helper would add a second consumer (the new cron-oauth-probe's notification path) on top of zero — the helper-extraction-when-only-one-caller pattern is over-abstraction. /work-time should resist creating `send-ops-notification.ts` unless a second caller materializes in scope.
- **No CPO sign-off required.** Brand-survival threshold is `none` per the scope-out (observability-tier change; no auth flow, no PII, no schema, no secret rotation). `requires_cpo_signoff: false` in frontmatter.
- **GDPR gate non-triggered (verified at deepen-pass)**. Same Phase 2.7 analysis as the original plan body — neither the canonical regex nor extensions (a)-(d) match. No `/soleur:gdpr-gate` invocation.
- **Terraform-architect routing not triggered.** No new infrastructure is provisioned; only an existing `sentry_cron_monitor` resource is mutated and a new in-process Inngest function is added (Inngest substrate already provisioned per PR #3940). The Phase 2.8 IaC routing gate skips silently.

## Summary

The Sentry monitor `scheduled-oauth-probe` is **still** generating recurring "missed check-in" regressed-issue alerts (Sentry issue `a94c4ec23f654101a7fc4491b16a560c`, web-platform/production, latest fire 2026-05-21 08:30 CEST) despite the 2026-05-18 fix (PR #3964 + #3971) which collapsed the two-step in_progress → ok/error pattern to a single end-of-job heartbeat.

The May 18 plan correctly identified and fixed defect #1 (silent in_progress → ok gate via the `|| true`-wrapped jq-parsed CHECKIN_ID tmpfile), but its remediation for defect #2 (cadence mismatch) was sized to a **wrong model of GitHub Actions cron behavior**. The plan estimated "~60 min daytime, ~3-4 h overnight" and set `checkin_margin_minutes = 30`. The actual post-merge fire history is **much worse**:

| Window | Median gap | Max gap | Daytime samples >2 h |
| --- | --- | --- | --- |
| Pre-#3964 (16-17 May) | ~65 min | ~4 h overnight | 0 / 24 |
| Post-#3964 (18-21 May) | **~150 min** | **~5 h** (293 min) | **18 / 23** |

The structural issue isn't the workflow's check-in code (now correct). It's the **substrate**: GitHub-hosted Actions cron is best-effort and routinely degrades to 2-5h intervals under runner-pool load. **Any** hourly GHA-scheduled monitor with a margin under ~5h will produce false-positive missed-check-ins regardless of code correctness. The sister hourly monitor `scheduled-github-app-drift-guard` (180-min margin) exhibits the same gap distribution (median ~150 min, max 307 min post-#3964 window) and has been quietly absorbing missed check-ins that didn't yet cross the `failure_issue_threshold = 2` rail.

The durable fix is to migrate `scheduled-oauth-probe` off GHA cron and onto the **Inngest substrate** that already exists in this repo (`apps/web-platform/server/inngest/`). `scheduled-daily-triage` (PR #3985, TR9 PR-1, MERGED 2026-05-18) and `scheduled-follow-through` (PR #4062, TR9 PR-2, MERGED 2026-05-19) have **already** done this migration; both their Sentry monitors run with `checkin_margin_minutes = 30` because Inngest fires deterministically. Re-using the established pattern closes the symptom at the substrate-cadence level — heartbeat-pattern fixes in May 18 cannot reach the substrate.

Closes the recurring Sentry email noise structurally rather than via another margin-bump patch.

## User-Brand Impact

**If this lands broken, the user experiences:** continued operator-side Sentry email noise (false-positive missed-check-in pages roughly every 1-2 hours) AND degraded signal on the underlying oauth-probe — if real auth flows actually break, the persistent false-positives mask the real outage in the operator's inbox / Sentry dashboard. The user-facing surface (`app.soleur.ai/login`, `api.soleur.ai/auth/v1/...`) is NOT touched by this PR; the probe's failure-detection logic and curl-based reachability checks (lines 63-438 of the workflow) are preserved bit-for-bit in the Inngest function.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — this PR moves a synthetic-probe substrate from GHA cron to Inngest cron. No new processing of user data, no auth-flow change, no schema/secret rotation, no new external dependencies. The probe continues to read the same public auth surfaces under the same anon-key access scope it already uses; the secrets it consumes (`SUPABASE_ANON_KEY`, `OAUTH_PROBE_GITHUB_CLIENT_ID`, `SUPABASE_PROJECT_REF`, Sentry trio) are already in Doppler `prd` (used by Inngest functions today) — no new secrets-management surface.

**Brand-survival threshold:** none.

- **threshold: none, reason:** observability-tier change — the diff touches a Sentry cron-monitor IaC margin tunable (`apps/web-platform/infra/sentry/cron-monitors.tf`) and adds a new Inngest cron function under `apps/web-platform/server/inngest/functions/`. Both surfaces match the `apps/[^/]+/(infra|server)/` sensitive-path regex and trigger preflight Check 6's sensitive-path probe, but neither carries an auth flow, a schema, a PII transform, a secret rotation, or new processing activity. The probe's user-facing behavior (the curl reachability checks at `app.soleur.ai/login` and `api.soleur.ai/auth/v1/...`) is preserved verbatim from the existing GHA workflow; the `--max-time 10` curl bounds are retained; no new code paths reach user-controlled input. The workflow file is **deleted** in the same PR (per TR9 I-13 hygiene from PR-1 #3985) — the GHA-side surface goes to zero, not in-parallel-with-Inngest.

## Research Reconciliation — Spec vs. Codebase

| Claim (May 18 plan / user description / sibling docs) | Reality (grep + `gh run list` verified at plan time) | Plan response |
| --- | --- | --- |
| "GHA cron fires ~60 min daytime, ~3-4 h overnight" (May 18 plan, line 50) | Post-#3964 window (4 days, 49 fires): median gap 150 min daytime, max 293 min overnight. 18 of 23 daytime samples exceed 2h. Distribution is **strictly worse** than the May 18 model. | The May 18 model justified `checkin_margin_minutes = 30`. The actual distribution would need ~300+ min margin to absorb false positives — that's not a margin, that's "the monitor is decorative". Migrate to Inngest substrate instead, where the median gap on `scheduled-daily-triage` and `scheduled-follow-through` is **≤2 min** (per PR #3985 / PR #4062 plan data). |
| "matched GH App drift-guard sibling's `0 * * * *` + 15-min margin" (May 18 plan, line 51) | `cron-monitors.tf:87` shows `scheduled_github_app_drift_guard.checkin_margin_minutes = 180`, not 15. The May 18 plan paraphrased a fictional sibling. | Plan body fixed: the May 18 cadence claim was wrong. The actual sibling is at 180 min and has been silently surviving misses below `failure_issue_threshold = 2`. The sister monitor also needs the migration; see Sharp Edges + a paired tracking issue. |
| "Inngest cron is not viable as substrate for oauth-probe (out of scope)" (user's framing on May 18) | Both `cron-daily-triage.ts` and `cron-follow-through-monitor.ts` already use Inngest, BOTH spawn external processes (claude binary, child curl), BOTH POST to Sentry via the same heartbeat shape, and BOTH have `checkin_margin_minutes = 30` on their monitors. The substrate cost is ~120 LoC of plumbing — already established. | Adopt the established pattern. The probe is in fact a **better** Inngest fit than the existing cron-* fns because it makes outbound HTTP only (no claude spawn, no DB writes, no event emit) — pure synchronous fetch. |
| "Bug #1 (silent-fail) ≠ bug #2 (cadence). Bug #1 alone fixes the symptom." (implicit in May 18 plan structure) | Post-#3964 verification: every fire posts a clean `?status=ok` heartbeat (confirmed via `gh run view 26204528955 --log` on the most recent fire). Sentry still files missed-checkin because the **fires themselves don't happen on schedule**. Bug #1 fix is necessary but not sufficient. | Plan explicitly addresses bug #2 with substrate migration, not margin patches. |
| "Sister-workflow defect class is bounded to 7 workflows (May 18 Sharp Edge)" | Inventory at plan time: 7 sister `.github/workflows/scheduled-*.yml` workflows migrated to the shared composite action via PR #3971. None of them currently have `cron: '0 * * * *'` — the closest match (`scheduled-github-app-drift-guard`) DOES. So the GHA cadence defect class affects 2 currently: `scheduled-oauth-probe` (this PR) + `scheduled-github-app-drift-guard` (deferred to follow-up — see Sharp Edges). All other sister workflows are daily/weekly where the 180+min margin is decoupled from intra-day jitter. | Scope this PR to oauth-probe (single-domain). File a follow-up issue (tracking, no scope-out label, same code area) to migrate `scheduled-github-app-drift-guard` to Inngest cron via the same pattern after this PR ships. |
| "Heartbeat-mode loses runtime-overrun detection" (May 18 plan, Sharp Edge 6) | Confirmed: Sentry's heartbeat-only mode does not page on runtime overage. The probe completes in <1 minute today. Inngest `step.run` envelope adds <100 ms overhead. AbortSignal.timeout caps fetch at 10s; the Inngest function itself can carry a `step.run("probe", { timeout: "5m" }, ...)` invariant. | Plan adopts an Inngest-side timeout (5 min, matches GHA `timeout-minutes: 5`); plus the existing Better Stack `inngest-heartbeat.timer` (60s) plus the Sentry `scheduled_oauth_probe` `max_runtime_minutes = 10` (decorative in heartbeat mode but retained for sibling consistency). Three layers, each independent. |

## Hypotheses

Not a network-outage diagnosis class. Phase 1.4 keyword scan (`SSH`, `connection reset`, `kex`, `firewall`, `timeout`, `502`, `503`) does NOT match the feature description. The touched Terraform resource has no `provisioner "remote-exec"` / `connection { type = "ssh" }` block. Skipping Phase 1.4 silently per the runbook.

**The actual root-cause hypothesis cascade (in order tested + confirmed during diagnosis):**

1. **H1 — "Heartbeat code is wrong post-#3964."** REJECTED. `cat .github/actions/sentry-heartbeat/action.yml` shows the correct shape (no `|| true`, single POST, secret guard, `continue-on-error: true` at YAML tier). `gh run view 26204528955 --log` shows the curl line firing cleanly with all 3 secrets non-empty.
2. **H2 — "Sentry monitor cadence/timezone mismatched IaC."** REJECTED. `cron-monitors.tf:62-72` matches the workflow's `cron: '0 * * * *'`. Timezone is `UTC`. The margin (`checkin_margin_minutes = 30`) is what was set on May 18 per spec.
3. **H3 — "GHA cron is degraded; substrate cadence drift exceeds margin."** **CONFIRMED.** `gh run list --workflow=scheduled-oauth-probe.yml --limit 50` post-#3964 shows median 150-min gaps, max 293 min. Same shape on sister `scheduled-github-app-drift-guard` (max 307 min). The margin would need to be 300+ min to cover the distribution — at which point the monitor cannot detect any real outage shorter than 5 hours.
4. **H4 — "Inngest substrate exists; we're already using it for cron-*. Why isn't oauth-probe on it?"** Substrate predates this PR (Inngest server bootstrapped via PR-F / #3940 MERGED 2026-05-17; cron-daily-triage on PR #3985 MERGED 2026-05-18; cron-follow-through on PR #4062 MERGED 2026-05-19). The May 18 fix (PR #3964) was authored on the same day PR-F shipped; substrate migration of oauth-probe wasn't yet seen as an option. Now it is.
5. **H5 — "Sister hourly workflow (`scheduled-github-app-drift-guard`) is also drifting and will regress in Sentry similarly."** **CONFIRMED via cron-monitors.tf:82-92**: same `0 * * * *` schedule, 180-min margin. Margin is wider so it currently absorbs the misses below `failure_issue_threshold = 2`. Tracking: paired follow-up issue (filed post-merge, label `code-review` + `priority/p2-medium`, NOT `deferred-scope-out` — sister workflow lives in the same top-level dir, fails the cross-cutting-refactor criterion per the May 18 session error).

## Acceptance Criteria

### Pre-merge (PR)

**Code shape (Inngest function):**

- [ ] AC1 — A new file `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts` exists. It exports `cronOauthProbe = inngest.createFunction({...}, [{ cron: "0 * * * *" }, { event: "cron/oauth-probe.manual-trigger" }], cronOauthProbeHandler)`. The handler is wrapped in a single `step.run("probe", ...)` block per ADR-033 I1 (replay-memoization invariant) AND a sibling `step.run("sentry-heartbeat", ...)` block matching the shape at `cron-daily-triage.ts:329-371`.
- [ ] AC2 — The handler embeds the probe logic verbatim from `.github/workflows/scheduled-oauth-probe.yml:71-422` translated to TypeScript: 8 failure modes (`network_error`, `login_unreachable`, `google_authorize`, `github_authorize`, 5x `github_oauth_*`, `settings_*`, `callback_error_passthrough`) preserved by name; same curl forms with `--max-time 10` via `AbortSignal.timeout(10_000)` AND `fetch(url, { redirect: "manual" })` to capture 302 status codes without auto-following; same body-grep sentinels (`redirect_uri is not associated`, `Application suspended`, `authenticity_token|Sign in to GitHub|Authorize [A-Z]`).
- [ ] AC3 — The handler reads `APP_HOST`, `API_HOST`, `SUPABASE_ANON_KEY`, `OAUTH_PROBE_GITHUB_CLIENT_ID`, `SUPABASE_PROJECT_REF` from `process.env` (sourced from Doppler `prd` like all other Inngest functions — no new secret materialization). Hardcoded fallback `APP_HOST=app.soleur.ai`, `API_HOST=api.soleur.ai` matches the GHA workflow envs.
- [ ] AC4 — On failure_mode non-empty, the handler emits an Inngest event `inngest.send({ name: "cron/oauth-probe.failed", data: { failureMode, failureDetail, runId } })` from within the `step.run("probe", ...)` envelope. A new `apps/web-platform/server/inngest/functions/oauth-probe-failure-emitter.ts` (or extension of an existing event handler — TBD at /work time) consumes this event to file/comment-on the `[ci/auth-broken] Synthetic OAuth probe failed` GitHub issue. **OR** equivalently: the handler invokes the existing `gh api` issue-create/comment logic in-process via an Octokit call using `GITHUB_APP_*` Doppler secrets. /work-time choice; both shapes maintain the operator-tracking-issue surface from the GHA workflow lines 424-490. AC verification: filing one synthetic failure via `inngest send cron/oauth-probe.manual-trigger` from a dev shell produces an issue OR an issue comment on the canonical title within 60 s — verified at /work Phase 4 via dev/staging Doppler scope.
- [ ] AC5 — The handler emits a `notify-ops-email`-shape POST to Resend's HTTP API directly (no existing TypeScript helper — verified at deepen-plan time, no `apps/web-platform/server/email/` directory exists; `notify-ops-email` lives only as a composite action at `.github/actions/notify-ops-email/action.yml`). The handler issues `fetch("https://api.resend.com/emails", { method: "POST", headers: { Authorization: "Bearer ${RESEND_API_KEY}", "Content-Type": "application/json" }, body: JSON.stringify({ from: "Soleur Ops <noreply@soleur.ai>", to: ["ops@jikigai.com"], subject, html }) })` matching the composite action's exact payload shape (verified verbatim from `.github/actions/notify-ops-email/action.yml:33-44`). Subject preserves `[Soleur Ops] OAuth probe failure: <fail_mode>`; body preserves the 4-line HTML format (failure_mode, detail, run-log link, runbook link). RESEND_API_KEY is sourced from `process.env.RESEND_API_KEY` (already in Doppler `prd`; no new secret). The Resend POST is wrapped in `step.run("notify-ops-email", ...)` so an HTTP failure is retried per Inngest's default retry policy. At /work-time, prefer extracting the Resend POST into `apps/web-platform/server/email/send-ops-notification.ts` (new file) if the helper would have ≥2 callers; otherwise inline in the cron-oauth-probe handler.
- [ ] AC6 — The handler's auto-close-stale-issue branch (success path) matches GHA workflow lines 504-526: when `failure_mode == ""` AND an open `[ci/auth-broken] Synthetic OAuth probe failed` issue exists, post the canonical green-comment AND `gh api`/Octokit close the issue.
- [ ] AC7 — The handler's Sentry heartbeat step matches the cron-daily-triage shape at `cron-daily-triage.ts:329-371`: pre-flight env validation via `SENTRY_DOMAIN_RE`, `SENTRY_PROJECT_RE`, `SENTRY_PUBLIC_KEY_RE` regex guards; `POST https://${domain}/api/${projectId}/cron/scheduled-oauth-probe/${publicKey}/?status=${ok|error}`; `AbortSignal.timeout(10_000)`; fallback to `reportSilentFallback` on fetch error (per `cq-silent-fallback-must-mirror-to-sentry`). Slug `scheduled-oauth-probe` is hardcoded as `const SENTRY_MONITOR_SLUG = "scheduled-oauth-probe"` (continuity preserved — same slug as the existing Sentry monitor resource).
- [ ] AC8 — The new function is registered in the Inngest endpoint at `apps/web-platform/app/api/inngest/route.ts` (or wherever `inngest.createFunction` outputs are aggregated — Phase 0.1 verifies the registry file). Without registration the function is dead code. Sentinel: `grep -nE 'cronOauthProbe' apps/web-platform/app/api/inngest/route.ts` returns ≥1.

**Workflow deletion + GHA-side cleanup:**

- [ ] AC9 — `.github/workflows/scheduled-oauth-probe.yml` is **deleted** in this PR (`git ls-files .github/workflows/scheduled-oauth-probe.yml` returns empty). Per TR9 PR-1 / I-13 hygiene precedent: when an Inngest cron supersedes a GHA-scheduled workflow, the GHA file MUST be deleted in the same PR. Two GHA crons firing the same probe concurrently would double-charge Sentry rate-limits AND double the runbook-issue files.
- [ ] AC10 — The shared composite action `.github/actions/sentry-heartbeat/action.yml` is preserved unchanged (still consumed by 7 sister workflows per PR #3971). This PR does NOT touch composite-action internals.

**Sentry monitor IaC:**

- [ ] AC11 — `apps/web-platform/infra/sentry/cron-monitors.tf` `resource "sentry_cron_monitor" "scheduled_oauth_probe"` changes: `checkin_margin_minutes = 30` (unchanged in number, but the rationale changes — now Inngest-fired, matching `scheduled_daily_triage` precedent per cron-monitors.tf:99-104). `schedule = { crontab = "0 * * * *" }` unchanged. `max_runtime_minutes = 10` unchanged (decorative in heartbeat mode but retained for sibling consistency). `failure_issue_threshold = 2` LOWERED to **1** because Inngest deterministic firing means a single missed check-in is itself signal (per scheduled_daily_triage and scheduled_follow_through which both use threshold=1). The header comment block updated to remove the obsolete GHA-jitter reasoning that justified threshold=2.
- [ ] AC12 — The comment block above the resource (cron-monitors.tf:62-72) is rewritten to explain: (a) this monitor is Inngest-fired (not GHA-fired) as of this PR, (b) margin tightened from the GHA-jitter reality back to the Inngest precedent, (c) threshold lowered to 1 matching sibling Inngest-fired monitors. Sentinel: `grep -nE 'Inngest-fired|GHA-jitter|GHA-fired' apps/web-platform/infra/sentry/cron-monitors.tf` returns matches consistent with the new prose. Cross-link to ADR-030 + ADR-033.
- [ ] AC13 — The lone-line breadcrumb at cron-monitors.tf:24-29 (the comment naming the 2 exceptions to `failure_issue_threshold = 1`) is updated: after this PR, only `scheduled_github_app_drift_guard` remains at threshold=2. Comment rewritten accordingly. Sentinel: `grep -nE 'oauth-probe and github-app' apps/web-platform/infra/sentry/cron-monitors.tf` returns 0 (the joint reference is gone); `grep -nE 'github-app-drift-guard' apps/web-platform/infra/sentry/cron-monitors.tf` returns the new single-exception note.

**Operator-surface doc sweep (full enumeration at plan time; AC sentinel uses identical regex):**

- [ ] AC14 — `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` updated at the following sites (plan-time enumerated via `grep -nE 'scheduled-oauth-probe.yml|workflow run scheduled-oauth-probe|gh run list.*oauth-probe|scheduled.*OAuth Probe' knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md`):
  - line 5 (`applies_to: .github/workflows/scheduled-oauth-probe.yml`) — replace with `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts`.
  - line 16 (`runs every hour from a GitHub-hosted runner`) — replace with `runs every hour as a self-hosted Inngest cron on the Hetzner VM`.
  - line 33 (`Open the most recent green Scheduled: OAuth Probe run`) — replace with `Open the most recent Inngest function-run for cron-oauth-probe via the Inngest dashboard at https://inngest.soleur.ai/runs?function=cron-oauth-probe` OR the equivalent CLI form `inngest server runs --function cron-oauth-probe` (Phase 0.1 verifies the actual operator-facing URL/CLI).
  - line 34 (`Inspect the Sentry check-in (final) step log`) — replace with `Inspect the step.run("sentry-heartbeat") output in the Inngest function-run page`.
  - line 41 (`Re-run with workflow_dispatch after fixing the secret`) — replace with `Re-run via inngest send cron/oauth-probe.manual-trigger after fixing the secret`.
  - line 228 (`gh workflow run scheduled-oauth-probe.yml`) — replace with `inngest send cron/oauth-probe.manual-trigger` (and update the surrounding "Re-run the probe" recipe at lines 489-501 to use the Inngest CLI).
  - line 237 (`wait one probe cycle (1 h)`) — UNCHANGED (still hourly).
  - line 489-501 recipe (`Re-run the probe on demand`) — translated to Inngest CLI form. The `gh run watch` pattern is replaced with `inngest server runs --function cron-oauth-probe --latest` (verify exact flag at Phase 0.1 via `inngest server runs --help`).
  - Sentinel: `grep -cE 'gh run list.*oauth-probe|gh workflow run scheduled-oauth-probe|scheduled-oauth-probe\.yml' knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` returns 0.
- [ ] AC15 — `knowledge-base/engineering/ops/runbooks/github-app-drift.md` line 339 still references `scheduled-oauth-probe.yml` (`The user-facing OAuth probe (scheduled-oauth-probe.yml, every hour) ...`). Updated to `The user-facing OAuth probe (Inngest cron cron-oauth-probe, every hour) ...`. Sentinel: `grep -nE 'scheduled-oauth-probe\.yml' knowledge-base/engineering/ops/runbooks/github-app-drift.md` returns 0.
- [ ] AC16 — Plan-time enumerated operator-surface grep over all relevant docs, with `grep -rEn 'scheduled-oauth-probe\.yml|gh workflow run scheduled-oauth-probe|gh run list.*scheduled-oauth-probe' knowledge-base/ apps/web-platform/ README.md CONTRIBUTING.md 2>/dev/null | grep -v 'knowledge-base/project/\(plans\|specs\|learnings\)/' | grep -v archive/`:
  - `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` — covered by AC14.
  - `knowledge-base/engineering/ops/runbooks/github-app-drift.md` — covered by AC15.
  - `apps/web-platform/test/oauth-probe-contract.test.ts` (referenced from oauth-probe-failure.md line 230) — **VERIFY** at Phase 0.1 whether the contract test still applies (it tests sentinel constants like `authenticity_token` strings; those are workflow-agnostic and migrate to the Inngest function unchanged — the test should still pass since the sentinel strings live in test fixtures, not in a workflow shape). If the test imports from the workflow file directly, refactor to extract sentinels to a shared module.
  - Scope exclusion: `knowledge-base/project/{plans,specs,learnings}/**`, `**/archive/**`, `knowledge-base/legal/audits/**` (historical record per the May 18 plan AC10).
  - Final sentinel: `grep -rEn 'scheduled-oauth-probe\.yml|gh workflow run scheduled-oauth-probe|gh run list.*scheduled-oauth-probe' knowledge-base/engineering/ apps/web-platform/ README.md CONTRIBUTING.md 2>/dev/null | grep -v archive/ | grep -v 'knowledge-base/project/\(plans\|specs\|learnings\)/' | wc -l` returns 0.

**Verification gates:**

- [ ] AC17 — `terraform validate` passes on `apps/web-platform/infra/sentry/` (margin/threshold integer-type stability). Invocation: `cd apps/web-platform/infra/sentry && terraform init -input=false -backend=false && terraform validate`.
- [ ] AC18 — `bun run typecheck` (or repo's `package.json` `scripts.typecheck` — verify path at Phase 0.1) passes against the new `cron-oauth-probe.ts` file. The handler's `step.run` envelope return shape MUST match ADR-033 I5 (`{ ok, exitCode, signal, abortedByTimeout, durationMs }` — adapt for the no-spawn case: `{ ok, failureMode, failureDetail, durationMs }`).
- [ ] AC19 — A new test `apps/web-platform/test/server/inngest/cron-oauth-probe.test.ts` (path verified at deepen-plan time — sibling cron tests live at `test/server/inngest/cron-daily-triage.test.ts` and `test/server/inngest/cron-follow-through-monitor.test.ts`) covers:
  - The `failure_mode == ""` happy-path branch produces a `?status=ok` heartbeat call.
  - The `failure_mode != ""` branch produces a `?status=error` heartbeat call.
  - The fork-PR fallback (`SENTRY_INGEST_DOMAIN` empty) logs a warning and exits without throwing.
  - Each of the 8 failure modes maps to its canonical `record_failure(<mode>, <detail>)` value.
  Test harness uses mocked `fetch` per the existing pattern in sibling tests; no real Sentry network calls.
- [ ] AC20 — `cron-no-byok-lease-sweep.test.ts` (at `apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts`) auto-extends to the new `cron-oauth-probe.ts` via its glob `server/inngest/functions/cron-*.ts` (verified at deepen-plan time, line 39 of the test file). Re-run via `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/cron-no-byok-lease-sweep.test.ts` to confirm no BYOK violation (the handler uses no Anthropic API key; only Supabase/GitHub/Sentry/Resend env). The test enforces ADR-033 I2 across 4 import shapes (direct call, alias import, bare import + indirect call, dynamic import).
- [ ] AC21 — PR body uses `Ref` not `Closes` for the sister-workflow follow-up issue (filed post-merge, see AC25). PR body includes `Closes #3203` (the trap-RETURN cleanup issue is resolved by workflow deletion). The May 18 plan's proposed `Closes #3236` is dropped — verified at deepen-plan time that `gh issue view 3236 --json state` returns `CLOSED` (the dead-man's-switch tracking issue was closed by PR #3811 when the original Sentry monitors landed); no second-close needed. Plan body claim that this PR "folds Closes #3236" is wrong in the original plan and is amended here.

### Post-merge (auto + verification)

- [ ] AC22 — **Auto:** push to `main` triggers two auto-apply flows:
  1. `apps/web-platform/infra/sentry/cron-monitors.tf` change auto-applied via `.github/workflows/apply-sentry-infra.yml` (paths filter matches). The `sentry_cron_monitor.scheduled_oauth_probe` resource is updated in-place (margin number unchanged at 30; threshold lowered to 1; comment block updated). No operator action. Verification: `gh run list --workflow=apply-sentry-infra.yml --limit 1 --json conclusion` returns `success` within 5 minutes of merge.
  2. `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts` is included in the Next.js production build and registered in `apps/web-platform/app/api/inngest/route.ts` (per AC8 — verified at deepen-plan time: the file currently imports and registers `cfoOnPaymentFailed, cronDailyTriage, cronFollowThroughMonitor, githubOnEvent` at line 37; this PR extends the array). The Inngest server discovers registered functions via the `/api/inngest` introspection endpoint at first POST-deploy boot. **No operator action.** Verification (preferred, no-SSH): immediately after deploy, fire `inngest send cron/oauth-probe.manual-trigger` from a CI-side script (uses existing `INNGEST_EVENT_KEY` Doppler secret) and verify a function-run lands within 30s via `gh run view` of the resulting `step.run` output captured in the dispatch's response. **The plan deliberately does NOT prescribe SSH-into-Hetzner as the verification mechanism** (per `hr-no-dashboard-eyeball-pull-data-yourself` AND `hr-observability-as-plan-quality-gate`).
- [ ] AC23 — **Auto, T+90 min:** the first scheduled Inngest fire of `cron-oauth-probe` posts `?status=ok` to Sentry. Verification: `curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://${SENTRY_API_HOST}/api/0/projects/$SENTRY_ORG/$SENTRY_PROJECT/cron-monitors/scheduled-oauth-probe/checkins/?limit=1" | jq -r '.[0] | "\(.dateAdded) \(.status)"'` shows a recent `ok` check-in (≤90 min ago — covers the up-to-1-hour scheduling interval + Inngest's ≤2-min jitter). Per `hr-no-dashboard-eyeball-pull-data-yourself`: prefer Sentry API over dashboard.
- [ ] AC24 — **Auto, T+24h:** the recurring Sentry issue `a94c4ec23f654101a7fc4491b16a560c` is auto-resolved by Sentry once `recovery_threshold = 1` is met (one successful check-in). Verification: `curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://${SENTRY_API_HOST}/api/0/organizations/$SENTRY_ORG/issues/a94c4ec23f654101a7fc4491b16a560c/" | jq -r '.status'` returns `resolved`. No operator click — Sentry auto-resolves.
- [ ] AC25 — **Auto-follow-up:** the post-merge ship phase files a paired tracking issue (label `code-review` + `priority/p2-medium`, NOT `deferred-scope-out`): `chore: migrate scheduled-github-app-drift-guard to Inngest cron substrate (mirrors #4207)`. Body cites the same root-cause analysis (GHA hourly cron drift exceeds margin). Sister workflow is functionally separate (different probe surface, different runbook, different failure-routing) so the migration is mechanical-but-not-trivial — not folded in here.

## Files to Edit

- `apps/web-platform/infra/sentry/cron-monitors.tf` — lines 24-29 (joint-exception breadcrumb) updated to name only `scheduled_github_app_drift_guard` as the threshold=2 exception; lines 62-72 (`scheduled_oauth_probe` resource) updated: comment block rewritten to name Inngest-fired substrate; `failure_issue_threshold` 2 → 1; `checkin_margin_minutes` 30 unchanged (rationale changes only).
- `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` — per AC14 enumeration (10 line-pair edits + the "Re-run the probe on demand" recipe at lines 489-501).
- `knowledge-base/engineering/ops/runbooks/github-app-drift.md` — line 339 reference to `scheduled-oauth-probe.yml` translated to `cron-oauth-probe`.
- `apps/web-platform/app/api/inngest/route.ts` (verified at deepen-plan time as the canonical registry file at lines 21-22 + 37) — add `import { cronOauthProbe } from "@/server/inngest/functions/cron-oauth-probe";` and extend the `functions:` array at line 37 to include `cronOauthProbe`.

## Files to Create

- `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts` — the new Inngest function (handler + registration). Estimated ~250 LoC: ~180 LoC translated probe logic (8 failure modes, 5 probe helpers), ~30 LoC heartbeat + email + issue-touching, ~40 LoC the standard Inngest envelope (concurrency, retries, manual-trigger event registration).
- `apps/web-platform/test/inngest/cron-oauth-probe.test.ts` (or co-located per repo convention) — per AC19.
- `knowledge-base/project/specs/feat-one-shot-fix-scheduled-oauth-probe-recurrence/tasks.md` — auto-generated from this plan by `soleur:plan` Save Tasks step.

## Files to Delete

- `.github/workflows/scheduled-oauth-probe.yml` — replaced by `cron-oauth-probe.ts`. Per AC9.

## Open Code-Review Overlap

Two open code-review issues touch the affected surfaces. Plan-time `gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json && jq -r --arg p ".github/workflows/scheduled-oauth-probe.yml" '.[] | select(.body // "" | contains($p)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json`:

- **#3203: review: extract trap RETURN cleanup pattern in scheduled-oauth-probe (P3)** — **Resolved by deletion.** The `trap RETURN` pattern lives in `scheduled-oauth-probe.yml` which is deleted by this PR (AC9). The TypeScript translation of the probe in `cron-oauth-probe.ts` does not use bash `trap` — `try/finally` blocks in the Inngest handler handle cleanup of any tmpfiles equivalently. PR body adds `Closes #3203` once the workflow is verified deleted post-merge.

No code-review issues match `apps/web-platform/infra/sentry/cron-monitors.tf` or `apps/web-platform/server/inngest/functions/` paths at plan time.

## Domain Review

**Domains relevant:** Engineering / Ops (CTO lens — substrate migration of an observability primitive). Product: NONE (no user-facing surface). Legal: NONE (no PII / data-processing change; same anon-key reads). Sales/Marketing/Finance/Support: NONE.

### Engineering / Ops (CTO assessment — inline, plan-author lens)

**Status:** reviewed.
**Assessment:** This is a substrate migration of a synthetic observability probe from one cron substrate (GHA hosted-runner scheduler) to another (Inngest cron on the self-hosted Hetzner VM). The migration's value is asymmetric: it eliminates the GHA-cron-drift class permanently rather than paying down its margin per fire. Net complexity is comparable — Inngest functions carry an `step.run` envelope cost but eliminate the entire bash translation layer. The new function reuses the established `cron-daily-triage` / `cron-follow-through-monitor` patterns 1:1 (same heartbeat shape, same env-var sourcing, same `cron-no-byok-lease-sweep` test coverage). Risk to ADR-030 invariants: none — the probe makes no Anthropic API call (no BYOK exposure surface), no DB writes (no migration footprint), no new event emission patterns (the optional `cron/oauth-probe.failed` event is consumed by a new in-tree handler).

**Substrate-failure mode added by this PR:** if Inngest server is down (per the #4116 inngest-heartbeat brokenness window), the probe doesn't fire. Two compensating signals: (a) `inngest-heartbeat.timer` posts to Better Stack every 60s (Better Stack pages on heartbeat miss within 30s grace), (b) the existing `cron-daily-triage` and `cron-follow-through-monitor` ALSO depend on Inngest server liveness, so a substrate-down event is detected via the existing Sentry monitors for those functions. Per the #4116 learning, Better Stack is the canonical Inngest-substrate liveness signal — this PR does not change that.

**Substrate-failure mode removed:** GHA-cron-drift-induced false missed-checkins (the present recurring alert). Permanently gone.

**Threshold rationale (cron-monitors.tf:24-29 breadcrumb):** Inngest-fired monitors deterministically miss a fire only if Inngest substrate is down, in which case multiple monitors fire simultaneously (a substrate-down event, not a probe-down event). One missed check-in is itself signal — match the sibling Inngest-fired precedent (`scheduled_daily_triage`, `scheduled_follow_through`) with `failure_issue_threshold = 1`.

## GDPR / Compliance Gate

Not triggered. Per `hr-gdpr-gate-on-regulated-data-surfaces` canonical regex: this PR touches a TypeScript file under `apps/web-platform/server/inngest/`, a Terraform monitor resource, runbooks, and workflow deletion. None match schemas/migrations/auth flows/API routes/`.sql` files at the canonical regex level. Phase 2.7 extension triggers (a)-(d) also do not fire:
- (a) NO new LLM/external-API processing on operator-session data — the probe makes only synchronous HTTP fetches to public auth surfaces.
- (b) Brand-survival threshold is `none`.
- (c) The new cron does NOT read from `knowledge-base/project/learnings/` or `knowledge-base/project/specs/`.
- (d) NO new artifact-distribution surface (no plugin update, no public PR-body data, no package release).

Skipping silently per Phase 2.7.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/sentry/cron-monitors.tf`:
  - Updated comment block at lines 24-29 (the joint-exception breadcrumb): `scheduled_oauth_probe` removed from the `failure_issue_threshold = 2` exception list; `scheduled_github_app_drift_guard` named as the sole remaining exception with a one-line reason "(still GHA-fired hourly; see follow-up issue tracking migration to Inngest)".
  - Updated `scheduled_oauth_probe` resource (lines 62-72): comment block re-written to declare Inngest-fired substrate; `failure_issue_threshold` 2 → 1; all other fields unchanged.

No new providers, no new sensitive variables, no new state-storage. The `jianyuan/sentry v0.15.0-beta2` provider is already in `.terraform.lock.hcl`.

### Apply path

(b) cloud-init + idempotent bootstrap N/A — this is a pure Terraform state-update on an existing resource. Apply path: `.github/workflows/apply-sentry-infra.yml` triggers on push-to-main with paths filter on `apps/web-platform/infra/sentry/**`; the workflow runs `terraform plan -target=sentry_cron_monitor.scheduled_oauth_probe` then `apply -auto-approve` on the same. Expected change: in-place attribute update (no destroy + create). Expected downtime: 0 — Sentry monitor in-place updates do not interrupt check-in collection.

### Distinctness / drift safeguards

- `dev != prd` precondition: the Sentry monitors live in the `web-platform` project only (no dev mirror — Sentry monitors are not a Doppler-config-by-env resource). N/A here.
- `lifecycle.ignore_changes`: not applied; the monitor resource is fully apply-friendly.
- State-storage: `apps/web-platform/infra/sentry/backend.tf` already pins to R2 per the established sentry IaC root pattern.

### Vendor-tier reality check

Sentry billing: this PR modifies an existing seat (no NEW `sentry_cron_monitor` resource is created), so PAYG headroom is irrelevant per `knowledge-base/project/learnings/2026-05-15-sentry-iac-billing-and-quirks.md`. No `GET /api/0/customers/jikigai/` pre-flight needed.

Inngest substrate: this PR adds one new function to the existing self-hosted Inngest server on the Hetzner VM. No new vendor cost. Cron-platform concurrency cap (`{ scope: "account", key: '"cron-platform"', limit: 1 }` per `cron-daily-triage.ts:391`) IS extended to this new function to maintain Architecture F7 (prevent OOM under cron-* fan-out). Probe is short-lived (<1 min) so the 1-concurrent cap is generous.

## Observability

```yaml
liveness_signal:
  what: Sentry cron-monitor heartbeat for `scheduled-oauth-probe` slug
  cadence: every 1 h (matches Inngest cron `0 * * * *`)
  alert_target: Sentry monitor `scheduled-oauth-probe` (failure_issue_threshold=1, recovery_threshold=1) — same Sentry issue ID currently firing (`a94c4ec23f654101a7fc4491b16a560c`) auto-resolves on first ok; future drifts open a new fingerprint
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf:62-72
error_reporting:
  destination: Sentry (via `reportSilentFallback` from `@/server/observability` per cq-silent-fallback-must-mirror-to-sentry); secondary destination = `cron-oauth-probe.failed` Inngest event → filed GitHub issue `[ci/auth-broken] Synthetic OAuth probe failed` (same canonical title as today; same `ci/auth-broken` + `priority/p1-high` labels)
  fail_loud: yes — `step.run("probe", ...)` errors bubble to Inngest's run-failure stream (visible via `inngest server runs --status=FAILED --function cron-oauth-probe`); per ADR-033 I5 the return shape is deterministic so a structural regression surfaces at typecheck time
failure_modes:
  - mode: substrate-down (Inngest server unreachable)
    detection: inngest-heartbeat.timer Better Stack heartbeat miss within 60s + Sentry `scheduled_oauth_probe` missed-checkin within margin; sister `scheduled_daily_triage` + `scheduled_follow_through` ALSO miss
    alert_route: Better Stack email + Sentry email (operator gets both signals; substrate-down inferred from cross-monitor correlation)
  - mode: probe-detection regression (real auth failure)
    detection: `cron-oauth-probe` returns `ok: false`; `cron/oauth-probe.failed` Inngest event fires; issue filed at `[ci/auth-broken] Synthetic OAuth probe failed`; Resend email to ops
    alert_route: GitHub issue (operator notification via subscribed-issues) + Resend email (same as today)
  - mode: Sentry heartbeat curl failure (e.g., revoked SENTRY_PUBLIC_KEY)
    detection: `reportSilentFallback` mirrors to Sentry under `feature: "cron-sentry-heartbeat", op: "fetch"`; the probe itself reports `ok` (auth probe is healthy), but Sentry monitor `scheduled-oauth-probe` shows missed-checkin
    alert_route: same Sentry monitor surface as today; the Sentry-side log shows the auth failure
  - mode: probe times out (>5 min)
    detection: `step.run("probe", { timeout: "5m" }, ...)` aborts; Inngest emits failure; cron-oauth-probe returns `ok: false, abortedByTimeout: true`; Sentry heartbeat posts `?status=error`
    alert_route: same as probe-detection regression
logs:
  where: Inngest server `journalctl -u inngest-server.service` (per #4116 — no remote log aggregation yet; local-only)
  retention: systemd default (rotated at journald disk-usage thresholds; ~7 days at current write rate on the Hetzner VM)
discoverability_test:
  command: curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://${SENTRY_API_HOST}/api/0/projects/$SENTRY_ORG/$SENTRY_PROJECT/cron-monitors/scheduled-oauth-probe/checkins/?limit=5" | jq -r '.[] | "\(.dateAdded) \(.status)"'
  expected_output: 5 most recent check-ins, each `ok` status, gaps no greater than 90 min apart (under Inngest deterministic firing, expected gap ≤62 min between fires — `0 * * * *` cron, ≤2-min Inngest jitter)
```

## Test Strategy

The probe-detection logic (8 failure modes, 5 probe-helpers) is load-bearing AND not currently test-covered for behavior (only sentinel-string presence is tested in `oauth-probe-contract.test.ts`). The migration creates an opportunity to bring it under test for behavior — but doing so would expand scope beyond "fix the recurring alert." Test strategy:

1. **TypeScript unit tests** (AC19) — covers happy/error/no-secret branches against mocked `fetch`. New file at `apps/web-platform/test/inngest/cron-oauth-probe.test.ts`. Does NOT replace the probe-detection behavioral test gap (deferred to a follow-up).
2. **Compile + register gate** (AC8, AC18) — `bun run typecheck` + grep on the function-registry. Without registration, the function is dead code.
3. **Cron-no-BYOK gate** (AC20) — `cron-no-byok-lease-sweep.test.ts` auto-extends to the new file. Sanity check that the new function does not import Anthropic SDK / use BYOK leases.
4. **`terraform validate`** (AC17) — covers the cron-monitor schema (threshold INT change).
5. **Sentry contract test extension** — the existing `oauth-probe-contract.test.ts` (per runbook line 230) is preserved. If it imports from the workflow file path, refactor at /work time to import from a shared sentinels module that both the test and the new TS function consume (the strings: `redirect_uri is not associated`, `Application suspended`, `authenticity_token|Sign in to GitHub|Authorize [A-Z]`).
6. **First-post-merge fire as the contract test** (AC22, AC23) — the deterministic verdict is "did the first Inngest fire of `cron-oauth-probe` post a `?status=ok` heartbeat to Sentry?" The Sentry checkins API response (per AC23) IS the assertion.

No new test infrastructure is added beyond the new test file.

## Risks

1. **Inngest function registration race.** First-deploy: the build ships the new function, the Inngest server polls `/api/inngest`, the function appears in the registry. If the first scheduled fire falls within the poll window (~10s), it could be missed. **Mitigation:** Inngest poll is much faster than the hourly cadence; even a 60s poll window is 60x smaller than the 1h schedule. **Residual risk:** if a deploy happens at exactly `:00` UTC, the first fire might be the SECOND hour, not the first. Acceptable.
2. **Existing `[ci/auth-broken]` issue-filing/closing logic does not perfectly map 1:1 to in-process Octokit calls.** The workflow uses `gh issue create`/`gh issue list`/`gh issue close`/`gh issue comment`. The TypeScript version needs to thread a GitHub App auth token (per `hr-github-app-auth-not-pat`) and use Octokit. **Mitigation:** Phase 0.1 verifies whether `apps/web-platform/server/github/` already exports an Octokit App client (it should — the github-resolve route uses one). If not present, the alternative is to keep the issue-filing in a tiny GHA workflow triggered by `inngest send github/cron-failure-notification` event — but that's a workaround that re-introduces a GHA dependency. Prefer the in-process Octokit path.
3. **Substrate-cost amortization.** The Inngest function runs on the Hetzner VM (shared compute pool). The probe consumes ~1 min of CPU per hour = ~24 min/day = trivial. No PAYG impact.
4. **Probe `oauth-probe-contract.test.ts` may import from the deleted workflow file.** If so, AC9 (workflow deletion) breaks the test. **Mitigation:** Phase 0.1 reads the test file and verifies its dependency surface; if it imports from `scheduled-oauth-probe.yml` (e.g., via `fs.readFileSync` of the workflow text), refactor the sentinel strings to a shared module BEFORE the workflow deletion.
5. **`scheduled-github-app-drift-guard` continues to leak.** This sister workflow has the same root cause and is NOT fixed by this PR. **Mitigation:** AC25 files a paired follow-up tracking issue. **Residual risk:** the operator may receive an `[ci/auth-broken]` issue from drift-guard during the follow-up's lead-time. Acceptable — drift-guard's margin is 180 min (vs oauth-probe's 30 min) so its noise floor is lower; #4189 (the 2026-05-20 fire) was a REAL `installation_permission_drift` finding, not a Sentry missed-checkin.

## Sharp Edges

- **The May 18 plan's mental model of GHA cron behavior was wrong by ~3x.** The May 18 plan estimated ~60 min daytime; reality is ~150 min. Future GHA-cron-on-Hetzner-substrate-replacement plans MUST pull the 30-day gap distribution via `gh run list --limit 100 --json createdAt` and compute median/max BEFORE setting margins. Plan-time substrate-cadence assertions need real data. Generalizes `2026-04-22-plan-ac-external-state-must-be-api-verified` from Doppler/secret state to cron-fire history.
- **GHA cron is best-effort substrate; Sentry monitors with `checkin_margin_minutes` < observed max-gap are decorative.** For ANY workflow expecting <hourly fire reliability, GHA cron is the wrong substrate. Migrate to Inngest cron (Hetzner self-hosted, deterministic firing) per the TR9 PR-1/PR-2 precedent. Daily/weekly GHA crons remain fine — the margin can absorb day-scale jitter without false-positives.
- **`failure_issue_threshold = 2` is a band-aid for noisy substrates; `= 1` is correct for deterministic substrates.** The May 18 plan kept threshold=2 to absorb GHA jitter. With Inngest substrate, single-miss = real signal. Apply the lowering ANYTIME a monitor moves from GHA to Inngest cron (this PR for oauth-probe; the follow-up issue for github-app-drift-guard).
- **Sister-workflow defect class is bounded BUT not closed by this PR.** Only 2 currently-hourly workflows exist (`scheduled-oauth-probe` + `scheduled-github-app-drift-guard`). The sister migration (AC25 follow-up) is mechanically similar (~250 LoC TS file, same Sentry monitor lowering, same workflow deletion) and should land within 1-2 weeks of this PR. Don't fold it into THIS PR per the May 18 session-error guidance (`cross-cutting-refactor` doesn't apply when files live in the same top-level dir; file as paired tracking issue, not deferred-scope-out).
- **The probe's `dig CNAME api.soleur.ai` step (workflow lines 302-310) lives in bash; TypeScript has no built-in `dig`.** The TS translation MUST either (a) shell out to `dig` via `child_process.spawn` (preserves the canonical CNAME deref behavior; requires `dig` to be installed on the Hetzner VM — verify at Phase 0.1 via `ssh prod-web -- 'command -v dig'`), or (b) use Node's `dns.promises.resolveCname()` which returns the same CNAME chain. Prefer (b) — no shell dependency, no need to ship `dig` in the deploy environment. The output normalization (strip `.supabase.co.?$`, head -1) is trivial in TS.
- **In-process issue-filing logic increases Inngest function complexity.** The GHA workflow's `gh issue list/create/comment/close` is ~70 lines of bash. The TS equivalent via Octokit is ~50 lines but adds a runtime dependency (Octokit) + GitHub App auth threading. **Mitigation:** if the cost is too high at /work time, fall back to emitting `cron/oauth-probe.failed` Inngest event and consuming it in a tiny `oauth-probe-failure-handler.ts` function that ONLY does the GitHub side. Two functions = clearer separation of concerns but more boilerplate.
- **The `notify-ops-email` composite action depends on `actions/checkout` (workflow line 42-47, runbook reference at line 36-40).** The TS path uses Resend SDK directly — no checkout needed, no sparse-checkout dance.
- **Cron concurrency cap key is `'"cron-platform"'` (literal-string-in-string).** Per `cron-daily-triage.ts:391` the concurrency-key is a JSON-string-encoded literal because Inngest expects the key to be a runtime-string. The new function MUST mirror this verbatim — typos here are silent ("two cron-* fns running concurrently" never throws but bypasses the F7 OOM guard). Phase 0.1 grep verification: `grep -n 'cron-platform' apps/web-platform/server/inngest/functions/*.ts`.
- **`max_runtime_minutes = 10` on a heartbeat-mode monitor is decorative.** Retained for sibling consistency only. If a future migration brings oauth-probe back to two-step in_progress → ok/error (unlikely; it's <1 min today), the field becomes load-bearing. Same note as the May 18 plan Sharp Edge 6.
- **The recurring Sentry issue `a94c4ec23f654101a7fc4491b16a560c` is the SAME issue ID as the May 18 fire (`2c759a282af94e91a393417075074b98` was the earlier ID; the latest is `a94c...`).** Sentry creates a new fingerprint for each recovery → re-regression cycle. AC24 watches the LATEST ID; if a NEW fingerprint forms after AC24's verification window closes, it's a fresh regression and should be investigated independently.

## Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-05-21-fix-scheduled-oauth-probe-recurrence-plan.md. Branch: feat-one-shot-fix-scheduled-oauth-probe-recurrence. Worktree: .worktrees/feat-one-shot-fix-scheduled-oauth-probe-recurrence/. Issue: n/a (no parent issue; folds Closes #3203 via workflow deletion; #3236 was already closed by PR #3811). Plan reviewed, deepen-plan run, implementation next.
```
