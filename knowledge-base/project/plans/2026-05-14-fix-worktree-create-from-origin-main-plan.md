---
title: "fix(git-worktree): create new worktrees from origin/main directly to bypass local-main lock contention"
type: fix
date: 2026-05-14
issue: 3741
branch: feat-one-shot-3741
lane: single-domain
requires_cpo_signoff: false
---

# fix(git-worktree): create new worktrees from origin/main directly to bypass local-main lock contention

## Overview

`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh create` currently runs `git fetch origin <from>:<from>` (or `git checkout <from> && git pull` in non-bare repos) before `git worktree add`. Both of those commands try to mutate the local `<from>` ref. When ANY sibling worktree has that branch checked out, git aborts with `fatal: refusing to fetch into branch 'refs/heads/<from>' checked out at '...'` (bare path) or refuses to checkout the locked branch (non-bare path).

This is structurally inappropriate for a multi-session worktree-oriented tool: a worktree-create operation should NEVER depend on local-main being unlocked, because there is always a possibility another session has main checked out (`/soleur:postmerge`, `/soleur:ship`, a release-cut worktree, or a stale worktree parked on main).

The fix is to base new worktrees on `origin/<from>` directly:

- `git fetch origin <from>` (no refspec) — updates `refs/remotes/origin/<from>` without touching the local ref. NEVER fails on lock contention because no local ref is mutated.
- `git worktree add -b <new-branch> <path> origin/<from>` — creates the worktree from the remote-tracking ref. Always works regardless of local `<from>` state.

A new opt-in `--update-local-main` flag preserves the existing behavior (refspec fetch + `update-ref` fallback) for operators who want the local `main` ref kept in sync (e.g., release-cut workflows).

## User-Brand Impact

**If this lands broken, the user experiences:** Any session (`/soleur:one-shot`, `/soleur:work`, scheduled cron agent) that hits the locked-main path either fails fast (visible) or silently bases the new worktree on a stale `origin/main` (invisible — the worktree starts behind, all subsequent diffs are off, PRs from the worktree appear to revert merged work). The visible failure mode is what motivated this issue (#3741, 2026-05-13); the invisible failure mode is what the AC3 check exists to prevent.

**If this leaks, the user's data/workflow is exposed via:** No data exposure surface — this is operator-tooling internal to the soleur plugin. Worst case is wasted operator time + a confusing PR-state.

**Brand-survival threshold:** none — local developer tooling, no third-party data flow, no production write surface.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1:** `worktree-manager.sh create <name>` succeeds when any sibling worktree has `main` checked out. Verified by `plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh` (AC7).
- [ ] **AC2:** Local `main` ref is unaffected by the default `create` path. The new test asserts `git rev-parse refs/heads/main` returns the same SHA before and after `worktree-manager.sh create` (no advancement, no rollback).
- [ ] **AC3:** Created worktree HEAD matches `refs/remotes/origin/main` HEAD at the moment of fetch. The new test asserts `git -C <worktree> rev-parse HEAD == git rev-parse refs/remotes/origin/main`.
- [ ] **AC4:** Existing setup steps run unchanged on the new worktree: `ensure_bare_config`, `ensure_worktree_identity`, `copy_env_files`, `install_deps`, lease acquisition (where applicable). Verified by inspection — the diff touches only `update_branch_ref` and the `git worktree add ... <ref>` argument, NOT the post-create setup block.
- [ ] **AC5:** The `Updating main...` log line is replaced with `Fetching latest origin/main...` (or removed for the new code path). The `--update-local-main` opt-in path keeps the old `Updating main...` line.
- [ ] **AC6:** `worktree-manager.sh --update-local-main create <name>` (or `worktree-manager.sh create <name> --update-local-main` — see Implementation Phase 2 for placement decision) runs the existing behavior verbatim: `git fetch origin main:main` then `update-ref` fallback. The 2026-04-13 stale-fallback fix (`git update-ref refs/heads/main origin/main`) MUST remain intact in this path.
- [ ] **AC7:** Test added at `plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh`. Exercises: (a) sibling worktree holds `main` → `create` succeeds, (b) local `main` SHA unchanged after create, (c) new worktree HEAD == `origin/main` HEAD, (d) `--update-local-main` flag advances local `main` when local is behind.
- [ ] **AC8:** New test file wired into `scripts/test-all.sh` (or its discovery glob extended) so it actually runs in CI. The current iterator at `scripts/test-all.sh:43` only globs `plugins/soleur/test/*.test.sh` — skill-nested tests under `plugins/soleur/skills/*/test/` are NOT picked up. See "Research Reconciliation — Spec vs. Codebase" below.
- [ ] **AC9:** `bash plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh` passes locally on the feature branch.
- [ ] **AC10:** `bash scripts/test-all.sh` passes locally (no regression in sibling suites).
- [ ] **AC11:** `SKILL.md` Sharp Edges section updated: the existing entry at line 312 ("In bare repos with multiple worktrees, `git fetch origin branch:branch` fails when the target branch is checked out in any worktree") is amended to note this is now bypassed by default in `create`; the entry remains as documentation of the underlying git behavior.
- [ ] **AC12:** PR body includes `Closes #3741` (not `Ref` — this is application-layer behavior change that ships at merge, no post-merge operator step).

### Post-merge (operator)

- None required. The change is self-contained to the script + test + SKILL.md doc.

## Files to Edit

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — modify `update_branch_ref()` (lines 245-265) to split into two responsibilities, OR introduce a new helper `fetch_origin_branch()`; modify `create_worktree()` (lines 379-457) and `create_for_feature()` (lines 459-560) to pass `origin/$from_branch` to `git worktree add` by default; add `--update-local-main` flag parsing alongside `--yes` (line 1379-1389); update `show_help()` (lines 1324-1378) to document the new flag.
- `plugins/soleur/skills/git-worktree/SKILL.md` — update the `create` command docs (lines 86-107) to describe the new default behavior and the `--update-local-main` opt-in; amend the Sharp Edges entry at line 312 to note default-bypass.
- `scripts/test-all.sh` — extend the bash-test discovery loop (line 43) to also iterate `plugins/soleur/skills/*/test/*.test.sh` so the new test (and the pre-existing `lease-protects-active.test.sh`) run in CI.

## Files to Create

- `plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh` — new test file. Mirrors the structure of `plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` (fake bare repo + upstream + two worktrees + lease setup). Tests 4 invariants: (a) create succeeds when sibling holds main, (b) local main unchanged, (c) worktree HEAD == origin/main, (d) `--update-local-main` advances local main.

## Research Reconciliation — Spec vs. Codebase

| Spec / Issue Claim | Reality | Plan Response |
|---|---|---|
| "Replace the current logic at ~`scripts/worktree-manager.sh:960-1000`" (issue body) | Lines 960-1000 are inside `cleanup_merged_worktrees()`, NOT the `create` path. The `create`-path fetch happens via `update_branch_ref()` at line 245-265 (called from `create_worktree:425` and `create_for_feature:488`). | Plan targets `update_branch_ref()` and its callers in `create_worktree()` / `create_for_feature()`. The `cleanup_merged_worktrees()` block at line 960-1000 is OUT OF SCOPE — that path is about advancing local main AFTER cleanup, which is a legitimate operation the user wants. Touching it would expand scope to "stop advancing local main entirely" which the issue's Scope-Out section explicitly defers. |
| "Current: `git fetch origin main:main 2>/dev/null && git worktree add ... main`" (issue body Proposed Fix) | The current `create` path calls `update_branch_ref` (which has TWO branches: bare + non-bare) and then `git worktree add -b ... <from_branch>`. Bare branch fails first at the refspec fetch (the issue's symptom); non-bare branch fails at `git checkout`. | Plan addresses BOTH branches. The non-bare branch is rarely hit in current soleur (the project repo IS bare per `git rev-parse --is-bare-repository == true`), but the fix MUST cover both to avoid future regression on contributor forks. |
| "Test added at `plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh` (AC7)" | The directory exists (`lease-protects-active.test.sh` lives there) but `scripts/test-all.sh:43` only iterates `plugins/soleur/test/*.test.sh`. The pre-existing `lease-protects-active.test.sh` is currently NOT being run in CI. | Plan adds AC8 to wire the new test into `scripts/test-all.sh` AND surfaces the pre-existing gap. The wiring extension (`for f in plugins/soleur/test/*.test.sh plugins/soleur/skills/*/test/*.test.sh`) covers both files in one edit. |
| "From learning 2026-04-13: bare-repo refspec-fetch fix added `update-ref` fallback" | Verified at `worktree-manager.sh:255-261`. The 2026-04-13 fix is intact and is the load-bearing behavior for the `--update-local-main` opt-in path. | Plan explicitly preserves this code in the opt-in path. AC6 names it. |

## Implementation Phases

### Phase 0 — Preconditions and verification

- [ ] `git rev-parse --is-bare-repository` returns `true` (the project repo IS bare; the new path is the production path).
- [ ] Sanity-run the test reproducer in `/tmp` to confirm `git fetch origin main` (no refspec) does NOT mutate local main, and `git worktree add origin/main` succeeds when main is locked. **DONE at plan time** — see verification log in this session's Research Insights.
- [ ] Confirm `--update-local-main` is not already a recognized flag (`grep -n update-local-main plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` returns empty). **DONE at plan time.**

### Phase 1 — RED: write the failing test

Create `plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh` with the following test cases (mirror the `lease-protects-active.test.sh` shape — fake bare repo + upstream + worktrees, no Docker, no network):

```bash
#!/usr/bin/env bash
# 2026-05-14 reproducer: worktree-manager.sh create must succeed when a
# sibling worktree holds main checked out (issue #3741).
#
# Plan: knowledge-base/project/plans/2026-05-14-fix-worktree-create-from-origin-main-plan.md
#
# Run via:  bash plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
WM="$REPO_ROOT/plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"

PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Stand up upstream + local bare clone (mirrors the soleur bare-repo layout) ---
UPSTREAM="$TMP/upstream.git"
git init --bare -b main "$UPSTREAM" >/dev/null
SEED="$TMP/seed"
git clone "$UPSTREAM" "$SEED" >/dev/null 2>&1
( cd "$SEED" && git -c user.email=t@t -c user.name=t commit --allow-empty -m seed >/dev/null && git push origin main >/dev/null 2>&1 )
rm -rf "$SEED"

LOCAL="$TMP/local.git"
git init --bare -b main "$LOCAL" >/dev/null
( cd "$LOCAL" && git remote add origin "$UPSTREAM" && git fetch origin main:main >/dev/null 2>&1 )

# Advance upstream so origin/main is ahead of local main
SEED2="$TMP/seed2"
git clone "$UPSTREAM" "$SEED2" >/dev/null 2>&1
( cd "$SEED2" && git -c user.email=t@t -c user.name=t commit --allow-empty -m "upstream-advance" >/dev/null && git push origin main >/dev/null 2>&1 )
rm -rf "$SEED2"

# --- Setup: sibling worktree A holds main checked out ---
mkdir -p "$TMP/.worktrees"
( cd "$LOCAL" && git worktree add "$TMP/.worktrees/feat-a" main >/dev/null 2>&1 )

LOCAL_MAIN_BEFORE=$(git -C "$LOCAL" rev-parse refs/heads/main)

# --- AC1: create succeeds when sibling holds main ---
(
  cd "$LOCAL"
  bash "$WM" --yes create feat-bar >/tmp/wt-out.$$ 2>&1
) && pass "AC1: create succeeds with sibling holding main" || fail "AC1: create FAILED (output: $(cat /tmp/wt-out.$$))"

# --- AC2: local main unchanged ---
LOCAL_MAIN_AFTER=$(git -C "$LOCAL" rev-parse refs/heads/main)
[[ "$LOCAL_MAIN_BEFORE" == "$LOCAL_MAIN_AFTER" ]] \
  && pass "AC2: local main SHA unchanged ($LOCAL_MAIN_BEFORE)" \
  || fail "AC2: local main advanced from $LOCAL_MAIN_BEFORE to $LOCAL_MAIN_AFTER (should be unchanged)"

# --- AC3: worktree HEAD == origin/main HEAD ---
WT_HEAD=$(git -C "$TMP/.worktrees/feat-bar" rev-parse HEAD 2>/dev/null || echo "MISSING")
ORIGIN_MAIN=$(git -C "$LOCAL" rev-parse refs/remotes/origin/main)
[[ "$WT_HEAD" == "$ORIGIN_MAIN" ]] \
  && pass "AC3: worktree HEAD == origin/main ($WT_HEAD)" \
  || fail "AC3: worktree HEAD ($WT_HEAD) != origin/main ($ORIGIN_MAIN)"

# --- AC6: --update-local-main advances local main ---
# Add yet another upstream commit
SEED3="$TMP/seed3"
git clone "$UPSTREAM" "$SEED3" >/dev/null 2>&1
( cd "$SEED3" && git -c user.email=t@t -c user.name=t commit --allow-empty -m "upstream-advance-2" >/dev/null && git push origin main >/dev/null 2>&1 )
rm -rf "$SEED3"

# Release main lock by removing the sibling worktree (otherwise refspec fetch fails by design)
( cd "$LOCAL" && git worktree remove --force "$TMP/.worktrees/feat-a" >/dev/null 2>&1 )

LOCAL_MAIN_BEFORE_UPDATE=$(git -C "$LOCAL" rev-parse refs/heads/main)
(
  cd "$LOCAL"
  bash "$WM" --yes --update-local-main create feat-baz >/tmp/wt-out2.$$ 2>&1
) && pass "AC6a: --update-local-main create succeeded" || fail "AC6a: --update-local-main create failed (output: $(cat /tmp/wt-out2.$$))"

LOCAL_MAIN_AFTER_UPDATE=$(git -C "$LOCAL" rev-parse refs/heads/main)
[[ "$LOCAL_MAIN_AFTER_UPDATE" != "$LOCAL_MAIN_BEFORE_UPDATE" ]] \
  && pass "AC6b: --update-local-main advanced local main" \
  || fail "AC6b: --update-local-main did NOT advance local main"

rm -f /tmp/wt-out.$$ /tmp/wt-out2.$$
echo
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
```

Run the test — it MUST fail on the unmodified script. Expected failures: AC1 fails with `fatal: refusing to fetch into branch 'refs/heads/main'`; AC2/AC3 do not execute.

### Phase 2 — GREEN: minimal fix

**Step 2.1 — Add `--update-local-main` flag parsing.** Extend the flag-parse loop at lines 1379-1389:

```bash
UPDATE_LOCAL_MAIN=false   # add at line ~55 alongside YES_FLAG=false

# In the flag-parse loop (lines 1379-1389):
for arg in "$@"; do
  if [[ "$arg" == "--yes" ]]; then
    YES_FLAG=true
  elif [[ "$arg" == "--update-local-main" ]]; then
    UPDATE_LOCAL_MAIN=true
  else
    args+=("$arg")
  fi
done
```

**Step 2.2 — Introduce a `fetch_origin_branch()` helper and refactor `update_branch_ref()`.** The cleanest design:

```bash
# Fetch origin/<branch> without mutating the local <branch> ref.
# Safe to run while the local <branch> is checked out in another worktree —
# fetches refs/remotes/origin/<branch> and FETCH_HEAD only.
# Returns the SHA of origin/<branch> on stdout (caller can echo for AC3 verification).
fetch_origin_branch() {
  local branch="$1"
  echo -e "${BLUE}Fetching latest origin/$branch...${NC}"
  if git fetch origin "$branch" 2>/dev/null; then
    git rev-parse "refs/remotes/origin/$branch"
  else
    echo -e "${YELLOW}Warning: Could not fetch origin/$branch — using cached ref${NC}"
    git rev-parse "refs/remotes/origin/$branch" 2>/dev/null || echo ""
  fi
}
```

Keep `update_branch_ref()` exactly as-is (it remains the implementation of the opt-in path AND the implementation of `cleanup_merged_worktrees`'s post-cleanup main advancement, which is unchanged).

**Step 2.3 — Modify `create_worktree()` (line ~379).** Replace lines 424-432:

```bash
  # OLD:
  update_branch_ref "$from_branch"
  mkdir -p "$WORKTREE_DIR"
  ensure_gitignore
  echo -e "${BLUE}Creating worktree...${NC}"
  git worktree add -b "$branch_name" "$worktree_path" "$from_branch"

  # NEW:
  mkdir -p "$WORKTREE_DIR"
  ensure_gitignore
  local base_ref
  if [[ "$UPDATE_LOCAL_MAIN" == "true" ]]; then
    update_branch_ref "$from_branch"
    base_ref="$from_branch"
  else
    fetch_origin_branch "$from_branch" >/dev/null
    base_ref="origin/$from_branch"
  fi
  echo -e "${BLUE}Creating worktree from $base_ref...${NC}"
  git worktree add -b "$branch_name" "$worktree_path" "$base_ref"
```

Apply the identical edit to `create_for_feature()` at lines 487-496.

**Step 2.4 — Confirm `verify_worktree_created()` still works.** The verify helper at line 156 takes `$from_branch` for diagnostic-hint messages only; it doesn't enforce the ref. No change needed. Diagnostic hints can reference the literal `$base_ref` (cosmetic — out of scope for AC; if it falls through naturally with the local variable, fine).

**Step 2.5 — Update `show_help()`.** Add to the Global Flags block:

```
  --yes                               Auto-confirm all prompts
  --update-local-main                 (create only) Also update local main ref to latest
                                      origin/main. Default: only refs/remotes/origin/main
                                      is updated; local main is never mutated.
```

**Step 2.6 — Update SKILL.md docs.** Edit `plugins/soleur/skills/git-worktree/SKILL.md`:

- Update `### create` section (lines 86-107) to describe the new default ("worktrees are created from `origin/main` directly; local `main` is NOT touched") and document `--update-local-main` for operators who want the local ref advanced.
- Amend Sharp Edges entry at line 312 (the `git fetch origin branch:branch` failure mode): append "— bypassed by default in `worktree-manager.sh create` since 2026-05-14 (#3741), which now bases new worktrees on `refs/remotes/origin/<from>` directly. The refspec-fetch path still runs when `--update-local-main` is passed."

**Step 2.7 — Wire the new test into `scripts/test-all.sh`.** Replace line 43:

```bash
# OLD:
for f in plugins/soleur/test/*.test.sh; do

# NEW:
for f in plugins/soleur/test/*.test.sh plugins/soleur/skills/*/test/*.test.sh; do
```

This is a one-line edit that picks up BOTH the new `create-from-origin-main.test.sh` AND the pre-existing `lease-protects-active.test.sh` (which has been silently not-running). If the pre-existing test fails when first picked up, that is a SEPARATE issue (the plan does NOT cover fixing it — see Scope-Out); document the result in the PR body and file a follow-up issue.

### Phase 3 — REFACTOR

- Re-read the diff for unused locals, stale comments, and any logging-output drift between the two paths.
- Verify the `Updating main...` → `Fetching latest origin/main...` log line swap actually happens (AC5).

### Phase 4 — Verify ACs

- [ ] `bash plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh` passes locally.
- [ ] `bash scripts/test-all.sh` passes locally.
- [ ] `grep -n "git fetch origin main:main\|git checkout main" plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` shows only:
  - The `cleanup_merged_worktrees()` site (line ~972) — UNCHANGED, this is the legitimate post-cleanup main-advancement path.
  - The `update_branch_ref()` site (line ~250) — UNCHANGED, now invoked only when `--update-local-main` is passed (AC6).
- [ ] `grep -n "origin/$from_branch\|origin/\$from_branch\|base_ref" plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` shows the new code path in both `create_worktree` and `create_for_feature`.

### Phase 5 — PR

- Commit with conventional title: `fix(git-worktree): base new worktrees on origin/main to bypass local-main lock`
- PR body includes `Closes #3741` and a `## Changelog` section with `### Fixed` entry.
- `semver:patch` label (bug fix, no new agent/skill).
- Labels: `domain/engineering`, `priority/p2-medium`, `type/feature` (carried over from issue).

## Risks

### R1: Tracking-branch semantics change
**Risk:** New worktrees are set up to track `origin/main` (via `branch 'feat-X' set up to track 'origin/main'`) rather than local `main`. Operators who run `git pull` from inside the worktree will now pull from `origin/main` directly. Verified in preflight (`/tmp` repro) — `git worktree add -b feat-b origin/main` produces `branch 'feat-b' set up to track 'origin/main'`.
**Mitigation:** Acceptable — feature branches typically rebase/merge from `origin/main` anyway. The issue body's Risks section explicitly accepts this.

### R2: Stale `origin/<from>` ref
**Risk:** If `git fetch origin <from>` fails silently (network error, auth issue), the new worktree could be based on a stale `refs/remotes/origin/<from>`.
**Mitigation:** Echo the base SHA at create time so operators can verify against `git ls-remote origin <from>`. AC3 covers verification in the test. Add a one-line log: `echo "Worktree based on origin/$from_branch @ $base_sha"` after the `git worktree add` call.

### R3: Non-bare-repo regression (contributor forks)
**Risk:** A contributor who clones the repo as non-bare runs `worktree-manager.sh create` and hits the OTHER branch of `update_branch_ref` (the `git checkout && git pull` branch at line 262). The default path now bypasses `update_branch_ref` entirely, so this is fine — `fetch_origin_branch` works identically in bare and non-bare repos.
**Mitigation:** AC1's test runs against a bare repo (matching the production layout). The non-bare path is not exercised by the test but is the same `git fetch origin main` + `git worktree add origin/main` calls, which work identically in both modes.

### R4: Pre-existing `lease-protects-active.test.sh` may have been silently broken
**Risk:** Wiring the new bash-test discovery in `scripts/test-all.sh` (AC8) will also pick up `lease-protects-active.test.sh` for the first time in CI. If that test fails on main HEAD (it has not been run in CI before), the PR appears to regress something unrelated.
**Mitigation:** Run `bash plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` locally BEFORE the wiring change to confirm it passes. If it fails, the test-all.sh wiring (AC8) is split into a follow-up PR with `lease-protects-active.test.sh` fix; this PR's AC8 is then scoped to "add the new test to the loop" only.

### R5: `--update-local-main` flag placement ambiguity
**Risk:** `--update-local-main` can be parsed as either a global flag (before subcommand) or a subcommand flag (after `create <name>`). The current `--yes` flag is parsed globally (before subcommand dispatch). Inconsistency confuses operators.
**Mitigation:** Parse `--update-local-main` in the same loop as `--yes` (global, position-independent). This is the simpler design — argv-order doesn't matter. Documented in `show_help()`.

### R6: `git worktree add origin/<from>` syntax compatibility
**Risk:** Older git versions might not accept a remote-tracking ref as the starting point.
**Verified:** This has been standard git behavior since at least git 2.5. The soleur repo uses git >= 2.30 (required for `git worktree repair`). No constraint.

## Domain Review

**Domains relevant:** none

No cross-domain implications — infrastructure/tooling change scoped to one shell script + one test + one doc edit + one CI-runner extension. No product surface, no legal/compliance surface, no marketing surface, no data flow. Lane: `single-domain` (engineering).

## Test Scenarios

### Scenario A — Sibling worktree holds main (the issue's exact repro)

1. Set up: `feat-a` worktree with `main` checked out.
2. Run: `worktree-manager.sh --yes create feat-b` from the bare repo root or another worktree.
3. Expected:
   - Exit 0.
   - Output contains `Fetching latest origin/main...` (NOT `Updating main...`).
   - `git -C .worktrees/feat-b rev-parse HEAD == git rev-parse refs/remotes/origin/main`.
   - `git rev-parse refs/heads/main` unchanged.

### Scenario B — No sibling holds main (the common case)

1. Set up: no other worktrees, local main behind by 2 commits.
2. Run: `worktree-manager.sh --yes create feat-c`.
3. Expected:
   - Exit 0.
   - `git -C .worktrees/feat-c rev-parse HEAD == git rev-parse refs/remotes/origin/main` (NEW commits).
   - `git rev-parse refs/heads/main` STILL behind by 2 (NOT advanced — this is by design).

### Scenario C — Operator wants local main updated

1. Set up: same as B (local main behind).
2. Run: `worktree-manager.sh --yes --update-local-main create feat-d`.
3. Expected:
   - Exit 0.
   - `git rev-parse refs/heads/main` advanced to match `origin/main`.
   - The old `Updating main...` log line is emitted.
   - 2026-04-13 `update-ref` fallback path is still reachable (covered by existing manual smoke).

### Scenario D — `git fetch origin main` fails (network outage)

1. Set up: simulate by unsetting `origin` remote between worktrees.
2. Run: `worktree-manager.sh --yes create feat-e`.
3. Expected:
   - Warning emitted: `Could not fetch origin/main — using cached ref`.
   - Worktree created from the cached `refs/remotes/origin/main` (may be stale but works).
   - Exit 0 (do NOT block worktree creation on network — degradation is acceptable, the warning is the operator signal).

### Scenario E — Non-bare contributor fork

Not covered by the test (the test uses a bare repo). Documented as out-of-scope for automated verification; the implementation parity is verified by inspection (same `fetch_origin_branch` helper called in both bare and non-bare paths).

## Open Code-Review Overlap

Queried open `code-review` labeled issues for matches against the planned `Files to Edit`:

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in \
  "plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh" \
  "plugins/soleur/skills/git-worktree/SKILL.md" \
  "scripts/test-all.sh" \
  "plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh"; do
  echo "--- $path ---"
  jq -r --arg path "$path" '
    .[] | select(.body // "" | contains($path))
    | "#\(.number): \(.title)"
  ' /tmp/open-review-issues.json
done
```

**Result:** None (to be re-verified inline during `/work` Phase 0). If matches surface, the planner's default disposition is **Acknowledge** unless the overlap directly contradicts an AC of this plan — in which case fold-in and add `Closes #<N>` to the PR body.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- The `--update-local-main` flag parser MUST be added to the SAME global-flag loop as `--yes` (line 1379-1389). Adding it inside a subcommand parser would change the flag's positional semantics relative to `--yes` and surprise operators.
- The Sharp Edges entry at SKILL.md:312 is load-bearing documentation of the underlying git refspec-fetch behavior — it must be amended (note default-bypass) NOT removed. The git behavior is still relevant for the `--update-local-main` opt-in path and for any future tool that ships a similar refspec-fetch.
- `scripts/test-all.sh`'s test-discovery glob extension (`plugins/soleur/skills/*/test/*.test.sh`) WILL also pick up the pre-existing `lease-protects-active.test.sh`. If that test fails on main HEAD (it has not been CI-run before), the test-all.sh wiring change becomes a separate-PR concern. Verify local-pass BEFORE merging this PR's AC8.
- The `fetch_origin_branch` helper deliberately does NOT mutate any local ref. Do NOT add an "as a convenience" `update-ref` call to it — that would silently bring back the lock-contention class via a different path. Locally-advancing main is an opt-in operation, full stop.
- When the issue body says "Replace the current logic at ~`scripts/worktree-manager.sh:960-1000`", trust the codebase line ranges in `Files to Edit` over the issue's line citation. The 960-1000 block is `cleanup_merged_worktrees`, NOT the `create` path. Following the issue line citation literally would edit the wrong function and ship a no-op for the user's actual symptom.

## Non-Goals (Scope-Outs)

These are listed in the issue body and inherited verbatim:

- **Cleanup of stale worktrees parked on main** — separate hygiene concern. Worktrees that intentionally or accidentally sit on `main` are a workflow issue, not a `create`-path issue.
- **Locking mechanism for cross-session main-update coordination** — overengineering for the actual failure mode. The fix is to make `create` not depend on local-main at all; cross-session main-update coordination becomes irrelevant.
- **Branch-tracking for non-main base branches** — the issue scope is the `main` case. The proposed fix generalizes naturally (the code uses `$from_branch` throughout) but the test scenario and ACs are scoped to `main` to avoid blow-up.
- **Fix the pre-existing `lease-protects-active.test.sh` if it fails on main HEAD** — separate concern. The AC8 wiring change merely starts running it; if it surfaces a regression, file a follow-up issue.

## Verification Steps (post-implementation)

1. `bash plugins/soleur/skills/git-worktree/test/create-from-origin-main.test.sh` → exit 0.
2. `bash plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` → exit 0 (pre-existing test, sanity).
3. `bash scripts/test-all.sh` → exit 0, suite count increased by ≥2 (the new test + the now-included `lease-protects-active.test.sh`).
4. Manual reproduction of the issue's exact scenario:
   ```bash
   # In a second worktree, hold main:
   cd .worktrees/some-existing-feat && git checkout main
   # In a third worktree (or the bare root), run create:
   bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create feat-verify
   # Expected: success, no "fatal: refusing to fetch into branch" error.
   ```

## Source

- GitHub issue: #3741 (filed 2026-05-13).
- Surfaced during `/soleur:one-shot #3724` invocation (D1 prereq of #2725 incident-commander skill).
- Builds on: 2026-04-13 fix at PR (origin/main fallback stale-ref) — `update-ref` fallback preserved in `--update-local-main` opt-in path.
- Related learning files:
  - `knowledge-base/project/learnings/2026-04-13-worktree-manager-origin-main-fallback-stale-ref.md` — same code surface, prior fix.
  - `knowledge-base/project/learnings/2026-03-23-stale-index-blocks-main-pull-in-worktree-manager.md` — sibling failure mode in the non-bare branch of `update_branch_ref`.
  - `knowledge-base/project/learnings/2026-04-21-concurrent-cleanup-merged-wipes-active-worktree.md` — concurrent-session class that this fix structurally addresses for the `create` path.
