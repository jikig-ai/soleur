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

# plan <file> <addr:actions[:import=<id>]>... — a minimal plan JSON; actions are comma-joined,
# e.g. hcloud_server.rehearsal:delete,create. A trailing `:import=<id>` sets .change.importing,
# the shape `terraform show -json` gives an `import` block's resource_change.
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
# The commas join a resource's action verbs (plan() splits on them), not array elements.
# shellcheck disable=SC2054
HOSTONLY_OK=(hcloud_server.rehearsal:delete,create hcloud_volume_attachment.rehearsal:delete,create
             hcloud_volume_attachment.rehearsal_luks:delete,create hcloud_firewall_attachment.rehearsal:update
             hcloud_volume.rehearsal:no-op hcloud_volume.rehearsal_luks:no-op)

# run <script> <plan> <mode> — sets RC and OUT.
RC=0; OUT=""
run() { RC=0; OUT="$(bash "$1" "$2" "$3" 2>&1)" || RC=$?; }
# want <label> <want-rc> <plan-file> <mode> [script] [reason]
# A REFUSAL IS ASSERTED BY ITS REASON, not only by rc=1. Several fixtures are refused by more than
# one check (a non-rehearsal create in host-only mode also trips the replace-presence check), so an
# rc-only row stays green when the check it names is deleted. With [reason], some `::error::` line
# must carry that fixed string. Pass "" for [script] to keep the pristine SUT.
want() {
  local label="$1" w="$2" p="$3" m="$4" s="${5:-$SUT}" why="${6:-}"
  cases=$((cases + 1)); run "$s" "$p" "$m"
  if [[ "$RC" != "$w" ]]; then fail "$label — expected rc=$w, got $RC" "$OUT"; return; fi
  if [[ -n "$why" ]] && ! grep -F -- '::error::' <<<"$OUT" | grep -cF >/dev/null -- "$why"; then
    fail "$label — rc=$RC but no ::error:: line carries the reason '$why'" "$OUT"; return
  fi
  pass "$label (rc=$RC${why:+, reason matched})"
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

# (#10196 D3) The rehearsal's two late-attachment delay resources. Their addresses are exact-match
# admitted in host-only mode; additive mode already admits them as plain rehearsal-scoped creates.
DELAY_LUKS=terraform_data.rehearsal_attach_delay_luks
DELAY_PT=terraform_data.rehearsal_attach_delay_pt
# real_delay_plan <file> <spec>... — plan() output with the two delay replaces appended in the shape
# a real `terraform show -json` gives a terraform_data whose triggers_replace changed. Generated
# 2026-10-13 with terraform 1.9.8 from a scratch root declaring the same two resources (no providers
# needed: terraform_data is built in), applied with triggers_replace="1", then planned with "2"; the
# entries are that output verbatim apart from the ids, which are fixed strings here.
real_delay_plan() {
  local out="$1"; shift
  plan "$out" "$@"
  jq -c --arg l "$DELAY_LUKS" --arg p "$DELAY_PT" '.resource_changes += ([$l, $p] | map({
      address: ., mode: "managed", type: "terraform_data", name: (. | split(".")[1]),
      provider_name: "terraform.io/builtin/terraform",
      change: {actions: ["delete", "create"],
               before: {id: "00000000-0000-0000-0000-000000000000", input: null, output: null, triggers_replace: "1"},
               after: {input: null, output: null, triggers_replace: "2"},
               after_unknown: {id: true}, before_sensitive: {}, after_sensitive: {},
               replace_paths: [["triggers_replace"]]},
      action_reason: "replace_because_cannot_update"}))' "$out" > "$out.tmp" && mv "$out.tmp" "$out"
}
real_delay_plan "$TMP/delay-ok.json" "${HOSTONLY_OK[@]}" tls_private_key.rehearsal_host_ssh:delete,create
want "host-only: the two delay replaces (real terraform show -json shape) alongside the three host replaces are admitted" 0 "$TMP/delay-ok.json" host-only
plan "$TMP/delay-ok-min.json" "${HOSTONLY_OK[@]}" "$DELAY_LUKS:delete,create" "$DELAY_PT:create,delete"
want "host-only: the delay replaces in either action order are admitted" 0 "$TMP/delay-ok-min.json" host-only
plan "$TMP/delay-seed.json" hcloud_server.rehearsal:create hcloud_volume.rehearsal:create hcloud_volume.rehearsal_luks:create \
  hcloud_volume_attachment.rehearsal:create hcloud_volume_attachment.rehearsal_luks:create "$DELAY_LUKS:create" "$DELAY_PT:create"
want "additive: the seed plan creating both delay resources is admitted (plain rehearsal-scoped creates)" 0 "$TMP/delay-seed.json" additive

# ── refused (the Guard 3 matrix) ────────────────────────────────────────────────
plan "$TMP/m1.json" "${HOSTONLY_OK[@]/hcloud_volume.rehearsal:no-op/hcloud_volume.rehearsal:delete,create}"
want "row 1: host-only refuses a replace of hcloud_volume.rehearsal (the dirtied volume)" 1 "$TMP/m1.json" host-only "" "a replace of hcloud_volume.rehearsal is not admitted"
plan "$TMP/m1b.json" "${HOSTONLY_OK[@]/hcloud_volume.rehearsal_luks:no-op/hcloud_volume.rehearsal_luks:delete,create}"
want "row 1b / T14: host-only refuses a replace of hcloud_volume.rehearsal_luks (would skip the adopt arm)" 1 "$TMP/m1b.json" host-only "" "a replace of hcloud_volume.rehearsal_luks is not admitted"
plan "$TMP/m2.json" "${HOSTONLY_OK[@]}" hcloud_ssh_key.rehearsal:forget
want "row 2: host-only refuses a forget (deny-list the inert verbs)" 1 "$TMP/m2.json" host-only "" "hcloud_ssh_key.rehearsal forget is not admitted"
plan "$TMP/m3.json" hcloud_server.rehearsal:delete,create
want "row 3: additive refuses a replace" 1 "$TMP/m3.json" additive "" "non-additive change(s)"
plan "$TMP/m4.json" "${HOSTONLY_OK[@]}" hcloud_firewall.rehearsal:delete,create
want "row 4: host-only refuses a second, unlisted replace" 1 "$TMP/m4.json" host-only "" "a replace of hcloud_firewall.rehearsal is not admitted"
printf '{not json' > "$TMP/m5.json"
want "row 5: an unparseable plan fails closed" 1 "$TMP/m5.json" host-only "" "could not parse the plan JSON"
want "row 5: an unparseable plan fails closed (additive)" 1 "$TMP/m5.json" additive "" "could not parse the plan JSON"
plan "$TMP/m9a.json" "${HOSTONLY_OK[@]/hcloud_volume.rehearsal:no-op/hcloud_volume.rehearsal:update}"
want "row 9: host-only refuses an in-place update of a volume" 1 "$TMP/m9a.json" host-only "" "an update of hcloud_volume.rehearsal is not admitted"
plan "$TMP/m9b.json" "${HOSTONLY_OK[@]/hcloud_volume.rehearsal_luks:no-op/hcloud_volume.rehearsal_luks:delete}"
want "row 9: host-only refuses a plain delete of a volume" 1 "$TMP/m9b.json" host-only "" "hcloud_volume.rehearsal_luks delete is not admitted"
plan "$TMP/empty.json"
want "harness RED: a host-only plan with ZERO resource_changes is not clean (the replace must be present)" 1 "$TMP/empty.json" host-only "" "server=0 attachment=0 attachment_luks=0"
plan "$TMP/noatt.json" hcloud_server.rehearsal:delete,create hcloud_firewall_attachment.rehearsal:update
want "host-only refuses a host replace without both attachments" 1 "$TMP/noatt.json" host-only "" "server=1 attachment=0 attachment_luks=0"
plan "$TMP/prodcreate.json" hcloud_server.git_data:create
want "additive refuses a create of a NON-rehearsal address" 1 "$TMP/prodcreate.json" additive "" "NON-rehearsal address: hcloud_server.git_data"
want "host-only refuses a create of a NON-rehearsal address" 1 "$TMP/prodcreate.json" host-only "" "NON-rehearsal address: hcloud_server.git_data"
plan "$TMP/fwother.json" "${HOSTONLY_OK[@]}" hcloud_firewall.rehearsal:update
want "host-only refuses an update of anything but the firewall attachment" 1 "$TMP/fwother.json" host-only "" "an update of hcloud_firewall.rehearsal is not admitted"
want "an unknown mode is a usage error" 64 "$TMP/payload.json" replace

# ── (review W3) fixtures that used to pass for the WRONG reason, or not at all ────────
# (a) the admitted host-only set PLUS a production create. prodcreate.json above is also refused
# by the replace-presence check, so it cannot show that host-only runs the scope check at all.
plan "$TMP/w3a.json" "${HOSTONLY_OK[@]}" hcloud_server.git_data:create
want "W3a: host-only refuses a NON-rehearsal create riding on an otherwise admitted plan" 1 "$TMP/w3a.json" host-only "" \
  "NON-rehearsal address: hcloud_server.git_data"
# (b) server + plain attachment replaced, the LUKS attachment NOT: boot #2 would come up with the
# LUKS volume still attached to a server that no longer exists.
plan "$TMP/w3b.json" hcloud_server.rehearsal:delete,create hcloud_volume_attachment.rehearsal:delete,create \
  hcloud_firewall_attachment.rehearsal:update hcloud_volume.rehearsal:no-op hcloud_volume.rehearsal_luks:no-op
want "W3b: host-only refuses a replace that omits hcloud_volume_attachment.rehearsal_luks" 1 "$TMP/w3b.json" host-only "" \
  "server=1 attachment=1 attachment_luks=0"
# (c) near-miss create addresses. `git_data_rehearsal` never matched the old glob; a MODULE-scoped
# `.rehearsal` did, because a case-glob `*` spans dots.
plan "$TMP/w3c1.json" hcloud_volume.git_data_rehearsal:create
want "W3c: additive refuses a create of hcloud_volume.git_data_rehearsal (suffix is not scope)" 1 "$TMP/w3c1.json" additive "" \
  "NON-rehearsal address: hcloud_volume.git_data_rehearsal"
plan "$TMP/w3c2.json" module.git_data.hcloud_server.rehearsal:create
want "W3c: additive refuses a module-scoped create ending .rehearsal (the old glob admitted it)" 1 "$TMP/w3c2.json" additive "" \
  "NON-rehearsal address: module.git_data.hcloud_server.rehearsal"
plan "$TMP/w3c3.json" "${HOSTONLY_OK[@]}" module.git_data.hcloud_volume.rehearsal_luks:create
want "W3c: host-only refuses the same module-scoped create" 1 "$TMP/w3c3.json" host-only "" \
  "NON-rehearsal address: module.git_data.hcloud_volume.rehearsal_luks"
# (d) an import. It plans as no-op, so the verb deny-list alone admits it — in BOTH modes.
plan "$TMP/w3d1.json" "${HOSTONLY_OK[@]/hcloud_volume.rehearsal:no-op/hcloud_volume.rehearsal:no-op:import=100000001}"
want "W3d: host-only refuses an importing resource_change (an import plans as no-op)" 1 "$TMP/w3d1.json" host-only "" \
  "the plan IMPORTS hcloud_volume.rehearsal"
plan "$TMP/w3d2.json" hcloud_server.rehearsal:create hcloud_volume.rehearsal:no-op:import=100000001
want "W3d: additive refuses an importing resource_change" 1 "$TMP/w3d2.json" additive "" \
  "the plan IMPORTS hcloud_volume.rehearsal"

# ── (#10196 D3, Guard 4 row 5) the delay addresses are admitted EXACTLY, never by glob or index ──
plan "$TMP/dl-glob.json" "${HOSTONLY_OK[@]}" terraform_data.rehearsal_other:delete,create
want "D3: host-only refuses a replace of a terraform_data that is not one of the two delay addresses (no glob)" 1 "$TMP/dl-glob.json" host-only "" \
  "a replace of terraform_data.rehearsal_other is not admitted"
plan "$TMP/dl-prefix.json" "${HOSTONLY_OK[@]}" terraform_data.rehearsal_attach_delay_luks_extra:delete,create
want "D3: host-only refuses a near-miss suffix of a delay address (exact match, not prefix)" 1 "$TMP/dl-prefix.json" host-only "" \
  "a replace of terraform_data.rehearsal_attach_delay_luks_extra is not admitted"
plan "$TMP/dl-idx.json" "${HOSTONLY_OK[@]}" "terraform_data.rehearsal_attach_delay_luks[0]:delete,create"
want "D3: host-only refuses an indexed ([0]) replace of a delay address" 1 "$TMP/dl-idx.json" host-only "" \
  "a replace of terraform_data.rehearsal_attach_delay_luks[0] is not admitted"
plan "$TMP/dl-idx-create.json" "$DELAY_LUKS[0]:create"
want "D3: additive refuses a CREATE of an indexed ([0]) delay address (the create regex has no index)" 1 "$TMP/dl-idx-create.json" additive "" \
  "NON-rehearsal address: terraform_data.rehearsal_attach_delay_luks[0]"
plan "$TMP/dl-upd.json" "${HOSTONLY_OK[@]}" "$DELAY_PT:update"
want "D3: host-only refuses an in-place update of a delay resource (only a replace is admitted)" 1 "$TMP/dl-upd.json" host-only "" \
  "an update of terraform_data.rehearsal_attach_delay_pt is not admitted"
plan "$TMP/dl-del.json" "${HOSTONLY_OK[@]}" "$DELAY_PT:delete"
want "D3: host-only refuses a plain delete of a delay resource" 1 "$TMP/dl-del.json" host-only "" \
  "terraform_data.rehearsal_attach_delay_pt delete is not admitted"
plan "$TMP/dl-prod.json" "${HOSTONLY_OK[@]}" terraform_data.root_authorized_keys:delete,create
want "D3: host-only refuses a replace of a production terraform_data" 1 "$TMP/dl-prod.json" host-only "" \
  "a replace of terraform_data.root_authorized_keys is not admitted"

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
want "row 6 instrument: the pristine script refuses the volume replace" 1 "$TMP/m1.json" host-only "" "a replace of hcloud_volume.rehearsal is not admitted"
want "row 6 MUTANT (unanchored hcloud_volume*rehearsal) admits the volume replace — the arm is live" 0 "$TMP/m1.json" host-only "$MUT"
# row 7 — the "replace must be present" check removed.
mutant nopresence '  if [[ "$seen_server$seen_att$seen_att_luks" != 111 ]]; then' '  if false; then'
want "row 7 instrument: the pristine script refuses an empty host-only plan" 1 "$TMP/empty.json" host-only "" "server=0 attachment=0 attachment_luks=0"
want "row 7 MUTANT (presence check removed) admits the empty plan — the arm is live" 0 "$TMP/empty.json" host-only "$MUT"
# row 8 — only ["delete","create"] recognised as a replace.
mutant onlydc '      delete,create|create,delete)' '      delete,create)'
want "row 8 instrument: the pristine script admits [create,delete] ordering" 0 "$TMP/order.json" host-only
want "row 8 MUTANT (only delete,create) refuses the create_before_destroy ordering — the arm is live" 1 "$TMP/order.json" host-only "$MUT" "hcloud_server.rehearsal create,delete is not admitted"

# shellcheck disable=SC2016  # rows 10-13: the mutant anchors are literal script text, not expansions
{
# row 10 — the create scope check run in additive mode only (W3a must catch it).
mutant scopeadditive 'done <<<"$creates"' 'done <<<"$([[ "$MODE" == additive ]] && printf '"'"'%s'"'"' "$creates")"'
want "row 10 MUTANT (scope check additive-only) admits W3a's production create — the arm is live" 0 "$TMP/w3a.json" host-only "$MUT"
# row 11 — the presence check without the LUKS attachment (W3b must catch it).
mutant noluksatt '  if [[ "$seen_server$seen_att$seen_att_luks" != 111 ]]; then' '  if [[ "$seen_server$seen_att" != 11 ]]; then'
want "row 11 MUTANT (presence ignores attachment_luks) admits W3b — the arm is live" 0 "$TMP/w3b.json" host-only "$MUT"
# row 12 — the scope check loosened back to the old glob (W3c's module-scoped create must catch it).
mutant oldglob '  if [[ ! "$addr" =~ ^[a-z0-9_]+\.rehearsal(_[a-z0-9_]+)?$ ]]; then' '  if [[ "$addr" != *.rehearsal && "$addr" != *.rehearsal_* ]]; then'
want "row 12 MUTANT (the old *.rehearsal glob) admits the module-scoped create — the arm is live" 0 "$TMP/w3c2.json" additive "$MUT"
# row 13 — the importing check removed (W3d must catch it).
mutant noimport 'done <<<"$imports"' 'done <<<""'
want "row 13 MUTANT (importing check removed) admits the importing host-only plan — the arm is live" 0 "$TMP/w3d1.json" host-only "$MUT"
# rows 14-16 (#10196 D3): the admitted-delay list.
# row 14 — the list is a glob over every terraform_data.
mutant tdglob '          tls_private_key.rehearsal_host_ssh) ;;' '          tls_private_key.rehearsal_host_ssh) ;;
          terraform_data.*) ;;'
want "row 14 instrument: the pristine script refuses a replace of an unlisted terraform_data" 1 "$TMP/dl-glob.json" host-only "" "a replace of terraform_data.rehearsal_other is not admitted"
want "row 14 MUTANT (terraform_data.* glob) admits the unlisted replace — the arm is live" 0 "$TMP/dl-glob.json" host-only "$MUT"
want "row 14 MUTANT (terraform_data.* glob) admits a production terraform_data replace — the arm is live" 0 "$TMP/dl-prod.json" host-only "$MUT"
# row 15 — the create regex widened to accept an index suffix.
mutant createidx '  if [[ ! "$addr" =~ ^[a-z0-9_]+\.rehearsal(_[a-z0-9_]+)?$ ]]; then' '  if [[ ! "$addr" =~ ^[a-z0-9_]+\.rehearsal(_[a-z0-9_]+)?(\[[0-9]+\])?$ ]]; then'
want "row 15 instrument: the pristine script refuses a create of an indexed delay address" 1 "$TMP/dl-idx-create.json" additive "" "NON-rehearsal address: terraform_data.rehearsal_attach_delay_luks[0]"
want "row 15 MUTANT (create regex accepts [0]) admits the indexed create — the arm is live" 0 "$TMP/dl-idx-create.json" additive "$MUT"
# row 16 — the two delay entries dropped from the admitted list: the must-PASS plan flips to refused.
mutant nodelay '          terraform_data.rehearsal_attach_delay_luks|terraform_data.rehearsal_attach_delay_pt) ;;' ''
want "row 16 instrument: the pristine script admits the two delay replaces alongside the host replaces" 0 "$TMP/delay-ok.json" host-only
want "row 16 MUTANT (delay addresses removed from the admitted list) refuses the must-PASS plan — the arm is live" 1 "$TMP/delay-ok.json" host-only "$MUT" "a replace of terraform_data.rehearsal_attach_delay_"
}

# ── floors: printf + exit, never through pass()/fail() (ADR-193) ────────────────
# 3 -> 7 (review W3): rows 10-13, one per new check, each flipping a W3 fixture to admitted.
# 7 -> 10 (#10196 D3): rows 14-16, one per new check on the admitted-delay list (glob, indexed create, list removal).
MUT_EXPECTED=10
if (( MUTS != MUT_EXPECTED )); then
  printf '[FATAL] anti-vacuity floor: %s script mutants ran, expected %s\n' "$MUTS" "$MUT_EXPECTED" >&2
  exit 1
fi
# 25 -> 36 (review W3): +7 W3 fixtures (a, b, 3x c, 2x d) and +4 mutant rows. Measured: 36 ran.
# (d)'s rows name the IMPORTS reason, so an import-free twin fixture would add nothing the reason
# match does not already prove.
# 36 -> 53 (#10196 D3): +3 must-PASS delay plans (real-shape host-only, either order, additive seed), +7 refusal rows
# (glob, near-miss suffix, [0] replace, [0] create, update, delete, production terraform_data) and +7 mutant
# rows (3 instruments + 4 mutants across rows 14-16). Measured: 53 ran.
MIN_CASES=53
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
