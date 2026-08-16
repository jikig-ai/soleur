#!/usr/bin/env bash
# Mutation battery for scripts/verify-lockfile-guards.sh — the ADR-191 discoverability probe.
#
# What this pins is narrow and specific: the wrapper must not be able to report success
# when a guard beneath it has failed. That is the whole reason it exists as a probe — the
# preflight Check 10 contract matches on its success marker, so a wrapper that prints the
# marker unconditionally would report a healthy invariant against an arbitrarily broken
# tree, which is worse than having no probe.
#
# Row 1 is deliberately adversarial: the stub guard PRINTS its own "OK" line and THEN
# exits non-zero. A wrapper keying on output rather than exit status passes that row; one
# keying on exit status does not. The guards' own coverage lives in their batteries —
# nothing here re-tests them.
set -euo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

WRAPPER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify-lockfile-guards.sh"
[[ -r "$WRAPPER" ]] || {
  echo "FATAL: wrapper not readable at $WRAPPER" >&2
  exit 2
}

MARKER='verify-lockfile-guards: OK'
passes=0
fails=0
asserted=0
pass() {
  passes=$((passes + 1))
  asserted=$((asserted + 1))
  echo "[ok] $*"
}
fail() {
  fails=$((fails + 1))
  asserted=$((asserted + 1))
  echo "[FAIL] $*" >&2
}

SANDBOX_ROOT=$(mktemp -d -t verify-lockfile-guards.XXXXXXXX) || {
  echo "FATAL: mktemp failed" >&2
  exit 2
}
trap 'rm -rf "$SANDBOX_ROOT"' EXIT

# Builds a synthetic repo whose two guards are stubs with the given exit codes. The
# wrapper resolves its own directory via `git rev-parse --show-toplevel`, so the sandbox
# must be a real repo.
make_repo() {
  local name="$1"
  local rc1="$2"
  local rc2="$3"
  local d="$SANDBOX_ROOT/$name"
  mkdir -p "$d/scripts" || return 2
  git -C "$d" init -q -b main || return 2
  cp "$WRAPPER" "$d/scripts/" || return 2
  # Each stub prints the SAME success line the real guard prints before exiting, so a
  # wrapper that greps output instead of checking status cannot tell the rows apart.
  printf '#!/usr/bin/env bash\necho "lint-dual-lockfile: OK"\nexit %s\n' "$rc1" > "$d/scripts/lint-dual-lockfile.sh" || return 2
  printf '#!/usr/bin/env bash\necho "lint-workflow-install-sites: OK"\nexit %s\n' "$rc2" > "$d/scripts/lint-workflow-install-sites.sh" || return 2
  printf 'x\n' > "$d/README.md" || return 2
  git -C "$d" add -A || return 2
  printf '%s' "$d"
}

# Asserts BOTH halves of the contract on one run: the exit status the caller sees, and
# whether the marker Check 10 matches on was emitted. Checking only the status would
# leave the marker free to print on a red run.
expect() {
  local repo="$1" want_rc="$2" want_marker="$3" label="$4" out rc
  out=$(cd "$repo" && bash scripts/verify-lockfile-guards.sh 2>&1) || rc=$?
  rc=${rc:-0}
  if [[ "$rc" != "$want_rc" ]]; then
    fail "$label — expected rc=$want_rc, got $rc"
    return
  fi
  if [[ "$want_marker" == yes ]]; then
    if [[ "$out" != *"$MARKER"* ]]; then
      fail "$label — rc correct but success marker absent"
      return
    fi
  else
    if [[ "$out" == *"$MARKER"* ]]; then
      fail "$label — success marker printed on a failing run"
      return
    fi
  fi
  pass "$label"
}

# --- CONTROL: both guards green. Without this row every RED row below proves nothing,
# because a wrapper that always exits non-zero would satisfy them all. ---
CONTROL=$(make_repo control 0 0) || {
  echo "FATAL: sandbox setup failed" >&2
  exit 2
}
expect "$CONTROL" 0 yes "CONTROL both guards green — rc=0 AND marker printed"

# --- Row 1: first guard fails. `set -e` must abort before the second guard runs. ---
R1=$(make_repo row1 1 0)
expect "$R1" 1 no "row1 first guard RED (while printing its own OK line) — marker withheld"

# --- Row 2: second guard fails. The failure is downstream of a green first guard, which
# is the case a wrapper keying on the first exit status alone would miss. ---
R2=$(make_repo row2 0 1)
expect "$R2" 1 no "row2 second guard RED after a green first — marker withheld"

# --- Row 3: both fail. ---
R3=$(make_repo row3 1 1)
expect "$R3" 1 no "row3 both guards RED — marker withheld"

# --- H1: the suite's own executed-assertion floor. ---
# Floors PASSES, never `asserted` — `asserted` is incremented by pass() AND fail() alike,
# so it measures that assertions RAN and never that they CONCLUDED. Emitted WITHOUT
# routing through fail(), because a floor dispatched through the helper it backstops is
# disarmed by the same one-line edit it exists to catch. See
# knowledge-base/project/learnings/security-issues/2026-08-16-a-guard-asserting-absence-was-backwards-and-my-floors-counted-the-wrong-thing.md
MIN_ASSERTIONS=4
if [[ $((passes + fails)) -ne $asserted ]]; then
  echo "[FAIL] H1 counter reconciliation: ${passes} passed + ${fails} failed != ${asserted} asserted — an assertion counter is not incrementing, so this run cannot be trusted" >&2
  exit 1
fi
if [[ $passes -lt $MIN_ASSERTIONS ]]; then
  echo "[FAIL] H1 only ${passes} assertion(s) PASSED, below the floor of ${MIN_ASSERTIONS} — assertions were neutered or skipped" >&2
  exit 1
fi

echo
echo "verify-lockfile-guards.test.sh: ${passes} passed, ${fails} failed, ${asserted} assertion(s) executed (floor ${MIN_ASSERTIONS})"
[[ $fails -eq 0 ]] || exit 1
