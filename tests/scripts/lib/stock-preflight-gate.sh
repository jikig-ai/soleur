# shellcheck shell=bash
# Sourced STOCK preflight gate for every apply_target whose plan can fail on Hetzner
# capacity in .github/workflows/apply-web-platform-infra.yml (#6453).
#
# NOT "every destroy-shaped target" any more: #6730's `web-host-create` is purely ADDITIVE
# and sources this gate too. The wording mattered — a reader who took "destroy-shaped" as
# the membership rule would conclude an additive path is out of scope, which is how a birth
# ships without a capacity check.
#
# EXTRACTED + SOURCED: the workflow's six plan steps (inngest-host-replace,
# registry-host-replace, registry-region-migrate, git-data-host-replace, web-host-create,
# web-host-replace) AND
# tests/scripts/test-stock-preflight-gate.sh source this file and call
# stock_preflight_gate directly, so CI runs the SAME bytes the test exercises
# (no re-derived inline jq to drift). Mirrors the sibling *-gate.sh files in this directory.
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
#   This gate asserts Hetzner REPORTS every server the plan will CREATE as available in its target
#   location BEFORE the destroy runs. It is a TRIPWIRE, not a routine gate — matching
#   the host_creates HALT in apply-web-platform-infra.yml (search: "This is a TRIPWIRE,
#   not a routine gate").
#
# NO [ack-destroy] BYPASS: a destructive prod host recreate is authorized by the
# menu-ack workflow_dispatch (hr-menu-option-ack-not-prod-write-auth), never a
# commit trailer — and an ack cannot conjure stock. Matches the sibling gates
# (inngest-host-replace, registry-host-replace, registry-region-migrate,
# git-data-host-replace, web-host-replace), none of which carry an override.
#
# PRESENCE vs `available` — LOAD-BEARING (rewritten 2026-10-05, after Hetzner removed GET /datacenters):
#   Hetzner deleted /v1/datacenters (HTTP 410 `deprecated_api_endpoint`; changelog
#   https://docs.hetzner.cloud/changelog#2026-06-02-datacenters-deprecated). The replacement is the
#   `locations[]` array on each server type: GET /v1/server_types?name=<type> ->
#   server_types[].locations[] = [{id,name,available,recommended,deprecation}]. PRESENCE of a location
#   entry means the type is *supported* there (what it CAN host); `available` is the indicator that it is
#   orderable right now — Hetzner's own wording is an indicator, not a guarantee. A gate built on presence
#   passes the live trap: on 2026-07-15 the `hcloud` CLI said `cx33 -> fsn1,nbg1,hel1` (the SUPPORTED set)
#   while cx33 was orderable NOWHERE. Do NOT "simplify" this to presence or to the CLI. The gate authorizes
#   ONLY on the JSON boolean `true` for exactly one matching type and exactly one matching location.
#   `available: true` is not a reservation: a replace can still destroy and then fail to create. The gate
#   narrows that window to Hetzner's own signal; it does not remove it.
#   Re-evaluation probe for ADR-154's old trigger (a type back in stock): GET /v1/server_types?name=cx33
#   -> locations[].available.
#
# Stock is time-varying on an HOURS timescale: cx33 went from "orderable in hel1"
# to orderable in ZERO datacenters within ~3h on 2026-07-15 (hel1's available count
# dropped 14 -> 12). Hence: query live on every dispatch, and NEVER encode today's
# availability in a test (the suite uses synthesized fixtures via the _stock_fetch
# seam — cq-test-fixtures-synthesized-only).
#
# Stock is reported per LOCATION (locations[].available): there is no per-datacenter breakdown and no
# sibling fallback within a location.
#
# FAIL-CLOSED on every resolution/API failure: an unreachable API is not evidence of
# availability. A blocked recreate is recoverable; a stranded fleet is a deploy freeze.

# EU allow-set — mirrors the `web_hosts` residency validation in
# apps/web-platform/infra/variables.tf (search: "must be an EU Hetzner DC") — GDPR
# residency, CLO T-1. A type's locations[]
# also lists ash (US), hil (US) and sin (Singapore); an unfiltered
# "orderable elsewhere" suggestion would advise putting a prod host in Singapore.
STOCK_PREFLIGHT_EU_LOCATIONS="${STOCK_PREFLIGHT_EU_LOCATIONS:-nbg1 fsn1 hel1}"

# Injectable fetch seam. The test redefines this to cat a synthesized fixture, so the
# suite is hermetic (no network, no HCLOUD_TOKEN). Never inline curl at a call site.
HCLOUD_API="${HCLOUD_API:-https://api.hetzner.cloud/v1}"
# `--fail-with-body` (curl >= 7.76): a non-2xx answer exits 22 and still prints the body. Without it `curl -sS`
# exits 0 on a 410, and the caller would have to guess from the body alone whether it was told "no".
_stock_fetch() {
  curl -sS --fail-with-body --max-time 20 -H "Authorization: Bearer ${HCLOUD_TOKEN:-}" "${HCLOUD_API}$1"
}

# _stock_verdict <types_json> <type> <loc>
#   -> ORDERABLE | UNAVAILABLE | UNKNOWN_TYPE | UNKNOWN_LOCATION | MALFORMED:<reason>
# ONE jq program, ONE token. Only the exact string ORDERABLE authorizes anything. The caller captures it as
# `verdict=$(_stock_verdict ...) || verdict=""` — jq prints the verdict of the FIRST document and then exits 5 on
# trailing junk (`<valid doc>garbage`), so a bare capture would read ORDERABLE off a body that is not one document.
# The type is selected by NAME, never by position: if `?name=` were ever ignored the list would hold other types and
# [0] would answer about the wrong one. `type != "object"` stays LEFT of has("error") (jq `or` short-circuits).
_stock_verdict() {
  printf '%s' "$1" | jq -r --arg t "$2" --arg l "$3" '
    if (type != "object") or has("error") or ((.server_types | type) != "array") then "MALFORMED:shape"
    elif (.server_types | length) == 0 then "UNKNOWN_TYPE"
    else [.server_types[] | select(.name == $t)] as $m
      | if   ($m | length) == 0 then "MALFORMED:filter-ignored"
        elif ($m | length) >  1 then "MALFORMED:duplicate-type"
        elif ($m[0].locations | type) != "array" then "MALFORMED:locations"
        else [$m[0].locations[] | select(.name == $l)] as $e
          | if   ($e | length) == 0 then "UNKNOWN_LOCATION"
            elif ($e | length) >  1 then "MALFORMED:duplicate-location"
            elif ($e[0].available | type) != "boolean" then "MALFORMED:available"
            elif $e[0].available then "ORDERABLE" else "UNAVAILABLE" end
        end
    end' 2>/dev/null
}

# _stock_eu_locations_for <types_json> <type>
# Echoes the EU-filtered location names where <type> is reported available (space-separated). ADVISORY ONLY: it
# runs on the UNAVAILABLE arm and never influences the verdict or the exit code; a failure degrades the `<none>`
# text. Strict `== true` (a string "true" or 1 is not suggested) and the allow-set intersection happens INSIDE jq,
# so no location name can word-split into a shell loop. Takes only what it reads.
_stock_eu_locations_for() {
  printf '%s' "$1" | jq -r --arg t "$2" --arg eu "$STOCK_PREFLIGHT_EU_LOCATIONS" '
    ($eu | split(" ") | map(select(. != ""))) as $allow
    | [.server_types[] | select(.name == $t)] | if length == 1 then .[0].locations[]? else empty end
    | select(.available == true and (.name | IN($allow[]))) | .name' 2>/dev/null | sort -u | paste -sd' ' -
}

# stock_preflight <server_type> <location>
# rc=0  -> Hetzner REPORTS the type available in <location> right now (an indicator, not a reservation)
# rc=1  -> reported unavailable, OR unknown type/location, OR the API could not be read
# Emits a ::error:: on abort. The stock-miss and API-blip messages are DISTINCT so an
# operator does not read a transient blip as a real shortage and file a spurious #6463 dup.
stock_preflight() {
  local want_type="$1" want_loc="$2"
  local types_json="" verdict="" reason="" elsewhere="" fetch_rc=0

  if [[ -z "$want_type" || -z "$want_loc" ]]; then
    echo "::error::stock-preflight ABORT: called without server_type/location (got '${want_type}'/'${want_loc}'). Fail-closed." >&2
    return 1
  fi

  # Shape-guard both values BEFORE they reach a URL query. `want_type` is interpolated into
  # `/server_types?name=${want_type}`, so a value carrying `&name=` (or `#`, or a space) would
  # make Hetzner answer about a DIFFERENT type than terraform is about to order — the gate
  # returns green and the create still fails, i.e. exactly the stranding it exists to prevent.
  # var.registry_server_type carries no terraform validation (inngest_server_type and, since
  # #6570, git_data_server_type both do — see their `validation` blocks in variables.tf), and
  # even those only constrain the PREFIX, so the plan JSON is not a trusted source of shape
  # here. Real Hetzner ids are lowercase alnum (cx33, cpx41, cax11); locations are
  # lowercase alnum with an optional dash (fsn1, hel1, ash-dc1). Anything else fails closed —
  # a value we cannot safely ask about is not evidence of availability.
  if [[ ! "$want_type" =~ ^[a-z0-9]+$ ]]; then
    echo "::error::stock-preflight ABORT: server_type '${want_type}' is not a valid Hetzner type name (expected lowercase alphanumeric). Fail-closed — a value that cannot be safely queried must never authorize a destroy." >&2
    return 1
  fi
  if [[ ! "$want_loc" =~ ^[a-z0-9-]+$ ]]; then
    echo "::error::stock-preflight ABORT: location '${want_loc}' is not a valid Hetzner location name (expected lowercase alphanumeric/dash). Fail-closed." >&2
    return 1
  fi

  # ONE fetch. Resolve the type by NAME (not ?per_page=50 — that silently encodes "Hetzner has <=50 types" and fails
  # CLOSED if one ever lands on page 2). `fetch_rc` is captured, not discarded: with --fail-with-body a non-2xx answer
  # exits 22, and the abort text must be able to tell a changed API contract from a flaky network.
  types_json=$(_stock_fetch "/server_types?name=${want_type}" 2>/dev/null) || fetch_rc=$?
  verdict=""
  if [[ "$fetch_rc" -ne 0 ]]; then
    reason="curl exit ${fetch_rc}"
  elif [[ -z "$types_json" ]]; then
    reason="empty body"
  else
    # `|| verdict=""` — see _stock_verdict. NEVER a bare assignment, never `local v=$(...)` (masks the status).
    verdict=$(_stock_verdict "$types_json" "$want_type" "$want_loc") || verdict=""
  fi

  # Exactly one `return 0` in this function: the exact token ORDERABLE. Everything else, including an empty or
  # multi-line verdict, aborts. Four DISTINCT classes with different advice, so an operator mid-incident does not
  # read a changed contract as a shortage or a typo as an outage.
  case "$verdict" in
    ORDERABLE) return 0 ;;
    UNAVAILABLE) ;;   # falls through to the stock-miss abort and the remediation menu below
    UNKNOWN_TYPE)
      echo "::error::stock-preflight ABORT: unknown server_type '${want_type}' (no match at /server_types?name=). Fail-closed — a typo must never authorize a destroy." >&2
      return 1 ;;
    UNKNOWN_LOCATION)
      echo "::error::stock-preflight ABORT: unknown location '${want_loc}' for server_type '${want_type}' (not in its /server_types locations[]: a mistyped location, or a type Hetzner does not offer there — check \`location\` in the plan and variables.tf). Fail-closed." >&2
      return 1 ;;
    *)
      if [[ -z "$reason" ]]; then reason="${verdict:-unparseable body}"; fi
      if [[ "$reason" == curl* || "$reason" == "empty body" ]]; then
        echo "::error::stock-preflight ABORT: cannot PROVE stock for '${want_type}' in '${want_loc}' (Hetzner API unreachable at /server_types: ${reason}). An unreachable API is not evidence of availability. Retry: re-dispatch; if it repeats on consecutive dispatches the API contract has likely changed — see the header of this file for the changelog URL." >&2
      else
        echo "::error::stock-preflight ABORT: cannot PROVE stock for '${want_type}' in '${want_loc}' (Hetzner answered /server_types in a shape this gate does not accept: ${reason}). This is NOT a stock shortage: the API contract may have changed. Open an issue naming this line; do NOT blind re-dispatch." >&2
      fi
      return 1 ;;
  esac

  elsewhere=$(_stock_eu_locations_for "$types_json" "$want_type")
  echo "::error::stock-preflight ABORT: server_type '${want_type}' is reported NOT orderable in '${want_loc}' today by Hetzner (orderable in EU: ${elsewhere:-<none>}). That is an indicator, not a guarantee, so it can block a replace that would have succeeded — but a -replace DESTROYS before it creates, and this recreate would strand the fleet with no rollback if the create fails (#6393, #6463)." >&2
  # REMEDIATION MENU — order is the point: the cheapest correct action first, so an operator
  # reading this mid-abort does not escalate to a cost/HA decision when waiting would do.
  #
  # DELETED 2026-07-20 (#6575): the warm-standby tine. It offered a genuinely FREE repair —
  # "if you only need the private NIC or the /workspaces volume re-attached, that is not a
  # recreate; dispatch apply_target=warm-standby, no stock required" — and it was web-2-scoped
  # via a per-address _STOCK_TINE_ADDR setter. With web-2 retired (#6538) and the warm_standby
  # job removed, BOTH the subject and the dispatch are gone. State the loss plainly rather than
  # paper over it: **no additive dispatch remains** that can re-attach a NIC or a workspaces
  # volume. The Terraform shape is unchanged — hcloud_server_network.web is still a SEPARATE
  # for_each'd resource, an "ADDITIVE online attach" (network.tf) — so the repair is still
  # non-destructive; only the
  # one-click route to it is gone. (This block used to add "not an inline network{} block that
  # would force-replace the host". That premise was RETRACTED 2026-09-22 by #8539: at hcloud
  # provider v1.63.0 `network` is not ForceNew and updates in place. The conclusion above is
  # unaffected — a separate additive attach is non-destructive either way — but the reason was
  # wrong, and this is operator-facing text read during a blocked recreate.) It now requires the operator-local full apply per the
  # OPERATOR_APPLIED_EXCLUSIONS contract (ADR-096).
  #
  # WHY THE WEB-1 CLAUSE BELOW IS CONDITIONALLY WORDED: there are SIX callers, and only two
  # of them (#6730's web-host-create and #6969's web-host-replace) preflight a web host. The
  # other four — inngest-host-replace, registry-host-replace, registry-region-migrate,
  # git-data-host-replace — never do. So the web-1 specifics stay a guarded "if this host is
  # web-1" clause rather than an unconditional claim, which would misdirect the four non-web
  # paths in the one message they read during a blocked prod recreate.
  #
  # NOTE web-host-replace refuses web-1 by name (it is the LUKS-pinned host), so on that
  # caller the clause is reachable only for a NON-web-1 key. It stays conditional anyway: the
  # condition is on the host the PLAN creates, not on the dispatch key, and the six callers
  # do not share a key space.
  #
  # CORRECTED at #6730: this comment previously read "after #6575, NO production call site
  # preflights a web host at all. The four surviving callers are …". Both halves went false
  # the moment web-host-create landed, and the stale version made the conditional clause look
  # like dead code — one cleanup away from being deleted just as it became reachable.
  # The retry advice is correct on every caller, but the REASON differs by shape, and an
  # additive caller told "nothing has been destroyed — this gate runs BEFORE the destroy" is
  # being reassured about a destroy that was never going to happen. Both framings are stated
  # so the message is true on the path the operator is actually on.
  echo "::error::  - PRIMARY: wait and re-dispatch. A retry costs nothing — on a -replace caller because this gate runs BEFORE the destroy, and on an additive caller (web-host-create) because nothing existed to destroy. Stock is time-varying on an HOURS timescale (cx33 went orderable -> nowhere in ~3h on 2026-07-15)." >&2
  echo "::error::  - SECONDARY: change server_type WITHIN the same location (the 'orderable in EU' list above is what is actually orderable right now). This is an operator cost/HA decision — see #6463 — not a free action." >&2
  echo "::error::  - IF THIS HOST IS web-1: change server_type within hel1 ONLY; do NOT relocate it. hcloud_server.web pins its location precisely because 'a location change would force-REPLACE the live prod host' (server.tf), and hcloud_volume.workspaces is location-bound — so relocating web-1 strands or RECREATES the workspaces volume. That is a data-migration decision, not a stock workaround." >&2
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
#     NOTE: this relies on jq's `index()` returning 0 for `["create"]` and 0 being TRUTHY in
#     jq (only false/null are falsy). In most languages 0 is falsy — had jq followed that
#     convention, every pure-create plan would silently skip the gate. T13/T13b pin it.
#
# `@tsv` IS LOAD-BEARING — do NOT "simplify" it to @csv or a join("\t"). It escapes
# tab/newline/CR/backslash inside values, which is the only reason a hostile or odd
# `.address` cannot (a) split into extra fields and mis-pair a server_type with the wrong
# location, or (b) smuggle a newline into the `echo "::error::..."` below and forge a
# GitHub Actions workflow command. Field delimiters are the sole surviving real tabs.
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

  # Every hcloud_server entry MUST carry an ARRAY .change.actions. jq's `null | index(...)`
  # returns null (it does NOT error), so an entry missing .change.actions is silently dropped
  # by the select below — a server create that vanishes from the work-list rather than
  # fail-closing. Assert the shape explicitly instead of inferring it from an empty result.
  if jq -e '[.resource_changes[]
              | select(.type == "hcloud_server")
              | select((.change.actions | type) != "array")] | length > 0' \
       "$plan_json" >/dev/null 2>&1; then
    echo "::error::stock-preflight ABORT: an hcloud_server entry in '${plan_json}' has no array .change.actions — cannot classify create-vs-no-op. Fail-closed: an unclassifiable plan is not evidence of safety." >&2
    return 1
  fi

  # `if ! pairs=$(jq …)` — NEVER a bare assignment. jq exits 5 on a runtime error (e.g.
  # `.resource_changes` present but a string, so `.resource_changes[]` cannot iterate), and a
  # bare assignment + `2>/dev/null` swallows that into an empty `pairs`, which the emptiness
  # branch below would read as "nothing to preflight" and authorize the destroy. The now-deleted
  # web2-recreate-gate.sh (removed with its job, #6575) carried this same check for this same
  # stated reason — "A jq null/empty would evaluate false in the arithmetic below and could
  # silently mis-decide; fail LOUD instead." — recorded here so the rationale outlives it.
  if ! pairs=$(jq -r '
    .resource_changes[]
    | select(.type == "hcloud_server")
    | select(.change.actions | index("create"))
    | [.address, (.change.after.server_type // ""), (.change.after.location // "")]
    | @tsv
  ' "$plan_json" 2>/dev/null); then
    echo "::error::stock-preflight ABORT: jq extraction failed on '${plan_json}' — cannot enumerate planned server creates. Fail-closed: a plan we cannot read is not evidence of availability." >&2
    return 1
  fi

  if [[ -z "$pairs" ]]; then
    # No server create planned => nothing to preflight. A pure in-place update, a
    # volume-only plan, or a no-op is legitimately out of this gate's scope.
    #
    # This MUST announce itself. On all six call sites the preceding destroy-guard has
    # already asserted the plan IS the exact scoped recreate, so a server create is
    # guaranteed present — an empty extraction there means the jq broke (a provider field
    # rename, a terraform-show-json shape change), NOT a legitimate no-op. Returning 0
    # silently would make a rotted gate indistinguishable from a passing one in the run log,
    # which is the one place an operator looks. Every sibling *-gate.sh in this directory echoes
    # a positive line on its success path for this reason.
    echo "stock-preflight: 0 planned server creates in '${plan_json}' — nothing to preflight (in-place update / volume-only / no-op)." >&2
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
    # No per-address tine scoping remains: the only address-scoped suggestion was the web-2
    # warm-standby tine, deleted with its subject (#6575). The surviving menu is correct for
    # every host, so the address is reported by the trailing "...while preflighting" line only.
    if ! stock_preflight "$stype" "$sloc"; then
      echo "::error::  ...while preflighting ${addr} (${stype} @ ${sloc})." >&2
      rc=1
    fi
  done <<<"$pairs"

  # NOT dead code, and NOT a legitimate no-op. `pairs` was non-empty, yet no line yielded an
  # address — i.e. jq emitted tab-only rows (`[null,null,null] | @tsv` => "\t\t"), so every
  # iteration hit the `-z "$addr"` continue and n stayed 0. Reaching here means the extraction
  # produced structurally unusable rows for a plan the destroy-guard already proved is a
  # scoped recreate. Fail closed: returning 0 here silently authorized the destroy.
  if [[ "$n" -eq 0 ]]; then
    echo "::error::stock-preflight ABORT: extracted $(printf '%s' "$pairs" | grep -c '') row(s) from '${plan_json}' but none carried a resource address. Fail-closed: an unreadable plan is not evidence of availability." >&2
    return 1
  fi

  # Positive liveness. The plan's Observability block declares the gate's liveness_signal as
  # "the stock preflight step's own PASS/ABORT annotation" — without this line only the ABORT
  # half existed, and a gate that is silent on success cannot be distinguished from a gate
  # that has rotted into a no-op. Mirrors the sibling gates' `PASS —` lines.
  if [[ "$rc" -eq 0 ]]; then
    echo "stock-preflight PASS: ${n} planned server create(s) reported available in target location(s) (an indicator, not a reservation)." >&2
  fi
  return "$rc"
}
