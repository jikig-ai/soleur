#!/usr/bin/env bash
# Companion suite for scripts/followthroughs/git-data-reboot-evidence-landed-8210.sh.
#
# Registered EXPLICITLY in scripts/test-all.sh: scripts/followthroughs/ matches no SUITE_GLOBS
# entry, so an unregistered .test.sh is an orphan that gates nothing while looking exactly like
# coverage (scripts/lint-orphan-test-suites.sh exists for that class).
#
# WHAT THIS PINS. The probe is the mechanism that closes #8210 unattended, so the load-bearing
# properties are (a) it reaches 0 ONLY when main's evidence records the reboot PASS *and* the
# rung-2 gate releases, and (b) since #8010 it separates "the gate looked and the answer was no"
# (exit 2, rendered NOT YET) from "the gate could not look" (exit 3, rendered CANNOT ESTABLISH by
# scripts/sweep-followthroughs.sh's rc -> WORD map). Before that split an anonymous rate limit on
# the sweeper's credential-less runner posted "the rehearsal simply has not run yet" on #8210
# every day for as long as the limit lasted.
#
# THE DECISION UNDER TEST IS TOKEN MEMBERSHIP, so the table below is driven token by token, one
# arm per member of BOTH sets — a wording match would pass for the wrong reason, and the gate's
# messages are prose that changes.
#
# THE GATE IS STUBBED, DELIBERATELY. The real gate's own refuse paths are pinned by
# tests/scripts/test-git-data-birth-readiness-gate.sh; duplicating them here would make this
# suite a second implementation of that contract and a second thing to drift. What only this
# suite can assert is the probe's READING of a gate verdict, so the stub is the narrowest thing
# that produces one: a chosen rc and a chosen output, with an optional STDERR preamble so the
# "select the token line by shape, never positionally" property is exercised rather than asserted.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SUT="$HERE/git-data-reboot-evidence-landed-8210.sh"

[[ -f "$SUT" ]] || { echo "FATAL: SUT not found at $SUT" >&2; exit 1; }
[[ -x "$SUT" ]] || { echo "FATAL: SUT not executable at $SUT" >&2; exit 1; }

# The fixture git environment (tripwire + builder) — sourcing ARMS the git-location tripwire, so
# a `git init` here can never land commits on the developer's live branch (#7833 / #7849).
# shellcheck source=../../plugins/soleur/test/lib/git-fixture-env.sh
source "${ROOT}/plugins/soleur/test/lib/git-fixture-env.sh" \
  || { echo "FATAL: cannot source git-fixture-env.sh" >&2; exit 2; }

fails=0; total=0
pass() { total=$((total + 1)); printf '  PASS: %s\n' "$1"; }
fail() { total=$((total + 1)); printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

# Instrument self-test: both counters must move before any verdict is trusted.
_p0=$total; pass "instrument" >/dev/null; _f0=$fails
fail "instrument" 2>/dev/null
if [[ $total -ne $((_p0 + 2)) || $fails -ne $((_f0 + 1)) ]]; then
  printf 'FATAL: instrument self-test -- pass()/fail() did not both move counters\n' >&2; exit 1
fi
total=$_p0; fails=$_f0

# Refuses an empty, relative, root or synthetic-fs fixture dir (byte-identical copy; the
# fixture-dir-operand-assert suite pins every tracked copy).
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

WORK="$(mktemp -d -t gdre-8210.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT
git_fixture_env "$WORK" || { printf 'FATAL: git_fixture_env refused %s\n' "$WORK" >&2; exit 2; }

# --- the fixture repo -------------------------------------------------------------------------
# A checkout shaped like the one the sweeper hands the probe: the probe COPY under
# scripts/followthroughs/, a gate library under tests/scripts/lib/, the template and the evidence
# beside each other under apps/web-platform/infra/, and refs/remotes/origin/main == HEAD.
#
# origin/main is written with `update-ref` rather than by adding a remote: the probe's own
# `git fetch -q origin main` is already `|| true`, so a remote would only add a network-shaped
# dependency to a decision the probe makes from `rev-parse --verify origin/main` alone.
#
# new_repo <name> [reboot-verdict|none] — builds $WORK/<name>. It deliberately PRINTS NOTHING:
# a `dir=$(new_repo …)` binding leaves the operand's root unresolvable to the P1a/P1b fixture
# scanners, so every later `git -C "$dir"` and every `> "$dir/…"` would read as an unguarded
# operand. Callers bind `$WORK/<name>` — a root the scanners can resolve — and assert it.
new_repo() {
  local d="$WORK/$1"; assert_fixture_dir "$d"
  local rv="${2:-PASS}"
  mkdir -p "$d/scripts/followthroughs" "$d/tests/scripts/lib" "$d/apps/web-platform/infra"
  cp "$SUT" "$d/scripts/followthroughs/git-data-reboot-evidence-landed-8210.sh"
  chmod +x "$d/scripts/followthroughs/git-data-reboot-evidence-landed-8210.sh"
  printf '#cloud-config\n# fixture\n' > "$d/apps/web-platform/infra/cloud-init-git-data.yml"
  {
    printf 'RUNG2_BOOT_REHEARSAL=PASS\n'
    printf 'RUNG2_EVIDENCE_URL=https://github.com/jikig-ai/soleur/actions/runs/34768256297\n'
    [[ "$rv" == "none" ]] || printf 'RUNG2_REBOOT_REOPEN=%s\n' "$rv"
  } > "$d/apps/web-platform/infra/git-data-rung2-boot-evidence.env"
  write_gate "$d"
  git -C "$d" init -q \
    && git -C "$d" add -A \
    && git -C "$d" commit -q -m "fixture tree" \
    && git -C "$d" update-ref refs/remotes/origin/main HEAD \
    || { printf 'FATAL: fixture repo %s could not be built\n' "$d" >&2; exit 2; }
}

# write_gate <repo> — the stub library. Reads its verdict from the environment so an arm changes
# nothing on disk: T8210_PRE goes to STDERR (ahead of the verdict, which is what the probe's
# `2>&1` capture may interleave), T8210_OUT to STDOUT, T8210_RC is the return.
write_gate() {
  local d="$1"; assert_fixture_dir "$d"
  cat > "$d/tests/scripts/lib/git-data-birth-readiness-gate.sh" <<'GATE'
git_data_rung2_rehearsal_gate() {
  [[ -n "${T8210_PRE:-}" ]] && printf '%s\n' "$T8210_PRE" >&2
  [[ -n "${T8210_OUT:-}" ]] && printf '%s\n' "$T8210_OUT"
  return "${T8210_RC:-0}"
}
GATE
}

# run_probe <repo> <gate-rc> <gate-stdout> [gate-stderr-preamble]
#
# Runs the probe COPY inside its own fixture and leaves the result in the globals RC and OUT. The
# probe derives its repo root from its own path, so it must be the copy, never "$SUT".
#
# NOT a command substitution: `rc=$(run_probe …)` would evaluate the whole arm in a subshell and
# OUT would never reach the assertions that read it — which is how the first draft of this file
# reported six green arms whose output was the empty string.
RC=0; OUT=""
run_probe() {
  local d="$1"; assert_fixture_dir "$d"
  RC=0
  OUT="$(T8210_RC="$2" T8210_OUT="$3" T8210_PRE="${4:-}" \
    bash "$d/scripts/followthroughs/git-data-reboot-evidence-landed-8210.sh" 2>&1)" || RC=$?
}

# expect <label> <want-rc>  — reads the LAST run_probe result.
expect() {
  if [[ "$RC" == "$2" ]]; then pass "$1 (rc=$RC)"; else fail "$1: want rc=$2, got rc=$RC"; printf '%s\n' "$OUT" >&2; fi
}
# want_out / deny_out <label> <needle>  — read against the LAST run_probe output.
want_out() { if printf '%s' "$OUT" | grep -qF -- "$2"; then pass "$1"; else fail "$1: output lacks '$2'"; fi; }
deny_out() { if printf '%s' "$OUT" | grep -qF -- "$2"; then fail "$1: output carries '$2'"; else pass "$1"; fi; }

# The two token sets, copied from the gate's contract (#8010) and from the probe's own `case`.
# Driven one arm per member: membership IS the decision, so a sampled table would leave the
# untested members free to fall into the wrong bucket.
CANNOT_TOKENS=(TOOLING_MISSING RUN_OFFLINE RUN_RATE_LIMITED RUN_UNRESOLVABLE RUN_SHA_UNREACHABLE
               RUN_HASH_UNCOMPUTABLE RUN_ARTIFACT_RECORD_UNREADABLE SENTRY_VERDICT_UNREADABLE)
MEASURED_TOKENS=(SENTRY_VERDICT_FATAL SENTRY_UNAVAILABLE_UNACKED SENTRY_ACK_MISMATCH RUN_NOT_FOUND
                 RUN_WRONG_WORKFLOW RUN_WRONG_EVENT RUN_NOT_MAIN RUN_NOT_COMPLETED RUN_NOT_SUCCESS
                 RUN_HASH_MISMATCH RUN_NO_EVIDENCE_ARTIFACT)

hold_line() { printf 'git_data_rung2_rehearsal_gate: HOLD [%s] — %s' "$1" "the remedy sentence for $1, which head -1 used to cut off"; }

echo "== rc 0: the evidence records the reboot PASS and the gate releases"
new_repo pass PASS; R_PASS="$WORK/pass"; assert_fixture_dir "$R_PASS"
run_probe "$R_PASS" 0 "git_data_rung2_rehearsal_gate: RELEASED — fixture"
expect "gate RELEASES over a PASS evidence -> PASS" 0
want_out "the PASS arm names the reboot proof" "the boot-time LUKS reopen (#8210) is proven"

echo "== rc 1: a landed non-PASS reboot verdict is a FAIL, never 'not run yet'"
new_repo failverdict FAIL; R_FAIL="$WORK/failverdict"; assert_fixture_dir "$R_FAIL"
run_probe "$R_FAIL" 0 ""
expect "RUNG2_REBOOT_REOPEN=FAIL -> FAIL" 1
want_out "the FAIL arm quotes the verdict it read" "RUNG2_REBOOT_REOPEN=FAIL"

echo "== rc 2: the MEASURED pre-conditions (the arms that never reach the gate)"
new_repo nokey none; R_NOKEY="$WORK/nokey"; assert_fixture_dir "$R_NOKEY"
run_probe "$R_NOKEY" 0 ""
expect "evidence with no RUNG2_REBOOT_REOPEN key -> NOT YET" 2
want_out "the no-key arm says it predates the reset arm" "predates the #8210"

new_repo noevidence PASS; R_NOEV="$WORK/noevidence"; assert_fixture_dir "$R_NOEV"
rm -f "$R_NOEV/apps/web-platform/infra/git-data-rung2-boot-evidence.env"
run_probe "$R_NOEV" 0 ""
expect "no evidence file on main -> NOT YET" 2
want_out "the no-evidence arm names the intended safe state" "intended safe state"

new_repo notmain PASS; R_BRANCH="$WORK/notmain"; assert_fixture_dir "$R_BRANCH"
printf 'drift\n' >> "$R_BRANCH/apps/web-platform/infra/cloud-init-git-data.yml"
git -C "$R_BRANCH" commit -q -am "move HEAD off origin/main" || { echo "FATAL: fixture commit failed" >&2; exit 2; }
run_probe "$R_BRANCH" 0 ""
expect "HEAD is not origin/main -> NOT YET" 2
want_out "the off-main arm refuses to grade this branch's payload" "not origin/main"

new_repo nolib PASS; R_NOLIB="$WORK/nolib"; assert_fixture_dir "$R_NOLIB"
rm -f "$R_NOLIB/tests/scripts/lib/git-data-birth-readiness-gate.sh"
run_probe "$R_NOLIB" 0 ""
expect "gate library unreadable -> NOT YET (not a verdict about the host)" 2

new_repo nofn PASS; R_NOFN="$WORK/nofn"; assert_fixture_dir "$R_NOFN"
printf '# a library that defines nothing\n' > "$R_NOFN/tests/scripts/lib/git-data-birth-readiness-gate.sh"
run_probe "$R_NOFN" 0 ""
expect "gate function absent after sourcing -> NOT YET" 2

echo "== rc 3: one arm per COULD-NOT-MEASURE token"
R="$R_PASS"
for t in "${CANNOT_TOKENS[@]}"; do
  run_probe "$R" 1 "$(hold_line "$t")"
  expect "could-not-measure token $t -> CANNOT ESTABLISH" 3
  want_out "$t: the verdict heading is CANNOT ESTABLISH" "CANNOT ESTABLISH:"
  want_out "$t: the bracketed token reaches the comment" "[$t]"
  want_out "$t: the remedy sentence is not truncated" "which head -1 used to cut off"
  deny_out "$t: does not also print the NOT YET heading" "NOT YET:"
done

echo "== rc 2: one arm per MEASURED refusal token"
for t in "${MEASURED_TOKENS[@]}"; do
  run_probe "$R" 1 "$(hold_line "$t")"
  expect "measured token $t -> NOT YET" 2
  want_out "$t: the verdict heading is NOT YET" "NOT YET:"
  want_out "$t: the bracketed token reaches the comment" "[$t]"
  deny_out "$t: does not also print the CANNOT ESTABLISH heading" "CANNOT ESTABLISH:"
done

echo "== an ABORT carrying a could-not-measure token is still CANNOT ESTABLISH"
# TOOLING_MISSING is the gate's ABORT, so it arrives with rc 2 and the word ABORT. Keying on the
# verdict WORD instead of the token would drop it into the NOT YET bucket.
run_probe "$R" 2 "git_data_rung2_rehearsal_gate: ABORT [TOOLING_MISSING] — jq is not installed"
expect "ABORT [TOOLING_MISSING] -> CANNOT ESTABLISH" 3
want_out "the ABORT arm still prints the token" "[TOOLING_MISSING]"

echo "== the verdict line is selected by SHAPE, not by position"
# A stderr preamble arrives first under the probe's `2>&1`. head -1 would report it as the cause.
PRE="git_data_rung2_rehearsal_gate: reading apps/web-platform/infra/git-data-rung2-boot-evidence.env"
run_probe "$R" 1 "$(hold_line RUN_RATE_LIMITED)" "$PRE"
expect "a stderr preamble ahead of the verdict does not change the rc" 3
want_out "the token line is the one printed, past the preamble" "[RUN_RATE_LIMITED]"
want_out "the preamble's own remedy tail survives" "which head -1 used to cut off"

echo "== a multi-line gate capture prints the WHOLE token line"
run_probe "$R" 1 "$(printf '%s\n%s\n%s' "noise before" "$(hold_line RUN_OFFLINE)" "noise after")"
expect "token on a middle line -> CANNOT ESTABLISH" 3
want_out "the whole middle line is printed" "$(hold_line RUN_OFFLINE)"

echo "== a TOKENLESS refusal falls back to NOT YET, never to CANNOT ESTABLISH"
# The gate's pre-#8010 arms refuse in prose. Fail-closed in the direction that keeps #8210 open.
run_probe "$R" 1 "git_data_rung2_rehearsal_gate: HOLD — STALE EVIDENCE. the payload moved"
expect "tokenless HOLD -> NOT YET" 2
want_out "the tokenless fallback still prints a cause" "STALE EVIDENCE"
deny_out "the tokenless fallback is not read as an instrument failure" "CANNOT ESTABLISH:"

echo "== the two verdicts share no heading, and each names its own remedy route"
run_probe "$R" 1 "$(hold_line RUN_RATE_LIMITED)"
expect "rate limit -> CANNOT ESTABLISH" 3
want_out "the instrument arm says it resolved the run anonymously" "ANONYMOUSLY"
want_out "the instrument arm points at the rehearsal runbook" "git-data-rung2-rehearsal.md"
deny_out "the instrument arm does not blame the payload" "payload has been edited"
run_probe "$R" 1 "$(hold_line RUN_HASH_MISMATCH)"
expect "hash mismatch -> NOT YET" 2
want_out "the measured arm says the gate looked" "MEASURED that"
want_out "the measured arm disclaims the instrument reading" "it exits 3, CANNOT ESTABLISH"

echo "== invariant: nothing that is not a released PASS may reach exit 0"
# Re-derived rather than restated: every fixture whose expected rc was not 0, re-run.
for spec in "failverdict:0:" "nokey:0:" "noevidence:0:" "notmain:0:" "nolib:0:" "nofn:0:"; do
  d="$WORK/${spec%%:*}"
  run_probe "$d" 0 "git_data_rung2_rehearsal_gate: RELEASED — fixture"
  if [[ "$RC" != 0 ]]; then pass "never-0: ${spec%%:*} (rc=$RC) even with a RELEASING gate"; else fail "never-0: ${spec%%:*} reached PASS"; fi
done
for t in "${CANNOT_TOKENS[@]}" "${MEASURED_TOKENS[@]}"; do
  run_probe "$R" 1 "$(hold_line "$t")"
  if [[ "$RC" != 0 ]]; then pass "never-0: HOLD [$t] (rc=$RC)"; else fail "never-0: HOLD [$t] reached PASS"; fi
done

# Assertion count, EXACT, reported with printf + exit, never through fail() (ADR-193).
EXACT=138
if (( total != EXACT )); then
  printf 'FATAL: %d assertions ran, expected exactly %d -- coverage changed; update EXACT deliberately\n' "$total" "$EXACT" >&2
  exit 1
fi
printf '\n%d assertions, %d failed\n' "$total" "$fails"
# THE VERDICT IS AN `exit`, NOT A TRAILING TEST EXPRESSION — the defect this suite's three
# siblings in this same PR reject BY NAME, shipped here anyway.
#
# A bare `[[ "$fails" -eq 0 ]]` makes the exit status a property of whichever line happens to
# be LAST: appending any command after it permanently greens the suite while it goes on
# printing accurate FAIL text, and deleting the line does the same. This file also installs
# `trap 'rm -rf "$WORK"' EXIT`, so an EXIT trap firing after it is one more way the status
# moves. `run_suite()` classifies on the exit code alone, and an explicit exit cannot be
# defeated by an append.
exit $(( fails > 0 ))
