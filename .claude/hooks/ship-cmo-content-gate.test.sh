#!/usr/bin/env bash
# Unit tests for ship-cmo-content-gate.sh.

set -euo pipefail

. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/ship-cmo-content-gate.sh"

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Mock gh
BINDIR="$TMPDIR/bin"
mkdir -p "$BINDIR"
cat > "$BINDIR/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"pr view 123 --json title --jq .title"* ]]; then
  echo "${MOCK_PR_TITLE:-feat: add shiny thing}"
elif [[ "$*" == *"pr view 123 --json headRefName --jq .headRefName"* ]]; then
  echo "${MOCK_PR_HEAD:-feat-branch}"
elif [[ "$*" == *"pr view --json number --jq .number"* ]]; then
  echo "123"
else
  echo ""
fi
EOF
chmod +x "$BINDIR/gh"

# Create a dummy git repo in TMPDIR
WORKDIR="$TMPDIR/repo"
mkdir -p "$WORKDIR"
git -C "$WORKDIR" init -q -b main
git -C "$WORKDIR" config user.email "test@example.com"
git -C "$WORKDIR" config user.name "Test User"
touch "$WORKDIR/file.txt"
git -C "$WORKDIR" add file.txt
git -C "$WORKDIR" commit -q -m "initial commit"
git -C "$WORKDIR" checkout -q -b feat-branch

run_hook() {
  local cmd="$1" pr_title="$2" skip_env="${3:-0}" extra_commit_msg="${4:-}"
  if [[ -n "$extra_commit_msg" ]]; then
    git -C "$WORKDIR" commit --allow-empty -q -m "$extra_commit_msg"
  fi
  PATH="$BINDIR:$PATH" MOCK_PR_TITLE="$pr_title" SOLEUR_SKIP_CMO_CONTENT_GATE="$skip_env" \
    bash "$HOOK" <<EOF
{"tool_name": "Bash", "tool_input": {"command": "$cmd"}, "cwd": "$WORKDIR"}
EOF
}

echo "=== Test ship-cmo-content-gate.sh ==="

# 1. Irrelevant command -> exit 0 / empty
res=$(run_hook "git status" "feat: something")
assert_eq "non-merge command passes silently" "" "$res"

# 2. Fix PR -> passes silently
res=$(run_hook "gh pr merge 123 --squash" "fix: a bug")
assert_eq "fix PR passes silently" "" "$res"

# 3. Feat PR without CMO disposition -> deny
res=$(run_hook "gh pr merge 123 --squash --auto" "feat: new capability")
decision=$(echo "$res" | jq -r .decision 2>/dev/null || echo "")
assert_eq "feat PR without CMO disposition is denied" "deny" "$decision"

# 4. Feat PR with SOLEUR_SKIP_CMO_CONTENT_GATE=1 -> pass
res=$(run_hook "gh pr merge 123 --squash --auto" "feat: new capability" "1")
assert_eq "feat PR with skip override passes" "" "$res"

# 5. Compound call: a `gh pr merge <M>` mention inside a quoted --body BEFORE
#    the real `gh pr ready <N>` must not hijack PR_NUM — the deny has to land
#    on N (#11795).
res=$(run_hook "gh pr edit 123 --body 'note: gh pr merge 999' && gh pr ready 123" "feat: new capability")
decision=$(echo "$res" | jq -r .decision 2>/dev/null || echo "")
assert_eq "quoted merge-body before real ready is still denied" "deny" "$decision"
assert_eq "quoted merge-body before real ready denies the real PR" "PR #123" "$(echo "$res" | jq -r .reason 2>/dev/null | grep -oE 'PR #[0-9]+' | head -1)"

# 6. Same shape with the quoted mention AFTER the real invocation.
res=$(run_hook "gh pr ready 123 && gh pr edit 123 --body 'note: gh pr merge 999'" "feat: new capability")
decision=$(echo "$res" | jq -r .decision 2>/dev/null || echo "")
assert_eq "quoted merge-body after real ready is still denied" "deny" "$decision"
assert_eq "quoted merge-body after real ready denies the real PR" "PR #123" "$(echo "$res" | jq -r .reason 2>/dev/null | grep -oE 'PR #[0-9]+' | head -1)"

# 7. Feat PR with trailer -> pass
res=$(run_hook "gh pr merge 123 --squash --auto" "feat: new capability" "0" "$(printf 'cmo: review\n\nReviewed-By-CMO: skip (internal only)')")
assert_eq "feat PR with Reviewed-By-CMO trailer passes" "" "$res"

# 8. Session rooted at the main checkout: HEAD==main, the trailer lives only on
#    the PR head ref (#11682). Pin origin/feat-branch at the feat tip first.
git -C "$WORKDIR" update-ref refs/remotes/origin/feat-branch "$(git -C "$WORKDIR" rev-parse feat-branch)"
git -C "$WORKDIR" checkout -q main
res=$(run_hook "gh pr merge 123 --squash --auto" "feat: new capability")
assert_eq "main-checkout session sees trailer on origin/<headRef>" "" "$res"

# 9. Same fixture but the PR head predates the trailer commit -> still deny
git -C "$WORKDIR" update-ref refs/remotes/origin/feat-branch "$(git -C "$WORKDIR" rev-parse feat-branch^)"
res=$(run_hook "gh pr merge 123 --squash --auto" "feat: new capability")
decision=$(echo "$res" | jq -r .decision 2>/dev/null || echo "")
assert_eq "main-checkout session still denies without the trailer" "deny" "$decision"
git -C "$WORKDIR" checkout -q feat-branch
git -C "$WORKDIR" update-ref -d refs/remotes/origin/feat-branch

# 10. Deleted head branch: no origin/<headRef>, no local pull ref — the lazy
#    pull/N/head fetch still reaches the trailer (#11682 fallback arm).
git init -q --bare "$TMPDIR/origin.git"
git -C "$WORKDIR" push -q "$TMPDIR/origin.git" "feat-branch:refs/pull/123/head"
git -C "$WORKDIR" remote add origin "$TMPDIR/origin.git"
git -C "$WORKDIR" checkout -q main
res=$(run_hook "gh pr merge 123 --squash --auto" "feat: new capability")
assert_eq "main-checkout session sees trailer via pull/N/head fetch" "" "$res"
git -C "$WORKDIR" checkout -q feat-branch

# --- 11-14. Changed-path reader (#12332): the marketing-surface diff is read NUL-delimited and rename-free.
#    Fixtures carry NO Reviewed-By-CMO trailer, so only the diff arm can let a PR through.
# make_gate_repo <dir> <mutating-shell-snippet>: main with a marketing file + an unrelated file, then a feat
# branch with the snippet applied and committed. No `origin` remote, so BASE_REF=main and TIP=HEAD.
# Canonical fixture-dir guard (byte-identical to plugins/soleur/test/test-helpers.sh); the relative-path
# ratchet recognises only this executed statement before a write into a fixture root.
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
make_gate_repo() {
  local dir="$1" snippet="$2"
  assert_fixture_dir "$dir"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test User"
  mkdir -p "$dir/knowledge-base/marketing" "$dir/docs"
  printf 'old\n' > "$dir/knowledge-base/marketing/old-plan.md"
  printf 'x\n' > "$dir/docs/keep.md"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "initial commit"
  git -C "$dir" checkout -q -b feat-branch
  ( cd "$dir" && bash -c "$snippet" )
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "branch change"
}
run_hook_in() { # <dir> <pr-title>
  local dir="$1" pr_title="$2"
  PATH="$BINDIR:$PATH" MOCK_PR_TITLE="$pr_title" SOLEUR_SKIP_CMO_CONTENT_GATE=0 \
    bash "$HOOK" <<EOF
{"tool_name": "Bash", "tool_input": {"command": "gh pr merge 123 --squash --auto"}, "cwd": "$dir"}
EOF
}
decision_of() { echo "$1" | jq -r '.decision // empty' 2>/dev/null || echo ""; }

# 11. Control OUTSIDE the surface: a branch that only touches docs/ is denied.
make_gate_repo "$TMPDIR/g-ctl" "printf 'y\\n' >> docs/keep.md"
res=$(run_hook_in "$TMPDIR/g-ctl" "feat: new capability")
assert_eq "control: a diff outside the marketing surface is denied" "deny" "$(decision_of "$res")"

# 12. A non-ASCII marketing path (git C-quotes it, so a ^-anchored regex over the plain list misses it).
make_gate_repo "$TMPDIR/g-utf8" "printf 'n\\n' > \$'knowledge-base/marketing/caf\\xc3\\xa9-plan.md'"
precond=$(git -C "$TMPDIR/g-utf8" diff --name-only main...HEAD)
assert_eq "precondition: the plain name-only list C-quotes the non-ASCII marketing path" "1" "$([[ "$precond" == '"'* ]] && echo 1 || echo 0)"
res=$(run_hook_in "$TMPDIR/g-utf8" "feat: new capability")
assert_eq "a non-ASCII marketing path counts as a marketing change (passes)" "" "$res"

# 13. A quote-and-backslash marketing path (core.quotePath=false would not unquote these).
make_gate_repo "$TMPDIR/g-quote" "printf 'n\\n' > \$'knowledge-base/marketing/q\"uote\\\\slash.md'"
precond=$(git -C "$TMPDIR/g-quote" diff --name-only main...HEAD)
assert_eq "precondition: the plain list C-quotes a quote-and-backslash marketing path" "1" "$([[ "$precond" == '"'* ]] && echo 1 || echo 0)"
res=$(run_hook_in "$TMPDIR/g-quote" "feat: new capability")
assert_eq "a quote-and-backslash marketing path counts as a marketing change (passes)" "" "$res"

# 14. Rename AWAY from the marketing surface: the OLD path is the marketing path (default rename detection lists only the new one).
make_gate_repo "$TMPDIR/g-rename" "git mv knowledge-base/marketing/old-plan.md docs/old-plan.md"
res=$(run_hook_in "$TMPDIR/g-rename" "feat: new capability")
assert_eq "a rename away from knowledge-base/marketing/ counts as a marketing change (passes)" "" "$res"

# 15. A gitlink (submodule pointer) under the marketing surface that configuration hides: a committed `ignore = all`
#    in .gitmodules plus a local diff.ignoreSubmodules=all. Without --ignore-submodules=none the diff omits the
#    gitlink, the marketing list is empty and the gate wrongly denies.
make_gate_repo "$TMPDIR/g-gitlink" "printf '[submodule \"sm\"]\\n\\tpath = knowledge-base/marketing/sm\\n\\turl = https://example.invalid/sm.git\\n\\tignore = all\\n' > .gitmodules; mkdir -p knowledge-base/marketing/sm; git update-index --add --cacheinfo 160000,\$(git rev-parse HEAD),knowledge-base/marketing/sm; git config diff.ignoreSubmodules all"
precond=$(git -C "$TMPDIR/g-gitlink" diff --name-only main...HEAD)
assert_eq "precondition: the config-hidden plain diff omits the marketing gitlink" "0" "$(printf '%s\n' "$precond" | grep -Fxc 'knowledge-base/marketing/sm' || true)"
res=$(run_hook_in "$TMPDIR/g-gitlink" "feat: new capability")
assert_eq "a config-hidden gitlink under knowledge-base/marketing/ counts as a marketing change (passes)" "" "$res"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
