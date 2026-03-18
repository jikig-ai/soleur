---
title: "fix: docs data files resolve paths relative to CWD instead of file location"
type: fix
date: 2026-03-18
deepened: 2026-03-18
---

# fix: docs data files resolve paths relative to CWD instead of file location

## Enhancement Summary

**Deepened on:** 2026-03-18
**Sections enhanced:** 4 (MVP import diffs, test scenarios, acceptance criteria, context)
**Sources:** 3 plan reviewers, 2 existing institutional learnings, source file audit

### Key Improvements

1. MVP snippets now show complete import line diffs (add `dirname`/`fileURLToPath`, remove dead `resolve` import)
2. Test scenario 2 marked aspirational -- `eleventy.config.js` has its own CWD dependency via `dir.input` that is out of scope
3. Two existing learnings confirm this is a documented, recurring problem with the prescribed fix matching this plan

## Overview

Four Eleventy data files under `plugins/soleur/docs/_data/` use `resolve("plugins/soleur/...")` to locate agent, skill, command, and plugin directories. `resolve()` with a relative argument resolves against `process.cwd()`, not the file's own location. The build works from the repo root (CI's default CWD) but fails from any other directory.

## Problem Statement

`agents.js:139`, `skills.js:112`, `stats.js:17-19`, and `plugin.js:7` all call `resolve("plugins/soleur/...")`. This is CWD-dependent. If Eleventy is invoked from a different directory (e.g., `plugins/soleur/docs/`), the resolved path points to a nonexistent location and the build crashes with `ENOENT`.

Affected files (confirmed via `grep -r 'resolve("' plugins/soleur/docs/_data/` -- no other data files use `resolve()`):

| File | Line | Expression |
|------|------|-----------|
| `plugins/soleur/docs/_data/agents.js` | 139 | `resolve("plugins/soleur/agents")` |
| `plugins/soleur/docs/_data/skills.js` | 112 | `resolve("plugins/soleur/skills")` |
| `plugins/soleur/docs/_data/stats.js` | 17-19 | `resolve("plugins/soleur/agents")`, `resolve("plugins/soleur/skills")`, `resolve("plugins/soleur/commands")` |
| `plugins/soleur/docs/_data/plugin.js` | 7 | `resolve("plugins/soleur/.claude-plugin/plugin.json")` |

**Not affected:** `changelog.js` and `github.js` do not use `resolve()`.

## Proposed Solution

Replace CWD-relative `resolve()` calls with file-relative resolution using `import.meta.url`. Each ESM file can derive its own directory, then navigate to the target using a known relative path.

The `_data/` directory is 4 levels below the repo root (`_data` -> `docs` -> `soleur` -> `plugins` -> root), so the relative path from any data file to `plugins/soleur/agents` is `../../agents` (2 levels up from `_data/` to `plugins/soleur/`).

### Path verification

| From `_data/` | `..` (1) | `../..` (2) | Target |
|---------------|----------|-------------|--------|
| `_data/` | `docs/` | `plugins/soleur/` | -- |
| Target: `agents/` | -- | -- | `../../agents` |
| Target: `skills/` | -- | -- | `../../skills` |
| Target: `commands/` | -- | -- | `../../commands` |
| Target: `.claude-plugin/plugin.json` | -- | -- | `../../.claude-plugin/plugin.json` |

## Acceptance Criteria

- [x] All 4 data files (`agents.js`, `skills.js`, `stats.js`, `plugin.js`) use `import.meta.url`-based path resolution instead of CWD-relative `resolve()`
- [x] Dead `resolve` imports removed from all 4 files (no lint warnings)
- [x] `npm run docs:build` succeeds from the repo root (existing behavior preserved)
- [x] No hardcoded absolute paths -- all paths remain relative to the file's location
- [x] `agents.js` retains its `relative` import (used at line 146 for agent path derivation)

## Test Scenarios

- Given CWD is the repo root, when `npx @11ty/eleventy` runs, then the build completes with 32 output files (regression check)
- Given the repo is checked out to a non-standard path (e.g., a git worktree under `.worktrees/`), when the docs build runs from the worktree root, then paths resolve correctly because they are file-relative, not CWD-relative

**Out of scope (aspirational):** Running the Eleventy build from `plugins/soleur/docs/` with `--config=../../../eleventy.config.js`. Even after this fix, `eleventy.config.js` itself uses `dir.input: "plugins/soleur/docs"` which Eleventy resolves relative to the config file directory or CWD. Fixing the config file's CWD dependency is a separate concern.

## Context

This is a documented, recurring problem with two existing learnings:

1. `knowledge-base/project/learnings/2026-03-10-eleventy-build-fails-in-worktree.md` -- Documents the exact ENOENT error when running from a worktree. Prescribes the fix: "agents.js should resolve paths relative to the repository root using `path.resolve(__dirname, '../../agents')`".
2. `knowledge-base/project/learnings/2026-03-15-eleventy-build-must-run-from-repo-root.md` -- Documents the CWD constraint as a workaround. This fix eliminates the need for the workaround.
3. `knowledge-base/project/learnings/build-errors/eleventy-v3-passthrough-and-nunjucks-gotchas.md` -- Documents the related Eleventy v3 passthrough copy path resolution issue. The `eleventy.config.js` file already handles that correctly with explicit mapping.

After this fix, learnings 1 and 2 above can be archived (the root cause will be resolved).

## MVP

Each file needs two changes: (a) update the import line to add `fileURLToPath`/`dirname` and remove dead `resolve`, and (b) replace the `resolve()` call with `join(__dirname, ...)`.

### plugins/soleur/docs/_data/agents.js

```javascript
// Import line change (line 2):
// Before:
import { join, resolve, relative } from "node:path";
// After:
import { fileURLToPath } from "node:url";
import { dirname, join, relative } from "node:path";

// Add after imports:
const __dirname = dirname(fileURLToPath(import.meta.url));

// Line 139 change:
// Before:
const agentsDir = resolve("plugins/soleur/agents");
// After:
const agentsDir = join(__dirname, "..", "..", "agents");
```

Note: `relative` is retained -- it is used at line 146 for deriving agent domain/sub from path.

### plugins/soleur/docs/_data/skills.js

```javascript
// Import line change (line 2):
// Before:
import { join, resolve } from "node:path";
// After:
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

// Add after imports:
const __dirname = dirname(fileURLToPath(import.meta.url));

// Line 112 change:
// Before:
const skillsDir = resolve("plugins/soleur/skills");
// After:
const skillsDir = join(__dirname, "..", "..", "skills");
```

### plugins/soleur/docs/_data/stats.js

```javascript
// Import line change (line 2):
// Before:
import { join, resolve } from "node:path";
// After:
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

// Add after imports:
const __dirname = dirname(fileURLToPath(import.meta.url));

// Lines 17-19 change:
// Before:
const agentsDir = resolve("plugins/soleur/agents");
const skillsDir = resolve("plugins/soleur/skills");
const commandsDir = resolve("plugins/soleur/commands");
// After:
const agentsDir = join(__dirname, "..", "..", "agents");
const skillsDir = join(__dirname, "..", "..", "skills");
const commandsDir = join(__dirname, "..", "..", "commands");
```

### plugins/soleur/docs/_data/plugin.js

```javascript
// Import line change (line 2):
// Before:
import { resolve } from "node:path";
// After:
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

// Add after imports:
const __dirname = dirname(fileURLToPath(import.meta.url));

// Line 7 change:
// Before:
readFileSync(resolve("plugins/soleur/.claude-plugin/plugin.json"), "utf-8")
// After:
readFileSync(join(__dirname, "..", "..", ".claude-plugin", "plugin.json"), "utf-8")
```

## Post-Fix Cleanup

After merging, archive these two learnings (their root cause will be resolved):

- `knowledge-base/project/learnings/2026-03-10-eleventy-build-fails-in-worktree.md`
- `knowledge-base/project/learnings/2026-03-15-eleventy-build-must-run-from-repo-root.md`

## References

- Existing learning: `knowledge-base/project/learnings/build-errors/eleventy-v3-passthrough-and-nunjucks-gotchas.md`
- Existing learning: `knowledge-base/project/learnings/2026-03-10-eleventy-build-fails-in-worktree.md`
- Existing learning: `knowledge-base/project/learnings/2026-03-15-eleventy-build-must-run-from-repo-root.md`
- Node.js ESM `import.meta.url` docs: https://nodejs.org/api/esm.html#importmetaurl
- Eleventy config: `eleventy.config.js`
