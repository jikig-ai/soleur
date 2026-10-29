#!/usr/bin/env bash
# inngest-a5-a6-owner-ask-10136.sh -- NOTIFY-ONLY follow-through probe: asks the owner, in plain words, for the
# next open owner-human act of the Inngest TLS arc (#10136): A5 (the scheduler signing-key rotation) and then
# A6 (the "no known access" record). The A5 ask names the exact dispatch lines of the rotation route
# (.github/workflows/inngest-key-rotate.yml, ADR-307, #10540): the read-only plan rehearsal, the rotate line, and the converge line
# that finishes a failed run. Only the owner dispatches rotate and converge, each under a fresh in-session go naming the exact line;
# the route prints the S5-A5-DONE line and never posts it, and the owner posts it themselves on the epic (an agent-posted line,
# or one posted by the workflow, does not satisfy the record).
#
# EXIT CONTRACT. 0 and 1 are NEVER taken: this probe never closes its tracker and never performs an act (A5 and A6
# are owner-human: no agent runs them and no delegation covers them, runbook inngest-server.md, "Production Envelope
# for the post-merge acts"). It speaks the notify-only vocabulary of followthrough-convention.md:
#   2 NOT YET            nothing for the owner to do yet
#   3 CANNOT ESTABLISH   a read failed or returned something unparseable; never turned into an ask
#   5 ACTION REQUIRED    the owner has something to do (the sweeper repeats the comment on every daily sweep of an
#                        open tracker, so the ask repeats until the owner posts the done line)
# Under shell tracing with GH_TOKEN set it refuses with 78 (EX_CONFIG, also never 0 or 1). The suite asserts the never-0/1 invariant on every input. The owner ends the tracker by closing it AND removing
# its follow-through label.
#
# DECISION ORDER, first match wins. Any read that fails or returns something unparseable is exit 3, never an ask.
#   1. trusted S6-A6-DONE and S5-A5-DONE on the epic -> 2  both acts recorded; close this tracker
#      (S6 without S5 is an inconsistent record -> 3, never "both recorded")
#   2. no S5-A5-DONE, today >= 2026-11-09, and NOT (soak #11215 closed COMPLETED and route #10540 closed COMPLETED)
#                                                    -> 5  the legal bridge date is at risk; says which is missing
#      (placed before the soak rows on purpose: a stuck soak must not silence the warning)
#   3. trusted S5-A5-DONE on the epic                -> 5  ask for A6, with the 2026-12-10 lapse date and days left
#   4. soak tracker (#11215) open                    -> 2  waiting on the 48-hour check
#   5. soak tracker closed, not COMPLETED            -> 3  cannot establish
#   6. route (#10540) not closed COMPLETED           -> 2  A5 is blocked on the route
#   7. otherwise                                     -> 5  ask for A5 (names the dispatch lines and #10543: fixed, or a quiet window)
#
# THE ANCHORS live on the epic (#10136), not on this probe's tracker: the tracker's number does not exist when this
# file is written (the soak probe's header names the same trap). They are read through scripts/lib/trusted-verdict.sh,
# so only a comment by an author with write permission counts and a fenced or HTML-commented line does not. The owner
# posts, as plain unfenced lines on #10136 (the UTC time must be a full ISO time ending in Z):
#   S5-A5-DONE: 2026-11-20T14:00:00Z     after the signing-key rotation is complete
#   S6-A6-DONE: 2026-11-25T09:30:00Z     after the no-known-access record is filed and linked
# A line starting with a marker whose time is NOT a real UTC time in that format is named in every ask that is waiting
# for it (the dead-man warning, the A6 ask, the A5 ask), not silently ignored.
#
# DATES are constants derived from the legal bridge date 2026-11-12 (extendable once, to 2026-12-10): the dead-man
# is three days before it. If the bridge is extended or lapses, edit them here.
#
# OWNER_ASK_TODAY (YYYY-MM-DD) is a TEST SEAM for the date. It is inert in production: the sweeper runs this under
# `env -i` and the tracker directive declares only GH_TOKEN, so nothing can bind it.
#
# PUBLIC OUTPUT. The sweeper republishes this script's output in a public issue comment, so every line is authored
# plain words built from constants and computed integers: no login, host id, key name or credential. The suite greps
# for that. `state` and `stateReason` from gh are validated against a closed shape and only compared, never printed.
#
# CREDENTIAL POSTURE. The directive declares only GH_TOKEN (issue reads and the author-permission lookup).
#
# RETIREMENT. This probe dies when its tracker is closed after A6 is recorded. Delete with it:
#   scripts/followthroughs/inngest-a5-a6-owner-ask-10136.test.sh
#   the run_suite line for it in scripts/test-all.sh
#   the tracker pointers in the A5 and A6 rows of knowledge-base/engineering/operations/runbooks/inngest-server.md
# Re-census at retirement with: git grep -n 'inngest-a5-a6-owner-ask-10136'
set -uo pipefail

# Refuse to run under shell tracing while the credential is bound: xtrace would print GH_TOKEN into the sweeper's public
# comment (#7797). 78 (EX_CONFIG) lands in the sweeper's TRANSIENT bucket, never a pass or a close.
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

EPIC=10136
SOAK=11215
ROUTE=10540
REPLAY=10543
LINKED=10382
DEADMAN=2026-11-09
BRIDGE=2026-11-12
LAPSE=2026-12-10
REPO="jikig-ai/soleur"
# The exact dispatch lines of the rotation route (runbook inngest-server.md, "Key rotation"). The date in a confirm is the UTC date
# of the dispatch, so it is shown as a pattern. These are authored constants: nothing here is read from GitHub.
PLAN_LINE="gh workflow run inngest-key-rotate.yml -f mode=plan -f keys=signing -f reason='A5 rehearsal'"
ROTATE_LINE="gh workflow run inngest-key-rotate.yml -f mode=rotate -f keys=signing -f confirm=ROTATE-INNGEST-SIGNING-YYYY-MM-DD -f quiet_window=true -f reason='A5 (#10136)'"
CONVERGE_LINE="gh workflow run inngest-key-rotate.yml -f mode=converge -f keys=signing -f confirm=CONVERGE-INNGEST-SIGNING-YYYY-MM-DD -f quiet_window=true -f reason='converge after a failed A5 run'"

say() { printf '%s\n' "$*"; }

# issue_state <n>: sets ST (OPEN|CLOSED) and REASON (e.g. COMPLETED); returns 1 on a failed or unparseable read.
# ST and REASON are cleared first as defence in depth: every caller returns 3 on a failed read today, so a stale value is
# unreachable (the suite's header enumerates the callers), but a future caller must not inherit the previous issue.
issue_state() {
  local out
  ST=""; REASON=""
  out="$(gh issue view "$1" --repo "$REPO" --json state,stateReason --jq '.state+" "+(.stateReason // "")' 2>/dev/null)" || return 1
  [[ "$out" =~ ^(OPEN|CLOSED)[[:space:]]([A-Z_]*)$ ]] || return 1
  ST="${BASH_REMATCH[1]}"; REASON="${BASH_REMATCH[2]}"
  return 0
}
completed() { [[ "$ST" == CLOSED && "$REASON" == COMPLETED ]]; }

# anchor_state <name> <text>: prints ok (a well-formed done line), bad (a line starts with the marker but is not
# well-formed) or none. Returns 1 when grep itself fails (rc >= 2), which the caller turns into exit 3.
anchor_state() {
  local name="$1" text="$2" rc
  local re="^${name}: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(:[0-9]{2})?Z[[:space:]]*$" ts
  grep -Eq "$re" <<<"$text"; rc=$?
  if [ "$rc" -eq 0 ]; then
    # the shape matched; the time must also be a real time (2026-13-45T99:99:99Z is a typo, not a done line)
    ts="$(grep -E "$re" <<<"$text" | tail -n 1 | sed -E "s/^${name}: //; s/[[:space:]]+$//")"
    if date -u -d "$ts" +%s >/dev/null 2>&1; then say ok; else say bad; fi
    return 0
  fi
  [ "$rc" -eq 1 ] || return 1
  grep -Eq "^${name}:" <<<"$text"; rc=$?
  if [ "$rc" -eq 0 ]; then say bad; return 0; fi
  [ "$rc" -eq 1 ] || return 1
  say none
}

# The body runs in a subshell so an internal error (unbound variable, failed builtin) cannot leak exit 1.
main() {
  local need
  for need in gh jq grep date tr; do
    command -v "$need" >/dev/null 2>&1 || { say "CANNOT ESTABLISH: $need is not installed"; return 3; }
  done
  [ -n "${GH_TOKEN:-}" ] || { say "CANNOT ESTABLISH: GH_TOKEN is not set (the tracker directive must declare secrets=GH_TOKEN)"; return 3; }

  local today="${OWNER_ASK_TODAY:-$(date -u +%F)}"
  [[ "$today" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { say "CANNOT ESTABLISH: today's date is not YYYY-MM-DD"; return 3; }
  local today_e
  today_e="$(date -u -d "$today" +%s 2>/dev/null)" && [[ "$today_e" =~ ^[0-9]+$ ]] || { say "CANNOT ESTABLISH: today's date does not parse"; return 3; }
  # Dates are compared as epochs, never with [[ a < b ]] / [[ a > b ]]: a bare < or > reads as a redirect to scanners.
  local deadman_e bridge_e lapse_e
  deadman_e="$(date -u -d "$DEADMAN" +%s)"; bridge_e="$(date -u -d "$BRIDGE" +%s)"; lapse_e="$(date -u -d "$LAPSE" +%s)"

  local libdir
  libdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" 2>/dev/null && pwd)" || libdir=""
  [ -n "$libdir" ] || { say "CANNOT ESTABLISH: trusted-verdict lib directory unresolved"; return 3; }
  # shellcheck source=../lib/trusted-verdict.sh
  if ! source "$libdir/trusted-verdict.sh" || ! declare -F trusted_verdict_bodies >/dev/null; then
    say "CANNOT ESTABLISH: trusted-verdict lib unavailable"; return 3
  fi

  local bodies
  bodies="$(trusted_verdict_bodies "$EPIC" "$REPO")" \
    || { say "CANNOT ESTABLISH: could not read the owner's done lines on the epic (comment or permission read failed)"; return 3; }
  bodies="$(tr -d '\r' <<<"$bodies")" || { say "CANNOT ESTABLISH: could not normalise the owner's done lines"; return 3; }

  local a5 a6
  a5="$(anchor_state S5-A5-DONE "$bodies")" || { say "CANNOT ESTABLISH: could not scan the owner's done lines"; return 3; }
  a6="$(anchor_state S6-A6-DONE "$bodies")" || { say "CANNOT ESTABLISH: could not scan the owner's done lines"; return 3; }
  local fmt="YYYY-MM-DDTHH:MM:SSZ" bad_note=""
  [ "$a5" != bad ] || bad_note="A line starting with S5-A5-DONE: was found on #$EPIC but is not a real UTC time, so it was ignored. Use $fmt (the real time, ending in Z)."
  [ "$a6" != bad ] || bad_note="${bad_note:+$bad_note }A line starting with S6-A6-DONE: was found on #$EPIC but is not a real UTC time, so it was ignored. Use $fmt (the real time, ending in Z)."
  days() { if [ "$1" -eq 1 ]; then say "1 day"; else say "$1 days"; fi; }

  # 1. both acts recorded
  if [ "$a6" = ok ] && [ "$a5" = ok ]; then
    say "NOT YET: A5 and A6 are both recorded on #$EPIC. Close this tracker and remove its follow-through label."
    return 2
  fi
  if [ "$a6" = ok ] && [ "$a5" != ok ]; then
    say "CANNOT ESTABLISH: A6 is recorded on #$EPIC but A5 is not. A6 only follows A5. Post the S5-A5-DONE line ($fmt, the real time ending in Z) or correct the A6 line."
    return 3
  fi

  # 2. the bridge date is at risk, whatever state the soak is in
  if [ "$a5" != ok ] && [ "$today_e" -ge "$deadman_e" ]; then
    local soak_ok=0 route_ok=0 soak_msg="" route_msg=""
    issue_state "$SOAK" || { say "CANNOT ESTABLISH: could not read the soak tracker (#$SOAK)"; return 3; }
    if completed; then soak_ok=1
    elif [ "$ST" = OPEN ]; then soak_msg="The 48-hour check on the new link (#$SOAK) has not finished."
    else soak_msg="The 48-hour check on the new link (#$SOAK) was closed without a completed result."
    fi
    issue_state "$ROUTE" || { say "CANNOT ESTABLISH: could not read the rotation route tracker (#$ROUTE)"; return 3; }
    if completed; then route_ok=1; else route_msg="The route work for the key rotation (#$ROUTE) is not done."; fi
    if [ "$soak_ok" -eq 0 ] || [ "$route_ok" -eq 0 ]; then
      say "ACTION REQUIRED: the signing-key rotation (A5) cannot start yet and the legal bridge date is close."
      [ -z "$soak_msg" ] || say "$soak_msg"
      [ -z "$route_msg" ] || say "$route_msg"
      if [ "$today_e" -gt "$lapse_e" ]; then
        say "The extended date of $LAPSE has also passed."
      elif [ "$today_e" -gt "$bridge_e" ]; then
        say "The legal bridge date of $BRIDGE has passed. It can be extended once, to $LAPSE, only with the TLS change merged and a dated go."
      else
        say "The legal bridge ends $BRIDGE (it can be extended once, to $LAPSE)."
      fi
      say "Ways out: finish what is missing above, then give your go for A5 in a session."
      say "Or, once the 48-hour check has passed, the rotation route may already be usable before #$ROUTE closes: its read-only rehearsal can be run any time ($PLAN_LINE), and the rotation itself needs your go."
      [ -z "$bad_note" ] || say "$bad_note"
      return 5
    fi
  fi

  # 3. A5 recorded: ask for A6
  if [ "$a5" = ok ]; then
    local left=$(( ( lapse_e - today_e ) / 86400 ))
    say "ACTION REQUIRED: A5 is recorded. Next is A6, the no-known-access record."
    say "Write it in the legal audits folder of the knowledge base and link it from #$LINKED and #$EPIC. The legal reviewer attests it separately."
    say "It needs the measured firewall-rule re-read from the host and the read-only list of Hetzner members on the private network."
    if [ "$left" -lt 0 ]; then
      say "The Inngest accepted-risk entry lapsed on $LAPSE ($(days "$(( -left ))") ago)."
    elif [ "$today_e" -gt "$bridge_e" ]; then
      say "If the bridge was extended, the Inngest accepted-risk entry lapses $LAPSE ($(days "$left") left)."
    else
      say "The Inngest accepted-risk entry lapses $LAPSE ($(days "$left") left)."
    fi
    say "When it is filed, post this line on #$EPIC, with the real UTC time: S6-A6-DONE: $fmt"
    [ -z "$bad_note" ] || say "$bad_note"
    return 5
  fi

  # 4. and 5. the soak
  issue_state "$SOAK" || { say "CANNOT ESTABLISH: could not read the soak tracker (#$SOAK)"; return 3; }
  if [ "$ST" = OPEN ]; then
    say "NOT YET: waiting on the 48-hour check on the new link (#$SOAK is open)."
    return 2
  fi
  if [ "$REASON" != COMPLETED ]; then
    say "CANNOT ESTABLISH: the 48-hour check tracker (#$SOAK) was closed without a completed result. Reopen it, and close it as completed once the check has passed."
    return 3
  fi

  # 6. the route
  issue_state "$ROUTE" || { say "CANNOT ESTABLISH: could not read the rotation route tracker (#$ROUTE)"; return 3; }
  if ! completed; then
    say "NOT YET: A5 is blocked on #$ROUTE (the rotation route is not done)."
    return 2
  fi

  # 7. ask for A5
  issue_state "$REPLAY" || { say "CANNOT ESTABLISH: could not read the dashboard-send defect tracker (#$REPLAY)"; return 3; }
  say "ACTION REQUIRED: A5 is ready. It replaces the scheduler's signing key on both the Inngest host and the web app, restarts the Inngest host with a reboot, and then redeploys web."
  if completed; then
    say "The dashboard-send defect (#$REPLAY) is fixed."
  else
    say "The dashboard-send defect (#$REPLAY) is not fixed: run A5 in a quiet window with no sends in flight, and check for lost sends afterwards."
  fi
  if [ "$today_e" -ge "$deadman_e" ]; then
    say "The legal bridge date is $BRIDGE (it can be extended once, to $LAPSE), so this is time-sensitive."
  fi
  [ -z "$bad_note" ] || say "$bad_note"
  say "The rotation is one dispatch of the rotation workflow, and only you dispatch it. It needs your go in a session that names the exact line. A go on another issue does not count, and no agent runs it."
  say "Rehearsal (read-only, any session may run it): $PLAN_LINE"
  say "Rotation (your go must name this line; the date is the UTC date of the dispatch; use keys=both only if you also want the event key rotated in the same window): $ROTATE_LINE"
  say "If a run fails after it started writing, do not retry the rotation. Finish it with this line, which needs its own go from you: $CONVERGE_LINE"
  say "Your go should also say, in plain words, that the Inngest host is down for a few minutes during the reboot and one scheduled tick inside that gap may be skipped, and that the new key is live on the host a little before web catches up."
  say "When the rotation run is green it prints a line S5-A5-DONE: followed by the real UTC time. Post that line yourself as a comment on #$EPIC, with the run's evidence block. The workflow never posts it, and a line posted by an agent or by the workflow does not count. The line looks like this: S5-A5-DONE: $fmt"
  return 5
}

( main )
rc=$?
case "$rc" in
  2|3|5) exit "$rc" ;;
  *) say "CANNOT ESTABLISH: probe internal error (rc=$rc)"; exit 3 ;;
esac
