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
# The mutation arms below source a COPY of the gate from $TMP. Since #6997 the gate
# resolves the shared preamble relative to ${BASH_SOURCE[0]}, which for that copy is $TMP —
# where plan-gate-preamble.sh does not exist. Pre-sourcing the real preamble in the same
# shell satisfies the gate's `declare -F` re-source guard, so the copy finds the functions
# already defined. Same shape as test-git-data-host-birth-gate.sh.
PREAMBLE="${ROOT}/tests/scripts/lib/plan-gate-preamble.sh"

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

# rc_noactions <address> <type>
#
# An entry with NO `.change.actions` key. Built through jq -R like its siblings rather
# than as an inline JSON literal: an inline literal has to escape the `["key"]` quotes
# through both the shell and printf, and getting that wrong yields a fixture that is
# malformed for a DIFFERENT reason than the one under test — which then "passes" the
# abort check while proving nothing about the shape guard.
rc_noactions() {
  printf '{"address":%s,"type":%s,"change":{"before":null,"after":{}}}' \
    "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)"
}

# rc_update <address> <type> <before-json> <after-json>
#
# An IN-PLACE update, the one action shape rc_entry cannot express: it hardcodes
# `before:null`, which is the create/delete edge. The reboot arm compares before
# against after on two named attributes, so it needs both sides populated.
rc_update() {
  printf '{"address":%s,"type":%s,"change":{"actions":["update"],"before":%s,"after":%s}}' \
    "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)" "$3" "$4"
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

# ── REJECT: the server WITHOUT its private NIC — the literal #6416 shape ──────────
#
# THE ARM THIS FILE WAS MISSING. Every other assertion here is a PROHIBITION ("nothing
# forbidden happens"). A birth also needs a REQUIREMENT ("the necessary things happen"),
# and the allow-set cannot express one: it says the NIC is PERMITTED to change, never that
# it MUST. So the gate passed a plan creating the server and nothing else — a host with no
# private IP and, transiently, no firewall, which is #6416 verbatim, the exact failure this
# whole path exists to make impossible.
#
# It was caught by review, not by this suite, and the reason is instructive: a suite built
# entirely from "does the gate refuse bad plans?" cases cannot discover a missing
# requirement. The question that finds it is "what is the WORST plan the gate ACCEPTS?"
mk_plan "$TMP/no-nic.json" "$(printf '[%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["create"]')")"
check "the server with NO private NIC => ABORT (#6416)" 1 "hcloud_server_network" "$TMP/no-nic.json" "web-2"

# The volume ATTACHMENT is the same class, and its absence is the data-loss shape rather
# than the no-network one: cloud-init's /mnt/data mount is fail-open (`|| true` + `nofail`),
# so a host born with no attachment writes user worktrees to the ROOT DISK, serves happily,
# and loses every one of them the first time the real volume mounts over that path.
mk_plan "$TMP/no-attach.json" "$(printf '[%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["create"]')" \
  "$(rc_entry 'hcloud_server_network.web["web-2"]' 'hcloud_server_network' '["create"]')")"
check "the server with NO volume attachment => ABORT" 1 "hcloud_volume_attachment" "$TMP/no-attach.json" "web-2"

# Both required members present but the NIC is an UPDATE rather than a CREATE. A new server
# gets a new NIC by construction, so an update here means the plan is not the birth it
# claims to be — and a count-of-entries check would have accepted it.
mk_plan "$TMP/nic-not-create.json" "$(printf '[%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["create"]')" \
  "$(rc_update 'hcloud_server_network.web["web-2"]' 'hcloud_server_network' '{"ip":"10.0.1.11"}' '{"ip":"10.0.1.12"}')" \
  "$(rc_entry 'hcloud_volume_attachment.workspaces["web-2"]' 'hcloud_volume_attachment' '["create"]')")"
check "a NIC that updates instead of creating => ABORT" 1 "hcloud_server_network" "$TMP/nic-not-create.json" "web-2"

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

# ── REJECT: a reboot-forcing in-place update on ANY host ──────────────────────────
# This arm exists because the birth `-target` set is NOT closed over the fleet.
# `hcloud_firewall_attachment.web` is a SINGLETON whose `server_ids` is
# `[for h in hcloud_server.web : h.id]`, so it must ride the birth (else the new host
# boots with no firewall — half of the #6416 failure mode). Targeting it drags every
# `hcloud_server.web` instance into the plan, web-1 included. A `placement_group_id`
# or `server_type` delta on web-1 then power-cycles the SOLE live origin behind
# app.soleur.ai, and it is layered behind the out-of-scope arm, which also catches it — this arm owns the MESSAGE, not the refusal: zero destroys, and the
# host-create count is still exactly 1.
mk_plan "$TMP/reboot.json" "$(printf '[%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["create"]')" \
  "$(rc_update 'hcloud_server.web["web-1"]' 'hcloud_server' \
      '{"placement_group_id":1,"server_type":"cx33"}' \
      '{"placement_group_id":2,"server_type":"cx33"}')")"
check "a reboot-forcing update on a LIVE host => ABORT" 1 "reboot" "$TMP/reboot.json" "web-2"

# The reboot arm is scoped to the two attributes that power-cycle, NOT to "any
# update" — otherwise it would be a blanket update ban wearing a specific name. A
# non-reboot delta on a live host is still rejected here, but by the ALLOW-SET, and
# the distinction is the whole point: the message an operator reads must name the
# real objection. Asserting the reboot arm stays silent is what pins its scope; a
# blanket-ban implementation passes the abort check above and fails this one.
mk_plan "$TMP/benign-update.json" "$(printf '[%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["create"]')" \
  "$(rc_update 'hcloud_server.web["web-1"]' 'hcloud_server' \
      '{"placement_group_id":1,"server_type":"cx33","name":"old"}' \
      '{"placement_group_id":1,"server_type":"cx33","name":"new"}')")"
check "a NON-reboot update on a live host => ABORT as out-of-scope" 1 "out-of-scope" "$TMP/benign-update.json" "web-2"
out="$(web_host_birth_gate "$TMP/benign-update.json" "web-2" 2>&1)"
if [[ "$out" != *"reboot-forcing"* ]]; then
  pass "the reboot arm stays silent on a non-reboot delta (scoped to the 2 power-cycling attributes)"
else
  fail "the reboot arm fired on a name-only change — it is a blanket update ban, not a reboot check" "n/a" "$out"
fi

# ── REJECT: any change outside the birth allow-set ────────────────────────────────
# The plan's `nested_deletes` requirement is met here rather than by re-implementing
# the five Cloudflare nested-block counters: no cloudflare_* address is in the birth
# allow-set at all, so a nested rule-array shrinkage cannot reach this path without
# first tripping this arm. Refusing the whole resource is strictly stronger than
# counting its blocks, and it does not drift when the provider schema changes.
mk_plan "$TMP/out-of-scope.json" "$(printf '[%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["create"]')" \
  "$(rc_entry 'hcloud_server_network.web["web-2"]' 'hcloud_server_network' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.workspaces["web-2"]' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_update 'cloudflare_ruleset.seo_page_redirects' 'cloudflare_ruleset' \
      '{"rules":[{"a":1},{"b":2}]}' '{"rules":[{"a":1}]}')")"
check "a cloudflare_ruleset change riding the birth => ABORT" 1 "out-of-scope" "$TMP/out-of-scope.json" "web-2"
check "the out-of-scope ABORT names the offending address" 1 "seo_page_redirects" "$TMP/out-of-scope.json" "web-2"

# ANOTHER host's fan-out is out of scope too — one authorization births one host, and
# its sibling's volume/NIC must not ride along on the same apply.
mk_plan "$TMP/sibling-fanout.json" "$(printf '[%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["create"]')" \
  "$(rc_entry 'hcloud_volume.workspaces["web-3"]' 'hcloud_volume' '["create"]')")"
check "a DIFFERENT host's volume riding the birth => ABORT" 1 "out-of-scope" "$TMP/sibling-fanout.json" "web-2"

# The full in-scope fan-out — all ten addresses — must PASS. Without this control the
# allow-set could be too narrow and the gate would refuse every real birth plan, which
# is an outage dressed as a safety feature.
mk_plan "$TMP/full-fanout.json" "$(printf '[%s,%s,%s,%s,%s,%s,%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["create"]')" \
  "$(rc_entry 'hcloud_server_network.web["web-2"]' 'hcloud_server_network' '["create"]')" \
  "$(rc_entry 'hcloud_volume.workspaces["web-2"]' 'hcloud_volume' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.workspaces["web-2"]' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_update 'hcloud_firewall_attachment.web' 'hcloud_firewall_attachment' '{"server_ids":[1]}' '{"server_ids":[1,2]}')" \
  "$(rc_entry 'betteruptime_heartbeat.web_zot_consumer["web-2"]' 'betteruptime_heartbeat' '["create"]')" \
  "$(rc_entry 'betteruptime_heartbeat.web_nic_guard["web-2"]' 'betteruptime_heartbeat' '["create"]')" \
  "$(rc_entry 'doppler_secret.web_zot_consumer_url["web-2"]' 'doppler_secret' '["create"]')" \
  "$(rc_entry 'doppler_secret.web_nic_guard_url["web-2"]' 'doppler_secret' '["create"]')" \
  "$(rc_update 'cloudflare_record.app' 'cloudflare_record' '{"content":"1.2.3.4"}' '{"content":"5.6.7.8"}')")"
check "the FULL ten-address birth fan-out => PASS" 0 "PASS" "$TMP/full-fanout.json" "web-2"

# A `no-op` refresh entry is not a change and must not trip the out-of-scope arm —
# terraform emits these routinely for transitively-pulled resources.
mk_plan "$TMP/noop.json" "$(printf '[%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["create"]')" \
  "$(rc_entry 'hcloud_server_network.web["web-2"]' 'hcloud_server_network' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.workspaces["web-2"]' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_entry 'cloudflare_record.app' 'cloudflare_record' '["no-op"]')")"
check "a no-op refresh of an out-of-scope resource => PASS" 0 "PASS" "$TMP/noop.json" "web-2"

# The apex A record is IN scope: on a web-1 birth it must update to the new address, or
# app.soleur.ai keeps resolving to the dead host. On a web-2 birth it plans as a no-op.
# Both shapes must PASS — a gate that refused the update would block the only birth that
# actually needs it.
mk_plan "$TMP/dns-update.json" "$(printf '[%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["create"]')" \
  "$(rc_entry 'hcloud_server_network.web["web-2"]' 'hcloud_server_network' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.workspaces["web-2"]' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_update 'cloudflare_record.app' 'cloudflare_record' '{"content":"1.2.3.4"}' '{"content":"5.6.7.8"}')")"
check "the apex A record updating alongside the birth => PASS" 0 "PASS" "$TMP/dns-update.json" "web-2"

# ── REJECT: unparseable input (fail-closed) ───────────────────────────────────────
# "I could not check" must never read as "it is fine". This gate authorizes a
# billing host on a production network; an unreadable plan is an abort, not a pass.
printf 'not json at all\n' > "$TMP/garbage.json"
check "unparseable plan JSON => fail-closed ABORT" 1 "failed" "$TMP/garbage.json" "web-2"

check "missing plan file => fail-closed ABORT" 1 "not found" "$TMP/nonexistent.json" "web-2"

mk_plan "$TMP/nochanges.json" 'null'
check "null resource_changes => fail-closed ABORT" 1 "" "$TMP/nochanges.json" "web-2"

# An entry with NO `.change.actions` at all. jq's `null | index("delete")` returns null
# rather than erroring, so such an entry is silently DROPPED by the destroy/out-of-scope
# selects — a resource that vanishes from the work-list instead of failing closed.
#
# This aborts today only by ACCIDENT: `.change.actions | any(...)` happens to error on
# null, so the out_of_scope counter comes back empty and trips the numeric check. That is
# one jq expression away from silently passing, and the failure it would then hide is a
# destroy the gate could not see. Assert the shape explicitly, and assert the MESSAGE
# names it — a generic "counter parse failed" tells the operator nothing about which
# entry is unclassifiable. Mirrors stock-preflight-gate.sh's identical guard.
mk_plan "$TMP/noactions.json" "$(printf '[%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["create"]')" \
  "$(rc_noactions 'hcloud_volume.workspaces["web-2"]' 'hcloud_volume')")"
check "an entry with no .change.actions => fail-closed ABORT" 1 "unclassifiable" "$TMP/noactions.json" "web-2"
check "the unclassifiable ABORT names the offending address" 1 'hcloud_volume.workspaces["web-2"]' "$TMP/noactions.json" "web-2"

# ── REJECT: no host key supplied ──────────────────────────────────────────────────
out="$(web_host_birth_gate "$TMP/happy.json" "" 2>&1)"; rc=$?
if [[ "$rc" -eq 1 && "$out" == *"host key"* ]]; then
  pass "empty host key => ABORT (cannot verify identity without the request)"
else
  fail "empty host key must abort" "$rc" "$out"
fi

# ── MUTATION SECTION ──────────────────────────────────────────────────────────────
# Every reject arm above is only worth what its mutation proves.
#
# THE ARMS ARE NOT INDEPENDENT, and pretending otherwise is how a mutation battery
# lies. The out-of-scope allow-set is keyed on the requested host, so it already
# refuses a create of the WRONG host, a SECOND host, and any update to a live one —
# it strictly subsumes the identity, cardinality and reboot arms. The naive contract
# "neuter arm X and the bad plan sails through" is therefore FALSE for those three by
# construction: a second arm catches the plan, rc stays 1, and a battery written that
# way reports them dead when they are merely layered.
#
# So there are two contracts here, and each arm is filed under the one that is true
# of it:
#
#   SOLE-GUARD  neuter it and the plan is ACCEPTED (rc 0). Only provable for an arm
#               that is genuinely the last line for its fixture.
#   LAYERED     neuter it and the plan is still REJECTED (rc 1), but its own
#               signature disappears from the output and a DIFFERENT arm's appears.
#               That proves two things at once: this arm is what actually caught the
#               plan, and removing it does not open the door.
#
# Both contracts fail loudly if the arm is absent, because both first require the
# mutation to change the file at all (the non-vacuity floor in mutate_and_check).
printf '\nmutation checks (each neuters one guard; the arm it protects must flip)\n'

mutate_and_check() {
  local label="$1" sed_expr="$2" plan="$3" key="$4"
  local mutated out rc
  mutated="$TMP/mutated-gate.sh"
  sed "$sed_expr" "$GATE" > "$mutated"
  # NON-VACUITY FLOOR — the reason this helper is trustworthy at all.
  #
  # `sed` exits 0 when its expression matches NOTHING, so a mutation aimed at a guard
  # that does not exist emits a byte-identical copy of the gate. The bad plan then
  # sails through the un-neutered gate, rc is 0, and this helper reports the arm as
  # "load-bearing" — the strongest possible green for the weakest possible reason.
  # That is not hypothetical: every mutation below returned that exact false green
  # while the two arms they name were still unimplemented. Requiring the file to
  # actually differ is what separates "I removed the guard and the plan got through"
  # from "there was never a guard to remove".
  if cmp -s "$mutated" "$GATE"; then
    fail "$label — the mutation matched NOTHING in the gate (byte-identical copy). Either the guard is missing or the sed expression drifted from the source; this check would have reported a vacuous pass." "n/a" "no textual change"
    return
  fi
  # shellcheck source=/dev/null
  out="$(bash -c "source '$PREAMBLE'; source '$mutated'; web_host_birth_gate '$plan' '$key'" 2>&1)"; rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "$label (arm is load-bearing — neutering it lets the bad plan through)"
  else
    fail "$label — the arm did NOT change behavior when neutered; it may be dead code" "$rc" "$out"
  fi
}

# mutate_layered <label> <sed-expr> <plan> <key> <own-signature> <fallback-signature>
#
# The LAYERED contract. Asserts, after neutering: the file changed (non-vacuity), the
# plan is still rejected, this arm's signature is GONE, and the fallback arm's is
# present. Dropping any one of those four turns this into a check that cannot fail.
mutate_layered() {
  local label="$1" sed_expr="$2" plan="$3" key="$4" own="$5" fallback="$6"
  local mutated base out rc
  mutated="$TMP/mutated-layered.sh"
  sed "$sed_expr" "$GATE" > "$mutated"
  if cmp -s "$mutated" "$GATE"; then
    fail "$label — the mutation matched NOTHING in the gate (byte-identical copy); the guard is missing or the sed expression drifted." "n/a" "no textual change"
    return
  fi
  # Control: the UNMUTATED gate must reject this plan via THIS arm. Without it, an
  # arm that never fired for this fixture would still satisfy "signature absent".
  base="$(web_host_birth_gate "$plan" "$key" 2>&1)"
  if [[ "$base" != *"$own"* ]]; then
    fail "$label — the unmutated gate did not reject this plan via the '$own' arm; the fixture does not exercise it." "n/a" "$base"
    return
  fi
  out="$(bash -c "source '$PREAMBLE'; source '$mutated'; web_host_birth_gate '$plan' '$key'" 2>&1)"; rc=$?
  if [[ "$rc" -eq 1 && "$out" != *"$own"* && "$out" == *"$fallback"* ]]; then
    pass "$label (layered — owns the rejection; neutering it hands off to '$fallback', never to PASS)"
  else
    fail "$label — layered contract broken (want rc=1, '$own' absent, '$fallback' present)" "$rc" "$out"
  fi
}

# SOLE-GUARD: an IN-SCOPE destroy. Every address here is in web-2's fan-out, so the
# out-of-scope arm counts zero and the destroy arm is genuinely the last line.
# Neutering it therefore ACCEPTS a plan that deletes web-2's own data volume.
mk_plan "$TMP/inscope-destroy.json" "$(printf '[%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["create"]')" \
  "$(rc_entry 'hcloud_server_network.web["web-2"]' 'hcloud_server_network' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.workspaces["web-2"]' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_entry 'hcloud_volume.workspaces["web-2"]' 'hcloud_volume' '["delete"]')")"
check "an IN-SCOPE destroy (the host's own volume) => ABORT" 1 "destroy" "$TMP/inscope-destroy.json" "web-2"
mutate_and_check "destroy guard" 's/if \[\[ "\$destroys" -ne 0 \]\]; then/if false; then/' "$TMP/inscope-destroy.json" "web-2"

# SOLE-GUARD: the cloudflare ruleset is out of scope and nothing else objects to it.
mutate_and_check "out-of-scope guard" 's/if \[\[ "\$out_of_scope" -ne 0 \]\]; then/if false; then/' "$TMP/out-of-scope.json" "web-2"

# SOLE-GUARD: the actions-shape check.
#
# Worth recording how this arm was classified, because the first reading was wrong. Before
# the guard existed, a no-actions plan DID abort — so it looked layered, with the numeric
# counter-validation as the backstop. Measuring the mutation says otherwise: neuter this
# arm and the plan PASSES. The pre-guard abort came from the `offenders` extraction and
# the ordering around it, not from a second arm that would still catch it.
#
# That is the whole reason the mutation is measured rather than reasoned about. "Something
# else would catch it" is the most comfortable thing to believe about a guard you are
# about to weaken, and here it was false.
#
# Anchored on the ABORT line's own literal rather than the multi-line `jq -e` condition:
# that condition spans two lines and is dense with regex metacharacters, so a sed aimed at
# it is brittle in a way the non-vacuity floor would (correctly) report as a missing guard.
# SOLE-GUARD: the requirement arm. No prohibition arm can catch a MISSING member — that
# is the whole point of adding it — so neutering it must let the #6416 plan through, and
# does. This is the one mutation in the battery whose fixture is a plan that is dangerous
# by OMISSION rather than by commission.
mutate_and_check "required-creates guard" 's/if \[\[ "\$required_creates" -ne 1 \]\]; then/if false; then/' \
  "$TMP/no-nic.json" "web-2"

# THE CLASSIFIABILITY ARM MOVED TO THE SHARED PREAMBLE (#6997), so this is no longer a
# SOLE-GUARD mutation of this gate's own source — the guard is not in this file any more.
# It is now proved from the preamble's side, in test-plan-gate-preamble.sh, which owns both
# the assertion and its four non-vacuity probes.
#
# What is asserted HERE is the property that file cannot see: that this gate INVOKES the
# preamble rather than merely sourcing it. Neutering the call must leave the plan rejected
# (the numeric assert below still catches a no-actions plan) while the PREAMBLE-DISTINCTIVE
# signature disappears.
#
# THE ANCHOR IS NOT THE GATE NAME. Every abort this gate emits — including its own — is
# prefixed "web_host_birth_gate:", so a gate-name anchor cannot tell a preamble abort from a
# gate abort, and an arm built on it would be a redness detector rather than a binding.
mutate_layered "classifiability call (invoked, not merely sourced)" \
  's/^  plan_gate_assert_classifiable .*/  :/' \
  "$TMP/noactions.json" "web-2" \
  "unclassifiable plan entry" "counter parse failed"

# LAYERED: a create of web-1 is both an identity mismatch and out of scope. The
# identity arm runs first and owns the message; the allow-set is the backstop.
mutate_layered "identity guard" 's/if \[\[ "\$created_addr" != "\$want_addr" \]\]; then/if false; then/' \
  "$TMP/wrong.json" "web-2" "IDENTITY MISMATCH" "out-of-scope"

# LAYERED: a second host create is both a cardinality breach and out of scope.
mutate_layered "cardinality guard" 's/if \[\[ "\$creates" -ne 1 \]\]; then/if false; then/' \
  "$TMP/two.json" "web-2" "expected exactly 1" "out-of-scope"

# LAYERED: a web-1 power-cycle is both a reboot and an out-of-scope change today.
# The reboot arm earns its place by naming the consequence — and by surviving a
# future widening of the allow-set, which would silence the backstop but not it.
mutate_layered "reboot guard" 's/if \[\[ "\$reboot_updates" -ne 0 \]\]; then/if false; then/' \
  "$TMP/reboot.json" "web-2" "reboot-forcing" "out-of-scope"

printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
