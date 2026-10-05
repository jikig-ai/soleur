#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2015,SC2016  # row/mutation functions are dispatched indirectly; A && B || C is the assertion idiom; literals are single-quoted on purpose
# Guards 2 and 3 of #8500 (plan: knowledge-base/project/plans/archive/20260922-120349-2026-09-22-feat-admin-merge-ready-script-plan.md).
#
# Guard 2 -- the wiring lint. The population is DERIVED: every text file under plugins/soleur/
# (test directories and *.test.* excluded), walked with `find` under the root argument, so a new
# skill, agent, command or script that adds an admin merge is covered without editing this file
# (and a `cp -r` copy of the tree is read as a tree, not through a .git pointer to the real index).
# After joining backslash continuations and stripping a trailing shell comment, every line that
# runs `gh pr merge` (any whitespace) with an `--admin` token must:
#   * carry a `--match-head-commit` TOKEN (a comment mentioning it does not count), and
#   * be preceded by admin-merge-ready.sh -- earlier on the same line, or on an earlier line of the
#     same fenced block (same file, for scripts).
# Plus: no API-level merge (`pulls/<n>/merge` PUT, `mergePullRequest`) anywhere in the population;
# the old inline ADMIN-MERGE-READY block is gone from the reference; no doc presents
# `gh pr checks --required` as a sufficient gate; ship, merge-pr, one-shot and drain-prs each
# point at the script. Every W row asserts the REASON it reds, not merely that it reds.
#
# Guard 3 -- the reference's merge block, EXECUTED. The block is prose that agents copy, so the
# suite extracts that exact fenced block and runs it against PATH stubs for gh, sleep and the
# readiness script. It must never print ADMIN-MERGED unless GitHub reports the PR MERGED at $SHA,
# must re-run the readiness script before every attempt, and must retry only the base-modified race.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
REF_REL="plugins/soleur/skills/ship/references/settle-then-admin-merge.md"
CONST_REL="knowledge-base/project/constitution.md"

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
command -v python3 >/dev/null || { echo "[FATAL] python3 required" >&2; exit 1; }
TIMEOUT_BIN="$(command -v timeout)" || { echo "[FATAL] timeout(1) required" >&2; exit 1; }

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
  local root="$1" v=0 out hits ref="$1/$REF_REL"
  out=$(find "$root/plugins/soleur" -type d \( -name test -o -name tests -o -name node_modules -o -name fixtures \) -prune -o \
          -type f \( -name '*.md' -o -name '*.sh' -o -name '*.ts' -o -name '*.js' -o -name '*.mjs' -o -name '*.py' \
                     -o -name '*.yml' -o -name '*.yaml' -o -name '*.json' -o -name '*.njk' -o -name '*.txt' \) \
          ! -name '*.test.*' -print0 2>/dev/null \
        | xargs -0 -r awk -v ROOT="$root/" '
            FNR == 1 { seen = 0 }
            /^[[:space:]]*```/ { seen = 0; next }
            {
              line = $0
              while (sub(/\\[[:space:]]*$/, "", line)) { if ((getline nxt) <= 0) break; line = line " " nxt }
              code = line; sub(/[[:space:]]#.*$/, "", code)
              f = FILENAME; sub("^" ROOT, "", f)
              mp = match(code, /gh[[:space:]]+pr[[:space:]]+merge/)
              if (mp && code ~ /(^|[^A-Za-z0-9_-])--admin([^A-Za-z0-9_-]|$)/) {
                hits++
                if (code !~ /(^|[^A-Za-z0-9_-])--match-head-commit([^A-Za-z0-9_-]|$)/)
                  print "VIOLATION no --match-head-commit: " f ": " line
                if (!seen && substr(code, 1, mp - 1) !~ /admin-merge-ready\.sh/)
                  print "VIOLATION no admin-merge-ready.sh before the merge: " f ": " line
              }
              if ((code ~ /pulls\/[^[:space:]]*\/merge/ && code ~ /PUT/) || code ~ /mergePullRequest[[:space:]]*\(/)
                print "VIOLATION API-level merge: " f ": " line
              if (code ~ /admin-merge-ready\.sh/) seen = 1
            }
            END { print "HITS " hits + 0 }')
  hits=$(grep -oE '^HITS [0-9]+$' <<<"$out" | tail -1 | cut -d' ' -f2)
  grep '^VIOLATION' <<<"$out" && v=1
  (( ${hits:-0} >= 3 )) || { echo "VIOLATION population: only ${hits:-0} admin-merge lines found (want >= 3) -- the scan is not seeing the tree"; v=1; }

  if [[ ! -f "$ref" ]]; then echo "VIOLATION reference missing: $REF_REL"; return 1; fi
  if grep -Fq 'RUNS=$(gh api' "$ref" || grep -Fq 'ADMIN-MERGE-READY $SHA' "$ref"; then
    echo "VIOLATION the inline ADMIN-MERGE-READY block is back in the reference"; v=1
  fi
  local nblocks
  nblocks=$(awk '/^[[:space:]]*```/ { if (inb) { if (m) n++; inb = 0 } else { inb = 1; m = 0 } next }
                 inb && /gh[[:space:]]+pr[[:space:]]+merge/ && /--admin/ { m = 1 } END { print n + 0 }' "$ref")
  [[ "$nblocks" == 1 ]] || { echo "VIOLATION reference merge block: want exactly one fenced block running an admin merge, got $nblocks"; v=1; }

  local phrase hit
  for phrase in "respects the repo's required checks" "already maintains the authoritative definition"; do
    hit=$( { grep -rlF --include='*.md' "$phrase" "$root/plugins/soleur" 2>/dev/null; grep -lF "$phrase" "$root/$CONST_REL" 2>/dev/null; } | head -1)
    [[ -z "$hit" ]] || { echo "VIOLATION a doc presents gh pr checks --required as sufficient: ${hit#"$root"/}"; v=1; }
  done
  local s
  for s in ship merge-pr one-shot drain-prs; do
    grep -Fq 'admin-merge-ready.sh' "$root/plugins/soleur/skills/$s/SKILL.md" 2>/dev/null \
      || { echo "VIOLATION skills/$s/SKILL.md does not reference admin-merge-ready.sh"; v=1; }
  done
  return "$v"
}

mktree() { # <name> -> a copy of plugins/soleur (+ the constitution) under a fresh root
  local d="$SANDBOX/tree-$1"; assert_fixture_dir "$d"
  rm -rf "$d"; mkdir -p "$d/plugins" "$d/knowledge-base/project"
  cp -r "$REPO_ROOT/plugins/soleur" "$d/plugins/"
  cp "$REPO_ROOT/$CONST_REL" "$d/$CONST_REL"
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
plant() { # <root> <relpath> <content> : write a new file under the tree
  assert_fixture_dir "$1"
  mkdir -p "$(dirname "$1/$2")"
  printf '%b' "$3" > "$1/$2"
}
# case_lint <id> <want: pass | expected VIOLATION prefix> <mutation-fn|->
case_lint() {
  CASES_RUN=$((CASES_RUN + 1))
  local id="$1" want="$2" fn="$3" t out rc
  t=$(mktree "$id"); assert_fixture_dir "$t"
  [[ "$fn" == "-" ]] || "$fn" "$t"
  out=$(lint "$t"); rc=$?
  if [[ "$want" == pass ]]; then
    if (( rc == 0 )); then pass "$id"; else fail "$id (lint rc=$rc, want pass): $(head -2 <<<"$out" | tr '\n' '|')"; fi
  elif (( rc != 0 )) && grep -qF -- "$want" <<<"$out"; then pass "$id"
  else fail "$id (lint rc=$rc, want '$want'): $(head -3 <<<"$out" | tr '\n' '|')"; fi
}

REF_MERGE='if err=$(gh pr merge <N> --squash --admin --match-head-commit "$SHA" 2>&1)'
# The gate line as it appears in the reference; the placeholder brackets are built from
# variables so no line of this file carries a redirect-shaped literal.
LT='<'; GT='>'
REF_GATE="     bash \"\${CLAUDE_PLUGIN_ROOT}/scripts/admin-merge-ready.sh\" ${LT}N${GT} \"\$SHA\"; rc=\$?"$'\n'
W1() { edit "$1/$REF_REL" "$REF_MERGE" 'if err=$(gh pr merge <N> --squash --admin 2>&1)'; }
W2() { plant "$1" plugins/soleur/skills/zz-new/SKILL.md '# x\n\nRun `gh pr merge 1 --squash --admin`.\n'; }
W3() { assert_fixture_dir "$1"; printf '\n```bash\nRUNS=$(gh api --paginate "repos/{owner}/{repo}/commits/$SHA/check-runs")\n```\n' >> "$1/$REF_REL"; }
W4() { assert_fixture_dir "$1"; printf '\nGitHub CLI already respects the repo'"'"'s required checks configuration.\n' >> "$1/plugins/soleur/skills/schedule/SKILL.md"; }
W5() { assert_fixture_dir "$1"; local f
  for f in "$REF_REL" plugins/soleur/skills/ship/SKILL.md plugins/soleur/skills/merge-pr/SKILL.md; do
    python3 - "$1/$f" <<'PY'
import re, sys
p = sys.argv[1]
keep = [l for l in open(p).read().split("\n") if not (re.search(r"gh\s+pr\s+merge", l) and "--admin" in l)]
open(p, "w").write("\n".join(keep))
PY
  done; }
W6() { edit "$1/$REF_REL" "$REF_GATE" ''; }
W7() { plant "$1" plugins/soleur/skills/zz-split/SKILL.md '```bash\nbash scripts/admin-merge-ready.sh 1 "$S"\ngh pr merge 1 --squash \\\n  --admin\n```\n'; }
W8() { assert_fixture_dir "$1"; printf '\nThe CLI respects the repo'"'"'s required checks.\n' >> "$1/plugins/soleur/skills/drain-prs/SKILL.md"; }
W9() { edit "$1/plugins/soleur/skills/one-shot/SKILL.md" 'which runs `"${CLAUDE_PLUGIN_ROOT}/scripts/admin-merge-ready.sh"`' 'which runs a readiness check'; }
W10() { plant "$1" plugins/soleur/scripts/zz-merge.sh '#!/usr/bin/env bash\ngh pr merge "$1" --squash --admin --match-head-commit "$2"\n'; }
W11() { edit "$1/$REF_REL" "$REF_GATE" ''
  edit "$1/$REF_REL" '     sleep 18' "$REF_GATE"'     sleep 18'; }
W12() { plant "$1" plugins/soleur/skills/zz-ws/SKILL.md '```bash\nbash scripts/admin-merge-ready.sh 1 "$S"\ngh  pr merge 1 --squash --admin\n```\n'; }
W13() { plant "$1" plugins/soleur/skills/zz-cmt/SKILL.md '```bash\nbash scripts/admin-merge-ready.sh 1 "$S"\ngh pr merge 1 --squash --admin  # always add --match-head-commit\n```\n'; }
W14() { plant "$1" plugins/soleur/agents/zz-agent.md '```bash\ngh pr merge 1 --squash --admin\n```\n'; }
W15() { plant "$1" plugins/soleur/skills/zz-api/SKILL.md '```bash\ngh api -X PUT "repos/{owner}/{repo}/pulls/1/merge" -f merge_method=squash\n```\n'; }
W16() { assert_fixture_dir "$1"; printf '\nGitHub already maintains the authoritative definition of required checks.\n' >> "$1/$CONST_REL"; }
WH1() { plant "$1" plugins/soleur/skills/zz-ok/SKILL.md '```bash\nbash scripts/admin-merge-ready.sh 1 "$SHA" || exit 1\ngh pr merge 1 --admin --squash --match-head-commit "$SHA"\n```\n'; }
WH0() { plant "$1" plugins/soleur/skills/zz-nogate/SKILL.md '```bash\ngh pr merge 1 --admin --squash --match-head-commit "$SHA"\n```\n'; }

echo "== Guard 2: admin-merge wiring lint"
CASES_RUN=$((CASES_RUN + 1))
if out=$(lint "$REPO_ROOT"); then pass "real tree is clean"; else fail "real tree: $out"; fi
case_lint W-H1 pass WH1
case_lint W-H0 "VIOLATION no admin-merge-ready.sh before the merge" WH0
case_lint W1 "VIOLATION no --match-head-commit" W1
case_lint W2 "VIOLATION no --match-head-commit" W2
case_lint W3 "VIOLATION the inline ADMIN-MERGE-READY block" W3
case_lint W4 "VIOLATION a doc presents" W4
case_lint W5 "VIOLATION population" W5
case_lint W6 "VIOLATION no admin-merge-ready.sh before the merge" W6
case_lint W7 "VIOLATION no --match-head-commit" W7
case_lint W8 "VIOLATION a doc presents" W8
case_lint W9 "VIOLATION skills/one-shot/SKILL.md" W9
case_lint W10-scripts "VIOLATION no admin-merge-ready.sh before the merge: plugins/soleur/scripts/zz-merge.sh" W10
case_lint W11-order "VIOLATION no admin-merge-ready.sh before the merge: $REF_REL" W11
case_lint W12-whitespace "VIOLATION no --match-head-commit: plugins/soleur/skills/zz-ws" W12
case_lint W13-comment "VIOLATION no --match-head-commit: plugins/soleur/skills/zz-cmt" W13
case_lint W14-agents "VIOLATION no --match-head-commit: plugins/soleur/agents/zz-agent.md" W14
case_lint W15-api "VIOLATION API-level merge" W15
case_lint W16-constitution "VIOLATION a doc presents gh pr checks --required as sufficient: $CONST_REL" W16

# ── Guard 3: the merge block, executed ──────────────────────────────────────────────────────
TSHA=abcdefabcdefabcdefabcdefabcdefabcdefabcd
# extract <reference> : the one ```bash block running an admin merge, or exit 1
extract() {
  awk '/^[[:space:]]*```bash[[:space:]]*$/ { inb=1; buf=""; next }
       /^[[:space:]]*```[[:space:]]*$/ { if (inb && buf ~ /gh pr merge [^ ]+ --squash --admin/) { printf "%s", buf; found++ } inb=0; next }
       inb { sub(/^   /, ""); buf = buf $0 "\n" }
       END { exit (found == 1) ? 0 : 1 }' "$1"
}
G3="$SANDBOX/g3"; assert_fixture_dir "$G3"; mkdir -p "$G3/bin" "$G3/root/scripts"
cat > "$G3/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$G3_DIR/gh.log"
nth() { local n=$1 f=$2 v; v=$(sed -n "${n}p" "$f"); [[ -n "$v" ]] || v=$(tail -1 "$f"); printf '%s' "$v"; }
case "$*" in
  "pr merge 4242 --squash --admin --match-head-commit $G3_SHA")
    n=$(( $(cat "$G3_DIR/merges" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$G3_DIR/merges"
    case "$(nth "$n" "$G3_DIR/merge_modes")" in
      ok) exit 0 ;;
      race) echo "GraphQL: Base branch was modified. Review and try the merge again. (mergePullRequest)" >&2; exit 1 ;;
      *) echo "GraphQL: Resource not accessible by integration" >&2; exit 1 ;;
    esac ;;
  'pr view 4242 --json state,headRefOid --jq "\(.state) \(.headRefOid)"')
    n=$(( $(cat "$G3_DIR/views" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$G3_DIR/views"
    grep -qx "$n" "$G3_DIR/view_fail" 2>/dev/null && { echo "HTTP 502" >&2; exit 1; }
    nth "$n" "$G3_DIR/states"; echo ;;
  *) echo "STUB-MISS $*" >> "$G3_DIR/gh.log"; exit 64 ;;
esac
GH
cat > "$G3/bin/sleep" <<'SLP'
#!/usr/bin/env bash
echo "$*" >> "$G3_DIR/sleeps"
SLP
cat > "$G3/root/scripts/admin-merge-ready.sh" <<'RDY'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$G3_DIR/ready.log"
n=$(( $(cat "$G3_DIR/readies" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$G3_DIR/readies"
rc=$(sed -n "${n}p" "$G3_DIR/ready_rcs"); exit "${rc:-0}"
RDY
chmod +x "$G3/bin/gh" "$G3/bin/sleep" "$G3/root/scripts/admin-merge-ready.sh"
mkdir -p "$G3/root/.claude-plugin" && printf '{"name":"soleur"}\n' > "$G3/root/.claude-plugin/plugin.json"

BLOCK_SRC="$G3/block.sh"
if ! extract "$REPO_ROOT/$REF_REL" > "$BLOCK_SRC"; then echo "[FATAL] Guard 3: no merge block extracted from $REF_REL" >&2; exit 1; fi
grep -q '^SHA=<the 40-hex head SHA' "$BLOCK_SRC" || { echo "[FATAL] Guard 3: the block's SHA= placeholder line moved; update g3()" >&2; exit 1; }
# #7453 (ADR-179 A20): the reference is Read, not loader-delivered, so the token reaches bash
# unreplaced; the block's first line refuses an unset, relative or inside-the-checkout root
# (exit 5) before any gh call — a root inside the checkout would make the gate the PR's own copy.
# g3() exports the fixture root, as a hosted session or the agent's own export would; M13, M15
# and M16 run the block with a refused root.
PRESENCE_LINE='_top=$(git rev-parse --show-toplevel 2>/dev/null); [[ "${CLAUDE_PLUGIN_ROOT}" == /* && -r "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" && ( -z "$_top" || "$(realpath "${CLAUDE_PLUGIN_ROOT}")/" != "$_top/"* ) ]] || { echo "ADMIN-MERGE ABORTED: plugin root unresolved or inside this checkout"; exit 5; }'
REFUSED_MSG='ADMIN-MERGE ABORTED: plugin root unresolved or inside this checkout'
[[ "$(head -1 "$BLOCK_SRC")" == "$PRESENCE_LINE" ]] || { echo "[FATAL] Guard 3: the block no longer opens with the plugin-root presence check" >&2; exit 1; }
# Every bash fence that calls admin-merge-ready.sh (the --wait gate, the merge block, the
# was-green carryover) must OPEN with the presence line — not just the merge block above.
fence_heads="$(awk '/^[[:space:]]*```bash[[:space:]]*$/ { inb=1; first=""; body=""; next }
  /^[[:space:]]*```[[:space:]]*$/ { if (inb && body ~ /admin-merge-ready[.]sh/) print first; inb=0; next }
  inb { l=$0; sub(/^   /, "", l); if (first == "") first=l; body=body l "\n" }' "$REPO_ROOT/$REF_REL")"
n_fences="$(printf '%s\n' "$fence_heads" | grep -c .)"
n_guarded="$(printf '%s\n' "$fence_heads" | grep -cxF "$PRESENCE_LINE")"
CASES_RUN=$((CASES_RUN + 1))
if [[ "$n_fences" -eq 3 && "$n_guarded" -eq 3 ]]; then pass "G3-all-gate-fences-open-with-presence-check"
else fail "G3-all-gate-fences-open-with-presence-check: fences=$n_fences guarded=$n_guarded"; fi

# g3 <id> <sha-line-value> <ready_rcs> <merge_modes> <states> [view_fail] ; runs the block
g3() {
  G3_DIR="$G3/run-$1"; assert_fixture_dir "$G3_DIR"; rm -rf "$G3_DIR"; mkdir -p "$G3_DIR"
  printf '%b' "$3" > "$G3_DIR/ready_rcs"; printf '%b' "$4" > "$G3_DIR/merge_modes"; printf '%b' "$5" > "$G3_DIR/states"
  printf '%b' "${6-}" > "$G3_DIR/view_fail"
  : > "$G3_DIR/gh.log"; : > "$G3_DIR/sleeps"; : > "$G3_DIR/ready.log"
  sed -e 's/<N>/4242/g' -e "s|^SHA=<the 40-hex head SHA.*|SHA=$2|" "$BLOCK_SRC" > "$G3_DIR/block.sh"
  if grep -qE '<[A-Za-z]' "$G3_DIR/block.sh"; then echo "[FATAL] unsubstituted placeholder in the block" >&2; exit 1; fi
  export G3_DIR
  G3_SHA="$TSHA" CLAUDE_PLUGIN_ROOT="$G3/root" PATH="$G3/bin:$PATH" \
    "$TIMEOUT_BIN" 30 bash "$G3_DIR/block.sh" > "$G3_DIR/out" 2> "$G3_DIR/err"
  echo $? > "$G3_DIR/rc"
}
merges() { cat "$G3_DIR/merges" 2>/dev/null || echo 0; }
readies() { wc -l < "$G3_DIR/ready.log"; }
g3_case() { # <id> <condition-expression>
  CASES_RUN=$((CASES_RUN + 1))
  local id="$1"; shift
  if ! grep -q '^STUB-MISS' "$G3_DIR/gh.log" && eval "$*"; then pass "$id"
  else fail "$id: rc=$(cat "$G3_DIR/rc") merges=$(merges) readies=$(readies) out=$(tr '\n' '|' < "$G3_DIR/out") log=$(tr '\n' '|' < "$G3_DIR/gh.log")"; fi
}
RC='$(cat $G3_DIR/rc)'

echo "== Guard 3: the reference's merge block, executed"
g3 M1 "$TSHA" '' 'race\n' "OPEN $TSHA\n"
g3_case M1 "[[ $RC == 1 && \$(merges) == 20 && \$(readies) == 20 ]] && grep -qx 'ADMIN-MERGE NOT LANDED' \$G3_DIR/out && ! grep -q '^ADMIN-MERGED' \$G3_DIR/out"
g3 M2 "$TSHA" '' 'other\n' "OPEN $TSHA\n"
g3_case M2 "[[ $RC == 1 && \$(merges) == 1 ]] && grep -q '^ADMIN-MERGE ABORTED (gh pr merge failed' \$G3_DIR/out"
g3 M2b "$TSHA" '' 'other\n' "OPEN $TSHA\nMERGED $TSHA\n"
g3_case M2b-merged-despite-error "[[ $RC == 0 && \$(merges) == 1 ]] && grep -qx 'ADMIN-MERGED $TSHA' \$G3_DIR/out"
g3 M3 "$TSHA" '0\n4\n' 'race\nok\n' "OPEN $TSHA\n"
g3_case M3-stale-passthrough "[[ $RC == 4 && \$(merges) == 1 ]] && grep -q '^ADMIN-MERGE ABORTED rc=4' \$G3_DIR/out && ! grep -q '^ADMIN-MERGED' \$G3_DIR/out"
g3 M4 "$TSHA" '' 'ok\n' "OPEN $TSHA\nMERGED $TSHA\n"
g3_case M4 "[[ $RC == 0 && \$(merges) == 1 ]] && grep -qx 'ADMIN-MERGED $TSHA' \$G3_DIR/out && grep -qx '4242 $TSHA' \$G3_DIR/ready.log && grep -q -- '--match-head-commit $TSHA' \$G3_DIR/gh.log"
g3 M5 "$TSHA" '' 'ok\n' "OPEN $TSHA\n"
g3_case M5-enqueued-only "[[ $RC == 1 ]] && grep -qx 'ADMIN-MERGE NOT LANDED' \$G3_DIR/out"
g3 M6 "" '' 'ok\n' "MERGED $TSHA\n"
g3_case M6-empty-sha "[[ $RC == 1 && \$(merges) == 0 && ! -s \$G3_DIR/gh.log ]] && grep -qx 'ADMIN-MERGE ABORTED: SHA not set' \$G3_DIR/out"
g3 M6b "${TSHA:0:7}" '' 'ok\n' "MERGED $TSHA\n"
g3_case M6b-short-sha "[[ $RC == 1 && \$(merges) == 0 ]] && grep -qx 'ADMIN-MERGE ABORTED: SHA not set' \$G3_DIR/out"
g3 M8 "$TSHA" '' 'ok\n' "MERGED $TSHA\n"
g3_case M8-already-merged "[[ $RC == 0 && \$(merges) == 0 && \$(readies) == 0 ]] && grep -qx 'ADMIN-MERGED $TSHA' \$G3_DIR/out"
g3 M9 "$TSHA" '' 'ok\n' "OPEN $TSHA\n" '2\n'
g3_case M9-unreadable-state "[[ $RC == 1 ]] && grep -q '^ADMIN-MERGE UNKNOWN' \$G3_DIR/out && ! grep -q '^ADMIN-MERGED' \$G3_DIR/out"
g3 M10 "$TSHA" '' 'ok\n' "OPEN $TSHA\nMERGED 1111111111111111111111111111111111111111\n"
g3_case M10-other-sha "[[ $RC == 1 ]] && grep -qx 'ADMIN-MERGE NOT LANDED' \$G3_DIR/out"
g3 M11 "$TSHA" '' 'race\nok\n' "OPEN $TSHA\nOPEN $TSHA\nMERGED $TSHA\n"
g3_case M11-race-then-land "[[ $RC == 0 && \$(merges) == 2 && \$(wc -l < \$G3_DIR/sleeps) == 1 && \$(readies) == 2 ]]"
# M12: the positive row, stated explicitly — with the root exported, the stubbed gate RAN and
# the fake gh actually merged (proves the fake gh is on PATH).
g3 M12 "$TSHA" '' 'ok\n' "OPEN $TSHA\nMERGED $TSHA\n"
g3_case M12-root-exported-runs-gate "[[ $RC == 0 && -s \$G3_DIR/ready.log && \$(merges) == 1 ]]"
# M13: the block AS SHIPPED with the root unset. It must abort with exit 5 before any gh call. Ledgers are pre-created empty FILES and read directly, never through $(...).
CASES_RUN=$((CASES_RUN + 1))
M13="$G3/run-M13"; assert_fixture_dir "$M13"; rm -rf "$M13"; mkdir -p "$M13"
: > "$M13/gh.log"; : > "$M13/ready.log"
sed -e 's/<N>/4242/g' -e "s|^SHA=<the 40-hex head SHA.*|SHA=$TSHA|" "$BLOCK_SRC" > "$M13/block.sh"
G3_DIR="$M13" G3_SHA="$TSHA" PATH="$G3/bin:$PATH" env -u CLAUDE_PLUGIN_ROOT -u GROK_PLUGIN_ROOT \
  "$TIMEOUT_BIN" 30 bash "$M13/block.sh" > "$M13/out" 2> "$M13/err"
m13_rc=$?
if [[ "$m13_rc" -eq 5 ]] && grep -qxF "$REFUSED_MSG" "$M13/out" \
   && [[ ! -s "$M13/gh.log" && ! -s "$M13/ready.log" ]]; then
  pass "M13-unset-root-aborts-5"
else
  fail "M13-unset-root-aborts-5: rc=$m13_rc out=$(tr '\n' '|' < "$M13/out") gh=$(tr '\n' '|' < "$M13/gh.log")"
fi
# M14: the twin control. The PRE-migration block (the token with a default arm, no presence
# check), root unset, run from a tree holding a decoy gate: the decoy MUST run.
# That proves a decoy at that path is reachable at all, so M13's empty ledger means something.
# The default arm is assembled from pieces so this file never spells the rejected form.
CASES_RUN=$((CASES_RUN + 1))
M14="$G3/run-M14"; assert_fixture_dir "$M14"; rm -rf "$M14"; mkdir -p "$M14/plugins/soleur/scripts"
: > "$M14/gh.log"; : > "$M14/decoy.log"
printf '#!/usr/bin/env bash\necho decoy-ran >> "%s"\nexit 1\n' "$M14/decoy.log" > "$M14/plugins/soleur/scripts/admin-merge-ready.sh"
chmod +x "$M14/plugins/soleur/scripts/admin-merge-ready.sh"
DEF=':-'; OLD_ARM="\${CLAUDE_PLUGIN_ROOT${DEF}plugins/soleur}"
grep -vF 'ADMIN-MERGE ABORTED: plugin root unresolved' "$BLOCK_SRC" \
  | sed -e 's/<N>/4242/g' -e "s|^SHA=<the 40-hex head SHA.*|SHA=$TSHA|" \
        -e "s|\"\\\${CLAUDE_PLUGIN_ROOT}/scripts/admin-merge-ready.sh\"|\"$OLD_ARM/scripts/admin-merge-ready.sh\"|" > "$M14/block.sh"
grep -qF "$OLD_ARM" "$M14/block.sh" || { echo "[FATAL] M14: the pre-migration rewrite did not land" >&2; exit 1; }
( cd "$M14" && G3_DIR="$M14" G3_SHA="$TSHA" PATH="$G3/bin:$PATH" env -u CLAUDE_PLUGIN_ROOT -u GROK_PLUGIN_ROOT \
    "$TIMEOUT_BIN" 30 bash "$M14/block.sh" > "$M14/out" 2> "$M14/err" )
if grep -qx 'decoy-ran' "$M14/decoy.log"; then pass "M14-premigration-block-runs-decoy"
else fail "M14-premigration-block-runs-decoy: decoy did not run — M13's empty ledger proves nothing"; fi
# M15/M16: a root that EXISTS and carries plugin.json is still refused when it is relative or
# sits inside the current checkout — the "repair" an agent reaches for after exit 5 (security
# review of #8727). The gate stub at that root must not run.
refused_root() { # <id> <cwd> <root-value>
  CASES_RUN=$((CASES_RUN + 1))
  local d="$G3/run-$1"; assert_fixture_dir "$d"; rm -rf "$d"; mkdir -p "$d"
  : > "$d/gh.log"; : > "$d/ready.log"
  sed -e 's/<N>/4242/g' -e "s|^SHA=<the 40-hex head SHA.*|SHA=$TSHA|" "$BLOCK_SRC" > "$d/block.sh"
  ( cd "$2" && G3_DIR="$d" G3_SHA="$TSHA" CLAUDE_PLUGIN_ROOT="$3" PATH="$G3/bin:$PATH" \
      "$TIMEOUT_BIN" 30 bash "$d/block.sh" > "$d/out" 2> "$d/err" )
  local rc=$?
  if [[ "$rc" -eq 5 ]] && grep -qxF "$REFUSED_MSG" "$d/out" && [[ ! -s "$d/gh.log" && ! -s "$d/ready.log" ]]; then pass "$1"
  else fail "$1: rc=$rc out=$(tr '\n' '|' < "$d/out") gh=$(tr '\n' '|' < "$d/gh.log") ready=$(tr '\n' '|' < "$d/ready.log")"; fi
}
CHK="$G3/checkout"; assert_fixture_dir "$CHK"; rm -rf "$CHK"; mkdir -p "$CHK/plugins"
( source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh" && git_fixture_env "$CHK" || exit 1; git init -q "$CHK" ) || { echo "[FATAL] M15: git init failed" >&2; exit 1; }
cp -R "$G3/root" "$CHK/plugins/soleur"
[[ -x "$CHK/plugins/soleur/scripts/admin-merge-ready.sh" && -r "$CHK/plugins/soleur/.claude-plugin/plugin.json" ]] \
  || { echo "[FATAL] M15: fixture root copy incomplete" >&2; exit 1; }
refused_root M15-root-inside-checkout-refused "$CHK" "$CHK/plugins/soleur"
refused_root M16-relative-root-refused "$G3" "root"
# Twin control for M15: the SAME root copy, run from outside that checkout, is accepted and
# its gate runs — so M15's refusal is the checkout test, not a broken copy.
CASES_RUN=$((CASES_RUN + 1))
M15C="$G3/run-M15c"; assert_fixture_dir "$M15C"; rm -rf "$M15C"; mkdir -p "$M15C"
: > "$M15C/gh.log"; : > "$M15C/ready.log"; printf 'ok\n' > "$M15C/merge_modes"; printf 'OPEN %s\nMERGED %s\n' "$TSHA" "$TSHA" > "$M15C/states"
sed -e 's/<N>/4242/g' -e "s|^SHA=<the 40-hex head SHA.*|SHA=$TSHA|" "$BLOCK_SRC" > "$M15C/block.sh"
( cd "$G3" && G3_DIR="$M15C" G3_SHA="$TSHA" CLAUDE_PLUGIN_ROOT="$CHK/plugins/soleur" PATH="$G3/bin:$PATH" \
    "$TIMEOUT_BIN" 30 bash "$M15C/block.sh" > "$M15C/out" 2> "$M15C/err" )
if [[ -s "$M15C/ready.log" ]] && ! grep -qxF "$REFUSED_MSG" "$M15C/out"; then pass "M15c-same-root-outside-checkout-runs-gate"
else fail "M15c-same-root-outside-checkout-runs-gate: out=$(tr '\n' '|' < "$M15C/out")"; fi
# M7: a reference whose merge block cannot be found must not extract (no vacuous pass).
CASES_RUN=$((CASES_RUN + 1))
m7="$SANDBOX/m7.md"; cp "$REPO_ROOT/$REF_REL" "$m7"; edit "$m7" '```bash
   _top=$(git rev-parse --show-toplevel 2>/dev/null); [[ "${CLAUDE_PLUGIN_ROOT}" == /* && -r "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" && ( -z "$_top" || "$(realpath "${CLAUDE_PLUGIN_ROOT}")/" != "$_top/"* ) ]] || { echo "ADMIN-MERGE ABORTED: plugin root unresolved or inside this checkout"; exit 5; }
   SHA=<the 40-hex' '```sh
   _top=$(git rev-parse --show-toplevel 2>/dev/null); [[ "${CLAUDE_PLUGIN_ROOT}" == /* && -r "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" && ( -z "$_top" || "$(realpath "${CLAUDE_PLUGIN_ROOT}")/" != "$_top/"* ) ]] || { echo "ADMIN-MERGE ABORTED: plugin root unresolved or inside this checkout"; exit 5; }
   SHA=<the 40-hex'
if extract "$m7" >/dev/null; then fail "M7 (extraction succeeded on a reference with no merge block)"; else pass "M7"; fi

echo
echo "cases_run=$CASES_RUN passes=$passes fails=$fails ledger=${#FAILED[@]}"
_min_cases=39
if [[ "$CASES_RUN" -lt "$_min_cases" ]]; then
  printf '[FATAL] assertion floor: only %s case(s) ran, floor is %s\n' "$CASES_RUN" "$_min_cases" >&2; exit 1
fi
if [[ $((passes + fails)) -ne "$CASES_RUN" ]]; then
  printf '[FATAL] %s verdicts for %s cases\n' "$((passes + fails))" "$CASES_RUN" >&2; exit 1
fi
if [[ "${#FAILED[@]}" -ne "$fails" ]]; then
  printf '[FATAL] ledger/counter disagree: %s vs %s\n' "${#FAILED[@]}" "$fails" >&2; exit 1
fi
if [[ "${#FAILED[@]}" -ne 0 ]]; then
  printf '[FATAL] %s failing assertion(s):\n' "${#FAILED[@]}" >&2
  printf '  - %s\n' "${FAILED[@]}" >&2; exit 1
fi
echo "admin-merge-ready-wiring: all $passes cases passed"
