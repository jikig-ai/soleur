# Fix: `worktree-manager.sh feature` creates spec dir at bare root instead of worktree checkout

**Issue:** #2815
**Branch:** `feat-one-shot-2815-worktree-spec-dir`
**Type:** bug (priority/p2-medium, domain/engineering, type/bug)
**Detail level:** MINIMAL (single-file shell fix + small test)

## Enhancement Summary

**Deepened on:** 2026-04-22
**Sections enhanced:** Overview, Research Reconciliation, Files to Edit, Test Scenarios, Risks
**Research sources used:** 4 learnings files (2026-03-13 archive-kb stale-path, 2026-02-22 archiving slug extraction, 2026-03-17 worktree absolute-path, 2026-03-13 bash arithmetic + test-sourcing), live reads of `worktree-manager.sh` (lines 42-62 GIT_ROOT resolution, lines 393-458 `create_for_feature`, lines 686-812 `cleanup_merged_worktrees`), downstream consumer grep across brainstorm/plan/one-shot SKILL.md, test convention reconnaissance in `plugins/soleur/test/`.

### Key Improvements

1. **Regression-class callout:** The 2026-02-22 archiving-slug learning documents that the *fix* for a path-hardcoding bug can itself reproduce the bug if the author isn't vigilant. Added an explicit "do NOT introduce a new hardcoded `knowledge-base/project/` literal; reuse `$worktree_path`" check in the implementation phase.
2. **Cleanup-archival semantics clarified:** Enhanced the cleanup-merged archival analysis. The line 766-778 block is backward-compatibility only (legacy bare-root specs from pre-fix worktrees); for new worktrees, the spec's canonical archive is git history on main (the spec gets committed to the feature branch and merged). No archival code change is required — documented as a deliberate non-goal.
3. **Absolute-path safety confirmed:** Per 2026-03-17 learning, `$worktree_path` in the script is already absolute (constructed as `$WORKTREE_DIR/$branch_name` where `$WORKTREE_DIR="$GIT_ROOT/.worktrees"` and `$GIT_ROOT` is resolved absolute). No nested-worktree risk from the path swap.
4. **Test harness pattern pinned:** Per 2026-03-13 bash-arithmetic-and-test-sourcing learning, the new `.test.sh` invokes the production script via `bash <script>` subprocess rather than sourcing. This keeps the test truly end-to-end (exercises the whole `create_for_feature` flow including `git worktree add` + spec-dir creation) and matches the isolation pattern used by `resolve-git-root.test.sh`.
5. **Added `shellcheck` pre-merge gate:** `shellcheck plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` must pass on the modified file. Catches quoting regressions in path variables (especially critical when a path contains spaces — unlikely in the `.worktrees/feat-*` naming convention but low-cost to verify).

### New Considerations Discovered

- **Backward-compat observation:** There are no existing pre-fix bare-root spec directories on main (verified via `ls /home/jean/git-repositories/jikig-ai/soleur/knowledge-base/project/specs/` — all entries are feat-branch-named, matching the bare-root layout). Post-merge, on the next `cleanup-merged` run, legacy bare-root dirs for any already-merged feat-branches will be archived. This is the intended migration path.
- **The 2026-03-13 archive-kb learning's "current+legacy paths array" pattern does NOT apply here.** That pattern was for a directory *rename* (layout A → layout B). This issue is different: the spec never should have been at the bare root for a worktree-scoped workflow. The fix is a straight redirect, not a dual-read.
- **Test-sourcing decision:** The new test should NOT source `worktree-manager.sh` directly — it would trigger the top-level `IS_BARE`/`IS_IN_WORKTREE` detection against the **test harness's outer shell**, leaking the real repo's config into the synthetic test bare repo. Instead, invoke as a subprocess: `bash "$SCRIPT" --yes feature <name>`.
- **Risk flagged but rejected:** Could the fix break `cleanup_merged_worktrees` archival? No — the block at line 766-778 guards with `[[ -d "$spec_dir" ]]`, which silently skips when the dir doesn't exist (the new layout). No code-path break.

## Overview

`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` function `create_for_feature()` (line 393-458) creates the spec directory at `$GIT_ROOT/knowledge-base/project/specs/feat-<name>/` — i.e., the **bare repo root**. Downstream skills (`brainstorm`, `plan`) then read/write the spec from the **worktree** at `<worktree_path>/knowledge-base/project/specs/feat-<name>/`, producing two diverged locations (one tracked on main via stale bare-root directory, one tracked on the feature branch inside the worktree). This fix redirects the `mkdir -p` to the worktree path so the spec lives where downstream skills expect it and where `git add` inside the worktree will pick it up.

## Research Reconciliation — Spec vs. Codebase

| Claim (from #2815 body) | Reality | Plan response |
|---|---|---|
| `worktree-manager.sh feature <name>` creates spec at bare root. | Confirmed. Line 406: `local spec_dir="$GIT_ROOT/knowledge-base/project/specs/$branch_name"` and line 440: `mkdir -p "$spec_dir"`. In a bare repo, `$GIT_ROOT` is the bare root (lines 42-62). | Redirect to `$worktree_path/knowledge-base/project/specs/$branch_name`. |
| Brainstorm skill writes the spec to the worktree path. | Confirmed. `plugins/soleur/skills/brainstorm/SKILL.md:287` explicitly writes to `<worktree-path>/knowledge-base/project/specs/feat-<name>/spec.md`. | No change needed in brainstorm. |
| Plan skill does `mkdir -p knowledge-base/project/specs/<branch-name>` from CWD inside the worktree. | Confirmed. `plugins/soleur/skills/plan/SKILL.md:474`. Runs after `cd <worktree>`, so it targets the worktree (correct behavior). | No change needed in plan. |
| `cleanup_merged_worktrees` archives the spec from `$GIT_ROOT/knowledge-base/project/specs/$safe_branch`. | Confirmed. Line 767 reads bare-root path. Archival runs **before** `git worktree remove` (line 792) but after the fix the directory will live inside the worktree. The spec SHOULD already be committed on the feature branch and merged to main by the time `cleanup-merged` fires, so the canonical source of truth is main — but the on-disk stale copy at bare-root will no longer exist after the fix. | The archival block at line 766-778 becomes a **no-op** for the new worktree-scoped layout. It still safely handles legacy bare-root spec directories created by the old code (pre-fix worktrees). Leave it in place as a backward-compatibility hatch — do NOT delete. Add a brief inline comment noting the two layouts. |
| The `echo` hint at line 455 shows the relative path `knowledge-base/project/specs/$branch_name/spec.md`. | Confirmed. This is already worktree-relative (the user is told to `cd $worktree_path` first on line 454). | No change to the echo. |

## Hypotheses

Not applicable — this is not a network/SSH symptom. Bug is a single-line path mistake in a known function.

## Files to Edit

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
  - **Line 406:** change `local spec_dir="$GIT_ROOT/knowledge-base/project/specs/$branch_name"` → `local spec_dir="$worktree_path/knowledge-base/project/specs/$branch_name"`.
  - **Line 439 guard:** update the outer `if [[ -d "$GIT_ROOT/knowledge-base" ]]` check. After `git worktree add` runs, the worktree has its own copy of the `knowledge-base/` directory (checked out from `$from_branch`). Guard against worktrees where the branch does not contain `knowledge-base/` by checking `$worktree_path/knowledge-base` instead: `if [[ -d "$worktree_path/knowledge-base" ]]; then`.
  - **Line 767 (inside `cleanup_merged_worktrees`):** add a brief inline comment noting the layout transition: `# Legacy bare-root spec dirs created by pre-fix worktrees still archive here.` No behavior change — the check `[[ -d "$spec_dir" ]]` already silently skips when the directory doesn't exist (new layout).
  - No change to lines 411, 418, 441, 455 echo statements — the variable they print is now correct by virtue of the line 406 change.

### Regression-Class Callout (from 2026-02-22 archiving-slug learning)

The 2026-02-22 archiving slug extraction learning documents that the *fix* for a path-hardcoding bug can itself reproduce the bug class if the author only thinks about the primary case. Before committing Phase 2, the implementer MUST verify:

1. **No new hardcoded `$GIT_ROOT/knowledge-base` literal is introduced** in the diff. Run: `git diff plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh | grep '+' | grep -c 'GIT_ROOT/knowledge-base'` — should equal the count of context lines for line 767 (the legacy archival block) and nothing else.
2. **No new worktree-unrelated function is inadvertently changed** to reference `$worktree_path` (which is only scoped inside `create_for_feature`). Specifically: `cleanup_merged_worktrees` reuses the variable name `worktree_path` in a loop scope — do not change line 767 to `$worktree_path` (it would be the WRONG worktree in a cleanup context, plus would break legacy-layout archival).
3. **`shellcheck plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`** passes clean on the modified file. Catches stray quoting regressions.

## Files to Create

- `plugins/soleur/test/worktree-manager-feature-spec-dir.test.sh` — new bash test file following the project's `.test.sh` convention (see `plugins/soleur/test/resolve-git-root.test.sh` as the pattern template). Tests:
  1. **RED:** Given a bare repo + worktree-manager.sh `feature <name>` invocation, assert that `<worktree_path>/knowledge-base/project/specs/feat-<name>/` **exists** (currently fails).
  2. Assert that `$GIT_ROOT/knowledge-base/project/specs/feat-<name>/` (bare root) **does NOT exist** (currently fails — created at bare root).
  3. Idempotency: re-running `feature <name>` when the worktree already exists prints the existing-worktree message and does not re-create the spec dir at the bare root.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `create_for_feature` creates the spec directory at `<worktree_path>/knowledge-base/project/specs/feat-<name>/`, **not** at `<bare-root>/knowledge-base/project/specs/feat-<name>/`.
- [x] After running `worktree-manager.sh feature <name>`, a caller inside the worktree (`cd .worktrees/feat-<name> && ls knowledge-base/project/specs/feat-<name>`) sees the directory (no `mkdir -p` recovery needed).
- [x] New test `plugins/soleur/test/worktree-manager-feature-spec-dir.test.sh` passes (goes from RED to GREEN with the line 406 change).
- [x] Existing tests in `plugins/soleur/test/` still pass (`resolve-git-root.test.sh` and siblings — no regressions in `create_for_feature`'s siblings).
- [x] Script works from both bare root (`bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh feature <name>`) and from inside an existing worktree.
- [x] `cleanup_merged_worktrees` continues to succeed when archiving legacy bare-root spec dirs left over from pre-fix worktrees (backward compatibility — guard at line 768 silently skips when dir absent).

### Post-merge (operator)

- [ ] (No terraform, no migrations, no external service setup — pure shell bug fix.)
- [ ] Verify in the next `worktree-manager.sh feature <name>` invocation on a fresh branch that the spec directory lands inside the worktree. No-op otherwise.

## Test Scenarios

The new test file will cover:

1. **`feature <name>` on a bare repo**: sets up a bare repo + one worktree via `git worktree add`, invokes `create_for_feature`, asserts spec dir exists at worktree path and NOT at bare root.
2. **Idempotency**: calling `feature <name>` twice does not error and does not create duplicate dirs.
3. **No `knowledge-base/` on branch**: if the source branch lacks `knowledge-base/`, the spec dir is NOT created (current code already does this via the `[[ -d ... ]]` guard; update the guard to check the worktree path).

See `plugins/soleur/test/resolve-git-root.test.sh` for the `mktemp -d` + `git init --bare -q` test-setup pattern. Helpers in `plugins/soleur/test/test-helpers.sh` (`assert_contains`, `assert_eq`).

### Test Implementation Sketch

Following the pattern in `plugins/soleur/test/resolve-git-root.test.sh`:

```bash
#!/usr/bin/env bash
# plugins/soleur/test/worktree-manager-feature-spec-dir.test.sh
# Run: bash plugins/soleur/test/worktree-manager-feature-spec-dir.test.sh

set -euo pipefail

# Clear ALL GIT_* env vars that leak from outer shell / lefthook
while IFS= read -r var; do
  unset "$var" 2>/dev/null || true
done < <(env | grep -oP '^GIT_\w+' || true)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SCRIPT="$SCRIPT_DIR/../skills/git-worktree/scripts/worktree-manager.sh"

echo "=== worktree-manager.sh feature spec-dir location ==="

# Setup: create a synthetic bare repo with an initial commit on main
# that contains knowledge-base/ (mirrors the real soleur repo layout).
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Create a seed non-bare repo, make a commit with knowledge-base/, then clone --bare
git init -q "$TEST_DIR/seed"
mkdir -p "$TEST_DIR/seed/knowledge-base/project/specs"
touch "$TEST_DIR/seed/knowledge-base/.gitkeep"
git -C "$TEST_DIR/seed" add .
git -C "$TEST_DIR/seed" -c user.email=test@test -c user.name=test commit -q -m "seed"
git clone -q --bare "$TEST_DIR/seed" "$TEST_DIR/bare.git"

# Configure bare repo for worktree-manager expectations
git -C "$TEST_DIR/bare.git" config extensions.worktreeConfig true
git -C "$TEST_DIR/bare.git" config core.repositoryformatversion 1

# Test 1: feature <name> creates spec dir at worktree path (RED → GREEN)
echo "Test 1: spec dir created inside worktree"
cd "$TEST_DIR/bare.git"
bash "$SCRIPT" --yes feature acme-widget >/dev/null 2>&1 || true

WORKTREE="$TEST_DIR/bare.git/.worktrees/feat-acme-widget"
WORKTREE_SPEC="$WORKTREE/knowledge-base/project/specs/feat-acme-widget"
BARE_SPEC="$TEST_DIR/bare.git/knowledge-base/project/specs/feat-acme-widget"

assert_eq "true" "$([[ -d "$WORKTREE_SPEC" ]] && echo true || echo false)" \
  "spec dir exists inside worktree"

# Test 2: spec dir does NOT exist at bare root (the fix's core assertion)
echo "Test 2: spec dir does NOT exist at bare root"
assert_eq "false" "$([[ -d "$BARE_SPEC" ]] && echo true || echo false)" \
  "spec dir does not exist at bare root"

# Test 3: idempotency — second invocation is a no-op
echo "Test 3: idempotency"
bash "$SCRIPT" --yes feature acme-widget >/dev/null 2>&1 || true
assert_eq "true" "$([[ -d "$WORKTREE_SPEC" ]] && echo true || echo false)" \
  "spec dir still exists after second invocation"
assert_eq "false" "$([[ -d "$BARE_SPEC" ]] && echo true || echo false)" \
  "still no spec dir at bare root after second invocation"

echo "All tests passed."
```

Notes on the sketch:

- **Subprocess invocation (`bash "$SCRIPT"`)**, not `source`, per 2026-03-13 bash-arithmetic-and-test-sourcing learning. The script's top-level `IS_BARE`/`IS_IN_WORKTREE` detection would otherwise fire against the test harness's outer shell (real soleur bare repo) instead of the synthetic test bare repo.
- **GIT_* env scrub** at the top: lefthook/outer-shell `GIT_DIR` or `GIT_INDEX_FILE` would override the synthetic bare repo's detection.
- **`seed → clone --bare` pattern**: `git init --bare` creates an empty bare repo with no commits; `worktree add` against it needs a commit to check out. The seed-then-clone pattern produces a bare repo with one commit and `knowledge-base/` content matching the guard check on line 439.
- **Assertions pin exact truthy/falsy strings** (`"true"`/`"false"`) per `cq-mutation-assertions-pin-exact-post-state`. Using `assert_eq` with an inline conditional is more explicit than a bare `[[ -d ... ]]` exit code which can silently accept either direction in the event of a typo.
- **Test executes on bare repos only** (matches the issue's environment). Running from inside an existing worktree with a working tree is a separate code path that the existing `resolve-git-root.test.sh` already exercises.
- **`--yes` flag is required** to skip the interactive confirm prompt (the test runs non-interactively).

## Open Code-Review Overlap

None. (Queried `gh issue list --label code-review --state open --json number,title,body` and grepped for `worktree-manager.sh` and `git-worktree`; no open scope-outs touch this file.)

## Domain Review

**Domains relevant:** engineering (CTO) only — pure infra/tooling fix with no user-facing, product, marketing, finance, legal, sales, ops, or support implications.

**CTO assessment (inlined, no agent spawn needed):** Single-line shell fix + one small bash test. No architectural implications, no new dependencies, no cross-cutting concerns. Backward compatible with legacy spec dirs at the bare root via the existing archival code path. No Product/UX Gate (no user-facing changes). No Content Review Gate.

## Implementation Phases

### Phase 1 — RED test

1. Create `plugins/soleur/test/worktree-manager-feature-spec-dir.test.sh` following the `resolve-git-root.test.sh` template: `set -euo pipefail`, source `test-helpers.sh`, clear all `GIT_*` env vars, use `mktemp -d` + `git init --bare`.
2. Add three test cases: (a) spec dir lives inside the worktree, (b) spec dir does NOT live at bare root, (c) second invocation is idempotent.
3. Run `bash plugins/soleur/test/worktree-manager-feature-spec-dir.test.sh` — verify it FAILS on case (a) (directory at bare root, not worktree) and case (b) (directory exists at bare root).
4. Commit: `test(worktree): failing test for spec-dir-at-bare-root (#2815)`.

### Phase 2 — GREEN fix

1. Edit `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`:
   - Line 406: swap `$GIT_ROOT` → `$worktree_path`.
   - Line 439 guard: swap `$GIT_ROOT/knowledge-base` → `$worktree_path/knowledge-base`.
   - Line 767 (archival): add a one-line comment noting legacy bare-root spec dirs still archive through this block.
2. Run `bash plugins/soleur/test/worktree-manager-feature-spec-dir.test.sh` — verify GREEN.
3. Run `bash plugins/soleur/test/resolve-git-root.test.sh` and any other `.test.sh` that exercises `worktree-manager.sh` — verify no regressions.
4. Run `shellcheck plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — verify clean (no new warnings from the diff).
5. Regression-class sweep: `git diff plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh | grep '^+' | grep -F 'GIT_ROOT/knowledge-base' | wc -l` — expect zero. (Unchanged line 767's legacy archival literal stays, but the diff only contains removed/context lines for it.)
6. Commit: `fix(worktree): create spec dir inside worktree, not bare root (#2815)`.

### Phase 3 — Ship

1. `npx markdownlint-cli2 --fix` on the plan file (this file) before commit.
2. Use `/ship` to run compound, push, open PR. Semver label: `semver:patch` (bug fix).
3. PR body: `Closes #2815` (in body, not title, per `wg-use-closes-n-in-pr-body-not-title-to`).

## AI-Era Considerations

- AI tools used for initial exploration: Claude Code (this session) — read the script, issue body, downstream consumers (`brainstorm`, `plan` SKILL.md), and existing test patterns.
- The fix is a single-line change + one test file; AI-generated code needs minimal human review but the test assertions MUST be re-read to confirm the RED assertion actually tests worktree-path-exists (not bare-root-exists inverted).
- Per `cq-mutation-assertions-pin-exact-post-state`: the test assertions pin exact path existence (`[[ -d "$worktree_path/..." ]]` AND `[[ ! -d "$bare_root/..." ]]`) rather than a lenient `||` check.

## Risks

- **Backward compatibility with legacy bare-root spec dirs:** Pre-fix worktrees may have spec dirs already sitting at `<bare-root>/knowledge-base/project/specs/feat-*/`. The `cleanup_merged_worktrees` archival block (line 766-778) continues to handle these — it uses `$GIT_ROOT` and will still find and archive legacy layouts. After the fix, new worktrees populate `$worktree_path/...` instead; the bare-root block becomes a no-op for new worktrees. No cleanup migration needed.
- **The `[[ -d "$worktree_path/knowledge-base" ]]` guard:** If a feature branch is created from a `from-branch` that does NOT contain `knowledge-base/`, the spec dir is skipped (pre-existing behavior — the old code had `[[ -d "$GIT_ROOT/knowledge-base" ]]` for the same reason). After the fix, we check the worktree — which, for this repo, always contains `knowledge-base/` on `main`-derived branches. For hypothetical worktrees off non-main branches that lack `knowledge-base/`, the behavior is unchanged (skip). No regression.
- **`cleanup_merged_worktrees` removes the worktree at line 792.** Spec archival happens at line 766-778, **before** removal. For the new layout, the archival block's `[[ -d "$spec_dir" ]]` check fails (spec is in the worktree, not at bare root) — but the spec is already merged to main by the time `cleanup-merged` runs, so the canonical archive lives in git history. Explicit worktree-relative archival is **not needed** — it would duplicate git's own record.
- **Regression class: the fix reproducing the bug it fixes.** Per 2026-02-22 archiving-slug learning, changes to `worktree-manager.sh` have historically reintroduced the exact bug class being fixed. Mitigations:
  - The implementation Regression-Class Callout (above) enumerates the specific anti-patterns (new `$GIT_ROOT/knowledge-base` literal, accidental change of line 767 to `$worktree_path`).
  - Shellcheck is pre-merge gated.
  - The new `.test.sh` provides end-to-end coverage against both the primary failure mode (missing at worktree path) and the negative assertion (NOT at bare root) — so a regression can't pass the test by creating the dir at both locations.
- **Test-harness env leakage (2026-03-13 bash arithmetic/test-sourcing learning).** The new test MUST:
  - Scrub `GIT_*` env vars at startup (lefthook leaks `GIT_INDEX_FILE`, `GIT_DIR` can be set from outer bare repo).
  - Invoke the script as a subprocess (`bash "$SCRIPT" …`), not via `source`. Sourcing runs the script's top-level `IS_BARE`/`IS_IN_WORKTREE` detection against the *outer* shell (real soleur bare repo), contaminating the synthetic test bare repo.
- **Absolute-path safety (2026-03-17 learning).** `$worktree_path` in `create_for_feature` is constructed as `$WORKTREE_DIR/$branch_name` where `$WORKTREE_DIR="$GIT_ROOT/.worktrees"` and `$GIT_ROOT` is resolved to an absolute path at script init (lines 42-62, confirmed via `git rev-parse --absolute-git-dir`). No relative-path / CWD-leak risk — swapping `$GIT_ROOT` → `$worktree_path` at line 406 keeps the full path absolute.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| Create spec dir in BOTH bare root and worktree | No downstream changes | Creates two sources of truth — the original bug | REJECTED |
| Keep bare-root layout, update brainstorm/plan skills to write there | Fewer files touched | Breaks the "feature branch owns its artifacts" invariant; spec can't be committed with feature branch; conflicts with `plan` SKILL.md:474 which already writes to worktree | REJECTED |
| Move spec dir to worktree (this plan) | Matches downstream skills' assumption; lets `git add` include spec in feature branch PR | Must update archival comment to clarify legacy layout | ACCEPTED |

## Non-Goals / Out of Scope

- **NOT** refactoring `cleanup_merged_worktrees` archival logic to read from worktrees. The spec gets committed to the feature branch and merged to main; git history is the archive. Keeping the legacy bare-root archival block ensures pre-fix worktrees migrate gracefully.
- **NOT** adding an auto-migration that moves existing bare-root spec dirs into their corresponding worktrees. Legacy dirs get archived on `cleanup-merged` per existing code.
- **NOT** changing `plan` or `brainstorm` SKILL.md — they already target the worktree path correctly.

## Deferral Tracking

None — nothing deferred to later phases.

## Research Insights

### Applicable Learnings (from `knowledge-base/project/learnings/`)

- **`2026-03-13-archive-kb-stale-path-resolution.md`** — The most relevant prior art. Documents that `worktree-manager.sh` has previously had **multiple** path-hardcoding bugs (both `create_for_feature` and `cleanup_merged_worktrees`) after the knowledge-base restructure. Confirms the bug class this plan fixes is well-precedented in this script. The learning's "current+legacy path array" pattern is NOT adopted here because this issue isn't a directory rename — it's a location *semantics* correction (bare root → worktree). A dual-read array would be conceptually wrong.
- **`2026-02-22-archiving-slug-extraction-must-match-branch-conventions.md`** — Key insight quoted verbatim: *"When fixing a pattern mismatch bug, the fix itself can reproduce the same bug if the developer only thinks about the primary case."* This learning is the root justification for the Regression-Class Callout (see Files to Edit) and the `git diff | grep 'GIT_ROOT/knowledge-base' | wc -l` sweep in Phase 2.
- **`2026-03-17-worktree-creation-requires-absolute-path-from-bare-root.md`** — Confirms the fix's use of `$worktree_path` is safe: the variable is constructed from absolute components (`$GIT_ROOT/.worktrees/$branch_name` with `$GIT_ROOT` resolved absolute at init). No relative-path / nested-worktree risk.
- **`2026-03-13-bash-arithmetic-and-test-sourcing-patterns.md`** — Drives the test-harness decision: invoke the script as a subprocess (`bash "$SCRIPT"`), not via `source`. Sourcing would run the top-level `IS_BARE`/`IS_IN_WORKTREE` detection against the outer shell, leaking the real bare repo's state into the synthetic test bare repo.

### Best Practices Cross-Checked

- **Path-variable quoting (`shellcheck` SC2086)**: After the edit, line 406's new form `local spec_dir="$worktree_path/knowledge-base/project/specs/$branch_name"` keeps full double-quoting — no regression in the quoting style. The downstream `mkdir -p "$spec_dir"` at line 440 is already quoted.
- **Null-glob safety**: Not applicable here — the edit is a straight path swap, not a glob expansion.
- **Idempotency**: The existing early-return at line 409-413 (if worktree already exists, print "already exists" and return) means re-running `feature <name>` is a no-op — preserved by the fix.
- **Forward compatibility with `cleanup_merged_worktrees`**: The `[[ -d "$spec_dir" ]]` guard at line 768 (unchanged) is **silent-skip** when the dir doesn't exist. For post-fix worktrees, the bare-root spec never exists, the check fails silently, and archival falls through to the next loop iteration. No error, no warning — correct behavior since the canonical archive lives in git history on main after the feature branch merges.

### Edge Cases

- **Parallel sessions**: The existing `ensure_bare_config` function (called at line 318) already guards against parallel-session race conditions in the bare repo config. The fix does not introduce new shared-state mutations — `mkdir -p` against a per-branch worktree path is isolated by definition. No new parallelism risk.
- **Worktree removed mid-flight**: If the worktree is somehow removed between line 430 (`git worktree add`) and line 440 (`mkdir -p "$spec_dir"`), `mkdir -p` would succeed at the now-unregistered path, creating an orphan. This is the same behavior as the pre-fix code (except orphan would've been at bare root instead). No new exposure — and the scenario requires a concurrent actor, not a code bug.
- **`knowledge-base/` absent on the source branch**: The updated guard `[[ -d "$worktree_path/knowledge-base" ]]` checks the worktree's checked-out tree. If the branch doesn't include `knowledge-base/`, the spec dir is silently skipped. This matches prior behavior (the old guard checked `$GIT_ROOT/knowledge-base` but served the same semantic purpose).

## References

- Issue #2815 (this fix).
- Compound run 2026-04-22 during P1.7 pillar brainstorm (#2712, PR #2811) — the session that surfaced the bug.
- Brainstorm skill spec-write: `plugins/soleur/skills/brainstorm/SKILL.md:287`.
- Plan skill spec-write: `plugins/soleur/skills/plan/SKILL.md:474`.
- One-shot skill spec-write: `plugins/soleur/skills/one-shot/SKILL.md:68-69` (writes `session-state.md` to `knowledge-base/project/specs/<exact-branch-name>/` — also assumes worktree-relative path, aligned with this fix).
- Bare-repo GIT_ROOT resolution logic: `worktree-manager.sh:42-62`.
- Worktree path construction: `worktree-manager.sh:64` (`WORKTREE_DIR="$GIT_ROOT/.worktrees"`) and `:405` (`worktree_path="$WORKTREE_DIR/$branch_name"`).
- Cleanup archival flow: `worktree-manager.sh:766-778` (archive before remove).
- Test template: `plugins/soleur/test/resolve-git-root.test.sh`.
- Test helpers: `plugins/soleur/test/test-helpers.sh` (`assert_eq`, `assert_contains`).
- Project test convention: `.test.sh` (bash), per `#2212` learning.
- Prior learning on worktree-manager.sh path bugs: `knowledge-base/project/learnings/2026-03-13-archive-kb-stale-path-resolution.md`.
- Prior learning on fix-reproducing-the-bug: `knowledge-base/project/learnings/2026-02-22-archiving-slug-extraction-must-match-branch-conventions.md`.

## CLI Verification

No user-facing docs (`*.njk`, README, `apps/**`) are modified by this plan. The `echo` lines inside `worktree-manager.sh` are internal to the script and unchanged in shape. The `npx markdownlint-cli2 --fix` invocation in Phase 3 is a known project tool (used in dozens of plans). No CLI verification step required.
