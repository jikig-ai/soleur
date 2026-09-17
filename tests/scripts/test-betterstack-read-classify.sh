#!/usr/bin/env bash
# Tests for scripts/lib/betterstack-read-classify.sh (#8178).
#
# bs_read_classify partitions betterstack-query.sh's rc space into ONE token, so the
# birth poll and the inngest cutover classify a failed read identically instead of
# each re-deriving the partition. Hermetic: no network, no doppler, no live table.
#
# THE FUNCTION MUST RETURN 0 UNCONDITIONALLY. Its callers run under `set -e`, and a
# trailing `grep -q … && printf` would return non-zero on the common path and abort
# them. That is asserted directly (T13), not inferred from the token being right.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/betterstack-read-classify.sh"
pass=0; fail=0
FAILURES=()

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1)); echo "[ok] $label"
  else
    fail=$((fail + 1)); FAILURES+=("$label"); echo "[FAIL] $label $detail" >&2
  fi
}

# INSTRUMENT SELF-TEST (ADR-193). Drive both arms of _report once each and require
# both counters to have moved, then unwind — a suite whose reporter is stuck on the
# pass branch reports a clean run having asserted nothing.
_report "instrument self-test (pass arm)" ok
_report "instrument self-test (fail arm)" bad "expected — unwound below"
if (( pass < 1 || fail < 1 )); then
  printf 'FAIL: instrument self-test did not move both counters (pass=%d fail=%d)\n' "$pass" "$fail" >&2
  exit 1
fi
pass=0; fail=0; FAILURES=()

[[ -r "$LIB" ]] || { printf 'FAIL: library not readable at %s\n' "$LIB" >&2; exit 1; }
# shellcheck source=/dev/null
. "$LIB"

declare -F bs_read_classify >/dev/null \
  || { printf 'FAIL: bs_read_classify not defined after sourcing %s\n' "$LIB" >&2; exit 1; }

_body() { local f; f="$(mktemp)"; printf '%s' "$1" > "$f"; printf '%s' "$f"; }

want() {  # $1=label  $2=expected-token  $3=rc  $4=body-text
  local got bf; bf="$(_body "$4")"
  got="$(bs_read_classify "$3" "$bf")"
  if [[ "$got" == "$2" ]]; then _report "$1" ok
  else _report "$1" bad "rc=$3 -> got '$got', want '$2'"; fi
  rm -f "$bf"
}

# WANT() DISCRIMINATION CANARY — added because a mutation battery found the gap.
# The _report self-test above proves the REPORTER's two arms work; it says nothing
# about the DISPATCHER. Measured: rewriting want()'s comparison to `if true` left
# this suite reporting 24/24 green, so every assertion below could be disarmed by a
# one-line edit with no detector. This drives want() with a deliberately WRONG
# expectation and requires it to have recorded a failure, then unwinds — the same
# construction as the reporter canary, one level up.
_canary_fail_before=$fail
want "want() canary (expected to FAIL)" __definitely-not-a-token__ 3 ""
if (( fail != _canary_fail_before + 1 )); then
  printf 'FAIL: want() canary did not record a failure — the dispatcher does not discriminate, so every assertion in this suite is vacuous\n' >&2
  exit 1
fi
# Unwind the canary so it does not pollute the ledger or the verdict.
fail=$((fail - 1)); unset 'FAILURES[-1]'

# ── rc partition: one token per class ────────────────────────────────────────
want "T1  rc=3  -> credentials-absent"        credentials-absent       3  ""
want "T2  rc=1  -> reader-exit-1"             reader-exit-1            1  ""
want "T3  rc=6  -> transport (DNS)"           transport                6  ""
want "T4  rc=7  -> transport (connect)"       transport                7  ""
want "T5  rc=28 -> transport (timeout)"       transport               28  ""
want "T6  rc=35 -> transport (TLS)"           transport               35  ""
want "T7  rc=2  -> reader-refusal"            reader-refusal           2  ""
want "T8  rc=64 -> reader-refusal"            reader-refusal          64  ""
want "T9  rc=78 -> reader-refusal"            reader-refusal          78  ""
want "T10 rc=99 -> other"                     other                   99  ""
want "T11 rc=0  -> other"                     other                    0  ""

# ── rc=22 body discrimination ────────────────────────────────────────────────
want "T12 rc=22 auth (Code: 516)"             credentials-rejected    22  'Code: 516. DB::Exception: u123: Authentication failed'
want "T12b rc=22 auth (password is incorrect)" credentials-rejected   22  'password is incorrect'
want "T12c rc=22 maintenance"                 source-under-maintenance 22 'the cluster is under maintenance'
want "T12d rc=22 unmatched body -> other"     other                   22  'Code: 241. Memory limit exceeded'
want "T12e rc=22 empty body -> other"         other                   22  ''

# table-missing (ADR-192): a source that has never stored a row answers HTTP 500
# CLUSTER_DOESNT_EXIST, which --fail-with-body reports as the SAME rc=22 as an auth
# failure while meaning the opposite — the producer is at fault, not the reader.
# This is the distinction the failing run log could not make.
want "T12f rc=22 CLUSTER_DOESNT_EXIST -> table-missing" table-missing 22 'Code: 170. DB::Exception: Requested cluster not found. CLUSTER_DOESNT_EXIST'

# ── PRECEDENCE, pinned deliberately ──────────────────────────────────────────
# Today's arms are SEQUENTIAL ASSIGNMENTS, so a body carrying BOTH markers ends as
# `source-under-maintenance` — maintenance overwrites credentials-rejected. A natural
# if/elif rewrite inverts that silently and no existing fixture discriminates, so it
# is pinned here rather than left to chance.
want "T13 rc=22 BOTH markers -> maintenance wins" source-under-maintenance 22 'Authentication failed ... under maintenance'

# table-missing greps LAST, so it outranks both inherited markers. That is a NEW
# precedence this change introduces, and it is pinned rather than left implicit: a
# definitive vendor code (CLUSTER_DOESNT_EXIST names the producer) should beat a bare
# 'maintenance' substring, which can appear in unrelated prose. Both directions are
# asserted so a later reorder cannot pass silently.
want "T13b rc=22 maintenance + CLUSTER_DOESNT_EXIST -> table-missing" \
  table-missing 22 'under maintenance; Code: 170 CLUSTER_DOESNT_EXIST'
want "T13c rc=22 auth + CLUSTER_DOESNT_EXIST -> table-missing" \
  table-missing 22 'Authentication failed; CLUSTER_DOESNT_EXIST'

# ── return-code contract ─────────────────────────────────────────────────────
# Asserted directly: every caller runs under `set -e`.
_rc_probe() { local bf rc; bf="$(_body '')"; bs_read_classify 22 "$bf" >/dev/null; rc=$?; rm -f "$bf"; return "$rc"; }
if _rc_probe; then _report "T14 returns 0 on the common path" ok
else _report "T14 returns 0 on the common path" bad "returned non-zero — would abort a set -e caller"; fi

_rc_probe_match() { local bf rc; bf="$(_body 'Authentication failed')"; bs_read_classify 22 "$bf" >/dev/null; rc=$?; rm -f "$bf"; return "$rc"; }
if _rc_probe_match; then _report "T15 returns 0 on a MATCHING body" ok
else _report "T15 returns 0 on a matching body" bad "returned non-zero"; fi

# A missing rowsfile must not abort the caller either — the file is absent whenever
# the read died before writing one, which is exactly the rc=3 / rc=1 case.
_rc_probe_missing() { bs_read_classify 22 "/nonexistent/rows-$$" >/dev/null; }
if _rc_probe_missing; then _report "T16 returns 0 when rowsfile is absent" ok
else _report "T16 returns 0 when rowsfile is absent" bad "returned non-zero"; fi

# ── EXACTLY ONE token, no stray output ───────────────────────────────────────
_lines() { local bf n; bf="$(_body 'Authentication failed')"; n="$(bs_read_classify 22 "$bf" | wc -l)"; rm -f "$bf"; printf '%s' "$n"; }
if [[ "$(_lines)" == "1" ]]; then _report "T17 emits exactly one line" ok
else _report "T17 emits exactly one line" bad "got $(_lines) lines"; fi

# ── Assertion floor (printf + exit, never through the helper it backstops) ──
_total=$((pass + fail))
_FLOOR=20
if (( _total < _FLOOR )); then
  printf 'FAIL: assertion floor: %d ran, floor %d — the harness lost coverage rather than passing it\n' \
    "$_total" "$_FLOOR" >&2
  exit 1
fi
if (( ${#FAILURES[@]} != fail )); then
  printf 'FAIL: ledger drift: %d FAILURES entries vs fail counter %d\n' "${#FAILURES[@]}" "$fail" >&2
  exit 1
fi

printf 'betterstack-read-classify: %d passed, %d failed (%d assertions)\n' "$pass" "$fail" "$_total"
exit $(( fail > 0 ))
