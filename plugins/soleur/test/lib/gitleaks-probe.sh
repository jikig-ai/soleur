#!/usr/bin/env bash
# Shared gitleaks runnability probe + per-arm skip contract for TEST SUITES.
#
# SCOPE IS DELIBERATE — test suites only. The two production consumers are NOT
# here and should not be: `.claude/hooks/git-commit-secret-scan.sh` carries a
# 124/137 retry ladder that exists nowhere else, and
# `plugins/soleur/skills/code-to-prd/scripts/code-to-prd.sh` just exits 2 with no
# skip semantics at all. Those are three different FAILURE POLICIES, and a helper
# spanning all three would generalise over the one part that actually differs.
# Inlining code used once is the right call; this file exists because the four
# suites' copies were line-for-line identical (#8266 review).
#
# `command -v` only proves the name RESOLVES; an unpinned version-manager shim
# resolves and exits non-zero on every call, which is how an unrunnable gitleaks
# got reported as a verdict about the rules. The probe runs the binary.
#
# `timeout` is optional (stock macOS ships neither `timeout` nor `gtimeout`):
# absent, the probe runs unbounded rather than misreporting a runnable gitleaks.
# `${a[@]+"${a[@]}"}` — not `"${a[@]}"` — because bash 3.2 treats an EMPTY array
# as unbound under `set -u`, which is exactly that no-timeout host.

GITLEAKS_PIN_REMEDIATION="CI pins gitleaks 8.24.2 — install that version or pin it in your version manager."

# gl_probe -> sets HAVE_GITLEAKS (1|0) and GITLEAKS_REASON.
gl_probe() {
  HAVE_GITLEAKS=1
  GITLEAKS_REASON=""
  if ! command -v gitleaks >/dev/null 2>&1; then
    HAVE_GITLEAKS=0
    GITLEAKS_REASON="gitleaks is not on PATH"
    return 0
  fi
  local _probe_err _probe_rc=0 TO=()
  _probe_err=$(mktemp)
  if command -v timeout >/dev/null 2>&1; then TO=(timeout 10)
  elif command -v gtimeout >/dev/null 2>&1; then TO=(gtimeout 10); fi
  ${TO[@]+"${TO[@]}"} gitleaks version >/dev/null 2>"$_probe_err" || _probe_rc=$?
  if [[ "$_probe_rc" != "0" ]]; then
    HAVE_GITLEAKS=0
    GITLEAKS_REASON="gitleaks is not runnable here (rc=$(printf '%q' "$_probe_rc"), $(printf '%q' "$(head -n1 "$_probe_err")"))"
  fi
  rm -f "$_probe_err"
}

# Per-ARM skip, never per-suite. A skipped arm is not a pass: under CI=true the
# suite exits 1 at the end naming every skipped arm (CI installs the pinned
# binary, so a skip there is a broken environment); locally it exits 0 after
# listing them, so an unrunnable host tool is not reported as a subject verdict.
# ADR-188: a guard that can silently disarm must FAIL in CI and SKIP only locally.
SKIPPED_ARMS=()
_skip_arm() {  # $1 = arm label, $2 = reason
  echo "SKIP — $1 — $2. ${GITLEAKS_PIN_REMEDIATION}"
  SKIPPED_ARMS+=("$1")
}

# _needs_gl <arm label> -> 0 when a runnable gitleaks exists; otherwise records
# the skip (naming the arm and the probe's reason) and returns 1 so the caller
# can `_needs_gl "$label" || return 0`.
_needs_gl() {
  [[ "$HAVE_GITLEAKS" == 1 ]] && return 0
  _skip_arm "$1" "$GITLEAKS_REASON"
  return 1
}
