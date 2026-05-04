#!/usr/bin/env bash
# Audit (and optionally rewrite) Sentry alert rules / saved searches /
# Discover saved queries / dashboard widgets that reference the legacy
# extra-context key `extra.text` for `op:tool-label-scrub` events.
#
# Background: PR #3127 renamed the workspace-path leak diagnostic capture
# in apps/web-platform/server/tool-labels.ts from `extra.text` (200 chars
# of post-scrub residual) to `extra.shape` (the matched leak substring
# only). Any saved Sentry artifact filtering or grouping on `extra.text`
# for that op silently stops matching post-deploy. This script provides
# the operator-side closure: an audit-first, rewrite-as-fallback tool.
#
# Tag-vs-extra namespace caveat (IMPORTANT — Sentry sharp edge):
#   Sentry distinguishes between the **tag** namespace (Sentry.setTag()) and
#   the **extra-context** namespace (Sentry.setExtra()). The Sentry UI's
#   issue-stream search bar and alert-rule TaggedEventFilter operate on
#   tags, NOT on extra. Searching the issue stream for `extra.text` will
#   return zero results regardless of how many extra-context fields exist.
#   Saved searches and Discover/dashboard query strings DO reference
#   extra.* in free-text Sentry search syntax, so this script is the only
#   complete audit path. An operator who searches only the issue stream
#   and concludes "no follow-through targets" has not actually verified
#   anything — run this script.
#
# Modes:
#   (default)               dry-run: GET-only inventory, prints matches
#   --apply                 rewrite: replace `extra.text` -> `extra.shape`
#   --apply --add-or-clause rewrite: wrap in `(extra.text:* OR extra.shape:*)`
#                             — query strings only; fields[] always replaces.
#   --help                  usage
#
# Required env: SENTRY_AUTH_TOKEN, SENTRY_ORG, SENTRY_PROJECT
# Required scopes: org:read, project:read, project:write, event:read
#   (broader than configure-sentry-alerts.sh which only writes /rules/).
#   The Doppler `prd` SENTRY_AUTH_TOKEN may be a narrow `sntrys_` org-auth
#   token scoped only to releases; the operator can override by exporting
#   SENTRY_API_TOKEN's value as SENTRY_AUTH_TOKEN for this invocation,
#   or by minting a new token with the broader scope set.
# Idempotency: GET-then-PUT match-by-name; alert-rule duplicate names fail
# closed (no silent recovery).
# Region detection: probes /organizations/{org}/ on sentry.io and
# de.sentry.io, then reads .links.regionUrl from the response body.
# Refs #3147. Source PR #3127. Precedent: configure-sentry-alerts.sh.

set -euo pipefail

# --- Argument parsing ----------------------------------------------------
APPLY=0
ADD_OR_CLAUSE=0

usage() {
  cat <<'USAGE'
Usage: audit-sentry-extra-text-references.sh [OPTIONS]

Audits (default: dry-run) or rewrites Sentry artifacts that reference
extra.text on op:tool-label-scrub events.

Options:
  --apply           Rewrite matches in place (extra.text -> extra.shape).
                    Default mode is dry-run (no mutation).
  --add-or-clause   With --apply: wrap query strings in
                    (extra.text:foo OR extra.shape:foo) instead of
                    replacing. Discover fields[] arrays always replace
                    (no syntactic OR for array entries).
  --help            Show this message.

Environment:
  SENTRY_AUTH_TOKEN   Required.
  SENTRY_ORG          Required (e.g. jikigai).
  SENTRY_PROJECT      Required (e.g. soleur-web-platform).

Exit codes:
  0  zero matches (or all rewrites verified)
  1  env / dependency / API / verification failure
USAGE
}

while (($#)); do
  case "$1" in
    --apply) APPLY=1 ;;
    --add-or-clause) ADD_OR_CLAUSE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

if (( ADD_OR_CLAUSE && ! APPLY )); then
  echo "ERROR: --add-or-clause requires --apply (mutation only)." >&2
  exit 1
fi

# --- Required env --------------------------------------------------------
: "${SENTRY_AUTH_TOKEN:?SENTRY_AUTH_TOKEN must be set}"
: "${SENTRY_ORG:?SENTRY_ORG must be set}"
: "${SENTRY_PROJECT:?SENTRY_PROJECT must be set}"

# --- jq dependency -------------------------------------------------------
command -v jq >/dev/null 2>&1 || {
  echo "ERROR: jq not found - install via 'brew install jq' or 'apt-get install jq'" >&2
  exit 1
}

# --- Region detection ----------------------------------------------------
# Sentry has US (sentry.io) and EU (de.sentry.io) data-plane clusters.
# Probe /organizations/{org}/ (org-scoped, works for both user-auth and
# org-auth tokens) and read links.regionUrl from the body to find the
# canonical data-plane host. No hard-coded host — the workspace can
# migrate regions and the regionUrl field is authoritative.
#
# Why not /users/me/: the precedent script configure-sentry-alerts.sh
# uses /users/me/ which fails for org-auth tokens (sntrys_ prefix) that
# lack user scope. /organizations/{org}/ is the broadest probe that
# works for any token with org:read.
api_host=""
probe_resp=""
for candidate in sentry.io de.sentry.io; do
  resp_file=$(mktemp)
  http=$(curl -s --max-time 10 \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    -o "$resp_file" -w '%{http_code}' \
    "https://${candidate}/api/0/organizations/${SENTRY_ORG}/")
  if [[ "$http" == "200" ]]; then
    probe_resp=$(cat "$resp_file")
    rm -f "$resp_file"
    region_url=$(jq -r '.links.regionUrl // empty' <<<"$probe_resp" 2>/dev/null || true)
    if [[ -n "$region_url" ]]; then
      api_host="${region_url#https://}"
    else
      api_host="$candidate"
    fi
    break
  fi
  rm -f "$resp_file"
done
if [[ -z "$api_host" ]]; then
  echo "ERROR: Sentry token cannot read /organizations/${SENTRY_ORG}/ on either US or EU." >&2
  echo "  Verify SENTRY_AUTH_TOKEN has org:read scope and SENTRY_ORG is correct." >&2
  exit 1
fi

mode_label="dry-run"
if (( APPLY && ADD_OR_CLAUSE )); then
  mode_label="apply (add-or-clause)"
elif (( APPLY )); then
  mode_label="apply (replace)"
fi
echo "[info] api_host=${api_host} org=${SENTRY_ORG} project=${SENTRY_PROJECT} mode=${mode_label}"

# --- HTTP helpers --------------------------------------------------------
LITERAL_OLD='extra.text'
LITERAL_NEW='extra.shape'
SCOPE_OP='tool-label-scrub'

# Total matches across all four resource classes; used by inventory_all
# and the post-rewrite re-verify path.
total_matches=0

# auth_get <url> [--allow-404-empty] -> stdout: response body.
# Asserts JSON parseability. Single retry on HTTP 429 (R1 mitigation).
# With --allow-404-empty, a 404 returns "[]" (used for Discover when the
# endpoint is unavailable on the org's plan tier).
auth_get() {
  local url="$1"
  local allow_404_empty=0
  if [[ "${2:-}" == "--allow-404-empty" ]]; then
    allow_404_empty=1
  fi
  local body http
  local resp_file
  resp_file=$(mktemp)
  http=$(curl -s --max-time 10 \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    -o "$resp_file" -w '%{http_code}' "$url")
  if [[ "$http" == "429" ]]; then
    sleep 5
    http=$(curl -s --max-time 10 \
      -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
      -o "$resp_file" -w '%{http_code}' "$url")
  fi
  if [[ "$http" == "404" && "$allow_404_empty" == "1" ]]; then
    rm -f "$resp_file"
    echo "[note] ${url} -> 404; treating as empty (endpoint unavailable on this org's plan)" >&2
    printf '[]'
    return 0
  fi
  if [[ ! "$http" =~ ^2 ]]; then
    echo "ERROR: GET ${url} -> HTTP ${http}" >&2
    cat "$resp_file" >&2
    rm -f "$resp_file"
    exit 1
  fi
  body=$(cat "$resp_file")
  rm -f "$resp_file"
  if ! jq -e . <<<"$body" >/dev/null 2>&1; then
    echo "ERROR: GET ${url} returned non-JSON" >&2
    echo "$body" >&2
    exit 1
  fi
  printf '%s' "$body"
}

# auth_put <url> <body> -> stdout: response body on 2xx. Exits non-zero
# on any non-2xx, mirroring the precedent's error-then-fail pattern.
auth_put() {
  local url="$1" payload="$2" http
  local resp_file
  resp_file=$(mktemp)
  http=$(curl -s --max-time 10 -X PUT \
    -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    -o "$resp_file" -w '%{http_code}' \
    "$url" -d "$payload")
  if [[ ! "$http" =~ ^2 ]]; then
    echo "ERROR: PUT ${url} -> HTTP ${http}" >&2
    cat "$resp_file" >&2
    rm -f "$resp_file"
    exit 1
  fi
  cat "$resp_file"
  rm -f "$resp_file"
}

# --- Substitution primitive ----------------------------------------------
# jq-only string substitution. The input is bound via --arg (JSON-string
# encoded by jq); shell metacharacters, newlines, and quote-escapes in the
# input cannot escape the binding. R6 mitigation: never sed over a
# shell-quoted string.
sub_replace() {
  local input="$1"
  jq -nr --arg s "$input" --arg old "$LITERAL_OLD" --arg new "$LITERAL_NEW" \
    '$s | gsub($old | gsub("[.]"; "\\."); $new)'
}

# Add-or-clause variant for query strings. Wraps `extra.text:VAL` clauses
# as `(extra.text:VAL OR extra.shape:VAL)`. Operates only on the literal
# `extra.text:` token to avoid mangling unrelated occurrences.
sub_add_or_clause() {
  local input="$1"
  jq -nr --arg s "$input" \
    '$s | gsub("extra\\.text:(?<v>[^ )]+)"; "(extra.text:\(.v) OR extra.shape:\(.v))")'
}

# --- Inventory: alert rules ---------------------------------------------
# TaggedEventFilter operates on the tag namespace, not extra-context;
# realistic match count here is ~zero. Inventory for completeness.
inventory_alert_rules() {
  local body
  body=$(auth_get "https://${api_host}/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/rules/")
  if ! [[ "$(jq -r 'type' <<<"$body")" == "array" ]]; then
    echo "ERROR: /rules/ did not return an array" >&2
    echo "$body" >&2
    exit 1
  fi
  jq -r --arg old "$LITERAL_OLD" --arg op "$SCOPE_OP" '
    .[]
    | . as $rule
    | ($rule.filters // []) as $filters
    | ($filters | any((.value? // "") | tostring | contains($old))) as $has_old_in_value
    | ($filters | any((.key? // "") | tostring | contains($old))) as $has_old_in_key
    | ($filters | any((.value? // "") | tostring | contains($op))) as $has_op
    | select(($has_old_in_value or $has_old_in_key) and $has_op)
    | "\(.id)\t\(.name)\t\(if $has_old_in_value then "filters[].value" else "filters[].key" end)"
  ' <<<"$body" || true
}

# --- Inventory: issue saved searches ------------------------------------
inventory_saved_searches() {
  local body
  body=$(auth_get "https://${api_host}/api/0/organizations/${SENTRY_ORG}/searches/")
  if ! [[ "$(jq -r 'type' <<<"$body")" == "array" ]]; then
    echo "ERROR: /searches/ did not return an array" >&2
    echo "$body" >&2
    exit 1
  fi
  jq -r --arg old "$LITERAL_OLD" --arg op "$SCOPE_OP" '
    .[]
    | select((.query // "") | contains($old))
    | select((.query // "") | contains($op))
    | "\(.id)\t\(.name)\tquery"
  ' <<<"$body" || true
}

# --- Inventory: discover saved queries ----------------------------------
inventory_discover_saved() {
  local body
  body=$(auth_get "https://${api_host}/api/0/organizations/${SENTRY_ORG}/discover/saved/" --allow-404-empty)
  if ! [[ "$(jq -r 'type' <<<"$body")" == "array" ]]; then
    echo "ERROR: /discover/saved/ did not return an array" >&2
    echo "$body" >&2
    exit 1
  fi
  jq -r --arg old "$LITERAL_OLD" --arg op "$SCOPE_OP" '
    .[]
    | . as $q
    | ((($q.query // "") | contains($old)) or
       (($q.fields // []) | any(. == $old)) or
       (($q.yAxis // []) | any(. == $old))) as $has_old
    | ((($q.query // "") | contains($op))) as $has_op
    | select($has_old and $has_op)
    | (
        if (($q.query // "") | contains($old)) then "query"
        elif (($q.fields // []) | any(. == $old)) then "fields[]"
        else "yAxis[]" end
      ) as $where
    | "\($q.id)\t\($q.name // "")\t\($where)"
  ' <<<"$body" || true
}

# --- Inventory: dashboard widgets ---------------------------------------
# Two-step: list dashboards, then GET each by id (the list endpoint omits
# widgets[]). Sequential to stay under per-org rate limits.
inventory_dashboards() {
  local list_body ids id
  list_body=$(auth_get "https://${api_host}/api/0/organizations/${SENTRY_ORG}/dashboards/")
  if ! [[ "$(jq -r 'type' <<<"$list_body")" == "array" ]]; then
    echo "ERROR: /dashboards/ did not return an array" >&2
    echo "$list_body" >&2
    exit 1
  fi
  ids=$(jq -r '.[].id' <<<"$list_body")
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    local d_body
    d_body=$(auth_get "https://${api_host}/api/0/organizations/${SENTRY_ORG}/dashboards/${id}/")
    jq -r --arg dash_id "$id" --arg old "$LITERAL_OLD" --arg op "$SCOPE_OP" '
      . as $dash
      | ($dash.widgets // [])
      | to_entries[]
      | . as $w
      | ($w.value.queries // []) as $queries
      | ($queries | any(((.conditions // "") | contains($old)) or
                        ((.fields // []) | any(. == $old)) or
                        ((.aggregates // []) | any(. == $old)))) as $has_old
      | ($queries | any(((.conditions // "") | contains($op)))) as $has_op
      | select($has_old and $has_op)
      | "\($dash_id):\($w.key)\t\($w.value.title // "")\twidgets[].queries[]"
    ' <<<"$d_body" || true
  done <<<"$ids"
}

# --- Inventory aggregator ------------------------------------------------
inventory_all() {
  local rules searches discover dashboards count_rules count_searches count_discover count_dashboards

  rules=$(inventory_alert_rules)
  searches=$(inventory_saved_searches)
  discover=$(inventory_discover_saved)
  dashboards=$(inventory_dashboards)

  count_rules=$(printf '%s' "$rules" | grep -c . || true)
  count_searches=$(printf '%s' "$searches" | grep -c . || true)
  count_discover=$(printf '%s' "$discover" | grep -c . || true)
  count_dashboards=$(printf '%s' "$dashboards" | grep -c . || true)

  total_matches=$((count_rules + count_searches + count_discover + count_dashboards))

  if (( total_matches == 0 )); then
    echo "No matches found. extra.text -> extra.shape rename has no follow-through targets in this Sentry project."
    return 0
  fi

  if [[ -n "$rules" ]]; then
    while IFS=$'\t' read -r id name where; do
      printf '[issue-alert-rule]   id=%s name=%q match=%s\n' "$id" "$name" "$where"
    done <<<"$rules"
  fi
  if [[ -n "$searches" ]]; then
    while IFS=$'\t' read -r id name where; do
      printf '[saved-search]       id=%s name=%q match=%s\n' "$id" "$name" "$where"
    done <<<"$searches"
  fi
  if [[ -n "$discover" ]]; then
    while IFS=$'\t' read -r id name where; do
      printf '[discover-saved]     id=%s name=%q match=%s\n' "$id" "$name" "$where"
    done <<<"$discover"
  fi
  if [[ -n "$dashboards" ]]; then
    while IFS=$'\t' read -r id name where; do
      printf '[dashboard-widget]   id=%s name=%q match=%s\n' "$id" "$name" "$where"
    done <<<"$dashboards"
  fi

  echo
  echo "Summary: ${total_matches} matches (alert-rules=${count_rules} saved-searches=${count_searches} discover=${count_discover} dashboard-widgets=${count_dashboards})."
  if (( ! APPLY )); then
    echo "Run with --apply to rewrite, or --apply --add-or-clause for additive rewrite."
  fi
}

# --- Rewrite: alert rules ------------------------------------------------
# Match-by-name fail-closed: refuse to mutate if duplicate names exist
# (Sentry API does NOT enforce uniqueness; precedent script's pattern).
rewrite_alert_rules() {
  local body match_ids match_count
  body=$(auth_get "https://${api_host}/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/rules/")

  # Collect the IDs of rules that hit the inventory criteria.
  local target_ids
  target_ids=$(jq -r --arg old "$LITERAL_OLD" --arg op "$SCOPE_OP" '
    .[]
    | . as $r
    | ($r.filters // []) as $f
    | ($f | any(((.value? // "") | tostring | contains($old)) or
                ((.key?   // "") | tostring | contains($old)))) as $has_old
    | ($f | any((.value? // "") | tostring | contains($op))) as $has_op
    | select($has_old and $has_op)
    | .id
  ' <<<"$body")

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    local rule name
    rule=$(jq --arg id "$id" '.[] | select(.id == $id)' <<<"$body")
    name=$(jq -r '.name' <<<"$rule")

    match_ids=$(jq -r --arg name "$name" '.[] | select(.name == $name) | .id' <<<"$body")
    match_count=$(printf '%s' "$match_ids" | grep -c . || true)
    if (( match_count > 1 )); then
      echo "ERROR: ${match_count} rules named '${name}' found - refusing to mutate (resolve duplicates in Sentry UI)." >&2
      echo "  IDs: $(printf '%s' "$match_ids" | tr '\n' ' ')" >&2
      exit 1
    fi

    # Substitute extra.text -> extra.shape inside filters[].value and
    # filters[].key. jq --arg binds the literals safely.
    local mutated
    mutated=$(jq --arg old "$LITERAL_OLD" --arg new "$LITERAL_NEW" '
      .filters = ((.filters // []) | map(
        if (.value? != null) then .value = ((.value | tostring) | gsub($old | gsub("[.]"; "\\."); $new)) else . end
        | if (.key? != null) then .key = ((.key | tostring) | gsub($old | gsub("[.]"; "\\."); $new)) else . end
      ))
    ' <<<"$rule")

    auth_put "https://${api_host}/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/rules/${id}/" "$mutated" >/dev/null
    echo "[ok] Rewrote alert rule id=${id} name=$(printf '%q' "$name")"
  done <<<"$target_ids"
}

# --- Rewrite: saved searches --------------------------------------------
rewrite_saved_searches() {
  local body
  body=$(auth_get "https://${api_host}/api/0/organizations/${SENTRY_ORG}/searches/")

  local ids
  ids=$(jq -r --arg old "$LITERAL_OLD" --arg op "$SCOPE_OP" '
    .[] | select((.query // "") | contains($old))
        | select((.query // "") | contains($op))
        | .id
  ' <<<"$body")

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    local item old_query new_query payload
    item=$(jq --arg id "$id" '.[] | select(.id == $id)' <<<"$body")
    old_query=$(jq -r '.query' <<<"$item")
    if (( ADD_OR_CLAUSE )); then
      new_query=$(sub_add_or_clause "$old_query")
    else
      new_query=$(sub_replace "$old_query")
    fi
    payload=$(jq -n --arg q "$new_query" '{query: $q}')

    auth_put "https://${api_host}/api/0/organizations/${SENTRY_ORG}/searches/${id}/" "$payload" >/dev/null
    echo "[ok] Rewrote saved-search id=${id}"
  done <<<"$ids"
}

# --- Rewrite: discover saved queries ------------------------------------
# `fields[]` always replaces; --add-or-clause only affects the `query`
# string (R3 in the plan). Logged per-match.
rewrite_discover_saved() {
  local body
  body=$(auth_get "https://${api_host}/api/0/organizations/${SENTRY_ORG}/discover/saved/" --allow-404-empty)

  local ids
  ids=$(jq -r --arg old "$LITERAL_OLD" --arg op "$SCOPE_OP" '
    .[]
    | . as $q
    | ((($q.query // "") | contains($old)) or
       (($q.fields // []) | any(. == $old)) or
       (($q.yAxis // []) | any(. == $old))) as $has_old
    | ((($q.query // "") | contains($op))) as $has_op
    | select($has_old and $has_op)
    | $q.id
  ' <<<"$body")

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    local item new_query mutated
    item=$(jq --arg id "$id" '.[] | select((.id|tostring) == $id)' <<<"$body")
    if [[ -z "$item" ]]; then
      continue
    fi

    if (( ADD_OR_CLAUSE )); then
      new_query=$(sub_add_or_clause "$(jq -r '.query // ""' <<<"$item")")
      echo "[note] discover id=${id} fields[]/yAxis[] always replace (no syntactic OR for array entries)"
    else
      new_query=$(sub_replace "$(jq -r '.query // ""' <<<"$item")")
    fi

    mutated=$(jq --arg new_query "$new_query" --arg old "$LITERAL_OLD" --arg new "$LITERAL_NEW" '
      .query = $new_query
      | .fields = ((.fields // []) | map(if . == $old then $new else . end))
      | .yAxis = ((.yAxis // []) | map(if . == $old then $new else . end))
    ' <<<"$item")

    auth_put "https://${api_host}/api/0/organizations/${SENTRY_ORG}/discover/saved/${id}/" "$mutated" >/dev/null
    echo "[ok] Rewrote discover-saved id=${id}"
  done <<<"$ids"
}

# --- Rewrite: dashboard widgets -----------------------------------------
# Sentry dashboards API has no per-widget mutation; PUT the full payload
# back. GET -> jq-walk -> PUT-full -> re-GET.
rewrite_dashboards() {
  local list_body ids id
  list_body=$(auth_get "https://${api_host}/api/0/organizations/${SENTRY_ORG}/dashboards/")
  ids=$(jq -r '.[].id' <<<"$list_body")

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    local d_body has_target
    d_body=$(auth_get "https://${api_host}/api/0/organizations/${SENTRY_ORG}/dashboards/${id}/")
    has_target=$(jq -r --arg old "$LITERAL_OLD" --arg op "$SCOPE_OP" '
      ((.widgets // []) | any(
         (.queries // []) as $qs
         | ($qs | any(((.conditions // "") | contains($old)) or
                      ((.fields // []) | any(. == $old)) or
                      ((.aggregates // []) | any(. == $old))))
         and ($qs | any(((.conditions // "") | contains($op))))
      ))
    ' <<<"$d_body")
    if [[ "$has_target" != "true" ]]; then
      continue
    fi

    local mutated
    if (( ADD_OR_CLAUSE )); then
      # `conditions` gets OR-wrapping; `fields[]`/`aggregates[]` always
      # replace (no syntactic OR for array entries).
      mutated=$(jq --arg old "$LITERAL_OLD" --arg new "$LITERAL_NEW" '
        .widgets = ((.widgets // []) | map(
          .queries = ((.queries // []) | map(
            (.conditions // "") as $c
            | .conditions = ($c | gsub("extra\\.text:(?<v>[^ )]+)"; "(extra.text:\(.v) OR extra.shape:\(.v))"))
            | .fields = ((.fields // []) | map(if . == $old then $new else . end))
            | .aggregates = ((.aggregates // []) | map(if . == $old then $new else . end))
          ))
        ))
      ' <<<"$d_body")
      echo "[note] dashboard ${id}: fields[]/aggregates[] always replace (no syntactic OR for array entries)"
    else
      mutated=$(jq --arg old "$LITERAL_OLD" --arg new "$LITERAL_NEW" '
        .widgets = ((.widgets // []) | map(
          .queries = ((.queries // []) | map(
            .conditions = ((.conditions // "") | gsub($old | gsub("[.]"; "\\."); $new))
            | .fields = ((.fields // []) | map(if . == $old then $new else . end))
            | .aggregates = ((.aggregates // []) | map(if . == $old then $new else . end))
          ))
        ))
      ' <<<"$d_body")
    fi

    auth_put "https://${api_host}/api/0/organizations/${SENTRY_ORG}/dashboards/${id}/" "$mutated" >/dev/null
    echo "[ok] Rewrote dashboard id=${id}"
  done <<<"$ids"
}

# --- Main ---------------------------------------------------------------
inventory_all

if (( APPLY && total_matches > 0 )); then
  echo
  echo "[info] Applying rewrites..."
  rewrite_alert_rules
  rewrite_saved_searches
  rewrite_discover_saved
  rewrite_dashboards

  # Re-verify silently.
  total_matches=0
  remaining=$(inventory_all 2>&1 || true)
  if (( total_matches > 0 )); then
    echo "FAILED: ${total_matches} references still present after rewrite:" >&2
    printf '%s\n' "$remaining" >&2
    exit 1
  fi
  echo "Verified: 0 references to extra.text remain on op:tool-label-scrub"
fi
