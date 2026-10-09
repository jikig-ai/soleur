#!/usr/bin/env bash
# test-inngest-provision-plan-shape.sh — the plan-shape gate for the #9175 rehearsal.
# Phase A may only CREATE rehearsal-scoped addresses; Phase B's delta is exactly the NIC
# attachment. Drives scripts/inngest-provision-plan-shape.sh over synthesized plan JSON,
# then runs its script-level mutants and requires each to flip a verdict the pristine
# script gets right. Mirrors test-git-data-rung2-plan-shape.sh (#5274).
#
# Run: bash tests/scripts/test-inngest-provision-plan-shape.sh
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUT="$ROOT/scripts/inngest-provision-plan-shape.sh"
[[ -f "$SUT" ]] || { echo "FAIL: missing $SUT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

PASS=0; FAIL=0; cases=0
pass() { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL $1" >&2; [[ -n "${2:-}" ]] && printf '       %s\n' "$2" >&2; }

# INSTRUMENT SELF-TEST — both helpers move their counter once, or nothing below is trustworthy.
_p0=$PASS; _f0=$FAIL
pass "instrument self-test (EXPECTED)" >/dev/null
fail "instrument self-test (EXPECTED)" 2>/dev/null
if (( PASS != _p0 + 1 || FAIL != _f0 + 1 )); then echo "FAIL: instrument self-test" >&2; exit 2; fi
PASS=$_p0; FAIL=$_f0

TMP="$(mktemp -d -t ipplanshape.XXXXXXXX)" || { echo "FAIL: mktemp" >&2; exit 2; }
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
trap 'assert_fixture_dir "$TMP"; rm -rf "$TMP"' EXIT

# plan <file> <addr:actions[:import=<id>]>... — a minimal plan JSON; actions are comma-joined.
plan() {
  local out="$1"; shift
  assert_fixture_dir "$out"
  local arr="[]" spec addr acts imp
  for spec in "$@"; do
    addr="${spec%%:*}"; acts="${spec#*:}"; imp=""
    if [[ "$acts" == *:import=* ]]; then imp="${acts#*:import=}"; acts="${acts%%:import=*}"; fi
    arr="$(jq -c --arg a "$addr" --arg x "$acts" --arg i "$imp" \
      '. + [{address: $a, change: ({actions: ($x | split(","))} + (if $i == "" then {} else {importing: {id: $i}} end))}]' <<<"$arr")"
  done
  jq -n --argjson rc "$arr" '{format_version: "1.2", resource_changes: $rc}' > "$out"
}

# run <script> <plan> <mode> — sets RC and OUT.
RC=0; OUT=""
run() { RC=0; OUT="$(bash "$1" "$2" "$3" 2>&1)" || RC=$?; }
# want <label> <want-rc> <plan-file> <mode> [script] [reason]
want() {
  local label="$1" w="$2" p="$3" m="$4" s="${5:-$SUT}" why="${6:-}"
  cases=$((cases + 1)); run "$s" "$p" "$m"
  if [[ "$RC" != "$w" ]]; then fail "$label — expected rc=$w, got $RC" "$OUT"; return; fi
  if [[ -n "$why" ]] && ! grep -F -- '::error::' <<<"$OUT" | grep -qF -- "$why"; then
    fail "$label — rc=$RC but no ::error:: line carries the reason '$why'" "$OUT"; return
  fi
  pass "$label (rc=$RC${why:+, reason matched})"
}

# The full Phase-A create set, as `terraform plan` would emit it for this root.
ADDITIVE_OK=(
  tls_private_key.rehearsal:create hcloud_ssh_key.rehearsal:create
  doppler_environment.rehearsal:create
  random_id.rehearsal_signing_key:create random_id.rehearsal_event_key:create
  random_password.rehearsal_redis_password:create
  doppler_secret.rehearsal_signing_key:create doppler_secret.rehearsal_event_key:create
  doppler_secret.rehearsal_redis_password:create doppler_secret.rehearsal_diagnostic_boot:create
  doppler_secret.rehearsal_betterstack_logs_token:create doppler_service_token.rehearsal:create
  hcloud_volume.rehearsal:create hcloud_volume.rehearsal_luks:create
  hcloud_firewall.rehearsal:create hcloud_server.rehearsal:create
  hcloud_volume_attachment.rehearsal:create hcloud_volume_attachment.rehearsal_luks:create
)

# ── admitted ────────────────────────────────────────────────────────────────────
plan "$TMP/phaseA.json" "${ADDITIVE_OK[@]}"
want "additive: the Phase-A birth plan (creates only, rehearsal-scoped) is admitted" 0 "$TMP/phaseA.json" additive

# Phase B: second apply of the same root with nic_attached=true — the ONLY change is the
# counted NIC attachment; the rest of the stack no-ops (or is absent from the plan).
plan "$TMP/phaseB.json" hcloud_server_network.rehearsal\[0\]:create hcloud_server.rehearsal:no-op \
  hcloud_volume.rehearsal:no-op hcloud_volume.rehearsal_luks:no-op doppler_environment.rehearsal:no-op
want "nic-attach: the Phase-B delta (exactly hcloud_server_network.rehearsal[0] created) is admitted" 0 "$TMP/phaseB.json" nic-attach
# Must-PASS non-canonical: the same delta with refresh reads present.
plan "$TMP/phaseB-reads.json" hcloud_server_network.rehearsal\[0\]:create data.hcloud_network.private:read \
  hcloud_server.rehearsal:no-op
want "nic-attach: the Phase-B delta alongside a data-source read is admitted" 0 "$TMP/phaseB-reads.json" nic-attach

# ── refused ─────────────────────────────────────────────────────────────────────
plan "$TMP/m-replace.json" "${ADDITIVE_OK[@]/hcloud_server.rehearsal:create/hcloud_server.rehearsal:delete,create}"
want "additive refuses a host replace" 1 "$TMP/m-replace.json" additive "" "non-additive change(s)"
plan "$TMP/m-prod.json" "${ADDITIVE_OK[@]}" hcloud_server.inngest:create
want "additive refuses a create of a NON-rehearsal address (the PRODUCTION host)" 1 "$TMP/m-prod.json" additive "" "NON-rehearsal address: hcloud_server.inngest"
want "nic-attach refuses a NON-rehearsal create riding on the delta" 1 "$TMP/m-prod.json" nic-attach "" "NON-rehearsal address: hcloud_server.inngest"
plan "$TMP/m-module.json" module.foo.hcloud_server.rehearsal:create
want "additive refuses a module-scoped create ending .rehearsal" 1 "$TMP/m-module.json" additive "" "NON-rehearsal address: module.foo.hcloud_server.rehearsal"
plan "$TMP/m-suffix.json" hcloud_volume.inngest_rehearsal:create
want "additive refuses hcloud_volume.inngest_rehearsal (suffix is not scope)" 1 "$TMP/m-suffix.json" additive "" "NON-rehearsal address: hcloud_volume.inngest_rehearsal"
plan "$TMP/m-imp.json" "${ADDITIVE_OK[@]/hcloud_volume.rehearsal:create/hcloud_volume.rehearsal:no-op:import=100000001}"
want "additive refuses an importing resource_change (import plans as no-op)" 1 "$TMP/m-imp.json" additive "" "the plan IMPORTS hcloud_volume.rehearsal"
plan "$TMP/m-imp2.json" hcloud_server_network.rehearsal\[0\]:create hcloud_volume.rehearsal:no-op:import=100000001
want "nic-attach refuses an importing resource_change" 1 "$TMP/m-imp2.json" nic-attach "" "the plan IMPORTS hcloud_volume.rehearsal"
plan "$TMP/m-forget.json" hcloud_server_network.rehearsal\[0\]:create hcloud_ssh_key.rehearsal:forget
want "nic-attach refuses a forget (deny-list the inert verbs)" 1 "$TMP/m-forget.json" nic-attach "" "hcloud_ssh_key.rehearsal (forget) is not admitted"
plan "$TMP/m-extracreate.json" hcloud_server_network.rehearsal\[0\]:create doppler_secret.rehearsal_extra:create
want "nic-attach refuses a second rehearsal-scoped create (the delta is exactly the NIC)" 1 "$TMP/m-extracreate.json" nic-attach "" "a create of doppler_secret.rehearsal_extra is not admitted"
plan "$TMP/m-noidx.json" hcloud_server_network.rehearsal:create
want "nic-attach refuses the uncounted hcloud_server_network.rehearsal (the resource is counted [0])" 1 "$TMP/m-noidx.json" nic-attach "" "hcloud_server_network.rehearsal"
plan "$TMP/m-update.json" hcloud_server_network.rehearsal\[0\]:create hcloud_server.rehearsal:update
want "nic-attach refuses an in-place update of the host" 1 "$TMP/m-update.json" nic-attach "" "hcloud_server.rehearsal (update) is not admitted"
plan "$TMP/m-hostreplace.json" hcloud_server_network.rehearsal\[0\]:create hcloud_server.rehearsal:delete,create
want "nic-attach refuses a host replace riding on the attach (the delta must be attach-only)" 1 "$TMP/m-hostreplace.json" nic-attach "" "hcloud_server.rehearsal (delete,create) is not admitted"
plan "$TMP/empty.json"
want "nic-attach refuses a plan with ZERO resource_changes (the NIC create must be present)" 1 "$TMP/empty.json" nic-attach "" "does not create hcloud_server_network.rehearsal[0]"
printf '{not json' > "$TMP/bad.json"
want "an unparseable plan fails closed (additive)" 1 "$TMP/bad.json" additive "" "could not parse the plan JSON"
want "an unparseable plan fails closed (nic-attach)" 1 "$TMP/bad.json" nic-attach "" "could not parse the plan JSON"
want "an unknown mode is a usage error" 64 "$TMP/phaseA.json" teardown

# ── script-level mutants: each must flip a verdict the pristine script gets right ──
MUTS=0
mutant() { # <name> <old> <new> — writes $TMP/mut.<name>.sh; refuses if the edit did not land
  local dst="$TMP/mut.$1.sh"
  python3 - "$SUT" "$dst" "$2" "$3" <<'PY' || { echo "FAIL: mutant $1 did not land (anchor drifted)" >&2; exit 1; }
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
assert old in s, f"anchor not found in {src}"
open(dst, 'w').write(s.replace(old, new, 1))
PY
  MUTS=$((MUTS + 1)); MUT="$dst"; echo "  mut  $1"
}
# shellcheck disable=SC2016  # the mutant anchors are literal script text, not expansions
{
# M1 — the scope check removed: the module-scoped create must be admitted by the mutant.
mutant noscope 'if [[ ! "$addr" =~ ^[a-z0-9_]+\.rehearsal(_[a-z0-9_]+)?(\[[0-9]+\])?$ ]]; then' 'if false; then'
want "M1 (scope check removed) admits the module-scoped create — the arm is live" 0 "$TMP/m-module.json" additive "$MUT"
# M2 — the bracket arm dropped from the scope regex: the admitted [0] create is refused.
mutant nobracket '(\[[0-9]+\])?' ''
want "M2 (no [N] arm in the scope regex) refuses the counted NIC create — the arm is live" 1 "$TMP/phaseB.json" nic-attach "$MUT" "NON-rehearsal address: hcloud_server_network.rehearsal[0]"
# M3 — the importing check removed.
mutant noimport 'done <<<"$imports"' 'done <<<""'
want "M3 (importing check removed) admits the importing Phase-A plan — the arm is live" 0 "$TMP/m-imp.json" additive "$MUT"
# M4 — the NIC-presence floor removed: an empty Phase-B plan passes.
mutant nopresence 'if ! printf '"'"'%s\n'"'"' "$creates" | grep -qxF '"'"'hcloud_server_network.rehearsal[0]'"'"'; then' 'if false; then'
want "M4 (presence floor removed) admits a Phase-B plan with no NIC create — the arm is live" 0 "$TMP/empty.json" nic-attach "$MUT"
}

# ── floors: printf + exit, never through pass()/fail() (ADR-193) ────────────────
MUT_EXPECTED=4
if (( MUTS != MUT_EXPECTED )); then
  printf '[FATAL] anti-vacuity floor: %s script mutants ran, expected %s\n' "$MUTS" "$MUT_EXPECTED" >&2
  exit 1
fi
MIN_CASES=20
if (( cases < MIN_CASES )); then
  printf '[FATAL] anti-vacuity floor: only %s cases ran, floor is %s\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi
if (( PASS + FAIL != cases )); then
  printf '[FATAL] accounting: %s verdicts for %s cases\n' "$((PASS + FAIL))" "$cases" >&2
  exit 1
fi
echo "=== inngest-provision-plan-shape: ${PASS} passed, ${FAIL} failed (${cases} cases, ${MUTS} mutants) ==="
exit $(( FAIL > 0 ))
