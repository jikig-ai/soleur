#!/usr/bin/env bash

# Tests for worktree-manager.sh install_deps() hook-required binary
# enumeration (#8580).
#
# The defect: every install failure arm in install_deps() warns and CONTINUES,
# so `create` could report a worktree "created" while the pinned binaries the
# pre-commit hooks resolve from the worktree's own node_modules/.bin were never
# installed — and the first docs commit then hard-fails. The enumeration at the
# end of install_deps() prints a per-binary status line unconditionally: a
# check marker when the binary is executable, else a Warning to stderr naming
# the recovery command.
#
#   A1  lockfile-less repo  -> install skipped -> missing-binary Warning (stderr)
#   A2  PATH-stubbed npm fabricates the binary -> present marker (stdout)
#
# M7a TOKEN CONSTRAINT (load-bearing): this file is inside the
# markdown-lint.test.sh single-invoker scan set (every *.sh under plugins/),
# which greps comment-stripped source for the literal binary token, the literal
# .bin/<name> path, a package-runner prefix, or command-position usage. So the
# binary is named ONCE here, as a bare array member, and every .bin path —
# including inside the PATH stub's heredoc, which that scan does NOT skip — is
# composed from $HOOK_BIN. Assertions target the neutral markers (`hook dep`,
# `missing`, `npm ci --ignore-scripts`, the check glyph), never the literal
# binary path.
#
# Fixtures synthesized per cq-test-fixtures-synthesized-only.
# Run: bash plugins/soleur/test/worktree-manager-hook-deps.test.sh

set -euo pipefail

# Clear ALL git env vars that leak when this test runs inside a git hook/worktree.
while IFS= read -r var; do
  unset "$var" 2>/dev/null || true
done < <(env | grep -oP '^GIT_\w+' || true)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SCRIPT="$SCRIPT_DIR/../skills/git-worktree/scripts/worktree-manager.sh"

# Sibling suite convention: /tmp is a machine-global 4 GiB tmpfs shared by
# parallel worktrees, and a fixture that cannot be built yields a CONFIDENT
# WRONG verdict rather than a missing one.
export TMPDIR="${TMPDIR:-/var/tmp}"

# Isolate fixtures from the operator's git config (commit.gpgsign et al. break
# fixture commits; a failed fixture reads as a real SUT failure).
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

echo "=== worktree-manager.sh install_deps hook-dep enumeration ==="
echo ""

TEST_DIR=$(mktemp -d)
assert_fixture_dir "$TEST_DIR"
trap 'rm -rf "$TEST_DIR"' EXIT

# Keep lease/lock state inside the sandbox: session-state.sh anchors to the
# git-common-dir by default (the fixture's own .git here — already contained),
# and the explicit override is the sanctioned test surface for it.
export SOLEUR_SESSION_STATE_ROOT="$TEST_DIR/session-state"

# The hook-required binary under test — the sole member of the SUT's
# enumeration list today. Bare name ONLY (M7a): every probe path is composed
# as node_modules/.bin/$HOOK_BIN, never spelled as a literal. Exported so the
# npm stub below can read it at runtime.
export HOOK_BIN="markdownlint"

# A minimal fixture repo: `main` carrying package.json, plus package-lock.json
# when $2 asks for it (the lockfile is what routes install_deps to the npm arm).
new_repo() {
  local name="$1" with_lock="${2:-}"
  local repo="$TEST_DIR/$name"
  assert_fixture_dir "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.email "test@test.local"
  git -C "$repo" config user.name "Test"
  printf '{"name":"fixture","private":true}\n' > "$repo/package.json"
  if [[ "$with_lock" == "--with-lockfile" ]]; then
    printf '{"name":"fixture","lockfileVersion":3,"packages":{}}\n' \
      > "$repo/package-lock.json"
  fi
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "seed"
  printf '%s' "$repo"
}

# Drive the real `create` subcommand — the wiring under test is that
# install_deps (and with it the enumeration) runs on the create path.
# Captures stdout and stderr to SEPARATE files so the arm can assert which
# stream carried the line (the Warning contract is stderr; the marker stdout).
run_create() {
  local repo="$1" branch="$2" tag="$3" stub_bin="${4:-}" rc=0
  ( if [[ -n "$stub_bin" ]]; then export PATH="$stub_bin:$PATH"; fi
    cd "$repo" && bash "$SCRIPT" --yes create "$branch" main ) \
    >"$TEST_DIR/$tag.out" 2>"$TEST_DIR/$tag.err" || rc=$?
  printf '%s' "$rc"
}

# ---------------------------------------------------------------------------
# A1 — install skipped (no lockfile) -> the enumeration must WARN, naming the
#      recovery command. This is the warn-and-continue shape #8580 reports:
#      before the enumeration, the only signal was the lockfile warning and the
#      hook binary's absence went undiagnosed until the first docs commit died.
# ---------------------------------------------------------------------------
echo "A1: lockfile-less create prints the missing hook-dep warning"
REPO_A=$(new_repo repo-a)
RC_A=$(run_create "$REPO_A" "feat-hook-deps-a" a1)
OUT_A="$(cat "$TEST_DIR/a1.out")"
ERR_A="$(cat "$TEST_DIR/a1.err")"
assert_eq "0" "$RC_A" "create exits 0 on a lockfile-less repo (warn-and-continue, log: $TEST_DIR/a1.err)"
assert_contains "$ERR_A" "no recognized lockfile" \
  "install really was skipped — the arm's premise, not just any warning"
assert_contains "$ERR_A" "hook dep" "stderr carries the hook-dep status line"
assert_contains "$ERR_A" "missing" "the status is the missing-binary warning"
assert_contains "$ERR_A" "npm ci --ignore-scripts" "the warning names the recovery command"
assert_contains "$ERR_A" "--prefix" "the warning names which tree to install into"
assert_eq "false" "$([[ "$OUT_A" == *"hook dep"* ]] && echo true || echo false)" \
  "stdout carries no hook-dep line when the binary is absent (warning is stderr-only)"
assert_eq "true" "$([[ -d "$REPO_A/.worktrees/feat-hook-deps-a" ]] && echo true || echo false)" \
  "worktree was still created (the warning diagnoses, it does not block)"
echo ""

# ---------------------------------------------------------------------------
# A2 — an npm that actually installs -> the enumeration must print the present
#      marker. A PATH stub fabricates <prefix>/node_modules/.bin/$HOOK_BIN so
#      the -x probe finds it; the stub's heredoc composes the path from the
#      exported name for the same M7a reason as everything else in this file.
# ---------------------------------------------------------------------------
echo "A2: stubbed-npm create prints the present hook-dep marker"
NPM_STUB_DIR="$TEST_DIR/npm-stub"
assert_fixture_dir "$NPM_STUB_DIR"
mkdir -p "$NPM_STUB_DIR"
cat > "$NPM_STUB_DIR/npm" <<'EOF'
#!/usr/bin/env bash
# Stub: `npm ci --ignore-scripts --prefix <dir>` fabricates the hook-required
# binary the enumeration probes for, then reports success.
prefix=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)   prefix="$2"; shift 2 ;;
    --prefix=*) prefix="${1#--prefix=}"; shift ;;
    *)          shift ;;
  esac
done
[[ -n "$prefix" ]] || { echo "npm stub: no --prefix operand" >&2; exit 2; }
bin_dir="$prefix/node_modules/.bin"
mkdir -p "$bin_dir" || exit 2
printf '#!/bin/sh\nexit 0\n' > "$bin_dir/$HOOK_BIN"
chmod +x "$bin_dir/$HOOK_BIN"
exit 0
EOF
chmod +x "$NPM_STUB_DIR/npm"

REPO_B=$(new_repo repo-b --with-lockfile)
RC_B=$(run_create "$REPO_B" "feat-hook-deps-b" a2 "$NPM_STUB_DIR")
OUT_B="$(cat "$TEST_DIR/a2.out")"
ERR_B="$(cat "$TEST_DIR/a2.err")"
WT_B="$REPO_B/.worktrees/feat-hook-deps-b"
assert_eq "0" "$RC_B" "create exits 0 with the stubbed installer (log: $TEST_DIR/a2.err)"
assert_contains "$OUT_B" "Dependencies installed" \
  "the npm install arm ran and reported success (the arm's premise)"
assert_eq "true" "$([[ -x "$WT_B/node_modules/.bin/$HOOK_BIN" ]] && echo true || echo false)" \
  "the stub really fabricated the binary the probe looks for"
assert_contains "$OUT_B" "✓ hook dep present" \
  "stdout carries the present marker for the fabricated binary"
assert_eq "false" "$([[ "$ERR_B" == *"hook dep missing"* ]] && echo true || echo false)" \
  "no missing-binary warning when the install produced the binary"
echo ""

print_results 13
