#!/usr/bin/env bash
# Tests for tests/scripts/lib/git-data-plaintext-destroy-gate.sh (sourced by the destroy job in
# .github/workflows/git-data-plaintext-volume-destroy.yml, Option B of the W0 plaintext-volume route).
#
# The gate reads a `terraform show -json <plan>` document and PASSes (rc=0) iff the plan deletes
# the plaintext git-data volume 106867358 (name soleur-git-data-store) — optionally together with
# its attachment, which must bind that volume and server 170370833 — and changes nothing else.
# Entries whose actions are EXACTLY ["no-op"] or EXACTLY ["read"] (the -target closure pulls the
# server, module and data sources in) are ignorable; anything else is out of scope.
#
# Guard Contract (plan knowledge-base/project/plans/2026-10-26-feat-git-data-plaintext-volume-
# terraform-destroy-plan.md): M1-M9 must drive the gate RED, P1-P3 must stay GREEN, fixtures are
# type-faithful (volume before.id is a STRING; attachment volume_id/server_id are NUMBERS), and
# replacing the gate body with `return 0` must turn a must-RED fixture GREEN (H1).
#
# All fixtures are SYNTHESIZED (cq-test-fixtures-synthesized-only). Deterministic; no network.
#
# Run: bash tests/scripts/test-git-data-plaintext-destroy-gate.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${DIR}/lib/git-data-plaintext-destroy-gate.sh"
# shellcheck source=tests/scripts/lib/git-data-plaintext-destroy-gate.sh
source "$LIB"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

# INSTRUMENT SELF-TEST. Drives both helpers once and refuses to continue unless both counters
# moved, reported with printf + exit so it does not flow through the helpers it guards.
_p0=$passes; _f0=$fails
pass; fail "instrument self-test (expected, ignore)" 2>/dev/null
if [[ "$passes" -ne $((_p0 + 1)) || "$fails" -ne $((_f0 + 1)) ]]; then
  printf 'FATAL: instrument self-test: pass()/fail() did not move their counters\n'
  exit 1
fi
passes=$_p0; fails=$_f0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
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
assert_fixture_dir "$TMP"

PIN=106867358

# ── fixture builders (type-faithful) ────────────────────────────────────────────────
# Volume: before.id is a STRING in the hcloud provider's state.
vol_entry() { # id name actions-json
  jq -n --arg id "$1" --arg name "$2" --argjson act "$3" \
    '{address:"hcloud_volume.git_data",mode:"managed",type:"hcloud_volume",name:"git_data",
      change:{actions:$act,before:{id:$id,name:$name,size:10},after:null}}'
}
# Attachment: volume_id / server_id are NUMBERS.
att_entry() { # volume_id server_id actions-json
  jq -n --argjson v "$1" --argjson s "$2" --argjson act "$3" \
    '{address:"hcloud_volume_attachment.git_data",mode:"managed",type:"hcloud_volume_attachment",name:"git_data",
      change:{actions:$act,before:{id:"x",volume_id:$v,server_id:$s,automount:false},after:null}}'
}
other_entry() { # address actions-json [mode]
  jq -n --arg a "$1" --argjson act "$2" --arg m "${3:-managed}" \
    '{address:$a,mode:$m,change:{actions:$act,before:{id:"107140231"},after:null}}'
}
VOL="$(vol_entry 106867358 soleur-git-data-store '["delete"]')"
ATT="$(att_entry 106867358 170370833 '["delete"]')"
SRV_NOOP="$(other_entry hcloud_server.git_data '["no-op"]')"
LUKS_NOOP="$(other_entry hcloud_volume.git_data_luks '["no-op"]')"
PW_NOOP="$(other_entry random_password.git_data_luks '["no-op"]')"
DATA_READ="$(other_entry data.hcloud_ssh_keys.git_data_root '["read"]' data)"

write_plan() { # comma-joined entries -> $TMP/plan.json
  assert_fixture_dir "$TMP"
  printf '{"format_version":"1.2","resource_changes":[%s]}' "$1" > "$TMP/plan.json"
}

run_gate() { git_data_plaintext_destroy_gate "$TMP/plan.json" "${1-$PIN}"; }

# expect_green <label> / expect_red <label> <verdict-needle>
expect_green() {
  local out
  if out=$(run_gate "${2:-$PIN}" 2>&1); then pass; else fail "$1: expected PASS, got: ${out}"; fi
}
expect_red() {
  local out
  if out=$(run_gate "${3-$PIN}" 2>&1); then
    fail "$1: expected REFUSE, gate passed"
  elif [[ "$out" == *"$2"* ]]; then
    pass
  else
    fail "$1: refused but verdict '$2' not named; got: ${out}"
  fi
}

# ── must-PASS rows (P1-P3: none of them is the single canonical shape) ──────────────
write_plan "${VOL},${ATT}"
expect_green "P1a volume + attachment deletes"
write_plan "${VOL}"
expect_green "P1b attachment already gone: volume delete only"
write_plan "${ATT},${VOL}"
expect_green "P2 reordered resource_changes"
write_plan "${SRV_NOOP},${VOL},${LUKS_NOOP},${ATT},${PW_NOOP},${DATA_READ}"
expect_green "P3 extra no-op and read entries (server, LUKS volume, passphrase, data source)"

# ── must-RED rows (M1-M9) ───────────────────────────────────────────────────────────
LUKS_DELETE="$(other_entry hcloud_volume.git_data_luks '["delete"]')"
write_plan "${VOL},${ATT},${LUKS_DELETE}"
expect_red "M1 LUKS volume (107140231) deleted" "out_of_scope_change"

SRV_UPDATE="$(other_entry hcloud_server.git_data '["update"]')"
write_plan "${VOL},${ATT},${SRV_UPDATE}"
expect_red "M2 third non-ignorable change after two compliant deletes" "out_of_scope_change"

write_plan "$(vol_entry 106867359 soleur-git-data-store '["delete"]'),${ATT}"
expect_red "M3a wrong volume id" "wrong_volume_identity"
write_plan "$(vol_entry 106867358 soleur-git-data-store-luks '["delete"]'),${ATT}"
expect_red "M3b wrong volume name" "wrong_volume_identity"

write_plan "$(vol_entry 106867358 soleur-git-data-store '["delete","create"]'),${ATT}"
expect_red "M4a replace (delete,create)" "not_pure_delete"
write_plan "$(vol_entry 106867358 soleur-git-data-store '["create","delete"]'),${ATT}"
expect_red "M4b replace (create,delete)" "not_pure_delete"
write_plan "$(vol_entry 106867358 soleur-git-data-store '["forget"]'),${ATT}"
expect_red "M4c forget" "not_pure_delete"

write_plan "${VOL},$(att_entry 107140231 170370833 '["delete"]')"
expect_red "M5a attachment bound to the LUKS volume" "wrong_attachment_binding"
write_plan "${VOL},$(att_entry 106867358 170370999 '["delete"]')"
expect_red "M5b attachment bound to another server" "wrong_attachment_binding"

printf '{"format_version":"1.2"}' > "$TMP/plan.json"
expect_red "M6 resource_changes absent (degraded document)" "ABORT"
printf '{"format_version":"1.2","resource_changes":null}' > "$TMP/plan.json"
expect_red "M6b resource_changes null" "ABORT"

write_plan "${VOL},${ATT},{\"address\":\"hcloud_server.git_data\",\"mode\":\"managed\",\"change\":{\"before\":{}}}"
expect_red "M7 entry missing .change.actions" "ABORT"

write_plan "${VOL},${VOL},${ATT}"
expect_red "M8a duplicate volume entry" "wrong_volume_identity"
write_plan "$(jq -c '.deposed="abc123"' <<<"$VOL"),${ATT}"
expect_red "M8b deposed volume entry" "wrong_volume_identity"
write_plan "$(jq -c '.mode="data"' <<<"$VOL"),${ATT}"
expect_red "M8c volume entry with data mode" "wrong_volume_identity"

write_plan "$(vol_entry 106867358 soleur-git-data-store '["no-op"]'),${ATT}"
expect_red "M9a attachment delete with the volume present (no delete)" "volume_delete_missing"
write_plan "${ATT}"
expect_red "M9b attachment-only plan" "volume_delete_missing"

write_plan "${VOL},${ATT}"
expect_red "M10 dispatch input differs from the constant pin" "input_mismatch" 106867359
expect_red "M10b empty dispatch input" "input_mismatch" ""

# Surviving mutants from the battery, closed here: (a) dropping tostring on the volume id was
# EQUIVALENT for string ids, so a numeric-id fixture is what discriminates it; (b) a duplicate
# attachment entry had no fixture.
write_plan "$(jq -c '.change.before.id=106867358' <<<"$VOL"),${ATT}"
expect_green "P4 numeric volume before.id (type tolerance: compared via tostring)"
write_plan "${VOL},${ATT},${ATT}"
expect_red "M8d duplicate attachment entry" "wrong_volume_identity"

# ── workflow run-block behaviour (B1-B6, R1-R6) ─────────────────────────────────────
# The workflow's pre-plan read and read-back are code paths: extract each `run:` body with PyYAML and
# execute it under the runner's shell (`bash --noprofile --norc -eo pipefail`) against a STUB probe, so
# a grep-shaped assertion is not the only thing standing between a typo and a wrong verdict.
WF="${DIR}/../../.github/workflows/git-data-plaintext-volume-destroy.yml"
assert_fixture_dir "$TMP"
WS="$TMP/ws"; mkdir -p "$WS/apps/web-platform/infra"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'cat "$STUB_OUT"' 'exit "${STUB_RC:-0}"' > "$WS/apps/web-platform/infra/git-data-plaintext-volume-state.sh"
extract_block() { # step-name-prefix -> $TMP/<tag>.sh
  python3 -I - "$WF" "$1" "$2" <<'PY'
import sys, yaml
wf, prefix, dest = sys.argv[1:4]
d = yaml.safe_load(open(wf))
for j in d["jobs"].values():
    for st in j["steps"]:
        if st.get("name", "").startswith(prefix):
            open(dest, "w").write(st["run"])
            sys.exit(0)
sys.exit(3)
PY
}
extract_block "Pre-plan read" "$TMP/pre.sh" && extract_block "Read-back" "$TMP/rb.sh" || { printf 'FATAL: could not extract workflow run blocks\n'; exit 1; }
LUKS_OK=$'luks_volume=present\nluks_server_id=170370833'
stub() { printf '%s\n' "$1" > "$TMP/stub.out"; STUB_RC="${2:-0}"; }
run_pre() { # -> rc; output in $TMP/pre.log, $GITHUB_OUTPUT in $TMP/gh.out
  assert_fixture_dir "$TMP"; : > "$TMP/gh.out"
  GITHUB_WORKSPACE="$WS" GITHUB_OUTPUT="$TMP/gh.out" STUB_OUT="$TMP/stub.out" STUB_RC="$STUB_RC" \
    bash --noprofile --norc -eo pipefail "$TMP/pre.sh" > "$TMP/pre.log" 2>&1
}
run_rb() { # apply-outcome already-gone -> rc
  assert_fixture_dir "$TMP"; : > "$TMP/sum.md"
  GITHUB_WORKSPACE="$WS" GITHUB_RUN_ID=1 GITHUB_STEP_SUMMARY="$TMP/sum.md" STUB_OUT="$TMP/stub.out" STUB_RC="$STUB_RC" \
    APPLY_OUTCOME="$1" ALREADY_GONE="$2" bash --noprofile --norc -eo pipefail "$TMP/rb.sh" > "$TMP/rb.log" 2>&1
}
chk() { # label got-rc want-rc logfile needle
  if [[ "$2" -eq "$3" ]] && { [[ -z "${5-}" ]] || grep -qF -- "$5" "$4"; }; then pass; else fail "$1: rc=$2 (want $3) needle='${5-}' log: $(tr '\n' ' ' < "$4" | cut -c1-300)"; fi
}
stub $'plaintext_volume=present\nshape=present_attached\n'"$LUKS_OK"; run_pre; rc=$?
chk "B1 present_attached proceeds" "$rc" 0 "$TMP/pre.log" ""; chk "B1b already_gone=false" 0 0 "$TMP/gh.out" "already_gone=false"
stub $'plaintext_volume=present\nshape=present_detached\n'"$LUKS_OK"; run_pre; rc=$?
chk "B1c present_detached proceeds (attachment already gone)" "$rc" 0 "$TMP/pre.log" ""
stub $'plaintext_volume=absent\nshape=gone\n'"$LUKS_OK"; run_pre; rc=$?
chk "B2 gone short-circuits" "$rc" 0 "$TMP/gh.out" "already_gone=true"
stub $'plaintext_volume=absent\nshape=name_other_id\n'"$LUKS_OK"; run_pre; rc=$?
chk "B3 name under another id refused" "$rc" 1 "$TMP/pre.log" "verdict=name_other_id"
stub $'plaintext_volume=present\nshape=present_attached\nluks_volume=absent\nluks_server_id=null'; run_pre; rc=$?
chk "B4 LUKS volume missing refused" "$rc" 1 "$TMP/pre.log" "verdict=luks_volume_missing"
stub $'plaintext_volume=unknown\nerror=presence_proof x' 5; run_pre; rc=$?
chk "B5 probe exit 5 (presence proof) refused" "$rc" 1 "$TMP/pre.log" "verdict=pre_plan_read_failed"
stub $'plaintext_volume=present\nshape=attached_elsewhere\n'"$LUKS_OK"; run_pre; rc=$?
chk "B6 attached to another server refused" "$rc" 1 "$TMP/pre.log" "verdict=attached_elsewhere"

stub $'plaintext_volume=absent\nshape=gone\n'"$LUKS_OK"; run_rb success false; rc=$?
chk "R1 apply success + absent proves the end event" "$rc" 0 "$TMP/rb.log" "end event proven"
stub $'plaintext_volume=present\nshape=present_attached\n'"$LUKS_OK"; run_rb success false; rc=$?
chk "R2 apply success but volume still present" "$rc" 1 "$TMP/rb.log" "verdict=volume_still_present"
stub $'plaintext_volume=present\nshape=present_detached\n'"$LUKS_OK"; run_rb failure false; rc=$?
chk "R3 failed apply reports actual state and fails" "$rc" 1 "$TMP/rb.log" "volume_still_present_after_failed_apply"
stub $'plaintext_volume=present\nshape=present_attached\n'"$LUKS_OK"; run_rb "" false; rc=$?
chk "R4 apply skipped (earlier refusal): informational, no extra failure" "$rc" 0 "$TMP/rb.log" "nothing was changed"
stub $'plaintext_volume=absent\nshape=gone\n'"$LUKS_OK"; run_rb "" true; rc=$?
chk "R5 already-gone re-dispatch re-proves the end event" "$rc" 0 "$TMP/rb.log" "end event proven"
stub $'plaintext_volume=absent\nshape=gone\nluks_volume=absent\nluks_server_id=null'; run_rb success false; rc=$?
chk "R6 LUKS volume missing after the apply fails the run" "$rc" 1 "$TMP/rb.log" "verdict=luks_volume_missing"

# ── harness row H1: a vacuous gate (body replaced by `return 0`) must be DETECTED ──
# Source a mutated copy of the lib in a subshell and run a must-RED fixture through it: if it
# passes there, the fixtures are discriminating (the mutation would turn the suite RED).
assert_fixture_dir "$TMP"
MUT="$TMP/gate-mutant.sh"
printf '%s\n' '# shellcheck shell=bash' 'git_data_plaintext_destroy_gate() { return 0; }' > "$MUT"
write_plan "${VOL},${ATT},${LUKS_DELETE}"
# shellcheck source=/dev/null
if (source "$MUT"; git_data_plaintext_destroy_gate "$TMP/plan.json" "$PIN" >/dev/null 2>&1); then
  pass  # vacuous gate accepted the must-RED fixture: the suite WOULD have gone RED against it
else
  fail "H1: vacuous-gate mutant refused a must-RED fixture; the fixtures cannot detect a gutted gate"
fi

# ── structural: the lib calls the preamble (anchored on the CALL) and names the local ──
if grep -qE '^[[:space:]]*plan_gate_assert_readable' "$LIB" \
   && grep -qE 'local plan_json' "$LIB" \
   && ! grep -qF 'ack-destroy' "$LIB"; then
  pass
else
  fail "S1: lib must CALL plan_gate_assert_readable, name 'local plan_json', and carry no ack-destroy bypass"
fi

# ANTI-VACUITY FLOOR. Self-contained (bash builtins and this suite's own counters only): the
# threshold is declared on the line IMMEDIATELY above its `if` so guard-vacuity-floor's mutant
# can slice it. A FLOOR, NOT EQUALITY: the count is developer-incremented.
_floor=41
_ran=$((passes + fails))
if [[ "$_ran" -lt "$_floor" ]]; then
  fails=$((fails + 1))
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is %s. Arms were deleted, skipped, or the suite exited early.\n' "$_ran" "$_floor"
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor %s)\n' "$_ran" "$_floor"
fi

echo ""
echo "=== test-git-data-plaintext-destroy-gate.sh: ${passes} passed, ${fails} failed ==="
[ "$fails" -eq 0 ] || exit 1
