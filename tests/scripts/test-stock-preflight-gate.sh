#!/usr/bin/env bash
# Tests for tests/scripts/lib/stock-preflight-gate.sh (sourced by the five
# destroy-shaped apply_target jobs in .github/workflows/apply-web-platform-infra.yml, #6453).
#
# The gate asserts every server a plan will CREATE is orderable in its target location
# BEFORE the destroy runs — because a -replace destroys first, so DC *stock* (not the
# account cap) is what strands the fleet (#6393).
#
# HERMETIC BY CONSTRUCTION (cq-test-fixtures-synthesized-only): every fixture is
# SYNTHESIZED and the gate's _stock_fetch seam is redefined to serve them. No network,
# no HCLOUD_TOKEN, no captured-real API document. This is not stylistic — a live-bound
# suite is RED by lunchtime: on 2026-07-15 cx33 went from "orderable in hel1" to
# orderable in ZERO datacenters within ~3h, and hel1's available count fell 14 -> 12.
# NEVER assert against real stock here.
#
# Mirrors the posture of tests/scripts/test-git-data-host-replace-gate.sh:17-21.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$REPO_ROOT/tests/scripts/lib/stock-preflight-gate.sh"

# shellcheck source=/dev/null
source "$GATE"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

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
# arm11   (9003): an entry everywhere, available nowhere at all -> the cax11 shape
# sing44  (9004): available ONLY in the non-EU location         -> residency-filter probe
# partial55 (9005): lists ONLY eu-c                             -> unknown-location probe
LOCS_ALPHA33="[$(loc_entry eu-a false),$(loc_entry eu-b false),$(loc_entry eu-c false),$(loc_entry far false)]"
LOCS_BETA22="[$(loc_entry eu-a false),$(loc_entry eu-b true "$DEPR"),$(loc_entry eu-c true),$(loc_entry far true)]"
LOCS_ARM11="[$(loc_entry eu-a false),$(loc_entry eu-b false),$(loc_entry eu-c false),$(loc_entry far false)]"
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
    /datacenters*)        printf '%s' "$BODY_410"; return 0 ;;
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
# would advise putting a prod host outside the EU (variables.tf:94-96, CLO T-1).
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

# ---------------------------------------------------------------------------
# T6 — unknown location => rc 1 (fail-closed)
# ---------------------------------------------------------------------------
FETCH_MODE=ok
out=$(stock_preflight beta22 atlantis 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T6: expected rc=1 for an unknown location, got $rc"
grep -q "unknown location" <<<"$out" && pass || fail "T6: abort must name the unknown location"
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

# T7b — a non-2xx fetch (curl --fail-with-body exits 22 and still prints the body): rc 1, blip, and the
# reason carries the curl exit so an operator can tell a changed API contract from a flaky network.
printf '%s' "$BODY_410" > "$BODY_FILE"
FETCH_MODE=body_rc22
out=$(stock_preflight beta22 eu-b 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T7b: expected rc=1 when /server_types answers non-2xx, got $rc"
grep -q "cannot PROVE stock" <<<"$out" && pass || fail "T7b: a non-2xx answer must fail closed with the blip message"
grep -q "curl exit 22" <<<"$out" && pass || fail "T7b: the blip must carry the curl exit status. out=$out"
grep -q "NOT orderable" <<<"$out" && fail "T7b: an API error must not masquerade as a real shortage" || pass

FETCH_MODE=garbage
out=$(stock_preflight beta22 eu-b 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T7c: expected rc=1 on a malformed API document, got $rc"

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

# T7d — malformed-body table: every body must fail CLOSED with the blip message, never as a stock miss.
for body in '' '<html><body>502 Bad Gateway</body></html>' '[]' 'null' '"x"' '{}' \
            '{"server_types":null}' '{"server_types":{}}' '{"server_types":["x"]}'; do
  run_body "$body" beta22 eu-b
  [[ "$rc" -eq 1 ]] && pass || fail "T7d: body [$body] must abort, got rc=$rc"
  grep -q "cannot PROVE stock" <<<"$out" && pass || fail "T7d: body [$body] must produce the blip message. out=$out"
  grep -q "NOT orderable" <<<"$out" && fail "T7d: body [$body] must not read as a stock miss" || pass
done

# T7f — a 200 body that carries a VALID orderable doc AND an error key, and the bare 410 body at /server_types.
run_body "$(jq -c '. + {error: {code: "x"}}' <<<"$BASE")" beta22 eu-b
[[ "$rc" -eq 1 ]] && pass || fail "T7f: an error key beside a valid doc must abort, got $rc"
grep -q "cannot PROVE stock" <<<"$out" && pass || fail "T7f: an error key must produce the blip message. out=$out"
run_body "$BODY_410" beta22 eu-b
[[ "$rc" -eq 1 ]] && pass || fail "T7f: the bare 410 body at /server_types must abort, got $rc"
grep -q "cannot PROVE stock" <<<"$out" && pass || fail "T7f: the 410 body must produce the blip message. out=$out"

# T7i / T7j — trailing junk after a valid orderable doc, and two JSON documents. jq prints the verdict of the
# first document and then exits 5; the verdict must be captured with `|| verdict=""` so this can never authorize.
run_body "${BASE}garbage" beta22 eu-b
[[ "$rc" -eq 1 ]] && pass || fail "T7i: trailing junk after a valid doc must abort, got $rc"
run_body "${BASE}${BASE}" beta22 eu-b
[[ "$rc" -eq 1 ]] && pass || fail "T7j: two JSON documents must abort, got $rc"

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
  grep -q "NOT orderable" <<<"$out" && fail "T16: available=$v must not read as a stock miss" || pass
done
out=$(stock_preflight beta22 eu-a 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T16: a real available:false must abort, got $rc"
grep -q "NOT orderable in 'eu-a'" <<<"$out" && pass || fail "T16: a real false must be a stock miss. out=$out"

# T17 — duplicates and junk: a duplicate type, duplicate location entries in BOTH orders, a junk member.
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
run_body "{\"server_types\":[$OTHER,$BETA]}" beta22 eu-b
[[ "$rc" -eq 0 ]] && pass || fail "T18b: [other, wanted(true)] must pass on the WANTED type, got $rc"
run_body "{\"server_types\":[$OTHER]}" beta22 eu-b
[[ "$rc" -eq 1 ]] && pass || fail "T18c: a non-empty list without the wanted type must abort, got $rc"
grep -q "MALFORMED:filter-ignored" <<<"$out" && pass || fail "T18c: must report filter-ignored, never authorize or call it a typo. out=$out"

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
# T20 — WIRE LEVEL: the real _stock_fetch against a loopback HTTP server (python3 stdlib). The seam-level cases
# above cannot observe an HTTP status, the Authorization header, or --fail-with-body; this is the only case that can.
# The lib is re-sourced in a SUBSHELL so the real _stock_fetch replaces the seam there; HCLOUD_API/HCLOUD_TOKEN are
# set BEFORE the source (the lib reads them at source time). Named failure, never a skip, if it cannot run.
# Non-goals, stated: no wire-level timeout case (--max-time 20) and no 3xx case.
# ---------------------------------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
  fail "T20: python3 is required for the loopback wire test and was not found (this case never skips)"
else
  fixture_types beta22 > "$TMP/doc_ok.json"
  printf '%s' "$BODY_410" > "$TMP/doc_410.json"
  cat > "$TMP/srv.py" <<'PY'
import http.server, os, sys
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
    grep -qF "Bearer synthetic-token-123" "$TMP/req.log" && pass || fail "T20a: the Authorization bearer must reach the wire"
    out=$(loop_call 410 beta22 eu-b); rc=$?
    [[ "$rc" -eq 1 ]] && pass || fail "T20b: an HTTP 410 must abort, got $rc"
    grep -q "curl exit 22" <<<"$out" && pass || fail "T20b: an HTTP error must surface as curl exit 22 (--fail-with-body). out=$out"
    out=$(loop_call 502 beta22 eu-b); rc=$?
    [[ "$rc" -eq 1 ]] && pass || fail "T20c: an HTTP 502 carrying a VALID orderable body must still abort, got $rc"
  fi
  kill "$SRV_PID" 2>/dev/null; SRV_PID=""
fi

# Reaching this line IS the completion signal the EXIT trap checks (see cleanup above).
SUITE_DONE=1

# Minimum-cardinality floor. This suite is a linear accumulate-then-tally script, so a
# mid-file `exit`, a truncation, or a block silently removed leaves `fails` at 0 and the
# runner reports GREEN — truncating everything after T1 yielded "1 passed, 0 failed", EXIT 0.
# `fails -eq 0` proves nothing was WRONG; it cannot prove anything RAN. The `.ts` sibling
# already carries MIN_APPLY_TARGET_OPTIONS / MIN_GATED_TARGETS sentinels for exactly this;
# the asymmetry was the tell. `-lt` (not `-ne`) so adding cases never trips it.
MIN_ASSERTIONS=137
if [ "$passes" -lt "$MIN_ASSERTIONS" ]; then
  echo "stock-preflight-gate: FAIL — only $passes assertion(s) ran, expected >= ${MIN_ASSERTIONS}." >&2
  echo "  The suite did not run to completion (truncation / early exit / removed block)." >&2
  echo "  A green tally over a truncated suite is a false PASS on a gate that guards prod destroys." >&2
  exit 1
fi

echo "stock-preflight-gate: $passes passed, $fails failed"
[ "$fails" -eq 0 ] || exit 1
