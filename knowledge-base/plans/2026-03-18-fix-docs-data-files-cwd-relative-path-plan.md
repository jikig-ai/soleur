---
title: "fix: docs data files resolve paths relative to CWD instead of file location"
type: fix
date: 2026-03-18
---

# fix: docs data files resolve paths relative to CWD instead of file location

## Overview

Four Eleventy data files under `plugins/soleur/docs/_data/` use `resolve("plugins/soleur/...")` to locate agent, skill, command, and plugin directories. `resolve()` with a relative argument resolves against `process.cwd()`, not the file's own location. The build works from the repo root (CI's default CWD) but fails from any other directory.

## Problem Statement

`agents.js:139`, `skills.js:112`, `stats.js:17-19`, and `plugin.js:7` all call `resolve("plugins/soleur/...")`. This is CWD-dependent. If Eleventy is invoked from a different directory (e.g., `plugins/soleur/docs/`), the resolved path points to a nonexistent location and the build crashes with `ENOENT`.

Affected files:

| File | Line | Expression |
|------|------|-----------|
| `plugins/soleur/docs/_data/agents.js` | 139 | `resolve("plugins/soleur/agents")` |
| `plugins/soleur/docs/_data/skills.js` | 112 | `resolve("plugins/soleur/skills")` |
| `plugins/soleur/docs/_data/stats.js` | 17-19 | `resolve("plugins/soleur/agents")`, `resolve("plugins/soleur/skills")`, `resolve("plugins/soleur/commands")` |
| `plugins/soleur/docs/_data/plugin.js` | 7 | `resolve("plugins/soleur/.claude-plugin/plugin.json")` |

## Proposed Solution

Replace CWD-relative `resolve()` calls with file-relative resolution using `import.meta.url`. Each ESM file can derive its own directory, then navigate to the target using a known relative path.

The `_data/` directory is 4 levels below the repo root (`_data` -> `docs` -> `soleur` -> `plugins` -> root), so the relative path from any data file to `plugins/soleur/agents` is `../../agents` (2 levels up from `_data/` to `plugins/soleur/`).

### Pattern

```javascript
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
// __dirname = .../plugins/soleur/docs/_data

// To reach plugins/soleur/agents from _data/:
//   _data -> docs -> soleur (../../) then agents
const agentsDir = join(__dirname, "..", "..", "agents");
```

### Path verification

| From `_data/` | `..` (1) | `../..` (2) | Target |
|---------------|----------|-------------|--------|
| `_data/` | `docs/` | `plugins/soleur/` | -- |
| Target: `agents/` | -- | -- | `../../agents` |
| Target: `skills/` | -- | -- | `../../skills` |
| Target: `commands/` | -- | -- | `../../commands` |
| Target: `.claude-plugin/plugin.json` | -- | -- | `../../.claude-plugin/plugin.json` |

## Acceptance Criteria

- [ ] All 4 data files (`agents.js`, `skills.js`, `stats.js`, `plugin.js`) use `import.meta.url`-based path resolution instead of CWD-relative `resolve()`
- [ ] `npm run docs:build` succeeds from the repo root (existing behavior preserved)
- [ ] Eleventy build succeeds when CWD is `plugins/soleur/docs/` (the original failure scenario)
- [ ] No hardcoded absolute paths -- all paths remain relative to the file's location

## Test Scenarios

- Given CWD is the repo root, when `npx @11ty/eleventy` runs, then the build completes with 32 output files (regression check)
- Given CWD is `plugins/soleur/docs/`, when `npx @11ty/eleventy --config=../../../eleventy.config.js` runs, then the build completes without ENOENT errors on agent/skill/command directories
- Given the repo is checked out to a non-standard path (e.g., a git worktree under `.worktrees/`), when the docs build runs, then paths resolve correctly because they are file-relative, not CWD-relative

## Context

The existing learnings document `knowledge-base/project/learnings/build-errors/eleventy-v3-passthrough-and-nunjucks-gotchas.md` documents a related Eleventy v3 path resolution issue with passthrough copy. The `eleventy.config.js` file already handles that correctly with explicit mapping. This fix addresses the same class of problem in the JavaScript data files.

## MVP

### plugins/soleur/docs/_data/agents.js

Replace the CWD-relative resolve:

```javascript
// Before (line 139)
const agentsDir = resolve("plugins/soleur/agents");

// After
import { fileURLToPath } from "node:url";
const __dirname = dirname(fileURLToPath(import.meta.url));
const agentsDir = join(__dirname, "..", "..", "agents");
```

### plugins/soleur/docs/_data/skills.js

```javascript
// Before (line 112)
const skillsDir = resolve("plugins/soleur/skills");

// After
import { fileURLToPath } from "node:url";
const __dirname = dirname(fileURLToPath(import.meta.url));
const skillsDir = join(__dirname, "..", "..", "skills");
```

### plugins/soleur/docs/_data/stats.js

```javascript
// Before (lines 17-19)
const agentsDir = resolve("plugins/soleur/agents");
const skillsDir = resolve("plugins/soleur/skills");
const commandsDir = resolve("plugins/soleur/commands");

// After
import { fileURLToPath } from "node:url";
const __dirname = dirname(fileURLToPath(import.meta.url));
const agentsDir = join(__dirname, "..", "..", "agents");
const skillsDir = join(__dirname, "..", "..", "skills");
const commandsDir = join(__dirname, "..", "..", "commands");
```

### plugins/soleur/docs/_data/plugin.js

```javascript
// Before (line 7)
readFileSync(resolve("plugins/soleur/.claude-plugin/plugin.json"), "utf-8")

// After
import { fileURLToPath } from "node:url";
const __dirname = dirname(fileURLToPath(import.meta.url));
readFileSync(join(__dirname, "..", "..", ".claude-plugin", "plugin.json"), "utf-8")
```

## References

- Existing learning: `knowledge-base/project/learnings/build-errors/eleventy-v3-passthrough-and-nunjucks-gotchas.md`
- Node.js ESM `import.meta.url` docs: https://nodejs.org/api/esm.html#importmetaurl
- Eleventy config: `eleventy.config.js`
