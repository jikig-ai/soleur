#!/usr/bin/env bash
# Follow-through probe: host kernel patch cadence (Ref #12008, item 2). NOTIFY-ONLY.
#
# It runs the #12007 reader (plugins/soleur/skills/cve-exposure/scripts/host-state.sh, unmodified) and decides, per host row,
# whether the host is past its patch and reboot cadence. The cadence numbers are the four constants below; the
# runbook (knowledge-base/engineering/operations/runbooks/host-kernel-patch-cadence.md) names this file for them and
# never copies the numbers.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   5 = ACTION REQUIRED   at least one row is past its cadence and not acknowledged
#   2 = NOT YET           every row is fresh, observed and within its cadence
#   3 = CANNOT ESTABLISH  anything else: an unknown, stale or silent row, a missing or duplicate or unseen role row,
#                         an unreadable uptime, a reader problem, an argument, an acknowledged-only overdue row
#   (78 under xtrace.) This probe NEVER exits 0 or 1: it must not close the tracker and must not read as a failure.
#
# Public output. The sweeper republishes stdout near-verbatim as a public tracker comment. Stdout is therefore
# exactly one of three fixed lines; no class name, no count, no version, no host, no digit. The reader's
# stderr is discarded. Unknown is the default (ADR-322): only a fresh, observed row with a numeric uptime can
# be within cadence, and only that row can be overdue.
#
# PROXY CAVEAT. uptime_s is the time since the last boot, an upper bound on the age of the running kernel: a
# reboot onto the same kernel resets it, and the value can come from a row up to 48 hours older than the
# row that carries the state. It is the conservative signal, not a kernel age. The reader's kernel_age_hours is the age of
# its newest report row, not of the kernel, and is not used.
#
# Credential posture: this script holds none. The tracker directive's secrets= clause injects the Better Stack read
# credentials the reader needs; without them the reader exits non-zero and this prints the cannot-establish line.
# The tracker is filed UNARMED until a session run of the reader shows at least one fresh, observed row.
#
# Test seam: HKC_READER (a stub path) and HKC_TODAY (YYYY-MM-DD) are honoured only when HKC_TEST=1; the sweeper
# runs probes under env -i, so neither can redirect a production run.
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md
#
# RETIREMENT: when the host kernel emitters are rolled out and this probe has been observed through one full
# cadence, or the owner closes the tracker, delete every site together: this file,
# scripts/followthroughs/host-kernel-cadence-12008.test.sh, the run_suite line in scripts/test-all.sh, the rows in
# scripts/suite-shard-legs.tsv and scripts/suite-durations.tsv, and the directive in the tracker body.

set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace (see #7797)\n' >&2; exit 78 ;;
esac

# soleur:followthrough-stub v1

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

# Cadence per host class, in days. The owner edits these four lines; the runbook points here.
readonly CADENCE_DAYS_WEB=30
readonly CADENCE_DAYS_INNGEST=30
readonly CADENCE_DAYS_REGISTRY=30
readonly CADENCE_DAYS_GIT_DATA=45

# Time-boxed acknowledgement per host row (YYYY-MM-DD, empty by default). It suppresses ONLY an overdue
# row, never an unknown one, and only until that date. A non-empty value needs a comment line directly above it that
# carries its tracking issue number, and may be at most 90 days past this file's last commit date (the test
# enforces both). An expired date re-arms the row.
readonly ACK_UNTIL_WEB_1=''
readonly ACK_UNTIL_WEB_2=''
readonly ACK_UNTIL_INNGEST=''
readonly ACK_UNTIL_REGISTRY=''
readonly ACK_UNTIL_GIT_DATA=''

REQUIRED_ROLES='web-1 web-2 inngest registry git-data'

emit() { # token -> prints the one fixed line and exits; an unrecognised token can only print cannot-establish
  local tok="$1" rc
  case "$tok" in
    review-needed) rc=5 ;;
    nothing-to-report) rc=2 ;;
    cannot-establish) rc=3 ;;
    *) tok=cannot-establish; rc=3 ;;
  esac
  printf 'host-kernel-cadence: %s\n' "$tok"
  exit "$rc"
}

[ "$#" -eq 0 ] || emit cannot-establish

today="$(date -u +%Y-%m-%d)"
if [ "${HKC_TEST:-}" = 1 ] && [ -n "${HKC_TODAY:-}" ]; then today="$HKC_TODAY"; fi

known_role() { case "$1" in web-1|web-2|inngest|registry|git-data) return 0 ;; *) return 1 ;; esac; }

cadence_days() {
  case "$1" in
    web-1|web-2) printf '%s' "$CADENCE_DAYS_WEB" ;;
    inngest) printf '%s' "$CADENCE_DAYS_INNGEST" ;;
    registry) printf '%s' "$CADENCE_DAYS_REGISTRY" ;;
    git-data) printf '%s' "$CADENCE_DAYS_GIT_DATA" ;;
  esac
}

ack_for() {
  case "$1" in
    web-1) printf '%s' "$ACK_UNTIL_WEB_1" ;;
    web-2) printf '%s' "$ACK_UNTIL_WEB_2" ;;
    inngest) printf '%s' "$ACK_UNTIL_INNGEST" ;;
    registry) printf '%s' "$ACK_UNTIL_REGISTRY" ;;
    git-data) printf '%s' "$ACK_UNTIL_GIT_DATA" ;;
  esac
}

ack_live() { [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [[ "$1" > "$today" ]]; }

classify_row() { # role marker_state kernel_state uptime_s -> overdue | acked | within | unknown
  local role="$1" ms="$2" ks="$3" up="$4" days ack
  days="$(cadence_days "$role")"
  [[ "$days" =~ ^[0-9]+$ ]] || { echo unknown; return; }
  [ "$ms" = fresh ] && [ "$ks" = observed ] || { echo unknown; return; }
  [[ "$up" =~ ^[0-9]{1,12}$ ]] || { echo unknown; return; }
  if [ "$up" -le $((days * 86400)) ]; then echo within; return; fi
  ack="$(ack_for "$role")"
  if [ -n "$ack" ] && ack_live "$ack"; then echo acked; return; fi
  echo overdue
}

aggregate() { # classes... -> token. Precedence: overdue, then unknown, then acked, then the all-clear.
  local c
  for c in "$@"; do if [ "$c" = overdue ]; then echo review-needed; return; fi; done
  for c in "$@"; do if [ "$c" = unknown ]; then echo cannot-establish; return; fi; done
  for c in "$@"; do if [ "$c" = acked ]; then echo cannot-establish; return; fi; done
  echo nothing-to-report
}

READER="$ROOT/plugins/soleur/skills/cve-exposure/scripts/host-state.sh"
if [ "${HKC_TEST:-}" = 1 ] && [ -n "${HKC_READER:-}" ]; then READER="$HKC_READER"; fi
cd "$ROOT" || emit cannot-establish
[ -f "$READER" ] || emit cannot-establish

out="$(bash "$READER" 2>/dev/null)"; rc=$?
[ "$rc" -eq 0 ] || emit cannot-establish

declare -A SEEN=()
classes=()
problem=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in SOLEUR_CVE_HOST_STATE\ *) continue ;; esac
  fields="$(awk -F'\t' 'NF >= 8 { print $1 "\t" $2 "\t" $3 "\t" $6; next } { print "BAD" }' <<<"$line")"
  if [ -z "$fields" ] || [ "$fields" = BAD ]; then problem=1; continue; fi
  IFS=$'\t' read -r role ms ks up <<<"$fields"
  if ! known_role "$role"; then problem=1; continue; fi
  [ -z "${SEEN[$role]:-}" ] || problem=1
  SEEN[$role]=1
  classes+=("$(classify_row "$role" "$ms" "$ks" "$up")")
done <<<"$out"

for r in $REQUIRED_ROLES; do
  [ -n "${SEEN[$r]:-}" ] || classes+=("unknown")
done
if [ "$problem" -ne 0 ]; then classes+=("unknown"); fi

emit "$(aggregate "${classes[@]}")"
