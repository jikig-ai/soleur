---
date: 2026-07-06
category: bug-fixes
module: agent-runner
tags: [concierge, plugin-delivery, dogfooding, workspace-relative-path, CLAUDE_PLUGIN_ROOT, root-cause]
issue: 4826
related:
  - 2026-07-05-config-lock-mask-is-sdk-bwrap-not-substrate-preseed-host-side.md
  - ADR-080-runtime-plugin-deploys-via-image-rebuild.md
---

# Learning: a connected repo that ships `plugins/soleur/` silently shadows the DEPLOYED plugin — via a workspace-relative invocation path

## Problem

For FIVE rounds, `worktree-manager.sh` guard fixes were merged, deployed (image + host
mount both verified fresh), and yet the operator's Concierge session kept wedging with the
EXACT pre-fix behavior. Each round's fix was logically correct and passed local + CI tests.

Root cause (finally): **the operator's connected repo IS `jikig-ai/soleur` itself** (they
dogfood Concierge on the platform's own repo). The workspace is a clone of soleur, which
contains `plugins/soleur/` as **committed source files**. Two facts then combine:

1. `scaffoldWorkspaceDefaults` overlays the deployed plugin as a symlink ONLY
   `if (!existsSync(symlinkTarget))` — but the git clone already put a real `plugins/soleur/`
   there, so the symlink is never created. The workspace keeps its committed copy.
2. `go.md` / `one-shot` invoked the script by a **workspace-relative path**:
   `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`. Even though the
   *command* `/soleur:go` is the DEPLOYED one (Claude Code loads commands from the plugin
   mount), the bash it shells out to resolves `./plugins/soleur/...` against the CWD =
   the workspace = the connected repo's **frozen committed checkout**.

So every session ran the operator's checked-out `worktree-manager.sh` (stale, at whatever
commit their working tree sat on), NOT the deployed one. All plugin-script fixes were
shadowed. Only APP-side fixes (the git-config heal, the telemetry hook — container code, not
the plugin mount) ever took effect, which is exactly the split we observed.

There are actually TWO shadowing layers, both fixed here:
- **The SDK plugin load itself.** `cc-dispatcher.ts` set the SDK `plugins: [{ path }]` to
  `path.join(workspacePath, "plugins", "soleur")` — the WORKSPACE path. For a normal user
  that is a symlink to the deployed plugin (fresh); for the dogfooder it is the committed
  copy, so even the COMMANDS/SKILLS (go.md, one-shot) load stale. A fix to only the bash
  invocation path would NOT reach the dogfooder because their stale go.md would still run.
- **The bash invocation.** go.md/one-shot shelled out via `./plugins/soleur/...`
  (workspace-relative → committed copy).

## Solution

Route BOTH the SDK plugin load and the bash invocations to the DEPLOYED plugin root:

- `cc-dispatcher.ts` (the real Concierge SDK factory) now loads the plugin from
  `getPluginPath()` (deployed), not `<workspacePath>/plugins/soleur` — so commands/skills
  come from the deployed tree. Safe because `/app/shared` is sandbox-readable (the SDK base
  `--ro-bind / /` exposes it; not in the sandbox `denyRead` — proven by normal users' plugin
  symlinks already resolving there) and `getPluginPath()` respects the `SOLEUR_PLUGIN_PATH`
  override for the advanced plugin-dev-testing case.
- `buildAgentEnv` now exports `CLAUDE_PLUGIN_ROOT = args.pluginPath` (= `getPluginPath()`
  after the cc-dispatcher change) into the agent bash env. It was NOT in `AGENT_ENV_ALLOWLIST`
  (the env is a curated replacement of process.env), so it had to be injected explicitly.
- `go.md` (readiness gate + session-start preamble) and `one-shot` (worktree create) now call
  `bash "${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/skills/.../worktree-manager.sh"`. The var
  resolves to the deployed script in Concierge; the `:-./plugins/soleur` fallback preserves
  CLI/local behavior. Verified: with the var EXPORTED, the deployed script runs; unset, the
  workspace-relative fallback runs.

Both halves deploy reliably (app code + plugin mount) and neither depends on the operator
updating their workspace checkout — so the fix reaches them without a `git pull`.

## Key Insight

1. **"The command is deployed" does not mean "the scripts it shells out to are deployed."**
   Claude Code loads commands/skills from the plugin mount, but a bash command inside them
   with a relative path resolves against the workspace CWD. When the connected repo ships a
   colliding directory, the relative path silently binds to the repo's frozen copy. Invoke
   out-of-tree scripts by an ABSOLUTE, deployment-anchored path (`${CLAUDE_PLUGIN_ROOT}`),
   never a workspace-relative one.

2. **Dogfooding a platform ON its own repo is a distinct, sharp config** that violates the
   silent assumption "the connected repo does not contain `plugins/soleur/`". The overlay's
   `if (!existsSync)` guard is correct for normal users and a trap for the soleur-on-soleur
   operator. Any platform that can be pointed at its own source needs to handle the collision
   explicitly.

3. **When N correct-looking fixes all fail identically, stop fixing and instrument WHAT CODE
   ACTUALLY RUNS.** The breakthrough came from the operator's `readlink -f` output resolving
   to a path INSIDE `/workspaces/<uuid>/` (not out to the mount) — proof the running script
   was the workspace copy, not the deployed one. That one observation, under-weighted for
   rounds, was the whole answer.

## Session Errors

- **Chased the guard LOGIC for 4 rounds** when the running code was never the code I was
  fixing. **Prevention:** before iterating a fix on a blind surface, verify the artifact
  under test is the one executing (path provenance / a version sentinel), not just that the
  fix is correct in isolation.

## Follow-ups

- The `git-worktree/SKILL.md` usage EXAMPLES still show `./plugins/soleur/...`. They are CLI
  docs, lower-risk, but an agent could copy one in Concierge — migrate them to the
  `${CLAUDE_PLUGIN_ROOT}` form for consistency.
- Consider whether `scaffoldWorkspaceDefaults` should detect a connected repo that already
  ships `plugins/soleur/` and surface it (the collision is currently silent).

## Tags
category: bug-fixes
module: agent-runner
