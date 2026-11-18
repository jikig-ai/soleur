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
#    says PASS. The gate's soak reads Doppler marker TIMES; the grader reads the instance's own probe rows, so a
#    replaced-but-unsoaked instance cannot ride an old marker.
#
# ERROR HANDLING. Every guarded command carries an explicit `|| return 1`. Nothing here relies on `set -e` inside a
# function: bash switches errexit off in a function called as `fn || ...` or `if fn`. The steps call each function as
# a bare statement, under `set -euo pipefail`, and back each refusal with an inline exit of their own.
#
# This file never names the soak marker's Doppler key and never names the gate script by file name in code.

if [[ -n "${SSE_LIB_LOADED:-}" ]]; then return 0; fi
SSE_LIB_LOADED=1

# THE GRAMMAR, its one copy (G4). Producer: the gate's soak_ev (in its fail() and its two pass emits). Consumers: the
# mirror and the pass re-check below, the probe, and the gate suite. Every field is a closed token: no backtick (the
# mirror fences it), no raw environment text.
readonly SOAK_EV_RE='SOLEUR_SOAK_EVIDENCE kind=(workspaces_luks|git_data) host=[a-z][a-z0-9-]{0,30} soak_days=([1-9][0-9]{0,2}|invalid) source=(default|env) floor_days=[1-9][0-9]{0,2} marker_at=([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z|none|unparseable) age_s=(-?[0-9]+|none) required_s=([1-9][0-9]*|none) verdict=(pass|fail) sub_condition=(B_[a-z_]+|none)'
# The per-instance verdict line. The grader= value is pinned by a wiring row, not by the grammar.
# shellcheck disable=SC2034 # read by the probe and the gate suite
readonly INSTANCE_EV_RE='SOLEUR_INSTANCE_SOAK host=([a-z][a-z0-9-]{0,30}|invalid) grader=[a-z0-9-]+ rc=([0-9]+|none) verdict=(PASS|FAIL|NOT_YET|CANNOT_ESTABLISH)'
# The soak floor in seconds: the gate's SOAK_FLOOR_DAYS * 86400 = the grader's SOAK_DAYS * 86400 (a parity row pins all three).
readonly SOAK_FLOOR_S=259200
# The only host the grader can read: its rows library hardwires web-2's Better Stack host name. Until #12869.
readonly SSE_GRADED_HOST="web-2"
readonly SSE_GRADER_NAME="web2-luks-live-6931"

SSE_INSTANCE_HOST=invalid
SSE_INSTANCE_DONE=0

# ---------------------------------------------------------------------------------------------------------------------
# sse_gate_chain_mirror <stderr-file> <gated-host> <gate-rc> — the summary mirror. Writes the grammar-matching lines of
# the captured stderr into a fenced block under one heading; on a non-zero rc names the refusing id (read from the
# anchored gate_fail line, `none` when the gate never ran) and returns 1.
sse_gate_chain_mirror() {
  local f="$1" rc="$3" id=none l sum="${GITHUB_STEP_SUMMARY:-/dev/null}"
  [[ -r "$f" ]] || { echo "::error::§(c) gate chain: the captured gate stderr ($f) is missing - a wiring defect, do not re-dispatch"; return 1; }
  [[ "$rc" =~ ^[0-9]+$ ]] || { echo "::error::§(c) gate chain: gate rc '$rc' is not an integer - a wiring defect, do not re-dispatch"; return 1; }
  while IFS= read -r l || [[ -n "$l" ]]; do
    if [[ "$l" =~ ^gate_fail\ sub_condition=([A-Za-z0-9_]+)$ ]]; then id="${BASH_REMATCH[1]}"; break; fi
  done <"$f"
  if [[ "$rc" -ne 0 ]]; then
    printf '### §(c) gate chain soak evidence (refused: sub_condition=%s)\n\n' "$id" >>"$sum" || return 1
  else
    printf '### §(c) gate chain soak evidence\n\n' >>"$sum" || return 1
  fi
  printf '```text\n' >>"$sum" || return 1
  grep -E "^${SOAK_EV_RE}\$" "$f" >>"$sum" || [[ $? -eq 1 ]] || return 1
  printf '```\n\n' >>"$sum" || return 1
  if [[ "$rc" -ne 0 ]]; then
    echo "::error::§(c) gate chain refused the flip (sub_condition=${id}) - the preconditions are not met (or could not be proven). NOTHING planned, NOTHING applied."
    if [[ "$id" == *_soak_days_below_floor ]]; then
      echo "::error::a configured soak value is below the 3-day floor; delete it from Doppler prd (#12933, Operator-authorizes) - the floor cannot be shortened, values may only lengthen it"
    fi
    printf -- '- per-instance soak grader: NOT RUN (gate refused)\n' >>"$sum" || return 1
    return 1
  fi
  return 0
}

# sse_gate_chain_verify <stderr-file> <gated-host> — the pass re-check (anti-vacuity). For each soak kind: exactly one
# grammar line, for this host, verdict=pass sub_condition=none, an ISO marker_at, integer age_s and required_s,
# required_s >= SOAK_FLOOR_S and age_s >= required_s. Anything else is a code defect, never a soak wait.
sse_gate_chain_verify() {
  local f="$1" host="$2" k l n line a r re_full="^${SOAK_EV_RE}\$" re_pass
  [[ -r "$f" ]] || { echo "::error::§(c) gate chain: the captured gate stderr ($f) is missing - a wiring defect, do not re-dispatch"; return 1; }
  if [[ ! "$host" =~ ^[a-z][a-z0-9-]{0,30}$ ]]; then
    echo "::error::§(c) gate chain: the gated host is malformed - a wiring defect, do not re-dispatch"
    return 1
  fi
  for k in git_data workspaces_luks; do
    n=0; line=""
    while IFS= read -r l || [[ -n "$l" ]]; do
      [[ "$l" =~ $re_full ]] || continue
      [[ "$l" == "SOLEUR_SOAK_EVIDENCE kind=${k} "* ]] || continue
      n=$((n + 1)); line="$l"
    done <"$f"
    re_pass="^SOLEUR_SOAK_EVIDENCE kind=${k} host=${host} soak_days=[1-9][0-9]{0,2} source=(default|env) floor_days=[1-9][0-9]{0,2} marker_at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z age_s=([0-9]{1,12}) required_s=([0-9]{1,12}) verdict=pass sub_condition=none\$"
    a=""; r=""
    if [[ "$n" -eq 1 && "$line" =~ $re_pass ]]; then a="${BASH_REMATCH[2]}"; r="${BASH_REMATCH[3]}"; fi
    if [[ -z "$a" || -z "$r" ]] || (( 10#$r < SOAK_FLOOR_S || 10#$a < 10#$r )); then
      echo "::error::§(c) gate chain: gate passed but soak evidence for kind=${k} is missing or malformed - a code defect, not a soak wait; do not re-dispatch"
      return 1
    fi
  done
  return 0
}

# sse_gate_chain_check <stderr-file> <gated-host> <gate-rc> — mirror, then (rc 0 only) the pass re-check. The step
# calls the two halves separately because its own flip-marker check sits between them; this composite is the same
# contract in one call (a refusal can never come back 0).
sse_gate_chain_check() {
  sse_gate_chain_mirror "$1" "$2" "$3" || return 1
  [[ "$3" -eq 0 ]] || return 1
  sse_gate_chain_verify "$1" "$2" || return 1
  return 0
}

# ---------------------------------------------------------------------------------------------------------------------
# _sse_instance_emit <rc|none> <VERDICT> — the one verdict line: stderr, plus a fenced copy in the summary.
_sse_instance_emit() {
  local line="SOLEUR_INSTANCE_SOAK host=${SSE_INSTANCE_HOST} grader=${SSE_GRADER_NAME} rc=$1 verdict=$2"
  SSE_INSTANCE_DONE=1
  printf '%s\n' "$line" >&2
  # shellcheck disable=SC2016 # the backticks are the markdown fence, not an expansion
  printf '### per-instance soak grader (serve only)\n\n```text\n%s\n```\n\n' "$line" >>"${GITHUB_STEP_SUMMARY:-/dev/null}" || return 1
  return 0
}

# The EXIT/TERM backstop: a cancel, a timeout or an abort while the grader's output is buffering still leaves a line.
_sse_instance_trap() {
  if [[ "${SSE_INSTANCE_DONE:-0}" -ne 1 ]]; then _sse_instance_emit none CANNOT_ESTABLISH || true; fi
}

# sse_instance_soak <gated-host> <grader-path> — run the per-instance soak grader and refuse unless it says PASS.
sse_instance_soak() {
  case "$-" in
    *x*) echo "::error::per-instance soak grader refuses to run under xtrace (it would print the Better Stack credentials) - a wiring defect, do not re-dispatch"
         return 78 ;;
  esac
  local host="$1" grader="$2" rc=0 grade first verdict next
  SSE_INSTANCE_DONE=0
  SSE_INSTANCE_HOST=invalid
  if [[ "$host" =~ ^[a-z][a-z0-9-]{0,30}$ ]]; then SSE_INSTANCE_HOST="$host"; fi
  trap _sse_instance_trap EXIT
  trap 'exit 143' TERM

  # until #12869: the grader reads only one host's probe rows (its rows library hardwires that host's Better Stack
  # host name), so any other gated host cannot be graded and fails closed without calling it.
  if [[ "$SSE_INSTANCE_HOST" != "$SSE_GRADED_HOST" ]]; then
    _sse_instance_emit none CANNOT_ESTABLISH || return 1
    echo "::error::per-instance soak grader: the gated host (${SSE_INSTANCE_HOST}) is not ${SSE_GRADED_HOST}; the grader reads only ${SSE_GRADED_HOST}'s probe rows until #12869. NOTHING planned, NOTHING applied."
    return 1
  fi

  # Only the names the grader reads (G10): the job's earlier steps export Terraform and Doppler credentials to
  # GITHUB_ENV. An empty SOLEUR_FT_EARLIEST means "no clock", so an unmet soak reads NOT YET, never a window FAIL.
  grade="$(env -i PATH="$PATH" HOME="${HOME-}" TMPDIR="${RUNNER_TEMP:-/tmp}" \
    BETTERSTACK_QUERY_HOST="${BETTERSTACK_QUERY_HOST-}" BETTERSTACK_QUERY_USERNAME="${BETTERSTACK_QUERY_USERNAME-}" \
    BETTERSTACK_QUERY_PASSWORD="${BETTERSTACK_QUERY_PASSWORD-}" SOLEUR_FT_EARLIEST= bash "$grader")" || rc=$?

  case "$rc" in
    0) verdict=PASS ;;
    1) verdict=FAIL ;;
    2) verdict=NOT_YET ;;
    *) verdict=CANNOT_ESTABLISH ;;
  esac
  # The grader's own first line, to the log only, and only when it is verdict-shaped: the grader is shared with the
  # sweeper, and GitHub reads workflow commands from stdout and stderr.
  first="${grade%%$'\n'*}"
  if [[ "$first" =~ ^(PASS|FAIL|NOT\ YET|CANNOT\ ESTABLISH):\ [^[:cntrl:]]*$ ]]; then
    printf 'grade_text=%s\n' "$first" >&2
  else
    printf 'grade_text=unprintable\n' >&2
  fi
  _sse_instance_emit "$rc" "$verdict" || return 1
  if [[ "$rc" -eq 0 ]]; then return 0; fi

  case "$verdict:$rc" in
    NOT_YET:*) next="NOT_YET: read the grader line above; if it says no GREEN web-2 readiness row and web-2 was created more than 90 days ago, replace the host (web-host-replace.md) and wait for the 3-day soak; otherwise wait or check web-2 probe telemetry" ;;
    FAIL:*) next="the soak of this instance is spoiled; investigate, a replace is the repair" ;;
    CANNOT_ESTABLISH:3) next="Better Stack credentials or the shared helper are missing" ;;
    *) next="a code or wiring defect; do not re-dispatch" ;;
  esac
  echo "::error::per-instance soak grader verdict=${verdict} rc=${rc} - NOTHING planned, NOTHING applied. ${next}"
  return 1
}
