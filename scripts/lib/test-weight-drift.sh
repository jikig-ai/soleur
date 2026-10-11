# shellcheck shell=bash
# test-weight-drift.sh — #9814 local-vs-committed weight-drift comparator.
#
# weight_drift_report <timing-log> <durations-manifest...>
#
# Reads a run's per-suite timing log (run_suite appends
# "<label>\t<elapsed_ms>[\t<class>]" when TEST_TIMING_LOG is set) and compares
# each ran row against the committed weights in every
# scripts/suite-durations*.tsv manifest passed to it. Emits advisory lines to
# stdout AND stderr (the operator-protection dual-emit convention — a line that
# only reaches stderr is invisible to an agent's stdout capture):
#
#   WEIGHT_DRIFT <label> committed=<ms> local=<ms>            local > 2*committed AND local > floor
#   WEIGHT_DRIFT <label> committed=<ms> basis=floor local=<ms>  same, anchor row class == floor
#   WEIGHT_DRIFT <label> committed=unmeasured local=<ms>      no row in any manifest
#   WEIGHT_DRIFT_UNAVAILABLE rows=<n> reason=elapsed-zero     ran rows exist, every elapsed_ms is 0
#   WEIGHT_DRIFT_LOG <path>                                   trailer when >=1 WEIGHT_DRIFT emitted
#
# A row "ran" iff field 3 does not start "skip=" AND elapsed_ms > 0.
# FAIL/KILLED/TRIPWIRE rows still count as ran — they consumed wall-clock.
# Comment (^#) and torn (NF < 2) rows are skipped. Duplicate label rows: last
# wins. Zero readable manifests: every ran row reports committed=unmeasured —
# absence is visible, never silently skipped.
#
# Always returns 0 — this is a warn-only signal, never a gate. One LC_ALL=C awk
# pass (bash-3.2-safe: no declare -A, no bash-4 builtins).

# Value-pinned, mirroring LOCAL_FAST_CAP_MS in test-all-fast-tier-budget.test.sh
# — pin the value, exercise the predicate.
WEIGHT_DRIFT_FLOOR_MS=10000

weight_drift_report() {
  local _wd_log="${1:-}"; shift || true
  local -a _wd_manifests=()
  local _m
  for _m in "$@"; do
    [[ -f "$_m" && -r "$_m" ]] && _wd_manifests+=("$_m")
  done
  if [[ ! -r "$_wd_log" ]]; then
    printf 'weight_drift_report: timing log unreadable: %s\n' "${_wd_log:-<unset>}" >&2
    return 0
  fi
  # Manifests first so the label->ms/class maps are populated before log rows
  # are read; the timing log is identified by FILENAME, not position.
  LC_ALL=C awk -F'\t' \
    -v wdr_log="$_wd_log" -v wdr_floor="$WEIGHT_DRIFT_FLOOR_MS" '
    FILENAME != wdr_log {
      if ($1 ~ /^#/ || NF < 2) next
      if ($2 ~ /^[0-9]+$/) { w[$1] = $2; c[$1] = $3 }
      next
    }
    {
      # Timing-log rows. NF<2 and comments are already excluded by the same
      # guards above — this block only sees FILENAME == wdr_log.
      if ($1 ~ /^#/ || NF < 2) next
      # __run_boundary_*__ probe markers and torn rows with a non-numeric
      # elapsed field are not suite timings — not candidates, and not counted
      # into WEIGHT_DRIFT_UNAVAILABLE rows=.
      if ($1 ~ /^__run_boundary_/ || $2 !~ /^[0-9]+$/) next
      if ($3 ~ /^skip=/) next
      cand++
      if (($2 + 0) > 0) {
        ran++
        l = $1; ms = $2 + 0
        if (l in w) {
          if (ms > 2 * w[l] && ms > wdr_floor) {
            if (c[l] == "floor") line = "WEIGHT_DRIFT " l " committed=" w[l] " basis=floor local=" ms
            else                 line = "WEIGHT_DRIFT " l " committed=" w[l] " local=" ms
            print line; print line > "/dev/stderr"; emitted++
          }
        } else {
          line = "WEIGHT_DRIFT " l " committed=unmeasured local=" ms
          print line; print line > "/dev/stderr"; emitted++
        }
      }
    }
    END {
      if (ran == 0 && cand > 0) {
        line = "WEIGHT_DRIFT_UNAVAILABLE rows=" cand " reason=elapsed-zero"
        print line; print line > "/dev/stderr"
      }
      if (emitted > 0) {
        t = "WEIGHT_DRIFT_LOG " wdr_log
        print t; print t > "/dev/stderr"
      }
    }
  ' "${_wd_manifests[@]+"${_wd_manifests[@]}"}" "$_wd_log" || true
  return 0
}
