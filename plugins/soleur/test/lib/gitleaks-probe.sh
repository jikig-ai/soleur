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

# Bounded external invocation (#7697). The wedged-holder incident was a
# gitleaks/git child parked in anon_pipe_read while its parent held the
# repo-wide test-all lock for 4.6 days — every external call the suites make
# must carry an exec-boundary deadline. gl_run wraps timeout(1) around the
# command, closes its stdin, and suppresses any credential prompt, so a wedge
# returns rc=124 instead of parking a suite (and the gate lock) forever.
# The timeout binary is resolved ONCE at source time; a host with neither
# `timeout` nor `gtimeout` (stock macOS) emits one [note] and runs unbounded —
# the file's documented degrade posture, never a hard dependency.
_GL_TIMEOUT_CMD=()
if command -v timeout >/dev/null 2>&1; then _GL_TIMEOUT_CMD=(timeout)
elif command -v gtimeout >/dev/null 2>&1; then _GL_TIMEOUT_CMD=(gtimeout)
else
  echo "[note] gitleaks-probe: timeout/gtimeout absent — suite invocations run unbounded (#7697 degrade)" >&2
fi

# gl_run <bound_s> <cmd> [args...] — exit code is the command's; 124 means the
# bound fired. stdin is /dev/null and GIT_TERMINAL_PROMPT=0 so nothing in the
# chain can wait on a terminal or a pipe-read that will never be satisfied.
gl_run() {
  local bound="${1:-120}"
  shift
  [[ "$bound" =~ ^[0-9]+$ ]] || bound=120
  if ((${#_GL_TIMEOUT_CMD[@]})); then
    env GIT_TERMINAL_PROMPT=0 "${_GL_TIMEOUT_CMD[@]}" -k 5 "$bound" "$@" </dev/null
  else
    env GIT_TERMINAL_PROMPT=0 "$@" </dev/null
  fi
}

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
  if command -v timeout >/dev/null 2>&1; then TO=(timeout 10)
  elif command -v gtimeout >/dev/null 2>&1; then TO=(gtimeout 10); fi
  # stderr captured inline, not via mktemp: a tempfile here would need an owning
  # trap (ADR-129, lint-trap-tempfile-ownership rule c) that a sourced library
  # cannot register without stealing the caller's EXIT trap. Same shape as the
  # production hook's probe.
  _probe_err="$( { ${TO[@]+"${TO[@]}"} gitleaks version >/dev/null; } 2>&1 )" || _probe_rc=$?
  if [[ "$_probe_rc" != "0" ]]; then
    HAVE_GITLEAKS=0
    GITLEAKS_REASON="gitleaks is not runnable here (rc=$(printf '%q' "$_probe_rc"), $(printf '%q' "${_probe_err%%$'\n'*}"))"
  fi
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
