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
#
# LOCALE REGRESSION ARMS (below Test 5). The prune compared two LC_ALL=C-sorted lists
# with a comm running in the user's locale, which deleted tracked files (including
# .claude-plugin/marketplace.json) from the bare root. The arms F0-F12 run a calibrated
# fixture under C and en_US.UTF-8, and pin the safety net around the prune: the
# tracked-path guard and its abort, the ceiling, the pinned HEAD (run from a worktree),
# symlinked ancestors, git's own files, and the sibling census (F7).
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
# Top-level docs dir name, held in a variable so this fixture's synthetic paths are not read as a
# consumer of the real directory by scripts/test-affected-kb-consumers.test.sh.
KB="knowledge""-base"

# Calibrated, frozen fixture: ~22 tracked paths + 8 really-deleted ones, chosen by a seeded
# search so the LEGACY pipeline under en_US.UTF-8 prints "not in sorted order" AND emits a
# tracked path (.claude-plugin/marketplace.json). A 5-path fixture does not reproduce the
# bug at all (measured), so do not shrink or regenerate this list; arm F0 proves it bites.
HEAD_PATHS=(
  ".claude-plugin/marketplace.json"
  "${KB}/legal/legitimate-interest-assessments/2026-07-07-beta-crm-lia.md"
  "tests/scripts/lib/vector-redeliver-gate.sh"
  "apps/web-platform/supabase/migrations/071_ux_audit_artifacts_bucket.sql"
  "${KB}/project/learnings/workflow-patterns/2026-09-18-an-index-exists-claim-is-two-claims-mapping-direction-and-class-membership.md"
  "${KB}/engineering/architecture/decisions/ADR-127-review-evidence-trailer-is-a-boolean-not-a-content-attestation.md"
  "plugins/soleur/cursor/skills/soleur-xcode-test/SKILL.md"
  "${KB}/project/specs/archive/20261013-041741-feat-one-shot-6357-stale-cloudflared-registry-ingress/decision-challenges.md"
  "${KB}/project/specs/archive/20261013-051752-feat-one-shot-zot-migration-completion/session-state.md"
  "${KB}/project/specs/archive/20261012-213508-feat-enforce-ux-content-gates/tasks.md"
  "${KB}/project/learnings/2026-07-30-a-known-gap-of-seven-was-a-predicate-and-my-battery-mutated-one-axis.md"
  "apps/web-platform/test/sandbox-credential-deny-runtime.test.ts"
  "plugins/soleur/agents/community/.gitkeep"
  "apps/web-platform/infra/cutover-monitor-baseline.txt"
  "${KB}/project/specs/archive/20261012-213508-feat-weekly-analytics-improvements/session-state.md"
  "${KB}/project/specs/archive/20261013-032858-feat-one-shot-collapse-icon-workspace-selector-align/session-state.md"
  ".claude/hooks/new-scheduled-cron-prefer-inngest.test.sh"
  "${KB}/project/specs/archive/20261013-041741-feat-one-shot-4826-nav-rail-position-resume/tasks.md"
  "${KB}/project/plans/archive/20260423-131811-2026-04-23-fix-repo-setup-git-clone-creds-plan.md"
  "${KB}/project/learnings/best-practices/2026-05-05-workflow-jwt-mint-silent-failure-traps.md"
  "apps/web-platform/test/server/kb-active-workspace-scoping.test.ts"
  "${KB}/project/specs/archive/20261012-213508-verify-canus${NA}ool-caching-876/session-state.md"
)
DEL_PATHS=(
  "${KB}/project/specs/feat-one-shot-2618-terraform-drift-deploy-pipeline-fix/session-state.md"
  "${KB}/brainstorms/archive/20260227-162802-2026-02-27-feature-video-deps-brainstorm.md"
  "${KB}/brainstorms/2026-02-06-pull-before-worktree-brainstorm.md"
  "${KB}/brainstorms/2026-03-14-linkedin-company-variant-brainstorm.md"
  ".openhands/skills/pricing-strategist/SKILL.md"
  "${KB}/project/specs/feat-one-shot-9239-backstop-hook-resolution/tasks.md"
  "${KB}/project/plans/2026-06-03-fix-kb-sync-affordance-and-reconcile-self-heal-plan.md"
  "${KB}/project/specs/verify-canus${NA}ool-caching-876/session-state.md"
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

f1_arm() { # f1_arm <C|en_US>: the locale is DERIVED from the label so the two cannot disagree
  local label="$1" loc root
  case "$label" in
    C) loc="C" ;;
    en_US) loc="en_US.UTF-8" ;;
    *) echo "FATAL: unknown f1_arm label '$label'" >&2; exit 2 ;;
  esac
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
  assert_contains "$(cat "$TEST_DIR/f1-$label-2.log")" "Synced on-disk files from git HEAD" "[$label] second sync ran to completion (positive control for the absence check above)"
  assert_file_exists "$root/$MARKETPLACE" "[$label] $MARKETPLACE still present after the second sync"
}

echo "Test F1 (C): locale-pinned prune — marketplace survives, deleted paths pruned"
f1_arm "C"
echo ""

echo "Test F1 (en_US.UTF-8): same fixture under the locale that triggered the bug"
if [[ "$HAVE_ENUS" -eq 1 ]]; then
  f1_arm "en_US"
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
assert_eq "1" "$(count_grep "Synced on-disk files from git HEAD (prune skipped" "$TEST_DIR/f5.log")" "[ceiling] the final line says the prune was skipped (it must not read as a clean sync)"
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

echo "Test F8b: an ordering bug that returns EVERY tracked path prints a bounded ERROR list"
mkdir -p "$TEST_DIR/stubflood"
{
  printf '#!/usr/bin/env bash\n'
  printf 'printf "%%s\\n"'
  for p in "${HEAD_PATHS[@]}"; do printf ' %q' "$p"; done
  printf '\n'
} > "$TEST_DIR/stubflood/comm"
chmod +x "$TEST_DIR/stubflood/comm"
root=$(make_arm_root "f8b")
run_sync "$root" "C" "$TEST_DIR/f8b.log" PATH="$TEST_DIR/stubflood:$PATH"
assert_eq "10" "$(count_grep "ERROR: tracked path in prune set" "$TEST_DIR/f8b.log")" "[guard] ${#HEAD_PATHS[@]} tracked hits print 10 ERROR lines, not one per path"
assert_eq "${#HEAD_PATHS[@]}" "$(count_existing "$root" "${HEAD_PATHS[@]}")" "[guard] every tracked path survives a comm that returned all of them"
echo ""

echo "Test F5c/F5d: the ceiling reads a leading zero as decimal and counts paths to REMOVE"
root=$(make_arm_root "f5c")
run_sync "$root" "C" "$TEST_DIR/f5c.log" SOLEUR_SYNC_PRUNE_MAX=09
assert_eq "0" "$(count_grep "too great for base" "$TEST_DIR/f5c.log")" "[ceiling] a leading-zero value (09) raises no octal arithmetic error"
assert_eq "0" "$(count_existing "$root" "${DEL_PATHS[@]}")" "[ceiling] MAX=09 reads as decimal 9, so a prune of 8 runs"
run_sync "$root" "C" "$TEST_DIR/f5d.log" SOLEUR_SYNC_PRUNE_MAX=1
assert_eq "0" "$(count_grep "exceed SOLEUR_SYNC_PRUNE_MAX" "$TEST_DIR/f5d.log")" "[ceiling] a settled root has nothing to remove, so MAX=1 does not trip (candidates are not counted)"
root=$(make_arm_root "f5e")
run_sync "$root" "C" "$TEST_DIR/f5e.log" SOLEUR_SYNC_PRUNE_MAX=lots
assert_contains "$(cat "$TEST_DIR/f5e.log")" "ignoring invalid SOLEUR_SYNC_PRUNE_MAX=lots" "[ceiling] an invalid value is announced"
assert_eq "0" "$(count_existing "$root" "${DEL_PATHS[@]}")" "[ceiling] an invalid value falls back to the default, so the prune runs"
# A scratch dir that cannot be made skips the prune; it must not abort the whole sync (cleanup-merged tail).
mkdir -p "$TEST_DIR/nomktemp"
cat > "$TEST_DIR/nomktemp/mktemp" <<'NOMKTEMP'
#!/usr/bin/env bash
if [[ "${1:-}" == "-d" ]]; then exit 1; fi
exec /usr/bin/env -S PATH=/usr/bin:/bin mktemp "$@"
NOMKTEMP
chmod +x "$TEST_DIR/nomktemp/mktemp"
root=$(make_arm_root "f13")
run_sync "$root" "C" "$TEST_DIR/f13.log" PATH="$TEST_DIR/nomktemp:$PATH"
assert_eq "0" "$SYNC_RC" "[scratch] exits 0 when the scratch dir cannot be created"
assert_eq "${#DEL_PATHS[@]}" "$(count_existing "$root" "${DEL_PATHS[@]}")" "[scratch] nothing is pruned without a scratch dir"
assert_contains "$(cat "$TEST_DIR/f13.log")" "prune skipped" "[scratch] the skip is announced"
echo ""

echo "Test F9: an empty HEAD tree never reads as 'everything ever tracked is stale'"
SEED9="$TEST_DIR/seed9"
git init -q -b main "$SEED9"
git -C "$SEED9" config user.email "test@test.local"
git -C "$SEED9" config user.name "Test"
printf 'v1\n' > "$SEED9/a.txt"
git -C "$SEED9" add -A
git -C "$SEED9" commit -q -m "add"
git -C "$SEED9" rm -q a.txt
git -C "$SEED9" commit -q -m "remove everything"
ROOT9="$TEST_DIR/arm-f9"
assert_fixture_dir "$ROOT9"
git clone -q --bare "$SEED9" "$ROOT9"
printf 'stale\n' > "$ROOT9/a.txt"
run_sync "$ROOT9" "C" "$TEST_DIR/f9.log"
assert_eq "0" "$SYNC_RC" "[empty-head] exits 0"
assert_file_exists "$ROOT9/a.txt" "[empty-head] nothing is pruned when HEAD lists no paths"
assert_contains "$(cat "$TEST_DIR/f9.log")" "prune skipped" "[empty-head] the skip is announced"
echo ""

echo "Test F10: candidates that only LOOK removable are kept (symlinks, git's own files, odd names)"
SEED4="$TEST_DIR/seed4"
OUTSIDE4="$TEST_DIR/outside4"
git init -q -b main "$SEED4"
git -C "$SEED4" config user.email "test@test.local"
git -C "$SEED4" config user.name "Test"
mkdir -p "$SEED4/old" "$SEED4/link/sub" "$SEED4/-dash"
for p in old/x.md link/sub/old.txt gone.lnk -dash/old.txt description keep.txt; do printf 'v1\n' > "$SEED4/$p"; done
git -C "$SEED4" add -A
git -C "$SEED4" commit -q -m "history"
git -C "$SEED4" rm -rq -- old link -dash gone.lnk description
mkdir -p "$SEED4/real"
printf 'v1\n' > "$SEED4/real/x.md"
ln -s real "$SEED4/old"
ln -s "$OUTSIDE4" "$SEED4/link"
git -C "$SEED4" add -A
git -C "$SEED4" commit -q -m "dirs become symlinks, files are deleted"
ROOT4="$TEST_DIR/arm-f10"
assert_fixture_dir "$ROOT4"
assert_fixture_dir "$OUTSIDE4"
git clone -q --bare "$SEED4" "$ROOT4"
mkdir -p "$OUTSIDE4/sub" "$ROOT4/-dash"
printf 'outside\n' > "$OUTSIDE4/sub/old.txt"
printf 'v1\n' > "$ROOT4/-dash/old.txt"
ln -s /nonexistent-target "$ROOT4/gone.lnk"
run_sync "$ROOT4" "C" "$TEST_DIR/f10.log"
assert_eq "0" "$SYNC_RC" "[odd-paths] exits 0"
assert_file_exists "$ROOT4/real/x.md" "[odd-paths] a tracked file behind a directory that became a symlink survives"
assert_file_exists "$OUTSIDE4/sub/old.txt" "[odd-paths] a file OUTSIDE the root behind a symlinked ancestor survives"
assert_eq "gone" "$([[ -L "$ROOT4/gone.lnk" || -e "$ROOT4/gone.lnk" ]] && echo present || echo gone)" "[odd-paths] a dangling symlink at a tracked-deleted path is pruned"
assert_eq "gone" "$([[ -e "$ROOT4/-dash" ]] && echo present || echo gone)" "[odd-paths] a deleted file under a dash-leading directory is pruned and the emptied directory removed"
assert_eq "0" "$(count_grep "invalid option" "$TEST_DIR/f10.log")" "[odd-paths] no dirname/rmdir option error on a dash-leading name"
assert_eq "yes" "$([[ -s "$ROOT4/description" ]] && echo yes || echo no)" "[odd-paths] git's own description file survives a once-tracked file of that name"
echo ""

echo "Test F11: run from a feature worktree, the prune still follows the bare root's HEAD"
root=$(make_arm_root "f11")
assert_fixture_dir "$root"
WT11="$TEST_DIR/wt-f11"
assert_fixture_dir "$WT11"
git -C "$root" worktree add -q -b featx "$WT11" main
git -C "$WT11" config user.email "test@test.local"
git -C "$WT11" config user.name "Test"
git -C "$WT11" rm -q -- "${HEAD_PATHS[1]}"
git -C "$WT11" commit -q -m "feature branch deletes a path main still tracks"
SYNC_RC=0
( cd "$WT11" && env LC_ALL=C bash "$SCRIPT" --yes sync-bare-files ) > "$TEST_DIR/f11.log" 2>&1 || SYNC_RC=$?
assert_eq "0" "$SYNC_RC" "[worktree] exits 0"
assert_file_exists "$root/${HEAD_PATHS[1]}" "[worktree] a path main tracks survives a sync run from a branch that deleted it"
assert_eq "v1" "$(cat "$root/${HEAD_PATHS[1]}")" "[worktree] the root mirrors main, not the feature branch"
assert_eq "0" "$(count_existing "$root" "${DEL_PATHS[@]}")" "[worktree] the really-deleted paths are still pruned"
# The PRODUCTION layout: the git dir is `<root>/.git` (core.bare=true) and the root holds the tree.
root="$TEST_DIR/arm-f11b"
assert_fixture_dir "$root"
mkdir -p "$root"
git clone -q --bare "$SEED2" "$root/.git"
git -C "$root" config core.bare true
cp -a "$TEMPLATE/." "$root/"
WT11B="$TEST_DIR/wt-f11b"
assert_fixture_dir "$WT11B"
git -C "$root" worktree add -q -b featy "$WT11B" main
git -C "$WT11B" config user.email "test@test.local"
git -C "$WT11B" config user.name "Test"
git -C "$WT11B" rm -q -- "${HEAD_PATHS[1]}"
git -C "$WT11B" commit -q -m "feature branch deletes a path main still tracks"
printf 'stale\n' > "$root/${HEAD_PATHS[1]}"
SYNC_RC=0
( cd "$WT11B" && env LC_ALL=C bash "$SCRIPT" --yes sync-bare-files ) > "$TEST_DIR/f11b.log" 2>&1 || SYNC_RC=$?
assert_eq "0" "$SYNC_RC" "[worktree/.git layout] exits 0"
assert_eq "v1" "$(cat "$root/${HEAD_PATHS[1]}" 2>/dev/null || echo MISSING)" "[worktree/.git layout] the root's copy is refreshed from main, not removed or taken from the branch"
assert_eq "${#HEAD_PATHS[@]}" "$(count_existing "$root" "${HEAD_PATHS[@]}")" "[worktree/.git layout] every tracked path is on disk after a sync run from a worktree"
assert_eq "0" "$(count_existing "$root" "${DEL_PATHS[@]}")" "[worktree/.git layout] the really-deleted paths are pruned"
echo ""

echo "Test F12: a '..' path in history never reaches rm"
SEED12="$TEST_DIR/seed12"
git init -q -b main "$SEED12"
git -C "$SEED12" config user.email "test@test.local"
git -C "$SEED12" config user.name "Test"
BLOB12=$(printf 'x\n' | git -C "$SEED12" hash-object -w --stdin)
SUB12=$(printf '100644 blob %s\tdotdot-victim.txt\n' "$BLOB12" | git -C "$SEED12" mktree)
TREE1=$(printf '040000 tree %s\t..\n100644 blob %s\tkeep.txt\n' "$SUB12" "$BLOB12" | git -C "$SEED12" mktree)
TREE2=$(printf '100644 blob %s\tkeep.txt\n' "$BLOB12" | git -C "$SEED12" mktree)
C1=$(git -C "$SEED12" commit-tree "$TREE1" -m "tree with a dotdot entry")
C2=$(git -C "$SEED12" commit-tree "$TREE2" -p "$C1" -m "drop it")
git -C "$SEED12" update-ref refs/heads/main "$C2"
ROOT12="$TEST_DIR/arm-f12"
assert_fixture_dir "$ROOT12"
git clone -q --bare "$SEED12" "$ROOT12"
printf 'victim\n' > "$TEST_DIR/dotdot-victim.txt"
run_sync "$ROOT12" "C" "$TEST_DIR/f12.log"
assert_eq "0" "$SYNC_RC" "[dotdot] exits 0"
assert_file_exists "$TEST_DIR/dotdot-victim.txt" "[dotdot] a file above the root named by a '..' history path survives"
echo ""

echo "Test F7: sibling census — no C-sorted list is compared by a comm/join in the user's locale"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
SELF_REL="plugins/soleur/test/worktree-manager-bare-sync.test.sh"
# in_scope: the file sorts/uniqs under LC_ALL=C and does not pin the whole script's locale. The pin must
# start at column 0 (an indented one is function- or subshell-scoped) and name C itself.
census_in_scope() {
  grep -qE 'LC_ALL=C[[:space:]]+(sort|uniq)' "$1" || return 1
  if grep -qE '^(export[[:space:]]+)?LC_ALL=C[[:space:]]*(#.*)?$' "$1"; then return 1; fi
  return 0
}
# violations: a non-comment comm/join that takes a -<digit> option (alone or after other options) with no
# `LC_ALL=C` immediately in front of the command. A pin on an earlier pipeline stage does not count: the
# original bug had `LC_ALL=C sort` feeding a bare `comm -23` on one line.
census_violations() {
  census_in_scope "$1" || return 0
  grep -nE '(^|[^[:alnum:]_./-])(/usr/bin/)?(comm|join)[[:space:]]+(-[-A-Za-z0-9=]+[[:space:]]+)*-[0-9]' "$1" \
    | grep -vE '^[0-9]+:[[:space:]]*#' \
    | grep -vE 'LC_ALL=C[[:space:]]+(env[[:space:]]+)?(/usr/bin/)?(comm|join)([[:space:]]|$)' || true
}
printf '%s\n' '#!/usr/bin/env bash' 'a=$(printf x | LC_ALL=C sort -u)' 'comm -23 <(echo "$a") <(echo y)' > "$TEST_DIR/census-offender.sh"
printf '%s\n' '#!/usr/bin/env bash' 'a=$(printf x | LC_ALL=C sort -u)' 'LC_ALL=C comm -23 <(echo "$a") <(echo y)' > "$TEST_DIR/census-compliant.sh"
printf '%s\n' '#!/usr/bin/env bash' 'export LC_ALL=C' 'a=$(printf x | LC_ALL=C sort -u)' 'comm -23 <(echo "$a") <(echo y)' > "$TEST_DIR/census-pinned.sh"
# The ORIGINAL bug shape: the pin sits on the sort stage of the SAME line as the unpinned comm.
printf '%s\n' '#!/usr/bin/env bash' 'comm -23 <(a | LC_ALL=C sort -u) <(b | LC_ALL=C sort -u)' > "$TEST_DIR/census-oneline.sh"
printf '%s\n' '#!/usr/bin/env bash' 'a=$(printf x | LC_ALL=C sort -u)' 'comm -z -23 <(echo "$a") <(echo y)' > "$TEST_DIR/census-zflag.sh"
printf '%s\n' '#!/usr/bin/env bash' 'f() {' '  LC_ALL=C' '  :' '}' 'a=$(printf x | LC_ALL=C sort -u)' 'comm -23 <(echo "$a") <(echo y)' > "$TEST_DIR/census-indented.sh"
assert_eq "1" "$(census_violations "$TEST_DIR/census-offender.sh" | wc -l | tr -d ' ')" "[census] predicate flags a synthetic offender"
assert_eq "0" "$(census_violations "$TEST_DIR/census-compliant.sh" | wc -l | tr -d ' ')" "[census] predicate passes a synthetic compliant file"
assert_eq "0" "$(census_violations "$TEST_DIR/census-pinned.sh" | wc -l | tr -d ' ')" "[census] predicate passes a file that pins LC_ALL=C at column 0"
assert_eq "1" "$(census_violations "$TEST_DIR/census-oneline.sh" | wc -l | tr -d ' ')" "[census] predicate flags the original one-line shape (pin on the sort, bare comm)"
assert_eq "1" "$(census_violations "$TEST_DIR/census-zflag.sh" | wc -l | tr -d ' ')" "[census] predicate flags a comm with a leading -z option"
assert_eq "1" "$(census_violations "$TEST_DIR/census-indented.sh" | wc -l | tr -d ' ')" "[census] an INDENTED LC_ALL=C (function-scoped) does not exempt the file"
census_examined=0
census_bad=""
census_seen=" "
if [[ -n "$REPO_ROOT" ]]; then
  # Prefilter with one git grep (the scope predicate's first limb) instead of forking per tracked script.
  while IFS= read -r f; do
    [[ -n "$f" && "$f" != "$SELF_REL" && -f "$REPO_ROOT/$f" ]] || continue
    census_in_scope "$REPO_ROOT/$f" || continue
    census_examined=$((census_examined + 1))
    census_seen+="$f "
    v=$(census_violations "$REPO_ROOT/$f")
    if [[ -n "$v" ]]; then census_bad+="$f: $v"$'\n'; fi
  done < <(git -C "$REPO_ROOT" grep -lE 'LC_ALL=C[[:space:]]+(sort|uniq)' -- '*.sh')
fi
# Population floor expressed as an assertion value, not an `if` on the counter: an `if` over a
# counter reads as a hand-rolled anti-vacuity floor to scripts/guard-vacuity-floor.test.sh.
assert_eq "yes" "$([[ "$census_examined" -ge 20 ]] && echo yes || echo no)" "[census] examined at least 20 in-scope scripts (population floor; measured ~45)"
for anchor in plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh scripts/plugin-delivery-canary.sh apps/web-platform/infra/run-registered-suites.sh; do
  assert_eq "yes" "$([[ "$census_seen" == *" $anchor "* ]] && echo yes || echo no)" "[census] the population includes $anchor (a sibling this class already hit)"
done
assert_eq "" "$census_bad" "[census] no tracked script (test files included) compares a C-sorted list with a locale-bound comm/join"
echo ""

# Anti-vacuity floor, a FLOOR never an equality. With en_US.UTF-8 installed every arm runs: 93 assertions.
# Without it the two en_US-only arms become counted skips (PASS + FAIL + SKIPPED = 79: 77 pass + 2 skip),
# so the floor follows the box: a run that has the locale may not silently lose the en_US arms or any
# other assertion (13 unguarded assertions of slack was the review finding on a flat 41). Measured by
# shadowing `locale` on PATH for the absent case. Raise it in the SAME edit that adds an assertion;
# neutering assert_* or deleting arms trips it (exit 1).
print_results $(( HAVE_ENUS == 1 ? 93 : 79 ))
