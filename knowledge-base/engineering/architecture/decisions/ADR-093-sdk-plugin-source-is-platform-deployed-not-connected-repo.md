# ADR-093: The SDK plugin/hook/skill source is the platform-deployed root, never the connected-repo workspace copy

- **Status:** Accepted
- **Date:** 2026-07-06
- **Issue:** [#4826](https://github.com/jikig-ai/soleur/issues/4826) (delivery wedge; the infra bug behind it)
- **Supersedes attempt:** [#6115](https://github.com/jikig-ai/soleur/pull/6115) (reverted via [#6117](https://github.com/jikig-ai/soleur/pull/6117)) — this decision corrects that attempt: it covers BOTH SDK factories (#6115 fixed only `cc-dispatcher.ts`) and the residual in-process SKILL.md reader, and it does not gate on the (falsified) "regenerate the ADR-079 canary fixture" premise.
- **Relationship to prior ADRs:** does not reverse ADR-044 (workspace connection resolution) or ADR-080 (runtime plugin deploys via image rebuild — the deployed root's provenance). Reconciles with ADR-079 (bwrap canary): this change does not touch `buildAgentSandboxConfig`, so the committed `sandbox-canary-argv.json` fixture is unchanged and no regeneration is required. Extends the trust-boundary modeling first introduced for the untrusted `contributor` PR-author (ADR-074, C4 `model.c4`).

## Context

A Concierge (web) session runs its Soleur plugin — commands, skills, agents, **and executable `hooks/hooks.json` command-hooks** — under the Agent SDK. Both real-SDK factories set `plugins: [{ type: "local", path: <workspacePath>/plugins/soleur }]`:

- `cc-dispatcher.ts` — the cc-soleur-go Concierge factory (the dominant production path).
- `agent-runner.ts startAgentSession` — the legacy domain-leader factory.

For a workspace whose **connected repo ships its own committed `plugins/soleur/`** (the operator dogfoods Soleur on `jikig-ai/soleur` itself, and any customer who forks or points at soleur tomorrow), that workspace-relative path resolves to the **connected repo's frozen committed copy** instead of the platform-deployed plugin. This is one bug with two faces:

1. **Security (untrusted-code execution).** The connected repo's `hooks/hooks.json` registers `type:"command"` hooks (SessionStart / Stop) that the SDK runs as **subprocesses of the Node dispatch process — outside the bwrap tool sandbox, with the server process's environment and privileges**. Loading the workspace copy therefore executes arbitrary untrusted repo shell in the platform's trusted dispatch context. A separate in-process reader, `context-queries-hook.ts`, additionally sourced skill `SKILL.md` frontmatter from the untrusted workspace copy into the agent context (prompt-injection-adjacent).
2. **Delivery (#4826 wedge).** Because commands/skills load from the frozen copy, **every platform plugin fix is silently shadowed** for that workspace — the root cause of the multi-round #4826 worktree-creation wedge (deployed `worktree-manager.sh` guard fixes never ran).

`getPluginPath()` (`SOLEUR_PLUGIN_PATH || /app/shared/plugins/soleur`) already resolves the platform-deployed root, is sandbox-readable (`--ro-bind / /`), and is boot-validated by `verifyPluginMountOnce()`. It was consumed by `workspace.ts` and `plugin-mount-check.ts` but **not** by the SDK load path.

## Decision

**Always load the SDK plugin/hook/skill source from the platform-controlled deployed root (`getPluginPath()`), never the connected-repo workspace copy. The workspace copy is untrusted and inert for the SDK.**

1. **Both real-SDK factories bind `plugins: [{ path: getPluginPath() }]`.** `cc-dispatcher.ts` and `agent-runner.ts startAgentSession` both source the plugin path from `getPluginPath()` (an absolute, workspace-independent `/app/` path). `pluginJsonPath` (MCP-server-name extraction) derives transitively.
2. **The residual in-process SKILL.md reader sources from the deployed root too.** `context-queries-hook.ts`'s `skillsDir` sources from `getPluginPath()`. The `knowledge-base/` root stays workspace-relative — it is repo content, and injected pointers are gated by `git ls-files` committed-only + realpath containment (path-trust ≠ content-trust; ADR-086 §Consequences).
3. **A loaded-gun guard makes a regression fail loudly.** `assertTrustedPluginPath()` (reusing the `/app/` allowlist from `getPluginPath()`) wraps the `plugins:[{path}]` binding at the shared `buildAgentQueryOptions` chokepoint. If a future change threads a workspace-relative path into that binding, it throws in production instead of silently re-opening the hole. It is test-tolerant (mirrors `getPluginPath()`'s VITEST/NODE_ENV=test bypass — fixtures use mkdtemp roots).

**Scope of this decision (Slice A).** The SDK/reader load-source move + the guard. The delivery half — injecting `CLAUDE_PLUGIN_ROOT` into the sandboxed agent bash env and migrating the shelled-out `worktree-manager.sh` invocations off `./plugins/soleur` — is a **separately-sequenced follow-up** (Slice B, tracked in [#6121](https://github.com/jikig-ai/soleur/issues/6121)) that carries the sharper, on-host-unverified safe-bash + env-propagation surface; it is not gated by this decision. The connected-repo `git pull` workaround remains covered by #6108 in the interim.

## Consequences

- **Positive:** the SDK plugin/hook source has **zero dependence on the untrusted workspace** — a connected repo cannot influence it. The in-process command-hook execution threat is closed; the #4826 delivery shadow is closed for the SDK load path. Canary-neutral: `buildAgentSandboxConfig` is untouched, so the ADR-079 fixture and the blocking bwrap probe are unaffected.
- **Negative / accepted:** the shelled-out `bash ./plugins/soleur/.../worktree-manager.sh` invocations in deployed skills are still CWD-relative (CWD = workspace), so they still run the connected repo's committed script until Slice B lands. This is why the "no manual `git pull`" hard requirement is only fully met by the sequenced second PR; #6108 + the interim workaround cover it meanwhile.
- **Operational:** a `canary_sandbox_failed` on the re-apply deploy must be triaged as a **HOST bwrap/userns issue** (the #4932/#5849 false-rollback lineage — read `/hooks/deploy-status` for the actual reason), **not** as a plugin-path problem to revert. Reverting the plugin fix for that reason would repeat the misattribution the whole saga was made of.

## Alternatives considered

| Alternative | Rejected because |
|---|---|
| **Force-symlink `<workspace>/plugins/soleur` → deployed** (delete the committed dir, replace with a symlink) | Weak — the SDK load path is still a workspace path (a scaffolding race falls back to untrusted code); AND catastrophic for the dogfooder's working tree (`git status` shows all of `plugins/soleur/` deleted+symlinked). |
| **Non-colliding workspace symlink `<workspace>/.soleur-plugin` → deployed**, point the SDK there (#6117's proposed direction) | Still routes the SDK load through a symlink in the untrusted workspace dir (a malicious repo can pre-create it). Its only claimed advantage — "`/app/shared` is not sandbox-accessible" — is refuted: the sandbox binds the entire root read-only, and `getPluginPath()` is already the boot-validated path. |
| **Document-only the ignored `pluginPath` arg** (no runtime guard) | A comment does not stop a future dev from wiring a workspace-derived path into `plugins:`. The loaded-gun `assertTrustedPluginPath` converts that regression into a loud production failure. |
| **Regenerate the ADR-079 canary fixture as part of this change** (the original request's framing) | A no-op: the fixture is produced without `plugins:`/`--setenv` in the projection, so neither the plugin-path change nor `CLAUDE_PLUGIN_ROOT` injection can alter it. Retained only as a defensive contingency. |
