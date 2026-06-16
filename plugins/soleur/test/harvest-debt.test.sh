#!/usr/bin/env bash
# Test for harvest-debt.sh — the inline SOLEUR-DEBT marker harvester.
#
# harvest-debt greps tracked SOURCE (not prose) for deferral markers, groups
# them by file, and flags markers that name no upgrade trigger as `no-trigger`.
# It is read-only: never writes, never closes (that is resolve-debt's job).
#
# NOTE: the marker literal is built via a '-' concatenation boundary (MARK) so
# this test file is NOT itself a marker site — a real harvest run over the repo
# must not self-report these fixtures. Same idiom as digest-scrub.test.sh's
# push-protection split.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARVEST="${SCRIPT_DIR}/../skills/harvest-debt/scripts/harvest-debt.sh"
MARK="SOLEUR-DEB""T:" # concatenated: no contiguous marker literal in this source

pass=0
fail=0

ok() { # <bool-rc> <desc>
  if [[ "$1" == 0 ]]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: $2"; fi
}

# --- Fixture repo: markers in code, one in an excluded path, one in prose (.md) ---
seed_repo() {
  local d="$1"
  git -C "$d" init -q
  git -C "$d" config user.email t@t
  git -C "$d" config user.name t
  mkdir -p "$d/src" "$d/node_modules/pkg" "$d/docs"
  printf '%s\n' "function lock() {} // ${MARK} global lock; per-account locks if throughput matters" > "$d/src/a.js"
  printf '%s\n' "const items = [] # ${MARK} hardcoded list" > "$d/src/b.py"
  printf '%s\n' "vendored // ${MARK} pinned dep; bump when upstream cuts a release" > "$d/node_modules/pkg/index.js"
  printf '%s\n' "Prose mentioning the // ${MARK} convention should not be harvested." > "$d/docs/note.md"
  git -C "$d" add -A
}

# === Case 1-6: a repo with markers ===
tmpd="$(mktemp -d)"
trap 'rm -rf "$tmpd"' EXIT
seed_repo "$tmpd"
out="$(cd "$tmpd" && bash "$HARVEST")"
rc=$?

ok "$([[ "$rc" == 0 ]] && echo 0 || echo 1)" "exit 0 when markers present (got $rc)"
ok "$([[ -n "$out" ]] && echo 0 || echo 1)" "produces a non-empty report (anchors the exclusion asserts below)"
ok "$(grep -q "src/a.js" <<<"$out" && echo 0 || echo 1)" "groups under src/a.js"
ok "$(grep -q "global lock" <<<"$out" && grep -q "per-account locks if throughput matters" <<<"$out" && echo 0 || echo 1)" "splits ceiling and trigger"
ok "$(grep -q "src/b.py" <<<"$out" && grep -qi "no-trigger" <<<"$out" && echo 0 || echo 1)" "flags trigger-less marker as no-trigger"
ok "$(grep -q "node_modules" <<<"$out" && echo 1 || echo 0)" "excludes node_modules"
ok "$(grep -q "docs/note.md" <<<"$out" && echo 1 || echo 0)" "excludes prose (.md) references"
ok "$(grep -qE "2 marker" <<<"$out" && echo 0 || echo 1)" "summary counts 2 markers (md + node_modules excluded)"
ok "$(grep -qE "1 (with )?no.?trigger" <<<"$out" && echo 0 || echo 1)" "summary counts 1 no-trigger"

# === Case 7: empty repo (no markers) ===
tmp2="$(mktemp -d)"
git -C "$tmp2" init -q
git -C "$tmp2" config user.email t@t
git -C "$tmp2" config user.name t
printf 'clean code, nothing deferred\n' > "$tmp2/clean.txt"
git -C "$tmp2" add -A
out2="$(cd "$tmp2" && bash "$HARVEST")"
rc2=$?
ok "$([[ "$rc2" == 0 ]] && echo 0 || echo 1)" "exit 0 on empty state (got $rc2)"
ok "$(grep -qi "no .*marker" <<<"$out2" && echo 0 || echo 1)" "empty state prints a no-markers line"
rm -rf "$tmp2"

# === Case 8: --help ===
if bash "$HARVEST" --help >/dev/null 2>&1; then ok 0 "--help exits 0"; else ok 1 "--help exits 0"; fi

# === Case 9: usage errors exit 2 ===
bash "$HARVEST" --bogus >/dev/null 2>&1 && rc_bogus=0 || rc_bogus=$?
ok "$([[ "$rc_bogus" == 2 ]] && echo 0 || echo 1)" "unknown argument exits 2"
nongit="$(mktemp -d)" # mktemp dir is not a git work tree
( cd "$nongit" && bash "$HARVEST" >/dev/null 2>&1 ) && rc_nongit=0 || rc_nongit=$?
ok "$([[ "$rc_nongit" == 2 ]] && echo 0 || echo 1)" "outside a git work tree exits 2"
rm -rf "$nongit"

# === Case 10: edge cases — same-file grouping, trailing-; (empty trigger), colon in path ===
tmp3="$(mktemp -d)"
git -C "$tmp3" init -q
git -C "$tmp3" config user.email t@t
git -C "$tmp3" config user.name t
mkdir -p "$tmp3/src"
# two markers in ONE file → one header, both listed
printf '%s\n%s\n' \
  "a() {} // ${MARK} first ceiling; first trigger" \
  "b() {} // ${MARK} second ceiling; second trigger" > "$tmp3/src/multi.js"
# trailing ';' with empty trigger → still no-trigger
printf '%s\n' "c // ${MARK} dangling semicolon only;" > "$tmp3/src/dangling.js"
# colon IN the path must not mis-peel file/lineno
printf '%s\n' "d // ${MARK} colon path; verify the parse anchors on :digits:" > "$tmp3/src/we:ird.js"
git -C "$tmp3" add -A
out3="$(cd "$tmp3" && bash "$HARVEST")"
ok "$([[ "$(grep -c "## src/multi.js" <<<"$out3")" == 1 ]] && echo 0 || echo 1)" "same-file markers share one header"
ok "$(grep -q "first trigger" <<<"$out3" && grep -q "second trigger" <<<"$out3" && echo 0 || echo 1)" "both same-file markers listed"
ok "$(grep -q "dangling semicolon only.*no-trigger" <<<"$out3" && echo 0 || echo 1)" "trailing-; (empty trigger) flags no-trigger"
ok "$(grep -q "## src/we:ird.js" <<<"$out3" && echo 0 || echo 1)" "colon-in-path peels file correctly"
ok "$(grep -q "colon path" <<<"$out3" && echo 0 || echo 1)" "colon-in-path ceiling parsed (lineno boundary anchored on :digits:)"
rm -rf "$tmp3"

echo "=== harvest-debt: ${pass} passed, ${fail} failed ==="
[[ "$fail" == 0 ]]
