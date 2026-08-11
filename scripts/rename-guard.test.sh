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
  assert_guard "$label" "$want_rc" "$dir" "$mutant"
}

# MB-1 (matrix row 3): delete the source-allowlist check -> TS-2 reverts to a
# violation, proving the exemption is load-bearing rather than decorative.
mb_delete "MB-1 deleting the source check reverts TS-2 to a violation" srcallow "$R2" 1

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
MUT2="$WORK/mutant-splitsets.sh"
cp "$PRISTINE" "$MUT2" || { echo "harness: cp failed" >&2; exit 2; }
python3 - "$MUT2" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
# Give the SOURCE call its own, wider resolver — the two-assemblies defect.
needle = 'if matching_allow_re "${source}" >/dev/null; then'
assert needle in s, "source call site not found — MB-2 marker drifted"
s = s.replace(needle, 'if matching_allow_re_wide "${source}" >/dev/null; then', 1)
s = s.replace('violations=""\nwhile IFS=', 'matching_allow_re_wide() { return 0; }\nviolations=""\nwhile IFS=', 1)
p.write_text(s)
PY
if diff -q "$PRISTINE" "$MUT2" >/dev/null 2>&1; then
  fail "MB-2 split-set mutation" "mutation did not land"
else
  assert_guard "MB-2 a WIDER source set fails the guard open on TS-1" 0 "$R1" "$MUT2"
fi

# ---------------------------------------------------------------------------
# Anti-vacuity floor on this harness's own dispatch.
# ---------------------------------------------------------------------------
EXPECTED_MIN=8
if [[ "$TOTAL" -lt "$EXPECTED_MIN" ]]; then
  echo "FAIL: harness dispatched only $TOTAL assertions (expected >= $EXPECTED_MIN) — vacuous run" >&2
  exit 1
fi

echo
echo "rename-guard: $PASS passed, $FAIL failed, $TOTAL total"
[[ "$FAIL" -eq 0 ]] || exit 1
