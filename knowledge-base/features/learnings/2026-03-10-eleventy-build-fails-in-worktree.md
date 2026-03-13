# Learning: Eleventy build fails in worktrees due to relative path in agents.js

## Problem
Running `npx @11ty/eleventy` from a worktree (`plugins/soleur/docs/` CWD) fails with:
```
ENOENT: no such file or directory, scandir '.../plugins/soleur/docs/plugins/soleur/agents'
```
The `_data/agents.js` file uses a relative path (`plugins/soleur/agents`) that resolves from the docs directory CWD, doubling the path in worktrees.

## Solution
No fix applied in this session. Workaround: verify template changes by reading the file directly and checking grep counts rather than running the full Eleventy build in a worktree.

For a proper fix, `agents.js` should resolve paths relative to the repository root using `path.resolve(__dirname, '../../agents')` or similar absolute path construction.

## Key Insight
Eleventy data files that use relative paths break in git worktrees because the CWD differs from the main repo checkout. Always use `__dirname`-relative paths in Eleventy data files to ensure portability across worktrees.

## Tags
category: build-errors
module: docs
