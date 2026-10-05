#!/usr/bin/env bash
# Tests for tests/scripts/lib/stock-preflight-gate.sh (sourced by every apply_target job in
# .github/workflows/apply-web-platform-infra.yml that runs the stock preflight, #6453; enumerate them with
# `git grep -n stock_preflight_gate -- .github/workflows`).
#
# The gate asserts every server a plan will CREATE is orderable in its target location
# BEFORE the destroy runs — because a -replace destroys first, so DC *stock* (not the
# account cap) is what strands the fleet (#6393).
#
# HERMETIC BY CONSTRUCTION (cq-test-fixtures-synthesized-only): every fixture is
# SYNTHESIZED and the gate's _stock_fetch seam is redefined to serve them. No network,
# no HCLOUD_TOKEN, no captured-real API document. This is not stylistic — a live-bound
# suite is RED by lunchtime: on 2026-07-15 cx33 went from "orderable in hel1" to
# orderable in ZERO datacenters within ~3h, and hel1's available count fell 14 -> 12 (measured on the
# since-removed /v1/datacenters).
# NEVER assert against real stock here.
#
# Mirrors the posture of tests/scripts/test-git-data-host-replace-gate.sh:17-21.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$REPO_ROOT/tests/scripts/lib/stock-preflight-gate.sh"

# The lib reads these at source time / per call; an operator's exported value must never reach this suite.
unset HCLOUD_API HCLOUD_TOKEN
# shellcheck source=/dev/null
source "$GATE"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; return 0; }

# INSTRUMENT SELF-TEST: drive pass() and fail() once each and require BOTH counters to move, then unwind. A suite whose
# verdict helpers can be neutered goes green over every defect it exists to catch; the floor at the end sums the same
# counters, so it cannot see this. Reported with echo + exit, never through the helpers under test.
_p0=$passes; _f0=$fails
pass; fail "instrument self-test (expected, discarded)" 2>/dev/null
if [[ "$passes" -ne $((_p0 + 1)) || "$fails" -ne $((_f0 + 1)) ]]; then
  echo "stock-preflight-gate: FAIL — pass()/fail() do not move their counters; every verdict below would be unreliable." >&2
  exit 1
fi
passes=$_p0; fails=$_f0
# ... and fail() must actually PRINT: a verdict nobody can read is a red run with zero FAIL lines and a misleading
# "truncation" message. Run in a subshell so no counter moves.
if ! ( fail "probe" 2>&1 ) | grep -q '^FAIL: probe'; then
  echo "stock-preflight-gate: FAIL — fail() does not print its FAIL: line; a red run would be unreadable." >&2
  exit 1
fi

TMP="$(mktemp -d)"
SRV_PID=""
SUITE_DONE=0
# The EXIT trap is also the completion check: the tally floor at the END of this file cannot see an `exit 0`
# placed before it (a mid-file exit skips the very tail that holds the floor). SUITE_DONE is set only at the tally.
cleanup() {
  local rc=$?
  [[ -n "$SRV_PID" ]] && kill "$SRV_PID" 2>/dev/null
  rm -rf "$TMP"
  if [[ "$SUITE_DONE" -ne 1 ]]; then
    echo "stock-preflight-gate: FAIL — the suite exited before reaching its final tally (rc=${rc}): truncation or early exit." >&2
    exit 1
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Synthesized API fixtures.
#
# Type ids are arbitrary synthetic integers — NOT Hetzner's real ids. Binding a
# fixture to a real id invites someone to "verify" it against live state, which is
# exactly the coupling this suite exists to avoid.
#
# Shape mirrors the real API AFTER Hetzner removed GET /datacenters (changelog 2026-06-02): every
# server type carries locations[] = [{id,name,available,recommended,deprecation}]. PRESENCE of an entry
# means the type is supported in that location; `available` is the indicator that it is orderable right
# now (Hetzner's own wording: an indicator, not a guarantee). The fixtures keep the two apart on purpose:
# alpha33 has an entry in every EU location with available:false (supported everywhere, orderable
# nowhere), so a gate that treated PRESENCE as availability would pass T2/T3 and ship the live trap.
# ---------------------------------------------------------------------------
loc_entry() { # <name> <available-json> [deprecation-json]
  printf '{"id":1,"name":"%s","available":%s,"recommended":false,"deprecation":%s}' "$1" "$2" "${3:-null}"
}
type_doc() { # <id> <name> <locations-json-array>
  printf '{"id":%s,"name":"%s","locations":%s}' "$1" "$2" "$3"
}
DEPR='{"announced":"2099-01-01T00:00:00+00:00","unavailable_after":"2099-06-01T00:00:00+00:00"}'

# alpha33 (9001): an entry everywhere, available NOWHERE       -> the cx33/#6463 shape
# beta22  (9002): available in eu-b (non-null deprecation) + eu-c + far   -> the orderable shape
# arm11   (9003): entries ONLY in the three EU locations (no non-EU entry), available nowhere -> the cax11 shape
# sing44  (9004): available ONLY in the non-EU location         -> residency-filter probe
# partial55 (9005): lists ONLY eu-c                             -> unknown-location probe
LOCS_ALPHA33="[$(loc_entry eu-a false),$(loc_entry eu-b false),$(loc_entry eu-c false),$(loc_entry far false)]"
LOCS_BETA22="[$(loc_entry eu-a false),$(loc_entry eu-b true "$DEPR"),$(loc_entry eu-c true),$(loc_entry far true)]"
LOCS_ARM11="[$(loc_entry eu-a false),$(loc_entry eu-b false),$(loc_entry eu-c false)]"
LOCS_SING44="[$(loc_entry eu-a false),$(loc_entry eu-b false),$(loc_entry eu-c false),$(loc_entry far true)]"
LOCS_PARTIAL55="[$(loc_entry eu-c true)]"
LOCS_OTHER="[$(loc_entry eu-a true),$(loc_entry eu-b true),$(loc_entry eu-c true),$(loc_entry far true)]"

fixture_types() {
  local doc
  case "$1" in
    alpha33)   doc=$(type_doc 9001 alpha33 "$LOCS_ALPHA33") ;;
    beta22)    doc=$(type_doc 9002 beta22 "$LOCS_BETA22") ;;
    arm11)     doc=$(type_doc 9003 arm11 "$LOCS_ARM11") ;;
    sing44)    doc=$(type_doc 9004 sing44 "$LOCS_SING44") ;;
    partial55) doc=$(type_doc 9005 partial55 "$LOCS_PARTIAL55") ;;
    *)         echo '{"server_types":[],"meta":{"pagination":{"page":1}}}'; return 0 ;;   # unknown type
  esac
  printf '{"server_types":[%s],"meta":{"pagination":{"page":1}}}' "$doc"
}

# The EU allow-set for this suite's synthetic topology.
STOCK_PREFLIGHT_EU_LOCATIONS="eu-a eu-b eu-c"

# Fetch seam override. FETCH_MODE steers failure injection. TRIPWIRE: every requested path is
# appended to $CALLS_LOG (a FILE — a counter would not survive the $(...) subshells the lib calls the
# seam from). Hetzner removed GET /datacenters (HTTP 410): the seam serves that synthesized 410 body
# for it, so a gate that still depends on /datacenters can neither pass nor go unnoticed (T1b).
FETCH_MODE="ok"
BODY_FILE="$TMP/body.json"
CALLS_LOG="$TMP/calls.log"
: > "$CALLS_LOG"
BODY_410='{"error":{"code":"deprecated_api_endpoint","message":"API functionality was removed","details":{"announcement":"https://docs.hetzner.cloud/changelog#2026-06-02-datacenters-deprecated"}}}'
_stock_fetch() {
  local path="$1"
  printf '%s\n' "$path" >> "$CALLS_LOG"
  case "$FETCH_MODE" in
    fail_all)  return 1 ;;
    garbage)   echo '{"unexpected":"shape"}'; return 0 ;;
    body)      cat "$BODY_FILE"; return 0 ;;
    body_rc22) cat "$BODY_FILE"; return 22 ;;
  esac
  case "$path" in
    /server_types?name=*) fixture_types "${path#/server_types?name=}" ;;
    /datacenters*)        printf '%s' "$BODY_410"; return 22 ;;   # what the real fetch does now: curl --fail-with-body exits 22
    *)                    return 1 ;;
  esac
}

# run_body <body> <type> <loc> — serve <body> verbatim for /server_types, set out/rc in THIS shell.
run_body() {
  printf '%s' "$1" > "$BODY_FILE"
  FETCH_MODE=body
  out=$(stock_preflight "$2" "$3" 2>&1); rc=$?
  FETCH_MODE=ok
}

# plan_with <addr> <actions-json> <type> <loc> [extra-resources-json-array]
# Built with jq, NOT a heredoc: terraform addresses contain double quotes
# (hcloud_server.web["web-2"]), which string-interpolate into malformed JSON and make
# every rc=1 assertion pass VACUOUSLY on the "not a plan document" abort rather than on
# the behaviour under test.
plan_with() {
  local extra="${5:-[]}"
  jq -n \
    --arg addr "$1" --argjson actions "$2" --arg stype "$3" --arg sloc "$4" --argjson extra "$extra" \
    '{resource_changes: ([{
        address: $addr,
        type: "hcloud_server",
        change: {actions: $actions, after: {server_type: $stype, location: $sloc}}
      }] + $extra)}' > "$TMP/plan.json"
  echo "$TMP/plan.json"
}

# ---------------------------------------------------------------------------
# T1 — orderable => rc 0
# ---------------------------------------------------------------------------
FETCH_MODE=ok
: > "$CALLS_LOG"
if stock_preflight beta22 eu-b >/dev/null 2>&1; then pass; else fail "T1: beta22@eu-b is available; expected rc=0"; fi
# T1b — ONE fetch, and it is /server_types. /datacenters is gone (HTTP 410); a gate that still asks for it is dead.
calls=$(cat "$CALLS_LOG")
[[ "$calls" == "/server_types?name=beta22" ]] && pass || fail "T1b: the gate must make exactly one request, /server_types?name=beta22; got: ${calls}"

# ---------------------------------------------------------------------------
# T2 — NOT orderable here, orderable elsewhere in EU => rc 1 + the remediation menu.
# This is the live #6463 shape. REWRITTEN 2026-07-20 (#6575): this test previously asserted the
# abort MUST name warm-standby (the free additive NIC//workspaces-volume repair on web-2). That
# contract was falsified by the web-2 retire (#6538) and the deletion of the warm_standby job —
# no additive dispatch exists to name. The surviving contract is the web-1-shaped menu: wait for
# stock first, change server_type second, and never treat a relocation as a stock workaround.
# ---------------------------------------------------------------------------
FETCH_MODE=ok
out=$(stock_preflight alpha33 eu-b 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T2: expected rc=1 for alpha33@eu-b, got $rc"
grep -q "NOT orderable in 'eu-b'" <<<"$out" && pass || fail "T2: abort must name the location"
grep -q "PRIMARY: wait and re-dispatch" <<<"$out" && pass || fail "T2: the cheapest correct action (wait for stock) MUST be offered FIRST, before any cost/HA escalation"
grep -q "IF THIS HOST IS web-1" <<<"$out" && pass || fail "T2: an addressless probe must carry the CONDITIONALLY-WORDED web-1 clause (it cannot know the host)"
grep -q "workspaces" <<<"$out" && pass || fail "T2: the web-1 clause must state that relocating strands/recreates the location-bound workspaces volume — a data-migration decision, not a stock workaround"
grep -q "#6463" <<<"$out" && pass || fail "T2: abort must point at #6463 for a genuine rebirth"
grep -q "class=stock" <<<"$out" && pass || fail "T2: the stock-miss abort must carry the greppable class=stock token. out=$out"
grep -q "do NOT relocate it" <<<"$out" && pass || fail "T2: the web-1 clause must still forbid relocating web-1"
grep -q "force-REPLACE the live prod host" <<<"$out" && pass || fail "T2: the web-1 clause must still name the force-REPLACE of the live prod host"
grep -q "Do NOT bypass" <<<"$out" && pass || fail "T2: the no-bypass line must survive"
grep -q "outage continues while you wait" <<<"$out" && pass || fail "T2: PRIMARY must say that a host already destroyed stays down while waiting"
grep -q "warm-standby" <<<"$out" && fail "T2: warm-standby was deleted with web-2 (#6575/#6538); offering it points the operator at a dispatch that does not exist" || pass
grep -q "DESTROYS before it creates" <<<"$out" && pass || fail "T2: abort must state why a failed create is unrecoverable"
# The fabricated option the first draft shipped: workflow_dispatch has NO location input
# (apply-web-platform-infra.yml:76-104), so "re-dispatch against another location" is not
# an action an operator can take. Guard against its reintroduction.
grep -qiE "re-dispatch against|dispatch .*another location" <<<"$out" && fail "T2: abort offers a fabricated location re-dispatch (no such workflow input)" || pass

# ---------------------------------------------------------------------------
# T3 — orderable nowhere (the arm11/cax11 shape) => rc 1, EU list reads <none>
# ---------------------------------------------------------------------------
FETCH_MODE=ok
out=$(stock_preflight arm11 eu-a 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T3: expected rc=1 for arm11@eu-a, got $rc"
grep -q "orderable in EU: <none>" <<<"$out" && pass || fail "T3: with no EU stock the suggestion must read <none>, not an empty string"

# ---------------------------------------------------------------------------
# T4 — RESIDENCY: available only in a non-EU DC. Must NOT be suggested.
# /server_types locations[] really does include ash/hil/sin; an unfiltered "orderable elsewhere"
# would advise putting a prod host outside the EU (variables.tf: "must be an EU Hetzner DC"; CLO T-1).
# ---------------------------------------------------------------------------
FETCH_MODE=ok
out=$(stock_preflight sing44 eu-a 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T4: expected rc=1 for sing44@eu-a, got $rc"
grep -q "far" <<<"$out" && fail "T4: non-EU location leaked into the orderable-elsewhere suggestion" || pass
grep -q "orderable in EU: <none>" <<<"$out" && pass || fail "T4: non-EU-only stock must read <none> after the EU filter"

# ---------------------------------------------------------------------------
# T5 — unknown server type => rc 1 (fail-closed; a typo must never authorize a destroy)
# ---------------------------------------------------------------------------
FETCH_MODE=ok
out=$(stock_preflight bogus99 eu-b 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T5: expected rc=1 for an unknown type, got $rc"
grep -q "unknown server_type" <<<"$out" && pass || fail "T5: abort must name the unknown type"
grep -q "class=config" <<<"$out" && pass || fail "T5: an unknown type is the config class. out=$out"

# ---------------------------------------------------------------------------
# T6 — unknown location => rc 1 (fail-closed)
# ---------------------------------------------------------------------------
FETCH_MODE=ok
out=$(stock_preflight beta22 atlantis 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T6: expected rc=1 for an unknown location, got $rc"
grep -q "unknown location" <<<"$out" && pass || fail "T6: abort must name the unknown location"
grep -q "class=config" <<<"$out" && pass || fail "T6: an unknown location is the config class. out=$out"
# partial55 lists ONLY eu-c: eu-b is a location the type is not offered in => unknown location, never a stock miss.
out=$(stock_preflight partial55 eu-b 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T6: partial55@eu-b must abort, got $rc"
grep -q "unknown location" <<<"$out" && pass || fail "T6: a location absent from locations[] must say unknown location"
grep -q "NOT orderable" <<<"$out" && fail "T6: an unknown location must not masquerade as a stock miss" || pass

# ---------------------------------------------------------------------------
# T7 — API failure => rc 1 with a DISTINCT message. An unreachable API is not
# evidence of availability. The message must differ from the stock-miss abort or an
# operator reads a blip as a real shortage and files a spurious #6463 duplicate.
# ---------------------------------------------------------------------------
FETCH_MODE=fail_all
out=$(stock_preflight beta22 eu-b 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T7: expected rc=1 when the API is unreachable, got $rc"
grep -q "cannot PROVE stock" <<<"$out" && pass || fail "T7: API-blip abort must be DISTINCT from the stock-miss abort"
grep -q "NOT orderable" <<<"$out" && fail "T7: API blip must not masquerade as a real shortage" || pass
grep -q "class=unreachable" <<<"$out" && pass || fail "T7: a fetch failure is the unreachable class. out=$out"
grep -q "class=malformed" <<<"$out" && fail "T7: a fetch failure must not read as a malformed answer" || pass

# T7b — a non-2xx fetch (curl --fail-with-body exits 22 and still prints the body): rc 1, the unreachable class, and
# the reason carries BOTH the curl exit and the API's own error code. curl's status is 22 for EVERY HTTP error, so the
# body's error code is what separates a removed endpoint or a bad token (NOT transient) from a gateway page (transient).
# NOTE: the advice text itself names `api_error=` codes, so assertions on the REASON anchor on `curl exit 22 api_error=`.
printf '%s' "$BODY_410" > "$BODY_FILE"
FETCH_MODE=body_rc22
out=$(stock_preflight beta22 eu-b 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T7b: expected rc=1 when /server_types answers non-2xx, got $rc"
grep -q "cannot PROVE stock" <<<"$out" && pass || fail "T7b: a non-2xx answer must fail closed with the blip message"
grep -q "with a 2xx: curl exit 22" <<<"$out" && pass || fail "T7b: the REASON must carry the curl exit status (the advice prose also names exit 22, so anchor on the reason segment). out=$out"
grep -q "class=unreachable" <<<"$out" && pass || fail "T7b: a non-2xx answer is the unreachable class. out=$out"
grep -q "api_error=deprecated_api_endpoint" <<<"$out" && pass || fail "T7b: a 410 must surface the API's own error code. out=$out"
grep -q "NOT orderable" <<<"$out" && fail "T7b: an API error must not masquerade as a real shortage" || pass
grep -q "class=malformed" <<<"$out" && fail "T7b: an HTTP error must not read as a malformed 2xx answer" || pass
printf '%s' '{"error":{"code":"unauthorized","message":"x"}}' > "$BODY_FILE"
out=$(stock_preflight beta22 eu-b 2>&1); rc=$?
grep -q "api_error=unauthorized" <<<"$out" && pass || fail "T7b: a 401 must be distinguishable from a 410. out=$out"
printf '%s' '<html>502</html>' > "$BODY_FILE"
out=$(stock_preflight beta22 eu-b 2>&1); rc=$?
grep -q "curl exit 22 api_error=" <<<"$out" && fail "T7b: a non-JSON error page has no api_error to report" || pass
# an error code that is not a short [a-z_] token is never echoed (it could carry anything into a ::error:: line)
printf '%s' '{"error":{"code":"x\n::error::forged"}}' > "$BODY_FILE"
out=$(stock_preflight beta22 eu-b 2>&1); rc=$?
grep -q '^::error::forged' <<<"$out" && fail "T7b: an API-supplied error code must never forge a workflow command line" || pass
grep -q "curl exit 22 api_error=" <<<"$out" && fail "T7b: a non-token error code must not be echoed at all" || pass
# the code sanitizer is exact: [a-z_]{1,64}, nothing else — each of these must be dropped, the 64-char one kept
for code in 'abc def' 'abc;x' 'ABC' "$(printf 'a%.0s' $(seq 1 65))"; do
  jq -nc --arg c "$code" '{error: {code: $c}}' > "$BODY_FILE"
  out=$(stock_preflight beta22 eu-b 2>&1); rc=$?
  grep -q "curl exit 22 api_error=" <<<"$out" && fail "T7b: error code [${code:0:20}...] must not be echoed" || pass
done
code64=$(printf 'a%.0s' $(seq 1 64))
jq -nc --arg c "$code64" '{error: {code: $c}}' > "$BODY_FILE"
out=$(stock_preflight beta22 eu-b 2>&1); rc=$?
grep -q "curl exit 22 api_error=${code64}" <<<"$out" && pass || fail "T7b: a 64-char [a-z_] code is the longest that is echoed. out=$out"
# the advice text is class-specific and pinned: transient vs NOT transient must not swap between classes
printf '%s' "$BODY_410" > "$BODY_FILE"
out=$(stock_preflight beta22 eu-b 2>&1); rc=$?
# the transient / NOT-transient LISTS are pinned whole — moving one member across the divide must go red
grep -qF "Transient — re-dispatch once: a curl exit other than 22 (timeout, DNS, connect), api_error=rate_limit_exceeded, or exit 22 with no api_error (a gateway error page)." <<<"$out" && pass || fail "T7b: the transient list must be exact. out=$out"
grep -qF "NOT transient: any other api_error (deprecated_api_endpoint, unauthorized, forbidden, ...) or the same failure on consecutive dispatches" <<<"$out" && pass || fail "T7b: the NOT-transient list must be exact. out=$out"
grep -qF "curl exit 22 means an HTTP error status" <<<"$out" && pass || fail "T7b: the advice must say what exit 22 means. out=$out"
grep -q "NOT a stock shortage" <<<"$out" && fail "T7b: the malformed advice must not appear on the unreachable class" || pass

FETCH_MODE=garbage
out=$(stock_preflight beta22 eu-b 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T7c: expected rc=1 on a malformed API document, got $rc"
grep -q "class=malformed" <<<"$out" && pass || fail "T7c: a 2xx answer in an unusable shape is the malformed class. out=$out"
grep -q "body=object keys=unexpected" <<<"$out" && pass || fail "T7c: the abort must carry a sanitized shape hint. out=$out"
grep -q "NOT a stock shortage" <<<"$out" && pass || fail "T7c: the malformed class must say it is NOT a shortage. out=$out"
grep -qF "probe command: header of tests/scripts/lib/stock-preflight-gate.sh" <<<"$out" && pass || fail "T7c: the malformed abort must point at the probe. out=$out"
grep -q "Transient — re-dispatch once" <<<"$out" && fail "T7c: the transient advice must not appear on the malformed class" || pass
grep -q "api_error=" <<<"$out" && fail "T7c: a 2xx answer carries no api_error" || pass

# ---------------------------------------------------------------------------
# T8 — gate over a tfplan: a -replace (delete+create) of an unorderable type => rc 1
# ---------------------------------------------------------------------------
FETCH_MODE=ok
p=$(plan_with 'hcloud_server.web["web-2"]' '["delete","create"]' alpha33 eu-b)
out=$(stock_preflight_gate "$p" 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T8: a -replace to an unorderable type must abort, got $rc"
grep -qF 'hcloud_server.web["web-2"]' <<<"$out" && pass || fail "T8: abort must name the offending address"

# T8b — same shape, orderable type => rc 0
p=$(plan_with 'hcloud_server.web["web-2"]' '["delete","create"]' beta22 eu-b)
stock_preflight_gate "$p" >/dev/null 2>&1 && pass || fail "T8b: a -replace to an orderable type must pass"

# ---------------------------------------------------------------------------
# T9 — EXTRACTION MUST #1: sibling non-server entries carry change.after WITHOUT
# server_type/location. An unfiltered .resource_changes[].change.after.server_type
# yields null for these. select(.type == "hcloud_server") must run FIRST.
# ---------------------------------------------------------------------------
FETCH_MODE=ok
sibs='[{"address":"hcloud_server_network.web[\"web-2\"]","type":"hcloud_server_network","change":{"actions":["create"],"after":{"ip":"10.0.1.11"}}},{"address":"hcloud_volume_attachment.workspaces[\"web-2\"]","type":"hcloud_volume_attachment","change":{"actions":["create"],"after":{"volume_id":42}}}]'
p=$(plan_with 'hcloud_server.web["web-2"]' '["delete","create"]' beta22 eu-b "$sibs")
out=$(stock_preflight_gate "$p" 2>&1); rc=$?
[[ "$rc" -eq 0 ]] && pass || fail "T9: siblings without server_type must be filtered out, not fail-closed. rc=$rc out=$out"

# ---------------------------------------------------------------------------
# T10 — EXTRACTION MUST #2: a no-op entry ALSO carries after.server_type. Without the
# actions|index("create") filter the gate would preflight untouched hosts — and abort a
# legitimate dispatch because some unrelated live host's type went out of stock.
# alpha33 is unorderable, so an unfiltered gate FAILS here; a correct gate passes.
# ---------------------------------------------------------------------------
FETCH_MODE=ok
noop='[{"address":"hcloud_server.registry","type":"hcloud_server","change":{"actions":["no-op"],"after":{"server_type":"alpha33","location":"eu-b"}}}]'
p=$(plan_with 'hcloud_server.web["web-2"]' '["delete","create"]' beta22 eu-b "$noop")
out=$(stock_preflight_gate "$p" 2>&1); rc=$?
[[ "$rc" -eq 0 ]] && pass || fail "T10: a no-op host must NOT be preflighted (unfiltered gate would abort). rc=$rc out=$out"

# ---------------------------------------------------------------------------
# T10b — NON-MISDIRECTION on the four surviving production paths. RETARGETED 2026-07-20
# (Superseded in part by #6730 and #6969: web-host-create and web-host-replace now preflight web hosts too. This case
# still guards the NON-web paths, which is why the web-1 clause stays conditionally worded.)
# (#6575): the warm-standby half of this test is vacuous now that no such dispatch exists, but
# the invariant it protected is MORE live, not less. After the web-2 retire, every production
# caller of stock_preflight_gate is a NON-WEB host (inngest-host-replace, registry-host-replace,
# registry-region-migrate, git-data-host-replace), while the surviving menu carries a web-1
# clause. So the risk inverted: the thing that must not leak onto a registry abort is now the
# web-1 text. Assert the generic menu survives and the web-1 specifics stay suppressed.
# ---------------------------------------------------------------------------
FETCH_MODE=ok
p=$(plan_with 'hcloud_server.registry' '["delete","create"]' alpha33 eu-b)
out=$(stock_preflight_gate "$p" 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T10b: an unorderable registry recreate must abort, got $rc"
grep -q "warm-standby" <<<"$out" && fail "T10b: warm-standby was deleted with web-2 (#6575); it must never be offered on any path" || pass
grep -q "#6463" <<<"$out" && pass || fail "T10b: the generic #6463 tine must survive on every path"
grep -q "PRIMARY: wait and re-dispatch" <<<"$out" && pass || fail "T10b: the wait-for-stock primary must survive on non-web paths"
grep -q "NOT orderable in 'eu-b'" <<<"$out" && pass || fail "T10b: the stock-miss abort itself must still fire"

# T10c — REPLACES the former over-suppression guard (which asserted web-2 KEPT the warm-standby
# tine through the gate path). This PR is legitimately the "fix that drops the tine everywhere"
# that guard existed to catch, so the old assertion had to go — but the invariant must outlive
# it. A stock abort that emits ZERO remediation lines is a dead end for the operator, so assert
# the floor directly: >= 1 remediation line, whatever its wording.
p=$(plan_with 'hcloud_server.git_data' '["delete","create"]' alpha33 eu-b)
out=$(stock_preflight_gate "$p" 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T10c: an unorderable git-data recreate must abort, got $rc"
tines=$(grep -c '^::error::  - ' <<<"$out" || true)
[[ "$tines" -ge 1 ]] && pass || fail "T10c: a stock abort MUST emit at least one remediation line; got ${tines}. A future edit must not be able to strip every tine silently. out=$out"

# ---------------------------------------------------------------------------
# T11 — no server create planned => rc 0 (out of scope, not fail-closed)
# ---------------------------------------------------------------------------
FETCH_MODE=ok
cat > "$TMP/plan.json" <<'JSON'
{"resource_changes":[{"address":"hcloud_volume.registry","type":"hcloud_volume","change":{"actions":["update"],"after":{"size":60}}}]}
JSON
stock_preflight_gate "$TMP/plan.json" >/dev/null 2>&1 && pass || fail "T11: a volume-only plan is out of scope; must not abort"

# ---------------------------------------------------------------------------
# T12 — malformed / missing plan => rc 1 (fail-closed)
#
# Each case asserts its DISTINCT message, not just rc. Every fail-closed path returns 1, so
# an rc-only assertion cannot tell "the guard I am testing fired" from "some other guard
# fired first" — deleting the missing-plan guard entirely left this block GREEN (control
# fell through to the .resource_changes check, rc-equivalent but message-divergent, telling
# the operator the file is malformed when it is actually absent). That is the same
# misdiagnosis class T7 exists to prevent; T12/T12b/T13 now hold the same bar as T5/T6/T7.
# ---------------------------------------------------------------------------
out=$(stock_preflight_gate "$TMP/does-not-exist.json" 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T12: a missing plan must fail closed, got $rc"
grep -q "missing or unreadable" <<<"$out" && pass || fail "T12: a MISSING plan must say so, not report a malformed document. out=$out"

echo '{"not":"a plan"}' > "$TMP/bad.json"
out=$(stock_preflight_gate "$TMP/bad.json" 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T12b: a non-plan document must fail closed, got $rc"
grep -q "no .resource_changes" <<<"$out" && pass || fail "T12b: a non-plan document must name the missing .resource_changes. out=$out"

# T12c — .resource_changes present but NOT an array => jq runtime error (exit 5).
# A bare `pairs=$(jq …)` + 2>/dev/null swallows that into an empty extraction, which the
# emptiness branch reads as "nothing to preflight" => rc 0 => the destroy proceeds unguarded.
# Mirrors the guard shape the now-deleted web2-recreate-gate.sh used (#6575): assert the
# jq key parsed as a non-negative integer BEFORE comparing, so a missing key fails CLOSED.
echo '{"resource_changes":"hello"}' > "$TMP/scalar.json"
out=$(stock_preflight_gate "$TMP/scalar.json" 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T12c: a non-array .resource_changes must fail closed (jq exits 5), got $rc"
grep -q "jq extraction failed" <<<"$out" && pass || fail "T12c: a failed extraction must say so. out=$out"

# T12d — an hcloud_server with NO .change.actions. jq's `null | index("create")` returns
# null (it does not error), so `select` silently DROPS the entry and the work-list comes back
# empty => rc 0. A planned server create must never vanish from the work-list.
echo '{"resource_changes":[{"address":"hcloud_server.web[\"web-2\"]","type":"hcloud_server"}]}' > "$TMP/noactions.json"
out=$(stock_preflight_gate "$TMP/noactions.json" 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T12d: an hcloud_server with no .change.actions must fail closed, got $rc"
grep -q "no array .change.actions" <<<"$out" && pass || fail "T12d: must name the unclassifiable entry. out=$out"

# T12e — tab-only extraction rows (address/type/location all null => `[null,null,null]|@tsv`
# emits "\t\t"). `pairs` is non-empty so the emptiness branch is skipped, every iteration
# hits the `-z addr` continue, and n stays 0 — which previously returned 0 SILENTLY.
cat > "$TMP/nulladdr.json" <<'JSON'
{"resource_changes":[{"address":null,"type":"hcloud_server","change":{"actions":["create"],"after":{"server_type":null,"location":null}}}]}
JSON
out=$(stock_preflight_gate "$TMP/nulladdr.json" 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T12e: rows with no resource address must fail closed, got $rc"
grep -q "none carried a resource address" <<<"$out" && pass || fail "T12e: must name the addressless rows. out=$out"

# ---------------------------------------------------------------------------
# T13 — a create whose after{} lacks server_type => rc 1 (cannot prove stock)
# ---------------------------------------------------------------------------
cat > "$TMP/plan.json" <<'JSON'
{"resource_changes":[{"address":"hcloud_server.mystery","type":"hcloud_server","change":{"actions":["create"],"after":{}}}]}
JSON
out=$(stock_preflight_gate "$TMP/plan.json" 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T13: a create with no server_type must fail closed, got $rc"
grep -q "carries no server_type/location" <<<"$out" && pass || fail "T13: must name the unprovable target, not fall through to another guard's message. out=$out"

# ---------------------------------------------------------------------------
# T13b — git-data plans a plain CREATE (a -replace on an address NOT in state exits 0 and
# plans a create). This is the headline justification for gating that path — it was argued in
# prose and encoded nowhere. Assert the gate actually catches that shape.
#
# The trailing "warm-standby is not offered here" assertion was DELETED 2026-07-20 (#6575):
# with the dispatch and its subject both gone, no code path can emit that string, so the
# assertion was vacuous — it would pass over a suite that had lost the abort entirely. The
# non-vacuous half (an unorderable plain-create on a LIVE production path must abort) is
# retained in full; git-data-host-replace is one of the four surviving callers.
# ---------------------------------------------------------------------------
FETCH_MODE=ok
p=$(plan_with 'hcloud_server.git_data' '["create"]' arm11 eu-a)
out=$(stock_preflight_gate "$p" 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T13b: an unorderable git-data plain-create must abort, got $rc"
grep -q "NOT orderable in 'eu-a'" <<<"$out" && pass || fail "T13b: must fire the stock-miss abort. out=$out"

# ---------------------------------------------------------------------------
# T14 — NON-VACUITY: prove the suite reads .available and not mere PRESENCE. alpha33 has an
# entry in every location and zero available:true. If the gate treated presence as availability,
# T2/T3/T4 would all pass; assert the divergence exists so this suite cannot silently become a
# presence test.
# ---------------------------------------------------------------------------
present=$(fixture_types alpha33 | jq -r '[.server_types[0].locations[]] | length')
avail=$(fixture_types alpha33 | jq -r '[.server_types[0].locations[] | select(.available == true)] | length')
[[ "$present" -gt 0 && "$avail" -eq 0 ]] && pass || fail "T14: fixture must keep present!=available (present=$present available=$avail) or the suite cannot catch a presence regression"

# ---------------------------------------------------------------------------
# NEW-SHAPE CASES (this PR). Malformed bodies are built with jq -n / jq, never heredoc interpolation.
# ---------------------------------------------------------------------------
BASE=$(fixture_types beta22)

# T7d — malformed-body table: every body must fail CLOSED, never as a stock miss, in the RIGHT class: an empty body is
# the unreachable class, everything else a 2xx in an unusable shape is the malformed class — and the malformed abort
# carries a sanitized hint (jq type or top-level key names) because the operator cannot reproduce the response.
for body in '' '<html><body>502 Bad Gateway</body></html>' '[]' 'null' '"x"' '{}' \
            '{"server_types":null}' '{"server_types":{}}' '{"server_types":["x"]}'; do
  run_body "$body" beta22 eu-b
  [[ "$rc" -eq 1 ]] && pass || fail "T7d: body [$body] must abort, got rc=$rc"
  grep -q "cannot PROVE stock" <<<"$out" && pass || fail "T7d: body [$body] must produce the blip message. out=$out"
  grep -q "NOT orderable" <<<"$out" && fail "T7d: body [$body] must not read as a stock miss" || pass
  if [[ -z "$body" ]]; then
    grep -q "class=unreachable" <<<"$out" && pass || fail "T7d: an empty body is the unreachable class. out=$out"
  else
    grep -q "class=malformed" <<<"$out" && pass || fail "T7d: body [$body] is the malformed class. out=$out"
    grep -q "body=" <<<"$out" && pass || fail "T7d: body [$body] must carry a shape hint. out=$out"
  fi
done
run_body '<html><body>502 Bad Gateway</body></html>' beta22 eu-b
grep -q "body=not-json" <<<"$out" && pass || fail "T7d: an HTML error page must hint not-json. out=$out"
run_body '[]' beta22 eu-b
grep -q "body=array" <<<"$out" && pass || fail "T7d: a top-level array must hint array. out=$out"

# T7f — a 200 body that carries a VALID orderable doc AND an error key, and the bare 410 body at /server_types.
run_body "$(jq -c '. + {error: {code: "x"}}' <<<"$BASE")" beta22 eu-b
[[ "$rc" -eq 1 ]] && pass || fail "T7f: an error key beside a valid doc must abort, got $rc"
grep -q "cannot PROVE stock" <<<"$out" && pass || fail "T7f: an error key must produce the blip message. out=$out"
grep -q "class=malformed" <<<"$out" && pass || fail "T7f: an error key beside a valid doc is the malformed class. out=$out"
grep -q "api_error=" <<<"$out" && fail "T7f: a 2xx answer carries no api_error, even when it has an error key" || pass
run_body "$BODY_410" beta22 eu-b
[[ "$rc" -eq 1 ]] && pass || fail "T7f: the bare 410 body at /server_types must abort, got $rc"
grep -q "cannot PROVE stock" <<<"$out" && pass || fail "T7f: the 410 body must produce the blip message. out=$out"
grep -q "class=malformed" <<<"$out" && pass || fail "T7f: a 410 body served with a 2xx status is the malformed class. out=$out"

# T7h — the shape hint names KEYS, never values, caps at 8 keys / 120 chars, and drops keys outside [A-Za-z0-9_].
run_body '{"k":"SECRETVALUE-xyz"}' beta22 eu-b
grep -q "SECRETVALUE" <<<"$out" && fail "T7h: a body VALUE must never reach the log. out=$out" || pass
grep -q "body=object keys=k)" <<<"$out" && pass || fail "T7h: the hint must be the key names only. out=$out"
run_body "$(jq -nc '[range(0; 12) | {key: ("k" + tostring), value: 1}] | from_entries')" beta22 eu-b
hint=$(grep -o 'body=[^)]*' <<<"$out" | head -n1)
[[ "$(tr -cd ',' <<<"$hint" | wc -c)" -le 7 ]] && pass || fail "T7h: at most 8 keys may be listed. hint=$hint"
run_body "$(jq -nc '[range(0; 8) | {key: ("k" + tostring + ("y" * 30)), value: 1}] | from_entries')" beta22 eu-b
hint=$(grep -o 'body=[^)]*' <<<"$out" | head -n1)
[[ "${#hint}" -le 125 ]] && pass || fail "T7h: the hint is capped at 120 chars after 'body='. len=${#hint}"
run_body '{"a b":1,"ok_key":2}' beta22 eu-b
grep -q "a b" <<<"$out" && fail "T7h: a key outside [A-Za-z0-9_] must be dropped. out=$out" || pass
grep -q "ok_key" <<<"$out" && pass || fail "T7h: a clean key must be kept. out=$out"

# T7i — trailing junk after a valid orderable doc: jq prints the verdict of the FIRST document and then exits non-zero,
# so the verdict must be captured with `|| verdict=""` or ORDERABLE would be read off a body that is not one document.
# T7j — two VALID documents: a different mechanism — jq prints two lines and exits 0, and the exact-token `case` rejects
# the multi-line verdict. The abort names it instead of echoing a verdict token as the reason.
run_body "${BASE}garbage" beta22 eu-b
[[ "$rc" -eq 1 ]] && pass || fail "T7i: trailing junk after a valid doc must abort, got $rc"
grep -q "class=malformed" <<<"$out" && pass || fail "T7i: trailing junk is the malformed class. out=$out"
run_body "${BASE}${BASE}" beta22 eu-b
[[ "$rc" -eq 1 ]] && pass || fail "T7j: two JSON documents must abort, got $rc"
grep -q "multiple JSON documents" <<<"$out" && pass || fail "T7j: two documents must be named, not reported as a verdict token. out=$out"
grep -q "does not accept: ORDERABLE" <<<"$out" && fail "T7j: the abort must never print ORDERABLE as the rejected shape" || pass

# T15 — locations absent / null / object => MALFORMED:locations (blip); [] => unknown location.
for v in absent null object; do
  case "$v" in
    absent) body=$(jq -c '.server_types[0] |= del(.locations)' <<<"$BASE") ;;
    null)   body=$(jq -c '.server_types[0].locations = null' <<<"$BASE") ;;
    object) body=$(jq -c '.server_types[0].locations = {}' <<<"$BASE") ;;
  esac
  run_body "$body" beta22 eu-b
  [[ "$rc" -eq 1 ]] && pass || fail "T15: locations $v must abort, got $rc"
  grep -q "MALFORMED:locations" <<<"$out" && pass || fail "T15: locations $v must report MALFORMED:locations. out=$out"
  grep -q "class=malformed" <<<"$out" && pass || fail "T15: locations $v is the malformed class. out=$out"
done
run_body "$(jq -c '.server_types[0].locations = []' <<<"$BASE")" beta22 eu-b
[[ "$rc" -eq 1 ]] && pass || fail "T15: an empty locations array must abort, got $rc"
grep -q "unknown location" <<<"$out" && pass || fail "T15: an empty locations array must say unknown location. out=$out"

# T16 — `available` must be the boolean true: "true", 1, null, absent are MALFORMED:available (never orderable,
# never a stock miss); a real false at eu-a is a stock miss.
for v in str num null absent; do
  case "$v" in
    str)    body=$(jq -c '(.server_types[0].locations[] | select(.name == "eu-b") | .available) = "true"' <<<"$BASE") ;;
    num)    body=$(jq -c '(.server_types[0].locations[] | select(.name == "eu-b") | .available) = 1' <<<"$BASE") ;;
    null)   body=$(jq -c '(.server_types[0].locations[] | select(.name == "eu-b") | .available) = null' <<<"$BASE") ;;
    absent) body=$(jq -c '.server_types[0].locations |= map(if .name == "eu-b" then del(.available) else . end)' <<<"$BASE") ;;
  esac
  run_body "$body" beta22 eu-b
  [[ "$rc" -eq 1 ]] && pass || fail "T16: available=$v must abort, got $rc"
  grep -q "MALFORMED:available" <<<"$out" && pass || fail "T16: available=$v must report MALFORMED:available. out=$out"
  grep -q "class=malformed" <<<"$out" && pass || fail "T16: available=$v is the malformed class. out=$out"
  grep -q "NOT orderable" <<<"$out" && fail "T16: available=$v must not read as a stock miss" || pass
done
FETCH_MODE=ok
out=$(stock_preflight beta22 eu-a 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T16: a real available:false must abort, got $rc"
grep -q "NOT orderable in 'eu-a'" <<<"$out" && pass || fail "T16: a real false must be a stock miss. out=$out"

# T17 — duplicates and junk: a duplicate type, duplicate location entries in BOTH orders, a junk STRING member (jq
# errors on `"x".name`, so the verdict is empty and the answer aborts as unparseable; T22 pins number/array/bool junk and
# the deliberate decision that a NULL sibling is skipped).
run_body "$(jq -c '.server_types += [.server_types[0]]' <<<"$BASE")" beta22 eu-b
[[ "$rc" -eq 1 ]] && pass || fail "T17: a duplicate type must abort, got $rc"
run_body "$(jq -c --argjson e "$(loc_entry eu-b false)" '.server_types[0].locations += [$e]' <<<"$BASE")" beta22 eu-b
[[ "$rc" -eq 1 ]] && pass || fail "T17: duplicate location entries (true,false) must abort, got $rc"
run_body "$(jq -c --argjson e "$(loc_entry eu-b false)" '.server_types[0].locations = [$e] + .server_types[0].locations' <<<"$BASE")" beta22 eu-b
[[ "$rc" -eq 1 ]] && pass || fail "T17: duplicate location entries (false,true) must abort, got $rc"
run_body "$(jq -c '.server_types[0].locations += ["x"]' <<<"$BASE")" beta22 eu-b
[[ "$rc" -eq 1 ]] && pass || fail "T17: a junk member in locations must abort, got $rc"

# T18 — selection by NAME, never by position. If `?name=` were ignored the list would hold other types.
OTHER=$(type_doc 9100 other "$LOCS_OTHER")
ALPHA=$(type_doc 9001 alpha33 "$LOCS_ALPHA33")
BETA=$(type_doc 9002 beta22 "$LOCS_BETA22")
run_body "{\"server_types\":[$OTHER,$ALPHA]}" alpha33 eu-b
[[ "$rc" -eq 1 ]] && pass || fail "T18a: [other(true everywhere), wanted(false)] must abort on the WANTED type, got $rc"
grep -q "NOT orderable in 'eu-b'" <<<"$out" && pass || fail "T18a: must be a stock miss for the wanted type. out=$out"
# the ADVISORY list is also about the WANTED type: `other` is orderable in every EU location, alpha33 in none
grep -q "orderable in EU: <none>" <<<"$out" && pass || fail "T18a: the alternatives list must describe the wanted type, not the first type in the list. out=$out"
run_body "{\"server_types\":[$OTHER,$BETA]}" beta22 eu-b
[[ "$rc" -eq 0 ]] && pass || fail "T18b: [other, wanted(true)] must pass on the WANTED type, got $rc"
run_body "{\"server_types\":[$OTHER]}" beta22 eu-b
[[ "$rc" -eq 1 ]] && pass || fail "T18c: a non-empty list without the wanted type must abort, got $rc"
grep -q "MALFORMED:filter-ignored" <<<"$out" && pass || fail "T18c: must report filter-ignored, never authorize or call it a typo. out=$out"
grep -q "class=malformed" <<<"$out" && pass || fail "T18c: filter-ignored is the malformed class. out=$out"

# T19 — alternatives strictness: only the boolean true is suggested, and only inside the EU allow-set.
ALT_STR=$(type_doc 9200 alt66 "[$(loc_entry eu-a false),$(loc_entry eu-b false),$(loc_entry eu-c '"true"'),$(loc_entry far true)]")
ALT_NUM=$(type_doc 9200 alt66 "[$(loc_entry eu-a false),$(loc_entry eu-b false),$(loc_entry eu-c 1),$(loc_entry far true)]")
ALT_OK=$(type_doc 9200 alt66 "[$(loc_entry eu-a false),$(loc_entry eu-b false),$(loc_entry eu-c true),$(loc_entry far true)]")
run_body "{\"server_types\":[$ALT_STR]}" alt66 eu-b
grep -q "orderable in EU: <none>" <<<"$out" && pass || fail "T19: a string \"true\" must not be suggested. out=$out"
run_body "{\"server_types\":[$ALT_NUM]}" alt66 eu-b
grep -q "orderable in EU: <none>" <<<"$out" && pass || fail "T19: the number 1 must not be suggested. out=$out"
run_body "{\"server_types\":[$ALT_OK]}" alt66 eu-b
grep -q "orderable in EU: eu-c)" <<<"$out" && pass || fail "T19: the exact payload must be eu-c (never far). out=$out"

ALT_TWO=$(type_doc 9200 alt66 "[$(loc_entry eu-a false),$(loc_entry eu-b true),$(loc_entry eu-c true),$(loc_entry far true)]")
run_body "{\"server_types\":[$ALT_TWO]}" alt66 eu-a
grep -q "orderable in EU: eu-b eu-c)" <<<"$out" && pass || fail "T19d: two EU locations available and one non-EU must list exactly eu-b eu-c. out=$out"
[[ "$rc" -eq 1 ]] && pass || fail "T19d: the stock miss at eu-a must still abort, got $rc"

# MUST-PASS — harmless variations of a good document are still authorized (a gate that rejects everything is
# today's failure, not safety): extra fields, reversed key order, a null sibling, a non-null deprecation.
run_body "$(jq -c '.server_types[0].extra = {"a": [1, 2]} | .meta = null' <<<"$BASE")" beta22 eu-b
[[ "$rc" -eq 0 ]] && pass || fail "MUST-PASS: extra fields and a null sibling must still pass, got $rc. out=$out"
run_body "$(jq -c '.server_types[0].locations |= map(to_entries | reverse | from_entries)' <<<"$BASE")" beta22 eu-b
[[ "$rc" -eq 0 ]] && pass || fail "MUST-PASS: reversed key order must still pass, got $rc. out=$out"
[[ "$(jq -r '.server_types[0].locations[] | select(.name == "eu-b") | .deprecation | type' <<<"$BASE")" == "object" ]] \
  && pass || fail "MUST-PASS: the canonical orderable fixture must carry a non-null deprecation at eu-b"

# ---------------------------------------------------------------------------
# T21 — NAME OVERLAP (fixture POPULATION): types and locations whose names merely CONTAIN, or are CONTAINED IN, the wanted
# one must never be mistaken for it. Real names overlap (cx33 / ccx33). The positive-only fixtures above cannot see a
# `contains` / `endswith` / `startswith` regression, because every wanted name there is unique in its document.
# ---------------------------------------------------------------------------
OV_SUF=$(type_doc 9301 beta22x "$LOCS_OTHER")     # name merely STARTS with the wanted one, orderable everywhere
OV_PRE=$(type_doc 9302 xbeta22 "$LOCS_OTHER")     # name merely ENDS with the wanted one, orderable everywhere
OV_WANT=$(type_doc 9002 beta22 "$LOCS_ALPHA33")   # the wanted type itself: unavailable at eu-b
run_body "{\"server_types\":[$OV_SUF,$OV_PRE,$OV_WANT]}" beta22 eu-b
[[ "$rc" -eq 1 ]] && pass || fail "T21: orderable cousins beside an unavailable wanted type must abort, got $rc"
grep -q "NOT orderable in 'eu-b'" <<<"$out" && pass || fail "T21: the answer must be about the WANTED type (stock miss). out=$out"
grep -q "orderable in EU: <none>" <<<"$out" && pass || fail "T21: the alternatives list must not be built from an orderable name-cousin. out=$out"
run_body "{\"server_types\":[$OV_SUF,$OV_PRE]}" beta22 eu-b
[[ "$rc" -eq 1 ]] && pass || fail "T21: only name-cousins of the wanted type must abort, got $rc"
grep -q "MALFORMED:filter-ignored" <<<"$out" && pass || fail "T21: cousins are not the wanted type (filter-ignored). out=$out"
OV_LOC=$(type_doc 9303 ovl "[$(loc_entry eu-b2 true),$(loc_entry eu-b false)]")
run_body "{\"server_types\":[$OV_LOC]}" ovl eu-b
[[ "$rc" -eq 1 ]] && pass || fail "T21: a location cousin (eu-b2 true) beside eu-b false must abort, got $rc"
grep -q "NOT orderable in 'eu-b'" <<<"$out" && pass || fail "T21: the answer must be about eu-b, not eu-b2. out=$out"
OV_LOC2=$(type_doc 9303 ovl "[$(loc_entry eu-b2 true)]")
run_body "{\"server_types\":[$OV_LOC2]}" ovl eu-b
[[ "$rc" -eq 1 ]] && pass || fail "T21: only a location cousin must abort, got $rc"
grep -q "unknown location" <<<"$out" && pass || fail "T21: a location cousin is not the wanted location. out=$out"

# ---------------------------------------------------------------------------
# T22 — JUNK MEMBERS beside the subject. A number, array or boolean member makes jq error, so the verdict is empty and
# the answer aborts (loud). A NULL member is skipped by `select` — a DELIBERATE decision: it cannot widen anything,
# because exactly one named match with available:true still governs. Pinned both ways so neither drifts silently.
# ---------------------------------------------------------------------------
for junk in 1 '[]' true; do
  run_body "$(jq -c --argjson j "$junk" '.server_types[0].locations += [$j]' <<<"$BASE")" beta22 eu-b
  [[ "$rc" -eq 1 ]] && pass || fail "T22: a junk member [$junk] in locations must abort, got $rc"
  run_body "$(jq -c --argjson j "$junk" '.server_types += [$j]' <<<"$BASE")" beta22 eu-b
  [[ "$rc" -eq 1 ]] && pass || fail "T22: a junk member [$junk] in server_types must abort, got $rc"
done
run_body "$(jq -c '.server_types = [null] + .server_types' <<<"$BASE")" beta22 eu-b
[[ "$rc" -eq 0 ]] && pass || fail "T22: a null sibling in server_types is skipped (deliberate), got $rc. out=$out"
run_body "$(jq -c '.server_types[0].locations = [null] + .server_types[0].locations' <<<"$BASE")" beta22 eu-b
[[ "$rc" -eq 0 ]] && pass || fail "T22: a null sibling in locations is skipped (deliberate), got $rc. out=$out"

# ---------------------------------------------------------------------------
# T23 — INPUT GUARDS: a value that cannot be queried safely must abort BEFORE any request. `&name=` would make Hetzner
# answer about a different type than terraform orders. Each row asserts the message AND that no request was made.
# ---------------------------------------------------------------------------
: > "$CALLS_LOG"
for row in 'beta22&name=alpha33|eu-b|not a valid Hetzner type name' 'BETA22|eu-b|not a valid Hetzner type name' \
           'beta 22|eu-b|not a valid Hetzner type name' '|eu-b|called without server_type/location' \
           'beta22|EU-B|not a valid Hetzner location name' 'beta22|eu-b#x|not a valid Hetzner location name' \
           'beta22||called without server_type/location' 'beta22 |eu-b|not a valid Hetzner type name' \
           'beta#22|eu-b|not a valid Hetzner type name' 'beta22|eu=b|not a valid Hetzner location name'; do
  IFS='|' read -r g_type g_loc g_msg <<<"$row"
  out=$(stock_preflight "$g_type" "$g_loc" 2>&1); rc=$?
  [[ "$rc" -eq 1 ]] && pass || fail "T23: [$g_type]/[$g_loc] must abort, got $rc"
  grep -q "$g_msg" <<<"$out" && pass || fail "T23: [$g_type]/[$g_loc] must say '$g_msg'. out=$out"
  grep -q "class=config" <<<"$out" && pass || fail "T23: an unqueryable value is the config class. out=$out"
  [[ "$(grep -o 'class=' <<<"$out" | wc -l)" -eq 1 ]] && pass || fail "T23: exactly one class token per abort. out=$out"
done
[[ ! -s "$CALLS_LOG" ]] && pass || fail "T23: an unsafe value must never reach the network; calls: $(cat "$CALLS_LOG")"

# ---------------------------------------------------------------------------
# T24 — MULTI-CREATE plans, BOTH orders. Each planned create is judged alone and every failure counts; a gate that stops
# at the first bad row, or lets a later good row reset the verdict, authorizes a destroy for the bad one.
# ---------------------------------------------------------------------------
two_plan() { # <addr1> <type1> <loc1> <addr2> <type2> <loc2>
  jq -n --arg a1 "$1" --arg t1 "$2" --arg l1 "$3" --arg a2 "$4" --arg t2 "$5" --arg l2 "$6" \
    '{resource_changes: [
        {address: $a1, type: "hcloud_server", change: {actions: ["create"], after: {server_type: $t1, location: $l1}}},
        {address: $a2, type: "hcloud_server", change: {actions: ["create"], after: {server_type: $t2, location: $l2}}}]}' \
    > "$TMP/plan2.json"
  echo "$TMP/plan2.json"
}
FETCH_MODE=ok
: > "$CALLS_LOG"
out=$(stock_preflight_gate "$(two_plan hcloud_server.bad alpha33 eu-b hcloud_server.good beta22 eu-b)" 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T24: [bad, good] must abort, got $rc"
[[ "$(grep -c '^/server_types' "$CALLS_LOG")" -eq 2 ]] && pass || fail "T24: [bad, good] must preflight BOTH rows; calls: $(cat "$CALLS_LOG")"
grep -qF "hcloud_server.bad" <<<"$out" && pass || fail "T24: the offending address must be named. out=$out"
: > "$CALLS_LOG"
out=$(stock_preflight_gate "$(two_plan hcloud_server.good beta22 eu-b hcloud_server.bad alpha33 eu-b)" 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T24: [good, bad] must abort, got $rc"
[[ "$(grep -c '^/server_types' "$CALLS_LOG")" -eq 2 ]] && pass || fail "T24: [good, bad] must preflight BOTH rows; calls: $(cat "$CALLS_LOG")"
: > "$CALLS_LOG"
out=$(stock_preflight_gate "$(two_plan hcloud_server.a beta22 eu-b hcloud_server.b beta22 eu-c)" 2>&1); rc=$?
[[ "$rc" -eq 0 ]] && pass || fail "T24: [good, good] must pass, got $rc. out=$out"
grep -q "2 planned server create(s)" <<<"$out" && pass || fail "T24: the PASS line must count both creates. out=$out"
[[ "$(grep -c '^/server_types' "$CALLS_LOG")" -eq 2 ]] && pass || fail "T24: [good, good] must make one request per create; calls: $(cat "$CALLS_LOG")"

# T24c — N-create plans: the middle/last row bad, and two creates of the SAME type and location (no memoization — each
# create is its own request, because stock for one server does not cover two).
multi_plan() { # <addr> <type> <loc> ... (any number of triples)
  jq -n '$ARGS.positional as $a | {resource_changes: [range(0; ($a | length); 3) as $i
      | {address: $a[$i], type: "hcloud_server", change: {actions: ["create"], after: {server_type: $a[$i + 1], location: $a[$i + 2]}}}]}' \
    --args "$@" > "$TMP/planN.json"
  echo "$TMP/planN.json"
}
FETCH_MODE=ok
: > "$CALLS_LOG"
out=$(stock_preflight_gate "$(multi_plan hcloud_server.a beta22 eu-b hcloud_server.b beta22 eu-c hcloud_server.c alpha33 eu-b)" 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T24c: [good, good, bad] must abort, got $rc"
[[ "$(grep -c '^/server_types' "$CALLS_LOG")" -eq 3 ]] && pass || fail "T24c: all three creates must be preflighted; calls: $(cat "$CALLS_LOG")"
grep -qF "hcloud_server.c" <<<"$out" && pass || fail "T24c: the THIRD row must be the one named. out=$out"
: > "$CALLS_LOG"
out=$(stock_preflight_gate "$(multi_plan hcloud_server.a beta22 eu-b hcloud_server.b alpha33 eu-b hcloud_server.c beta22 eu-c)" 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T24c: [good, bad, good] must abort, got $rc"
grep -qF "hcloud_server.b" <<<"$out" && pass || fail "T24c: the MIDDLE row must be the one named. out=$out"
grep -qF "hcloud_server.a" <<<"$out" && fail "T24c: a good row must not be named as the offender" || pass
: > "$CALLS_LOG"
out=$(stock_preflight_gate "$(multi_plan hcloud_server.a beta22 eu-b hcloud_server.b beta22 eu-b)" 2>&1); rc=$?
[[ "$rc" -eq 0 ]] && pass || fail "T24c: two creates of the same type+location must pass when available, got $rc"
[[ "$(grep -c '^/server_types?name=beta22$' "$CALLS_LOG")" -eq 2 ]] && pass || fail "T24c: each create is its own request (no memoization); calls: $(cat "$CALLS_LOG")"

# T24b — a create row with NO ADDRESS beside a valid row. It used to be skipped silently (`continue`), so the plan passed
# with a single fetch. A create that cannot be named cannot be reconciled: abort.
jq -n '{resource_changes: [
    {address: "hcloud_server.good", type: "hcloud_server", change: {actions: ["create"], after: {server_type: "beta22", location: "eu-b"}}},
    {address: null, type: "hcloud_server", change: {actions: ["create"], after: {server_type: "beta22", location: "eu-b"}}}]}' > "$TMP/noaddr.json"
out=$(stock_preflight_gate "$TMP/noaddr.json" 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T24b: an addressless create row beside a valid row must abort, got $rc. out=$out"
grep -q "carries no resource address" <<<"$out" && pass || fail "T24b: the abort must name the addressless row. out=$out"
# the exact shape that used to be skipped silently: no address AND no target (tab-only row) beside a valid row
jq -n '{resource_changes: [
    {address: "hcloud_server.good", type: "hcloud_server", change: {actions: ["create"], after: {server_type: "beta22", location: "eu-b"}}},
    {address: null, type: "hcloud_server", change: {actions: ["create"], after: {}}}]}' > "$TMP/noaddr2.json"
: > "$CALLS_LOG"
out=$(stock_preflight_gate "$TMP/noaddr2.json" 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T24b: a tab-only create row beside a valid row must abort (it used to be skipped), got $rc. out=$out"
grep -q "carries no resource address" <<<"$out" && pass || fail "T24b: the abort must name the tab-only row. out=$out"
grep -q "plans a create but carries no server_type/location" <<<"$out" && fail "T24b: an addressless row must not be misattributed to a shifted field" || pass

# ---------------------------------------------------------------------------
# T25 — DEPRECATION is annotated, never gated. eu-b carries a (future-dated) deprecation, eu-c does not. Measured live
# 2026-10-05: past-dated deprecations already read available:false, so the gate has nothing to add — but an announced
# future cutoff on a host that is orderable today is worth a ::warning::. The timestamp is sanitized before it is echoed.
# ---------------------------------------------------------------------------
FETCH_MODE=ok
out=$(stock_preflight beta22 eu-b 2>&1); rc=$?
[[ "$rc" -eq 0 ]] && pass || fail "T25: a deprecated-but-available location must still pass, got $rc"
grep -q "::warning::stock-preflight: 'beta22' in 'eu-b'" <<<"$out" && pass || fail "T25: the deprecation must be annotated. out=$out"
grep -q "unavailable_after=2099-06-01T00:00:00+00:00" <<<"$out" && pass || fail "T25: the cutoff date must be shown. out=$out"
out=$(stock_preflight beta22 eu-c 2>&1); rc=$?
grep -q "::warning::" <<<"$out" && fail "T25: a location without a deprecation must not warn" || pass
run_body "$(jq -c '(.server_types[0].locations[] | select(.name == "eu-b") | .deprecation.unavailable_after) = "x\n::error::forged"' <<<"$BASE")" beta22 eu-b
[[ "$rc" -eq 0 ]] && pass || fail "T25: a hostile deprecation value must not change the verdict, got $rc"
grep -q '^::error::' <<<"$out" && fail "T25: a hostile deprecation value must never forge a workflow command line" || pass

# T25b — the annotation is exact: absent on the stock-miss arm, "unknown" when no cutoff is given, sanitized, capped.
run_body "$(jq -c '(.server_types[0].locations[] | select(.name == "eu-a") | .deprecation) = {"announced": "x", "unavailable_after": "2099-01-01T00:00:00Z"}' <<<"$BASE")" beta22 eu-a
[[ "$rc" -eq 1 ]] && pass || fail "T25b: eu-a is unavailable and must abort, got $rc"
grep -q "::warning::" <<<"$out" && fail "T25b: a deprecation on an UNAVAILABLE location must not warn (the verdict is already a stock miss)" || pass
run_body "$(jq -c '(.server_types[0].locations[] | select(.name == "eu-b") | .deprecation) = {"announced": "2099-01-01T00:00:00Z"}' <<<"$BASE")" beta22 eu-b
grep -q "unavailable_after=unknown" <<<"$out" && pass || fail "T25b: a deprecation with no cutoff must still be annotated as unknown. out=$out"
run_body "$(jq -c '(.server_types[0].locations[] | select(.name == "eu-b") | .deprecation.unavailable_after) = "2099 01;x"' <<<"$BASE")" beta22 eu-b
grep -q "unavailable_after=2099?01?x" <<<"$out" && pass || fail "T25b: characters outside [0-9A-Za-z:.+-] must be replaced. out=$out"
run_body "$(jq -c --arg v "$(printf 'a%.0s' $(seq 1 50))ZZZ" '(.server_types[0].locations[] | select(.name == "eu-b") | .deprecation.unavailable_after) = $v' <<<"$BASE")" beta22 eu-b
grep -q "ZZZ" <<<"$out" && fail "T25b: the cutoff is capped at 40 chars. out=$out" || pass

# ---------------------------------------------------------------------------
# T26 — ADVISORY POPULATION: the "orderable in EU" list is exact-name, sorted, de-duplicated and EU-only. A location named
# like a SUBSTRING of the allow-set ("u-a", inside "eu-a") must not be suggested; listing order must not matter.
# ---------------------------------------------------------------------------
ALT_POP=$(type_doc 9400 alt77 "[$(loc_entry eu-c true),$(loc_entry eu-b true),$(loc_entry u-a true),$(loc_entry eu-a false)]")
run_body "{\"server_types\":[$ALT_POP]}" alt77 eu-a
grep -q "orderable in EU: eu-b eu-c)" <<<"$out" && pass || fail "T26: reverse-listed EU stock must read exactly 'eu-b eu-c' and never u-a. out=$out"
ALT_DUP=$(type_doc 9401 alt78 "[$(loc_entry eu-a false),$(loc_entry eu-c true),$(loc_entry eu-c true)]")
run_body "{\"server_types\":[$ALT_DUP]}" alt78 eu-a
grep -q "orderable in EU: eu-c)" <<<"$out" && pass || fail "T26: a duplicated suggestion must be de-duplicated. out=$out"

# the wanted type listed FIRST, another type (orderable in every EU location) second: the list must still be the WANTED
# type's own — here eu-c only — not the first type's and not a union
ADV_W=$(type_doc 9501 advw "[$(loc_entry eu-a false),$(loc_entry eu-b false),$(loc_entry eu-c true)]")
ADV_O=$(type_doc 9502 advo "$LOCS_OTHER")
run_body "{\"server_types\":[$ADV_W,$ADV_O]}" advw eu-a
grep -q "orderable in EU: eu-c)" <<<"$out" && pass || fail "T26: wanted-first alternatives must be exactly eu-c. out=$out"
run_body "{\"server_types\":[$ADV_O,$ADV_W]}" advw eu-a
grep -q "orderable in EU: eu-c)" <<<"$out" && pass || fail "T26: wanted-last alternatives must be exactly eu-c. out=$out"

# T27 — the production endpoint default and the endpoint-override warning (the suite unsets HCLOUD_API before sourcing,
# and every other case replaces _stock_fetch, so nothing else would notice a wrong default).
[[ "$_STOCK_DEFAULT_API" == "https://api.hetzner.cloud/v1" && "$HCLOUD_API" == "https://api.hetzner.cloud/v1" ]] \
  && pass || fail "T27: the production endpoint default must be https://api.hetzner.cloud/v1 (got default=$_STOCK_DEFAULT_API effective=$HCLOUD_API)"
w=$(HCLOUD_API="$_STOCK_DEFAULT_API" _stock_warn_if_endpoint_overridden 2>&1)
[[ -z "$w" ]] && pass || fail "T27: the default endpoint must not warn. out=$w"
w=$(HCLOUD_API='https://svcuser:SYNTH-PASS-123@h.example:8443/v1?apikey=SYNTHKEY#frag' _stock_warn_if_endpoint_overridden 2>&1)
grep -q "host=h.example:8443)" <<<"$w" && pass || fail "T27: only the authority host may be printed. out=$w"
grep -qE "SYNTH|svcuser|apikey|frag" <<<"$w" && fail "T27: userinfo, query and fragment must never reach the log. out=$w" || pass
# a pathless value with a query and fragment, and a scheme-less value whose query contains `://`
w=$(HCLOUD_API='https://h.example?apikey=SYNTHKEY#frag' _stock_warn_if_endpoint_overridden 2>&1)
grep -q "host=h.example)" <<<"$w" && pass || fail "T27: a pathless value must print its host only. out=$w"
grep -qE "SYNTHKEY|apikey|frag" <<<"$w" && fail "T27: query and fragment must be cut at the first ? or #. out=$w" || pass
w=$(HCLOUD_API='h.example/v1?next=http://SYNTHSECRET' _stock_warn_if_endpoint_overridden 2>&1)
grep -q "host=h.example)" <<<"$w" && pass || fail "T27: a scheme-less value must not have its query read as the authority. out=$w"
grep -q "SYNTHSECRET" <<<"$w" && fail "T27: a :// inside a query must never reach the log. out=$w" || pass
# the header carries the literal read-only probe the abort messages point at
grep -qF 'curl -sS -H "Authorization: Bearer $HCLOUD_TOKEN_READONLY"' "$GATE" && pass || fail "T27: the lib header must carry the literal probe command the abort text points at"
w=$(HCLOUD_API=$'https://a.example\nb.example/v1' _stock_warn_if_endpoint_overridden 2>&1)
[[ "$(wc -l <<<"$w")" -eq 1 ]] && pass || fail "T27: a newline in the value must not split the warning line. out=$w"

# ---------------------------------------------------------------------------
# T20 — WIRE LEVEL: the real _stock_fetch against a loopback HTTP server (python3 stdlib). The seam-level cases
# above cannot observe an HTTP status, the request path, the Authorization header, or --fail-with-body; this is the only
# case that can. The lib is re-sourced in a SUBSHELL so the real _stock_fetch replaces the seam there; HCLOUD_API is
# set BEFORE the source (the lib reads it at source time; HCLOUD_TOKEN is read per call). Named failure, never a skip,
# if it cannot run.
# Non-goals, stated: no wire-level timeout case (--max-time 20) and no 3xx case.
# ---------------------------------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
  fail "T20: python3 is required for the loopback wire test and was not found (this case never skips)"
else
  fixture_types beta22 > "$TMP/doc_ok.json"
  printf '%s' "$BODY_410" > "$TMP/doc_410.json"
  cat > "$TMP/srv.py" <<'PY'
import http.server, os, signal, sys
signal.alarm(120)  # an orphan (the suite SIGKILLed before its EXIT trap) must not outlive a CI job
d = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        mode = open(os.path.join(d, "mode")).read().strip()
        with open(os.path.join(d, "req.log"), "a") as f:
            f.write("%s\t%s\n" % (self.path, self.headers.get("Authorization", "")))
        ok = open(os.path.join(d, "doc_ok.json")).read()
        if mode == "ok":
            code, body = 200, ok
        elif mode == "410":
            code, body = 410, open(os.path.join(d, "doc_410.json")).read()
        elif mode == "401":
            code, body = 401, '{"error":{"code":"unauthorized","message":"x"}}'
        else:
            code, body = 502, ok
        b = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)
    def log_message(self, *a):
        pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
open(os.path.join(d, "port.tmp"), "w").write(str(srv.server_address[1]))
os.rename(os.path.join(d, "port.tmp"), os.path.join(d, "port"))
srv.serve_forever()
PY
  python3 "$TMP/srv.py" "$TMP" >/dev/null 2>&1 &
  SRV_PID=$!
  PORT=""
  for _ in $(seq 1 50); do
    [[ -s "$TMP/port" ]] && { PORT=$(cat "$TMP/port"); break; }
    sleep 0.1
  done
  if [[ -z "$PORT" ]]; then
    fail "T20: the loopback server did not publish a port within 5s"
  else
    loop_call() { # <mode> <type> <loc>
      printf '%s' "$1" > "$TMP/mode"; : > "$TMP/req.log"
      (
        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
        export HCLOUD_API="http://127.0.0.1:${PORT}/v1" HCLOUD_TOKEN="synthetic-token-123" NO_PROXY=127.0.0.1 no_proxy=127.0.0.1
        # shellcheck source=/dev/null
        source "$GATE"
        stock_preflight "$2" "$3"
      ) 2>&1
    }
    out=$(loop_call ok beta22 eu-b); rc=$?
    [[ "$rc" -eq 0 ]] && pass || fail "T20a: a 200 orderable document over HTTP must pass, got $rc. out=$out"
    [[ "$(wc -l < "$TMP/req.log")" -eq 1 ]] && pass || fail "T20a: exactly one request expected; log: $(cat "$TMP/req.log")"
    # the EXACT request line: the path is the property (a regression to /datacenters, or a dropped ?name=, is the very
    # bug this PR fixes) and the header is exact (a doubled or suffixed credential must not pass a substring match)
    want_req=$(printf '/v1/server_types?name=beta22\tBearer synthetic-token-123')
    [[ "$(cat "$TMP/req.log")" == "$want_req" ]] && pass || fail "T20a: the request line must be exactly the single /server_types?name= call with the bearer; got: $(cat "$TMP/req.log")"
    grep -q "HCLOUD_API is overridden (host=127.0.0.1:" <<<"$out" && pass || fail "T20a: a non-default HCLOUD_API must be announced. out=$out"
    out=$(loop_call 410 beta22 eu-b); rc=$?
    [[ "$rc" -eq 1 ]] && pass || fail "T20b: an HTTP 410 must abort, got $rc"
    grep -q "with a 2xx: curl exit 22" <<<"$out" && pass || fail "T20b: an HTTP error must surface as curl exit 22 (--fail-with-body). out=$out"
    grep -q "api_error=deprecated_api_endpoint" <<<"$out" && pass || fail "T20b: the 410 body must reach the abort line over the wire. out=$out"
    [[ "$(wc -l < "$TMP/req.log")" -eq 1 ]] && pass || fail "T20b: a 410 must not be retried; log: $(cat "$TMP/req.log")"
    out=$(loop_call 502 beta22 eu-b); rc=$?
    [[ "$rc" -eq 1 ]] && pass || fail "T20c: an HTTP 502 carrying a VALID orderable body must still abort, got $rc"
    grep -q "with a 2xx: curl exit 22" <<<"$out" && pass || fail "T20c: the 502 must abort through the status, not the body. out=$out"
    [[ "$(wc -l < "$TMP/req.log")" -eq 1 ]] && pass || fail "T20c: a 502 must not be retried; log: $(cat "$TMP/req.log")"
    out=$(loop_call 401 beta22 eu-b); rc=$?
    [[ "$rc" -eq 1 ]] && pass || fail "T20d: an HTTP 401 must abort, got $rc"
    grep -q "api_error=unauthorized" <<<"$out" && pass || fail "T20d: a 401 must be distinguishable from a 410 over the wire. out=$out"
  fi
  kill "$SRV_PID" 2>/dev/null; SRV_PID=""
fi

# Reaching this line IS the completion signal the EXIT trap checks (see cleanup above).
SUITE_DONE=1

# Minimum-cardinality floor. This suite is a linear accumulate-then-tally script, so a
# removed block (or a truncation that keeps the trap) leaves `fails` at 0 and the runner reports
# GREEN. A mid-file `exit` is caught by the EXIT-trap completion check above, not by this floor,
# which sits in the very tail such an exit skips. `fails -eq 0` proves nothing was WRONG; it
# cannot prove anything RAN. The `.ts` sibling
# already carries MIN_APPLY_TARGET_OPTIONS / MIN_GATED_TARGETS sentinels for exactly this;
# the asymmetry was the tell. `-lt` (not `-ne`) so adding cases never trips it.
MIN_ASSERTIONS=319
if [ "$passes" -lt "$MIN_ASSERTIONS" ]; then
  echo "stock-preflight-gate: FAIL — only $passes assertion(s) ran, expected >= ${MIN_ASSERTIONS}." >&2
  echo "  The suite did not run to completion (truncation / early exit / removed block)." >&2
  echo "  A green tally over a truncated suite is a false PASS on a gate that guards prod destroys." >&2
  exit 1
fi

echo "stock-preflight-gate: $passes passed, $fails failed"
[ "$fails" -eq 0 ] || exit 1
