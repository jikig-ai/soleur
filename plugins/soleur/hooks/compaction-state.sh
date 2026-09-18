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
# is. Re-measure on a CLI bump -- FR7's canary exists to say when.
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
if [[ -n "${SOLEUR_HOOK_TRACE:-}" ]]; then
  assert_fixture_dir "$SOLEUR_HOOK_TRACE"
  printf 'ran\n' >> "$SOLEUR_HOOK_TRACE"
fi

[[ "${SOLEUR_DISABLE_COMPACTION_HOOKS:-0}" == "1" ]] && exit 0

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
[[ -n "$CWD" ]] || CWD="$PWD"

# --- TR1 scope guard ---------------------------------------------------------
# A plugin hook is global. `git rev-parse --is-inside-work-tree` is true in
# EVERY customer repo, so gating on it would let PreCompact tell a stranger's
# summarizer to preserve "PR #, plan path, unchecked ACs, operator holds" while
# summarizing work that has none. The guard is welcome-hook.sh's sentinel -- a
# plugins/soleur directory -- AND a Soleur plan/spec artifact. Both conjuncts
# are load-bearing: a plugin developer's checkout has the first without the
# second.
# ANCHORED at the enclosing repository, matching welcome-hook.sh, which resolves
# GIT_ROOT and tests exactly one directory. An unanchored walk is strictly wider
# than that precedent: a Soleur checkout at ~/dev makes ~/dev/plugins/soleur and
# ~/dev/knowledge-base/project/plans visible to EVERY unrelated repo nested
# beneath it -- and nesting is this repo's own .worktrees/ layout, not a
# hypothetical. So the walk stops at the first directory carrying .git (a FILE
# in a linked worktree, a directory in a normal clone) and refuses if that root
# did not satisfy both conjuncts.
soleur_root() {
  local d="$CWD" i=0
  while [[ -n "$d" && "$d" != "/" && $i -lt 40 ]]; do
    if [[ -d "$d/plugins/soleur" ]] \
      && { [[ -d "$d/knowledge-base/project/plans" ]] || [[ -d "$d/knowledge-base/project/specs" ]]; }; then
      printf '%s' "$d"
      return 0
    fi
    # Repo boundary: climbing past it is what admits the nested-repo case.
    [[ -e "$d/.git" ]] && return 1
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
if [[ ! -d "$LEDGER_DIR" ]] || [[ ! -O "$LEDGER_DIR" ]]; then
  printf 'SOLEUR_COMPACTION_SKIPPED reason=ledger-dir-unusable path=%s\n' "$LEDGER_DIR" >&2
  exit 0
fi
chmod 700 "$LEDGER_DIR" 2>/dev/null || true
LEDGER="$LEDGER_DIR/${SID}.ledger"
PENDING="$LEDGER_DIR/${SID}.pending"

# Bounded growth. Entries are disposable by construction -- a lost ledger costs
# one directive, never correctness.
find "$LEDGER_DIR" -maxdepth 1 -type f -mmin +10080 -delete 2>/dev/null || true

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
  if [[ -n "$SID" ]]; then
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

SOURCE="$(jget source)"

# --- SessionStart, window reset ----------------------------------------------
# startup / resume / clear all open a new window. Guarding only `resume` would
# leave two of the three unscoped, which is how a long session pins
# recommend=true forever (TR2).
if [[ "$SOURCE" != "compact" ]]; then
  if [[ -n "$SID" ]]; then
    rm -f "$PENDING" 2>/dev/null || true
    if [[ -f "$LEDGER" ]]; then
      assert_fixture_dir "$LEDGER_DIR"
      : > "$LEDGER" 2>/dev/null || true
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

if [[ -z "$SID" ]]; then
  emit "SOLEUR_COMPACTION_SKIPPED reason=no-session-id"
  exit 0
fi

# Commit the pending slot. Reached exactly once per real compaction.
COMMITTED=""
if [[ -f "$PENDING" ]]; then
  COMMITTED="$(head -1 "$PENDING" 2>/dev/null || true)"
  [[ -n "$COMMITTED" ]] || COMMITTED="unknown"
  assert_fixture_dir "$LEDGER_DIR"
  printf '%s\n' "$COMMITTED" >> "$LEDGER" 2>/dev/null || true
  rm -f "$PENDING" 2>/dev/null || true
fi

COUNT_TOTAL=0
COUNT_AUTO=0
if [[ -r "$LEDGER" ]]; then
  COUNT_TOTAL="$(grep -c . "$LEDGER" 2>/dev/null || true)"
  COUNT_AUTO="$(grep -cx 'auto' "$LEDGER" 2>/dev/null || true)"
fi
COUNT_TOTAL="${COUNT_TOTAL:-0}"
COUNT_AUTO="${COUNT_AUTO:-0}"

if [[ "$COUNT_TOTAL" -eq 0 ]]; then
  # No PreCompact was seen for this window. Honest silence beats a guess: the
  # transcript cannot supply the answer (finding 1 above).
  emit "SOLEUR_COMPACTION_SKIPPED reason=no-ledger-entry -- context was compacted but this session's compaction ledger is empty. Re-read the plan and spec before editing (hr-always-read-a-file-before-editing-it)."
  exit 0
fi

TRIGGER="$COMMITTED"
[[ -n "$TRIGGER" ]] || TRIGGER="$(tail -1 "$LEDGER" 2>/dev/null || true)"
case "$TRIGGER" in
  manual|auto) : ;;
  *) TRIGGER="unknown" ;;
esac

CLI="${SOLEUR_COMPACTION_CLI_VERSION:-}"
if [[ -z "$CLI" ]]; then
  CLI="$(timeout 5 claude --version 2>/dev/null | head -1 | awk '{print $1}' || true)"
fi
CLI="${CLI:-unknown}"

BRANCH="$(timeout 5 git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
BRANCH="${BRANCH:-unknown}"

PLAN=""
if [[ "$BRANCH" != "unknown" ]]; then
  for p in "$ROOT/knowledge-base/project/plans/"*"-${BRANCH}-plan.md"; do
    [[ -e "$p" ]] && PLAN="knowledge-base/project/plans/$(basename "$p")"
  done
fi
SPEC=""
[[ -d "$ROOT/knowledge-base/project/specs/$BRANCH" ]] \
  && SPEC="knowledge-base/project/specs/$BRANCH/"

THRESHOLD="${SOLEUR_COMPACTION_COUNT_THRESHOLD:-2}"
case "$THRESHOLD" in
  ''|*[!0-9]*) THRESHOLD=2 ;;   # a non-numeric seam makes (( )) evaluate false
esac                            # silently, skipping the branch rather than failing

RECOMMEND=false
if [[ "$TRIGGER" == "auto" ]] && (( COUNT_AUTO >= THRESHOLD )); then
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
