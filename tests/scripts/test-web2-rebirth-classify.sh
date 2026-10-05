#!/usr/bin/env bash
# Test suite for tests/scripts/lib/web2-rebirth-classify.sh (#9372): every refuse rule, every heal window, the
# state-rm check, and a mutation battery that removes each rule from a COPY and requires the battery to go red.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${DIR}/lib/web2-rebirth-classify.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

PIN=106466179; SID=1001; NEW=777
# The baseline is the FIRST dispatch: the pinned ext4 volume is attached to web-2 and held by state.
base=(apply=no pause=no pin=$PIN pin_status=present pin_format=ext4 pin_name_ok=yes pin_server=$SID names=$PIN web2_sid=$SID web2_vols=$PIN state_vol=$PIN state_server=present)

battery() {
  local lib="$1" n=0
  # shellcheck disable=SC1090
  source "$lib"
  want() { # <name> <want> <overrides...>
    local name="$1" w="$2"; shift 2
    local -a args=("${base[@]}") o
    for o in "$@"; do
      local k="${o%%=*}" i
      for i in "${!args[@]}"; do [[ "${args[$i]%%=*}" == "$k" ]] && args[$i]="$o"; done
      [[ " ${args[*]} " == *" $o "* ]] || args+=("$o")
    done
    n=$((n + 1))
    local got; got="$(web2_rebirth_classify "${args[@]}")"
    [[ "$got" == "$w" ]] || printf 'FAILED %s (got %s want %s)\n' "$name" "$got" "$w"
  }
  want "first dispatch proceeds" proceed
  want "first apply dispatch with a real pause proceeds" proceed apply=yes pause=yes
  want "REFUSE 6: apply without a real push-apply pause" refuse:push_apply_pause_not_real apply=yes pause=no
  want "plan_only without the pause still proceeds (read-only)" proceed apply=no pause=no
  want "REFUSE 1: pinned volume is not ext4 (already formatted)" refuse:pinned_volume_not_the_empty_plaintext_one pin_format=none
  want "REFUSE 1: pinned volume is another filesystem" refuse:pinned_volume_not_the_empty_plaintext_one pin_format=other
  want "REFUSE 1: name or labels mismatch" refuse:pinned_volume_not_the_empty_plaintext_one pin_name_ok=no
  want "REFUSE 5: pinned volume attached to another server" refuse:pinned_volume_attached_elsewhere pin_server=9999
  want "REFUSE 5: web-2 holds a different volume as well" refuse:web2_holds_another_volume web2_vols=$PIN,$NEW names=$PIN,$NEW state_vol=$PIN
  want "REFUSE: two volumes carry the name while the pin exists" refuse:duplicate_volume_name names=$PIN,$NEW
  want "REFUSE: state does not hold the pinned volume" refuse:state_does_not_hold_the_pinned_volume state_vol=none
  want "REFUSE 2: already reborn (state holds another volume attached to web-2)" refuse:already_reborn pin_status=absent names=$NEW web2_vols=$NEW state_vol=$NEW
  want "REFUSE 4: state holds an id Hetzner does not know" refuse:state_volume_unknown_to_hetzner pin_status=absent names=none web2_vols=none state_vol=$NEW
  want "REFUSE 3: pin gone, one other named volume, state empty (orphan raw volume)" refuse:orphan_raw_volume pin_status=absent names=$NEW web2_vols=none state_vol=none
  want "REFUSE 3: pin gone, two named volumes" refuse:duplicate_volume_name pin_status=absent names=$NEW,888 web2_vols=none state_vol=none
  want "REFUSE: pin gone, named volume differs from the state's" refuse:state_volume_unknown_to_hetzner pin_status=absent names=$NEW web2_vols=none state_vol=888
  want "heal: detach done" heal:detach_done pin_server=none web2_vols=none
  want "heal: delete done (404, state still holds it)" heal:delete_done pin_status=absent names=none web2_vols=none state_vol=$PIN
  want "heal: state rm done, old server still exists" heal:state_rm_done pin_status=absent names=none web2_vols=none state_vol=none
  want "heal: apply midway, server and volume both gone" heal:apply_midway pin_status=absent names=none web2_vols=server_absent state_vol=none state_server=absent
  want "heal: raw volume created, not attached" heal:volume_created pin_status=absent names=$NEW web2_vols=none state_vol=$NEW state_server=absent
  want "bad input: unknown key" refuse:bad_input_unknown_key_bogus bogus=1
  want "bad input: non-numeric pin" refuse:bad_input pin=abc
  want "bad input: missing pin_status" refuse:bad_input pin_status=
  # state-rm check
  n=$((n + 1)); web2_rebirth_state_rm_check "$PIN" "$PIN" 5 L 6 L >/dev/null || printf 'FAILED state rm: the happy path was refused\n'
  n=$((n + 1)); web2_rebirth_state_rm_check "$PIN" "888" 5 L 6 L >/dev/null && printf 'FAILED state rm: a foreign id was accepted\n'
  n=$((n + 1)); web2_rebirth_state_rm_check "$PIN" "$PIN" 5 L 5 L >/dev/null && printf 'FAILED state rm: an unchanged serial was accepted\n'
  n=$((n + 1)); web2_rebirth_state_rm_check "$PIN" "$PIN" 5 L 7 L >/dev/null && printf 'FAILED state rm: a +2 serial was accepted\n'
  n=$((n + 1)); web2_rebirth_state_rm_check "$PIN" "$PIN" 5 L 6 M >/dev/null && printf 'FAILED state rm: a changed lineage was accepted\n'
  n=$((n + 1)); web2_rebirth_state_rm_check "$PIN" "$PIN" "" L 6 L >/dev/null && printf 'FAILED state rm: unreadable inputs were accepted\n'
  printf 'RAN %s\n' "$n"
}

fails=0
report="$(battery "$LIB" 2>&1)"; ran=0
while IFS= read -r line; do
  case "$line" in FAILED*) fails=$((fails + 1)); printf '  FAIL %s\n' "${line#FAILED }" ;; RAN*) ran="${line#RAN }" ;; *) [[ -z "$line" ]] || printf '       %s\n' "$line" ;; esac
done <<<"$report"
printf '\nreal classifier: %s assertions, %s failed\n' "$ran" "$fails"
[[ "$ran" -ge 28 ]] || { echo "  FAIL assertion floor: ran ${ran} < 28"; fails=$((fails + 1)); }

mutate() { # <marker>
  local m="$1" copy="$TMP/cls.mut.sh" after
  cp "$LIB" "$copy"
  sed -i -E "s/^(\s*)[^#]*(# CLS:${m})\$/\1: \2/" "$copy"
  if cmp -s "$LIB" "$copy"; then echo "  FAIL mutation '${m}' did not change the classifier"; fails=$((fails + 1)); return; fi
  after="$(battery "$copy" 2>&1 | grep -c '^FAILED')"
  if [[ "$after" -gt 0 ]]; then echo "  ok   mutation killed: ${m} (${after} red)"; else echo "  FAIL mutation SURVIVED: ${m}"; fails=$((fails + 1)); fi
}
for m in PAUSE STATE-UNKNOWN REBORN PIN-SHAPE PIN-ELSEWHERE WEB2-OTHER DUP-NAME STATE-PIN DUP-NAME-GONE ORPHAN RM-ID RM-SERIAL RM-LINEAGE; do mutate "$m"; done

[[ "$fails" -eq 0 ]] && { echo "web2-rebirth-classify: all assertions and mutations passed"; exit 0; }
echo "web2-rebirth-classify: ${fails} FAILED"; exit 1
