---
date: 2026-07-06
category: bug-fixes
module: agent-runner
tags: [concierge, plugin-delivery, dogfooding, workspace-relative-path, CLAUDE_PLUGIN_ROOT, sandbox-canary, root-cause, wrong-layer]
issue: 4826
related:
  - 2026-07-05-config-lock-mask-is-sdk-bwrap-not-substrate-preseed-host-side.md
  - 2026-07-03-faithful-canary-capture-must-run-in-the-deploy-base-image.md
  - 2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md
  - ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md
  - ADR-080-runtime-plugin-deploys-via-image-rebuild.md
---

# Learning: a connected repo that ships `plugins/soleur/` silently shadows the DEPLOYED plugin — AND the canary that "blocked the fix" never touched the plugin path

> This re-captures the file reverted with #6115, **enhanced** with the two facts the #6115→#6117 round got wrong.

## Problem

For FIVE rounds, `worktree-manager.sh` guard fixes were merged, deployed (image + host mount both verified fresh),
and yet the operator's Concierge session kept wedging with the EXACT pre-fix behavior. Each round's fix was
logically correct and passed local + CI tests.

Root cause: **the operator's connected repo IS `jikig-ai/soleur` itself** (they dogfood Concierge on the platform's
own repo). The workspace is a clone of soleur, which contains `plugins/soleur/` as **committed source files**. Two
facts combine:

1. `scaffoldWorkspaceDefaults` overlays the deployed plugin as a symlink ONLY `if (!existsSync(symlinkTarget))`
   (`workspace.ts:438`) — but the git clone already put a real `plugins/soleur/` there, so the symlink is never
   created. The workspace keeps its committed copy.
2. `go.md` / `one-shot` invoked the script by a **workspace-relative path**
   (`bash ./plugins/soleur/…/worktree-manager.sh`). Even though the *command* `/soleur:go` is the DEPLOYED one,
   the bash it shells out to resolves `./plugins/soleur/…` against the CWD = the workspace = the connected repo's
   **frozen committed checkout**.

And a THIRD, deeper layer: the SDK plugin load itself. Both real-SDK factories set the SDK `plugins:[{path}]` to
`path.join(workspacePath,"plugins","soleur")` — `cc-dispatcher.ts:2387` (Concierge) **and** `agent-runner.ts:1109`
(legacy `startAgentSession`). For the dogfooder that is the committed copy, so even the COMMANDS/SKILLS/HOOKS load
stale. Only APP-side fixes (git-config heal, telemetry hook — container code, not the plugin mount) ever took
effect, exactly the split observed.

## Key Insight

1. **"The command is deployed" ≠ "the scripts it shells out to are deployed."** Claude Code loads commands/skills
   from the plugin mount, but a bash command inside them with a *relative* path resolves against the workspace CWD.
   When the connected repo ships a colliding directory, the relative path silently binds to the repo's frozen copy.
   Invoke out-of-tree scripts by an ABSOLUTE, deployment-anchored path (`${CLAUDE_PLUGIN_ROOT}`), never
   workspace-relative.

2. **There are TWO SDK factories, not one.** `#6115` fixed only `cc-dispatcher.ts` and left
   `agent-runner.ts startAgentSession` still loading the workspace copy. A guard placed at one factory while a
   second factory is the real (or an also-reachable) trigger is the recurring "wrong site" trap
   (cf. `2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md`). Grep ALL
   `plugins:[` construction sites before declaring a plugin-load fix complete.

3. **Loading a connected repo's plugin is untrusted-code execution.** The plugin's `hooks/hooks.json` registers
   `type:"command"` hooks that the Agent SDK runs as **subprocesses of the Node dispatch process — outside the
   bwrap tool sandbox, with server privileges** — on every session start/stop. The security-correct posture is:
   **always load the platform-deployed plugin (`getPluginPath()`), never the workspace copy.**

4. **The canary that "blocked #6115" never touched the plugin path — verify the ACTUAL failing gate, don't reason
   from the SDK's sandbox model on a dev machine.** #6115 was reverted (#6117) on the stated reason that the
   `/app/shared` plugin path "does not work in the bwrap agent sandbox." That is false, and so is the sibling
   theory that "changing the plugin path drifts the ADR-079 argv fixture." The code:
   - `/app/shared` is readable in the sandbox (`--ro-bind / /`) and is already the path `verifyPluginMountOnce()`
     validates at every container boot (`plugin-mount-check.ts:32`).
   - The BLOCKING `canary_sandbox_failed` gate is a **hardcoded, plugin-independent** probe —
     `docker exec … bwrap --new-session --die-with-parent --dev /dev --unshare-pid --bind / / -- true`
     (`ci-deploy.sh:1281`) — that runs only AFTER health/login/dashboard already passed (so the container booted
     fine with the plugin change). Its only failure modes are host bwrap/userns capability drift (the documented
     `#4932`/`#5849`/`#2276` FALSE-ROLLBACK class).
   - The faithful ADR-079 argv canary is NON-BLOCKING at deploy (`run_faithful_sandbox_canary || true`,
     `ci-deploy.sh:1297`), and its `--capture`/`--verify` fixture is driven by `buildAgentSandboxConfig` with **no
     `plugins:` key** and **drops all `--setenv`** — so neither the plugin path nor `CLAUDE_PLUGIN_ROOT` can change
     it.
   On the evidence, #6115's `canary_sandbox_failed` was a HOST bwrap/userns false-rollback coincident with a window
   of active web-2 fresh-boot instability (`#6090`/`#6116` landed right after the revert) — **not** caused by the
   plugin change. Reverting the plugin fix "for the canary" was a near-6th round of wrong-layer misattribution.

## Solution (the redo, corrected)

Load the plugin from `getPluginPath()` in BOTH SDK factories (Slice A — the security core; ADR-093). The residual
in-process SKILL.md reader (`context-queries-hook.ts` `skillsDir`) sources from `getPluginPath()` too, while
`knowledge-base/` stays workspace-rooted (repo content, `git ls-files`+containment gated). A **loaded-gun guard**
(`assertTrustedPluginPath`, test-tolerant `/app/` allowlist) wraps the `plugins:[{path}]` chokepoint so a future
workspace-relative regression fails loudly instead of silently re-opening the hole. Slice B (a sequenced follow-up):
export `CLAUDE_PLUGIN_ROOT = getPluginPath()` into the agent bash env (not in `AGENT_ENV_ALLOWLIST` — injected
explicitly) and migrate the shelled-out `worktree-manager.sh`/readiness-diag invocations to
`${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` behind a safe-bash exact-literal carve-out. **No ADR-079 fixture
regeneration is needed** (the change doesn't touch `buildAgentSandboxConfig`). The gating on-host step is NOT a
fixture regen — it is reading `/hooks/deploy-status` for the real reason and refusing to re-misattribute a host
`canary_sandbox_failed` to the plugin path. **Observability was reduced (not the originally-planned per-dispatch
`source=='workspace-shadow'` probe — that monitors a state the post-Slice-A code cannot produce, a tautology):**
rely on the existing `verifyPluginMountOnce()` boot probe + a single scaffold-time `connectedRepoShipsPlugin`
diagnostic breadcrumb that makes the previously-silent collision observable.

## Session Errors

- **Chased the guard LOGIC for 4 rounds** when the running code was never the code being fixed. **Prevention:**
  before iterating a fix on a blind surface, verify the artifact under test is the one executing (path provenance /
  a version sentinel), not just that the fix is correct in isolation. The load-source probe operationalizes this.
- **The revert (#6117) accepted a plausible-but-wrong sandbox theory** ("`/app/shared` not sandbox-accessible")
  without reading the actual `canary_sandbox_failed` gate. **Prevention:** when a canary/deploy gate blocks a
  change, read the gate's own code to confirm the change can even reach it before attributing the failure to it.

## Tags
category: bug-fixes
module: agent-runner
