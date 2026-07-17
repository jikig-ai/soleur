#!/usr/bin/env bash
# Attestation for sigpipe-triage-feasibility.sh.
#
# The load-bearing rung here is the NEGATIVE one (T2/T3). A triage probe that
# reads the corpus through a grep which does not early-exit reports zero
# reachable sites and closes the question with a false all-clear — an error in
# the opposite and more dangerous direction than the over-count that prompted
# this work. Nobody goes looking for a green.
#
# T3 exists because identity does not imply behaviour: the session that authored
# this probe resolved `grep` to GNU grep 3.12 and STILL drained, because a shell
# FUNCTION wrapped it. A `--version` check passes there. Only behaviour discriminates.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$SCRIPT_DIR/sigpipe-triage-feasibility.sh"
fails=0

pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n    -> %s\n' "$1" "${2:-}" >&2; fails=$((fails + 1)); }


# Run the probe with SIGPIPE restored to its DEFAULT disposition.
#
# Required on CI. The GitHub Actions runner is Node-spawned, Node sets SIGPIPE to
# SIG_IGN, and the runner's shell inherits it — and POSIX forbids a shell from
# resetting a signal it inherited as ignored, so `trap - PIPE` CANNOT undo this.
# Under SIG_IGN the probe correctly reports "the defect cannot occur here" and
# proceeds, which would make T2/T3 (whose whole subject is the REFUSAL path)
# fail for an environmental reason rather than a real one.
#
# Python's subprocess restores default signal dispositions in the child
# (restore_signals=True is its default), so this is a portable reset with no new
# dependency — python3 is present on every runner this repo uses.
run_probe_sigpipe_default() {
  python3 - "$@" <<'PYEOF'
import subprocess, sys
sys.exit(subprocess.run(sys.argv[1:]).returncode)   # restore_signals=True by default
PYEOF
}

echo "== sigpipe-triage-feasibility attestation =="

if [[ ! -f "$PROBE" ]]; then
  fail "probe exists" "$PROBE not found"
  exit 1
fi

# ---------------------------------------------------------------------------
# T1 — the probe runs clean on a host whose grep early-exits.
# ---------------------------------------------------------------------------
# `env -i` strips any interactive shell function shadowing grep. This is the
# CI-equivalent environment, and the only one a verdict may be taken from.
t1_out="$(run_probe_sigpipe_default env -i PATH="/usr/bin:/bin" HOME="$HOME" \
  /bin/bash "$PROBE" --pathspec 'apps/web-platform/infra/' 2>&1)"
t1_rc=$?
if [[ "$t1_rc" -eq 0 ]]; then
  pass "exits 0 on an early-exiting (CI-equivalent) grep"
else
  fail "exits 0 on an early-exiting grep" "rc=$t1_rc; output: $(printf '%s' "$t1_out" | tr '\n' '~')"
fi

# T1b — a verdict without its command is not a finding. Every emitted count must
# be accompanied by the command that produced it (AC2).
if printf '%s' "$t1_out" | grep -qF 'cmd:'; then
  pass "  ...and every emitted count carries its command (AC2)"
else
  fail "counts carry commands" "no 'cmd:' provenance lines in probe output"
fi

# ---------------------------------------------------------------------------
# T2 — NEGATIVE ARM: the probe REFUSES to run through a draining grep.
# ---------------------------------------------------------------------------
# A grep that reads to EOF before answering never lets the producer take
# SIGPIPE. Every reading through it is 0/N. The probe must exit non-zero rather
# than emit a verdict.
shimdir="$(mktemp -d)"
trap 'rm -rf "$shimdir"' EXIT

cat > "$shimdir/grep" <<'SHIM'
#!/usr/bin/env bash
# A draining grep: consumes stdin to EOF, then answers. Mirrors `ugrep -q`
# (no early exit) and the shell-function wrapper observed on the authoring host.
# Faithful: drains stdin ONLY when actually reading stdin. A shim that ignores a
# FILE argument is not a draining grep — it is a BROKEN grep, and it makes the
# probe HANG (grep waiting on a stdin nobody writes) instead of going red. The
# earlier shim did exactly that: the identity-check regression T3 exists to catch
# would TIME OUT rather than fail — in CI, an 8-minute red against a step
# budgeted ~3s. A guard that hangs on the regression it guards is not a guard.
has_file=0
for a in "$@"; do case "$a" in -*) ;; *) [[ -f "$a" ]] && has_file=1 ;; esac; done
if [[ " $* " == *" -q"* && "$has_file" -eq 0 ]]; then
  input="$(cat)"          # drain to EOF — the producer never gets SIGPIPE
  pat=""
  for a in "$@"; do case "$a" in -*) ;; *) pat="$a"; break ;; esac; done
  [[ "$input" == *"$pat"* ]] && exit 0 || exit 1
fi
exec /usr/bin/grep "$@"
SHIM
chmod +x "$shimdir/grep"

t2_out="$(run_probe_sigpipe_default env -i PATH="$shimdir:/usr/bin:/bin" HOME="$HOME" \
  /bin/bash "$PROBE" --pathspec 'apps/web-platform/infra/' 2>&1)"
t2_rc=$?
if [[ "$t2_rc" -ne 0 ]]; then
  pass "exits NON-ZERO through a draining grep (the false-all-clear guard)"
else
  fail "refuses a draining grep" \
    "rc=0 — the probe emitted a verdict through a grep that cannot observe the defect. This is the false all-clear the whole exercise exists to prevent."
fi

# T2b — the refusal must NAME the cause, not just exit non-zero. A bare rc=1 in a
# CI log gets retried; a named cause gets fixed.
if printf '%s' "$t2_out" | grep -qiE 'grep|early.?exit|drain'; then
  pass "  ...and the refusal names the grep as the cause"
else
  fail "refusal is diagnosable" "non-zero exit carried no grep-related explanation: $(printf '%s' "$t2_out" | tr '\n' '~')"
fi

# ---------------------------------------------------------------------------
# T3 — the guard is BEHAVIOURAL, not an identity check.
# ---------------------------------------------------------------------------
# This is the rung that pins the plan's own corrected premise. The shim below
# reports itself as GNU grep 3.12 (so any `--version` / identity assertion
# PASSES) while still draining. A probe that gates on identity emits a verdict
# here; a probe that gates on behaviour refuses.
cat > "$shimdir/grep" <<'SHIM'
#!/usr/bin/env bash
# Claims GNU identity, drains anyway — the exact shape that fooled the authoring
# session (GNU grep 3.12 resolved, shell function wrapping it, 0/N everywhere).
if [[ "${1:-}" == "--version" ]]; then
  echo "grep (GNU grep) 3.12"; exit 0
fi
# Faithful: drains stdin ONLY when actually reading stdin. A shim that ignores a
# FILE argument is not a draining grep — it is a BROKEN grep, and it makes the
# probe HANG (grep waiting on a stdin nobody writes) instead of going red. The
# earlier shim did exactly that: the identity-check regression T3 exists to catch
# would TIME OUT rather than fail — in CI, an 8-minute red against a step
# budgeted ~3s. A guard that hangs on the regression it guards is not a guard.
has_file=0
for a in "$@"; do case "$a" in -*) ;; *) [[ -f "$a" ]] && has_file=1 ;; esac; done
if [[ " $* " == *" -q"* && "$has_file" -eq 0 ]]; then
  input="$(cat)"
  pat=""
  for a in "$@"; do case "$a" in -*) ;; *) pat="$a"; break ;; esac; done
  [[ "$input" == *"$pat"* ]] && exit 0 || exit 1
fi
exec /usr/bin/grep "$@"
SHIM
chmod +x "$shimdir/grep"

t3_out="$(run_probe_sigpipe_default env -i PATH="$shimdir:/usr/bin:/bin" HOME="$HOME" \
  /bin/bash "$PROBE" --pathspec 'apps/web-platform/infra/' 2>&1)"
t3_rc=$?
if [[ "$t3_rc" -ne 0 ]]; then
  pass "refuses a GNU-IDENTIFYING grep that drains (behaviour, not identity)"
else
  fail "guard is behavioural" \
    "rc=0 against a grep that reports 'GNU grep 3.12' and drains anyway. An identity/--version check cannot discriminate this — and this is exactly the host that authored the probe. Output: $(printf '%s' "$t3_out" | tr '\n' '~')"
fi

echo
if [[ "$fails" -gt 0 ]]; then
  printf 'FAILED: %d check(s)\n' "$fails" >&2
  exit 1
fi
echo "all checks passed"
