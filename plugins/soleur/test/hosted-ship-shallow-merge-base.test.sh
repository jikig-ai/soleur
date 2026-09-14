#!/usr/bin/env bash
# Hermetic proof that `git fetch --unshallow origin` restores a merge-base
# for origin/main...HEAD on a depth-1 clone whose branch point is below the
# shallow tip. Synthesized file:// repo — no network.
#
# Pins the hosted ship-merge checkout sequence (event-ship-merge.ts
# checkout-pr) without spawning Inngest.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

PASS=0; FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

ROOT="$(mktemp -d "$TMPDIR/hosted-ship-shallow.XXXXXXXX")"
cleanup() { rm -rf "$ROOT"; }
trap cleanup EXIT

git init -q -b main "$ROOT/src"
git -C "$ROOT/src" config user.email t@t
git -C "$ROOT/src" config user.name t
echo c1 > "$ROOT/src/f"
git -C "$ROOT/src" add f && git -C "$ROOT/src" commit -q -m c1
C1="$(git -C "$ROOT/src" rev-parse HEAD)"
echo c2 >> "$ROOT/src/f"
git -C "$ROOT/src" commit -q -am c2
echo c3 >> "$ROOT/src/f"
git -C "$ROOT/src" commit -q -am c3

git -C "$ROOT/src" checkout -q -b feat "$C1"
echo feat >> "$ROOT/src/f"
git -C "$ROOT/src" commit -q -am feat
git -C "$ROOT/src" checkout -q main

git clone -q --depth=1 "file://$ROOT/src" "$ROOT/clone"
git -C "$ROOT/clone" fetch -q origin feat:feat
git -C "$ROOT/clone" checkout -q feat

if git -C "$ROOT/clone" merge-base origin/main HEAD >/dev/null 2>&1; then
  fail "depth-1 clone unexpectedly has merge-base (fixture does not reproduce the defect)"
else
  pass "depth-1 clone has no merge-base for origin/main HEAD"
fi

git -C "$ROOT/clone" fetch --unshallow origin >/dev/null 2>&1
unshallow_rc=$?
if [[ "$unshallow_rc" -eq 0 ]]; then
  pass "git fetch --unshallow origin exits 0 on a shallow clone"
else
  fail "git fetch --unshallow origin rc=$unshallow_rc"
fi

if mb="$(git -C "$ROOT/clone" merge-base origin/main HEAD 2>/dev/null)"; then
  [[ -n "$mb" ]] && pass "merge-base after unshallow: $mb" \
    || fail "merge-base after unshallow printed empty"
else
  fail "merge-base after unshallow still fails"
fi

porcelain="$(git -C "$ROOT/clone" status --porcelain)"
if [[ -z "$porcelain" ]]; then
  pass "working tree clean after unshallow (no contamination)"
else
  fail "working tree dirty after unshallow: $porcelain"
fi

deleted="$(git -C "$ROOT/clone" diff --name-only | head -5)"
if [[ -z "$deleted" ]]; then
  pass "git diff --name-only empty after unshallow"
else
  fail "unshallow produced a diff: $deleted"
fi

# Second unshallow on a now-complete repo: measured fatal, continue-arm.
git -C "$ROOT/clone" fetch --unshallow origin >/dev/null 2>"$ROOT/second.err"
second_rc=$?
if [[ "$second_rc" -eq 128 ]] \
   && grep -qF 'fatal: --unshallow on a complete repository does not make sense' "$ROOT/second.err"; then
  pass "second --unshallow is the measured complete-repository fatal (rc=128)"
else
  fail "second --unshallow rc=$second_rc stderr=$(tr '\n' ' ' < "$ROOT/second.err")"
fi

echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 && "$PASS" -ge 6 ]]
exit $?
