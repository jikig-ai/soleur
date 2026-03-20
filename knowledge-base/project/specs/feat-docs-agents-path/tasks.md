# Tasks: fix docs data files CWD-relative path

## Phase 1: Core Fix

Each file needs two changes: (a) update the import line to add `fileURLToPath`/`dirname` and remove dead `resolve`, (b) replace `resolve()` calls with `join(__dirname, ...)`.

- [ ] 1.1 Update `plugins/soleur/docs/_data/agents.js`
  - 1.1.1 Import line: replace `import { join, resolve, relative } from "node:path"` with `import { fileURLToPath } from "node:url"` + `import { dirname, join, relative } from "node:path"` (retain `relative` -- used at line 146)
  - 1.1.2 Add `const __dirname = dirname(fileURLToPath(import.meta.url))` after imports
  - 1.1.3 Line 139: replace `resolve("plugins/soleur/agents")` with `join(__dirname, "..", "..", "agents")`
- [ ] 1.2 Update `plugins/soleur/docs/_data/skills.js`
  - 1.2.1 Import line: replace `import { join, resolve } from "node:path"` with `import { fileURLToPath } from "node:url"` + `import { dirname, join } from "node:path"`
  - 1.2.2 Add `const __dirname = dirname(fileURLToPath(import.meta.url))` after imports
  - 1.2.3 Line 112: replace `resolve("plugins/soleur/skills")` with `join(__dirname, "..", "..", "skills")`
- [ ] 1.3 Update `plugins/soleur/docs/_data/stats.js`
  - 1.3.1 Import line: replace `import { join, resolve } from "node:path"` with `import { fileURLToPath } from "node:url"` + `import { dirname, join } from "node:path"`
  - 1.3.2 Add `const __dirname = dirname(fileURLToPath(import.meta.url))` after imports
  - 1.3.3 Lines 17-19: replace all 3 `resolve()` calls with `join(__dirname, ...)` equivalents
- [ ] 1.4 Update `plugins/soleur/docs/_data/plugin.js`
  - 1.4.1 Import line: replace `import { resolve } from "node:path"` with `import { fileURLToPath } from "node:url"` + `import { dirname, join } from "node:path"`
  - 1.4.2 Add `const __dirname = dirname(fileURLToPath(import.meta.url))` after imports
  - 1.4.3 Line 7: replace `resolve("plugins/soleur/.claude-plugin/plugin.json")` with `join(__dirname, "..", "..", ".claude-plugin", "plugin.json")`

## Phase 2: Validation

- [ ] 2.1 Run `npx @11ty/eleventy` from worktree root -- verify build succeeds with 32 output files (regression check)
- [ ] 2.2 Verify no dead `resolve` imports remain: `grep 'resolve' plugins/soleur/docs/_data/*.js` should return nothing

## Phase 3: Commit and Ship

- [ ] 3.1 Run `soleur:compound` before commit
- [ ] 3.2 Commit with message `fix(docs): resolve data file paths relative to file location, not CWD`
- [ ] 3.3 Push and create PR

## Phase 4: Post-Fix Cleanup (after merge)

- [ ] 4.1 Archive `knowledge-base/project/learnings/2026-03-10-eleventy-build-fails-in-worktree.md` (root cause resolved)
- [ ] 4.2 Archive `knowledge-base/project/learnings/2026-03-15-eleventy-build-must-run-from-repo-root.md` (root cause resolved)
