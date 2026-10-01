#!/usr/bin/env bash
# Test suite for tests/scripts/lib/web-host-replace-gate.sh (#6969).
#
# THE SIBLING OF web-host-birth-gate.sh, AND ITS OPPOSITE BY CONTRACT. The birth gate
# requires exactly one host CREATE and permits NO destroys; this one requires exactly one
# host REPLACE (delete+create) of the requested key. Its header carries the warning that
# produced this file:
#
#   "Scoped host REPLACEMENT is a different operation with a different gate; it does not
#    borrow this one."
#
# So neither may ever be graded against the other's allow-set: a replace run through the
# birth gate aborts on the destroy arm (correct but useless), and a birth run through this
# gate aborts on the replace-cardinality arm.
#
# WHAT ACTUALLY PROTECTS PRODUCTION IS THE REJECT SET. `hcloud_server.web["web-1"]` is the
# singleton behind the app.soleur.ai A record with no failover partner and no load
# balancer, so the interesting question is never "does the happy plan pass?" but "what is
# the WORST plan this gate ACCEPTS?". Every arm below is a refusal and every refusal is
# mutation-proven in the battery at the end.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
GATE="${ROOT}/tests/scripts/lib/web-host-replace-gate.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

passes=0
fails=0
# INDEPENDENT CASE COUNTER (ADR-193 #2): incremented AT THE CALL SITE (check / mutate_*),
# never inside pass()/fail(), so a neutered fail() cannot drop a row and its count together.
cases=0
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
# terraform-show-json embeds .variables verbatim, including values declared sensitive.
#
# mk_plan <file> <json-array-of-resource_changes>
mk_plan() {
  local f="$1" changes="$2"
  printf '{"format_version":"1.2","resource_changes":%s}\n' "$changes" > "$f"
}

# rc_entry <address> <type> <actions-json>
rc_entry() {
  printf '{"address":%s,"type":%s,"change":{"actions":%s,"before":{},"after":{}}}' \
    "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)" "$3"
}

# rc_noactions <address> <type>
#
# An entry with NO `.change.actions` key. Built through jq -R like its siblings rather than
# as an inline JSON literal: an inline literal has to escape the `["key"]` quotes through
# both the shell and printf, and getting that wrong yields a fixture malformed for a
# DIFFERENT reason than the one under test — which then "passes" the abort check while
# proving nothing about the shape guard.
rc_noactions() {
  printf '{"address":%s,"type":%s,"change":{"before":{},"after":{}}}' \
    "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)"
}

# rc_change <address> <type> <raw-json-.change>
#
# For malformed-`.change` fixtures: `.change` is emitted VERBATIM, so it can be a scalar, an
# array, a bare number — any shape the shape guard must refuse. Address and type still go
# through jq -R, so only the field under test is hand-written. Hand-escaping the whole entry
# through a printf format is how a fixture ends up malformed for a DIFFERENT reason than the
# one under test, which then "passes" the abort check while proving nothing.
rc_change() {
  printf '{"address":%s,"type":%s,"change":%s}' \
    "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)" "$3"
}

# rc_update <address> <type> <before-json> <after-json>
#
# An IN-PLACE update with both sides populated — the shape the reboot arm compares on two
# named attributes.
rc_update() {
  printf '{"address":%s,"type":%s,"change":{"actions":["update"],"before":%s,"after":%s}}' \
    "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)" "$3" "$4"
}

# The canonical happy plan for a scoped replace of <key>: the server replaced (delete+create)
# plus the three members whose recreation/update the replace ENTAILS.
#
# The NIC and the volume attachment both reference `hcloud_server.web[key].id`, which is
# ForceNew — a new server implies a new instance of each, by construction. The firewall
# attachment's `server_ids` is a plain updatable list over the whole for_each map, so it
# UPDATES rather than replaces.
#
# NOTE what is deliberately ABSENT: hcloud_volume.workspaces[key]. It is preserved by
# OMISSION from the -target set — an untargeted resource cannot be planned for destroy —
# so it appears in a real plan only as a no-op dependency, which the positive-action filter
# skips. Its named backstop below is redundant on purpose.
happy_changes() {
  local k="${1:-web-2}"
  printf '[%s,%s,%s,%s]' \
    "$(rc_entry "hcloud_server.web[\"${k}\"]" 'hcloud_server' '["delete","create"]')" \
    "$(rc_entry "hcloud_server_network.web[\"${k}\"]" 'hcloud_server_network' '["delete","create"]')" \
    "$(rc_entry "hcloud_volume_attachment.workspaces[\"${k}\"]" 'hcloud_volume_attachment' '["delete","create"]')" \
    "$(rc_entry 'hcloud_firewall_attachment.web' 'hcloud_firewall_attachment' '["update"]')"
}

check() {
  local name="$1" want_rc="$2" needle="$3" plan="$4" key="$5"
  local out rc
  cases=$((cases + 1))
  out="$(web_host_replace_gate "$plan" "$key" 2>&1)"; rc=$?
  # Bash pattern match, NOT a `printf ... | grep -q` pipe: under `pipefail` an early grep
  # match SIGPIPEs the producer (141) and the pipeline reports failure even though it
  # matched — a false negative that flakes only when the match lands early.
  if [[ "$rc" -eq "$want_rc" && "$out" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name (want rc=$want_rc containing '$needle')" "$rc" "$out"
  fi
}

printf '\n=== web-host-replace-gate ===\n\n'

# ── The one plan that must PASS ───────────────────────────────────────────────────
mk_plan "$TMP/happy.json" "$(happy_changes web-2)"
check "the requested host's scoped replace => PASS" 0 "PASS" "$TMP/happy.json" "web-2"
# ANCHORED ON THE PASS LINE'S OWN PHRASING, not the bare key: the status line printed on every
# invocation already contains `requested=web-2` and `replaced_addr=hcloud_server.web["web-2"]`,
# so a 'web-2' needle here would be satisfied by a run in which the PASS line said nothing
# about which host it authorized. Same defect as the passphrase anchor below, found by the
# same audit (cq-assert-anchor-not-bare-token).
check "the PASS line names the host it authorized" 0 'replace of hcloud_server.web["web-2"] permitted' "$TMP/happy.json" "web-2"

# A key that is neither web-1 nor web-2 must work identically — the gate is generic over
# var.web_hosts keys, not hardcoded to the host that motivated it (#6969 was web-2).
mk_plan "$TMP/happy-web3.json" "$(happy_changes web-3)"
check "the gate is generic over var.web_hosts keys => PASS for web-3" 0 "PASS" "$TMP/happy-web3.json" "web-3"

# ── REJECT: web-1, the LUKS-pinned host ───────────────────────────────────────────
#
# MEASURED TOPOLOGY, and it is the reason this arm exists rather than a key-conditional
# widening of the allow-set. web-1 is NOT "web-2 with a bigger blast radius":
#
#   1. hcloud_volume_attachment.workspaces_luks.server_id is hardcoded to
#      hcloud_server.web["web-1"].id (workspaces-luks.tf). server_id is ForceNew, so
#      replacing web-1 REQUIRES recreating that attachment — a member no other key has.
#      Omit it and the LUKS at-rest store boots UNATTACHED while the host reports healthy.
#   2. cloudflare_record.app.content is hcloud_server.web["web-1"].ipv4_address (dns.tf).
#      Replacing web-1 without re-pointing it leaves app.soleur.ai resolving to a destroyed
#      host — a total outage of the product.
#   3. every web-1-pinned terraform_data.* SSH provisioner pins connection.host to web-1
#      (22 measured 2026-10-02: 18 server.tf + 3 workspaces-luks.tf + 1 ci-ssh-key.tf; the old
#      "17" was server.tf-only and not a measurement); `-target` is upstream-only so none is
#      pulled into the plan, and a replaced web-1 leaves every one of them un-run against a dead IP.
#   4. DECISIVE, and not a plan property at all: /mnt/data pins BY-ID to
#      hcloud_volume.workspaces[key] — on web-1 the PLAINTEXT volume the 2026-07-23 cutover
#      SUPERSEDED — and nothing on a fresh boot opens the LUKS mapper (crypttab keyfile
#      `none` on the template path web-1 was built from; #6931's fresh-boot unlock path, ADR-263,
#      does not change web-1's by-id pin). A rebuilt web-1 boots healthy and
#      serves every worktree rolled back to 2026-07-23 while the live LUKS volume sits
#      attached and unopened.
#
#      An earlier revision of this suite asserted an "AMBIGUOUS `scsi-0HC_Volume_*` glob"
#      here, quoting a workspaces-luks.tf comment that went stale when #6604 pinned the
#      mount by-id. The needle below was re-anchored on the real hazard; the old one would
#      have kept passing against a rationale the codebase falsifies.
#
# (4) is invisible to ANY plan-shaped gate: it is a property of cloud-init, not of
# resource_changes. A gate that admitted web-1 would be certifying a safety it cannot
# observe. #6931 (fresh-boot guest-side LUKS path, ADR-263) is DONE. The remaining unblock
# conditions are key-conditional gate arms, a rehearsal and #6964 — NOT the ADR-119 mount pin,
# which already shipped. See ADR-148 §Alternatives.
mk_plan "$TMP/happy-web1.json" "$(happy_changes web-1)"
check "the LUKS-pinned host web-1 => ABORT (refused by name)" 1 "web-1" "$TMP/happy-web1.json" "web-1"
# ANCHORED ON THE DECISIVE HAZARD'S OWN WORDS. This asserted "AMBIGUOUS" until the review
# panel measured that ground false; a needle pinned to a rationale the codebase contradicts
# keeps passing while the message misleads the operator it exists for.
check "the web-1 refusal names the superseded-plaintext hazard" 1 "superseded by the 2026-07-23 LUKS cutover" "$TMP/happy-web1.json" "web-1"
check "the web-1 refusal names the real remaining unblock conditions (rehearsal, #6964) and says the arms are arms-only, not the shipped mount pin" 1 "arms-only and cannot observe any of the blockers above, so this still needs a rehearsal on a non-production host and #6964 first" "$TMP/happy-web1.json" "web-1"

# ── REJECT: no host key supplied ──────────────────────────────────────────────────
#
# A replace gate that does not check WHICH host is being replaced is a count check wearing
# a costume, and the count it performs would be satisfied by replacing web-1.
check "no host key => ABORT" 1 "no host key" "$TMP/happy.json" ""

# ── REJECT: unreadable input (fail-closed) ────────────────────────────────────────
check "a missing plan file => ABORT" 1 "not found" "$TMP/does-not-exist.json" "web-2"

printf 'this is not json at all\n' > "$TMP/garbage.json"
check "unparseable JSON => ABORT" 1 "unparseable" "$TMP/garbage.json" "web-2"

printf '{"format_version":"1.2"}\n' > "$TMP/no-changes-key.json"
check "a plan with no resource_changes array => ABORT" 1 "unparseable" "$TMP/no-changes-key.json" "web-2"

printf '{"format_version":"1.2","resource_changes":null}\n' > "$TMP/null-changes.json"
check "a NULL resource_changes => ABORT (not 'zero changes')" 1 "unparseable" "$TMP/null-changes.json" "web-2"

# An entry with no `.change.actions` array. jq's `null | index("delete")` returns null
# rather than erroring, so such an entry is silently DROPPED by every select — a resource
# that vanishes from the work-list instead of failing closed, which is precisely how a
# destroy the gate cannot see would ride along.
mk_plan "$TMP/noactions.json" "$(printf '[%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["delete","create"]')" \
  "$(rc_noactions 'hcloud_volume.workspaces["web-2"]' 'hcloud_volume')")"
check "an entry with non-array .change.actions => ABORT" 1 "unclassifiable" "$TMP/noactions.json" "web-2"

# ── REJECT: wrong replace cardinality ─────────────────────────────────────────────
#
# ZERO replaces is the "the host is not in state" case: `terraform plan -replace=<addr>` on
# an address absent from state exits 0 with no warning and plans a plain CREATE. That is a
# BIRTH, and it must go through the birth path's gate, which grades the additive contract.
# The fixture keeps the NIC/attachment/firewall members so this arm is the SOLE objection.
mk_plan "$TMP/zero-replaces.json" "$(printf '[%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["create"]')" \
  "$(rc_entry 'hcloud_server_network.web["web-2"]' 'hcloud_server_network' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.workspaces["web-2"]' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_entry 'hcloud_firewall_attachment.web' 'hcloud_firewall_attachment' '["update"]')")"
check "a plain CREATE (host absent from state) => ABORT, not a silent birth" 1 "no host replace" "$TMP/zero-replaces.json" "web-2"

mk_plan "$TMP/two-replaces.json" "$(printf '[%s,%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["delete","create"]')" \
  "$(rc_entry 'hcloud_server.web["web-3"]' 'hcloud_server' '["delete","create"]')" \
  "$(rc_entry 'hcloud_server_network.web["web-2"]' 'hcloud_server_network' '["delete","create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.workspaces["web-2"]' 'hcloud_volume_attachment' '["delete","create"]')" \
  "$(rc_entry 'hcloud_firewall_attachment.web' 'hcloud_firewall_attachment' '["update"]')")"
check "two host replaces => ABORT (one authorization replaces one host)" 1 "expected exactly 1" "$TMP/two-replaces.json" "web-2"

# ── REJECT: the wrong host ────────────────────────────────────────────────────────
#
# THE ARM THAT MAKES THIS GATE WORTH HAVING. A count-only check passes a plan that replaces
# exactly one host that is not the one requested, and a mis-scoped -target replacing web-1
# reads identical to a correct web-2 replace in every count-based arm.
mk_plan "$TMP/wrong-identity.json" "$(printf '[%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-3"]' 'hcloud_server' '["delete","create"]')" \
  "$(rc_entry 'hcloud_server_network.web["web-3"]' 'hcloud_server_network' '["delete","create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.workspaces["web-3"]' 'hcloud_volume_attachment' '["delete","create"]')" \
  "$(rc_entry 'hcloud_firewall_attachment.web' 'hcloud_firewall_attachment' '["update"]')")"
check "a replace of a host other than the requested one => ABORT" 1 "IDENTITY MISMATCH" "$TMP/wrong-identity.json" "web-2"

# ── REJECT: the named preserve backstops ──────────────────────────────────────────
#
# All three targets are OUTSIDE the allow-set, so out_of_scope already refuses them. These
# arms are INTENTIONALLY REDUNDANT: they exist for the error text an operator reads
# mid-abort. "an address you did not authorize changed" is true and tells nobody that the
# workspace store was about to be destroyed.
mk_plan "$TMP/vol-destroy.json" "$(printf '[%s,%s]' \
  "$(happy_changes web-2 | sed 's/^\[//; s/\]$//')" \
  "$(rc_entry 'hcloud_volume.workspaces["web-2"]' 'hcloud_volume' '["delete"]')")"
check "a destroy of the host's workspaces volume => ABORT (named)" 1 "workspaces volume" "$TMP/vol-destroy.json" "web-2"

mk_plan "$TMP/luks-vol-destroy.json" "$(printf '[%s,%s]' \
  "$(happy_changes web-2 | sed 's/^\[//; s/\]$//')" \
  "$(rc_entry 'hcloud_volume.workspaces_luks' 'hcloud_volume' '["delete"]')")"
check "a destroy of the LUKS at-rest volume => ABORT (named)" 1 "LUKS" "$TMP/luks-vol-destroy.json" "web-2"

# A rotated passphrase luksFormat/luksOpens a NEW header on the fresh boot, STRANDING the
# existing at-rest data behind it while the host boots and reports healthy. Both the
# random_password and the doppler_secret that carries it must show zero positive actions.
#
# ANCHORED ON THE ARM'S OWN PROSE, never the bare word "passphrase": the gate's status line
# prints `luks_passphrase_touched=N` on EVERY invocation, so a "passphrase" needle is
# satisfied by a run in which this arm never fired. The mutation battery caught exactly
# that — the layered case reported the arm as un-owned because the status line kept the
# needle alive after the arm was neutered (cq-assert-anchor-not-bare-token).
PASSPHRASE_ARM='opens a NEW header'
mk_plan "$TMP/passphrase-rotate.json" "$(printf '[%s,%s]' \
  "$(happy_changes web-2 | sed 's/^\[//; s/\]$//')" \
  "$(rc_entry 'random_password.workspaces_luks' 'random_password' '["delete","create"]')")"
check "a LUKS passphrase rotation => ABORT (named)" 1 "$PASSPHRASE_ARM" "$TMP/passphrase-rotate.json" "web-2"

mk_plan "$TMP/passphrase-secret.json" "$(printf '[%s,%s]' \
  "$(happy_changes web-2 | sed 's/^\[//; s/\]$//')" \
  "$(rc_entry 'doppler_secret.workspaces_luks_key' 'doppler_secret' '["update"]')")"
check "an update to the LUKS passphrase SECRET => ABORT (named)" 1 "$PASSPHRASE_ARM" "$TMP/passphrase-secret.json" "web-2"

# ── REJECT: a reboot-forcing update on another live host ──────────────────────────
#
# Reachable BECAUSE hcloud_firewall_attachment.web is a fleet singleton over
# `[for h in hcloud_server.web : h.id]` — it MUST ride the replace (else the fresh host
# boots naked on its public IPv4), but targeting it drags every web host into the plan,
# web-1 included. A server_type delta on web-1 then power-cycles the sole live origin
# behind app.soleur.ai, with a replace count of exactly 1 and correct identity.
mk_plan "$TMP/reboot.json" "$(printf '[%s,%s]' \
  "$(happy_changes web-2 | sed 's/^\[//; s/\]$//')" \
  "$(rc_update 'hcloud_server.web["web-1"]' 'hcloud_server' '{"server_type":"cx33","placement_group_id":1}' '{"server_type":"cpx42","placement_group_id":1}')")"
check "a reboot-forcing update on another live host => ABORT" 1 "reboot-forcing" "$TMP/reboot.json" "web-2"

# ── REJECT: anything outside the four-member allow-set ────────────────────────────
mk_plan "$TMP/out-of-scope.json" "$(printf '[%s,%s]' \
  "$(happy_changes web-2 | sed 's/^\[//; s/\]$//')" \
  "$(rc_entry 'cloudflare_ruleset.waf_custom' 'cloudflare_ruleset' '["update"]')")"
check "a Cloudflare ruleset riding along => ABORT (out of scope)" 1 "out-of-scope" "$TMP/out-of-scope.json" "web-2"

# The apex A record is NOT in the allow-set. On a non-web-1 replace it is a genuine no-op
# (its content is web-1's address), so any POSITIVE action on it means the plan is
# re-pointing production DNS as a side effect of replacing a standby.
mk_plan "$TMP/cf-record.json" "$(printf '[%s,%s]' \
  "$(happy_changes web-2 | sed 's/^\[//; s/\]$//')" \
  "$(rc_entry 'cloudflare_record.app' 'cloudflare_record' '["update"]')")"
check "a change to the apex A record on a standby replace => ABORT" 1 "out-of-scope" "$TMP/cf-record.json" "web-2"

# EXACT-EQUALITY membership, not substring. `contains`/`inside` would let the bare
# for_each map address satisfy the keyed member and wave the entire fleet through.
mk_plan "$TMP/bare-map.json" "$(printf '[%s,%s]' \
  "$(happy_changes web-2 | sed 's/^\[//; s/\]$//')" \
  "$(rc_entry 'hcloud_server.web' 'hcloud_server' '["update"]')")"
check "the bare for_each map address does NOT satisfy the keyed member" 1 "out-of-scope" "$TMP/bare-map.json" "web-2"

# A no-op / read entry outside the allow-set must NOT abort — the volume rides in as a
# no-op dependency of the targeted attachment on every real plan, and a gate that refused
# it would refuse every correct replace. That is an outage dressed as a safety feature.
mk_plan "$TMP/noop-dep.json" "$(printf '[%s,%s,%s]' \
  "$(happy_changes web-2 | sed 's/^\[//; s/\]$//')" \
  "$(rc_entry 'hcloud_volume.workspaces["web-2"]' 'hcloud_volume' '["no-op"]')" \
  "$(rc_entry 'data.hcloud_image.snapshot' 'hcloud_image' '["read"]')")"
check "no-op and read entries outside the allow-set do NOT false-abort" 0 "PASS" "$TMP/noop-dep.json" "web-2"

# ── REJECT: the DETECTION-layer vacuities (added at review; all were PASSing) ──────
#
# Every one of these was a plan the gate ACCEPTED, and none was caught by the original
# 12-mutation battery — because that battery mutated only the bash `if [[ ]]` arms and never
# touched the ~90-line jq block that computes the counters. The decision logic was covered;
# the DETECTION logic was not. Each fixture below is the input that proved an arm blind.

# A SCALAR .change. jq raises on `.change.actions` and exits 5; `if jq -e ...; then` read that
# error as "no offenders", and the counting filter's `.change.actions?` dropped the same entry
# from every select. MEASURED PASSing before the shape guard became a positive assertion.
mk_plan "$TMP/scalar-change.json" "$(printf '[%s,%s]' \
  "$(happy_changes web-2 | sed 's/^\[//; s/\]$//')" \
  "$(rc_change 'hcloud_volume.workspaces["web-2"]' 'hcloud_volume' '"delete"')")"
check "a SCALAR .change (destroys the workspaces volume) => ABORT" 1 "unclassifiable" "$TMP/scalar-change.json" "web-2"

# The same shape at every other JSON type, because one malformed fixture only ever proved one.
for _shape in '0' 'true' '["delete"]' '"x"'; do
  mk_plan "$TMP/badchange.json" "$(printf '[%s,%s]' \
    "$(happy_changes web-2 | sed 's/^\[//; s/\]$//')" \
    "$(rc_change 'hcloud_volume.workspaces_luks' 'hcloud_volume' "$_shape")")"
  check "a .change of type ${_shape} => ABORT (fail-closed)" 1 "unclassifiable" "$TMP/badchange.json" "web-2"
done

# NESTED actions: `[["delete"]]` passes a bare `type=="array"` check, then compares an array to
# a string in every `any(. == "delete")` — false forever.
mk_plan "$TMP/nested-actions.json" "$(printf '[%s,%s]' \
  "$(happy_changes web-2 | sed 's/^\[//; s/\]$//')" \
  "$(rc_change 'hcloud_volume.workspaces_luks' 'hcloud_volume' '{"actions":[["delete"]]}')")"
check "a NESTED .change.actions ([[\"delete\"]]) => ABORT" 1 "unclassifiable" "$TMP/nested-actions.json" "web-2"

# An UNKNOWN verb. The filter was an allow-list of create/update/delete/forget, so anything
# terraform grows next was classified INERT — the fail-open direction, and the comment claimed
# the opposite. Now a deny-list of the two known-inert verbs.
mk_plan "$TMP/unknown-verb.json" "$(printf '[%s,%s]' \
  "$(happy_changes web-2 | sed 's/^\[//; s/\]$//')" \
  "$(rc_entry 'hcloud_volume.workspaces_luks' 'hcloud_volume' '["destroy"]')")"
check "an UNKNOWN action verb is NOT treated as inert => ABORT" 1 "out-of-scope" "$TMP/unknown-verb.json" "web-2"

# `forget` had ZERO instances anywhere in the suite, yet appears in four gate predicates.
# A forgotten volume is state divergence the next apply resolves destructively.
mk_plan "$TMP/forget.json" "$(printf '[%s,%s]' \
  "$(happy_changes web-2 | sed 's/^\[//; s/\]$//')" \
  "$(rc_entry 'hcloud_volume.workspaces["web-2"]' 'hcloud_volume' '["forget"]')")"
check "a FORGET on the workspaces volume => ABORT (named)" 1 "workspaces volume" "$TMP/forget.json" "web-2"

# out_of_scope discriminating a DELETE. Every out-of-scope fixture used ["update"], and the two
# ["delete"] fixtures targeted addresses with named backstops that fire first — so no assertion
# anywhere exercised the `delete` verb in this filter. This address has NO named backstop.
mk_plan "$TMP/oos-delete.json" "$(printf '[%s,%s]' \
  "$(happy_changes web-2 | sed 's/^\[//; s/\]$//')" \
  "$(rc_entry 'hcloud_volume_attachment.workspaces_luks' 'hcloud_volume_attachment' '["delete"]')")"
check "a DELETE of the LUKS attachment (no named backstop) => ABORT" 1 "out-of-scope" "$TMP/oos-delete.json" "web-2"

# The firewall requirement arm's DISCRIMINATION. hcloud_firewall_attachment.web is INSIDE the
# allow-set, so out_of_scope structurally cannot see it: the exact-equality predicate is the
# only thing between "the fleet firewall attachment is destroyed" and a PASS.
mk_plan "$TMP/fw-delete.json" "$(printf '[%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["delete","create"]')" \
  "$(rc_entry 'hcloud_server_network.web["web-2"]' 'hcloud_server_network' '["delete","create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.workspaces["web-2"]' 'hcloud_volume_attachment' '["delete","create"]')" \
  "$(rc_entry 'hcloud_firewall_attachment.web' 'hcloud_firewall_attachment' '["delete"]')")"
check "the fleet firewall attachment DESTROYED => ABORT (not 'requirement met')" 1 "hcloud_firewall_attachment" "$TMP/fw-delete.json" "web-2"

# A sibling host's NIC must not ride along. NOTE WHAT THIS DOES AND DOES NOT PROVE, because the
# first version of this comment overclaimed: it does NOT independently prove the nic arm is
# KEY-scoped. Measured — type-scoping the arm (dropping the ["<key>"] from its address match)
# leaves the whole suite green, because any sibling address is out-of-scope BY CONSTRUCTION, so
# out_of_scope owns the rejection either way. The key-scoping is LAYERED behind out_of_scope and
# cannot be discriminated by any plan fixture; the parity test is what pins the arm's address
# shape. This case is still a real regression guard for the layered behaviour — it is just not
# the sole-guard proof the label claimed.
mk_plan "$TMP/sibling-nic.json" "$(printf '[%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["delete","create"]')" \
  "$(rc_entry 'hcloud_server_network.web["web-3"]' 'hcloud_server_network' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.workspaces["web-2"]' 'hcloud_volume_attachment' '["delete","create"]')" \
  "$(rc_entry 'hcloud_firewall_attachment.web' 'hcloud_firewall_attachment' '["update"]')")"
check "a SIBLING host's NIC in the plan => ABORT (out_of_scope owns this; see note)" 1 "out-of-scope" "$TMP/sibling-nic.json" "web-2"

# ── REJECT: the requirement arms (dangerous by OMISSION) ──────────────────────────
#
# Every arm above is a PROHIBITION — it constrains what the plan may ALSO do, never what it
# must do. The allow-set cannot express a requirement: it says these addresses are
# PERMITTED to change, not that they must. A prohibition-only gate accepts a plan whose
# only entry is the server replace, and each omission below has already shipped as an
# incident on a sibling path.
mk_plan "$TMP/no-nic.json" "$(printf '[%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["delete","create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.workspaces["web-2"]' 'hcloud_volume_attachment' '["delete","create"]')" \
  "$(rc_entry 'hcloud_firewall_attachment.web' 'hcloud_firewall_attachment' '["update"]')")"
check "the server replaced with NO private NIC => ABORT (#6416)" 1 "hcloud_server_network" "$TMP/no-nic.json" "web-2"

mk_plan "$TMP/no-attach.json" "$(printf '[%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["delete","create"]')" \
  "$(rc_entry 'hcloud_server_network.web["web-2"]' 'hcloud_server_network' '["delete","create"]')" \
  "$(rc_entry 'hcloud_firewall_attachment.web' 'hcloud_firewall_attachment' '["update"]')")"
check "the server replaced with NO volume attachment => ABORT (silent data loss)" 1 "hcloud_volume_attachment" "$TMP/no-attach.json" "web-2"

mk_plan "$TMP/no-firewall.json" "$(printf '[%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-2"]' 'hcloud_server' '["delete","create"]')" \
  "$(rc_entry 'hcloud_server_network.web["web-2"]' 'hcloud_server_network' '["delete","create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.workspaces["web-2"]' 'hcloud_volume_attachment' '["delete","create"]')")"
check "the server replaced with NO firewall re-attach => ABORT (naked public IP)" 1 "hcloud_firewall_attachment" "$TMP/no-firewall.json" "web-2"

# ── THE KEYED ARMS FOR web-1 (#9356) ──────────────────────────────────────────────
#
# THESE FIXTURES ARE ARMS-ONLY AND CERTIFY NOTHING ABOUT WEB-1 SAFETY. A web-1 replace entails
# three blockers no plan can show: the by-id /mnt/data pin to the SUPERSEDED plaintext volume,
# the web-1-pinned terraform_data SSH provisioners (not in a -target plan), and -target being
# upstream-only. The arms exist so a later relaxing change is graded against them; the REFUSAL
# at the top of the gate is what keeps web-1 out, and it stays first and intact (CPO condition 1).
#
# The arms are reachable only with the refusal constant cleared. `check_arms` clears it INSIDE a
# subshell so the override never leaks into the rest of the suite; `check` (no override) is
# used wherever the refusal must be seen intact.
#
# mk_w1 <file> <att-entry|-> <apex-entry|-> [extra-entry|-] [prior-luks-id|none] [content-refs-json|none]
LUKS_ID="9356001"
OTHER_LUKS_ID="9356002"
APEX_B='{"name":"app","type":"A","proxied":true,"ttl":1,"zone_id":"zone1","content":"192.0.2.10","id":"rec1"}'
APEX_A='{"name":"app","type":"A","proxied":true,"ttl":1,"zone_id":"zone1","content":"192.0.2.99","id":"rec1"}'
REFS_OK='["hcloud_server.web[\"web-1\"].ipv4_address","hcloud_server.web[\"web-1\"]","hcloud_server.web"]'

# rc_att <actions-json> <volume-id-json>
rc_att() {
  printf '{"address":"hcloud_volume_attachment.workspaces_luks","type":"hcloud_volume_attachment","change":{"actions":%s,"before":{},"after":{"volume_id":%s}}}' "$1" "$2"
}
# rc_apex <actions-json> <before-json> <after-json> <after_unknown-json>
rc_apex() {
  printf '{"address":"cloudflare_record.app","type":"cloudflare_record","change":{"actions":%s,"before":%s,"after":%s,"after_unknown":%s}}' "$1" "$2" "$3" "$4"
}
mk_w1() {
  local f="$1" att="$2" apex="$3" extra="${4:--}" prior="${5:-$LUKS_ID}" refs="${6:-$REFS_OK}"
  local entries
  entries="$(happy_changes web-1 | sed 's/^\[//; s/\]$//')"
  [[ "$att" != "-" ]] && entries="${entries},${att}"
  [[ "$apex" != "-" ]] && entries="${entries},${apex}"
  [[ "$extra" != "-" ]] && entries="${entries},${extra}"
  jq -n --argjson c "[${entries}]" --arg id "$prior" --argjson refs "${refs/none/null}" '
    {format_version: "1.2", resource_changes: $c}
    + (if $id == "none" then {} else {prior_state: {values: {root_module: {resources: [{address: "hcloud_volume.workspaces_luks", values: {id: $id}}]}}}} end)
    + (if $refs == null then {} else {configuration: {root_module: {resources: [{address: "cloudflare_record.app", expressions: {content: {references: $refs}}}]}}} end)' > "$f"
}

# check_arms <name> <want_rc> <needle> <plan> [key]  — the refusal constant cleared in a SUBSHELL.
check_arms() {
  local name="$1" want_rc="$2" needle="$3" plan="$4" key="${5:-web-1}"
  local out rc
  cases=$((cases + 1))
  out="$( _WEB_HOST_REPLACE_LUKS_PINNED_KEY=""; web_host_replace_gate "$plan" "$key" 2>&1 )"; rc=$?
  if [[ "$rc" -eq "$want_rc" && "$out" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name (want rc=$want_rc containing '$needle')" "$rc" "$out"
  fi
}

ATT_OK="$(rc_att '["delete","create"]' "$LUKS_ID")"
APEX_OK="$(rc_apex '["update"]' "$APEX_B" "$APEX_A" '{}')"
W1_PASS='replace of hcloud_server.web["web-1"] permitted'
ARM_ATT='does NOT create hcloud_volume_attachment.workspaces_luks onto the LUKS volume'
ARM_APEX='cloudflare_record.app is not updated in place'

# H2 — MUST-PASS (arms-only fixture, NOT a safety claim) -------------------------
mk_w1 "$TMP/w1-complete.json" "$ATT_OK" "$APEX_OK"
check_arms "H2: an arms-complete web-1 plan with the refusal cleared => PASS (arms-only fixture, not a safety claim)" 0 "$W1_PASS" "$TMP/w1-complete.json"
check_arms "H2: the PASS names the keyed arms it evaluated" 0 "keyed arms for web-1: luks_attachment_recreated_onto_prior_volume=1 apex_record_repointed_in_place=1" "$TMP/w1-complete.json"

# A differently ordered, key-reshuffled equivalent of the same plan: order must not matter.
jq -S '.resource_changes |= reverse' "$TMP/w1-complete.json" > "$TMP/w1-reordered.json"
check_arms "H2: a differently ordered equivalent plan JSON => PASS" 0 "$W1_PASS" "$TMP/w1-reordered.json"

# Provider id typing: the volume id is a string in state and an integer in the attachment.
mk_w1 "$TMP/w1-attstr.json" "$(rc_att '["create"]' "\"$LUKS_ID\"")" "$APEX_OK"
check_arms "a string-typed attachment volume_id equal to the prior id => PASS (string vs integer)" 0 "$W1_PASS" "$TMP/w1-attstr.json"

# An unknown-after-apply content with the source reference present (the real replace shape).
mk_w1 "$TMP/w1-unknown.json" "$ATT_OK" "$(rc_apex '["update"]' "$APEX_B" '{"name":"app","type":"A","proxied":true,"ttl":1,"zone_id":"zone1","id":"rec1"}' '{"content":true}')"
check_arms "apex content unknown-after-apply, sourced from the replaced server => PASS" 0 "$W1_PASS" "$TMP/w1-unknown.json"

# A provider-computed attribute dropped from `after` (marked unknown) is tolerated.
mk_w1 "$TMP/w1-computed.json" "$ATT_OK" "$(rc_apex '["update"]' '{"name":"app","type":"A","proxied":true,"ttl":1,"zone_id":"zone1","content":"192.0.2.10","modified_on":"t0"}' '{"name":"app","type":"A","proxied":true,"ttl":1,"zone_id":"zone1","content":"192.0.2.99"}' '{"modified_on":true}')"
check_arms "a computed attribute unknown-after-apply on the apex record is tolerated => PASS" 0 "$W1_PASS" "$TMP/w1-computed.json"

# Refusal intact (CPO condition 1): the SAME complete plan, refusal active, no override.
check "CPO 1: a COMPLETE web-1 plan still ABORTS while the refusal is active (arms are inert)" 1 "REFUSES it by name" "$TMP/w1-complete.json" "web-1"

# Guard 4 rows 1 / 2 / 2b -------------------------------------------------------
mk_w1 "$TMP/w1-no-att.json" "-" "$APEX_OK"
check_arms "row 1: the LUKS attachment absent => ABORT" 1 "$ARM_ATT" "$TMP/w1-no-att.json"
mk_w1 "$TMP/w1-att-delete.json" "$(rc_att '["delete"]' "$LUKS_ID")" "$APEX_OK"
check_arms "the LUKS attachment only DELETED (never created) => ABORT" 1 "$ARM_ATT" "$TMP/w1-att-delete.json"
mk_w1 "$TMP/w1-no-apex.json" "$ATT_OK" "-"
check_arms "row 2: the apex record absent => ABORT" 1 "$ARM_APEX" "$TMP/w1-no-apex.json"
mk_w1 "$TMP/w1-apex-dc.json" "$ATT_OK" "$(rc_apex '["delete","create"]' "$APEX_B" "$APEX_A" '{}')"
check_arms "row 2b: a delete+create of the apex record (an outage window) => ABORT" 1 "$ARM_APEX" "$TMP/w1-apex-dc.json"
mk_w1 "$TMP/w1-apex-noop.json" "$ATT_OK" "$(rc_apex '["no-op"]' "$APEX_B" "$APEX_B" '{}')"
check_arms "an apex record that is a no-op (stale, not re-pointed) => ABORT" 1 "$ARM_APEX" "$TMP/w1-apex-noop.json"

# Row 3: the LUKS volume in the keyed allow-set. An UPDATE is not a delete, so no named
# backstop objects: out_of_scope is the SOLE objection.
mk_w1 "$TMP/w1-luksvol-update.json" "$ATT_OK" "$APEX_OK" "$(rc_entry 'hcloud_volume.workspaces_luks' 'hcloud_volume' '["update"]')"
check_arms "row 3: an UPDATE of hcloud_volume.workspaces_luks stays out of scope => ABORT" 1 "out-of-scope" "$TMP/w1-luksvol-update.json"
mk_w1 "$TMP/w1-luksvol-delete.json" "$ATT_OK" "$APEX_OK" "$(rc_entry 'hcloud_volume.workspaces_luks' 'hcloud_volume' '["delete"]')"
check_arms "a DELETE of the LUKS volume under the arms key stays a named prohibition => ABORT" 1 "LUKS at-rest volume" "$TMP/w1-luksvol-delete.json"
mk_w1 "$TMP/w1-ptvol-delete.json" "$ATT_OK" "$APEX_OK" "$(rc_entry 'hcloud_volume.workspaces["web-1"]' 'hcloud_volume' '["delete"]')"
check_arms "a DELETE of web-1's plaintext backstop volume under the arms key => ABORT (named)" 1 "workspaces volume" "$TMP/w1-ptvol-delete.json"
mk_w1 "$TMP/w1-pw.json" "$ATT_OK" "$APEX_OK" "$(rc_entry 'random_password.workspaces_luks' 'random_password' '["delete","create"]')"
check_arms "a passphrase rotation under the arms key stays a prohibition => ABORT" 1 "$PASSPHRASE_ARM" "$TMP/w1-pw.json"
mk_w1 "$TMP/w1-webkey.json" "$ATT_OK" "$APEX_OK" "$(rc_entry 'doppler_secret.workspaces_luks_web_key' 'doppler_secret' '["update"]')"
check_arms "an update of the web-class key copy under the arms key => ABORT (named)" 1 "$PASSPHRASE_ARM" "$TMP/w1-webkey.json"

# Ordering: the arms run AFTER every prohibition. A plan that is missing the apex arm AND
# destroys the LUKS volume must be refused for the DESTROY, never reported as an arm gap.
mk_w1 "$TMP/w1-order.json" "$ATT_OK" "-" "$(rc_entry 'hcloud_volume.workspaces_luks' 'hcloud_volume' '["delete"]')"
check_arms "ordering: a prohibition outranks a missing arm (the destroy is named, not the apex gap)" 1 "LUKS at-rest volume" "$TMP/w1-order.json"

# Row 5: the arms are for the arms key ONLY. A web-2 plan that carries web-1's two members is out of
# scope; the base allow-set must not widen for any other key.
w2_plan_with_w1_members() {
  printf '[%s,%s,%s]' "$(happy_changes web-2 | sed 's/^\[//; s/\]$//')" "$ATT_OK" "$APEX_OK"
}
mk_plan "$TMP/w2-w1members.json" "$(w2_plan_with_w1_members)"
check "row 5: a web-2 plan that creates the LUKS attachment and re-points the apex record => ABORT" 1 "out-of-scope" "$TMP/w2-w1members.json" "web-2"
mk_plan "$TMP/w2-attonly.json" "$(printf '[%s,%s]' "$(happy_changes web-2 | sed 's/^\[//; s/\]$//')" "$ATT_OK")"
check "row 5: a web-2 plan that creates only the LUKS attachment => ABORT" 1 "out-of-scope" "$TMP/w2-attonly.json" "web-2"
mk_plan "$TMP/w2-webkey.json" "$(printf '[%s,%s]' "$(happy_changes web-2 | sed 's/^\[//; s/\]$//')" "$(rc_entry 'doppler_secret.workspaces_luks_web_key' 'doppler_secret' '["update"]')")"
check "an update of the web-class key copy on a web-2 replace => ABORT (named)" 1 "$PASSPHRASE_ARM" "$TMP/w2-webkey.json" "web-2"

# Row 6: an apex entry with no `actions`.
mk_w1 "$TMP/w1-apex-noactions.json" "$ATT_OK" "$(rc_noactions 'cloudflare_record.app' 'cloudflare_record')"
check_arms "row 6: an apex entry missing .change.actions => ABORT (unclassifiable)" 1 "unclassifiable" "$TMP/w1-apex-noactions.json"

# Row 7: the apex update must CHANGE content and nothing else.
mk_w1 "$TMP/w1-apex-same.json" "$ATT_OK" "$(rc_apex '["update"]' "$APEX_B" "$APEX_B" '{}')"
check_arms "row 7: an apex update whose content does not change => ABORT" 1 "$ARM_APEX" "$TMP/w1-apex-same.json"
for _attr in 'proxied:false' 'ttl:300' 'name:"www"' 'zone_id:"zone2"' 'type:"CNAME"'; do
  _k="${_attr%%:*}"; _v="${_attr#*:}"
  _a="$(jq -c --arg k "$_k" --argjson v "$_v" '.[$k] = $v' <<<"$APEX_A")"
  mk_w1 "$TMP/w1-apex-attr.json" "$ATT_OK" "$(rc_apex '["update"]' "$APEX_B" "$_a" '{}')"
  check_arms "row 7: the apex update also changes ${_k} => ABORT" 1 "$ARM_APEX" "$TMP/w1-apex-attr.json"
done
mk_w1 "$TMP/w1-apex-extra.json" "$ATT_OK" "$(rc_apex '["update"]' "$APEX_B" "$(jq -c '. + {comment:"x"}' <<<"$APEX_A")" '{}')"
check_arms "row 7: the apex update introduces an attribute absent before => ABORT" 1 "$ARM_APEX" "$TMP/w1-apex-extra.json"
mk_w1 "$TMP/w1-apex-nullcontent.json" "$ATT_OK" "$(rc_apex '["update"]' "$APEX_B" "$(jq -c '.content = null' <<<"$APEX_A")" '{}')"
check_arms "row 7: the apex content nulled => ABORT" 1 "$ARM_APEX" "$TMP/w1-apex-nullcontent.json"

# The content must be SOURCED from the replaced server: after_unknown.content is true for ANY replace.
mk_w1 "$TMP/w1-apex-foreign.json" "$ATT_OK" "$(rc_apex '["update"]' "$APEX_B" '{"name":"app","type":"A","proxied":true,"ttl":1,"zone_id":"zone1","id":"rec1"}' '{"content":true}')" - "$LUKS_ID" '["var.origin_ip"]'
check_arms "apex content sourced from a variable, not the replaced server => ABORT" 1 "$ARM_APEX" "$TMP/w1-apex-foreign.json"
mk_w1 "$TMP/w1-apex-sibling.json" "$ATT_OK" "$APEX_OK" - "$LUKS_ID" '["hcloud_server.web[\"web-2\"].ipv4_address","hcloud_server.web[\"web-2\"]"]'
check_arms "apex content sourced from a SIBLING host => ABORT" 1 "$ARM_APEX" "$TMP/w1-apex-sibling.json"
mk_w1 "$TMP/w1-apex-bare.json" "$ATT_OK" "$APEX_OK" - "$LUKS_ID" '["hcloud_server.web"]'
check_arms "apex content referencing only the bare for_each map => ABORT" 1 "$ARM_APEX" "$TMP/w1-apex-bare.json"
mk_w1 "$TMP/w1-apex-noconfig.json" "$ATT_OK" "$APEX_OK" - "$LUKS_ID" none
check_arms "a plan with no configuration section (source unprovable) => ABORT, fail-closed" 1 "$ARM_APEX" "$TMP/w1-apex-noconfig.json"

# Row 8: the attachment must go back onto the prior state's LUKS volume.
mk_w1 "$TMP/w1-att-other.json" "$(rc_att '["delete","create"]' "$OTHER_LUKS_ID")" "$APEX_OK"
check_arms "row 8: the attachment recreated onto a DIFFERENT volume id => ABORT" 1 "$ARM_ATT" "$TMP/w1-att-other.json"
mk_w1 "$TMP/w1-att-unknownvol.json" "$(printf '{"address":"hcloud_volume_attachment.workspaces_luks","type":"hcloud_volume_attachment","change":{"actions":["delete","create"],"before":{},"after":{},"after_unknown":{"volume_id":true}}}')" "$APEX_OK"
check_arms "the attachment's volume id unknown-after-apply (volume being replaced) => ABORT" 1 "$ARM_ATT" "$TMP/w1-att-unknownvol.json"
mk_w1 "$TMP/w1-noprior.json" "$ATT_OK" "$APEX_OK" - none
check_arms "no prior-state LUKS volume id recorded (cannot prove the volume) => ABORT, fail-closed" 1 "$ARM_ATT" "$TMP/w1-noprior.json"

# ── MUTATION SECTION ──────────────────────────────────────────────────────────────
#
# AC4. Reading a gate and believing its arms are load-bearing is exactly the confidence
# this section exists to refuse. The birth gate's own history is the precedent: it carried
# a DUPLICATED allow-set whose second copy, when a member was deleted from it, left the
# suite fully green — guarded by nothing. So each arm is neutered in turn and the suite
# must go red for it.
#
# Two contracts, because they are genuinely different:
#   mutate_and_check — SOLE guard. Neutering it makes the plan PASS.
#   mutate_layered   — LAYERED guard. Neutering it hands the rejection to a named
#                      fallback arm, never to PASS. It earns its place by OWNING the
#                      message and by surviving a future widening of the fallback.

# mutate_and_check <label> <sed-expr> <plan> <key>
mutate_and_check() {
  local label="$1" sed_expr="$2" plan="$3" key="$4" pre="${5:-:}"
  local mutated out rc
  cases=$((cases + 1))
  mutated="$TMP/mutated-gate.sh"
  sed "$sed_expr" "$GATE" > "$mutated"
  # NON-VACUITY FLOOR. A sed expression that matches nothing produces a byte-identical
  # copy, the "mutated" gate still rejects, and the assertion passes while proving the
  # exact opposite of what it claims. This is the check that makes the battery meaningful.
  if cmp -s "$mutated" "$GATE"; then
    fail "$label — the mutation matched NOTHING in the gate (byte-identical copy); the guard is missing or the sed expression drifted." "n/a" "no textual change"
    return
  fi
  out="$(bash -c "source '$mutated'; $pre; web_host_replace_gate '$plan' '$key'" 2>&1)"; rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "$label (sole guard — neutering it ACCEPTS the dangerous plan)"
  else
    fail "$label — neutering the guard still rejected; it is not the sole arm for this fixture (reclassify as layered)" "$rc" "$out"
  fi
}

# mutate_layered <label> <sed-expr> <plan> <key> <own-signature> <fallback-signature>
mutate_layered() {
  local label="$1" sed_expr="$2" plan="$3" key="$4" own="$5" fallback="$6" pre="${7:-:}"
  local mutated base out rc
  cases=$((cases + 1))
  mutated="$TMP/mutated-layered.sh"
  sed "$sed_expr" "$GATE" > "$mutated"
  if cmp -s "$mutated" "$GATE"; then
    fail "$label — the mutation matched NOTHING in the gate (byte-identical copy); the guard is missing or the sed expression drifted." "n/a" "no textual change"
    return
  fi
  # POSITIVE CONTROL: the UNMUTATED gate must reject this plan via THIS arm. Without it, an
  # arm that never fired for this fixture would still satisfy "own signature absent" and the
  # case would pass without ever exercising the guard.
  base="$( eval "$pre"; web_host_replace_gate "$plan" "$key" 2>&1 )"
  if [[ "$base" != *"$own"* ]]; then
    fail "$label — the unmutated gate did not reject this plan via the '$own' arm; the fixture does not exercise it." "n/a" "$base"
    return
  fi
  out="$(bash -c "source '$mutated'; $pre; web_host_replace_gate '$plan' '$key'" 2>&1)"; rc=$?
  if [[ "$rc" -eq 1 && "$out" != *"$own"* && "$out" == *"$fallback"* ]]; then
    pass "$label (layered — owns the rejection; neutering it hands off to '$fallback', never to PASS)"
  else
    fail "$label — layered contract broken (want rc=1, '$own' absent, '$fallback' present)" "$rc" "$out"
  fi
}

# mutate_must_reject <label> <sed-expr> <plan> <key> <needle> [pre]
#
# The inverse contract: the mutated gate must REJECT a plan the unmutated gate PASSES. It proves
# the suite would notice a mutation that makes the gate refuse a correct plan (the arms demanded
# for every key, so a web-2 replace would abort). Same non-vacuity floors as the others.
mutate_must_reject() {
  local label="$1" sed_expr="$2" plan="$3" key="$4" needle="$5" pre="${6:-:}"
  local mutated base out rc
  cases=$((cases + 1))
  mutated="$TMP/mutated-reject.sh"
  sed "$sed_expr" "$GATE" > "$mutated"
  if cmp -s "$mutated" "$GATE"; then
    fail "$label — the mutation matched NOTHING in the gate (byte-identical copy)." "n/a" "no textual change"
    return
  fi
  base="$( eval "$pre"; web_host_replace_gate "$plan" "$key" 2>&1 )"; rc=$?
  if [[ "$base" != *"PASS"* ]]; then
    fail "$label — the unmutated gate does not PASS this plan; the fixture is not a must-pass control." "n/a" "$base"
    return
  fi
  out="$(bash -c "source '$mutated'; $pre; web_host_replace_gate '$plan' '$key'" 2>&1)"; rc=$?
  if [[ "$rc" -eq 1 && "$out" == *"$needle"* ]]; then
    pass "$label (the mutated gate REFUSES the correct plan — the suite's must-pass row would go red)"
  else
    fail "$label — the mutated gate did not refuse with '$needle'" "$rc" "$out"
  fi
}

# SOLE: the web-1 refusal. Nothing else objects to a well-formed web-1 replace plan — the
# allow-set is keyed on the REQUESTED host, so every address in it is in scope when the
# request IS web-1. Neuter this arm and the gate authorizes replacing the sole live origin.
# Graded on the COMPLETE arms plan (W1_COMPLETE), not the arms-less happy-web1.json: with the keyed
# arms in place an arms-less web-1 plan is ALSO rejected by the arms once the refusal is removed,
# which would reclassify this guard as layered and hide the "arms became the relaxation path"
# mutation (Guard 4 row 4). The refusal must be the SOLE thing between a complete plan and PASS.
mutate_and_check "web-1 refusal (arms complete: the arms must not become the relaxation path)" 's/if \[\[ "\$host_key" == "\$_WEB_HOST_REPLACE_LUKS_PINNED_KEY" \]\]; then/if false; then/' \
  "$TMP/w1-complete.json" "web-1"

# SOLE: the actions-shape guard. Measured, not reasoned about — the birth gate's equivalent
# looked layered behind numeric counter-validation and was not.
mutate_and_check "actions-shape guard" 's/^    echo "web_host_replace_gate: ABORT — unclassifiable.*/    return 0/' \
  "$TMP/noactions.json" "web-2"

# LAYERED: the replace-cardinality arm. Classified SOLE on first writing and MEASURED
# otherwise — with zero replaces the identity arm reads an empty replaced_addr, which can
# never equal the requested address, so it catches the plain-CREATE fixture too. The
# cardinality arm still earns its place: it OWNS the message, and the message is the one
# an operator can act on ("the host is not in state; use web-host-create"), where the
# identity fallback would report a mismatch against an empty address. Recorded rather than
# quietly re-pointed, because "I reasoned it was the only arm" is precisely the belief this
# battery exists to refuse.
mutate_layered "replace-cardinality guard" 's/if \[\[ "\$replaced" -ne 1 \]\]; then/if false; then/' \
  "$TMP/zero-replaces.json" "web-2" "no host replace" "IDENTITY MISMATCH"

# SOLE: the three requirement arms. No prohibition can catch a MISSING member — that is the
# whole point of adding them — so each fixture is dangerous by OMISSION and each mutation
# must let it through.
mutate_and_check "NIC requirement arm" 's/if \[\[ "\$nic" -lt 1 \]\]; then/if false; then/' \
  "$TMP/no-nic.json" "web-2"
mutate_and_check "volume-attachment requirement arm" 's/if \[\[ "\$vatt" -lt 1 \]\]; then/if false; then/' \
  "$TMP/no-attach.json" "web-2"
mutate_and_check "firewall requirement arm" 's/if \[\[ "\$fw" -lt 1 \]\]; then/if false; then/' \
  "$TMP/no-firewall.json" "web-2"

# SOLE: the out-of-scope arm. The Cloudflare ruleset is in nobody else's jurisdiction.
mutate_and_check "out-of-scope guard" 's/if \[\[ "\$oos" -ne 0 \]\]; then/if false; then/' \
  "$TMP/out-of-scope.json" "web-2"

# LAYERED: identity. A replace of web-3 on a web-2 dispatch is both an identity mismatch and
# out of scope. Identity runs first and owns the message; the allow-set is the backstop.
mutate_layered "identity guard" 's/if \[\[ "\$replaced_addr" != "\$want_addr" \]\]; then/if false; then/' \
  "$TMP/wrong-identity.json" "web-2" "IDENTITY MISMATCH" "out-of-scope"

# LAYERED: the three named preserve backstops. Each target is out of the allow-set, so
# out_of_scope is the fallback — these arms exist for the operator-legible message.
mutate_layered "workspaces-volume backstop" 's/if \[\[ "\$wvd" -ne 0 \]\]; then/if false; then/' \
  "$TMP/vol-destroy.json" "web-2" "workspaces volume" "out-of-scope"
mutate_layered "LUKS-volume backstop" 's/if \[\[ "\$lvd" -ne 0 \]\]; then/if false; then/' \
  "$TMP/luks-vol-destroy.json" "web-2" "LUKS at-rest volume" "out-of-scope"
mutate_layered "LUKS-passphrase backstop" 's/if \[\[ "\$lpt" -ne 0 \]\]; then/if false; then/' \
  "$TMP/passphrase-rotate.json" "web-2" "$PASSPHRASE_ARM" "out-of-scope"

# LAYERED: the reboot arm. A web-1 power-cycle is both a reboot and out of scope today. The
# arm earns its place by naming the consequence, and by surviving a future widening of the
# allow-set that would silence the backstop but not it.
mutate_layered "reboot guard" 's/if \[\[ "\$reboot" -ne 0 \]\]; then/if false; then/' \
  "$TMP/reboot.json" "web-2" "reboot-forcing" "out-of-scope"

# ── GUARD 4: the keyed arms (#9356) ───────────────────────────────────────────────
#
# Every row neuters ONE guard in a copy of the gate and requires the suite to notice. The arms
# are reachable only with the refusal cleared, so each runs under the same subshell override the
# fixtures use ($PRE); row 4 (the refusal) runs WITHOUT it, which is the point of that row.
PRE='_WEB_HOST_REPLACE_LUKS_PINNED_KEY=""'

# Row 1 / 2: each requirement arm is SOLE. No prohibition can see a MISSING member.
mutate_and_check "row 1: LUKS-attachment requirement arm" 's/if \[\[ "\$latt" -lt 1 \]\]; then/if false; then/' \
  "$TMP/w1-no-att.json" "web-1" "$PRE"
mutate_and_check "row 2: apex-record requirement arm" 's/if \[\[ "\$apex" -lt 1 \]\]; then/if false; then/' \
  "$TMP/w1-no-apex.json" "web-1" "$PRE"

# Row 2b: the apex actions must be EXACTLY ["update"].
mutate_and_check "row 2b: apex actions widened to accept delete+create" \
  's/select(.change.actions == \["update"\]) # arm:apex-actions/select(.change.actions | index("update") or index("create")) # arm:apex-actions/' \
  "$TMP/w1-apex-dc.json" "web-1" "$PRE"

# Row 3: hcloud_volume.workspaces_luks added to the keyed allow-set.
mutate_and_check "row 3: the LUKS volume added to the keyed allow-set" \
  's/^      "cloudflare_record.app"$/      "cloudflare_record.app",\n      "hcloud_volume.workspaces_luks"/' \
  "$TMP/w1-luksvol-update.json" "web-1" "$PRE"

# Row 4 is the existing "web-1 refusal" mutation above, graded on the COMPLETE arms plan.

# Row 5: the keyed allow-set applied to every key (a web-2 plan carrying web-1's members passes),
# and, inversely, the arms DEMANDED of every key (a correct web-2 replace aborts).
mutate_and_check "row 5a: the keyed allow-set applied to key web-2" \
  's/if \$k == \$akey then allow_arms else \[\] end/if true then allow_arms else [] end/' \
  "$TMP/w2-w1members.json" "web-2"
mutate_must_reject "row 5b: the keyed ARMS demanded of every key (a correct web-2 replace aborts)" \
  's/if \[\[ "\$host_key" == "\$_WEB_HOST_REPLACE_LUKS_ARMS_KEY" \]\]; then/if true; then/' \
  "$TMP/happy.json" "web-2" "$ARM_ATT"

# Row 6: the shape guard is the sole thing that sees an apex entry without actions.
mutate_and_check "row 6: actions-shape guard (an apex entry with no actions)" \
  's/^    echo "web_host_replace_gate: ABORT — unclassifiable.*/    return 0/' \
  "$TMP/w1-apex-noactions.json" "web-1" "$PRE"

# Row 7: content change, other-attribute change and content source each have their own line.
mutate_and_check "row 7a: apex content-must-change predicate" \
  's/.*# arm:apex-content$/                | select(true)/' \
  "$TMP/w1-apex-same.json" "web-1" "$PRE"
_PROXIED_FLIP="$TMP/w1-apex-proxied.json"
mk_w1 "$_PROXIED_FLIP" "$ATT_OK" "$(rc_apex '["update"]' "$APEX_B" "$(jq -c '.proxied = false' <<<"$APEX_A")" '{}')"
mutate_and_check "row 7b: apex other-attributes-unchanged predicate" \
  's/.*# arm:apex-attrs$/                | select(true)/' \
  "$_PROXIED_FLIP" "web-1" "$PRE"
mutate_and_check "row 7c: apex content-sourced-from-the-replaced-server predicate" \
  's/.*# arm:apex-source$/                | select(true)/' \
  "$TMP/w1-apex-foreign.json" "web-1" "$PRE"

# Row 8: the attachment must return onto the prior state's LUKS volume.
mutate_and_check "row 8: attachment volume-id equals the prior state's LUKS volume id" \
  's/.*# arm:luks-volume-id$/                | select(true)/' \
  "$TMP/w1-att-other.json" "web-1" "$PRE"

# H1 — HARNESS: remove the whole keyed block. A plan missing an arm must then PASS, which proves
# the suite's fixtures reach the arms and would go red if the block were gone.
mutate_and_check "H1: the whole keyed-arms block removed (arms-less gate passes an arm-less web-1 plan)" \
  's/if \[\[ "\$host_key" == "\$_WEB_HOST_REPLACE_LUKS_ARMS_KEY" \]\]; then/if false; then/' \
  "$TMP/w1-no-apex.json" "web-1" "$PRE"

# The web-class key copy (#9377) joins the passphrase prohibition. Layered over out_of_scope (it is
# in nobody's allow-set), and it earns its place by naming the consequence.
mutate_layered "luks_passphrase_touched names the web-class key copy" \
  's/ or \.address == "doppler_secret\.workspaces_luks_web_key"//' \
  "$TMP/w2-webkey.json" "web-2" "$PASSPHRASE_ARM" "out-of-scope"

# ── ANTI-VACUITY FLOOR ────────────────────────────────────────────────────────────
#
# `cases` is incremented at every check/mutate call site and NEVER inside pass()/fail(), so it
# moves whether or not a verdict is recorded. Two assertions: the conservation identity (every
# case recorded exactly one verdict — a neutered pass/fail breaks it) and a floor (deleting a
# block of arms lowers `cases` and reddens the floor). A FLOOR, not equality: it is developer
# incremented, and `-eq` trains people to bump it unread.
CASES_FLOOR=100
_verdicts=$((passes + fails))
if [[ "$cases" -ne "$_verdicts" ]]; then
  fails=$((fails + 1))
  printf '  FAIL CONSERVATION: %s cases ran but %s verdicts were recorded (a pass/fail was dropped).\n' "$cases" "$_verdicts"
elif [[ "$cases" -lt "$CASES_FLOOR" ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s cases ran, floor is %s. Arms were deleted or the suite exited early.\n' "$cases" "$CASES_FLOOR"
else
  printf '  ok   anti-vacuity floor: %s cases ran, each recorded one verdict (floor %s)\n' "$cases" "$CASES_FLOOR"
fi

printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
