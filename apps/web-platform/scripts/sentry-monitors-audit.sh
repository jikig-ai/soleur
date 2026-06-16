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
# Dual-path output by caller (plan OQ1; PR #3811 review P1-H):
#   - Operator runs (Phase 2.1 baseline, local re-runs): AUDIT_OUT_DIR
#     unset → tracked dir `knowledge-base/legal/audits/`. Produces the
#     canonical pre-import snapshot in git history.
#   - CI release runs (Phase 2.2 — `reusable-release.yml`): override
#     AUDIT_OUT_DIR to `$RUNNER_TEMP/sentry-audit/`; the workflow then
#     uploads the resulting report as a per-release GitHub release
#     asset. Avoids commit-storm + write-to-main authorization surface.
#
# Plan: knowledge-base/project/plans/2026-05-15-feat-sentry-monitors-alerts-adapt-plan.md
# Phase: 1 (script) + 2.1 (operator run) + 2.2 (CI re-run on release)

set -euo pipefail

: "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN must be set}"
: "${SENTRY_ORG:=jikigai}"
SENTRY_PROJECT="${SENTRY_PROJECT:-}"

# Retry wrapper for Sentry API calls — the org-subdomain intermittently
# returns 500/timeout on GET /organizations/{org}/ and POST /releases/.
# Three attempts with 5s/10s backoff covers the transient 500 pattern
# observed since 2026-05-19. Returns the last attempt's output.
curl_retry() {
  local max_attempts=3
  local attempt=1
  local backoff=5
  local result=""
  while (( attempt <= max_attempts )); do
    result=$(curl "$@" 2>/dev/null) && break
    if (( attempt < max_attempts )); then
      echo "::warning::Sentry API attempt $attempt/$max_attempts failed — retrying in ${backoff}s" >&2
      sleep "$backoff"
      backoff=$(( backoff * 2 ))
    fi
    attempt=$(( attempt + 1 ))
  done
  printf '%s' "$result"
}

# --- Region detection (skipped if SENTRY_API_HOST is set) -----------------
# Probe order (PR-β §10.2 widened from `de.sentry.io sentry.io` baseline):
#   1. ${SENTRY_ORG}.sentry.io — org-subdomain is the ONLY host that works
#      for slug-scoped paths when the org slug ends in a region code (e.g.
#      `jikigai-eu`), per learning
#      `2026-05-17-sentry-eu-region-host-rewrites-slugs-with-eu-suffix.md`.
#   2. eu.sentry.io — EU regional API; works for slug-less endpoints only.
#   3. de.sentry.io — DE ingest cluster; no `/api/0/` surface but kept as a
#      back-compat probe for legacy personal tokens against the EU footprint.
#   4. sentry.io — US/global legacy.
# Region-probe target is still `/users/me/` (returns 200 for personal tokens
# regardless of org scope); internal-integration tokens 401 on `/users/me/`
# but the 4-gate block below catches that via the org-GET probe.
api_host="${SENTRY_API_HOST:-}"
if [[ -z "$api_host" ]]; then
  for candidate in "${SENTRY_ORG}.sentry.io" eu.sentry.io de.sentry.io sentry.io; do
    http=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' \
      -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
      "https://${candidate}/api/0/users/me/" 2>/dev/null || echo 000)
    if [[ "$http" == "200" ]]; then
      api_host="$candidate"
      break
    fi
  done
  if [[ -z "$api_host" ]]; then
    echo "ERROR: Sentry token not valid against any candidate host (${SENTRY_ORG}.sentry.io, eu.sentry.io, de.sentry.io, sentry.io). For internal-integration tokens (which 401 on /users/me/), set SENTRY_API_HOST explicitly to the org-subdomain." >&2
    exit 1
  fi
fi

# --- 4-gate destination-controllability check (PR-β §10 / C5) -------------
# Recurrence-prevention controls per #3861 Branch C. Gates verify the auth
# token can both READ and WRITE against the target org+project, and that the
# runtime DSN's encoded org-id matches the token's org-id (catches the
# split-state where audit token rotated but runtime DSN didn't).
#
# Additive to the L+30ish DSN cluster substring residency check below
# (Architecture F2: existing check is load-bearing for the SDK-DSN-vs-token-
# org-id split that the gates alone cannot catch — see plan §C5).
#
# Skipped under test mode (SENTRY_FIXTURE_MONITORS set) — the gates issue
# real HTTP calls that fixtures cannot mock without recursive
# fixture-of-fixtures complexity.
if [[ -z "${SENTRY_FIXTURE_MONITORS:-}" ]]; then
  # Gate 1: audit_destination_admin_controllable (org GET returns 200)
  gate1_body=$(curl_retry -s --max-time 10 \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    "https://${api_host}/api/0/organizations/${SENTRY_ORG}/")
  if ! jq -e '.id' <<<"$gate1_body" >/dev/null 2>&1; then
    echo "ERROR: Gate 1 (audit_destination_admin_controllable) failed — org ${SENTRY_ORG} not reachable at ${api_host}. Token may lack org:read scope, OR the host rewrites slugs ending in '-eu' (use the org-subdomain ${SENTRY_ORG}.sentry.io as SENTRY_API_HOST instead — see learning 2026-05-17-sentry-eu-region-host-rewrites-slugs-with-eu-suffix.md). Refs #3861." >&2
    exit 1
  fi

  # Gate 2: audit_project_scope (project GET returns 200) — skipped if no project set
  if [[ -n "$SENTRY_PROJECT" ]]; then
    gate2_http=$(curl_retry -s --max-time 10 -o /dev/null -w '%{http_code}' \
      -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
      "https://${api_host}/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/")
    if [[ "$gate2_http" != "200" ]]; then
      echo "ERROR: Gate 2 (audit_project_scope) failed — project ${SENTRY_ORG}/${SENTRY_PROJECT} returned HTTP ${gate2_http}. Token may lack project:read scope. Refs #3861." >&2
      exit 1
    fi
  fi

  # Gate 3: audit_write_probe (POST release, expect 201 only — Kieran P1-4
  # dropped the 208 branch). Cleans up via DELETE on best-effort.
  probe_ver="audit-probe-$(date +%s)-$$"
  gate3_http=$(curl_retry -s --max-time 10 -o /dev/null -w '%{http_code}' \
    -X POST \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"version\":\"${probe_ver}\",\"projects\":[\"${SENTRY_PROJECT:-web-platform}\"]}" \
    "https://${api_host}/api/0/organizations/${SENTRY_ORG}/releases/")
  if [[ "$gate3_http" != "201" ]]; then
    echo "ERROR: Gate 3 (audit_write_probe) failed — POST release returned HTTP ${gate3_http}, expected 201 (208 branch dropped per Kieran P1-4). Token may lack project:releases scope (Admin level required). Refs #3861." >&2
    exit 1
  fi
  curl -s --max-time 10 -X DELETE \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    "https://${api_host}/api/0/organizations/${SENTRY_ORG}/releases/${probe_ver}/" \
    -o /dev/null 2>/dev/null || true

  # Gate 4: audit_dsn_org_id_matches_token_org_id — extract `o<id>` from DSN
  # (e.g. `o4523123` from `https://k@o4523123.ingest.de.sentry.io/789`) and
  # compare to `.id` from Gate 1's org body. Catches destination-controllability
  # drift where the audit token's org-id and the runtime DSN's org-id diverge
  # (#3861 — originally framed as "phantom-ingest to unowned third-party org"
  # before the 2026-05-19 token-scope reframe; the gate remains useful as a
  # general DSN/token org-id-matches check regardless of ownership framing).
  #
  # `|| true` braces keep `set -o pipefail` happy when the DSN env is unset
  # (callers like `reusable-release.yml`'s release-time audit step do not
  # pass `NEXT_PUBLIC_SENTRY_DSN`). The `[[ -n "$dsn_org_id" && ... ]]` guard
  # below already handles empty `dsn_org_id` correctly — but without `|| true`
  # the pipeline itself fails before reaching the guard, exiting the script
  # with no visible error. Mirrors the same pattern on `dsn_cluster` below.
  dsn_org_id=$(printf '%s' "${NEXT_PUBLIC_SENTRY_DSN:-${SENTRY_DSN:-}}" \
    | { grep -oE 'o[0-9]+' || true; } | head -1 | tr -d 'o')
  token_org_id=$(jq -r '.id // empty' <<<"$gate1_body")
  if [[ -n "$dsn_org_id" && -n "$token_org_id" && "$dsn_org_id" != "$token_org_id" ]]; then
    echo "ERROR: Gate 4 (audit_dsn_org_id_matches_token_org_id) failed — DSN encodes org id ${dsn_org_id} but audit token authenticates against org id ${token_org_id}. Runtime DSN and audit token are pointing at different orgs (split-state). Refs #3861." >&2
    exit 1
  fi
fi

# --- DSN cluster + residency mismatch detector ----------------------------
# DSN cluster substring is the authoritative residency signal (per learning
# 2026-05-15-sentry-dsn-cluster-substring-authoritative-residency.md): the
# SDK ingests events at the cluster encoded in `NEXT_PUBLIC_SENTRY_DSN` /
# `SENTRY_DSN`, not at the API host the auditor happens to probe.
#
# Extract the cluster segment (e.g., `de` from
# `https://abc@o123.ingest.de.sentry.io/456`). Fail-closed default `us`
# covers bare `ingest.sentry.io` DSNs and missing-DSN envs (which means a
# DE-host probe against an unset DSN env will trip the mismatch detector
# below — the right failure mode for §5(2) accountability).
# `|| true` keeps `set -e` happy when the DSN env is unset or US-shaped
# (both `grep -oE` calls exit 1 on no-match). The fallback below resolves
# to `us`, which is the correct US-cluster default.
dsn_cluster=$(printf '%s' "${NEXT_PUBLIC_SENTRY_DSN:-${SENTRY_DSN:-}}" \
  | { grep -oE 'ingest\.[a-z0-9]{2,}\.sentry\.io' || true; } \
  | { grep -oE '\.[a-z0-9]{2,}\.' || true; } \
  | tr -d '.')
[[ -z "$dsn_cluster" ]] && dsn_cluster="us"

# Mismatch detector: if the region segment of the probed host differs from
# the DSN cluster, refuse to emit the audit artifact. The audit workflow's
# `set +e` + `::warning::` branch handles the non-zero exit gracefully (no
# `gh release upload`). Refs #3861.
#
# Host shapes:
#   `sentry.io`          → US legacy global (`host_region=us`)
#   `de.sentry.io`       → DE ingest (no /api/0/, but historically probed)
#   `eu.sentry.io`       → EU regional API (slug-less endpoints only)
#   `us.sentry.io`       → US regional API
#   `<org-slug>.sentry.io` → org-subdomain — region NOT encoded in host;
#                            the slug may or may not end in a region code.
#                            `host_region=""` and the comparison is skipped
#                            because there's no host-region signal to
#                            compare. The 4-gate block above already
#                            verified org-controllability against this
#                            host; the DSN's `ingest.<cluster>.sentry.io`
#                            substring remains the residency signal but
#                            the host-vs-DSN comparison is meaningless
#                            here (PR-β §10 / 2026-05-17).
#   Anything else        → unknown — pass through as-is.
case "$api_host" in
  sentry.io)    host_region="us" ;;
  de.sentry.io) host_region="de" ;;
  eu.sentry.io) host_region="eu" ;;
  us.sentry.io) host_region="us" ;;
  *.sentry.io)  host_region="" ;;  # org-subdomain — see comment block above
  *)            host_region="$api_host" ;;
esac
if [[ -n "$host_region" && "$host_region" != "$dsn_cluster" ]]; then
  echo "ERROR: residency mismatch — probed=${api_host} DSN cluster=${dsn_cluster} — refusing to emit audit artifact (refs #3861)" >&2
  exit 2
fi

# --- Fetch monitors (org-wide) -------------------------------------------
# Both fetches use curl_retry (not bare curl): a transient timeout here under
# `set -euo pipefail` would propagate curl's exit 28 and abort the whole audit
# step, which in the apply-sentry-infra.yml workflow SKIPS the plan+apply steps —
# a transient Sentry-EU blip silently darks the apply (observed on the #5325
# go-live: the #5380 apply failed exit 28 on this exact path and only succeeded
# on re-run). curl_retry always returns 0 (last attempt's output), so a genuine
# persistent failure surfaces at the JSON-shape validation below with a clear
# "response is not a JSON array" message + exit 1 — never a cryptic exit 28.
fetch_monitors() {
  if [[ -n "${SENTRY_FIXTURE_MONITORS:-}" ]]; then
    cat "$SENTRY_FIXTURE_MONITORS"
    return
  fi
  curl_retry -s --max-time 10 \
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
    curl_retry -s --max-time 10 \
      -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
      "https://${api_host}/api/0/organizations/${SENTRY_ORG}/alert-rules/"
  else
    curl_retry -s --max-time 10 \
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
#          or conditions.
# Class B: alert rule that references a monitor.slug for which no monitor
#          row exists.
# Class C: issue-alert rule with an empty actions[] array (paging route
#          silently removed via Sentry UI). Operator MUST treat as a real
#          orphan — the routing path is gone even though the rule exists.
#
# Extraction is structural — jq pulls slug references from
# .conditions[].value and .filters[].value (where Sentry stores monitor-slug
# bindings on `TaggedEventFilter` and `EventMonitorCondition`-shaped rules).
# Falls back to substring search ONLY if the structured pass returns zero,
# so the report is never blank against rules that bind monitors via a
# field not yet enumerated.

monitor_slugs=$(jq -r '.[].slug // empty' <<<"$monitors_json")

# Broad extraction — every literal "value" field across each rule's
# conditions and filters, plus the legacy `monitor_slug` field. Used ONLY
# for Class A's "is this monitor referenced anywhere?" non-orphan check,
# where over-counting is safe (it suppresses false-positive Class A) and
# under-counting is dangerous.
rule_slug_refs=$(jq -r '
  .[] | (
    (.conditions // [])[]?.value? // empty,
    (.filters // [])[]?.value? // empty,
    .monitor_slug? // empty
  )
' <<<"$rules_json" | sort -u)

# Narrow extraction — only values from filters / conditions whose `key`
# explicitly binds a monitor slug (`monitor.slug`), plus the legacy
# `monitor_slug` field. Used for Class B orphan flagging, where
# over-counting floods false-positives. Production `TaggedEventFilter`
# rules carry generic shapes like `{"key":"feature","value":"auth"}`
# whose `.value` is a tag value, NOT a monitor slug; without this gate
# every tag-bound rule would emit a spurious "alert references missing
# monitor `auth`" line on every release audit.
#
# Note on the array-build-then-iterate pattern: a bare comma-separated
# stream of `select | .value? // empty` branches inside `(...)` returns
# no values in jq 1.6+ when any branch's left-hand iterator is empty
# (the `?` swallows the empty-stream and the comma operator's union
# collapses). Wrapping each branch in `[... | ...]` then re-iterating
# via `[]` makes each branch independent.
monitor_bound_slug_refs=$(jq -r '
  .[] | (
    ([.conditions // [] | .[] | select(.key? == "monitor.slug") | .value])[],
    ([.filters    // [] | .[] | select(.key? == "monitor.slug") | .value])[],
    (.monitor_slug? // empty)
  )
' <<<"$rules_json" | sort -u)

# Fallback substring sweep for forward-compat — only consulted if the
# structured pass found nothing. Stored in a separate var so we never mix
# substring matches into the rule_slug_refs set used by Class A non-orphan
# check.
rules_serialized=$(jq -c '.' <<<"$rules_json")

orphan_monitors=()  # Class A
orphan_alerts=()    # Class B
empty_action_rule_ids=()  # Class C

while IFS= read -r slug; do
  [[ -z "$slug" ]] && continue
  if printf '%s\n' "$rule_slug_refs" | grep -qFx -- "$slug"; then
    continue
  fi
  # Structured pass missed it; fall back to substring sweep ONCE before
  # flagging as orphan (covers Sentry rule shapes the structured pass
  # doesn't enumerate yet).
  if ! grep -qF -- "$slug" <<<"$rules_serialized"; then
    orphan_monitors+=("$slug")
  fi
done <<<"$monitor_slugs"

# Class B: every monitor-bound slug ref that does NOT appear in monitor_slugs.
# Uses the NARROW extraction (`monitor_bound_slug_refs`) so generic tag-filter
# values (e.g. `{"key":"feature","value":"auth"}`) cannot flood the report
# with false-positive "alert references missing monitor `auth`" lines.
monitor_slug_set=$(printf '%s\n' "$monitor_slugs" | sort -u)
while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  # Belt-and-braces: also require slug shape (kebab-case, no spaces). The
  # narrow extraction should already guarantee this, but defends against a
  # future Sentry API change shipping a monitor.slug binding with a
  # non-slug-shaped value.
  [[ "$ref" =~ ^[a-z0-9][a-z0-9-]*$ ]] || continue
  if ! printf '%s\n' "$monitor_slug_set" | grep -qFx -- "$ref"; then
    orphan_alerts+=("$ref")
  fi
done <<<"$monitor_bound_slug_refs"

# Class C: alert rules with empty routing. Two shapes to handle:
#   - Issue Alerts have top-level `.actions[]`.
#   - Metric Alerts (returned from /organizations/<org>/alert-rules/) store
#     routing under `.triggers[].actions[]` and have NO top-level `.actions`.
# Without the shape branch, every Metric Alert flags as Class C because
# `.actions // []` evaluates to `[]` (length 0) — drowning real orphans.
# Branch by the presence of `.triggers`: if a rule has triggers, count
# their flattened actions; otherwise check top-level actions.
while IFS= read -r rid; do
  [[ -z "$rid" ]] && continue
  empty_action_rule_ids+=("$rid")
done < <(jq -r '
  .[] | select(
    if has("triggers") then
      ([.triggers[]?.actions[]?] | length == 0)
    else
      ((.actions // []) | length == 0)
    end
  ) | .id | tostring
' <<<"$rules_json")

# --- Resolve report path --------------------------------------------------
# AUDIT_DATE_OVERRIDE is honored by the test suite to defeat the midnight
# UTC race in T4 idempotency (3 invocations crossing the date boundary
# would produce 2 reports). Production callers should leave it unset.
date_iso="${AUDIT_DATE_OVERRIDE:-$(date -u '+%Y-%m-%d')}"
out_dir="${AUDIT_OUT_DIR:-knowledge-base/legal/audits}"
mkdir -p "$out_dir"
out_file="${out_dir}/sentry-migration-audit-${date_iso}.md"

# --- Render report (overwrite, idempotent per-day) ------------------------
{
  printf '# Sentry Monitors/Alerts Migration Audit\n\n'
  printf -- '- **Date (UTC):** %s\n' "$date_iso"
  printf -- '- **Sentry org:** %s\n' "$SENTRY_ORG"
  printf -- '- **Probed host:** %s\n' "$api_host"
  printf -- '- **DSN cluster:** %s\n' "$dsn_cluster"
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
  total_orphans=$(( ${#orphan_monitors[@]} + ${#orphan_alerts[@]} + ${#empty_action_rule_ids[@]} ))
  if (( total_orphans == 0 )); then
    printf 'No orphans detected. All three classes (A: monitor without alert; B: alert referencing missing monitor; C: alert with empty actions[]) are clean.\n\n'
  fi

  if (( ${#orphan_alerts[@]} > 0 )); then
    printf '_Class B (alert rule referencing a missing monitor):_\n\n'
    for ref in "${orphan_alerts[@]}"; do
      printf -- '- `%s` — referenced by an alert rule; no monitor with this slug exists.\n' "$ref"
    done
    printf '\n**Remediation:** Sentry split likely deleted the monitor; either delete the dangling alert via API or re-create the monitor in `cron-monitors.tf`.\n\n'
  fi

  if (( ${#empty_action_rule_ids[@]} > 0 )); then
    printf '_Class C (alert rule with empty actions[] — paging route silently removed):_\n\n'
    for rid in "${empty_action_rule_ids[@]}"; do
      printf -- '- rule id `%s` — `actions` array is empty; threshold breaches will fire no notification.\n' "$rid"
    done
    printf '\n**Remediation:** restore the action target via the Sentry UI (re-add NotifyEmailAction Team or IssueOwners). The Terraform `actions_v2 lifecycle.ignore_changes` posture means TF cannot self-heal this — UI fix is the only path.\n\n'
  fi

  if (( ${#orphan_monitors[@]} > 0 )); then
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
  # Defense-in-depth: filter to numeric-only ids. Sentry's contract says
  # rule ids are numeric, but a compromised response could ship shell
  # metacharacters; the README's `for id in $ids` consumer would word-split
  # them. Fail-closed at the producer.
  ids_array=$(jq -c '[.[].id | tostring | select(test("^[0-9]+$"))]' <<<"$rules_json")
  printf '<!-- ids: %s -->\n' "$ids_array"
} > "$out_file"

echo "[ok] Wrote audit report: $out_file"
