# shellcheck shell=bash
# Sourced STOCK preflight gate for every destroy-shaped apply_target in
# .github/workflows/apply-web-platform-infra.yml (#6453).
#
# EXTRACTED + SOURCED: the workflow's five destroy-guard plan steps AND
# tests/scripts/test-stock-preflight-gate.sh source this file and call
# stock_preflight_gate directly, so CI runs the SAME bytes the test exercises
# (no re-derived inline jq to drift). Mirrors tests/scripts/lib/web2-recreate-gate.sh.
#
# WHAT IT GUARDS — and what it deliberately does NOT:
#   A terraform `-replace` DESTROYS BEFORE IT CREATES. It therefore frees its own
#   server slot, so the Hetzner *account cap* NEVER blocks a recreate — a
#   `free_slots == 0` preflight would abort every recreate for no reason (#6453
#   asked for exactly that; it was dropped). What actually strands the fleet is DC
#   *stock*: the destroy succeeds, the create fails `resource_unavailable`, and the
#   fleet is short a host with no rollback. That is #6393, which wedged the web-1
#   prod deploy leg ~10h (PIR corrected 2026-07-14, #6400).
#
#   This gate asserts every server the plan will CREATE is orderable in its target
#   location BEFORE the destroy runs. It is a TRIPWIRE, not a routine gate
#   (matching apply-web-platform-infra.yml:447).
#
# NO [ack-destroy] BYPASS: a destructive prod host recreate is authorized by the
# menu-ack workflow_dispatch (hr-menu-option-ack-not-prod-write-auth), never a
# commit trailer — and an ack cannot conjure stock. Matches the sibling gates
# (web2-recreate, inngest-host-replace, registry-host-replace, git-data-host-replace),
# none of which carry an override.
#
# `available` vs `.supported` — LOAD-BEARING:
#   /v1/datacenters exposes BOTH. `.supported` (24 per EU DC) is what a DC *can*
#   host; `.server_types.available` is what is *orderable right now*. A gate built
#   on `.supported` passes the live trap. The `hcloud` CLI has the same trap:
#   `hcloud server-type list -o columns=name,location` reports the SUPPORTED set —
#   on 2026-07-15 it said `cx33 -> fsn1,nbg1,hel1` while cx33 was orderable NOWHERE.
#   Do NOT "simplify" this to the CLI.
#
# Stock is time-varying on an HOURS timescale: cx33 went from "orderable in hel1"
# to orderable in ZERO datacenters within ~3h on 2026-07-15 (hel1's available count
# dropped 14 -> 12). Hence: query live on every dispatch, and NEVER encode today's
# availability in a test (the suite uses synthesized fixtures via the _stock_fetch
# seam — cq-test-fixtures-synthesized-only).
#
# Each Hetzner LOCATION maps to exactly ONE datacenter (fsn1 -> fsn1-dc14), so there
# is no sibling-DC fallback within a location.
#
# FAIL-CLOSED on every resolution/API failure: an unreachable API is not evidence of
# availability. A blocked recreate is recoverable; a stranded fleet is a deploy freeze.

# EU allow-set — mirrors the residency validation at
# apps/web-platform/infra/variables.tf:94-96 (GDPR residency, CLO T-1). /v1/datacenters
# also returns ash-dc1 (US), hil-dc1 (US) and sin-dc1 (Singapore); an unfiltered
# "orderable elsewhere" suggestion would advise putting a prod host in Singapore.
STOCK_PREFLIGHT_EU_LOCATIONS="${STOCK_PREFLIGHT_EU_LOCATIONS:-nbg1 fsn1 hel1}"

# Injectable fetch seam. The test redefines this to cat a synthesized fixture, so the
# suite is hermetic (no network, no HCLOUD_TOKEN). Never inline curl at a call site.
HCLOUD_API="${HCLOUD_API:-https://api.hetzner.cloud/v1}"
_stock_fetch() {
  curl -sS --max-time 20 -H "Authorization: Bearer ${HCLOUD_TOKEN:-}" "${HCLOUD_API}$1"
}

# _stock_eu_locations_for <server_types_json> <datacenters_json> <type_id>
# Echoes the EU-filtered location names where <type_id> is orderable (space-separated).
_stock_eu_locations_for() {
  local dcs_json="$2" type_id="$3" out=() loc
  local all
  all=$(printf '%s' "$dcs_json" | jq -r --argjson i "$type_id" \
    '.datacenters[] | select(.server_types.available | index($i)) | .location.name' 2>/dev/null | sort -u)
  for loc in $all; do
    case " $STOCK_PREFLIGHT_EU_LOCATIONS " in
      *" $loc "*) out+=("$loc") ;;
    esac
  done
  printf '%s' "${out[*]-}"
}

# stock_preflight <server_type> <location>
# rc=0  -> orderable in <location> right now
# rc=1  -> NOT orderable, OR unknown type/location, OR the API could not be reached
# Emits a ::error:: on abort. The stock-miss and API-blip messages are DISTINCT so an
# operator does not read a transient blip as a real shortage and file a spurious #6463 dup.
stock_preflight() {
  local want_type="$1" want_loc="$2"
  local types_json dcs_json type_id dc_name orderable elsewhere

  if [[ -z "$want_type" || -z "$want_loc" ]]; then
    echo "::error::stock-preflight ABORT: called without server_type/location (got '${want_type}'/'${want_loc}'). Fail-closed." >&2
    return 1
  fi

  # Resolve the type by NAME (not ?per_page=50 — that silently encodes "Hetzner has
  # <=50 types" and fails CLOSED if one ever lands on page 2, aborting a legitimate
  # recreate). Unknown type => 0 results.
  types_json=$(_stock_fetch "/server_types?name=${want_type}" 2>/dev/null) || types_json=""
  if [[ -z "$types_json" ]] || ! printf '%s' "$types_json" | jq -e '.server_types' >/dev/null 2>&1; then
    echo "::error::stock-preflight ABORT: cannot PROVE stock for '${want_type}' in '${want_loc}' (Hetzner API unreachable or malformed at /server_types). An unreachable API is not evidence of availability. Re-dispatch." >&2
    return 1
  fi
  type_id=$(printf '%s' "$types_json" | jq -r '.server_types[0].id // empty' 2>/dev/null)
  if [[ -z "$type_id" ]]; then
    echo "::error::stock-preflight ABORT: unknown server_type '${want_type}' (no match at /server_types?name=). Fail-closed — a typo must never authorize a destroy." >&2
    return 1
  fi

  dcs_json=$(_stock_fetch "/datacenters" 2>/dev/null) || dcs_json=""
  if [[ -z "$dcs_json" ]] || ! printf '%s' "$dcs_json" | jq -e '.datacenters' >/dev/null 2>&1; then
    echo "::error::stock-preflight ABORT: cannot PROVE stock for '${want_type}' in '${want_loc}' (Hetzner API unreachable or malformed at /datacenters). An unreachable API is not evidence of availability. Re-dispatch." >&2
    return 1
  fi

  # Each location maps to exactly one datacenter; no sibling-DC fallback.
  dc_name=$(printf '%s' "$dcs_json" | jq -r --arg l "$want_loc" \
    '.datacenters[] | select(.location.name == $l) | .name' 2>/dev/null | head -1)
  if [[ -z "$dc_name" ]]; then
    echo "::error::stock-preflight ABORT: unknown location '${want_loc}' (no datacenter at /datacenters). Fail-closed." >&2
    return 1
  fi

  # .available (orderable NOW) — never .supported.
  orderable=$(printf '%s' "$dcs_json" | jq -r --arg d "$dc_name" --argjson i "$type_id" \
    '.datacenters[] | select(.name == $d) | (.server_types.available | index($i)) != null' 2>/dev/null)
  if [[ "$orderable" == "true" ]]; then
    return 0
  fi

  elsewhere=$(_stock_eu_locations_for "$types_json" "$dcs_json" "$type_id")
  echo "::error::stock-preflight ABORT: server_type '${want_type}' is NOT orderable in '${want_loc}' today (orderable in EU: ${elsewhere:-<none>}). A -replace DESTROYS before it creates — this recreate would strand the fleet with no rollback (#6393, #6463)." >&2
  # The warm-standby tine is load-bearing: hcloud_server_network.web is a SEPARATE
  # for_each'd resource — an ADDITIVE online attach (apps/web-platform/infra/network.tf:9-13),
  # deliberately not an inline network{} block (which would force-replace the host). So a
  # private-NIC or /workspaces-volume repair is NOT a recreate and needs NO stock. That is how
  # web-2's private IP was restored 2026-07-13 without recreating it. Omitting this tine funnels
  # a free repair into #6463 (a cost/HA escalation) — the opposite of the intent.
  #
  # ...but it is WEB-2-SPECIFIC: apply_target=warm-standby targets hcloud_server_network.web
  # ["web-2"], hcloud_volume.workspaces["web-2"] and hcloud_volume_attachment.workspaces
  # ["web-2"] and NOTHING else (apply-web-platform-infra.yml:791-796). Offering it on the
  # inngest/registry/git-data aborts would point an operator at a dispatch that does nothing
  # for their host — misdirection in the one message they read during a prod abort. So the
  # gate suppresses it for any other address. _STOCK_TINE_ADDR is set per-address by
  # stock_preflight_gate; when UNSET (a direct operator probe — the plan's
  # discoverability_test) the tine stands, because web-2 is that probe's documented subject.
  if [[ -z "${_STOCK_TINE_ADDR+x}" || "${_STOCK_TINE_ADDR}" == 'hcloud_server.web["web-2"]' ]]; then
    echo "::error::  - If you only need the private NIC or the /workspaces volume re-attached, this is NOT a recreate: dispatch apply_target=warm-standby (additive, no destroy, no stock required). See apply-web-platform-infra.yml:451." >&2
  fi
  echo "::error::  - If the host genuinely must be reborn: see #6463 (type/DC change is an operator cost/HA decision)." >&2
  echo "::error::  - Stock is time-varying (cx33 went orderable->nowhere in ~3h on 2026-07-15) — re-run later." >&2
  echo "::error::  Do NOT bypass." >&2
  return 1
}

# stock_preflight_gate <terraform-show-json-file>
# Extracts every hcloud_server the plan will CREATE and preflights each one.
# rc=0 iff every planned server create is orderable in its target location.
#
# Extraction MUSTs (both fixture-proven — see the sibling test):
#   - select(.type == "hcloud_server") FIRST. Sibling entries carry change.after
#     WITHOUT these keys (hcloud_server_network -> ["ip"];
#     hcloud_volume_attachment -> ["volume_id"]), so an unfiltered
#     .resource_changes[].change.after.server_type yields null for 2-5 entries per path.
#   - filter .change.actions | index("create"). A no-op entry ALSO carries
#     after.server_type, so an unfiltered gate would preflight untouched hosts.
#     (delete+create -> both actions present, so a -replace is correctly caught.)
stock_preflight_gate() {
  local plan_json="$1" pairs n=0 rc=0 addr stype sloc

  if [[ -z "$plan_json" || ! -r "$plan_json" ]]; then
    echo "::error::stock-preflight ABORT: plan JSON '${plan_json}' missing or unreadable. Fail-closed." >&2
    return 1
  fi
  if ! jq -e '.resource_changes' "$plan_json" >/dev/null 2>&1; then
    echo "::error::stock-preflight ABORT: '${plan_json}' has no .resource_changes (not a terraform show -json document). Fail-closed." >&2
    return 1
  fi

  pairs=$(jq -r '
    .resource_changes[]
    | select(.type == "hcloud_server")
    | select(.change.actions | index("create"))
    | [.address, (.change.after.server_type // ""), (.change.after.location // "")]
    | @tsv
  ' "$plan_json" 2>/dev/null)

  if [[ -z "$pairs" ]]; then
    # No server create planned => nothing to preflight. A pure in-place update, a
    # volume-only plan, or a no-op is legitimately out of this gate's scope.
    return 0
  fi

  while IFS=$'\t' read -r addr stype sloc; do
    [[ -z "$addr" ]] && continue
    n=$((n + 1))
    if [[ -z "$stype" || -z "$sloc" ]]; then
      echo "::error::stock-preflight ABORT: ${addr} plans a create but carries no server_type/location in change.after. Fail-closed — cannot prove stock for an unknown target." >&2
      rc=1
      continue
    fi
    # _STOCK_TINE_ADDR scopes the web-2-only warm-standby suggestion to web-2's address.
    if ! _STOCK_TINE_ADDR="$addr" stock_preflight "$stype" "$sloc"; then
      echo "::error::  ...while preflighting ${addr} (${stype} @ ${sloc})." >&2
      rc=1
    fi
  done <<<"$pairs"

  if [[ "$n" -eq 0 ]]; then
    return 0
  fi
  return "$rc"
}
