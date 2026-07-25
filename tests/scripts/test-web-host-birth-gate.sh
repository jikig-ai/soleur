#!/usr/bin/env bash
# Test suite for tests/scripts/lib/web-host-birth-gate.sh (#6730).
#
# This gate is the INVERSE of web2-retire-gate.sh: retirement permits destroys and
# requires host_creates == 0; a BIRTH requires exactly one host create and permits
# no destroys at all. The two must never be graded against each other's allow-set —
# the retire gate's own header carries that warning, and this file is the sibling it
# was warning about.
#
# The property that actually protects production is the REJECT set. A birth gate that
# only proves "the happy plan passes" is worthless: the whole reason this job may
# create a host, when every other route HALTs, is that this gate refuses everything
# that is not the one requested host. So every arm below is a refusal, and each is
# mutation-proven in the mutation section at the end.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
GATE="${ROOT}/tests/scripts/lib/web-host-birth-gate.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf '  FAIL %s\n' "$1"; printf '       rc=%s\n' "${2:-?}"; printf '       out=%s\n' "${3:-}"
}

# shellcheck source=/dev/null
source "$GATE"

# ── Fixture builder ───────────────────────────────────────────────────────────────
# Synthesizes a `terraform show -json`-shaped plan document. Fixtures are SYNTHESIZED,
# never captured from a real plan (cq-test-fixtures-synthesized-only) — a captured
# terraform-show-json embeds .variables verbatim including sensitive values.
#
# mk_plan <file> <json-array-of-resource_changes>
mk_plan() {
  local f="$1" changes="$2"
  printf '{"format_version":"1.2","resource_changes":%s}\n' "$changes" > "$f"
}

# rc_entry <address> <type> <actions-json>
rc_entry() {
  printf '{"address":%s,"type":%s,"change":{"actions":%s,"before":null,"after":{}}}' \
    "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)" "$3"
}

# The canonical happy plan: exactly one web-2 server create, plus its non-server
# fan-out (network attachment, volume, volume attachment) which are creates too but
# are NOT hcloud_server and so do not count as host births.
happy_changes() {
  printf '[%s,%s,%s,%s]' \
    "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["create"]')" \
    "$(rc_entry 'hcloud_server_network.web["web-2"]' 'hcloud_server_network' '["create"]')" \
    "$(rc_entry 'hcloud_volume.workspaces["web-2"]' 'hcloud_volume' '["create"]')" \
    "$(rc_entry 'hcloud_volume_attachment.workspaces["web-2"]' 'hcloud_volume_attachment' '["create"]')"
}

check() {
  local name="$1" want_rc="$2" needle="$3" plan="$4" key="$5"
  local out rc
  out="$(web_host_birth_gate "$plan" "$key" 2>&1)"; rc=$?
  if [[ "$rc" -eq "$want_rc" && "$out" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name (want rc=$want_rc containing '$needle')" "$rc" "$out"
  fi
}

printf '\n=== web-host-birth-gate ===\n\n'

# ── The one plan that must PASS ───────────────────────────────────────────────────
mk_plan "$TMP/happy.json" "$(happy_changes)"
check "the requested host's scoped birth => PASS" 0 "PASS" "$TMP/happy.json" "web-2"
check "the PASS line names the host it authorized" 0 'web-2' "$TMP/happy.json" "web-2"

# ── REJECT: zero creates ──────────────────────────────────────────────────────────
# A dispatch that asked for a birth and whose plan births nothing is either a no-op
# (the host already exists) or a mis-scoped -target set. Either way, applying it is
# not what was authorized.
mk_plan "$TMP/zero.json" "$(printf '[%s]' "$(rc_entry 'hcloud_volume.workspaces["web-2"]' 'hcloud_volume' '["create"]')")"
check "zero host creates => ABORT" 1 "no host" "$TMP/zero.json" "web-2"

# ── REJECT: two creates ───────────────────────────────────────────────────────────
# The -target set escaped its scope. Birthing two hosts on one authorization is
# exactly the unbounded-blast-radius case the HALT exists to prevent.
mk_plan "$TMP/two.json" "$(printf '[%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["create"]')" \
  "$(rc_entry 'hcloud_server.web["web-3"]' 'hcloud_server' '["create"]')")"
check "two host creates => ABORT" 1 "exactly 1" "$TMP/two.json" "web-2"

# ── REJECT: the wrong host ────────────────────────────────────────────────────────
# THE load-bearing arm. Counting creates is not enough — a plan that births exactly
# one host, but not the one the operator authorized, passes every count-based check.
# web-1 is the singleton behind app.soleur.ai; birthing it by accident is the total
# outage this whole gate exists to make impossible.
mk_plan "$TMP/wrong.json" "$(printf '[%s]' "$(rc_entry 'hcloud_server.web["web-1"]' 'hcloud_server' '["create"]')")"
check "a create of a DIFFERENT host than requested => ABORT" 1 "web-1" "$TMP/wrong.json" "web-2"
check "the wrong-host ABORT names the requested key too" 1 "web-2" "$TMP/wrong.json" "web-2"

# ── REJECT: destroys / replaces ───────────────────────────────────────────────────
# A birth is purely additive. A replace (delete+create) reads as one create to a
# naive counter while destroying a live host.
mk_plan "$TMP/replace.json" "$(printf '[%s]' "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["delete","create"]')")"
check "a REPLACE of the requested host => ABORT" 1 "destroy" "$TMP/replace.json" "web-2"

mk_plan "$TMP/destroy.json" "$(printf '[%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["create"]')" \
  "$(rc_entry 'hcloud_volume.workspaces["web-1"]' 'hcloud_volume' '["delete"]')")"
check "any destroy anywhere in the plan => ABORT" 1 "destroy" "$TMP/destroy.json" "web-2"

# ── REJECT: unparseable input (fail-closed) ───────────────────────────────────────
# "I could not check" must never read as "it is fine". This gate authorizes a
# billing host on a production network; an unreadable plan is an abort, not a pass.
printf 'not json at all\n' > "$TMP/garbage.json"
check "unparseable plan JSON => fail-closed ABORT" 1 "failed" "$TMP/garbage.json" "web-2"

check "missing plan file => fail-closed ABORT" 1 "not found" "$TMP/nonexistent.json" "web-2"

mk_plan "$TMP/nochanges.json" 'null'
check "null resource_changes => fail-closed ABORT" 1 "" "$TMP/nochanges.json" "web-2"

# ── REJECT: no host key supplied ──────────────────────────────────────────────────
out="$(web_host_birth_gate "$TMP/happy.json" "" 2>&1)"; rc=$?
if [[ "$rc" -eq 1 && "$out" == *"host key"* ]]; then
  pass "empty host key => ABORT (cannot verify identity without the request)"
else
  fail "empty host key must abort" "$rc" "$out"
fi

# ── MUTATION SECTION ──────────────────────────────────────────────────────────────
# Every reject arm above is only worth what its mutation proves. Each mutation
# neuters exactly one guard and asserts the corresponding arm goes GREEN-when-it-
# should-be-RED — i.e. the arm was actually load-bearing, not decorative.
printf '\nmutation checks (each neuters one guard; the arm it protects must flip)\n'

mutate_and_check() {
  local label="$1" sed_expr="$2" plan="$3" key="$4"
  local mutated out rc
  mutated="$TMP/mutated-gate.sh"
  sed "$sed_expr" "$GATE" > "$mutated"
  # shellcheck source=/dev/null
  out="$(bash -c "source '$mutated'; web_host_birth_gate '$plan' '$key'" 2>&1)"; rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "$label (arm is load-bearing — neutering it lets the bad plan through)"
  else
    fail "$label — the arm did NOT change behavior when neutered; it may be dead code" "$rc" "$out"
  fi
}

# Neuter the identity check -> the wrong-host plan must now (wrongly) pass.
mutate_and_check "identity guard" 's/if \[\[ "\$created_addr" != "\$want_addr" \]\]; then/if false; then/' "$TMP/wrong.json" "web-2"

# Neuter the destroy check -> the destroy plan must now (wrongly) pass.
mutate_and_check "destroy guard" 's/if \[\[ "\$destroys" -ne 0 \]\]; then/if false; then/' "$TMP/destroy.json" "web-2"

# Neuter the exactly-one check -> the two-create plan must now (wrongly) pass.
mutate_and_check "cardinality guard" 's/if \[\[ "\$creates" -ne 1 \]\]; then/if false; then/' "$TMP/two.json" "web-2"

printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
