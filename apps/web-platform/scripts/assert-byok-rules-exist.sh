#!/usr/bin/env bash
# Issue-alert detector liveness assertion (#4656 item 5; extended #4849).
#
# Asserts the expected `sentry_issue_alert` rules exist in Sentry by name via a
# READ-ONLY project rules-list GET. A silent mis-wire — a dropped `-target` in
# the apply workflow, a deleted/muted rule, or a name drift — is otherwise
# invisible until a real incident fails to page. For `byok-art-33-breach` that
# means the GDPR Art. 33(1) 72-hour notification clock never starts; for
# `chat-message-save-failure` (#4849) it means an interactive-message-save
# outage goes un-paged (both single-user-incident threshold).
#
# Wired as a post-apply step in apply-sentry-infra.yml so every apply that
# touches issue-alerts.tf re-proves all expected rules are live.
#
# READ-ONLY by design (plan D2): emits NO synthetic `op=canary` breach event.
# A fake breach would inject false Art. 33 audit residue into the single-user
# GDPR surface and could itself page. Existence-by-name is the deterministic,
# side-effect-free liveness signal.
#
# SCOPE — existence-by-name, deliberately NOT filter-shape. The rule's
# `conditions_v2`/`filters_v2`/`actions_v2` are Terraform-owned (only
# `environment` is in `lifecycle.ignore_changes`), and this assertion runs
# POST-apply in the same workflow — so immediately after `terraform apply`
# re-writes the filters from source, a rule's tag filters are guaranteed
# correct. Tag-drift (a UI edit that leaves the rule present but renames a
# `tagged_event` key) between applies is therefore self-healing on the next
# apply; the residual window (out-of-band UI mute/drift undetected until the
# next apply) is covered by the deferred recurring-liveness-cron option (plan
# Phase 3.2, gated on review judgment). Name-matching is safe here because the
# failure mode this gate catches is ABSENCE — a duplicate name still passes,
# which is the correct (fail-open-to-present) direction for an existence check.
#
# Required env: SENTRY_AUTH_TOKEN, SENTRY_ORG, SENTRY_PROJECT, SENTRY_API_HOST.
# Test injection (assert-byok-rules-exist.test.sh ONLY):
#   SENTRY_FIXTURE_RULES — file path; served instead of the live GET.

set -euo pipefail

# Fail-loud on a cleared/misconfigured org secret (no silent default) — a wrong
# org would query the wrong project and produce a false liveness verdict. The
# workflow always passes `secrets.SENTRY_ORG`; this guards the empty-secret case.
: "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN must be set}"
: "${SENTRY_ORG:?SENTRY_ORG must be set}"
: "${SENTRY_PROJECT:?SENTRY_PROJECT must be set}"

# The issue-alert rules this control depends on. Names are the `name` attribute
# of the `sentry_issue_alert` resources in
# apps/web-platform/infra/sentry/issue-alerts.tf.
EXPECTED_RULES=("byok-art-33-breach" "byok-cap-exceeded" "chat-message-save-failure" "workspace-sync-health")

fetch_rules() {
  if [[ -n "${SENTRY_FIXTURE_RULES:-}" ]]; then
    cat "$SENTRY_FIXTURE_RULES"
    return
  fi
  # Project issue-alert rules list — NOT the org `/monitors/` (Crons) endpoint,
  # which excludes issue alerts. `--max-time` bounds the call; `-fsS` fails on
  # 4xx/5xx so an auth/region error surfaces as a non-zero exit, not a parsed
  # error body.
  : "${SENTRY_API_HOST:?SENTRY_API_HOST must be set (org-subdomain, e.g. jikigai.sentry.io)}"
  curl -fsS --max-time 10 \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    "https://${SENTRY_API_HOST}/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/rules/"
}

rules_json="$(fetch_rules)"

# Fail closed on a non-array payload (Sentry error envelopes are objects).
if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$rules_json"; then
  echo "ERROR: Sentry rules response is not a JSON array — auth/region/endpoint failure. Cannot assert BYOK rule liveness." >&2
  printf '%s\n' "$rules_json" | head -c 500 >&2
  exit 1
fi

missing=()
for rule in "${EXPECTED_RULES[@]}"; do
  if ! jq -e --arg n "$rule" 'any(.[]; .name == $n)' >/dev/null 2>&1 <<<"$rules_json"; then
    missing+=("$rule")
  fi
done

if (( ${#missing[@]} > 0 )); then
  echo "ERROR: issue-alert liveness assertion FAILED — rule(s) absent in Sentry: ${missing[*]}" >&2
  echo "A silent mis-wire (dropped -target, deleted/muted rule, or name drift) leaves the named control un-paged: byok-art-33-breach → the GDPR Art. 33(1) 72h clock never starts; chat-message-save-failure → message-save outage un-paged; workspace-sync-health → diverged/stale workspace KB clone (and probe self-failure) un-paged. Refs #4656 item 5, #4849, #4882." >&2
  exit 1
fi

echo "[ok] issue-alert liveness: all expected rules present in Sentry (${EXPECTED_RULES[*]})."
