#!/usr/bin/env bash

# Tests for worktree-manager.sh install_deps() bounded/skippable install
# contract (#9269).
#
# The defect: install_deps() ran `bun install`/`npm ci`/`yarn install` with no
# timeout and no opt-out. On a host whose egress policy denies the package
# registry (the Devin cloud sandbox denied registry.npmjs.org:443), the package
# manager retried ~100 times until the caller had to kill it — a pipeline halt
# that looked like a stall, with no diagnostic naming the cause.
#
# The contract under test:
#   - --no-install / SOLEUR_WORKTREE_SKIP_INSTALL=1 skips every install arm and
#     emits SOLEUR_WORKTREE_INSTALL_SKIPPED reason=opt-out (stdout marker).
#   - An unreachable registry host emits reason=registry-unreachable host=<h>
#     per arm and the arm's install command never runs (bounded curl preflight,
#     no retry loop).
#   - A stalled install is killed by the timeout wrap and reported as
#     reason=timeout (rc 124/137 accepted).
#   - Warn-and-continue is preserved: create/feature exit 0 with the worktree
#     on disk in every skip arm.
#
# M7a TOKEN CONSTRAINT (load-bearing): see worktree-manager-hook-deps.test.sh —
# never spell the hook binary name or the node_modules/.bin/<name> path as a
# literal; assertions target the neutral markers only.
#
# Fixtures synthesized per cq-test-fixtures-synthesized-only.
# Run: bash plugins/soleur/test/worktree-manager-install-bounded.test.sh

set -euo pipefail

# Clear ALL git env vars that leak when this test runs inside a git hook/worktree.
while IFS= read -r var; do
  unset "$var" 2>/dev/null || true
done < <(env | grep -oP '^GIT_\w+' || true)

# Keep warns on stderr — headless_or_stderr diverts to a per-PID log file when
# CLAUDECODE is set and fd 2 is not a TTY, which is exactly the CI shape.
unset CLAUDECODE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Sibling suite convention: /tmp is a machine-global 4 GiB tmpfs shared by
# parallel worktrees, and a fixture that cannot be built yields a CONFIDENT
# WRONG verdict rather than a missing one.
export TMPDIR="${TMPDIR:-/var/tmp}"

TEST_DIR=$(mktemp -d)

# #8659 pattern: the incident sandbox must live inside THIS suite's tmpdir and
# be exported BEFORE test-helpers.sh is sourced, so the suite's own
# `trap rm -rf EXIT` below removes it and never replaces the helpers' composed
# cleanup trap.
export INCIDENTS_REPO_ROOT="$TEST_DIR/incidents"
mkdir -p "$INCIDENTS_REPO_ROOT/.claude"

source "$SCRIPT_DIR/test-helpers.sh"
SCRIPT="$SCRIPT_DIR/../skills/git-worktree/scripts/worktree-manager.sh"

# Isolate fixtures from the operator's git config (commit.gpgsign et al. break
# fixture commits; a failed fixture reads as a real SUT failure).
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

echo "=== worktree-manager.sh install_deps bounded/skippable contract (#9269) ==="
echo ""

assert_fixture_dir "$TEST_DIR"
trap 'rm -rf "$TEST_DIR"' EXIT

git_fixture_env "$TEST_DIR" || {
  printf 'FATAL: git_fixture_env refused to build an environment for %s\n' "$TEST_DIR" >&2
  exit 2
}

# Keep lease/lock state inside the sandbox.
export SOLEUR_SESSION_STATE_ROOT="$TEST_DIR/session-state"

# A fixture repo on `main` carrying package.json + package-lock.json at the
# root (routes install_deps to the npm arm) plus apps/demo/ with its own
# lockfile (routes the apps/* loop to a second npm arm).
new_repo() {
  local name="$1"
  local repo="$TEST_DIR/$name"
  assert_fixture_dir "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.email "test@test.local"
  git -C "$repo" config user.name "Test"
  printf '{"name":"fixture","private":true}\n' > "$repo/package.json"
  printf '{"name":"fixture","lockfileVersion":3,"packages":{}}\n' \
    > "$repo/package-lock.json"
  mkdir -p "$repo/apps/demo"
  printf '{"name":"demo","private":true}\n' > "$repo/apps/demo/package.json"
  printf '{"name":"demo","lockfileVersion":3,"packages":{}}\n' \
    > "$repo/apps/demo/package-lock.json"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "seed"
  printf '%s' "$repo"
}

# npm stub. Handles the registry-config probe (`npm --prefix <dir> config get
# registry` -> the URL the host resolver expects), logs every other invocation
# to $STUB_CMD_LOG so arms can assert "npm ci never ran", and sleeps when
# STUB_CMD_SLEEP is set (timeout arm).
make_npm_stub() {
  local dir="$1"
  assert_fixture_dir "$dir"
  mkdir -p "$dir"
  cat > "$dir/npm" <<'EOF'
#!/usr/bin/env bash
# Registry-config probe: the SUT resolves the host it will install from via
# `npm --prefix <dir> config get registry`. Answer it without logging — the
# probe is preflight, not an install.
for ((i=1; i<=$#; i++)); do
  if [[ "${!i}" == "config" ]]; then
    printf 'https://registry.npmjs.org/\n'
    exit 0
  fi
done
printf '%s\n' "$*" >> "${STUB_CMD_LOG:?}"
if [[ -n "${STUB_CMD_SLEEP:-}" ]]; then
  sleep "$STUB_CMD_SLEEP"
fi
exit "${STUB_CMD_RC:-0}"
EOF
  chmod +x "$dir/npm"
}

# curl stub — the SUT's reachability preflight. CURL_STUB_RC decides the
# probe's verdict; every call is logged so arms can bound the probe count.
make_curl_stub() {
  local dir="$1"
  assert_fixture_dir "$dir"
  mkdir -p "$dir"
  cat > "$dir/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CURL_STUB_LOG:?}"
exit "${CURL_STUB_RC:-0}"
EOF
  chmod +x "$dir/curl"
}

# Drive the real subcommand with a controlled PATH and env. stdout/stderr go to
# SEPARATE files so each arm can assert which stream carried the line (markers
# are stdout; human warns are stderr).
run_wt() {
  local tag="$1" stub_dir="$2" rc=0
  shift 2
  ( cd "$REPO" && PATH="$stub_dir:$PATH" STUB_CMD_LOG="$TEST_DIR/stub-$tag.log" \
      CURL_STUB_LOG="$TEST_DIR/curl-$tag.log" \
      env "$@" ) >"$TEST_DIR/$tag.out" 2>"$TEST_DIR/$tag.err" || rc=$?
  printf '%s' "$rc"
}

stub_ci_count() {
  local tag="$1"
  if [[ -f "$TEST_DIR/stub-$tag.log" ]]; then
    grep -c 'ci --ignore-scripts' "$TEST_DIR/stub-$tag.log" || true
  else
    echo 0
  fi
}

# ---------------------------------------------------------------------------
# B1 — SOLEUR_WORKTREE_SKIP_INSTALL=1: every arm skipped, opt-out marker, rc 0.
# ---------------------------------------------------------------------------
echo "B1: env-var opt-out skips all install arms"
REPO=$(new_repo repo-b1)
STUB_B1="$TEST_DIR/stub-b1"; make_npm_stub "$STUB_B1"; make_curl_stub "$STUB_B1"
RC=$(run_wt b1 "$STUB_B1" SOLEUR_WORKTREE_SKIP_INSTALL=1 bash "$SCRIPT" --yes create feat-b1 main)
OUT="$(cat "$TEST_DIR/b1.out")"; ERR="$(cat "$TEST_DIR/b1.err")"
assert_eq "0" "$RC" "create exits 0 under opt-out (log: $TEST_DIR/b1.err)"
assert_contains "$OUT" "SOLEUR_WORKTREE_INSTALL_SKIPPED reason=opt-out" \
  "stdout carries the opt-out marker"
assert_eq "0" "$(stub_ci_count b1)" "the install never invoked under opt-out"
assert_eq "0" "$([[ -f "$TEST_DIR/curl-b1.log" ]] && wc -l < "$TEST_DIR/curl-b1.log" || echo 0)" \
  "registry probe never ran under opt-out"
assert_eq "true" "$([[ -d "$REPO/.worktrees/feat-b1" ]] && echo true || echo false)" \
  "worktree still created under opt-out"
assert_contains "$ERR" "hook dep missing" "hook-dep enumeration still reports state under opt-out"
echo ""

# ---------------------------------------------------------------------------
# B2 — --no-install flag: same gate, CLI surface.
# ---------------------------------------------------------------------------
echo "B2: --no-install flag skips all install arms"
REPO=$(new_repo repo-b2)
STUB_B2="$TEST_DIR/stub-b2"; make_npm_stub "$STUB_B2"; make_curl_stub "$STUB_B2"
RC=$(run_wt b2 "$STUB_B2" bash "$SCRIPT" --yes --no-install create feat-b2 main)
OUT="$(cat "$TEST_DIR/b2.out")"
assert_eq "0" "$RC" "create exits 0 under --no-install (log: $TEST_DIR/b2.err)"
assert_contains "$OUT" "SOLEUR_WORKTREE_INSTALL_SKIPPED reason=opt-out" \
  "flag feeds the same opt-out gate"
assert_eq "0" "$(stub_ci_count b2)" "the install never invoked under --no-install"
assert_eq "true" "$([[ -d "$REPO/.worktrees/feat-b2" ]] && echo true || echo false)" \
  "worktree still created under --no-install"
echo ""

# ---------------------------------------------------------------------------
# B3 — unreachable registry: probe fails fast, arm skipped, host named.
# ---------------------------------------------------------------------------
echo "B3: denied registry skips install arms and names the host"
REPO=$(new_repo repo-b3)
STUB_B3="$TEST_DIR/stub-b3"; make_npm_stub "$STUB_B3"; make_curl_stub "$STUB_B3"
RC=$(run_wt b3 "$STUB_B3" CURL_STUB_RC=7 bash "$SCRIPT" --yes create feat-b3 main)
OUT="$(cat "$TEST_DIR/b3.out")"; ERR="$(cat "$TEST_DIR/b3.err")"
assert_eq "0" "$RC" "create exits 0 with unreachable registry (log: $TEST_DIR/b3.err)"
assert_contains "$OUT" "SOLEUR_WORKTREE_INSTALL_SKIPPED reason=registry-unreachable" \
  "stdout carries the registry-unreachable marker"
assert_contains "$OUT" "host=registry.npmjs.org" "the marker names the blocked host"
assert_eq "2" "$(grep -c 'SOLEUR_WORKTREE_INSTALL_SKIPPED reason=registry-unreachable' <<< "$OUT")" \
  "both arms (root + apps/demo) report the skip"
assert_eq "0" "$(stub_ci_count b3)" "the install never invoked when its registry is unreachable"
assert_eq "1" "$(wc -l < "$TEST_DIR/curl-b3.log" | tr -d ' ')" \
  "probe memoized: two npm arms share one curl probe"
assert_contains "$(cat "$TEST_DIR/curl-b3.log")" "--max-time" \
  "the probe carries its bound flags (a bare curl would reintroduce the stall)"
assert_eq "false" "$([[ "$OUT" == *"Installing dependencies"* ]] && echo true || echo false)" \
  "skipped arms never emit a started-then-skipped banner pair"
assert_contains "$ERR" "registry.npmjs.org" "stderr warn names the blocked host"
assert_eq "true" "$([[ -d "$REPO/.worktrees/feat-b3" ]] && echo true || echo false)" \
  "worktree still created with unreachable registry"
echo ""

# ---------------------------------------------------------------------------
# B4 — stalled install: the timeout wrap bounds it and reports reason=timeout.
# ---------------------------------------------------------------------------
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  echo "B4: stalled install is bounded and reported as timeout"
  REPO=$(new_repo repo-b4)
  STUB_B4="$TEST_DIR/stub-b4"; make_npm_stub "$STUB_B4"; make_curl_stub "$STUB_B4"
  START=$SECONDS
  RC=$(run_wt b4 "$STUB_B4" STUB_CMD_SLEEP=60 SOLEUR_WORKTREE_INSTALL_TIMEOUT_SECS=2 \
       bash "$SCRIPT" --yes create feat-b4 main)
  ELAPSED=$((SECONDS - START))
  OUT="$(cat "$TEST_DIR/b4.out")"; ERR="$(cat "$TEST_DIR/b4.err")"
  assert_eq "0" "$RC" "create exits 0 when installs time out (log: $TEST_DIR/b4.err)"
  assert_eq "true" "$([[ "$ELAPSED" -lt 40 ]] && echo true || echo false)" \
    "two 60s installs bounded by a 2s timeout finished in ${ELAPSED}s (<40s ceiling)"
  assert_contains "$OUT" "SOLEUR_WORKTREE_INSTALL_SKIPPED reason=timeout" \
    "stdout carries the timeout marker"
  assert_eq "2" "$(grep -c 'SOLEUR_WORKTREE_INSTALL_SKIPPED reason=timeout' <<< "$OUT")" \
    "both timed-out arms report (not one collapsed marker)"
  assert_eq "true" "$([[ -d "$REPO/.worktrees/feat-b4" ]] && echo true || echo false)" \
    "worktree still created when installs time out"
  echo ""
else
  echo "B4: SKIPPED — no timeout/gtimeout binary on this host (the unbounded"
  echo "    fallback arm is the documented no-boundary case)"
  SKIPPED=$((SKIPPED + 1))
  echo ""
fi

# ---------------------------------------------------------------------------
# B5 — SOLEUR_WORKTREE_SKIP_INSTALL=0 (set, non-1): gate is =="1", not "set".
# ---------------------------------------------------------------------------
echo "B5: SOLEUR_WORKTREE_SKIP_INSTALL=0 still installs"
REPO=$(new_repo repo-b5)
STUB_B5="$TEST_DIR/stub-b5"; make_npm_stub "$STUB_B5"; make_curl_stub "$STUB_B5"
RC=$(run_wt b5 "$STUB_B5" SOLEUR_WORKTREE_SKIP_INSTALL=0 bash "$SCRIPT" --yes create feat-b5 main)
OUT="$(cat "$TEST_DIR/b5.out")"
assert_eq "0" "$RC" "create exits 0 (log: $TEST_DIR/b5.err)"
assert_eq "2" "$(stub_ci_count b5)" "the install ran for root + apps/demo"
assert_contains "$OUT" "Dependencies installed" "happy path unaffected by a non-1 env value"
assert_eq "false" "$([[ "$OUT" == *"reason=opt-out"* ]] && echo true || echo false)" \
  "no opt-out marker for a non-1 env value"
echo ""

# ---------------------------------------------------------------------------
# B6 — `feature` subcommand: opt-out covers the second call site behaviorally.
# ---------------------------------------------------------------------------
echo "B6: feature <name> honours the opt-out"
REPO=$(new_repo repo-b6)
STUB_B6="$TEST_DIR/stub-b6"; make_npm_stub "$STUB_B6"; make_curl_stub "$STUB_B6"
RC=$(run_wt b6 "$STUB_B6" SOLEUR_WORKTREE_SKIP_INSTALL=1 bash "$SCRIPT" --yes feature b6-widget main)
OUT="$(cat "$TEST_DIR/b6.out")"
assert_eq "0" "$RC" "feature exits 0 under opt-out (log: $TEST_DIR/b6.err)"
assert_contains "$OUT" "SOLEUR_WORKTREE_INSTALL_SKIPPED reason=opt-out" \
  "feature path emits the opt-out marker"
assert_eq "0" "$(stub_ci_count b6)" "the install never invoked on the feature path"
assert_eq "true" "$([[ -d "$REPO/.worktrees/feat-b6-widget" ]] && echo true || echo false)" \
  "feature worktree created under opt-out"
echo ""

# ---------------------------------------------------------------------------
# B7 — happy path: reachable registry, working npm, no opt-out. Unchanged
#      output strings (the sibling hook-deps suite asserts on them).
# ---------------------------------------------------------------------------
echo "B7: reachable registry happy path is unchanged"
REPO=$(new_repo repo-b7)
STUB_B7="$TEST_DIR/stub-b7"; make_npm_stub "$STUB_B7"; make_curl_stub "$STUB_B7"
RC=$(run_wt b7 "$STUB_B7" bash "$SCRIPT" --yes create feat-b7 main)
OUT="$(cat "$TEST_DIR/b7.out")"
assert_eq "0" "$RC" "create exits 0 (log: $TEST_DIR/b7.err)"
assert_eq "2" "$(stub_ci_count b7)" "the install ran for root + apps/demo"
assert_contains "$OUT" "Dependencies installed" "root arm reports success verbatim"
assert_contains "$OUT" "demo dependencies installed" "apps arm reports success verbatim"
assert_eq "false" "$([[ "$OUT" == *"SOLEUR_WORKTREE_INSTALL_SKIPPED"* ]] && echo true || echo false)" \
  "no skip marker on the happy path"
echo ""

# ---------------------------------------------------------------------------
# B8 — bun arm host resolution: a bunfig.toml registry override must drive the
#      probed endpoint (the sed-parser path the npm arm can't exercise).
# ---------------------------------------------------------------------------
echo "B8: bun arm probes the bunfig.toml registry override"
REPO=$(new_repo repo-b8)
# $() binding is untraceable to the fixture scanner — assert the operand
# directly so the redirects below have their guard.
assert_fixture_dir "$REPO"
rm -f "$REPO/package-lock.json" "$REPO/apps/demo/package-lock.json"
printf '{\n  "lockfileVersion": 1\n}\n' > "$REPO/bun.lock"
printf '{\n  "lockfileVersion": 1\n}\n' > "$REPO/apps/demo/bun.lock"
printf '[install]\nregistry = "https://npm.internal.example:4873/mirror"\n' \
  > "$REPO/apps/demo/bunfig.toml"
# worktree add checks out the COMMITTED tree — the lockfile swap must land in a
# commit or install_deps sees the seeded package-lock.json files instead.
git -C "$REPO" add -A && git -C "$REPO" commit -q -m "bun-lockfile fixture"
STUB_B8="$TEST_DIR/stub-b8"; make_curl_stub "$STUB_B8"
cat > "$STUB_B8/bun" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_CMD_LOG:?}"
exit 0
EOF
chmod +x "$STUB_B8/bun"
RC=$(run_wt b8 "$STUB_B8" bash "$SCRIPT" --yes create feat-b8 main)
OUT="$(cat "$TEST_DIR/b8.out")"
CURL_LOG="$(cat "$TEST_DIR/curl-b8.log")"
assert_eq "0" "$RC" "create exits 0 on the bun path (log: $TEST_DIR/b8.err)"
assert_contains "$CURL_LOG" "https://registry.npmjs.org/" \
  "root arm probes the default npm registry (no bunfig at root)"
assert_contains "$CURL_LOG" "https://npm.internal.example:4873/" \
  "apps/demo arm probes the bunfig.toml registry override, port preserved"
assert_eq "2" "$(grep -c 'install --frozen-lockfile --cwd' "$TEST_DIR/stub-b8.log")" \
  "bun install ran for root + apps/demo"
assert_contains "$OUT" "demo dependencies installed" "bun app arm reports success"
echo ""

# ---------------------------------------------------------------------------
# B9 — ordinary install failure: warn-and-continue plus a reason=failed marker
#      (an every-arm-failed run must not be stdout-indistinguishable from a
#      healthy install).
# ---------------------------------------------------------------------------
echo "B9: ordinary install failure is marked and non-fatal"
REPO=$(new_repo repo-b9)
STUB_B9="$TEST_DIR/stub-b9"; make_npm_stub "$STUB_B9"; make_curl_stub "$STUB_B9"
RC=$(run_wt b9 "$STUB_B9" STUB_CMD_RC=3 bash "$SCRIPT" --yes create feat-b9 main)
OUT="$(cat "$TEST_DIR/b9.out")"; ERR="$(cat "$TEST_DIR/b9.err")"
assert_eq "0" "$RC" "create exits 0 when installs fail (log: $TEST_DIR/b9.err)"
assert_eq "2" "$(stub_ci_count b9)" "the install ran for root + apps/demo"
assert_eq "2" "$(grep -c 'SOLEUR_WORKTREE_INSTALL_SKIPPED reason=failed' <<< "$OUT")" \
  "each failed arm emits reason=failed on stdout"
assert_contains "$ERR" "install failed" "the pre-existing warn path is preserved"
assert_eq "false" "$([[ "$OUT" == *"Dependencies installed"* ]] && echo true || echo false)" \
  "no false success report"
assert_eq "true" "$([[ -d "$REPO/.worktrees/feat-b9" ]] && echo true || echo false)" \
  "worktree still created when installs fail"
echo ""

print_results 43
