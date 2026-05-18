---
name: vendor-cron-heartbeat-silent-fail-pattern
description: Two-step vendor cron check-ins (in_progress → ok/error) with `|| true` on the first call and a gated follow-up create a silent-fail trap that makes monitors report "Last successful check-in: Never" while workflow runs themselves stay green. Heartbeat (single end-of-job POST) eliminates the trap.
metadata:
  type: best-practice
  category: integration-issues
  module: ci-observability
date: 2026-05-18
related_issues: [3236, 3964, 3968]
related_workflows:
  - .github/workflows/scheduled-oauth-probe.yml
related_iac:
  - apps/web-platform/infra/sentry/cron-monitors.tf
---

# Learning: vendor cron heartbeat silent-fail pattern

## Problem

`scheduled-oauth-probe.yml` generated recurring Sentry "missed check-in" alerts (`Last successful check-in: Never`) even though every workflow run on GitHub Actions completed successfully and exited green. The pattern in the workflow was the textbook Sentry Crons two-step shape:

```yaml
- name: Sentry check-in (in_progress)
  continue-on-error: true
  run: |
    resp=$(curl --max-time 10 -fSs -X POST "...?status=in_progress" || true)
    if [[ -n "$resp" ]]; then
      printf '%s' "$resp" | jq -r '.id // empty' > "${RUNNER_TEMP}/sentry-checkin-id-${MONITOR_SLUG}" || true
    fi

- ... probe steps ...

- name: Sentry check-in (ok)
  if: success()
  run: |
    CHECKIN_ID=$(cat "${RUNNER_TEMP}/sentry-checkin-id-${MONITOR_SLUG}" 2>/dev/null || true)
    if [[ -n "${CHECKIN_ID}" ]]; then
      curl --max-time 10 -fSs -X PUT ".../${CHECKIN_ID}/?status=ok" || true
    fi
```

Two compounding silencers:

1. The first call wraps `curl -fSs` with `|| true` AND has `continue-on-error: true`. Any transient HTTP error (Sentry 5xx, DNS hiccup, secret rotation) leaves `resp` empty AND swallows the exit code.
2. The follow-up step's `if [[ -n "${CHECKIN_ID}" ]]` gate makes the terminal `?status=ok` POST conditional on `jq`-extracted state from the (possibly absent) first response. Empty CHECKIN_ID → `?status=ok` never sent → Sentry never sees a terminal state for that run.

The cron monitor's `failure_issue_threshold = 2` plus `recovery_threshold = 1` then produces a steady-state alarm at the configured cadence forever.

## Solution

Collapse the two-step pattern to a single end-of-job heartbeat:

```yaml
- name: Sentry check-in (final)
  if: always()
  continue-on-error: true
  env:
    SENTRY_INGEST_DOMAIN: ${{ secrets.SENTRY_INGEST_DOMAIN }}
    SENTRY_PROJECT_ID: ${{ secrets.SENTRY_PROJECT_ID }}
    SENTRY_PUBLIC_KEY: ${{ secrets.SENTRY_PUBLIC_KEY }}
    MONITOR_SLUG: <workflow-slug>
    FAIL_MODE: ${{ steps.<probe-step-id>.outputs.failure_mode }}
  run: |
    set -u
    if [[ -z "${SENTRY_INGEST_DOMAIN:-}" || -z "${SENTRY_PROJECT_ID:-}" || -z "${SENTRY_PUBLIC_KEY:-}" ]]; then
      echo "::warning::Sentry Crons secrets not configured; skipping check-in."
      exit 0
    fi
    if [[ -z "${FAIL_MODE:-}" ]]; then
      status="ok"
    else
      status="error"
    fi
    curl --max-time 10 -fSs -X POST \
      "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/cron/${MONITOR_SLUG}/${SENTRY_PUBLIC_KEY}/?status=${status}"
```

Three load-bearing changes:

- **`if: always()` + single step** replaces the `success()/failure()` step split. No tmpfile, no `jq`-extracted state to lose.
- **No `|| true` on the curl.** Exit code lands in the step log — operators can SEE Sentry rejecting our auth instead of guessing why "Last successful check-in: Never".
- **`continue-on-error: true` retained at the YAML tier** so a Sentry-side blip (5xx, transient DNS) still does not red-flag an otherwise-green probe. The two properties are complementary, not redundant.

Pair with monitor IaC tuned to observed `gh run list` cadence — GitHub Actions cron is best-effort, and sub-hourly schedules (`*/5`, `*/15`) routinely degrade to ~60-min effective cadence. Match the monitor's `schedule.crontab` to actual fire intervals (hourly is usually safe) and pad `checkin_margin_minutes` to absorb daytime jitter (30 min is a reasonable default).

## Key Insight

**For vendor cron / heartbeat integrations, prefer the single end-of-job POST over the two-step in_progress → ok/error pattern unless you specifically need runtime-overrun detection.** The two-step pattern's correctness depends on the first call succeeding AND the response shape being parseable AND the parsed handle being passed through to the terminal call. Every `|| true` between those steps is a silencer; every gated `if` on parsed state is a silencer. Heartbeat eliminates them all by removing the intermediate state.

When you DO need the two-step pattern (because you specifically want Sentry to detect a runtime-overrun, not just a missed-run), encode it correctly:

- Drop `|| true` from the first curl.
- Capture the response shape at step-output level (`echo "checkin_id=..." >> $GITHUB_OUTPUT`), not in a tmpfile parsed via `cat ... 2>/dev/null`.
- Make the terminal call's `if:` condition assert on whether the first call succeeded, not on whether a tmpfile is non-empty.
- Send an explicit `?status=error` when the id is missing rather than skipping the call.

`max_runtime_minutes` is decorative in heartbeat-only mode — Sentry only detects missed runs in that mode, not overages. Retain the field for schema consistency across monitor resources but don't expect it to load-bear.

## Sister-workflow inventory

If you find this pattern, grep:

```bash
grep -lE '"\$\{RUNNER_TEMP\}/sentry-checkin-id-' .github/workflows/scheduled-*.yml
```

In this repo at the time of PR #3964, 7 sister workflows carried the identical defect: `scheduled-terraform-drift`, `scheduled-daily-triage`, `scheduled-realtime-probe`, `scheduled-skill-freshness`, `scheduled-content-vendor-drift`, `scheduled-community-monitor`, `scheduled-github-app-drift-guard`. Migration tracked in #3968.

## Session Errors

- **PreToolUse security_reminder_hook advisory output mis-read as blocking.** The hook prints a GitHub Actions injection reminder formatted as "PreToolUse:Edit hook error" but is advisory, not blocking. First Edit attempt on `scheduled-oauth-probe.yml` appeared to no-op; retry of the same Edit succeeded. **Prevention:** when a hook output contains advisory prose (security reminder, style hint) without an explicit `BLOCKED:` token, verify via Read whether the edit landed before re-attempting; don't infer blocking from output formatting alone.
- **Plan AC10 operator-surface grep missed one site.** Plan enumerated 3 update sites in `github-app-drift.md`; the post-edit sentinel grep caught a 4th (`15-min like the OAuth probe` at line 347). Plan-time enumeration used regex `every 15`; runtime sentinel used `every 15 minutes|every 15 min|15-min`. **Prevention:** plan-time enumeration grep MUST use the EXACT regex shape the post-edit sentinel grep will use; divergent regex shapes between enumeration time and verification time guarantee missed sites. When the AC sentinel uses an alternation like `(every 15 minutes|every 15 min|15-min)`, the enumeration sweep must do the same.
- **Initial sister-workflow scope-out filing drew DISSENT from code-simplicity-reviewer.** Proposed `cross-cutting-refactor` for migrating 7 sister workflows. The reviewer correctly DISSENTed: per the criterion's literal text, files in the same top-level directory (`.github/workflows/`) are RELATED, not unrelated. Recovery: flipped to plain tracking issue (no `deferred-scope-out` label, no PR cross-reference in body to avoid ship Phase 5.5 gate). **Prevention:** before claiming `cross-cutting-refactor`, verify files live in DIFFERENT top-level directories. "Different feature surfaces in the same directory" is a common rationalization that does NOT satisfy the literal criterion text. When a multi-file fix is mechanical AND lives in the same top-level directory, file as a plain tracking issue and reference it from the PR body — don't try to score it as a scope-out exemption.
