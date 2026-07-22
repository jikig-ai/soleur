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
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Synthesized API fixtures.
#
# Type ids are arbitrary synthetic integers — NOT Hetzner's real ids. Binding a
# fixture to a real id invites someone to "verify" it against live state, which is
# exactly the coupling this suite exists to avoid.
#
# Shape mirrors the real API: /datacenters exposes BOTH .available (orderable now)
# and .supported (what the DC can host). The two DIVERGE in these fixtures on
# purpose — 9001 is `supported` everywhere but `available` nowhere in EU. A gate
# that read .supported would pass T2/T3 and ship the live trap; these fixtures make
# that mistake fail loudly.
# ---------------------------------------------------------------------------
SUPPORTED_ALL='[9001,9002,9003,9004]'

fixture_types() {
  case "$1" in
    alpha33) echo '{"server_types":[{"id":9001,"name":"alpha33"}]}' ;;
    beta22)  echo '{"server_types":[{"id":9002,"name":"beta22"}]}' ;;
    arm11)   echo '{"server_types":[{"id":9003,"name":"arm11"}]}' ;;
    sing44)  echo '{"server_types":[{"id":9004,"name":"sing44"}]}' ;;
    *)       echo '{"server_types":[]}' ;;   # unknown type
  esac
}

# alpha33 (9001): supported in EU, available NOWHERE      -> the cx33/#6463 shape
# beta22  (9002): available in eu-b + eu-c                -> the orderable shape
# arm11   (9003): supported, available nowhere at all     -> the cax11 shape
# sing44  (9004): available ONLY in the non-EU DC         -> residency-filter probe
fixture_dcs() {
  cat <<JSON
{"datacenters":[
  {"name":"eu-a-dc1","location":{"name":"eu-a"},"server_types":{"available":[],           "supported":$SUPPORTED_ALL}},
  {"name":"eu-b-dc1","location":{"name":"eu-b"},"server_types":{"available":[9002],       "supported":$SUPPORTED_ALL}},
  {"name":"eu-c-dc1","location":{"name":"eu-c"},"server_types":{"available":[9002],       "supported":$SUPPORTED_ALL}},
  {"name":"far-dc1", "location":{"name":"far"}, "server_types":{"available":[9002,9004],  "supported":$SUPPORTED_ALL}}
]}
JSON
}

# The EU allow-set for this suite's synthetic topology.
STOCK_PREFLIGHT_EU_LOCATIONS="eu-a eu-b eu-c"

# Fetch seam override. FETCH_MODE steers failure injection.
FETCH_MODE="ok"
_stock_fetch() {
  local path="$1"
  case "$FETCH_MODE" in
    fail_all)   return 1 ;;
    fail_dcs)   [[ "$path" == /datacenters* ]] && return 1 ;;
    garbage)    echo '{"unexpected":"shape"}'; return 0 ;;
  esac
  case "$path" in
    /server_types?name=*) fixture_types "${path#/server_types?name=}" ;;
    /datacenters*)        fixture_dcs ;;
    *)                    return 1 ;;
  esac
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
if stock_preflight beta22 eu-b >/dev/null 2>&1; then pass; else fail "T1: beta22@eu-b is available; expected rc=0"; fi

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
# /v1/datacenters really does return ash/hil/sin; an unfiltered "orderable elsewhere"
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

FETCH_MODE=fail_dcs
out=$(stock_preflight beta22 eu-b 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T7b: expected rc=1 when /datacenters fails, got $rc"
grep -q "cannot PROVE stock" <<<"$out" && pass || fail "T7b: /datacenters failure must fail closed with the blip message"

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
# T14 — NON-VACUITY: prove the suite reads .available and not .supported.
# Every type is `supported` everywhere in the fixtures. If the gate were rewritten
# against .supported, T2/T3/T4 would all pass. Assert the divergence exists so this
# suite cannot silently become a .supported test.
# ---------------------------------------------------------------------------
sup=$(fixture_dcs | jq -r '[.datacenters[] | select(.name=="eu-a-dc1") | .server_types.supported[]] | length')
avl=$(fixture_dcs | jq -r '[.datacenters[] | select(.name=="eu-a-dc1") | .server_types.available[]] | length')
[[ "$sup" -gt 0 && "$avl" -eq 0 ]] && pass || fail "T14: fixture must keep supported!=available (supported=$sup available=$avl) or the suite cannot catch a .supported regression"

# Minimum-cardinality floor. This suite is a linear accumulate-then-tally script, so a
# mid-file `exit`, a truncation, or a block silently removed leaves `fails` at 0 and the
# runner reports GREEN — truncating everything after T1 yielded "1 passed, 0 failed", EXIT 0.
# `fails -eq 0` proves nothing was WRONG; it cannot prove anything RAN. The `.ts` sibling
# already carries MIN_APPLY_TARGET_OPTIONS / MIN_GATED_TARGETS sentinels for exactly this;
# the asymmetry was the tell. `-lt` (not `-ne`) so adding cases never trips it.
MIN_ASSERTIONS=53
if [ "$passes" -lt "$MIN_ASSERTIONS" ]; then
  echo "stock-preflight-gate: FAIL — only $passes assertion(s) ran, expected >= ${MIN_ASSERTIONS}." >&2
  echo "  The suite did not run to completion (truncation / early exit / removed block)." >&2
  echo "  A green tally over a truncated suite is a false PASS on a gate that guards prod destroys." >&2
  exit 1
fi

echo "stock-preflight-gate: $passes passed, $fails failed"
[ "$fails" -eq 0 ] || exit 1
