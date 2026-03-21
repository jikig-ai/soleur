# Learning: Eleventy docs build must run from repo root

## Problem

Running `npx @11ty/eleventy` from inside `plugins/soleur/docs/` fails with ENOENT because `_data/agents.js` resolves `plugins/soleur/agents` relative to CWD.

## Solution

Always run the Eleventy build from the worktree/repo root:

```bash
npx @11ty/eleventy --input=plugins/soleur/docs --output=plugins/soleur/docs/_site
```

## Key Insight

The docs data files (agents.js, etc.) use `resolve("plugins/soleur/agents")` which is CWD-relative. The build must run from the repo root so these relative paths resolve correctly.

## Tags

category: build-errors
module: docs
