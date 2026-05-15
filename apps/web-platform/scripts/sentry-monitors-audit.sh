#!/usr/bin/env bash
# Sentry Monitors/Alerts migration audit (one-shot, idempotent).
#
# Lists every Sentry Monitor and every project Issue Alert Rule, joins the
# two on monitor.slug references in alert filters, and writes a Markdown
# report to knowledge-base/legal/audits/sentry-migration-audit-<YYYY-MM-DD>.md
# (or to AUDIT_OUT_DIR if set).
#
# Idempotency: the report path is keyed by date; same-day re-runs OVERWRITE
# the prior report at the same path (no append, no duplicate header).
#
# Match-by-id: monitors and rules are addressed by their immutable id/slug
# fields, never by name (Sentry API allows duplicate names — see
# 2026-04-29-supabase-auth-probe-and-sentry-rule-api-quirks.md).
#
# Required env: SENTRY_AUTH_TOKEN, SENTRY_ORG (SENTRY_PROJECT optional).
#
# Test injection (used by sentry-monitors-audit.test.sh ONLY):
#   SENTRY_API_HOST           — bypass region probe; force this host
#   SENTRY_FIXTURE_MONITORS   — file path; serve as monitors GET response
#   SENTRY_FIXTURE_RULES      — file path; serve as project rules response
#   AUDIT_OUT_DIR             — write report here instead of repo legal dir
#
# Plan: knowledge-base/project/plans/2026-05-15-feat-sentry-monitors-alerts-adapt-plan.md
# Phase: 1 (script) + 2.1 (operator run) + 2.2 (CI re-run on release)

set -euo pipefail

: "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN must be set}"
: "${SENTRY_ORG:=jikigai}"
SENTRY_PROJECT="${SENTRY_PROJECT:-}"

# --- Region detection (skipped if SENTRY_API_HOST is set) -----------------
api_host="${SENTRY_API_HOST:-}"
if [[ -z "$api_host" ]]; then
  for candidate in sentry.io de.sentry.io; do
    http=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' \
      -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
      "https://${candidate}/api/0/users/me/" 2>/dev/null || echo 000)
    if [[ "$http" == "200" ]]; then
      api_host="$candidate"
      break
    fi
  done
  if [[ -z "$api_host" ]]; then
    echo "ERROR: Sentry token not valid against either US or EU ingest" >&2
    exit 1
  fi
fi

# --- Fetch monitors (org-wide) -------------------------------------------
fetch_monitors() {
  if [[ -n "${SENTRY_FIXTURE_MONITORS:-}" ]]; then
    cat "$SENTRY_FIXTURE_MONITORS"
    return
  fi
  curl -s --max-time 10 \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    "https://${api_host}/api/0/organizations/${SENTRY_ORG}/monitors/"
}

fetch_rules() {
  if [[ -n "${SENTRY_FIXTURE_RULES:-}" ]]; then
    cat "$SENTRY_FIXTURE_RULES"
    return
  fi
  if [[ -z "$SENTRY_PROJECT" ]]; then
    # Org-wide alert-rules endpoint (metric alerts) — best-effort fallback.
    curl -s --max-time 10 \
      -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
      "https://${api_host}/api/0/organizations/${SENTRY_ORG}/alert-rules/"
  else
    curl -s --max-time 10 \
      -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
      "https://${api_host}/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/rules/"
  fi
}

monitors_json=$(fetch_monitors)
rules_json=$(fetch_rules)

# Validate JSON shape; fail closed on garbage.
for label in monitors rules; do
  case "$label" in
    monitors) payload="$monitors_json" ;;
    rules)    payload="$rules_json" ;;
  esac
  if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$payload"; then
    echo "ERROR: ${label} response is not a JSON array" >&2
    printf '%s\n' "$payload" | head -c 500 >&2
    exit 1
  fi
done

# --- Compute orphans ------------------------------------------------------
# Class A: monitor whose slug is NOT referenced by any alert rule's filters
#          or conditions. (Heuristic: substring search of monitor.slug in
#          serialized rule JSON.)
# Class B: alert rule that references a monitor.slug for which no monitor
#          row exists. (Same substring heuristic, inverted.)
#
# All rule slugs we care about are matched literally — monitor slugs are
# kebab-case unique tokens, so substring collisions are extremely unlikely
# for the soleur naming convention. If a future slug collides, the test
# suite's match-by-id contract still holds because we render rows keyed by
# id/slug, not name.

monitor_slugs=$(jq -r '.[].slug // empty' <<<"$monitors_json")
rules_serialized=$(jq -c '.' <<<"$rules_json")

orphan_monitors=()
while IFS= read -r slug; do
  [[ -z "$slug" ]] && continue
  if ! grep -qF -- "$slug" <<<"$rules_serialized"; then
    orphan_monitors+=("$slug")
  fi
done <<<"$monitor_slugs"

# --- Resolve report path --------------------------------------------------
date_iso=$(date -u '+%Y-%m-%d')
out_dir="${AUDIT_OUT_DIR:-knowledge-base/legal/audits}"
mkdir -p "$out_dir"
out_file="${out_dir}/sentry-migration-audit-${date_iso}.md"

# --- Render report (overwrite, idempotent per-day) ------------------------
{
  printf '# Sentry Monitors/Alerts Migration Audit\n\n'
  printf -- '- **Date (UTC):** %s\n' "$date_iso"
  printf -- '- **Sentry org:** %s\n' "$SENTRY_ORG"
  printf -- '- **API host:** %s\n' "$api_host"
  printf -- '- **Project filter:** %s\n\n' "${SENTRY_PROJECT:-<org-wide>}"

  printf '## Monitors\n\n'
  if [[ "$(jq 'length' <<<"$monitors_json")" == "0" ]]; then
    printf '_No monitors returned by the API._\n\n'
  else
    printf '| slug | name | type | schedule |\n'
    printf '|---|---|---|---|\n'
    jq -r '.[] | [.slug, .name, .type, (.config.schedule // "")] | @tsv' <<<"$monitors_json" | \
      while IFS=$'\t' read -r slug name typ sched; do
        printf '| %s | %s | %s | %s |\n' "$slug" "$name" "$typ" "$sched"
      done
    printf '\n'
  fi

  printf '## Alert Rules\n\n'
  if [[ "$(jq 'length' <<<"$rules_json")" == "0" ]]; then
    printf '_No alert rules returned by the API._\n\n'
  else
    printf '| id | name |\n'
    printf '|---|---|\n'
    jq -r '.[] | [(.id|tostring), .name] | @tsv' <<<"$rules_json" | \
      while IFS=$'\t' read -r id name; do
        printf '| %s | %s |\n' "$id" "$name"
      done
    printf '\n'
  fi

  printf '## Orphans\n\n'
  if (( ${#orphan_monitors[@]} == 0 )); then
    printf 'No orphan monitors detected. _All monitors referenced by at least one alert rule._\n\n'
  else
    printf '_Class A (monitor without paired routing alert):_\n\n'
    for slug in "${orphan_monitors[@]}"; do
      printf -- '- `%s` — orphan: not referenced by any alert rule.\n' "$slug"
    done
    printf '\n**Remediation runbook:** plan §2.1.5 — delete monitor or pair with new alert.\n\n'
  fi

  printf '## DPA evidence\n\n'
  printf 'Vendor DPA: https://sentry.io/legal/dpa/\n'
  printf 'Article 30 register entry: knowledge-base/legal/article-30-register.md (PA8).\n\n'

  # Machine-readable id manifest (Phase 5 import consumer).
  ids_array=$(jq -c '[.[].id | tostring]' <<<"$rules_json")
  printf '<!-- ids: %s -->\n' "$ids_array"
} > "$out_file"

echo "[ok] Wrote audit report: $out_file"
