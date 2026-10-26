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
# passing non-full run additionally runs the command. The plugin stays
# repo-agnostic: nothing here names a repository suite.
#
# FAIL DIRECTION. Anything that stops the scan from deciding (no base ref, a git
# or mktemp failure) RUNS the command. A missed ratchet is a CI-only red; a spurious
# run is a few minutes.
#
# Variables are `_ct_`-prefixed locals; results travel through the AFFECTED_CT_*
# globals, and the scan is never called through `$(...)` (a subshell would lose
# the affected_mktemp scratch registration and leak the temp file).

AFFECTED_CT_PATTERN=""
AFFECTED_CT_COMMAND=""
AFFECTED_CT_PATHS=()

# Scan results.
AFFECTED_CT_STATE=none   # none | fired | scan-error
AFFECTED_CT_COUNT=0      # changed files under the globs that carry the pattern
AFFECTED_CT_LEG=""       # which leg could not decide (scan-error only)

# Hook results, read by finish().
AFFECTED_CT_OUT_RC=""
AFFECTED_CT_OUT_REASON=""
AFFECTED_CT_OUT_MODE=""
AFFECTED_CT_OUT_COUNTS=0 # 1 => finish() replaces ran/of/skipped with `-`
AFFECTED_CT_OUT_FIELD=""

# _ct_in_globs <path> — rc 0 when the path matches a configured glob.
_ct_in_globs() {
  local _ct_p="$1" _ct_g
  for _ct_g in ${AFFECTED_CT_PATHS[@]+"${AFFECTED_CT_PATHS[@]}"}; do
    affected_glob_match "$_ct_p" "$_ct_g" && return 0
  done
  return 1
}

# affected_ct_scan — sets AFFECTED_CT_STATE / _COUNT / _LEG.
#
#   base:      --base, else origin/main, else origin/master — never @{upstream}
#              (on a pushed feature branch it hides every pushed fixture);
#              then `git merge-base <base> HEAD`.
#   tracked:   ONE `git diff -U0` of the working tree against the merge-base
#              (committed + staged + unstaged), parsed by an awk state machine so
#              a header, a path or a removal line can never count as added text.
#   untracked: `git ls-files --others --exclude-standard`, limited to the globs,
#              each file read with `grep -IqF` (binary skipped).
affected_ct_scan() {
  AFFECTED_CT_STATE=none
  AFFECTED_CT_COUNT=0
  AFFECTED_CT_LEG=""
  local _ct_base="" _ct_mb="" _ct_b _ct_rc=0 _ct_p _ct_diff _ct_hits _ct_untr

  if ! declare -F affected_glob_match >/dev/null 2>&1; then
    AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG=glob-matcher; return 0
  fi
  if [[ -z "$AFFECTED_CT_PATTERN" ]] || ((${#AFFECTED_CT_PATHS[@]} == 0)); then
    AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG=config; return 0
  fi

  if [[ -n "${ARG_BASE:-}" ]]; then
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
    AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG=no-base; return 0
  fi
  _ct_mb="$(git merge-base "$_ct_base" HEAD 2>/dev/null)" || _ct_rc=$?
  if (( _ct_rc != 0 )) || [[ -z "$_ct_mb" ]]; then
    AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG=no-merge-base; return 0
  fi

  # --- tracked leg ---------------------------------------------------------
  affected_mktemp ct-diff || { AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG=mktemp; return 0; }
  _ct_diff="$AFFECTED_TMP"
  affected_mktemp ct-hits || { AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG=mktemp; return 0; }
  _ct_hits="$AFFECTED_TMP"
  _ct_rc=0
  git -c core.quotePath=false diff -U0 --no-color --no-ext-diff --no-textconv -M \
    --src-prefix=a/ --dst-prefix=b/ "$_ct_mb" -- >"$_ct_diff" 2>/dev/null || _ct_rc=$?
  if (( _ct_rc != 0 )); then
    AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG=diff; return 0
  fi
  # The pattern travels in the environment: `awk -v` processes backslash
  # escapes, ENVIRON does not. State resets on every `diff --git`; the path comes
  # from the `+++ b/<path>` header (git appends a TAB when it contains a space);
  # nothing counts until the first `@@` of that file, so a header or path that
  # NAMES the pattern, or a removal line, can never fire. One path per matching file.
  _ct_rc=0
  CT_PAT="$AFFECTED_CT_PATTERN" awk '
    BEGIN { pat = ENVIRON["CT_PAT"]; path = ""; inh = 0; seen = 0 }
    /^diff --git / { path = ""; inh = 0; seen = 0; next }
    inh == 0 && /^\+\+\+ / {
      p = substr($0, 5)
      sub(/\t$/, "", p)
      if (substr(p, 1, 2) == "b/") path = substr(p, 3); else path = ""
      next
    }
    inh == 0 && /^@@ / { inh = 1; next }
    inh == 1 && /^@@ / { next }
    inh == 1 && substr($0, 1, 1) == "+" && seen == 0 && path != "" {
      if (index(substr($0, 2), pat) > 0) { print path; seen = 1 }
    }
  ' "$_ct_diff" >"$_ct_hits" 2>/dev/null || _ct_rc=$?
  if (( _ct_rc != 0 )); then
    AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG=awk; return 0
  fi
  while IFS= read -r _ct_p; do
    [[ -n "$_ct_p" ]] || continue
    if _ct_in_globs "$_ct_p"; then AFFECTED_CT_COUNT=$((AFFECTED_CT_COUNT + 1)); fi
  done <"$_ct_hits"

  # --- untracked leg -------------------------------------------------------
  affected_mktemp ct-untracked || { AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG=mktemp; return 0; }
  _ct_untr="$AFFECTED_TMP"
  _ct_rc=0
  git -c core.quotePath=false ls-files --others --exclude-standard >"$_ct_untr" 2>/dev/null || _ct_rc=$?
  if (( _ct_rc != 0 )); then
    AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG=ls-files; return 0
  fi
  while IFS= read -r _ct_p; do
    [[ -n "$_ct_p" && -f "$_ct_p" ]] || continue
    _ct_in_globs "$_ct_p" || continue
    _ct_rc=0
    grep -IqF -- "$AFFECTED_CT_PATTERN" "$_ct_p" 2>/dev/null || _ct_rc=$?
    case "$_ct_rc" in
      0) AFFECTED_CT_COUNT=$((AFFECTED_CT_COUNT + 1)) ;;
      1) : ;;
      *) AFFECTED_CT_STATE=scan-error; AFFECTED_CT_LEG=grep; return 0 ;;
    esac
  done <"$_ct_untr"

  (( AFFECTED_CT_COUNT > 0 )) && AFFECTED_CT_STATE=fired
  return 0
}

# affected_ct_hook <rc> <mode> <reason> — called by finish() on its way out.
# Sets AFFECTED_CT_OUT_* (the possibly-folded rc/reason/mode and the marker
# field); never exits and never calls finish().
affected_ct_hook() {
  local _ct_rc="$1" _ct_mode="$2" _ct_reason="$3" _ct_crc=0
  AFFECTED_CT_OUT_RC="$_ct_rc"
  AFFECTED_CT_OUT_REASON="$_ct_reason"
  AFFECTED_CT_OUT_MODE="$_ct_mode"
  AFFECTED_CT_OUT_COUNTS=0
  AFFECTED_CT_OUT_FIELD=""
  [[ "${AFFECTED_CT_ARMED:-0}" == 1 ]] || return 0

  # --explain: report what the scan sees, run nothing, add no marker field.
  if [[ "${AFFECTED_CT_EXPLAIN:-0}" == 1 ]]; then
    affected_ct_scan
    echo "CONTENT_TRIGGER armed=1 state=${AFFECTED_CT_STATE} paths=${#AFFECTED_CT_PATHS[@]}"
    return 0
  fi

  # Only the exits that set the flag are decided here. --full, test_command,
  # --self-check, help and refusals never run the command and print no field.
  [[ "${AFFECTED_CT_ELIGIBLE:-0}" == 1 ]] || return 0

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
      echo "affected-tests: the content-trigger scan could not decide (leg=$(affected_marker_field "$AFFECTED_CT_LEG")) — running the declared command." >&2 ;;
    *)
      AFFECTED_CT_OUT_FIELD=ran
      echo "affected-tests: content trigger fired ($AFFECTED_CT_COUNT changed file(s) add the configured string) — running the declared command." ;;
  esac

  # The command's result is a gate result: it runs under the same remaining
  # budget as the primary run, and its failure is the gate's failure.
  affected_bound bash -c "$AFFECTED_CT_COMMAND" || _ct_crc=$?
  case "$_ct_crc" in
    0) : ;;
    124|137)
      (( _ct_crc == 137 )) && echo "affected-tests: the content-trigger command exited 137 (SIGKILL — OOM or kill escalation), not necessarily budget expiry; deferral still applies." >&2
      if [[ "$AFFECTED_BUDGET_ACTIVE" == 1 && "${CI_NAME:-none}" != none ]]; then
        AFFECTED_CT_OUT_RC=6
        AFFECTED_CT_OUT_REASON=budget-deferred
        AFFECTED_CT_OUT_FIELD=skipped
      else
        AFFECTED_CT_OUT_RC=1
        AFFECTED_CT_OUT_REASON=content-trigger-failed
        AFFECTED_CT_OUT_FIELD=failed
        echo "affected-tests: the content-trigger command failed (rc=$_ct_crc)." >&2
      fi ;;
    *)
      AFFECTED_CT_OUT_RC=1
      AFFECTED_CT_OUT_REASON=content-trigger-failed
      AFFECTED_CT_OUT_FIELD=failed
      echo "affected-tests: the content-trigger command failed (rc=$_ct_crc)." >&2 ;;
  esac

  # An inert diff that nonetheless ran the command is no longer "docs-only":
  # keep the pass line honest and the counts (which were changed-file counts
  # for the inert path) out of the marker.
  if [[ "$_ct_reason" == inert && "$AFFECTED_CT_OUT_RC" == 0 ]]; then
    AFFECTED_CT_OUT_REASON=inert-content-trigger
    AFFECTED_CT_OUT_MODE=selected
    AFFECTED_CT_OUT_COUNTS=1
  fi
  return 0
}
