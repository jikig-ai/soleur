#!/usr/bin/env bash
# health-colo-capture-12846.sh -- follow-through probe for the tracker "Capture the per-colo H read before the old zone is
# deleted (deadline 2026-11-24)" (Ref #12846, CTO Q10).
#
# WHAT IT PROVES. Only the old Cloudflare zone holds the flip-window hours, and it may be deleted from about 2026-11-25.
# After the change that adds the `analytics-health-colo` read to plugins/soleur/scripts/cloudflare-readonly.sh merges, the
# H handoff loop must be run once against the old zone and its kept evidence files pushed on a branch (runbook
# knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md, addendum 2026-11-19, "Deadline"). This probe
# proves that the capture was RECORDED: a comment on #12846 by an author with write permission holding an unfenced line
#   S1-HEALTHCOLO-CAPTURED: YYYY-MM-DDTHH:MM:SSZ <the kept file names and the branch>
# whose time is a real UTC time. It does not prove the capture itself (the files, the zone, the window): that is the
# runbook's keep predicate, run by the loop. It nags daily until the line exists. The verdict on the data has no deadline
# and is not this probe's concern.
#
# THE MARKER is read through scripts/lib/trusted-verdict.sh (`trusted_verdict_bodies 12846`), never by a direct comment
# read: only an author holding admin, maintain or write counts, and a line inside a fenced block or an HTML comment does
# not count (the lib strips both). `S1-HEALTHCOLO-CAPTURED:` is in the lib's candidate family `S[0-9]+-[A-Z][A-Z0-9_-]*:`.
# The time must match YYYY-MM-DDTHH:MM:SSZ, parse with `date -u -d`, and print back identically (so 24:00:00 or Feb 30 is
# not a time). A marker line whose time fails is no capture, and the ask says so without echoing the line.
#
# EXIT CONTRACT. 1 is NEVER taken (this probe has no "should not close" regression to report).
#   0 PASS               a trusted S1-HEALTHCOLO-CAPTURED: line with a real UTC time exists -> the sweeper closes the tracker
#   3 CANNOT ESTABLISH   gh, jq, grep, date or tr missing; GH_TOKEN unset; the lib unavailable; the lib's rc 2 (a failed
#                        comment or permission read, the lib header's rc 2 list); an unparseable clock; any internal error
#   5 ACTION REQUIRED    no qualifying line. Before 2026-11-25T00:00:00Z the ask is to run the loop before 2026-11-24; from
#                        then on it is to record the runbook's fallback `Unverified:` line on #12846 and close the tracker
# Under shell tracing with GH_TOKEN set it refuses with 78 (EX_CONFIG). The body returns an internal code for PASS (10), so a
# stray `exit 0` from anything the body runs or sources lands on the internal-error arm (3), never on a close.
#
# HEALTHCOLO_CAPTURE_NOW (YYYY-MM-DDTHH:MM:SSZ) is a TEST SEAM for the clock. It is inert in production: the sweeper runs
# this under `env -i` and the tracker directive declares only GH_TOKEN, so nothing can bind it.
#
# PUBLIC OUTPUT. The sweeper republishes stdout in a public comment, so every line is authored text built from constants:
# no login, no comment text, no matched line.
#
# CREDENTIAL POSTURE. GH_TOKEN only, used read-only: the comment read of #12846 and the lib's author-permission lookups.
# Directive: secrets=GH_TOKEN.
#
# RETIREMENT. This probe dies when its tracker closes (on PASS, or by hand after the fallback line). Delete together:
#   scripts/followthroughs/health-colo-capture-12846.sh (this file)
#   scripts/followthroughs/health-colo-capture-12846.test.sh
#   the run_suite line for scripts/health-colo-capture-12846 in scripts/test-all.sh
#   its rows in scripts/suite-shard-legs.tsv and scripts/suite-durations.tsv (regenerate with --incremental --write)
#   no scripts/lib/test-affected-paths.sh entry (none declared: the edge is derived from the file names)
#   the tracker's soleur:followthrough directive and its follow-through label
#   the probe's name in the 2026-11-19 addendum's "Deadline" paragraph of origin-tls-strict-flip.md
# Re-census at retirement with: git grep -n 'health-colo-capture-12846'
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md
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

ISSUE=12846
REPO="jikig-ai/soleur"
MARKER="S1-HEALTHCOLO-CAPTURED"
DEADLINE="2026-11-25T00:00:00Z"
RUNBOOK="knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md"
CAPTURED=10

say() { printf '%s\n' "$*"; }

# real_utc <ts>: rc 0 when <ts> (already shape-checked) is a real UTC time that prints back identically.
real_utc() {
  local e back
  e="$(date -u -d "$1" +%s 2>/dev/null)" && [[ "$e" =~ ^[0-9]+$ ]] || return 1
  back="$(date -u -d "@$e" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || return 1
  [ "$back" = "$1" ]
}

# The body runs in a subshell so an internal error (unbound variable, failed builtin, a sourced exit) cannot leak 0 or 1.
main() {
  local need
  for need in gh jq grep date tr; do
    command -v "$need" >/dev/null 2>&1 || { say "CANNOT ESTABLISH: $need is not installed"; return 3; }
  done
  [ -n "${GH_TOKEN:-}" ] || { say "CANNOT ESTABLISH: GH_TOKEN is not set (the tracker directive must declare secrets=GH_TOKEN)"; return 3; }

  local now_e deadline_e
  if [ -n "${HEALTHCOLO_CAPTURE_NOW:-}" ]; then
    [[ "$HEALTHCOLO_CAPTURE_NOW" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
      || { say "CANNOT ESTABLISH: the clock override is not YYYY-MM-DDTHH:MM:SSZ"; return 3; }
    real_utc "$HEALTHCOLO_CAPTURE_NOW" || { say "CANNOT ESTABLISH: the clock override is not a real UTC time"; return 3; }
    now_e="$(date -u -d "$HEALTHCOLO_CAPTURE_NOW" +%s 2>/dev/null)"
  else
    now_e="$(date -u +%s 2>/dev/null)"
  fi
  [[ "$now_e" =~ ^[0-9]+$ ]] || { say "CANNOT ESTABLISH: the current time does not parse"; return 3; }
  # Dates are compared as epochs, never with [[ a < b ]]: a bare < or > reads as a redirect to scanners.
  deadline_e="$(date -u -d "$DEADLINE" +%s 2>/dev/null)" && [[ "$deadline_e" =~ ^[0-9]+$ ]] \
    || { say "CANNOT ESTABLISH: the deadline constant does not parse"; return 3; }

  local libdir
  libdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" 2>/dev/null && pwd)" || libdir=""
  [ -n "$libdir" ] || { say "CANNOT ESTABLISH: trusted-verdict lib directory unresolved"; return 3; }
  # shellcheck source=../lib/trusted-verdict.sh
  if ! source "$libdir/trusted-verdict.sh" || ! declare -F trusted_verdict_bodies >/dev/null; then
    say "CANNOT ESTABLISH: trusted-verdict lib unavailable"; return 3
  fi

  local bodies
  bodies="$(trusted_verdict_bodies "$ISSUE" "$REPO")" || { say "CANNOT ESTABLISH: could not read the trusted comments on #$ISSUE (comment or permission read failed)"; return 3; }
  bodies="$(tr -d '\r' <<<"$bodies")" || { say "CANNOT ESTABLISH: could not normalise the comments on #$ISSUE"; return 3; }

  # grep rc 0 = marker lines, 1 = none (an answer), anything else = the grep failed (never read as "none")
  local lines rc
  lines="$(grep -E "^${MARKER}:" <<<"$bodies")"; rc=$?
  [ "$rc" -le 1 ] || { say "CANNOT ESTABLISH: could not scan the comments on #$ISSUE"; return 3; }

  local captured=0 bad=0 line ts
  if [ "$rc" -eq 0 ]; then
    while IFS= read -r line; do
      if [[ "$line" =~ ^${MARKER}:\ ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)([[:space:]].*)?$ ]]; then
        ts="${BASH_REMATCH[1]}"
      else
        bad=1; continue
      fi
      real_utc "$ts" || { bad=1; continue; }
      captured=1
    done <<<"$lines"
  fi

  if [ "$captured" -eq 1 ]; then
    say "PASS: the per-colo H capture is recorded on #$ISSUE (a trusted $MARKER: line with a real UTC time)."
    return "$CAPTURED"
  fi

  if [ "$now_e" -lt "$deadline_e" ]; then
    say "ACTION REQUIRED: run the H handoff loop now (runbook $RUNBOOK, addendum 2026-11-19) before 2026-11-24, then post the $MARKER: line on #$ISSUE"
    say "The line goes first in an unfenced comment on #$ISSUE by an author with write permission: $MARKER: followed by the read instant as YYYY-MM-DDTHH:MM:SSZ, then the kept file names and the branch."
  else
    say "ACTION REQUIRED: deadline passed without a capture: record the runbook's fallback Unverified: line on #$ISSUE and close this tracker"
    say "The fallback lines are in the 2026-11-19 addendum's Deadline paragraph of $RUNBOOK. Close this tracker and remove its follow-through label."
  fi
  if [ "$bad" -eq 1 ]; then
    say "A line starting with $MARKER: was found on #$ISSUE but its time is not a real UTC time in the form YYYY-MM-DDTHH:MM:SSZ, so it was ignored."
  fi
  return 5
}

( main )
rc=$?
case "$rc" in
  "$CAPTURED") exit 0 ;;
  3|5) exit "$rc" ;;
  *) say "CANNOT ESTABLISH: probe internal error (rc=$rc)"; exit 3 ;;
esac
