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
# T2 — NOT orderable here, orderable elsewhere in EU => rc 1 + the three tines.
# This is the live #6463 shape. The abort MUST name warm-standby: hcloud_server_network.web
# is a separate for_each'd ADDITIVE attach (network.tf:9-13), so a NIC/volume repair needs
# no recreate and no stock. Omitting the tine funnels a free repair into a #6463 escalation.
# ---------------------------------------------------------------------------
FETCH_MODE=ok
out=$(stock_preflight alpha33 eu-b 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T2: expected rc=1 for alpha33@eu-b, got $rc"
grep -q "NOT orderable in 'eu-b'" <<<"$out" && pass || fail "T2: abort must name the location"
grep -q "warm-standby" <<<"$out" && pass || fail "T2: abort MUST offer the additive warm-standby tine (the free repair path)"
grep -q "#6463" <<<"$out" && pass || fail "T2: abort must point at #6463 for a genuine rebirth"
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
# T11 — no server create planned => rc 0 (out of scope, not fail-closed)
# ---------------------------------------------------------------------------
FETCH_MODE=ok
cat > "$TMP/plan.json" <<'JSON'
{"resource_changes":[{"address":"hcloud_volume.registry","type":"hcloud_volume","change":{"actions":["update"],"after":{"size":60}}}]}
JSON
stock_preflight_gate "$TMP/plan.json" >/dev/null 2>&1 && pass || fail "T11: a volume-only plan is out of scope; must not abort"

# ---------------------------------------------------------------------------
# T12 — malformed / missing plan => rc 1 (fail-closed)
# ---------------------------------------------------------------------------
stock_preflight_gate "$TMP/does-not-exist.json" >/dev/null 2>&1 && fail "T12: a missing plan must fail closed" || pass
echo '{"not":"a plan"}' > "$TMP/bad.json"
stock_preflight_gate "$TMP/bad.json" >/dev/null 2>&1 && fail "T12b: a non-plan document must fail closed" || pass

# ---------------------------------------------------------------------------
# T13 — a create whose after{} lacks server_type => rc 1 (cannot prove stock)
# ---------------------------------------------------------------------------
cat > "$TMP/plan.json" <<'JSON'
{"resource_changes":[{"address":"hcloud_server.mystery","type":"hcloud_server","change":{"actions":["create"],"after":{}}}]}
JSON
out=$(stock_preflight_gate "$TMP/plan.json" 2>&1); rc=$?
[[ "$rc" -eq 1 ]] && pass || fail "T13: a create with no server_type must fail closed, got $rc"

# ---------------------------------------------------------------------------
# T14 — NON-VACUITY: prove the suite reads .available and not .supported.
# Every type is `supported` everywhere in the fixtures. If the gate were rewritten
# against .supported, T2/T3/T4 would all pass. Assert the divergence exists so this
# suite cannot silently become a .supported test.
# ---------------------------------------------------------------------------
sup=$(fixture_dcs | jq -r '[.datacenters[] | select(.name=="eu-a-dc1") | .server_types.supported[]] | length')
avl=$(fixture_dcs | jq -r '[.datacenters[] | select(.name=="eu-a-dc1") | .server_types.available[]] | length')
[[ "$sup" -gt 0 && "$avl" -eq 0 ]] && pass || fail "T14: fixture must keep supported!=available (supported=$sup available=$avl) or the suite cannot catch a .supported regression"

echo "stock-preflight-gate: $passes passed, $fails failed"
[ "$fails" -eq 0 ] || exit 1
