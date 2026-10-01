# shellcheck shell=bash
# Sourced, never executed. Bounded apt for the git-data suites' fixture containers (#9379).
#
# WHY. The #8744 loop bounded the NUMBER of apt attempts (3, Acquire::Retries=5 inside each)
# and not their elapsed time, so one stalled apt fetch could eat a whole suite budget and
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
# A stalled attempt is killed at GD_APT_ATTEMPT_CAP (default 90 s) and retried, up to 3 attempts, all
# inside the shared budget. Measured: about one apt cycle in three stalled for the full allotted time
# although apt's own Acquire timeouts were set, and a fresh attempt succeeded in about 15 s.
#
# TWO HALVES.
#   host      gd_apt_state_arm <state-dir> <budget-seconds>   idempotent ON DISK (a second call, even from a
#             subshell, finds `budget` and changes nothing); creates the state dir, copies this file into it,
#             writes budget/spent; exports GD_APT_STATE. Returns non-zero on a bad budget or an unwritable
#             dir, which callers must treat as a harness defect. Call it immediately before each apt-bearing
#             `docker run`, which then mounts `-v "$GD_APT_STATE:/work/apt"` (read-write: the container
#             appends to `spent`).
#             gd_apt_state_summary                            one `GD_APT: spent=..` line for the log
#   container . /work/apt/apt-bounded.sh || exit 97
#             gd_apt_install_bounded <pkg>... || exit $?
#
# CONTRACT (return codes of gd_apt_install_bounded).
#   0    installed
#   100  environment decline: the shared budget is spent or expired mid-cycle, OR apt itself failed
#        (apt's own rc is 100) on every attempt. FIXTURE_APT_FAILED is the last stderr line.
#   98   state dir missing/unarmed (a site forgot the mount). A harness defect, NEVER 100: there is
#        deliberately no self-armed fallback that would hide the omission.
#   other  apt's own rc when it is not 100 (e.g. 137 from an OOM kill that was not a timeout).
#        Not retried, no marker: 100 sits in the environment allowlists of the rehearsal suite's skip-eligible
#        arms, and mapping an OOM kill onto it would turn a harness defect into a green skip.
# Callers load the lib as its OWN statement ending in `exit 97` (never in an && chain ending in
# `|| exit 100`: a missing mount must not be able to read as the environment decline), and pass the helper's rc
# through (`|| exit $?`): a hardcoded 100 would launder 97/98/137 into the decline.
#
# KNOWN LIMITS (accepted, recorded in the ADR-188 amendment). `timeout -k 5` signals the process GROUP
# with TERM but tracks only its direct child for the KILL, so an apt that ignores TERM is not reaped
# (real apt dies on TERM). A cap kill landing mid-dpkg can leave "dpkg was interrupted" for the next attempt;
# no `dpkg --configure -a` repair is run because the unit suite executes this on the host. An OOM kill (137)
# that lands at or after the cap is indistinguishable from a timeout kill by rc and is classed as one.
#
# Discipline: `return`, not `exit` (the one exception is assert_fixture_dir below); no option changes; rc
# captured as `|| rc=$?` so the function is correct under `set -e` (R4's driver runs without it).

# Canonical fixture-dir guard, copied byte-for-byte from the repo's hook suites (the fixture-relative
# ratchet recognises only this exact text; an inline `case` is not accepted). `exit 2` is deliberate here:
# an empty or relative state path is a harness defect and must end the shell with a FATAL line, never
# fall through to a write that retargets the cwd or the filesystem root.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

_GD_APT_LIB_SELF="${BASH_SOURCE[0]}"

# Sum of the `spent` ledger. awk, not bash arithmetic: a garbled line counts as 0 instead of aborting the shell.
_gd_apt_spent() { awk '{s += $1} END {print s + 0}' "$1/spent" 2>/dev/null; }

gd_apt_state_arm() {
  local dir="${1:?gd_apt_state_arm needs a state dir}" budget="${2:?gd_apt_state_arm needs a budget in seconds}"
  assert_fixture_dir "$dir"
  case "$budget" in ''|*[!0-9]*) echo "GD_APT: budget '${budget}' is not an integer" >&2; return 2 ;; esac
  budget=$(( 10#$budget ))   # a leading zero would otherwise read as octal downstream
  if [ -r "$dir/budget" ]; then GD_APT_STATE="$dir"; export GD_APT_STATE; return 0; fi   # already armed on disk
  mkdir -p "$dir" || return 2
  cp "$_GD_APT_LIB_SELF" "$dir/apt-bounded.sh" || return 2
  printf '%s\n' "$budget" > "$dir/budget" || return 2
  : > "$dir/spent" || return 2
  chmod -R a+rwX "$dir"
  GD_APT_STATE="$dir"; export GD_APT_STATE
  echo "GD_APT: armed budget=${budget}s of apt time, shared across every apt-bearing container" >&2
}

gd_apt_state_summary() {
  [ -n "${GD_APT_STATE:-}" ] || return 0
  printf 'GD_APT: spent=%ss of budget=%ss across %s apt attempt(s)\n' \
    "$(_gd_apt_spent "$GD_APT_STATE")" "$(cat "$GD_APT_STATE/budget")" "$(wc -l < "$GD_APT_STATE/spent" | tr -d ' ')"
}

# Container: the 20-line credential-scrubbed tail (apt error text can embed proxy user:pass@host), then a cause
# line, then (decline only) the bare marker. All on stderr: docker demuxes the two streams, so a marker on
# stdout could land BEFORE the diagnostics it follows (measured, #8744). The scrub cuts a URL authority at its
# LAST `@` (a password may itself contain `@` or `/`), also masks scheme-less `user:pass@host` and
# Authorization headers; a retention row in the unit suite pins that an ordinary archive URL survives.
_gd_apt_scrubbed_tail() {
  tail -n 20 "$1" 2>/dev/null | sed -E \
    -e 's#//[^[:space:]]*@#//***@#g' \
    -e 's#(^|[[:space:]])[A-Za-z0-9._~%-]+:[^[:space:]@/]+@#\1***:***@#g' \
    -e 's#([Aa]uthorization:[[:space:]]*[A-Za-z]+)[[:space:]]+[^[:space:]]+#\1 ***#g' >&2
}

gd_apt_install_bounded() {
  local dir="${GD_APT_STATE_DIR:-/work/apt}" budget
  budget="$(cat "$dir/budget" 2>/dev/null || true)"
  case "$budget" in
    ''|*[!0-9]*) echo "GD_APT: no armed apt budget at ${dir} — the site forgot the state mount" >&2; return 98 ;;
  esac
  [ -r "$dir/spent" ] || { echo "GD_APT: ${dir}/spent is missing — the state dir is half-armed" >&2; return 98; }
  budget=$(( 10#$budget ))
  local log="${GD_APT_LOG:-/tmp/apt-fixture.log}"
  assert_fixture_dir "$dir"; assert_fixture_dir "$log"
  local -a backoffs; read -r -a backoffs <<< "${GD_APT_BACKOFFS:-10 30}"
  # PER-ATTEMPT CAP: an integer >= 1 (`timeout 0` means NO timeout, which would silently defeat the bound).
  local cap="${GD_APT_ATTEMPT_CAP:-90}"
  case "$cap" in ''|*[!0-9]*|0|0*) cap=90 ;; esac
  local spent_before try=1 left allot started rc stage=none cause="" sl dt=0
  spent_before="$(_gd_apt_spent "$dir")"
  : > "$log"
  while :; do
    left=$(( budget - $(_gd_apt_spent "$dir") ))
    if [ "$left" -le 0 ]; then cause=timeout; rc=124; stage=none; break; fi
    allot="$left"; [ "$cap" -lt "$allot" ] && allot="$cap"
    started=$(date +%s); rc=0
    # ONE timeout per attempt around the whole pair: the `&&` is the final status inside bash -c,
    # so there is no per-call cap to clamp and no AND-OR errexit hazard.
    # shellcheck disable=SC2016  # the script is deliberately single-quoted: it expands inside bash -c
    timeout -k 5 "$allot" bash -c '
      echo GD_APT_STAGE=update
      apt-get update -qq -o Acquire::Retries=5 \
        && { echo GD_APT_STAGE=install; apt-get install -y -qq -o Acquire::Retries=5 "$@"; }
    ' _ "$@" >> "$log" 2>&1 || rc=$?
    dt=$(( $(date +%s) - started )); [ "$dt" -lt 0 ] && dt=0   # a backward clock step must not refund budget
    printf '%s\n' "$dt" >> "$dir/spent"   # charge the attempt whatever its outcome
    [ "$rc" -eq 0 ] && return 0
    stage="$(grep -ao 'GD_APT_STAGE=[a-z]*' "$log" | tail -n 1 | cut -d= -f2 || true)"; [ -n "$stage" ] || stage=update
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
    left=$(( budget - $(_gd_apt_spent "$dir") ))
    [ "$sl" -ge "$left" ] && break                   # the backoff would consume the rest: no attempt could follow it
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
