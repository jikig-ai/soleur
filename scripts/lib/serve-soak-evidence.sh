#!/usr/bin/env bash
# serve-soak-evidence.sh — the serve arm's soak evidence helper (#12849, ADR-263 2026-11-18 addendum). Sourced by two
# steps of .github/workflows/cf-lb-overlay.yml (job ga_pool_update) and by the read-only probe
# scripts/serve-soak-evidence-last.sh; executed directly by the gate suite (apps/web-platform/infra/lb-weight-gate.test.sh
# §SK), so the step logic is tested as the file that runs, never as a sed-extracted step body.
#
#  - The `§(c) gate chain` step captures the traffic-weight gate's stderr to a file and calls
#    sse_gate_chain_mirror (the summary mirror; a refusal names its id) and, after its own flip-marker check,
#    sse_gate_chain_verify (anti-vacuity: a gate that passes must have printed one well-formed pass line per soak kind).
#  - The `per-instance soak grader (serve only)` step calls sse_instance_soak, which runs the per-instance soak grader
#    scripts/followthroughs/web2-luks-live-6931.sh with only the names it reads, and refuses the serve flip unless it
#    says PASS. The gate's soak reads Doppler marker TIMES; the grader reads web-2's readiness and probe rows and
#    requires one boot_id across them, so a replaced instance cannot ride its predecessor's rows or an old marker.
#
# ERROR HANDLING. Every guarded command carries an explicit `|| return 1`. Nothing here relies on `set -e` inside a
# function: bash switches errexit off in a function called as `fn || ...` or `if fn`. The steps call each function as
# a bare statement under `set -euo pipefail`: the mirror call is followed by the step's inline gate_rc exit, and the
# verify and grader calls are each their step's last statement, so a non-zero return fails the step.
#
# TRAPS. sse_instance_soak installs the EXIT and TERM traps of the shell that calls it. It must be the last statement
# of a step that sets no trap of its own (a wiring row refuses any other `trap` in that step).
#
# This file never names the soak marker's Doppler key and never names the gate script by file name in code.

# Reload guard: a readonly grammar means this shell already sourced the file. An inherited environment value cannot
# fake it (the environment carries no readonly attribute), unlike a plain marker variable.
if [[ "$(declare -p SOAK_EV_RE 2>/dev/null)" == "declare -r "* ]]; then return 0; fi

# THE GRAMMAR, its one copy (G4). Producer: the gate's soak_ev (in its fail() and its two pass emits). Consumers: the
# mirror and the pass re-check below, the probe, and the gate suite. Every field is a closed token: no backtick (the
# mirror fences it), no raw environment text. Groups: 1 kind, 2 soak_days, 3 source, 4 marker_at, 5 age_s,
# 6 required_s, 7 verdict, 8 sub_condition (the pass re-check reads them by number).
readonly SOAK_EV_RE='SOLEUR_SOAK_EVIDENCE kind=(workspaces_luks|git_data) host=[a-z][a-z0-9-]{0,30} soak_days=([1-9][0-9]{0,2}|invalid) source=(default|env) floor_days=[1-9][0-9]{0,2} marker_at=([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|none|unparseable) age_s=(-?[0-9]+|none) required_s=([1-9][0-9]*|none) verdict=(pass|fail) sub_condition=(B_[a-z_]+|none)'
# The per-instance verdict line. rc=none: the grader was never run (wrong host, no scratch HOME); rc=interrupted: a
# cancel, timeout or abort while it ran. The grader= value is pinned by a wiring row, not by the grammar.
# shellcheck disable=SC2034 # read by the probe and the gate suite
readonly INSTANCE_EV_RE='SOLEUR_INSTANCE_SOAK host=([a-z][a-z0-9-]{0,30}|invalid) grader=[a-z0-9-]+ rc=([0-9]+|none|interrupted) verdict=(PASS|FAIL|NOT_YET|CANNOT_ESTABLISH)'
# The grader's first line as the log and the summary may show it: verdict-shaped, no control character, no backtick.
readonly GRADE_TEXT_RE='^(PASS|FAIL|NOT YET|CANNOT ESTABLISH): [^[:cntrl:]`]*$'
# The soak floor in seconds: the gate's SOAK_FLOOR_DAYS * 86400 = the grader's SOAK_DAYS * 86400 (a parity row pins all three).
readonly SOAK_FLOOR_S=259200
# The only host the grader can read: its rows library hardwires web-2's Better Stack host name. Until #12869.
readonly SSE_GRADED_HOST="web-2"
readonly SSE_GRADER_NAME="web2-luks-live-6931"

SSE_INSTANCE_HOST=invalid
SSE_INSTANCE_DONE=0

# ---------------------------------------------------------------------------------------------------------------------
# sse_gate_chain_mirror <stderr-file> <gated-host> <gate-rc> — the summary mirror. Writes the grammar-matching lines of
# the captured stderr into a fenced block under one heading; on a non-zero rc names the refusing id and returns 1. The
# id is read from the anchored gate_fail line; when the wrapper refused before the gate ran it is
# gate_not_run_<class> (from its marker_source_fail line); `none` when neither line is there.
sse_gate_chain_mirror() {
  local f="$1" host="$2" rc="$3" id=none wrap="" l sum="${GITHUB_STEP_SUMMARY:-/dev/null}" floor_d=$((SOAK_FLOOR_S / 86400))
  [[ -r "$f" ]] || { echo "::error::§(c) gate chain: the captured gate stderr ($f) is missing - a wiring defect, do not re-dispatch"; return 1; }
  [[ "$rc" =~ ^[0-9]+$ ]] || { echo "::error::§(c) gate chain: gate rc '$rc' is not an integer - a wiring defect, do not re-dispatch"; return 1; }
  [[ "$host" =~ ^[a-z][a-z0-9-]{0,30}$ ]] || host=invalid
  while IFS= read -r l || [[ -n "$l" ]]; do
    if [[ "$l" =~ ^gate_fail\ sub_condition=([A-Za-z0-9_]+)$ ]]; then id="${BASH_REMATCH[1]}"; break; fi
    if [[ -z "$wrap" && "$l" =~ ^marker_source_fail\ class=([a-z0-9_]+)\  ]]; then wrap="gate_not_run_${BASH_REMATCH[1]}"; fi
  done <"$f"
  [[ "$id" != none || -z "$wrap" ]] || id="$wrap"
  # The annotation first: a failed summary write must never cost the refusal its ::error:: line.
  if [[ "$rc" -ne 0 ]]; then
    echo "::error::§(c) gate chain refused the flip (sub_condition=${id}) for ${host} - the preconditions are not met (or could not be proven). NOTHING planned, NOTHING applied. A refused serve never drains: if ${host} is already serving, dispatch mode=drain."
    if [[ "$id" == *_soak_days_below_floor ]]; then
      echo "::error::a configured soak value is below the ${floor_d}-day floor; delete it from Doppler prd (#12933, Operator-authorizes) - the floor cannot be shortened, values may only lengthen it. Never restore the weight by a full-root apply."
    fi
    printf '### §(c) gate chain soak evidence (refused: sub_condition=%s)\n\n' "$id" >>"$sum" || return 1
  else
    printf '### §(c) gate chain soak evidence\n\n' >>"$sum" || return 1
  fi
  printf '```text\n' >>"$sum" || return 1
  grep -E "^${SOAK_EV_RE}\$" "$f" >>"$sum" || [[ $? -eq 1 ]] || return 1
  printf '```\n\n' >>"$sum" || return 1
  if [[ "$rc" -ne 0 ]]; then
    printf -- '- per-instance soak grader: NOT RUN (gate refused)\n' >>"$sum" || return 1
    return 1
  fi
  return 0
}

# sse_gate_chain_verify <stderr-file> <gated-host> — the pass re-check (anti-vacuity). Every line that starts with the
# evidence token must match the grammar whole (a near-miss is a defect, never skipped). For each soak kind: exactly one
# line, for this host, verdict=pass sub_condition=none, an ISO marker_at, age_s and required_s of at most 12 digits,
# required_s >= SOAK_FLOOR_S and age_s >= required_s. Anything else is a code defect, never a soak wait.
sse_gate_chain_verify() {
  local f="$1" host="$2" k l n a r m ag rq v sc re_full="^${SOAK_EV_RE}\$"
  local -A cnt=() age=() req=() good=()
  [[ -r "$f" ]] || { echo "::error::§(c) gate chain: the captured gate stderr ($f) is missing - a wiring defect, do not re-dispatch"; return 1; }
  if [[ ! "$host" =~ ^[a-z][a-z0-9-]{0,30}$ ]]; then
    echo "::error::§(c) gate chain: the gated host is malformed - a wiring defect, do not re-dispatch"
    return 1
  fi
  while IFS= read -r l || [[ -n "$l" ]]; do
    [[ "$l" == SOLEUR_SOAK_EVIDENCE* ]] || continue
    if [[ ! "$l" =~ $re_full ]]; then
      echo "::error::§(c) gate chain: gate passed but printed a malformed soak evidence line - a code defect, not a soak wait; do not re-dispatch"
      return 1
    fi
    # copy the groups first: the next =~ below overwrites BASH_REMATCH
    k="${BASH_REMATCH[1]}"; m="${BASH_REMATCH[4]}"; ag="${BASH_REMATCH[5]}"; rq="${BASH_REMATCH[6]}"; v="${BASH_REMATCH[7]}"; sc="${BASH_REMATCH[8]}"
    cnt[$k]=$(( ${cnt[$k]:-0} + 1 ))
    good[$k]=0
    if [[ "$l" == "SOLEUR_SOAK_EVIDENCE kind=${k} host=${host} "* && "$v" == pass && "$sc" == none && "$m" == [0-9]* \
          && "$ag" =~ ^[0-9]{1,12}$ && "$rq" =~ ^[0-9]{1,12}$ ]]; then
      good[$k]=1; age[$k]="$ag"; req[$k]="$rq"
    fi
  done <"$f"
  for k in git_data workspaces_luks; do
    n="${cnt[$k]:-0}"; a="${age[$k]:-}"; r="${req[$k]:-}"
    if [[ "$n" -ne 1 || "${good[$k]:-0}" -ne 1 || -z "$a" || -z "$r" ]] || (( 10#$r < SOAK_FLOOR_S || 10#$a < 10#$r )); then
      echo "::error::§(c) gate chain: gate passed but soak evidence for kind=${k} is missing or malformed - a code defect, not a soak wait; do not re-dispatch"
      return 1
    fi
  done
  return 0
}

# ---------------------------------------------------------------------------------------------------------------------
# _sse_instance_emit <rc|none|interrupted> <VERDICT> [grade-text] — the one verdict line: stderr, plus a fenced copy in
# the summary (and the grader's own first line in a second fence, when it is verdict-shaped).
_sse_instance_emit() {
  local line="SOLEUR_INSTANCE_SOAK host=${SSE_INSTANCE_HOST} grader=${SSE_GRADER_NAME} rc=$1 verdict=$2" sum="${GITHUB_STEP_SUMMARY:-/dev/null}"
  SSE_INSTANCE_DONE=1
  printf '%s\n' "$line" >&2
  # shellcheck disable=SC2016 # the backticks are the markdown fence, not an expansion
  printf '### per-instance soak grader (serve only)\n\n```text\n%s\n```\n\n' "$line" >>"$sum" || return 1
  if [[ -n "${3:-}" ]]; then
    # shellcheck disable=SC2016 # the backticks are the markdown fence, not an expansion
    printf '```text\ngrade_text=%s\n```\n\n' "$3" >>"$sum" || return 1
  fi
  return 0
}

# The EXIT/TERM backstop: a cancel, a timeout or an abort while the grader's output is buffering still leaves a line.
_sse_instance_trap() {
  if [[ "${SSE_INSTANCE_DONE:-0}" -ne 1 ]]; then _sse_instance_emit interrupted CANNOT_ESTABLISH || true; fi
}

# sse_instance_soak <gated-host> <grader-path> — run the per-instance soak grader and refuse unless it says PASS. A
# verdict counts only when the grader's exit code and its first line agree (0 PASS:, 1 FAIL:, 2 NOT YET:,
# 3 CANNOT ESTABLISH:); every grader exit path prints that line, so a mismatch (an empty or truncated grader, a bash
# abort) is a code defect, never a grade.
sse_instance_soak() {
  case "$-" in
    *x*) echo "::error::per-instance soak grader refuses to run under xtrace (it would print the Better Stack credentials) - a wiring defect, do not re-dispatch"
         return 78 ;;
  esac
  local host="$1" grader="$2" rc=0 grade first="" shown="" want="" verdict next ghome floor_d=$((SOAK_FLOOR_S / 86400))
  SSE_INSTANCE_DONE=0
  SSE_INSTANCE_HOST=invalid
  if [[ "$host" =~ ^[a-z][a-z0-9-]{0,30}$ ]]; then SSE_INSTANCE_HOST="$host"; fi
  trap _sse_instance_trap EXIT
  trap 'exit 143' TERM

  # until #12869: the grader reads only one host's probe rows (its rows library hardwires that host's Better Stack
  # host name), so any other gated host cannot be graded and fails closed without calling it.
  if [[ "$SSE_INSTANCE_HOST" != "$SSE_GRADED_HOST" ]]; then
    echo "::error::per-instance soak grader: the gated host (${SSE_INSTANCE_HOST}) is not ${SSE_GRADED_HOST}; the grader reads only ${SSE_GRADED_HOST}'s probe rows until #12869 - a wiring defect, do not re-dispatch. NOTHING planned, NOTHING applied."
    _sse_instance_emit none CANNOT_ESTABLISH || return 1
    return 1
  fi

  # Only the names the grader reads (G10): the job's earlier steps export Terraform and Doppler credentials to
  # GITHUB_ENV. HOME is a fresh scratch directory (jq loads ~/.jq, and the job's HOME is writable by earlier steps) and
  # PATH is pinned. An empty SOLEUR_FT_EARLIEST means "no clock", so an unmet soak reads NOT YET, never a window FAIL.
  # W2L_REQUIRE_BOOT_JOIN=1: the readiness and the newest probe row must carry one known boot_id (R2).
  # Residual: env's own argv carries the three values until it execs bash (same-user readable for that instant).
  if ! ghome="$(mktemp -d -p "${RUNNER_TEMP:-/tmp}" sse-grader-home.XXXXXX)"; then
    echo "::error::per-instance soak grader: no scratch HOME could be created under RUNNER_TEMP - the grader was not run; retry the dispatch. NOTHING planned, NOTHING applied."
    _sse_instance_emit none CANNOT_ESTABLISH || return 1
    return 1
  fi
  grade="$(env -i PATH=/usr/bin:/bin HOME="$ghome" TMPDIR="${RUNNER_TEMP:-/tmp}" \
    BETTERSTACK_QUERY_HOST="${BETTERSTACK_QUERY_HOST-}" BETTERSTACK_QUERY_USERNAME="${BETTERSTACK_QUERY_USERNAME-}" \
    BETTERSTACK_QUERY_PASSWORD="${BETTERSTACK_QUERY_PASSWORD-}" SOLEUR_FT_EARLIEST= W2L_REQUIRE_BOOT_JOIN=1 bash "$grader")" || rc=$?
  rm -rf "$ghome" || true

  # The grader's own first line goes to the log only when it is verdict-shaped: the grader is shared with the
  # sweeper, and GitHub reads workflow commands from stdout and stderr.
  first="${grade%%$'\n'*}"
  if [[ "$first" =~ $GRADE_TEXT_RE ]]; then shown="$first"; printf 'grade_text=%s\n' "$first" >&2
  else printf 'grade_text=unprintable\n' >&2; fi
  case "$rc" in
    0) want="PASS"; verdict=PASS ;;
    1) want="FAIL"; verdict=FAIL ;;
    2) want="NOT YET"; verdict=NOT_YET ;;
    3) want="CANNOT ESTABLISH"; verdict=CANNOT_ESTABLISH ;;
    *) verdict=CANNOT_ESTABLISH ;;
  esac
  if [[ -n "$want" && ( -z "$shown" || "$shown" != "${want}: "* ) ]]; then
    verdict=CANNOT_ESTABLISH
    next="the grader's exit code (rc ${rc}) and its first line (grade_text above) disagree - a code or wiring defect in the grader, not a grade; do not re-dispatch"
  fi
  _sse_instance_emit "$rc" "$verdict" "$shown" || return 1
  if [[ "$rc" -eq 0 && "$verdict" == PASS ]]; then return 0; fi

  if [[ -z "${next:-}" ]]; then
    case "$verdict:$rc" in
      NOT_YET:*) next="NOT_YET: read the grade_text line above. A Better Stack read fault: retry. A soak still running: wait for the ${floor_d}-day soak. No GREEN web-2 readiness row and web-2 created more than 90 days ago, a readiness row that is not formatted/opened, or a boot_id that differs between the readiness and probe rows: replace the host (web-host-replace.md), dispatch mode=drain first if web-2 is serving, and wait for the ${floor_d}-day soak" ;;
      FAIL:*) next="the soak of this instance is spoiled; if web-2 is serving (live weight 1) dispatch mode=drain first, then investigate - a replace is the repair" ;;
      CANNOT_ESTABLISH:3) next="Better Stack credentials or the shared helper are missing" ;;
      *) next="a code or wiring defect; do not re-dispatch" ;;
    esac
  fi
  echo "::error::per-instance soak grader verdict=${verdict} rc=${rc} - NOTHING planned, NOTHING applied. ${next}"
  return 1
}
