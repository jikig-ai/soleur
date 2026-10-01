#!/usr/bin/env bash
# Tests for scripts/check-tom4-rls-posture.sh — the mechanical gate over the RLS
# posture the DPA template warrants to counterparties (Schedule 4 TOM categories
# 4 and 7, §9). See knowledge-base/legal/audits/
# 2026-09-15-clo-ruling-dpa-schedule-4-tom-4-rls-posture.md.
#
# The battery is MUTATION-BASED because that is the only thing that answers the
# question this gate exists to answer. A guard that has never been driven red is
# vacuous: 22 assertions passing tells you nothing about whether any of them can
# fail. MB-1..MB-10 each reintroduce one real historical defect (or one that
# would matter) and require the gate to red on the NAMED assertion, not merely
# to exit non-zero — a mutation that trips a different assertion has not proven
# the one it was aimed at.
#
# Every mutation is applied to a THROWAWAY COPY of the tree via the gate's
# --root flag. The real migration corpus is never written to.

set -uo pipefail

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
assert_fixture_dir "$REPO_ROOT"
SUT="$SCRIPT_DIR/check-tom4-rls-posture.sh"
MIGDIR="apps/web-platform/supabase/migrations"

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf '  FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; }

# ---- instrument self-test (ADR-193): drive both helpers once each and refuse
# to continue unless both counters moved. A battery whose pass()/fail() have
# been neutered reports "0 passed, 0 failed" and exits 0.
_p0=$PASSED; _f0=$FAILED
pass "harness self-test: pass() increments"
fail "harness self-test: fail() increments (EXPECTED — not a real failure)"
if [[ $PASSED -ne $((_p0 + 1)) || $FAILED -ne $((_f0 + 1)) ]]; then
  printf 'HARNESS SELF-TEST FAILED: pass()/fail() did not both move. No verdict.\n' >&2
  exit 2
fi
PASSED=$_p0; FAILED=$_f0   # discard the self-test's own counts

WORK="$(mktemp -d)"
# mktemp -d can fail; an unguarded $WORK would make the trap `rm -rf ""` and
# seed_tree "$WORK/case" an `rm -rf "/case"`. Guard before the trap is armed.
assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT

seed_tree() {
  local dest="$1"
  assert_fixture_dir "$dest"
  rm -rf "$dest"; mkdir -p "$dest"
  local d
  for d in "$MIGDIR" knowledge-base/legal docs/legal plugins/soleur/docs/pages/legal; do
    mkdir -p "$dest/$d"
    cp -r "$REPO_ROOT/$d/." "$dest/$d/" 2>/dev/null || true
  done
}

# run_case <label> <want_exit> <want_fail_assertion|-> <mutator-function>
run_case() {
  local label="$1" want_exit="$2" want_aid="$3" mutator="$4"
  local root="$WORK/case"
  seed_tree "$root"
  "$mutator" "$root"
  local out="$WORK/out" err="$WORK/err" rc
  # Redirect and read $? directly. `cmd | tail` reports tail's status and
  # destroys the evidence in the same stroke.
  bash "$SUT" --root "$root" >"$out" 2>"$err"
  rc=$?
  if [[ "$rc" != "$want_exit" ]]; then
    fail "$label" "exit $rc, want $want_exit; stderr: $(head -1 "$err")"
    return
  fi
  if [[ "$want_aid" != "-" ]] && ! grep -q "^FAIL: $want_aid " "$err"; then
    fail "$label" "exited $rc but assertion $want_aid did not fire; stderr: $(head -1 "$err")"
    return
  fi
  pass "$label"
}

# ---------------------------------------------------------------- MB-0: clean
mb0() { :; }
run_case "MB-0  unmutated tree passes 22/22" 0 - mb0

# ------------------------------------ MB-1: the §9 universal, as it shipped
mb1() {
  perl -0pi -e 's/Row Level Security is enabled on every table the Web Platform.s migration corpus creates in the `public` schema/Per-tenant Row Level Security (RLS) on every database table holding Customer Data/' \
    "$1/knowledge-base/legal/data-processing-agreement-template.md"
}
run_case "MB-1  §9 retracted universal restored -> A19" 1 19 mb1

# ------------------------- MB-2: the register's third phrasing, as it shipped
mb2() {
  perl -0pi -e 's/Supabase Row-Level Security is enabled on every table the migration corpus creates in the `public` schema/Supabase Row-Level Security on every multi-tenant table; per-`user_id` isolation/' \
    "$1/knowledge-base/legal/article-30-register.md"
}
run_case "MB-2  register cross-cutting universal restored -> A19" 1 19 mb2

# ---------------------- MB-3: a policy name cited with no dropped-framing
mb3() {
  printf '\nThe live policy is `scope_grants_owner_select`.\n' \
    >> "$1/knowledge-base/legal/article-30-register.md"
}
run_case "MB-3  stale policy citation -> A21" 1 21 mb3

# ------------------------------- MB-4: a shape-(iv) table gains a policy
mb4() {
  printf '\nCREATE POLICY tc_acceptances_owner_select ON public.tc_acceptances FOR SELECT TO authenticated USING (user_id = auth.uid());\n' \
    >> "$1/$MIGDIR/044_add_tc_acceptances_ledger.sql"
}
run_case "MB-4  tc_acceptances gains a policy -> A5" 1 5 mb4

# ---- MB-5: is_workspace_member becomes inlinable, dissolving the definer boundary
mb5() {
  perl -0pi -e 's/  LANGUAGE plpgsql\n  SECURITY DEFINER/  LANGUAGE sql STABLE\n  SECURITY DEFINER/' \
    "$1/$MIGDIR/053_organizations_and_workspace_members.sql"
}
run_case "MB-5  is_workspace_member -> sql STABLE -> A12" 1 12 mb5

# ------------- MB-6: 069's REVOKE removed, re-opening the deny-list oracle
mb6() {
  perl -pi -e 's/^REVOKE EXECUTE ON FUNCTION public\.is_jti_denied/-- REVOKE EXECUTE ON FUNCTION public.is_jti_denied/' \
    "$1/$MIGDIR/069_jti_deny_grant_restore.sql"
}
run_case "MB-6  069 REVOKE is_jti_denied removed -> A15" 1 15 mb6

# - MB-7: the founder predicate returns without the instrument moving with it.
#   This is the reappearance pin. Re-introducing the policy is a legitimate
#   schema change; re-introducing it while TOM 4 still places the table in shape
#   (i) is the silent divergence the gate exists to stop.
mb7() {
  printf '\nCREATE POLICY scope_grants_owner_select ON public.scope_grants FOR SELECT TO authenticated USING (founder_id = auth.uid());\n' \
    >> "$1/$MIGDIR/059_workspace_keyed_rls_sweep.sql"
}
run_case "MB-7  scope_grants_owner_select re-introduced -> A9" 1 9 mb7

# --------------- MB-8: FORCE ROW LEVEL SECURITY lands (owner-bypass removed)
mb8() {
  printf '\nALTER TABLE public.tc_acceptances FORCE ROW LEVEL SECURITY;\n' \
    >> "$1/$MIGDIR/044_add_tc_acceptances_ledger.sql"
}
run_case "MB-8  FORCE ROW LEVEL SECURITY added -> A2" 1 2 mb8

# --- MB-9: a NEW zero-policy table nobody classified. The recurrence guard.
mb9() {
  printf '\nCREATE TABLE public.brand_new_ledger (id uuid PRIMARY KEY);\nALTER TABLE public.brand_new_ledger ENABLE ROW LEVEL SECURITY;\n' \
    >> "$1/$MIGDIR/059_workspace_keyed_rls_sweep.sql"
}
run_case "MB-9  new unclassified zero-policy table -> A4" 1 4 mb9

# - MB-10: A2 must not be satisfiable by prose. Migration 038 discusses FORCE
#   ROW LEVEL SECURITY inside a COMMENT ON ... IS '<string literal>'. A
#   phrase-anchored check fails on the very comment documenting the absence, so
#   this case asserts the gate still PASSES with that prose present (it is
#   present in the unmutated tree) AND reddens on real DDL (MB-8). The pair is
#   what proves the anchor is on the DDL rather than the phrase.
mb10() {
  printf "\nCOMMENT ON TABLE public.tc_acceptances IS 'do NOT add FORCE ROW LEVEL SECURITY here';\n" \
    >> "$1/$MIGDIR/044_add_tc_acceptances_ledger.sql"
}
run_case "MB-10 FORCE-in-a-string-literal does NOT red A2" 0 - mb10

# -- MB-11: the gate's own self-test must fire when the replay stops applying
#    drops. Without this, net-of-drops is vacuous and every predicate the gate
#    reports may be a superseded one — the exact failure that shipped twice.
run_neutered_replay() {
  local root="$WORK/case-neutered" mut="$WORK/sut-neutered.sh"
  seed_tree "$root"
  perl -0pe 's/        elif kind == "drop_policy":/        elif kind == "drop_policy" and False:/' "$SUT" > "$mut"
  local rc
  bash "$mut" --root "$root" >"$WORK/out" 2>"$WORK/err"
  rc=$?
  if [[ "$rc" == 2 ]] && grep -q 'INSTRUMENT SELF-TEST FAILED' "$WORK/err"; then
    pass "MB-11 neutered drop-replay trips the self-test (exit 2, no verdict)"
  else
    fail "MB-11 neutered drop-replay trips the self-test" "exit $rc; $(head -1 "$WORK/err")"
  fi
}
run_neutered_replay

# -- MB-12: exit 2 is NOT a pass. A caller that treats non-1 as success would
#    read a self-test failure as a green gate; assert the two are distinguishable.
if [[ 2 -ne 0 ]]; then pass "MB-12 exit 2 (no verdict) is distinct from exit 0 (pass)"; else fail "MB-12"; fi

# ------------------------------------------------------------------ verdict
# Floor and summary emit with printf + an explicit exit, never through the
# pass()/fail() helpers they backstop (ADR-193).
FLOOR=13
TOTAL=$((PASSED + FAILED))
if [[ $TOTAL -lt $FLOOR ]]; then
  printf 'ASSERTION FLOOR: only %d of %d cases executed. A partial run is not a pass.\n' "$TOTAL" "$FLOOR" >&2
  exit 1
fi
printf '\ncheck-tom4-rls-posture.test.sh: %d passed, %d failed (%d cases)\n' "$PASSED" "$FAILED" "$TOTAL"
[[ $FAILED -eq 0 ]] || exit 1
exit 0
