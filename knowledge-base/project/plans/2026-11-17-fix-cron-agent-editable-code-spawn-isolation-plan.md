---
title: "fix(security): cron claude spawns get a fresh per-spawn HOME and load the plugin and allowlisted scripts from the read-only deployed copy"
type: fix
date: 2026-11-17
slug: fix-cron-agent-editable-code-spawn-isolation
branch: feat-one-shot-12824-cron-spawn-isolation
issue: 12824
closes: 12824
ref: [12824, 9601]
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# fix(security): cron claude spawns get a fresh per-spawn HOME and load the plugin and allowlisted scripts from the read-only deployed copy

`Closes #12824` goes in the PR body, never the title. `Ref #9601` (the agent security hardening epic) is a
reference only; the PR must not close the epic. Dark launch: no feature flag, no Doppler `prd` change, no
production write, no live cron trigger, no label edit on existing issues, one PR.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-11-17. **Sections enhanced:** Overview, Property List, Proposed Solution, Phase 0,
Phase 2, Attack Surface, User-Brand Impact, Observability, Guard Contract (all three guards), ADR,
Acceptance Criteria, Risks, Research Insights. **Agents:** security-sentinel, observability-coverage-reviewer,
user-impact-reviewer, test-design-reviewer, learnings-researcher, a verify-the-negative pass and a
post-edit self-audit pass; forks ruled by the CTO agent (S1-S5).

### Key Improvements

1. **Server RCE closed (CTO S1).** `/app/.next` is chowned to uid 1001 and no write pattern covered it,
   so any file-tool cron's agent could plant code the web server (prod secrets; the cron host) loads. The
   containment hook now allows Write/Edit only under the run's own clone and HOME (allow-by-root, realpath
   of nearest existing ancestor), which also closes cross-cron planting and founder-workspace writes.
2. **No cron runs code its agent wrote (R5/A4 reversed).** Bug-fixer loses `vitest run` and
   `install_deps`; the census's all-writable set and exemption map are both empty.
3. **Observability made true:** setup-step failures post heartbeat ok:false but file no FAILED issue (claim
   corrected); `reportSilentFallback(null, …)` with tags to survive Sentry dedup; three new failure-mode
   rows; teardown at warning level.
4. **Test design hardened:** Guard 2 on the real filesystem; resolver takes its candidate path as a
   parameter (the `getPluginPath()` silent swap would make the untrusted row pass for the wrong reason);
   H1 uses a known-writable control; census root is the constant, not a fixture env.
5. **Git hardening (S5)** and a measured nested-CLAUDE.md import arm (S3, Phase 0.7g).

### New Considerations Discovered

- CI runs agent-committed site code with secrets (F6, pre-existing).
- Playwright's default browser path is `$HOME/.cache`; Phase 0.6 records where the image's browser lives.
- The `discoverability_test.expected_output` is now the single literal `deny` (Check 10 tokenizes it).
- The helper module is `_cron-spawn-fs.ts` (underscore prefix, so it is not presumed a new Inngest
  function by the task-design gate).

## Overview

Crons that give their spawned `claude --print` child the file tools (Write/Edit) run that child in a
fresh clone of the repository, load the plugin from that same clone, and let it run scripts from that
clone, all while the child holds an installation token and the operator Anthropic key. The child can
therefore change code it is then allowed to run. This plan isolates the spawn: a fresh, empty `HOME`
per spawn, and plugin and script execution from the deployed, kernel-read-only copy of the vendored
plugin instead of the editable clone. It also measures two of the reported paths against the real CLI
and adds a census test for the write-and-execute class.

The brief named `/opt/soleur/plugin` as "the image's read-only vendored plugin copy". It is the vendored
copy, but it is not read-only (the Dockerfile chowns it to the runtime user). The read-only copy of the
same tree is the `:ro` bind at `/app/shared/plugins/soleur`, seeded from `/opt/soleur/plugin` at deploy.
The CTO agent ruled (R1, 2026-11-17) that the plan targets that mount. See Research Reconciliation.

What this PR closes, and what it does not, stated plainly:

- **Closed:** path 1 (edit an allowlisted script in the clone, then run it), path 3 (edit a plugin hook
  the CLI loads via `--plugin-dir`) for all 12 plugin-loading functions (11 crons plus `event-ship-merge.ts`), the cross-run half of path 4
  (`~/.bashrc` and any other HOME file planted in one run and read by a later one), and the cross-run
  npm-cache variant of it (`~/.npm/_npx` is no longer shared between ux-audit runs).
- **Also closed (deepen-pass, CTO S1 and the R5/A4 reversal):** path 2 for bug-fixer. Its allowlist
  loses `./node_modules/.bin/vitest run` and its spawn env sets `SOLEUR_WORKTREE_SKIP_INSTALL=1`, so no
  cron keeps a verb that runs code the agent wrote. Bug-fixer therefore opens fixes without a local test
  baseline (fix-issue's SKILL documents "proceed without a baseline"); CI still runs the suite on its PR.
- **Write confinement (CTO S1).** The containment hook's `decide()` allows Write/Edit/MultiEdit only when
  the realpath of the target's nearest existing ancestor is under the run's own clone (`spawnCwd`, derived
  from the hook's own file location) or the run's own spawn HOME (accepted only when `process.env.HOME`
  is exactly `<dirname(spawnCwd)>/home-*`; otherwise the clone only). This closes a pre-existing server
  RCE found while deepening: `/app/.next` is chowned to uid 1001 (Dockerfile) and no write pattern covered
  it, so a prompt-injected agent in any file-tool cron could plant code the web server (holding every prod
  secret, and the process that runs the crons) loads. It also closes cross-cron planting (S2), writes into
  another live run's HOME (T9) and founder workspaces under `/workspaces/<uuid>`.
- **Not closed, tracked:** the installation token and the operator Anthropic key are still in the agent
  env (path 2's root fix, the brief's scope-out, F1). With no exec verb left the agent cannot run its own
  code with them, but a context-injection route could still surface them (S3, measured in Phase 0.7g).
  CI runs agent-committed code with secrets (Eleventy `_data/*.js`, Nunjucks-rendered markdown; F6).
  Pre-existing and filed, not fixed here.

## Research Insights

### Premise Validation

- #12824 is OPEN (P1, type/security). The only open PR naming it is #12847, this branch's own draft
  (collision pre-check `SOLEUR_COLLISION exit=10 prs=12847 foreign=none`); no foreign run.
- #12757 is CLOSED by #12806 (merged 2026-11-16T17:11Z), so `CRON_GIT_CONFIG_PIN` is on `main` and
  `spawnClaudeEval` already spreads it last (`_cron-claude-eval-substrate.ts`, the `env:` literal of
  the `spawn(claudeBin, …)` call). #12814 (non-inngest git pin) and #9601 (epic) are OPEN.
- **STALE premise — "the image's read-only vendored plugin copy" at `/opt/soleur/plugin`.** The copy
  exists (`apps/web-platform/Dockerfile`, `COPY _plugin-vendored /opt/soleur/plugin`), but the same
  Dockerfile later runs `RUN chown -R 1001:1001 /opt/soleur` before `USER soleur` (uid 1001), and no
  `docker run` passes `--read-only`. The runtime user can write it, and a write there outlives the
  run (it lasts until the next redeploy), which is worse than the per-run clone. The read-only copy
  of the same vendored tree is the host mount `-v /mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro`
  (`apps/web-platform/infra/ci-deploy.sh`, both the canary and the prod `docker run`;
  `apps/web-platform/infra/cloud-init.yml`), seeded at deploy from `/opt/soleur/plugin` of the
  verified image. `server/plugin-path.ts` `getPluginPath()` returns it and `assertTrustedPluginPath()`
  guards it; ADR-093 already requires the hosted SDK to load the plugin from that absolute `/app/`
  path. This plan therefore targets `getPluginPath()`, not the literal `/opt/soleur/plugin`.
- **Correction to the brief — the crons run in the web container.** Inngest functions execute on the
  web host's `soleur-web-platform` container (`server/inngest/execution-placement.ts`), not on the
  dedicated Inngest host, so the web image's paths and mounts are the ones that apply.
- The two hook files the CLI runs on every tool call (`cron-bash-allowlist-hook.mjs`,
  `cron-gh-output-framing-hook.mjs`) are not in the image as standalone files; they run from the clone
  (`HOOK_REL_PATH`, `FRAMING_HOOK_REL_PATH` joined to `spawnCwd`) and are write-protected by existing
  `WRITE_PROTECTED_PATTERNS` entries.

### Property List

- P1. No code a cron's agent can write is later executed by that cron with the spawn's secrets, other
  than the tracked, named exemptions (path 2 and anything it subsumes).
- P2. Nothing a cron's agent writes into its own `HOME` survives into a later spawn, and no agent can Write outside its own run's clone and HOME (CTO S1, which also closes the concurrent same-uid case).
- P3. The plugin a cron loads (skills, agents, hooks) is the deployed plugin, not the clone's copy.
- P4. The allowlisted scripts a cron may run are the deployed copies, and the clone copies are denied.
- P5. Paths 3 and 4 are measured on the real CLI, with the result recorded in the PR.
- P6. A test goes red when any cron can both write and execute the same path.
- P7. No cron's agent can write a path that the process hosting the crons (the web server, holding prod
  secrets) executes, and no cron holds a verb that runs code the agent wrote (deepen-pass, CTO S1).

### Cut List

- Adding write-protect patterns for `plugins/soleur/**`, `~/.bashrc` and test files → P1/P4 → cut by
  the 2026-11-16 CTO ruling (it denies the edits bug-fixer exists to make, leaving issues permanently
  `bot-fix/attempted`). Not reopened here.
- A separate bind-mount or new image path for the plugin → P3/P4 → already covered by the existing
  `:ro` mount at `/app/shared/plugins/soleur` plus `getPluginPath()`.
- A per-cron "fresh HOME" helper in each `buildSpawnEnv` → P2 → covered by the existing
  `spawnClaudeEval` chokepoint, which already overrides env last for the git pin.

### Relevant files

- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — `spawnClaudeEval` /
  `spawnClaudeEvalUnguarded` (the single chokepoint for all 19 claude spawns), `setupEphemeralWorkspace`,
  `buildCronEvalSettings`, `CRON_BASH_ALLOWLISTS`, `buildAllowlistLines`, `runHookSelfTest`,
  `budgetFlags` refusal precedent (`--max-budget-usd`, #8611).
- The 12 files that pass `"--plugin-dir","plugins/soleur"` in their own `CLAUDE_CODE_FLAGS`:
  `cron-bug-fixer.ts`, `cron-agent-native-audit.ts`, `cron-architecture-diagram-sync.ts`,
  `cron-campaign-calendar.ts`, `cron-competitive-analysis.ts`, `cron-content-generator.ts`,
  `cron-growth-audit.ts`, `cron-growth-execution.ts`, `cron-legal-audit.ts`, `cron-seo-aeo-audit.ts`,
  `cron-ux-audit.ts`, `event-ship-merge.ts` (all under `apps/web-platform/server/inngest/functions/`).
- `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs` — `decide()`: Write/Edit/MultiEdit are
  allowed for every path that misses `WRITE_PROTECTED_PATTERNS`, so a file-tool cron can write anywhere
  uid 1001 can.
- `apps/web-platform/server/plugin-path.ts` — `getPluginPath()`, `assertTrustedPluginPath()`,
  `isPluginPathTestEnv()`.
- `apps/web-platform/server/host-git.ts` — `CRON_GIT_CONFIG_PIN`, `xdgGitResidualPresent(home)`.
- `apps/web-platform/server/inngest/functions/_cron-shared.ts` — `resolveCronWorkspaceRoot()`
  (`CRON_WORKSPACE_ROOT=/workspaces` in prod); `cron-workspace-gc.ts` sweeps `soleur-*` dirs older than 1h.
- `plugins/soleur/hooks/hooks.json` — PreToolUse hooks on Bash/Write/Edit and SessionStart hooks, all
  `${CLAUDE_PLUGIN_ROOT}`-relative; per ADR-277 cron spawns get none of the `SOLEUR_DISABLE_*` overrides,
  so these hooks run inside cron spawns with the spawn env (path 3 reaches all 12 plugin-loading functions).
- `plugins/soleur/skills/fix-issue/SKILL.md` — calls
  `bash "${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh" --yes create …` and the
  literal `./node_modules/.bin/vitest run --root apps/web-platform`.
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — `create` runs `install_deps`
  (`bun install` / `npm ci`) in the new worktree unless `SOLEUR_WORKTREE_SKIP_INSTALL=1` or
  `--no-install`; package lifecycle scripts come from the editable clone (a transitive write-and-execute
  composition through a read-only script). It finds the repo from the CWD (`git rev-parse`), and its own
  libraries from `SCRIPT_DIR`, so it runs correctly from the read-only root with CWD in the clone.
- `apps/web-platform/.dockerignore` — the vendored tree keeps only `md/json/njk/yml/yaml/sh/txt` and
  `.claude-plugin`; `.py/.ts/.mjs/.cjs/.js` plugin files are absent from the deployed copy. No allowlisted
  cron script is one of those types (only `.sh`).
- Tests that pin today's shape (will need updates): `cron-producer-output-wiring.test.ts`,
  `cron-content-generator.test.ts`, `cron-untrusted-preamble.test.ts` (argv `--plugin-dir plugins/soleur`);
  `cron-claude-eval-substrate.test.ts` (allowlisted script commands, `makeSpawnCwd`);
  `cron-spawn-git-config-pin.test.ts` (`KNOWN_HOME_LITERALS`, every `HOME:` literal ends in
  `...CRON_GIT_CONFIG_PIN`); `cron-claude-eval-mcp-flags.test.ts`, `cron-bash-allowlist-hook.test.ts`
  (`CRON_BASH_ALLOWLISTS`); `claude-cli-pin-knows-models.test.ts` already spawns the CLI under a temp HOME
  (precedent).

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-06-07-headless-claude-print-plugin-skill-resolution-needs-plugin-dir.md`
  — headless `--print` needs an explicit `--plugin-dir` before `--`; keep it, change only its value.
- `knowledge-base/project/learnings/2026-06-10-bot-cron-safe-commit-substrate-symlink-removal.md` — a
  scrubbed-HOME probe must run a negative control first (a user-level plugin install leaks into results);
  the earlier symlink into the host plugin dir was read-write and cron runs mutated the live install.
- `knowledge-base/project/learnings/2026-05-15-deterministic-permissions-empirical-probes-and-review-gaps.md`
  — probe the CLI, not the docs; a hook with the wrong output envelope silently does nothing.
- `knowledge-base/project/learnings/integration-issues/2026-06-08-headless-claude-print-is-deny-list-and-hook-driven-not-allow-list.md`
  — `--allowedTools` does not fail closed headless; only the hook does, and only at the tool layer.
- `knowledge-base/project/learnings/bug-fixes/2026-07-06-connected-repo-shadows-deployed-plugin-via-workspace-relative-path.md`
  — a workspace copy of `plugins/soleur/` shadows the deployed plugin; the load path must be absolute.
- `knowledge-base/project/learnings/bug-fixes/2026-06-29-cron-mcp-telemetry-egress-silence-at-source.md`
  — `--plugin-dir` auto-connects the plugin's MCP servers; keep `--strict-mcp-config` and
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`.
- `knowledge-base/project/learnings/2026-06-07-self-discovering-parity-guard-for-cross-producer-drift.md`,
  `2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`,
  `2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md`
  — a census discovers its population structurally, asserts identity against a stored map, has a
  non-vacuity floor, and is shown red on a seeded violation.

### Functional overlap and external research

- Functional-discovery found no community skill or agent that does per-spawn HOME isolation or
  read-only plugin loading for a spawned CLI ("none relevant").
- No external research: the change is confined to this repo's substrate, whose behavior is measured
  against the pinned CLI rather than taken from docs.

- **Deepen-pass additions (2026-11-17).**
  `knowledge-base/project/learnings/2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md`:
  the spawn env stays an allowlist; the new `HOME`/`TMPDIR` keys are added to the literal, never via a
  spread of `process.env`. `knowledge-base/project/learnings/2026-04-29-bind-mount-seed-detection-needs-late-sentinel.md`:
  `.seed-complete` (written last) is the completeness proof, not the manifest; the resolver checks both.
  `knowledge-base/project/learnings/2026-06-12-inngest-cron-heartbeat-gate-on-final-attempt-and-step-memoization.md`:
  the resolver's verdict lives in the memoized setup step, so a retried claude-eval step reuses it; the
  exit-time seed-tag compare is what catches a mount that changed after setup.
  `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`:
  the census floor is a fixed constant (not indexed to the discovered count), and H1 uses a known-writable
  control. `knowledge-base/project/learnings/2026-03-05-verify-pretooluse-hooks-ci-deterministic-guard-testing.md`:
  hooks are re-verified in the headless `--print` context (Phase 0.3), not assumed from interactive runs.
  `knowledge-base/project/learnings/2026-04-19-enoent-on-optional-mount-should-not-alarm.md`: in CI and
  local dev the mount is legitimately absent; the resolver throws (fail closed) but tests never reach the
  real mount, and no boot-time alarm is added.

### CLAUDE.md conventions in force

`hr-observability-as-plan-quality-gate`, `cq-write-failing-tests-before`, `hr-autonomous-loop-skill-api-budget-disclosure`
(the local CLI measurement spends a few cents of API usage), `hr-weigh-every-decision-against-target-user-impact`,
`wg-when-deferring-a-capability-create-a` (the path-2 follow-up), `cq-silent-fallback-must-mirror-to-sentry`.

### CTO rulings applied (2026-11-17, during planning)

Full table in `knowledge-base/project/specs/feat-one-shot-12824-cron-spawn-isolation/decision-challenges.md`.
R1 read-only mount via `getPluginPath()` plus a runtime read-only and `.seed-complete` check; R2 the
substrate owns `--plugin-dir` with a required `loadPlugin`; R3 fresh HOME for every claude spawn at the
chokepoint; R4 both script-allowlisting crons move to the read-only root; R5 (reversed at deepen-pass by CTO S1:
bug-fixer loses vitest and `install_deps`, no exemption); R6 the `.bashrc` decision rule, pinned to the CLI
version measured; R7 the census anchor, plus MCP commands as executed paths and stale exemptions red;
R8 a separate cross-tenant Write issue (superseded by CTO S1: the Write confinement lands in this PR); R9 amend ADR-033 (cron spawn); A1 ux-audit is checked under a
fresh HOME and never falls back to the shared npm cache; A2 no new pattern for the spawn HOME's `.claude`.

## Research Reconciliation — Spec vs. Codebase

| Brief / issue claim | Reality on `main` | Plan response |
|---|---|---|
| "the image's read-only vendored plugin copy (Dockerfile `_plugin-vendored`)" | `/opt/soleur/plugin` is the vendored copy but `RUN chown -R 1001:1001 /opt/soleur` makes it writable by the runtime user, and writes persist until redeploy | Load from `getPluginPath()` (`/app/shared/plugins/soleur`, `:ro` bind of the same tree), with a runtime not-writable check (R1) |
| "15 crons load via `--plugin-dir`" (issue path 3) | 12 files pass `"--plugin-dir","plugins/soleur"`; 18 call sites reach `spawnClaudeEval` | The census counts by identity map, not by the issue's number; the plan uses the measured 12 |
| bug-fixer passes `HOME: process.env.HOME` | True, and so does every other cron `buildSpawnEnv`; the substrate spreads `buildSpawnEnv` then `CRON_GIT_CONFIG_PIN` | The fresh HOME is applied once at the chokepoint, after `buildSpawnEnv`, before the pin (R3) |
| allowlisted script is run from the clone | `bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` (bug-fixer) and 13 `community-router.sh` lines (community-monitor) | Both move to `bash <plugin-root>/…`, substituted at allowlist-build time (R4) |
| (unstated) a read-only script runs only read-only code | `worktree-manager.sh create` runs `install_deps` in the new worktree; lifecycle scripts come from the editable clone | Closed: bug-fixer sets `SOLEUR_WORKTREE_SKIP_INSTALL=1` and loses vitest (R5 reversed, CTO S1) |
| (unstated) the hook files run from the image | They run from the clone and are write-protected by existing patterns | Classified as pattern-protected in the census; no relocation (out of scope) |
| crons run on the Inngest host | They run in the web container on the exec host | Paths and mounts are the web container's |

## Problem Statement

`spawnClaudeEval` is the one chokepoint every cron's `claude --print` child passes through. Today it:

1. runs the child with `HOME` inherited from the container (`/home/soleur`), which persists across every
   run until the next redeploy, so a file one run plants in `HOME` is read by every later run and by
   other consumers of that HOME;
2. lets each cron pass `--plugin-dir plugins/soleur`, a path relative to the clone, so the CLI loads
   skills, agents and hooks from files the agent can edit with Write/Edit, and runs the plugin's
   `PreToolUse` and `SessionStart` hook scripts with the spawn env;
3. writes an allowlist file whose `bash plugins/soleur/…` lines name scripts inside the same clone.

The containment hook checks the command, not the file the command runs. The fix is to make every path
a cron executes either unwritable by that cron or not executed in a later spawn, and to prove it with a
census that goes red when a cron can write and execute the same path.

## Proposed Solution

- **Plugin root (R1, R2).** A new `resolveCronPluginRoot()` in the substrate returns
  `assertTrustedPluginPath(getPluginPath())` after these checks, each a throw (the cron fails closed;
  there is no fallback to `/opt/soleur/plugin` or to the clone): the manifest
  `.claude-plugin/plugin.json` exists; `.seed-complete` exists (same sentinel `plugin-mount-check.ts`
  reads; one retry after about 30 s, CTO T1); neither the root nor `hooks/` is writable by the process
  (the `W_OK` probe in `_cron-spawn-fs.ts` must throw `EROFS` or `EACCES`); and it is absolute. Details in
  Phase 2.1. `spawnClaudeEval` refuses a caller-supplied `--plugin-dir` in both the
  `--plugin-dir X` and `--plugin-dir=X` forms, as it already refuses `--max-budget-usd`. `SpawnArgs`
  gains a required `loadPlugin: boolean`; when true the substrate inserts `--plugin-dir <root>` before
  the caller's flags (so it can never land after the caller's trailing `--`). The 12 plugin-loading
  crons drop their flag pair and pass `loadPlugin: true`; the other callers pass `loadPlugin: false`.
- **Per-spawn HOME (R3).** Inside `spawnClaudeEvalUnguarded`, before the child starts:
  `mkdtemp(join(ephemeralRoot, "home-"))` (CTO T4: a sibling of `repo/`, never under `spawnCwd`, so
  `~/.claude.json` and session state can never land in the git tree; one assertion pins
  `!spawnHome.startsWith(spawnCwd + sep)`), then `mkdir(<spawnHome>/tmp, 0o700)` (CTO T5), then the env is
  `{ ...buildSpawnEnv(token), HOME: spawnHome, TMPDIR: <spawnHome>/tmp,
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1", ...CRON_GIT_CONFIG_PIN }`. `mkdtemp` already creates mode
  0700. The HOME is removed in the same `finally` that clears the heartbeat timer; a removal failure
  reports `cron-spawn-home-teardown` through `warnSilentFallback` (warning, no page) and does not fail the run. Living
  inside the run's ephemeral root, a leaked HOME shares the workspace's existing teardown
  (`teardownEphemeralWorkspace` removes `ephemeralRoot`) and `cron-workspace-gc` sweep, with no new GC
  prefix and no separate age race. Tools that hard-code `/tmp` instead of honouring `TMPDIR` are a noted
  residual, not chased here. Per-cron
  `HOME: process.env.HOME` lines stay, each with a one-line comment that the substrate overrides it.
- **Allowlisted scripts (R4).** `CRON_BASH_ALLOWLISTS` and `COMMUNITY_ROUTER_READ_VERBS` keep a
  placeholder token `<plugin-root>` in place of `plugins/soleur`; `buildAllowlistLines` substitutes the
  resolved root, passed as an explicit `pluginRoot` parameter so the function stays pure
  (`buildAllowlistLines(cronName, allow, env, pluginRoot)`; a line still carrying the token after
  substitution, or carrying `$`, throws). `setupEphemeralWorkspace` resolves the root once, for every cron
  whose lines carry the token or whose spawn has `loadPlugin: true` (13 crons: the 12 plugin loaders plus
  community-monitor), returns it with `{ephemeralRoot, spawnCwd, pluginRoot}`, and the spawn reuses it, so
  the setup step and the claude-eval step cannot disagree. **`runHookSelfTest` receives the substituted
  lines, not the raw `allow` map value** (today it gets `allow` at the `runHookSelfTest({ … allow, … })`
  call in `setupEphemeralWorkspace`; with a raw `<plugin-root>` token in `allow[0]` the hook would deny
  community-monitor's self-test verb and abort every run). The community-monitor prompt is built from the
  same substituted lines through an explicit placeholder map (the allowlist's `<uint>` slot renders as the
  prompt's `<channel_id>`), and the existing prompt-grammar test stays, so the prompt and the allowlist
  cannot disagree. The relative clone forms are dropped, so `bash plugins/soleur/…` is denied.
- **ux-audit MCP from the image (CTO T6).** ux-audit's MCP `command` switches unconditionally from
  `npx @playwright/mcp@0.0.75` to the root-owned `/app/node_modules/.bin/` binary of the same pinned
  package (`test/playwright-mcp-version-pin.test.ts` already pins the version): `npx` runs code from a
  HOME cache, which is the write-then-execute class this PR closes. `PLAYWRIGHT_BROWSERS_PATH` is not set
  here. If Phase 0.6 shows uid 1001 cannot reach the root-installed browser, that is a pre-existing
  breakage recorded with a follow-up (an image change), not fixed here.
- **Plugin seed integrity (CTO T1).** `ci-deploy.sh` reseeds the `:ro` mount source in place
  (`find "$DST" -mindepth 1 -delete; cp -a …`) while the old container may still run crons. For crons this
  race is new in this PR (their plugin used to come from the clone); the PR body and the ADR-033 residual
  list say so. In-PR: at resolve, a missing `.seed-complete` waits about 30 s and retries once, then throws
  `NonRetriableError` (`seed-incomplete`); the resolver records the seed tag from `.seed-complete` at
  spawn and re-reads it at exit, and a mismatch reports `plugin-reseeded-mid-run` through
  `reportSilentFallback` and marks the run degraded. The atomic versioned-seed swap is follow-up F3; a
  canary readiness gate on the mount is follow-up F4 (CTO T3).
- **Vendored-file coverage (CTO T2).** The deployed copy holds only md, json, njk, yml, yaml, sh and txt
  (`apps/web-platform/.dockerignore`). A census row fails when a `${CLAUDE_PLUGIN_ROOT}/…` or
  skill-relative script path named by a skill a plugin-loading cron invokes is absent from the vendored
  file set (known: ship's `scripts/lint-ratchet.py` via event-ship-merge, ux-audit's
  `scripts/bot-signin.ts` and `bot-fixture.ts`). Each miss gets a recorded disposition: by default the
  call degrades as the skill documents; calling the clone path is allowed only for a cron with no
  Write/Edit and no arbitrary-exec verb, and needs an exemption row. A cron that can write must degrade.
  `.dockerignore` does not change (shipping executable `.py`/`.ts` into the hosted mount widens the
  hosted-session surface).
- **Measurements (paths 3 and 4).** Phase 0 runs the prod-pinned CLI locally in a scratch directory
  (see Phase 0) and records the result tables in the spec directory and the PR body.
- **Census (P6).** `cron-write-execute-census.test.ts` (Guard 1) plus the chokepoint tests (Guard 2) and
  the resolver tests (Guard 3).
- **Write confinement in the containment hook (CTO S1).** In `cron-bash-allowlist-hook.mjs`, the
  Write/Edit/MultiEdit branch becomes allow-by-root: resolve the target (absolute, `..` normalised), take
  the realpath of its nearest existing ancestor (so a symlink in the clone pointing outward resolves
  outside and is denied), and allow only when it lies under `realpath(spawnCwd)` or `realpath(spawnHome)`.
  `spawnCwd` is a fixed walk up from the hook's own file (`<spawnCwd>/apps/web-platform/server/inngest/…`),
  never an env value; `spawnHome` is accepted only when `process.env.HOME` equals a `home-*` child of
  `dirname(spawnCwd)`, so an env value cannot widen the area. Existing `WRITE_PROTECTED_PATTERNS` still
  apply inside both roots. This is an allow-list, not another deny pattern, so the 2026-11-16 ruling does
  not bar it. Deny reason: `cron-containment: write outside run roots: <path>`. The work phase lists every
  place a cron's prompt or skill writes (each must be inside the two roots, or the cron degrades as
  documented); `/tmp/ux-audit` and the Playwright profile move under `TMPDIR`/the spawn HOME.
- **No code-exec verb for any cron (R5/A4 reversed).** `CRON_BASH_ALLOWLISTS["cron-bug-fixer"]` drops
  `./node_modules/.bin/vitest run`, and bug-fixer's spawn env sets `SOLEUR_WORKTREE_SKIP_INSTALL=1`, so
  `worktree-manager.sh create` runs no `install_deps`. The census has no exemption for running code
  in-run; its all-writable set must be empty. The PR body says bug-fixer loses its local test baseline.
- **Git hardening (CTO S5).** At the `CRON_GIT_CONFIG_PIN` spread point add `GIT_CONFIG_COUNT=3` with
  `core.hooksPath=/dev/null`, `core.fsmonitor=false`, `safe.bareRepository=explicit`
  (`GIT_CONFIG_KEY_n`/`GIT_CONFIG_VALUE_n`; command-level config outranks the clone's `.git/config`).
  Today the pin carries only `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_NOSYSTEM` (`server/host-git.ts`), so nothing
  else sets a COUNT; a test fails if any other site sets `GIT_CONFIG_COUNT`. The #12757 census maps in
  `cron-spawn-git-config-pin.test.ts` are updated to match.
- **Follow-ups filed from this PR (beyond F1/F2).** F3: atomic versioned plugin seed with a symlink
  swap in `ci-deploy.sh` (CTO T1). F4: make the plugin-mount check a canary readiness gate (CTO T3). F6: CI runs
  agent-committed code with secrets (CTO S4, P1). F5,
  only if Phase 0.6 shows it: uid 1001 cannot reach the root-installed Playwright browser (image change).
  All `type/security` or `type/bug`, `domain/engineering`, no priority label.
- **Follow-ups filed from this PR.** F1 (path 2's root fix: take `GH_TOKEN` and `ANTHROPIC_API_KEY` out
  of the agent env; re-evaluation criterion: before any cron regains a local test runner or install, it
  must run tokenless; also lists `npm_config_ignore_scripts` and moving the hook `.mjs` to the `:ro` root).
  F2 (now: the Dockerfile chowns only `.next/cache`, so no uid-1001 code can write `.next/server`; needs an
  ISR measurement first; P1; the Write/Edit allow-list originally planned for F2 lands in this PR per
  CTO S1; `/app/node_modules/.vite-temp` is recorded here). Both `type/security`, `domain/engineering`; the priority
  of F2 is the operator's call (decision-challenges row O1).

## Technical Approach

### Architecture

```text
Inngest step (web container, uid 1001)
  setupEphemeralWorkspace ──► /workspaces/soleur-<cron>-X/repo         (clone: agent-writable)
                         └──► repo/.claude/{settings.json,cron-allow.txt}  (write-protected)
    resolveCronPluginRoot() ─► /app/shared/plugins/soleur              (:ro bind, EROFS; once per run, in setup)
  spawnClaudeEval
    mkdtemp ────────────────► /workspaces/soleur-<cron>-X/home-Y   (per spawn, 0700, sibling of repo/, rm in finally)
    claude --strict-mcp-config … [--plugin-dir /app/shared/plugins/soleur] <flags> -- <prompt>
         env: buildSpawnEnv ∪ {HOME: Y, TMPDIR: Y/tmp} ∪ CRON_GIT_CONFIG_PIN
         executes: plugin hooks/skills (ro) · containment + framing hook (clone, pattern-protected)
                   allowlisted `bash /app/shared/plugins/soleur/…` (ro) · no code-exec verb (vitest removed)
         writes:   Write/Edit only under repo/ and home-Y/ (hook allow-by-root, CTO S1)
```

### Implementation Phases

#### Phase 0: Measure before building (local only, no production)

All arms run the prod-pinned CLI (`@anthropic-ai/claude-code@2.1.321`, the pin in
`apps/web-platform/package.json` and the Dockerfile), invoked as
`npx --yes @anthropic-ai/claude-code@2.1.321` from a scratch directory under the session scratchpad,
never the operator's real HOME and never against prod. Auth: an `ANTHROPIC_API_KEY` read from Doppler
`dev` (read-only), passed only on the probe's env. API spend disclosure: about 8 runs of `--model haiku`
with `--max-turns` at most 6, roughly USD 0.05 in total (`hr-autonomous-loop-skill-api-budget-disclosure`).
The probe is a committed script, `knowledge-base/project/specs/feat-one-shot-12824-cron-spawn-isolation/probes/cli-isolation-probe.sh`,
so review can re-run it. A probe hook records only `set`/`unset` for `GH_TOKEN` (a dummy value), never
a value. Script guards: `--arm <id>` runs one arm; it refuses to run when `HOME` is not under the
scratch directory, refuses a `GH_TOKEN` that looks real (`ghs_`/`ghp_`/`github_pat_` prefix), keeps the
CLI version in one variable, and exits non-zero when an arm's verdict does not match its pre-written
branch.

- **0.1 Negative control.** Empty HOME, no `--plugin-dir`: the probe plugin's marker file must not
  appear (rules out a user-level plugin install leaking in, per the 2026-06-10 learning).
- **0.2 Fresh empty HOME works.** Empty HOME, `ANTHROPIC_API_KEY` only, `--print` with the prod flag
  shape (`--strict-mcp-config`, `--output-format json`, `--allowedTools`, `--plugin-dir <abs>`, `--`):
  the run returns a `result` event. Record which files the CLI creates in HOME.
- **0.3 Path 3, measured.** A scratch plugin with `hooks/hooks.json` registering a `PreToolUse(Bash)`
  hook script that appends a line to a log outside the plugin. Prompt: run `echo one`, then Edit the
  hook script to append `EDITED`, then run `echo two`. Result table: did the hook run in `--print`
  under `--plugin-dir`; did the edited body run on the next tool call; did it see `GH_TOKEN` as `set`.
  Control arm: the same with the plugin dir `chmod -R a-w` (the Edit must fail and the log shows no
  `EDITED`), which stands in for the read-only mount.
- **0.4 Path 4, measured.** `SHELL=/bin/bash`, empty HOME. Prompt: run `echo "[$PROBE_RC]"`, Write
  `$HOME/.bashrc` with `export PROBE_RC=sourced`, run `echo "[$PROBE_RC]"` again. Arm B: a second,
  separate spawn reusing the same HOME runs `echo "[$PROBE_RC]"`. Outcomes: in-run re-source (A prints
  `[sourced]` on the second call), cross-run only (B prints `[sourced]`), or neither. Decision rule (R6):
  cross-run is closed by the fresh HOME; an in-run result needs no exemption now, because no cron can run
  code it wrote (R5 reversed) and Write confinement keeps the rc file inside the run's own HOME; record it,
  pinned to 2.1.321.
- **0.5 `${CLAUDE_PLUGIN_ROOT}` substitution.** A scratch skill whose text is
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/x.sh"`: record the literal Bash command the CLI emits with an
  absolute `--plugin-dir`. If it is the absolute root, the new allowlist line matches the fix-issue
  SKILL's own call; if it stays unsubstituted, the hook denies `$` and fix-issue takes its documented
  `git worktree add` fallback (SKILL.md line 144). Record which, in the PR (CTO R4 dissent).
- **0.6 ux-audit MCP under an empty HOME (A1, CTO T6).** In the pinned web-platform image as uid 1001
  (if the image pulls locally, read-only; otherwise on the host, labelled `unverified-in-image`), with an
  empty HOME: run `/app/node_modules/.bin/playwright-mcp --help` (the pinned `@playwright/mcp@0.0.75`
  declares `"bin": {"playwright-mcp": "cli.js"}` in its `package.json`, and `apps/web-platform/package.json`
  lists it as a runtime dependency, so `npm ci` in the image places it under `/app/node_modules/.bin/`),
  and record whether the root-run
  `npx playwright install` (Dockerfile) left a browser uid 1001 can launch. A missing browser is recorded
  as pre-existing with a follow-up, not fixed here.
- **Decision branches, written before measuring (CTO A5).** 0.5: absolute → the absolute allowlist line
  matches; literal `${CLAUDE_PLUGIN_ROOT}` → the call is denied, the cron fails closed and reports FAILED;
  record it and never allowlist a `$` line. 0.4: the R6 rule above. 0.7b: a cold-cache failure is accepted
  (below). 0.7c: anything other than `EROFS`/`EACCES` fails the resolver.
- **0.7a git and gh under an empty HOME.** With `CRON_GIT_CONFIG_PIN` set and an empty HOME: `git commit`
  in a scratch repo succeeds with the pinned identity; `gh api /rate_limit` with a dummy `GH_TOKEN`
  reaches auth (a 401 is the expected pass, a config-dir error is the failure). No API spend.
- **0.7b Cold-cache install.** In a scratch copy of `apps/web-platform/package.json` + lockfile, empty HOME,
  registry unreachable (`npm_config_registry=http://127.0.0.1:9`): run `bun install --frozen-lockfile` and
  `npm ci`. (Bug-fixer no longer runs `install_deps`, R5 reversed; this arm now only
  records cold-cache behaviour for the record and F1.) Never point the npm or bun cache at the shared `/home/soleur`
  cache to keep it warm (a writable shared cache is a cross-run write-then-execute path); a per-spawn cache
  directory under the spawn HOME is acceptable.
- **0.7c `:ro` errno.** `docker run --rm -v <dir>:/p:ro node:22-slim node -e 'try{require("fs").accessSync("/p",2);console.log("OK")}catch(e){console.log(e.code)}'`
  as uid 1001 and as root; record both codes. The resolver accepts only `EROFS` and `EACCES`.
- **0.7d Clone remote branches (CTO A3 dissent).** In a `git clone --depth=1` of the repo (the substrate's
  exact clone shape, `setupEphemeralWorkspace`), record `git branch -r`. Static expectation: `--depth`
  implies `--single-branch`, and no cron allowlists `git fetch`/`git pull`, so only `origin/main` (and
  `origin/HEAD`) appear. If any other remote branch appears, roadmap-review's `git switch <name>` could
  check out a changed hook file: the census must then treat the hook files as writable for that cron, and
  the fix (deny the DWIM remote-tracking form in `gitVerbReason`) lands in this PR, not as an exemption.
- **0.7e worktree-manager from a read-only copy.** `worktree-manager.sh` sources
  `$SCRIPT_DIR/../../../scripts/lib/*.sh`. Run `bash <ro-copy>/skills/git-worktree/scripts/worktree-manager.sh --yes create probe-1`
  from a `chmod -R a-w` copy of the plugin tree with CWD in a `git clone --depth=1` scratch clone and
  `SOLEUR_WORKTREE_SKIP_INSTALL=1`; record that the libs resolve and the worktree is created in the clone,
  not under the plugin copy. No API spend.
- **0.7g Nested CLAUDE.md import (CTO S3).** In the spawn shape, a nested `CLAUDE.md` in the clone with an
  `@`-import of a canary file under `.git/` (a path the Read gate denies). Prompt the model to repeat any
  canary it sees; `--model haiku`, one turn. Decision branches, written before measuring: the canary does
  NOT reach context → record it, add nothing; it DOES → use a CLI-native way to exclude nested
  `CLAUDE.md`/`AGENTS.md` if the pinned CLI has one, else add a write-deny for
  `(^|/)(CLAUDE(\.local)?|AGENTS)\.md$` inside the confined roots, recorded as a narrow, explicit exception
  to the 2026-11-16 ruling (it blocks context injection of the tokenized `.git/config`, not deny-list sprawl
  over executed code). Also record `~/.claude.json` contents in arm 0.2.
- **0.7f Record.** Write `measurements.md` in the spec directory: CLI version, command, raw output
  excerpt and verdict per arm. These outputs become the fixtures of the tests that depend on them
  (the substituted command string, the HOME file list), not hand-written shapes.

#### Phase 1: Tests first (RED)

Write Guard 1, 2 and 3 suites and the updated shape tests against the new contract. They must fail on
`main` for the reasons in the Guard Contract matrices (`cq-write-failing-tests-before`).

#### Phase 2: Substrate and callers (GREEN)

- 2.1 `resolveCronPluginRoot()` and its errors (`CronPluginRootError` with a closed `reason` enum:
  `manifest-missing`, `seed-incomplete`, `writable`, `untrusted-path`), called once per run in
  `setupEphemeralWorkspace`, reported once per run through `reportSilentFallback` op
  `cron-plugin-root-untrusted` (tags `cron`, `reason`), then thrown as Inngest's `NonRetriableError` so a
  configuration fault does not retry into repeated Sentry events and operator emails. The not-writable
  check probes both the root and `hooks/` (a root-only probe misses a writable subtree). The error text
  names the local-dev cause ("plugin root must be a read-only mount; locally, bind-mount a copy `:ro`"),
  with no bypass setting. The filesystem calls live in one small module (`_cron-spawn-fs.ts`: resolver
  probes, HOME create/remove) so handler tests replace it with one `vi.mock` line; CI-as-root is handled by
  mocking that module, not by a chmod fixture. `getPluginPath()` silently falls back to the default when
  an override is untrusted, so a drifted `SOLEUR_PLUGIN_PATH` surfaces as `writable` or `seed-incomplete`
  on the default path, not `untrusted-path`; the Observability text says so.
- 2.2 `--plugin-dir` refusal (exact token `--plugin-dir` AND any token starting `--plugin-dir=`; do not
  copy the exact-token-only shape of the existing `--max-budget-usd` refusal) and the required
  `loadPlugin`; argv assembled by an exported pure `buildClaudeArgv(pluginRoot, args)` that takes the
  root as a parameter, so tests read the real argv without the test-env bypass in `getPluginPath()`.
- 2.3 Per-spawn HOME, its env position, its removal and `cron-spawn-home-teardown`. The `mkdtemp` runs
  inside the existing `try`, so its failure (ENOSPC on `/workspaces` is the case the GC exists for)
  still clears the heartbeat in `finally` and reports op `cron-spawn-home-create` before throwing. The
  removal runs after the process-group SIGKILL escalation has settled (await the exit and the
  escalation timer), never while a grandchild can still write into the HOME. `probeCronGitConfig()`
  runs against the spawn HOME (or the plan records why the container HOME is the right probe).
- 2.4 `<plugin-root>` substitution in `buildAllowlistLines`; `CRON_BASH_ALLOWLISTS["cron-bug-fixer"]`
  and `COMMUNITY_ROUTER_READ_VERBS`; the community-monitor prompt builds from the substituted lines.
- 2.5 The 12 plugin-loading functions drop the flag pair and pass `loadPlugin: true`; the other callers pass
  `false`; rewrite the stale header comments (the #5091/#5026 block in the substrate, and each cron's
  "`--plugin-dir plugins/soleur` registers the plugin (clone's tracked tree)" line).
- 2.6 ux-audit MCP `command` → `/app/node_modules/.bin/` binary, unconditionally (CTO T6).
- 2.7a Seed retry and seed-tag compare (CTO T1); vendored-file coverage row and per-miss dispositions
  (CTO T2).
- 2.8 Test plumbing: one shared seeded plugin-root fixture (manifest, `.seed-complete`, the mocked
  not-writable probe returning `EROFS`) wired through the test setup; derive every handler test that ends
  in a spawn with `git grep -l 'spawnClaudeEval\|setupEphemeralWorkspace' apps/web-platform/test` and
  update each (known: `cron-bug-fixer.test.ts` mocks `@/server/plugin-path` without
  `assertTrustedPluginPath`, does not mock `_cron-spawn-fs.ts`, and indexes `mkdtempSpy.mock.calls[0]`,
  which a second `mkdtemp` reorders). Phase 0 values the tests depend on are literals in the tests with a
  comment citing `measurements.md`, plus one test that fails when the CLI pin in `package.json` moves off
  2.1.321 ("re-run the Phase 0 probe").

#### Phase 3: Census and anchor (Guard 1)

`cron-write-execute-census.test.ts`, the anchor citing `docker-run-tuple.test.sh`, the exemption map, and the mutation
battery recorded in the PR.

#### Phase 4: ADR, follow-ups, measurements in the PR

- Amend `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`
  with a dated 2026-11-17 amendment (see Architecture Decision).
- File F1 and F2 with `gh issue create` (bodies name the residual, the re-evaluation criterion and the
  milestone from `knowledge-base/product/roadmap.md`); put their numbers into the census exemption map
  and the ADR residual list. No label edit on any existing issue.
- Copy the Phase 0 tables into the PR body.

## Alternative Approaches Considered

| Option | Why not |
|---|---|
| Load from `/opt/soleur/plugin` (the brief's literal path) | Writable by uid 1001 and persists across runs until redeploy (E1); worse than the clone |
| Write-protect `plugins/soleur/**`, tests and `~/.bashrc` | Rejected by the 2026-11-16 CTO ruling: bug-fixer must edit and test; it would also be one more deny list |
| Keep `--plugin-dir` in each cron and check it in a test | 12 copies that drift; the substrate already owns `--max-budget-usd` the same way (R2) |
| Fresh HOME only for file-tool crons | A per-cron split invites drift; one chokepoint covers all 18 call sites (R3) |
| Keep vitest and `install_deps` for bug-fixer, exempted to F1 (original R5/A4) | Reversed by CTO S1: code they run executes as uid 1001 below the Write hook and can write `/app/.next/server`; removing the token (F1) would not close that |
| Deny patterns for `/app/`, `/opt/soleur/` (S1 option b) | One more deny list (2026-11-16 ruling) and incomplete; the allow-by-root confinement covers every outside path |
| Make the spawn HOME read-only (0555 with pre-created rc files) | Out of scope; in-run execution is already open through path 2 (R6) |
| Relocate the hook `.mjs` files out of the clone | They are already pattern-protected; relocation needs an image change and is not this class |

## Technical Considerations

### Attack Surface Enumeration

Every way a file-tool cron's agent can get code it wrote executed with the spawn env, and what this PR
does to each:

| Path | Executed by | Writable by the agent after this PR | Disposition |
|---|---|---|---|
| Plugin hooks (`hooks/*.sh`), skills, agents | CLI via `--plugin-dir` | No (`:ro` mount, EROFS) | Closed (path 3) |
| `bash <plugin-root>/skills/…/worktree-manager.sh`, `community-router.sh` | Allowlisted Bash | No (`:ro`) | Closed (path 1) |
| `bash plugins/soleur/…` (clone copy) | Was allowlisted | Yes | Denied: no longer allowlisted |
| Containment and framing hook `.mjs` (clone) | CLI `PreToolUse`/`PostToolUse` | No (existing `WRITE_PROTECTED_PATTERNS`) | Unchanged, census-classified |
| `.claude/settings.json`, `cron-allow.txt` | CLI settings | No (`.claude` pattern) | Unchanged |
| `~/.bashrc` and other HOME rc files | CLI shell snapshot | Own run's HOME only | Cross-run closed; in-run measured (0.4), no code-exec verb to exploit it |
| `~/.claude/settings.json` hooks in HOME | CLI user settings | No (`.claude` pattern); fresh HOME has none | Inherited user settings removed |
| `~/.npm/_npx` (ux-audit MCP launch) | `npx` at session start | Yes, per spawn only | Cross-run closed |
| Test files run by `./node_modules/.bin/vitest run` | Was allowlisted (bug-fixer) | Yes | Closed: verb removed (R5 reversed) |
| `package.json` lifecycle scripts run by `install_deps` | `worktree-manager.sh create` | Yes | Closed: `SOLEUR_WORKTREE_SKIP_INSTALL=1` |
| `/app/.next/server/**` route chunks | The web server (holds prod secrets, runs the crons) | Was: yes (chowned to uid 1001) | Closed: Write confinement (S1); F2 removes the chown |
| Nested `CLAUDE.md` `@`-imports of `.git/config` | CLI context loader | Yes, inside the clone | Measured (0.7g); branch per S3 |
| Agent-committed `_data/*.js`, Nunjucks markdown | CI with secrets | Yes, via PR | Pre-existing → F6 |
| `.git/hooks`, `core.hooksPath`, `core.fsmonitor` | git | No (`.git` pattern) | Hardened: `GIT_CONFIG_COUNT` pin (S5) |
| `.mcp.json` in the clone | CLI | n/a (`--strict-mcp-config`) | Unchanged |
| Any path outside the run's clone and HOME (`/home/soleur`, `/workspaces/<uuid>`, another run's root, `/opt/soleur`) | Other consumers | Was: yes | Closed: Write confinement (S1) |

### Performance and cost

Resolver probes (manifest, sentinel, root and `hooks/` `W_OK`, seed tag) run once per run in setup, plus
one seed-tag re-read at exit; one `mkdtemp`, one `mkdir` and one `rm -r` per spawn; negligible against a multi-minute
spawn. No change to model, turns or budget flags.

### NFR impact

Security (containment) improves; availability risk is the fail-closed resolver (a missing or writable
mount fails every plugin-loading cron loudly rather than running unprotected). No latency or cost NFR moves.

## User-Brand Impact

- **If this lands broken, the user experiences:** scheduled agents that maintain the product (the bug
  fixer, audits, content, ship-merge follow-ups) stop producing their issues and PRs; each self-reports
  FAILED and its Sentry cron monitor goes red, emailing the operator (AC15; **falsified in review, see the
  addendum below and #12859**: the heartbeat goes red in Sentry, but no Terraform monitor binds these slugs,
  so nobody is emailed). No founder-facing UI changes.
  Three degraded modes land with it, each detectable: a skill step whose `.py`/`.ts` script is absent
  from the deployed copy degrades as the skill documents (for example event-ship-merge's ship flow runs
  without `scripts/lint-ratchet.py`); the vendored-file coverage row forces a recorded disposition per
  miss, and a degraded run must not report green. ux-audit's switch to the image's `playwright-mcp` may
  find no browser uid 1001 can launch (Phase 0.6 measures it; F5 if so). A deploy that reseeds the plugin
  mount mid-run can hand a running cron a mixed plugin tree, new for crons in this PR (seed-tag compare
  marks the run degraded; F3 fixes it).
- **Behaviour change the operator will see:** bug-fixer opens fix PRs without running tests locally
  first (vitest and `install_deps` removed); CI still runs the suite before merge, so a broken fix shows
  as a red PR rather than a skipped PR. A cron whose prompt writes outside its own clone and HOME now gets
  a `write outside run roots` deny and degrades as documented.
- **Still open after this PR (stated plainly):** the cron agents still hold a repo-write token and the
  Anthropic key in their env (F1). They can no longer run code they wrote, but a context-injection route
  could still surface the token to the model (Phase 0.7g measures the nested-CLAUDE.md case). CI runs
  agent-committed site code with secrets (F6). `/app/.next` is still chowned to uid 1001 in the image, now
  unreachable by the agent's Write tool but reachable by any future code-exec verb (F2).
- **Closed, which founders should know:** before this PR a prompt-injected file-tool cron could Write
  into founder workspaces under `/workspaces/<uuid>` and into the web server's build output; the Write
  confinement closes both.
- **If this leaks, the user's workflow is exposed via:** a prompt-injected issue, web page or social
  snippet steering a file-tool cron to rewrite a plugin hook or allowlisted script, which then runs with
  an installation token that can write `jikig-ai/soleur`, the repository every plugin user pulls from.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one successful exploit pushes code to every plugin user, so
  the strictest tier applies, matching the #12757 sibling in this epic. CPO sign-off is required at plan
  time; `soleur:engineering:review:user-impact-reviewer` runs at review.

### Addendum — 2026-11-17 (PR #12847 review)

The bullets above are the plan-time statement and are kept as written. The review changed four of them:

- **Operator email (AC15) is false.** The claude-eval crons' heartbeat slugs are not declared in
  `apps/web-platform/infra/sentry/cron-monitor-alerts.tf`, so a red heartbeat opens a Sentry issue that
  emails nobody. Measured with `grep -rl '"<slug>"' apps/web-platform/infra/sentry/` (no match for any of the
  13 slugs). The fix is #12859. Until it lands, a fail-closed cron is visible in Sentry only.
- **Founder workspaces are closed for writes, not for reads.** The Write confinement closes writes into
  `/workspaces/<uuid>`. `Read`/`Glob`/`Grep` there are still allowed by the hook, and the two server-cwd crons
  have no hook. A prompt-injected cron holding `gh issue create` could publish a founder's knowledge base.
  This predates the PR and is out of its scope; filed as #12863.
- **Write roots are the clone and `<HOME>/tmp`, not HOME.** gh, curl, git and the CLI read config from HOME,
  so a writable HOME was itself a write-then-execute path. A cron that writes into HOME now gets the
  `write outside run roots` deny, whose message names the working directory and `$TMPDIR` as the places to
  write instead.
- **A mid-run reseed is partly fixed.** The run is marked not-ok (`pluginReseeded`), and
  `classifyEvalFatal` makes the heartbeat red for best-effort crons. Output-aware crons still get only the
  tagged Sentry event (`plugin-reseeded-mid-run`). F3 is still the full fix.

## Observability

```yaml
liveness_signal:
  what: "the existing per-cron Sentry cron heartbeat (postSentryHeartbeat, _cron-shared.ts) and output-aware run verdict; a resolver refusal (thrown inside the setup-workspace step) lands in each cron's existing setup-failure catch, which reports op setup-ephemeral-workspace and posts heartbeat ok:false, so the monitor goes red (it emails nobody until #12859 declares the monitors; AC15 falsified in review); that catch files no FAILED self-report issue, so none is claimed. A spawn-HOME create fault throws inside the claude-eval step and takes the existing claude-eval failure path. New ops: three error (cron-plugin-root-untrusted, cron-spawn-home-create, plugin-reseeded-mid-run) and one warning (cron-spawn-home-teardown); no new monitor."
  cadence: "per cron run, on each cron's own schedule"
  alert_target: "each cron's Sentry heartbeat monitor (ok:false, routed to operator email by cron-monitor-alerts.tf) and the Sentry issue for op cron-plugin-root-untrusted"
  configured_in: "apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts (resolveCronPluginRoot, spawnClaudeEvalUnguarded); apps/web-platform/server/inngest/functions/_cron-shared.ts (heartbeat)"
error_reporting:
  destination: "Sentry via reportSilentFallback / warnSilentFallback and the Inngest sentry-correlation middleware; Better Stack via the Vector journald shipper of the pino logs"
  fail_loud: "a thrown CronPluginRootError naming reason (manifest-missing, seed-incomplete, writable, untrusted-path) and the cron, mirrored as op cron-plugin-root-untrusted via reportSilentFallback(null, {feature: cronName, op, message: <fixed per-reason string>, tags: {cron, reason}}) - err is null and the reason is in tags, because a reportSilentFallback(err) after pino's logger.error({err}) hook is deduplicated by Sentry and the tagged capture is lost (#8629); the caller's existing setup-ephemeral-workspace report also fires for the same run, documented as the generic companion event; a hook deny 'cron-containment: not allowlisted: bash plugins/soleur/...' in the run's permission_denials"
failure_modes:
  - mode: "the plugin mount is absent, half-seeded or writable (drifted SOLEUR_PLUGIN_PATH, missing :ro)"
    detection: "in-surface: resolveCronPluginRoot runs inside the step before the child spawns and reports op cron-plugin-root-untrusted with a closed reason enum, which separates the four causes in one event"
    alert_route: "Sentry issue (op cron-plugin-root-untrusted) + heartbeat ok:false"
  - mode: "a skill's own script call is denied after the move (CLAUDE_PLUGIN_ROOT substitution differs from the allowlist line)"
    detection: "in-surface: the hook's deny reason names the exact command; the run's permission_denials carry it; Phase 0.5 records the expected form"
    alert_route: "the run report / FAILED self-report and heartbeat ok:false"
  - mode: "the CLI fails to start under the fresh HOME"
    detection: "in-surface: the child's stderr tail (redacted) and capture_status no-result-event from parseClaudeResultLine"
    alert_route: "heartbeat ok:false and the existing claude-eval FATAL classification"
  - mode: "a spawn HOME is not removed"
    detection: "warnSilentFallback op cron-spawn-home-teardown (layer: pino mirror + Inngest sentry-correlation middleware); the HOME lives inside the run's ephemeralRoot, which teardownEphemeralWorkspace and cron-workspace-gc already remove"
    alert_route: "Sentry warning (no page)"
  - mode: "the spawn HOME cannot be created (ENOSPC on /workspaces)"
    detection: "in-surface: reportSilentFallback(null, op cron-spawn-home-create, tags {cron}) inside the try, before the throw; the finally still clears the heartbeat timer (layer: pino mirror + sentry-correlation)"
    alert_route: "Sentry issue (op cron-spawn-home-create) + heartbeat ok:false via the claude-eval failure path"
  - mode: "the plugin mount is reseeded by a deploy while a spawn runs"
    detection: "in-surface: the seed tag read from .seed-complete at spawn differs at exit; reportSilentFallback(null, op plugin-reseeded-mid-run, tags {cron}) (layer: pino mirror + sentry-correlation); the run's output-aware verdict is downgraded to not-ok, so the heartbeat posts ok:false rather than a green run on a mixed plugin tree"
    alert_route: "Sentry issue (op plugin-reseeded-mid-run) + heartbeat ok:false"
  - mode: "a new cron executes a path it can write"
    detection: "pre-merge: cron-write-execute-census.test.ts goes red on the PR that adds it, naming the cron, the path and the source"
    alert_route: "CI failure on that PR"
logs:
  where: "pino logger in the web-platform container, shipped to Better Stack; no new log line carries a path under HOME or a token"
  retention: "Better Stack and Sentry plan retention; nothing new is retained"
discoverability_test:
  command: "node -e 'process.stdout.write(require(\"node:child_process\").spawnSync(process.execPath,[\"apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs\",(require(\"node:fs\").writeFileSync(require(\"node:path\").join(require(\"node:os\").tmpdir(),\"c12824-allow.txt\"),\"bash /app/shared/plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh\"),require(\"node:path\").join(require(\"node:os\").tmpdir(),\"c12824-allow.txt\"))],{input:JSON.stringify({tool_name:\"Bash\",tool_input:{command:\"bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create x\"}}),encoding:\"utf8\"}).stdout)'"
  expected_output: "deny"
```

The command carries none of Check 10's shell-active bytes (`|`, `;`, `&`, `<`, `>`, `$`, backtick). It was
run on 2026-11-17 under `env -i PATH=/usr/local/bin:/usr/bin:/bin:<node dir>` against `main` and printed
`permissionDecision":"deny"` with reason `cron-containment: not allowlisted: bash plugins/soleur/skills/git-worktree/scripts/worktree-man`;
the same probe with the read-only path printed `allow`. It shows offline, with no credentials, that the
new allowlist line admits the deployed copy and refuses the clone copy.

**Affected-surface note (2.9.2):** the cron worker is not directly inspectable. The in-surface signals are
the resolver's closed `reason` enum (one event separates absent, half-seeded, writable and untrusted
mounts) and the hook's deny text (names the refused command). Delivery of the HOME and `--plugin-dir`
into the spawned process is proven before merge by Guard 2's spawn-spy rows, which read the real argv
and env at spawn time.

## Guard Contract

### Guard 1 — write-and-execute census

**Property.** For every cron that reaches `spawnClaudeEval`, no path that cron executes is one that cron
can write, unless the (cron, path) pair is in the exemption map with an open tracking issue.

**Assembly.** The population is every `spawnClaudeEval(...)` call under `apps/web-platform/server/`
(discovered with the TypeScript compiler API, one `createSourceFile` per file as
`cron-spawn-git-config-pin.test.ts` already does, open-world and recursive, stored as an identity map of
file → `cronName`); any reference to `spawnClaudeEval` that is not a direct call (an alias, a re-export,
a value passed around) fails the census, so aliasing cannot hide a call site. The plugin root fed to
`buildAllowlistLines(…, pluginRoot)` and `buildClaudeArgv(pluginRoot, …)` is the constant
`SOLEUR_PLUGIN_PATH_DEFAULT`, never `getPluginPath()`, so a test fixture's `SOLEUR_PLUGIN_PATH` cannot
move the census onto a temp directory. Executed-path sources, all read from the real producers, never retyped: (1) the
argv from the exported `buildClaudeArgv()` for that cron's `loadPlugin` and flags (the `--plugin-dir`
root); (2) every line of `buildAllowlistLines(cronName, CRON_BASH_ALLOWLISTS[cronName])` whose first
token, or the token after `bash`/`sh`/`node`, is a path (`./node_modules/.bin/*` resolves against the
clone); (3) every hook command in `buildCronEvalSettings(spawnCwd, opts)` for both `frameGhOutput`
values; (4) every MCP server
`command` a cron passes via `--mcp-config`. Writability (CTO A3): a path is writable if the
REAL `decide()` from `cron-bash-allowlist-hook.mjs`, fed that cron's real allowlist lines, allows a
`Write` or `Edit` to it, OR allows any command from a fixed probe set of tree-writing Bash forms aimed at
it (`git checkout -- <p>`, `git checkout --orphan x`, `git restore <p>`, `git switch <branch>`,
`git apply`, `git am`, `cp x <p>`, `tee <p>`, `sed -i … <p>`); it is unwritable only if every probe is
denied or it is under the plugin root and the anchor below holds. The census never assumes "git verbs
write clone paths only": it asks `decide()`. A cron is classed **all paths writable in-run** when any of
its allowlist lines matches a fixed list of arbitrary-exec verb shapes (`./node_modules/.bin/*`,
`bash <non-plugin-root path>`, `node <path>`, any package-install verb, a worktree `create` that runs
`install_deps`), decided by line shape, never by cron name. After the R5/A4 reversal no cron matches; the
census asserts that the all-writable set is empty and the exemption map is empty, so any cron acquiring
an exec verb goes red. Write confinement probes (CTO S1), each through the real `decide()` with the hook's
spawnCwd and HOME derivation exercised: `/app/.next/server/x.js`, `/home/soleur/.bashrc`,
`/workspaces/<uuid-shaped>/x`, another run's `<root>/repo/x`, `/opt/soleur/plugin/x`, a `..` escape out of
`repo/`, and a symlink in the clone pointing outward must all be denied; the run's own `repo/x` and
`home-*/x` must be allowed; a `HOME` env value that is not a `home-*` child of `dirname(spawnCwd)` must
not widen the allowed area. PATH: every entry in the spawn env's `PATH` is absolute and outside spawnCwd
and the spawn HOME. Every cron is treated as write-capable
unless its allowlist carries the `no-file-tools` directive (`--allowedTools` does not fail closed headless).
Any allowlist line that runs something and fits no source class lands in a red UNCLASSIFIED bucket.

**Anchor.** The "under the plugin root is unwritable" premise rests on two things outside the census:
every `-v …:/app/shared/plugins/soleur` mount ends `:ro`, which `apps/web-platform/infra/lib/docker-run-tuple.py`
`_VOLS` already pins into all three tuples (canary and prod in `ci-deploy.sh`, first-boot in
`cloud-init.yml`) and `apps/web-platform/infra/docker-run-tuple.test.sh` asserts; the census cites that test
by name rather than repeating it (CTO T7); and Guard 3's runtime check. The HOME rc-file source is dropped:
Guard 2's per-spawn-HOME assertion over every registered cron is the regression guard for it (CTO T7). The
exemption map is an identity map; an entry that matches nothing goes red, so it can only shrink honestly.
A diff that edits both a producer and the exemption map proves consistency, not integrity; any new
exemption is a review finding.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` (clone path) back to bug-fixer's allowlist | RED (writable path executed) |
| 2 | After the compliant worktree line, add a second line `bash plugins/soleur/skills/x/y.sh` to a different cron | RED (second member) |
| 3 | Remove `/cron-bash-allowlist-hook/` from `WRITE_PROTECTED_PATTERNS` | RED (hook file writable and executed) |
| 4 | Rename the discovered call (the census finds zero `spawnClaudeEval` calls) | RED (identity map / non-vacuity floor) |
| 5 | Change `SOLEUR_PLUGIN_PATH_DEFAULT` to `/opt/soleur/plugin` | RED (not the `:ro` mount target the anchor names; the census compares the constant, since `getPluginPath()` bypasses under vitest) |
| 6 | Drop `:ro` from `_VOLS` | RED (in `docker-run-tuple.test.sh`, the cited anchor; the census does not duplicate it) |
| 7 | Add any entry to the exemption map | RED (the map must be empty; an entry matching no exec-verb cron is also stale) |
| 8 | Add an allowlist line `python3 scripts/x.py` | RED (UNCLASSIFIED) |
| 9 | Remove `cron-community-monitor` from `CRON_NO_FILE_TOOLS` while its router lines still name the clone | RED |
| 10 | Make the hook's `gitVerbReason` admit `git checkout -- <path>` for roadmap-review | RED (hook file writable via a probe form) |
| 11 | Add `./node_modules/.bin/tsx` to roadmap-review's allowlist, or restore `./node_modules/.bin/vitest run` to bug-fixer's | RED (all-writable set non-empty) |
| 12 | Set `loadPlugin: false` on a cron whose prompt invokes a `soleur:` skill | RED (skills silently not found) |
| 13 | Add a `${CLAUDE_PLUGIN_ROOT}/scripts/x.py` reference to a skill a plugin-loading cron invokes, with no disposition row | RED (vendored-file coverage) |
| 14 | Revert the Write branch to allow-unless-pattern (today's behaviour) | RED (`/app/.next/server/x.js` and `/workspaces/<uuid>/x` allowed) |
| 15 | Resolve the target lexically instead of by nearest-existing-ancestor realpath | RED (outward symlink in the clone allowed) |
| 16 | Derive the allowed HOME from `process.env.HOME` without the `home-*` sibling check | RED (`HOME=/` widens the area) |
| 17 | Drop `SOLEUR_WORKTREE_SKIP_INSTALL=1` from bug-fixer's spawn env | RED (worktree `create` runs `install_deps`, an exec verb) |
| 18 | Add a second `GIT_CONFIG_COUNT` setter, or drop `core.hooksPath=/dev/null` from the pin | RED |

**Harness rows:** (H1) replace the census's `decide()` with a stub that denies everything → RED via a
known-writable control: a `Write` to a clone file (absolute path, the form the hook sees) must classify
writable; bug-fixer's all-writable class comes from its allowlist text, not `decide()`, so it cannot serve
as the control; (H2) make the census iterate an empty population →
RED by the floor; (H3) must-PASS: a cron whose allowlist holds only `gh issue view` and loads no plugin;
(H4) must-PASS: bug-fixer with no vitest line, `SOLEUR_WORKTREE_SKIP_INSTALL=1`, and its worktree line on the
read-only root.

### Guard 2 — chokepoint argv and env

**Property.** Every claude child receives a HOME that no other spawn ever received, that exists with mode
0700 while the child runs and is gone after it exits, and receives `--plugin-dir <resolved root>` before
any caller flag exactly when `loadPlugin` is true.

**Assembly.** `spawnClaudeEvalUnguarded` is the single chokepoint (`resolveClaudeBin()` may be referenced
only in the substrate, already pinned by `cron-claude-eval-mcp-flags.test.ts`); the observed artifacts are
the argv and env passed to the mocked `child_process.spawn`, and the filesystem state at spawn time and
after resolve. Guard 2 uses the REAL filesystem under a temp workspace root and mocks only
`child_process.spawn` (mocking `_cron-spawn-fs.ts` here would test the fake, so rows 4, 5 and 10 could not
fail); modes and existence are checked inside the fake spawn call.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `HOME: spawnHome` spread | RED |
| 2 | Move `HOME: spawnHome` before `...buildSpawnEnv(token)` (reorder, not delete) | RED (a cron's `HOME: process.env.HOME` wins) |
| 3 | Reuse one module-level HOME for every spawn | RED (two spawns see equal HOMEs) |
| 4 | Remove the HOME in the child's `spawn` callback instead of after exit | RED (stat at spawn time finds it absent) |
| 5 | Skip the removal | RED (dir exists after resolve) |
| 6 | Accept a caller `--plugin-dir=plugins/soleur` | RED (both forms must throw) |
| 7 | Insert `--plugin-dir` after `...flags` | RED (lands after `--`) |
| 8 | Make `loadPlugin` optional with a `true` default | RED (type test + a caller that omits it) |
| 9 | Pass the raw `allow` (unsubstituted) to `runHookSelfTest` | RED (community-monitor setup throws) |
| 10 | Replace `mkdtemp` with `mkdir(…, {mode: 0o755})` | RED (mode at spawn time is not 0700; `mkdtemp` already creates 0700, so a dropped `chmod` alone is not a meaningful mutation) |
| 11 | Create the HOME under `spawnCwd` | RED (HOME-not-in-clone assertion) |
| 12 | Create `<HOME>/tmp` with mode 0755, or omit `TMPDIR` from the env | RED (TMPDIR equals `<HOME>/tmp`, mode 0700 at spawn time) |

**Harness rows:** (H1) the spy records env by reference and the test mutates it → RED unless the spy
deep-copies at call time; (H2) must-PASS: a `loadPlugin: false` cron whose flags contain no `--plugin-dir`.

### Guard 3 — plugin-root resolver

**Property.** `resolveCronPluginRoot()` returns a path only when it is the trusted absolute root, holds a
manifest and a `.seed-complete`, and is not writable by the process; otherwise it throws with the reason.

**Assembly.** The resolver is the only producer of the root for argv (Guard 2) and allowlist lines
(Guard 1); `getPluginPath()` and `assertTrustedPluginPath()` are its inputs.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the `W_OK` check | RED (writable fixture accepted) |
| 2 | Drop the `.seed-complete` check | RED |
| 3 | Treat `EPERM`/`ENOENT` from `accessSync` as read-only | RED (only `EROFS`/`EACCES` mean read-only) |
| 4 | Fall back to `/opt/soleur/plugin` on failure | RED (must throw) |
| 5 | Probe only the root, not `hooks/` | RED (fixture with a read-only root and writable `hooks/` accepted) |
| 6 | Drop the single `.seed-complete` retry, or retry forever | RED (fixture whose sentinel appears after the first probe must pass; one that never appears must throw after exactly one retry) |
| 7 | Skip the exit-time seed-tag compare | RED (fixture whose tag changes during the spawn reports no `plugin-reseeded-mid-run`) |

**Harness rows:** (H1) the mocked probe returns success for every call → RED by row 1's fixture; (H2)
must-PASS: a fixture with manifest, sentinel and a probe that throws `EROFS`. The resolver takes the
candidate path as a parameter (`resolveCronPluginRoot(candidate = getPluginPath())`), so row 4's
neighbour, an `untrusted-path` assertion, feeds a non-`/app/` path directly with `vi.stubEnv` for
`VITEST`/`NODE_ENV` and asserts the exact reason; `getPluginPath()` silently swaps a bad override for the
default, so going through it would fail on `writable` or `seed-incomplete` and pass for the wrong
reason. Row 6 uses fake timers (or an injected sleep), never a real 30 s wait.

## Architecture Decision (ADR/C4)

### ADR

Amend `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`
with a dated 2026-11-17 amendment (#12824): the substrate owns `--plugin-dir` and loads the deployed
`:ro` plugin through `resolveCronPluginRoot()`; every claude spawn gets a fresh per-spawn HOME; allowlisted
scripts are named under the plugin root; the write-and-execute census is the guard. Update the #12757
amendment's residual list: the "agent-editable-code class is tracked in #12824" bullet becomes the
residuals that remain (F1 token in the agent env, F2 the `.next` chown, F6 CI running agent-committed
code). The amendment also records the Write confinement (allow-by-root in the containment hook) and that
no cron holds a code-exec verb. No new ADR (R9). There
are three `ADR-033-*` files; cite this one by its full name.

The amendment states that the census's all-writable set is empty and that bug-fixer runs without a local
test baseline. Its residual list also names: the in-place reseed race, new for crons in this PR (F3, with
the seed-tag detection); tools that ignore `TMPDIR`; the vendored-copy file-type gap with its per-miss
dispositions; and the S3 measurement result.

Also add a short dated amendment to
`knowledge-base/engineering/architecture/decisions/ADR-093-sdk-plugin-source-is-platform-deployed-not-connected-repo.md`
(architecture-strategist): where the plugin loads from is that ADR's decision, and it now covers cron CLI
spawns as well as hosted sessions, with the `:ro` and not-writable checks. Still no new ADR.

### C4 views

**No C4 element or relationship changes; the work phase must back this with the full read.** The work
phase reads `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` in full and
records, for: external human actors (no new actor; the plugin users who pull from the repo are already
modelled as readers of `github`), external systems (`github`, `anthropic`, `inngest` — no new system),
containers and stores (the plugin mount and workspaces volume — confirm their element descriptions do
not claim crons load the plugin from the clone, and fix any that do), and access relationships (the
api/cron → plugin edge, if present, now reads the deployed mount). It then runs
`bash plugins/soleur/test/c4-count-parity.test.sh` and records the result. Any falsified description is
an in-scope edit.

### Sequencing

Nothing is soak-gated; the amendment describes the shipped state.

## GDPR / Compliance Gate

`soleur:gdpr-gate` ran at plan Phase 2.7, triggered by condition (b), the `single-user incident` threshold.
The canonical regulated-data regex matched none of the paths the plan names
(`gdpr-gate: path scan complete — 67 examined, 0 matched`); the corpus is 1 day since `last-verified`, so
no staleness banner fired. None of the five v1 checks fired: no schema column, no PII table, no FK to
`users`, no new vendor or SDK, no Art. 9 column. The change moves where a spawned CLI reads its plugin and
HOME; it processes no personal data. The deepen pass found that a prompt-injected file-tool cron could
Write into founder workspaces under `/workspaces/<uuid>` (pre-existing); the Write confinement in this PR
closes it, and per the CPO condition the PR body asks `soleur:legal:clo` for a GDPR read on whether the
pre-existing exposure needs a record (no evidence of exploitation is known). This is not legal review.

## Domain Review

**Domains relevant:** Engineering, Product (CPO sign-off for the `single-user incident` threshold only)

### Engineering

**Status:** reviewed
**Assessment:** the CTO agent ruled the scope before planning and ruled R1-R9 and A1-A2 during planning.
Main corrections: the brief's `/opt/soleur/plugin` is writable, so the target is the `:ro` mount with a
runtime check; the substrate owns `--plugin-dir`; fresh HOME for every spawn at the chokepoint; both
script-allowlisting crons move; the install vector shares path 2's exemption; a separate issue for
cross-tenant Write.

### Product/UX Gate

Not applicable: no UI surface (no `components/**`, `app/**/page.tsx` or `app/**/layout.tsx` in either file
list). The CPO took part only as the plan-time sign-off the threshold requires: **approved with conditions**
(2026-11-17), folded in as follows.

1. F1 is filed p1, `single-user incident`, current active milestone. (Condition 1's fallback, scoping the
   bug-fixer token down or pausing the cron, is largely met by removing bug-fixer's code-exec verbs in
   this PR; row O2 records it.)
2. The cross-tenant Write the CPO asked to be filed (F2 at planning time) now lands in this PR as the
   Write confinement (CTO S1); the CLO GDPR read is still requested in the PR body, since founder data was
   in reach before it. F2 now names the `.next` chown; its priority stays the operator's (row O1), with the
   CPO's recommendation (at least p1, `single-user incident`) recorded in its body.
3. The PR body opens with a plain "still open" paragraph: the cron agents still hold a repo-write token
   in their env (F1); bug-fixer has lost its local test baseline (AC16).
4. A cron that fails closed must reach the operator's normal alert channel, not only Sentry: AC15 checks
   that every affected cron's monitor is routed through `sentry_alert.cron_monitor_failure`
   (`apps/web-platform/infra/sentry/cron-monitor-alerts.tf`), which emails the operator.

Other domains (Legal, Marketing, Operations, Finance, Sales, Support): no implications. No personal data,
copy, vendor or spend (beyond a few cents of local probe API usage).

## Files to Edit

- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — `resolveCronPluginRoot()`,
  `CronPluginRootError`, `buildClaudeArgv()`, `--plugin-dir` refusal, required `loadPlugin`, per-spawn HOME
  and its teardown, `<plugin-root>` substitution in `buildAllowlistLines`, bug-fixer and community-router
  allowlist lines, the #5091/#5026 comment block.
- The 12 plugin-loading callers (drop `"--plugin-dir","plugins/soleur"`, pass `loadPlugin: true`, fix the
  header comment): `cron-bug-fixer.ts`, `cron-agent-native-audit.ts`, `cron-architecture-diagram-sync.ts`,
  `cron-campaign-calendar.ts`, `cron-competitive-analysis.ts`, `cron-content-generator.ts`,
  `cron-growth-audit.ts`, `cron-growth-execution.ts`, `cron-legal-audit.ts`, `cron-seo-aeo-audit.ts`,
  `cron-ux-audit.ts`, `event-ship-merge.ts`.
- The other callers (pass `loadPlugin: false`): `cron-community-monitor.ts` (also builds its prompt from
  the substituted router lines), `cron-roadmap-review.ts`, `cron-daily-triage.ts`,
  `cron-follow-through-monitor.ts`, `oneshot-f2-defer-gate-review.ts`, `oneshot-recheck-4217-calibration.ts`.
  The work phase re-derives this list from the census's discovered population; a caller not listed here
  is added, not skipped.
- `cron-ux-audit.ts` MCP `command` — switch to the `/app/node_modules/.bin/` binary (CTO T6); its
  `/tmp/ux-audit` and Playwright-profile write sites move under the spawn `TMPDIR`/HOME (S1 confinement).
- `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs` — Write/Edit/MultiEdit allow-by-root
  (clone and spawn HOME, derived from the hook's own path), deny reason `write outside run roots`
  (CTO S1); the `CLAUDE.md`/`AGENTS.md` write-deny only if Phase 0.7g resolves the import and no
  CLI-native exclusion exists (CTO S3).
- `cron-bug-fixer.ts` / `CRON_BASH_ALLOWLISTS["cron-bug-fixer"]` — drop `./node_modules/.bin/vitest run`,
  set `SOLEUR_WORKTREE_SKIP_INSTALL=1` in its spawn env, update the prompt's test step to the
  no-baseline path (R5/A4 reversed).
- `_cron-claude-eval-substrate.ts` — `GIT_CONFIG_COUNT`/`KEY_n`/`VALUE_n` at the pin spread point (CTO S5).
- `apps/web-platform/test/server/inngest/cron-bash-allowlist-hook.test.ts` and
  `cron-spawn-git-config-pin.test.ts` — confinement rows and the updated #12757 census maps.
- Tests that pin today's shape: `apps/web-platform/test/server/inngest/cron-producer-output-wiring.test.ts`,
  `cron-content-generator.test.ts`, `cron-untrusted-preamble.test.ts`, `cron-claude-eval-substrate.test.ts`,
  `cron-claude-eval-mcp-flags.test.ts`, `cron-spawn-git-config-pin.test.ts` (the substrate's new `HOME`
  literal joins `KNOWN_HOME_LITERALS` and ends with `...CRON_GIT_CONFIG_PIN`),
  `cron-community-monitor-allowlist.test.ts`, `cron-community-monitor-prompt-grammar.test.ts`,
  `cron-bash-allowlist-hook.test.ts` (any bug-fixer worktree-line case). Derive the final list with
  `git grep -ln 'plugins/soleur\|--plugin-dir\|buildSpawnEnv\|CRON_BASH_ALLOWLISTS\|COMMUNITY_ROUTER_READ_VERBS' apps/web-platform/test`.
- `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md` — amendment.
- `knowledge-base/engineering/architecture/decisions/ADR-093-sdk-plugin-source-is-platform-deployed-not-connected-repo.md` — amendment (cron spawns load the deployed plugin).
- `knowledge-base/engineering/architecture/diagrams/*.c4` — only if the full read finds a falsified description.

## Files to Create

- `apps/web-platform/test/server/inngest/cron-write-execute-census.test.ts` — Guard 1.
- `apps/web-platform/server/inngest/functions/_cron-spawn-fs.ts` — the small filesystem module (resolver
  probes, HOME create/remove) that handler tests replace with one `vi.mock` (CTO T8).
- `apps/web-platform/test/server/inngest/cron-spawn-isolation.test.ts` — Guards 2 and 3 (spawn spy and
  resolver; isolated from `cron-claude-eval-substrate.test.ts`, which must not mock `node:child_process`).
- `knowledge-base/project/specs/feat-one-shot-12824-cron-spawn-isolation/probes/cli-isolation-probe.sh` — Phase 0 probe.
- `knowledge-base/project/specs/feat-one-shot-12824-cron-spawn-isolation/measurements.md` — Phase 0 results.
- `knowledge-base/project/specs/feat-one-shot-12824-cron-spawn-isolation/decision-challenges.md` — rulings table (written at plan time).

## Open Code-Review Overlap

None. Checked 96 open `code-review` issues against the substrate, `cron-bug-fixer.ts`, `cron-ux-audit.ts`,
`cron-community-monitor.ts`, `event-ship-merge.ts`, `cron-growth-audit.ts`, `cron-legal-audit.ts`,
`cron-content-generator.ts`, `cron-bash-allowlist-hook.mjs`, `plugin-path.ts`, the two shape tests,
`worktree-manager.sh`, `fix-issue/SKILL.md` and ADR-033: no body names any of them.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | [brief] "file-tool crons (cron-bug-fixer.ts and siblings) spawn the claude child with a fresh empty per-spawn HOME instead of the shared container HOME, with CRON_GIT_CONFIG_PIN set on it" | Proposed Solution "Per-spawn HOME"; Phase 2.3; Guard 2; AC3, AC4 | mapped (applied to every claude spawn at the chokepoint, a superset, per CTO R3) |
| 2 | [brief] "point --plugin-dir and the allowlisted scripts at the image's read-only vendored plugin copy (Dockerfile _plugin-vendored), not the editable clone — closes paths 1 and 3" | Phases 2.1, 2.2, 2.4, 2.5; Guards 1, 3; AC1, AC2, AC5, AC6 | mapped (target corrected to the `:ro` mount of the same vendored tree, CTO R1) |
| 3 | [brief] "measure paths 3 and 4 against the real CLI locally and record results in the PR" | Phase 0; AC9 | mapped |
| 4 | [brief] "add a census test that fails when one cron can both write and execute the same path" | Phase 3; Guard 1; AC7, AC8 | mapped |
| 5 | [brief] "removing the token from the agent env (path 2) — file a follow-up issue from this PR" | Phase 4 (F1); AC11 | mapped (filed, not implemented) |
| 6 | [issue #12824] "Choose an isolation design for crons that keep file tools" | Proposed Solution; Alternatives; ADR amendment | mapped |
| 7 | [issue #12824] "Measure paths 3 and 4 against the real CLI." | Phase 0 | mapped |
| 8 | [issue #12824] "Add a test that fails when a cron can both write and execute the same path." | Guard 1 | mapped |
| 9 | [brief] "dark launch, no feature-flag changes, no Doppler prd changes, no production writes, no live cron trigger, no label edits; at most one PR" | Header; AC12; Split Assessment | mapped |
| 10 | [brief] "the git-global-config-pin issue for non-inngest spawns and the fix-issue commit-identity issue are separate PRs" | Not touched (`host-git.ts` spawns outside `server/inngest`, fix-issue identity) | descoped — justification: brief OUT list |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Substrate resolver, refusal, `loadPlugin`, argv builder | asks 2 | asked |
| Per-spawn HOME and teardown | asks 1 | asked |
| `<plugin-root>` allowlist substitution (bug-fixer, community-monitor) | asks 2 ("and the allowlisted scripts") | asked |
| 18 caller edits | asks 1, 2 | asked |
| ux-audit MCP command switch | — | inferred — justification: A1/T6, a fresh HOME (ask 1) breaks the npx cache and `npx` from a HOME cache is a write-then-execute path |
| Seed retry, seed-tag compare, vendored-file coverage row | asks 2 | asked (consequences of loading from the deployed copy, CTO T1/T2) |
| Phase 0 probe script and `measurements.md` | asks 3 | asked |
| Census, chokepoint and resolver suites | asks 4 | asked |
| F1 issue | asks 5 | asked |
| Write confinement in the containment hook | asks 4 | asked (CTO S1: `/app/.next` is a path the cron's own host process executes and the agent could write, the write-then-execute ask 4 names) |
| Remove vitest / `install_deps` from bug-fixer | asks 4 | asked (CTO S1 reversal of R5/A4: code they run writes below the hook) |
| `GIT_CONFIG_COUNT` hardening | — | inferred — justification: CTO S5, hardens the clone root the confinement leaves writable; three env keys |
| Phase 0.7g nested CLAUDE.md probe | asks 3 | asked (measure against the real CLI, CTO S3) |
| F2 issue (`.next` chown), F3-F6 | — | inferred — justification: residuals found while enumerating ask 4's attack surface; each is pre-existing or needs an image/deploy/CI change outside a dark-launch PR (CTO S1, T1, T3, T6, S4) |
| ADR-033 amendment | asks 6 | asked (architecture decision is a plan deliverable) |
| Shape-test updates | asks 1, 2 | asked |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform/server/inngest/` (substrate + callers) and `knowledge-base/` (ADR, spec artifacts)
- Planned files: about 44 (after deepen-pass) | Estimated changed lines: about 1,500 (most in the three new suites and the measurement record; the 18 caller edits are 1-3 lines each)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines — files and lines exceed
- Recommendation: single PR. The brief caps the work at one PR, and the parts cannot ship apart safely:
  the refusal of a caller `--plugin-dir` without the 18 caller edits breaks every cron, and the callers
  without the census leave the class unguarded.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** `resolveCronPluginRoot()` returns `getPluginPath()` only when manifest, `.seed-complete` and a
  not-writable root (`EROFS`/`EACCES`) all hold, and throws `CronPluginRootError` with the matching reason
  otherwise; Guard 3 rows 1-7 go red when applied (`cron-spawn-isolation.test.ts`).
- **AC2** `spawnClaudeEval` throws on `--plugin-dir X` and `--plugin-dir=X` in caller flags; with
  `loadPlugin: true` the real argv carries `--plugin-dir <root>` before the caller flags and before `--`;
  with `false` it carries none (Guard 2 rows 6-8).
- **AC3** Every claude child's env has a HOME equal to a fresh `home-*` dir directly under the run's
  `ephemeralRoot` (not under `spawnCwd`), and `TMPDIR` equal to `<HOME>/tmp`, mode 0700 at spawn time, distinct across two spawns, absent after
  resolve; `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_NOSYSTEM` still equal `CRON_GIT_CONFIG_PIN` (Guard 2 rows 1-5, 10-12).
- **AC4** `cron-spawn-git-config-pin.test.ts` passes with the substrate's HOME literal in
  `KNOWN_HOME_LITERALS`; no other map entry shrinks.
- **AC5** No file under `apps/web-platform/server/` contains the string pair `"--plugin-dir"` outside the
  substrate: `git grep -n -- '"--plugin-dir"' apps/web-platform/server | grep -v _cron-claude-eval-substrate.ts`
  prints nothing.
- **AC6** No allowlist line produced by `buildAllowlistLines` for any cron names `plugins/soleur/` or
  contains `$` or `<plugin-root>`; bug-fixer's and community-monitor's script lines start with
  `bash /app/shared/plugins/soleur/` in a prod-shaped env.
- **AC7** `cron-write-execute-census.test.ts` passes, its discovered population equals its stored identity
  map, its exemption map is empty, the all-writable set is empty, and every Write-confinement probe in
  Guard 1 has the expected allow/deny verdict.
- **AC8** The Guard 1 mutation battery (rows 1-18, H1-H4), the Guard 2 battery (rows 1-12, H1-H2) and the
  Guard 3 battery (rows 1-7, H1-H2) is run once against the finished suite and the
  per-row result is pasted in the PR body; every RED row was red with vitest exit code 1 (an exit of 2 or
  127, a crash or a collection error, counts as not-run, never as red), every must-PASS row was green, and
  each mutation ran in a scratch copy or a reverted working tree so no mutation reaches a commit.
- **AC9** `measurements.md` records Phase 0 arms 0.1-0.6 and 0.7a-0.7f with the CLI version (2.1.321), command, output
  excerpt and verdict; the PR body carries the path-3 and path-4 tables.
- **AC10** The ADR-033 (cron spawn) amendment exists, names F1 and F2 by number, and its #12757 residual
  bullet for #12824 is updated; the C4 read is recorded and `c4-count-parity.test.sh` is green.
- **AC11** F1, F2, F3, F4 (and F5 if Phase 0.6 triggered it) are filed (`gh issue view <N> --json state` reads `OPEN`) with re-evaluation
  criteria and a milestone; no existing issue's labels changed.
- **AC12** The diff touches no feature flag, no Doppler config, no `infra/*.tf`, no workflow file; the
  diff's file set is a subset of Files to Edit + Files to Create + this plan +
  `knowledge-base/project/specs/feat-one-shot-12824-cron-spawn-isolation/**` (the KB INDEX is untracked
  since ADR-235, so it is not in the diff).
- **AC13** The web-platform suite and typecheck pass: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest`
  and `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- **AC14** The Observability `discoverability_test.command` prints a `permissionDecision` of `deny` (reason `cron-containment: not allowlisted`) on the final tree.
- **AC15** Every cron whose spawn now runs through `resolveCronPluginRoot()` has its Sentry cron monitor
  routed in `apps/web-platform/infra/sentry/cron-monitor-alerts.tf` (the existing routing test passes and
  the work phase lists the 13 monitor slugs it checked: the 11 plugin-loading crons, community-monitor,
  and the monitor that covers `event-ship-merge.ts` or a note that it has none and how its failure surfaces), so a fail-closed run emails the operator.
- **AC16** The PR body's first paragraph states, in plain words, that the cron agents still hold a
  repo-write token in their env (naming F1), that bug-fixer now opens fixes without a local test run, and
  that a prompt-injected cron could previously write into founder workspaces and the web server's build
  output (closed here), with a request for a CLO read.
- **AC19** `CRON_BASH_ALLOWLISTS["cron-bug-fixer"]` contains no `./node_modules/.bin/` line and
  bug-fixer's spawn env has `SOLEUR_WORKTREE_SKIP_INSTALL=1`; fix-issue's SKILL "no baseline" path is the
  documented behaviour (no SKILL edit needed, or the edit is listed).
- **AC20** `decide()` denies Write/Edit/MultiEdit outside the run's clone and HOME (Guard 1 rows 14-16) with
  reason `cron-containment: write outside run roots`, and every write site the work phase enumerated for
  the 18 callers' prompts and skills is inside the two roots or has a recorded degrade disposition.
- **AC21** The spawn env carries `GIT_CONFIG_COUNT=3` with `core.hooksPath=/dev/null`, `core.fsmonitor=false`,
  `safe.bareRepository=explicit`, and no other site sets `GIT_CONFIG_COUNT`.
- **AC17** community-monitor's `setupEphemeralWorkspace` passes the hook self-test with the substituted
  router lines (Guard 2 row 9).
- **AC18** A red census prints, per finding, the cron, the path, the executed source (argv, allowlist line,
  hook command or MCP command) and the write route `decide()` allowed, followed by the three fixes in
  order (write the line as `bash <plugin-root>/…`; add a `WRITE_PROTECTED_PATTERNS` entry; add an
  exemption naming an open issue, with the map's `file:line`); a red from the identity map says
  "add `file → cronName`". The census file opens with a header comment explaining the model.

### Post-merge

- None that need a human. The deploy itself re-seeds the mount; the first scheduled run of each cron
  reports through its existing heartbeat. AC14 of the prior containment plan (a read-only Sentry check
  until 2026-11-18T17:27Z) belongs to that plan and is not part of this PR.

## Test Scenarios

- A plugin-loading cron spawns with a prod-shaped resolver: argv has `--plugin-dir /app/shared/plugins/soleur`
  before its flags; env HOME is a fresh dir; the dir is gone after exit.
- A fixture root that is writable (the mocked `_cron-spawn-fs.ts` probe returns success): the cron throws `writable` before any spawn and
  reports `cron-plugin-root-untrusted`.
- A fixture root without `.seed-complete`: throws `seed-incomplete`.
- A caller that still passes `--plugin-dir plugins/soleur`: throws before spawning.
- Two concurrent spawns of different crons: two different HOMEs.
- The hook, fed bug-fixer's built allowlist: `bash "/app/shared/plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh" --yes create bot-fix-1-x`
  allows; `bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create x` denies.
- Community-monitor: every prompt command, run through the real hook with the built allowlist, allows
  (existing G2-8 shape, new paths).
- Census mutation battery as in Guard 1.

## Dependencies & Risks

- **Fail-closed availability.** A drifted `SOLEUR_PLUGIN_PATH`, a missing `:ro` or a half-seeded mount now
  fails every plugin-loading cron loudly. That is intended; the reason enum makes it a one-event diagnosis.
- **Behavior moves to the deployed plugin.** Skills now come from the image's plugin, not the clone's
  `main` HEAD, so a plugin change reaches crons at deploy, as it already does for hosted sessions
  (ADR-080, ADR-093). Crons that edit plugin files still edit the clone and commit them.
- **Non-`.sh` plugin files are absent from the deployed copy** (`.dockerignore` keeps only md/json/njk/yml/
  yaml/sh/txt). Work phase: grep the skills each plugin-loading cron invokes for
  `${CLAUDE_PLUGIN_ROOT}/…\.(py|ts|mjs|cjs|js)` and record each hit's disposition; none is allowlisted today.
- **`${CLAUDE_PLUGIN_ROOT}` substitution form** (Phase 0.5) decides whether fix-issue's own worktree call
  matches; the fallback path is documented in the SKILL.
- **Spawn HOME removal vs a running grandchild.** A detached grandchild of the claude child can outlive it;
  the process-group kill (ADR-033 I3) runs before removal, and `rm -r` with `force` tolerates a race.
- **Write confinement breaks a cron that writes elsewhere.** A prompt or skill step that writes outside
  the run's clone and HOME (a shared `/tmp` path, `~/` under the container HOME) is now denied. The work
  phase enumerates every write site of the 18 callers' prompts and invoked skills before the hook change
  lands; each must resolve inside the two roots (TMPDIR helps) or carry a recorded degrade disposition.
- **Bug-fixer quality without a local baseline.** Fixes are no longer pre-tested in the run; CI is the
  only test gate, so more fix PRs may go red. Accepted (CTO S1); the PR body says so.
- **ux-audit browser under a fresh HOME.** Playwright's default browser path on Linux is
  `$HOME/.cache/ms-playwright`. The image installs Chromium as root (likely `/root/.cache`), so uid 1001
  probably cannot reach it today; but if a browser ever lived under `/home/soleur/.cache`, the fresh HOME
  would hide it. Phase 0.6 records where the browser is and whether uid 1001 can launch it. Pointing
  `PLAYWRIGHT_BROWSERS_PATH` at a uid-1001-writable cache would itself be a cross-run write-then-execute
  path, so the fix (F5) is an image change that installs the browser to a root-owned path, never a
  writable cache (CTO T6).
- **CI as root.** `access(W_OK)` succeeds for root on a 0555 dir, so the resolver tests `vi.mock`
  `_cron-spawn-fs.ts`, never a chmod fixture alone. Guard 2 is the exception: it uses the real filesystem
  under a temp root and mocks only `child_process.spawn`, checking modes inside the fake spawn call.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- The census must quantify over the discovered population, not this plan's list of 18 callers; one
  battery row adds a caller the census has never seen.
- Phase 0's outputs are the fixtures. Do not hand-write the substituted command string or the HOME file
  list; copy them from `measurements.md`.
- `GH_TOKEN` in every probe is a dummy value; the probe hook prints `set`/`unset`, never a value.
- An outcome is not a mechanism: Phase 0.3's control arm (read-only plugin dir) is what lets the PR say
  the mount closes path 3, rather than only that the hook ran.
- Re-run the ADR-033 residual sweep when F1/F2 numbers are known; the plan cannot know them yet.

## Plan Review (2026-11-17)

Panel: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer (single-user-incident
5-agent panel), plus the CTO devex seat; the CPO seat ran as the plan-time sign-off. One P0 found by two
reviewers independently (the hook self-test would receive the raw `<plugin-root>` token and abort every
community-monitor run) is folded into Proposed Solution, Guard 2 row 9 and AC17. Mechanical findings are
applied in place; forks T1-T9 were ruled by the CTO agent; deletions of operator-asked scope (DHH: delete
the census) were rejected. Every disposition is a row in
`knowledge-base/project/specs/feat-one-shot-12824-cron-spawn-isolation/decision-challenges.md`.
