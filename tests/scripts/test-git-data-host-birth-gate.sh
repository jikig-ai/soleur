#!/usr/bin/env bash
# Test suite for tests/scripts/lib/git-data-host-birth-gate.sh (#6977).
#
# THE GATE THIS GRADES IS THE ONLY CHECK ON ITS PATH. Per ADR-145 a new dispatch job
# inherits nothing: the per-PR `host_creates > 0` HALT is a separate inline copy in the
# `apply` job whose `if:` is mutually exclusive with every dispatch job. So this is not
# defense-in-depth behind an existing guard — for the birth dispatch it is the whole of
# the defense, and every branch is load-bearing.
#
# WHAT IT PROTECTS. git-data is the shared bare-repo store — the workflow's own words are
# "the fleet's most irreplaceable data store". The reachable failures a wrong gate waves
# through, in descending severity:
#   (a) the host lands NAKED on its public IPv4/IPv6 (hcloud_firewall_attachment.git_data
#       omitted — it is DOWNSTREAM of the server, so `-target` does not auto-pull it),
#       exposing every connected user's source code to the open internet;
#   (b) the host lands with /mnt/git-data-luks silently UNMOUNTED, so at-rest encryption
#       is absent while every artifact claims it is present;
#   (c) the host lands with NO private NIC (#6416), which no reboot repairs because
#       `runcmd` is once-per-instance — and ADR-115 bars git-data from the reboot
#       primitive anyway, so the host must be replaced;
#   (d) the gate WEDGES the retry path, leaving a half-created host with no recovery in
#       either direction except the laptop apply this work exists to eliminate.
#
# (d) is why the requirement arm is split by entailment rather than "require the fan-out".
# The distinction is the single most important contract in this file.
#
# The property that protects production is the REJECT set. A birth gate that only proves
# "the happy plan passes" is worthless, so every arm below is a refusal and each is
# mutation-proven at the end under an explicit SOLE-GUARD or LAYERED contract.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
GATE="${ROOT}/tests/scripts/lib/git-data-host-birth-gate.sh"
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

# ── Fixture builders ──────────────────────────────────────────────────────────────
# Fixtures are SYNTHESIZED, never captured (cq-test-fixtures-synthesized-only): a real
# `terraform show -json` embeds `.variables` VERBATIM, including values declared
# `sensitive = true` — sensitivity masks render-time text output, not JSON serialization.
# This tree has already shipped a captured fixture carrying a GitHub App RSA private key.

# mk_plan, rc_entry, rc_noactions, rc_empty_actions, rc_scalar_change, gate_check,
# gate_mutate_and_check and gate_mutate_layered now come from the shared harness (#6997).
# It requires pass/fail/TMP (defined above) and GATE/PREAMBLE (defined above) — hence the
# source ordering. This suite is the harness's FIRST consumer and its migration is the
# harness's own proof: the arm count below must be unchanged.
# shellcheck source=tests/scripts/lib/gate-suite-harness.sh
source "${ROOT}/tests/scripts/lib/gate-suite-harness.sh"

# rc_update <address> <type> <before-json> <after-json>
#
# The one shape rc_entry cannot express: it hardcodes before:null, the create/delete edge.
# The reboot and firewall-content arms both compare before against after, so they need
# both sides populated.
rc_update() {
  printf '{"address":%s,"type":%s,"change":{"actions":["update"],"before":%s,"after":%s}}' \
    "$(printf '%s' "$1" | jq -R .)" "$(printf '%s' "$2" | jq -R .)" "$3" "$4"
}

# rc_fw_attach <actions-json> <server_ids-json> [firewall_id-json]
#
# The firewall attachment needs a populated `.change.after`: the gate asserts the OUTCOME
# (server_ids ends at length 1) rather than a verb, because this resource's terraform ID
# is the FIREWALL's id — so a host destroyed outside terraform leaves it alive with
# server_ids emptied and a legitimate re-birth plans an UPDATE here, not a create.
#
# `firewall_id` defaults to unknown (`after_unknown.firewall_id: true`), which is the real
# shape when the firewall is created in the same plan. Passing a KNOWN id models the
# attachment binding some OTHER, pre-existing firewall.
rc_fw_attach() {
  local acts="$1" sids="$2" fwid="${3:-}"
  if [[ -n "$fwid" ]]; then
    printf '{"address":"hcloud_firewall_attachment.git_data","type":"hcloud_firewall_attachment","change":{"actions":%s,"before":null,"after":{"server_ids":%s,"firewall_id":%s},"after_unknown":{}}}' "$acts" "$sids" "$fwid"
  else
    printf '{"address":"hcloud_firewall_attachment.git_data","type":"hcloud_firewall_attachment","change":{"actions":%s,"before":null,"after":{"server_ids":%s},"after_unknown":{"firewall_id":true}}}' "$acts" "$sids"
  fi
}

# The three members whose existence the server's own creation ENTAILS: each references
# `hcloud_server.git_data.id` AND has the server as its state identity, so a new server
# implies a new instance. These are the ONLY addresses the requirement arm may demand
# `creates == 1` from.
#
# hcloud_firewall_attachment.git_data is NOT among them — see rc_fw_attach.
entailed_four() {
  printf '%s,%s,%s,%s' \
    "$(rc_entry 'hcloud_server_network.git_data' 'hcloud_server_network' '["create"]')" \
    "$(rc_entry 'hcloud_volume_attachment.git_data' 'hcloud_volume_attachment' '["create"]')" \
    "$(rc_entry 'hcloud_volume_attachment.git_data_luks' 'hcloud_volume_attachment' '["create"]')" \
    "$(rc_fw_attach '["create"]' '[9001]')"
}

# The other thirteen in-scope members, all as creates.
rest_thirteen() {
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s' \
    "$(rc_entry 'hcloud_volume.git_data' 'hcloud_volume' '["create"]')" \
    "$(rc_entry 'hcloud_volume.git_data_luks' 'hcloud_volume' '["create"]')" \
    "$(rc_entry 'hcloud_firewall.git_data' 'hcloud_firewall' '["create"]')" \
    "$(rc_entry 'doppler_config.git_data_prd' 'doppler_config' '["create"]')" \
    "$(rc_entry 'doppler_service_token.git_data' 'doppler_service_token' '["create"]')" \
    "$(rc_entry 'tls_private_key.git_transport' 'tls_private_key' '["create"]')" \
    "$(rc_entry 'tls_private_key.git_provision' 'tls_private_key' '["create"]')" \
    "$(rc_entry 'tls_private_key.git_remove' 'tls_private_key' '["create"]')" \
    "$(rc_entry 'doppler_secret.git_transport_ssh_private_key' 'doppler_secret' '["create"]')" \
    "$(rc_entry 'doppler_secret.git_provision_ssh_private_key' 'doppler_secret' '["create"]')" \
    "$(rc_entry 'doppler_secret.git_remove_ssh_private_key' 'doppler_secret' '["create"]')" \
    "$(rc_entry 'random_password.git_data_luks' 'random_password' '["create"]')" \
    "$(rc_entry 'doppler_secret.git_data_luks_key' 'doppler_secret' '["create"]')"
}

# rest_thirteen_except <address> — the thirteen presence members minus one.
# rest_thirteen_with <address> <actions-json> — the thirteen with ONE member's actions replaced.
#
# ONE ENTRY PER ADDRESS IS AN INVARIANT OF THE INPUT FORMAT, and violating it silently
# changes what the mutation battery measures. `terraform show -json` emits exactly one
# `resource_changes` entry per address. An earlier revision of this suite built its
# "a delete on X" fixtures by APPENDING a second entry for X alongside the `["create"]`
# one already in rest_thirteen — a document terraform cannot produce. The gate's presence
# arm then found the surviving create and passed, so neutering the passphrase arm let the
# plan through and the battery reported SOLE-GUARD. On a realistic single-entry plan the
# same mutation is caught by the presence arm: the arm is LAYERED. The battery was
# measuring an impossible input and reporting a wrong classification — which is the
# failure this file's own mutation-section header warns about, one level down.
#
# Filtered with jq rather than sed: a regex over serialized JSON silently matches nothing
# (yielding a fixture identical to the happy one, so the ABORT assertion fails for the
# wrong reason) or matches too much (yielding malformed JSON, so the gate aborts in the
# PREAMBLE and the arm under test never runs — a pass that proves nothing).
rest_thirteen_except() {
  printf '[%s]' "$(rest_thirteen)" \
    | jq -c --arg a "$1" '[.[] | select(.address != $a)]' \
    | sed 's/^\[//; s/\]$//'
}

rest_thirteen_with() {
  printf '[%s]' "$(rest_thirteen)" \
    | jq -c --arg a "$1" --argjson acts "$2" \
        '[.[] | if .address == $a then .change.actions = $acts else . end]' \
    | sed 's/^\[//; s/\]$//'
}

# The canonical happy plan: the full eighteen-address birth.
happy_changes() {
  printf '[%s,%s,%s]' \
    "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
    "$(entailed_four)" \
    "$(rest_thirteen)"
}

# A minimal plan: the server plus only the four entailed members. Everything the
# requirement arm demands as PRESENCE is absent, so this must ABORT — but via the
# presence assertion, naming a missing address, not via a count.
minimal_changes() {
  printf '[%s,%s]' \
    "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
    "$(entailed_four)"
}

# This suite's own `check` signature, bound to its gate. `check()` had drifted into three
# incompatible signatures across the four suites that grew a copy, so the harness ships the
# general `gate_check <name> <fn> <want_rc> <needle> <args…>` and each suite keeps the
# one-line wrapper that preserves its existing call sites.
check() {
  local name="$1"; shift
  gate_check "$name" git_data_host_birth_gate "$@"
}

printf '\n=== git-data-host-birth-gate ===\n\n'

# ── The plans that must PASS ──────────────────────────────────────────────────────
mk_plan "$TMP/happy.json" "$(happy_changes)"
check "the full eighteen-address scoped birth => PASS" 0 "PASS" "$TMP/happy.json"
check "the PASS line names the host it authorized" 0 "hcloud_server.git_data" "$TMP/happy.json"

# THE PARTIAL-BIRTH RESUME FIXTURE — the case v1 of this gate would have wedged forever.
#
# `random_password.git_data_luks` is dependency-free and lands in Terraform's first wave.
# On a dispatch whose server create fails AFTER it lands, it is in state; the re-dispatch
# re-plans it as `no-op`. A gate requiring `creates == 1` on it then ABORTS on every
# retry, permanently. And the replace gate cannot rescue the operator either — it needs
# `actions ⊇ {delete,create}` on a resource that does not exist. Both automated routes
# refuse, leaving only the untargeted laptop apply this entire work exists to eliminate.
#
# So this fixture is not an edge case. It is the documented recovery path, and it MUST
# pass.
mk_plan "$TMP/partial-resume.json" "$(printf '[%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(rc_entry 'hcloud_server_network.git_data' 'hcloud_server_network' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.git_data' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.git_data_luks' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_fw_attach '["create"]' '[9001]')" \
  "$(rc_entry 'hcloud_volume.git_data' 'hcloud_volume' '["no-op"]')" \
  "$(rc_entry 'hcloud_volume.git_data_luks' 'hcloud_volume' '["no-op"]')" \
  "$(rc_entry 'hcloud_firewall.git_data' 'hcloud_firewall' '["no-op"]')" \
  "$(rc_entry 'doppler_config.git_data_prd' 'doppler_config' '["no-op"]')" \
  "$(rc_entry 'doppler_service_token.git_data' 'doppler_service_token' '["no-op"]')" \
  "$(rc_entry 'tls_private_key.git_transport' 'tls_private_key' '["no-op"]')" \
  "$(rc_entry 'tls_private_key.git_provision' 'tls_private_key' '["no-op"]')" \
  "$(rc_entry 'tls_private_key.git_remove' 'tls_private_key' '["no-op"]')" \
  "$(rc_entry 'doppler_secret.git_transport_ssh_private_key' 'doppler_secret' '["no-op"]')" \
  "$(rc_entry 'doppler_secret.git_provision_ssh_private_key' 'doppler_secret' '["no-op"]')" \
  "$(rc_entry 'doppler_secret.git_remove_ssh_private_key' 'doppler_secret' '["no-op"]')" \
  "$(rc_entry 'random_password.git_data_luks' 'random_password' '["no-op"]')" \
  "$(rc_entry 'doppler_secret.git_data_luks_key' 'doppler_secret' '["no-op"]')")"
check "a PARTIAL-BIRTH RESUME (mixed create/no-op) => PASS" 0 "PASS" "$TMP/partial-resume.json"

# The three shared-network members terraform pulls in transitively as no-ops. Refusing
# these would abort on legitimate shared drift, so they must NOT be out-of-scope.
#
# hcloud_ssh_key.default is safe to tolerate ONLY because server.tf carries
# `lifecycle { ignore_changes = [public_key] }` on it — without that, the job's ephemeral
# ssh-keygen key would ForceNew-replace the SSH key shared by web-1, registry, inngest
# and grok-dogfood. Tolerated as a no-op, never as a change.
mk_plan "$TMP/transitive-noop.json" "$(printf '[%s,%s,%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" \
  "$(rest_thirteen)" \
  "$(rc_entry 'hcloud_ssh_key.default' 'hcloud_ssh_key' '["no-op"]')" \
  "$(rc_entry 'hcloud_network.private' 'hcloud_network' '["no-op"]')" \
  "$(rc_entry 'hcloud_network_subnet.private' 'hcloud_network_subnet' '["no-op"]')")"
check "transitive no-ops on shared network resources => PASS" 0 "PASS" "$TMP/transitive-noop.json"

# A `read` on the server-type data source. The arch precondition depends on it, and under
# `-target` an UNREFERENCED data source is pruned and never read — which silently disarms
# the phantom-type guard that is the only plan-time check that fires at all.
mk_plan "$TMP/data-read.json" "$(printf '[%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" \
  "$(rest_thirteen)" \
  "$(rc_entry 'data.hcloud_server_type.git_data' 'hcloud_server_type' '["read"]')")"
check "a data-source read riding the birth => PASS" 0 "PASS" "$TMP/data-read.json"

# ── REJECT: cardinality ───────────────────────────────────────────────────────────
mk_plan "$TMP/zero.json" "$(printf '[%s]' "$(rc_entry 'hcloud_volume.git_data' 'hcloud_volume' '["create"]')")"
check "zero host creates => ABORT" 1 "no host create" "$TMP/zero.json"

mk_plan "$TMP/two.json" "$(printf '[%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(rc_entry 'hcloud_server.web["web-1"]' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" "$(rest_thirteen)")"
check "two host creates => ABORT" 1 "expected exactly 1" "$TMP/two.json"

# The 0-vs->1 messages must be DISTINCT. They send the operator to opposite diagnoses:
# zero means the host already exists or the -target set is mis-scoped; more than one
# means the -target set escaped its scope entirely.
out_zero="$(git_data_host_birth_gate "$TMP/zero.json" 2>&1)"
out_two="$(git_data_host_birth_gate "$TMP/two.json" 2>&1)"
if [[ "$out_zero" != "$out_two" && "$out_zero" == *"no host create"* && "$out_two" == *"expected exactly 1"* ]]; then
  pass "the 0-creates and >1-creates aborts carry DISTINCT messages"
else
  fail "0-vs->1 cardinality messages must differ" "n/a" "zero=[$out_zero] two=[$out_two]"
fi

# ── REJECT: identity ──────────────────────────────────────────────────────────────
# A count-only gate passes a plan that births exactly one host that is not this one.
# hcloud_server.web["web-1"] is the singleton behind app.soleur.ai.
mk_plan "$TMP/wrong-host.json" "$(printf '[%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.web["web-1"]' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" "$(rest_thirteen)")"
check "a create of a DIFFERENT host => ABORT" 1 "IDENTITY MISMATCH" "$TMP/wrong-host.json"
check "the identity ABORT names the wrongly-born host" 1 'hcloud_server.web["web-1"]' "$TMP/wrong-host.json"

# ── REJECT: destroys ──────────────────────────────────────────────────────────────
mk_plan "$TMP/replace.json" "$(printf '[%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["delete","create"]')" \
  "$(entailed_four)" "$(rest_thirteen)")"
# Needle is the ARM's phrasing, not the bare word "destroy" — the telemetry line printed
# before every verdict contains `destroys=N`, so a bare needle is satisfied without any
# arm firing. Measured: replacing this arm's message with prose containing no "destroy"
# left the suite fully green.
check "a REPLACE of the host => ABORT" 1 "destroy/forget action" "$TMP/replace.json"

# `forget` is a state-drop, not a destroy — it abandons a live billing resource without
# deleting it. Equally not a birth, so it counts.
mk_plan "$TMP/forget.json" "$(printf '[%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" "$(rest_thirteen_with 'hcloud_volume.git_data' '["forget"]')")"
check "a FORGET (state-drop) anywhere => ABORT" 1 "DATA VOLUME" "$TMP/forget.json"

# ── REJECT: a named volume destroy — issue AC2, both volumes ──────────────────────
# The generic destroy arm already refuses these. This arm exists for the MESSAGE: an
# operator reading "1 destroy/forget action" mid-dispatch does not know that the thing
# about to be destroyed is the store holding every user's source code.
mk_plan "$TMP/destroy-vol.json" "$(printf '[%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" "$(rest_thirteen_with 'hcloud_volume.git_data' '["delete"]')")"
check "destroying the DATA volume => ABORT naming it (AC2)" 1 "hcloud_volume.git_data" "$TMP/destroy-vol.json"
check "the data-volume abort says DATA VOLUME" 1 "DATA VOLUME" "$TMP/destroy-vol.json"

mk_plan "$TMP/destroy-luks-vol.json" "$(printf '[%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" "$(rest_thirteen_with 'hcloud_volume.git_data_luks' '["delete"]')")"
check "destroying the LUKS volume => ABORT naming it (AC2)" 1 "hcloud_volume.git_data_luks" "$TMP/destroy-luks-vol.json"

# ── REJECT: the firewall-content arm ──────────────────────────────────────────────
# THE HOLE v1 OF THIS GATE OPENED. v1 moved hcloud_firewall.git_data into the allow-set,
# where `update` is permitted and no arm inspected it. hcloud_firewall.git_data is a
# ZERO-RULE DENY-ALL firewall, and hcloud_firewall_attachment.git_data is the only thing
# binding it to the host — so an `update` adding inbound rules is the one mutation that
# converts a correct-looking birth into a bare-repo store on the open internet, silently.
mk_plan "$TMP/fw-rules.json" "$(printf '[%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" \
  "$(printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s' \
    "$(rc_entry 'hcloud_volume.git_data' 'hcloud_volume' '["create"]')" \
    "$(rc_entry 'hcloud_volume.git_data_luks' 'hcloud_volume' '["create"]')" \
    "$(rc_entry 'doppler_config.git_data_prd' 'doppler_config' '["create"]')" \
    "$(rc_entry 'doppler_service_token.git_data' 'doppler_service_token' '["create"]')" \
    "$(rc_entry 'tls_private_key.git_transport' 'tls_private_key' '["create"]')" \
    "$(rc_entry 'tls_private_key.git_provision' 'tls_private_key' '["create"]')" \
    "$(rc_entry 'tls_private_key.git_remove' 'tls_private_key' '["create"]')" \
    "$(rc_entry 'doppler_secret.git_transport_ssh_private_key' 'doppler_secret' '["create"]')" \
    "$(rc_entry 'doppler_secret.git_provision_ssh_private_key' 'doppler_secret' '["create"]')" \
    "$(rc_entry 'doppler_secret.git_remove_ssh_private_key' 'doppler_secret' '["create"]')" \
    "$(rc_entry 'random_password.git_data_luks' 'random_password' '["create"]')" \
    "$(rc_entry 'doppler_secret.git_data_luks_key' 'doppler_secret' '["create"]')")" \
  "$(rc_update 'hcloud_firewall.git_data' 'hcloud_firewall' \
      '{"rule":[]}' '{"rule":[{"direction":"in","port":"22","protocol":"tcp","source_ips":["0.0.0.0/0"]}]}')")"
check "an UPDATE adding inbound rules to the deny-all firewall => ABORT" 1 "FIREWALL" "$TMP/fw-rules.json"
check "the firewall abort names the rule count it refused" 1 "1 inbound rule" "$TMP/fw-rules.json"

# The firewall CREATING with zero rules is the correct birth shape and must pass — it is
# in the happy fixture above. But a firewall created WITH rules is equally wrong, and a
# create-only-inspects-updates arm would miss it.
mk_plan "$TMP/fw-born-with-rules.json" "$(printf '[%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" \
  "$(printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s' \
    "$(rc_entry 'hcloud_volume.git_data' 'hcloud_volume' '["create"]')" \
    "$(rc_entry 'hcloud_volume.git_data_luks' 'hcloud_volume' '["create"]')" \
    "$(rc_entry 'doppler_config.git_data_prd' 'doppler_config' '["create"]')" \
    "$(rc_entry 'doppler_service_token.git_data' 'doppler_service_token' '["create"]')" \
    "$(rc_entry 'tls_private_key.git_transport' 'tls_private_key' '["create"]')" \
    "$(rc_entry 'tls_private_key.git_provision' 'tls_private_key' '["create"]')" \
    "$(rc_entry 'tls_private_key.git_remove' 'tls_private_key' '["create"]')" \
    "$(rc_entry 'doppler_secret.git_transport_ssh_private_key' 'doppler_secret' '["create"]')" \
    "$(rc_entry 'doppler_secret.git_provision_ssh_private_key' 'doppler_secret' '["create"]')" \
    "$(rc_entry 'doppler_secret.git_remove_ssh_private_key' 'doppler_secret' '["create"]')" \
    "$(rc_entry 'random_password.git_data_luks' 'random_password' '["create"]')" \
    "$(rc_entry 'doppler_secret.git_data_luks_key' 'doppler_secret' '["create"]')" \
    '{"address":"hcloud_firewall.git_data","type":"hcloud_firewall","change":{"actions":["create"],"before":null,"after":{"rule":[{"direction":"in","port":"22","protocol":"tcp"}]}}}')")"
check "a firewall CREATED carrying inbound rules => ABORT" 1 "FIREWALL" "$TMP/fw-born-with-rules.json"

# A volume RESIZE riding the birth is a mis-scope signal, not a birth.
mk_plan "$TMP/vol-resize.json" "$(printf '[%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" "$(rest_thirteen_with 'hcloud_volume.git_data' '["update"]')")"
check "a volume RESIZE riding the birth => ABORT" 1 "VOLUME UPDATE" "$TMP/vol-resize.json"
check "the volume-update abort names the offending volume" 1 "hcloud_volume.git_data" "$TMP/vol-resize.json"

# ── REJECT: the LUKS-passphrase catastrophe arm ───────────────────────────────────
# ADR-115's second normative blocker. A rotated passphrase luksOpens a NEW header, and
# `isLuks` then declines to reformat — so existing at-rest data becomes permanently
# unopenable. There is no recovery: git-data is excluded from the reboot primitive.
for verb in delete forget update; do
  mk_plan "$TMP/luks-pw-$verb.json" "$(printf '[%s,%s,%s]' \
    "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
    "$(entailed_four)" "$(rest_thirteen_with 'random_password.git_data_luks' "[\"$verb\"]")")"
  check "a $verb on the LUKS PASSPHRASE => ABORT" 1 "LUKS PASSPHRASE" "$TMP/luks-pw-$verb.json"
done

mk_plan "$TMP/luks-secret-update.json" "$(printf '[%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" "$(rest_thirteen_with 'doppler_secret.git_data_luks_key' '["update"]')")"
check "an UPDATE on the LUKS key SECRET => ABORT" 1 "LUKS PASSPHRASE" "$TMP/luks-secret-update.json"

# ── REJECT: the ORPHANED PASSPHRASE MINT (found at review, measured PASS before the arm) ──
#
# The state this gate's own TOO LOOSE paragraph describes: volumes retained, passphrase
# pair absent from state. Terraform plans a CREATE for an out-of-state resource regardless
# of what the gate asks, so "do not MANDATE a create" never implied "refuse one" — and
# every other arm passed. The apply would mint a fresh passphrase over a volume that
# already holds data, and the old header becomes permanently unopenable.
mk_plan "$TMP/orphan-mint.json" "$(printf '[%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" \
  "$(printf '[%s]' "$(rest_thirteen)" | jq -c '[.[] | if .address == "hcloud_volume.git_data_luks" or .address == "hcloud_volume.git_data" then .change.actions = ["no-op"] else . end]' | sed 's/^\[//; s/\]$//')")"
check "a passphrase CREATE while the LUKS volume is a no-op => ABORT" 1 "ORPHANED LUKS PASSPHRASE MINT" "$TMP/orphan-mint.json"

# The CORRECT first birth has both as create — it must still PASS, or the arm has just
# banned every legitimate birth.
check "a passphrase create ALONGSIDE the volume create => PASS" 0 "PASS" "$TMP/happy.json"

# ── REJECT: firewall attachment outcomes ──────────────────────────────────────────
# Omitted entirely — the store boots naked.
mk_plan "$TMP/fw-attach-missing.json" "$(printf '[%s,%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(rc_entry 'hcloud_server_network.git_data' 'hcloud_server_network' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.git_data' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.git_data_luks' 'hcloud_volume_attachment' '["create"]')" \
  "$(rest_thirteen)")"
check "the firewall attachment OMITTED => ABORT" 1 "bound to exactly one server" "$TMP/fw-attach-missing.json"

# A RE-BIRTH: the attachment survived the host's out-of-band destruction (its terraform ID
# is the FIREWALL's id), so it plans an UPDATE from [] to one server. This MUST PASS —
# demanding a create here is what wedges the documented recovery path.
mk_plan "$TMP/fw-attach-rebirth.json" "$(printf '[%s,%s,%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(rc_entry 'hcloud_server_network.git_data' 'hcloud_server_network' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.git_data' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.git_data_luks' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_fw_attach '["update"]' '[9001]')" \
  "$(printf '[%s]' "$(rest_thirteen)" | jq -c '[.[] | .change.actions = ["no-op"]]' | sed 's/^\[//; s/\]$//')")"
check "a RE-BIRTH where the attachment UPDATES [] -> one server => PASS" 0 "PASS" "$TMP/fw-attach-rebirth.json"

# Fan-out: bound to more than one server.
mk_plan "$TMP/fw-attach-fanout.json" "$(printf '[%s,%s,%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(rc_entry 'hcloud_server_network.git_data' 'hcloud_server_network' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.git_data' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.git_data_luks' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_fw_attach '["create"]' '[9001,9002]')" \
  "$(rest_thirteen)")"
check "the firewall attachment bound to TWO servers => ABORT" 1 "bound to exactly one server" "$TMP/fw-attach-fanout.json"

# Identity: bound to a firewall whose id is already KNOWN, i.e. some OTHER firewall than
# the deny-all one this plan creates. Every rule-content arm inspects
# hcloud_firewall.git_data, so this satisfies all of them while the store ends up behind
# whatever that other firewall permits.
mk_plan "$TMP/fw-wrong-identity.json" "$(printf '[%s,%s,%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(rc_entry 'hcloud_server_network.git_data' 'hcloud_server_network' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.git_data' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.git_data_luks' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_fw_attach '["create"]' '[9001]' '"111"')" \
  "$(rest_thirteen)")"
check "the attachment binding a DIFFERENT, already-known firewall => ABORT" 1 "FIREWALL IDENTITY" "$TMP/fw-wrong-identity.json"

# The rule set not disclosed at plan time (a computed `dynamic "rule"` block). Counting an
# undisclosed rule set as zero rules is the same fail-open as reading a degraded 200 as an
# empty list.
mk_plan "$TMP/fw-rules-unknown.json" "$(printf '[%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" \
  "$(printf '[%s]' "$(rest_thirteen)" | jq -c '[.[] | if .address == "hcloud_firewall.git_data" then .change.after = {"rule":null} | .change.after_unknown = {"rule":true} else . end]' | sed 's/^\[//; s/\]$//')")"
check "an UNDISCLOSED firewall rule set => ABORT" 1 "FIREWALL CONTENT UNREADABLE" "$TMP/fw-rules-unknown.json"

# Inline firewall_ids on the server bypasses the attachment the gate inspects entirely.
mk_plan "$TMP/server-inline-fw.json" "$(printf '[%s,%s,%s]' \
  '{"address":"hcloud_server.git_data","type":"hcloud_server","change":{"actions":["create"],"before":null,"after":{"firewall_ids":[111]}}}' \
  "$(entailed_four)" "$(rest_thirteen)")"
check "inline firewall_ids on the server => ABORT" 1 "firewall_ids inline" "$TMP/server-inline-fw.json"

# A future terraform verb on an out-of-scope address must be REFUSED, not classified inert.
mk_plan "$TMP/novel-verb.json" "$(printf '[%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" "$(rest_thirteen)" \
  "$(rc_entry 'hcloud_volume.workspaces' 'hcloud_volume' '["evict"]')")"
check "a FUTURE terraform verb on an out-of-scope address => ABORT" 1 "out-of-scope" "$TMP/novel-verb.json"

# ── REJECT: reboot-forcing in-place update ────────────────────────────────────────
# A BACKSTOP here, not live coverage, and the suite says so rather than over-claiming.
# hcloud_firewall_attachment.git_data is `server_ids = [hcloud_server.git_data.id]` — a
# direct singleton — unlike the web fleet's `[for h in hcloud_server.web : h.id]`. So no
# other hcloud_server can enter this gate's transitive closure and this arm cannot fire
# on a real plan today. It is kept because the closure is a property of today's HCL, not
# a guarantee.
mk_plan "$TMP/reboot.json" "$(printf '[%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" "$(rest_thirteen)" \
  "$(rc_update 'hcloud_server.web["web-1"]' 'hcloud_server' \
      '{"placement_group_id":1,"server_type":"cpx22"}' \
      '{"placement_group_id":2,"server_type":"cpx22"}')")"
check "a reboot-forcing update on a LIVE host => ABORT" 1 "reboot" "$TMP/reboot.json"

# Scope pin: the reboot arm covers the two power-cycling attributes, not "any update".
# A blanket-ban implementation passes the abort check above and fails this one.
mk_plan "$TMP/benign-update.json" "$(printf '[%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" "$(rest_thirteen)" \
  "$(rc_update 'hcloud_server.web["web-1"]' 'hcloud_server' \
      '{"placement_group_id":1,"server_type":"cpx22","name":"old"}' \
      '{"placement_group_id":1,"server_type":"cpx22","name":"new"}')")"
out="$(git_data_host_birth_gate "$TMP/benign-update.json" 2>&1)"
if [[ "$out" != *"reboot-forcing"* ]]; then
  pass "the reboot arm stays silent on a non-reboot delta (scoped to the 2 power-cycling attributes)"
else
  fail "the reboot arm fired on a name-only change — it is a blanket update ban, not a reboot check" "n/a" "$out"
fi

# ── REJECT: out-of-scope ──────────────────────────────────────────────────────────
mk_plan "$TMP/oos.json" "$(printf '[%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" "$(rest_thirteen)" \
  "$(rc_update 'cloudflare_ruleset.seo_page_redirects' 'cloudflare_ruleset' \
      '{"rules":[{"a":1},{"b":2}]}' '{"rules":[{"a":1}]}')")"
check "a cloudflare_ruleset change riding the birth => ABORT" 1 "out-of-scope" "$TMP/oos.json"
check "the out-of-scope ABORT names the offending address" 1 "seo_page_redirects" "$TMP/oos.json"

# EXACT membership, not substring. `contains`/`inside` would let a bare
# `hcloud_volume.git_data` satisfy the `hcloud_volume.git_data_luks` member and vice
# versa — the two volumes are the plaintext store and the encrypted store, so conflating
# them is precisely the confusion the gate must not make.
mk_plan "$TMP/substring.json" "$(printf '[%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" "$(rest_thirteen)" \
  "$(rc_entry 'hcloud_volume.git_data_luks_backup' 'hcloud_volume' '["create"]')")"
check "an address that SUBSTRING-matches an allow member => ABORT" 1 "out-of-scope" "$TMP/substring.json"
check "the substring ABORT names the impostor address" 1 "git_data_luks_backup" "$TMP/substring.json"

# ── REJECT: the backstop arms ─────────────────────────────────────────────────────
# Neither is reachable from the -target set today — both are stated as backstops rather
# than over-claimed as live coverage.
#
# The heartbeat pair belongs to #6548/#6982: the FEEDER already shipped (it is
# web-host-resident), so creating a monitor this route cannot arm reproduces the #6537
# fed-but-paused shape — a green dashboard measuring nothing.
mk_plan "$TMP/heartbeat.json" "$(printf '[%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" "$(rest_thirteen)" \
  "$(rc_entry 'betteruptime_heartbeat.git_data_prd' 'betteruptime_heartbeat' '["create"]')")"
check "creating the git-data HEARTBEAT => ABORT" 1 "out-of-scope" "$TMP/heartbeat.json"

# terraform_data.git_data_probe_install is the load-bearing one. It SSH-provisions
# web-1 — the live serving host — and `remote-exec` runs at APPLY, not at plan. It also
# sits in the per-merge apply's -target list on a step with no destroy-guard. If someone
# ever adds this address to the birth set by hand, this arm is what stops a birth
# dispatch from root-SSHing production.
mk_plan "$TMP/probe.json" "$(printf '[%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" "$(rest_thirteen)" \
  "$(rc_entry 'terraform_data.git_data_probe_install' 'terraform_data' '["create"]')")"
check "creating the web-1 SSH PROBE => ABORT" 1 "out-of-scope" "$TMP/probe.json"
check "the probe ABORT names the address" 1 "git_data_probe_install" "$TMP/probe.json"

# ── REJECT: the requirement arm, split by entailment ──────────────────────────────
#
# ENTAILED HALF — creates == 1. Each of these four references hcloud_server.git_data.id,
# so a new server implies a new instance by construction. Their absence means the
# -target set is mis-scoped, and each absence has a distinct catastrophic shape.
mk_plan "$TMP/no-nic.json" "$(printf '[%s,%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.git_data' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.git_data_luks' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_fw_attach '["create"]' '[9001]')" \
  "$(rest_thirteen)")"
check "the server with NO private NIC => ABORT (#6416)" 1 "hcloud_server_network.git_data" "$TMP/no-nic.json"

mk_plan "$TMP/no-fw-attach.json" "$(printf '[%s,%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(rc_entry 'hcloud_server_network.git_data' 'hcloud_server_network' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.git_data' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.git_data_luks' 'hcloud_volume_attachment' '["create"]')" \
  "$(rest_thirteen)")"
check "the server with NO firewall attachment => ABORT (public exposure)" 1 "hcloud_firewall_attachment.git_data" "$TMP/no-fw-attach.json"
check "the firewall-attachment abort explains the exposure" 1 "public" "$TMP/no-fw-attach.json"

mk_plan "$TMP/no-luks-attach.json" "$(printf '[%s,%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(rc_entry 'hcloud_server_network.git_data' 'hcloud_server_network' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.git_data' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_fw_attach '["create"]' '[9001]')" \
  "$(rest_thirteen)")"
check "the server with NO LUKS volume attachment => ABORT" 1 "hcloud_volume_attachment.git_data_luks" "$TMP/no-luks-attach.json"

# An entailed member that UPDATES instead of creating. A new server gets a new NIC by
# construction, so an update here means the plan is not the birth it claims to be — and
# a presence-only check would accept it.
mk_plan "$TMP/nic-updates.json" "$(printf '[%s,%s,%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(rc_update 'hcloud_server_network.git_data' 'hcloud_server_network' '{"ip":"10.0.1.20"}' '{"ip":"10.0.1.21"}')" \
  "$(rc_entry 'hcloud_volume_attachment.git_data' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_entry 'hcloud_volume_attachment.git_data_luks' 'hcloud_volume_attachment' '["create"]')" \
  "$(rc_fw_attach '["create"]' '[9001]')" \
  "$(rest_thirteen)")"
check "an entailed member that UPDATES instead of creating => ABORT" 1 "hcloud_server_network.git_data" "$TMP/nic-updates.json"

# PRESENCE HALF — the other thirteen must APPEAR with actions in {create, no-op}. This
# still catches a typo'd -target (an address absent from the closure fails presence) and
# still satisfies AC4's intent, without poisoning the retry.
mk_plan "$TMP/minimal.json" "$(minimal_changes)"
check "a plan missing the presence members => ABORT" 1 "not present in the plan" "$TMP/minimal.json"

# AC4 specifically: each of the three SSH private-key secrets. Omit one and its private
# half lives only in tfstate while the host's authorized_keys holds the public half — the
# host accepts a key nobody can present.
for k in transport provision remove; do
  addr="doppler_secret.git_${k}_ssh_private_key"
  mk_plan "$TMP/no-$k-secret.json" "$(printf '[%s,%s,%s]' \
    "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
    "$(entailed_four)" \
    "$(rest_thirteen_except "$addr")")"
  check "a birth omitting ${addr} => ABORT (AC4)" 1 "$addr" "$TMP/no-$k-secret.json"
done

# Fixture self-check: rest_thirteen_except must actually REMOVE one member, else every
# assertion in the loop above is vacuous — the same class of silent-no-op the jq rewrite
# was chosen to avoid, so it is asserted rather than assumed.
n_all=$(printf '[%s]' "$(rest_thirteen)" | jq 'length')
n_less=$(printf '[%s]' "$(rest_thirteen_except 'doppler_secret.git_remove_ssh_private_key')" | jq 'length')
if [[ "$n_all" -eq 13 && "$n_less" -eq 12 ]]; then
  pass "fixture self-check: rest_thirteen is 13 members and _except removes exactly one"
else
  fail "fixture self-check failed — the AC4 omission cases would be vacuous" "n/a" "all=$n_all less=$n_less"
fi

# A presence member that DESTROYS must be caught by a destroy-class arm, never satisfy
# "present". Built by jq mutation of the actions array for the same reason as above.
mk_plan "$TMP/presence-delete.json" "$(printf '[%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" \
  "$(printf '[%s]' "$(rest_thirteen)" \
     | jq -c '[.[] | if .address == "random_password.git_data_luks" then .change.actions = ["delete"] else . end]' \
     | sed 's/^\[//; s/\]$//')")"
check "a presence member that DELETES => ABORT via a destroy-class arm" 1 "LUKS PASSPHRASE" "$TMP/presence-delete.json"

# ── REJECT: the degenerate producer shapes no fixture instantiated ────────────────
#
# Found by an INDEPENDENT vacuity review, not by this battery — every mutation here
# perturbs bytes the arms already read, so a fixture-space gap is structurally invisible
# to it. Each of these MEASURED rc=0 PASS before the fix.

# An EMPTY actions array makes an entry invisible to every arm at once: `[] | any(...)` is
# false so the out-of-scope and firewall selects skip it, and `[] | index("delete")` is
# null so the destroy select skips it. Here it hides a DESTROY of the singleton behind
# app.soleur.ai riding the birth.
mk_plan "$TMP/empty-actions.json" "$(printf '[%s,%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" "$(rest_thirteen)" \
  '{"address":"hcloud_server.web[\"web-1\"]","type":"hcloud_server","change":{"actions":[],"before":{"id":9},"after":null}}')"
check "an EMPTY actions array hiding a destroy => fail-closed ABORT" 1 "unclassifiable" "$TMP/empty-actions.json"

# The same shape on a REQUIRED member: jq's `all` over an empty array is `true`, so it
# satisfied the presence assertion — a fail-OPEN default at the one place the gate is a
# quantifier.
mk_plan "$TMP/empty-actions-presence.json" "$(printf '[%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" \
  "$(printf '[%s]' "$(rest_thirteen)" | jq -c '[.[] | if .address == "doppler_secret.git_data_luks_key" then .change.actions = [] else . end]' | sed 's/^\[//; s/\]$//')")"
check "an EMPTY actions array on a REQUIRED member => fail-closed ABORT" 1 "unclassifiable" "$TMP/empty-actions-presence.json"

# A `no-op` firewall carrying inbound rules. This is the PARTIAL-BIRTH RESUME shape — the
# documented must-pass recovery path — so scoping the content arm to create|update left
# the headline promise unchecked on the one plan an operator is told to re-run.
mk_plan "$TMP/fw-noop-with-rules.json" "$(printf '[%s,%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(entailed_four)" \
  "$(printf '[%s]' "$(rest_thirteen)" | jq -c '[.[] | if .address == "hcloud_firewall.git_data" then (.change.actions = ["no-op"] | .change.after = {"rule":[{"direction":"in","port":"22","source_ips":["0.0.0.0/0"]}]}) else . end]' | sed 's/^\[//; s/\]$//')")"
check "a NO-OP firewall carrying inbound rules => ABORT" 1 "FIREWALL CONTENT" "$TMP/fw-noop-with-rules.json"

# ── REJECT: fail-closed input (delegated to the preamble) ─────────────────────────
printf 'not json at all\n' > "$TMP/garbage.json"
check "unparseable plan JSON => fail-closed ABORT" 1 "unparseable" "$TMP/garbage.json"
check "missing plan file => fail-closed ABORT" 1 "not found" "$TMP/nonexistent.json"
mk_plan "$TMP/nullrc.json" 'null'
check "null resource_changes => fail-closed ABORT" 1 "no resource_changes array" "$TMP/nullrc.json"

mk_plan "$TMP/noactions.json" "$(printf '[%s,%s]' \
  "$(rc_entry 'hcloud_server.git_data' 'hcloud_server' '["create"]')" \
  "$(rc_noactions 'hcloud_volume.git_data' 'hcloud_volume')")"
check "an entry with no .change.actions => fail-closed ABORT" 1 "unclassifiable" "$TMP/noactions.json"
check "the unclassifiable ABORT names the offending address" 1 "hcloud_volume.git_data" "$TMP/noactions.json"

# The telemetry line must precede the verdict, so an operator reading a truncated log
# still sees the counters that produced the decision.
out="$(git_data_host_birth_gate "$TMP/happy.json" 2>&1)"
if [[ "$out" == *"host_creates="*"destroys="*"out_of_scope="* ]]; then
  pass "the gate emits a counter telemetry line before its verdict"
else
  fail "expected a telemetry line naming the counters" "n/a" "$out"
fi

# ── MUTATION SECTION ──────────────────────────────────────────────────────────────
# THE ARMS ARE NOT INDEPENDENT, and pretending otherwise is how a mutation battery lies.
# The out-of-scope allow-set already refuses a wrong-host create, a second host, and any
# update to a live one — it strictly subsumes the identity, cardinality and reboot arms.
# The naive contract "neuter arm X and the bad plan sails through" is therefore FALSE for
# those three by construction, and a battery written that way reports them dead when they
# are merely layered.
#
#   SOLE-GUARD  neuter it and the plan is ACCEPTED (rc 0).
#   LAYERED     neuter it and the plan is still REJECTED (rc 1), but its own signature
#               disappears and a DIFFERENT arm's appears — proving both that this arm
#               owns the rejection and that removing it does not open the door.
#
# Both first require the mutation to change the file at all. `sed` exits 0 when it matches
# nothing, so without that floor a mutation aimed at a guard that does not exist emits a
# byte-identical copy, the bad plan sails through the UN-neutered gate, and the battery
# reports the arm load-bearing for the weakest possible reason. That is not hypothetical —
# it is how a 35/35 battery in this tree hid seven P1s.
printf '\nmutation checks (each neuters one guard; the arm it protects must flip)\n'

# Both contracts now live in tests/scripts/lib/gate-suite-harness.sh (#6997) — written once
# rather than once per gate suite, because each has four moving parts and every one of them
# can be got subtly wrong in a way that reports a pass. These wrappers preserve THIS suite's
# argument order (plan before own/fallback), which differs from the shared signature.
mutate_and_check() {
  gate_mutate_and_check "$1" "$2" git_data_host_birth_gate "$3"
}

mutate_layered() {
  gate_mutate_layered "$1" "$2" "$4" "$5" git_data_host_birth_gate "$3"
}


# SOLE-GUARD: a REPLACE of the host itself. This fixture — not the volume-destroy one —
# is where the generic destroy arm is genuinely the last line, and finding that out was
# the point of measuring rather than reasoning.
#
# On the volume-destroy fixture the destroy arm is LAYERED behind the named
# volume-destroy arm, which now runs before it. On a REPLACE the plan is
# `["delete","create"]` on hcloud_server.git_data: `creates` is 1 (index("create") is
# satisfied), identity matches, the firewall and passphrase arms see nothing, the address
# is in the allow-set so out_of_scope is 0, all four entailed members create and all
# thirteen presence members create. Every other arm is silent. Neuter the destroy arm and
# the gate PASSES a plan that destroys the live store and rebuilds it empty — which is
# precisely the difference between a birth and a replace that a count check cannot see.
mutate_and_check "destroy guard" \
  's/if \[\[ "\$destroys" -ne 0 \]\]; then/if false; then/' "$TMP/replace.json"

# The named-volume/generic-destroy relationship is asserted from the OTHER direction, by
# the "named volume-destroy guard" LAYERED mutation at the end of this section. Stating it
# twice is not more coverage: on the volume fixture the named arm runs first and the
# generic arm never fires, so neutering the generic arm changes nothing and a mutation
# written that way asserts an ordering that does not exist. The layered control caught
# exactly that, which is the whole reason it requires the unmutated gate to reject via the
# arm being neutered.

# SOLE-GUARD: the cloudflare ruleset is out of scope and nothing else objects to it.
mutate_and_check "out-of-scope guard" \
  's/if \[\[ "\$out_of_scope" -ne 0 \]\]; then/if false; then/' "$TMP/oos.json"

# SOLE-GUARD: the requirement arm. No prohibition can catch a MISSING member — that is
# the entire reason it exists — so neutering it must let the #6416 plan through.
mutate_and_check "entailed-creates guard" \
  's/if \[\[ "\$required_creates" -ne 1 \]\]; then/if false; then/' "$TMP/no-nic.json"

# SOLE-GUARD: the presence half, mutated independently of the entailed half. A battery
# that mutated only one would report the whole requirement arm covered.
mutate_and_check "presence guard" \
  's/if \[\[ "\$present" -eq 0 \]\]; then/if false; then/' "$TMP/minimal.json"

# SOLE-GUARD: a firewall CREATED carrying inbound rules. The firewall is in the allow-set
# (it is upstream of its own attachment), and a `create` satisfies the presence arm, so
# nothing else in the gate looks at its rule contents. Neutering this accepts a birth that
# stands the store up with an inbound rule already open — the publicly-reachable-store
# shape, which every other counter in the plan reads as correct.
mutate_and_check "firewall-content guard" \
  's/if \[\[ "\$firewall_rules" -ne 0 \]\]; then/if false; then/' "$TMP/fw-born-with-rules.json"

# LAYERED for the UPDATE shape, and this is a measured correction rather than a design
# claim: an `update` on the firewall fails the presence arm too, because presence demands
# actions be a subset of {create, no-op}. So the update path has a backstop the create
# path does not. The content arm still owns the message — "not present in the plan" would
# send an operator hunting a mis-scoped -target instead of an open inbound rule.
mutate_layered "firewall-content guard (update shape, behind presence)" \
  's/if \[\[ "\$firewall_rules" -ne 0 \]\]; then/if false; then/' \
  "$TMP/fw-rules.json" "FIREWALL CONTENT" "not present in the plan"

# LAYERED, and this classification was CORRECTED by measurement on a realistic fixture.
#
# An earlier revision reported SOLE-GUARD — but only because its fixture APPENDED a second
# `random_password.git_data_luks` entry alongside the `["create"]` one already in
# rest_thirteen, a document terraform cannot emit. On a single-entry plan an `update` also
# fails the presence arm (which demands actions ⊆ {create, no-op}), so the passphrase arm
# is the backstop's message, not its refusal. It absolutely earns its place — "permanently
# unopenable" versus "not present in the plan" is the difference between an operator
# re-dispatching and an operator hunting a mis-scoped -target — but the contract is LAYERED.
mutate_layered "luks-passphrase guard" \
  's/if \[\[ "\$luks_passphrase_touched" -ne 0 \]\]; then/if false; then/' \
  "$TMP/luks-pw-update.json" "LUKS PASSPHRASE" "not present in the plan"

# SOLE-GUARD: the orphaned-mint arm. A passphrase CREATE satisfies presence and every
# verb filter, so nothing else in the gate objects. This is the arm review added.
mutate_and_check "orphaned-passphrase-mint guard" \
  's/if \[\[ "\$luks_orphan_mint" -ne 0 \]\]; then/if false; then/' "$TMP/orphan-mint.json"

# SOLE-GUARD: the firewall-attachment outcome arm. With the attachment omitted, no other
# arm requires it — it is downstream of the server, so -target does not auto-pull it, and
# the allow-set only PERMITS it to change.
mutate_and_check "firewall-attachment outcome guard" \
  's/if \[\[ "\$fw_attach_ok" -eq 0 \]\]; then/if false; then/' "$TMP/fw-attach-missing.json"

# SOLE-GUARD: the firewall-identity arm.
mutate_and_check "firewall-identity guard" \
  's/if \[\[ "\$fw_identity_bad" -ne 0 \]\]; then/if false; then/' "$TMP/fw-wrong-identity.json"

# SOLE-GUARD: the undisclosed-rule-set arm.
mutate_and_check "firewall-unreadable guard" \
  's/if \[\[ "\$firewall_unreadable" -ne 0 \]\]; then/if false; then/' "$TMP/fw-rules-unknown.json"

# SOLE-GUARD: inline firewall_ids on the server.
mutate_and_check "server-inline-firewall guard" \
  's/if \[\[ "\$server_inline_firewalls" -ne 0 \]\]; then/if false; then/' "$TMP/server-inline-fw.json"

# LAYERED: the volume-update arm — the one arm the first revision of this battery never
# mutated at all, while the header claimed "each is mutation-proven". On a single-entry
# plan an `update` also fails presence, so it owns the message and presence is the backstop.
mutate_layered "volume-update guard" \
  's/if \[\[ "\$volume_updates" -ne 0 \]\]; then/if false; then/' \
  "$TMP/vol-resize.json" "VOLUME UPDATE" "not present in the plan"

# LAYERED: the preamble's actions-shape check, reached through this gate.
#
# Measured, and the measurement contradicted the first classification. Neutering it does
# NOT accept the plan: `null | any(...)` raises in jq, so the out_of_scope filter fails,
# that counter comes back empty, and plan_gate_assert_numeric refuses it. So the shape
# check is layered behind the numeric floor — but only by ACCIDENT of which jq builtin
# happens to raise on null. `null | index("delete")` returns null quite happily, so the
# destroy counter reads a no-actions entry as zero and would sail through.
#
# That is exactly why the explicit shape check exists rather than relying on the floor:
# the backstop here is one jq expression away from disappearing, and what it would then
# hide is a destroy the gate cannot see.
mutate_layered "actions-shape guard (via preamble)" \
  's/^  plan_gate_assert_classifiable .*/  :/' \
  "$TMP/noactions.json" "unclassifiable" "counter parse failed"

# LAYERED: a create of web-1 is both an identity mismatch and out of scope.
mutate_layered "identity guard" \
  's/if \[\[ "\$created_addr" != "\$want_addr" \]\]; then/if false; then/' \
  "$TMP/wrong-host.json" "IDENTITY MISMATCH" "out-of-scope"

# LAYERED: a second host create is both a cardinality breach and out of scope.
mutate_layered "cardinality guard" \
  's/if \[\[ "\$creates" -ne 1 \]\]; then/if false; then/' \
  "$TMP/two.json" "expected exactly 1" "out-of-scope"

# LAYERED: a web-1 power-cycle is both a reboot and an out-of-scope change.
mutate_layered "reboot guard" \
  's/if \[\[ "\$reboot_updates" -ne 0 \]\]; then/if false; then/' \
  "$TMP/reboot.json" "reboot-forcing" "out-of-scope"

# LAYERED: the named volume-destroy arm owns the MESSAGE; the generic destroy arm is the
# backstop. Proving this is what stops the named arm being quietly deleted as redundant.
mutate_layered "named volume-destroy guard" \
  's/if \[\[ "\$volume_destroys" -ne 0 \]\]; then/if false; then/' \
  "$TMP/destroy-vol.json" "DATA VOLUME" "destroy"




# ANTI-VACUITY FLOOR (#6997). Nothing else asserts that the assertions RAN. Every
# non-vacuity mechanism in this suite lives inside a helper — the `cmp -s` mutation floors,
# the layered contract's unmutated control, the preamble-distinctive anchors — so deleting
# the CALLS to those helpers silences all of them at once while the suite still exits 0,
# because the only merge gate is the `fails -eq 0` expression below and CI reads only the
# exit code. Measured: removing one arm block took a sibling suite from 13 assertions to 8,
# still exit 0.
#
# DELIBERATELY SELF-CONTAINED — bash builtins and this suite's own counters only, no
# harness function. The first version called a helper from gate-suite-harness.sh and the
# harness `source` lived INSIDE the arm block, so deleting the arms also undefined the
# floor: it exited 127 under `set -uo pipefail`, recorded nothing, and the suite passed. A
# floor that depends on the thing it guards is not a floor.
#
# A FLOOR, NOT EQUALITY — the count is developer-incremented, so `-eq` would redden the
# suite on every legitimately-added assertion and train people to bump it unread.
_ran=$((passes + fails))
if [[ "$_ran" -lt 76 ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 76. Arms were deleted, skipped, or the suite exited early.\n' "$_ran"
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor 76)\n' "$_ran"
fi

printf '\n=== %d passed, %d failed ===\n\n' "$passes" "$fails"
[[ "$fails" -eq 0 ]]
