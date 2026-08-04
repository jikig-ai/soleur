#!/usr/bin/env bash
# infra-config-red-alert.sh — actionable, no-SSH alert when the infra-config delivery gate reds
# (#7220). SOURCED by .github/workflows/apply-deploy-pipeline-fix.yml.
#
# WHY THIS EXISTS RATHER THAN REUSING seccomp_unenforced_alert.
#
# The first version of the #7220 alert step called `seccomp_unenforced_alert` with an
# infra-config detail string, on the reasoning that the TRANSPORT (issue + Sentry) was worth
# reusing. The transport was; the IDENTITY was not, and only `detail` is a parameter there.
# Review measured what the operator would actually have received:
#
#   * an issue TITLED "Security profile (seccomp) not enforced on the server", whose body says
#     the container sandbox is running with a wider system-call surface than intended — a
#     fabricated security claim for what is a config-delivery failure;
#   * a remediation ("re-run the workflow once the image pull path is healthy") that cannot work
#     for a deterministic handler fault, so it loops forever;
#   * a dedupe key of `ci/seccomp-unenforced`, so an open seccomp incident SWALLOWS this alert as
#     a comment — and vice versa. Two independent P1 classes, one slot;
#   * a Sentry event tagged feature:agent-sandbox op:seccomp-remediation-failed, paging the
#     dedicated seccomp rule.
#
# `operator-digest` harvests action-required issues by TITLE, so the one surface this alert
# exists to serve would have shown a non-technical founder a security breach that did not
# happen. That is the same "the annotation was two-thirds false" harm #7220 is about,
# reproduced one layer up. Hence a sibling with its own label, title, body and tags.
#
# FAIL-OPEN by contract: this runs on the failure path, so a telemetry hiccup must never mask
# the real failure or abort the caller's shell. Every external call is guarded; always returns 0.
#
# Env: SENTRY_INGEST_DOMAIN / SENTRY_PROJECT_ID / SENTRY_PUBLIC_KEY (Sentry emit skipped if any
# is unset); INFRA_CONFIG_ALERT_RUN_URL / INFRA_CONFIG_ALERT_SHA (context); GH_TOKEN for `gh`.

infra_config_red_alert() {
  # $1 = one-line technical detail. $2 = "reachable" | "unreachable".
  # The second argument is load-bearing and is why this is not a one-arg function: when the
  # status endpoint is DOWN (000/502/503), the gate's own recovery guidance is the opposite of
  # the reachable case, and an alert that contradicts the gate is worse than no alert.
  local detail="${1:-unspecified}"
  local reach="${2:-reachable}"
  local run_url="${INFRA_CONFIG_ALERT_RUN_URL:-}"
  local sha="${INFRA_CONFIG_ALERT_SHA:-}"

  local op="infra-config-gate-red"
  [[ "$reach" == "unreachable" ]] && op="infra-config-listener-down"

  if [[ -n "${SENTRY_INGEST_DOMAIN:-}" && -n "${SENTRY_PROJECT_ID:-}" && -n "${SENTRY_PUBLIC_KEY:-}" ]]; then
    local payload=""
    payload="$(jq -n --arg d "$detail" --arg op "$op" \
      '{message: ("infra-config delivery gate RED: " + $d),
        level: "error", platform: "other", logger: "apply-deploy-pipeline-fix",
        tags: {feature: "infra-config", op: $op},
        extra: {detail: $d}}' 2>/dev/null || true)"
    if [[ -n "$payload" ]]; then
      curl -s -o /dev/null --max-time 10 -X POST \
        "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/store/" \
        -H "Content-Type: application/json" \
        -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=${SENTRY_PUBLIC_KEY}" \
        -d "$payload" 2>/dev/null || echo "::warning::infra-config-red: Sentry POST failed"
    fi
  fi

  local existing=""
  existing="$(gh issue list --label ci/infra-config-red --state open \
    --json number --jq '.[0].number // empty' 2>/dev/null || true)"

  if [[ -n "$existing" ]]; then
    gh issue comment "$existing" \
      --body "Recurred${sha:+ on \`${sha}\`} — ${detail}.${run_url:+ CI run: ${run_url}}" \
      2>/dev/null || echo "::warning::infra-config-red: failed to comment on #${existing}"
  else
    # Two bodies, because the two states need OPPOSITE advice. Emitting the reachable text on an
    # unreachable listener is what would tell the operator not to pull the exact lever the gate
    # just told them to pull.
    local body
    if [[ "$reach" == "unreachable" ]]; then
      body="$(cat <<EOF
The server's config-delivery channel did not answer, and the automatic check just failed.

**What this means:** the small service that receives configuration updates on the production server is not responding. The website itself is a separate system and stays up — but until this is restored, configuration changes cannot reach the server, *and this is also the channel used to repair it remotely*.

**What happens next:** this one does need a decision from you, because the safe repair path depends on why it is not answering. Reply on this issue and an engineer/agent will pick it up; the CI run linked below records exactly what was tried.

**Detail:** ${detail}${sha:+
**Commit:** \`${sha}\`}${run_url:+
**CI run:** ${run_url}}
EOF
)"
    else
      body="$(cat <<EOF
A configuration update did not finish applying on the production server.

**What this means:** the files themselves reached the server. What did not happen is the step that makes the server *start using* them. The website stays up and no customer data is affected — this is an internal update that stalled partway.

**What happens next:** no manual server access is needed, and **nothing needs re-provisioning**. The CI run linked below names the exact line the update stopped at. This issue auto-updates if it recurs; close it once an update completes cleanly.

**Detail:** ${detail}${sha:+
**Commit:** \`${sha}\`}${run_url:+
**CI run:** ${run_url}}
EOF
)"
    fi
    # Idempotent label bootstrap — `gh issue create` HARD-FAILS on an unknown label, and this
    # function is fail-open, so a missing label would silently drop the PRIMARY operator surface
    # down to an invisible CI ::warning::. Same reasoning as the seccomp precedent.
    gh label create ci/infra-config-red --color B60205 \
      --description "infra-config delivery gate red; config reached the host but did not activate (#7220)" \
      2>/dev/null || true
    gh label create domain/engineering 2>/dev/null || true
    gh label create priority/p1-high 2>/dev/null || true
    local title="Server config update did not finish applying — the site is up"
    [[ "$reach" == "unreachable" ]] && title="Server config channel is not responding — needs a decision"
    gh issue create \
      --label ci/infra-config-red --label domain/engineering --label priority/p1-high \
      --title "$title" \
      --body "$body" \
      2>/dev/null || echo "::warning::infra-config-red: failed to file ci/infra-config-red issue"
  fi
  return 0
}

# Direct-exec convenience: `infra-config-red-alert.sh "<detail>" [reachable|unreachable]`.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  infra_config_red_alert "${1:-}" "${2:-reachable}"
fi
