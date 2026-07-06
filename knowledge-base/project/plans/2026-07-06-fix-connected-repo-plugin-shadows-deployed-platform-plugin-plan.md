---
title: "fix: connected-repo plugin shadows the deployed platform plugin (security + #4826 delivery wedge)"
date: 2026-07-06
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
security_review: required
supersedes_attempt: "#6115 (reverted via #6117)"
related_adrs: [ADR-044, ADR-079, ADR-080, ADR-068]
tags: [concierge, plugin-delivery, security, untrusted-code-execution, sandbox-canary, dogfooding, CLAUDE_PLUGIN_ROOT]
---

# 🐛🔒 Fix: a connected repo's committed `plugins/soleur/` shadows the DEPLOYED platform plugin — untrusted-code execution + the #4826 delivery wedge

## Overview

A Concierge session loads its Soleur plugin (commands, skills, agents, **and executable hooks**) from a
**workspace-relative** path. For a workspace whose connected repo ships its own committed `plugins/soleur/`
(the operator dogfoods Concierge on `jikig-ai/soleur` itself), the platform loads the **connected repo's frozen
committed copy** instead of the platform-deployed plugin. This is **one bug with two faces**:

1. **SECURITY (untrusted-code execution).** The connected repo's `hooks/hooks.json` registers `type:"command"`
   hooks (`welcome-hook.sh` @ SessionStart; `stop-hook.sh` + `browser-cleanup-hook.sh` @ Stop) that the Agent SDK
   runs **as subprocesses of the Node dispatch process — outside the bwrap tool sandbox, with the server
   process's environment and privileges** — on every session start/stop. Loading a connected repo's plugin
   therefore executes arbitrary untrusted repo shell in the platform's trusted dispatch context, and can weaken
   the platform's own in-process tool-gating.
2. **DELIVERY (#4826 wedge).** Because commands/skills load from the frozen copy, **every platform plugin fix is
   silently shadowed** for that workspace. This is the root cause of the 5-round #4826 Concierge
   worktree-creation wedge: the deployed `worktree-manager.sh` guard fixes (#6108, …) never ran.

**The correct posture (this plan): always load the PLATFORM-controlled deployed plugin, never the connected
repo's copy.** This closes the security finding and the delivery gap in one move.

**Out of scope:** the nav-rail feature #4826 *describes* (that issue is CLOSED; it is blocked by this infra bug,
not built here). This plan builds the infra fix only.

**This plan supersedes the reverted #6115** and — critically — **corrects the premise on which #6115 was reverted
AND the premise this planning request was framed with.** See Research Reconciliation below; it is the most
important section of this plan.

---

## Research Reconciliation — Premise vs. Codebase

> **hr-verify-repo-capability-claim-before-assert + the ADR-079 learning ("verify sandbox assumptions against the
> canary, never reason them from a dev machine") in action.** Three parties have offered three *different* reasons
> for why #6115's deploy canary failed. All three are inconsistent with the actual code. Do not build this plan on
> any of them.

| Claim (source) | Reality (code evidence) | Plan response |
|---|---|---|
| "`/app/shared` direct plugin path **does not work in the bwrap agent sandbox**" — #6117 revert PR body | The sandbox base binds the **entire root read-only** (`--ro-bind / /`, `sandbox-canary-argv.json:11-13`), so `/app/shared/plugins/soleur` is readable. It is **already** the exact path `verifyPluginMountOnce()` / `getPluginPath()` validate at **every container boot** (`plugin-mount-check.ts:32`, `plugin-path.ts:17`). | Refuted. `getPluginPath()` is sandbox-accessible and boot-validated. Option 3 (below) uses it. |
| "Changing the plugin path **alters the bwrap SETUP argv → the committed ADR-079 fixture byte-mismatches → canary fails**; the fix REQUIRES regenerating the fixture" — this planning request's framing | The ADR-079 `--capture`/`--verify` fixture is produced by driving `query()` with `buildAgentSandboxConfig(resolvedOwn)` and **no `plugins:` key at all** (`sandbox-canary.mjs:725,736-758`) — it never invokes `realSdkQueryFactory`/cc-dispatcher. The canonical projection **drops all `--setenv`** (`sandbox-canary.mjs:414`; `sandbox-canary-argv.json` `droppedForDeterminism.setenv:26`). So **neither the cc-dispatcher plugin-path change nor the `CLAUDE_PLUGIN_ROOT` env injection can change the committed fixture.** And the faithful-argv canary is **NON-BLOCKING** at deploy (`run_faithful_sandbox_canary \|\| true`, `ci-deploy.sh:1297`) — it never rolls back. | **No fixture regeneration is required by this change.** The requested "fixture-regen" step would be a no-op. Retained only as a defensive contingency (see Canary Handling). |
| "#6115 broke the canary via the plugin change" (the shared assumption) | The BLOCKING `canary_sandbox_failed` gate is a **hardcoded, plugin-independent** probe: `docker exec soleur-web-platform-canary bwrap --new-session --die-with-parent --dev /dev --unshare-pid --bind / / -- true` (`ci-deploy.sh:1281`) — **written at exactly one site** (`ci-deploy.sh:1287`; verified by grep of every writer of the reason string). It runs **only after** health/login/dashboard already passed (`ci-deploy.sh:1279` `if CANARY_HEALTHY==true`), so the canary container **booted fine with #6115's plugin change** — the plugin change was not even exercised by the health probes (they do not dispatch an agent session). The probe's only failure modes are host bwrap/userns capability drift or a broken bwrap binary — the **documented `#4932`/`#5849`/`#2276` false-rollback class** (`ci-deploy.sh:1268-1278` block: "the probe still failed even with the sysctl correctly asserted … rolled back EVERY web-platform deploy"). | **On the code evidence, #6115's `canary_sandbox_failed` was a host-level bwrap/userns false-rollback coincident with — not caused by — the plugin change.** Corroborating: the git log shows active web-2 fresh-boot-death firefighting in the exact window (`#6090`/`#6116` landed immediately after the revert; `2026-07-05-fix-web2-recreate-fanout…-plan.md` references `canary_sandbox_failed`). |
| "a genuinely broken deployed plugin path could still crash the canary container / fail health" (residual worry) | `verifyPluginMountOnce()` **never throws** — on missing/empty/partial mount it calls `reportSilentFallback` and `return`s (`plugin-mount-check.ts:34-95`). So even a truly broken deployed root cannot crash the container or fail `canary_health_failed`/`canary_sandbox_failed`. | Strengthens the reconciliation: the plugin change is decoupled from **every** blocking canary reason. (architecture-strategist, verified.) |

**Consequence for the design.** The gating constraint is *not* "regenerate the ADR-079 fixture." It is **"do not
re-attempt cutover into a host whose hardcoded bwrap probe is red, and — if the canary re-fails — read the actual
deploy-state reason and refuse to re-misattribute a host bwrap failure to the plugin path (a 6th round of the same
mistake)."** The plan's on-host verification step is built around this.

**Honesty caveat (load-bearing).** The three refutations above are reasoned from code on a dev machine — exactly
the posture the ADR-079 learning warns against. They are strong (direct, unambiguous line-level evidence) but the
plan still **requires an on-host confirmation step** before declaring the fix landed (Phase 4). If the on-host
evidence contradicts this reconciliation, that is a finding, not a failure — surface it and re-scope.

---

## User-Brand Impact

**If this lands broken, the user experiences:** a Concierge session that either (a) continues to silently run the
connected repo's frozen tooling (delivery regression — the #4826 wedge persists and every future plugin fix is
invisible to that workspace), or (b) fails to load the plugin at all (dead session: no commands/skills). Concrete
artifact: the operator's `/soleur:go` session wedging on worktree creation, or returning "no such command".

**If this leaks, the user's workflow/credentials are exposed via:** untrusted `hooks/*.sh` from a connected repo
executing in the **Node dispatch process** (server env + privileges, outside the bwrap sandbox) on every session
start/stop — able to read the dispatch process's environment (service tokens, ambient secrets) and weaken the
platform's in-process tool-gating callbacks. Exposure vector: `plugins/soleur/hooks/hooks.json` → `type:"command"`
hooks resolved against the untrusted workspace copy.

**Brand-survival threshold:** `single-user incident`. A single Concierge user with a connected repo that ships
`plugins/soleur/` (the operator today; any customer who forks/points at soleur tomorrow) is enough. `requires_cpo_signoff: true`; `user-impact-reviewer` + `security-sentinel` run at review.

---

## Confirmed Root Cause (verified; not re-derived)

Two independent mechanisms make the connected-repo copy win, both must be fixed:

1. **The SDK plugin load itself.** Both real-SDK factories set `plugins: [{ type:"local", path: <workspacePath>/plugins/soleur }]`:
   - `cc-dispatcher.ts:2387` — `const pluginPath = path.join(workspacePath, "plugins", "soleur")` (Concierge / cc-soleur-go).
   - `agent-runner.ts:1109` — identical line inside legacy `startAgentSession` (**#6115 missed this second factory**).
   Both flow through `agent-runner-query-options.ts:231` → `plugins:[{type:"local",path:args.pluginPath}]`.
   `scaffoldWorkspaceDefaults` only symlinks the workspace path to the deployed plugin
   `if (!existsSync(symlinkTarget))` (`workspace.ts:438`); a committed `plugins/soleur/` dir makes that false, so
   the symlink is skipped and the committed copy stays.
2. **The bash the deployed skills shell out to.** Even when the SDK loads the DEPLOYED `go.md`/`one-shot`, their
   `bash ./plugins/soleur/…/worktree-manager.sh` invocations are **CWD-relative** (CWD = workspace), so they run
   the connected repo's committed `worktree-manager.sh`. Fixing (1) alone does not fix (2).

Already deployed & working (do NOT redo): #6108 (`worktree-manager.sh` non-bare guard), #6068 (host git-config
heal + `git-lock-marker-telemetry` hook), `git-repo-readiness-diag.sh`. Operator's interim unblock
(`git -C /workspaces/<id> pull origin main`) is a workaround, **not** part of this plan — this plan removes the
need for it (see Hard ACs).

---

## Design — Options Evaluated & Decision

| Option | Security posture | Canary impact | Git-tree impact | Verdict |
|---|---|---|---|---|
| **1. Force-symlink `<workspace>/plugins/soleur` → deployed** (delete the committed dir, replace with a symlink in `scaffoldWorkspaceDefaults`) | **Weak** — the SDK load path is still a workspace path; a scaffolding race/failure falls back to loading untrusted code. | Neutral (path string unchanged) — but irrelevant, see Reconciliation (the change doesn't hit the fixture anyway). | **Catastrophic** — the dogfooder's `git status` shows all of `plugins/soleur/` deleted+symlinked; destroys their working tree. | ❌ Reject |
| **2. Non-colliding workspace symlink `<workspace>/.soleur-plugin` → deployed**, point SDK there (#6117's proposed direction) | **Weak** — still routes the SDK plugin load through a symlink in the untrusted workspace dir; a malicious repo can pre-create `.soleur-plugin`. Its ONLY claimed advantage ("`/app/shared` not sandbox-accessible") is **refuted** (Reconciliation row 1). | Changes nothing that matters; adds a symlink indirection. | Clean (gitignored name). | ❌ Reject — solves a non-problem, weakens security. |
| **3. Load the plugin from `getPluginPath()` (absolute platform path), for BOTH factories; inject `CLAUDE_PLUGIN_ROOT`; migrate the shelled-out `worktree-manager.sh` invocations to `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}`** | **Strong** — the SDK plugin source is an absolute platform path with **zero dependence on the untrusted workspace**; a connected repo cannot influence it. `getPluginPath()` carries an `/app/`-prefix allowlist guard (`plugin-path.ts:23-46`). | None — doesn't touch `buildAgentSandboxConfig` (Reconciliation row 2). | Clean — no workspace mutation. | ✅ **Select** |

**Decision: Option 3.** It is the security-correct posture the finding demands (platform-controlled, workspace-
independent load source), it is delivery-correct (deployed plugin authoritative), and — per the Reconciliation —
it is canary-neutral. It is #6115's approach, **corrected to (a) cover BOTH SDK factories (#6115 missed
`agent-runner.ts`), (b) replace the false "regenerate the fixture" step with the real on-host bwrap-health gate,
and (c) add a discriminating load-source probe so the affected surface is no longer blind.**

`${CLAUDE_PLUGIN_ROOT}` must be injected explicitly: it is **NOT** in `AGENT_ENV_ALLOWLIST` (`agent-env.ts:33-49`),
by design (the allowlist copies ambient `process.env`; this is a per-dispatch value). Threaded via
`BuildAgentEnvOptions.pluginPath` → `env.CLAUDE_PLUGIN_ROOT` at `agent-env.ts`, from
`agent-runner-query-options.ts:206` alongside the existing `plugins:` binding. This half is **provably
canary-neutral** (`--setenv` is dropped from the projection).

---

## Implementation Phases

Contract-order matters (contract change before consumer). Single atomic PR; phases are TDD order.

### Phase 1 — SDK loads the deployed plugin (both factories) [security core]
1. `cc-dispatcher.ts`: import `getPluginPath` from `./plugin-path`; replace `path.join(workspacePath,"plugins","soleur")` (`:2387`) with `getPluginPath()`. Keep the `nosemgrep` intent (now the value is a platform constant, not workspace-derived).
2. `agent-runner.ts:1109` (legacy `startAgentSession`): same replacement. **This is the factory #6115 missed** — leave it and the security hole persists on the legacy path.
3. Decide the shared-builder story: both factories still call `buildAgentQueryOptions({ pluginPath, … })`; with both now passing `getPluginPath()`, `plugins:[{path}]` at `agent-runner-query-options.ts:231` is correct.
4. **[F3 — security-sentinel, residual in-process reader] Fix `context-queries-hook.ts:161`.** `createContextQueriesHook(args.workspacePath)` (registered for BOTH factories at `agent-runner-query-options.ts:289`) builds `skillsDir = path.join(workspacePath,"plugins","soleur","skills")` and reads `<name>/SKILL.md` from the **untrusted workspace copy** on every Skill dispatch — independent of `plugins:`, so Phase 1.1/1.2 do NOT touch it. It is not arbitrary code-exec (its only `execFile` is a fixed `git ls-files -- <query>` gated to `knowledge-base/`), but it (a) sources SKILL.md frontmatter from untrusted content into the agent context (prompt-injection-adjacent) and (b) violates the ADR's trust-boundary claim. **Fix:** source `skillsDir` from `getPluginPath()`; keep the `knowledge-base/` root workspace-rooted (that split is correct). `settingSources:[]` (`agent-runner-query-options.ts:195`) already blocks workspace `.claude/settings.json` hook loading — no separate closure needed. `agent-runner.ts:1167` `pluginJsonPath` derives from `pluginPath` → fixed transitively by 1.2.
5. **[architecture — loaded-gun guard]** `QueryFactoryArgs.pluginPath` (`soleur-go-runner.ts:1042`) is currently ignored by `realSdkQueryFactory`. Rather than only "document," have the plugin-path consumers assert `path.isAbsolute(p) && p.startsWith("/app/")` (reuse the `plugin-path.ts` allowlist) so a future dev who "wires up the ignored arg" with a workspace-derived path fails loudly instead of silently reopening the hole.

### Phase 2 — Inject `CLAUDE_PLUGIN_ROOT` into the agent bash env, **fail-closed** [delivery]
1. `agent-env.ts`: add `pluginPath?: string` to `BuildAgentEnvOptions`; after the allowlist loop / GH_TOKEN block (`~:147`), `if (opts?.pluginPath) env.CLAUDE_PLUGIN_ROOT = opts.pluginPath;` with the WHY comment (per-dispatch, not allowlisted). This half is **provably canary-neutral** (`--setenv` dropped from the projection).
2. `agent-runner-query-options.ts:206`: thread `pluginPath: args.pluginPath` into `buildAgentEnv(...)` (now `getPluginPath()`).
3. **[F2 — security-sentinel + architecture, fail-open→fail-closed] Prove and enforce the runtime guarantee.** AC3 only proves `CLAUDE_PLUGIN_ROOT` in `buildAgentEnv`'s OUTPUT; it does NOT prove the value reaches the **bwrap-sandboxed Bash subprocess** (`--setenv` vs `--clearenv` is SDK-internal). If it does not propagate, Phase 3's `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` resolves to the **untrusted** `./plugins/…`. So: (a) add an **in-image test** asserting `CLAUDE_PLUGIN_ROOT` is present in the sandboxed Bash env (echo it from inside a sandboxed Bash op); (b) on the **server** dispatch, fail **closed** — if `CLAUDE_PLUGIN_ROOT` is unset where it must be set, error/observe, never silently downgrade to the workspace copy. The `:-./plugins/soleur` fallback is retained ONLY for the CLI surface (no safe-bash gate there).

### Phase 3 — Deployed scripts, not workspace-relative [delivery — REDESIGNED per security F1; sequencing under review]
**⚠️ F1 (security-sentinel, CRITICAL) invalidated the original `${CLAUDE_PLUGIN_ROOT:-…}`-regex approach.** `safe-bash.ts`'s `SHELL_METACHAR_DENYLIST` rejects `$`/`{`/`}` **per-segment, BEFORE any allowlist** (stage 1), and safe-bash sees the **unexpanded** command string. So `bash "${CLAUDE_PLUGIN_ROOT:-…}/…/worktree-manager.sh …"` is denied at stage 1 and can never be auto-approved — and punching `$` out of the denylist would re-enable `$(…)`/`${…}` injection across the entire auto-approve surface (a far worse regression). Compounding facts:
- `worktree-manager.sh list/ls` is currently the ONLY auto-approved worktree-manager verb; the wedge invocations are `cleanup-merged`/`create` (already NOT auto-approved — they run via `autoAllowBashIfSandboxed`/the sandbox path, to be confirmed at /work).
- The existing `(?:\./)?plugins/soleur/…` allowlist entry **auto-approves the untrusted workspace copy on the server** — a latent hole to close.
- **A single shared SKILL.md line cannot be both server-safe (absolute `/app/…`, `$`-free) AND CLI-correct (`./plugins/…` or `${CLAUDE_PLUGIN_ROOT}`).** This is a genuine per-surface path decision, not a fallback expando.

**Two implementable resolutions (pick at /work after on-host verification of F2 env-propagation):**
- **(3a) Exact-literal allowlist carve-out.** Skills keep `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}/…` (CLI-correct + correct server *resolution* once F2 proves the var reaches sandbox bash); `safe-bash.ts` adds an **exact-literal** allowlist entry matching that precise raw string for the known script tail + subcommand set — a literal carve-out that does NOT loosen the general `$` denylist (no `$(…)` enabled). Remove/rescope the `./plugins/…` server auto-approve so the untrusted copy is never auto-approved. Safe regex for the expanded absolute form, if that path is chosen instead: `^bash\s+/app/[\w.\-/]*plugins/soleur/skills/git-worktree/scripts/worktree-manager\.sh\s+(?:list|ls|cleanup-merged|create)…$` (never contains `$`/`{`/`}`; `..` still blocked by `PATH_TRAVERSAL_DENYLIST`).
- **(3b) Absolute server path.** Deployed skills emit `/app/shared/plugins/soleur/…` directly; CLI resolution handled separately. Simpler denylist story, but the shared-file per-surface conflict must be solved (e.g. a build-time surface variant).

**Scope trim (simplicity-reviewer):** keep in this slice only `go.md:24,41` + `one-shot/SKILL.md:47,65` + `work/SKILL.md:43,85,163` (the `/soleur:go`→worktree-creation flow) + the `safe-bash.ts` change. **Defer** `brainstorm`/`merge-pr`/`drain-prs`/`fix-issue`/`ship`/`git-worktree/SKILL.md` example lines (same sandboxed-Bash risk class as the already-deferred `archive-kb`/`deploy`/… families — the cut line is "in the wedge flow," not "same script name") to the tracked follow-up.

**Sequencing (decision surfaced to operator — see `## Sequencing Decision`):** Phase 3's safe-bash redesign + F2 env-propagation are unverified-from-dev-machine and carry the sharpest security surface; Phase 1 (+F3) is a clean, standalone security fix. Recommendation is to **ship Phase 1+F3 as the security PR now and land Phase 2+3 (delivery) as a sequenced second PR** once F1/F2 are resolved on-host — unless the operator wants both bundled.

### Phase 4 — On-host cutover verification (NOT fixture regeneration) [operator/CI]
See **Canary Handling** below. This is the corrected replacement for the requested ADR-079 fixture-regen step.

### Phase 5 — Observability [reduced per simplicity-reviewer]
**Correction:** after Phase 1 the SDK load source is a compile-time constant (`getPluginPath()`), so a per-dispatch
`source=='workspace-shadow'` event monitors a **state the code cannot produce** (a tautology). Reduce to: (a) rely on
the existing `verifyPluginMountOnce()` boot probe (deployed-root missing/empty → Sentry) + the deploy SHA to answer
"is the new build actually running on the operator's surface?"; (b) a single diagnostic breadcrumb field
`connectedRepoShipsPlugin` on the existing dispatch/plugin-mount channel (records the previously-silent collision
condition — no new pipeline). Drop the synthetic-`workspace-shadow` test and the shadow-count monitor.

### Phase 6 — Defense-in-depth: make the collision non-silent (optional, in scope if cheap)
`scaffoldWorkspaceDefaults` (`workspace.ts:433-444`): when the connected repo already ships a real `plugins/soleur/`
dir, `log.warn` / mirror a one-line Sentry breadcrumb ("connected repo ships plugins/soleur — deployed plugin is
authoritative via SDK load; workspace copy is inert for the SDK"). Does not change the load (Phase 1 already made
the workspace symlink irrelevant to the SDK); purely surfaces the previously-silent condition.

---

## Files to Edit

- `apps/web-platform/server/cc-dispatcher.ts` — `:2387` → `getPluginPath()`; add import.
- `apps/web-platform/server/agent-runner.ts` — `:1109` → `getPluginPath()`; add import.
- `apps/web-platform/server/agent-env.ts` — `BuildAgentEnvOptions.pluginPath` + `CLAUDE_PLUGIN_ROOT` injection.
- `apps/web-platform/server/agent-runner-query-options.ts` — thread `pluginPath` into `buildAgentEnv`.
- `apps/web-platform/server/context-queries-hook.ts` — `:161` `skillsDir` → `getPluginPath()` (**F3 residual reader**).
- `apps/web-platform/server/safe-bash.ts` — allowlist change is an **exact-literal carve-out** (NOT a regex `$`-extension — see Phase 3 F1); remove/rescope the `./plugins/…` server auto-approve (security-reviewed).
- `apps/web-platform/server/workspace.ts` — `scaffoldWorkspaceDefaults` non-silent collision warn (Phase 6).
- (Observability breadcrumb — Phase 5, reduced: `connectedRepoShipsPlugin` on the existing channel; NOT a per-dispatch source probe.)
- `plugins/soleur/commands/go.md` — `:24`, `:41`.
- `plugins/soleur/skills/one-shot/SKILL.md` — `:47`, `:65`.
- `plugins/soleur/skills/work/SKILL.md` — `:43,85,163` (kept in-scope: the wedge flow).
- *(deferred to follow-up: `ship`/`brainstorm`/`merge-pr`/`drain-prs`/`fix-issue`/`git-worktree/SKILL.md` examples — same sandboxed-Bash risk class.)*
- **Tests:** `apps/web-platform/test/cc-dispatcher-real-factory.test.ts` (T3 `:466-474` flips to `getPluginPath()` value), `agent-runner-query-options.test.ts` (`PLUGIN`/`:60`), `agent-env.test.ts` (re-add `CLAUDE_PLUGIN_ROOT` injection + omission tests), `agent-runner-helpers.test.ts:187`, `mu1-integration.test.ts:69/74/273` (symlink expectations — verify still valid since Phase 1 makes the symlink SDK-irrelevant but the item-1 symlink for normal users is unchanged).

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-093-sdk-plugin-source-is-platform-deployed-not-connected-repo.md` (ordinal provisional — see ADR gate).
- `knowledge-base/project/learnings/bug-fixes/2026-07-06-connected-repo-shadows-deployed-plugin-via-workspace-relative-path.md` (re-capture of the file reverted with #6115, **enhanced** — see below).

---

## Canary Handling (the corrected gating step)

**No ADR-079 fixture regeneration is required by this change** (Reconciliation row 2). The steps that ARE required:

1. **Pre-cutover host-health gate (operator/CI, read-only).** Before merging/cutover, confirm the **hardcoded**
   bwrap probe is green on the target host — i.e. `bwrap --new-session --die-with-parent --dev /dev --unshare-pid
   --bind / / -- true` exits 0 inside a canary container on the current host. If it is red, the host has a
   userns/bwrap capability issue (the `#4932`/`#5849` class, prevented at source by `bwrap-userns-sysctl.service`)
   — resolve THAT first; it is unrelated to this PR. **Automation:** read the last `final_write_state` reason from
   `/hooks/deploy-status` (HMAC + CF Access via Doppler `prd_terraform`, read-only) — do NOT SSH.
2. **CI `--verify` stays green (deterministic, no creds needed for the assertion).** Because this PR does not touch
   `buildAgentSandboxConfig`, the on-branch `sandbox-canary.mjs --verify` byte-diff against
   `sandbox-canary-argv.json` must remain green. **AC:** the fixture is unchanged in this PR's diff.
3. **Cutover diagnostic (operator, on the re-apply deploy).** Read the actual deploy-state reason from
   `/hooks/deploy-status` + Sentry. **If `canary_sandbox_failed` recurs, treat it as the HOST bwrap/userns issue
   (diagnose per the `#4932`/`#5849` lineage), NOT as a plugin-path problem to revert.** Reverting the plugin fix
   for a `canary_sandbox_failed` would be the 6th round of the same misattribution. The load-source probe (Phase 5)
   + `verifyPluginMountOnce` Sentry signal confirm the plugin actually loads from the deployed root on the surface.
4. **Defensive contingency only:** IF the on-host `--verify` unexpectedly shows `argv_drift` (it should not),
   THEN regenerate via `sandbox-canary-verify-in-image.sh` / `--capture` **inside the `node:22-slim` deploy base
   image** (never on a dev machine or the runner — host-conditional tokens, per the ADR-079 learning) and commit
   the refreshed fixture. This is a no-op contingency, documented so /work does not improvise.

---

## Architecture Decision (ADR/C4)

This changes a **trust boundary** (the SDK plugin/hook load source moves from the untrusted connected-repo
workspace copy to the platform-controlled deployed root) → ADR is a deliverable of THIS plan (`wg-architecture-decision-is-a-plan-deliverable`), not a follow-up.

### ADR
Create **ADR-093 — "SDK plugin/hook source is the platform-deployed root, never the connected-repo workspace copy."**
Decision: both real-SDK factories load `plugins:[{path: getPluginPath()}]`; deployed skills invoke out-of-tree
scripts via `${CLAUDE_PLUGIN_ROOT}`; the connected-repo workspace copy is untrusted and inert for the SDK.
Alternatives Considered: Options 1 & 2 above (record why rejected). Relates to / does not reverse ADR-044
(workspace connection resolution), ADR-080 (runtime plugin deploys via image rebuild — the deployed root's
provenance), ADR-079 (canary — record the reconciliation that no fixture regen is required). **Ordinal is
provisional**; re-verify next-free against `origin/main` at ship (ADR-ordinal collision gate) and sweep planning
docs for the old ordinal if renumbered.

### C4 views
Read all three model files. **model.c4 read in full** (this session): the relevant elements/edges are
`claude -> skillloader "Loads plugin" {File I/O}` (`model.c4:298`), the `skillloader` container (`:56-59`), the `api`
container's in-process Agent-SDK hooks note (`:39-42`), and — the precedent to mirror — the **`contributor`
untrusted external actor** (`model.c4:19-25`) with its explicit trust-boundary comment block (`:286-291`).
**[architecture MEDIUM] Edge-annotation alone under-models the boundary.** A trust boundary is the *relationship
between* a trusted and an untrusted source; the model currently represents only the trusted `plugin` system.
**C4 task:** mirror the `contributor` precedent — add an element (or explicit note + boundary comment à la
`:286-290`) representing the **connected-repo committed `plugins/soleur/` as an UNTRUSTED plugin source**, and state
the boundary: the SDK loads the deployed root and treats the workspace copy as inert. Then annotate
`claude -> skillloader "Loads plugin"` with the deployed-root source. **/work MUST also read `views.c4` + `spec.c4`**
(not read this session — sequence early, they are a late-failure risk) to confirm the new element/edge renders and no
`view include` references an undefined element; then run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Sequencing
The decision is true at merge (no soak gate). ADR status `accepted` on merge.

---

## Observability

```yaml
liveness_signal:
  what: "per-dispatch structured event recording the SDK plugin load source (deployed vs workspace-shadow) + path"
  cadence: "every Concierge/agent dispatch (both factories)"
  alert_target: "Sentry (breadcrumb/tag) + existing Better Stack pipeline"
  configured_in: "cc-dispatcher.ts + agent-runner.ts (or shared agent-runner-query-options.ts), plus existing verifyPluginMountOnce() boot probe (plugin-mount-check.ts)"
error_reporting:
  destination: "Sentry via reportSilentFallback (existing plugin-mount channel)"
  fail_loud: true
failure_modes:
  - mode: "connected repo ships plugins/soleur (previously-silent collision condition)"
    detection: "connectedRepoShipsPlugin breadcrumb on the existing dispatch/plugin-mount channel (diagnostic; post-Phase-1 the SDK load source is constant, so a per-dispatch 'workspace-shadow' state cannot occur — do NOT monitor it)"
    alert_route: "Sentry breadcrumb (diagnostic, not an alert)"
  - mode: "deployed plugin root missing/empty in a container (canary or prod)"
    detection: "verifyPluginMountOnce() -> reportSilentFallback('plugin-mount path missing'/'empty') (plugin-mount-check.ts)"
    alert_route: "Sentry plugin-mount dashboard"
  - mode: "canary rolls back with canary_sandbox_failed on the re-apply"
    detection: "/hooks/deploy-status final_write_state reason + Sentry faithful-canary FAIL event"
    alert_route: "deploy-status webhook read (no SSH); triage as HOST bwrap/userns per Canary Handling step 3"
logs:
  where: "Sentry + Better Stack (existing dispatch + plugin-mount channels)"
  retention: "existing"
discoverability_test:
  command: "curl -s https://deploy.soleur.ai/hooks/deploy-status | jq -r '.reason'  # + Sentry API query source=='workspace-shadow'"
  expected_output: "deploy reason 'ok'; zero source=='workspace-shadow' events post-deploy"
```

`§2.9.2 blind-surface note:` cc-dispatcher is a container-dispatch surface. The load-source probe's fields
(`source` / `pluginPath` / `connectedRepoShipsPlugin`) **discriminate the competing hypotheses in one event**
(deployed-load-succeeded vs workspace-shadow-persists vs deployed-root-missing) — the exact instrumentation whose
absence caused the 5-round guessing saga.

---

## Domain Review

**Domains relevant:** Engineering (security, architecture). Product: NONE (no UI-surface files in Files-to-Edit —
server TS + plugin markdown only; no `components/**`, `app/**/page.tsx`). Product/UX Gate skipped.

### Engineering — Security (BLOCKING per the finding; operator explicitly requested)
`security-sentinel` runs at plan-review AND at code-review. Focus: (1) both SDK factories now load from
`getPluginPath()` — confirm no residual workspace-relative SDK plugin load remains; (2) the `safe-bash.ts:151`
allowlist extension is tightly anchored (no over-broadening that would allow arbitrary `${...}` paths); (3) the
`${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` fallback cannot be induced (by unsetting the env) to run the untrusted
copy on the Concierge surface; (4) the in-process hook execution threat is fully closed by the deployed-load
posture. `user-impact-reviewer` runs at review (single-user-incident threshold).

**CPO sign-off required at plan time** (single-user-incident). Invoke CPO domain leader or confirm CPO review.

---

## Slice B /work Resolution (2026-07-07)

**F2 verified POSITIVE in-image → resolution 3a shipped.** The gating unknown resolved cleanly:
`CLAUDE_PLUGIN_ROOT` reaches the bwrap-sandboxed bash (verdict `propagates`, `node:22-slim`
in-image). The mechanism is **env inheritance, not `--setenv`**: the SDK spawns bwrap with
`options.env` as its process env and does NOT `--clearenv`, so the sandboxed command inherits
`CLAUDE_PLUGIN_ROOT`. The env-isolation boundary (CWE-526) is `buildAgentEnv` upstream, unchanged.

**Fail-closed, refined.** The plan framed the server risk as "fail closed if `CLAUDE_PLUGIN_ROOT`
is unset — never silently downgrade to `./plugins`." The codebase makes the unset-on-server state
**unrepresentable**: both factories compute `pluginPath = getPluginPath()` (a non-empty `/app/`
default) and thread it unconditionally, so `buildAgentEnv` always injects the var on server
dispatch and `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` never resolves the `:-` branch there. The
fail-closed guarantee is `assertTrustedPluginPath` (Slice A + AC7b), which **throws** before
dispatch on any non-`/app/` value — a stronger guard than a runtime "if unset" check (the value
cannot be unset). The `:-./plugins/soleur` default serves ONLY the CLI surface (var unset →
local checkout, correct). No separate server fail-closed branch was added because there is no
server code path that reaches it — adding one would be untestable dead code (simplicity-reviewer).

**3a vs 3b:** 3a (exact-literal `${CLAUDE_PLUGIN_ROOT:-…}` carve-out) chosen — it is CLI-correct
AND server-correct with F2 proven, needs no build-time surface variant (3b), and does not weaken
the `$`-denylist. Not an architecture fork (bounded, plan-pre-authorized) → no CTO routing.

## Sequencing Decision (operator input requested)

Security review (F1) established that the **delivery half (Phase 2+3)** carries the sharpest, least-verified
surface — a `safe-bash.ts` allowlist redesign + an unproven-from-dev-machine runtime env-propagation guarantee (F2)
— whereas the **security half (Phase 1 + F3 + hooks.json closure)** is a clean, standalone fix that fully closes the
untrusted-code-execution finding on its own. This is a genuine ship-sequencing decision:

- **Option S1 — Split (recommended):** Ship **Phase 1 + F3** as the security PR now (closes the finding
  immediately, low blast radius). Land **Phase 2 + 3** (delivery / #4826 wedge) as a sequenced second PR once F1's
  safe-bash carve-out and F2's env-propagation are verified on-host. The operator's interim `git -C /workspaces/<id>
  pull origin main` + #6108 cover the wedge in the meantime. **Trade-off:** the HARD "no manual git pull" AC (AC11)
  is met by the *second* PR, not the first.
- **Option S2 — Bundle:** One PR does everything. Fully meets AC11 at merge, but couples the security-critical fix
  to the riskier safe-bash + env-propagation changes and cannot cut over until those are on-host-verified.

*Recommendation: S1* (mirrors the foundations-vs-delivery learning — do not gate a clean security fix on an
unverified delivery mechanism). The operator's call, surfaced via AskUserQuestion.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1 (security — enumerate ALL workspace-plugin readers, not two lines):** re-derive the residual-reader set with a broad grep, not a hardcoded pair — `git grep -nE '"plugins",\s*"soleur"|plugins/soleur' apps/web-platform/server` — and confirm every SDK plugin/hook/skill reader sources from `getPluginPath()`: both factories (`cc-dispatcher.ts:2387`, `agent-runner.ts:1109`), the F3 `context-queries-hook.ts:161` `skillsDir`, and `agent-runner.ts:1167` `pluginJsonPath` (transitive). No reader constructs a `workspacePath`-relative plugin/skills path. (The narrow `path.join(workspacePath,"plugins","soleur")` grep MISSES `context-queries-hook`'s `join(repoRoot,"plugins","soleur","skills")` shape — that miss is the F3 finding.)
- [x] **AC2 (canary-neutral):** this PR's diff does **not** touch `apps/web-platform/infra/sandbox-canary-argv.json` nor `apps/web-platform/server/agent-runner-sandbox-config.ts`; `bun scripts/sandbox-canary.mjs --verify infra/sandbox-canary-argv.json` (CI, in-image) remains green (verdict `verify_ok`). **[Slice B: verified UNTOUCHED via `git diff --name-only origin/main...HEAD`.]**
- [x] **AC3 (env injection, canary-neutral):** `buildAgentEnv(..., { pluginPath: "/app/shared/plugins/soleur" }).CLAUDE_PLUGIN_ROOT === "/app/shared/plugins/soleur"`; `buildAgentEnv(...)` with no `pluginPath` omits the key. `CLAUDE_PLUGIN_ROOT` is NOT added to `AGENT_ENV_ALLOWLIST`. **[Slice B B1/B2: `agent-env.ts` + `agent-env.test.ts` (injection/omission/ambient-no-leak tests GREEN).]**
- [ ] **AC4 (both factories):** `cc-dispatcher-real-factory.test.ts` T3 asserts `opts.plugins == [{type:"local", path:"/app/shared/plugins/soleur"}]`; an equivalent assertion covers `agent-runner.ts startAgentSession`.
- [x] **AC5 (invocation migration):** every `bash ./plugins/soleur/.../worktree-manager.sh` / `git-repo-readiness-diag.sh` site in `go.md`, `one-shot`, `{work,ship,brainstorm,merge-pr,drain-prs,fix-issue}/SKILL.md`, and `git-worktree/SKILL.md` uses the `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` form. Verify: `git grep -nE 'bash \./plugins/soleur/skills/git-worktree/scripts/(worktree-manager|git-repo-readiness-diag)\.sh' plugins/soleur/{commands,skills}` returns only intentionally-deferred sites (see Open Code-Review Overlap / deferral). **[Slice B: the 7 WEDGE-FLOW sites migrated (go.md:24,41 · one-shot:47,65 · work:43,85,163); AC5 grep over those 3 files returns 0 bare sites. The `ship`/`brainstorm`/`merge-pr`/`drain-prs`/`fix-issue`/`git-worktree` families stay DEFERRED per the Phase 3 scope-trim → #6121, NOT this slice — the AC's file list is the plan's full-migration target, not Slice B's.]**
- [x] **AC6 (safe-bash — F1-safe):** the `$` metachar denylist is **unchanged** (still rejects `$`/`{`/`}`/`$(…)`); the new allowlist entry is an **exact-literal carve-out** for the specific worktree-manager/readiness-diag invocation(s) only; the pre-existing `./plugins/…` server auto-approve of the untrusted copy is removed/rescoped. Unit-test: the exact known invocation is allowed; an arbitrary `${FOO}` / `$(…)` / a `../`-traversal / a different script path is denied. **[Slice B B4: `EXACT_LITERAL_SAFE_COMMANDS` set + stage-0 exact-equality check; bare `(?:\./)?plugins/…` regex REMOVED; `safe-bash.test.ts` allow/deny matrix GREEN (282 tests).]**
- [x] **AC7 (F2 — runtime env guarantee):** an **in-image** test asserts `CLAUDE_PLUGIN_ROOT` is present in the **sandboxed Bash** env (not merely in `buildAgentEnv` output — that is AC3). **[Slice B B3: PROVEN in `node:22-slim` in-image — verdict `propagates`, `clearenv:false`. MECHANISM (empirical): the SDK does NOT `--clearenv`, so the sandboxed bash INHERITS `CLAUDE_PLUGIN_ROOT` from the bwrap-process env (= `options.env` = buildAgentEnv output). It is NOT in the 26-var `--setenv` allowlist; inheritance carries it. Committed as `plugin-root-sandbox-propagation-probe.mjs` + `plugin-root-propagation-verify-in-image.sh` + a creds-gated CI job (fail-closed on `does_not_propagate`). Because propagation is env-inheritance, the fallback is NOT fail-open on the server: `CLAUDE_PLUGIN_ROOT` is ALWAYS injected on the server dispatch (both factories thread `getPluginPath()`), so `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` never resolves to the `:-` branch there — the CLI (var unset) is the only surface that hits the local `./plugins/soleur` default, which is correct.]**
- [x] **AC7b (loaded-gun guard):** plugin-path consumers assert `path.isAbsolute(p) && p.startsWith("/app/")`; a workspace-relative value fails loudly (unit-tested). **[Slice A `assertTrustedPluginPath` (unit-tested in `plugin-path.test.ts`); Slice B threads its validated result into BOTH the `CLAUDE_PLUGIN_ROOT` env injection AND the `plugins:` binding, computed once — an untrusted value now fails closed before either reaches a live dispatch.]**
- [ ] **AC8 (ADR/C4):** ADR-093 created (`accepted`); the `claude -> skillloader "Loads plugin"` edge/description in `model.c4` annotated with the deployed-root trust boundary; `c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- [ ] **AC9 (typecheck/tests):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; the four touched test suites pass (use the package's real runner — vitest per `vitest.config.ts`, NOT `npm run -w`).
- [ ] **AC10 (learning):** the reverted learning file is re-created enhanced with the canary drift-gate reconciliation and the "two SDK factories" correction.
- [ ] **AC11 (HARD — no manual pull, deployed authoritative):** With this fix, a Soleur user — **including one whose connected repo IS soleur itself** — never needs a manual `git pull`/`git fetch` for the platform to use current tooling. Evidenced by: the SDK loads commands/skills/agents/hooks from the deployed root (Phase 1); the wedge script family runs from the deployed root via `${CLAUDE_PLUGIN_ROOT}` (Phase 3). *Test:* on a synthetic workspace whose committed `plugins/soleur/worktree-manager.sh` differs from deployed, the loaded/executed version is the deployed one (assert via the load-source probe + a version sentinel).
- [ ] **AC12 (HARD invariant — worktree bases stay fresh; non-regression, folded into AC9):** worktree creation continues to base off a **fresh `git fetch origin main`** (`worktree-manager.sh:853` heal-base fetch; `:1583-1587` `git fetch origin main:main` before create). This PR does **not** touch `worktree-manager.sh`'s base-fetch logic, so the property is preserved by construction; verified by the existing `worktree-manager` test suite staying green under AC9 (not a standalone grep of untouched code — that would be LARP per simplicity-reviewer). Stated here because it is a HARD operator requirement the delivery half must not regress.
- [ ] **AC12b (F4 — test-bypass not widened):** under `NODE_ENV=production` (VITEST unset), `getPluginPath()` with a non-`/app/` `SOLEUR_PLUGIN_PATH` override falls back to the default (the `/app/` prefix guard holds); this fix adds no new production exposure.

### Post-merge (operator)
- [ ] **AC13:** Read `/hooks/deploy-status` reason after the re-apply deploy (`curl … | jq -r '.reason'`) — expect `ok`. If `canary_sandbox_failed`, triage as HOST bwrap/userns (Canary Handling step 3), do NOT revert the plugin fix. `Automation:` deploy-status webhook read (no SSH).
- [ ] **AC14 (reframed — the shadow-count monitor was a dead branch):** confirm the operator's container is running the new build (deploy SHA advanced) AND Sentry shows **zero** `verifyPluginMountOnce` plugin-mount fallbacks on it post-deploy; plus the `connectedRepoShipsPlugin` breadcrumb is observed (proving the collision path was exercised and is now inert). `Automation:` deploy-status + Sentry API.
- [ ] **AC15:** `gh issue close` the tracking issue only after AC13+AC14 hold (use `Ref #N` in the PR body, not `Closes`, since verification is post-merge).

---

## Test Scenarios
1. **Shadow closed (both factories):** synthetic workspace with a differing committed `plugins/soleur/`; assert SDK `plugins:` path == deployed root for `realSdkQueryFactory` AND `startAgentSession`.
2. **Env injection both-or-nothing:** `CLAUDE_PLUGIN_ROOT` present iff `pluginPath` supplied; absent from allowlist.
3. **safe-bash:** deployed-form worktree-manager `list` allowed; arbitrary `${X}`/absolute path denied.
4. **Fallback safety:** with `CLAUDE_PLUGIN_ROOT` set (Concierge), `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` resolves to deployed; unset (CLI), resolves to `./plugins/soleur` (local-correct).
5. **Canary neutrality:** `--verify` green; fixture untouched in diff.
6. **Load-source probe discriminates** deployed vs workspace-shadow vs missing-root.

---

## Open Code-Review Overlap
Run `gh issue list --label code-review --state open --json number,title,body` and `jq --arg path <each>` against
Files-to-Edit at /work (deferred until the edit list is frozen). Record `None` / dispositions there.

**Disposition (Slice A /work, 2026-07-06):** `None`. The four open `code-review` issues (#4529 compound-docs, #4525
`resolveCurrentOrganizationId` migration, #4254 tenant-iso fixture drift, #3829 Sentry-monitor CI gate) touch none of
Slice A's edited files (`cc-dispatcher.ts`, `agent-runner.ts`, `context-queries-hook.ts`, `plugin-path.ts`,
`agent-runner-query-options.ts`, `workspace.ts`, `model.c4`/`views.c4`).

## Deferrals (tracked)
- **Slice B (Phase 2+3) + broader `${CLAUDE_PLUGIN_ROOT}` migration** — filed as **#6121** (consolidated tracker,
  `type/security` + `deferred-scope-out`, milestone Phase 4). Covers: the delivery half (`CLAUDE_PLUGIN_ROOT` env
  injection + F2 in-image env-propagation proof + F1 `safe-bash.ts` exact-literal carve-out + wedge-flow skill
  migration) AND the non-worktree-manager script families (`archive-kb.sh`, `deploy.sh`, `pencil-setup check_deps.sh`,
  `feature-video`, `community-router.sh`, `compound token-efficiency-report.sh`, brand/validation workshop refs — ~9
  sites). Re-eval criterion recorded in the issue: after PR-A soaks + Slice B's safe-bash/F2 are on-host-verified.

---

## Sharp Edges & Risks
- **[F1] safe-bash rejects `$` before the allowlist.** `bash "${CLAUDE_PLUGIN_ROOT:-…}"` can never be auto-approved via a regex; do NOT weaken `SHELL_METACHAR_DENYLIST` (it seals `$(…)` injection). Use an exact-literal carve-out (Phase 3a) and remove the `./plugins/…` server auto-approve of the untrusted copy. `list/ls` is the only currently-auto-approved worktree-manager verb.
- **[F2] the `:-./plugins/soleur` fallback fails OPEN to untrusted code.** It must be fail-closed on the server surface; the runtime guarantee that `CLAUDE_PLUGIN_ROOT` reaches the *sandboxed* bash is unverified from a dev machine — prove it in-image before relying on Phase 3.
- **[F3] a non-`plugins:` in-process reader (`context-queries-hook.ts:161`) reads the workspace copy** — Phase 1 alone leaves it; AC1's narrow grep misses it. Enumerate ALL readers.
- **A plan whose `## User-Brand Impact` section is empty/placeholder fails deepen-plan Phase 4.6** — it is filled above.
- **Two SDK factories, not one (#6115's miss).** The most likely repeat-mistake is fixing only `cc-dispatcher.ts`
  and shipping with `agent-runner.ts:1109` still loading the workspace copy. AC1's grep is the guard.
- **Wrong-layer misattribution is the dominant failure mode here** (the whole saga). At review, resist any
  "canary failed → revert the plugin change" reflex without reading `/hooks/deploy-status` for the actual reason
  and confirming the hardcoded bwrap probe's host health first.
- **`safe-bash.ts` over-broadening** is a security regression risk — the allowlist extension must be anchored to the
  exact script path + subcommands, reviewed by security-sentinel.
- **C4 completeness:** `views.c4` + `spec.c4` still to be read at /work; a `view include` of an undefined element
  fails `c4-render.test.ts`, not `tsc`.
- **Which factory does the operator's surface actually run?** cc-dispatcher (cc-soleur-go) vs legacy
  `startAgentSession` — the load-source probe (Phase 5) answers this empirically post-deploy; fix both regardless.
