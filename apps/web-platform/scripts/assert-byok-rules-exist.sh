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
# The paragraph above is CORRECT for these four rules, and was briefly
# "corrected" into a falsehood on 2026-08-19 (#7590) before being restored.
# Recording why, because the mistake is one grep away from being made again:
# `issue-alerts.tf` DOES contain
# `ignore_changes = [conditions_v2, filters_v2, actions_v2, environment, frequency]`
# — but on the four `auth-*` resources, which are a DIFFERENT four rules,
# managed by `configure-sentry-alerts.sh` and tracked by #4781. The four in
# EXPECTED_RULES below carry `ignore_changes = [environment]` only and do not
# declare the v2 attributes empty, so Terraform genuinely owns their filters.
# A file-level grep for `ignore_changes` cannot tell those two sets apart;
# resolve the attribute per RESOURCE BLOCK before believing either claim.
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


# REFUSE TO RUN UNDER XTRACE (#7797). Shell tracing echoes commands AFTER
# expansion, so SENTRY_AUTH_TOKEN would be printed in full the moment it is
# bound -- which is exactly how two live tokens reached an agent transcript.
# `$-` is the load-bearing arm: bash applies an env-supplied SHELLOPTS or
# BASH_ENV before line 1, so `x` is already set by the time this runs. Do not
# delete it. Tracing stays available with the credential unset, so this refuses
# a leak without blocking a debugging session.
case "$-" in
  *x*)
    if [ -n "${SENTRY_AUTH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with SENTRY_AUTH_TOKEN set (see #7797). Re-run with SENTRY_AUTH_TOKEN= to trace safely.\n' >&2
      exit 78
    fi
    ;;
esac
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
  if [[ -n "${SENTRY_FIXTURE_RULES:+x}" ]]; then
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
  echo "ERROR: Sentry workflows response is not a JSON array. NOTE: this branch does NOT catch auth/region/HTTP errors — \`curl -fsS\` exits 22 on any >=400 and \`set -e\` aborts at the assignment above, before this check. What reaches here is a 200 carrying a non-array body: schema drift, an HTML interstitial, or a proxy injection. Cannot assert BYOK rule liveness." >&2
  printf '%s\n' "$rules_json" | head -c 500 >&2
  exit 1
fi

# PAGINATION CEILING. The fetch asks for one page of 100 and does not follow
# cursors. The org returns 30 workflows today (measured 2026-08-19), but it
# grew 4 -> 29 issue-alert resources in 76 days, so the ceiling is reachable.
# If it is ever hit, a rule on page 2 is indistinguishable from an absent one,
# and the absence branch below would tell the operator a GDPR control is dark
# when it is live. Fail with THIS message instead, naming the real cause.
#
# The sibling `sentry_fetch_collection` in sentry-monitors-audit.sh follows
# cursors against this same endpoint; porting it here is the real fix and is
# deliberately not done in this PR — this guard exists so the day the ceiling
# is reached produces an accurate diagnosis rather than a false alarm.
if (( $(jq 'length' <<<"$rules_json") >= 100 )); then
  echo "ERROR: the workflows payload returned >= 100 rows, which is this fetch's unpaginated ceiling — a rule beyond page 1 would read as ABSENT and produce a false 'control is dark' alarm. Do not trust a liveness verdict from this run. Fix: follow the Link rel=\"next\" cursor here, mirroring sentry_fetch_collection in sentry-monitors-audit.sh. Refs #7590." >&2
  exit 1
fi

# LIVENESS, not mere existence. Matching on `.name` alone was a fail-open: a
# rule disabled in the Sentry UI is still present in the payload, so all four
# controls could be muted and this gate would report green. Measured
# 2026-08-19 (#7590): a fully-muted fixture exited 0 with "[ok] ... all
# expected rules present". The header above has claimed since #4656 that this
# gate catches a "deleted/muted rule"; until now it caught only deleted.
#
# The enabled test is written as "no row with this name has `.enabled == true`"
# rather than "some row has `.enabled == false`", so a payload that stops
# carrying the field fails CLOSED (reported as muted) instead of silently
# reverting to existence-by-name.
#
# ABSENCE IS REPORTED FIRST. A run can produce both lists, and absence is the
# stronger finding: it is the one whose remediation differs (an apply can
# recreate a deleted rule; only live state can re-enable a muted one). Ordering
# the muted branch first made T2/T3/T7/T8 stop naming the absent rule.
missing=()
disabled=()
for rule in "${EXPECTED_RULES[@]}"; do
  if ! jq -e --arg n "$rule" 'any(.[]; .name == $n)' >/dev/null 2>&1 <<<"$rules_json"; then
    missing+=("$rule")
  elif ! jq -e --arg n "$rule" 'any(.[]; .name == $n and .enabled == true)' >/dev/null 2>&1 <<<"$rules_json"; then
    disabled+=("$rule")
  fi
done

if (( ${#missing[@]} > 0 )); then
  echo "ERROR: issue-alert liveness assertion FAILED — rule(s) absent in Sentry: ${missing[*]}" >&2
  echo "A silent mis-wire (dropped -target, deleted rule, or name drift) leaves the named control un-paged: byok-art-33-breach → the GDPR Art. 33(1) 72h clock never starts; chat-message-save-failure → message-save outage un-paged; workspace-sync-health → diverged/stale workspace KB clone (and probe self-failure) un-paged. Refs #4656 item 5, #4849, #4882." >&2
  exit 1
fi

if (( ${#disabled[@]} > 0 )); then
  echo "ERROR: issue-alert liveness assertion FAILED — rule(s) PRESENT BUT NOT ENABLED in Sentry: ${disabled[*]}" >&2
  echo "The rule exists but is muted, so it pages nobody — same user-visible outcome as absence, different repair. An apply will NOT fix it: enablement is live state. Re-enable in the Sentry UI. Refs #7590." >&2
  exit 1
fi

echo "[ok] issue-alert liveness: all expected rules present in Sentry (${EXPECTED_RULES[*]})."
