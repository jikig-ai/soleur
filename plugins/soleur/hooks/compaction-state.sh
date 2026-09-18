#!/usr/bin/env bash
# compaction-state.sh -- compaction-aware session hooks (#8323, ADR-227).
#
# Bound TWICE in hooks.json and dispatching on hook_event_name:
#   PreCompact   (matcher manual|auto)                -> shape the summary (FR3)
#   SessionStart (matcher startup|resume|clear|compact) -> reset the window, or
#                                                        emit the directive (FR1/FR2)
#
# ---------------------------------------------------------------------------
# MEASURED PAYLOAD CONTRACT -- Claude Code 2.1.273, Linux, 2026-09-18.
# Captured from a real marker hook bound in a throwaway project and driven by
# headless `claude -p --continue "/compact"`. Docs are not the source here; this
# is. NOTHING DETECTS DRIFT IN IT AUTOMATICALLY -- an earlier revision shipped a
# canary and review deleted it (ADR-227 `## Amendment`), because it watched the
# transcript while this contract lives in the stdin envelope. Re-measure these
# rows on a CLI bump; a matcher miss here is silent in both directions (a missing
# PreCompact under-counts, a missing SessionStart source over-counts).
#
#   SessionStart:startup  keys: cwd hook_event_name session_id source transcript_path
#                         ...and transcript_path names a file that DOES NOT YET EXIST.
#   SessionStart:compact  keys: cwd hook_event_name model prompt_id session_id
#                               source transcript_path        -- NO `trigger`.
#   PreCompact            keys: custom_instructions cwd hook_event_name prompt_id
#                               session_id transcript_path trigger  -- NO `source`.
#   PostCompact           keys: compact_summary cwd hook_event_name prompt_id
#                               session_id transcript_path trigger  -- not bound here.
#
#   source after a compaction is literally "compact".
#   transcript_path is STABLE across a compaction (identical at all three events).
#   --fork-session starts a new session_id and a new transcript file, and fired
#     no SessionStart hook at all.
#
# THE TWO FINDINGS THAT DETERMINE THIS FILE'S DESIGN:
#
#   1. At SessionStart:compact the just-fired compaction's compact_boundary is
#      NOT on disk. Measured twice: compaction #1 read count=0 (1 present
#      afterwards), compaction #2 read count=1 (2 present). PostCompact, 100 ms
#      later, reads the same lagging value. The boundary's own timestamp
#      PRECEDES the hook fire, so the record exists in memory and is flushed
#      after the hook returns. The transcript therefore cannot answer "how many
#      compactions has this session had" at the moment this hook needs it, and
#      carries no trigger for the current compaction either.
#
#   2. PreCompact firing does NOT imply a compaction occurred -- 3 fires
#      produced 2 boundaries, because a /compact with nothing left to compact
#      fires PreCompact and then no SessionStart:compact. So "append one line
#      per PreCompact and count lines" over-counts and moves the
#      recommendation one compaction early, with every fixture green.
#
# Hence PENDING-THEN-COMMIT over a per-session ledger under TMPDIR:
#   PreCompact            overwrites one `pending` slot with its own trigger.
#   SessionStart:compact  commits that slot as one ledger line, then counts.
#                         It fires exactly once per REAL compaction.
#   SessionStart:other    truncates the ledger and clears pending -- this is
#                         what makes TR2's session-window scoping exact rather
#                         than approximated, and it is why the matcher is
#                         startup|resume|clear|compact and not compact alone.
#
# The transcript is NOT read. An earlier revision greped it once for a
# `prior_boundaries` corroboration marker; review deleted that, because nothing
# consumed the field and -- since the ledger resets per window while the
# transcript accumulates across --resume -- the two numbers diverge arbitrarily,
# so it handed the model a contradiction with no reconciliation rule. The
# measurements in this header are what the transcript was for; they are
# recorded, not re-derived at runtime.
#
# FAIL-OPEN BY CONTRACT. Every path exits 0. `trap 'exit 0' ERR EXIT`: the EXIT
# arm is load-bearing because a `set -u` unbound-variable expansion terminates
# the shell with status 1 WITHOUT firing ERR, and any non-zero exit other than 2
# makes Claude Code silently drop the whole JSON output.
#
# Kill switch: SOLEUR_DISABLE_COMPACTION_HOOKS=1
# Threshold:   SOLEUR_COMPACTION_COUNT_THRESHOLD (default 2)
# ---------------------------------------------------------------------------

set -uo pipefail
trap 'exit 0' ERR EXIT

# Canonical copy of test-helpers.sh's assert_fixture_dir -- P1a requires every
# tracked copy be byte-equal, and the P1b scanner recognises ONLY this name.
# Here it guards the ledger window: TMPDIR is caller-supplied, so a relative or
# synthetic-fs value would put these writes somewhere unintended. The exit 2 is
# converted to 0 by the EXIT trap above, which is the fail-open contract -- the
# hook refuses to write and says nothing, rather than writing to a bad path.
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

# Written before every guard, so it certifies INVOCATION rather than success.
# The suite floors on this: a harness that asserts without spawning the hook
# produces none of these lines.
[[ "${SOLEUR_DISABLE_COMPACTION_HOOKS:-0}" == "1" ]] && exit 0

# Coverage trace, BELOW the kill switch. It sat above it, which made the README's
# "no directive, no summary shaping, nothing written" false -- measured: with the
# switch set, the hook still appended. `assert_fixture_dir` validates a path
# STRING (absolute, no `..`, not a synthetic fs); it says nothing about symlinks,
# ownership, or file-vs-directory, so on its own it authorises an append to any
# absolute path the process can write. Require an EXISTING regular non-symlink
# file: a harness creates it deliberately, a stray export cannot conjure one.
if [[ -n "${SOLEUR_HOOK_TRACE:-}" ]]; then
  assert_fixture_dir "$SOLEUR_HOOK_TRACE"
  if [[ -f "$SOLEUR_HOOK_TRACE" && ! -L "$SOLEUR_HOOK_TRACE" && -O "$SOLEUR_HOOK_TRACE" ]]; then
    printf 'ran\n' >> "$SOLEUR_HOOK_TRACE"
  fi
fi

# Deliberate set -u fault, reachable only through this seam. It is the only way
# to drive the EXIT arm of the trap above from a test: an ERR-only trap leaves
# the fail-open contract broken on exactly this fault, and nothing else in the
# script can be made to raise it on demand.
if [[ "${SOLEUR_COMPACTION_SELFTEST_UNBOUND:-0}" == "1" ]]; then
  printf '%s' "$__soleur_deliberately_unbound_variable"
fi

RAW="$(cat 2>/dev/null)" || RAW=""

HAVE_JQ=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1

# Flat top-level scalar read. Every field this hook consumes is a top-level
# string in the measured envelopes, so the no-jq fallback is adequate rather
# than a partial JSON parser pretending otherwise.
jget() { # <key>
  local k="$1"
  if (( HAVE_JQ )); then
    printf '%s' "$RAW" | jq -r --arg k "$k" '.[$k] // empty' 2>/dev/null
    return 0
  fi
  printf '%s' "$RAW" \
    | grep -oE "\"$k\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" 2>/dev/null \
    | head -1 \
    | sed 's/.*:[[:space:]]*"\(.*\)"$/\1/' 2>/dev/null
}

EVENT="$(jget hook_event_name)"
CWD="$(jget cwd)"
# Caller-supplied, and the input to the scope walk, `git -C "$ROOT"` and two
# globs -- so it gets the same gate as the ledger root rather than being trusted
# because it comes from the CLI. A relative or `..`-bearing value would make the
# walk test paths against whatever cwd the hook inherited.
[[ -n "$CWD" ]] || CWD="$PWD"
case "$CWD" in
  /*) [[ "$CWD" == */../* || "$CWD" == */.. ]] && CWD="$PWD" ;;
  *) CWD="$PWD" ;;
esac
# A non-existent cwd makes every test at the leaf false, so the walk climbs to a
# real Soleur ancestor and reports ITS branch and plan for a directory that is
# not there. Refuse instead of guessing.
[[ -d "$CWD" ]] || exit 0

# --- TR1 scope guard ---------------------------------------------------------
# A plugin hook is global. `git rev-parse --is-inside-work-tree` is true in
# EVERY customer repo, so gating on it would let PreCompact tell a stranger's
# summarizer to preserve "PR #, plan path, unchecked ACs, operator holds" while
# summarizing work that has none. The guard is welcome-hook.sh's sentinel -- a
# plugins/soleur directory -- AND a Soleur plan/spec artifact. Both conjuncts
# are load-bearing: a plugin developer's checkout has the first without the
# second.
# CTO ruling 2 (ADR-227 amendment). This is a RELEVANCE test -- is this project
# one Soleur manages -- and explicitly NOT an authenticity test; no cheap
# filesystem predicate can distinguish "my Soleur project" from "a repo I cloned
# that looks like one", because a clone carries tracked files and Soleur's
# artifacts are tracked. That limit is named rather than papered over, and the
# platform baseline already exceeds it: a cloned repo reaches the model at equal
# authority through CLAUDE.md / AGENTS.md, unconditionally and with no guard.
#
# The former first conjunct was a `plugins/soleur` directory, copied from
# welcome-hook.sh. That tests whether the OPENED REPO is the Soleur monorepo --
# which no marketplace install ever is, since `claude plugin install` puts the
# plugin under ~/.claude/plugins/. It excluded the entire installed base, for a
# feature whose consumers (plan/SKILL.md, work/SKILL.md) run wherever Soleur is
# installed. Shipping that guard alongside this PR's retirement of the
# unconditional /clear prose would have REMOVED working advice from a population
# it could not serve. Installation itself needs no test: this file only exists
# inside an installed, enabled plugin, so reaching this line IS the proof.
#
# ANCHORED at the enclosing repository, matching welcome-hook.sh's one-GIT_ROOT
# shape: the walk stops at the first directory carrying .git (a FILE in a linked
# worktree, a directory in a normal clone), so a stranger repo nested under a
# Soleur checkout -- this repo's own .worktrees/ layout -- does not inherit scope.
soleur_root() {
  local d="$CWD" i=0
  while [[ -n "$d" && "$d" != "/" && $i -lt 40 ]]; do
    if [[ -d "$d/knowledge-base/project/plans" ]] || [[ -d "$d/knowledge-base/project/specs" ]]; then
      printf '%s' "$d"
      return 0
    fi
    # Repo boundary: climbing past it is what admits the nested-repo case.
    # `-e` is FALSE for a DANGLING symlink, so `-L` is needed too or a broken
    # .git link silently stops being a boundary.
    { [[ -e "$d/.git" ]] || [[ -L "$d/.git" ]]; } && return 1
    d="$(dirname "$d")"
    i=$((i + 1))
  done
  return 1
}
ROOT="$(soleur_root)" || exit 0
[[ -n "$ROOT" ]] || exit 0

# --- ledger ------------------------------------------------------------------
SID_RAW="$(jget session_id)"
SID="$(printf '%s' "$SID_RAW" | tr -cd 'A-Za-z0-9_-' | cut -c1-64)"
# Non-injective on two axes: `x/y`, `x.y` and `xy` all map to `xy`, and two ids
# differing past char 64 map together. Harmless for today's UUIDs, and a
# collision makes one session count another's compactions -- the over-firing
# direction. Refuse a lossy id instead of sharing a key.
[[ "$SID" == "$SID_RAW" ]] || SID=""
umask 077   # ledger files were 0644; protection rested entirely on the dir mode
LEDGER_DIR="${TMPDIR:-/tmp}/soleur-compaction"
assert_fixture_dir "$LEDGER_DIR"
# FAIL CLOSED on squatting. With TMPDIR unset this is /tmp/soleur-compaction,
# world-reachable on a multi-user host. `mkdir -p || true` + `chmod || true`
# degrades SILENTLY if another user pre-created the directory -- and a
# pre-seeded <sid>.pending then flows through COMMITTED -> TRIGGER -> the
# directive, which the model reads at elevated authority. Refuse instead:
# the EXIT trap turns this into a silent exit 0, which is the fail-open
# contract for the FEATURE and fail-closed for the WRITE.
# Two calls, not `mkdir -m 0700 -p`: with -p the mode applies only to the
# DEEPEST directory (shellcheck SC2174), so any parent this creates would take
# the umask. The leaf is created WITHOUT -p so it is either made 0700 here or
# already exists, and the ownership check below is what actually decides.
mkdir -p "${LEDGER_DIR%/*}" 2>/dev/null || true
mkdir -m 0700 "$LEDGER_DIR" 2>/dev/null || true
# `-L` FIRST: `-d` and `-O` both stat rather than lstat, so a symlink planted at
# this predictable path satisfied both -- measured, the hook wrote through it into
# a victim-owned directory and chmod 700'd the TARGET.
if [[ -L "$LEDGER_DIR" ]] || [[ ! -d "$LEDGER_DIR" ]] || [[ ! -O "$LEDGER_DIR" ]]; then
  LEDGER_DIR_UNUSABLE=1
else
  LEDGER_DIR_UNUSABLE=0
  chmod 700 "$LEDGER_DIR" 2>/dev/null || true
fi
LEDGER="$LEDGER_DIR/${SID}.ledger"
PENDING="$LEDGER_DIR/${SID}.pending"

# Bounded growth. Entries are disposable by construction -- a lost ledger costs
# one directive, never correctness.
find "$LEDGER_DIR" -maxdepth 1 -type f \( -name '*.ledger' -o -name '*.pending' \) \
  -mmin +10080 -delete 2>/dev/null || true

# Every value interpolated into `additionalContext` is read by the model at
# ELEVATED AUTHORITY, so each one is an injection surface. `trigger` and
# `threshold` are closed-set / digits-only; these are free text from sources the
# hook does not own -- a git ref name is chosen by whoever created the branch, and
# a GIT FILENAME MAY CONTAIN NEWLINES, which `jq --arg` faithfully preserves as
# real newlines inside the string the model reads. Reduce to a conservative
# display charset and cap the length; an empty result becomes `unknown`.
sanitize_display() { # <value> <fallback>
  local v
  v="$(printf '%s' "${1-}" | tr -cd 'A-Za-z0-9._/+@-' | cut -c1-200)"
  printf '%s' "${v:-${2-unknown}}"
}

# --- PreCompact (FR3) --------------------------------------------------------
if [[ "$EVENT" == "PreCompact" ]]; then
  # AP-020: check a contracted field's SHAPE rather than assuming it. `trigger`
  # is model-adjacent input that (a) gates the recommendation and (b) is
  # interpolated into text the model reads at elevated authority. Unvalidated, a
  # multi-line value inflates the ledger's line count -- which IS count_total --
  # and forces recommend=true. Closed set, measured at CLI 2.1.273.
  TRIGGER="$(jget trigger)"
  case "$TRIGGER" in
    manual|auto) : ;;
    *) TRIGGER="unknown" ;;
  esac
  # Summary shaping does not need the ledger, so an unusable root suppresses the
  # WRITE and not the FR3 prose.
  if [[ -n "$SID" ]] && (( ! LEDGER_DIR_UNUSABLE )); then
    # OVERWRITE, never append: PreCompact fires on no-op compactions, and only
    # SessionStart:compact proves one actually happened.
    assert_fixture_dir "$LEDGER_DIR"
    printf '%s\n' "$TRIGGER" > "$PENDING" 2>/dev/null || true
  fi
  # Plain text, never JSON: this stream is read by the summarizer, and never
  # exits 2 -- blocking a compaction trades a recoverable context loss for a
  # dead session (NG3).
  cat <<'PRECOMPACT'
When summarizing, preserve these verbatim -- a resume depends on them:
- the git branch and the worktree directory currently in use
- the PR # and the issue # under work, and the plan path
- the active skill and phase, and every unchecked acceptance criteria item
- anything recorded under Operator Holds
- every file path mentioned, spelled exactly as written
Keep the paths themselves. Summarize what was done to them; do not reproduce
what they contain.
PRECOMPACT
  exit 0
fi

[[ "$EVENT" == "SessionStart" ]] || exit 0

# Reached here with an unusable ledger root: PreCompact already returned above,
# so this is the SessionStart arm and it owes the model a reason. Emitting
# nothing made a permanent per-host disable indistinguishable from "this session
# has not compacted" -- and the plan's own Observability block promises every
# failure path emits a named marker.

SOURCE="$(jget source)"

# --- SessionStart, window reset ----------------------------------------------
# startup / resume / clear all open a new window. Guarding only `resume` would
# leave two of the three unscoped, which is how a long session pins
# recommend=true forever (TR2).
case "$SOURCE" in
  startup|resume|clear) SOURCE_CLASS=reset ;;
  compact)              SOURCE_CLASS=compact ;;
  *)                    SOURCE_CLASS=unknown ;;
esac

if [[ "$SOURCE_CLASS" != "compact" ]]; then
  # `unknown` lands here and does NOTHING -- it must not reset, because the
  # matcher admits any source containing one of the four words and a future
  # `precompact` would otherwise truncate the ledger at the event it counts.
  [[ "$SOURCE_CLASS" == "reset" ]] || exit 0
  if [[ -n "$SID" ]]; then
    assert_fixture_dir "$LEDGER_DIR"
    rm -f "$LEDGER" "$PENDING" 2>/dev/null || true
    if [[ -s "$LEDGER" ]]; then
      # A surviving ledger carries the PREVIOUS window's rows into this one and
      # is the only state that over-counts. Never silent.
      printf 'SOLEUR_COMPACTION_SKIPPED reason=window-reset-failed path=%s\n' "$LEDGER" >&2
    fi
  fi
  exit 0
fi

# --- envelope emission -------------------------------------------------------
# stdout carries the JSON envelope and NOTHING else; a stray byte invalidates
# the whole output. Diagnostics go to stderr.
emit() { # <additionalContext>
  local ctx="${1:0:8000}"
  if (( HAVE_JQ )); then
    jq -nc --arg c "$ctx" \
      '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
  else
    # The envelope cannot be built with jq in this state, so it is emitted
    # literally -- no interpolation, hence nothing to escape.
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"SOLEUR_COMPACTION_SKIPPED reason=jq-unavailable -- compaction state could not be reported. Context was just compacted: re-read the plan and spec before editing (hr-always-read-a-file-before-editing-it)."}}'
  fi
}

if (( ! HAVE_JQ )); then
  emit ""
  exit 0
fi

if (( LEDGER_DIR_UNUSABLE )); then
  emit "SOLEUR_COMPACTION_SKIPPED reason=ledger-dir-unusable -- the compaction ledger directory is missing, foreign-owned or a symlink, so no compaction state could be recorded. Context was just compacted: re-read the plan and spec before editing (hr-always-read-a-file-before-editing-it)."
  exit 0
fi

if [[ -z "$SID" ]]; then
  emit "SOLEUR_COMPACTION_SKIPPED reason=no-session-id"
  exit 0
fi

# Commit the pending slot. Reached exactly once per real compaction.
COMMITTED=""
if [[ -f "$PENDING" ]]; then
  COMMITTED="$(head -1 "$PENDING" 2>/dev/null || true)"
  # Re-assert the closed set BEFORE the append. The pending file is same-uid
  # writable and its value reaches count_total and the "compaction N" sentence
  # even where it cannot reach `recommend`.
  case "$COMMITTED" in
    manual|auto) : ;;
    *) COMMITTED="unknown" ;;
  esac
  assert_fixture_dir "$LEDGER_DIR"
  printf '%s\n' "$COMMITTED" >> "$LEDGER" 2>/dev/null || true
  rm -f "$PENDING" 2>/dev/null || true
fi

COUNT_TOTAL=0
COUNT_AUTO=0
if [[ -r "$LEDGER" ]]; then
  COUNT_TOTAL="$(LC_ALL=C grep -acxE 'manual|auto|unknown' "$LEDGER" 2>/dev/null || true)"
  COUNT_AUTO="$(LC_ALL=C grep -acx 'auto' "$LEDGER" 2>/dev/null || true)"
fi
COUNT_TOTAL="${COUNT_TOTAL:-0}"
COUNT_AUTO="${COUNT_AUTO:-0}"

if [[ "$COUNT_TOTAL" -eq 0 ]]; then
  # No PreCompact was seen for this window. Honest silence beats a guess: the
  # transcript cannot supply the answer (finding 1 above).
  emit "SOLEUR_COMPACTION_SKIPPED reason=no-ledger-entry -- context was compacted but this session's compaction ledger is empty. Re-read the plan and spec before editing (hr-always-read-a-file-before-editing-it)."
  exit 0
fi

# `tail -1 "$LEDGER"` as the fallback reinstated, on the missing-pending path,
# exactly what alternative (a) is rejected for: it reports the PREVIOUS
# compaction's trigger for the current event. Measured -- a third compaction with
# no pending slot inherited `trigger=auto` and was not counted. Unknown is the
# honest answer, and the closed-set rule already stops it recommending.
TRIGGER="$COMMITTED"
case "$TRIGGER" in
  manual|auto) : ;;
  *) TRIGGER="unknown" ;;
esac

CLI="${SOLEUR_COMPACTION_CLI_VERSION:-}"
if [[ -z "$CLI" ]] && command -v claude >/dev/null 2>&1; then
  # `command -v` first: this runs with the cwd of an arbitrary repo, so resolving
  # `claude` by bare name is a PATH question, not a given.
  CLI="$(timeout 5 claude --version 2>/dev/null | head -1 | awk '{print $1}' || true)"
fi
CLI="$(sanitize_display "$CLI" unknown)"

# `symbolic-ref --short -q` is this repo's precedent for exactly this
# (.claude/hooks/ship-unpushed-commits-gate.sh): it exits non-zero on a detached
# HEAD, where `rev-parse --abbrev-ref` returns the literal string `HEAD` and
# would have the directive assert `Branch: HEAD.` to the model. CI checks out a
# detached HEAD on pull_request, so that is the common case, not an edge one.
BRANCH="$(timeout 5 git -C "$ROOT" symbolic-ref --short -q HEAD 2>/dev/null || true)"
BRANCH="$(sanitize_display "$BRANCH" unknown)"

PLAN=""
if [[ "$BRANCH" != "unknown" ]]; then
  for p in "$ROOT/knowledge-base/project/plans/"*"-${BRANCH}-plan.md"; do
    [[ -e "$p" ]] && PLAN="$(sanitize_display "knowledge-base/project/plans/$(basename "$p")" "")"
  done
fi
SPEC=""
[[ -d "$ROOT/knowledge-base/project/specs/$BRANCH" ]] \
  && SPEC="$(sanitize_display "knowledge-base/project/specs/$BRANCH/" "")"

THRESHOLD="${SOLEUR_COMPACTION_COUNT_THRESHOLD:-2}"
case "$THRESHOLD" in
  ''|*[!0-9]*) THRESHOLD=2 ;;   # a non-numeric seam makes (( )) evaluate false
esac                            # silently, skipping the branch rather than failing
THRESHOLD=$((10#$THRESHOLD))    # `010` passes the digit filter and (( )) reads octal
# The CTO ruling requires a floor of at least 1: with the trigger operand gone,
# THRESHOLD=0 makes the gate true on a ledger holding ZERO auto lines. Floored to
# the DEFAULT (2) rather than to 1 -- a deviation, recorded in ADR-227. `0` is
# what an operator types meaning "off", and flooring to 1 would hand that person
# the MOST aggressive setting, which is the over-firing harm delivered to someone
# trying to disable the feature. The off switch is
# SOLEUR_DISABLE_COMPACTION_HOOKS. Written as if/fi, not `(( )) && x`: measured on
# bash 5.3.15 the && form does not abort under `trap ERR EXIT`, but if/fi does not
# depend on that exemption.
if (( THRESHOLD < 1 )); then THRESHOLD=2; fi

# CTO ruling 1 (ADR-227 amendment): the gate is COUNT_AUTO alone. The current
# event's trigger was a second operand that could only ever REVOKE -- COUNT_AUTO
# rises only on a SessionStart:compact that commits an `auto` line, so the first
# emission crossing the threshold always had trigger=auto and fired either way.
# Its sole behavioural delta was retracting a recommendation already issued,
# which overwrites a correct recommend=true with an affirmative recommend=false
# at the moment the model can least reconstruct it. The ledger is append-only
# within a window, so RECOMMEND is already monotonic without a sticky bit.
RECOMMEND=false
if (( COUNT_AUTO >= THRESHOLD )); then
  RECOMMEND=true
fi

# Pointers, never content. Nothing read out of the transcript is echoed: the
# only transcript-derived value here is an integer (NG5, and the
# elevated-authority framing hook-delivered text carries).
CTX="SOLEUR_COMPACTION_DIRECTIVE count_auto=${COUNT_AUTO} count_total=${COUNT_TOTAL} trigger=${TRIGGER} recommend=${RECOMMEND} threshold=${THRESHOLD} cli=${CLI} branch=${BRANCH}

Context was just compacted (compaction ${COUNT_TOTAL} of this session, trigger=${TRIGGER}).
The summary above is a paraphrase written by another model. Before editing any
file, re-read the artifacts it names -- hr-always-read-a-file-before-editing-it.
Branch: ${BRANCH}."
[[ -n "$PLAN" ]] && CTX="${CTX}
Plan: ${PLAN}"
[[ -n "$SPEC" ]] && CTX="${CTX}
Spec and tasks: ${SPEC}"

if [[ "$RECOMMEND" == "true" ]]; then
  CTX="${CTX}

${COUNT_AUTO} automatic compactions have now occurred in this session window.
At the next phase boundary -- not mid-pipeline -- emit the resume prompt per
wg-end-of-work-emit-resume-prompt and recommend continuing in a fresh session.
Inside /soleur:one-shot, never pause for this: carry the recommendation into the
final resume prompt instead."
fi

emit "$CTX"
exit 0
