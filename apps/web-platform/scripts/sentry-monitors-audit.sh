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
#   SENTRY_TF_DIR             — read Class D `.tf` declarations from here
#   AUDIT_OUT_DIR             — write report here instead of repo legal dir
#
# Class D state half (PRODUCTION input, not test-only):
#   SENTRY_STATE_SLUGS_FILE — path to a file of newline-separated monitor slugs
#     that Terraform state tracks. Class D = live AND undeclared AND *not in
#     state*: a monitor in state with no .tf block is a PENDING DESTROY the next
#     apply reclaims, not an orphan. Without this file the two are
#     indistinguishable and the script only WARNS (failing on an unresolvable set
#     deadlocks the apply — see the gate at the foot of this file).
#
#     A FILE PATH, not a value, so that "state is empty" (a legitimate state with
#     zero cron monitors, in which every live monitor IS a true orphan) is
#     distinguishable from "state was never read". A bare value cannot express
#     that: empty-string and unset are the same thing to the shell, so an empty
#     state would silently downgrade to a warning — fail-open on exactly the case
#     where every live monitor is unreclaimable. Mirrors the SENTRY_FIXTURE_*
#     file-path convention above.
#
#     Produced after `terraform init` by:
#       terraform show -json | jq -r '
#         .values.root_module.resources[]?
#         | select(.type=="sentry_cron_monitor") | .values.name'
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

# --- Class D: live monitor with no declaring .tf resource block -----------
# The live→IaC direction (A/B/C all run IaC→live or live→live). Since #6589
# deleted the `-target=` allow-list from apply-sentry-infra.yml, the plan runs
# against the FULL ROOT — so an undeclared live monitor is no longer a
# harmless bookkeeping gap: it is spend Terraform will never reclaim, because
# only a resource that once existed in the config can be destroyed by removing
# it. Live monitors grew 8 → 49 in two months and never decreased while
# deletion was a silent no-op; each undeclared monitor bills $0.78/mo forever.
#
# Slug↔declaration relation: Sentry derives the monitor slug by slugifying the
# resource's `name`. Every `sentry_cron_monitor` in this root already sets a
# kebab-case `name`, so slugification is the identity and `name` == live slug
# — verified against the live org: 49 `resource "sentry_cron_monitor"` blocks,
# 49 `name =` attributes, 49 live monitors, exact set match.
CRON_MONITOR_MONTHLY_USD="0.78"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tf_dir="${SENTRY_TF_DIR:-${script_dir}/../infra/sentry}"

# TR3: liveness comes from `environments[].lastCheckIn`, NOT a top-level
# `.lastCheckIn`. The list endpoint has NO top-level lastCheckIn field, so
# `.[].lastCheckIn` reads `null` for every monitor and reports the whole org
# as never-checked-in (the 2026-07-17 research agent hit exactly this: it
# claimed 50 never-checked-in; the true count was 2). A monitor carries one
# entry per environment, each with its own check-in, so the newest across
# environments is the monitor's liveness. `max` over the empty array yields
# null → the `never` sentinel; an empty field would make the marker below
# unparseable for any consumer splitting on `=`.
monitor_last_checkin() {
  jq -r --arg s "$1" '
    [ .[] | select(.slug == $s) | .environments[]?.lastCheckIn // empty ] | max // "never"
  ' <<<"$monitors_json"
}

monitor_created() {
  jq -r --arg s "$1" '
    [ .[] | select(.slug == $s) | .dateCreated // empty ] | first // "unknown"
  ' <<<"$monitors_json"
}

orphan_live_monitors=()   # Class D — live, undeclared, AND not in state (unreclaimable)
class_d_unresolved=()     # live + undeclared, but state unknown -> cannot classify
class_d_state_unknown=0
# Class D compares two halves — the live monitor list and the .tf root that
# declares it. A synthetic monitor list judged against the REAL tf root makes
# every fixture slug "undeclared" by construction: noise, not a finding. So the
# comparison runs only when both halves agree on their source. Same skip
# predicate the 4-gate block above uses, and it cannot fail open in production:
# SENTRY_FIXTURE_MONITORS is test-injection only (see the header), so with it
# unset the gate always runs; a fixture run that supplies SENTRY_TF_DIR pairs
# coherently and gets the full gate.
if [[ -z "${SENTRY_FIXTURE_MONITORS:-}" || -n "${SENTRY_TF_DIR:-}" ]]; then
  if [[ ! -d "$tf_dir" ]]; then
    echo "ERROR: Sentry Terraform root not found at ${tf_dir} — cannot prove any live monitor is declared, and flagging all of them as Class D would be a false positive. Refs #6589." >&2
    exit 1
  fi

  # Anchor on the declaration construct, NOT a bare slug grep. These .tf files
  # name monitor slugs in prose comments (e.g. the CLAUDE-EVAL COHORT block
  # lists 12 of them), so `grep -F "$slug" *.tf` matches a comment and silently
  # suppresses a real orphan. Scoping to the `sentry_cron_monitor` block header
  # also keeps `name =` from a sibling `sentry_issue_alert` / `sentry_uptime_
  # monitor` block (both carry kebab-case names in this same root) from being
  # read as a cron declaration. `in_block` clears on the first `name =` so a
  # nested block's attribute cannot leak in either.
  declared_slugs=$(awk '
    /^resource[[:space:]]+"sentry_cron_monitor"[[:space:]]/ { in_block=1; next }
    in_block && /^[[:space:]]*name[[:space:]]*=[[:space:]]*"/ {
      if (match($0, /"[^"]*"/)) { print substr($0, RSTART+1, RLENGTH-2); in_block=0 }
    }
    in_block && /^}/ { in_block=0 }
  ' "$tf_dir"/*.tf | sort -u)

  # Zero declarations parsed against a non-empty live org means the anchor broke
  # (e.g. a reformat moved `resource` off column 0), not that every monitor is
  # orphaned. Erroring here is still fail-closed, but it names the real defect
  # instead of flooding the operator with 49 bogus orphans.
  if [[ -z "$declared_slugs" && "$(jq 'length' <<<"$monitors_json")" != "0" ]]; then
    echo "ERROR: no sentry_cron_monitor declarations parsed from ${tf_dir}/*.tf while the API returned live monitors — Class D extraction is broken; refusing to report every live monitor as an orphan. Refs #6589." >&2
    exit 1
  fi

  # ── The state half — load-bearing, and NOT an optimisation ────────────────
  # Class D means "Terraform can never reclaim this". `live AND not declared` is
  # NOT that set: a monitor that is IN STATE with no remaining .tf block is a
  # PENDING DESTROY — the very next full-root apply reclaims it. That is #6589's
  # fix working, not an orphan.
  #
  # Getting this wrong DEADLOCKS the apply. apply-sentry-infra.yml runs this
  # audit BEFORE `terraform plan` (a deliberate gate-call-graph ordering, so the
  # workflow_dispatch path cannot bypass the 4-gate check). So a Class D that
  # fires on a pending destroy fails the job before the plan runs, the destroy
  # never happens, the monitor stays live and billing — and the detector has
  # recreated the exact #6074 end state it exists to prevent, by blocking its own
  # cure. This is not hypothetical: at the time of writing, live=50 declared=49,
  # and the one difference is scheduled-ghcr-token-minter — precisely the orphan
  # #6589 destroys.
  #
  # SENTRY_STATE_SLUGS carries the slugs Terraform tracks (see the header for the
  # producer). Absent, the two cases are INDISTINGUISHABLE from here, so the
  # candidates are reported without failing: failing on a set we cannot resolve
  # is what causes the deadlock, and a gate that cannot be correct should not be
  # the one with teeth. The authoritative fail-closed run is
  # apply-sentry-infra.yml, which inits Terraform first and injects the state
  # half — the caller that can actually know.
  state_known=0
  state_slugs=""
  if [[ -n "${SENTRY_STATE_SLUGS_FILE:-}" ]]; then
    if [[ ! -f "$SENTRY_STATE_SLUGS_FILE" ]]; then
      echo "ERROR: SENTRY_STATE_SLUGS_FILE is set to '${SENTRY_STATE_SLUGS_FILE}' but no such file exists. Refusing to silently fall back to the state-unknown warn path — the caller believes it provided state. Refs #6589." >&2
      exit 1
    fi
    state_known=1
    state_slugs=$(grep -vE '^[[:space:]]*$' "$SENTRY_STATE_SLUGS_FILE" | sort -u || true)
  fi

  class_d_candidates=()
  while IFS= read -r slug; do
    [[ -z "$slug" ]] && continue
    printf '%s\n' "$declared_slugs" | grep -qFx -- "$slug" && continue
    class_d_candidates+=("$slug")
  done <<<"$monitor_slugs"

  if (( state_known == 1 )); then
    for slug in ${class_d_candidates[@]+"${class_d_candidates[@]}"}; do
      # In state => Terraform WILL reclaim it on the next apply => not Class D.
      printf '%s\n' "$state_slugs" | grep -qFx -- "$slug" && continue
      orphan_live_monitors+=("$slug")
    done
  else
    class_d_state_unknown=1
    class_d_unresolved=( ${class_d_candidates[@]+"${class_d_candidates[@]}"} )
  fi
fi

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
  total_orphans=$(( ${#orphan_monitors[@]} + ${#orphan_alerts[@]} + ${#empty_action_rule_ids[@]} + ${#orphan_live_monitors[@]} ))
  if (( total_orphans == 0 )); then
    printf 'No orphans detected. All four classes (A: monitor without alert; B: alert referencing missing monitor; C: alert with empty actions[]; D: live monitor with no .tf declaration) are clean.\n\n'
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

  if (( ${#orphan_live_monitors[@]} > 0 )); then
    printf '_Class D (live monitor with no declaring `.tf` resource block):_\n\n'
    printf '| slug | created | last check-in | cost/mo (USD) |\n'
    printf '|---|---|---|---|\n'
    for slug in "${orphan_live_monitors[@]}"; do
      printf '| `%s` | %s | %s | %s |\n' \
        "$slug" "$(monitor_created "$slug")" "$(monitor_last_checkin "$slug")" "$CRON_MONITOR_MONTHLY_USD"
    done
    printf '\n**Monthly spend on undeclared monitors:** $%s (%d × $%s).\n\n' \
      "$(printf '%s %s' "${#orphan_live_monitors[@]}" "$CRON_MONITOR_MONTHLY_USD" | awk '{printf "%.2f", $1 * $2}')" \
      "${#orphan_live_monitors[@]}" "$CRON_MONITOR_MONTHLY_USD"
    printf '**Remediation:** these monitors exist only in Sentry. Terraform cannot destroy a resource it never declared, so `terraform apply` will NOT reclaim them. Either add a `sentry_cron_monitor` block to `%s` (adopt via `terraform import`) or delete the monitor via the Sentry API. Refs #6589.\n\n' \
      "apps/web-platform/infra/sentry/cron-monitors.tf"
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

# --- Class D gate ---------------------------------------------------------
# Deliberately NOT the A/B/C posture. Those classes only `printf` into the
# report and let the script exit 0 — that is correct for them (they describe
# routing gaps an operator triages), and changing it would break the callers
# that treat a non-zero audit as a hard stop. Class D is different: it is
# unreclaimable recurring spend, and a detector that only writes a line into
# a report nobody opens is wired to nothing. It must exit non-zero.
#
# Placed last, after the report is written and the markers are emitted, so
# the operator gets the full list — a bare failure with no slugs is not
# actionable. Nothing runs after this point, so the gate cannot be skipped.
#
# Callers: apply-sentry-infra.yml runs this under `set -euo pipefail` BEFORE
# `terraform plan`, so a Class D orphan halts the apply before any state
# mutation; sentry-audit-gate.yml fails the required check on Sentry-touching
# PRs. reusable-release.yml wraps the call in `set +e` and downgrades any
# non-zero to a `::warning::`, so releases stay unblocked.
#
# ONLY unreclaimable monitors reach here — `live AND undeclared AND not in
# state`. A pending destroy (in state, block removed) is excluded upstream: it
# is not an orphan, and failing on it would halt the apply BEFORE the plan that
# reclaims it, leaving the monitor live and billing. See the state-half comment
# above.
if (( ${#orphan_live_monitors[@]} > 0 )); then
  for slug in "${orphan_live_monitors[@]}"; do
    printf 'SOLEUR_SENTRY_CLASS_D_ORPHAN: slug=%s created=%s last_checkin=%s cost_usd=%s\n' \
      "$slug" "$(monitor_created "$slug")" "$(monitor_last_checkin "$slug")" "$CRON_MONITOR_MONTHLY_USD"
  done
  echo "ERROR: ${#orphan_live_monitors[@]} live Sentry monitor(s) are unreclaimable (Class D): no declaring resource block in ${tf_dir}/*.tf AND absent from Terraform state, so no apply can ever destroy them — each bills \$${CRON_MONITOR_MONTHLY_USD}/mo. Import them into Terraform, or delete them via the Sentry API. See the Class D table in ${out_file}. Refs #6589." >&2
  exit 1
fi

# State unknown: `live AND undeclared` was computed, but without the state half a
# PENDING DESTROY (which the next apply reclaims) is indistinguishable from a
# genuinely unreclaimable orphan. Report, do not fail — failing on an unresolvable
# set is what deadlocks the apply. The authoritative fail-closed run is
# apply-sentry-infra.yml, which inits Terraform and injects SENTRY_STATE_SLUGS.
if (( class_d_state_unknown == 1 )) && (( ${#class_d_unresolved[@]} > 0 )); then
  echo "::warning::${#class_d_unresolved[@]} live Sentry monitor(s) have no declaring .tf block, but SENTRY_STATE_SLUGS was not provided so this run cannot tell a pending destroy from an unreclaimable orphan. Not failing: see ${out_file}. Candidates: ${class_d_unresolved[*]}" >&2
fi
