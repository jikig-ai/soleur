#!/usr/bin/env bash
# Follow-through probe: host kernel patch cadence (Ref #12008, item 2). NOTIFY-ONLY.
#
# It runs the #12007 reader (plugins/soleur/skills/cve-exposure/scripts/host-state.sh, unmodified) and decides, per host row,
# whether the host is past its patch and reboot cadence. The cadence numbers are the four constants below; the
# runbook (knowledge-base/engineering/operations/runbooks/host-kernel-patch-cadence.md) names this file for them and
# never copies the numbers.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   5 = ACTION REQUIRED   at least one row is past its cadence
#   2 = NOT YET           every required row is fresh, observed and within its cadence
#   3 = CANNOT ESTABLISH  anything else: an unknown, stale or silent row, a missing or duplicate or unseen role row,
#                         a row whose fixed columns do not have the reader's shape, an unreadable uptime, a reader
#                         problem, an argument
#   (78 under xtrace.) This probe NEVER exits 0 or 1: it must not close the tracker and must not read as a failure.
#
# Rows. The five REQUIRED_ROLES must each appear once. IGNORED_ROLES are rows the reader prints for hosts that are
# default-off and have no emitter and no cadence; they are skipped, never graded. Any other role is a problem
# (fail closed), and the suite pins the reader's role table against these two lists, so a role the reader adds or
# renames fails in the change that causes it.
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
# The tracker is filed UNARMED. It is armed only once a session run of this probe prints a line other than
# cannot-establish (which needs the emitter roll-out and the git-data reader source); until then it can only say
# cannot-establish. Acknowledging a row that is overdue by design is deferred to the arming change.
#
# Test seam: HKC_READER (a stub path) is honoured only when HKC_TEST=1; the sweeper runs probes under env -i, so
# nothing can redirect a production run.
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

REQUIRED_ROLES='web-1 web-2 inngest registry git-data'
IGNORED_ROLES='grok-dogfood'

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

known_role() { case "$1" in web-1|web-2|inngest|registry|git-data) return 0 ;; *) return 1 ;; esac; }
ignored_role() { case " $IGNORED_ROLES " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

cadence_days() {
  case "$1" in
    web-1|web-2) printf '%s' "$CADENCE_DAYS_WEB" ;;
    inngest) printf '%s' "$CADENCE_DAYS_INNGEST" ;;
    registry) printf '%s' "$CADENCE_DAYS_REGISTRY" ;;
    git-data) printf '%s' "$CADENCE_DAYS_GIT_DATA" ;;
  esac
}

classify_row() { # role marker_state kernel_state uptime_s -> overdue | within | unknown
  local role="$1" ms="$2" ks="$3" up="$4" days
  days="$(cadence_days "$role")"
  [ "$ms" = fresh ] && [ "$ks" = observed ] || { echo unknown; return; }
  [[ "$up" =~ ^[0-9]{1,12}$ ]] || { echo unknown; return; }
  if [ "$up" -le $((days * 86400)) ]; then echo within; return; fi
  echo overdue
}

aggregate() { # classes... -> token. Precedence: overdue, then unknown, then the all-clear.
  local c
  for c in "$@"; do if [ "$c" = overdue ]; then echo review-needed; return; fi; done
  for c in "$@"; do if [ "$c" = unknown ]; then echo cannot-establish; return; fi; done
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
  # Columns (the reader's header comment): host_role marker_state kernel_state age_hours kernel uptime_s kernel_age_hours
  # source_marker. Eight or more fields are accepted so a column appended later is safe; the fixed columns must have
  # their shape or the row is a problem, so a column inserted before uptime_s cannot shift a number into its place
  # unnoticed unless it also keeps every enum and numeric column valid.
  fields="$(awk -F'\t' 'NF >= 8 && $2 ~ /^(fresh|stale|silent|unknown)$/ && $3 ~ /^(observed|stale|unknown)$/ && $4 ~ /^([0-9]+|unknown)$/ && $5 ~ /^[A-Za-z0-9._+~:-]+$/ && $7 ~ /^([0-9]+|unknown)$/ { print $1 "\t" $2 "\t" $3 "\t" $6; next } { print "BAD" }' <<<"$line")"
  if [ -z "$fields" ] || [ "$fields" = BAD ]; then problem=1; continue; fi
  IFS=$'\t' read -r role ms ks up <<<"$fields"
  if ignored_role "$role"; then continue; fi
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
