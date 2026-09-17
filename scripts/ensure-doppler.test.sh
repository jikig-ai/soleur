#!/usr/bin/env bash
# Unit suite for scripts/ensure-doppler.sh — the Doppler CLI bootstrap + state probe.
#
# ── WHAT THIS PINS, AND WHY IT IS NOT A TYPO TEST ───────────────────────────────────────────
# The SUT exists because a missing `doppler` binary reads, to an agent, as "this session has no
# observability access" — which sends it to an hourly probe or to SSH instead of installing a
# CLI. The value is therefore entirely in the STATE DISCRIMINATION, and the first revision of
# that discrimination was WRONG in a way no syntax check could catch: it asserted `doppler me`
# exits 0 and prints its error to stdout, matched on message text, and so reported `ready`
# against a CLI that had never been authenticated. Measured against v3.76.5 the real behaviour
# is stderr + exit 1. A green `--state` is worthless unless it can be driven to each of its four
# answers, so every case below drives one.
#
# The `unknown` case is the load-bearing one. rc!=0 alone cannot mean `unauthenticated`: a
# network fault exits non-zero too, and answering `unauthenticated` there sends the operator to
# a login flow that fixes nothing. T4 is the regression guard on that conflation.
#
# ── HARNESS CONTRACT ────────────────────────────────────────────────────────────────────────
# Accumulate-then-exit. Every case runs the REAL script against stub binaries in a per-run
# mktemp sandbox with a controlled PATH — never the operator's actual doppler, and never a
# fixed path (parallel worktrees are this repo's documented workflow). No case reaches the
# network: the install path is exercised only through its missing-dependency refusal.
#
# Traps deliberately avoided (work/SKILL.md):
#   1. A deliberately-nonzero command inside `$( )` aborts under `set -e` before fail() prints.
#      Every SUT invocation is wrapped `rc=0; out=$(…) || rc=$?`.
#   2. A loop over an empty data source exits 0 with ZERO coverage. CASES_RUN and the
#      pass/fail counters are reconciled at the end.
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SCRIPT_DIR}/ensure-doppler.sh"

passes=0
fails=0
CASES_RUN=0

pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() {
  fails=$((fails + 1))
  echo "  FAIL: $1" >&2
}

[[ -f "$SUT" ]] || { echo "FATAL: SUT not found at $SUT" >&2; exit 1; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

# A minimal PATH carrying only what the SUT legitimately needs, so a stub dir
# prepended to it fully controls which `doppler` resolves.
BASE_PATH="/usr/bin:/bin"

# make_stub <dir> <exit-code> <stderr-text>
make_stub() {
  local dir="$1" code="$2" msg="$3"
  mkdir -p "$dir"
  cat > "$dir/doppler" <<EOF
#!/usr/bin/env bash
if [[ -n "${msg}" ]]; then echo "${msg}" >&2; fi
exit ${code}
EOF
  chmod +x "$dir/doppler"
}

# Absolute bash: T6 strips PATH to a directory with no tools at all, so an
# interpreter resolved THROUGH PathN would vanish with them and the case would
# report rc=127 (command not found) instead of the SUT's own refusal.
BASH_ABS="$(command -v bash)"

# NOTE: this runs the SUT inside `$( )`. A counter incremented in here would be
# incremented in a SUBSHELL and lost — which is exactly what made the first run
# report cases_run=3 for 7 cases. Callers increment CASES_RUN themselves.
run_state() {
  local path="$1" installdir="$2"
  local out rc=0
  out="$(PATH="$path" DOPPLER_INSTALL_DIR="$installdir" "$BASH_ABS" "$SUT" --state 2>/dev/null)" || rc=$?
  printf '%s\n%s' "$out" "$rc"
}

echo "T1: --state reports 'missing' when no binary exists anywhere"
res="$(run_state "$BASE_PATH" "$SANDBOX/absent")"
CASES_RUN=$((CASES_RUN + 1))
out="$(head -n1 <<<"$res")"
[[ "$out" == "missing" ]] && pass "no binary -> missing" || fail "expected 'missing', got '$out'"

echo "T2: --state reports 'unauthenticated' on the real v3.76.5 signature (stderr + exit 1)"
make_stub "$SANDBOX/unauth" 1 "Doppler Error: you must provide a token"
res="$(run_state "$SANDBOX/unauth:$BASE_PATH" "$SANDBOX/absent")"
CASES_RUN=$((CASES_RUN + 1))
out="$(head -n1 <<<"$res")"
[[ "$out" == "unauthenticated" ]] && pass "token error -> unauthenticated" || fail "expected 'unauthenticated', got '$out'"

echo "T3: --state reports 'ready' when the CLI answers cleanly"
make_stub "$SANDBOX/ready" 0 ""
res="$(run_state "$SANDBOX/ready:$BASE_PATH" "$SANDBOX/absent")"
CASES_RUN=$((CASES_RUN + 1))
out="$(head -n1 <<<"$res")"
[[ "$out" == "ready" ]] && pass "exit 0 -> ready" || fail "expected 'ready', got '$out'"

echo "T4: a NETWORK failure is 'unknown', never 'unauthenticated' (the conflation guard)"
make_stub "$SANDBOX/netfail" 1 "Doppler Error: dial tcp: lookup api.doppler.com: no such host"
res="$(run_state "$SANDBOX/netfail:$BASE_PATH" "$SANDBOX/absent")"
CASES_RUN=$((CASES_RUN + 1))
out="$(head -n1 <<<"$res")"
if [[ "$out" == "unknown" ]]; then
  pass "unrecognised rc!=0 -> unknown (does not misroute to a login flow)"
else
  fail "expected 'unknown', got '$out' — a network fault must not read as unauthenticated"
fi

echo "T5: an already-present binary short-circuits and prints its path (no download)"
make_stub "$SANDBOX/present" 0 ""
rc=0
out="$(PATH="$SANDBOX/present:$BASE_PATH" DOPPLER_INSTALL_DIR="$SANDBOX/absent" "$BASH_ABS" "$SUT" 2>/dev/null)" || rc=$?
CASES_RUN=$((CASES_RUN + 1))
if [[ "$rc" -eq 0 && "$out" == "$SANDBOX/present/doppler" ]]; then
  pass "pre-installed -> exit 0 and prints path"
else
  fail "expected exit 0 + '$SANDBOX/present/doppler', got rc=$rc out='$out'"
fi

echo "T6: a missing prerequisite refuses with exit 2 rather than attempting an install"
mkdir -p "$SANDBOX/emptybin"
rc=0
out="$(PATH="$SANDBOX/emptybin" DOPPLER_INSTALL_DIR="$SANDBOX/absent" "$BASH_ABS" "$SUT" 2>&1)" || rc=$?
CASES_RUN=$((CASES_RUN + 1))
if [[ "$rc" -eq 2 ]]; then
  pass "no curl/tar/sha256sum -> exit 2"
else
  fail "expected exit 2, got rc=$rc out='$out'"
fi

echo "T7: the SUT never pipes \`doppler me\` (the construct that produced the false 'ready')"
# `$?` after a pipe is the LAST stage's status, which is how the original bug was measured
# into existence. Assert on the file directly — a pipeline here would fail open.
#
# `\|[^|]` is load-bearing: a bare `\|` also matches the FIRST character of `||`, so the
# previous form flagged `… me 2>&1 >/dev/null)" || rc=$?` — a logical OR that is precisely the
# CORRECT construct — and reported the fixed script as still broken. A single pipe is a `|`
# whose next character is not another `|`; the `$` arm keeps a trailing-pipe line matchable.
if grep -vE '^[[:space:]]*#' "$SUT" | grep -qE '(doppler|"?\$bin"?) me[^|]*\|([^|]|$)'; then
  fail "SUT pipes 'doppler me' — exit status would be the pipe's, not doppler's"
else
  pass "no piped 'doppler me' in the SUT"
fi
CASES_RUN=$((CASES_RUN + 1))

echo
echo "cases_run=$CASES_RUN passes=$passes fails=$fails"
if [[ "$CASES_RUN" -lt 7 ]]; then
  echo "FATAL: expected at least 7 invocations, saw $CASES_RUN — suite lost coverage" >&2
  exit 1
fi
if [[ $((passes + fails)) -ne "$CASES_RUN" ]]; then
  echo "FATAL: $((passes + fails)) verdicts for $CASES_RUN cases — a case decided nothing" >&2
  exit 1
fi
[[ "$fails" -eq 0 ]] || exit 1
echo "ensure-doppler: all $passes assertions passed"
