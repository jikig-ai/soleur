#!/usr/bin/env bash
# Tests for apps/web-platform/scripts/rename-guard.sh.
#
# The guard exists because gitleaks evaluates its path allowlist against the
# rename DESTINATION and does not re-scan content against the SOURCE path, so
# `git mv server/secrets.ts <allowlisted>/x.md` launders a real secret past the
# scan (#3160).
#
# That laundering requires the SOURCE to be OUTSIDE the allowlist. When both
# source and destination are allowlisted — precisely what compound's archive-kb
# step does on every one-shot run, `git mv` -ing plans/specs into their own
# `archive/` subdirectory — the content was ALREADY unscanned before the rename.
# No new unscanned surface is created, so there is nothing to launder, and the
# guard firing there is a false positive by construction.
#
# The previously-filed remedy (pre-apply the `secret-scan-allow-rename` label,
# #5095) disarms the guard for the ENTIRE pull request, including a genuine
# outside->allowlist rename that happens to share the PR. The source-allowlist
# exemption is evaluated per rename pair and preserves the guard's real
# property. See #5095 / #5097.
#
# Fixtures are synthesized git repos under mktemp (cq-test-fixtures-synthesized-only)
# carrying the REAL .gitleaks.toml + parser, so the allowlist regexes under test
# are the ones that actually ship.
#
# Exit contract of the SUT: 0 no violation / override, 1 violation, 2 input error.

set -euo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SUT="$REPO_ROOT/apps/web-platform/scripts/rename-guard.sh"
PARSER_REL="apps/web-platform/scripts/parse-gitleaks-allowlists.mjs"

PASS=0
FAIL=0
TOTAL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() {
  echo "FAIL: $1"
  echo "  detail: ${2:-}"
  FAIL=$((FAIL + 1))
  TOTAL=$((TOTAL + 1))
}

WORK="$(mktemp -d)" || { echo "harness: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT

[[ -f "$SUT" ]] || { echo "FAIL: TS-0 SUT missing at $SUT"; exit 1; }
[[ -f "$REPO_ROOT/$PARSER_REL" ]] || { echo "harness: parser missing" >&2; exit 2; }
[[ -f "$REPO_ROOT/.gitleaks.toml" ]] || { echo "harness: .gitleaks.toml missing" >&2; exit 2; }

# mk_repo <name> — a git repo carrying the real parser + gitleaks config.
# Echoes the repo path.
mk_repo() {
  local d="$WORK/$1"
  mkdir -p "$d/apps/web-platform/scripts" || return 1
  cp "$REPO_ROOT/$PARSER_REL" "$d/$PARSER_REL" || return 1
  cp "$REPO_ROOT/.gitleaks.toml" "$d/.gitleaks.toml" || return 1
  git -C "$d" init -q -b main || return 1
  git -C "$d" config user.email t@t.invalid || return 1
  git -C "$d" config user.name tester || return 1
  git -C "$d" add -A >/dev/null 2>&1 || return 1
  git -C "$d" commit -q -m "base" || return 1
  printf '%s' "$d"
}

# commit_rename <repo> <from> <to> — stage a rename as its own commit.
commit_rename() {
  local d="$1" from="$2" to="$3"
  mkdir -p "$d/$(dirname "$to")" || return 1
  git -C "$d" mv "$from" "$to" || return 1
  git -C "$d" commit -q -m "rename $from -> $to" || return 1
}

# seed_file <repo> <path> <content>
seed_file() {
  local d="$1" p="$2" c="$3"
  mkdir -p "$d/$(dirname "$p")" || return 1
  printf '%s\n' "$c" > "$d/$p" || return 1
  git -C "$d" add "$p" >/dev/null 2>&1 || return 1
  git -C "$d" commit -q -m "seed $p" || return 1
}

# run_guard <repo> <sut-path> [labels] — echoes "rc=<n>\n<output>"
run_guard() {
  local d="$1" sut="$2" labels="${3:-[]}"
  local base head out rc
  base="$(git -C "$d" rev-list --max-parents=0 HEAD)"
  head="$(git -C "$d" rev-parse HEAD)"
  set +e
  out="$(cd "$d" && BASE_SHA="$base" HEAD_SHA="$head" PR_LABELS="$labels" bash "$sut" 2>&1)"
  rc=$?
  set -e
  printf 'rc=%s\n%s\n' "$rc" "$out"
}

assert_guard() {
  local label="$1" want_rc="$2" dir="$3" sut="$4" labels="${5:-[]}"
  local combined rc body
  combined="$(run_guard "$dir" "$sut" "$labels")"
  rc="${combined%%$'\n'*}"; rc="${rc#rc=}"
  body="${combined#*$'\n'}"
  if [[ "$rc" == "$want_rc" ]]; then
    pass "$label"
  else
    fail "$label" "expected rc=$want_rc got rc=$rc; output: $(printf '%s' "$body" | head -4 | tr '\n' ' ')"
  fi
}

# ---------------------------------------------------------------------------
# TS-1 (matrix row 1): OUTSIDE -> allowlist, no override -> exit 1.
# The guard's real property must survive the exemption.
# ---------------------------------------------------------------------------
R1="$(mk_repo outside)" || { echo "harness: setup failed" >&2; exit 2; }
seed_file "$R1" "apps/web-platform/server/secrets.ts" "const token = 'synthetic';"
commit_rename "$R1" "apps/web-platform/server/secrets.ts" "knowledge-base/project/plans/laundered.md"
assert_guard "TS-1 outside->allowlist rename is a violation" 1 "$R1" "$SUT"

# ---------------------------------------------------------------------------
# TS-2 (matrix row 2): allowlist -> allowlist -> exit 0. The archive-kb shape.
# ---------------------------------------------------------------------------
R2="$(mk_repo archival)" || exit 2
seed_file "$R2" "knowledge-base/project/plans/2026-08-11-a-plan.md" "# a plan"
commit_rename "$R2" "knowledge-base/project/plans/2026-08-11-a-plan.md" \
  "knowledge-base/project/plans/archive/20260811-000000-2026-08-11-a-plan.md"
assert_guard "TS-2 allowlist->allowlist archival rename is exempt" 0 "$R2" "$SUT"

# ---------------------------------------------------------------------------
# TS-3: a MIXED PR — one archival rename AND one laundering rename — still
# fails. This is what pre-applying the label cannot do: the label suppresses the
# whole PR, the exemption is per rename pair.
# ---------------------------------------------------------------------------
R3="$(mk_repo mixed)" || exit 2
seed_file "$R3" "knowledge-base/project/plans/2026-08-11-b-plan.md" "# b plan"
commit_rename "$R3" "knowledge-base/project/plans/2026-08-11-b-plan.md" \
  "knowledge-base/project/plans/archive/20260811-000000-2026-08-11-b-plan.md"
seed_file "$R3" "apps/web-platform/server/creds.ts" "const k = 'synthetic';"
commit_rename "$R3" "apps/web-platform/server/creds.ts" "knowledge-base/project/plans/sneaky.md"
assert_guard "TS-3 mixed PR: archival exempt but laundering still fails" 1 "$R3" "$SUT"

# ---------------------------------------------------------------------------
# TS-4: the label override still works on a genuine violation.
# ---------------------------------------------------------------------------
assert_guard "TS-4 label override still suppresses a real violation" 0 "$R1" "$SUT" '["secret-scan-allow-rename"]'

# ---------------------------------------------------------------------------
# TS-5: a PR with no renames at all -> exit 0.
# ---------------------------------------------------------------------------
R5="$(mk_repo norenames)" || exit 2
seed_file "$R5" "docs/readme.md" "hello"
assert_guard "TS-5 no renames is a clean pass" 0 "$R5" "$SUT"

# ---------------------------------------------------------------------------
# TS-6 (matrix row 5): parser failure -> exit 2, fail-closed, unchanged.
# ---------------------------------------------------------------------------
R6="$(mk_repo brokenparser)" || exit 2
seed_file "$R6" "knowledge-base/project/plans/2026-08-11-c-plan.md" "# c"
commit_rename "$R6" "knowledge-base/project/plans/2026-08-11-c-plan.md" \
  "knowledge-base/project/plans/archive/20260811-000000-c.md"
printf 'process.exit(3);\n' > "$R6/$PARSER_REL"
assert_guard "TS-6 parser failure still exits 2 (fail-closed preserved)" 2 "$R6" "$SUT"

# ---------------------------------------------------------------------------
# TS-7 (R-A): a rename PLUS a content edit in the same commit drops below git's
# default similarity threshold, so git reports D+A rather than R and the pair
# never reaches the chokepoint. One extra line defeated the whole guard.
# ---------------------------------------------------------------------------
R7="$(mk_repo subthreshold)" || exit 2
seed_file "$R7" "apps/web-platform/server/creds2.ts" "$(for i in $(seq 1 40); do echo "const k$i = 'synthetic$i';"; done)"
mkdir -p "$R7/knowledge-base/project/plans"
git -C "$R7" mv apps/web-platform/server/creds2.ts knowledge-base/project/plans/laundered2.md
# A REALISTIC edit-while-moving: enough to fall below git's ~50% default, well
# above the 5% floor the guard now sets. A total rewrite (similarity ~0) is
# genuinely D+A rather than a rename and is a documented residual limit.
# 40 original lines + 60 added ~= 40% similarity: BELOW git's ~50% default
# (so the unguarded form misses it) and well ABOVE the 5% floor the guard
# now sets. That band is exactly what MB-3 proves is load-bearing.
for i in $(seq 1 200); do echo "added filler content line number $i here" >> "$R7/knowledge-base/project/plans/laundered2.md"; done
git -C "$R7" add -A >/dev/null 2>&1
git -C "$R7" commit -q -m "move and edit"
assert_guard "TS-7 rename+edit below similarity threshold is still a violation" 1 "$R7" "$SUT"

# ---------------------------------------------------------------------------
# TS-8 (G7): git quotes non-ASCII paths under core.quotePath=true, so the
# trailing quote defeats every `$`-anchored allowlist regex and the target reads
# as un-allowlisted -> exempt.
# ---------------------------------------------------------------------------
R8="$(mk_repo nonascii)" || exit 2
seed_file "$R8" "apps/web-platform/server/creds3.ts" "const b = 'synthetic';"
commit_rename "$R8" "apps/web-platform/server/creds3.ts" "knowledge-base/project/plans/café.md"
assert_guard "TS-8 non-ASCII destination is still a violation (quotePath)" 1 "$R8" "$SUT"

# ---------------------------------------------------------------------------
# TS-9 (G3): `git log --name-status` prints NO diff for merge commits by
# default, so a rename introduced during conflict resolution is invisible.
# ---------------------------------------------------------------------------
R9="$(mk_repo evilmerge)" || exit 2
seed_file "$R9" "apps/web-platform/server/creds4.ts" "const c = 'synthetic';"
git -C "$R9" checkout -q -b side
seed_file "$R9" "docs/side.md" "side"
git -C "$R9" checkout -q main
seed_file "$R9" "docs/mainline.md" "mainline"
git -C "$R9" merge -q --no-ff side -m "merge side" >/dev/null 2>&1
mkdir -p "$R9/knowledge-base/project/plans"
git -C "$R9" mv apps/web-platform/server/creds4.ts knowledge-base/project/plans/viamerge.md
git -C "$R9" commit -q --amend --no-edit
assert_guard "TS-9 rename inside a merge commit is still a violation" 1 "$R9" "$SUT"

# ---------------------------------------------------------------------------
# TS-10 (G8 — THE P1): the source is allowlisted for SOME rules only. gitleaks
# still scans it under every other rule, so moving it to a GLOBALLY allowlisted
# path converts scanned content into unscanned content. Laundering does not
# require source-outside; it requires scope(dest) NOT subset-of scope(source).
# ---------------------------------------------------------------------------
R10="$(mk_repo perrule)" || exit 2
seed_file "$R10" "knowledge-base/project/learnings/2026-01-01-x.md" "a learning"
commit_rename "$R10" "knowledge-base/project/learnings/2026-01-01-x.md" "knowledge-base/plans/x.md"
assert_guard "TS-10 per-rule-allowlisted source -> globally allowlisted dest is a violation" 1 "$R10" "$SUT"

# ---------------------------------------------------------------------------
# TS-11 (R-C): an allowlist parser that succeeds but returns an EMPTY array
# currently disarms the whole gate and exits 0. Absence of an allowlist must be
# fail-closed, not a clean pass.
# ---------------------------------------------------------------------------
R11="$(mk_repo emptyallow)" || exit 2
seed_file "$R11" "apps/web-platform/server/creds5.ts" "const d = 'synthetic';"
commit_rename "$R11" "apps/web-platform/server/creds5.ts" "knowledge-base/project/plans/empty.md"
printf 'console.log("[]");\n' > "$R11/$PARSER_REL"
assert_guard "TS-11 empty allowlist fails closed (exit 2), never a clean pass" 2 "$R11" "$SUT"

# ---------------------------------------------------------------------------
# TS-12 (r1): the Rename-Allowed-By trailer override had NO fixture at all —
# 12 lines including the log-injection strip were deletable at full green.
# ---------------------------------------------------------------------------
R12="$(mk_repo trailer)" || exit 2
seed_file "$R12" "apps/web-platform/server/creds6.ts" "const e = 'synthetic';"
mkdir -p "$R12/knowledge-base/project/plans"
git -C "$R12" mv apps/web-platform/server/creds6.ts knowledge-base/project/plans/trailered.md
git -C "$R12" commit -q -m "move it

Rename-Allowed-By: Tester"
assert_guard "TS-12 Rename-Allowed-By trailer suppresses a real violation" 0 "$R12" "$SUT"

# ---------------------------------------------------------------------------
# MB — mutation battery. Each mutant is proven landed with `diff -q` against a
# PRISTINE BACKUP, never against HEAD.
# ---------------------------------------------------------------------------
PRISTINE="$WORK/pristine-rename-guard.sh"
cp "$SUT" "$PRISTINE" || { echo "harness: cp failed" >&2; exit 2; }

mb_delete() {
  local label="$1" marker="$2" dir="$3" want_rc="$4"
  local mutant="$WORK/mutant-$marker.sh"
  cp "$PRISTINE" "$mutant" || { fail "$label" "cp failed"; return; }
  grep -v "# MUT:${marker}\b" "$mutant" > "$mutant.new" 2>/dev/null || true
  mv "$mutant.new" "$mutant"
  if diff -q "$PRISTINE" "$mutant" >/dev/null 2>&1; then
    fail "$label" "marker '$marker' matched nothing"
    return
  fi
  # POSITIVE CONTROL (H-2): a mutant destroyed by the deletion (0 bytes, syntax
  # error) also "changes the verdict", so a landing check alone cannot tell a
  # load-bearing branch from a wrecked program. Require the mutant to still BE
  # the guard: it must run and still emit its own banner on an unrelated fixture.
  local ctl
  ctl="$(cd "$R5" && BASE_SHA="$(git -C "$R5" rev-list --max-parents=0 HEAD)" \
        HEAD_SHA="$(git -C "$R5" rev-parse HEAD)" PR_LABELS='[]' bash "$mutant" 2>&1)"
  if ! grep -qF 'rename-guard:' <<<"$ctl"; then
    fail "$label" "mutant is not a working program (no banner on the no-rename control): $(printf '%s' "$ctl" | head -2 | tr '\n' ' ')"
    return
  fi
  assert_guard "$label" "$want_rc" "$dir" "$mutant"
}

# MB-1 (matrix row 3): delete the source-allowlist check -> TS-2 reverts to a
# violation, proving the exemption is load-bearing rather than decorative.
mb_delete "MB-1 deleting the scope-subset exemption reverts TS-2 to a violation" scopesubset "$R2" 1
# MB-3 (r5): narrowing the rename matcher to exact-R100 must redden TS-7.
mb_delete "MB-3 deleting the low-similarity rename flag reverts TS-7" renamethresh "$R7" 0
# MB-4 (r1): the trailer override block was entirely unfixtured.
mb_delete "MB-4 deleting the trailer override reverts TS-12 to a violation" trailer "$R12" 1
# MB-5 (G8): deleting the scope-subset check reverts TS-10 to a pass.


# ---------------------------------------------------------------------------
# MB-2 (matrix row 4): SOURCE and TARGET resolved against DIFFERENT sets.
#
# The dangerous direction is a source set WIDER than the target set: every
# source then reads as "already allowlisted", so a genuine laundering rename is
# exempted and the guard fails OPEN. Injecting that divergence must flip TS-1
# from a violation (1) to a clean pass (0) — which is exactly the regression the
# shared-resolver design prevents. A mutant that changes the verdict on the
# security case is the proof that source and target must share one assembly.
# ---------------------------------------------------------------------------
MUT2="$WORK/mutant-widesource.sh"
cp "$PRISTINE" "$MUT2" || { echo "harness: cp failed" >&2; exit 2; }
python3 - "$MUT2" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
needle = '  src_res="$(matched_allow_res "${source}")"'
assert needle in s, "MB-2 anchor drifted"
# Give the SOURCE a set that matches EVERYTHING: the subset test then always
# holds and every rename is exempt — the two-assemblies fail-open.
s = s.replace(needle, '  src_res="$(printf \'%s\\n\' "${ALLOW_RES[@]}")"', 1)
p.write_text(s)
PYEOF
if diff -q "$PRISTINE" "$MUT2" >/dev/null 2>&1; then
  fail "MB-2 wide-source mutation" "mutation did not land"
else
  assert_guard "MB-2 a source set matching EVERYTHING fails the guard open on TS-1" 0 "$R1" "$MUT2"
fi

# ---------------------------------------------------------------------------
# MB-5: revert the scope-subset test to the OLD boolean ("is the source
# allowlisted at ALL?"). That is the exact defect this guard shipped with, so
# TS-10 must flip from a violation back to a clean pass. A DELETION cannot prove
# this — deleting the exemption makes the guard stricter, not weaker.
# ---------------------------------------------------------------------------
MUT5="$WORK/mutant-oldboolean.sh"
cp "$PRISTINE" "$MUT5" || { echo "harness: cp failed" >&2; exit 2; }
python3 - "$MUT5" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
needle = '  subset=1'
assert needle in s, "MB-5 anchor drifted"
i = s.index(needle)
j = s.index('  matched_re="$(printf', i)
s = s[:i] + '  if [[ -n "${src_res}" ]]; then\n    continue\n  fi\n\n' + s[j:]
p.write_text(s)
PYEOF
if diff -q "$PRISTINE" "$MUT5" >/dev/null 2>&1; then
  fail "MB-5 old-boolean mutation" "mutation did not land"
else
  assert_guard "MB-5 reverting to the old boolean re-opens TS-10 (the shipped defect)" 0 "$R10" "$MUT5"
fi

# ---------------------------------------------------------------------------
# Anti-vacuity floor on this harness's own dispatch.
# ---------------------------------------------------------------------------
EXPECTED_MIN=16
if [[ "$TOTAL" -lt "$EXPECTED_MIN" ]]; then
  echo "FAIL: harness dispatched only $TOTAL assertions (expected >= $EXPECTED_MIN) — vacuous run" >&2
  exit 1
fi

echo
echo "rename-guard: $PASS passed, $FAIL failed, $TOTAL total"
[[ "$FAIL" -eq 0 ]] || exit 1
