#!/usr/bin/env bash
# inngest-a5-a6-owner-ask-10136.sh -- NOTIFY-ONLY follow-through probe: asks the owner, in plain words, for the
# next open owner-human act of the Inngest TLS arc (#10136): A5 (the scheduler signing-key rotation) and then
# A6 (the "no known access" record).
#
# WHAT IT NEVER DOES. It never closes its tracker and never performs an act. A5 and A6 are owner-human: no agent
# runs them and no delegation covers them (runbook inngest-server.md, "Production Envelope for the post-merge
# acts"). So this probe NEVER exits 0 (the close verb) or 1 (FAIL); the suite asserts that on every input. It
# speaks the notify-only vocabulary of followthrough-convention.md: 2 NOT YET, 3 CANNOT ESTABLISH, 5 ACTION REQUIRED.
# On an open tracker the sweeper repeats an exit-5 comment on every daily sweep, so the ask repeats until the
# owner posts the done line. The owner ends the tracker by closing it AND removing its follow-through label.
#
# DECISION ORDER, first match wins. Any read that fails or returns something unparseable is exit 3, never an ask.
#   1. trusted S6-A6-DONE on the epic          -> 2  both acts recorded; close this tracker
#   2. no S5-A5-DONE, today >= 2026-11-09, and the rotation route (#10540) not closed COMPLETED
#                                              -> 5  the legal bridge date is at risk (before the soak rows on purpose)
#   3. trusted S5-A5-DONE on the epic          -> 5  ask for A6, with the 2026-12-10 lapse date and the days left
#   4. soak tracker (#11215) open              -> 2  waiting on the soak
#   5. soak tracker closed, not COMPLETED      -> 3  cannot establish
#   6. route (#10540) not closed COMPLETED     -> 2  A5 is blocked on the route
#   7. otherwise                               -> 5  ask for A5 (names #10543: fixed, or a quiesced window)
#
# THE ANCHORS live on the epic (#10136), not on this probe's tracker: the tracker's number does not exist when
# this file is written (the soak probe's header names the same trap). They are read through
# scripts/lib/trusted-verdict.sh, so only a comment by an author with write permission counts and a fenced or
# HTML-commented line does not. The owner posts, as plain unfenced lines on #10136:
#   S5-A5-DONE: <UTC ISO>     after the signing-key rotation is complete
#   S6-A6-DONE: <UTC ISO>     after the no-known-access record is filed and linked
#
# DATES are constants derived from the legal bridge date 2026-11-12 (extendable once, to 2026-12-10): the dead-man
# is three days before it. If the bridge is extended or lapses, edit them here.
#
# PUBLIC OUTPUT. The sweeper republishes this script's output in a public issue comment, so every line is authored
# plain words: no login, host id, key name or legal-internal text. The suite greps for that.
#
# CREDENTIAL POSTURE. The directive declares only GH_TOKEN (issue reads and the permission lookup). No other secret.
#
# RETIREMENT. This probe dies when its tracker is closed after A6 is recorded. Delete with it:
#   scripts/followthroughs/inngest-a5-a6-owner-ask-10136.test.sh
#   the run_suite line for it in scripts/test-all.sh
#   the A5 and A6 rows' tracker pointers in knowledge-base/engineering/operations/runbooks/inngest-server.md
# Re-census at retirement with: git grep -n 'inngest-a5-a6-owner-ask-10136'
set -uo pipefail

EPIC=10136
SOAK=11215
ROUTE=10540
REPLAY=10543
DEADMAN=2026-11-09
BRIDGE=2026-11-12
LAPSE=2026-12-10
REPO="jikig-ai/soleur"

say() { printf '%s\n' "$*"; }

# The body runs in a subshell so an internal error (unbound variable, failed builtin) cannot leak exit 1.
main() {
  local need
  for need in gh jq grep date tr; do
    command -v "$need" >/dev/null 2>&1 || { say "CANNOT ESTABLISH: $need is not installed"; return 3; }
  done
  [ -n "${GH_TOKEN:-}" ] || { say "CANNOT ESTABLISH: GH_TOKEN is not set (the tracker directive must declare secrets=GH_TOKEN)"; return 3; }

  local today="${OWNER_ASK_TODAY:-$(date -u +%F)}"
  [[ "$today" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { say "CANNOT ESTABLISH: today's date is not YYYY-MM-DD"; return 3; }
  date -u -d "$today" +%s >/dev/null 2>&1 || { say "CANNOT ESTABLISH: today's date does not parse"; return 3; }

  # shellcheck source=../lib/trusted-verdict.sh
  if ! source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" 2>/dev/null && pwd)/trusted-verdict.sh" \
     || ! declare -F trusted_verdict_bodies >/dev/null; then
    say "CANNOT ESTABLISH: trusted-verdict lib unavailable"; return 3
  fi

  local bodies
  bodies="$(trusted_verdict_bodies "$EPIC" "$REPO")" \
    || { say "CANNOT ESTABLISH: could not read the owner's done lines on the epic (comment or permission read failed)"; return 3; }

  local a5=0 a6=0
  grep -Eq '^S5-A5-DONE: [0-9]{4}-[0-9]{2}-[0-9]{2}T' <<<"$bodies" && a5=1
  grep -Eq '^S6-A6-DONE: [0-9]{4}-[0-9]{2}-[0-9]{2}T' <<<"$bodies" && a6=1

  # issue_state <n>: sets ST (OPEN|CLOSED) and REASON (e.g. COMPLETED); returns 1 on a failed or unparseable read.
  issue_state() {
    local out
    out="$(gh issue view "$1" --repo "$REPO" --json state,stateReason --jq '.state+" "+(.stateReason // "")' 2>/dev/null)" || return 1
    [[ "$out" =~ ^(OPEN|CLOSED)[[:space:]]([A-Z_]*)$ ]] || return 1
    ST="${BASH_REMATCH[1]}"; REASON="${BASH_REMATCH[2]}"
    return 0
  }
  route_landed() { [[ "$ST" == CLOSED && "$REASON" == COMPLETED ]]; }

  # 1. both acts recorded
  if [ "$a6" -eq 1 ]; then
    say "NOT YET: A5 and A6 are both recorded on #$EPIC. Close this tracker and remove its follow-through label."
    return 2
  fi

  # 2. the bridge date is at risk, whatever state the soak is in
  if [ "$a5" -eq 0 ] && [[ ! "$today" < "$DEADMAN" ]]; then
    issue_state "$ROUTE" || { say "CANNOT ESTABLISH: could not read the rotation route tracker (#$ROUTE)"; return 3; }
    if ! route_landed; then
      say "ACTION REQUIRED: the signing-key rotation has no dated route. The route work (#$ROUTE) is not done."
      if [[ "$today" > "$BRIDGE" ]]; then
        say "The legal bridge date of $BRIDGE has passed. It can be extended once, to $LAPSE, only with the TLS change merged and a dated go."
      else
        say "The legal bridge ends $BRIDGE (it can be extended once, to $LAPSE)."
      fi
      say "Two ways out: schedule #$ROUTE, or run the manual key rotation procedure from the runbook with your go."
      return 5
    fi
  fi

  # 3. A5 recorded: ask for A6
  if [ "$a5" -eq 1 ]; then
    local left=$(( ( $(date -u -d "$LAPSE" +%s) - $(date -u -d "$today" +%s) ) / 86400 ))
    say "ACTION REQUIRED: A5 is recorded. Next is A6, the no-known-access record."
    say "Write it under knowledge-base/legal/audits/ and link it from #10382 and #$EPIC. The legal reviewer attests it separately."
    say "It needs the measured firewall-rule re-read from the host and the read-only list of servers on the private network."
    say "The Inngest row lapses $LAPSE ($left days left)."
    say "When it is filed, post this line on #$EPIC: S6-A6-DONE: <UTC time>"
    return 5
  fi

  # 4. and 5. the soak
  issue_state "$SOAK" || { say "CANNOT ESTABLISH: could not read the soak tracker (#$SOAK)"; return 3; }
  if [ "$ST" = OPEN ]; then
    say "NOT YET: waiting on the soak (#$SOAK is open)."
    return 2
  fi
  if [ "$REASON" != COMPLETED ]; then
    say "CANNOT ESTABLISH: the soak tracker (#$SOAK) was closed without a completed result. Reopen it, or post the soak result on #$EPIC."
    return 3
  fi

  # 6. the route
  issue_state "$ROUTE" || { say "CANNOT ESTABLISH: could not read the rotation route tracker (#$ROUTE)"; return 3; }
  if ! route_landed; then
    say "NOT YET: A5 is blocked on #$ROUTE (the rotation route is not done)."
    return 2
  fi

  # 7. ask for A5
  issue_state "$REPLAY" || { say "CANNOT ESTABLISH: could not read the dashboard-send defect tracker (#$REPLAY)"; return 3; }
  say "ACTION REQUIRED: A5 is ready. It replaces the scheduler's signing key on both the Inngest host and the web app, then restarts the server and redeploys web."
  if [ "$ST" = CLOSED ] && [ "$REASON" = COMPLETED ]; then
    say "The dashboard-send defect (#$REPLAY) is fixed."
  else
    say "The dashboard-send defect (#$REPLAY) is still open: run it in a quiesced window and check for lost sends afterwards."
  fi
  say "Reply with your go for A5, naming the rotation. When it is done, post this line on #$EPIC: S5-A5-DONE: <UTC time>"
  return 5
}

( main )
rc=$?
case "$rc" in
  2|3|5) exit "$rc" ;;
  *) say "CANNOT ESTABLISH: probe internal error (rc=$rc)"; exit 3 ;;
esac
