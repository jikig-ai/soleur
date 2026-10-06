# shellcheck shell=bash
# Pure state classifier for the single-use web-2 volume rebirth (#9372, ADR-263 addendum).
#
# It maps what Hetzner and Terraform state say RIGHT NOW to exactly one verdict, before any write:
#
#   proceed                    the first dispatch: the pinned plaintext volume is attached to web-2 and in state
#   heal:detach_done           the volume was detached last time; continue at DELETE
#   heal:delete_done           the volume is gone (404) and state still holds it; continue at `state rm`
#   heal:state_rm_done         state is clean and the old server still exists; continue at the `post` plan
#   heal:apply_midway          the volume and the server are both gone; the `post` plan creates both
#   heal:volume_created        the raw volume exists (in state) and is not yet attached; use mode post-heal
#   resume:post_apply          the rebirth already ran (state holds the new volume, the ONLY volume attached to web-2, the pin gone,
#                              server younger than 72 h): nothing is replaced; a plan that may only ADD what a partly failed apply left
#                              missing, then the readiness poll, the recovery check and the reboot run
#   refuse:<reason>            nothing is written; the reason names the state this workflow cannot heal
#
# Inputs are plain key=value words so the classifier is testable without Hetzner or Terraform. A missing,
# unknown or malformed key REFUSES (fail closed): "I could not read it" is never a verdict.
#
#   apply=yes|no                 a destructive run (plan_only=false)
#   pause=yes|no                 the push-apply pause assertion passed (only consulted when apply=yes)
#   pin=<volume id>              the pinned plaintext volume
#   pin_status=present|absent    Hetzner GET of the pinned id (absent = 404)
#   pin_format=ext4|none|other   the pinned volume's filesystem as Hetzner reports it (when present)
#   pin_name_ok=yes|no           name and labels match the live web-2 volume (when present)
#   pin_server=<server id>|none  the server the pinned volume is attached to (when present)
#   names=<id,id>|none           ids of every volume named soleur-web-platform-data-web-2
#   web2_sid=<server id>         web-2's server id as captured from Hetzner
#   web2_vols=<id,id>|none|server_absent   volume ids attached to web-2
#   web2_age_s=<n>|none          age of web-2's Hetzner server in seconds (none = unknown or absent)
#   state_vol=<id>|none          the id Terraform state holds for hcloud_volume.workspaces["web-2"]
#   state_server=present|absent  hcloud_server.web["web-2"] is in state

web2_rebirth_classify() {
  local apply="" pause="" pin="" pin_status="" pin_format="" pin_name_ok="" pin_server="" names="" web2_sid=""
  local web2_vols="" state_vol="" state_server="" web2_age="" kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    case "$k" in
      apply) apply="$v" ;; pause) pause="$v" ;; pin) pin="$v" ;; pin_status) pin_status="$v" ;;
      pin_format) pin_format="$v" ;; pin_name_ok) pin_name_ok="$v" ;; pin_server) pin_server="$v" ;;
      names) names="$v" ;; web2_sid) web2_sid="$v" ;; web2_vols) web2_vols="$v" ;;
      state_vol) state_vol="$v" ;; state_server) state_server="$v" ;; web2_age_s) web2_age="$v" ;;
      *) echo "refuse:bad_input_unknown_key_${k}"; return 0 ;;
    esac
  done
  [[ "$apply" =~ ^(yes|no)$ && "$pin" =~ ^[0-9]+$ && "$web2_sid" =~ ^[0-9]+$ ]] || { echo "refuse:bad_input"; return 0; }
  [[ "$pin_status" =~ ^(present|absent)$ && "$state_server" =~ ^(present|absent)$ ]] || { echo "refuse:bad_input"; return 0; }
  [[ "$state_vol" =~ ^([0-9]+|none)$ && "$names" =~ ^([0-9]+(,[0-9]+)*|none)$ ]] || { echo "refuse:bad_input"; return 0; }
  [[ "$web2_vols" =~ ^([0-9]+(,[0-9]+)*|none|server_absent)$ ]] || { echo "refuse:bad_input"; return 0; }
  [[ "$web2_age" =~ ^([0-9]{1,12}|none)$ ]] || { echo "refuse:bad_input"; return 0; }
  if [[ "$pin_status" == "present" ]]; then
    [[ "$pin_format" =~ ^(ext4|none|other)$ && "$pin_name_ok" =~ ^(yes|no)$ && "$pin_server" =~ ^([0-9]+|none)$ ]] || { echo "refuse:bad_input"; return 0; }
  fi

  local -a name_ids=() w2_ids=()
  [[ "$names" == "none" ]] || IFS=, read -r -a name_ids <<<"$names"
  [[ "$web2_vols" == "none" || "$web2_vols" == "server_absent" ]] || IFS=, read -r -a w2_ids <<<"$web2_vols"
  local id x foreign in_names other_names=0 other_attached=0 pin_listed=0
  for id in "${name_ids[@]}"; do
    if [[ "$id" == "$pin" ]]; then pin_listed=1; else other_names=$((other_names + 1)); fi
  done
  for id in "${w2_ids[@]}"; do [[ "$id" == "$pin" ]] || other_attached=$((other_attached + 1)); done

  [[ "$apply" == "yes" && "$pause" != "yes" ]] && { echo "refuse:push_apply_pause_not_real"; return 0; }          # CLS:PAUSE

  # A server Hetzner knows that state does not hold cannot be healed by any window below: the post plan would try to create a
  # second server with the same name. Refuse; a person decides (the runbook names the remedy).
  [[ "$state_server" == "absent" && "$web2_vols" != "server_absent" ]] && { echo "refuse:orphan_server"; return 0; }   # CLS:ORPHAN-SERVER

  # Single use: a volume other than the pin is already in state and attached to web-2.
  if [[ "$state_vol" != "none" && "$state_vol" != "$pin" ]]; then
    in_names=0; for id in "${name_ids[@]}"; do [[ "$id" == "$state_vol" ]] && in_names=1; done
    [[ "$in_names" -eq 0 ]] && { echo "refuse:state_volume_unknown_to_hetzner"; return 0; }                          # CLS:STATE-UNKNOWN
    for id in "${w2_ids[@]}"; do
      if [[ "$id" == "$state_vol" ]]; then
        # Resume is only offered for a settled rebirth: the pinned plaintext volume is GONE and the new volume is the ONLY volume web-2 holds.
        [[ "$pin_status" != "absent" ]] && { echo "refuse:state_does_not_hold_the_pinned_volume"; return 0; }                # CLS:RESUME-PIN
        foreign=0; for x in "${w2_ids[@]}"; do [[ "$x" == "$state_vol" ]] || foreign=1; done
        [[ "$foreign" -eq 1 ]] && { echo "refuse:web2_holds_another_volume"; return 0; }                                      # CLS:RESUME-FOREIGN
        # Single use: a LATER dispatch must not touch a host that may hold data. Within 72 h of the rebirth only the resume path
        # (a plan that may only ADD what a partly failed apply left missing, then readiness, recovery check, reboot) is offered; an
        # unknown age fails closed. The workflow additionally requires the soak marker to be absent.
        if [[ "$web2_age" =~ ^[0-9]+$ && "$web2_age" -le 259200 ]]; then echo "resume:post_apply"; else echo "refuse:already_reborn"; fi   # CLS:REBORN
        return 0
      fi
    done
  fi

  if [[ "$pin_status" == "present" ]]; then
    [[ "$pin_format" != "ext4" || "$pin_name_ok" != "yes" ]] && { echo "refuse:pinned_volume_not_the_empty_plaintext_one"; return 0; }  # CLS:PIN-SHAPE
    [[ "$pin_server" != "none" && "$pin_server" != "$web2_sid" ]] && { echo "refuse:pinned_volume_attached_elsewhere"; return 0; }    # CLS:PIN-ELSEWHERE
    [[ "$other_attached" -gt 0 ]] && { echo "refuse:web2_holds_another_volume"; return 0; }                                           # CLS:WEB2-OTHER
    [[ "$other_names" -gt 0 ]] && { echo "refuse:duplicate_volume_name"; return 0; }                                                  # CLS:DUP-NAME
    [[ "$state_vol" != "$pin" ]] && { echo "refuse:state_does_not_hold_the_pinned_volume"; return 0; }                                # CLS:STATE-PIN
    if [[ "$pin_server" == "none" ]]; then echo "heal:detach_done"; else echo "proceed"; fi
    return 0
  fi

  # The pinned id is gone (404).
  local n_names="${#name_ids[@]}" n_attached="${#w2_ids[@]}"
  [[ "$pin_listed" -eq 1 ]] && { echo "refuse:inconsistent_pin_listing"; return 0; }                                              # CLS:INCONSISTENT
  # No window below expects ANY volume attached to web-2 (the REBORN case above already returned): a volume there would be
  # detached by the server replace.
  [[ "$n_attached" -gt 0 ]] && { echo "refuse:web2_holds_another_volume"; return 0; }                                               # CLS:FOREIGN-GONE
  [[ "$n_names" -gt 1 ]] && { echo "refuse:duplicate_volume_name"; return 0; }                                                 # CLS:DUP-NAME-GONE
  if [[ "$n_names" -eq 0 ]]; then
    if [[ "$state_vol" == "$pin" ]]; then echo "heal:delete_done"; return 0; fi
    if [[ "$state_vol" == "none" ]]; then
      if [[ "$state_server" == "present" ]]; then echo "heal:state_rm_done"; else echo "heal:apply_midway"; fi
      return 0
    fi
    echo "refuse:state_volume_unknown_to_hetzner"; return 0
  fi
  # Exactly one volume carries the name and it is not the pin.
  if [[ "$state_vol" == "none" ]]; then echo "refuse:orphan_raw_volume"; return 0; fi                                               # CLS:ORPHAN
  if [[ "$state_vol" == "${name_ids[0]}" ]]; then echo "heal:volume_created"; return 0; fi
  # Unreachable by construction (state's volume was proven to be among the names, and exactly one id carries the name, so it IS
  # name_ids[0]); kept as the fail-closed default so a future edit to the rules above cannot fall through to a verdict.
  echo "refuse:state_volume_mismatch"
}

# web2_rebirth_state_rm_check <pin> <state_id_before> <serial_before> <lineage_before> <serial_after> <lineage_after>
# The `terraform state rm` of the volume (and its attachment) is one state write: the address held the pinned id,
# the serial moved by exactly one, and the lineage did not change. Prints the reason and returns 1 otherwise.
web2_rebirth_state_rm_check() {
  local pin="$1" id_before="$2" s0="$3" l0="$4" s1="$5" l1="$6"
  [[ "$pin" =~ ^[0-9]+$ && "$s0" =~ ^[0-9]+$ && "$s1" =~ ^[0-9]+$ && -n "$l0" && -n "$l1" ]] || { echo "state-rm-check: unreadable inputs"; return 1; }
  [[ "$id_before" == "$pin" ]] || { echo "state-rm-check: the state address held id ${id_before}, not the pinned ${pin}"; return 1; }   # CLS:RM-ID
  [[ "$s1" -eq $((s0 + 1)) ]] || { echo "state-rm-check: serial moved ${s0} -> ${s1} (expected +1)"; return 1; }                          # CLS:RM-SERIAL
  [[ "$l0" == "$l1" ]] || { echo "state-rm-check: lineage changed"; return 1; }                                                          # CLS:RM-LINEAGE
  return 0
}
