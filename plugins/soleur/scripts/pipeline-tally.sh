#!/usr/bin/env bash
# pipeline-tally.sh — running tally of autonomous-pipeline work units (#9403).
#
# WHAT IT COUNTS, AND WHY UNITS
#
# Autonomous loops (one-shot, work, review, test-fix-loop, drain-*, resolve-*,
# eval-harness) spend real work — review seats spawned, CI cycles, fix rounds,
# agent rounds — but print no running tally, so the cost shape of a run is only
# ever discovered post-hoc (inciting incident: PR #9339, an 11-seat review and
# ~8 CI cycles for a small fix). This script is the measuring instrument: a
# per-branch counter file under the session-state root, mutated only through
# the subcommands below.
#
# The counters are UNITS OF WORK, never money — the honest currency for
# zero-marginal Max-subscription runs (#5086 doctrine, ADR-056). No currency
# or price token appears in any output, by design and by sentinel.
#
# COUNTER FILE
#
#   <session-state-root>/counters/<slug>
#
#   <session-state-root> = _session_state_root() from scripts/lib/session-state.sh
#     (SOLEUR_SESSION_STATE_ROOT override, else <git-common-dir>/
#     soleur-session-state, else the /tmp/soleur-session-state-orphan fallback;
#     under the orphan fallback the counters dir gains a -<repo-basename>
#     suffix so two checkouts cannot collide).
#   <slug> = branch name sanitized — every char outside [A-Za-z0-9._-] becomes
#     '-' (the _safe_worktree_name transform, generalized; session-state.sh does
#     not export it, so the transform is replicated here). Detached HEAD writes
#     `HEAD`. hooks/stop-hook.sh reads this ledger via `show` — no second path
#     resolver exists.
#
#   Flat key=value lines, rewritten wholesale under with_lock:
#     seats / ci_cycles / fix_rounds / agent_rounds   (counts, default 0)
#     cap_<dim>=N      (0 = unset — persisted at init so caps survive
#                       skill-to-skill handoff; argv dies at skill boundaries)
#     warned_<dim>=N   (count at which WARN first fired; 0 = never)
#     capped=<dim>     (empty, or the dim that hit its hard cap)
#
# CANONICAL PER-SKILL CALL-OUT BLOCK — copy verbatim into each instrumented
# SKILL.md (the components.test.ts sentinel anchors on these call forms;
# comment-only mentions of this file do not satisfy it):
#
#   # --- Pipeline tally (soleur #9403) ---
#   TALLY="${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-tally.sh"
#   bash "$TALLY" init                            # once, at skill start (merge-safe)
#   bash "$TALLY" show                            # at every phase boundary
#   bash "$TALLY" incr <dim> [n]                  # after each counted operation
#   VERDICT="$(bash "$TALLY" gate <dim>)"         # BEFORE each expensive step
#   # VERDICT == STOP → write specs/<branch>/session-state.md with a
#   #   `budget-capped` marker + resume prompt, then exit the phase cleanly —
#   #   classified stop, never a blocking prompt in an unattended run (#8611).
#   # VERDICT == WARN → continue; the crossing is recorded in the ledger.
#   # VERDICT == UNKNOWN → substrate unreadable; caps unenforced (ship renders
#   #   `cap-unenforced`). Every call exits 0 — the tally is fail-open by
#   #   contract and must never red a pipeline.
#
# DIMENSIONS: seats | ci_cycles | fix_rounds | agent_rounds
# (`ci-cycles` is accepted as an alias for `ci_cycles` everywhere a dim is
# taken). One writer per dimension per skill invocation — a prose `incr` and a
# workflow `counts:` post for the same dim never both fire.
#
# SUBCOMMANDS
#
#   init [--reset] [--branch <b>]
#        [--max-seats N] [--max-ci-cycles N] [--max-fix-rounds N]
#        [--max-agent-rounds N]
#     Idempotent MERGE: creates the file if absent, preserves counters, merges
#     --max-* flags into cap_<dim>. Prints `tally-init: <slug> <outcome>` where
#     outcome ∈ fresh | continued | reset | capped-reset | stale-reset:
#       fresh         no file existed; new ledger created
#       continued     existing ledger kept; argv caps merged. A capped ledger
#                     prints `continued capped=<dim>` — the latch is visible.
#       reset         --reset given: counts/warned/capped cleared
#       capped-reset  ledger carried capped AND new --max-* caps were supplied —
#                     the raised-cap resume path; latch AND warned_* cleared,
#                     counts preserved
#       stale-reset   ledger file untouched for >24h (mtime — inactivity, not
#                     age, so a multi-day run still counting survives): fresh
#                     ledger. Stale beats capped — a stale-ledger continuation
#                     must not STOP a fresh run by accident.
#     CAP SEMANTICS: a ledger carrying `capped` is NOT reset by a bare `init` —
#     it reports `continued` and `capped` persists, so the next `gate` still
#     returns STOP (a budget-capped run cannot be accidentally resumed under
#     the same caps; livelock impossible). `capped` clears only via an explicit
#     `--reset` or by supplying new --max-* caps. Reset clears the LEDGER, never
#     the budget: cap_<dim> values survive every reset form unless the argv
#     overrides them; to drop caps entirely, remove the counter file. Also
#     sweeps sibling counter files with mtime > 30 days.
#     Flag validation: values must match ^[1-9][0-9]*$ — non-numeric, negative,
#     zero and leading-zero forms (`08`) are rejected with
#     SOLEUR_TALLY_ERROR reason=bad-flag on stderr and exit 0.
#
#   incr <dim> [n] [--branch <b>]
#     Adds n (default 1, ^[0-9]+$ validated and 10#-normalized) to <dim> under
#     lock and prints the updated `tally:` line. Missing/unreadable file →
#     stderr SOLEUR_TALLY_ERROR reason=missing-file, stdout UNKNOWN, exit 0 —
#     NEVER auto-creates (auto-create would make an init-after-incr ordering
#     defect undetectable). `--branch <b>` posts to another branch's ledger
#     (fleet-skill item attribution).
#
#   show [--branch <b>]
#     Absent/unreadable file → UNKNOWN. Else prints
#     `tally: seats=N ci_cycles=N fix_rounds=N agent_rounds=N`, a `cap:<dim>=<n>`
#     token line when caps are set (the stop-hook floor reads this), and, when
#     any is set, `warned:<dim>=<at>` / `capped:<dim>=<cap>` tokens.
#
#   gate <dim> [--branch <b>]
#     Reads cap_<dim> from the FILE, never argv. Verdict on stdout:
#       STOP  capped is set (any dim), or count >= cap_<dim> (cap > 0);
#             sets capped=<dim> when empty — first cap wins, it is sticky
#       WARN  count >= ceil(cap*0.8); records warned_<dim>=count on first fire
#       OK    otherwise, including cap unset
#     Substrate failure (missing file, unreadable, no flock, lock contention)
#     → stdout UNKNOWN + stderr SOLEUR_TALLY_ERROR reason=<k>. Exit 0 always.
#     An UNKNOWN under configured caps is `cap-unenforced`, never a clean pass.
#
#   selfcheck
#     Prints SOLEUR_TALLY_OK, exits 0, writes NOTHING — handled before the lib
#     is sourced (session-state.sh creates its state dirs at source time), so
#     it is safe in a read-only sandbox with tmpfs HOME.
#
# STDERR DISCIPLINE: SOLEUR_TALLY_ERROR reason=<k> markers; reasons are
#   bad-flag | missing-file | unreadable | no-flock | lock-failed |
#   write-failed | lib-missing. Nothing else on stderr. `unreadable` covers a
#   file that exists but cannot be parsed as a ledger (no `seats=` key) — a
#   corrupt file must never render as the legitimate `tally: 0` ZERO state.
#
# EXIT: always 0 (fail-open — counters must never red a pipeline).
#
# macOS: util-linux flock is absent → with_lock unavailable → mutations and
# gates degrade to UNKNOWN (+reason=no-flock); `show` remains a pure read.
# Documented limitation until the session-state flock polyfill lands.

# selfcheck fast-path BEFORE sourcing the lib — see header (write-free).
if [[ "${1:-}" == "selfcheck" ]]; then
  printf 'SOLEUR_TALLY_OK\n'
  exit 0
fi

# Deliberately NOT `set -euo pipefail`: every subcommand is contractually
# fail-open (exit 0 even on internal error), so all failure surfaces below are
# explicit checks returning through the SOLEUR_TALLY_ERROR path instead.
# Every expansion that can be unset is defaulted (${var:-}).

TALLY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P || true)"
TALLY_LIB="${TALLY_SCRIPT_DIR}/lib/session-state.sh"
if [[ -r "$TALLY_LIB" ]]; then
  # shellcheck source=lib/session-state.sh
  . "$TALLY_LIB" || true
fi

_tally_err() { printf 'SOLEUR_TALLY_ERROR reason=%s\n' "$1" >&2; }

# Owning trap for _tally_write's mktemp allocation (lint-trap-ownership): the
# write is tmp+mv atomic; a die between alloc and mv would leak <$file>.tmp.*.
_TALLY_TMP=""
trap 'rm -f "${_TALLY_TMP:-}"' EXIT

# Every char outside [A-Za-z0-9._-] becomes '-'. Generalizes
# _safe_worktree_name (worktree-manager.sh) — NOT byte-identical to it
# (`tr '/' '-'` vs full-class), but leases and counters are disjoint
# namespaces so the divergence is safe.
_tally_slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'; }

# Canonicalize a dim token -> seats|ci_cycles|fix_rounds|agent_rounds, or fail.
_tally_dim() {
  case "$1" in
    seats|ci_cycles|fix_rounds|agent_rounds) printf '%s' "$1" ;;
    ci-cycles) printf 'ci_cycles' ;;
    *) return 1 ;;
  esac
}

# _tally_paths <branch-or-empty> -> T_SLUG T_COUNTERS_DIR T_FILE (rc 1 = no root)
_tally_paths() {
  local branch="${1:-}"
  if [[ -z "$branch" ]]; then
    branch=$(git branch --show-current 2>/dev/null || true)
    [[ -n "$branch" ]] || branch="HEAD"
  fi
  T_SLUG=$(_tally_slug "$branch")
  local root=""
  if command -v _session_state_root >/dev/null 2>&1; then
    root=$(_session_state_root 2>/dev/null || true)
  fi
  if [[ -z "$root" ]]; then
    T_COUNTERS_DIR=""; T_FILE=""
    return 1
  fi
  T_COUNTERS_DIR="$root/counters"
  if [[ "$root" == "/tmp/soleur-session-state-orphan" ]]; then
    # Orphan fallback (not a git repo): suffix the counters dir with the repo
    # basename so counters from different checkouts cannot collide.
    local base
    base=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")")
    T_COUNTERS_DIR="$root/counters-$(_tally_slug "$base")"
  fi
  T_FILE="$T_COUNTERS_DIR/$T_SLUG"
  return 0
}

# Field read: grep+cut, the substrate's own idiom (no jq). Always rc 0.
_tally_field() {
  grep "^$2=" "$1" 2>/dev/null | head -1 | cut -d= -f2-
  return 0
}

# Is this a parseable ledger? `seats=` is the first key every write emits; a
# file that lacks it is corrupt/partial and must be reported `unreadable`
# rather than silently re-read as an all-zero tally (which would masquerade as
# the legitimate "instrumented, nothing counted" ZERO state). A cap_* carrying
# a non-numeric value is corrupt too — it would load as 0 and render a
# budget that looks configured but silently never enforces.
_tally_ledger_ok() {
  [[ -f "$1" && -r "$1" ]] || return 1
  grep -q '^seats=' "$1" 2>/dev/null || return 1
  if grep -vE '^(seats|ci_cycles|fix_rounds|agent_rounds|capped)=' "$1" \
     | grep -qE '^(cap_|warned_)[a-z_]+=[^0-9]' 2>/dev/null; then
    return 1
  fi
  return 0
}

# Indirect get/set on the T_* ledger vars (bash 3.2-safe; keys are whitelisted).
_tally_getf() { local _r="T_$1"; printf '%s' "${!_r}"; }
_tally_setf() { printf -v "T_$1" '%s' "$2"; }

# Load the ledger into T_* globals; missing/corrupt fields default to 0/empty.
_tally_load() {
  local k v
  for k in seats ci_cycles fix_rounds agent_rounds \
           cap_seats cap_ci_cycles cap_fix_rounds cap_agent_rounds \
           warned_seats warned_ci_cycles warned_fix_rounds warned_agent_rounds; do
    v=""
    [[ -r "$1" ]] && v=$(_tally_field "$1" "$k")
    [[ "$v" =~ ^[0-9]+$ ]] || v=0
    _tally_setf "$k" "$((10#$v))"
  done
  T_capped=""
  if [[ -r "$1" ]]; then
    T_capped=$(_tally_field "$1" capped)
  fi
  return 0
}

# Wholesale rewrite. tmp+mv in the same dir so a crash never leaves a torn
# ledger; the lock (held by callers) orders concurrent writers.
_tally_write() {
  local tmp
  mkdir -p "$(dirname "$1")" 2>/dev/null || true
  tmp=$(mktemp "$1.tmp.XXXXXX" 2>/dev/null) || return 1
  _TALLY_TMP="$tmp"
  cat > "$tmp" <<EOF
seats=$(_tally_getf seats)
ci_cycles=$(_tally_getf ci_cycles)
fix_rounds=$(_tally_getf fix_rounds)
agent_rounds=$(_tally_getf agent_rounds)
cap_seats=$(_tally_getf cap_seats)
cap_ci_cycles=$(_tally_getf cap_ci_cycles)
cap_fix_rounds=$(_tally_getf cap_fix_rounds)
cap_agent_rounds=$(_tally_getf cap_agent_rounds)
warned_seats=$(_tally_getf warned_seats)
warned_ci_cycles=$(_tally_getf warned_ci_cycles)
warned_fix_rounds=$(_tally_getf warned_fix_rounds)
warned_agent_rounds=$(_tally_getf warned_agent_rounds)
capped=$T_capped
EOF
  if ! mv "$tmp" "$1" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null || true
    _TALLY_TMP=""
    return 1
  fi
  _TALLY_TMP=""
  return 0
}

_tally_print_line() {
  printf 'tally: seats=%s ci_cycles=%s fix_rounds=%s agent_rounds=%s\n' \
    "$(_tally_getf seats)" "$(_tally_getf ci_cycles)" \
    "$(_tally_getf fix_rounds)" "$(_tally_getf agent_rounds)"
}

# Reap sibling counter files older than 30 days (mtime) — opportunistic
# housekeeping inside init; never fatal, never the current file's problem.
# Runs under THIS slug's lock while touching sibling files — benign: only
# mtime>30d files die, and incr's in-lock existence re-check covers the race.
_tally_sweep() {
  [[ -n "${T_COUNTERS_DIR:-}" && -d "$T_COUNTERS_DIR" ]] || return 0
  find "$T_COUNTERS_DIR" -maxdepth 1 -type f -mtime +30 -delete 2>/dev/null || true
  return 0
}

# Run an impl under the branch-scoped lock. rc 1 + UNKNOWN + marker on failure.
_tally_locked() {
  if ! command -v flock >/dev/null 2>&1; then
    _tally_err no-flock
    printf 'UNKNOWN\n'
    return 1
  fi
  if ! command -v with_lock >/dev/null 2>&1; then
    _tally_err lib-missing
    printf 'UNKNOWN\n'
    return 1
  fi
  if ! with_lock "pipeline-tally-$T_SLUG" 10 -- "$@"; then
    _tally_err lock-failed
    printf 'UNKNOWN\n'
    return 1
  fi
  return 0
}

# Cap values: ^[1-9][0-9]*$ — rejects non-numeric, negative, 0, and the
# leading-zero forms (`08`) that 10# would otherwise silently accept.
_tally_norm_cap() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]] || return 1
  printf '%s' "$((10#$1))"
}

# --- init -------------------------------------------------------------------

_tally_init_locked() {
  local reset="$1" caps_given="$2"
  local n_seats="$3" n_ci="$4" n_fix="$5" n_agent="$6"
  local existed=0 outcome
  [[ -f "$T_FILE" ]] && existed=1
  _tally_load "$T_FILE"

  # Staleness = 24h of INACTIVITY, keyed on file mtime, not a written key:
  # every incr/gate write bumps it, so a multi-day pipeline that crosses the
  # threshold while still counting never gets zeroed mid-run.
  local stale=0 mtime=0
  if (( existed )); then
    mtime=$(stat -c %Y "$T_FILE" 2>/dev/null || stat -f %m "$T_FILE" 2>/dev/null || echo 0)
    [[ "$mtime" =~ ^[0-9]+$ ]] && (( $(date +%s) - 10#$mtime > 86400 )) && stale=1
  fi

  if (( ! existed )); then
    outcome=fresh
  elif (( reset )); then
    outcome=reset
  elif (( stale )); then
    # Stale beats capped: a >24h-old ledger — even a capped one — is a
    # previous run's record; a fresh run must not inherit a foreign latch.
    outcome=stale-reset
  elif [[ -n "$T_capped" ]] && (( caps_given )); then
    outcome=capped-reset
  elif [[ -n "$T_capped" ]]; then
    # Budget-capped ledger + no raised caps: the ledger CONTINUES and `capped`
    # persists, so the next `gate` still returns STOP. See CAP SEMANTICS above.
    outcome="continued capped=$T_capped"
  else
    outcome=continued
  fi

  case "$outcome" in
    reset|stale-reset)
      # Fresh ledger — counts, warnings, capped cleared. cap_<dim> survive:
      # reset clears the ledger, never the budget.
      _tally_setf seats 0; _tally_setf ci_cycles 0
      _tally_setf fix_rounds 0; _tally_setf agent_rounds 0
      _tally_setf warned_seats 0; _tally_setf warned_ci_cycles 0
      _tally_setf warned_fix_rounds 0; _tally_setf warned_agent_rounds 0
      T_capped=""
      ;;
    capped-reset)
      # Same run continuing under a raised budget: clear the latch AND the
      # warned_* markers (they fired against the OLD cap and would annotate
      # the new budget falsely). Counts persist — the branch's cost record is
      # the tally the feature exists to report.
      T_capped=""
      _tally_setf warned_seats 0; _tally_setf warned_ci_cycles 0
      _tally_setf warned_fix_rounds 0; _tally_setf warned_agent_rounds 0
      ;;
  esac

  # Merge argv caps (unset dims keep whatever the ledger carries).
  [[ -n "$n_seats" ]] && _tally_setf cap_seats "$n_seats"
  [[ -n "$n_ci" ]] && _tally_setf cap_ci_cycles "$n_ci"
  [[ -n "$n_fix" ]] && _tally_setf cap_fix_rounds "$n_fix"
  [[ -n "$n_agent" ]] && _tally_setf cap_agent_rounds "$n_agent"

  _tally_write "$T_FILE" || { _tally_err write-failed; printf 'UNKNOWN\n'; return 0; }
  _tally_sweep
  printf 'tally-init: %s %s\n' "$T_SLUG" "$outcome"
  return 0
}

cmd_init() {
  local reset=0 caps_given=0 branch=""
  local n_seats="" n_ci="" n_fix="" n_agent="" v=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reset) reset=1; shift ;;
      --branch) branch="${2:-}"; [[ -n "$branch" ]] || { _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; }; shift 2 ;;
      --max-seats)
        v=$(_tally_norm_cap "${2:-}") || { _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; }
        n_seats=$v; caps_given=1; shift 2 ;;
      --max-ci-cycles)
        v=$(_tally_norm_cap "${2:-}") || { _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; }
        n_ci=$v; caps_given=1; shift 2 ;;
      --max-fix-rounds)
        v=$(_tally_norm_cap "${2:-}") || { _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; }
        n_fix=$v; caps_given=1; shift 2 ;;
      --max-agent-rounds)
        v=$(_tally_norm_cap "${2:-}") || { _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; }
        n_agent=$v; caps_given=1; shift 2 ;;
      *) _tally_err bad-flag; printf 'UNKNOWN\n'; return 0 ;;
    esac
  done
  _tally_paths "$branch" || { _tally_err lib-missing; printf 'UNKNOWN\n'; return 0; }
  _tally_locked _tally_init_locked "$reset" "$caps_given" "$n_seats" "$n_ci" "$n_fix" "$n_agent" || true
  return 0
}

# --- incr -------------------------------------------------------------------

_tally_incr_locked() {
  local dim="$1" n="$2"
  if [[ ! -f "$T_FILE" ]]; then
    _tally_err missing-file; printf 'UNKNOWN\n'; return 0
  fi
  if ! _tally_ledger_ok "$T_FILE"; then
    _tally_err unreadable; printf 'UNKNOWN\n'; return 0
  fi
  _tally_load "$T_FILE"
  _tally_setf "$dim" "$(( $(_tally_getf "$dim") + n ))"
  _tally_write "$T_FILE" || { _tally_err write-failed; printf 'UNKNOWN\n'; return 0; }
  _tally_print_line
  return 0
}

cmd_incr() {
  local dim="" n=1 n_set=0 branch=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --branch) branch="${2:-}"; [[ -n "$branch" ]] || { _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; }; shift 2 ;;
      -* ) _tally_err bad-flag; printf 'UNKNOWN\n'; return 0 ;;
      *)
        if [[ -z "$dim" ]]; then dim="$1"
        elif (( ! n_set )); then n="$1"; n_set=1
        else _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; fi
        shift ;;
    esac
  done
  dim=$(_tally_dim "${dim:-}") || { _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; }
  if [[ ! "$n" =~ ^[0-9]+$ ]]; then
    _tally_err bad-flag; printf 'UNKNOWN\n'; return 0
  fi
  n=$((10#$n))
  _tally_paths "$branch" || { _tally_err lib-missing; printf 'UNKNOWN\n'; return 0; }
  # Missing file is reported before any lock attempt: the error must fire even
  # where flock is unavailable, and `incr` NEVER creates the ledger.
  if [[ ! -f "$T_FILE" ]]; then
    _tally_err missing-file; printf 'UNKNOWN\n'; return 0
  fi
  _tally_locked _tally_incr_locked "$dim" "$n" || true
  return 0
}

# --- show -------------------------------------------------------------------

cmd_show() {
  local branch=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --branch) branch="${2:-}"; [[ -n "$branch" ]] || { _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; }; shift 2 ;;
      *) _tally_err bad-flag; printf 'UNKNOWN\n'; return 0 ;;
    esac
  done
  _tally_paths "$branch" || { _tally_err lib-missing; printf 'UNKNOWN\n'; return 0; }
  if [[ ! -f "$T_FILE" ]]; then
    _tally_err missing-file; printf 'UNKNOWN\n'; return 0
  fi
  if ! _tally_ledger_ok "$T_FILE"; then
    _tally_err unreadable; printf 'UNKNOWN\n'; return 0
  fi
  _tally_load "$T_FILE"
  _tally_print_line
  # Second line: configured caps (the stop-hook floor and ship's render both
  # consume this shape — `cap:<dim>=<n>` tokens).
  local caps="" d w c
  for d in seats ci_cycles fix_rounds agent_rounds; do
    c=$(_tally_getf "cap_$d")
    (( c > 0 )) && caps="${caps}cap:${d}=${c} "
  done
  [[ -n "$caps" ]] && printf '%s\n' "${caps% }"
  # Third line: warned/capped annotations, only when set.
  local ann=""
  for d in seats ci_cycles fix_rounds agent_rounds; do
    w=$(_tally_getf "warned_$d")
    [[ "$w" != "0" ]] && ann="${ann}warned:${d}=${w} "
  done
  [[ -n "$T_capped" ]] && ann="${ann}capped:${T_capped}=$(_tally_getf "cap_$T_capped")"
  ann="${ann% }"
  [[ -n "$ann" ]] && printf '%s\n' "$ann"
  return 0
}

# --- gate -------------------------------------------------------------------

_tally_gate_locked() {
  local dim="$1"
  if [[ ! -f "$T_FILE" ]]; then
    _tally_err missing-file; printf 'UNKNOWN\n'; return 0
  fi
  if ! _tally_ledger_ok "$T_FILE"; then
    _tally_err unreadable; printf 'UNKNOWN\n'; return 0
  fi
  _tally_load "$T_FILE"
  # A set `capped` is sticky and global: STOP regardless of which dim is asked.
  if [[ -n "$T_capped" ]]; then
    printf 'STOP\n'; return 0
  fi
  local cap count
  cap=$(_tally_getf "cap_$dim"); count=$(_tally_getf "$dim")
  if (( cap <= 0 )); then
    printf 'OK\n'; return 0
  fi
  if (( count >= cap )); then
    T_capped="$dim"
    # Best-effort persist: the verdict stands even if the write fails (the
    # next gate re-derives STOP from count >= cap).
    _tally_write "$T_FILE" || true
    printf 'STOP\n'; return 0
  fi
  local warn_thresh=$(( (cap * 8 + 9) / 10 ))   # ceil(cap * 0.8)
  if (( count >= warn_thresh )); then
    if [[ "$(_tally_getf "warned_$dim")" == "0" ]]; then
      _tally_setf "warned_$dim" "$count"   # at-count on first fire only
      _tally_write "$T_FILE" || true
    fi
    printf 'WARN\n'; return 0
  fi
  printf 'OK\n'
  return 0
}

cmd_gate() {
  local dim="" branch=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --branch) branch="${2:-}"; [[ -n "$branch" ]] || { _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; }; shift 2 ;;
      *)
        if [[ -z "$dim" ]]; then dim="$1"; else _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; fi
        shift ;;
    esac
  done
  dim=$(_tally_dim "${dim:-}") || { _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; }
  _tally_paths "$branch" || { _tally_err lib-missing; printf 'UNKNOWN\n'; return 0; }
  # Same ordering as cmd_incr: missing-file must win over no-flock.
  if [[ ! -f "$T_FILE" ]]; then
    _tally_err missing-file; printf 'UNKNOWN\n'; return 0
  fi
  _tally_locked _tally_gate_locked "$dim" || true
  return 0
}

# --- dispatch ---------------------------------------------------------------

_tally_usage() {
  cat >&2 <<'EOF'
usage: pipeline-tally.sh <subcommand> [args]

  init [--reset] [--branch <b>] [--max-seats N] [--max-ci-cycles N]
       [--max-fix-rounds N] [--max-agent-rounds N]
  incr <dim> [n] [--branch <b>]
  show [--branch <b>]
  gate <dim> [--branch <b>]
  selfcheck

dims: seats | ci_cycles (alias ci-cycles) | fix_rounds | agent_rounds
fail-open: every subcommand exits 0; errors are SOLEUR_TALLY_ERROR on stderr.
EOF
}

case "${1:-}" in
  init) shift; cmd_init "$@" ;;
  incr) shift; cmd_incr "$@" ;;
  show) shift; cmd_show "$@" ;;
  gate) shift; cmd_gate "$@" ;;
  -h|--help|"") _tally_usage ;;
  *) _tally_err bad-flag; _tally_usage ;;
esac
exit 0
