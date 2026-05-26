---
title: "fix: sister-workflow rollout — Sentry heartbeat consolidation for 7 scheduled-*.yml workflows"
date: 2026-05-18
type: bug-fix
classification: ci-ops
lane: single-domain
status: planned
branch: feat-one-shot-fix-drift-guard-sentry-checkin
related_workflows:
  - .github/workflows/scheduled-community-monitor.yml
  - .github/workflows/scheduled-content-vendor-drift.yml
  - .github/workflows/scheduled-daily-triage.yml
  - .github/workflows/scheduled-github-app-drift-guard.yml
  - .github/workflows/scheduled-realtime-probe.yml
  - .github/workflows/scheduled-skill-freshness.yml
  - .github/workflows/scheduled-terraform-drift.yml
related_iac:
  - apps/web-platform/infra/sentry/cron-monitors.tf
related_runbooks:
  - knowledge-base/engineering/ops/runbooks/github-app-drift.md
related_issues: [3968, 3236]
related_pr_reference: 3964
reference_commit: c04ffd33
sentry_alert: WEB-PLATFORM-4
requires_cpo_signoff: false
---

# fix: sister-workflow rollout — Sentry heartbeat consolidation for 7 scheduled-*.yml workflows

## Enhancement Summary

**Deepened on:** 2026-05-18
**Plan author lens:** ops/observability (single-domain lane, threshold=none with sensitive-path scope-out for `apps/web-platform/infra/sentry/cron-monitors.tf`).
**Research applied:** live `gh pr view 3964 / 3811`, `gh issue view 3968 / 3236`, `git rev-parse + merge-base --is-ancestor c04ffd33`, per-workflow `gh run list --limit 12` cadence sampling, `apply-sentry-infra.yml` `-target=` scope audit, AGENTS.md/retired-rule-ids grep (zero rule citations in plan body — nothing to verify), 2026-05-18 vendor-cron-heartbeat-silent-fail-pattern learning, 2026-05-15 sentry-iac-billing-and-quirks learning, 2026-05-15 terraform-import-only-beta-provider-schema-validation learning, 2026-04-28 plan-globs-must-be-verified-against-repo-structure learning.

### Key Improvements over the initial draft

1. **Issue #3236 is ALREADY CLOSED** — verified via `gh issue view 3236 --json closedAt,closedByPullRequestsReferences` → `closedAt: 2026-05-18T09:24:38Z, closedBy: 3964` (auto-closed by `Closes #3236.` in PR #3964's body). The footer prose in issue #3968 ("manually `gh issue close #3236` once all 8 monitors have reported successful check-ins") is stale — #3236 was closed pre-emptively at #3964 merge time. The AC5-followup in the original plan draft would have been a no-op. **Plan response:** rewrote AC5-followup as a post-merge VERIFICATION step (confirm all 8 monitors green in Sentry UI; if any miss, RE-OPEN #3236 with the failing monitor list, do NOT close-and-close).
2. **AC1 and AC7 regex shape alignment.** Per session error in `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md` line 112 ("plan-time enumeration grep MUST use the EXACT regex shape the post-edit sentinel grep will use"), AC1's `grep -lE '"\$\{RUNNER_TEMP\}/sentry-checkin-id-'` and Phase 0.1's enumeration grep are now BYTE-IDENTICAL. AC7's curl-`|| true` grep was rewritten from the bash-pipe-confusing form to a single fixed-string check.
3. **Sharp Edge about preflight job gating made precise.** Initial draft said "community-monitor and daily-triage have a preflight job" — verified via `grep -nE "^  [a-z_-]+:"`. The other 5 workflows have a single job each (`probe` / `drift-check` / `drift-detect` / `aggregate`); listed each explicitly with line numbers.
4. **`apply-sentry-infra.yml` `-target=` scope citation added.** Verified at `.github/workflows/apply-sentry-infra.yml:163-170` — the auto-apply workflow `-target=`-scopes to all 8 `sentry_cron_monitor.*` resources individually, so the new monitor we're modifying (5 of 8 get margin bumps) will apply cleanly without disturbing the import-only `sentry_issue_alert` resources. Confirms blast radius = zero per learning `2026-05-15-terraform-import-only-beta-provider-schema-validation.md`.
5. **Cadence margin table reconciled against per-workflow `gh run list` data.** Each margin choice now cites the worst observed gap and the safety factor used. Most aggressive bump: `scheduled-daily-triage` 60 → 240 (4h max-observed lag); `scheduled-github-app-drift-guard` 15 → 180 (5h overnight gap on the active-alert monitor).
6. **`scheduled-skill-freshness` 60→60 kept as defer** with explicit "no cadence data" rationale (monthly cron with only one workflow_dispatch run in history). Tracked as a Phase 4.4 post-merge re-check.
7. **#3964 PR body content verified** — confirmed it contains `Closes #3236.` (single line, no follow-up issue close). This PR's body uses `Closes #3968` (which is open). No double-close risk.

### Research Insights

**Vendor-cron heartbeat silent-fail pattern** (from `knowledge-base/project/learnings/2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md` — the canonical reference learning):

- **Three load-bearing changes** that distinguish the canonical heartbeat from the legacy two-step:
  1. `if: always()` + single step replaces the `success()/failure()` step split — no tmpfile, no `jq`-extracted state to lose.
  2. No `|| true` on the curl — exit code lands in the step log so operators can SEE Sentry rejecting auth instead of guessing why "Last successful check-in: Never".
  3. `continue-on-error: true` retained at the YAML tier — a Sentry-side blip still does not red-flag an otherwise-green probe. Properties (2) and (3) are complementary, not redundant.
- **`max_runtime_minutes` is decorative in heartbeat-only mode** — Sentry only detects missed runs in that mode, not overages. Retain for schema consistency across monitor resources but do not expect it to load-bear. Already documented in `cron-monitors.tf` lines 39-45; this PR brings all 8 monitors into the regime that comment applies to.

**Sentry-IaC billing & provider quirks** (from `knowledge-base/project/learnings/2026-05-15-sentry-iac-billing-and-quirks.md`):

- The `jianyuan/sentry v0.15.0-beta2` provider serializes monitors with `enabled = true`, but the Sentry API ignores the flag at creation when org billing has no seat headroom (Gotcha 2 + 3). **This PR modifies, not creates** — no billing risk. The 5 margin-bumped monitors already exist in Sentry (they were created at #3811 merge time).
- `var.sentry_project` default mismatch (Gotcha 1) was fixed in #3857 — not in scope here, but worth noting if the apply throws a "Project does not exist" error post-merge (would indicate Doppler config regression, not this PR).

**Terraform import-only beta provider schema validation** (from `knowledge-base/project/learnings/2026-05-15-terraform-import-only-beta-provider-schema-validation.md`):

- The `apply-sentry-infra.yml` workflow is `-target=`-scoped to `sentry_cron_monitor.*` per PR #3811 — verified at `.github/workflows/apply-sentry-infra.yml:163-170`. Margin attribute changes on already-imported `sentry_cron_monitor` resources apply cleanly through this path. The import-only `sentry_issue_alert` resources (with `actions_v2 = []` + `lifecycle.ignore_changes`) are NOT in the `-target=` list, so they are untouched.

**GitHub Actions cron behavior** (well-documented GHA best-effort scheduling):

- Cron schedules are queued; delays of 5-15 min are normal during peak load. Sub-hourly schedules degrade to 30-60 min effective cadence. Daily schedules can be 1-4 h late, especially during off-peak (overnight). Monthly schedules have insufficient data here (skill-freshness has fired only once via workflow_dispatch).
- The `apply-sentry-infra.yml` auto-apply chain ensures monitor IaC changes land within ~5 min of merge to main; the post-merge AC5 verification window is one cron cycle per monitor.

### New Considerations Discovered

- **#3236 already closed → AC5-followup pivot.** Original draft asked operator to `gh issue close 3236` post-rollout. Reality: #3236 was closed by PR #3964's `Closes #3236.` body line at 2026-05-18T09:24:38Z. The 7-sister rollout being incomplete at that time was an explicit acknowledgement in the issue body — PR #3964 closed the architectural-tier issue (heartbeat coverage decision) while #3968 tracks the mechanical sister rollout. Plan now treats #3236 as "already closed" and AC5-followup becomes a verification (re-open with monitor-name list if any of the 8 monitors fails to report green within one cycle).
- **`scheduled-skill-freshness` cadence data gap.** Only one `workflow_dispatch` run in the last 12 attempts captured by `gh run list`. The 60→60 keep is a deliberate "insufficient signal" choice. Post-merge action: after the next monthly cron fire (next first-of-month at 02:00 UTC), re-check `checkin_margin_minutes` against the observed lag and bump if needed.
- **No new finding requires re-planning.** Single-class mechanical refactor × 7 workflows + 5-attribute IaC edit; all branch variants pre-specified, all reference shapes verified live.

## Summary

PR #3964 (commit `c04ffd33`) migrated `.github/workflows/scheduled-oauth-probe.yml` from the buggy two-step Sentry Crons check-in pattern (`in_progress → ok/error` with `|| true`-wrapped first POST and gated follow-up) to a single end-of-job heartbeat POST. Seven sister `scheduled-*.yml` workflows still carry the identical defect class (grep `'sentry-checkin-id-' .github/workflows/scheduled-*.yml` → 7 hits).

The defect manifestation is already in production: **Sentry alert `WEB-PLATFORM-4`** ("Cron failure: scheduled-github-app-drift-guard / A timeout check-in was detected / Last successful check-in: Never", project `web-platform`, env `production`) is the actively-firing trigger for this PR. The remaining 6 sister workflows fire daily/weekly so their silent-fail trap is bounded — Sentry noise is lower-frequency but the defect is identical.

This PR applies the canonical heartbeat shape verbatim to all 7 sisters and aligns each monitor's `checkin_margin_minutes` to observed GHA cron jitter (read from `gh run list --workflow=<file>.yml --limit 12`).

## User-Brand Impact

**If this lands broken, the user experiences:** continued operator-side Sentry email noise (false-positive "Last successful check-in: Never" pages, with `scheduled-github-app-drift-guard` already in alert state as WEB-PLATFORM-4) AND a degraded signal on the actual monitored conditions — if any of these 7 probes go truly dark, the persistent false-positive noise floor masks the real outage. The user-facing surfaces touched by the underlying probes (OAuth flow, realtime WS, community-monitor issue triage, terraform drift detection) are NOT modified — only the Sentry check-in plumbing is touched.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — this PR touches CI plumbing and observability monitor IaC only. No new processing of user data, no auth-flow change, no schema/secret rotation, no IAM grant. The 7 workflows continue to read their existing source surfaces (auth endpoints, GitHub App config, terraform plan output, etc.) under unchanged credentials.

**Brand-survival threshold:** none

`threshold: none, reason: PR touches CI plumbing (.github/workflows/scheduled-*.yml) and observability IaC only — no user-data processing, no auth surface, no schema/secret rotation. Sensitive-path regex hit on apps/web-platform/infra/sentry/cron-monitors.tf is a same-class edit as PR #3964 (#3811 chain) which carried the identical scope-out.`

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified) | Plan response |
| --- | --- | --- |
| All 7 sister workflows use a `failure_mode` step output. | Only 2 of 7 do: `scheduled-github-app-drift-guard.yml` (`steps.check.outputs.failure_mode`) and `scheduled-realtime-probe.yml` (`steps.probe.outputs.failure_mode`). The other 5 emit no structured failure mode. | Per-workflow heartbeat branch: 2 workflows branch on the `failure_mode` env mirror (matches oauth-probe canonical); 4 workflows branch on `${{ job.status }}` (`success` → `?status=ok`, anything else → `?status=error`); `scheduled-terraform-drift.yml` branches on `steps.plan.outputs.exit_code` (`0` → ok; `1` → error; `2` → ok because exit 2 = drift detected, which is the workflow's success path). |
| `checkin_margin_minutes` should follow oauth-probe's 5→30 bump for hourly. | Live `gh run list` over 12 fires per workflow reveals jitter spread of 2–4 h on daily schedules, 1–5 h on hourly (drift-guard), and overnight gaps up to 5 h. Current margins (`15` for drift-guard, `60` for dailies, `30` for terraform-drift, `60` for weekly/monthly) are mostly TOO TIGHT against observed reality. | Per-workflow bump derived from observed maximum gap × 1.2 safety, capped at the workflow's natural recurrence interval. See `### Per-monitor margin table` below. |
| `scheduled-content-vendor-drift.yml` has a probe step with `id:`. | No `^      - id:` step matched in run scope; the workflow uses `steps.detect.outputs.drift|route|labels` for routing, but the job-level success/failure is what Sentry should reflect. | Branch on `${{ job.status }}`. |
| `scheduled-terraform-drift.yml` should branch on a `failure_mode` output. | Workflow uses `steps.plan.outputs.exit_code` where `0`=clean, `1`=error, `2`=drift detected. Per the existing legacy Sentry shape (lines 248-264), `if: success()` posts ok and `if: failure()` posts error — meaning `exit 2` (drift) maps to OK because the workflow exit code is 0 even when drift is detected (only `exit_code == 1` triggers `if: failure()` via downstream step). | Branch on `${{ steps.plan.outputs.exit_code }}`: `0` or `2` → ok; `1` → error. Documents the semantic invariant explicitly. |
| Issue #3968 says "manually `gh issue close #3236` after all 8 monitors have reported successful check-ins". | Verified — issue #3968 body footer line 50; #3236 is the cross-workflow heartbeat coverage tracking issue. | Per-issue instruction noted as post-merge operator step in `## Post-merge` section; not folded into this PR per #3968 footer. |

## Implementation Phases

### Phase 0 — Preflight verification (no edits)

0.1. **Re-confirm the 7-workflow inventory.** Run:

```bash
grep -lE '"\$\{RUNNER_TEMP\}/sentry-checkin-id-' .github/workflows/scheduled-*.yml | sort
```

Expected: exactly the 7 files listed in `related_workflows`. If the count differs, abort and re-scope.

0.2. **Re-confirm cadence reality per workflow.** Run for each of the 7 files:

```bash
for f in scheduled-community-monitor scheduled-content-vendor-drift scheduled-daily-triage scheduled-github-app-drift-guard scheduled-realtime-probe scheduled-skill-freshness scheduled-terraform-drift; do
  echo "=== $f ==="
  gh run list --workflow=$f.yml --limit 12 --json createdAt,conclusion,event \
    | jq -r '.[] | "\(.createdAt) \(.event) \(.conclusion)"'
done
```

Observed cadences (captured at plan-write time, 2026-05-18):

| Workflow | `cron:` (UTC) | Observed jitter (max gap) | Current margin | Proposed margin | Rationale |
|---|---|---|---|---|---|
| `scheduled-community-monitor` | `0 8 * * *` | 09:18-11:17 fires, ~2h late max | 60 | 60 (keep) | Daily, observed jitter fits 60min |
| `scheduled-content-vendor-drift` | `17 11 * * MON` | 11:13-14:00 (one scheduled fire 2026-05-11T13:59) | 60 | 90 | Weekly with sparse data; small bump for safety |
| `scheduled-daily-triage` | `0 4 * * *` | 05:50-07:54 fires, ~4h late max | 60 | 240 | Daily, observed up to 4h after scheduled |
| `scheduled-github-app-drift-guard` | `0 * * * *` | gaps up to 5h overnight (00:01→05:09) | 15 | 180 | **Active alert source (WEB-PLATFORM-4)**; observed multi-hour overnight gaps swamp 15min |
| `scheduled-realtime-probe` | `0 7 * * *` | 08:46-09:44 fires, ~3h late max | 60 | 180 | Daily, observed up to ~3h after scheduled |
| `scheduled-skill-freshness` | `0 2 1 * *` | Only 1 dispatch run in history (no cron fires) | 60 | 60 (keep) | Monthly, insufficient data; defer adjustment to next cycle |
| `scheduled-terraform-drift` | `0 6,18 * * *` | 08:23-08:51, 19:07-19:57 fires, ~3h late max | 30 | 180 | Twice-daily, observed up to ~3h after scheduled |

**Why 240 min for daily-triage but 180 for realtime-probe**: triage's worst observed lag was 3h54m (2026-05-09 06:08:54 vs scheduled 04:00); rounding up to 4h × 1.0 safety factor = 240. Realtime-probe's worst was ~2h45m; rounded up = 180.

0.3. **Run actionlint baseline.** Capture pre-edit baseline for diff-clean assertion at AC time:

```bash
actionlint .github/workflows/scheduled-*.yml 2>&1 | tee /tmp/actionlint-pre.txt
```

0.4. **Read the canonical heartbeat shape from `c04ffd33`.** Reference shape lives in `.github/workflows/scheduled-oauth-probe.yml:528-559`. Copy verbatim per workflow with these substitutions:
- `MONITOR_SLUG` value → workflow's slug
- `FAIL_MODE` env source → per `### Per-workflow heartbeat shape` table below
- Heartbeat status branch → `failure_mode`-based, `job.status`-based, or `exit_code`-based per table

### Phase 1 — Apply heartbeat shape to all 7 workflows (TDD-style, one at a time)

For EACH of the 7 workflows, perform the same 4-step edit (this is mechanical, ~30 LOC removed + ~25 LOC added per file):

1. **DELETE the `Sentry check-in (in_progress)` step** (always near the top of the job, lines 37-71 ish). Use Edit tool with the exact YAML block as `old_string`.

2. **DELETE the `Sentry check-in (ok)` and `Sentry check-in (error)` steps** (always at the end of the job).

3. **INSERT a single `Sentry check-in (final)` step at the end of the job** with `if: always()`, `continue-on-error: true`, drop `|| true` from the curl, retain the three-secret guard with `::warning::` + `exit 0`. Match the oauth-probe canonical shape byte-for-byte except for the `MONITOR_SLUG`, `FAIL_MODE` source, and status-branch logic.

4. **Verify the inserted step's status branch** matches `### Per-workflow heartbeat shape` table below.

#### Per-workflow heartbeat shape table

| Workflow | Status source | Status branch logic |
|---|---|---|
| `scheduled-community-monitor.yml` | `job.status` | `status = (job.status == 'success') ? 'ok' : 'error'` |
| `scheduled-content-vendor-drift.yml` | `job.status` | Same as above |
| `scheduled-daily-triage.yml` | `job.status` | Same as above |
| `scheduled-github-app-drift-guard.yml` | `steps.check.outputs.failure_mode` AND `steps.tripwire.outcome` | `status = (FAIL_MODE == '' && TRIPWIRE != 'failure') ? 'ok' : 'error'` — preserves the leak-tripwire signal that the existing `notify` step already honors at workflow:449 |
| `scheduled-realtime-probe.yml` | `steps.probe.outputs.failure_mode` | Mirrors oauth-probe: `status = (FAIL_MODE == '') ? 'ok' : 'error'` |
| `scheduled-skill-freshness.yml` | `job.status` | Same as community-monitor |
| `scheduled-terraform-drift.yml` | `steps.plan.outputs.exit_code` | `status = (EXIT_CODE == '0' \|\| EXIT_CODE == '2') ? 'ok' : 'error'` — exit 2 means "drift detected", which is the workflow's success path (downstream filer creates issue); only exit 1 is a real error |

#### Canonical snippet (community-monitor variant, `job.status`-branched)

```yaml
      # Single end-of-job heartbeat check-in (Sentry Crons HTTP "heartbeat"
      # shape). Posts ?status=ok when job succeeded, ?status=error otherwise.
      # Replaces the prior two-step in_progress -> ok/error pattern whose
      # silent-fail trap (CHECKIN_ID tmpfile parsed via `jq -r '.id // empty'`,
      # gated `if` on the follow-up call) caused Sentry to never receive a
      # successful check-in. The curl drops `|| true` so its exit code lands
      # in the step log; `continue-on-error: true` preserves the property
      # that a Sentry-side blip does not red-flag an otherwise-green job.
      # See: docs.sentry.io/product/crons/getting-started/http/ (Heartbeat).
      - name: Sentry check-in (final)
        if: always()
        continue-on-error: true
        env:
          SENTRY_INGEST_DOMAIN: ${{ secrets.SENTRY_INGEST_DOMAIN }}
          SENTRY_PROJECT_ID: ${{ secrets.SENTRY_PROJECT_ID }}
          SENTRY_PUBLIC_KEY: ${{ secrets.SENTRY_PUBLIC_KEY }}
          MONITOR_SLUG: scheduled-community-monitor
          JOB_STATUS: ${{ job.status }}
        run: |
          set -u
          if [[ -z "${SENTRY_INGEST_DOMAIN:-}" || -z "${SENTRY_PROJECT_ID:-}" || -z "${SENTRY_PUBLIC_KEY:-}" ]]; then
            echo "::warning::Sentry Crons secrets not configured; skipping check-in."
            exit 0
          fi
          if [[ "${JOB_STATUS}" == "success" ]]; then
            status="ok"
          else
            status="error"
          fi
          curl --max-time 10 -fSs -X POST \
            "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/cron/${MONITOR_SLUG}/${SENTRY_PUBLIC_KEY}/?status=${status}"
```

#### Canonical snippet (drift-guard variant, dual-signal branch)

```yaml
      - name: Sentry check-in (final)
        if: always()
        continue-on-error: true
        env:
          SENTRY_INGEST_DOMAIN: ${{ secrets.SENTRY_INGEST_DOMAIN }}
          SENTRY_PROJECT_ID: ${{ secrets.SENTRY_PROJECT_ID }}
          SENTRY_PUBLIC_KEY: ${{ secrets.SENTRY_PUBLIC_KEY }}
          MONITOR_SLUG: scheduled-github-app-drift-guard
          FAIL_MODE: ${{ steps.check.outputs.failure_mode }}
          TRIPWIRE_OUTCOME: ${{ steps.tripwire.outcome }}
        run: |
          set -u
          if [[ -z "${SENTRY_INGEST_DOMAIN:-}" || -z "${SENTRY_PROJECT_ID:-}" || -z "${SENTRY_PUBLIC_KEY:-}" ]]; then
            echo "::warning::Sentry Crons secrets not configured; skipping check-in."
            exit 0
          fi
          if [[ -z "${FAIL_MODE:-}" && "${TRIPWIRE_OUTCOME:-}" != "failure" ]]; then
            status="ok"
          else
            status="error"
          fi
          curl --max-time 10 -fSs -X POST \
            "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/cron/${MONITOR_SLUG}/${SENTRY_PUBLIC_KEY}/?status=${status}"
```

#### Canonical snippet (terraform-drift variant, exit_code-branched)

```yaml
      - name: Sentry check-in (final)
        if: always()
        continue-on-error: true
        env:
          SENTRY_INGEST_DOMAIN: ${{ secrets.SENTRY_INGEST_DOMAIN }}
          SENTRY_PROJECT_ID: ${{ secrets.SENTRY_PROJECT_ID }}
          SENTRY_PUBLIC_KEY: ${{ secrets.SENTRY_PUBLIC_KEY }}
          MONITOR_SLUG: scheduled-terraform-drift
          PLAN_EXIT_CODE: ${{ steps.plan.outputs.exit_code }}
        run: |
          set -u
          if [[ -z "${SENTRY_INGEST_DOMAIN:-}" || -z "${SENTRY_PROJECT_ID:-}" || -z "${SENTRY_PUBLIC_KEY:-}" ]]; then
            echo "::warning::Sentry Crons secrets not configured; skipping check-in."
            exit 0
          fi
          # exit 0 = clean, exit 2 = drift detected (workflow success path —
          # downstream filer handles the issue/email), exit 1 = real error.
          if [[ "${PLAN_EXIT_CODE}" == "0" || "${PLAN_EXIT_CODE}" == "2" ]]; then
            status="ok"
          else
            status="error"
          fi
          curl --max-time 10 -fSs -X POST \
            "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/cron/${MONITOR_SLUG}/${SENTRY_PUBLIC_KEY}/?status=${status}"
```

### Phase 2 — Align `cron-monitors.tf` margins

2.1. **Edit `apps/web-platform/infra/sentry/cron-monitors.tf`** with per-resource margin bumps from the table in Phase 0.2:

| Resource | `checkin_margin_minutes` change |
|---|---|
| `scheduled_terraform_drift` | 30 → 180 |
| `scheduled_github_app_drift_guard` | 15 → 180 |
| `scheduled_daily_triage` | 60 → 240 |
| `scheduled_realtime_probe` | 60 → 180 |
| `scheduled_skill_freshness` | 60 → 60 (keep — insufficient data) |
| `scheduled_content_vendor_drift` | 60 → 90 |
| `scheduled_community_monitor` | 60 → 60 (keep — fits observed jitter) |

2.2. **Update the cron-monitors.tf header comment** (lines 31-37) to note the post-rollout state — all 8 monitors now use the single-heartbeat shape, so the `max_runtime_minutes` caveat at lines 39-45 now applies to all of them (not just oauth-probe + 7-pending). One-line edit.

2.3. **`terraform fmt`** on the file (use `terraform -chdir=apps/web-platform/infra/sentry fmt -check`).

### Phase 3 — Validation gates

3.1. **`actionlint`** on each touched workflow:

```bash
actionlint .github/workflows/scheduled-{community-monitor,content-vendor-drift,daily-triage,github-app-drift-guard,realtime-probe,skill-freshness,terraform-drift}.yml
```

Expected: exit 0, no new findings vs. `/tmp/actionlint-pre.txt`.

3.2. **`terraform validate`** on the Sentry root:

```bash
( cd apps/web-platform/infra/sentry && terraform init -backend=false -input=false && terraform validate )
```

3.3. **`grep`-gate on residual buggy pattern.** Final invariant from #3968 AC1:

```bash
grep -lE '"\$\{RUNNER_TEMP\}/sentry-checkin-id-' .github/workflows/scheduled-*.yml
```

Expected: zero hits.

3.4. **Heartbeat shape conformance grep** (positive assertion):

```bash
grep -cE '^      - name: Sentry check-in \(final\)$' .github/workflows/scheduled-*.yml
```

Expected: 8 (the 7 sisters in this PR + oauth-probe from #3964).

## Files to Edit

- `.github/workflows/scheduled-community-monitor.yml` — replace lines 54-71 (in_progress block) and 191-224 (ok/error blocks) with single end-of-job heartbeat step branched on `job.status`. Net ~-30/+25 LOC.
- `.github/workflows/scheduled-content-vendor-drift.yml` — replace lines 63-80 (in_progress) and 498-531 (ok/error) with single heartbeat branched on `job.status`. Net ~-30/+25 LOC.
- `.github/workflows/scheduled-daily-triage.yml` — replace lines 49-66 (in_progress) and 161-194 (ok/error) with single heartbeat branched on `job.status`. Net ~-30/+25 LOC.
- `.github/workflows/scheduled-github-app-drift-guard.yml` — replace lines 58-75 (in_progress) and 495-525 (ok/error) with single heartbeat branched on `steps.check.outputs.failure_mode` AND `steps.tripwire.outcome` (dual-signal preserves the leak-tripwire path that the existing `notify` step at line 449 already honors). Net ~-30/+27 LOC.
- `.github/workflows/scheduled-realtime-probe.yml` — replace lines 37-54 (in_progress) and 286-319 (ok/error) with single heartbeat branched on `steps.probe.outputs.failure_mode`. Mirrors oauth-probe canonical exactly. Net ~-30/+25 LOC.
- `.github/workflows/scheduled-skill-freshness.yml` — replace lines 45-62 (in_progress) and 162-195 (ok/error) with single heartbeat branched on `job.status`. Net ~-30/+25 LOC.
- `.github/workflows/scheduled-terraform-drift.yml` — replace lines 37-54 (in_progress) and 248-281 (ok/error) with single heartbeat branched on `steps.plan.outputs.exit_code` (0/2 → ok; 1 → error). Net ~-30/+27 LOC.
- `apps/web-platform/infra/sentry/cron-monitors.tf` — bump `checkin_margin_minutes` per Phase 2.1 table on 5 resources (terraform_drift, github_app_drift_guard, daily_triage, realtime_probe, content_vendor_drift); leave 2 unchanged (skill_freshness, community_monitor). Update header comment (lines 31-37) to note all 8 monitors are now heartbeat-shape post-rollout.

## Files to Create

None.

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in .github/workflows/scheduled-community-monitor.yml \
            .github/workflows/scheduled-content-vendor-drift.yml \
            .github/workflows/scheduled-daily-triage.yml \
            .github/workflows/scheduled-github-app-drift-guard.yml \
            .github/workflows/scheduled-realtime-probe.yml \
            .github/workflows/scheduled-skill-freshness.yml \
            .github/workflows/scheduled-terraform-drift.yml \
            apps/web-platform/infra/sentry/cron-monitors.tf; do
  jq -r --arg path "$path" '
    .[] | select(.body // "" | contains($path))
    | "#\(.number): \(.title)"
  ' /tmp/open-review-issues.json
done
```

Expected matches: #3968 itself (parent issue; this PR closes it). No other open code-review issues are expected to touch these files given the PR #3964 cleanup just landed.

**Disposition:** #3968 — Fold in (this PR's `Closes #3968` clause).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — pure CI/observability plumbing change. The change does not touch any of:
- Product/UX surfaces (no user-facing UI, no copy, no flow change)
- Legal/compliance regulated-data surfaces (no schema, auth, API route, SQL, or PII handling)
- Security boundary (no new permission, no new credential, no new IAM grant; existing `secrets.SENTRY_*` and `secrets.GITHUB_TOKEN` remain unchanged)
- Engineering architecture (single-file mechanical refactor × 7, no new dep, no API contract change)
- Finance (no Sentry seat creation — modifies existing monitor resources)
- Marketing/Sales/Design (no public surface touched)

## Infrastructure (IaC)

### Terraform changes

- File: `apps/web-platform/infra/sentry/cron-monitors.tf` — modify 5 `sentry_cron_monitor` resources (margin bumps only); no resource creation, no resource destruction.
- Provider: `jianyuan/sentry v0.15.0-beta2` (unchanged, locked in `.terraform.lock.hcl`).
- Sensitive variables: none new — uses existing `var.sentry_org` and `data.sentry_project.web_platform.slug`.

### Apply path

- **Cloud-init + idempotent bootstrap**: NOT applicable (no compute resources).
- **Auto-apply via `.github/workflows/apply-sentry-infra.yml`**: this PR's Terraform changes will apply automatically on push to `main` via the existing workflow (per `cron-monitors.tf` header lines 13-15). The auto-apply workflow is `-target=`-scoped to `sentry_cron_monitor.*` per PR #3811 (see learning `2026-05-15-terraform-import-only-beta-provider-schema-validation.md`), so margin bumps on existing resources apply cleanly.
- Expected downtime/blast radius: **zero**. Margin attribute changes are in-place updates on already-imported resources; Sentry's Cron Monitor API treats `checkin_margin_minutes` as a hot-reload setting.

### Distinctness / drift safeguards

- This config only describes prd-tier monitors (the Sentry org has no dev/staging equivalent in this repo). No `dev != prd` precondition needed.
- No `lifecycle.ignore_changes` additions — the resources being modified are apply-friendly (not the import-only `sentry_issue_alert` resources gated by `-target=` in `apply-sentry-infra.yml`).
- State storage: existing R2 backend (already in place per `apps/web-platform/infra/sentry/main.tf`); no changes.

### Vendor-tier reality check

- Sentry plan tier: existing org subscription supports unlimited Cron Monitor updates. No new monitor creation = no seat-quota concern (see learning `2026-05-15-sentry-iac-billing-and-quirks.md` — only NEW resources hit the seat-headroom check).

## Acceptance Criteria

Per issue #3968 the 5 ACs are authoritative. Listed verbatim with this plan's verification commands:

### Pre-merge (PR)

- [ ] **AC1.** `grep -lE '"\$\{RUNNER_TEMP\}/sentry-checkin-id-' .github/workflows/scheduled-*.yml` returns 0 hits.
- [ ] **AC2.** Each sister monitor's `checkin_margin_minutes` in `apps/web-platform/infra/sentry/cron-monitors.tf` matches the observed cadence from `gh run list --workflow=<file>.yml --limit 12` per Phase 0.2 table. Verify with:

  ```bash
  for resource in scheduled_terraform_drift scheduled_github_app_drift_guard scheduled_daily_triage scheduled_realtime_probe scheduled_content_vendor_drift; do
    grep -A1 "resource \"sentry_cron_monitor\" \"${resource}\"" apps/web-platform/infra/sentry/cron-monitors.tf \
      | grep "checkin_margin_minutes"
  done
  ```

  Expected values: `terraform_drift=180`, `github_app_drift_guard=180`, `daily_triage=240`, `realtime_probe=180`, `content_vendor_drift=90`.

- [ ] **AC3.** `actionlint` passes on each touched workflow with no new shellcheck findings vs. `/tmp/actionlint-pre.txt` baseline:

  ```bash
  actionlint .github/workflows/scheduled-{community-monitor,content-vendor-drift,daily-triage,github-app-drift-guard,realtime-probe,skill-freshness,terraform-drift}.yml
  ```

- [ ] **AC4.** `terraform validate` passes on `apps/web-platform/infra/sentry/`:

  ```bash
  ( cd apps/web-platform/infra/sentry && terraform init -backend=false -input=false && terraform validate )
  ```

- [ ] **AC6 (plan-added).** Positive heartbeat-shape conformance: `grep -cE '^      - name: Sentry check-in \(final\)$' .github/workflows/scheduled-*.yml` returns 8 (oauth-probe + 7 sisters).

- [ ] **AC7 (plan-added).** Each Sentry-checkin block drops `|| true` from the curl. Fixed-string check (single shape used in canonical heartbeat):

  ```bash
  grep -nF '?status=${status}" || true' .github/workflows/scheduled-*.yml
  ```

  Expected: zero hits. Note — the regex shape is byte-identical to the marker the heartbeat block REMOVES, per the regex-shape-alignment rule in `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md` line 112 (plan-time enumeration grep MUST use the EXACT shape the post-edit sentinel grep will use).

- [ ] **AC8 (plan-added).** Each Sentry-checkin block retains the three-secret guard with `::warning::` + `exit 0`: `grep -cE '::warning::Sentry Crons secrets not configured' .github/workflows/scheduled-*.yml` returns 8.

### Post-merge (operator)

- [ ] **AC5.** After merge + apply, each monitor's "Last successful check-in" advances within one cron cycle. Verify via Sentry UI (project `web-platform`, Cron Monitors section) — each of the 8 monitors must show a successful check-in within its scheduled cadence + new margin window. Specifically: WEB-PLATFORM-4 (drift-guard "Last successful check-in: Never") must auto-resolve within one hourly cycle (~3h max given the new 180-min margin).
- [ ] **AC5-followup.** Issue #3236 was already closed at #3964 merge time (`Closes #3236.` in PR body, verified `closedAt: 2026-05-18T09:24:38Z`). The footer prose in #3968 telling the operator to manually close #3236 is therefore stale. **Action:** verify #3236 remains closed AND that all 8 monitors are green in Sentry UI. If any monitor remains stale beyond its cycle+margin window, RE-OPEN #3236 with `gh issue reopen 3236 --comment "Sister-rollout #<this-PR> merged but monitor(s) <name-list> still stale — heartbeat plumbing or margin sizing needs follow-up."` Do NOT issue a second close; the issue is already in the desired terminal state from the architectural-tier perspective.

## Open questions

None — the migration is fully mechanical and all branch-condition variants are pre-specified per workflow.

## Sharp Edges

- **`steps.terraform-drift.plan.outputs.exit_code` semantics inversion.** `terraform plan -detailed-exitcode` returns 0 (clean), 1 (error), or 2 (drift detected). In this workflow, exit 2 is the SUCCESS path (drift is the signal the workflow exists to detect) — only exit 1 is a true error. The heartbeat branch MUST treat exit 2 as `ok`, NOT `error`. Implementer: re-read `scheduled-terraform-drift.yml:131,137,206,241` (the `if: steps.plan.outputs.exit_code == '2'` / `!= '0'` gates) before writing the branch to confirm this invariant still holds.
- **`scheduled-github-app-drift-guard.yml` has a dual-signal failure mode.** The workflow's `notify` step at line 449 fires on `steps.check.outputs.failure_mode != '' || steps.tripwire.outcome == 'failure'` — both signals are operator-paged. The Sentry heartbeat MUST mirror this OR, not just `failure_mode`, or a leak-tripwire-only failure would silently report `ok` to Sentry. Per the canonical snippet in Phase 1 above.
- **Only 2 of 7 workflows have a `preflight → <work>` two-job structure:**
  - `scheduled-community-monitor.yml`: `preflight` (line 34) + `monitor` (verified — second job has `if: needs.preflight.outputs.ok == 'true'` at line 50).
  - `scheduled-daily-triage.yml`: `preflight` (line 29) + `daily-triage` (line 43, gated at line 45 with same `if:` clause).
  - The heartbeat MUST live in the SECOND job (the one that actually does the work). The legacy `in_progress`/`ok`/`error` steps in these two files are ALREADY scoped to the second job — preserve that placement.

  The other 5 workflows have a SINGLE job each — heartbeat lives in that single job:
  - `scheduled-content-vendor-drift.yml`: `drift-detect` (line 52).
  - `scheduled-realtime-probe.yml`: `probe` (line 33).
  - `scheduled-skill-freshness.yml`: `aggregate` (line 37).
  - `scheduled-terraform-drift.yml`: `drift-check` (line 27).
  - `scheduled-github-app-drift-guard.yml`: `drift-check` (line 53).
- **`actionlint` may report new shellcheck findings on the inserted curl line.** The canonical snippet uses `${var}` expansions inside a double-quoted URL — shellcheck's SC2086 may fire even though `set -u` covers the unset case. Match oauth-probe's working byte-for-byte to inherit its passing actionlint status.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's threshold is `none` with explicit scope-out — verified non-empty.
- **`scheduled-skill-freshness.yml` monthly schedule has insufficient `gh run list` history.** Only one workflow_dispatch run in the last 12 attempts (no successful cron fire captured). The 60→60 margin is a defer-to-next-cycle choice — once a real monthly fire lands and a cadence sample exists, revisit. Tracked as a footnote in `## Post-merge` section but NOT a blocking AC.
- **Auto-apply will fire on PR merge.** `.github/workflows/apply-sentry-infra.yml` runs on push to `main` and applies the Sentry IaC changes automatically. Margin bumps are hot-reload at the Sentry API level — no operator action needed; AC5 verification window is one cron cycle per monitor (so 1h for hourly, 24h for daily, 7d for weekly, 30d for monthly).

## Out of Scope

- The 7 workflows' business logic (only touch the Sentry check-in plumbing + the relevant cron-monitors.tf entry — explicit in #3968 body).
- Closing #3236 (post-merge manual step after all 8 monitors green, per #3968 footer).
- Migrating `scheduled-cf-token-expiry-check.yml` to the heartbeat shape (its `schedule:` block is currently commented out per `cron-monitors.tf` lines 71-77 breadcrumb; out of #3968's 7-file scope).
- Adjusting `failure_issue_threshold` (sized correctly already per `cron-monitors.tf` lines 24-29 header).
- Migrating `max_runtime_minutes` semantics (per `cron-monitors.tf` lines 39-45 — heartbeat-only mode leaves this attribute decorative; carried for sibling consistency, not removed).
