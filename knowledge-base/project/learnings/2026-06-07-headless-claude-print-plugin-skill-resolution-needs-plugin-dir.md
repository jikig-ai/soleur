# Learning: headless `claude --print` needs `--plugin-dir` + `Skill`/`Task` allowlist to invoke /soleur:* skills

## Problem

The `cron-content-generator` Inngest eval (#4987) produced its audit issue (so the
#4960 silence fix worked), but the run was **quality-degraded**: its prompt's
`STEP 2`/`STEP 3` (`/soleur:content-writer`, `/soleur:social-distribute`) reported
"Content-writer skill unavailable" and fell back to hand-written distribution
content, and `STEP 4` build-validation was skipped ("bash unavailable"). This is
invisible to the `cron-cloud-task-heartbeat` watchdog — the audit issue still gets
created, so silence-detection stays green while output quality silently degrades.

The substrate (`_cron-claude-eval-substrate.ts`) symlinks the plugin into
`<spawnCwd>/plugins/soleur`, but a bare symlinked `plugins/` dir alone does NOT make
`/soleur:content-writer` resolvable in a headless `claude --print` run.

## Solution

Two flags on the `claude --print` spawn argv (`CLAUDE_CODE_FLAGS` in
`apps/web-platform/server/inngest/functions/cron-content-generator.ts`):

1. **`--allowedTools` must list `Skill` and `Task`.** `--allowedTools` is an explicit
   allowlist; without `Skill` (invoke a plugin skill) the skill cannot run at all, and
   `Task` is needed for content-writer's fact-checker subagent. (`Task` precedent:
   cron-competitive-analysis / cron-legal-audit already allow it.)
2. **`--plugin-dir plugins/soleur` registers the symlinked plugin.** Per
   `claude --plugin-dir <path>` ("Load a plugin from a directory or .zip", verified in
   CLI v2.1.167), loading a directory-based plugin in `--print` requires the flag
   explicitly — the interactive marketplace/`enabledPlugins` trust flow does not run
   under `--print`. The path must precede the `--` end-of-options marker (the prompt is
   the sole positional after `--`, per #4017).

Separately, `STEP 4` build-validation was rewritten to **defer to CI** rather than run a
local `npx @11ty/eleventy` build: the ephemeral eval workspace is a shallow clone with
no `node_modules`, so a local build cannot run. CI runs the Eleventy build +
`validate-blog-links.sh` as required checks on the auto-PR the eval opens; the eval's
job is to make CI green, not to self-validate.

## Key Insight

A headless `claude --print` spawn does NOT inherit interactive plugin discovery. Any
server-side eval whose prompt invokes `/soleur:*` skills needs BOTH `Skill`(+`Task`) in
`--allowedTools` AND an explicit `--plugin-dir`. Sibling claude-eval producers that
invoke `/soleur:*` skills almost certainly share this latent gap — fleet audit filed as
**#4993**.

## Session Errors

1. **Dangling doc citation in a shipped code comment.** The prior session's commit
   `c5018e4c` added a comment citing `feature-request-plugin-dir-settings.md`, a file
   that exists nowhere in the repo (`git ls-files | grep` + repo-wide `grep -rl` both
   empty). Recovery: re-grounded the comment in verified `claude --help` output
   (`--plugin-dir` is a real, documented flag) and dropped the phantom reference.
   Prevention: before committing a code comment that cites a doc/path, verify the target
   exists (`git ls-files | grep <basename>`); treat code-comment citations with the same
   path-authority skepticism as plan-prescribed paths
   (`hr-when-a-plan-specifies-relative-paths-e-g`).
2. **Pre-existing cross-file test-isolation flake (one-off).** `signature-verify.test.ts`
   fails in the full `test/server/inngest/` vitest run but passes 5/5 in isolation —
   a state leak between files in a single vitest process. Unrelated to this diff (which
   only touches `cron-content-generator.ts`); `main` CI is green because CI isolates
   per-file. Classified one-off (no recurrence vector that blocks anything); noted, not
   filed.

## Tags
category: integration-issues
module: apps/web-platform/server/inngest
