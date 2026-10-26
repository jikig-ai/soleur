#!/usr/bin/env bash
# content-trigger.sh — the gate's config-declared CONTENT trigger (#10924 P4b).
#
# Sourced by plugins/soleur/scripts/affected-tests.sh. Declarations only: no
# `exit`, no top-level side effects — the one exit site stays finish() in
# common.sh, which calls affected_ct_hook just before it prints the verdict.
#
# WHAT IT IS. A selector that matches diff PATHS cannot see a test fixture that
# merely NAMES a path (a `knowledge-base/` literal in a new test file): the path
# is a test-tree path, the dependency is in the text. The three flat keys in
# `.soleur-test-gate.json` —
#     content_trigger_pattern   fixed string (never a regex)
#     content_trigger_paths     globs the scan is limited to
#     content_trigger_command   what to run when the string is ADDED there
# — declare one such rule. When the diff adds a line (tracked files) or holds a
# line (untracked files) containing the pattern, in a file under the globs, a
# passing run that the operator did not make `--full` additionally runs the
# command. The plugin stays repo-agnostic: nothing here names a repository suite.
#
# FAIL DIRECTION. Anything that stops the scan from deciding (no base ref, a git
# failure, a path git C-quotes, an untracked tree too large to read) RUNS the
# command. A missed ratchet is a CI-only red; a spurious run is a few minutes.
#
# Variables are `_ct_`-prefixed locals; results travel through the AFFECTED_CT_*
# globals. The scan keeps its working data in variables, never in scratch files:
# nothing to register with affected_mktemp, nothing to leak on an early exit.

AFFECTED_CT_PATTERN=""
AFFECTED_CT_COMMAND=""
AFFECTED_CT_PATHS=()

# Scan results.
AFFECTED_CT_STATE=none   # none | fired | scan-error
AFFECTED_CT_LEG=""       # which leg could not decide (scan-error only)

# Hook results, read by finish().
AFFECTED_CT_OUT_RC=""
AFFECTED_CT_OUT_REASON=""
AFFECTED_CT_OUT_RESET=0  # 1 => the command ran on an inert diff: finish() replaces mode and counts
AFFECTED_CT_OUT_FIELD=""

# Untracked-leg bounds: past either the verdict is "could not decide" (command runs).
# The first bounds the listing the glob loop walks, the second the per-file reads.
AFFECTED_CT_MAX_LISTED=20000
AFFECTED_CT_MAX_READ=500

# _affected_ct_in_globs <path> — rc 0 when the path matches a configured glob.
_affected_ct_in_globs() {
  local _ct_p="$1" _ct_g
  for _ct_g in ${AFFECTED_CT_PATHS[@]+"${AFFECTED_CT_PATHS[@]}"}; do
    affected_glob_match "$_ct_p" "$_ct_g" && return 0
  done
  return 1
}

# affected_ct_scan — sets AFFECTED_CT_STATE / _LEG; returns at the first hit.
#
#   base:      --base, else origin/main, else origin/master — never @{upstream}
#              (on a pushed feature branch it hides every pushed fixture);
#              then `git merge-base <base> HEAD`.
#   tracked:   ONE `git diff -U0 --text` of the working tree against the merge-base
#              (committed + staged + unstaged), parsed by an awk state machine so
#              a header, a path or a removal line can never count as added text.
#              `--text` makes git diff files marked `-diff`/`binary` or holding NUL.
#   untracked: `git ls-files --others --exclude-standard`, limited to the globs,
#              regular files only (a symlink is not read), each read with
#              `grep -aqF` (as text, like the tracked leg's `--text`; under `-q` GNU grep
#              exits 0 on a binary match either way, so `-a` is belt-and-braces for
#              greps that would otherwise answer `Binary file matches`).
affected_ct_scan() {
  AFFECTED_CT_STATE=none
  AFFECTED_CT_LEG=""
  local _ct_base="" _ct_mb="" _ct_b _ct_rc=0 _ct_p _ct_hits _ct_untr _ct_listed=0 _ct_read=0

  if ! declare -F affected_glob_match >/dev/null 2>&1; then
    AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG="glob-matcher"; return 0
  fi

  if [[ -n "${ARG_BASE:-}" ]]; then
    # A ref the operator named, handed to git as an operand: never an option.
    if [[ "$ARG_BASE" == -* ]]; then
      AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG="bad-base"; return 0
    fi
    _ct_base="$ARG_BASE"
  else
    for _ct_b in origin/main origin/master; do
      if git rev-parse --verify --quiet "$_ct_b" >/dev/null 2>&1; then
        _ct_base="$_ct_b"
        break
      fi
    done
  fi
  if [[ -z "$_ct_base" ]]; then
    AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG="no-base"; return 0
  fi
  _ct_mb="$(git merge-base "$_ct_base" HEAD 2>/dev/null)" || _ct_rc=$?
  if (( _ct_rc != 0 )) || [[ -z "$_ct_mb" ]]; then
    AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG="no-merge-base"; return 0
  fi

  # --- tracked leg ---------------------------------------------------------
  # The diff is piped straight into awk (which reads to EOF, so the producer can
  # never take a SIGPIPE) and only the matching PATHS are kept, in a variable:
  # no scratch file, so nothing to leak and no redirect target to prove absolute.
  # pipefail (set by the gate) turns a failing `git diff` into a non-zero status.
  #
  # The pattern travels in the environment: `awk -v` processes backslash
  # escapes, ENVIRON does not. State resets on every `diff --git`; the path comes
  # from the `+++ b/<path>` header (git appends a TAB when it contains a space);
  # nothing counts until the first `@@` of that file, so a header or path that
  # NAMES the pattern, or a removal line, can never fire. A header git C-quotes
  # (`+++ "b/..."`: a name holding a quote, backslash or control byte) cannot be
  # decoded here, so a quoted-name file that adds the pattern reports `?quoted`
  # and the scan declines to decide rather than dropping it.
  _ct_rc=0
  # `--no-renames`: a renamed file is then a delete plus an add, so moving a file that
  # already names the string INTO the globs (or editing it while moving) fires, as an
  # added file does; with rename detection git shows only the delta. `tr -d` keeps a
  # NUL (which `--text` can emit) from truncating a line in awks that stop at one.
  _ct_hits="$(git -c core.quotePath=false diff -U0 --text --no-color --no-ext-diff --no-textconv --no-renames \
    --src-prefix=a/ --dst-prefix=b/ "$_ct_mb" -- 2>/dev/null \
    | LC_ALL=C tr -d '\000' \
    | CT_PAT="$AFFECTED_CT_PATTERN" awk '
    BEGIN { pat = ENVIRON["CT_PAT"]; path = ""; inh = 0; seen = 0 }
    /^diff --git / { path = ""; inh = 0; seen = 0; next }
    inh == 0 && /^\+\+\+ / {
      p = substr($0, 5)
      sub(/\t$/, "", p)
      if (substr(p, 1, 1) == "\"") path = "?quoted"
      else if (substr(p, 1, 2) == "b/") path = substr(p, 3)
      else path = ""
      next
    }
    inh == 0 && /^@@ / { inh = 1; next }
    inh == 1 && substr($0, 1, 1) == "+" && seen == 0 && path != "" {
      if (index(substr($0, 2), pat) > 0) { print path; seen = 1 }
    }
  ')" || _ct_rc=$?
  if (( _ct_rc != 0 )); then
    AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG="diff"; return 0
  fi
  while IFS= read -r _ct_p; do
    [[ -n "$_ct_p" ]] || continue
    if [[ "$_ct_p" == "?quoted" ]]; then
      AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG="quoted-path"; return 0
    fi
    if _affected_ct_in_globs "$_ct_p"; then AFFECTED_CT_STATE=fired; return 0; fi
  done <<<"$_ct_hits"

  # --- untracked leg -------------------------------------------------------
  _ct_rc=0
  _ct_untr="$(git -c core.quotePath=false ls-files --others --exclude-standard 2>/dev/null)" || _ct_rc=$?
  if (( _ct_rc != 0 )); then
    AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG="ls-files"; return 0
  fi
  while IFS= read -r _ct_p; do
    [[ -n "$_ct_p" ]] || continue
    _ct_listed=$((_ct_listed + 1))
    if (( _ct_listed > AFFECTED_CT_MAX_LISTED )); then
      AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG="untracked-cap"; return 0
    fi
    if [[ "$_ct_p" == \"* ]]; then
      AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG="quoted-path"; return 0
    fi
    [[ -f "$_ct_p" && ! -L "$_ct_p" ]] || continue
    _affected_ct_in_globs "$_ct_p" || continue
    _ct_read=$((_ct_read + 1))
    if (( _ct_read > AFFECTED_CT_MAX_READ )); then
      AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG="untracked-cap"; return 0
    fi
    _ct_rc=0
    grep -aqF -- "$AFFECTED_CT_PATTERN" "$_ct_p" 2>/dev/null || _ct_rc=$?
    case "$_ct_rc" in
      0) AFFECTED_CT_STATE=fired; return 0 ;;
      1) : ;;
      *) AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG="grep"; return 0 ;;
    esac
  done <<<"$_ct_untr"
  return 0
}

# affected_ct_hook <rc> <reason> — called by finish() (armed only) on its way out.
# Sets AFFECTED_CT_OUT_*; never exits and never calls finish().
affected_ct_hook() {
  local _ct_rc="$1" _ct_reason="$2" _ct_crc=0
  AFFECTED_CT_OUT_RC="$_ct_rc"
  AFFECTED_CT_OUT_REASON="$_ct_reason"
  AFFECTED_CT_OUT_RESET=0
  AFFECTED_CT_OUT_FIELD=""

  # Only the exits that set the flag are decided here. An operator's --full,
  # test_command, --self-check, help, refusals and no-test exits never reach it.
  [[ "${AFFECTED_CT_ELIGIBLE:-0}" == 1 ]] || return 0

  # --explain: report what the scan sees, run nothing, add no marker field.
  if [[ "${ARG_EXPLAIN:-0}" == 1 ]]; then
    affected_ct_scan
    echo "CONTENT_TRIGGER armed=1 state=${AFFECTED_CT_STATE} paths=${#AFFECTED_CT_PATHS[@]}"
    return 0
  fi

  # A primary run that did not pass owns the verdict; the command adds nothing.
  if (( _ct_rc != 0 )); then
    AFFECTED_CT_OUT_FIELD=skipped
    return 0
  fi

  affected_ct_scan
  case "$AFFECTED_CT_STATE" in
    none)
      AFFECTED_CT_OUT_FIELD=clear
      return 0 ;;
    scan-error)
      AFFECTED_CT_OUT_FIELD=scan-error
      echo "affected-tests: the content-trigger scan could not decide (leg=$(affected_marker_field "$AFFECTED_CT_LEG")) — running the declared command." ;;
    *)
      AFFECTED_CT_OUT_FIELD=ran
      echo "affected-tests: content trigger fired (the configured string is added under the configured paths) — running the declared command." ;;
  esac

  # The command's result is a gate result: it runs under the same remaining
  # budget as the primary run, and its failure is the gate's failure.
  affected_bound bash -c "$AFFECTED_CT_COMMAND" || _ct_crc=$?
  if (( _ct_crc != 0 )); then
    (( _ct_crc == 137 )) && echo "affected-tests: the content-trigger command exited 137 (SIGKILL — OOM or kill escalation), not necessarily budget expiry." >&2
    if [[ ( "$_ct_crc" == 124 || "$_ct_crc" == 137 ) && "$AFFECTED_BUDGET_ACTIVE" == 1 && "${CI_NAME:-none}" != none ]]; then
      AFFECTED_CT_OUT_RC=6
      AFFECTED_CT_OUT_REASON=budget-deferred
      AFFECTED_CT_OUT_FIELD=deferred
      echo "affected-tests: the content-trigger command did not finish within the shared budget — the selected tests passed; only the command is owed to CI."
    else
      AFFECTED_CT_OUT_RC=1
      AFFECTED_CT_OUT_REASON=content-trigger-failed
      AFFECTED_CT_OUT_FIELD=failed
      echo "CONTENT_TRIGGER_FAILED rc=$_ct_crc"
      echo "  remedy: run the content_trigger_command from .soleur-test-gate.json directly (bash -c '<command>'), fix it, re-run the gate"
    fi
  fi

  # An inert diff that nonetheless ran the command is no longer "docs-only":
  # keep the pass line honest, and keep changed-file counts (the inert path's
  # unit) out of a marker that describes a command run.
  if [[ "$_ct_reason" == inert ]]; then
    AFFECTED_CT_OUT_RESET=1
    [[ "$AFFECTED_CT_OUT_RC" == 0 ]] && AFFECTED_CT_OUT_REASON=inert-content-trigger
  fi
  return 0
}
