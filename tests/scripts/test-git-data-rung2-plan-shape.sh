#!/usr/bin/env bash
# test-git-data-rung2-plan-shape.sh — Guard 3 (#5274): the rung-2 payload phase and replace arm
# replace ONLY the host, never the dirtied plaintext volume or the LUKS volume, and the seed phase
# is additive-only. Drives scripts/git-data-rung2-plan-shape.sh over synthesized plan JSON, then
# runs its script-level mutants and requires each to flip a verdict the pristine script gets right.
#
# Run: bash tests/scripts/test-git-data-rung2-plan-shape.sh
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUT="$ROOT/scripts/git-data-rung2-plan-shape.sh"
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

TMP="$(mktemp -d -t r2planshape.XXXXXXXX)" || { echo "FAIL: mktemp" >&2; exit 2; }
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

# plan <file> <addr:actions>... — a minimal plan JSON; actions are comma-joined, e.g.
# hcloud_server.rehearsal:delete,create
plan() {
  local out="$1"; shift
  assert_fixture_dir "$out"
  local arr="[]" spec addr acts
  for spec in "$@"; do
    addr="${spec%%:*}"; acts="${spec#*:}"
    arr="$(jq -c --arg a "$addr" --arg x "$acts" '. + [{address: $a, change: {actions: ($x | split(","))}}]' <<<"$arr")"
  done
  jq -n --argjson rc "$arr" '{format_version: "1.2", resource_changes: $rc}' > "$out"
}
HOSTONLY_OK=(hcloud_server.rehearsal:delete,create hcloud_volume_attachment.rehearsal:delete,create
             hcloud_volume_attachment.rehearsal_luks:delete,create hcloud_firewall_attachment.rehearsal:update
             hcloud_volume.rehearsal:no-op hcloud_volume.rehearsal_luks:no-op)

# run <script> <plan> <mode> — sets RC and OUT.
RC=0; OUT=""
run() { RC=0; OUT="$(bash "$1" "$2" "$3" 2>&1)" || RC=$?; }
want() { # <label> <want-rc> <plan-file> <mode> [script]
  local label="$1" w="$2" p="$3" m="$4" s="${5:-$SUT}"
  cases=$((cases + 1)); run "$s" "$p" "$m"
  if [[ "$RC" == "$w" ]]; then pass "$label (rc=$RC)"; else fail "$label — expected rc=$w, got $RC" "$OUT"; fi
}

# ── admitted ────────────────────────────────────────────────────────────────────
plan "$TMP/seed.json" hcloud_server.rehearsal:create hcloud_volume.rehearsal:create hcloud_volume.rehearsal_luks:create \
  hcloud_volume_attachment.rehearsal:create doppler_config.rehearsal:create tls_private_key.rehearsal_host_ssh:create
want "additive: a fresh seed plan (creates only, rehearsal-scoped) is admitted" 0 "$TMP/seed.json" additive
plan "$TMP/payload.json" "${HOSTONLY_OK[@]}"
want "host-only: the payload replace of the host + both attachments, firewall update, volumes untouched" 0 "$TMP/payload.json" host-only
plan "$TMP/replace.json" "${HOSTONLY_OK[@]}" tls_private_key.rehearsal_host_ssh:delete,create
want "host-only: the replace arm also rotating tls_private_key.rehearsal_host_ssh" 0 "$TMP/replace.json" host-only
# Must-PASS, non-canonical: the admitted set in another order, create_before_destroy ordering.
plan "$TMP/order.json" hcloud_volume_attachment.rehearsal_luks:create,delete hcloud_firewall_attachment.rehearsal:update \
  hcloud_server.rehearsal:create,delete hcloud_volume_attachment.rehearsal:delete,create
want "host-only: the admitted set in another order with [create,delete] ordering is admitted" 0 "$TMP/order.json" host-only

# ── refused (the Guard 3 matrix) ────────────────────────────────────────────────
plan "$TMP/m1.json" "${HOSTONLY_OK[@]/hcloud_volume.rehearsal:no-op/hcloud_volume.rehearsal:delete,create}"
want "row 1: host-only refuses a replace of hcloud_volume.rehearsal (the dirtied volume)" 1 "$TMP/m1.json" host-only
plan "$TMP/m1b.json" "${HOSTONLY_OK[@]/hcloud_volume.rehearsal_luks:no-op/hcloud_volume.rehearsal_luks:delete,create}"
want "row 1b / T14: host-only refuses a replace of hcloud_volume.rehearsal_luks (would skip the adopt arm)" 1 "$TMP/m1b.json" host-only
plan "$TMP/m2.json" "${HOSTONLY_OK[@]}" hcloud_ssh_key.rehearsal:forget
want "row 2: host-only refuses a forget (deny-list the inert verbs)" 1 "$TMP/m2.json" host-only
plan "$TMP/m3.json" hcloud_server.rehearsal:delete,create
want "row 3: additive refuses a replace" 1 "$TMP/m3.json" additive
plan "$TMP/m4.json" "${HOSTONLY_OK[@]}" hcloud_firewall.rehearsal:delete,create
want "row 4: host-only refuses a second, unlisted replace" 1 "$TMP/m4.json" host-only
printf '{not json' > "$TMP/m5.json"
want "row 5: an unparseable plan fails closed" 1 "$TMP/m5.json" host-only
want "row 5: an unparseable plan fails closed (additive)" 1 "$TMP/m5.json" additive
plan "$TMP/m9a.json" "${HOSTONLY_OK[@]/hcloud_volume.rehearsal:no-op/hcloud_volume.rehearsal:update}"
want "row 9: host-only refuses an in-place update of a volume" 1 "$TMP/m9a.json" host-only
plan "$TMP/m9b.json" "${HOSTONLY_OK[@]/hcloud_volume.rehearsal_luks:no-op/hcloud_volume.rehearsal_luks:delete}"
want "row 9: host-only refuses a plain delete of a volume" 1 "$TMP/m9b.json" host-only
plan "$TMP/empty.json"
want "harness RED: a host-only plan with ZERO resource_changes is not clean (the replace must be present)" 1 "$TMP/empty.json" host-only
plan "$TMP/noatt.json" hcloud_server.rehearsal:delete,create hcloud_firewall_attachment.rehearsal:update
want "host-only refuses a host replace without both attachments" 1 "$TMP/noatt.json" host-only
plan "$TMP/prodcreate.json" hcloud_server.git_data:create
want "additive refuses a create of a NON-rehearsal address" 1 "$TMP/prodcreate.json" additive
want "host-only refuses a create of a NON-rehearsal address" 1 "$TMP/prodcreate.json" host-only
plan "$TMP/fwother.json" "${HOSTONLY_OK[@]}" hcloud_firewall.rehearsal:update
want "host-only refuses an update of anything but the firewall attachment" 1 "$TMP/fwother.json" host-only
want "an unknown mode is a usage error" 64 "$TMP/payload.json" replace

# ── script-level mutants (rows 6-8): each flips a verdict the pristine script gets right ──
MUTS=0
mutant() { # <name> <old> <new> — writes $TMP/mut.<name>.sh; refuses if the edit did not land
  local dst="$TMP/mut.$1.sh"
  python3 - "$SUT" "$dst" "$2" "$3" <<'PY' || { echo "FAIL: mutant $1 did not land (anchor drifted)" >&2; exit 1; }
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1:
    sys.exit(1)
open(dst, "w").write(s.replace(old, new))
PY
  MUTS=$((MUTS + 1)); MUT="$dst"
}
# row 6 — an unanchored address match admits a volume replace.
mutant unanchored '          tls_private_key.rehearsal_host_ssh) ;;' '          tls_private_key.rehearsal_host_ssh) ;;
          hcloud_volume*rehearsal) ;;'
want "row 6 instrument: the pristine script refuses the volume replace" 1 "$TMP/m1.json" host-only
want "row 6 MUTANT (unanchored hcloud_volume*rehearsal) admits the volume replace — the arm is live" 0 "$TMP/m1.json" host-only "$MUT"
# row 7 — the "replace must be present" check removed.
mutant nopresence '  if [[ "$seen_server$seen_att$seen_att_luks" != 111 ]]; then' '  if false; then'
want "row 7 instrument: the pristine script refuses an empty host-only plan" 1 "$TMP/empty.json" host-only
want "row 7 MUTANT (presence check removed) admits the empty plan — the arm is live" 0 "$TMP/empty.json" host-only "$MUT"
# row 8 — only ["delete","create"] recognised as a replace.
mutant onlydc '      delete,create|create,delete)' '      delete,create)'
want "row 8 instrument: the pristine script admits [create,delete] ordering" 0 "$TMP/order.json" host-only
want "row 8 MUTANT (only delete,create) refuses the create_before_destroy ordering — the arm is live" 1 "$TMP/order.json" host-only "$MUT"

# ── floors: printf + exit, never through pass()/fail() (ADR-193) ────────────────
MUT_EXPECTED=3
if (( MUTS != MUT_EXPECTED )); then
  printf '[FATAL] anti-vacuity floor: %s script mutants ran, expected %s\n' "$MUTS" "$MUT_EXPECTED" >&2
  exit 1
fi
MIN_CASES=25
if (( cases < MIN_CASES )); then
  printf '[FATAL] anti-vacuity floor: only %s cases ran, floor is %s\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi
if (( PASS + FAIL != cases )); then
  printf '[FATAL] accounting: %s verdicts for %s cases\n' "$((PASS + FAIL))" "$cases" >&2
  exit 1
fi
echo "=== git-data-rung2-plan-shape: ${PASS} passed, ${FAIL} failed (${cases} cases, ${MUTS} mutants) ==="
exit $(( FAIL > 0 ))
