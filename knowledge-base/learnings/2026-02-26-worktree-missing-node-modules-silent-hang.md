# Learning: Worktree missing node_modules causes silent Eleventy hang

## Problem

Running `npx @11ty/eleventy --input=plugins/soleur/docs --output=_site` in a newly created git worktree hangs indefinitely with no error output. The command never completes and must be manually killed. This happened three consecutive times before the root cause was identified.

## Solution

Git worktrees do not share `node_modules/` with the main working tree. Run `npm install` in the worktree before any build commands:

```bash
cd .worktrees/feat-<name>
npm install
npx @11ty/eleventy --input=plugins/soleur/docs --output=_site
```

After `npm install`, the build completes in under 1 second (0.35s for 18 files).

## Key Insight

`npx` with a missing local package silently attempts to download and can hang on network issues or interactive prompts that are suppressed in non-TTY contexts. The failure mode is a silent hang, not an error message. When builds hang in worktrees, check `node_modules/` existence first — `ls node_modules/@11ty/eleventy/package.json 2>/dev/null` is a quick diagnostic.

A potential preventive measure: the `worktree-manager.sh feature` subcommand could run `npm install` (or detect `package.json` and warn) after creating the worktree.

## Tags
category: build-errors
module: docs, git-worktree
