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
# APPEND-ONLY FAILURE LEDGER (ADR-193). A counter reconciliation cannot be this suite's
# backstop: `passes + fails == CASES_RUN` is INVARIANT under the exact substitution it has
# to detect. Redirect fail()'s increment into `passes` and the sum is unchanged, `fails` is
# 0, and the suite exits 0 while still printing `FAIL:` to stderr — measured on this file.
# An entry here can only be APPENDED, so silencing the verdict means deleting evidence
# rather than moving a number between two buckets that are summed together.
FAILED=()

pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() {
  fails=$((fails + 1))
  FAILED+=("$1")
  echo "  FAIL: $1" >&2
}

# INSTRUMENT SELF-TEST — a positive control proving both helpers still RECORD, run before
# any real case so the unwind is a reset to zero rather than a slice. A floor that counts
# assertions cannot see a `fail()` that counts but does not record, nor a `pass()` that
# records nothing; only driving both and reading all three observables can.
_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
pass "instrument self-test: pass() records (EXPECTED — unwound)"
fail "instrument self-test: fail() records (EXPECTED — unwound, not a real failure)"
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record (passes %s->%s, fails %s->%s, ledger %s->%s)\n' \
    "$_iv_p" "$passes" "$_iv_f" "$fails" "$_iv_n" "${#FAILED[@]}" >&2
  exit 1
fi
passes=0; fails=0; FAILED=(); CASES_RUN=0

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

# ── `ready` MUST MEAN INVOCABLE ────────────────────────────────────────────────────────────
# The --state resolver falls back to $INSTALL_DIR, so a binary that is NOT on PATH
# authenticates fine and printed a bare `ready`. The caller then runs `doppler run ...`, gets
# `command not found`, and is back at "this session has no observability access" — the
# misdiagnosis this whole file exists to prevent. Measured 2026-09-17 on the operator machine,
# where doppler lives in ~/.local/bin and is not on the default PATH. The NON---state branch
# already emitted the export hint; only the agent-facing branch did not, which is backwards.
echo "T8: --state says 'ready' for an off-PATH binary but MUST emit the PATH remedy"
offdir="$SANDBOX/offpath"; mkdir -p "$offdir"
printf '#!/usr/bin/env bash\nexit 0\n' > "$offdir/doppler"; chmod +x "$offdir/doppler"
minp="$SANDBOX/minbin"; mkdir -p "$minp"
for b in bash grep command uname mktemp dirname sed; do
  src="$(command -v "$b" 2>/dev/null)" && [[ -n "$src" ]] && ln -sf "$src" "$minp/" 2>/dev/null
done
# Positive control: doppler must genuinely be absent from this PATH, or the case is vacuous.
if PATH="$minp" command -v doppler >/dev/null 2>&1; then
  fail "T8 harness is vacuous — doppler resolved on the minimal PATH"
else
  t8_out="$(PATH="$minp" DOPPLER_INSTALL_DIR="$offdir" "$BASH_ABS" "$SUT" --state 2>/dev/null)"
  t8_err="$(PATH="$minp" DOPPLER_INSTALL_DIR="$offdir" "$BASH_ABS" "$SUT" --state 2>&1 >/dev/null)"
  if [[ "$t8_out" == "ready" ]] && grep -qi 'not on PATH' <<<"$t8_err" && grep -q 'export PATH' <<<"$t8_err"; then
    pass "off-PATH binary -> stdout stays 'ready', stderr carries the export remedy"
  else
    fail "off-PATH 'ready' carried no remedy — out='$t8_out' err='$t8_err'"
  fi
fi
CASES_RUN=$((CASES_RUN + 1))

# ── AN UNRECOGNISED FLAG MUST NOT TRIGGER AN INSTALL ───────────────────────────────────────
# Only `--state` was recognised and there was no else-arm, so `--status` fell through to the
# download path and printed a filesystem path on stdout. A caller branching on the four state
# words matches none of them and takes its default arm.
echo "T9: an unknown flag is EX_USAGE (64), not a silent install"
t9_out="$("$BASH_ABS" "$SUT" --status 2>/dev/null)"; t9_rc=$?
CASES_RUN=$((CASES_RUN + 1))
if [[ "$t9_rc" -eq 64 && -z "$t9_out" ]]; then
  pass "unknown flag -> exit 64, nothing printed to stdout"
else
  fail "unknown flag did not refuse — rc=$t9_rc out='$t9_out'"
fi

# ── A REVOKED TOKEN IS `unauthenticated`, NOT `unknown` ────────────────────────────────────
# MEASURED 2026-09-17 against the real v3.76.5 CLI: a revoked/expired token reports
# `Doppler Error: Invalid Auth token`. The original alternation carried the literal
# `invalid token`, which does NOT match that string, so the most common real auth failure fell
# to `unknown` — and the runbook tells the operator `unknown` is explicitly NOT a token
# problem and that a login flow "fixes nothing". That steers them away from the one fix that
# works. The fixture is the CLI's measured wording, not a paraphrase.
echo "T10: the real 'Invalid Auth token' wording classifies as unauthenticated"
stub="$SANDBOX/revoked"; mkdir -p "$stub"
cat > "$stub/doppler" <<'DEOF'
#!/usr/bin/env bash
echo "Unable to fetch actor" >&2
echo "Doppler Error: Invalid Auth token" >&2
exit 1
DEOF
chmod +x "$stub/doppler"
t10_out="$(PATH="$stub:$PATH" DOPPLER_INSTALL_DIR="$stub" "$BASH_ABS" "$SUT" --state 2>/dev/null)"
CASES_RUN=$((CASES_RUN + 1))
if [[ "$t10_out" == "unauthenticated" ]]; then
  pass "revoked-token wording -> unauthenticated (routes to the fix that works)"
else
  fail "a revoked token classified as '$t10_out' — the operator is steered away from re-auth"
fi

echo
echo "cases_run=$CASES_RUN passes=$passes fails=$fails ledger=${#FAILED[@]}"

# Every gate below reports with `printf` + `exit 1` DIRECTLY, never through pass()/fail() —
# a floor dispatched through the helper it backstops is disarmed by the same one-line edit
# that disarms every assertion under it. `[FATAL]` is the sentinel this repo's
# guard-vacuity-floor meta-suite matches on; a bare `FATAL:` is not in its vocabulary and
# scores the mutant CONSTRUCTION (non-zero, no sentinel) instead of FIRES.
_min_cases=10
if [[ "$CASES_RUN" -lt "$_min_cases" ]]; then
  printf '[FATAL] assertion floor: only %s invocation(s) ran, floor is %s — the suite lost coverage\n' \
    "$CASES_RUN" "$_min_cases" >&2
  exit 1
fi
if [[ $((passes + fails)) -ne "$CASES_RUN" ]]; then
  printf '[FATAL] %s verdicts for %s cases — a case decided nothing\n' \
    "$((passes + fails))" "$CASES_RUN" >&2
  exit 1
fi
# The ledger and the counter must agree. They are written by the same helper but are not the
# same KIND of observable, so a redirected increment moves one and not the other.
if [[ "${#FAILED[@]}" -ne "$fails" ]]; then
  printf '[FATAL] ledger/counter disagree: %s ledger entries vs fails=%s — the verdict machinery was tampered with\n' \
    "${#FAILED[@]}" "$fails" >&2
  exit 1
fi
if [[ "${#FAILED[@]}" -ne 0 ]]; then
  printf '[FATAL] %s failing assertion(s):\n' "${#FAILED[@]}" >&2
  printf '  - %s\n' "${FAILED[@]}" >&2
  exit 1
fi
echo "ensure-doppler: all $passes assertions passed"
