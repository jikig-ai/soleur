---
title: "fix: Bun test runner crash on missing dependencies"
type: fix
date: 2026-03-18
---

## Enhancement Summary

**Deepened on:** 2026-03-18
**Sections enhanced:** 5
**Research sources:** Bun official docs (Context7), worktree-manager.sh code review, institutional learnings (3 relevant), CI workflow analysis

### Key Improvements

1. Corrected `bunfig.toml` config -- `root = "."` is a no-op (already the default); replaced with actionable comment-only config since Bun has no test-discovery exclusion mechanism
2. Identified that `scheduled-ship-merge.yml` and `scheduled-bug-fixer.yml` also use setup-bun without pinning -- should be pinned for consistency
3. Provided concrete implementation for `install_deps()` function in worktree-manager.sh, positioned after `copy_env_files` in both `create_worktree()` and `create_for_feature()`
4. Added edge case: `bun` may not be on PATH in all environments -- the dep install must degrade gracefully

### New Considerations Discovered

- The prior learning `2026-02-26-worktree-missing-node-modules-silent-hang.md` already recommended adding `npm install` to worktree creation -- this fix finally implements that recommendation
- Bun's `root` test config option defaults to `.` (current directory), so setting it explicitly is redundant -- the only value is as documentation

# fix: Bun test runner crash on missing dependencies

## Overview

`bun test` (v1.3.5) crashes with a segfault (`pas panic: deallocation did fail ... Large heap did not find object`) when test files import modules that are not installed. This occurs reliably in fresh git worktrees where `bun install` has not been run, and intermittently in other contexts where dependencies are partially missing.

The original hypothesis was that Bun recursively discovers duplicate test files inside `.worktrees/` directories. Investigation disproved this: `.worktrees/` is at the bare repo level, not inside individual worktree checkouts. The actual root cause is a Bun 1.3.5 bug where the test runner segfaults instead of reporting missing module errors during test file loading.

### Research Insights

**Bun test discovery behavior (from official docs):**

- Bun ignores `node_modules` directories and hidden directories (starting with `.`) by default during test discovery
- The only discovery-scoping option is `[test] root` in `bunfig.toml`, which defaults to `.` (current directory)
- There is NO `pathIgnorePatterns` or `testPathIgnorePatterns` equivalent for test discovery (unlike Jest)
- `coveragePathIgnorePatterns` only affects coverage reporting, not file discovery

**Crash characteristics observed:**

- RSS spikes to 1.09GB before the allocator panic, suggesting Bun attempts to load/parse all discovered files before failing
- The crash is deterministic when `node_modules/` is absent (100% reproduction rate)
- After `bun install`, tests pass reliably across multiple consecutive runs (0% failure rate)

## Problem Statement

**Crash reproduction (deterministic):**

```bash
# In a fresh worktree (no node_modules)
bun test
# => [PID] pas panic: deallocation did fail at 0x100...: Large heap did not find object
# RSS spikes to 1.09GB before crash
```

**After `bun install`, tests pass reliably** -- 1136 tests across 13 files in ~3 seconds.

**Impact:**

- Every new worktree starts without `node_modules`, so the first `bun test` always crashes
- CI is unaffected (runs `bun install` before `bun test` in `ci.yml`)
- Developers lose time debugging a segfault that is actually "missing dependencies"
- The crash report URL points to a Bun internal bug, not user error

## Root Cause Analysis

1. **Bun 1.3.5 allocator bug:** When test files import unresolvable modules, Bun's heap allocator panics instead of producing a clean error message. This is a known class of Bun bugs fixed in later versions.

2. **Missing dependency guard:** There is no pre-flight check before `bun test` to ensure dependencies are installed. The root `package.json` has devDependencies (`@11ty/eleventy`, `markdown-it`, `yaml`) that test files transitively depend on.

3. **Worktree isolation:** Git worktrees share the git object store but not the working tree. Each worktree needs its own `bun install`. The existing learning `2026-02-26-worktree-missing-node-modules-silent-hang.md` documents a similar issue but for a different symptom (silent hang, not crash).

### Research Insights

**Institutional learnings applied:**

- `2026-02-26-worktree-missing-node-modules-silent-hang.md`: Documents that `npx` with missing local packages silently hangs in non-TTY contexts. That learning explicitly recommended: "the `worktree-manager.sh feature` subcommand could run `npm install` (or detect `package.json` and warn) after creating the worktree." This fix implements that long-standing recommendation.
- `2026-02-12-bun-coverage-threshold-config.md`: Confirms `bunfig.toml` is directory-scoped and Bun picks it up automatically from the working directory. The root config will not conflict with `apps/telegram-bridge/bunfig.toml` -- Bun merges the configs.
- `2026-03-03-no-unified-test-runner-from-repo-root.md`: Documents that CI runs both test suites separately with different `working-directory` values. The root `bun test` is a developer convenience, not the CI path.

**Why the original `.worktrees/` hypothesis was wrong:**

- This repo uses `core.bare=true` with `.worktrees/` at the bare repo root
- Individual worktree checkouts at `.worktrees/feat-<name>/` do NOT contain a nested `.worktrees/` directory
- Even if they did, Bun's default behavior ignores dot-prefixed directories during test discovery

## Proposed Solution

### 1. Create root `bunfig.toml` as configuration anchor

Add a root-level `bunfig.toml` as a standard location for future test configuration. Since Bun already defaults `root` to `.` and already ignores dot-directories, the config serves primarily as documentation and a hook for future settings.

**File: `bunfig.toml` (repo root)**

```toml
[test]
# Bun test discovery notes:
# - Default root is "." (current directory) -- no override needed
# - Bun ignores dot-directories (.worktrees, .git, etc.) by default
# - No pathIgnorePatterns exists for test discovery (only coveragePathIgnorePatterns)
# - Per-app configs (e.g., apps/telegram-bridge/bunfig.toml) are merged automatically
```

### Research Insights

**Best practices for `bunfig.toml`:**

- Keep the root config minimal; per-app configs handle coverage thresholds and app-specific settings
- Bun merges configs: a root `bunfig.toml` does NOT override `apps/telegram-bridge/bunfig.toml` -- both apply when running from their respective directories
- Setting `root = "."` is a no-op since that's already the default. Omitting it avoids confusion about what it actually changes.

**Edge case: `root` option semantics:**

- `root = "."` means "start discovery from the directory containing `bunfig.toml`" -- which is the default behavior
- `root = "test"` would restrict discovery to only the `test/` directory, which would miss `apps/*/test/` and `plugins/soleur/test/`
- For a monorepo with test files in multiple directories, the only correct `root` is `.` (the default)

### 2. Upgrade Bun from 1.3.5 to 1.3.11

Update the CI workflow to pin the latest stable version instead of `latest` (which is already 1.3.11). Pinning prevents surprise breakage from future Bun releases.

**File: `.github/workflows/ci.yml`**

```yaml
- name: Setup Bun
  uses: oven-sh/setup-bun@3d267786b128fe76c2f16a390aa2448b815359f3 # v2.1.2
  with:
    bun-version: "1.3.11"
```

### Research Insights

**CI version pinning best practices:**

- `bun-version: latest` in CI is a reproducibility risk -- a Bun release with breaking changes could fail CI for unrelated PRs
- Pin to a specific version and upgrade intentionally via dedicated PRs
- The SHA-pinned action ref (`@3d267786b...`) is good practice per `2026-02-21-github-actions-workflow-security-patterns.md` (already in place)

**Other workflows to consider:**

- `scheduled-ship-merge.yml` uses `setup-bun` without `bun-version` (defaults to `latest`)
- `scheduled-bug-fixer.yml` uses `setup-bun` without `bun-version` (defaults to `latest`)
- These workflows don't run `bun test`, so the crash doesn't affect them, but pinning for consistency is recommended as a separate follow-up

**Local Bun upgrade:**

- Local Bun is 1.3.5 (installed via system package manager or `bun upgrade`)
- Run `bun upgrade` locally to get 1.3.11 -- this may independently fix the crash, but the worktree dep-install guard is still needed as defense-in-depth

### 3. Add dependency check to worktree creation

The worktree-manager script should run `bun install` automatically after creating a new worktree. This prevents the crash at the source by ensuring `node_modules/` is populated before any build or test commands.

**File: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`**

### Research Insights

**Implementation approach (from code review of worktree-manager.sh):**

The script has two creation paths that need the dep-install hook:

1. `create_worktree()` (line 118) -- generic worktree creation
2. `create_for_feature()` (line 188) -- feature-specific creation with spec directory

Both paths already call `copy_env_files "$worktree_path"` as a post-creation step. The `install_deps` function should be added immediately after `copy_env_files` in both paths.

**Concrete implementation:**

```bash
# Install dependencies in a newly created worktree
install_deps() {
  local worktree_path="$1"

  # Only act if package.json exists in the worktree
  if [[ ! -f "$worktree_path/package.json" ]]; then
    return 0
  fi

  # Skip if node_modules already exists (e.g., worktree created from a branch that committed it)
  if [[ -d "$worktree_path/node_modules" ]]; then
    return 0
  fi

  echo -e "${BLUE}Installing dependencies...${NC}"

  # Prefer bun, fall back to npm
  if command -v bun &>/dev/null; then
    if bun install --cwd "$worktree_path" 2>/dev/null; then
      echo -e "  ${GREEN}Dependencies installed (bun)${NC}"
    else
      echo -e "  ${YELLOW}Warning: bun install failed -- run manually in the worktree${NC}"
    fi
  elif command -v npm &>/dev/null; then
    if (cd "$worktree_path" && npm install --silent 2>/dev/null); then
      echo -e "  ${GREEN}Dependencies installed (npm)${NC}"
    else
      echo -e "  ${YELLOW}Warning: npm install failed -- run manually in the worktree${NC}"
    fi
  else
    echo -e "  ${YELLOW}Warning: Neither bun nor npm found -- install dependencies manually${NC}"
  fi
}
```

**Insertion points in worktree-manager.sh:**

- After `copy_env_files "$worktree_path"` in `create_worktree()` (~line 177)
- After `copy_env_files "$worktree_path"` in `create_for_feature()` (~line 237)

**Edge cases:**

- Network unavailable: `bun install` fails gracefully with a warning, doesn't block worktree creation
- `bun` not on PATH: falls back to `npm`, then warns
- Multiple `package.json` files (app-level): root install is sufficient since root `package.json` has the devDependencies needed by root-level test files. App-level deps can be installed on demand.
- `bun.lock` vs `package-lock.json`: `bun install` uses `bun.lock` if present (this repo has one), `npm install` would generate a `package-lock.json` -- prefer bun

**Convention compliance:**

- Function uses `local` for all variables per constitution.md shell convention
- Error messages go to stdout (not stderr) to match existing `copy_env_files` pattern
- Uses `echo -e` with color codes consistent with existing script style

### 4. Document the fix as a learning

**File: `knowledge-base/project/learnings/2026-03-18-bun-test-segfault-missing-deps.md`**

Document that Bun 1.3.5 segfaults on missing dependencies instead of reporting a clean error, and that worktrees need `bun install` before testing.

### Research Insights

**Learning structure (from existing patterns):**

- Follow the Problem / Solution / Key Insight format used by all other learnings
- Include YAML frontmatter with `title`, `date`, `category`, `tags`, `severity`
- Category should be `runtime-errors` (segfault is a runtime crash)
- Tags should include `bun`, `testing`, `git-worktree`, `segfault`
- Cross-reference `2026-02-26-worktree-missing-node-modules-silent-hang.md` as the related prior learning

## Acceptance Criteria

- [x] Root `bunfig.toml` exists with `[test]` section documenting Bun's discovery behavior
- [x] CI pins Bun to `1.3.11` instead of `latest` in `.github/workflows/ci.yml`
- [x] `bun test` passes reliably from repo root (13 files, 1136 tests)
- [x] Worktree creation flow ensures `node_modules/` is populated via `install_deps()` in both `create_worktree()` and `create_for_feature()`
- [x] `install_deps()` degrades gracefully when bun/npm unavailable or network fails
- [x] Learning document captures the root cause, fix, and cross-references prior learning
- [x] `apps/telegram-bridge/bunfig.toml` coverage config continues to work (Bun merges configs)

## Test Scenarios

- Given a fresh worktree without `node_modules/`, when `bun install && bun test` runs, then all 1136 tests pass
- Given `bunfig.toml` at repo root, when `bun test` runs from root, then only 13 test files are discovered (not files from other worktrees)
- Given CI with `bun-version: "1.3.11"`, when the CI workflow runs, then tests pass without segfault
- Given worktree-manager.sh creates a new worktree, when `package.json` exists in the worktree, then `node_modules/` is populated automatically
- Given worktree-manager.sh creates a new worktree, when `bun` is not on PATH, then a warning is printed but worktree creation succeeds
- Given the root `bunfig.toml` exists, when `bun test --coverage` runs from `apps/telegram-bridge/`, then coverage thresholds from `apps/telegram-bridge/bunfig.toml` are still enforced

## Context

**Existing patterns:**

- `apps/telegram-bridge/bunfig.toml` -- per-app test config with coverage thresholds (keep as-is, Bun merges configs)
- `.github/workflows/ci.yml` -- currently uses `bun-version: latest`
- Learning: `2026-02-26-worktree-missing-node-modules-silent-hang.md` -- related prior incident (recommended this fix)
- `worktree-manager.sh` already has post-creation hooks (`copy_env_files`) -- `install_deps` follows the same pattern

**Relevant files:**

- `package.json` (root) -- devDependencies needed by tests
- `bun.lock` (root) -- lockfile for deterministic installs
- `.gitignore` -- already ignores `.worktrees`
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` -- worktree lifecycle (lines 118-183 for `create_worktree`, lines 188-246 for `create_for_feature`)

## References

- Bun crash report: `bun.report/1.3.5/lt11e86ceb...`
- Bun test discovery docs: `github.com/oven-sh/bun/blob/main/docs/test/discovery.mdx`
- Bun test configuration docs: `github.com/oven-sh/bun/blob/main/docs/test/configuration.mdx`
- Learning: `knowledge-base/project/learnings/technical-debt/2026-03-03-no-unified-test-runner-from-repo-root.md`
- Learning: `knowledge-base/project/learnings/implementation-patterns/2026-02-12-bun-coverage-threshold-config.md`
- Learning: `knowledge-base/project/learnings/2026-02-26-worktree-missing-node-modules-silent-hang.md`
