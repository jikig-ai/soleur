# shellcheck shell=bash
# Sourced STOCK preflight gate for every apply_target whose plan can fail on Hetzner
# capacity in .github/workflows/apply-web-platform-infra.yml (#6453).
#
# NOT "every destroy-shaped target" any more: #6730's `web-host-create` is purely ADDITIVE
# and sources this gate too. The wording mattered — a reader who took "destroy-shaped" as
# the membership rule would conclude an additive path is out of scope, which is how a birth
# ships without a capacity check.
#
# EXTRACTED + SOURCED: every `if ! stock_preflight_gate` plan step in the workflow (enumerate them with
# `git grep -n stock_preflight_gate -- .github/workflows` — a count written here goes stale) plus the
# registry_pull_path_gate advisory probe (calls stock_preflight directly, under `set +e`) AND
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
#   `available: true` is not a reservation: a replace can still destroy and then fail to create — on stock
#   (it can flip between this read and the create) OR on a failure `available` says nothing about
#   (placement group, quota, volume attach). The gate narrows the stock window to Hetzner's own signal; it
#   does not remove it, and nothing here recovers a host once the destroy has run.
#   Each planned create is judged ALONE: stock for one server does not cover two of one type (the
#   web-host-create / web-host-replace gates cap creates at one, so only the other callers could ever see two).
#   Scope is CREATES: an in-place server_type update has no create action and is not preflighted (the
#   provider resizes it in place; it is not destroy-first).
#   Re-evaluation probe for ADR-154's old trigger (a type back in stock): GET /v1/server_types?name=cx33
#   -> locations[].available (ADR-154 carries a dated addendum pointing here).
#   MEASURED 2026-10-05, read-only token, shapes only: `?name=cx33` -> HTTP 200, entries for fsn1, nbg1 and
#   hel1 ALL `available:false` (presence != available holds on the new endpoint; a sold-out type keeps its
#   entry). An unknown `?name=` -> 200 `{"server_types":[]}` (the UNKNOWN_TYPE arm is reachable; a top-level `[]`
#   would be MALFORMED:shape); a repeated name is answered for the first. In the 20 location entries observed to
#   carry a non-null `deprecation` (cpx11..cpx51, all past-dated) `available` was false in every one, so the gate
#   never gates on `deprecation` and only annotates an ORDERABLE answer that carries one — an inference from 20
#   entries, not a vendor guarantee.
#   Rate limit seen: 3600 requests/hour per project; one gate run costs one request per planned create.
#   Probe by hand (read-only token; never paste a token into a transcript):
#     curl -sS -H "Authorization: Bearer $HCLOUD_TOKEN_READONLY" \
#       "https://api.hetzner.cloud/v1/server_types?name=<type>" | jq '.server_types[].locations'
#
# ENV SURFACE — what each variable can and cannot do. No variable this library defines forces a pass directly.
#   HCLOUD_API redirects the single call and the bearer token with it, so a stub behind it returning
#   `available:true` WOULD authorize: a non-default value is announced with a ::warning:: naming the host
#   (userinfo, path and query stripped); no workflow in this repo sets it. curl's own environment (HTTPS_PROXY, CA
#   bundle, ~/.curlrc) steers the same call and is not announced. A Doppler write already gives code execution on
#   the runner, so this is disclosure, not a barrier. HCLOUD_TOKEN is read per call. STOCK_PREFLIGHT_EU_LOCATIONS
#   only feeds the advisory "orderable in EU" text and can never change the verdict or the exit code.
# ACCEPTED LIMITS of the jq read, each needing a hostile TLS endpoint or code execution on the runner (either
#   already holds full authority): duplicate JSON keys within one object resolve last-wins (jq's parser; Hetzner
#   emits none), `$(...)` drops NUL bytes before jq sees the body, and jq auto-loads ~/.jq.
#
# Stock is time-varying on an HOURS timescale: cx33 went from "orderable in hel1"
# to orderable in ZERO datacenters within ~3h on 2026-07-15 (measured on the since-removed /v1/datacenters:
# hel1's available count dropped 14 -> 12). Hence: query live on every dispatch, and NEVER encode today's
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

# _STOCK_LAST_CLASS — the class of the most recent verdict in THIS shell (#9510).
# stock_preflight overwrites it on every return (orderable|stock|config|unreachable|malformed);
# stock_preflight_gate resets it on entry and folds every failed row's class into it — a
# plan-shape abort (unreadable plan, create row with no address/type/location) reads 'plan',
# and two rows failing on different classes fold to 'mixed'. It exists so a caller's CLOSING
# line can name the class that actually fired: the eight `stock-preflight ABORTED` lines in
# apply-web-platform-infra.yml used to claim "not orderable" for all four classes, which sends
# a mid-incident reader waiting on stock for a typo, a dead token, or a changed contract.
# It is a sourced-shell global, so readers must invoke the gate in the step's own shell
# (`if ! stock_preflight_gate tfplan.json` — a $(...) capture would run it in a subshell and
# lose the write). Readers MUST NOT rely on it surviving across a subshell boundary.
_STOCK_LAST_CLASS=""

# Injectable fetch seam. The test redefines this to cat a synthesized fixture, so the
# suite is hermetic (no network, no HCLOUD_TOKEN). Never inline curl at a call site.
_STOCK_DEFAULT_API="https://api.hetzner.cloud/v1"
HCLOUD_API="${HCLOUD_API:-$_STOCK_DEFAULT_API}"
# `--fail-with-body` (curl >= 7.76): a non-2xx answer exits 22 and still prints the body. Without it `curl -sS`
# exits 0 on a 410, and the caller would have to guess from the body alone whether it was told "no".
_stock_fetch() {
  curl -sS --fail-with-body --max-time 20 -H "Authorization: Bearer ${HCLOUD_TOKEN:-}" "${HCLOUD_API}$1"
}

# _stock_verdict <types_json> <type> <loc>
#   -> ORDERABLE | UNAVAILABLE | UNKNOWN_TYPE | UNKNOWN_LOCATION | MALFORMED:<reason>
# ONE jq program, ONE token. Only the exact string ORDERABLE authorizes anything. The caller captures it as
# `verdict=$(_stock_verdict ...) || verdict=""` — on trailing junk (`<valid doc>garbage`) jq prints the verdict of the
# FIRST document and then exits non-zero (5 on jq 1.8.2), so a bare capture would read ORDERABLE off a body that is not
# one document. Two VALID documents are a different mechanism: jq prints two lines and exits 0, and it is the exact-token
# `case` in stock_preflight that rejects the multi-line verdict.
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
# runs on the UNAVAILABLE arm — where the verdict has already proven exactly one type and an array `locations` — and
# never influences the verdict or the exit code; the caller degrades a failure to the `<none>` text with
# `|| elsewhere=""` (a bare assignment would abort under `bash -eo pipefail`). Strict `== true` (a string "true" or
# 1 is not suggested) and the allow-set intersection happens INSIDE jq, so no location name can word-split into a
# shell loop. Takes only what it reads.
_stock_eu_locations_for() {
  printf '%s' "$1" | jq -r --arg t "$2" --arg eu "$STOCK_PREFLIGHT_EU_LOCATIONS" '
    ($eu | split(" ") | map(select(. != ""))) as $allow
    | .server_types[] | select(.name == $t) | .locations[]
    | select(.available == true and (.name | IN($allow[]))) | .name' 2>/dev/null | sort -u | paste -sd' ' -
}

# _stock_api_error <body> — on a non-2xx answer (curl exit 22, --fail-with-body) prints ` api_error=<code>` taken from
# the body's `.error.code` (e.g. deprecated_api_endpoint, unauthorized, rate_limit_exceeded), or nothing. curl's own
# exit status already separates a network failure (6 DNS, 7 connect, 28 timeout) from an HTTP error status (22); this
# code separates WHICH HTTP error — a removed endpoint or a bad token (NOT transient) from a rate limit or a gateway
# page (transient). Only a short [a-z_] token is ever echoed — no body text reaches a
# `::error::` line. Always returns 0.
_stock_api_error() {
  local c
  c=$(printf '%s' "$1" | jq -r '(.error.code? // empty) | select(type == "string" and test("\\A[a-z_]{1,64}\\z"))' 2>/dev/null | head -n1) || c=""
  [[ -n "$c" ]] && printf ' api_error=%s' "$c"
  return 0
}

# _stock_shape_hint <body> — a sanitized, length-capped description of an unusable answer (`object keys=a,b` or the jq
# type), so the abort line carries evidence an operator without Doppler access can act on. Key names are restricted
# to [A-Za-z0-9_] and the whole hint to 120 chars; no value is ever echoed. Always returns 0.
_stock_shape_hint() {
  local h
  h=$(printf '%s' "$1" | jq -r 'if type == "object" then "object keys=" + ([keys[] | select(test("\\A[A-Za-z0-9_]{1,32}\\z"))] | .[:8] | join(",")) else type end' 2>/dev/null | head -n1 | cut -c1-120) || h=""
  printf '%s' "${h:-not-json}"
  return 0
}

# _stock_deprecation_note <body> <type> <loc> — on an ORDERABLE answer, annotate (never gate on) a non-null location
# `deprecation`. Observed 2026-10-05: all 20 past-dated deprecations read available:false, so what this normally shows
# is an announced FUTURE cutoff on a host that is orderable today. The timestamp is restricted to
# [0-9A-Za-z:.+-] and 40 chars before it reaches a `::warning::` line. Always returns 0.
_stock_deprecation_note() {
  local ua
  ua=$(printf '%s' "$1" | jq -r --arg t "$2" --arg l "$3" '
    [.server_types[] | select(.name == $t) | .locations[] | select(.name == $l) | .deprecation
     | select(. != null) | (.unavailable_after // "unknown") | tostring] | .[0] // empty' 2>/dev/null | head -n1 | cut -c1-40) || ua=""
  [[ -z "$ua" ]] && return 0
  ua="${ua//[^0-9A-Za-z:.+-]/?}"
  echo "::warning::stock-preflight: '${2}' in '${3}' is reported available but carries a Hetzner deprecation (unavailable_after=${ua}). Not gating — if that date is still ahead, plan a server_type change before it." >&2 || true
  return 0
}

# _stock_warn_if_endpoint_overridden — HCLOUD_API can redirect the single call (and the bearer token), so a non-default
# value is announced. Only the sanitized authority HOST is printed: path, query, fragment and userinfo
# (`user:password@`) are cut first, because a credential embedded in the value would otherwise reach the run log
# unmasked (the loader masks only the whole value). Always returns 0.
_stock_warn_if_endpoint_overridden() {
  [[ "$HCLOUD_API" == "$_STOCK_DEFAULT_API" ]] && return 0
  local h="$HCLOUD_API" scheme_re='^[A-Za-z][A-Za-z0-9+.-]*://'
  # strip the scheme ONLY when the value starts with one: a scheme-less value whose query contains `://` must not
  # have its query read as the authority
  [[ "$h" =~ $scheme_re ]] && h="${h#*://}"
  h="${h%%[/?#]*}"
  h="${h##*@}"
  h="${h//[^A-Za-z0-9.:_-]/?}"
  echo "::warning::stock-preflight: HCLOUD_API is overridden (host=${h:0:80}); the verdict below is only as trustworthy as that endpoint." >&2 || true
  return 0
}

# stock_preflight <server_type> <location>
# rc=0  -> Hetzner REPORTS the type available in <location> right now (an indicator, not a reservation)
# rc=1  -> aborted; the first line carries a greppable `class=` token, one of four with DIFFERENT advice
#          (stock_preflight_gate's own plan-shape aborts — an unreadable plan, a create with no address, type or
#          location — carry none: they are about the plan, not about Hetzner):
#          class=stock (Hetzner reports it unavailable: wait), class=config (unknown type/location: fix the plan),
#          class=malformed (Hetzner answered 2xx in an unusable shape: NOT a shortage, contract may have changed),
#          class=unreachable (no 2xx: curl exit, plus api_error= when the body names one).
# The classes are DISTINCT so an operator does not read a blip as a real shortage and file a spurious #6463 dup.
stock_preflight() {
  local want_type="$1" want_loc="$2"
  local types_json="" verdict="" reason="" elsewhere="" api_err="" fetch_rc=0

  _STOCK_LAST_CLASS=""
  if [[ -z "$want_type" || -z "$want_loc" ]]; then
    _STOCK_LAST_CLASS=config
    echo "::error::stock-preflight ABORT: class=config — called without server_type/location (got '${want_type}'/'${want_loc}'). Fail-closed." >&2
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
  # lowercase alnum with an optional dash (fsn1, hel1, ash). Anything else fails closed —
  # a value we cannot safely ask about is not evidence of availability.
  if [[ ! "$want_type" =~ ^[a-z0-9]+$ ]]; then
    _STOCK_LAST_CLASS=config
    echo "::error::stock-preflight ABORT: class=config — server_type '${want_type}' is not a valid Hetzner type name (expected lowercase alphanumeric). Fail-closed — a value that cannot be safely queried must never authorize a destroy." >&2
    return 1
  fi
  if [[ ! "$want_loc" =~ ^[a-z0-9-]+$ ]]; then
    _STOCK_LAST_CLASS=config
    echo "::error::stock-preflight ABORT: class=config — location '${want_loc}' is not a valid Hetzner location name (expected lowercase alphanumeric/dash). Fail-closed." >&2
    return 1
  fi

  # ONE fetch. Resolve the type by NAME (not ?per_page=50 — that silently encodes "Hetzner has <=50 types" and fails
  # CLOSED if one ever lands on page 2). `fetch_rc` is captured, not discarded: with --fail-with-body a non-2xx answer
  # exits 22 and the body names the API error — see _stock_api_error for what that adds to curl's own exit status.
  _stock_warn_if_endpoint_overridden
  types_json=$(_stock_fetch "/server_types?name=${want_type}" 2>/dev/null) || fetch_rc=$?
  if [[ "$fetch_rc" -ne 0 ]]; then
    api_err=$(_stock_api_error "$types_json") || api_err=""
    verdict="UNREACHABLE:curl exit ${fetch_rc}${api_err}"
  elif [[ -z "$types_json" ]]; then
    verdict="UNREACHABLE:empty body"
  else
    # `|| verdict=""` — see _stock_verdict. NEVER a bare assignment, never `local v=$(...)` (masks the status).
    verdict=$(_stock_verdict "$types_json" "$want_type" "$want_loc") || verdict=""
  fi

  # Exactly one `return 0` in this function: the exact token ORDERABLE. Everything else, including an empty or
  # multi-line verdict, aborts. Four DISTINCT classes (`class=` token) with different advice, so an operator
  # mid-incident does not read a changed contract as a shortage or a typo as an outage.
  case "$verdict" in
    ORDERABLE) _STOCK_LAST_CLASS=orderable; _stock_deprecation_note "$types_json" "$want_type" "$want_loc"; return 0 ;;
    UNAVAILABLE) ;;   # falls through to the stock-miss abort and the remediation menu below
    UNKNOWN_TYPE)
      _STOCK_LAST_CLASS=config
      echo "::error::stock-preflight ABORT: class=config — unknown server_type '${want_type}' (no match at /server_types?name=). Fail-closed — a typo must never authorize a destroy." >&2
      return 1 ;;
    UNKNOWN_LOCATION)
      _STOCK_LAST_CLASS=config
      echo "::error::stock-preflight ABORT: class=config — unknown location '${want_loc}' for server_type '${want_type}' (not in its /server_types locations[]: a mistyped location, or a type Hetzner does not offer there — check \`location\` in the plan and variables.tf). Fail-closed." >&2
      return 1 ;;
    UNREACHABLE:*)
      _STOCK_LAST_CLASS=unreachable
      echo "::error::stock-preflight ABORT: class=unreachable — cannot PROVE stock for '${want_type}' in '${want_loc}' (Hetzner did not answer /server_types with a 2xx: ${verdict#UNREACHABLE:}; curl exit 22 means an HTTP error status). An unreachable API is not evidence of availability. Transient — re-dispatch once: a curl exit other than 22 (timeout, DNS, connect), api_error=rate_limit_exceeded, or exit 22 with no api_error (a gateway error page). NOT transient: any other api_error (deprecated_api_endpoint, unauthorized, forbidden, ...) or the same failure on consecutive dispatches — the API contract changed or HCLOUD_TOKEN is wrong: do NOT blind re-dispatch (changelog and probe command: header of tests/scripts/lib/stock-preflight-gate.sh, https://docs.hetzner.cloud/changelog#2026-06-02-datacenters-deprecated)." >&2
      return 1 ;;
    *)
      _STOCK_LAST_CLASS=malformed
      if [[ "$verdict" == *$'\n'* ]]; then reason="multiple JSON documents"; else reason="${verdict:-unreadable body (trailing data, or a member jq could not read)}"; fi
      echo "::error::stock-preflight ABORT: class=malformed — cannot PROVE stock for '${want_type}' in '${want_loc}' (Hetzner answered /server_types in a shape this gate does not accept: ${reason}; body=$(_stock_shape_hint "$types_json")). This is NOT a stock shortage: the API contract may have changed. Open an issue naming this line; do NOT blind re-dispatch (probe command: header of tests/scripts/lib/stock-preflight-gate.sh)." >&2
      return 1 ;;
  esac

  _STOCK_LAST_CLASS=stock
  elsewhere=$(_stock_eu_locations_for "$types_json" "$want_type") || elsewhere=""
  echo "::error::stock-preflight ABORT: class=stock — server_type '${want_type}' is reported NOT orderable in '${want_loc}' today by Hetzner (orderable in EU: ${elsewhere:-<none>}). That is an indicator, not a guarantee, so it can block a replace that would have succeeded — but a -replace DESTROYS before it creates, and this recreate would strand the fleet with no rollback if the create fails (#6393, #6463)." >&2
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
  # WHY THE WEB-1 CLAUSE BELOW IS CONDITIONALLY WORDED: there are several callers (see the header), and only
  # two of them (#6730's web-host-create and #6969's web-host-replace) preflight a web host. The
  # others — inngest-host-replace, registry-host-replace, registry-region-migrate, registry-luks-recut,
  # git-data-host-replace, git-data-host-create — never do. So the web-1 specifics stay a guarded "if this host is
  # web-1" clause rather than an unconditional claim, which would misdirect the four non-web
  # paths in the one message they read during a blocked prod recreate.
  #
  # NOTE web-host-replace refuses web-1 by name (it is the LUKS-pinned host), so on that
  # caller the clause is reachable only for a NON-web-1 key. It stays conditional anyway: the
  # condition is on the host the PLAN creates, not on the dispatch key, and the callers
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
  echo "::error::  - PRIMARY: wait and re-dispatch. A retry costs nothing — on a -replace caller because this gate runs BEFORE the destroy, and on an additive caller (web-host-create) because nothing existed to destroy. Stock is time-varying on an HOURS timescale (cx33 went orderable -> nowhere in ~3h on 2026-07-15). If this host was ALREADY destroyed (a recovery re-dispatch after a failed create) the outage continues while you wait — waiting is still the only safe action, and there is no bypass." >&2
  echo "::error::  - SECONDARY: change server_type WITHIN the same location. The 'orderable in EU' list above names the locations where Hetzner currently REPORTS this same type available — informational only: moving a host to another location is a residency/data decision, not a stock workaround (see the web-1 clause). Changing the type is an operator cost/HA decision — see #6463 — not a free action." >&2
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
#
# The extraction lives in _stock_plan_creates so stock_recovery_report (#9510) grades the
# SAME population the gate did — a re-derived copy could disagree on what counts as a create.
_stock_plan_creates() {
  jq -r '
    .resource_changes[]
    | select(.type == "hcloud_server")
    | select(.change.actions | index("create"))
    | [.address, (.change.after.server_type // ""), (.change.after.location // "")]
    | @tsv
  ' "$1" 2>/dev/null
}

# _stock_gate_fold <class> — accumulate the class of each FAILED row into
# _STOCK_GATE_CLASS: first failure wins; a second failure of a DIFFERENT class folds
# to 'mixed' so the closing line never names one class over a multi-cause abort.
_stock_gate_fold() {
  case "$_STOCK_GATE_CLASS" in
    "")   _STOCK_GATE_CLASS="$1" ;;
    "$1") ;;
    *)    _STOCK_GATE_CLASS="mixed" ;;
  esac
}

stock_preflight_gate() {
  local plan_json="$1" pairs n=0 rc=0 addr stype sloc row rest
  # 'plan' until a probe says otherwise: every early plan-shape abort below returns with
  # this class, which is exactly right — none of them ever asked Hetzner.
  _STOCK_LAST_CLASS=plan
  _STOCK_GATE_CLASS=""

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
  if ! pairs=$(_stock_plan_creates "$plan_json"); then
    echo "::error::stock-preflight ABORT: jq extraction failed on '${plan_json}' — cannot enumerate planned server creates. Fail-closed: a plan we cannot read is not evidence of availability." >&2
    return 1
  fi

  if [[ -z "$pairs" ]]; then
    # No server create planned => nothing to preflight. A pure in-place update, a
    # volume-only plan, or a no-op is legitimately out of this gate's scope.
    #
    # This MUST announce itself. On the replace call sites the preceding destroy-guard has
    # already asserted the plan IS the exact scoped recreate, so a server create is
    # guaranteed present — an empty extraction there means the jq broke (a provider field
    # rename, a terraform-show-json shape change), NOT a legitimate no-op. Returning 0
    # silently would make a rotted gate indistinguishable from a passing one in the run log,
    # which is the one place an operator looks. Every sibling *-gate.sh in this directory echoes
    # a positive line on its success path for this reason.
    echo "stock-preflight: 0 planned server creates in '${plan_json}' — nothing to preflight (in-place update / volume-only / no-op)." >&2
    _STOCK_LAST_CLASS=orderable
    return 0
  fi

  # Split each row on its literal tabs by parameter expansion, NOT `IFS=$'\t' read -r a b c`: tab is IFS-whitespace, so
  # `read` collapses a LEADING empty field and shifts the rest left — a row with no address but a real target then read
  # as (addr=<type>, type=<location>, loc=<empty>) and aborted under the wrong name. @tsv escapes every tab inside a
  # value, so the surviving tabs are exactly the field delimiters and this split is exact.
  # @tsv of a 3-element array always yields exactly two tabs, so no field-count check is needed (a row with fewer
  # would be a jq bug and cannot be produced from this extraction).
  while IFS= read -r row; do
    addr="${row%%$'\t'*}"; rest="${row#*$'\t'}"
    stype="${rest%%$'\t'*}"; sloc="${rest#*$'\t'}"
    if [[ -z "$addr" ]]; then
      # A create row that cannot be NAMED cannot be reconciled with what the plan will order. This used to `continue`
      # silently, so one valid row beside one addressless row passed with a single fetch. Fail closed, per row.
      echo "::error::stock-preflight ABORT: a planned server create row carries no resource address (type '${stype}', location '${sloc}'). Fail-closed — a create we cannot name is not evidence of availability." >&2
      _stock_gate_fold plan
      rc=1
      continue
    fi
    n=$((n + 1))
    if [[ -z "$stype" || -z "$sloc" ]]; then
      echo "::error::stock-preflight ABORT: ${addr} plans a create but carries no server_type/location in change.after. Fail-closed — cannot prove stock for an unknown target." >&2
      _stock_gate_fold plan
      rc=1
      continue
    fi
    # No per-address tine scoping remains: the only address-scoped suggestion was the web-2
    # warm-standby tine, deleted with its subject (#6575). The surviving menu is correct for
    # every host, so the address is reported by the trailing "...while preflighting" line only.
    # Only FAILED probes fold a class — a passing row contributes no class to the abort.
    if ! stock_preflight "$stype" "$sloc"; then
      echo "::error::  ...while preflighting ${addr} (${stype} @ ${sloc})." >&2
      _stock_gate_fold "$_STOCK_LAST_CLASS"
      rc=1
    fi
  done <<<"$pairs"

  # BACKSTOP, kept on purpose. Every addressless row already sets rc=1 above, so the function would return 1 anyway;
  # this adds the one line that names the whole-plan symptom (`pairs` non-empty, yet no row carried an address — jq
  # emitted only tab-only rows, `[null,null,null] | @tsv` => "\t\t") for a plan the destroy-guard already proved is a
  # scoped recreate. It used to be the ONLY thing standing between that shape and `return 0`.
  if [[ "$n" -eq 0 ]]; then
    echo "::error::stock-preflight ABORT: extracted $(printf '%s' "$pairs" | grep -c '') row(s) from '${plan_json}' but none carried a resource address. Fail-closed: an unreadable plan is not evidence of availability." >&2
    [[ -n "$_STOCK_GATE_CLASS" ]] && _STOCK_LAST_CLASS="$_STOCK_GATE_CLASS"
    return 1
  fi

  # Positive liveness. The plan's Observability block declares the gate's liveness_signal as
  # "the stock preflight step's own PASS/ABORT annotation" — without this line only the ABORT
  # half existed, and a gate that is silent on success cannot be distinguished from a gate
  # that has rotted into a no-op. Mirrors the sibling gates' `PASS —` lines.
  if [[ "$rc" -eq 0 ]]; then
    _STOCK_LAST_CLASS=orderable
    echo "stock-preflight PASS: ${n} planned server create(s) reported available in target location(s) (an indicator, not a reservation)." >&2
  else
    _STOCK_LAST_CLASS="${_STOCK_GATE_CLASS:-plan}"
  fi
  return "$rc"
}

# stock_abort_closing <label> [tail]
# The workflow's closing line after `stock_preflight_gate` returns non-zero. It renders the
# class that ACTUALLY fired from _STOCK_LAST_CLASS (#9510): before this helper, all eight call
# sites printed "<target> stock-preflight ABORTED: the planned server_type is not orderable"
# for every class, so a `config`, `unreachable` or `malformed` abort still told the operator to
# wait for stock. `class=stock` keeps that wording; every other class names what to do instead.
# The class vocabulary is gate-side: 'plan' covers a plan-shape abort (no probe ran), 'mixed'
# covers two rows failing on different classes, 'none' covers an unset/stale global.
stock_abort_closing() {
  local label="$1" tail="${2:-}" cls="${_STOCK_LAST_CLASS:-none}" advice
  case "$cls" in
    orderable)
      advice="the gate's last verdict was ORDERABLE — if this line is visible a wrapper is printing an abort after a pass; read the lines above." ;;
    stock)
      advice="a planned server_type is reported NOT orderable in its target location by Hetzner. Refusing to apply — the destroy would succeed and the create could not, stranding the host with no rollback (#6393, #6463). Wait for stock and re-dispatch." ;;
    config)
      advice="NOT a stock shortage — the plan names a server_type or location Hetzner does not list, or an unsafe value never reached the network (the ::error:: line above names the row). Do NOT re-dispatch until the plan/vars are fixed." ;;
    unreachable)
      advice="NOT a stock shortage — Hetzner did not answer 2xx, so stock could not be proven (the ::error:: line above carries the curl status / api_error). Re-dispatch ONCE only if it is a transient shape; a repeat, or a non-transient api_error, means the token or the API contract changed — do NOT blind re-dispatch." ;;
    malformed)
      advice="NOT a stock shortage — Hetzner answered 2xx in a shape this gate does not accept: a contract change. Do NOT re-dispatch; open an issue naming the ::error:: line above." ;;
    plan)
      advice="NOT a stock verdict — the plan itself could not be classified (unreadable JSON, or a create row with no address / server_type / location; the ::error:: lines above name the row). Reconcile the plan." ;;
    mixed)
      advice="the aborts above carry MORE THAN ONE failure class — read every ::error:: line; at least one of them is not a stock shortage." ;;
    *)
      advice="the gate aborted — read the ::error:: lines above for the cause (no probe verdict was recorded)." ;;
  esac
  echo "::error::${label} stock-preflight ABORTED (class=${cls}): ${advice}${tail:+ ${tail}}" >&2
}

# stock_recovery_report <label> <plan_json> [state_json | --probe-state]
# Post-apply-failure diagnostic for the destroy-first replace paths (#9510 Item A). A -replace
# destroys before it creates, so a create that fails after the destroy strands the host with no
# rollback. The recovery that already exists is a NEW DISPATCH: the job's gates pin the data
# volumes out of the destroy set, so a re-dispatch re-plans a create + reattach against the
# retained volumes (the absent-vs-tainted two-arm doctrine is in
# knowledge-base/engineering/operations/runbooks/web-host-replace.md). What the failure run was
# missing is the DIAGNOSTIC — did the create fail on stock, or on a cause stock says nothing
# about. This function re-reads Hetzner for every planned create (a FRESH fetch through
# stock_preflight — never a replayed verdict), names the current class per address, reads a
# post-failure `terraform show -json` dump when supplied to say whether the address is absent
# (the re-dispatch plans a bare create) or tainted/present (the re-dispatch plans delete+create
# or nothing), and prints the doctrine. It NEVER authorizes anything: it is an annotation, so it
# returns 0 unconditionally — the job's own `exit 1` carries the failure.
stock_recovery_report() {
  local label="$1" plan_json="$2" state_src="${3:-}"
  local pairs row addr stype sloc rest pcls pstate state_note="no post-failure state read"
  local state_file="" cleanup_state=""
  echo "::error::${label} recovery-read: the apply failed; re-reading Hetzner stock for every planned server create so a stock-caused failure is distinguishable from a config/contract/apply one. Diagnostic only — this annotates the failure, it does not change it." >&2

  case "$state_src" in
    --probe-state)
      # The job's working dir is the infra root and `terraform init` already ran there;
      # AWS_* backend creds reach this step through the loader's $GITHUB_ENV export.
      # $RUNNER_TEMP, not /tmp (#7661 G10): `terraform show -json` does not redact sensitive
      # values — the state dump can carry live tokens, so the file must not sit at a
      # predictable world-readable path. mktemp's own file is 0600 regardless.
      if command -v terraform >/dev/null 2>&1; then
        state_file="$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/stock-recovery-state.XXXXXXXX")" && cleanup_state=1
        if [[ -n "$state_file" ]]; then
          terraform show -json > "$state_file" 2>/dev/null || { rm -f "$state_file"; state_file=""; }
        fi
        [[ -z "$state_file" ]] && state_note="terraform show -json failed — post-failure state unreadable"
      else
        state_note="terraform not on PATH — post-failure state unreadable"
      fi ;;
    "") ;;
    *)  if [[ -r "$state_src" ]]; then state_file="$state_src"
        else state_note="state file '${state_src}' unreadable"; fi ;;
  esac

  pairs=""
  if [[ -r "$plan_json" ]]; then pairs=$(_stock_plan_creates "$plan_json" 2>/dev/null) || pairs=""; fi
  if [[ -z "$pairs" ]]; then
    echo "::error::${label} recovery-read: no planned server creates could be read from '${plan_json}' — the failure was not a server create; the apply error above is the record." >&2
  else
    while IFS= read -r row; do
      addr="${row%%$'\t'*}"; rest="${row#*$'\t'}"
      stype="${rest%%$'\t'*}"; sloc="${rest#*$'\t'}"
      if [[ -z "$addr" || -z "$stype" || -z "$sloc" ]]; then
        echo "::error::${label} recovery-read: a planned-create row is unreadable (addr='${addr}' type='${stype}' loc='${sloc}') — skipping its probe." >&2
        continue
      fi
      pstate="unprobed (${state_note})"
      if [[ -n "$state_file" ]]; then
        # Scope the descent to .values (post-apply STATE) — `.configuration` also carries
        # `address` keys for everything the plan declared, so an unscoped `..` would read a
        # destroyed-but-declared server as "present", picking the wrong recovery arm.
        pstate=$(jq -r --arg a "$addr" '
          [.values | .. | objects | select(.address? == $a and .type? == "hcloud_server")] as $m
          | if ($m | length) == 0 then "absent — the create never landed; a re-dispatch plans a bare create"
            elif ([$m[] | (.status? // "")] | any(. == "tainted")) then "tainted in state — the create landed and a LATER step failed; a re-dispatch of the replace target plans delete+create"
            else "present in state — the create landed; a re-dispatch plans no server create for it" end
        ' "$state_file" 2>/dev/null) || pstate=""
        [[ -z "$pstate" ]] && pstate="unreadable — the state file did not parse"
      fi
      # FRESH read — emits its own ::error:: evidence line, and sets _STOCK_LAST_CLASS.
      stock_preflight "$stype" "$sloc" >&2 || true
      pcls="${_STOCK_LAST_CLASS:-none}"
      echo "::error::${label} recovery-read: ${addr} wants ${stype}@${sloc} — post-failure stock class=${pcls}; state=${pstate}." >&2
      case "$pcls" in
        stock)
          echo "::error::${label}   → the create most likely failed on stock — wait for stock to return, then re-dispatch this job's documented recovery arm (the stock gate re-runs on that dispatch)." >&2 ;;
        orderable)
          echo "::error::${label}   → stock is orderable NOW — the create failed for a non-stock cause (quota, image, attach, bootstrap); a re-dispatch retries the SAME failure until that cause is fixed — read the apply error above." >&2 ;;
        unreachable)
          echo "::error::${label}   → the re-read could not prove stock (see the curl/api_error line above); retry the probe later, and treat a repeat like a contract problem." >&2 ;;
        *)
          echo "::error::${label}   → a config/contract fault, NOT stock — do NOT re-dispatch until the plan or the API contract is fixed." >&2 ;;
      esac
    done <<<"$pairs"
  fi

  echo "::error::${label} recovery doctrine: the data volumes are pinned out of the destroy set and are retained across the failed create — a re-dispatch re-plans a create that reattaches them. Recovery is a NEW workflow_dispatch per this job's annotation below; there is NO [ack-destroy] bypass and no saved-plan re-apply. (${state_note})" >&2
  [[ -n "$cleanup_state" && -n "$state_file" ]] && rm -f "$state_file"
  return 0
}
