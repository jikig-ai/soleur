#!/usr/bin/env bash

# Tests for worktree-manager.sh sync_bare_files() full-mirror reconciliation.
# Regression test for bare-root drift: the legacy populated working tree at the
# bare root drifted from HEAD because the old sync archived only a whitelist of
# trees and pruned deletions only under .claude/hooks/. Stale .github workflows
# (deleted in the Inngest migration #4483) and stale knowledge-base content
# (brand-guide drift, learning 2026-05-21) misled later analysis.
#
# The fix mirrors the FULL HEAD tree (checkout-index) and prunes tracked-deleted
# leftovers, gated on the git-history discriminator so untracked runtime artifacts
# are never removed. These tests pin all four behaviors + idempotency.
# Run: bash plugins/soleur/test/worktree-manager-bare-sync.test.sh

set -euo pipefail

# Clear ALL git env vars that leak when this test runs inside a git hook or worktree.
while IFS= read -r var; do
  unset "$var" 2>/dev/null || true
done < <(env | grep -oP '^GIT_\w+' || true)

# ...then re-pin config isolation. These must come AFTER the loop above: the
# loop unsets every GIT_* var, so an override exported by the caller is wiped.
# A host with `commit.gpgsign=true` (+ an ssh agent that declines) fails every
# fixture `git commit` with "failed to write commit object"; `git clone` then
# only warns "you appear to have cloned an empty repository", so the arms go red
# for a missing fixture while reading as genuine SUT failures.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SCRIPT="$SCRIPT_DIR/../skills/git-worktree/scripts/worktree-manager.sh"

echo "=== worktree-manager.sh sync_bare_files() full-mirror ==="
echo ""

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# --- Build a seed repo with two commits so HEAD has an add, a delete, and a change ---
SEED="$TEST_DIR/seed"
git init -q -b main "$SEED"
git -C "$SEED" config user.email "test@test.local"
git -C "$SEED" config user.name "Test"

# commit 1: baseline (old.yml will be deleted later; doc.md will change)
mkdir -p "$SEED/.github/workflows" "$SEED/plugins" "$SEED/knowledge-base/marketing"
printf 'name: old\n' > "$SEED/.github/workflows/old.yml"
printf 'keep me\n'   > "$SEED/plugins/keep.md"
printf 'v1\n'        > "$SEED/knowledge-base/marketing/doc.md"
git -C "$SEED" add .
git -C "$SEED" commit -q -m "commit1: baseline"

# commit 2 (HEAD): delete old.yml, change doc.md -> v2, add new.md
git -C "$SEED" rm -q .github/workflows/old.yml
printf 'v2\n'      > "$SEED/knowledge-base/marketing/doc.md"
printf 'brand new\n' > "$SEED/plugins/new.md"
git -C "$SEED" add .
git -C "$SEED" commit -q -m "commit2: delete old.yml, change doc, add new"

# --- Bare clone whose HEAD == commit2 ---
BARE="$TEST_DIR/bare.git"
git clone -q --bare "$SEED" "$BARE"

# --- Simulate the drifted populated working tree at the bare root (state of commit1) ---
mkdir -p "$BARE/.github/workflows" "$BARE/plugins" "$BARE/knowledge-base/marketing"
printf 'name: old\n' > "$BARE/.github/workflows/old.yml"   # tracked-deleted in HEAD -> must be pruned
printf 'keep me\n'   > "$BARE/plugins/keep.md"
printf 'v1\n'        > "$BARE/knowledge-base/marketing/doc.md"  # stale content -> must refresh to v2
# new.md intentionally absent -> must appear after sync

# Untracked runtime artifacts that were NEVER tracked: the safety boundary.
mkdir -p "$BARE/node_modules/pkg" "$BARE/_site"
printf 'dep\n'        > "$BARE/node_modules/pkg/index.js"
printf '<html>\n'     > "$BARE/_site/index.html"
printf 'SECRET=1\n'   > "$BARE/.env"

cd "$BARE"
bash "$SCRIPT" --yes sync-bare-files > "$TEST_DIR/sync1.log" 2>&1 || {
  echo "  WARN: sync-bare-files exited non-zero:"; sed 's/^/    /' "$TEST_DIR/sync1.log"; }

echo "Test 1: stale tracked-deleted file pruned"
assert_file_not_exists "$BARE/.github/workflows/old.yml" "old.yml removed from bare root"
echo ""

echo "Test 2: stale content refreshed to HEAD"
assert_eq "v2" "$(cat "$BARE/knowledge-base/marketing/doc.md")" "doc.md refreshed v1 -> v2"
echo ""

echo "Test 3: file added in HEAD now present"
assert_file_exists "$BARE/plugins/new.md" "new.md materialized from HEAD"
assert_file_exists "$BARE/plugins/keep.md" "keep.md still present"
echo ""

echo "Test 4: SAFETY BOUNDARY — never-tracked artifacts preserved"
assert_file_exists "$BARE/node_modules/pkg/index.js" "node_modules preserved"
assert_file_exists "$BARE/_site/index.html" "_site build output preserved"
assert_file_exists "$BARE/.env" "untracked .env preserved"
echo ""

echo "Test 5: idempotency — second run leaves the same state"
bash "$SCRIPT" --yes sync-bare-files > "$TEST_DIR/sync2.log" 2>&1 || {
  echo "  WARN: second sync exited non-zero:"; sed 's/^/    /' "$TEST_DIR/sync2.log"; }
assert_file_not_exists "$BARE/.github/workflows/old.yml" "old.yml still absent after 2nd run"
assert_eq "v2" "$(cat "$BARE/knowledge-base/marketing/doc.md")" "doc.md still v2 after 2nd run"
assert_file_exists "$BARE/.env" ".env still preserved after 2nd run"
echo ""

# =====================================================================================
# LOCALE REGRESSION ARMS. The prune step compared two LC_ALL=C-sorted lists with a `comm`
# running in the user's locale: under en_US.UTF-8 `comm` printed "not in sorted order"
# and returned a WRONG difference, so tracked files (incl. .claude-plugin/marketplace.json,
# the on-disk source of the local `soleur` marketplace) were deleted from the bare root.
# Every arm below runs against a FIXTURE bare repo under $TEST_DIR, never the real root.
# =====================================================================================

# Cyrillic "et" (U+0435 U+0442) — the same non-ASCII spelling as the real
# verify-canus<et>ool-caching-876 specs dir, which git quotes unless core.quotePath=false.
NA=$'\xd0\xb5\xd1\x82'

# Calibrated, frozen fixture: ~22 tracked paths + 8 really-deleted ones, chosen by a seeded
# search so the LEGACY pipeline under en_US.UTF-8 prints "not in sorted order" AND emits a
# tracked path (.claude-plugin/marketplace.json). A 5-path fixture does not reproduce the
# bug at all (measured), so do not shrink or regenerate this list; arm F0 proves it bites.
HEAD_PATHS=(
  ".claude-plugin/marketplace.json"
  "knowledge-base/legal/legitimate-interest-assessments/2026-07-07-beta-crm-lia.md"
  "tests/scripts/lib/vector-redeliver-gate.sh"
  "apps/web-platform/supabase/migrations/071_ux_audit_artifacts_bucket.sql"
  "knowledge-base/project/learnings/workflow-patterns/2026-09-18-an-index-exists-claim-is-two-claims-mapping-direction-and-class-membership.md"
  "knowledge-base/engineering/architecture/decisions/ADR-127-review-evidence-trailer-is-a-boolean-not-a-content-attestation.md"
  "plugins/soleur/cursor/skills/soleur-xcode-test/SKILL.md"
  "knowledge-base/project/specs/archive/20261013-041741-feat-one-shot-6357-stale-cloudflared-registry-ingress/decision-challenges.md"
  "knowledge-base/project/specs/archive/20261013-051752-feat-one-shot-zot-migration-completion/session-state.md"
  "knowledge-base/project/specs/archive/20261012-213508-feat-enforce-ux-content-gates/tasks.md"
  "knowledge-base/project/learnings/2026-07-30-a-known-gap-of-seven-was-a-predicate-and-my-battery-mutated-one-axis.md"
  "apps/web-platform/test/sandbox-credential-deny-runtime.test.ts"
  "plugins/soleur/agents/community/.gitkeep"
  "apps/web-platform/infra/cutover-monitor-baseline.txt"
  "knowledge-base/project/specs/archive/20261012-213508-feat-weekly-analytics-improvements/session-state.md"
  "knowledge-base/project/specs/archive/20261013-032858-feat-one-shot-collapse-icon-workspace-selector-align/session-state.md"
  ".claude/hooks/new-scheduled-cron-prefer-inngest.test.sh"
  "knowledge-base/project/specs/archive/20261013-041741-feat-one-shot-4826-nav-rail-position-resume/tasks.md"
  "knowledge-base/project/plans/archive/20260423-131811-2026-04-23-fix-repo-setup-git-clone-creds-plan.md"
  "knowledge-base/project/learnings/best-practices/2026-05-05-workflow-jwt-mint-silent-failure-traps.md"
  "apps/web-platform/test/server/kb-active-workspace-scoping.test.ts"
  "knowledge-base/project/specs/archive/20261012-213508-verify-canus${NA}ool-caching-876/session-state.md"
)
DEL_PATHS=(
  "knowledge-base/project/specs/feat-one-shot-2618-terraform-drift-deploy-pipeline-fix/session-state.md"
  "knowledge-base/brainstorms/archive/20260227-162802-2026-02-27-feature-video-deps-brainstorm.md"
  "knowledge-base/brainstorms/2026-02-06-pull-before-worktree-brainstorm.md"
  "knowledge-base/brainstorms/2026-03-14-linkedin-company-variant-brainstorm.md"
  ".openhands/skills/pricing-strategist/SKILL.md"
  "knowledge-base/project/specs/feat-one-shot-9239-backstop-hook-resolution/tasks.md"
  "knowledge-base/project/plans/2026-06-03-fix-kb-sync-affordance-and-reconcile-self-heal-plan.md"
  "knowledge-base/project/specs/verify-canus${NA}ool-caching-876/session-state.md"
)

# Locale detection into a variable: `locale -a | grep -q` under pipefail can SIGPIPE into a
# false "absent". `locale -a` spells it en_US.utf8; LC_ALL=en_US.UTF-8 still resolves.
LOCALES=$(locale -a 2>/dev/null || true)
HAVE_ENUS=0
if grep -qiE '^en_US\.utf-?8$' <<<"$LOCALES"; then HAVE_ENUS=1; fi

# A missing en_US locale is a counted SKIP locally (SKIPPED is part of the floor's ran count)
# and a hard FAIL under CI=true, so a runner without the locale cannot go silently green.
locale_absent() {
  if [[ "${CI:-}" == "true" ]]; then
    assert_eq "en_US.UTF-8 installed" "absent" "$1 (en_US.UTF-8 is required under CI=true)"
  else
    echo "  SKIP: $1 (en_US.UTF-8 not installed)"
    SKIPPED=$((SKIPPED + 1))
  fi
}

# Seed repo: commit 1 adds every path, commit 2 removes the DEL_PATHS (HEAD = tracked only).
SEED2="$TEST_DIR/seed2"
git init -q -b main "$SEED2"
git -C "$SEED2" config user.email "test@test.local"
git -C "$SEED2" config user.name "Test"
for p in "${HEAD_PATHS[@]}" "${DEL_PATHS[@]}"; do
  mkdir -p "$SEED2/$(dirname "$p")"
  printf 'v1\n' > "$SEED2/$p"
done
git -C "$SEED2" add -A
git -C "$SEED2" commit -q -m "commit1: tracked + soon-deleted paths"
for p in "${DEL_PATHS[@]}"; do git -C "$SEED2" rm -q "$p"; done
git -C "$SEED2" commit -q -m "commit2: delete the stale paths"

# Pristine drifted on-disk state (the bare root's populated working tree): every tracked path
# with STALE content plus the deleted paths still on disk. Each arm copies it; never reused.
TEMPLATE="$TEST_DIR/drift-template"
mkdir -p "$TEMPLATE"
for p in "${HEAD_PATHS[@]}" "${DEL_PATHS[@]}"; do
  mkdir -p "$TEMPLATE/$(dirname "$p")"
  printf 'stale\n' > "$TEMPLATE/$p"
done

# make_arm_root <name>: fresh bare clone (HEAD == commit2) + the drifted tree copied in.
make_arm_root() {
  local d="$TEST_DIR/arm-$1"
  assert_fixture_dir "$d"
  git clone -q --bare "$SEED2" "$d"
  cp -a "$TEMPLATE/." "$d/"
  printf '%s' "$d"
}

# run_sync <root> <locale> <log> [VAR=val ...]: real script, fixture root, rc left in SYNC_RC.
SYNC_RC=0
run_sync() {
  local root="$1" loc="$2" log="$3"
  shift 3
  assert_fixture_dir "$root"
  assert_fixture_dir "$log"
  SYNC_RC=0
  ( cd "$root" && env LC_ALL="$loc" "$@" bash "$SCRIPT" --yes sync-bare-files ) > "$log" 2>&1 || SYNC_RC=$?
}

count_existing() { # count_existing <root> <path>...
  local root="$1" n=0 p
  shift
  for p in "$@"; do if [[ -f "$root/$p" ]]; then n=$((n + 1)); fi; done
  printf '%s' "$n"
}
count_grep() { # count_grep <fixed-string> <file>: occurrence count, 0 when absent
  local n
  n=$(grep -cF -- "$1" "$2" || true)
  printf '%s' "${n:-0}"
}

NA_TRACKED="${HEAD_PATHS[$((${#HEAD_PATHS[@]} - 1))]}"
NA_DELETED="${DEL_PATHS[$((${#DEL_PATHS[@]} - 1))]}"
MARKETPLACE=".claude-plugin/marketplace.json"

echo "Test F0: fixture sensitivity — the LEGACY pipeline is wrong on this fixture (en_US.UTF-8)"
if [[ "$HAVE_ENUS" -eq 1 ]]; then
  git -C "$SEED2" -c core.quotePath=false ls-tree -r --name-only HEAD | LC_ALL=C sort -u > "$TEST_DIR/f0-head.txt"
  # Embedded copy of the pre-fix pipeline (comm in the user's locale over C-sorted inputs).
  legacy_out=$(cd "$SEED2" && LC_ALL=en_US.UTF-8 comm -23 \
    <(git log HEAD --pretty=format: --name-only --diff-filter=AMRC 2>/dev/null | LC_ALL=C sort -u | sed '/^$/d') \
    <(git ls-tree -r --name-only HEAD 2>/dev/null | LC_ALL=C sort -u) 2>"$TEST_DIR/f0.err" || true)
  assert_contains "$(cat "$TEST_DIR/f0.err")" "not in sorted order" "legacy comm warns 'not in sorted order' on the fixture"
  legacy_tracked=$(grep -cFxf "$TEST_DIR/f0-head.txt" <<<"$legacy_out" || true)
  legacy_tracked_ok="no"
  if [[ "${legacy_tracked:-0}" -ge 1 ]]; then legacy_tracked_ok="yes"; fi
  assert_eq "yes" "$legacy_tracked_ok" "legacy comm emits at least one TRACKED path as 'to delete'"
else
  locale_absent "F0 fixture-sensitivity guard"
fi
echo ""

f1_arm() { # f1_arm <label> <locale>
  local label="$1" loc="$2" root
  root=$(make_arm_root "f1-$label")
  run_sync "$root" "$loc" "$TEST_DIR/f1-$label-1.log"
  assert_eq "0" "$SYNC_RC" "[$label] sync-bare-files exits 0"
  assert_file_exists "$root/$MARKETPLACE" "[$label] $MARKETPLACE survives the prune"
  assert_eq "${#HEAD_PATHS[@]}" "$(count_existing "$root" "${HEAD_PATHS[@]}")" "[$label] every tracked path still on disk"
  assert_file_exists "$root/$NA_TRACKED" "[$label] tracked non-ASCII path survives"
  assert_eq "0" "$(count_existing "$root" "${DEL_PATHS[@]}")" "[$label] every really-deleted path pruned"
  assert_file_not_exists "$root/$NA_DELETED" "[$label] deleted non-ASCII path pruned"
  assert_eq "v1" "$(cat "$root/${HEAD_PATHS[1]}")" "[$label] stale tracked content refreshed from HEAD"
  assert_eq "0" "$(count_grep "not in sorted order" "$TEST_DIR/f1-$label-1.log")" "[$label] no 'not in sorted order' warning"
  assert_eq "0" "$(count_grep "ERROR: tracked path in prune set" "$TEST_DIR/f1-$label-1.log")" "[$label] no tracked path ever reached the prune set"
  assert_contains "$(cat "$TEST_DIR/f1-$label-1.log")" "Removed ${#DEL_PATHS[@]} stale tracked-deleted" "[$label] reports exactly the deleted paths"
  run_sync "$root" "$loc" "$TEST_DIR/f1-$label-2.log"
  assert_eq "0" "$SYNC_RC" "[$label] second sync exits 0"
  assert_eq "0" "$(count_grep "Removed" "$TEST_DIR/f1-$label-2.log")" "[$label] second sync removes nothing (idempotent)"
  assert_file_exists "$root/$MARKETPLACE" "[$label] $MARKETPLACE still present after the second sync"
}

echo "Test F1 (C): locale-pinned prune — marketplace survives, deleted paths pruned"
f1_arm "C" "C"
echo ""

echo "Test F1 (en_US.UTF-8): same fixture under the locale that triggered the bug"
if [[ "$HAVE_ENUS" -eq 1 ]]; then
  f1_arm "en_US" "en_US.UTF-8"
else
  locale_absent "F1 under en_US.UTF-8"
fi
echo ""

echo "Test F5: ceiling — a prune larger than SOLEUR_SYNC_PRUNE_MAX is skipped loudly"
root=$(make_arm_root "f5")
run_sync "$root" "C" "$TEST_DIR/f5.log" SOLEUR_SYNC_PRUNE_MAX=1
assert_eq "0" "$SYNC_RC" "[ceiling] exits 0 so cleanup-merged still completes"
assert_eq "${#DEL_PATHS[@]}" "$(count_existing "$root" "${DEL_PATHS[@]}")" "[ceiling] ALL stale paths remain (no partial prune past the ceiling)"
assert_contains "$(cat "$TEST_DIR/f5.log")" "SOLEUR_SYNC_PRUNE_MAX" "[ceiling] WARN names the override"
assert_file_exists "$root/$MARKETPLACE" "[ceiling] $MARKETPLACE intact"
assert_eq "v1" "$(cat "$root/${HEAD_PATHS[1]}")" "[ceiling] checkout-index refresh still applied"
root=$(make_arm_root "f5b")
run_sync "$root" "C" "$TEST_DIR/f5b.log" SOLEUR_SYNC_PRUNE_MAX="${#DEL_PATHS[@]}"
assert_eq "0" "$(count_existing "$root" "${DEL_PATHS[@]}")" "[ceiling] a prune exactly AT the ceiling still runs"
echo ""

echo "Test F8: injected ordering bug — a tracked path in the prune set is never deleted"
mkdir -p "$TEST_DIR/stubbin"
cat > "$TEST_DIR/stubbin/comm" <<STUB
#!/usr/bin/env bash
# Stub comm modelling the original bug: ignores its inputs and returns a tracked path
# FIRST, then a really-deleted path.
touch "$TEST_DIR/stub-comm.called"
printf '%s\n' "$MARKETPLACE" "${DEL_PATHS[0]}"
STUB
chmod +x "$TEST_DIR/stubbin/comm"
root=$(make_arm_root "f8")
run_sync "$root" "C" "$TEST_DIR/f8.log" PATH="$TEST_DIR/stubbin:$PATH"
assert_file_exists "$TEST_DIR/stub-comm.called" "[guard] the stub comm was actually called (arm is not vacuous)"
assert_eq "0" "$SYNC_RC" "[guard] exits 0 on an ordering-bug signal"
assert_file_exists "$root/$MARKETPLACE" "[guard] $MARKETPLACE survives a comm that returned it"
assert_contains "$(cat "$TEST_DIR/f8.log")" "ERROR: tracked path in prune set: $MARKETPLACE" "[guard] loud ERROR names the tracked path"
assert_eq "${#DEL_PATHS[@]}" "$(count_existing "$root" "${DEL_PATHS[@]}")" "[guard] abort-all: nothing pruned, even the genuinely stale path"
echo ""

echo "Test F7: sibling census — no C-sorted list is compared by a comm/join in the user's locale"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
# in_scope: file sorts/uniqs under LC_ALL=C and does not pin the whole script's locale.
census_in_scope() {
  grep -qE 'LC_ALL=C[[:space:]]+(sort|uniq)' "$1" || return 1
  if grep -qE '^[[:space:]]*(export[[:space:]]+)?LC_ALL=[A-Za-z0-9_.@-]*[[:space:]]*(#.*)?$' "$1"; then return 1; fi
  return 0
}
# violations: non-comment `comm`/`join` with a -<digit> option on a line lacking LC_ALL=C.
census_violations() {
  census_in_scope "$1" || return 0
  grep -nE '(^|[^[:alnum:]_./-])(comm|join)[[:space:]]+-[0-9]' "$1" | grep -vE '^[0-9]+:[[:space:]]*#' | grep -v 'LC_ALL=C' || true
}
printf '%s\n' '#!/usr/bin/env bash' 'a=$(printf x | LC_ALL=C sort -u)' 'comm -23 <(echo "$a") <(echo y)' > "$TEST_DIR/census-offender.sh"
printf '%s\n' '#!/usr/bin/env bash' 'a=$(printf x | LC_ALL=C sort -u)' 'LC_ALL=C comm -23 <(echo "$a") <(echo y)' > "$TEST_DIR/census-compliant.sh"
printf '%s\n' '#!/usr/bin/env bash' 'export LC_ALL=C' 'a=$(printf x | LC_ALL=C sort -u)' 'comm -23 <(echo "$a") <(echo y)' > "$TEST_DIR/census-pinned.sh"
assert_eq "1" "$(census_violations "$TEST_DIR/census-offender.sh" | wc -l | tr -d ' ')" "[census] predicate flags a synthetic offender"
assert_eq "0" "$(census_violations "$TEST_DIR/census-compliant.sh" | wc -l | tr -d ' ')" "[census] predicate passes a synthetic compliant file"
assert_eq "0" "$(census_violations "$TEST_DIR/census-pinned.sh" | wc -l | tr -d ' ')" "[census] predicate passes a file that pins LC_ALL at line start"
census_examined=0
census_bad=""
if [[ -n "$REPO_ROOT" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" && -f "$REPO_ROOT/$f" ]] || continue
    case "$f" in *.test.sh) continue ;; esac
    if census_in_scope "$REPO_ROOT/$f"; then census_examined=$((census_examined + 1)); fi
    v=$(census_violations "$REPO_ROOT/$f")
    if [[ -n "$v" ]]; then census_bad+="$f: $v"$'\n'; fi
  done < <(git -C "$REPO_ROOT" ls-files '*.sh')
fi
census_examined_ok="no"
if [[ "$census_examined" -ge 1 ]]; then census_examined_ok="yes"; fi
assert_eq "yes" "$census_examined_ok" "[census] examined at least one in-scope script (population floor)"
assert_eq "" "$census_bad" "[census] no tracked script compares a C-sorted list with a locale-bound comm/join"
echo ""

# Anti-vacuity floor: 41 = the MINIMUM number of assertions (PASS + FAIL + SKIPPED) a run on a
# box WITHOUT en_US.UTF-8 executes (39 pass + 2 counted skips: F0 and F1-en_US). Measured by
# shadowing `locale` on PATH; a run with the locale adds the en_US arms on top (54 pass). A floor,
# never an equality, so a dev box without the locale does not trip it. Raise it in the SAME edit
# that adds an assertion; neutering assert_* or deleting arms trips it (exit 1).
print_results 41
