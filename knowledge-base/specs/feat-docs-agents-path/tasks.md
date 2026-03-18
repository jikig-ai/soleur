# Tasks: fix docs data files CWD-relative path

## Phase 1: Core Fix

- [ ] 1.1 Update `plugins/soleur/docs/_data/agents.js` -- add `import.meta.url` resolution, replace `resolve("plugins/soleur/agents")` with `join(__dirname, "..", "..", "agents")`
- [ ] 1.2 Update `plugins/soleur/docs/_data/skills.js` -- add `import.meta.url` resolution, replace `resolve("plugins/soleur/skills")` with `join(__dirname, "..", "..", "skills")`
- [ ] 1.3 Update `plugins/soleur/docs/_data/stats.js` -- add `import.meta.url` resolution, replace all 3 `resolve()` calls with `join(__dirname, ...)` equivalents
- [ ] 1.4 Update `plugins/soleur/docs/_data/plugin.js` -- add `import.meta.url` resolution, replace `resolve("plugins/soleur/.claude-plugin/plugin.json")` with `join(__dirname, "..", "..", ".claude-plugin", "plugin.json")`

## Phase 2: Validation

- [ ] 2.1 Run `npx @11ty/eleventy` from repo root -- verify build succeeds (regression check)
- [ ] 2.2 Run Eleventy from `plugins/soleur/docs/` with `--config` pointing to repo root config -- verify build succeeds (original failure scenario)
- [ ] 2.3 Verify build output matches expected 32 files

## Phase 3: Commit and Ship

- [ ] 3.1 Run `soleur:compound` before commit
- [ ] 3.2 Commit with message `fix(docs): resolve data file paths relative to file location, not CWD`
- [ ] 3.3 Push and create PR
