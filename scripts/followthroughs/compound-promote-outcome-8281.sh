#!/usr/bin/env bash
# Follow-through verification for #8281 — the SCHEDULED weekly run of
# `cron-compound-promote` emits a readable outcome marker.
#
# #8281 made the promoter's outcome observable: every terminal path emits one
# WARN-level `SOLEUR_COMPOUND_PROMOTE_OUTCOME` record. This probe proves the
# WEEKLY path does it, which is the only claim a post-merge soak can settle.
#
# Both triggers dispatch the IDENTICAL handler (`cron-compound-promote.ts`
# registers `{ cron: "0 0 * * 0" }` and `{ event: "…manual-trigger" }` on one
# function), so "it entered through a different event" is NOT what separates
# them — an earlier revision of this header claimed that and was wrong. The
# separation is the marker's own `trigger` field, which the handler stamps from
# the invoking event. This probe REQUIRES `trigger == "cron"`, so the manual
# fire in the plan's post-merge step cannot satisfy it.
#
# Three fail-open shapes this probe is built to avoid, each measured in-repo:
#
#  1. ECHO. `--grep` becomes SQL `raw LIKE '%…%'`, and GitHub webhook payloads
#     (issue and PR bodies) land in the same source. This PR's body, plan, spec
#     and learnings all quote the marker name, so a client-side `grep -c` over
#     undecoded `raw` would count this PR's own description and auto-close
#     #8281 on an echo of itself. We decode structurally and field-isolate on
#     `.fn`, mirroring `anthropic-admin-key-6297.sh` and
#     `run-report-exit-first-contact-8076.sh`.
#  2. DARK CHANNEL. Zero decoded rows is only evidence if the pipeline is
#     known live. `SOLEUR_CLAUDE_COST` rides the same pino WARN → Vector
#     Source 3 → Better Stack path, so it is the positive control; with no
#     control rows we refuse to grade the absence.
#  3. SLIDING WINDOW. A window anchored to RUN time slides every time a sweep
#     is deferred, so a fire that happened can drop out of view and read as
#     "still soaking". The window is anchored to the merge floor instead.
#
# Exit semantics (per sweep-followthroughs.sh's rc→word map):
#   0 = PASS              (>=1 decoded scheduled marker after the floor)
#   1 = FAIL              (the channel is live but the scheduled path is dark)
#   2 = NOT YET           (no scheduled fire in the window yet — still soaking)
#   3 = CANNOT ESTABLISH  (a required credential is not injected)
#
# Directive on #8281 (earliest must sit >=8d past merge so one `0 0 * * 0`
# fire has landed; update FT8281_MERGE_FLOOR to the merge timestamp):
#   <!-- soleur:followthrough script=scripts/followthroughs/compound-promote-outcome-8281.sh earliest=<merge+8d> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->
set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797). Tracing echoes commands after expansion,
# so a credential is printed the moment it is used. `${VAR:+x}` tests
# non-emptiness WITHOUT expanding the value. All three Better Stack vars are
# tested, not just the password — the host and username are forwarded too.
case "$-" in
  *x*)
    if [ -n "${BETTERSTACK_QUERY_PASSWORD:+x}${BETTERSTACK_QUERY_USERNAME:+x}${BETTERSTACK_QUERY_HOST:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (see #7797).\n' >&2
      exit 78
    fi
    ;;
esac

for v in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
  if [ -z "${!v:-}" ]; then
    printf 'CANNOT ESTABLISH: %s is not injected (declare it in the directive secrets= clause).\n' "$v" >&2
    exit 3
  fi
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -z "$REPO_ROOT" ]; then
  # Without this, a failed cd leaves QUERY_SH as "/scripts/betterstack-query.sh"
  # and the probe reports a credential-shaped TRANSIENT on every sweep forever.
  printf 'CANNOT ESTABLISH: could not resolve the repo root from %s\n' "${BASH_SOURCE[0]}" >&2
  exit 3
fi
QUERY_SH="$REPO_ROOT/scripts/betterstack-query.sh"
# `-f` only: the script is invoked as `bash "$QUERY_SH"`, so its execute bit is
# irrelevant. The previous `[ ! -x ] && [ ! -f ]` compound was exactly
# equivalent to this while reading as an executability check it was not.
if [ ! -f "$QUERY_SH" ]; then
  printf 'NOT YET: betterstack-query.sh not found at %s\n' "$QUERY_SH" >&2
  exit 2
fi

MERGE_FLOOR="${FT8281_MERGE_FLOOR:-2026-09-18T00:00:00Z}"
LIMIT="${FT8281_LIMIT:-200}"
numeric() { [[ "$1" =~ ^[0-9]+$ ]]; }

floor_s="$(date -u -d "$MERGE_FLOOR" +%s 2>/dev/null || true)"
numeric "$floor_s" || {
  printf 'CANNOT ESTABLISH: FT8281_MERGE_FLOOR does not parse: %s\n' "${MERGE_FLOOR:0:40}" >&2; exit 3; }
numeric "$LIMIT" || {
  printf 'CANNOT ESTABLISH: FT8281_LIMIT is not a number: %s\n' "${LIMIT:0:40}" >&2; exit 3; }
now_s="$(date -u +%s)"
# +2d of slack so a fire at the floor's edge is inside the window.
WINDOW="$(( (now_s - floor_s) / 86400 + 2 ))d"

# One decoder for both reads. `-R` plus `fromjson?` at BOTH levels so a
# non-JSON line (merged stderr, a mid-stream ClickHouse exception) is skipped
# rather than aborting jq into a silent zero. The pino payload sits under
# `.message` of the decoded `raw` — measured, not assumed; see
# knowledge-base/engineering/operations/runbooks/betterstack-log-query.md.
# $1 = a jq boolean over the decoded message; $2 = what to print per row.
decode_rows() {
  jq -R -r 'fromjson? | .raw? | fromjson? | .message?
            | select(type == "object" and ('"$1"')) | '"$2"
}

# `run_query <label> <grep> <limit> <outfile>` — stderr is CAPTURED, never
# discarded. betterstack-query.sh exits 3 for "nothing was queried" and prints
# an actionable heredoc saying so; swallowing it reports a bare number to an
# operator who then cannot act. rc 3 is forwarded as 3, not folded into a
# generic transient.
#
# Writes to a FILE and is called as a plain statement, NOT inside `$(...)`.
# The first revision returned stdout through a command substitution, so its
# `exit 3` exited the SUBSHELL, the caller received an empty string, and a
# "nothing was queried" condition was graded as a dark channel (FAIL) instead
# of CANNOT ESTABLISH. Caught by the companion test's case 7.
run_query() {
  local label="$1" pattern="$2" lim="$3" outfile="$4" rc
  bash "$QUERY_SH" --since "$WINDOW" --grep "$pattern" --limit "$lim" > "$outfile" 2>&1
  rc=$?
  if [ "$rc" -eq 3 ]; then
    printf 'CANNOT ESTABLISH: betterstack-query.sh could not query (%s): %s\n' "$label" "$(head -c 400 "$outfile")" >&2
    exit 3
  fi
  if [ "$rc" -ne 0 ]; then
    printf 'NOT YET: betterstack-query.sh exited %s (%s): %s\n' "$rc" "$label" "$(head -c 400 "$outfile")" >&2
    exit 2
  fi
}

QOUT="$(mktemp -t ft8281-rows.XXXXXXXX)"
trap 'rm -f -- "$QOUT"' EXIT

# --- positive control: prove the channel carries WARN markers at all ---------
run_query control SOLEUR_CLAUDE_COST 5 "$QOUT"
ctl="$(cat "$QOUT")"
ctl_n="$(printf '%s\n' "$ctl" | decode_rows '.SOLEUR_CLAUDE_COST == true' '"row"' | grep -c . || true)"
if ! numeric "$ctl_n" || [ "$ctl_n" -eq 0 ]; then
  printf 'FAIL: the positive control (SOLEUR_CLAUDE_COST decoded under .message within %s) returned 0 rows — the WARN->Vector->Better Stack channel is dark or its row shape changed. Refusing to read an absence through a dead instrument.\n' "$WINDOW" >&2
  exit 1
fi

# --- the assertion: a SCHEDULED outcome marker exists -----------------------
run_query outcome SOLEUR_COMPOUND_PROMOTE_OUTCOME "$LIMIT" "$QOUT"
rows="$(cat "$QOUT")"
sel='.SOLEUR_COMPOUND_PROMOTE_OUTCOME == true and .fn == "cron-compound-promote"'
all_statuses="$(printf '%s\n' "$rows" | decode_rows "$sel" '"\(.trigger // "unset")\t\(.status // "unset")"' || true)"
all_n="$(printf '%s\n' "$all_statuses" | grep -c . || true)"
sched="$(printf '%s\n' "$all_statuses" | grep '^cron	' || true)"
sched_n="$(printf '%s\n' "$sched" | grep -c . || true)"

if [ "$sched_n" -ge 1 ]; then
  printf 'PASS: %s scheduled SOLEUR_COMPOUND_PROMOTE_OUTCOME marker(s) in %s (control live: %s rows). Statuses:\n%s\n' \
    "$sched_n" "$WINDOW" "$ctl_n" "$(printf '%s\n' "$sched" | sort | uniq -c)"
  exit 0
fi

if [ "$all_n" -ge 1 ]; then
  printf 'NOT YET: %s decoded outcome marker(s) in %s but none with trigger=cron (control live: %s rows) — only manual fires so far. Observed:\n%s\n' \
    "$all_n" "$WINDOW" "$ctl_n" "$(printf '%s\n' "$all_statuses" | sort | uniq -c)" >&2
  exit 2
fi

printf 'NOT YET: 0 decoded SOLEUR_COMPOUND_PROMOTE_OUTCOME markers in %s, though the channel is live (control: %s rows) — the weekly fire has not landed since %s.\n' \
  "$WINDOW" "$ctl_n" "$MERGE_FLOOR" >&2
exit 2
