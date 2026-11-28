#!/usr/bin/env bash
# Mutation matrix for tests/scripts/lib/bastion-host-birth-gate.sh (Guard 1, #12866).
#
# PROPERTY. A bastion-host-create apply runs only on a plan that creates hcloud_server.bastion and
# its private NIC, binds the zero-rule firewall to exactly that server, leaves every other bastion
# address created or already present, never rotates the host key, and changes nothing else.
#
# Fixtures are synthesized tfplan.json documents (ADR-322): one compliant birth, and one jq edit per
# row. Rows 6 (the apply consumes the gated plan file) and 8 (the -target lines equal
# bastion-resources.txt) are structure rows over the workflow; row 8 lives in
# plugins/soleur/test/terraform-target-parity.test.ts, row 6 is here.
#
# ANTI-VACUITY. `cases` moves at every assertion; H1 re-runs every RED row against a gate replaced by
# `return 0` and requires every one of them to flip; the floor and passes+fails==cases are reported
# by printf + exit 1, never through fail() (ADR-193).
#
# Run: bash tests/scripts/test-bastion-host-birth-gate.sh
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
GATE="${ROOT}/tests/scripts/lib/bastion-host-birth-gate.sh"
# The create-side checks the gate sources from its own directory (R3, #12879).
COMMON="${ROOT}/tests/scripts/lib/bastion-gate-common.sh"
# The reusable body of apply-web-platform-infra.yml's bastion_host_create caller job (size gate, #8361).
WORKFLOW="${ROOT}/.github/workflows/bastion-host-create.yml"

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
WORK="$(mktemp -d "${TMPDIR}/bhbg.XXXXXXXX")" || harness "mktemp failed"
case "$WORK" in /*/bhbg.*) : ;; *) harness "mktemp returned '$WORK'" ;; esac
trap 'rm -rf "${WORK:?}"' EXIT

GATE_PRESENT=0
if [[ -f "$GATE" ]]; then
  # shellcheck source=tests/scripts/lib/bastion-host-birth-gate.sh
  source "$GATE"
  declare -F bastion_host_birth_gate >/dev/null && GATE_PRESENT=1
fi
# RED until the gate exists: every row then fails on the missing function, never skips.
[[ "$GATE_PRESENT" == 1 ]] || bastion_host_birth_gate() { echo "bastion_host_birth_gate: NOT IMPLEMENTED"; return 99; }
GATE_FN=bastion_host_birth_gate

# ── The compliant birth plan ────────────────────────────────────────────────────────────────
cat > "$WORK/base.json" <<'JSON'
{
  "format_version": "1.2",
  "resource_changes": [
    {"address": "tls_private_key.bastion_host_ssh", "type": "tls_private_key",
     "change": {"actions": ["create"], "before": null, "after": {"algorithm": "ED25519"},
                "after_unknown": {"public_key_openssh": true, "private_key_openssh": true}}},
    {"address": "hcloud_firewall.bastion", "type": "hcloud_firewall",
     "change": {"actions": ["create"], "before": null,
                "after": {"name": "soleur-bastion", "rule": [], "apply_to": [], "labels": {"role": "bastion"}},
                "after_unknown": {"id": true, "rule": [], "apply_to": []}}},
    {"address": "hcloud_server.bastion", "type": "hcloud_server",
     "change": {"actions": ["create"], "before": null,
                "after": {"name": "soleur-bastion", "server_type": "cx23", "firewall_ids": null},
                "after_unknown": {"id": true}}},
    {"address": "hcloud_server_network.bastion", "type": "hcloud_server_network",
     "change": {"actions": ["create"], "before": null, "after": {"ip": "10.0.1.70"},
                "after_unknown": {"server_id": true}}},
    {"address": "hcloud_firewall_attachment.bastion", "type": "hcloud_firewall_attachment",
     "change": {"actions": ["create"], "before": null, "after": {"label_selectors": null},
                "after_unknown": {"firewall_id": true, "server_ids": true}}}
  ],
  "configuration": {"root_module": {"resources": [
    {"address": "hcloud_server.bastion", "expressions": {"name": {"constant_value": "soleur-bastion"}}},
    {"address": "hcloud_firewall_attachment.bastion", "expressions": {
      "firewall_id": {"references": ["hcloud_firewall.bastion.id", "hcloud_firewall.bastion"]},
      "server_ids": {"references": ["hcloud_server.bastion.id", "hcloud_server.bastion"]}}}
  ]}}
}
JSON
jq -e '.resource_changes | length == 5' "$WORK/base.json" >/dev/null || harness "base fixture is not valid JSON"

# mk runs inside $(...), so a shell counter would never persist: every fixture gets its own mktemp name,
# or a stored path (ROW4_DELETE, INLINE_CFG, ATT_KNOWN_OTHER, ATT_TWO_IDS, reused by the gate-mutation
# rows below) would be overwritten by the next mk and those rows would grade the wrong plan.
mk() { # <jq-edit> -> path of the mutated plan
  local f
  f="$(mktemp "$WORK/p.XXXXXXXX")" || harness "mktemp failed"
  jq "$1" "$WORK/base.json" > "$f" || harness "fixture edit failed: $1"
  printf '%s' "$f"
}
SET='def set($a; f): .resource_changes |= map(if .address == $a then f else . end);'
DROP='def drop($a): .resource_changes |= map(select(.address != $a));'
ADD='def add(r): .resource_changes += [r];'

RED_ROWS=()
# row <label> <PASS|RED> <plan-file> [message-substring]
# The substring is matched against the ABORT line(s) only, never the always-printed counter line
# (whose `destroys=`/`fw_rules=` would satisfy 'destroy'/'rule' whichever arm refused).
row() {
  local label="$1" want="$2" plan="$3" msg="${4:-}" out rc abort
  cases=$((cases + 1))
  out="$("$GATE_FN" "$plan" 2>&1)"; rc=$?
  abort="$(awk '/ABORT/' <<<"$out")"
  [[ "$want" == RED ]] && RED_ROWS+=("$label|$plan|$msg")
  if [[ "$want" == PASS ]]; then
    if [[ "$rc" -eq 0 && "$out" == *"PASS"* ]]; then pass "$label"; else fail "$label (want PASS, rc=$rc)" "$out"; fi
  else
    if [[ "$rc" -eq 1 && -n "$abort" && ( -z "$msg" || "$abort" == *"$msg"* ) ]]; then pass "$label"; else fail "$label (want RED rc=1${msg:+ with an ABORT line naming '$msg'}, rc=$rc)" "$out"; fi
  fi
}

echo "Guard 1 matrix"
row "baseline: a compliant first birth passes" PASS "$WORK/base.json"
row "1: the plan also creates hcloud_server.web[\"web-3\"]" RED \
  "$(mk "$ADD add({address: \"hcloud_server.web[\\\"web-3\\\"]\", type: \"hcloud_server\", change: {actions: [\"create\"], before: null, after: {}, after_unknown: {}}})")" "hcloud_server creates"
row "2: an empty resource_changes (0 checked)" RED "$(mk '.resource_changes = []')" "no host create"
row "3: a second change, an in-place update to hcloud_firewall.web" RED \
  "$(mk "$ADD add({address: \"hcloud_firewall.web\", type: \"hcloud_firewall\", change: {actions: [\"update\"], before: {}, after: {rule: []}, after_unknown: {}}})")" "out-of-scope"
ROW4_DELETE="$(mk "$ADD add({address: \"hcloud_volume.workspaces[\\\"web-2\\\"]\", type: \"hcloud_volume\", change: {actions: [\"delete\"], before: {}, after: null, after_unknown: {}}})")"
row "4: the plan deletes an unrelated resource" RED "$ROW4_DELETE" "destroy"
row "5: partial-birth retry (key and firewall no-op, server and NIC create) passes" PASS \
  "$(mk "$SET"' set("tls_private_key.bastion_host_ssh"; .change.actions = ["no-op"] | .change.before = .change.after) | set("hcloud_firewall.bastion"; .change.actions = ["no-op"] | .change.before = .change.after | .change.after_unknown = {})')"
row "5 (re-birth): the firewall attachment UPDATES to the new server, and passes" PASS \
  "$(mk "$SET"' set("tls_private_key.bastion_host_ssh"; .change.actions = ["no-op"]) | set("hcloud_firewall.bastion"; .change.actions = ["no-op"] | .change.after_unknown = {}) | set("hcloud_firewall_attachment.bastion"; .change.actions = ["update"] | .change.before = {server_ids: []})')"
row "5a: the host key is updated" RED "$(mk "$SET"' set("tls_private_key.bastion_host_ssh"; .change.actions = ["update"])')" "host key"
row "5a: the host key is deleted" RED "$(mk "$SET"' set("tls_private_key.bastion_host_ssh"; .change.actions = ["delete"])')"
row "5a: the host key is replaced (delete, create)" RED "$(mk "$SET"' set("tls_private_key.bastion_host_ssh"; .change.actions = ["delete","create"])')"
row "5b: every bastion resource is no-op (already born)" RED \
  "$(mk '.resource_changes |= map(.change.actions = ["no-op"] | .change.after_unknown = {})')" "#12879"
row "5c: hcloud_server.bastion is delete-and-create" RED "$(mk "$SET"' set("hcloud_server.bastion"; .change.actions = ["delete","create"])')" "destroy"
row "5c: hcloud_server.bastion is create-before-destroy" RED "$(mk "$SET"' set("hcloud_server.bastion"; .change.actions = ["create","delete"])')" "destroy"
row "7: the server is created without hcloud_server_network.bastion" RED "$(mk "$DROP"' drop("hcloud_server_network.bastion")')" "hcloud_server_network.bastion"
row "7: hcloud_server_network.bastion is a no-op beside a server create" RED "$(mk "$SET"' set("hcloud_server_network.bastion"; .change.actions = ["no-op"])')" "hcloud_server_network.bastion"
row "7: the NIC is planned at another private IP" RED "$(mk "$SET"' set("hcloud_server_network.bastion"; .change.after.ip = "10.0.1.71")')" "does not pin the private IP 10.0.1.70 (planned: 10.0.1.71)"
row "7: the NIC's IP is unknown at plan time" RED "$(mk "$SET"' set("hcloud_server_network.bastion"; .change.after.ip = null | .change.after_unknown.ip = true)')" "does not pin the private IP 10.0.1.70"
row "7: the NIC carries the right IP but marks it unknown" RED "$(mk "$SET"' set("hcloud_server_network.bastion"; .change.after_unknown.ip = true)')" "does not pin the private IP 10.0.1.70"
row "9: hcloud_firewall.bastion is planned with a rule" RED \
  "$(mk "$SET"' set("hcloud_firewall.bastion"; .change.after.rule = [{direction: "in", protocol: "tcp", port: "22", source_ips: ["0.0.0.0/0"]}])')" "FIREWALL CONTENT:"
row "9: an existing (no-op) firewall that carries a rule" RED \
  "$(mk "$SET"' set("hcloud_firewall.bastion"; .change.actions = ["no-op"] | .change.after_unknown = {} | .change.after.rule = [{direction: "in", protocol: "icmp", source_ips: ["0.0.0.0/0"]}])')" "FIREWALL CONTENT:"
row "9: the firewall rule set is unknown at plan time" RED "$(mk "$SET"' set("hcloud_firewall.bastion"; .change.after_unknown.rule = true)')" "FIREWALL CONTENT UNREADABLE"
row "9: the firewall entry has no rule key" RED "$(mk "$SET"' set("hcloud_firewall.bastion"; .change.after |= del(.rule))')" "FIREWALL CONTENT UNREADABLE"
row "9: the firewall's rule is null" RED "$(mk "$SET"' set("hcloud_firewall.bastion"; .change.after.rule = null)')" "FIREWALL CONTENT UNREADABLE"
row "9: the firewall's rule is an object, not an array" RED "$(mk "$SET"' set("hcloud_firewall.bastion"; .change.after.rule = {})')" "FIREWALL CONTENT UNREADABLE"
row "9: the firewall entry has no after_unknown" RED "$(mk "$SET"' set("hcloud_firewall.bastion"; .change |= del(.after_unknown))')" "FIREWALL CONTENT UNREADABLE"
row "9: the firewall's after_unknown is a boolean" RED "$(mk "$SET"' set("hcloud_firewall.bastion"; .change.after_unknown = true)')" "FIREWALL CONTENT UNREADABLE"
row "the firewall sets apply_to (a firewall-side binding)" RED \
  "$(mk "$SET"' set("hcloud_firewall.bastion"; .change.after.apply_to = [{label_selector: "role=web", server: null}])')" "LABEL BINDING: hcloud_firewall.bastion sets apply_to"
row "the firewall's apply_to is unknown at plan time" RED \
  "$(mk "$SET"' set("hcloud_firewall.bastion"; .change.after_unknown.apply_to = true)')" "LABEL BINDING: hcloud_firewall.bastion sets apply_to"
row "the firewall attachment sets label_selectors" RED \
  "$(mk "$SET"' set("hcloud_firewall_attachment.bastion"; .change.after.label_selectors = ["role=web"])')" "LABEL BINDING: hcloud_firewall_attachment.bastion sets label_selectors"
row "the attachment's label_selectors are unknown at plan time" RED \
  "$(mk "$SET"' set("hcloud_firewall_attachment.bastion"; .change.after_unknown.label_selectors = true)')" "LABEL BINDING: hcloud_firewall_attachment.bastion sets label_selectors"
ATT_UNBOUND="hcloud_firewall_attachment.bastion does not end this plan binding"
row "the firewall attachment is absent" RED "$(mk "$DROP"' drop("hcloud_firewall_attachment.bastion")')" "$ATT_UNBOUND"
row "the firewall attachment binds another server" RED \
  "$(mk '.configuration.root_module.resources |= map(if .address == "hcloud_firewall_attachment.bastion" then .expressions.server_ids.references = ["hcloud_server.git_data.id","hcloud_server.git_data"] else . end)')" "$ATT_UNBOUND"
# A KNOWN one-element server_ids (a re-birth's update, the id already in state) names hcloud_server.git_data:
# the count is right, so only the reference check refuses it, and it must apply on the known branch too.
ATT_KNOWN_OTHER="$(mk "$SET"' set("hcloud_firewall_attachment.bastion"; .change.after.server_ids = [4343] | .change.after_unknown.server_ids = false) | .configuration.root_module.resources |= map(if .address == "hcloud_firewall_attachment.bastion" then .expressions.server_ids.references = ["hcloud_server.git_data.id","hcloud_server.git_data"] else . end)')"
row "a known one-element server_ids whose reference is hcloud_server.git_data" RED "$ATT_KNOWN_OTHER" "$ATT_UNBOUND"
# Two server ids, one unknown at plan time (the bastion's id plus a literal one): the reference list can
# still read as the bastion's alone, so only the cardinality check refuses it.
ATT_TWO_IDS="$(mk "$SET"' set("hcloud_firewall_attachment.bastion"; .change.after.server_ids = [null, 12345] | .change.after_unknown.server_ids = [true, false])')"
row "the attachment's server_ids hold two ids, one unknown" RED "$ATT_TWO_IDS" "$ATT_UNBOUND"
row "the firewall attachment binds the bastion AND another server" RED \
  "$(mk '.configuration.root_module.resources |= map(if .address == "hcloud_firewall_attachment.bastion" then .expressions.server_ids.references += ["hcloud_server.git_data.id","hcloud_server.git_data"] else . end)')" "$ATT_UNBOUND"
row "the firewall attachment binds another firewall" RED \
  "$(mk '.configuration.root_module.resources |= map(if .address == "hcloud_firewall_attachment.bastion" then .expressions.firewall_id.references = ["hcloud_firewall.web.id","hcloud_firewall.web"] else . end)')" "$ATT_UNBOUND"
row "the plan has no configuration block (identity unreadable)" RED "$(mk 'del(.configuration)')" "$ATT_UNBOUND"
row "the server sets firewall_ids inline" RED "$(mk "$SET"' set("hcloud_server.bastion"; .change.after.firewall_ids = [1])')" "firewall_ids inline"
# The inline list only in configuration (its value unknown at plan time, so `after` shows none).
INLINE_CFG="$(mk "$SET"' set("hcloud_server.bastion"; .change.after.firewall_ids = null | .change.after_unknown.firewall_ids = true) | .configuration.root_module.resources |= map(if .address == "hcloud_server.bastion" then .expressions.firewall_ids = {references: ["hcloud_firewall.bastion.id", "hcloud_firewall.bastion"]} else . end)')"
row "the server's firewall_ids are set only in configuration (unknown in the plan)" RED "$INLINE_CFG" "firewall_ids inline"
row "the firewall is updated in place beside a birth" RED "$(mk "$SET"' set("hcloud_firewall.bastion"; .change.actions = ["update"] | .change.before = {rule: []} | .change.after_unknown = {})')" "in-place update"
row "the host key is absent from the plan" RED "$(mk "$DROP"' drop("tls_private_key.bastion_host_ssh")')" "tls_private_key.bastion_host_ssh"
row "the firewall is absent from the plan" RED "$(mk "$DROP"' drop("hcloud_firewall.bastion")')" "hcloud_firewall.bastion"
row "an out-of-scope create beside a valid birth" RED \
  "$(mk "$ADD add({address: \"doppler_secret.bastion_host_key\", type: \"doppler_secret\", change: {actions: [\"create\"], before: null, after: {}, after_unknown: {}}})")" "out-of-scope"
row "a forget (removed{} state drop) of an unrelated resource" RED \
  "$(mk "$ADD add({address: \"hcloud_server.git_data\", type: \"hcloud_server\", change: {actions: [\"forget\"], before: {}, after: null, after_unknown: {}}})")" "destroy"
row "an unclassifiable entry (empty actions)" RED \
  "$(mk "$ADD add({address: \"hcloud_server.web[\\\"web-1\\\"]\", type: \"hcloud_server\", change: {actions: [], before: {}, after: null}})")" "unclassifiable"
printf 'not json' > "$WORK/garbage.json"
row "an unparseable plan file" RED "$WORK/garbage.json"
row "a missing plan file" RED "$WORK/nope.json"
row "no plan path at all" RED ""
row "H2: reordered entries plus data-source reads and unrelated no-ops pass" PASS \
  "$(mk '.resource_changes |= reverse | .resource_changes += [{address: "data.hcloud_image.ubuntu", type: "hcloud_image", change: {actions: ["read"], before: null, after: {}, after_unknown: {}}}, {address: "hcloud_network.main", type: "hcloud_network", change: {actions: ["no-op"], before: {}, after: {}, after_unknown: {}}}]')"

# The allow-set file the gate reads (one list, shared with the -target parity test). The gate takes no
# override, so a bad list is tested through a copy of the gate sourced from a scratch directory.
# scratch_gate <dir> [gate-file] [common-file]: copies the gate (or a mutant of it), the shared
# create-side checks it sources from its own directory (or a mutant of them), and its preamble into <dir>.
scratch_gate() {
  mkdir -p "$1"
  cp "${2:-$GATE}" "$1/bastion-host-birth-gate.sh"
  cp "${3:-$COMMON}" "$1/bastion-gate-common.sh"
  cp "$ROOT/tests/scripts/lib/plan-gate-preamble.sh" "$1/"
}
# scratch_run <dir> <plan>: sources <dir>'s gate in a subshell and runs it -> out, rc
scratch_run() { out="$(source "$1/bastion-host-birth-gate.sh" && bastion_host_birth_gate "$2" 2>&1)"; rc=$?; }
cases=$((cases + 1))
if [[ "$GATE_PRESENT" == 1 ]]; then
  scratch_gate "$WORK/nolist"
  scratch_run "$WORK/nolist" "$WORK/base.json"
  if [[ "$rc" -eq 1 && "$out" == *"ABORT"*"(bastion-resources) is missing or empty"* ]]; then pass "a missing bastion-resources list aborts"; else fail "a missing bastion-resources list aborts (rc=$rc)" "$out"; fi
else
  fail "a missing bastion-resources list aborts (gate absent)"
fi
cases=$((cases + 1))
if [[ "$GATE_PRESENT" == 1 ]]; then
  scratch_gate "$WORK/shortlist"
  awk '$0 != "hcloud_server_network.bastion"' "$ROOT/tests/scripts/lib/bastion-resources.txt" > "$WORK/shortlist/bastion-resources.txt"
  scratch_run "$WORK/shortlist" "$WORK/base.json"
  if [[ "$rc" -eq 1 && "$out" == *"ABORT"*"does not list hcloud_server_network.bastion"* ]]; then pass "a list missing an address the gate names aborts"; else fail "a list missing an address the gate names aborts (rc=$rc)" "$out"; fi
else
  fail "a list missing an address the gate names aborts (gate absent)"
fi
cases=$((cases + 1))
if [[ "$GATE_PRESENT" == 1 && "$(BASTION_RESOURCES_FILE="$WORK/shortlist/bastion-resources.txt" "$GATE_FN" "$WORK/base.json" >/dev/null 2>&1; echo $?)" -eq 0 ]]; then
  pass "BASTION_RESOURCES_FILE in the environment does not redirect the gate"
else
  fail "BASTION_RESOURCES_FILE in the environment does not redirect the gate"
fi

# ── Gate mutations: each arm's row, re-driven through row() against a one-edit mutant ──────────
# gmrow <label> <from> <to> <plan> <msg>: the mutant (one exact replacement in the gate, or in the
# create-side checks it sources, sourced from a scratch copy) must make that RED row FAIL through row()
# itself, while the mutant still passes the compliant baseline (so the edit weakened one arm rather
# than breaking the gate wholesale).
# gmut_target <from>: the ONE file (the gate or bastion-gate-common.sh) holding <from> exactly once,
# the other holding it zero times; anything else prints nothing, and the row reports "did not land".
gmut_target() {
  python3 - "$GATE" "$COMMON" "$1" <<'PY'
import sys
g, c, a = sys.argv[1:]
n = [open(f).read().count(a) for f in (g, c)]
if n == [1, 0]: print(g)
elif n == [0, 1]: print(c)
PY
}
# gmut_apply <target-file> <out-file> <from> <to>: writes the one-replacement mutant of <target-file>.
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
gmut_fn() { (source "$GMUT_DIR/bastion-host-birth-gate.sh" && bastion_host_birth_gate "$1"); }
gmrow() {
  local label="$1" from="$2" to="$3" plan="$4" msg="$5" d r target
  GMUT=$((GMUT + 1)); d="$WORK/gmut$GMUT"
  cases=$((cases + 1))
  target=""
  [[ "$GATE_PRESENT" == 1 ]] && target="$(gmut_target "$from")"
  if [[ -z "$target" ]] || ! gmut_apply "$target" "$WORK/gmut$GMUT.sh" "$from" "$to"; then
    fail "gate mutation did not land: $label"; return
  fi
  if [[ "$target" == "$GATE" ]]; then
    scratch_gate "$d" "$WORK/gmut$GMUT.sh"
  else
    scratch_gate "$d" "$GATE" "$WORK/gmut$GMUT.sh"
  fi
  cp "$ROOT/tests/scripts/lib/bastion-resources.txt" "$d/"
  r="$(GATE_FN=gmut_fn; GMUT_DIR="$d"; passes=0; fails=0; row "$label" RED "$plan" "$msg" >/dev/null; printf '%s %s' "$passes" "$fails")"
  scratch_run "$d" "$WORK/base.json"
  if [[ "$r" == "0 1" && "$rc" -eq 0 ]]; then pass "gate mutation caught: $label"; else fail "gate mutation SURVIVED: $label (row passes/fails=$r, mutant baseline rc=$rc)" "$out"; fi
}
echo "Gate mutations"
gmrow "G04 the destroy arm removed (row 4 then refuses only as out-of-scope)" \
  'if [[ "$destroys" -ne 0 ]]; then' 'if false; then' "$ROW4_DELETE" "destroy"
gmrow "G05 the zero-rule arm removed" \
  'if [[ "$fw_rules" -ne 0 ]]; then' 'if false; then' \
  "$(mk "$SET"' set("hcloud_firewall.bastion"; .change.after.rule = [{direction: "in", protocol: "tcp", port: "22", source_ips: ["0.0.0.0/0"]}])')" "FIREWALL CONTENT:"
gmrow "G17 the configuration arm of inline firewall_ids dropped" \
  'select((((.change.after.firewall_ids // []) | length) > 0) or $cfg)' 'select((((.change.after.firewall_ids // []) | length) > 0))' "$INLINE_CFG" "firewall_ids inline"
gmrow "G22 a non-object after_unknown read as known (boolean)" \
  '          or ((.change.after_unknown | type) != "object")
          or ((.change.after_unknown.rule // false) | has_unknown)' '          or ((.change.after_unknown.rule // false) | has_unknown)' \
  "$(mk "$SET"' set("hcloud_firewall.bastion"; .change.after_unknown = true)')" "FIREWALL CONTENT UNREADABLE"
gmrow "G22 a non-object after_unknown read as known (absent)" \
  '          or ((.change.after_unknown | type) != "object")
          or ((.change.after_unknown.rule // false) | has_unknown)' '          or ((.change.after_unknown.rule // false) | has_unknown)' \
  "$(mk "$SET"' set("hcloud_firewall.bastion"; .change |= del(.after_unknown))')" "FIREWALL CONTENT UNREADABLE"
gmrow "G25 a non-array rule read as zero rules" \
  '          or ((.change.after.rule | type) != "array"))] | length' '          )] | length' \
  "$(mk "$SET"' set("hcloud_firewall.bastion"; .change.after.rule = {})')" "FIREWALL CONTENT UNREADABLE"
gmrow "G32 server_ids cardinality relaxed to at-least-one" \
  '((.change.after.server_ids // []) | length) == 1)' '((.change.after.server_ids // []) | length) >= 1)' "$ATT_TWO_IDS" "$ATT_UNBOUND"
gmrow "the server-id reference check moved behind the unknown branch" \
  '    | select($srv == ["hcloud_server.bastion", "hcloud_server.bastion.id"])
    | select($fw == ["hcloud_firewall.bastion", "hcloud_firewall.bastion.id"])
    | select((((.change.after.server_ids // []) | length) == 1) or ((.change.after_unknown.server_ids // false) == true))]' \
  '    | select($fw == ["hcloud_firewall.bastion", "hcloud_firewall.bastion.id"])
    | select((((.change.after.server_ids // []) | length) == 1) or (((.change.after_unknown.server_ids // false) == true) and $srv == ["hcloud_server.bastion", "hcloud_server.bastion.id"]))]' \
  "$ATT_KNOWN_OTHER" "$ATT_UNBOUND"
gmrow "the NIC IP pin dropped" \
  '| select(.change.after.ip == $ip)' '' "$(mk "$SET"' set("hcloud_server_network.bastion"; .change.after.ip = "10.0.1.71")')" "does not pin the private IP"
gmrow "the attachment's label_selectors check dropped" \
  'if [[ "$att_labels" -ne 0 ]]; then' 'if false; then' \
  "$(mk "$SET"' set("hcloud_firewall_attachment.bastion"; .change.after.label_selectors = ["role=web"])')" "LABEL BINDING"
gmrow "the firewall's apply_to check dropped" \
  'if [[ "$fw_apply_to" -ne 0 ]]; then' 'if false; then' \
  "$(mk "$SET"' set("hcloud_firewall.bastion"; .change.after.apply_to = [{label_selector: "role=web", server: null}])')" "LABEL BINDING"

# ── Row 6: the apply consumes the gated plan file ───────────────────────────────────────────
echo "Row 6 (workflow structure)"
JOB="$WORK/job.yml"
# Full-line comments are dropped first: a comment naming the gate, `terraform plan` or the apply
# must neither satisfy nor trip the structure checks below.
awk '/^  bastion_host_create:/{on=1; print; next} on && /^  [a-z0-9_]+:/{on=0} on && !/^[[:space:]]*#/' "$WORKFLOW" > "$JOB"
cases=$((cases + 1))
if [[ -s "$JOB" ]]; then pass "6: the bastion_host_create job exists"; else fail "6: the bastion_host_create job exists"; fi
# The gated plan file is tfplan; after the gate step runs, no step re-plans, and the apply names it.
gate_line=$(grep -n 'bastion_host_birth_gate ' "$JOB" | head -1 | cut -d: -f1)
apply_line=$(grep -nE 'terraform apply .*tfplan' "$JOB" | head -1 | cut -d: -f1)
replans=0
if [[ -n "$gate_line" ]]; then replans=$(tail -n +"$gate_line" "$JOB" | grep -cE 'terraform plan( |$)' || true); fi
cases=$((cases + 1))
if [[ -n "$gate_line" && -n "$apply_line" && "$apply_line" -gt "$gate_line" ]]; then pass "6: the apply of tfplan follows the gate"; else fail "6: the apply of tfplan follows the gate (gate=${gate_line:-none} apply=${apply_line:-none})"; fi
cases=$((cases + 1))
if [[ -n "$gate_line" && "$replans" -eq 0 ]]; then pass "6: no terraform plan runs after the gate"; else fail "6: no terraform plan runs after the gate (re-plans=$replans, gate=${gate_line:-none})"; fi
# Mutation over the extracted job: a re-plan inserted before the apply must be seen.
cases=$((cases + 1))
if [[ -n "$apply_line" ]]; then
  sed "${apply_line}i\\          terraform plan -out=tfplan" "$JOB" > "$WORK/job-mut.yml"
  m=$(tail -n +"$gate_line" "$WORK/job-mut.yml" | grep -cE 'terraform plan( |$)' || true)
  if [[ "$m" -ge 1 ]]; then pass "6 (mutation): an inserted re-plan is detected"; else fail "6 (mutation): an inserted re-plan is NOT detected"; fi
else
  fail "6 (mutation): no apply line to mutate"
fi

# ── H1: the suite goes RED when the gate is replaced by `return 0` ──────────────────────────
# Re-run every RED row through row() itself, in a subshell, against a gate that always passes: each
# must count as a failure there. This proves row()'s RED arm discriminates, not just that the gate does.
echo "H1 (neutered gate)"
neutered() { echo "neutered: PASS"; return 0; }
h1="$(
  GATE_FN=neutered; passes=0; fails=0
  for r in "${RED_ROWS[@]}"; do IFS='|' read -r l p m <<<"$r"; row "$l" RED "$p" "$m" >/dev/null; done
  printf '%s %s' "$passes" "$fails"
)"
cases=$((cases + 1))
if [[ "${#RED_ROWS[@]}" -ge 45 && "$h1" == "0 ${#RED_ROWS[@]}" ]]; then
  pass "H1: all ${#RED_ROWS[@]} RED rows fail against a neutered gate"
else
  fail "H1: RED rows=${#RED_ROWS[@]}, neutered-gate passes/fails=${h1}"
fi

echo
MIN_CASES=68
if [[ "$cases" -lt "$MIN_CASES" ]]; then
  printf 'test-bastion-host-birth-gate: FAIL (only %d assertions ran; floor %d)\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf 'test-bastion-host-birth-gate: FAIL (accounting: passes+fails=%d != cases=%d)\n' "$((passes + fails))" "$cases" >&2
  exit 1
fi
if [[ "$fails" -gt 0 ]]; then
  printf 'test-bastion-host-birth-gate: FAIL (%d of %d assertions failed)\n' "$fails" "$cases" >&2
  exit 1
fi
printf 'test-bastion-host-birth-gate: PASS (%d assertions, 0 failed)\n' "$cases"
