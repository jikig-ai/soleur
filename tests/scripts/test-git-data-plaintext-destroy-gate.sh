#!/usr/bin/env bash
# Tests for tests/scripts/lib/git-data-plaintext-destroy-gate.sh (sourced by the destroy job in
# .github/workflows/git-data-plaintext-volume-destroy.yml, Option B of the W0 plaintext-volume route),
# for the workflow's own run blocks, and for the read-only probe apps/web-platform/infra/git-data-
# plaintext-volume-state.sh.
#
# The gate reads a `terraform show -json <plan>` document and PASSes (rc=0) iff the plan deletes
# the plaintext git-data volume 106867358 (name soleur-git-data-store) — optionally together with
# its attachment, which must bind that volume and the LIVE server id passed as the third argument —
# and changes nothing else. Entries whose actions are EXACTLY ["no-op"] or EXACTLY ["read"] (the
# -target closure pulls the server, module and data sources in) are ignorable; anything else is out of
# scope, and so is any entry carrying previous_address / change.importing, or an errored plan.
#
# Rows: P* must PASS, M* must REFUSE with a named verdict, H1 proves a gutted gate is detectable, G*
# drive the helpers' own positive controls, B*/R* execute the workflow's pre-plan and read-back run
# blocks against a stub probe, W* execute the plan+gate and apply run blocks (the gate refusal must
# stop the apply) and pin the step wiring, T* drive the real probe against a curl shim, S1 is the
# structural pin on the lib. Fixtures are type-faithful (volume before.id is a STRING; attachment
# volume_id/server_id are NUMBERS) and SYNTHESIZED (cq-test-fixtures-synthesized-only). Deterministic;
# no network.
#
# Run: bash tests/scripts/test-git-data-plaintext-destroy-gate.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
LIB="${DIR}/lib/git-data-plaintext-destroy-gate.sh"
PROBE="${REPO}/apps/web-platform/infra/git-data-plaintext-volume-state.sh"
# shellcheck source=tests/scripts/lib/git-data-plaintext-destroy-gate.sh
source "$LIB"

passes=0
fails=0
FAILED=()
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "FAIL: $1" >&2; }

# INSTRUMENT SELF-TEST. Drives both helpers once and refuses to continue unless both counters AND the
# append-only ledger moved, reported with printf + exit so it does not flow through the helpers it guards.
_p0=$passes; _f0=$fails
pass; fail "instrument self-test (expected, ignore)" 2>/dev/null
if [[ "$passes" -ne $((_p0 + 1)) || "$fails" -ne $((_f0 + 1)) || "${#FAILED[@]}" -ne 1 ]]; then
  printf 'FATAL: instrument self-test: pass()/fail() did not move their counters or the ledger\n'
  exit 1
fi
passes=$_p0; fails=$_f0; FAILED=()

# The ONE verdict line of this suite. The child run below calls it too, so disarming it is visible there.
verdict() {
  echo ""
  echo "=== test-git-data-plaintext-destroy-gate.sh: ${passes} passed, ${fails} failed ==="
  if [[ "$fails" -ne 0 || "${#FAILED[@]}" -ne 0 ]]; then exit 1; fi
}
# Child mode (see the end of the file): one injected failure, then the verdict — nothing else runs.
if [[ -n "${PDG_INJECT_FAIL:-}" ]]; then fail "injected failure (child run, expected)"; verdict; exit 0; fi

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
# A server id that is NOT the one the old constant pinned: the live id is resolved by name, so the gate
# must bind the attachment to whatever the caller passes.
SID=180000001

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
ATT="$(att_entry 106867358 "$SID" '["delete"]')"
SRV_NOOP="$(other_entry hcloud_server.git_data '["no-op"]')"
LUKS_NOOP="$(other_entry hcloud_volume.git_data_luks '["no-op"]')"
PW_NOOP="$(other_entry random_password.git_data_luks '["no-op"]')"
DATA_READ="$(other_entry data.hcloud_ssh_keys.git_data_root '["read"]' data)"
LUKS_DELETE="$(other_entry hcloud_volume.git_data_luks '["delete"]')"

write_plan() { # comma-joined entries -> $TMP/plan.json
  assert_fixture_dir "$TMP"
  printf '{"format_version":"1.2","resource_changes":[%s]}' "$1" > "$TMP/plan.json"
}

run_gate() { git_data_plaintext_destroy_gate "$TMP/plan.json" "${1-$PIN}" "${2-$SID}"; }

# expect_green <label> [expected-volume-id] [live-server-id] / expect_red <label> <verdict-needle> [..]
expect_green() {
  local out
  if out=$(run_gate "${2-$PIN}" "${3-$SID}" 2>&1); then pass; else fail "$1: expected PASS, got: ${out}"; fi
}
expect_red() {
  local out
  if out=$(run_gate "${3-$PIN}" "${4-$SID}" 2>&1); then
    fail "$1: expected REFUSE, gate passed"
  elif [[ "$out" == *"$2"* ]]; then
    pass
  else
    fail "$1: refused but verdict '$2' not named; got: ${out}"
  fi
}
chk() { # label got-rc want-rc logfile needle
  if [[ "$2" -eq "$3" ]] && { [[ -z "${5-}" ]] || grep -qF -- "$5" "$4"; }; then pass; else fail "$1: rc=$2 (want $3) needle='${5-}' log: $(tr '\n' ' ' < "$4" | cut -c1-300)"; fi
}

# ── G: POSITIVE CONTROLS for the verdict-owning helpers ──────────────────────────────
# pass()/fail() are covered by the instrument self-test above. expect_green / expect_red / chk OWN their
# verdict, so each is driven in a subshell (counters isolated) with an input that MUST be refused and one
# that MUST be accepted; the control reports via printf + exit, never through the helper under test.
ctl() { # label want-fails want-passes command...
  local label="$1" wf="$2" wp="$3" r; shift 3
  r=$( ( passes=0; fails=0; FAILED=(); "$@" >/dev/null 2>&1; echo "${fails}:${passes}" ) )
  if [[ "$r" != "${wf}:${wp}" ]]; then
    printf 'FATAL: helper positive control "%s": got fails:passes=%s, want %s:%s — a verdict helper no longer rejects/accepts correctly\n' "$label" "$r" "$wf" "$wp"
    exit 1
  fi
  pass
}
printf 'hello\n' > "$TMP/ctl.log"
write_plan "${VOL},${ATT},${LUKS_DELETE}"
ctl "G1 expect_green rejects a refused plan" 1 0 expect_green "ctl"
ctl "G2 expect_red accepts the right verdict" 0 1 expect_red "ctl" "out_of_scope_change"
ctl "G3 expect_red rejects a wrong verdict needle" 1 0 expect_red "ctl" "wrong_volume_identity"
write_plan "${VOL},${ATT}"
ctl "G4 expect_green accepts a passing plan" 0 1 expect_green "ctl"
ctl "G5 expect_red rejects a passing plan" 1 0 expect_red "ctl" "out_of_scope_change"
ctl "G6 chk rejects a wrong rc" 1 0 chk "ctl" 1 0 "$TMP/ctl.log" ""
ctl "G7 chk rejects a missing needle" 1 0 chk "ctl" 0 0 "$TMP/ctl.log" "nope"
ctl "G8 chk accepts rc and needle" 0 1 chk "ctl" 0 0 "$TMP/ctl.log" "hello"
# G9: ctl itself must be able to reject — a control driven with a WRONG expectation must exit non-zero.
write_plan "${VOL},${ATT},${LUKS_DELETE}"
( ctl "G9 meta" 0 0 expect_green "ctl" ) >/dev/null 2>&1; _g9=$?
if [[ "$_g9" -eq 0 ]]; then
  printf 'FATAL: helper positive control G9: ctl accepted a wrong expectation — the controls themselves are disarmed\n'
  exit 1
fi
pass

# ── must-PASS rows ───────────────────────────────────────────────────────────────────
write_plan "${VOL},${ATT}"
expect_green "P1a volume + attachment deletes"
write_plan "${VOL}"
expect_green "P1b attachment already gone: volume delete only"
write_plan "${ATT},${VOL}"
expect_green "P2 reordered resource_changes"
write_plan "${SRV_NOOP},${VOL},${LUKS_NOOP},${ATT},${PW_NOOP},${DATA_READ}"
expect_green "P3 extra no-op and read entries (server, LUKS volume, passphrase, data source)"
write_plan "$(jq -c '.change.before.id=106867358' <<<"$VOL"),${ATT}"
expect_green "P4 numeric volume before.id (type tolerance: compared via tostring)"
write_plan "${VOL},$(att_entry 106867358 170370833 '["delete"]')"
expect_green "P5 a live server id equal to the OLD constant is just another id" "$PIN" 170370833

# ── must-RED rows ────────────────────────────────────────────────────────────────────
write_plan "${VOL},${ATT},${LUKS_DELETE}"
expect_red "M1 LUKS volume (107140231) deleted" "out_of_scope_change"

SRV_UPDATE="$(other_entry hcloud_server.git_data '["update"]')"
write_plan "${VOL},${ATT},${SRV_UPDATE}"
expect_red "M2 third non-ignorable change after two compliant deletes" "out_of_scope_change"

# every other-resource action shape the gate must refuse (G1/G2c/G2d/G2f/G2h/G2i loosenings)
for act in '["create"]' '["delete","create"]' '["create","delete"]' '["forget"]' '["delete"]' '["update"]'; do
  write_plan "${VOL},${ATT},$(other_entry hcloud_server.git_data "$act")"
  expect_red "M2-server $act on hcloud_server.git_data" "out_of_scope_change"
done
write_plan "${VOL},${ATT},$(other_entry random_password.git_data_luks '["update"]')"
expect_red "M2-passphrase update on the LUKS passphrase" "out_of_scope_change"
write_plan "${VOL},${ATT},$(other_entry doppler_secret.git_data_luks_key '["delete"]')"
expect_red "M2-secret delete on the passphrase secret" "out_of_scope_change"
write_plan "${VOL},${ATT},$(other_entry data.hcloud_ssh_keys.git_data_root '["delete"]' data)"
expect_red "M2-data a data-mode entry is not exempt from the action check" "out_of_scope_change"
write_plan "${VOL},${ATT},$(other_entry module.git_data_userdata.some_resource '["delete"]')"
expect_red "M2-module a module-nested delete" "out_of_scope_change"

# moved / imported / errored: state mutations outside the delete this gate attests
write_plan "${VOL},${ATT},$(jq -c '.previous_address="hcloud_server.old"' <<<"$SRV_NOOP")"
expect_red "M11a a no-op entry carrying previous_address (moved)" "out_of_scope_change"
write_plan "${VOL},${ATT},$(jq -c '.change.importing={id:"1"}' <<<"$SRV_NOOP")"
expect_red "M11b a no-op entry carrying change.importing (import)" "out_of_scope_change"
printf '{"format_version":"1.2","errored":true,"resource_changes":[%s,%s]}' "$VOL" "$ATT" > "$TMP/plan.json"
expect_red "M11c an errored plan" "out_of_scope_change"

write_plan "$(vol_entry 106867359 soleur-git-data-store '["delete"]'),${ATT}"
expect_red "M3a wrong volume id" "wrong_volume_identity"
write_plan "$(vol_entry 106867358 soleur-git-data-store-luks '["delete"]'),${ATT}"
expect_red "M3b wrong volume name" "wrong_volume_identity"
write_plan "$(vol_entry 1068673580 soleur-git-data-store '["delete"]'),${ATT}"
expect_red "M3c superstring volume id (a longer id that starts with the pin)" "wrong_volume_identity"
write_plan "$(jq -c 'del(.change.before.id)' <<<"$VOL"),${ATT}"
expect_red "M3d volume before.id absent" "wrong_volume_identity"
write_plan "$(jq -c 'del(.change.before.name)' <<<"$VOL"),${ATT}"
expect_red "M3e volume before.name absent" "wrong_volume_identity"
write_plan "$(jq -c 'del(.mode)' <<<"$VOL"),${ATT}"
expect_red "M3f volume mode absent" "wrong_volume_identity"

write_plan "$(vol_entry 106867358 soleur-git-data-store '["delete","create"]'),${ATT}"
expect_red "M4a replace (delete,create)" "not_pure_delete"
write_plan "$(vol_entry 106867358 soleur-git-data-store '["create","delete"]'),${ATT}"
expect_red "M4b replace (create,delete)" "not_pure_delete"
write_plan "$(vol_entry 106867358 soleur-git-data-store '["forget"]'),${ATT}"
expect_red "M4c forget" "not_pure_delete"
write_plan "${VOL},$(att_entry 106867358 "$SID" '["delete","create"]')"
expect_red "M4d attachment replace" "not_pure_delete"
write_plan "${VOL},$(att_entry 106867358 "$SID" '["update"]')"
expect_red "M4e attachment update" "not_pure_delete"
write_plan "${VOL},$(att_entry 106867358 "$SID" '["no-op"]')"
expect_red "M4f attachment no-op beside a volume delete" "not_pure_delete"

write_plan "${VOL},$(att_entry 107140231 "$SID" '["delete"]')"
expect_red "M5a attachment bound to the LUKS volume" "wrong_attachment_binding"
write_plan "${VOL},$(att_entry 106867358 170370999 '["delete"]')"
expect_red "M5b attachment bound to another server" "wrong_attachment_binding"
write_plan "${VOL},$(att_entry 1068673580 "$SID" '["delete"]')"
expect_red "M5c attachment bound to a superstring volume id" "wrong_attachment_binding"
write_plan "${VOL},$(att_entry 106867358 1800000010 '["delete"]')"
expect_red "M5d attachment bound to a superstring server id" "wrong_attachment_binding"
write_plan "${VOL},$(jq -c 'del(.change.before.volume_id)' <<<"$ATT")"
expect_red "M5e attachment volume_id absent" "wrong_attachment_binding"
write_plan "${VOL},$(jq -c 'del(.change.before.server_id)' <<<"$ATT")"
expect_red "M5f attachment server_id absent" "wrong_attachment_binding"
write_plan "${VOL},$(jq -c '.deposed="abc123"' <<<"$ATT")"
expect_red "M5g deposed attachment" "wrong_attachment_binding"
write_plan "${VOL},$(jq -c '.mode="data"' <<<"$ATT")"
expect_red "M5h attachment with data mode" "wrong_attachment_binding"
write_plan "${VOL},${ATT}"
expect_red "M5i attachment bound to a server that is not the live one" "wrong_attachment_binding" "$PIN" 170370833

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
write_plan "${VOL},${ATT},${ATT}"
expect_red "M8d duplicate attachment entry" "duplicate_attachment"

write_plan "$(vol_entry 106867358 soleur-git-data-store '["no-op"]'),${ATT}"
expect_red "M9a attachment delete with the volume present (no delete)" "volume_delete_missing"
write_plan "${ATT}"
expect_red "M9b attachment-only plan" "volume_delete_missing"

write_plan "${VOL},${ATT}"
expect_red "M10 dispatch input differs from the constant pin" "input_mismatch" 106867359
expect_red "M10b empty dispatch input" "input_mismatch" ""
expect_red "M10c superstring dispatch input" "input_mismatch" 1068673580
expect_red "M12a empty live server id" "server_pin_missing" "$PIN" ""
expect_red "M12b non-numeric live server id" "server_pin_missing" "$PIN" "abc"

# ── H1: a vacuous gate (body replaced by `return 0`) must be DETECTED ───────────────
# Source a mutated copy of the lib in a subshell and run a must-RED fixture through it: if it
# passes there, the fixtures are discriminating (the mutation would turn the suite RED).
MUT="$TMP/gate-mutant.sh"
printf '%s\n' '# shellcheck shell=bash' 'git_data_plaintext_destroy_gate() { return 0; }' > "$MUT"
write_plan "${VOL},${ATT},${LUKS_DELETE}"
# shellcheck source=/dev/null
if (source "$MUT"; git_data_plaintext_destroy_gate "$TMP/plan.json" "$PIN" "$SID" >/dev/null 2>&1); then
  pass  # vacuous gate accepted the must-RED fixture: the suite WOULD have gone RED against it
else
  fail "H1: vacuous-gate mutant refused a must-RED fixture; the fixtures cannot detect a gutted gate"
fi

# ── workflow run-block behaviour (B1-B7, R1-R10, V1-V3, W1-W9) ───────────────────────
# The workflow's steps are code paths: extract each `run:` body with PyYAML and execute it under the
# runner's shell (`bash --noprofile --norc -eo pipefail`) against STUB probe / doppler / terraform, so a
# grep-shaped assertion is not the only thing standing between a typo and a wrong verdict.
WF="${REPO}/.github/workflows/git-data-plaintext-volume-destroy.yml"
WS="$TMP/ws"; mkdir -p "$WS/apps/web-platform/infra"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'cat "$STUB_OUT"' 'exit "${STUB_RC:-0}"' > "$WS/apps/web-platform/infra/git-data-plaintext-volume-state.sh"
# extract_block <job> <step-name-prefix> <dest>: EXACTLY ONE step in the whole workflow may carry the name
# prefix, and it must be in <job> — a decoy step with a pristine copy of the block cannot be selected first.
extract_block() {
  python3 -I - "$WF" "$1" "$2" "$3" <<'PY'
import sys, yaml
wf, job, prefix, dest = sys.argv[1:5]
d = yaml.safe_load(open(wf))
hits = [(jn, st) for jn, j in d["jobs"].items() for st in j["steps"] if str(st.get("name", "")).startswith(prefix)]
if len(hits) != 1 or hits[0][0] != job:
    sys.exit(3)
open(dest, "w").write(hits[0][1]["run"])
PY
}
# wfq <job> <step-name-prefix|-> <key>: prints the YAML value of a step (or job when '-') key; "<absent>" if missing.
wfq() {
  python3 -I - "$WF" "$1" "$2" "$3" <<'PY'
import sys, yaml
wf, job, prefix, key = sys.argv[1:5]
d = yaml.safe_load(open(wf))
j = d["jobs"][job]
if prefix == "-":
    print(j.get(key, "<absent>")); sys.exit(0)
hits = [st for st in j["steps"] if str(st.get("name", "")).startswith(prefix)]
if len(hits) != 1:
    print("<ambiguous:%d>" % len(hits)); sys.exit(0)
print(hits[0].get(key, "<absent>"))
PY
}
extract_block destroy "Pre-plan read" "$TMP/pre.sh" \
  && extract_block destroy "Read-back" "$TMP/rb.sh" \
  && extract_block destroy "Terraform plan" "$TMP/plan.sh" \
  && extract_block destroy "Terraform apply" "$TMP/apply.sh" \
  && extract_block destroy "Extract R2 backend credentials" "$TMP/r2.sh" \
  && extract_block validate "Require main" "$TMP/main.sh" \
  && extract_block validate "Validate dispatch inputs" "$TMP/val.sh" \
  || { printf 'FATAL: could not extract (exactly one match each) the workflow run blocks\n'; exit 1; }

LUKS_OK=$'server_id=180000001\nluks_volume=present\nluks_volume_id=107140231\nluks_server_id=180000001'
stub() { printf '%s\n' "$1" > "$TMP/stub.out"; STUB_RC="${2:-0}"; }
run_pre() { # -> rc; output in $TMP/pre.log, $GITHUB_OUTPUT in $TMP/gh.out
  assert_fixture_dir "$TMP"; : > "$TMP/gh.out"
  GITHUB_WORKSPACE="$WS" GITHUB_OUTPUT="$TMP/gh.out" STUB_OUT="$TMP/stub.out" STUB_RC="$STUB_RC" \
    bash --noprofile --norc -eo pipefail "$TMP/pre.sh" > "$TMP/pre.log" 2>&1
}
run_rb() { # apply-outcome already-gone [pre-server-id pre-luks-id] -> rc
  assert_fixture_dir "$TMP"; : > "$TMP/sum.md"
  GITHUB_WORKSPACE="$WS" GITHUB_RUN_ID=1 GITHUB_STEP_SUMMARY="$TMP/sum.md" STUB_OUT="$TMP/stub.out" STUB_RC="$STUB_RC" \
    APPLY_OUTCOME="$1" ALREADY_GONE="$2" PRE_SERVER_ID="${3-180000001}" PRE_LUKS_ID="${4-107140231}" \
    bash --noprofile --norc -eo pipefail "$TMP/rb.sh" > "$TMP/rb.log" 2>&1
}

stub $'plaintext_volume=present\nshape=present_attached\n'"$LUKS_OK"; run_pre; rc=$?
chk "B1 present_attached proceeds" "$rc" 0 "$TMP/pre.log" ""; chk "B1b already_gone=false" 0 0 "$TMP/gh.out" "already_gone=false"
chk "B1e server_id is published for the gate" 0 0 "$TMP/gh.out" "server_id=180000001"
stub $'plaintext_volume=present\nshape=present_detached\n'"$LUKS_OK"; run_pre; rc=$?
chk "B1c present_detached proceeds (attachment already gone)" "$rc" 0 "$TMP/pre.log" ""
chk "B1d present_detached is NOT the already-gone short-circuit" 0 0 "$TMP/gh.out" "already_gone=false"
stub $'plaintext_volume=absent\nshape=gone\n'"$LUKS_OK"; run_pre; rc=$?
chk "B2 gone short-circuits" "$rc" 0 "$TMP/gh.out" "already_gone=true"
stub $'plaintext_volume=absent\nshape=name_other_id\n'"$LUKS_OK"; run_pre; rc=$?
chk "B3 name under another id refused" "$rc" 1 "$TMP/pre.log" "verdict=name_other_id"
stub $'plaintext_volume=present\nshape=present_attached\nserver_id=180000001\nluks_volume=absent\nluks_volume_id=107140231\nluks_server_id=null'; run_pre; rc=$?
chk "B4 LUKS volume missing refused" "$rc" 1 "$TMP/pre.log" "verdict=luks_volume_missing"
stub $'plaintext_volume=present\nshape=present_attached\nserver_id=180000001\nluks_volume=present\nluks_volume_id=107140231\nluks_server_id=999'; run_pre; rc=$?
chk "B4b LUKS volume present on a DIFFERENT server refused" "$rc" 1 "$TMP/pre.log" "verdict=luks_volume_missing"
stub $'plaintext_volume=present\nshape=present_attached\nluks_volume=present\nluks_server_id=180000001'; run_pre; rc=$?
chk "B4c probe without numeric server_id / luks_volume_id refused" "$rc" 1 "$TMP/pre.log" "verdict=server_pin_missing"
stub $'plaintext_volume=unknown\nerror=presence_proof x' 5; run_pre; rc=$?
chk "B5 probe exit 5 (presence proof) refused" "$rc" 1 "$TMP/pre.log" "verdict=pre_plan_read_failed"
stub $'plaintext_volume=present\nshape=attached_elsewhere\n'"$LUKS_OK"; run_pre; rc=$?
chk "B6 attached to another server refused" "$rc" 1 "$TMP/pre.log" "verdict=attached_elsewhere"
stub $'plaintext_volume=present\nshape=identity_mismatch\n'"$LUKS_OK"; run_pre; rc=$?
chk "B7 identity mismatch refused" "$rc" 1 "$TMP/pre.log" "verdict=identity_mismatch"

stub $'plaintext_volume=absent\nshape=gone\n'"$LUKS_OK"; run_rb success false; rc=$?
chk "R1 apply success + gone proves the end event" "$rc" 0 "$TMP/rb.log" "end event proven"
stub $'plaintext_volume=present\nshape=present_attached\n'"$LUKS_OK"; run_rb success false; rc=$?
chk "R2 apply success but volume still present" "$rc" 1 "$TMP/rb.log" "verdict=volume_still_present"
stub $'plaintext_volume=present\nshape=present_detached\n'"$LUKS_OK"; run_rb failure false; rc=$?
chk "R3 failed apply reports actual state and fails" "$rc" 1 "$TMP/rb.log" "volume_still_present_after_failed_apply"
stub $'plaintext_volume=present\nshape=present_attached\n'"$LUKS_OK"; run_rb skipped false; rc=$?
chk "R4 apply skipped (earlier refusal): informational, no extra failure" "$rc" 0 "$TMP/rb.log" "nothing was changed"
stub $'plaintext_volume=absent\nshape=gone\n'"$LUKS_OK"; run_rb skipped true; rc=$?
chk "R5 already-gone re-dispatch re-proves the end event" "$rc" 0 "$TMP/rb.log" "end event proven"
stub $'plaintext_volume=absent\nshape=gone\nserver_id=180000001\nluks_volume=absent\nluks_volume_id=107140231\nluks_server_id=null'; run_rb success false; rc=$?
chk "R6 LUKS volume missing after the apply fails the run" "$rc" 1 "$TMP/rb.log" "verdict=luks_volume_missing"
stub $'plaintext_volume=absent\nshape=gone\nserver_id=180000001\nluks_volume=present\nluks_volume_id=107140231\nluks_server_id=999'; run_rb success false; rc=$?
chk "R6b LUKS volume on a different server after the apply fails the run" "$rc" 1 "$TMP/rb.log" "verdict=luks_volume_missing"
stub $'plaintext_volume=absent\nshape=name_other_id\n'"$LUKS_OK"; run_rb success false; rc=$?
chk "R7 absent by id but the name lookup is NOT empty must not prove the end event" "$rc" 1 "$TMP/rb.log" "verdict=volume_still_present"
stub $'plaintext_volume=absent\nshape=gone\n'"$LUKS_OK"; run_rb failure false; rc=$?
chk "R8 failed apply but the device is gone: named verdict, still red" "$rc" 1 "$TMP/rb.log" "verdict=apply_failed_volume_gone"
stub $'plaintext_volume=absent\nshape=gone\n'"$LUKS_OK"; run_rb success false 190000009 107140231; rc=$?
chk "R9 server id changed since the pre-plan read" "$rc" 1 "$TMP/rb.log" "verdict=server_id_drift"
stub $'plaintext_volume=unknown\nerror=api x' 4; run_rb success false; rc=$?
chk "R10 probe failure at read-back fails the run" "$rc" 1 "$TMP/rb.log" "verdict=read_back_failed"

# The R2 credential step writes $GITHUB_ENV in the heredoc-delimiter form: a newline-bearing value cannot inject
# an extra assignment (BASH_ENV class). Run it with a hostile value and require the delimiter form.
: > "$TMP/ghenv"
AWS_ACCESS_KEY_ID=$'abc\nEVIL=1' AWS_SECRET_ACCESS_KEY=sec GITHUB_ENV="$TMP/ghenv" bash --noprofile --norc -eo pipefail "$TMP/r2.sh" > "$TMP/r2.log" 2>&1; rc=$?
chk "V0 the R2 credential step runs" "$rc" 0 "$TMP/r2.log" ""
if grep -qE '^AWS_ACCESS_KEY_ID<<SOLEUR_EOF_[0-9a-f]+$' "$TMP/ghenv" && ! grep -qxF 'EVIL=1' <(sed '/^AWS_ACCESS_KEY_ID<</,/^SOLEUR_EOF_/d' "$TMP/ghenv"); then pass
else fail "V0b R2 credentials must be written in the heredoc-delimiter form (a newline in a value must not become its own assignment)"; fi

# validate job: main only, literal compares
run_main() { GITHUB_REF="$1" bash --noprofile --norc -eo pipefail "$TMP/main.sh" > "$TMP/main.log" 2>&1; }
run_main refs/heads/main; rc=$?; chk "V1 a main dispatch passes the ref check" "$rc" 0 "$TMP/main.log" ""
run_main refs/heads/feature; rc=$?; chk "V2 a branch dispatch is refused loudly" "$rc" 1 "$TMP/main.log" "verdict=not_main"
run_val() { EXPECTED_RAW="$1" CONFIRM_RAW="$2" bash --noprofile --norc -eo pipefail "$TMP/val.sh" > "$TMP/val.log" 2>&1; }
run_val 106867358 DESTROY-PLAINTEXT-GIT-DATA-VOLUME; rc=$?; chk "V3a correct inputs pass" "$rc" 0 "$TMP/val.log" "validated"
run_val 106867359 DESTROY-PLAINTEXT-GIT-DATA-VOLUME; rc=$?; chk "V3b wrong volume id refused" "$rc" 1 "$TMP/val.log" "verdict=input_mismatch"
run_val 106867358 destroy; rc=$?; chk "V3c wrong confirm token refused" "$rc" 1 "$TMP/val.log" "verdict=input_mismatch"

# W*: the plan+gate step and the apply step, run against stub doppler/terraform on PATH. A gate refusal
# must stop the apply, at plan time AND again at apply time (the apply step re-judges the saved plan).
BIN="$TMP/bin"; mkdir -p "$BIN" "$TMP/wd"
cat > "$BIN/doppler" <<'SH'
#!/usr/bin/env bash
while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done
shift
exec "$@"
SH
cat > "$BIN/terraform" <<'SH'
#!/usr/bin/env bash
case "$1" in
  plan)  : > tfplan; exit "${STUB_PLAN_RC:-0}" ;;
  show)  cat "$STUB_PLAN" ;;
  apply) echo APPLIED >> "$APPLY_LOG"; exit "${STUB_APPLY_RC:-0}" ;;
esac
SH
chmod +x "$BIN/doppler" "$BIN/terraform"
run_step() { # script expected-id server-id [apply-rc] [plan-rc] -> rc; log $TMP/step.log; apply log $TMP/apply.log
  assert_fixture_dir "$TMP"; : > "$TMP/apply.log"; rm -f "$TMP/wd/tfplan" "$TMP/wd/tfplan.json"
  ( cd "$TMP/wd" && PATH="$BIN:$PATH" GITHUB_WORKSPACE="$REPO" CI_SSH_PUB=x DOPPLER_TOKEN=x \
      EXPECTED_VOLUME_ID="$2" SERVER_ID="$3" STUB_PLAN="$TMP/plan.json" APPLY_LOG="$TMP/apply.log" \
      STUB_APPLY_RC="${4:-0}" STUB_PLAN_RC="${5:-0}" bash --noprofile --norc -eo pipefail "$1" > "$TMP/step.log" 2>&1 )
}
applied() { [[ -s "$TMP/apply.log" ]]; }
write_plan "${VOL},${ATT}"
run_step "$TMP/plan.sh" "$PIN" "$SID"; rc=$?
chk "W1 plan+gate step passes a compliant plan" "$rc" 0 "$TMP/step.log" "gate PASSED"
if applied; then fail "W1b the plan step must never apply"; else pass; fi
write_plan "${VOL},${ATT},${LUKS_DELETE}"
run_step "$TMP/plan.sh" "$PIN" "$SID"; rc=$?
chk "W2 plan+gate step refuses a plan that also deletes the LUKS volume" "$rc" 1 "$TMP/step.log" "gate REFUSED"
run_step "$TMP/plan.sh" "$PIN" "$SID" 0 3; rc=$?
chk "W2b a failing terraform plan fails the step" "$rc" 3 "$TMP/step.log" "terraform plan failed"
write_plan "${VOL},${ATT}"
run_step "$TMP/apply.sh" "$PIN" "$SID"; rc=$?
chk "W3 apply step applies a compliant saved plan" "$rc" 0 "$TMP/step.log" ""
if applied; then pass; else fail "W3b the compliant plan was not applied"; fi
write_plan "${VOL},${ATT},${LUKS_DELETE}"
run_step "$TMP/apply.sh" "$PIN" "$SID"; rc=$?
chk "W4 apply step RE-RUNS the gate: a refused saved plan is not applied" "$rc" 1 "$TMP/step.log" "REFUSED the saved plan"
if applied; then fail "W4b a refused plan was APPLIED"; else pass; fi
write_plan "${VOL},${ATT}"
run_step "$TMP/apply.sh" "$PIN" 170370833; rc=$?
chk "W5 apply step with a server id that is not the live one is refused" "$rc" 1 "$TMP/step.log" "REFUSED the saved plan"
if applied; then fail "W5b a plan bound to another server was APPLIED"; else pass; fi
run_step "$TMP/apply.sh" "$PIN" ""; rc=$?
chk "W5c apply step with no server id is refused" "$rc" 1 "$TMP/step.log" "REFUSED the saved plan"
run_step "$TMP/apply.sh" "$PIN" "$SID" 7; rc=$?
chk "W6 a failing terraform apply fails the step with the re-dispatch message" "$rc" 1 "$TMP/step.log" "terraform apply failed"
if [[ -e "$TMP/wd/tfplan.json" ]]; then fail "W6b tfplan.json must be removed by the apply step's trap"; else pass; fi

# wiring pins (the keys that decide whether a refusal is obeyed)
PRE_IF="steps.pre.outputs.already_gone == 'false'"
[[ "$(wfq destroy "Terraform plan" if)" == "$PRE_IF" ]] && pass || fail "W7a plan step if: must be exactly ${PRE_IF}"
[[ "$(wfq destroy "Terraform apply" if)" == "$PRE_IF" ]] && pass || fail "W7b apply step if: must be exactly ${PRE_IF} (no always()/failure()/cancelled())"
[[ "$(wfq destroy "Terraform plan" continue-on-error)" == "<absent>" ]] && pass || fail "W8a plan step must not carry continue-on-error"
[[ "$(wfq destroy "Terraform apply" continue-on-error)" == "<absent>" ]] && pass || fail "W8b apply step must not carry continue-on-error"
[[ "$(wfq destroy - continue-on-error)" == "<absent>" ]] && pass || fail "W8c destroy job must not carry continue-on-error"
[[ "$(wfq validate - continue-on-error)" == "<absent>" ]] && pass || fail "W8d validate job must not carry continue-on-error"
[[ "$(wfq destroy - if)" == "github.ref == 'refs/heads/main'" ]] && pass || fail "W9 destroy job must be skipped off main"
[[ "$(wfq destroy - needs)" == "validate" ]] && pass || fail "W9b destroy job must need validate"
# the apply step judges the saved plan BEFORE it applies it (textual order inside the one step)
_apply_gate=$(grep -n 'git_data_plaintext_destroy_gate tfplan.json' "$TMP/apply.sh" | head -1 | cut -d: -f1)
_apply_tf=$(grep -n 'terraform apply' "$TMP/apply.sh" | head -1 | cut -d: -f1)
if [[ -n "$_apply_gate" && -n "$_apply_tf" && "$_apply_gate" -lt "$_apply_tf" ]]; then pass; else fail "W9c the apply step must gate the saved plan before terraform apply (gate line '${_apply_gate}', apply line '${_apply_tf}')"; fi

# ── T*: the real probe against a curl shim ───────────────────────────────────────────
SHIM="$TMP/shim"; mkdir -p "$SHIM"; FIXD="$TMP/fixd"
cat > "$SHIM/curl" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
out=""; url=""
while [[ $# -gt 0 ]]; do
  case "$1" in -o) out="$2"; shift 2 ;; https://*) url="$1"; shift ;; *) shift ;; esac
done
path="${url#https://api.hetzner.cloud/v1}"
key="$(printf '%s' "$path" | tr '/?&=' '____')"
if [[ -f "$FIXD/$key.body" ]]; then
  cat "$FIXD/$key.body" > "$out"; code="$(cat "$FIXD/$key.code" 2>/dev/null || echo 200)"
else
  : > "$out"; code=404
fi
printf '%s' "$code"
SH
chmod +x "$SHIM/curl"
fx() { local k; k="$(printf '%s' "$1" | tr '/?&=' '____')"; printf '%s' "$2" > "$FIXD/$k.body"; [[ -n "${3-}" ]] && printf '%s' "$3" > "$FIXD/$k.code"; return 0; }
base_fx() { # server-id: the happy path (volume attached to the server, LUKS volume on the same server)
  assert_fixture_dir "$TMP"; rm -rf "$FIXD"; mkdir -p "$FIXD"
  fx "/servers?name=soleur-git-data" "{\"servers\":[{\"id\":$1,\"name\":\"soleur-git-data\",\"volumes\":[107140231]}]}"
  fx "/volumes?name=soleur-git-data-luks-store" "{\"volumes\":[{\"id\":107140231,\"server\":$1}]}"
  fx "/volumes/106867358" "{\"volume\":{\"id\":106867358,\"name\":\"soleur-git-data-store\",\"server\":$1,\"created\":\"2026-09-01T00:00:00+00:00\",\"protection\":{\"delete\":false}}}"
  fx "/volumes?name=soleur-git-data-store" "{\"volumes\":[{\"id\":106867358}]}"
}
run_probe() { # -> rc; stdout $TMP/probe.out, stderr $TMP/probe.err
  assert_fixture_dir "$TMP"
  HCLOUD_TOKEN=x HAPI_RETRY_SLEEP_S=0 FIXD="$FIXD" PATH="$SHIM:$PATH" bash "$PROBE" > "$TMP/probe.out" 2> "$TMP/probe.err"
}
base_fx 180000001; run_probe; rc=$?
chk "T1 attached to the live server (an id that is NOT the old constant)" "$rc" 0 "$TMP/probe.out" "shape=present_attached"
chk "T1b the live ids are printed" 0 0 "$TMP/probe.out" "server_id=180000001"
chk "T1c volume_created is printed" 0 0 "$TMP/probe.out" "volume_created=2026-09-01T00:00:00+00:00"
chk "T1d volume_delete_protected is printed" 0 0 "$TMP/probe.out" "volume_delete_protected=false"
chk "T1e luks ids printed" 0 0 "$TMP/probe.out" "luks_volume_id=107140231"
if [[ "$(head -1 "$TMP/probe.out")" == "plaintext_volume=present" ]]; then pass; else fail "T1f the FIRST stdout line must be the plaintext_volume= summary"; fi
base_fx 180000001; fx "/volumes/106867358" '{"volume":{"id":106867358,"name":"soleur-git-data-store","server":null,"created":"x","protection":{"delete":false}}}'; run_probe; rc=$?
chk "T2 attached to no server is present_detached" "$rc" 0 "$TMP/probe.out" "shape=present_detached"
base_fx 180000001; fx "/volumes/106867358" '{"volume":{"id":106867358,"name":"soleur-git-data-store","server":999,"created":"x","protection":{"delete":false}}}'; run_probe; rc=$?
chk "T3 attached to another server is attached_elsewhere" "$rc" 0 "$TMP/probe.out" "shape=attached_elsewhere"
base_fx 180000001; fx "/volumes/106867358" '{"volume":{"id":106867358,"name":"other","server":180000001,"created":"x","protection":{"delete":false}}}'; run_probe; rc=$?
chk "T4 wrong name is identity_mismatch" "$rc" 0 "$TMP/probe.out" "shape=identity_mismatch"
base_fx 180000001; rm -f "$FIXD/_volumes_106867358.body"; fx "/volumes?name=soleur-git-data-store" '{"volumes":[]}'; run_probe; rc=$?
chk "T5 404 by id and an empty name list is gone" "$rc" 0 "$TMP/probe.out" "shape=gone"
chk "T5b gone is summarised absent" 0 0 "$TMP/probe.out" "plaintext_volume=absent"
base_fx 180000001; rm -f "$FIXD/_volumes_106867358.body"; fx "/volumes?name=soleur-git-data-store" '{"volumes":[{"id":555}]}'; run_probe; rc=$?
chk "T6 404 by id but the name exists under another id is name_other_id" "$rc" 0 "$TMP/probe.out" "shape=name_other_id"
base_fx 180000001; fx "/servers?name=soleur-git-data" '{"servers":[]}'; run_probe; rc=$?
chk "T7 zero servers named soleur-git-data: presence proof fails (exit 5)" "$rc" 5 "$TMP/probe.out" "presence_proof server_missing"
base_fx 180000001; fx "/servers?name=soleur-git-data" '{"servers":[{"id":1,"volumes":[107140231]},{"id":2,"volumes":[]}]}'; run_probe; rc=$?
chk "T8 two servers named soleur-git-data: presence proof fails (exit 5)" "$rc" 5 "$TMP/probe.out" "server_ambiguous"
base_fx 180000001; fx "/volumes?name=soleur-git-data-luks-store" '{"volumes":[{"id":107140231,"server":999}]}'; run_probe; rc=$?
chk "T9 LUKS volume attached to another server: presence proof fails (exit 5)" "$rc" 5 "$TMP/probe.out" "luks_volume_missing"
base_fx 180000001; fx "/volumes?name=soleur-git-data-luks-store" '{"volumes":[]}'; run_probe; rc=$?
chk "T10 no LUKS volume: presence proof fails (exit 5)" "$rc" 5 "$TMP/probe.out" "luks_volume_missing"
base_fx 180000001; fx "/volumes/106867358" '{}' 503; run_probe; rc=$?
chk "T11 a persistent 503 is an API error (exit 4), never absent" "$rc" 4 "$TMP/probe.out" "plaintext_volume=unknown"
base_fx 180000001; fx "/volumes?name=soleur-git-data-store" '<html>' 200; run_probe; rc=$?
chk "T12 a 200 with a non-JSON body is an API/parse error (exit 4), not the presence-proof code" "$rc" 4 "$TMP/probe.err" "parse"
assert_fixture_dir "$TMP"
env -u HCLOUD_TOKEN -u HCLOUD_TOKEN_READONLY PATH="$SHIM:/usr/bin:/bin" bash "$PROBE" > "$TMP/probe.out" 2>&1; rc=$?
chk "T13 no credential is exit 3" "$rc" 3 "$TMP/probe.out" "error=no_credential"
# the probe issues only GETs: no write verb anywhere in the file
if grep -E -- '-X[[:space:]]+(POST|PUT|PATCH|DELETE)' "$PROBE" >/dev/null; then fail "T14 the probe must issue only GETs"; else pass; fi

# ── structural: the lib calls the preamble (anchored on the CALL) and names the local ──
if grep -qE '^[[:space:]]*plan_gate_assert_readable' "$LIB" \
   && grep -qE 'local plan_json' "$LIB" \
   && ! grep -qF 'ack-destroy' "$LIB"; then
  pass
else
  fail "S1: lib must CALL plan_gate_assert_readable, name 'local plan_json', and carry no ack-destroy bypass"
fi

# ── the verdict gate itself: a failing assertion must make THIS suite exit non-zero ──
# The child re-runs the suite with one injected failure and must exit non-zero. If the final exit line is
# disarmed, the child exits 0 and this row (reported with printf + exit, not through fail()) goes red.
PDG_INJECT_FAIL=1 bash "${BASH_SOURCE[0]}" >/dev/null 2>&1; _crc=$?
if [[ "$_crc" -eq 0 ]]; then
  printf 'FATAL: the suite exited 0 with an injected failing assertion — its verdict() is disarmed\n'
  exit 1
fi
pass

# ANTI-VACUITY FLOOR. Self-contained (bash builtins and this suite's own counters only): the
# threshold is declared on the line IMMEDIATELY above its `if` so guard-vacuity-floor's mutant
# can slice it. A FLOOR, NOT EQUALITY: the count is developer-incremented.
_floor=141
_ran=$((passes + fails))
if [[ "$_ran" -lt "$_floor" ]]; then
  fails=$((fails + 1)); FAILED+=("anti-vacuity floor")
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is %s. Arms were deleted, skipped, or the suite exited early.\n' "$_ran" "$_floor"
else
  printf '  ok   anti-vacuity floor: %s assertions ran (floor %s)\n' "$_ran" "$_floor"
fi

verdict
