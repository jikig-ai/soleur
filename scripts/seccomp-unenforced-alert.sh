#!/usr/bin/env bash
# seccomp-unenforced-alert.sh — actionable, no-SSH alert when the item-4 seccomp
# remediation redeploy terminally fails, leaving the running container's seccomp profile
# UNENFORCED (#6512, ADR-079 Fix 2a). SOURCED by
# .github/workflows/apply-deploy-pipeline-fix.yml AND scripts/seccomp-unenforced-alert.test.sh.
#
# WHY two surfaces: a red CI job among a page of green is invisible to a non-technical
# founder (the #6454/#6512 shape). operator-digest harvests action-required GitHub issues —
# never PR bodies or red jobs — so the GitHub issue is the primary operator-readable surface;
# the Sentry event is the secondary alerting plane.
#   1. Plain-language GitHub issue (label ci/seccomp-unenforced), deduped to ONE open issue
#      at a time — comment on the open one if present, else create.
#   2. Sentry event (feature:agent-sandbox op:seccomp-remediation-failed) → the dedicated
#      seccomp_remediation_failed issue-alert (apps/web-platform/infra/sentry/issue-alerts.tf).
#      This is an EVENT-driven emit, deliberately NOT a cron-monitor check-in — an event-driven
#      check-in to a cadence monitor's slug resets its missed-check-in clock and masks a
#      genuinely-missed scheduled beat (code-simplicity MEDIUM).
#
# FAIL-OPEN by contract: this runs on the failure path immediately before the workflow's own
# `exit 1`, so a telemetry hiccup must NEVER mask the real failure or abort the caller's
# strict-mode (`set -euo pipefail`) shell. Every external call is guarded; the function always
# returns 0.
#
# Env (all optional except a working `gh`): SENTRY_INGEST_DOMAIN / SENTRY_PROJECT_ID /
# SENTRY_PUBLIC_KEY (Sentry emit skipped if any is unset); SECCOMP_ALERT_RUN_URL /
# SECCOMP_ALERT_SHA (context woven into the issue body / recurrence comment); GH_TOKEN for `gh`.

seccomp_unenforced_alert() {
  local detail="${1:-unspecified}"
  local run_url="${SECCOMP_ALERT_RUN_URL:-}"
  local sha="${SECCOMP_ALERT_SHA:-}"

  # 1. Sentry event (dedicated seccomp_remediation_failed issue-alert). Fail-open.
  if [[ -n "${SENTRY_INGEST_DOMAIN:-}" && -n "${SENTRY_PROJECT_ID:-}" && -n "${SENTRY_PUBLIC_KEY:-}" ]]; then
    local payload=""
    payload="$(jq -n --arg d "$detail" \
      '{message: ("seccomp remediation redeploy failed — running container left UNENFORCED: " + $d),
        level: "error", platform: "other", logger: "apply-deploy-pipeline-fix",
        tags: {feature: "agent-sandbox", op: "seccomp-remediation-failed"},
        extra: {detail: $d}}' 2>/dev/null || true)"
    if [[ -n "$payload" ]]; then
      curl -s -o /dev/null --max-time 10 -X POST \
        "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/store/" \
        -H "Content-Type: application/json" \
        -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=${SENTRY_PUBLIC_KEY}" \
        -d "$payload" 2>/dev/null || echo "::warning::seccomp-unenforced: Sentry POST failed"
    fi
  fi

  # 2. Plain-language GitHub issue (the operator-readable surface). Dedupe: at most one open
  #    ci/seccomp-unenforced issue — comment on it if present, else create a fresh one.
  local existing=""
  existing="$(gh issue list --label ci/seccomp-unenforced --state open \
    --json number --jq '.[0].number // empty' 2>/dev/null || true)"

  if [[ -n "$existing" ]]; then
    gh issue comment "$existing" \
      --body "Recurred${sha:+ on \`${sha}\`} — ${detail}.${run_url:+ CI run: ${run_url}}" \
      2>/dev/null || echo "::warning::seccomp-unenforced: failed to comment on #${existing}"
  else
    local body
    body="$(cat <<EOF
The security profile that isolates tenant agent sessions on the production server is **not being enforced**, and the automatic fix just failed.

**What this means:** the container sandbox is running with a wider system-call surface than intended — a security-hardening gap. The website itself stays up; there is no user-facing outage.

**What happens next:** no manual server access is needed. Re-running the **Apply deploy-pipeline-fix** workflow (via *Run workflow*), once the image pull path is healthy, will re-enforce the profile. This issue auto-updates if the failure recurs; close it once the profile is enforced again.

**Detail:** ${detail}${sha:+
**Commit:** \`${sha}\`}${run_url:+
**CI run:** ${run_url}}
EOF
)"
    gh issue create \
      --label ci/seccomp-unenforced --label domain/engineering --label priority/p1-high \
      --title "Security profile (seccomp) not enforced on the server — auto-remediation failed" \
      --body "$body" \
      2>/dev/null || echo "::warning::seccomp-unenforced: failed to file ci/seccomp-unenforced issue"
  fi
  return 0
}

# Direct-exec convenience: `seccomp-unenforced-alert.sh "<detail>"`.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  seccomp_unenforced_alert "${1:-}"
fi
