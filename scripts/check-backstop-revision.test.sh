#!/usr/bin/env bash
# Hermetic tests for scripts/check-backstop-revision.sh (#9239 Guard 1). No
# network: every arm builds a bare "origin" + working clone under TMPDIR so
# the SUT's own `git fetch`/`git merge-base`/`git show` run against fixture
# refs — the same code path CI exercises, at fixture speed.
#
# The fixture layout mirrors the real gate: a base branch carries the hook at
# some marker state; a PR branch modifies the diff under test; the SUT decides
# green/red from the merge-base comparison of the marker VALUE.
#
# Convention: pass/fail counters + ok()/no(), same as the sibling
# check-*.test.sh suites.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$REPO_ROOT/scripts/check-backstop-revision.sh"
export TMPDIR="${TMPDIR:-/var/tmp}"
pass=0; fail=0; cases=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }

[[ -r "$SUT" ]] || { echo "FATAL: $SUT missing" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "SKIP: no git"; exit 0; }
S="$(mktemp -d -t backstop-rev-guard.XXXXXXXX)" || exit 2
trap 'rm -rf "$S"' EXIT

HOOK=.claude/hooks/memory-backstop.sh
LIB=.claude/hooks/lib/log-rotation.sh

# mk_pr <case-dir> [base-marker] — build origin + clone whose PR branch is
# ready for a hook edit. Base marker "" means the base hook carries NO marker
# (the pre-#9239 shape this PR itself is graded against).
mk_pr() {
  local d="$1" base_marker="${2:-}"
  mkdir -p "$d/origin.git" "$d/work"
  git init --quiet --bare "$d/origin.git"
  git -C "$d/work" init --quiet -b main
  git -C "$d/work" remote add origin "$d/origin.git"
  mkdir -p "$d/work/.claude/hooks/lib"
  if [[ -n "$base_marker" ]]; then
    printf '#!/usr/bin/env bash\nreadonly BACKSTOP_REVISION=%s\n' "$base_marker" > "$d/work/$HOOK"
  else
    printf '#!/usr/bin/env bash\n# old hook — no marker (pre-#9239 shape)\n' > "$d/work/$HOOK"
  fi
  printf '# lib\n' > "$d/work/$LIB"
  git -C "$d/work" add -A
  git -C "$d/work" -c user.email=t@t -c user.name=t commit --quiet -m base
  git -C "$d/work" push --quiet origin main
  git -C "$d/work" checkout --quiet -b pr-branch
}

run_sut() { # <case-dir> [BASE_REF]
  local d="$1" ref="${2:-main}"
  ( cd "$d/work" && GITHUB_BASE_REF="$ref" bash "$SUT" >"$d/out" 2>"$d/err" )
  RC=$?
}

edit_hook() { # <case-dir> <marker-or-absent> — append a body line + set marker
  local d="$1" marker="$2"
  printf '# body change %s\n' "$RANDOM" >> "$d/work/$HOOK"
  if [[ "$marker" != "keep" ]]; then
    sed -i '/BACKSTOP_REVISION=/d' "$d/work/$HOOK"
    [[ -n "$marker" ]] && printf 'readonly BACKSTOP_REVISION=%s\n' "$marker" >> "$d/work/$HOOK"
  fi
  git -C "$d/work" add -A && git -C "$d/work" -c user.email=t@t -c user.name=t commit --quiet -m change
}

# A1: hook untouched → NO-OP, exit 0.
cases=$((cases + 1))
mk_pr "$S/a1" 1
printf 'unrelated\n' >> "$S/a1/work/README.md" && git -C "$S/a1/work" add -A \
  && git -C "$S/a1/work" -c user.email=t@t -c user.name=t commit --quiet -m other
run_sut "$S/a1"
if [[ "$RC" -eq 0 && "$(<"$S/a1/out")" == *NO-OP* ]]; then ok "A1: hook untouched -> NO-OP green"
else no "A1: untouched (rc=$RC) $(<"$S/a1/out") $(<"$S/a1/err")"; fi

# A2: hook touched, base markerless, new marker introduced -> PASS
# (the shape this PR itself is graded against).
cases=$((cases + 1))
mk_pr "$S/a2"
edit_hook "$S/a2" 1
run_sut "$S/a2"
if [[ "$RC" -eq 0 && "$(<"$S/a2/out")" == *verified* ]]; then ok "A2: marker introduced on markerless base -> green"
else no "A2: introduce-on-markerless (rc=$RC) $(<"$S/a2/out") $(<"$S/a2/err")"; fi

# A3: honest bump 1 -> 2 -> PASS.
cases=$((cases + 1))
mk_pr "$S/a3" 1
edit_hook "$S/a3" 2
run_sut "$S/a3"
if [[ "$RC" -eq 0 ]]; then ok "A3: 1 -> 2 bump -> green"
else no "A3: bump (rc=$RC) $(<"$S/a3/err")"; fi

# A4: hook edited, SAME marker -> FAIL.
cases=$((cases + 1))
mk_pr "$S/a4" 3
edit_hook "$S/a4" keep
run_sut "$S/a4"
if [[ "$RC" -ne 0 ]]; then ok "A4: same-value rewrite -> RED"
else no "A4: same value passed (rc=$RC)"; fi

# A5: hook edited, marker DECREASED 3 -> 2 -> FAIL (the -= bug the fix closes:
# a lowered marker merges green yet can never win resolution).
cases=$((cases + 1))
mk_pr "$S/a5" 3
edit_hook "$S/a5" 2
run_sut "$S/a5"
if [[ "$RC" -ne 0 && "$(<"$S/a5/err")" == *"not above"* ]]; then ok "A5: decreased marker -> RED"
else no "A5: decrease passed (rc=$RC) $(<"$S/a5/out") $(<"$S/a5/err")"; fi

# A6: hook edited, marker REMOVED -> FAIL.
cases=$((cases + 1))
mk_pr "$S/a6" 4
edit_hook "$S/a6" ""
run_sut "$S/a6"
if [[ "$RC" -ne 0 && "$(<"$S/a6/err")" == *"no BACKSTOP_REVISION"* ]]; then ok "A6: marker removed -> RED"
else no "A6: removal passed (rc=$RC) $(<"$S/a6/err")"; fi

# A7: watched LIB file edited, hook untouched -> gate fires and fails on the
# unchanged marker (the lib is part of the executed protection tree; it must
# ride a marker bump).
cases=$((cases + 1))
mk_pr "$S/a7" 5
printf '# rotated\n' >> "$S/a7/work/$LIB"
git -C "$S/a7/work" add -A && git -C "$S/a7/work" -c user.email=t@t -c user.name=t commit --quiet -m lib
run_sut "$S/a7"
if [[ "$RC" -ne 0 ]]; then ok "A7: lib-only edit without bump -> RED (watched path)"
else no "A7: lib-only edit passed (rc=$RC) $(<"$S/a7/out")"; fi

# A8: decoy comment marker must NOT satisfy the gate — base has
# `readonly BACKSTOP_REVISION=1`; PR adds a comment `BACKSTOP_REVISION=99`
# ABOVE the real line. Line-anchored parse reads the real 1 -> same value -> RED.
cases=$((cases + 1))
mk_pr "$S/a8" 1
sed -i '1i # BACKSTOP_REVISION=99 decoy' "$S/a8/work/$HOOK"
printf '# change\n' >> "$S/a8/work/$HOOK"
git -C "$S/a8/work" add -A && git -C "$S/a8/work" -c user.email=t@t -c user.name=t commit --quiet -m decoy
run_sut "$S/a8"
if [[ "$RC" -ne 0 ]]; then ok "A8: comment decoy marker does not count -> RED"
else no "A8: decoy marker counted (rc=$RC) $(<"$S/a8/out")"; fi

# A9: GITHUB_BASE_REF honored — base is `release` not `main`.
cases=$((cases + 1))
mk_pr "$S/a9" 1
git -C "$S/a9/work" checkout --quiet -b release && git -C "$S/a9/work" push --quiet origin release
git -C "$S/a9/work" checkout --quiet pr-branch
edit_hook "$S/a9" 2
run_sut "$S/a9" release
if [[ "$RC" -eq 0 ]]; then ok "A9: GITHUB_BASE_REF override resolves the named base"
else no "A9: BASE_REF override (rc=$RC) $(<"$S/a9/err")"; fi

echo
echo "RESULT: $pass passed, $fail failed ($cases cases)"
[[ "$fail" -eq 0 ]]
