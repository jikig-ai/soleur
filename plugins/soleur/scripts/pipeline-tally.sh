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
#     '-' — PLUS `-<sha1-6>` of the RAW branch name: `feat/x` and `feat-x`
#     sanitize identically and a shared ledger would let one branch's cap
#     latch starve a sibling. Detached HEAD writes `HEAD-<hash>`.
#     hooks/stop-hook.sh reads this ledger via `show` — no second path
#     resolver exists.
#
#   Flat key=value lines, rewritten wholesale under with_lock:
#     seats / ci_cycles / fix_rounds / agent_rounds   (counts, default 0)
#     cap_<dim>=N      (0 = unset — persisted at init so caps survive
#                       skill-to-skill handoff; argv dies at skill boundaries)
#     warned_<dim>=N   (level at which WARN first fired, ask included; 0 = never)
#     capped=<dim>     (empty, or the dim that hit its hard cap)
#
# CANONICAL PER-SKILL CALL-OUT BLOCK — the literal invocation every
# instrumented SKILL.md carries (the components.test.ts sentinel anchors on
# these call forms, comment-stripped — comment-only mentions do not satisfy it):
#
#   # --- Pipeline tally (soleur #9403) ---
#   bash "${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-tally.sh" init    # once, merge-safe
#   bash "${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-tally.sh" show    # phase boundary
#   bash "${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-tally.sh" incr <dim> [n]   # per op
#   VERDICT="$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-tally.sh" gate <dim> [n])"
#   # gate BEFORE each expensive step; [n] = the impending fan-out width so a
#   #   bulk spawn can't overshoot the cap unbounded (check-then-blast).
#   # VERDICT == STOP → write
#   #   knowledge-base/project/specs/<feature>/session-state.md with
#   #   appended `status: budget-capped` + a `budget-capped: <dim>=<n>/<cap>`
#   #   line + resume prompt, then exit the phase cleanly — classified stop,
#   #   never a blocking prompt in an unattended run (#8611). A parent detects
#   #   it via `grep -q budget-capped` on that file.
#   # VERDICT == WARN → continue; the crossing is recorded in the ledger.
#   # VERDICT == UNKNOWN → substrate unreadable; caps unenforced (ship renders
#   #   `cap-unenforced`). Every call exits 0 — the tally is fail-open by
#   #   contract and must never red a pipeline.
#
# COUNTING CONVENTIONS: `seats` = review-panel seats actually spawned (design
# pass included — `gate seats <panel-size>` before dispatch). `agent_rounds` =
# orchestration dispatches (one-shot child skills, drain items, resolver
# fan-outs). `fix_rounds` = fix/retry iterations. `ci_cycles` = CI runs the run
# itself drove (each push to the PR head). Heterogeneous units land on one dim
# by design — a cap reads as "work units", not a strict taxonomy.
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
#     outcome ∈ fresh | continued | reset | capped-reset | stale-reset |
#     repaired:
#       fresh         no file existed; new ledger created
#       continued     existing ledger kept; argv caps merged. A capped ledger
#                     prints `continued capped=<dim>` — the latch is visible.
#       reset         --reset given: counts/warned/capped cleared
#       capped-reset  ledger carried capped AND new --max-* caps were supplied —
#                     the raised-cap resume path; latch AND warned_* cleared,
#                     counts preserved. Beats stale-reset: an explicit raised
#                     cap is operator intent to continue THIS run; a bare init
#                     on the same stale file still stale-resets.
#       stale-reset   ledger file untouched for >24h (mtime — inactivity, not
#                     age: every gate read and every write refreshes it, so a
#                     multi-day run still counting survives): fresh ledger —
#                     a stale-ledger continuation must not STOP a fresh run
#                     by accident.
#       repaired      existing file failed ledger validation — rewritten
#                     clean (fail-open) with SOLEUR_TALLY_ERROR
#                     reason=unreadable; NEVER reported `continued`, because
#                     nothing readable was preserved.
#     CAP SEMANTICS: a ledger carrying `capped` is NOT reset by a bare `init` —
#     it reports `continued` and `capped` persists, so the next `gate` still
#     returns STOP (a budget-capped run cannot be accidentally resumed under
#     the same caps; livelock impossible). `capped` clears only via an explicit
#     `--reset` or by supplying new --max-* caps. Reset clears the LEDGER, never
#     the budget: cap_<dim> values survive every reset form unless the argv
#     overrides them; to drop caps entirely, remove the counter file. Also
#     sweeps sibling counter files with mtime > 30 days.
#     RATCHET GUARD: without --reset, a --max-* LOWER than a persisted nonzero
#     cap is refused and surfaced as a `cap-kept:` line (`cap-kept: <dim>=<kept>`) — a forwarded
#     or defaulted flag must not silently tighten the branch's budget.
#     Armed caps print as `armed: cap:<dim>=<n> …` on every init — a persisted
#     budget is never invisible.
#     Flag validation: values must match ^[1-9][0-9]{0,9}$ — non-numeric,
#     negative, zero, leading-zero forms (`08`), and digit strings that would
#     wrap mod-2^64 are rejected with SOLEUR_TALLY_ERROR reason=bad-flag on
#     stderr and exit 0. `--max-ci_cycles` (underscore) aliases --max-ci-cycles.
#
#   incr <dim> [n] [--branch <b>]
#     Adds n (default 1, ^[0-9]{1,10}$ validated and 10#-normalized) to <dim> under
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
#   gate <dim> [n] [--branch <b>]
#     Reads cap_<dim> from the FILE, never argv. Verdict on stdout:
#       STOP  capped is set (any dim), or count >= cap_<dim> (cap > 0);
#             sets capped=<dim> when empty — first cap wins, it is sticky.
#             With lookahead n: count+n > cap — STOP WITHOUT latching (a
#             smaller ask may still fit).
#       WARN  count+n >= ceil(cap*0.8); records warned_<dim> at the projected
#             level on first fire. (Caps <=4 warn and stop at the same count —
#             the warn band is empty there by construction.)
#       OK    otherwise, including cap unset
#     Substrate failure (missing file, unreadable, no flock, lock contention,
#     SOLEUR_DISABLE_SESSION_STATE kill-switch) → stdout UNKNOWN + stderr
#     SOLEUR_TALLY_ERROR reason=<k>. Exit 0 always.
#     An UNKNOWN under configured caps is `cap-unenforced`, never a clean pass.
#
#   selfcheck
#     Prints SOLEUR_TALLY_OK, exits 0, writes NOTHING — handled before the lib
#     is sourced (session-state.sh creates its state dirs at source time), so
#     it is safe in a read-only sandbox with tmpfs HOME.
#
# STDERR DISCIPLINE: SOLEUR_TALLY_ERROR reason=<k> markers; reasons are
#   bad-flag | bad-branch | missing-file | unreadable | no-flock | lock-failed |
#   lock-substrate-disabled | write-failed | lib-missing. `bad-branch` is the
#   _tally_paths refusal class (`--branch` token unsafe for a filename). Lock contention may
#   also print the substrate's own `[warn] lock contended` notice.
#   `unreadable` covers a file that exists but cannot be parsed as a ledger
#   (no `seats=` key, a non-numeric count/cap/warned value, or a capped token
#   outside the dim vocabulary) — a corrupt file must never render as the
#   legitimate `tally: 0` ZERO state.
#
# EXIT: always 0 (fail-open — counters must never red a pipeline).
#
# macOS: util-linux flock is absent → with_lock unavailable → mutations and
# gates degrade to UNKNOWN (+reason=no-flock); `show` remains a pure read.
# Documented limitation until the session-state flock polyfill lands.

# xtrace refusal — REQUIRED FIRST EXECUTABLE STATEMENT (lint-shell-trace-
# credential-refusal, unconditional arm): `_tally_getf` reads via `${!_r}`
# indirection, which the linter treats as runtime-named credential access —
# and `-x` prints expanded values. exit 78 is a refusal, not a failure
# surface, and precedes even the selfcheck fast-path.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

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

# Short discriminator appended to the slug: `feat/x` and `feat-x` slug identically,
# and a shared ledger would let one branch's cap latch starve a sibling. Hashing
# the RAW branch name keeps each branch's ledger its own.
_tally_shorthash() {
  local h
  h=$(printf '%s' "$1" | git hash-object --stdin 2>/dev/null | cut -c1-6)
  # `cut` exits 0 on empty input, so `||` alone can never reach the fallback —
  # test the captured hash instead (a git-less env would re-collide feat/x
  # and feat-x onto `feat-x-`).
  [[ -n "$h" ]] || h=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  printf '%s' "$h"
}


# Map _tally_paths rc -> the right error reason (1=bad-branch, 2=lib-missing).
_tally_paths_err() { case "$1" in 1) _tally_err bad-branch ;; *) _tally_err lib-missing ;; esac; }

# Canonicalize a dim token -> seats|ci_cycles|fix_rounds|agent_rounds, or fail.
_tally_dim() {
  case "$1" in
    seats|ci_cycles|fix_rounds|agent_rounds) printf '%s' "$1" ;;
    ci-cycles) printf 'ci_cycles' ;;
    *) return 1 ;;
  esac
}

# _tally_paths <branch-or-empty> -> T_SLUG T_COUNTERS_DIR T_FILE
# rc 1 = unsafe branch token refused; rc 2 = no session-state root.
# _tally_paths_err maps the rc to the right reason marker.
_tally_paths() {
  local branch="${1:-}"
  if [[ -z "$branch" ]]; then
    branch=$(git branch --show-current 2>/dev/null || true)
    [[ -n "$branch" ]] || branch="HEAD"
  fi
  T_SLUG=$(_tally_slug "$branch")-$(_tally_shorthash "$branch")
  # `.`/`..` survive the slug transform and would compose a path outside
  # counters/ (mv deposits the tmp file in the state root). Same refusal
  # class _validate_worktree_name applies; `--branch '-x'` is flag-eating.
  if [[ "$branch" == -* || "$T_SLUG" == .-* || "$T_SLUG" == ..-* ]]; then
    T_COUNTERS_DIR=""; T_FILE=""; T_SLUG=""
    return 1
  fi
  local root=""
  if command -v _session_state_root >/dev/null 2>&1; then
    root=$(_session_state_root 2>/dev/null || true)
  fi
  if [[ -z "$root" ]]; then
    T_COUNTERS_DIR=""; T_FILE=""
    return 2
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
# the legitimate "instrumented, nothing counted" ZERO state). Every count,
# cap_* and warned_* value must be PURE digits — a digit-prefixed corrupt like
# `cap_seats=5x` would pass a first-char check, load as 0, and render a budget
# that looks configured but silently never enforces. `capped=` is whitelisted
# to the dim vocabulary: a garbage latch would STOP every gate forever.
# Unknown keys (run_id, started_at from the old schema) are ignored.
_tally_ledger_ok() {
  [[ -f "$1" && -r "$1" ]] || return 1
  grep -q '^seats=' "$1" 2>/dev/null || return 1
  if grep -qvE '=[0-9]{1,18}$' \
     < <(grep -E '^(seats|ci_cycles|fix_rounds|agent_rounds|cap_[a-z_]+|warned_[a-z_]+)=' "$1" 2>/dev/null); then
    return 1
  fi
  # EVERY capped= line must carry the dim vocabulary or be empty — a duplicate
  # corrupt line after a clean one must not slip past a first-line read.
  if grep -qvE '^capped=(|seats|ci_cycles|fix_rounds|agent_rounds)$' \
     < <(grep -E '^capped=' "$1" 2>/dev/null); then
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
    # Sanitize: an unvetted latch value would reach indirect expansion in
    # `show` (`cap_$T_capped` -> invalid variable name) and mis-STOP gates.
    case "$T_capped" in
      ""|seats|ci_cycles|fix_rounds|agent_rounds) ;;
      *) T_capped="" ;;
    esac
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
  cat > "$tmp" <<EOF || { rm -f "$tmp"; _TALLY_TMP=""; return 1; }
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
  if [[ "${SOLEUR_DISABLE_SESSION_STATE:-}" == "1" ]]; then
    # Kill-switch sessions run with_lock's impl UNLOCKED (session-state.sh
    # _acquire_lock_impl returns 0) — a racing read-modify-write would emit a
    # confident tally of lost updates. UNKNOWN is the honest failure.
    _tally_err lock-substrate-disabled
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

# Cap values: ^[1-9][0-9]{0,9}$ — rejects non-numeric, negative, 0, the
# leading-zero forms (`08`) that 10# would otherwise silently accept, AND
# digit strings that wrap mod-2^64 into a different cap than the one asked for.
_tally_norm_cap() {
  [[ "$1" =~ ^[1-9][0-9]{0,9}$ ]] || return 1
  printf '%s' "$((10#$1))"
}

# --- init -------------------------------------------------------------------

_tally_init_locked() {
  local reset="$1" caps_given="$2"
  local n_seats="$3" n_ci="$4" n_fix="$5" n_agent="$6"
  local existed=0 ok=0 outcome
  [[ -f "$T_FILE" ]] && existed=1
  if (( existed )) && _tally_ledger_ok "$T_FILE"; then ok=1; fi
  _tally_load "$T_FILE"

  # Staleness = 24h of INACTIVITY, keyed on file mtime, not a written key:
  # every incr/gate write bumps it (gate also refreshes it on read), so a
  # multi-day pipeline that crosses the threshold while still counting never
  # gets zeroed mid-run.
  local stale=0 mtime=0
  if (( existed && ok )); then
    mtime=$(stat -c %Y "$T_FILE" 2>/dev/null || stat -f %m "$T_FILE" 2>/dev/null || echo 0)
    [[ "$mtime" =~ ^[0-9]+$ ]] && (( $(date +%s) - 10#$mtime > 86400 )) && stale=1
  fi

  if (( ! existed )); then
    outcome="fresh"
  elif (( reset )); then
    outcome="reset"
  elif (( ! ok )); then
    # Existing but unreadable/corrupt: rewrite a clean ledger (fail-open — the
    # pipeline must never wedge on state) but do NOT report `continued` —
    # nothing readable was preserved, and a repaired forensic record is not
    # a continuation.
    outcome="repaired"
    _tally_err unreadable
  elif [[ -n "$T_capped" ]] && (( caps_given )); then
    # Raised-cap resume BEATS stale: an explicit `--max-*` argv is operator
    # intent to continue THIS run under a new budget, and the counts are the
    # forensic record the feature exists to keep. (A bare init on the same
    # stale+capped file still stale-resets — argv intent is what disambiguates
    # resume from a new run.)
    outcome="capped-reset"
  elif (( stale )); then
    outcome="stale-reset"
  elif [[ -n "$T_capped" ]]; then
    # Budget-capped ledger + no raised caps: the ledger CONTINUES and `capped`
    # persists, so the next `gate` still returns STOP. See CAP SEMANTICS above.
    outcome="continued capped=$T_capped"
  else
    outcome="continued"
  fi

  case "$outcome" in
    reset|stale-reset|repaired)
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

  # Merge argv caps — RATCHET GUARD: without --reset, a --max-* LOWER than a
  # persisted nonzero cap is refused (a `cap-kept:` line surfaces it). A
  # forwarded or defaulted flag would otherwise silently tighten this branch's
  # budget and false-STOP a later unflagged run.
  _TALLY_KEPT=""
  _tally_merge_cap seats "$n_seats" "$reset"
  _tally_merge_cap ci_cycles "$n_ci" "$reset"
  _tally_merge_cap fix_rounds "$n_fix" "$reset"
  _tally_merge_cap agent_rounds "$n_agent" "$reset"

  _tally_write "$T_FILE" || { _tally_err write-failed; printf 'UNKNOWN\n'; return 0; }
  _tally_sweep
  printf 'tally-init: %s %s\n' "$T_SLUG" "$outcome"
  # Armed-cap disclosure: a persisted cap from an earlier invocation is
  # otherwise invisible until it stops a run.
  local armed; armed=$(_tally_cap_tokens)
  [[ -n "$armed" ]] && printf 'armed: %s\n' "${armed% }"
  [[ -n "$_TALLY_KEPT" ]] && printf 'cap-kept: %s\n' "${_TALLY_KEPT% }"
  return 0
}

# Trailing-space "cap:<d>=<n> ..." for the nonzero caps — shared by init's
# armed: line and show's cap: line so the two renderings cannot drift.
_tally_cap_tokens() {
  local _d _c out=""
  for _d in seats ci_cycles fix_rounds agent_rounds; do
    _c=$(_tally_getf "cap_$_d")
    (( _c > 0 )) && out="${out}cap:${_d}=${_c} "
  done
  printf '%s' "$out"
}

# Merge one --max-* value into cap_<dim>; refuses to lower a persisted nonzero
# cap unless --reset. Accumulates refusals in _TALLY_KEPT.
_tally_merge_cap() {
  local dim="$1" newv="$2" reset="$3" old
  [[ -n "$newv" ]] || return 0
  old=$(_tally_getf "cap_$dim")
  if (( ! reset )) && (( old > 0 )) && (( 10#$newv < old )); then
    _TALLY_KEPT="${_TALLY_KEPT}${dim}=${old} "
    return 0
  fi
  _tally_setf "cap_$dim" "$newv"
  return 0
}

cmd_init() {
  local reset=0 caps_given=0 branch="" flag=""
  local n_seats="" n_ci="" n_fix="" n_agent="" v=""
  while [[ $# -gt 0 ]]; do
    # Underscored spellings of a flag alias to its hyphenated form —
    # `--max-ci_cycles` would otherwise silently bad-flag the operator's budget.
    flag=$(printf '%s' "$1" | tr '_' '-')
    case "$flag" in
      --reset) reset=1; shift ;;
      --branch)
        branch="${2:-}"
        [[ -n "$branch" && "$branch" != -* ]] || { _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; }
        shift 2 ;;
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
  _tally_paths "$branch" || { _tally_paths_err $?; printf 'UNKNOWN\n'; return 0; }
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
      --branch)
        branch="${2:-}"
        [[ -n "$branch" && "$branch" != -* ]] || { _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; }
        shift 2 ;;
      -* ) _tally_err bad-flag; printf 'UNKNOWN\n'; return 0 ;;
      *)
        if [[ -z "$dim" ]]; then dim="$1"
        elif (( ! n_set )); then n="$1"; n_set=1
        else _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; fi
        shift ;;
    esac
  done
  dim=$(_tally_dim "${dim:-}") || { _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; }
  if [[ ! "$n" =~ ^[0-9]{1,10}$ ]]; then
    _tally_err bad-flag; printf 'UNKNOWN\n'; return 0
  fi
  n=$((10#$n))
  _tally_paths "$branch" || { _tally_paths_err $?; printf 'UNKNOWN\n'; return 0; }
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
      --branch)
        branch="${2:-}"
        [[ -n "$branch" && "$branch" != -* ]] || { _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; }
        shift 2 ;;
      *) _tally_err bad-flag; printf 'UNKNOWN\n'; return 0 ;;
    esac
  done
  _tally_paths "$branch" || { _tally_paths_err $?; printf 'UNKNOWN\n'; return 0; }
  if [[ ! -f "$T_FILE" ]]; then
    _tally_err missing-file; printf 'UNKNOWN\n'; return 0
  fi
  if ! _tally_ledger_ok "$T_FILE"; then
    _tally_err unreadable; printf 'UNKNOWN\n'; return 0
  fi
  _tally_load "$T_FILE"
  _tally_print_line
  # Second line: configured caps (the stop-hook floor and ship's render both
  # consume this shape — `cap:<dim>=<n>` tokens, same helper init's armed: uses).
  local caps d w
  caps=$(_tally_cap_tokens)
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
  local dim="$1" ask="${2:-0}"
  if [[ ! -f "$T_FILE" ]]; then
    _tally_err missing-file; printf 'UNKNOWN\n'; return 0
  fi
  if ! _tally_ledger_ok "$T_FILE"; then
    _tally_err unreadable; printf 'UNKNOWN\n'; return 0
  fi
  _tally_load "$T_FILE"
  # Refresh mtime on every successful gate read: staleness means "nothing
  # touched the ledger in 24h", and a polling caller (ship's phase-7 gate)
  # IS ledger activity — a quiet-but-live pipeline must not zero itself.
  touch "$T_FILE" 2>/dev/null || true
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
  # Lookahead: `gate <dim> <n>` asks "does the impending n-unit step fit?"
  # STOP without latching — a smaller ask may still fit.
  if (( ask > 0 && count + ask > cap )); then
    printf 'STOP\n'; return 0
  fi
  local warn_thresh=$(( (cap * 8 + 9) / 10 ))   # ceil(cap * 0.8)
  if (( count + ask >= warn_thresh )); then
    if [[ "$(_tally_getf "warned_$dim")" == "0" ]]; then
      _tally_setf "warned_$dim" "$((count + ask))"   # first-fire level incl. the ask
      _tally_write "$T_FILE" || true
    fi
    printf 'WARN\n'; return 0
  fi
  printf 'OK\n'
  return 0
}

cmd_gate() {
  local dim="" ask="" branch=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --branch)
        branch="${2:-}"
        [[ -n "$branch" && "$branch" != -* ]] || { _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; }
        shift 2 ;;
      *)
        if [[ -z "$dim" ]]; then dim="$1"
        elif [[ -z "$ask" ]]; then ask="$1"
        else _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; fi
        shift ;;
    esac
  done
  dim=$(_tally_dim "${dim:-}") || { _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; }
  if [[ -n "$ask" ]]; then
    [[ "$ask" =~ ^[0-9]{1,10}$ ]] || { _tally_err bad-flag; printf 'UNKNOWN\n'; return 0; }
    ask=$((10#$ask))
  else
    ask=0
  fi
  _tally_paths "$branch" || { _tally_paths_err $?; printf 'UNKNOWN\n'; return 0; }
  # Same ordering as cmd_incr: missing-file must win over no-flock.
  if [[ ! -f "$T_FILE" ]]; then
    _tally_err missing-file; printf 'UNKNOWN\n'; return 0
  fi
  _tally_locked _tally_gate_locked "$dim" "$ask" || true
  return 0
}

# --- dispatch ---------------------------------------------------------------

_tally_usage() {
  cat <<'EOF'
usage: pipeline-tally.sh <subcommand> [args]

  init [--reset] [--branch <b>] [--max-seats N] [--max-ci-cycles N]
       [--max-fix-rounds N] [--max-agent-rounds N]
  incr <dim> [n] [--branch <b>]
  show [--branch <b>]
  gate <dim> [n] [--branch <b>]
  selfcheck

dims: seats | ci_cycles (alias ci-cycles) | fix_rounds | agent_rounds
gate's optional [n] is a lookahead: STOP when count+n would exceed the cap.
fail-open: every subcommand exits 0; errors are SOLEUR_TALLY_ERROR on stderr.
EOF
}

case "${1:-}" in
  init) shift; cmd_init "$@" ;;
  incr) shift; cmd_incr "$@" ;;
  show) shift; cmd_show "$@" ;;
  gate) shift; cmd_gate "$@" ;;
  -h|--help|"") _tally_usage ;;
  *) _tally_err bad-flag; _tally_usage >&2 ;;
esac
exit 0
