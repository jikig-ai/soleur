# Learning: KB upload API FormData field name contract

## Problem

Custom icon upload from team-settings always failed with HTTP 400 because the component sent `formData.append("path", filename)` while the upload API route expected `formData.get("targetDir")`. Additionally, the component sent a full relative path (`settings/team-icons/cto.png`) but the API expected only a directory path and appended the filename from `file.name` itself.

## Solution

1. Changed the FormData field name from `"path"` to `"targetDir"` to match the API contract.
2. Sent only the directory portion (`"settings/team-icons"`) as `targetDir`.
3. Created a `new File([file], iconFilename, { type: file.type })` to control the filename the API uses, since the API reads `file.name` for the filename component.

## Key Insight

When integrating with an existing upload API, read the API route handler to verify the exact FormData field names and path semantics (directory vs full path). The API's `targetDir + file.name` composition means the client controls the filename via the File object's name property, not via a separate field. This is a contract that must be matched exactly — there's no validation error that tells you "wrong field name," just a generic "Missing file or targetDir."

## Session Errors

1. **npx vitest cache corruption** — npx resolved to a stale cache pointing at a different worktree, causing 108 phantom test failures. **Prevention:** Use `node node_modules/vitest/vitest.mjs run` directly in worktrees instead of `npx vitest` to avoid cross-worktree npx cache collisions.

2. **git add with wrong relative paths** — Used `apps/web-platform/` prefix while CWD was already inside that directory. **Prevention:** Always run `pwd` before `git add` to confirm CWD, or use absolute paths.

3. **replace_all missed third occurrence** — Dashboard page had three foundation card badge patterns but `replace_all` only replaced two because the third had different indentation (18 vs 20 spaces). **Prevention:** After any `replace_all` Edit, grep the file to verify zero remaining matches before proceeding. This is already in the work skill's common pitfalls but was not followed.

4. **Review agents analyzed stale branch state** — Implementation commits hadn't been pushed to remote, so agents using `git show` or checking remote state saw only planning artifacts. **Prevention:** Push to remote before spawning review agents, or ensure agents are instructed to use local branch state only (`git diff origin/main...HEAD`).

## Tags

category: integration-issues
module: web-platform/api/kb/upload
