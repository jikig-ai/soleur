#!/usr/bin/env bash
# Issue-alert detector liveness assertion (#4656 item 5; extended #4849).
#
# Asserts the expected `sentry_issue_alert` rules exist in Sentry by name via a
# READ-ONLY org workflows-list GET. A silent mis-wire — a dropped `-target` in
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
# SCOPE — existence-by-name, deliberately NOT filter-shape. Name-matching is
# safe here because the failure mode this gate catches is ABSENCE — a duplicate
# name still passes, which is the correct (fail-open-to-present) direction for
# an existence check.
#
# Corrected 2026-08-19 (#7590). This block used to justify the narrow scope by
# claiming the rule's `conditions_v2`/`filters_v2`/`actions_v2` are
# "Terraform-owned (only `environment` is in `lifecycle.ignore_changes`)", and
# concluded that tag-drift is "self-healing on the next apply". Both are false.
# `infra/sentry/issue-alerts.tf` declares those attributes as `[]` and lists
# `conditions_v2, filters_v2, actions_v2, environment, frequency` in
# `ignore_changes` — so Terraform does NOT own the filters and an apply cannot
# restore them. That is not theoretical: on 2026-06-02 all four rules drifted to
# empty filters and matched every issue in the project, and the repair was a
# manual re-PUT of the `configure-sentry-alerts.sh` definitions, not an apply.
# The recurrence guard is #4781 (OPEN). Existence-by-name remains the right
# scope for THIS script; only the reason is corrected.
#
# SCOPE — org-wide since #7590, previously project-scoped. The replacement
# endpoint (below) is org-scoped and its payload carries no project binding, so
# a same-named rule in a different project now satisfies this assertion. That
# is the same scope dissolution ADR-031 records for the audit script; it is
# accepted here for the same reason (this org has one project) and is stated
# rather than left for the next reader to discover from the URL.
#
# Required env: SENTRY_AUTH_TOKEN, SENTRY_ORG, SENTRY_API_HOST.
# Test injection (assert-byok-rules-exist.test.sh ONLY):
#   SENTRY_FIXTURE_RULES — file path; served instead of the live GET.

set -euo pipefail

# Fail-loud on a cleared/misconfigured org secret (no silent default) — a wrong
# org would query the wrong org and produce a false liveness verdict. The
# workflow always passes `secrets.SENTRY_ORG`; this guards the empty-secret case.
: "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN must be set}"
: "${SENTRY_ORG:?SENTRY_ORG must be set}"
# SENTRY_PROJECT is deliberately NOT required since #7590: the org-scoped
# replacement endpoint has no project segment, so the variable has no consumer
# in this script. A `:?` guard on an unused variable is a contract the next
# reader has to disprove.

# The issue-alert rules this control depends on. Names are the `name` attribute
# of the `sentry_issue_alert` resources in
# apps/web-platform/infra/sentry/issue-alerts.tf.
EXPECTED_RULES=("byok-art-33-breach" "byok-cap-exceeded" "chat-message-save-failure" "workspace-sync-health")

fetch_rules() {
  if [[ -n "${SENTRY_FIXTURE_RULES:-}" ]]; then
    cat "$SENTRY_FIXTURE_RULES"
    return
  fi
  # Org issue-alert list — NOT the org `/monitors/` (Crons) endpoint, which
  # excludes issue alerts. `--max-time` bounds the call; `-fsS` fails on 4xx/5xx
  # so an auth/region error surfaces as a non-zero exit, not a parsed error body.
  #
  # Migrated 2026-08-19 (#7590) off `projects/{org}/{proj}/rules/`, which Sentry
  # deprecated on 2026-05-14 and now serves under scheduled BROWNOUTS — 410 for
  # a window on a recurring schedule, 200 the rest of the time. Because this
  # step runs POST-apply under `set -euo pipefail` with `-fsS`, a brownout made
  # `apply-sentry-infra.yml` red AFTER `terraform apply` had already succeeded,
  # on a vendor's calendar rather than on anything about the apply. Measured
  # inside a live brownout on 2026-08-19: the old URL returned 410 with
  # `x-sentry-replacement-endpoint: /api/0/organizations/jikigai-eu/workflows/`
  # while the new one returned 200 with no deprecation headers and all four
  # EXPECTED_RULES present, one match each.
  #
  # `-fsS` is kept deliberately. The replacement carries no deprecation header,
  # so there is no brownout to absorb, and `-S` already prints curl's own
  # `(22) The requested URL returned error: <status>` on a genuine failure.
  : "${SENTRY_API_HOST:?SENTRY_API_HOST must be set (org-subdomain, e.g. jikigai.sentry.io)}"
  curl -fsS --max-time 10 \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/workflows/?per_page=100"
}

rules_json="$(fetch_rules)"

# Fail closed on a non-array payload (Sentry error envelopes are objects).
if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$rules_json"; then
  echo "ERROR: Sentry workflows response is not a JSON array — auth/region/endpoint failure. Cannot assert BYOK rule liveness." >&2
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
