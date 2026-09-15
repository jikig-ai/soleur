#!/usr/bin/env bash
# Tests for tests/scripts/lib/git-data-root-key-arm-gate.sh (#8189, ADR-220, Guard 4).
#
# PROPERTY. Both host-creating gates refuse a plan unless the committed fingerprint file is
# well-formed, data.hcloud_ssh_keys.git_data_root resolved in prior_state to exactly one key
# named soleur-git-data-root whose SHA256 (derived from public_key; Hetzner's own field is
# MD5) equals the file, and every created hcloud_server.git_data carries, as a set of
# strings, exactly {default key id, root key id}.
#
# LAYOUT
#   H  harness rows  — shapes that must PASS, or refuse for the stated harness reason
#   F  Guard 4 fixture rows (fingerprint / presence / membership) plus further negatives
#   R  refusal-surface rows — the per-reason remedy and the reason-word-only ::error annotation
#   C  call-site census — exactly two call sites, one in each gate
#   W  workflow wire — both gate steps export exactly the committed fingerprint path, before the call
#   M  mutation rows  — code edits on COPIES (mutate()), each must drive a named case RED
#
# THE MUTANT FLOOR COUNTS RED VERDICTS, not landed edits: a row adds to mutants_killed only when
# its verdict says the mutant was caught. A mutation that lands and survives does not count.
#
# FIXTURES ARE SYNTHESIZED (cq-test-fixtures-synthesized-only). The keys are generated with
# ssh-keygen into this run's temp dir by the shared harness's root_key_fixtures (the same helper
# both gate suites use) and deleted on exit; no key, public or private, is committed. Plan JSON is
# built with jq, never captured from a real plan.
#
# Overrides (for mutation rows and for RED-against-origin/main runs):
#   GD_ROOT_KEY_ARM       the arm file under test
#   GD_ROOT_KEY_LIB_DIR   the directory the call-site census scans for gate call sites
#   GD_ROOT_KEY_WF_DIR    the workflows directory the census scans for stray call sites, and whose
#                         apply-web-platform-infra.yml the W rows read
#
# Run: bash tests/scripts/test-git-data-root-key-arm.sh

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"
ARM="${GD_ROOT_KEY_ARM:-${ROOT}/tests/scripts/lib/git-data-root-key-arm-gate.sh}"
LIB_DIR="${GD_ROOT_KEY_LIB_DIR:-${ROOT}/tests/scripts/lib}"
WF_DIR="${GD_ROOT_KEY_WF_DIR:-${ROOT}/.github/workflows}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

passes=0
fails=0
mutants_killed=0
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf '  FAIL %s\n' "$1"; printf '       %s\n' "${2:-}"
}

command -v ssh-keygen >/dev/null 2>&1 || { echo "FATAL: ssh-keygen is required (the arm derives SHA256 from public_key with it)" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required" >&2; exit 2; }
python3 -c 'import yaml' >/dev/null 2>&1 || { echo "FATAL: python3 with PyYAML is required (the W rows parse the workflow)" >&2; exit 2; }
[[ -f "$ARM" ]] || { echo "FATAL: arm not found at $ARM" >&2; exit 2; }

# ── Synthesized keys (shared harness) ─────────────────────────────────────────────
# The harness's contract (pass/fail/TMP) is met above. Only its fixture half is used here: the
# arm is graded directly, never through gate_check.
# shellcheck source=tests/scripts/lib/gate-suite-harness.sh
source "${ROOT}/tests/scripts/lib/gate-suite-harness.sh"
root_key_fixtures
ROOT_PUB="$ROOT_KEY_PUB"
OTHER_PUB="$OTHER_KEY_PUB"
# Hetzner's `fingerprint` field is MD5 colon-hex (measured); the fixture carries that shape.
ROOT_MD5="$(ssh-keygen -l -E md5 -f "$TMP/root-key.pub" | awk '{print $2}' | sed 's/^MD5://')"
FP="$GIT_DATA_ROOT_KEY_FINGERPRINT_FILE"
[[ "$FP" == "$TMP/git-data-root-key.fingerprint" && "$(<"$FP")" == "$ROOT_KEY_FP" ]] \
  || { echo "FATAL: root_key_fixtures did not write the anchor at $TMP/git-data-root-key.fingerprint" >&2; exit 2; }

DEFAULT_ID="1111"
ROOT_ID=4242

# base_plan — the canonical PASS plan: the data source resolved in prior_state (id NUMBER),
# hcloud_ssh_key.default in prior_state (id string) and planned no-op, one server create
# carrying both ids as strings.
base_plan() {
  jq -nc --arg pub "$ROOT_PUB" --arg md5 "$ROOT_MD5" --arg def "$DEFAULT_ID" --argjson rid "$ROOT_ID" '
    {
      format_version: "1.2",
      terraform_version: "1.10.5",
      prior_state: {format_version: "1.0", values: {root_module: {resources: [
        {address: "data.hcloud_ssh_keys.git_data_root", mode: "data", type: "hcloud_ssh_keys", name: "git_data_root",
         values: {id: "synthesized", with_selector: "soleur-role=git-data-root",
                  ssh_keys: [{id: $rid, name: "soleur-git-data-root", fingerprint: $md5,
                              labels: {"soleur-role": "git-data-root"}, public_key: $pub}]}},
        {address: "hcloud_ssh_key.default", mode: "managed", type: "hcloud_ssh_key", name: "default",
         values: {id: $def, name: "soleur-web-platform"}}
      ]}}},
      resource_changes: [
        {address: "hcloud_ssh_key.default", mode: "managed", type: "hcloud_ssh_key", name: "default",
         change: {actions: ["no-op"], before: {id: $def}, after: {id: $def}, after_unknown: {}}},
        {address: "hcloud_server.git_data", mode: "managed", type: "hcloud_server", name: "git_data",
         change: {actions: ["create"], before: null,
                  after: {name: "soleur-git-data", ssh_keys: [$def, ($rid | tostring)]},
                  after_unknown: {id: true, ssh_keys: [false, false]}}}
      ]
    }'
}

# Canonical copy of plugins/soleur/test/test-helpers.sh's guard (the fixture-dir-operand-assert
# suite pins every tracked copy byte-identical, so do not reformat it). Executed as a statement
# before a write under a caller-supplied path so the P1b relative-operand ratchet can see the
# operand is absolute.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

# mk <file> [jq-filter] — the base plan with one jq edit applied.
mk() {
  local f="$1" filter="${2:-.}"
  assert_fixture_dir "$f"
  base_plan | jq -c "$filter" > "$f" || { echo "FATAL: fixture filter failed for $f" >&2; exit 2; }
}

# run_arm <arm-file> <plan> <fp> — sets OUT and RC. Run in a child bash so a mutant copy never
# leaks definitions into this shell.
OUT=""
RC=0
run_arm() {
  RC=0
  OUT="$(bash -c 'source "$1" || exit 97; git_data_root_key_arm "$2" "$3"' _ "$1" "$2" "$3" 2>&1)" || RC=$?
}

has_line() { [[ $'\n'"$1"$'\n' == *$'\n'"$2"$'\n'* ]]; }

# check <name> <want: pass|reason-word> <plan> [fp] [arm-file]
check() {
  local name="$1" want="$2" plan="$3" fp="${4-$FP}" arm="${5:-$ARM}"
  run_arm "$arm" "$plan" "$fp"
  if [[ "$want" == "pass" ]]; then
    if [[ "$RC" -eq 0 && "$OUT" == *"git_data_root_key_arm: PASS"* && "$OUT" != *"verdict="* ]]; then
      pass "$name"
    else
      fail "$name (want rc=0 PASS)" "rc=$RC out=$OUT"
    fi
  else
    if [[ "$RC" -eq 1 ]] && has_line "$OUT" "verdict=git_data_root_key_not_in_create reason=${want}"; then
      pass "$name"
    else
      fail "$name (want rc=1 reason=${want})" "rc=$RC out=$OUT"
    fi
  fi
}

printf '\n=== git-data-root-key-arm ===\n\n'

# ── Instrument self-test ──────────────────────────────────────────────────────────
# check() must record a FAILURE when its expectation is wrong in either direction; otherwise
# every row below is decorative. Counters are rolled back so the floor is unaffected.
mk "$TMP/selftest.json"
_p=$passes; _f=$fails
check "SELFTEST (expected to fail): a passing plan demanded as a refusal" "fingerprint" "$TMP/selftest.json" >/dev/null 2>&1
_ok1=$(( fails == _f + 1 ))
check "SELFTEST (expected to fail): a refusing plan demanded as a pass" "pass" "$TMP/selftest.json" "$TMP/absent.fingerprint" >/dev/null 2>&1
_ok2=$(( fails == _f + 2 ))
passes=$_p; fails=$_f
if [[ "$_ok1" -eq 1 && "$_ok2" -eq 1 ]]; then
  printf '  ok   instrument: check() records a failure in both directions\n'
else
  fails=$((fails + 1))
  printf '  FAIL INSTRUMENT: check() did not discriminate (refusal-direction=%s pass-direction=%s); every row below is decorative\n' "$_ok1" "$_ok2"
fi

# ── H: harness rows ───────────────────────────────────────────────────────────────
mk "$TMP/base.json"
check "H1 the base plan (key resolved, fingerprint matches, server carries both ids) => PASS" pass "$TMP/base.json"

# The fixture really does carry a NUMBER in the data source and STRINGS on the server; without
# this positive control H2 could pass on a fixture that never exercised the type difference.
if [[ "$(jq -r '.prior_state.values.root_module.resources[0].values.ssh_keys[0].id | type' "$TMP/base.json")" == "number" \
   && "$(jq -r '[.resource_changes[1].change.after.ssh_keys[] | type] | unique | join(",")' "$TMP/base.json")" == "string" ]]; then
  pass "H2 positive control: the data-source id is a number and the server ids are strings"
else
  fail "H2 positive control: fixture does not exercise number-vs-string" "$(jq -c . "$TMP/base.json")"
fi
check "H2 numeric id in the data source, string on the server => PASS" pass "$TMP/base.json"

mk "$TMP/reordered.json" '.resource_changes[1].change.after.ssh_keys |= reverse'
check "H3 reordered ssh_keys (root id first) => PASS" pass "$TMP/reordered.json"

mk "$TMP/replace.json" '.resource_changes[1].change.actions = ["delete","create"]'
check "H4 a replace (delete+create) carrying both ids => PASS" pass "$TMP/replace.json"

check "H5 missing fingerprint file => RED reason=fingerprint_file_missing" fingerprint_file_missing "$TMP/base.json" "$TMP/absent.fingerprint"
check "H5b empty fingerprint path => RED reason=fingerprint_file_missing" fingerprint_file_missing "$TMP/base.json" ""

printf '%s' "$ROOT_KEY_FP" > "$TMP/fp-no-newline"
check "H6 a fingerprint file without a trailing newline => PASS" pass "$TMP/base.json" "$TMP/fp-no-newline"

printf 'MD5:%s\n' "$ROOT_MD5" > "$TMP/fp-md5"
check "H7 an MD5 anchor (Hetzner's field) is malformed => reason=fingerprint_file_missing" fingerprint_file_missing "$TMP/base.json" "$TMP/fp-md5"
printf '%s\n%s\n' "$ROOT_KEY_FP" "$OTHER_KEY_FP" > "$TMP/fp-two-lines"
check "H8 a two-line anchor is malformed => reason=fingerprint_file_missing" fingerprint_file_missing "$TMP/base.json" "$TMP/fp-two-lines"
printf '%s extra\n' "$ROOT_KEY_FP" > "$TMP/fp-trailing"
check "H9 an anchor with trailing text is malformed => reason=fingerprint_file_missing" fingerprint_file_missing "$TMP/base.json" "$TMP/fp-trailing"

# ── F: Guard 4 fixture rows (the mutation matrix's fixture half) and further negatives ─
# matrix_check counts a Guard 4 row toward MUTANT_FLOOR only when its RED verdict held.
matrix_check() {
  local _f0=$fails
  check "$@"
  [[ "$fails" -eq "$_f0" ]] && mutants_killed=$((mutants_killed + 1))
  return 0
}

mk "$TMP/fp-mismatch.json" "$(printf '.prior_state.values.root_module.resources[0].values.ssh_keys[0].public_key = %s' "$(jq -Rn --arg p "$OTHER_PUB" '$p')")"
matrix_check "F1 [matrix] right name and label, different fingerprint => reason=fingerprint" fingerprint "$TMP/fp-mismatch.json"

mk "$TMP/ds-absent.json" '.prior_state.values.root_module.resources |= map(select(.address != "data.hcloud_ssh_keys.git_data_root"))'
matrix_check "F2 [matrix] data source absent from prior_state => reason=data_source_absent" data_source_absent "$TMP/ds-absent.json"

mk "$TMP/default-only.json" '.resource_changes[1].change.after.ssh_keys = ["1111"] | .resource_changes[1].change.after_unknown.ssh_keys = [false]'
matrix_check "F3 [matrix] created server carries only the default key => reason=server_keys" server_keys "$TMP/default-only.json"

mk "$TMP/deferred.json" '.prior_state.values.root_module.resources |= map(select(.address != "data.hcloud_ssh_keys.git_data_root")) | .resource_changes += [{address:"data.hcloud_ssh_keys.git_data_root",mode:"data",type:"hcloud_ssh_keys",name:"git_data_root",change:{actions:["read"],before:null,after:{with_selector:"soleur-role=git-data-root"},after_unknown:{ssh_keys:true}}}]'
check "F4 a deferred read in resource_changes => reason=data_source_absent" data_source_absent "$TMP/deferred.json"
mk "$TMP/deferred-and-prior.json" '.resource_changes += [{address:"data.hcloud_ssh_keys.git_data_root",mode:"data",type:"hcloud_ssh_keys",name:"git_data_root",change:{actions:["read"],before:null,after:{},after_unknown:{ssh_keys:true}}}]'
check "F5 a deferred read even alongside a prior_state entry => reason=data_source_absent" data_source_absent "$TMP/deferred-and-prior.json"
mk "$TMP/ds-dup.json" '.prior_state.values.root_module.resources += [.prior_state.values.root_module.resources[0]]'
check "F6 the data source twice in prior_state => reason=data_source_absent" data_source_absent "$TMP/ds-dup.json"
mk "$TMP/ds-managed.json" '.prior_state.values.root_module.resources[0].mode = "managed"'
check "F7 the address present but not mode=data => reason=data_source_absent" data_source_absent "$TMP/ds-managed.json"
mk "$TMP/no-prior.json" 'del(.prior_state)'
check "F8 no prior_state at all => reason=data_source_absent" data_source_absent "$TMP/no-prior.json"
mk "$TMP/null-resources.json" '.prior_state.values.root_module.resources = null'
check "F9 prior_state resources null (not an empty pass) => reason=data_source_absent" data_source_absent "$TMP/null-resources.json"
mk "$TMP/null-rc.json" '.resource_changes = null'
check "F10 resource_changes null => refused (data_source_absent)" data_source_absent "$TMP/null-rc.json"
printf 'not json\n' > "$TMP/garbage.json"
check "F11 unparseable plan => refused (data_source_absent)" data_source_absent "$TMP/garbage.json"
check "F12 plan file absent => refused (data_source_absent)" data_source_absent "$TMP/nope.json"

mk "$TMP/zero-keys.json" '.prior_state.values.root_module.resources[0].values.ssh_keys = []'
check "F13 the selector matched nothing (empty list) => reason=key_count" key_count "$TMP/zero-keys.json"
mk "$TMP/two-keys.json" "$(printf '.prior_state.values.root_module.resources[0].values.ssh_keys += [{id: 5151, name: "soleur-git-data-root", fingerprint: "x", labels: {}, public_key: %s}]' "$(jq -Rn --arg p "$OTHER_PUB" '$p')")"
check "F14 two keys carry the label => reason=key_count" key_count "$TMP/two-keys.json"
mk "$TMP/null-keys.json" '.prior_state.values.root_module.resources[0].values.ssh_keys = null'
check "F15 ssh_keys null (not a zero-length pass) => reason=key_count" key_count "$TMP/null-keys.json"

mk "$TMP/wrong-name.json" '.prior_state.values.root_module.resources[0].values.ssh_keys[0].name = "soleur-git-data-root-2"'
check "F16 the one key is named otherwise => reason=name" name "$TMP/wrong-name.json"

mk "$TMP/md5-only.json" '.prior_state.values.root_module.resources[0].values.ssh_keys[0].public_key = null'
check "F17 no public_key to hash (only Hetzner's MD5) => reason=fingerprint" fingerprint "$TMP/md5-only.json"
mk "$TMP/garbage-key.json" '.prior_state.values.root_module.resources[0].values.ssh_keys[0].public_key = "ssh-ed25519 not-base64"'
check "F18 a public_key ssh-keygen cannot parse => reason=fingerprint" fingerprint "$TMP/garbage-key.json"
mk "$TMP/two-line-key.json" "$(printf '.prior_state.values.root_module.resources[0].values.ssh_keys[0].public_key = %s' "$(jq -Rn --arg p "${ROOT_PUB}"$'\n'"${OTHER_PUB}" '$p')")"
check "F19 a public_key carrying two keys => reason=fingerprint" fingerprint "$TMP/two-line-key.json"

mk "$TMP/extra-key.json" '.resource_changes[1].change.after.ssh_keys += ["9999"] | .resource_changes[1].change.after_unknown.ssh_keys += [false]'
check "F20 the server carries a third key => reason=server_keys" server_keys "$TMP/extra-key.json"
mk "$TMP/root-only.json" '.resource_changes[1].change.after.ssh_keys = ["4242"]'
check "F21 the server carries only the root key => reason=server_keys" server_keys "$TMP/root-only.json"
mk "$TMP/keys-unknown.json" 'del(.resource_changes[1].change.after.ssh_keys) | .resource_changes[1].change.after_unknown.ssh_keys = true'
check "F22 the server ssh_keys unknown at plan time => reason=server_keys" server_keys "$TMP/keys-unknown.json"
mk "$TMP/key-element-unknown.json" '.resource_changes[1].change.after.ssh_keys = ["1111", null] | .resource_changes[1].change.after_unknown.ssh_keys = [false, true]'
check "F23 one server ssh_keys element unknown => reason=server_keys" server_keys "$TMP/key-element-unknown.json"
mk "$TMP/after-unknown-true.json" '.resource_changes[1].change.after_unknown = true'
check "F24 after_unknown wholly true => reason=server_keys" server_keys "$TMP/after-unknown-true.json"
mk "$TMP/no-default.json" '.prior_state.values.root_module.resources |= map(select(.address != "hcloud_ssh_key.default"))'
check "F25 hcloud_ssh_key.default not in prior_state (id unknown) => reason=server_keys" server_keys "$TMP/no-default.json"
mk "$TMP/default-replaced.json" '.resource_changes[0].change.actions = ["delete","create"]'
check "F26 hcloud_ssh_key.default planned to change (new id unknown) => reason=server_keys" server_keys "$TMP/default-replaced.json"
mk "$TMP/no-create.json" '.resource_changes[1].change.actions = ["no-op"]'
check "F27 no created hcloud_server.git_data => reason=server_keys" server_keys "$TMP/no-create.json"
mk "$TMP/two-servers.json" '.resource_changes += [(.resource_changes[1] | .change.after.ssh_keys = ["1111"])]'
check "F28 EVERY created server is checked (second one carries only the default) => reason=server_keys" server_keys "$TMP/two-servers.json"
mk "$TMP/same-id.json" '.prior_state.values.root_module.resources[1].values.id = "4242" | .resource_changes[1].change.after.ssh_keys = ["4242"]'
check "F29 default and root key share an id => reason=server_keys" server_keys "$TMP/same-id.json"
mk "$TMP/bad-actions.json" '.resource_changes[1].change.actions = null'
check "F30 a server entry with null actions => refused (data_source_absent)" data_source_absent "$TMP/bad-actions.json"

# ── R: the refusal surface (per-reason remedy; reason-word-only annotation) ──────────
# refusal_surface <name> <reason> <remedy> <plan> [fp] — the refusal carries, for its reason:
#   exactly one ::error line, and it is exactly the fixed-word annotation (the detail never
#   reaches it — the detail can carry an attacker-chosen key name);
#   the verdict line; a detail line; and exactly the remedy for that reason.
REMEDY_SETUP="dispatch apply-git-data-root-key.yml from main; commit its printed fingerprint; re-dispatch"
REMEDY_BREACH="do NOT re-anchor: a key object changed outside Terraform — open an incident (runbook git-data-luks-cutover-5274.md › Breach-triage trigger)"
REMEDY_SHAPE="the plan does not carry exactly the default and root key ids: a plan-shape defect, not a key problem"
refusal_surface() {
  local name="$1" reason="$2" remedy="$3" plan="$4" fp="${5-$FP}"
  local errs n_rem
  run_arm "$ARM" "$plan" "$fp"
  errs="$(grep -E '^::' <<<"$OUT" || true)"
  n_rem="$(grep -c '^git_data_root_key_arm: remedy: ' <<<"$OUT" || true)"
  if [[ "$RC" -eq 1 && "$errs" == "::error title=git-data-root-key-arm::verdict=git_data_root_key_not_in_create reason=${reason}" ]] \
     && has_line "$OUT" "verdict=git_data_root_key_not_in_create reason=${reason}" \
     && grep -q '^git_data_root_key_arm: detail: .' <<<"$OUT" \
     && [[ "$n_rem" -eq 1 ]] && has_line "$OUT" "git_data_root_key_arm: remedy: ${remedy}"; then
    pass "$name"
  else
    fail "$name" "rc=$RC annotations=[$errs] remedies=$n_rem out=$OUT"
  fi
}
refusal_surface "R1 fingerprint_file_missing => annotation + setup remedy" fingerprint_file_missing "$REMEDY_SETUP" "$TMP/base.json" "$TMP/absent.fingerprint"
refusal_surface "R2 data_source_absent => annotation + setup remedy" data_source_absent "$REMEDY_SETUP" "$TMP/ds-absent.json"
refusal_surface "R3 fingerprint => annotation + do-NOT-re-anchor incident remedy" fingerprint "$REMEDY_BREACH" "$TMP/fp-mismatch.json"
refusal_surface "R4 key_count => annotation + do-NOT-re-anchor incident remedy" key_count "$REMEDY_BREACH" "$TMP/two-keys.json"
refusal_surface "R5 name => annotation + do-NOT-re-anchor incident remedy" name "$REMEDY_BREACH" "$TMP/wrong-name.json"
refusal_surface "R6 server_keys => annotation + plan-shape remedy" server_keys "$REMEDY_SHAPE" "$TMP/default-only.json"
refusal_surface "R7 an unreadable plan (the preamble's refusal) => annotation + setup remedy" data_source_absent "$REMEDY_SETUP" "$TMP/garbage.json"
# The detail really does carry the key name on R5's fixture; the annotation really does not. Without
# this positive control R5's exact-match could pass on a detail that never named anything.
run_arm "$ARM" "$TMP/wrong-name.json" "$FP"
if grep -q '^git_data_root_key_arm: detail: .*soleur-git-data-root-2' <<<"$OUT" \
   && ! grep -E '^::' <<<"$OUT" | grep -q 'soleur-git-data-root-2'; then
  pass "R8 positive control: the key name is in the detail line and absent from the annotation"
else
  fail "R8 positive control: key name placement" "out=$OUT"
fi

# ── C: call-site census ───────────────────────────────────────────────────────────
# An INVOCATION is a line whose first token (optionally after `if !`) is the function name
# followed by whitespace. A definition (`name() {`) and a comment (`# ... name ...`) are not.
CALL_RE='^[[:space:]]*(if[[:space:]]+![[:space:]]*)?git_data_root_key_arm[[:space:]]'
SOURCE_RE='^[[:space:]]*source[[:space:]].*git-data-root-key-arm-gate\.sh"?[[:space:]]*$'

# census <lib-dir> <wf-dir> — prints its report; returns 0 iff exactly one call in each gate,
# zero anywhere else, and each gate sources the arm.
census() {
  local lib="$1" wf="$2" f n total=0 ok=0 others=""
  local rg="$lib/git-data-host-replace-gate.sh" bg="$lib/git-data-host-birth-gate.sh"
  for f in "$lib"/*.sh "$wf"/*.yml "$wf"/*.yaml; do
    [[ -f "$f" ]] || continue
    n=$(grep -cE "$CALL_RE" "$f" || true)
    total=$((total + n))
    if [[ "$n" -gt 0 && "$f" != "$rg" && "$f" != "$bg" ]]; then others+=" $(basename "$f")=$n"; fi
  done
  local nr nb sr sb
  nr=$(grep -cE "$CALL_RE" "$rg" 2>/dev/null || true); nr=${nr:-0}
  nb=$(grep -cE "$CALL_RE" "$bg" 2>/dev/null || true); nb=${nb:-0}
  sr=$(grep -cE "$SOURCE_RE" "$rg" 2>/dev/null || true); sr=${sr:-0}
  sb=$(grep -cE "$SOURCE_RE" "$bg" 2>/dev/null || true); sb=${sb:-0}
  echo "census: total=${total} replace=${nr} birth=${nb} replace_sources=${sr} birth_sources=${sb} others=[${others# }]"
  [[ "$total" -eq 2 && "$nr" -eq 1 && "$nb" -eq 1 && "$sr" -ge 1 && "$sb" -ge 1 && -z "$others" ]] && ok=1
  [[ "$ok" -eq 1 ]]
}

if c_out="$(census "$LIB_DIR" "$WF_DIR")"; then
  pass "C1 exactly two call sites, one in each gate, and both gates source the arm ($c_out)"
else
  fail "C1 call-site census" "$c_out"
fi

# Non-vacuity for the census: the scan really reached files (a glob that matched nothing would
# report total=0 and fail C1, but assert the population explicitly as a lower bound).
_n_scanned=$(find "$LIB_DIR" -maxdepth 1 -name '*.sh' | wc -l)
if [[ "$_n_scanned" -ge 3 && -f "$LIB_DIR/git-data-host-replace-gate.sh" && -f "$LIB_DIR/git-data-host-birth-gate.sh" ]]; then
  pass "C2 the census population is non-empty (${_n_scanned} lib files, both gates present)"
else
  fail "C2 census population" "scanned=${_n_scanned} in $LIB_DIR"
fi

# The call sits INSIDE each gate's function body, not at file scope where it would run at
# source time against no plan at all.
_in_fn() {  # <file> <fn-name>
  awk -v fn="$2" -v re="$CALL_RE" '
    $0 ~ "^" fn "\\(\\) \\{" { inside = 1; next }
    inside && /^}/ { inside = 0 }
    inside && $0 ~ re { found = 1 }
    END { exit found ? 0 : 1 }' "$1"
}
if _in_fn "$LIB_DIR/git-data-host-replace-gate.sh" git_data_host_replace_gate \
   && _in_fn "$LIB_DIR/git-data-host-birth-gate.sh" git_data_host_birth_gate; then
  pass "C3 each call site is inside its gate's function body"
else
  fail "C3 a call site is outside its gate function" ""
fi

# ── W: the workflow wire (#8189 review B1) ────────────────────────────────────────
# The arm reads its anchor from GIT_DATA_ROOT_KEY_FINGERPRINT_FILE, which each gate step exports.
# Deleting that export makes the arm refuse (fail closed), but RE-POINTING it at a file the run
# writes itself would make the arm compare against an anchor of the attacker's choosing, and no
# gate suite can see a workflow line. wire_pin parses the workflow (PyYAML, as Actions does) and,
# for each job, requires: exactly one step whose run: calls `if ! <gate> tfplan.json; then`;
# in that step exactly one non-comment line naming the variable, equal to the literal export of
# the committed path; positioned BEFORE the call, at the call's own indentation (not inside a
# branch the call does not share).
WF_FILE_NAME="apply-web-platform-infra.yml"
# wire_pin <workflow-file> — prints one report line; rc 0 iff both jobs hold.
wire_pin() {
  python3 - "$1" <<'PYEOF'
import sys, re, yaml
LIT = 'export GIT_DATA_ROOT_KEY_FINGERPRINT_FILE="${GITHUB_WORKSPACE}/apps/web-platform/infra/git-data-root-key.fingerprint"'
JOBS = {"git_data_host_replace": "git_data_host_replace_gate", "git_data_host_create": "git_data_host_birth_gate"}
try:
    wf = yaml.safe_load(open(sys.argv[1]))
except Exception as e:
    print(f"wire: unparseable workflow ({type(e).__name__})"); sys.exit(1)
# PyYAML reads the bare key `on:` as boolean True.
on = wf.get(True) or wf.get("on") if isinstance(wf, dict) else None
if not isinstance(on, dict) or "workflow_dispatch" not in on or not isinstance(wf.get("jobs"), dict):
    print("wire: not a dispatchable workflow with jobs"); sys.exit(1)
bad, good = [], []
for job, gate in JOBS.items():
    steps = (wf["jobs"].get(job) or {}).get("steps")
    if not isinstance(steps, list):
        bad.append(f"{job}: no steps"); continue
    call_re = re.compile(r"^(\s*)if ! " + re.escape(gate) + r" tfplan\.json; then$")
    hits = [st for st in steps if isinstance(st, dict) and isinstance(st.get("run"), str)
            and any(call_re.match(l) for l in st["run"].split("\n"))]
    if len(hits) != 1:
        bad.append(f"{job}: {len(hits)} steps call {gate} (want 1)"); continue
    lines = hits[0]["run"].split("\n")
    calls = [i for i, l in enumerate(lines) if call_re.match(l)]
    if len(calls) != 1:
        bad.append(f"{job}: {len(calls)} call lines (want 1)"); continue
    names = [i for i, l in enumerate(lines)
             if "GIT_DATA_ROOT_KEY_FINGERPRINT_FILE" in l and not l.lstrip().startswith("#")]
    if len(names) != 1:
        bad.append(f"{job}: {len(names)} non-comment lines name GIT_DATA_ROOT_KEY_FINGERPRINT_FILE (want exactly 1, the export)"); continue
    i, c = names[0], calls[0]
    ind = lambda l: len(l) - len(l.lstrip())
    if lines[i].strip() != LIT:
        bad.append(f"{job}: the export is not the committed path literal"); continue
    if i > c:
        bad.append(f"{job}: the export is AFTER the gate call"); continue
    if ind(lines[i]) != ind(lines[c]):
        bad.append(f"{job}: the export is not at the gate call's indentation"); continue
    good.append(job)
print(f"wire: ok=[{' '.join(good)}] bad=[{'; '.join(bad)}]")
sys.exit(0 if not bad and len(good) == len(JOBS) else 1)
PYEOF
}

if w_out="$(wire_pin "$WF_DIR/$WF_FILE_NAME")"; then
  pass "W1 both gate steps export exactly the committed fingerprint path before the gate call ($w_out)"
else
  fail "W1 fingerprint export wire" "$w_out"
fi

# wf_mutate <name> <job> <op> — writes $TMP/wf-<name>.yml: the workflow with ONE edit, inside
# <job>'s text only, to its export line. Ops: delete | repoint | after-call | branch | reassign. Asserts
# the edit landed (the copy differs). Sets MUT_WF_FILE.
MUT_WF_FILE=""
wf_mutate() {
  local name="$1" job="$2" op="$3" dst="$TMP/wf-$1.yml"
  assert_fixture_dir "$TMP"
  python3 - "$WF_DIR/$WF_FILE_NAME" "$dst" "$job" "$op" <<'PYEOF' || { fail "W-$name mutation LANDED" "the mutator could not apply op=$op in job $job"; return 1; }
import sys, re
src, dst, job, op = sys.argv[1:5]
L = open(src).read().split("\n")
start = next(i for i, l in enumerate(L) if l == f"  {job}:")
end = next((i for i in range(start + 1, len(L)) if re.match(r"^  [A-Za-z0-9_-]+:$", L[i])), len(L))
exp = [i for i in range(start, end) if L[i].lstrip().startswith("export GIT_DATA_ROOT_KEY_FINGERPRINT_FILE=")]
call = [i for i in range(start, end) if re.match(r"^\s*if ! git_data_host_(replace|birth)_gate tfplan\.json; then$", L[i])]
assert len(exp) == 1 and len(call) == 1
e, c = exp[0], call[0]
indent = L[e][: len(L[e]) - len(L[e].lstrip())]
if op == "delete":
    del L[e]
elif op == "repoint":
    L[e] = indent + 'export GIT_DATA_ROOT_KEY_FINGERPRINT_FILE="${RUNNER_TEMP}/git-data-root-key.fingerprint"'
elif op == "after-call":
    line = L.pop(e); c -= 1
    L.insert(c + 1, line)
elif op == "branch":
    L[e:e + 1] = [indent + "if false; then", indent + "  " + L[e].lstrip(), indent + "fi"]
elif op == "reassign":
    L.insert(e + 1, indent + 'GIT_DATA_ROOT_KEY_FINGERPRINT_FILE="${RUNNER_TEMP}/fp"')
else:
    sys.exit(1)
open(dst, "w").write("\n".join(L))
PYEOF
  if cmp -s "$WF_DIR/$WF_FILE_NAME" "$dst"; then
    fail "W-$name mutation LANDED" "op=$op in $job changed nothing"
    return 1
  fi
  MUT_WF_FILE="$dst"
}

# wire_red <label> <job> — the wire pin must go RED on MUT_WF_FILE, naming <job> as the bad one.
wire_red() {
  local out
  if ! out="$(wire_pin "$MUT_WF_FILE")" && [[ "$out" == *"bad=["*"$2:"* ]]; then
    pass "$1 ($out)"
    mutants_killed=$((mutants_killed + 1))
  else
    fail "$1 — the wire pin stayed green or blamed the wrong job" "$out"
  fi
}

wf_mutate del-replace git_data_host_replace delete && wire_red "W2 [mutant] export deleted from the replace step => wire RED" git_data_host_replace
wf_mutate del-create git_data_host_create delete && wire_red "W3 [mutant] export deleted from the create step => wire RED" git_data_host_create
wf_mutate repoint-replace git_data_host_replace repoint && wire_red "W4 [mutant] replace export re-pointed at a run-written path => wire RED" git_data_host_replace
wf_mutate repoint-create git_data_host_create repoint && wire_red "W5 [mutant] create export re-pointed at a run-written path => wire RED" git_data_host_create
wf_mutate after-replace git_data_host_replace after-call && wire_red "W6 [mutant] replace export moved after the gate call => wire RED" git_data_host_replace
wf_mutate reassign-create git_data_host_create reassign && wire_red "W7 [mutant] create step reassigns the variable after the export => wire RED" git_data_host_create
wf_mutate branch-replace git_data_host_replace branch && wire_red "W8 [mutant] replace export wrapped in a branch that never runs => wire RED" git_data_host_replace

# ── M: mutation rows ──────────────────────────────────────────────────────────────
# mutate <name> <file-under-lib> <expected-changed-lines> <sed-expr> — copies the WHOLE lib dir
# (the gates source the arm by their own directory) and the workflows dir, edits ONE file in
# the copy, and asserts the edit landed on exactly the expected number of lines. Sets MUT_LIB.
MUT_LIB=""
MUT_WF=""
mutate() {
  local name="$1"
  local target="$2"
  local want="$3"
  local expr="$4"
  local root="$TMP/mut-$name"
  local changed
  rm -rf "$root"; mkdir -p "$root/lib" "$root/wf"
  cp "$LIB_DIR"/*.sh "$root/lib/" || { echo "FATAL: mutation copy failed for $name" >&2; exit 2; }
  cp "$WF_DIR"/*.yml "$root/wf/" 2>/dev/null || true
  sed -i "$expr" "$root/lib/$target" || { echo "FATAL: sed failed for $name" >&2; exit 2; }
  changed=$(diff "$LIB_DIR/$target" "$root/lib/$target" | grep -c '^[<>]' || true)
  if [[ "$changed" -eq 0 ]]; then
    fail "M-$name mutation LANDED" "sed [$expr] changed nothing in $target — the row would test the baseline"
    return 1
  fi
  if [[ "$changed" -ne "$want" ]]; then
    fail "M-$name mutation landed on exactly $want diff line(s)" "sed [$expr] changed $changed diff lines in $target"
    return 1
  fi
  MUT_LIB="$root/lib"
  MUT_WF="$root/wf"
  return 0
}

# mutant_red <label> <want-reason> <plan> [fp] — asserts the NAMED case goes RED on MUT_LIB's arm:
# the case's own expectation (rc=1 with that reason) no longer holds. A kill adds to the floor.
#
# The mutant must still PASS the base plan first: a sed that broke the jq program would refuse
# EVERYTHING (as data_source_absent), and the named case would read RED for the wrong reason.
mutant_red() {
  local label="$1" want="$2" plan="$3" fp="${4-$FP}"
  run_arm "$MUT_LIB/git-data-root-key-arm-gate.sh" "$TMP/base.json" "$FP"
  if [[ "$RC" -ne 0 ]]; then
    fail "$label — the mutant no longer PASSes the base plan; it is broken, not neutered" "rc=$RC out=$OUT"
    return
  fi
  run_arm "$MUT_LIB/git-data-root-key-arm-gate.sh" "$plan" "$fp"
  if [[ "$RC" -eq 1 ]] && has_line "$OUT" "verdict=git_data_root_key_not_in_create reason=${want}"; then
    fail "$label — SURVIVED: the case still holds against the mutant; the arm is not load-bearing" "rc=$RC out=$OUT"
  else
    pass "$label"
    mutants_killed=$((mutants_killed + 1))
  fi
}

# ── mutant_red's own self-test, both directions (#8189 review B8) ────────────────────
# Driven against an UNMUTATED copy, where the verdict is known in advance:
#   known-GREEN  F1's case holds on the unmutated arm, so mutant_red must record SURVIVED (a fail);
#   known-RED    demanding reason=fingerprint of the base plan, which PASSes, must record killed.
# Counters (passes, fails, mutants_killed) are rolled back. An instrument that cannot tell the two
# apart makes every M row decorative, so a broken one ends the suite here.
rm -rf "$TMP/mut-selftest"; mkdir -p "$TMP/mut-selftest/lib"
cp "$LIB_DIR"/*.sh "$TMP/mut-selftest/lib/" || { echo "FATAL: self-test copy failed" >&2; exit 2; }
_p=$passes; _f=$fails; _k=$mutants_killed
MUT_LIB="$TMP/mut-selftest/lib"
mutant_red "SELFTEST known-GREEN (expected SURVIVED)" fingerprint "$TMP/fp-mismatch.json" >/dev/null 2>&1
_ok_green=$(( fails == _f + 1 && passes == _p && mutants_killed == _k ))
mutant_red "SELFTEST known-RED (expected killed)" fingerprint "$TMP/base.json" >/dev/null 2>&1
_ok_red=$(( fails == _f + 1 && passes == _p + 1 && mutants_killed == _k + 1 ))
passes=$_p; fails=$_f; mutants_killed=$_k; MUT_LIB=""
if [[ "$_ok_green" -ne 1 || "$_ok_red" -ne 1 ]]; then
  printf '  FAIL INSTRUMENT: mutant_red() did not discriminate (known-GREEN recorded-survived=%s known-RED recorded-killed=%s); every M row is decorative\n' "$_ok_green" "$_ok_red"
  echo ""
  echo "=== test-git-data-root-key-arm.sh: ${passes} passed, $((fails + 1)) failed ==="
  exit 1
fi
printf '  ok   instrument: mutant_red() records SURVIVED on a known-GREEN case and a kill on a known-RED one\n'

# M1 [matrix] remove the arm call from the BIRTH gate copy (the replace gate keeps it) => the
# census goes RED. 1 diff line: the call line deleted.
if mutate birth-call-removed git-data-host-birth-gate.sh 1 '/^[[:space:]]*git_data_root_key_arm[[:space:]]/d'; then
  if ! c_out="$(census "$MUT_LIB" "$MUT_WF")" && [[ "$c_out" == *"replace=1"* && "$c_out" == *"birth=0"* ]]; then
    pass "M1 [matrix] arm call removed from the birth gate only => call-site census RED ($c_out)"; mutants_killed=$((mutants_killed + 1))
  else
    fail "M1 [matrix] census stayed green with the birth gate's call removed" "$c_out"
  fi
fi

# M2 the same on the REPLACE gate copy.
if mutate replace-call-removed git-data-host-replace-gate.sh 1 '/^[[:space:]]*git_data_root_key_arm[[:space:]]/d'; then
  if ! c_out="$(census "$MUT_LIB" "$MUT_WF")" && [[ "$c_out" == *"replace=0"* ]]; then
    pass "M2 arm call removed from the replace gate only => call-site census RED ($c_out)"; mutants_killed=$((mutants_killed + 1))
  else
    fail "M2 census stayed green with the replace gate's call removed" "$c_out"
  fi
fi

# M3 a THIRD call site in another lib file => census RED (exactly, not at-least).
if mutate third-call-site plan-gate-preamble.sh 1 '1a git_data_root_key_arm "$plan" "$fp"'; then
  if ! c_out="$(census "$MUT_LIB" "$MUT_WF")" && [[ "$c_out" == *"plan-gate-preamble.sh=1"* ]]; then
    pass "M3 a third call site elsewhere => call-site census RED ($c_out)"; mutants_killed=$((mutants_killed + 1))
  else
    fail "M3 census stayed green with a third call site" "$c_out"
  fi
fi

# M4 [matrix fingerprint] neuter the fingerprint comparison => F1 goes RED.
if mutate fp-compare git-data-root-key-arm-gate.sh 2 's/^  if \[\[ "\$got" != "\$want" \]\]; then$/  if false; then/'; then
  mutant_red "M4 [matrix fingerprint] fingerprint comparison neutered => F1 goes RED" fingerprint "$TMP/fp-mismatch.json"
fi

# M5 neuter the prior_state presence arm => F2's reason=data_source_absent no longer holds.
if mutate presence git-data-root-key-arm-gate.sh 2 's/^            elif (\$ds | length) != 1 then$/            elif false then/'; then
  mutant_red "M5 presence arm neutered => F2 goes RED" data_source_absent "$TMP/ds-absent.json"
fi

# M6 neuter the deferred-read arm => F4's reason no longer holds... F4 also has no prior_state
# entry, so use F5 (deferred read ALONGSIDE a prior_state entry), where only this arm objects.
if mutate deferred git-data-root-key-arm-gate.sh 2 's/^          | if (\$deferred | length) > 0 then$/          | if false then/'; then
  mutant_red "M6 deferred-read arm neutered => F5 goes RED" data_source_absent "$TMP/deferred-and-prior.json"
fi

# M7 neuter the server set comparison => F3 no longer refuses.
if mutate server-set git-data-root-key-arm-gate.sh 2 's/^                                or ((\$c.after.ssh_keys | map(.*) | unique) != \$want)$/                                or false/'; then
  mutant_red "M7 [matrix membership] server set comparison neutered => F3 goes RED" server_keys "$TMP/default-only.json"
fi

# M8 neuter the key-count arm => F14 (two labelled keys) no longer says key_count.
if mutate key-count git-data-root-key-arm-gate.sh 2 's/^            elif (\$ds\[0\].values.ssh_keys | length) != 1 then$/            elif false then/'; then
  mutant_red "M8 key-count arm neutered => F14 goes RED" key_count "$TMP/two-keys.json"
fi

# M9 neuter the name arm => F16 no longer says name.
if mutate name git-data-root-key-arm-gate.sh 2 's/^              | if \$key.name != "soleur-git-data-root" then$/              | if false then/'; then
  mutant_red "M9 name arm neutered => F16 goes RED" name "$TMP/wrong-name.json"
fi

# M10 neuter the default-key-changing arm => F26 no longer says server_keys.
if mutate default-moving git-data-root-key-arm-gate.sh 2 's/^                    elif (\$def_moving | length) > 0 then$/                    elif false then/'; then
  mutant_red "M10 default-key-changing arm neutered => F26 goes RED" server_keys "$TMP/default-replaced.json"
fi

# M11 accept a MALFORMED anchor => H9 (trailing text) no longer refuses with its reason; the
# arm then compares a garbage anchor and refuses for `fingerprint` instead.
if mutate anchor-malformed git-data-root-key-arm-gate.sh 2 's/^  if \[\[ ! "\$want" =~ \^SHA256:\[A-Za-z0-9+\/\]{43}\$ \]\]; then$/  if false; then/'; then
  mutant_red "M11 malformed-anchor arm neutered => H9 goes RED" fingerprint_file_missing "$TMP/base.json" "$TMP/fp-trailing"
fi

# M12 LAYERED, measured: neuter the missing-file arm and a missing anchor is STILL refused with
# the same reason, because the malformed arm reads an empty string. The row pins that layering
# (refused, never PASS) rather than claiming the existence check is a sole guard.
if mutate anchor-missing git-data-root-key-arm-gate.sh 2 's/^  if \[\[ -z "\$fp_file" || ! -f "\$fp_file" || ! -r "\$fp_file" \]\]; then$/  if false; then/'; then
  run_arm "$MUT_LIB/git-data-root-key-arm-gate.sh" "$TMP/base.json" "$TMP/absent.fingerprint"
  if [[ "$RC" -eq 1 ]] && has_line "$OUT" "verdict=git_data_root_key_not_in_create reason=fingerprint_file_missing" && [[ "$OUT" == *"is malformed"* ]]; then
    pass "M12 missing-file arm neutered => H5 still refused, by the malformed arm (layered, never PASS)"; mutants_killed=$((mutants_killed + 1))
  else
    fail "M12 layered contract broken: with the missing-file arm neutered, H5 was not refused by the malformed arm" "rc=$RC out=$OUT"
  fi
fi

# M13 LAYERED: delete the preamble call and an unreadable plan is STILL refused with the same
# reason (the arm's own jq cannot parse it), but the preamble's ABORT line is gone. The row pins
# that the call is invoked (its signature appears on the unmutated arm) and never opens a PASS.
if mutate preamble-call git-data-root-key-arm-gate.sh 4 '/^  plan_gate_assert_readable "git_data_root_key_arm" "\$plan_json" || {$/,/^  }$/d'; then
  run_arm "$ARM" "$TMP/garbage.json" "$FP"
  _own_base="$OUT"
  run_arm "$MUT_LIB/git-data-root-key-arm-gate.sh" "$TMP/garbage.json" "$FP"
  if [[ "$_own_base" == *"git_data_root_key_arm: ABORT"* ]] \
     && [[ "$RC" -eq 1 && "$OUT" != *"git_data_root_key_arm: ABORT"* ]] \
     && has_line "$OUT" "verdict=git_data_root_key_not_in_create reason=data_source_absent"; then
    pass "M13 preamble call deleted => the unreadable plan is still refused, by the arm's jq (layered, never PASS)"; mutants_killed=$((mutants_killed + 1))
  else
    fail "M13 layered contract broken for the preamble call" "base=$_own_base | rc=$RC out=$OUT"
  fi
fi

# Control: the UNMUTATED copies, run through the same copy path, stay GREEN. Without it a
# copy step that broke sourcing would read as a caught mutation.
rm -rf "$TMP/mut-control"; mkdir -p "$TMP/mut-control/lib" "$TMP/mut-control/wf"
cp "$LIB_DIR"/*.sh "$TMP/mut-control/lib/"; cp "$WF_DIR"/*.yml "$TMP/mut-control/wf/" 2>/dev/null || true
if c_out="$(census "$TMP/mut-control/lib" "$TMP/mut-control/wf")"; then
  pass "M-control: the unmutated copy passes the census"
else
  fail "M-control: the unmutated copy fails the census" "$c_out"
fi
check "M-control: the unmutated arm copy PASSes the base plan" pass "$TMP/base.json" "$FP" "$TMP/mut-control/lib/git-data-root-key-arm-gate.sh"

# ── Floors ────────────────────────────────────────────────────────────────────────
# MUTANT_FLOOR counts KILLS (RED verdicts): 3 Guard 4 fixture rows (F1-F3) + 13 mutate() rows
# (M1 is Guard 4's code-edit row; M12 and M13 count on their layered verdict) + 7 workflow-wire
# mutants (W2-W8). A row whose mutation did not land, or whose mutant survived, does not count.
MUTANT_FLOOR=23
if [[ "$mutants_killed" -lt "$MUTANT_FLOOR" ]]; then
  fails=$((fails + 1))
  printf '  FAIL MUTANT FLOOR: only %s mutants were killed, floor is %s\n' "$mutants_killed" "$MUTANT_FLOOR"
else
  printf '  ok   mutant floor: %s mutants killed (floor %s)\n' "$mutants_killed" "$MUTANT_FLOOR"
fi

# ASSERTION FLOOR — self-contained (bash builtins and this suite's counters only), a floor not
# an equality. Set from the green run.
FLOOR=75
_ran=$((passes + fails))
if [[ "$_ran" -lt "$FLOOR" ]]; then
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is %s. Rows were deleted, skipped, or the suite exited early.\n' "$_ran" "$FLOOR"
  echo ""
  echo "=== test-git-data-root-key-arm.sh: ${passes} passed, $((fails + 1)) failed ==="
  exit 1
fi
printf '  ok   anti-vacuity floor: %s assertions ran (floor %s)\n' "$_ran" "$FLOOR"

echo ""
echo "=== test-git-data-root-key-arm.sh: ${passes} passed, ${fails} failed ==="
[ "$fails" -eq 0 ] || exit 1
