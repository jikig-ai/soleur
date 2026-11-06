#!/usr/bin/env bash
# Relayed-verdict parser for follow-through probes (owner-knowledge acts; technical-ruling-delegation.md, section 9).
#
# THE PROPERTY. A marker probe whose act only the owner can complete cannot tell an agent's post from the owner's: both come from
# the owner's login and scripts/lib/trusted-verdict.sh checks permission only. So an agent never writes the owner's DONE marker. It
# posts a sibling `<MARKER>-RELAYED:` record after the owner's one in-session reply, in ONE comment, as plain unfenced lines:
#   S6-A6-RELAYED: 2026-11-25T09:30:00Z          the time of the post, a real UTC time ending in Z
#   relayed-by: agent
#   owner-words: «the owner's sentence, verbatim»  (guillemets or straight double quotes; not empty)
#   owner-reply-at: 2026-11-25T09:29:00Z         when the owner typed it; not later than the post, not in the future
#   run=39400431311                              only when the caller gives a verifier: the id of the artifact the record rests on
# This is a provenance record, not proof of the owner's words: the shape and the artifact are checked, the sentence is read by humans.
#
# THE BLOCK is the marker line plus the lines after it, up to the next marker line (`^RESULT:` or `^S<n>-<WORD>:`, the family the
# trusted-verdict candidate regex uses) or 8 non-blank lines; blank lines are skipped and do not count. A label that occurs twice in
# one block (relayed-by, owner-words, owner-reply-at, run) makes the block malformed: it is never last-wins. The marker is case-sensitive.
#
# Usage (the caller passes text already read through trusted_verdict_bodies, so fenced and HTML-commented blocks are gone):
#   state="$(relayed_verdict_state S6-A6-RELAYED "$bodies" "" "$now_e")"; rc=$?
#   state="$(relayed_verdict_state S5-A5-RELAYED "$bodies" my_verifier "$now_e")"; rc=$?
# <verifier> is a function name or empty. When given, a `run=<id>` line (id: 1 to 18 digits, no leading zero) is required and the
# verifier is called as `<verifier> <id> <owner-reply-epoch>`; it returns 0 = the artifact qualifies, 1 = it does not, 2 = the read
# failed or returned something unparseable. <now_e> is the epoch the caller treats as now (a test seam is the caller's business).
#   stdout  ok    some block is well-formed (and the artifact qualifies)
#           bad   a line starts with the marker but no block is well-formed
#           none  no line starts with the marker
#   rc 0 = answered; rc 1 = the scan itself failed; rc 4 = the verifier's read failed and no other block recorded the act (the
#   caller maps it to its CANNOT ESTABLISH exit: absence of evidence is not a refusal). rc 4 never prints a state.
# Several blocks: the first well-formed one wins, in comment order; a failed verifier read on an earlier block does not hide a
# later good one.
#
# SOURCED, never executed: no top-level `exit`, no `set -e`. Convention: followthrough-convention.md, "Relayed records".

# relayed_utc_epoch <ts>: prints the epoch of a full UTC time ending in Z; returns 1 for anything else (a typo is not a time).
relayed_utc_epoch() {
  local e
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(:[0-9]{2})?Z$ ]] || return 1
  e="$(date -u -d "$1" +%s 2>/dev/null)" && [[ "$e" =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$e"
}

# relayed_verdict_state <marker> <text> <verifier> <now_e>
relayed_verdict_state() {
  local name="$1" text="$2" verifier="$3" now_e="$4"
  local -a lines=()
  local i j n seen=0 okfound=0 readfail=0 look line relayed_e reply_e vrc
  local by words reply run n_by n_words n_reply n_run
  local mark_re='^(RESULT|S[0-9]+-[A-Z][A-Z0-9_-]*):'
  # the owner's sentence in guillemets or straight double quotes, with at least one non-space character inside
  local words_re='^owner-words: («.*[^[:space:]].*»|".*[^[:space:]].*")[[:space:]]*$'
  local head_re="^${name}: ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(:[0-9]{2})?Z)[[:space:]]*\$"
  [[ "$now_e" =~ ^[0-9]+$ ]] || return 1
  mapfile -t lines <<<"$text" || return 1
  n=${#lines[@]}
  for ((i = 0; i < n; i++)); do
    [[ "${lines[i]}" == "${name}:"* ]] || continue
    seen=1
    [[ "${lines[i]}" =~ $head_re ]] || continue
    relayed_e="$(relayed_utc_epoch "${BASH_REMATCH[1]}")" || continue
    by=""; words=""; reply=""; run=""; look=0; n_by=0; n_words=0; n_reply=0; n_run=0
    for ((j = i + 1; j < n && look < 8; j++)); do
      line="${lines[j]}"
      [[ "$line" =~ $mark_re ]] && break
      [[ "$line" =~ ^[[:space:]]*$ ]] && continue
      look=$((look + 1))
      if [[ "$line" == relayed-by:* ]]; then
        n_by=$((n_by + 1))
        [[ "$line" =~ ^relayed-by:\ agent[[:space:]]*$ ]] && by=agent
      elif [[ "$line" == owner-words:* ]]; then
        n_words=$((n_words + 1))
        [[ "$line" =~ $words_re ]] && words=ok
      elif [[ "$line" == owner-reply-at:* ]]; then
        n_reply=$((n_reply + 1))
        [[ "$line" =~ ^owner-reply-at:\ ([0-9TZ:-]+)[[:space:]]*$ ]] && reply="${BASH_REMATCH[1]}"
      elif [[ "$line" == run=* ]]; then
        n_run=$((n_run + 1))
        [[ "$line" =~ ^run=([1-9][0-9]{0,17})[[:space:]]*$ ]] && run="${BASH_REMATCH[1]}"
      fi
    done
    [ "$n_by" -le 1 ] || continue
    [ "$n_words" -le 1 ] || continue
    [ "$n_reply" -le 1 ] || continue
    [ "$n_run" -le 1 ] || continue
    [ "$by" = agent ] && [ "$words" = ok ] || continue
    reply_e="$(relayed_utc_epoch "$reply")" || continue
    [ "$reply_e" -le "$relayed_e" ] || continue
    [ "$reply_e" -le "$now_e" ] || continue
    if [ -n "$verifier" ]; then
      [ -n "$run" ] || continue
      "$verifier" "$run" "$reply_e"; vrc=$?
      if [ "$vrc" -eq 2 ]; then readfail=1; continue; fi
      [ "$vrc" -eq 0 ] || continue
    fi
    okfound=1; break
  done
  if [ "$okfound" -eq 1 ]; then printf 'ok\n'; return 0; fi
  if [ "$readfail" -eq 1 ]; then return 4; fi
  if [ "$seen" -eq 1 ]; then printf 'bad\n'; else printf 'none\n'; fi
  return 0
}
