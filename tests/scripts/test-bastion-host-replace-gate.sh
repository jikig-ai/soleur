#!/usr/bin/env bash
# Mutation matrix for tests/scripts/lib/bastion-host-replace-gate.sh (Guard 1, #12879; ADR-327 step 2b).
# The workflow's wiring (step order, if: strings, the plan chain, the -replace branch) is pinned by
# executing its steps in tests/scripts/test-bastion-host-replace-workflow.sh (Q-R4), not by grep here.
#
# PROPERTY. A bastion-host-replace apply runs only on a plan that matches one of two arms:
#   replace   the plan destroys exactly the one live soleur-bastion whose id the dispatch pin, the
#             Hetzner API and the plan's before.id agree on (compared as strings), recreates it,
#             recreates its NIC at 10.0.1.70 and re-binds its zero-rule firewall attachment by id;
#   recovery  (pin `none`) the plan creates the server only when neither state nor the API holds any
#             soleur-bastion.
# On both arms an attachment update is graded on its BEFORE (Q-R1): it may unbind nothing but the pinned
# server (replace) or nothing at all (recovery), and no label selector; a partial replace's resume shapes
# (update from [] or null, or a bare create) pass on the replace arm (Q-R2).
# In both arms the host key and the firewall are exactly no-op and nothing outside
# bastion-resources.txt changes.
#
# Fixtures are synthesized (ADR-322) with the real types: a STRING before.id in the plan, a NUMERIC id
# in the Hetzner document, and the attachment's after.server_ids in both renderings the gate accepts:
# [null] with after_unknown [true] (a known one-element set with an unknown element; the canonical
# fixture) and wholly unknown, after_unknown true (the shape a captured birth plan shows; row 1b). Every
# RED row names the ABORT substring it expects; the substring is matched against ABORT lines only.
#
# ANTI-VACUITY. `cases` moves at every assertion; H1 re-runs every RED row against a gate replaced by
# `return 0` and requires each to flip; every helper that owns a verdict (row, irow, nrow, scratch_row,
# gmrow, gprow, the H1 predicate) is driven once with a must-fail input and must report the failure
# (CONTROLS, below); the floors and passes+fails==cases are reported by printf + exit 1, never through
# fail() (ADR-193).
#
# Run: bash tests/scripts/test-bastion-host-replace-gate.sh
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
GATE="${ROOT}/tests/scripts/lib/bastion-host-replace-gate.sh"
COMMON="${ROOT}/tests/scripts/lib/bastion-gate-common.sh"

cases=0
passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL %s\n' "$1"; [[ -z "${2:-}" ]] || printf '       %s\n' "$(head -c 900 <<<"$2")"; }

# INSTRUMENT SELF-TEST (ADR-193): both helpers must move their own counter and only it.
pass "instrument self-test (pass)" >/dev/null
fail "instrument self-test (fail)" >/dev/null
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf 'FATAL: INSTRUMENT BROKEN (passes=%d fails=%d after one call each)\n' "$passes" "$fails" >&2
  exit 2
fi
passes=0
fails=0

harness() { printf 'HARNESS: %s\n' "$1" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || harness "jq is required"
command -v python3 >/dev/null 2>&1 || harness "python3 is required"
WORK="$(mktemp -d "${TMPDIR}/bhrg.XXXXXXXX")" || harness "mktemp failed"
case "$WORK" in /*/bhrg.*) : ;; *) harness "mktemp returned '$WORK'" ;; esac
trap 'rm -rf "${WORK:?}"' EXIT
# Every gate output any row captures is appended here, for the key-marker row at the end.
ALL_OUT="$WORK/all-gate-output.txt"; : > "$ALL_OUT"

GATE_PRESENT=0
if [[ -f "$GATE" ]]; then
  # shellcheck source=tests/scripts/lib/bastion-host-replace-gate.sh
  source "$GATE"
  declare -F bastion_host_replace_gate >/dev/null && declare -F bastion_replace_identity >/dev/null && GATE_PRESENT=1
fi
# RED until the gate exists: every row then fails on the missing function, never skips.
if [[ "$GATE_PRESENT" != 1 ]]; then
  bastion_host_replace_gate() { echo "bastion_host_replace_gate: NOT IMPLEMENTED"; return 99; }
  bastion_replace_identity() { echo "bastion_replace_identity: NOT IMPLEMENTED"; return 99; }
  bastion_replace_next_dispatch() { echo "bastion_replace_next_dispatch: NOT IMPLEMENTED"; return 99; }
fi
GATE_FN=bastion_host_replace_gate

PIN=61234567
OTHER=70000000
MARK=SYNTHETIC-KEY-MARKER
# ── The canonical replace plan (string before.id, numeric NIC/attachment ids, every key field marked) ──
cat > "$WORK/replace.json" <<JSON
{
  "format_version": "1.2",
  "prior_state": {"values": {"root_module": {"resources": [
    {"address": "tls_private_key.bastion_host_ssh", "type": "tls_private_key",
     "values": {"algorithm": "ED25519", "private_key_openssh": "${MARK}-openssh", "private_key_pem": "${MARK}-pem",
                "private_key_pem_pkcs8": "${MARK}-pkcs8", "public_key_openssh": "ssh-ed25519 AAAA"}},
    {"address": "hcloud_server.bastion", "type": "hcloud_server",
     "values": {"id": "${PIN}", "name": "soleur-bastion", "server_type": "cx23"}}
  ]}}},
  "resource_changes": [
    {"address": "tls_private_key.bastion_host_ssh", "type": "tls_private_key",
     "change": {"actions": ["no-op"],
                "before": {"algorithm": "ED25519", "private_key_openssh": "${MARK}-openssh", "private_key_pem": "${MARK}-pem", "private_key_pem_pkcs8": "${MARK}-pkcs8"},
                "after": {"algorithm": "ED25519", "private_key_openssh": "${MARK}-openssh", "private_key_pem": "${MARK}-pem", "private_key_pem_pkcs8": "${MARK}-pkcs8"},
                "after_unknown": {}}},
    {"address": "hcloud_firewall.bastion", "type": "hcloud_firewall",
     "change": {"actions": ["no-op"],
                "before": {"id": "9001", "name": "soleur-bastion", "rule": [], "apply_to": [], "labels": {"role": "bastion"}},
                "after": {"id": "9001", "name": "soleur-bastion", "rule": [], "apply_to": [], "labels": {"role": "bastion"}},
                "after_unknown": {}}},
    {"address": "hcloud_server.bastion", "type": "hcloud_server",
     "change": {"actions": ["delete", "create"],
                "before": {"id": "${PIN}", "name": "soleur-bastion", "server_type": "cx23", "labels": {"app": "soleur-web-platform", "role": "bastion"}, "firewall_ids": []},
                "after": {"name": "soleur-bastion", "server_type": "cx23", "labels": {"app": "soleur-web-platform", "role": "bastion"}, "firewall_ids": null},
                "after_unknown": {"id": true, "ipv4_address": true}}},
    {"address": "hcloud_server_network.bastion", "type": "hcloud_server_network",
     "change": {"actions": ["delete", "create"],
                "before": {"id": "${PIN}-5001", "server_id": ${PIN}, "ip": "10.0.1.70", "subnet_id": "5001-10.0.1.0/24"},
                "after": {"ip": "10.0.1.70", "subnet_id": "5001-10.0.1.0/24"},
                "after_unknown": {"id": true, "server_id": true}}},
    {"address": "hcloud_firewall_attachment.bastion", "type": "hcloud_firewall_attachment",
     "change": {"actions": ["update"],
                "before": {"id": "9001", "firewall_id": 9001, "server_ids": [${PIN}], "label_selectors": null},
                "after": {"id": "9001", "firewall_id": 9001, "server_ids": [null], "label_selectors": null},
                "after_unknown": {"server_ids": [true]}}}
  ],
  "configuration": {"root_module": {"resources": [
    {"address": "hcloud_server.bastion", "expressions": {"name": {"constant_value": "soleur-bastion"}}},
    {"address": "hcloud_firewall_attachment.bastion", "expressions": {
      "firewall_id": {"references": ["hcloud_firewall.bastion.id", "hcloud_firewall.bastion"]},
      "server_ids": {"references": ["hcloud_server.bastion.id", "hcloud_server.bastion"]}}}
  ]}}
}
JSON
jq -e '.resource_changes | length == 5' "$WORK/replace.json" >/dev/null || harness "replace fixture is not valid JSON"
# ── The canonical recovery plan: no server in state, a bare create, the attachment re-bound ──
jq '.prior_state.values.root_module.resources |= map(select(.address != "hcloud_server.bastion"))
  | .resource_changes |= map(
      if .address == "hcloud_server.bastion" then .change.actions = ["create"] | .change.before = null
      elif .address == "hcloud_server_network.bastion" then .change.actions = ["create"] | .change.before = null
      elif .address == "hcloud_firewall_attachment.bastion" then .change.before.server_ids = []
      else . end)' "$WORK/replace.json" > "$WORK/recovery.json" || harness "recovery fixture edit failed"
# ── The Hetzner documents ──
printf '{"servers":[{"id":%s,"name":"soleur-bastion","status":"running","labels":{"app":"soleur-web-platform","role":"bastion"}}],"meta":{"pagination":{"total_entries":1}}}\n' "$PIN" > "$WORK/api1.json"
printf '{"servers":[],"meta":{"pagination":{"total_entries":0}}}\n' > "$WORK/api0.json"

# FIXTURE TYPE SELF-CHECK: the real types, or the tostring rows prove nothing.
cases=$((cases + 1))
if jq -e '(.prior_state.values.root_module.resources[] | select(.address == "hcloud_server.bastion") | .values.id | type) == "string"
   and ([.resource_changes[] | select(.address == "hcloud_server.bastion") | .change.before.id | type] == ["string"])
   and ([.resource_changes[] | select(.address == "hcloud_firewall_attachment.bastion") | .change.before.server_ids | map(type)] == [["number"]])
   and ([.resource_changes[] | select(.address == "hcloud_firewall_attachment.bastion") | .change.after.server_ids] == [[null]])
   and ([.resource_changes[] | select(.address == "hcloud_firewall_attachment.bastion") | .change.after_unknown.server_ids] == [[true]])' "$WORK/replace.json" >/dev/null \
   && jq -e '(.servers[0].id | type) == "number"' "$WORK/api1.json" >/dev/null; then
  pass "fixture types: string before.id and prior_state id, numeric API id, [<number>] before.server_ids, [null]/[true] after"
else
  fail "fixture types: string before.id and prior_state id, numeric API id, [<number>] before.server_ids, [null]/[true] after"
fi

# mk runs inside $(...), so a shell counter would never persist: every fixture gets its own mktemp name,
# or a stored path (a row reused by a mutation row below) would be overwritten by the next mk.
mk() { # <base-file> <jq-edit> -> path of the mutated document
  local f
  f="$(mktemp "$WORK/f.XXXXXXXX")" || harness "mktemp failed"
  jq "$2" "$1" > "$f" || harness "fixture edit failed: $2"
  printf '%s' "$f"
}
R="$WORK/replace.json"; V="$WORK/recovery.json"; A1="$WORK/api1.json"; A0="$WORK/api0.json"
SET='def set($a; f): .resource_changes |= map(if .address == $a then f else . end);'
DROP='def drop($a): .resource_changes |= map(select(.address != $a));'
ADD='def add(r): .resource_changes += [r];'

RED_ROWS=()
# row <label> <PASS|RED> <plan-file> <pin> <api-file> [message-substring]
row() {
  local label="$1" want="$2" plan="$3" pin="$4" api="$5" msg="${6:-}" out rc abort
  cases=$((cases + 1))
  out="$("$GATE_FN" "$plan" "$pin" "$api" 2>&1)"; rc=$?
  printf '%s\n' "$out" >> "$ALL_OUT"
  abort="$(awk '/ABORT/' <<<"$out")"
  [[ "$want" == RED ]] && RED_ROWS+=("$label|$plan|$pin|$api|$msg")
  if [[ "$want" == PASS ]]; then
    if [[ "$rc" -eq 0 && "$out" == *"PASS"* ]]; then pass "$label"; else fail "$label (want PASS, rc=$rc)" "$out"; fi
  else
    if [[ "$rc" -eq 1 && -n "$abort" && ( -z "$msg" || "$abort" == *"$msg"* ) ]]; then pass "$label"; else fail "$label (want RED rc=1${msg:+ with an ABORT line naming '$msg'}, rc=$rc)" "$out"; fi
  fi
}

ATT_UNBOUND="hcloud_firewall_attachment.bastion does not end this plan binding"
echo "Guard 1 matrix"
row "1: the canonical replace ([null]/[true] attachment, API id = pin = before.id) passes" PASS "$R" "$PIN" "$A1"
row "1b: the attachment's server_ids wholly unknown (true, after omitted) passes" PASS \
  "$(mk "$R" "$SET"' set("hcloud_firewall_attachment.bastion"; .change.after |= del(.server_ids) | .change.after_unknown.server_ids = true)')" "$PIN" "$A1"
row "1c: [true] with after.server_ids omitted (an inconsistent shape)" RED \
  "$(mk "$R" "$SET"' set("hcloud_firewall_attachment.bastion"; .change.after |= del(.server_ids))')" "$PIN" "$A1" "$ATT_UNBOUND"
row "2: the canonical recovery (pin none, API 0, no server in state) passes" PASS "$V" none "$A0"
row "2b: recovery with the attachment created rather than updated passes" PASS \
  "$(mk "$V" "$SET"' set("hcloud_firewall_attachment.bastion"; .change.actions = ["create"] | .change.before = null)')" none "$A0"
row "3: the replace plan with resource_changes reversed passes" PASS "$(mk "$R" '.resource_changes |= reverse')" "$PIN" "$A1"
row "3a: the partial-replace re-dispatch (NIC a bare create at 10.0.1.70) passes" PASS \
  "$(mk "$R" "$SET"' set("hcloud_server_network.bastion"; .change.actions = ["create"] | .change.before = null)')" "$PIN" "$A1"
row "3c: data-source reads and an unrelated no-op beside the replace pass" PASS \
  "$(mk "$R" '.resource_changes += [{address: "data.hcloud_server_type.bastion", type: "hcloud_server_type", change: {actions: ["read"], before: null, after: {}, after_unknown: {}}}, {address: "hcloud_network.main", type: "hcloud_network", change: {actions: ["no-op"], before: {}, after: {}, after_unknown: {}}}]')" "$PIN" "$A1"
row "3b: the attachment no-op (still bound to the deleted id)" RED \
  "$(mk "$R" "$SET"' set("hcloud_firewall_attachment.bastion"; .change.actions = ["no-op"])')" "$PIN" "$A1" "ACTION NOT ALLOWED: hcloud_firewall_attachment.bastion"
row "4: pin != API id (API = before.id)" RED "$R" 11111111 "$A1" "IDENTITY MISMATCH"
row "5: pin = API id != before.id" RED \
  "$(mk "$R" "$SET"' set("hcloud_server.bastion"; .change.before.id = "'"$OTHER"'")')" "$PIN" "$A1" "IDENTITY MISMATCH"
row "5b: pin = before.id, API id differs from both" RED "$R" "$PIN" "$(mk "$A1" ".servers[0].id = $OTHER")" "IDENTITY MISMATCH"
row "6: the API holds two soleur-bastion servers" RED "$R" "$PIN" "$(mk "$A1" '.servers += [.servers[0] | .id = '"$OTHER"']')" "refusing to guess"
row "7: the API server's role label is not bastion" RED "$R" "$PIN" "$(mk "$A1" '.servers[0].labels.role = "web"')" "API ROLE MISMATCH"
row "7b: the API server's name is not exactly soleur-bastion" RED "$R" "$PIN" "$(mk "$A1" '.servers[0].name = "soleur-bastion-old"')" "API NAME MISMATCH"
row "7c: the API server's id is not numeric" RED "$R" "$PIN" "$(mk "$A1" '.servers[0].id = "61234567x"')" "API ID NOT NUMERIC"
row "8: the API document has no .servers key" RED "$R" "$PIN" "$(mk "$A1" 'del(.servers)')" "HETZNER DOCUMENT UNREADABLE"
row "8b: the API document's .servers is not an array" RED "$R" "$PIN" "$(mk "$A1" '.servers = {}')" "HETZNER DOCUMENT UNREADABLE"
printf 'not json' > "$WORK/api-garbage.json"
row "8c: the API document is unparseable" RED "$R" "$PIN" "$WORK/api-garbage.json" "HETZNER DOCUMENT UNREADABLE"
row "8d: the API document is missing" RED "$R" "$PIN" "$WORK/api-nope.json" "HETZNER DOCUMENT UNREADABLE"
row "8e: on the recovery arm, a missing .servers is not zero servers" RED "$V" none "$(mk "$A0" 'del(.servers)')" "HETZNER DOCUMENT UNREADABLE"
row "9: pin none while the API still holds a soleur-bastion (lost state, #13117)" RED "$V" none "$A1" "#13117"
RECOVERY_PRIOR="$(mk "$V" '.prior_state.values.root_module.resources += [{address: "hcloud_server.bastion", type: "hcloud_server", values: {id: "'"$PIN"'"}}]')"
row "10: pin none while prior_state still holds hcloud_server.bastion" RED "$RECOVERY_PRIOR" none "$A0" "RECOVERY REFUSED"
row "10b: pin none while the plan's server carries a before (state holds it)" RED "$(mk "$V" "$SET"' set("hcloud_server.bastion"; .change.actions = ["delete","create"] | .change.before = {id: "'"$PIN"'"})')" none "$A0" "RECOVERY REFUSED"
row "11: pin = id but the server is a bare create (before null)" RED \
  "$(mk "$R" "$SET"' set("hcloud_server.bastion"; .change.actions = ["create"] | .change.before = null)')" "$PIN" "$A1" "IDENTITY MISMATCH"
row "12: the host key is updated (#13116)" RED "$(mk "$R" "$SET"' set("tls_private_key.bastion_host_ssh"; .change.actions = ["update"])')" "$PIN" "$A1" "#13116"
row "12b: the host key is replaced (#13116)" RED "$(mk "$R" "$SET"' set("tls_private_key.bastion_host_ssh"; .change.actions = ["delete","create"])')" "$PIN" "$A1" "#13116"
row "12c: the host key is created (a key regenerated after lost state, #13116)" RED \
  "$(mk "$R" "$SET"' set("tls_private_key.bastion_host_ssh"; .change.actions = ["create"] | .change.before = null)')" "$PIN" "$A1" "#13116"
row "13: the firewall is updated in place (a rule added)" RED \
  "$(mk "$R" "$SET"' set("hcloud_firewall.bastion"; .change.actions = ["update"] | .change.after.rule = [{direction: "in", protocol: "tcp", port: "22", source_ips: ["0.0.0.0/0"]}])')" "$PIN" "$A1" "ACTION NOT ALLOWED: hcloud_firewall.bastion"
row "14: the NIC is planned at another private IP" RED "$(mk "$R" "$SET"' set("hcloud_server_network.bastion"; .change.after.ip = "10.0.1.71")')" "$PIN" "$A1" "does not pin the private IP 10.0.1.70 (planned: 10.0.1.71)"
row "14b: the NIC's IP is unknown at plan time" RED "$(mk "$R" "$SET"' set("hcloud_server_network.bastion"; .change.after.ip = null | .change.after_unknown.ip = true)')" "$PIN" "$A1" "does not pin the private IP 10.0.1.70"
row "15: the attachment binding references another server" RED \
  "$(mk "$R" '.configuration.root_module.resources |= map(if .address == "hcloud_firewall_attachment.bastion" then .expressions.server_ids.references = ["hcloud_server.git_data.id","hcloud_server.git_data"] else . end)')" "$PIN" "$A1" "$ATT_UNBOUND"
row "16: the attachment sets label_selectors" RED \
  "$(mk "$R" "$SET"' set("hcloud_firewall_attachment.bastion"; .change.after.label_selectors = ["role=web"])')" "$PIN" "$A1" "LABEL BINDING: hcloud_firewall_attachment.bastion sets label_selectors"
row "16b: the firewall sets apply_to" RED \
  "$(mk "$R" "$SET"' set("hcloud_firewall.bastion"; .change.after.apply_to = [{label_selector: "role=web", server: null}])')" "$PIN" "$A1" "LABEL BINDING: hcloud_firewall.bastion sets apply_to"
row "17: hcloud_server.web[\"web-1\"] delete-and-create added" RED \
  "$(mk "$R" "$ADD add({address: \"hcloud_server.web[\\\"web-1\\\"]\", type: \"hcloud_server\", change: {actions: [\"delete\",\"create\"], before: {id: \"111\"}, after: {}, after_unknown: {}}})")" "$PIN" "$A1" "out-of-scope"
row "18: a compliant extra no-op, then a second out-of-scope update after it" RED \
  "$(mk "$R" "$ADD add({address: \"hcloud_network.main\", type: \"hcloud_network\", change: {actions: [\"no-op\"], before: {}, after: {}, after_unknown: {}}}) | add({address: \"hcloud_firewall.web\", type: \"hcloud_firewall\", change: {actions: [\"update\"], before: {}, after: {rule: []}, after_unknown: {}}})")" "$PIN" "$A1" "out-of-scope"
row "19: a forget of an out-of-list address" RED \
  "$(mk "$R" "$ADD add({address: \"hcloud_server.git_data\", type: \"hcloud_server\", change: {actions: [\"forget\"], before: {}, after: null, after_unknown: {}}})")" "$PIN" "$A1" "out-of-scope"
row "19b: a forget of a listed address (the NIC)" RED "$(mk "$R" "$SET"' set("hcloud_server_network.bastion"; .change.actions = ["forget"])')" "$PIN" "$A1" "ACTION NOT ALLOWED: hcloud_server_network.bastion"
row "21: the replacement's after.server_type is not cx23" RED "$(mk "$R" "$SET"' set("hcloud_server.bastion"; .change.after.server_type = "cx33")')" "$PIN" "$A1" "REPLACEMENT SHAPE: after.server_type"
row "21b: the replacement's after.name is not soleur-bastion" RED "$(mk "$R" "$SET"' set("hcloud_server.bastion"; .change.after.name = "soleur-bastion-2")')" "$PIN" "$A1" "REPLACEMENT SHAPE: after.name"
row "21c: the replacement's after.labels.role is not bastion" RED "$(mk "$R" "$SET"' set("hcloud_server.bastion"; .change.after.labels.role = "web")')" "$PIN" "$A1" "REPLACEMENT SHAPE: after.labels.role"
row "21d: on the recovery arm, the server's after.server_type is not cx23" RED "$(mk "$V" "$SET"' set("hcloud_server.bastion"; .change.after.server_type = "cx33")')" none "$A0" "REPLACEMENT SHAPE: after.server_type"
row "22: inline firewall_ids on the server" RED "$(mk "$R" "$SET"' set("hcloud_server.bastion"; .change.after.firewall_ids = [1])')" "$PIN" "$A1" "firewall_ids inline"
row "23: pin argument 0" RED "$R" 0 "$A1" "pin argument malformed"
row "23b: pin argument 12a" RED "$R" 12a "$A1" "pin argument malformed"
row "23c: pin argument empty" RED "$R" "" "$A1" "pin argument malformed"
row "23d: pin argument with a jq injection" RED "$R" '1) or true or (1' "$A1" "pin argument malformed"
row "24: a plan with no resource_changes (preamble)" RED "$(mk "$R" 'del(.resource_changes)')" "$PIN" "$A1" "no resource_changes array"
row "24b: an unclassifiable entry (empty actions)" RED \
  "$(mk "$R" "$ADD add({address: \"hcloud_server.web[\\\"web-1\\\"]\", type: \"hcloud_server\", change: {actions: [], before: {}, after: null}})")" "$PIN" "$A1" "unclassifiable"
printf 'not json' > "$WORK/garbage.json"
row "24c: an unparseable plan" RED "$WORK/garbage.json" "$PIN" "$A1"
echo "Deepen additions"
row "an attachment update whose known after.server_ids is still the old id" RED \
  "$(mk "$R" "$SET"' set("hcloud_firewall_attachment.bastion"; .change.after.server_ids = ['"$PIN"'] | .change.after_unknown.server_ids = [false])')" "$PIN" "$A1" "ATTACHMENT NOT RE-BOUND"
row "the server deleted with no create" RED "$(mk "$R" "$SET"' set("hcloud_server.bastion"; .change.actions = ["delete"])')" "$PIN" "$A1" "ACTION NOT ALLOWED: hcloud_server.bastion"
row "the NIC deleted with no create" RED "$(mk "$R" "$SET"' set("hcloud_server_network.bastion"; .change.actions = ["delete"])')" "$PIN" "$A1" "ACTION NOT ALLOWED: hcloud_server_network.bastion"
row "the server create-before-destroy (no create_before_destroy is declared)" RED "$(mk "$R" "$SET"' set("hcloud_server.bastion"; .change.actions = ["create","delete"])')" "$PIN" "$A1" "ACTION NOT ALLOWED: hcloud_server.bastion"
row "the NIC's before.server_id is another server (web-1's NIC mapped onto the bastion address)" RED \
  "$(mk "$R" "$SET"' set("hcloud_server_network.bastion"; .change.before.server_id = '"$OTHER"')')" "$PIN" "$A1" "NIC BEFORE PIN"
row "the NIC's before.ip is not 10.0.1.70" RED "$(mk "$R" "$SET"' set("hcloud_server_network.bastion"; .change.before.ip = "10.0.1.10")')" "$PIN" "$A1" "NIC BEFORE PIN"
row "the attachment's before.server_ids is another server" RED \
  "$(mk "$R" "$SET"' set("hcloud_firewall_attachment.bastion"; .change.before.server_ids = ['"$OTHER"'])')" "$PIN" "$A1" "ATTACHMENT BEFORE PIN"
row "the attachment's before.server_ids holds the pin AND another server" RED \
  "$(mk "$R" "$SET"' set("hcloud_firewall_attachment.bastion"; .change.before.server_ids = ['"$PIN"', '"$OTHER"'])')" "$PIN" "$A1" "ATTACHMENT BEFORE PIN"
echo "Q-R1 / Q-R2: the attachment's before, on both arms"
ATT='"hcloud_firewall_attachment.bastion"'
row "Q-R2: replace arm, the attachment updates from before.server_ids [] (a partial replace never re-bound it)" PASS \
  "$(mk "$R" "$SET"' set('"$ATT"'; .change.before.server_ids = [])')" "$PIN" "$A1"
row "Q-R2: replace arm, the attachment updates from before.server_ids null" PASS \
  "$(mk "$R" "$SET"' set('"$ATT"'; .change.before.server_ids = null)')" "$PIN" "$A1"
row "Q-R2: replace arm, the attachment is a bare create (before null)" PASS \
  "$(mk "$R" "$SET"' set('"$ATT"'; .change.actions = ["create"] | .change.before = null)')" "$PIN" "$A1"
row "Q-R1: replace arm, before.label_selectors [] passes (empty, like null)" PASS \
  "$(mk "$R" "$SET"' set('"$ATT"'; .change.before.label_selectors = [])')" "$PIN" "$A1"
row "Q-R1: recovery arm, the attachment updates from before.server_ids null" PASS \
  "$(mk "$V" "$SET"' set('"$ATT"'; .change.before.server_ids = null)')" none "$A0"
ATT_REC_OTHER="$(mk "$V" "$SET"' set('"$ATT"'; .change.before.server_ids = ['"$OTHER"'])')"
row "Q-R1: recovery arm, an update from another server's id refuses (it would strip that server's deny-all)" RED \
  "$ATT_REC_OTHER" none "$A0" "ATTACHMENT BEFORE PIN"
ATT_REC_NONE="$(mk "$V" "$SET"' set('"$ATT"'; .change.before.server_ids = ["none"])')"
row "Q-R1: recovery arm, before.server_ids [\"none\"] (the pin literal) refuses: only [] or null" RED \
  "$ATT_REC_NONE" none "$A0" "ATTACHMENT BEFORE PIN"
ATT_REP_LABELS="$(mk "$R" "$SET"' set('"$ATT"'; .change.before.label_selectors = [{selector: "role=web"}])')"
row "Q-R1: replace arm, before.label_selectors non-empty refuses" RED "$ATT_REP_LABELS" "$PIN" "$A1" "ATTACHMENT BEFORE LABEL BINDING"
ATT_REC_LABELS="$(mk "$V" "$SET"' set('"$ATT"'; .change.before.label_selectors = [{selector: "role=web"}])')"
row "Q-R1: recovery arm, before.label_selectors non-empty refuses" RED "$ATT_REC_LABELS" none "$A0" "ATTACHMENT BEFORE LABEL BINDING"
ATT_NO_SIDS="$(mk "$R" "$SET"' set('"$ATT"'; .change.before |= del(.server_ids))')"
row "Q-R1: replace arm, before lacks server_ids (unreadable, never empty)" RED "$ATT_NO_SIDS" "$PIN" "$A1" "ATTACHMENT BEFORE UNREADABLE"
row "Q-R1: recovery arm, before lacks label_selectors" RED \
  "$(mk "$V" "$SET"' set('"$ATT"'; .change.before |= del(.label_selectors))')" none "$A0" "ATTACHMENT BEFORE UNREADABLE"
row "Q-R1: replace arm, an update with no before object" RED \
  "$(mk "$R" "$SET"' set('"$ATT"'; .change.before = null)')" "$PIN" "$A1" "ATTACHMENT BEFORE UNREADABLE"
row "Q-R1: recovery arm, an update with no before object" RED \
  "$(mk "$V" "$SET"' set('"$ATT"'; .change.before = null)')" none "$A0" "ATTACHMENT BEFORE UNREADABLE"
row "Q-R1: replace arm, before.server_ids a string" RED \
  "$(mk "$R" "$SET"' set('"$ATT"'; .change.before.server_ids = "'"$PIN"'")')" "$PIN" "$A1" "ATTACHMENT BEFORE UNREADABLE"
row "Q-R1: recovery arm, before.label_selectors an object" RED \
  "$(mk "$V" "$SET"' set('"$ATT"'; .change.before.label_selectors = {})')" none "$A0" "ATTACHMENT BEFORE UNREADABLE"
ATT_CREATE_BEFORE="$(mk "$R" "$SET"' set('"$ATT"'; .change.actions = ["create"])')"
row "Q-R2: replace arm, an attachment create that carries a before" RED "$ATT_CREATE_BEFORE" "$PIN" "$A1" "ATTACHMENT BEFORE UNREADABLE"
echo "B5 / B6: arms the first battery did not pin"
KEY_TWICE="$(mk "$R" "$ADD add({address: \"tls_private_key.bastion_host_ssh\", type: \"tls_private_key\", deposed: \"00000001\", change: {actions: [\"delete\",\"create\"], before: {algorithm: \"ED25519\"}, after: {algorithm: \"ED25519\"}, after_unknown: {}}})")"
row "B5: a second host-key entry (deposed-shaped delete-and-create) refuses: listed exactly once" RED "$KEY_TWICE" "$PIN" "$A1" "is not in the plan exactly once"
ATT_KNOWN_OLD="$(mk "$R" "$SET"' set('"$ATT"'; .change.after.server_ids = ['"$PIN"'])')"
row "B6: after.server_ids [old id] with after_unknown [true] is not re-bound" RED "$ATT_KNOWN_OLD" "$PIN" "$A1" "ATTACHMENT NOT RE-BOUND"
row "B6: a 13-digit pin is malformed (the id is at most 12 digits)" RED "$R" 1234567890123 "$A1" "pin argument malformed"
API_ID_STRING="$(mk "$A1" '.servers[0].id = "'"$PIN"'"')"
row "B6: the API id is a numeric STRING, not a number" RED "$R" "$PIN" "$API_ID_STRING" "API ID NOT NUMERIC"
row "a listed address absent from the plan (the host key)" RED "$(mk "$R" "$DROP"' drop("tls_private_key.bastion_host_ssh")')" "$PIN" "$A1" "is not in the plan"
row "the recovery arm with the NIC delete-and-create" RED "$(mk "$V" "$SET"' set("hcloud_server_network.bastion"; .change.actions = ["delete","create"] | .change.before = {server_id: 1, ip: "10.0.1.70"})')" none "$A0" "ACTION NOT ALLOWED: hcloud_server_network.bastion"
echo "R3b behaviour rows (one per shared check, each RED with the common message)"
row "shared: an existing (no-op) firewall that carries a rule" RED \
  "$(mk "$R" "$SET"' set("hcloud_firewall.bastion"; .change.after.rule = [{direction: "in", protocol: "icmp", source_ips: ["0.0.0.0/0"]}])')" "$PIN" "$A1" "FIREWALL CONTENT:"
row "shared: the firewall's rule set is unreadable (no rule key)" RED "$(mk "$R" "$SET"' set("hcloud_firewall.bastion"; .change.after |= del(.rule))')" "$PIN" "$A1" "FIREWALL CONTENT UNREADABLE"
row "shared: the server's firewall_ids set only in configuration" RED \
  "$(mk "$R" '.configuration.root_module.resources |= map(if .address == "hcloud_server.bastion" then .expressions.firewall_ids = {references: ["hcloud_firewall.bastion.id", "hcloud_firewall.bastion"]} else . end)')" "$PIN" "$A1" "firewall_ids inline"
row "shared: the attachment's label_selectors unknown at plan time" RED \
  "$(mk "$R" "$SET"' set("hcloud_firewall_attachment.bastion"; .change.after_unknown.label_selectors = true)')" "$PIN" "$A1" "LABEL BINDING: hcloud_firewall_attachment.bastion"
row "shared: the plan has no configuration block (binding unreadable)" RED "$(mk "$R" 'del(.configuration)')" "$PIN" "$A1" "$ATT_UNBOUND"

# The allow-set (one list, shared with the -target parity test). The gate takes no override, so a bad
# or wider list is tested through a copy of the gate sourced from a scratch directory.
# scratch_gate <dir> [gate-file] [common-file]: the gate, the shared checks, and the preamble.
scratch_gate() {
  mkdir -p "$1"
  cp "${2:-$GATE}" "$1/bastion-host-replace-gate.sh"
  cp "${3:-$COMMON}" "$1/bastion-gate-common.sh"
  cp "$ROOT/tests/scripts/lib/plan-gate-preamble.sh" "$1/"
}
# scratch_run <dir> <plan> <pin> <api>: sources <dir>'s gate in a subshell and runs it -> out, rc
scratch_run() { out="$(source "$1/bastion-host-replace-gate.sh" && bastion_host_replace_gate "$2" "$3" "$4" 2>&1)"; rc=$?; printf '%s\n' "$out" >> "$ALL_OUT"; }
scratch_row() { # <label> <want-rc> <substring> <dir> <plan> <pin> <api>
  cases=$((cases + 1))
  if [[ "$GATE_PRESENT" != 1 ]]; then fail "$1 (gate absent)"; return; fi
  scratch_run "$4" "$5" "$6" "$7"
  if [[ "$rc" -eq "$2" && "$out" == *"$3"* ]]; then pass "$1"; else fail "$1 (rc=$rc)" "$out"; fi
}
echo "Allow-set rows"
[[ "$GATE_PRESENT" == 1 ]] && scratch_gate "$WORK/nolist"
scratch_row "20b: a missing bastion-resources list aborts" 1 "(bastion-resources) is missing or empty" "$WORK/nolist" "$R" "$PIN" "$A1"
if [[ "$GATE_PRESENT" == 1 ]]; then
  scratch_gate "$WORK/shortlist"
  awk '$0 != "hcloud_server_network.bastion"' "$ROOT/tests/scripts/lib/bastion-resources.txt" > "$WORK/shortlist/bastion-resources.txt"
fi
scratch_row "20: a list missing an address the gate grades aborts" 1 "does not list hcloud_server_network.bastion" "$WORK/shortlist" "$R" "$PIN" "$A1"
if [[ "$GATE_PRESENT" == 1 ]]; then
  scratch_gate "$WORK/widelist"
  { cat "$ROOT/tests/scripts/lib/bastion-resources.txt"; echo "hcloud_rdns.bastion"; } > "$WORK/widelist/bastion-resources.txt"
fi
NEW_MEMBER_UPDATE="$(mk "$R" "$ADD add({address: \"hcloud_rdns.bastion\", type: \"hcloud_rdns\", change: {actions: [\"update\"], before: {}, after: {}, after_unknown: {}}})")"
NEW_MEMBER_NOOP="$(mk "$R" "$ADD add({address: \"hcloud_rdns.bastion\", type: \"hcloud_rdns\", change: {actions: [\"no-op\"], before: {}, after: {}, after_unknown: {}}})")"
scratch_row "a NEW list member planned update is RED (no-op-only by default)" 1 "ACTION NOT ALLOWED: hcloud_rdns.bastion" "$WORK/widelist" "$NEW_MEMBER_UPDATE" "$PIN" "$A1"
scratch_row "a NEW list member planned no-op passes (control)" 0 "PASS" "$WORK/widelist" "$NEW_MEMBER_NOOP" "$PIN" "$A1"
cases=$((cases + 1))
if [[ "$GATE_PRESENT" == 1 && "$(BASTION_RESOURCES_FILE="$WORK/shortlist/bastion-resources.txt" "$GATE_FN" "$R" "$PIN" "$A1" >/dev/null 2>&1; echo $?)" -eq 0 ]]; then
  pass "BASTION_RESOURCES_FILE in the environment does not redirect the gate"
else
  fail "BASTION_RESOURCES_FILE in the environment does not redirect the gate"
fi

# ── The identity function the TOCTOU step re-runs on a fresh read ─────────────────────────────
echo "TOCTOU identity (bastion_replace_identity <pin> <doc> <before-id>)"
irow() { # <label> <want-rc> <substring> <pin> <doc> <before>
  local o r=0
  cases=$((cases + 1))
  o="$(bastion_replace_identity "$4" "$5" "$6" 2>&1)" || r=$?
  printf '%s\n' "$o" >> "$ALL_OUT"
  if [[ "$r" -eq "$2" && "$o" == *"$3"* ]]; then pass "$1"; else fail "$1 (rc=$r)" "$o"; fi
}
irow "identity holds: one soleur-bastion, role bastion, id = pin = before.id" 0 "" "$PIN" "$A1" "$PIN"
irow "identity holds on the recovery arm: none, zero servers, no before" 0 "" none "$A0" none
irow "a re-read whose id changed refuses" 1 "IDENTITY MISMATCH" "$PIN" "$(mk "$A1" ".servers[0].id = $OTHER")" "$PIN"
irow "a re-read whose server is now gone refuses" 1 "IDENTITY MISMATCH" "$PIN" "$A0" "$PIN"
irow "a re-read with a second server refuses" 1 "refusing to guess" "$PIN" "$(mk "$A1" '.servers += [.servers[0] | .id = '"$OTHER"']')" "$PIN"
irow "a re-read whose role changed refuses" 1 "API ROLE MISMATCH" "$PIN" "$(mk "$A1" '.servers[0].labels.role = "x"')" "$PIN"
irow "a re-read that is unreadable refuses (never zero)" 1 "HETZNER DOCUMENT UNREADABLE" none "$WORK/api-garbage.json" none
irow "a recovery re-read that now shows a server refuses" 1 "#13117" none "$A1" none

# ── The next-dispatch line the always-run summary prints ──────────────────────────────────────
echo "next dispatch (bastion_replace_next_dispatch <pre-ids> <doc|-> <state-server: 0|1|unread>)"
nrow() { # <label> <substring> <pre> <doc> <state> [forbidden-substring]
  local o r=0
  cases=$((cases + 1))
  o="$(bastion_replace_next_dispatch "$3" "$4" "$5" 2>&1)" || r=$?
  if [[ "$r" -eq 0 && "$o" == *"$2"* && ( -z "${6:-}" || "$o" != *"$6"* ) ]]; then pass "$1"; else fail "$1 (rc=$r)" "$o"; fi
}
nrow "no server anywhere: the line pins none" "expected_bastion_server_id=none" "$PIN" "$A0" 0
nrow "only a new id exists: the line pins the new id" "expected_bastion_server_id=${OTHER}" "$PIN" "$(mk "$A1" ".servers[0].id = $OTHER")" 1
nrow "only the pre-apply id exists: the line keeps the same pin" "expected_bastion_server_id=${PIN}" "$PIN" "$A1" 1
nrow "the API read failed: unread, no line to copy" "next dispatch: unread (API read failed); no line to copy" "$PIN" - 1 "gh workflow run"
nrow "two servers: no line to copy" "no line to copy" "$PIN" "$(mk "$A1" '.servers += [.servers[0] | .id = '"$OTHER"']')" 1 "gh workflow run"
nrow "the API shows none but state holds the server: no line to copy" "no line to copy" "$PIN" "$A0" 1 "gh workflow run"
nrow "the state read failed: no next dispatch" "post-failure state read FAILED; no next dispatch" "$PIN" "$A1" unread "gh workflow run"
nrow "the line names the route and its confirm token" "-f apply_target=bastion-host-replace -f confirm=REPLACE-bastion" "$PIN" "$A1" 1
nrow "a non-numeric API id is never printed into a line" "no line to copy" "$PIN" "$(mk "$A1" '.servers[0].id = "1;rm"')" 1 "gh workflow run"

# ── Gate mutations: one exact replacement in the gate or the common file, sourced from a scratch copy ──
# gmrow <label> <from> <to> <plan> <pin> <api> <msg>: the mutant must make that RED row FAIL through
# row() itself, while the mutant still passes the canonical replace (so the edit weakened one arm).
# gprow <label> <from> <to> <plan> <pin> <api>: the mutant must make a must-PASS row FAIL (an arm whose
# removal over-refuses, e.g. a dropped tostring comparing a number with a string).
gmut_target() {
  python3 - "$GATE" "$COMMON" "$1" <<'PY'
import sys
g, c, a = sys.argv[1:]
n = [open(f).read().count(a) for f in (g, c)]
if n == [1, 0]: print(g)
elif n == [0, 1]: print(c)
PY
}
gmut_apply() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys
s, d, a, b = sys.argv[1:]
t = open(s).read()
if t.count(a) != 1: sys.exit(1)
open(d, "w").write(t.replace(a, b))
PY
}
GMUT=0
gmut_fn() { (source "$GMUT_DIR/bastion-host-replace-gate.sh" && bastion_host_replace_gate "$@"); }
gmut_build() { # <from> <to> -> sets GMUT_D (scratch dir) or returns 1 (did not land)
  local from="$1" to="$2" target
  GMUT=$((GMUT + 1)); GMUT_D="$WORK/gmut$GMUT"
  target=""
  [[ "$GATE_PRESENT" == 1 ]] && target="$(gmut_target "$from")"
  [[ -n "$target" ]] || return 1
  gmut_apply "$target" "$WORK/gmut$GMUT.sh" "$from" "$to" || return 1
  cmp -s "$target" "$WORK/gmut$GMUT.sh" && return 1   # the mutant must differ from its source
  if [[ "$target" == "$GATE" ]]; then scratch_gate "$GMUT_D" "$WORK/gmut$GMUT.sh"; else scratch_gate "$GMUT_D" "$GATE" "$WORK/gmut$GMUT.sh"; fi
  cp "$ROOT/tests/scripts/lib/bastion-resources.txt" "$GMUT_D/"
}
gmrow() {
  local label="$1" from="$2" to="$3" plan="$4" pin="$5" api="$6" msg="$7" r
  cases=$((cases + 1))
  if ! gmut_build "$from" "$to"; then fail "gate mutation did not land: $label"; return; fi
  r="$(GATE_FN=gmut_fn; GMUT_DIR="$GMUT_D"; passes=0; fails=0; row "$label" RED "$plan" "$pin" "$api" "$msg" >/dev/null; printf '%s %s' "$passes" "$fails")"
  scratch_run "$GMUT_D" "$R" "$PIN" "$A1"
  if [[ "$r" == "0 1" && "$rc" -eq 0 ]]; then pass "gate mutation caught: $label"; else fail "gate mutation SURVIVED: $label (row passes/fails=$r, mutant baseline rc=$rc)" "$out"; fi
}
gprow() {
  local label="$1" from="$2" to="$3" plan="$4" pin="$5" api="$6" r
  cases=$((cases + 1))
  if ! gmut_build "$from" "$to"; then fail "gate mutation did not land: $label"; return; fi
  r="$(GATE_FN=gmut_fn; GMUT_DIR="$GMUT_D"; passes=0; fails=0; row "$label" PASS "$plan" "$pin" "$api" >/dev/null; printf '%s %s' "$passes" "$fails")"
  if [[ "$r" == "0 1" ]]; then pass "gate mutation caught (over-refusal): $label"; else fail "gate mutation SURVIVED: $label (PASS row passes/fails=$r)"; fi
}
echo "Gate mutations"
gprow "M01 tostring dropped from the API-id comparison (a number never equals the string pin)" \
  '(.servers[0].id | tostring) == $pin' '.servers[0].id == $pin' "$R" "$PIN" "$A1"
gmrow "M02 the API count check dropped" 'if [[ "$n" -gt 1 ]]; then' 'if false; then' \
  "$R" "$PIN" "$(mk "$A1" '.servers += [.servers[0] | .id = '"$OTHER"']')" "refusing to guess"
gmrow "M03 the role check dropped" '.servers[0].labels.role == $r' 'true' \
  "$R" "$PIN" "$(mk "$A1" '.servers[0].labels.role = "web"')" "API ROLE MISMATCH"
gmrow "M04 the recovery arm's prior_state check dropped" 'if [[ "$prior_has" -ne 0 ]]; then' 'if false; then' \
  "$RECOVERY_PRIOR" none "$A0" "RECOVERY REFUSED"
gmrow "M05 the attachment re-binding check dropped" 'if [[ "$att_rebound" -ne 1 ]]; then' 'if false; then' \
  "$(mk "$R" "$SET"' set("hcloud_firewall_attachment.bastion"; .change.after.server_ids = ['"$PIN"'] | .change.after_unknown.server_ids = [false])')" "$PIN" "$A1" "ATTACHMENT NOT RE-BOUND"
gmrow "M06 the attachment's update/create entry widened to no-op" 'elif $a == $t then [["update"],["create"]]' \
  'elif $a == $t then [["update"],["create"],["no-op"]]' \
  "$(mk "$R" "$SET"' set("hcloud_firewall_attachment.bastion"; .change.actions = ["no-op"])')" "$PIN" "$A1" "ACTION NOT ALLOWED: hcloud_firewall_attachment.bastion"
gmrow "M07 the after.server_type check dropped" 'if [[ "$shape_type" -ne 1 ]]; then' 'if false; then' \
  "$(mk "$R" "$SET"' set("hcloud_server.bastion"; .change.after.server_type = "cx33")')" "$PIN" "$A1" "REPLACEMENT SHAPE: after.server_type"
gmrow "M08 the after.name check dropped" 'if [[ "$shape_name" -ne 1 ]]; then' 'if false; then' \
  "$(mk "$R" "$SET"' set("hcloud_server.bastion"; .change.after.name = "soleur-bastion-2")')" "$PIN" "$A1" "REPLACEMENT SHAPE: after.name"
gmrow "M09 the after.labels.role check dropped" 'if [[ "$shape_role" -ne 1 ]]; then' 'if false; then' \
  "$(mk "$R" "$SET"' set("hcloud_server.bastion"; .change.after.labels.role = "web")')" "$PIN" "$A1" "REPLACEMENT SHAPE: after.labels.role"
gmrow "M10 the NIC before pin dropped" 'if [[ "$nic_before_ok" -ne 1 ]]; then' 'if false; then' \
  "$(mk "$R" "$SET"' set("hcloud_server_network.bastion"; .change.before.server_id = '"$OTHER"')')" "$PIN" "$A1" "NIC BEFORE PIN"
gmrow "M11 the attachment before pin dropped" 'if [[ "$att_before_ok" -ne 1 ]]; then' 'if false; then' \
  "$(mk "$R" "$SET"' set("hcloud_firewall_attachment.bastion"; .change.before.server_ids = ['"$OTHER"'])')" "$PIN" "$A1" "ATTACHMENT BEFORE PIN"
gmrow "M12 the call into bastion-gate-common.sh deleted (R3b call-site row)" \
  '  bastion_gate_create_side_judge "$g" "$plan_json" || { _bhrg_abort "$g" "a shared create-side check refused (the line above)."; return 1; }' '  :' \
  "$(mk "$R" "$SET"' set("hcloud_server_network.bastion"; .change.after.ip = "10.0.1.71")')" "$PIN" "$A1" "does not pin the private IP"
gmrow "M13 the out-of-scope arm dropped" 'if [[ "$out_of_scope" -ne 0 ]]; then' 'if false; then' \
  "$(mk "$R" "$ADD add({address: \"hcloud_server.web[\\\"web-1\\\"]\", type: \"hcloud_server\", change: {actions: [\"delete\",\"create\"], before: {id: \"111\"}, after: {}, after_unknown: {}}})")" "$PIN" "$A1" "out-of-scope"
gmrow "M14 the pin = before.id leg of the identity dropped" ' and $pin == $b' '' \
  "$(mk "$R" "$SET"' set("hcloud_server.bastion"; .change.before.id = "'"$OTHER"'")')" "$PIN" "$A1" "IDENTITY MISMATCH"
gmrow "M15 the attachment before re-scoped to the replace arm (Q-R1)" '  if [[ "$att_before_ok" -ne 1 ]]; then' \
  '  if [[ "$arm" == replace && "$att_before_ok" -ne 1 ]]; then' "$ATT_REC_OTHER" none "$A0" "ATTACHMENT BEFORE PIN"
gmrow "M16 the before.label_selectors leg dropped (Q-R1)" '              and (.change.before.label_selectors | . == null or . == [])
' '' "$ATT_REP_LABELS" "$PIN" "$A1" "ATTACHMENT BEFORE LABEL BINDING"
gmrow "M17 the both-keys-present leg dropped (Q-R1)" '              and (.change.before | has("server_ids") and has("label_selectors"))
' '' "$ATT_NO_SIDS" "$PIN" "$A1" "ATTACHMENT BEFORE UNREADABLE"
gmrow "M18 the [pin] leg opened to the recovery arm (Q-R1)" '($arm == "replace" and type == "array"' '(type == "array"' \
  "$ATT_REC_NONE" none "$A0" "ATTACHMENT BEFORE PIN"
gmrow "M19 the create's before==null leg dropped (Q-R2)" '(.change.actions == ["create"] and .change.before == null)' '(.change.actions == ["create"])' \
  "$ATT_CREATE_BEFORE" "$PIN" "$A1" "ATTACHMENT BEFORE UNREADABLE"
gmrow "M20 the UNREADABLE message folded into PIN" '    if [[ "$att_before_unreadable" -ne 0 ]]; then' '    if false; then' \
  "$ATT_NO_SIDS" "$PIN" "$A1" "ATTACHMENT BEFORE UNREADABLE"
gmrow "M21 the LABEL BINDING message folded into PIN" '    elif [[ "$att_before_labels" -ne 0 ]]; then' '    elif false; then' \
  "$ATT_REP_LABELS" "$PIN" "$A1" "ATTACHMENT BEFORE LABEL BINDING"
gmrow "M22 'listed exactly once' relaxed to 'listed at least once' (B5)" '| select(.address == $a)] | length) != 1) | $a ]' '| select(.address == $a)] | length) == 0) | $a ]' \
  "$KEY_TWICE" "$PIN" "$A1" "is not in the plan exactly once"
gmrow "M23 the [null] leg of the re-bind check dropped (B6)" ' and ((.change.after.server_ids? // null) == [null])' '' \
  "$ATT_KNOWN_OLD" "$PIN" "$A1" "ATTACHMENT NOT RE-BOUND"
gmrow "M24 the pin regex unbounded (B6)" '[0-9]{0,11}|none)$ ]]' '[0-9]*|none)$ ]]' "$R" 1234567890123 "$A1" "pin argument malformed"
gmrow "M25 the API id number-type check dropped (B6)" '(.servers[0].id | type) == "number" and ' '' "$R" "$PIN" "$API_ID_STRING" "API ID NOT NUMERIC"

# ── The key marker: no gate output any row captured carries a private_key_* value ──────────────
cases=$((cases + 1))
if [[ -s "$ALL_OUT" ]] && ! grep -qF "$MARK" "$ALL_OUT"; then pass "SYNTHETIC-KEY-MARKER (in private_key_openssh, _pem and _pem_pkcs8) appears in no captured gate output ($(wc -l < "$ALL_OUT") lines)"; else fail "SYNTHETIC-KEY-MARKER appears in captured gate output (or nothing was captured)"; fi
cases=$((cases + 1))
if jq -e '[.. | objects | to_entries[] | select(.key | startswith("private_key_")) | .value | strings | select(contains("'"$MARK"'"))] | length == 9' "$R" >/dev/null 2>&1 \
   && jq -e '[.prior_state | .. | objects | to_entries[] | select(.key | startswith("private_key_")) | .value | strings] | length == 3' "$R" >/dev/null 2>&1; then
  pass "the marker fixture holds all three private_key_* fields in change.before, change.after and prior_state (the masking jq finds them)"
else
  fail "the marker fixture holds all three private_key_* fields (the masking jq finds them)"
fi

# ── H1: the suite goes RED when the gate is replaced by `return 0` ──────────────────────────
echo "H1 (neutered gate)"
neutered() { echo "neutered: PASS"; return 0; }
# h1_replay <gate-fn>: every recorded RED row re-run against <gate-fn> -> "passes fails"
h1_replay() {
  ( GATE_FN="$1"; passes=0; fails=0
    for r in "${RED_ROWS[@]}"; do IFS='|' read -r l p pn a m <<<"$r"; row "$l" RED "$p" "$pn" "$a" "$m" >/dev/null; done
    printf '%s %s' "$passes" "$fails" )
}
# h1_ok <passes-fails>: the H1 verdict, every RED row failed and the floor is met.
h1_ok() { [[ "${#RED_ROWS[@]}" -ge "$MIN_RED" && "$1" == "0 ${#RED_ROWS[@]}" ]]; }
h1="$(h1_replay neutered)"
MIN_RED=73  # measured 2026-11-28 (review: 58 -> 73, Q-R1/Q-R2/B5/B6): the literal RED-row count (H3), never derived from the table
cases=$((cases + 1))
if h1_ok "$h1"; then
  pass "H1: all ${#RED_ROWS[@]} RED rows fail against a neutered gate"
else
  fail "H1: RED rows=${#RED_ROWS[@]} (floor ${MIN_RED}), neutered-gate passes/fails=${h1}"
fi

# ── CONTROLS: every helper that owns a verdict must still be able to REJECT ─────────────────────
# Each is driven once with a must-fail input in a subshell (its counters unwind with it) and must report
# exactly one fail and no pass. A helper neutered to `pass` (or a message check reduced to rc) fails
# here. Reported by printf + exit 1, never through pass()/fail() (ADR-193).
control() { # <label> <helper> <args...>
  local label="$1" r; shift
  r="$( passes=0; fails=0; cases=0; "$@" >/dev/null 2>&1; printf '%s %s' "$passes" "$fails" )"
  if [[ "$r" != "0 1" ]]; then
    printf 'test-bastion-host-replace-gate: FAIL (CONTROL %s: the helper did not reject a must-fail input; passes/fails=%s)\n' "$label" "$r" >&2
    exit 1
  fi
}
control "row: an ABORT naming another message is not that row's ABORT" row "ctl" RED "$R" 0 "$A1" "IDENTITY MISMATCH"
control "row: RED wanted, the gate passed" row "ctl" RED "$R" "$PIN" "$A1"
control "row: PASS wanted, the gate refused" row "ctl" PASS "$R" 11111111 "$A1"
control "irow: wrong rc" irow "ctl" 0 "" "$PIN" "$A0" "$PIN"
control "irow: right rc, wrong message" irow "ctl" 1 "API ROLE MISMATCH" "$PIN" "$A0" "$PIN"
control "nrow: the wanted substring is absent" nrow "ctl" "expected_bastion_server_id=none" "$PIN" "$A1" 1
control "nrow: the forbidden substring is present" nrow "ctl" "next dispatch" "$PIN" "$A1" 1 "gh workflow run"
control "scratch_row: wrong rc" scratch_row "ctl" 1 "PASS" "$WORK/widelist" "$NEW_MEMBER_NOOP" "$PIN" "$A1"
control "scratch_row: right rc, wrong substring" scratch_row "ctl" 0 "NO-SUCH-SUBSTRING" "$WORK/widelist" "$NEW_MEMBER_NOOP" "$PIN" "$A1"
control "gmrow: a behaviour-identical mutant SURVIVES" gmrow "ctl" 'if [[ "$n" -gt 1 ]]; then' 'if [[ "$n" -gt 1 ]] ; then' \
  "$R" "$PIN" "$(mk "$A1" '.servers += [.servers[0] | .id = '"$OTHER"']')" "refusing to guess"
control "gmrow: a mutation that does not land" gmrow "ctl" 'NO SUCH GATE TEXT' 'x' "$R" "$PIN" "$A1" "IDENTITY MISMATCH"
control "gprow: a behaviour-identical mutant SURVIVES" gprow "ctl" '(.servers[0].id | tostring) == $pin' '(.servers[0].id | tostring) == ($pin)' "$R" "$PIN" "$A1"
if h1_ok "$(h1_replay "$GATE_FN")"; then
  printf 'test-bastion-host-replace-gate: FAIL (CONTROL H1: the predicate accepted a replay against the REAL gate, which keeps every RED row passing)\n' >&2
  exit 1
fi

echo
MIN_CASES=136  # measured 2026-11-28 (H3; review: 121 -> 136, the Guard 2 grep rows moved to the workflow suite, Q-R1/Q-R2/B5/B6 rows and mutations added)
if [[ "$cases" -lt "$MIN_CASES" ]]; then
  printf 'test-bastion-host-replace-gate: FAIL (only %d assertions ran; floor %d)\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf 'test-bastion-host-replace-gate: FAIL (accounting: passes+fails=%d != cases=%d)\n' "$((passes + fails))" "$cases" >&2
  exit 1
fi
if [[ "$fails" -gt 0 ]]; then
  printf 'test-bastion-host-replace-gate: FAIL (%d of %d assertions failed)\n' "$fails" "$cases" >&2
  exit 1
fi
printf 'test-bastion-host-replace-gate: PASS (%d assertions, 0 failed)\n' "$cases"
