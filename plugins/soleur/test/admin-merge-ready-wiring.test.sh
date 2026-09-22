#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2015,SC2016  # row/mutation functions are dispatched indirectly; A && B || why is the assertion idiom
# Guards 2 and 3 of #8500 (plan: knowledge-base/project/plans/2026-09-22-feat-admin-merge-ready-script-plan.md).
#
# Guard 2 -- the wiring lint. Every line under plugins/soleur/ (skills + scripts, *.test.sh
# excluded) that runs `gh pr merge` with `--admin`, after joining backslash continuations, must
# carry `--match-head-commit`. The population is DERIVED by `find` under the root argument, so a
# new skill that adds an admin merge is covered without editing this file (and a `cp -r` copy of
# the tree is read as a tree, not through a .git pointer back to the real index). Plus:
# the reference's merge block runs admin-merge-ready.sh before `gh pr merge`; the old inline
# ADMIN-MERGE-READY block is gone; no .md presents `gh pr checks --required` as sufficient; and
# ship, merge-pr, one-shot and drain-prs each point at the script.
#
# Guard 3 -- the reference's merge block, EXECUTED. The block is prose that agents copy, so the
# suite extracts that exact fenced block and runs it against PATH stubs for gh, sleep and the
# readiness script. It must never print ADMIN-MERGED unless the script exited 0 right before a
# merge that GitHub then reports MERGED at $SHA, and must retry only the base-modified race.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
REF_REL="plugins/soleur/skills/ship/references/settle-then-admin-merge.md"

passes=0; fails=0; CASES_RUN=0; FAILED=()
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
passes=0; fails=0; FAILED=(); CASES_RUN=0

[[ -f "$REPO_ROOT/$REF_REL" ]] || { echo "[FATAL] reference not found at $REPO_ROOT/$REF_REL" >&2; exit 1; }

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
SANDBOX="$(mktemp -d)"; assert_fixture_dir "$SANDBOX"
trap 'rm -rf "$SANDBOX"' EXIT

# ── Guard 2: the lint ───────────────────────────────────────────────────────────────────────
# lint <root> : prints one `VIOLATION ...` line per problem; exit 0 iff none.
lint() {
  local root="$1" v=0 hits=0 f line ref="$1/$REF_REL"
  while IFS= read -r -d '' f; do
    while IFS= read -r line; do
      hits=$((hits + 1))
      [[ "$line" == *--match-head-commit* ]] || { echo "VIOLATION no --match-head-commit: ${f#"$root"/}: $line"; v=1; }
    done < <(awk '{ if (sub(/\\[[:space:]]*$/, "")) { buf = buf $0 " "; next } print buf $0; buf = "" }' "$f" \
               | grep -E -- 'gh pr merge' | grep -E -- '--admin' || true)
  done < <(find "$root/plugins/soleur/skills" "$root/plugins/soleur/scripts" -type f \
             \( -name '*.md' -o -name '*.sh' \) ! -name '*.test.sh' -print0 2>/dev/null)
  (( hits >= 3 )) || { echo "VIOLATION population: only $hits admin-merge lines found (want >= 3) -- the scan is not seeing the tree"; v=1; }

  [[ -f "$ref" ]] || { echo "VIOLATION reference missing: $REF_REL"; return 1; }
  if grep -Fq 'RUNS=$(gh api' "$ref" || grep -Fq 'ADMIN-MERGE-READY $SHA' "$ref"; then
    echo "VIOLATION the inline ADMIN-MERGE-READY block is back in the reference"; v=1
  fi
  # The fenced block holding `gh pr merge` must run admin-merge-ready.sh on an EARLIER line.
  local order
  order=$(awk '/^[[:space:]]*```/ { if (inb) { if (m) print (r && r < m) ? "ok" : "bad"; inb=0 } else { inb=1; r=0; m=0; n=0 } next }
               inb { n++; if (!r && /admin-merge-ready\.sh/) r=n; if (!m && /gh pr merge/) m=n }' "$ref")
  [[ "$order" == "ok" ]] || { echo "VIOLATION reference merge block: want exactly one fenced block with admin-merge-ready.sh before gh pr merge, got '$order'"; v=1; }

  if grep -rlF --include='*.md' "respects the repo's required checks" "$root/plugins/soleur" >/dev/null 2>&1; then
    echo "VIOLATION a doc presents gh pr checks --required as sufficient: $(grep -rlF --include='*.md' "respects the repo's required checks" "$root/plugins/soleur" | head -1)"; v=1
  fi
  local s
  for s in ship merge-pr one-shot drain-prs; do
    grep -Fq 'admin-merge-ready.sh' "$root/plugins/soleur/skills/$s/SKILL.md" 2>/dev/null \
      || { echo "VIOLATION skills/$s/SKILL.md does not reference admin-merge-ready.sh"; v=1; }
  done
  return "$v"
}

mktree() { # <name> -> copy of skills+scripts under a fresh root
  local d="$SANDBOX/tree-$1"; assert_fixture_dir "$d"
  rm -rf "$d"; mkdir -p "$d/plugins/soleur"
  cp -r "$REPO_ROOT/plugins/soleur/skills" "$REPO_ROOT/plugins/soleur/scripts" "$d/plugins/soleur/"
  printf '%s' "$d"
}
edit() { # <file> <old> <new> : exactly-one replacement, or FATAL
  OLD="$2" NEW="$3" python3 - "$1" <<'PY' || { echo "[FATAL] edit did not land in $1" >&2; exit 1; }
import os, sys
p = sys.argv[1]; s = open(p).read(); o = os.environ["OLD"]
if s.count(o) != 1: sys.exit(1)
open(p, "w").write(s.replace(o, os.environ["NEW"]))
PY
}
# case_lint <id> <want: pass|fail> <mutation-fn|-> ; the mutation receives the tree root
case_lint() {
  CASES_RUN=$((CASES_RUN + 1))
  local id="$1" want="$2" fn="$3" t out rc
  t=$(mktree "$id")
  [[ "$fn" == "-" ]] || "$fn" "$t"
  out=$(lint "$t"); rc=$?
  if [[ "$want" == pass && $rc -eq 0 ]] || [[ "$want" == fail && $rc -ne 0 ]]; then pass "$id"
  else fail "$id (lint rc=$rc, want $want): $(head -2 <<<"$out" | tr '\n' '|')"; fi
}

REF_MERGE='if err=$(gh pr merge <N> --squash --admin --match-head-commit "$SHA" 2>&1)'
W1() { edit "$1/$REF_REL" "$REF_MERGE" 'if err=$(gh pr merge <N> --squash --admin 2>&1)'; }
W2() { mkdir -p "$1/plugins/soleur/skills/zz-new"; printf '# x\n\nRun `gh pr merge 1 --squash --admin`.\n' > "$1/plugins/soleur/skills/zz-new/SKILL.md"; }
W3() { printf '\n```bash\nRUNS=$(gh api --paginate "repos/{owner}/{repo}/commits/$SHA/check-runs")\n```\n' >> "$1/$REF_REL"; }
W4() { printf '\nGitHub CLI already respects the repo'"'"'s required checks configuration.\n' >> "$1/plugins/soleur/skills/schedule/SKILL.md"; }
W5() { rm -rf "$1/plugins/soleur/skills" "$1/plugins/soleur/scripts"; mkdir -p "$1/plugins/soleur/skills" "$1/plugins/soleur/scripts"; }
W6() { edit "$1/$REF_REL" '     bash "${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/scripts/admin-merge-ready.sh" <N> "$SHA"; rc=$?
' ''; }
W7() { mkdir -p "$1/plugins/soleur/skills/zz-split"; printf '```bash\ngh pr merge 1 --squash \\\n  --admin\n```\n' > "$1/plugins/soleur/skills/zz-split/SKILL.md"; }
W8() { printf '\nThe CLI respects the repo'"'"'s required checks.\n' >> "$1/plugins/soleur/skills/drain-prs/SKILL.md"; }
WH1() { mkdir -p "$1/plugins/soleur/skills/zz-ok"; printf 'gh pr merge 1 --admin --squash --match-head-commit "$SHA"\n' > "$1/plugins/soleur/skills/zz-ok/SKILL.md"; }
W9() { edit "$1/plugins/soleur/skills/one-shot/SKILL.md" 'plugins/soleur/scripts/admin-merge-ready.sh' 'plugins/soleur/scripts/some-other.sh'; }

echo "== Guard 2: admin-merge wiring lint"
CASES_RUN=$((CASES_RUN + 1))
if out=$(lint "$REPO_ROOT"); then pass "real tree is clean"; else fail "real tree: $out"; fi
case_lint W-H1 pass WH1
case_lint W1 fail W1
case_lint W2 fail W2
case_lint W3 fail W3
case_lint W4 fail W4
case_lint W5 fail W5
case_lint W6 fail W6
case_lint W7 fail W7
case_lint W8 fail W8
case_lint W9-wiring-set fail W9

# ── Guard 3: the merge block, executed ──────────────────────────────────────────────────────
TSHA=abcdefabcdefabcdefabcdefabcdefabcdefabcd
# extract <reference> : the one ```bash block containing `gh pr merge`, or exit 1
extract() {
  awk '/^[[:space:]]*```bash[[:space:]]*$/ { inb=1; buf=""; next }
       /^[[:space:]]*```[[:space:]]*$/ { if (inb && buf ~ /gh pr merge [^ ]+ --squash --admin/) { printf "%s", buf; found++ } inb=0; next }
       inb { sub(/^   /, ""); buf = buf $0 "\n" }
       END { exit (found == 1) ? 0 : 1 }' "$1"
}
G3="$SANDBOX/g3"; mkdir -p "$G3/bin" "$G3/root/scripts"
cat > "$G3/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$G3_DIR/gh.log"
case "$*" in
  "pr merge 4242 --squash --admin --match-head-commit $G3_SHA")
    n=$(( $(cat "$G3_DIR/merges" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$G3_DIR/merges"
    mode=$(sed -n "${n}p" "$G3_DIR/merge_modes"); [[ -n "$mode" ]] || mode=$(tail -1 "$G3_DIR/merge_modes")
    case "$mode" in
      ok) exit 0 ;;
      race) echo "GraphQL: Base branch was modified. Review and try the merge again. (mergePullRequest)" >&2; exit 1 ;;
      *) echo "GraphQL: Resource not accessible by integration" >&2; exit 1 ;;
    esac ;;
  'pr view 4242 --json state,headRefOid --jq "\(.state) \(.headRefOid)"')
    cat "$G3_DIR/state" ;;
  *) echo "STUB-MISS $*" >> "$G3_DIR/gh.log"; exit 64 ;;
esac
GH
printf '#!/usr/bin/env bash\necho sleep >> "$G3_DIR/sleeps"\n' > "$G3/bin/sleep"
cat > "$G3/root/scripts/admin-merge-ready.sh" <<'RDY'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$G3_DIR/ready.log"
n=$(( $(cat "$G3_DIR/readies" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$G3_DIR/readies"
rc=$(sed -n "${n}p" "$G3_DIR/ready_rcs"); exit "${rc:-0}"
RDY
chmod +x "$G3/bin/gh" "$G3/bin/sleep" "$G3/root/scripts/admin-merge-ready.sh"

BLOCK_SRC="$G3/block.sh"
if ! extract "$REPO_ROOT/$REF_REL" > "$BLOCK_SRC"; then echo "[FATAL] Guard 3: no merge block extracted from $REF_REL" >&2; exit 1; fi

# g3 <id> <sha-line-value> <ready_rcs> <merge_modes> <state> ; runs the block, leaves $G3_DIR
g3() {
  G3_DIR="$G3/run-$1"; rm -rf "$G3_DIR"; mkdir -p "$G3_DIR"
  printf '%b' "$3" > "$G3_DIR/ready_rcs"; printf '%b' "$4" > "$G3_DIR/merge_modes"; printf '%s\n' "$5" > "$G3_DIR/state"
  : > "$G3_DIR/gh.log"
  sed -e 's/<N>/4242/g' -e "s|^SHA=<the sha= value.*|SHA=$2|" "$BLOCK_SRC" > "$G3_DIR/block.sh"
  grep -q '<' "$G3_DIR/block.sh" && grep -qE '<[A-Za-z]' "$G3_DIR/block.sh" \
    && { echo "[FATAL] unsubstituted placeholder in the block" >&2; exit 1; }
  export G3_DIR
  G3_SHA="$TSHA" CLAUDE_PLUGIN_ROOT="$G3/root" PATH="$G3/bin:$PATH" \
    timeout 30 bash "$G3_DIR/block.sh" > "$G3_DIR/out" 2> "$G3_DIR/err"
  echo $? > "$G3_DIR/rc"
}
merges() { cat "$G3_DIR/merges" 2>/dev/null || echo 0; }
g3_case() { # <id> <cond-description> <condition-expression...>
  CASES_RUN=$((CASES_RUN + 1))
  local id="$1"; shift
  if ! grep -q '^STUB-MISS' "$G3_DIR/gh.log" && eval "$*"; then pass "$id"
  else fail "$id: rc=$(cat "$G3_DIR/rc") merges=$(merges) out=$(tr '\n' '|' < "$G3_DIR/out") log=$(tr '\n' '|' < "$G3_DIR/gh.log")"; fi
}

echo "== Guard 3: the reference's merge block, executed"
g3 M1 "$TSHA" '' 'race\n' "OPEN $TSHA"
g3_case M1 '[[ $(cat $G3_DIR/rc) == 1 && $(merges) == 20 ]] && grep -qx "ADMIN-MERGE NOT LANDED" $G3_DIR/out && ! grep -q "^ADMIN-MERGED" $G3_DIR/out'
g3 M2 "$TSHA" '' 'other\n' "OPEN $TSHA"
g3_case M2 '[[ $(cat $G3_DIR/rc) == 1 && $(merges) == 1 ]] && grep -q "^ADMIN-MERGE ABORTED (gh pr merge failed" $G3_DIR/out'
g3 M3 "$TSHA" '0\n1\n' 'race\nok\n' "MERGED $TSHA"
g3_case M3 '[[ $(cat $G3_DIR/rc) == 1 && $(merges) == 1 ]] && grep -q "^ADMIN-MERGE ABORTED rc=1" $G3_DIR/out && ! grep -q "^ADMIN-MERGED" $G3_DIR/out'
g3 M4 "$TSHA" '' 'ok\n' "MERGED $TSHA"
g3_case M4 '[[ $(cat $G3_DIR/rc) == 0 && $(merges) == 1 ]] && grep -qx "ADMIN-MERGED $TSHA" $G3_DIR/out && grep -qx "4242 $TSHA" $G3_DIR/ready.log && grep -q -- "--match-head-commit $TSHA" $G3_DIR/gh.log'
g3 M5 "$TSHA" '' 'ok\n' "OPEN $TSHA"
g3_case M5 '[[ $(cat $G3_DIR/rc) == 1 ]] && grep -qx "ADMIN-MERGE NOT LANDED" $G3_DIR/out'
g3 M6 "" '' 'ok\n' "MERGED $TSHA"
g3_case M6 '[[ $(cat $G3_DIR/rc) == 1 && $(merges) == 0 ]] && grep -qx "ADMIN-MERGE ABORTED: SHA not set" $G3_DIR/out'
g3 M-race-then-land "$TSHA" '' 'race\nok\n' "MERGED $TSHA"
g3_case M-race-then-land '[[ $(cat $G3_DIR/rc) == 0 && $(merges) == 2 && $(wc -l < $G3_DIR/sleeps) == 1 && $(wc -l < $G3_DIR/ready.log) == 2 ]]'
# M7: a reference whose merge block cannot be found must not extract (no vacuous pass).
CASES_RUN=$((CASES_RUN + 1))
m7="$SANDBOX/m7.md"; cp "$REPO_ROOT/$REF_REL" "$m7"; edit "$m7" '```bash
   SHA=<the sha=' '```sh
   SHA=<the sha='
if extract "$m7" >/dev/null; then fail "M7 (extraction succeeded on a reference with no merge block)"; else pass "M7"; fi

EXPECTED_CASES=19
echo
echo "== $passes passed, $fails failed, $CASES_RUN cases =="
if [[ "$CASES_RUN" -ne "$EXPECTED_CASES" || $((passes + fails)) -ne "$CASES_RUN" ]]; then
  printf '[FATAL] ran %s cases (%s verdicts), expected %s\n' "$CASES_RUN" "$((passes + fails))" "$EXPECTED_CASES" >&2; exit 1
fi
if (( fails > 0 )); then printf '  failed: %s\n' "${FAILED[@]}" >&2; exit 1; fi
exit 0
