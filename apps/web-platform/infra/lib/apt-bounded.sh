# shellcheck shell=bash
# Sourced, never executed. Bounded apt for the git-data suites' fixture containers (#9379).
#
# WHY. The #8744 loop bounded the NUMBER of apt attempts (3, Acquire::Retries=5 inside each)
# and not their elapsed time, so one stalled archive fetch could eat a whole suite budget and
# surface as a bare rc=124 kill with an empty log. This puts ONE budget of apt seconds on every
# in-container apt cycle, shared across every container a suite spawns, and makes expiry produce
# exactly what apt exhaustion produced before: a credential-scrubbed log tail, a cause line, the
# bare FIXTURE_APT_FAILED marker, exit 100. Every existing consumer classifier is unchanged, and
# no arm that was fail-closed becomes a skip (ADR-188 amendment, #9379; #8744 keeps ownership hard).
#
# WHY APT-SECONDS AND NOT A WALL-CLOCK DEADLINE. A first cut armed one absolute epoch deadline.
# Measured on a real run, the suite's NON-apt container time (the T5 tarball downloads, sshd) spent
# that budget too, so later healthy primary arms inherited an expired deadline and starved. The
# shared state is therefore a host-owned directory mounted into every container: `budget` (apt
# seconds the suite may spend in total) and `spent` (one line appended per attempt). Only time
# inside the apt cycle is charged.
#
# TWO HALVES.
#   host      gd_apt_state_arm <state-dir> <budget-seconds>   idempotent; creates the state dir, copies
#             this file into it, writes budget/spent; exports GD_APT_STATE. Call it directly (never as
#             `$(...)`, which discards the export), immediately before each apt-bearing `docker run`,
#             which then mounts `-v "$GD_APT_STATE:/work/apt"`.
#             gd_apt_state_summary                            one `GD_APT: spent=..` line for the log
#   container . /work/apt/apt-bounded.sh || exit 97
#             gd_apt_install_bounded <pkg>... || exit $?
#
# A stalled attempt is killed at GD_APT_ATTEMPT_CAP (default 90 s) and retried, up to 3 attempts, all
# inside the shared budget.
#
# CONTRACT (return codes of gd_apt_install_bounded).
#   0    installed
#   100  environment decline: the shared budget is spent or expired mid-cycle, OR apt itself failed
#        (apt's own rc is 100) on every attempt. FIXTURE_APT_FAILED is the last stderr line.
#   98   state dir missing/unarmed (a site forgot the mount). A harness defect, NEVER 100: there is
#        deliberately no self-armed fallback that would hide the omission.
#   other  apt's own rc when it is not 100 (e.g. 137 from an OOM kill that was not a timeout).
#        Not retried, no marker: 100 sits in every consumer's environment allowlist, and mapping an
#        OOM kill onto it would turn a harness defect into a green skip (the S1 driver records it).
# Callers load the lib as its OWN statement ending in `exit 97` (never in an && chain ending in
# `|| exit 100`: a missing mount must not be able to read as the environment decline).
#
# Discipline: `return`, not `exit`; no option changes; rc captured as `|| rc=$?` so the function
# is correct under `set -e` (R4's driver runs without it, the other four with it).

_GD_APT_LIB_SELF="${BASH_SOURCE[0]}"

gd_apt_state_arm() {
  [ -n "${GD_APT_STATE:-}" ] && return 0
  local dir="${1:?gd_apt_state_arm needs a state dir}" budget="${GD_APT_SUITE_BUDGET:-${2:?gd_apt_state_arm needs a budget in seconds}}"
  case "$budget" in ''|*[!0-9]*) echo "GD_APT: budget '${budget}' is not an integer" >&2; return 2 ;; esac
  mkdir -p "$dir" || return 2
  cp "$_GD_APT_LIB_SELF" "$dir/apt-bounded.sh" || return 2
  printf '%s\n' "$budget" > "$dir/budget"; : > "$dir/spent"
  chmod -R a+rwX "$dir"
  GD_APT_STATE="$dir"; export GD_APT_STATE
  echo "GD_APT: armed budget=${budget}s of apt time, shared across every apt-bearing container" >&2
}

gd_apt_state_summary() {
  [ -n "${GD_APT_STATE:-}" ] || return 0
  printf 'GD_APT: spent=%ss of budget=%ss across %s apt attempt(s)\n' \
    "$(awk '{s += $1} END {print s + 0}' "$GD_APT_STATE/spent")" "$(cat "$GD_APT_STATE/budget")" "$(wc -l < "$GD_APT_STATE/spent" | tr -d ' ')"
}

# Container: the 20-line credential-scrubbed tail (apt error text can embed proxy user:pass@host),
# then a cause line, then (decline only) the bare marker. All on stderr: docker demuxes the two
# streams, so a marker on stdout could land BEFORE the diagnostics it follows (measured, #8744).
_gd_apt_scrubbed_tail() {
  tail -n 20 "$1" 2>/dev/null | sed -e 's#//[^/@[:space:]]*:[^/@[:space:]]*@#//***:***@#g' -e 's#//[^/@[:space:]:]*@#//***@#g' >&2
}

gd_apt_install_bounded() {
  local dir="${GD_APT_STATE_DIR:-/work/apt}" budget
  budget="$(cat "$dir/budget" 2>/dev/null || true)"
  case "$budget" in
    ''|*[!0-9]*) echo "GD_APT: no armed apt budget at ${dir} — the site forgot the state mount" >&2; return 98 ;;
  esac
  local log="${GD_APT_LOG:-/tmp/apt-fixture.log}" stagef="${GD_APT_LOG:-/tmp/apt-fixture.log}.stage"
  local -a backoffs; read -r -a backoffs <<< "${GD_APT_BACKOFFS:-10 30}"
  # PER-ATTEMPT CAP. Measured on a live run (the incident this exists for): one container's apt cycle
  # stalled ~285 s although Acquire::http::Timeout=20 and Retries=5 were set, and a shared budget alone
  # then let that one stall starve every later container. A stalled attempt is killed at the cap and
  # retried on a fresh connection, while the shared budget still bounds the total.
  local cap="${GD_APT_ATTEMPT_CAP:-90}"
  local spent_before try=1 left allot started rc stage=none cause="" sl dt=0
  spent_before="$(awk '{s += $1} END {print s + 0}' "$dir/spent")"
  : > "$log"
  while :; do
    left=$(( budget - $(awk '{s += $1} END {print s + 0}' "$dir/spent") ))
    if [ "$left" -le 0 ]; then cause=timeout; rc=124; stage=none; break; fi
    allot="$left"; [ "$cap" -lt "$allot" ] && allot="$cap"
    started=$(date +%s); rc=0; : > "$stagef"
    # ONE timeout per attempt around the whole pair: the `&&` is the final status inside bash -c,
    # so there is no per-call cap to clamp and no AND-OR errexit hazard. -k 5 reaps a TERM-ignoring
    # apt (the group is killed, so a spawned dpkg child cannot orphan).
    # shellcheck disable=SC2016  # the script is deliberately single-quoted: it expands inside bash -c
    timeout -k 5 "$allot" bash -c '
      sf="$1"; shift; echo update > "$sf"
      apt-get update -qq -o Acquire::Retries=5 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 \
        && { echo install > "$sf"; apt-get install -y -qq -o Acquire::Retries=5 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 "$@"; }
    ' _ "$stagef" "$@" >> "$log" 2>&1 || rc=$?
    dt=$(( $(date +%s) - started ))
    printf '%s\n' "$dt" >> "$dir/spent"   # charge the attempt whatever its outcome
    [ "$rc" -eq 0 ] && return 0
    stage="$(cat "$stagef" 2>/dev/null || true)"; [ -n "$stage" ] || stage=update
    sl=0
    # 124 = timeout fired and the child exited on TERM; 137 = it needed the -k KILL. An OOM kill is
    # ALSO 137, so rc alone cannot tell them apart: the elapsed >= allotted test is required.
    if { [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; } && [ "$dt" -ge "$allot" ]; then
      cause=timeout                                  # a stall: retry on a fresh connection if budget and attempts remain
      [ "$allot" -ge "$left" ] && break              # it spent the rest of the shared budget
    elif [ "$rc" -ne 100 ]; then cause=apt-rc; break
    else
      cause=apt-error                                # apt's own failure rc: retry with backoff
      sl="${backoffs[$(( try - 1 ))]:-0}"
    fi
    [ "$try" -ge 3 ] && break
    left=$(( budget - $(awk '{s += $1} END {print s + 0}' "$dir/spent") )); [ "$sl" -gt "$left" ] && sl="$left"
    if [ "$sl" -gt 0 ]; then sleep "$sl"; printf '%s\n' "$sl" >> "$dir/spent"; fi   # a backoff is apt-cycle time
    try=$(( try + 1 ))
  done
  _gd_apt_scrubbed_tail "$log"
  echo "FIXTURE_APT_CAUSE: ${cause} stage=${stage} attempt=${try} attempt_secs=${dt} spent_before=${spent_before}s budget=${budget}s rc=${rc}" >&2
  case "$cause" in
    timeout|apt-error) echo FIXTURE_APT_FAILED >&2; return 100 ;;
  esac
  return "$rc"
}
