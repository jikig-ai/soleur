---
title: "fix: Concierge gh-auth fallback + Bash review-gate posture (default widen + opt-in autonomous toggle)"
type: fix
date: 2026-06-03
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: Concierge `gh` auth + Bash permission posture

## Enhancement Summary

**Deepened on:** 2026-06-03
**Mode:** inline deterministic deepen (Task/Explore subagent fan-out and Pencil tooling unavailable in this one-shot pipeline context; mandatory gates 4.4/4.6/4.7/4.8/4.9 + quality checks executed inline against the live codebase).

### Key Improvements
1. Precedent-diff gate (4.4) confirmed all four pattern-bound shapes against the live repo: SECURITY DEFINER RPC (`resolve_workspace_installation_id` migration 079), `is_workspace_member(uuid,uuid)` (053:116), owner-role gating (`workspace_members.role = 'owner'`, 092/091), env injection (cron `buildSpawnEnv`), deps threading (`bashApprovalCache`). No novel patterns — every new construct has a sibling.
2. `resolveCurrentWorkspaceId` (`workspace-resolver.ts:190`) confirmed present — `resolve-bash-autonomous.ts` can mirror `resolve-installation-id.ts` structurally with zero new fallback logic.
3. P0.1 hardened: `worktree-manager.sh` subcommands are `create` and `cleanup-merged` — BOTH are write/destructive. The read-only allowlist for AC8 is likely EMPTY; /work must confirm by reading the full dispatch and, if no strictly read-only subcommand exists, DROP the worktree-manager allowance entirely rather than allowlisting `cleanup-merged`.

### New Considerations Discovered
- Gate 4.9 (UI-wireframe) is a HARD-BLOCK that this pipeline cannot clear (see "Deepen Gate Dispositions" below). Resolved by deferring `.pen` production to `/work` Phase 2.5 where Pencil tooling is available — NOT by silent skip.
- `gh` CLI present at `/usr/bin/gh`; AC6 verb shapes verifiable at /work P0.2.

### Deepen Gate Dispositions
- **4.6 User-Brand Impact:** PASS (section present, threshold `single-user incident`, concrete content).
- **4.7 Observability:** PASS (5 fields present, no `ssh` in discoverability_test).
- **4.8 PAT-shaped variable:** PASS (no PAT-shaped var/literal; Issue A uses App installation token via `generateInstallationToken`, honoring `hr-github-app-auth-not-pat`).
- **4.9 UI-wireframe:** HARD-BLOCK deferred to `/work` Phase 2.5. The plan touches UI surfaces (`components/settings/`, `app/(dashboard)/dashboard/settings/`). Per `wg-ui-feature-requires-pen-wireframe` a committed `.pen` is required and there is NO Markdown fallback. Pencil/ux-design-lead tooling is NOT available in this deepen pipeline context, so the `.pen` cannot be produced here. Phase 5 of this plan is the producer; `/work` MUST run `pencil-setup --auto` and generate `knowledge-base/product/design/product/concierge-autonomous-toggle.pen` BEFORE coding the Phase 5 component. Do not proceed past Phase 5 RED without the committed `.pen`.

Two confirmed Concierge (interactive chat) agent-path defects, delivered as logically separated commits in one worktree (`feat-one-shot-concierge-perms-gh-auth`).

- **Issue A** — `gh` CLI falls back to `gh auth login` because the Concierge never mints a GitHub App installation token. Clean bug; mirror the cron fix.
- **Issue B** — every Bash command requires manual Approve/Deny. Two parts: (1) conservatively widen the read-only safe-bash auto-approve; (2) add an off-by-default per-workspace "autonomous / trusted" toggle that bypasses the Bash review-gate for all non-BLOCKED commands.

`/work` reads phases sequentially; phases are ordered by dependency direction (schema/contract before consumer) even though the whole change is one PR.

## Premise Validation

All cited references verified against the worktree `apps/web-platform/server/` (no `origin/main` divergence relevant to the cited symbols):

- `cc-dispatcher.ts` — `realSdkQueryFactory` builds env only from `getUserServiceTokens(args.userId)` + `credential`; confirmed at the `const [workspacePath, serviceTokens] = await Promise.all([...])` site and the single `buildAgentQueryOptions({...})` call. No installation-token mint anywhere in the file. **Holds.**
- `cron-daily-triage.ts` `buildSpawnEnv(installationToken)` injects `GH_TOKEN: installationToken`; `mintInstallationToken({ tokenMinLifetimeMs })` is a `step.run("mint-installation-token", …)`. **Holds.**
- `_cron-shared.ts` `mintInstallationToken()` resolves the installation via `GET /repos/{owner}/{repo}/installation` against the **hardcoded** `jikig-ai/soleur` repo (`REPO_OWNER`/`REPO_NAME`) — NOT a per-workspace id. **Drift from premise — see Research Reconciliation row 1.** The interactive path must resolve the *workspace's* installation id, not the soleur monorepo's.
- `agent-env.ts` `ALLOWED_SERVICE_ENV_VARS` is derived from `PROVIDER_CONFIG[*].envVar`; the GitHub entry is `GITHUB_TOKEN` (`providers.ts:17`), **not** `GH_TOKEN`. `AGENT_ENV_ALLOWLIST` contains neither. **Drift from premise — see Research Reconciliation row 2.**
- `agent-runner-query-options.ts:142` — `env: buildAgentEnv(args.credential, args.serviceTokens)`. Confirmed; `permissionMode: args.permissionMode ?? "default"` at `:131`. **Holds.**
- `safe-bash.ts` — `SHELL_METACHAR_DENYLIST`, `PATH_TRAVERSAL_DENYLIST`, `SAFE_BASH_PATTERNS`, `isBashCommandSafe` confirmed verbatim at the cited shapes. **Holds.**
- `permission-callback.ts` Bash branch — `isBashCommandBlocked` runs first, then `isBashCommandSafe`, then near-miss telemetry, then `bashApprovalCache?.allow`, then the review-gate. `CanUseToolDeps.bashApprovalCache` is the threading precedent. **Holds.**
- `resolve-installation-id.ts` `resolveInstallationId(userId, workspaceId?)` already exists (ADR-044) and resolves the **active workspace's** installation id via the membership-checked `resolve_workspace_installation_id` SECURITY DEFINER RPC. **This is the per-workspace resolver Issue A needs — premise's "resolve the workspace's installation id" is already implemented; only the mint+inject wiring is missing.**
- Sentry `512e253141294ac1a808b2ef03a21289` (cron-follow-through-monitor) referenced in cron comments as the cron-side root cause; the interactive path shares it. (Not independently re-queried — no Sentry MCP loaded in this pipeline; the in-repo cron comments are the corroborating evidence.)

## Research Reconciliation — Spec vs. Codebase

| Premise claim | Codebase reality | Plan response |
| --- | --- | --- |
| "Mirror `mintInstallationToken()` from the crons." | `mintInstallationToken()` is hardcoded to `jikig-ai/soleur` (the monorepo). The Concierge serves arbitrary user workspaces whose installation id lives in `workspaces.github_installation_id`. | Do NOT reuse `mintInstallationToken()`. Use the existing `resolveInstallationId(args.userId)` (ADR-044, membership-checked) then `generateInstallationToken(installationId, { minRemainingMs })`. `generateInstallationToken` is already token-cache-memoized per installation id, so the crons' "memoization" requirement is satisfied by the existing cache, not a per-run closure. |
| "`ALLOWED_SERVICE_ENV_VARS` already includes the GitHub token var; confirm `GH_TOKEN` passes through `buildAgentEnv()`." | The provider var is `GITHUB_TOKEN`, not `GH_TOKEN`. `GH_TOKEN` is in NO allowlist. The crons inject `GH_TOKEN` by building their OWN spawn env, bypassing `buildAgentEnv`. `gh` CLI precedence: `GH_TOKEN` over `GITHUB_TOKEN`. | Add `GH_TOKEN` injection via a dedicated typed parameter on `buildAgentEnv` (`opts?: { ghToken?: string }`) that injects `GH_TOKEN` when present — NOT via the `serviceTokens` map (that path is keyed to `PROVIDER_CONFIG` and would land as `GITHUB_TOKEN`, the lower-precedence var, and would also be clobberable by a user's BYOK GitHub PAT row). Keep `GH_TOKEN` out of the service-token loop; never logged. |
| cc-router agent has platform MCP tools for agent-native parity. | `cc-dispatcher` wires `platformToolNames: []` and `mcpServers: readCcMcpAllowlist()` — the Concierge router currently exposes NO platform MCP tools. The legacy `agent-runner.ts` assembles `platformTools`. | Agent-native parity for the trusted toggle is provided via a **platform MCP tool pair** registered on the legacy `agent-runner.ts` platform-tools assembly (where domain-leader agents run with tools), NOT the cc-router (which is tool-restricted by design). The toggle read/write also has an HTTP route the UI uses; the MCP tools call the same server helper. Document this asymmetry so review does not flag the cc-router as missing the tool. |

## User-Brand Impact

**If this lands broken, the user experiences:**
- Issue A broken: the Concierge agent's `gh issue view`/`gh pr list`/push flows fail with `gh auth login` prompts mid-conversation — the agent stalls on an interactive auth wall it can never satisfy in the headless container (the exact reported symptom).
- Issue B part 1 broken (too-wide): a write `gh` verb or a redirect-to-file slips through auto-approve and runs without the user seeing it.
- Issue B part 2 broken (toggle leaks on): a workspace silently runs in autonomous mode the owner never enabled.

**If this leaks, the user's data / workflow / money is exposed via:** a prompt-injected agent (malicious issue body, poisoned repo file) under the autonomous toggle running destructive (`rm -rf`, force-push) or exfil commands with no approval gate. The BLOCKED list catches `curl`/`wget`/`nc`/`base64 -d`/`/dev/tcp`/`sudo`, but a creative non-blocked exfil (e.g. writing secrets into a committed file then pushing) is reachable. The minted `GH_TOKEN` is a live short-lived write-capable installation token in the agent env; if the widened auto-approve or the toggle let an injected command run `git push`, the blast radius is the connected repo.

**Brand-survival threshold:** single-user incident — the autonomous toggle is, by design, an approval-bypass on a code-executing surface. One compromised workspace under prompt injection is a brand-survival event. `requires_cpo_signoff: true` set; CPO sign-off required at plan time before `/work`. `user-impact-reviewer` will be invoked at review-time.

## Acceptance Criteria

### Pre-merge (PR)

**Issue A — gh installation token**

- AC1: `realSdkQueryFactory` resolves `resolveInstallationId(args.userId)` and, when non-null, mints `generateInstallationToken(installationId, { minRemainingMs: <floor >= runner wall-clock budget> })` and injects it as `GH_TOKEN` into the agent env. When null (no connected repo / non-member), no `GH_TOKEN` is injected and dispatch proceeds (graceful degradation — `gh` simply remains unauthenticated, same as today). Verified by `cc-dispatcher` unit test asserting `buildAgentEnv` received the `ghToken` and the resulting env has `GH_TOKEN` set, plus a null-installation test asserting `GH_TOKEN` absent.
- AC2: The minted token is NEVER logged. Grep gate: `git grep -nE 'log.*(ghToken|installationToken|GH_TOKEN)' apps/web-platform/server/cc-dispatcher.ts` returns zero log-of-value matches (a structured field naming the *presence* boolean is acceptable; the value is not).
- AC3: `buildAgentEnv(credential, serviceTokens, { ghToken })` injects `GH_TOKEN` (the `gh`-preferred var) and does NOT route it through the `serviceTokens` loop. Unit test: with `ghToken` set, `env.GH_TOKEN === ghToken`; with a `serviceTokens.GITHUB_TOKEN` BYOK row ALSO present, both coexist and `GH_TOKEN` is the minted one (precedence preserved). The mutually-exclusive auth-var switch (`ANTHROPIC_API_KEY` XOR `CLAUDE_CODE_OAUTH_TOKEN`) is untouched.
- AC4: On mint failure (`generateInstallationToken` throws / `resolveInstallationId` returns null due to RPC error), the failure is mirrored to Sentry via `reportSilentFallback` (`cq-silent-fallback-must-mirror-to-sentry`) under `{ feature: "cc-dispatcher", op: "mint-gh-token" }` and dispatch continues without `GH_TOKEN` (non-fatal — never block a conversation on a gh-auth mint). `resolveInstallationId` already mirrors its own RPC errors; the dispatcher mirrors the mint throw.
- AC5: Mint latency does not serialize behind the existing `Promise.all`. The mint depends only on `args.userId` (via `resolveInstallationId`), so it joins the existing `Promise.all([fetchUserWorkspacePath, getUserServiceTokens])` (extended to a 3-tuple) rather than adding a sequential await. (`generateInstallationToken` is on the interactive hot path — confirmed by the existing Sharp Edge re #122537945; the existing token cache + 401-retry budget already covers this.)

**Issue B part 1 — widened safe-bash (read-only)**

- AC6: New read-only `gh` verbs auto-approve: `gh issue view <n>`, `gh issue list [flags]`, `gh pr view <n>`, `gh pr list [flags]`, `gh issue status`, `gh pr status`, `gh pr diff <n>`, `gh pr checks <n>`, `gh repo view`. Each shipped with a positive unit test. NO write verbs.
- AC7: Regression tests prove ALL of these still gate or block: `gh issue edit`, `gh issue comment`, `gh issue close`, `gh pr merge`, `gh pr create`, `gh pr review`, `gh pr comment`, `gh repo delete`, `gh api -X POST …`, `gh secret set`. (Auto-approve returns false then falls through to review-gate; none auto-approve.)
- AC8: `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh <safe-subcommand>` auto-approves ONLY for an explicit subcommand allowlist (derived in Phase 0 from reading the script; `cleanup-merged` is NOT read-only — exclude it). Regression: `bash <other-path>`, `bash -c …`, `bash ./plugins/.../worktree-manager.sh <non-allowlisted-subcommand>`, and bare `bash` all do NOT auto-approve. The path is matched as an exact literal prefix (no `..`, enforced by the existing `PATH_TRAVERSAL_DENYLIST`).
- AC9: `&&`-joined chains auto-approve **iff every segment independently passes `isBashCommandSafe`**. Decompose on `&&` only (not `;`/`|`/`||` — those stay in the metachar denylist and block the whole command). Positive: `pwd && git status`, `cd sub && ls`. Negative: `git status && curl evil` (segment 2 blocked), `ls && rm x` (segment 2 unsafe), `pwd && pwd && echo ok` (all safe then approve), `git status & curl x` (single `&` is a metachar then whole command rejected, never reaches decomposition).
- AC10: Trailing `2>/dev/null` (and `2>&1`) on an otherwise-safe read command auto-approves, but redirects to a FILE path do not. Positive: `git status 2>/dev/null`, `ls -la 2>&1`. Negative: `cat secret > /tmp/x` (write redirect), `echo x >> ~/.bashrc`, `git log > out.txt`. Implemented by allowing ONLY the specific `2>/dev/null` / `2>&1` trailing tokens as a recognized suffix, NOT by removing `>`/`<` from `SHELL_METACHAR_DENYLIST`.
- AC11: `isBashCommandBlocked` remains authoritative and runs FIRST (unchanged ordering in `permission-callback.ts`). The decomposition + widened patterns live in `safe-bash.ts`; a blocked segment anywhere in a chain blocks the whole command BEFORE safe-bash decomposition is consulted (blocklist is applied to the raw full command in `permission-callback.ts` before `isBashCommandSafe`).
- AC12: `PATH_TRAVERSAL_DENYLIST` and the `SHELL_METACHAR_DENYLIST` security reasoning are preserved (extended, not gutted). Regression test: `cat ../../../etc/passwd`, `cd ..`, and `cat $(secret)` still rejected. The denylist comments are updated, not deleted, to document the new `&&`-decomposition and `2>/dev/null` carve-outs.
- AC13: The full new security surface has unit tests for every newly-allowed shape (AC6/AC8/AC9/AC10 positives) AND regression tests for every still-gated/blocked shape (AC7/AC8/AC9/AC10 negatives + AC12). Tests live in `apps/web-platform/test/permission-callback-safe-bash.test.ts` (extend) and/or a new `apps/web-platform/test/safe-bash.test.ts` (node project, `test/**/*.test.ts` glob — confirmed runner is vitest, NOT `bun test`).

**Issue B part 2 — autonomous toggle (opt-in bypass)**

- AC14: New `workspaces.bash_autonomous boolean NOT NULL DEFAULT false` column (migration appended at the next free number — directory-walk `ls supabase/migrations/` at write time; highest currently `096`). Off by default. Restrictive RLS so the toggle (an authz decision per constitution "add a restrictive policy for any column that stores values used for auth/authz decisions") is NOT writable via the permissive workspace UPDATE policy — write goes through a membership-checked (owner-only) SECURITY DEFINER RPC mirroring `resolve_workspace_installation_id` (`SET search_path = public, pg_temp`; `REVOKE` then `GRANT EXECUTE TO authenticated`; `is_workspace_member` + owner check). A `down.sql` is included.
- AC15: Server helpers `resolveBashAutonomous(userId, workspaceId?)` (read, mirrors `resolveInstallationId`) and `setBashAutonomous(userId, value)` (write via owner-only RPC). Both mirror errors via `reportSilentFallback`. Read defaults to `false` on any error/null (fail-closed — a settings-read failure must NOT silently enable bypass). Unit tests for both, including the fail-closed-on-error path.
- AC16: `permission-callback.ts` Bash branch: when the workspace is autonomous, auto-approve all commands where `isBashCommandBlocked === false` (blocklist stays authoritative; the toggle bypasses ONLY the review-gate, never the blocklist). Wired through a new `CanUseToolDeps.bashAutonomous?: boolean` (threaded from `cc-dispatcher` analogous to `bashApprovalCache`). The check is placed AFTER `isBashCommandBlocked` and AFTER `isBashCommandSafe` (so safe-bash telemetry still fires) but BEFORE the near-miss/cache/review-gate. Unit tests: autonomous + non-blocked then allow; autonomous + blocked (`sudo rm`) then still deny; non-autonomous then unchanged review-gate behavior.
- AC17: UI — a toggle in `components/settings/` with an explicit, unavoidable risk notice (interstitial confirm) stating that an agent under prompt injection could run destructive/exfil commands without approval, shown BEFORE the toggle can be switched on. Off by default. Wired to a settings HTTP route (`app/(dashboard)/dashboard/settings` then API route) that calls `setBashAutonomous`. Component test in `apps/web-platform/test/components/settings/<name>.test.tsx` (jsdom/happy-dom project, `test/**/*.test.tsx` glob — NOT co-located).
- AC18: Agent-native parity — a platform MCP tool pair (`workspace_get_autonomous`, `workspace_set_autonomous`) registered in `agent-runner.ts`'s platform-tools assembly (the surface where tool-capable domain-leader agents run). `workspace_set_autonomous` carries the same risk text in its tool description and is gated (Tier `gated` in `tool-tiers.ts` — a write that flips an approval-bypass MUST require a review-gate even for the agent). The cc-router (`cc-dispatcher`) does NOT get the tool (it wires `platformToolNames: []` by design); this asymmetry is documented in the tool's doc comment. Read tool (`workspace_get_autonomous`) is auto-approve tier.
- AC19: `requires_cpo_signoff: true` — CPO sign-off recorded before `/work` begins (Domain Review section).

### Post-merge (operator)

- AC20: Migration applied to DEV first, then PRD, via Supabase MCP (`mcp__plugin_supabase_supabase__*`) — read-only verify the column exists + RLS policy shape (`pg_policy`) + RPC grants. `Ref #<issue>` (not `Closes`) in PR body if the column apply is post-merge; otherwise `Closes`. Automation: feasible via Supabase MCP — bake into `/work` migration phase + `/soleur:ship` verify, not an operator dashboard step.

## Implementation Phases

Ordered by dependency direction. Each phase is its own commit.

### Phase 0 — Preconditions (verify at /work time, no commit)

- P0.1: Read `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` and enumerate which subcommands are strictly read-only (no `git worktree add/remove`, no `rm`, no file writes). The AC8 allowlist is derived from THIS read, not from memory. If only `list` is read-only, scope AC8 to `list` alone.
- P0.2: `command -v gh` and `gh issue list --help` / `gh pr list --help` to confirm the read-only subcommand token shapes the new regexes must match (CLI-verification gate). Pin the verified date in the test file comment.
- P0.3: `ls supabase/migrations/ | sort | tail -3` to pick the next free migration number; read the 2 most recent for the in-transaction DDL constraint (no `CREATE INDEX CONCURRENTLY`).
- P0.4: Read `tool-tiers.ts` `TOOL_TIER_MAP` scope to confirm `workspace_set_autonomous` lands in the `mcp__soleur_platform__*` family the map governs (per Sharp Edge re map scope).
- P0.5: Confirm `generateInstallationToken`'s `minRemainingMs` floor to use — match the cron's `TOKEN_MIN_LIFETIME_MS`-style floor so a warm-cache token outlives the conversation's expected duration.

### Phase 1 — Commit 1: Issue A (gh installation token) — write failing tests first

1. RED: `agent-env.test.ts` — assert `buildAgentEnv(cred, tokens, { ghToken })` sets `env.GH_TOKEN` and coexists with a `GITHUB_TOKEN` service token (AC3). `cc-dispatcher`-level test asserting mint+inject + null-install skip + mirror-on-failure (AC1/AC4).
2. GREEN: widen `buildAgentEnv` signature with a third `opts?: { ghToken?: string }` arg; inject `GH_TOKEN` outside the service-token loop, independent of the auth-var switch. In `realSdkQueryFactory`, extend the existing `Promise.all` to a 3-tuple resolving `resolveInstallationId(args.userId)`; if non-null, `await generateInstallationToken(id, { minRemainingMs })` inside a try/catch that `reportSilentFallback`s and falls through to `undefined` on throw; pass `{ ghToken }` into `buildAgentQueryOptions` then `buildAgentEnv`. Add `ghToken?: string` to `AgentQueryOptionsArgs`, thread to `buildAgentEnv`. Update `agent-runner-query-options.test.ts` drift snapshot ONLY if the shared-field set changes (it should NOT — `ghToken` is per-call divergent, not shared).
3. Comment cites `hr-github-app-auth-not-pat` and the Sentry id; NEVER log the value.

### Phase 2 — Commit 2: Issue B part 1 (widened safe-bash)

1. RED: extend `safe-bash.ts` tests with all AC6/AC8/AC9/AC10 positives and AC7/AC8/AC9/AC10/AC12 negatives.
2. GREEN, in `safe-bash.ts`:
   - Add read-only `gh` patterns to `SAFE_BASH_PATTERNS` (`gh\s+(issue|pr)\s+(view|list|status|diff|checks)…`, `gh\s+repo\s+view`), arg shapes using `PATH_TOKEN`/digit/flag tokens — no metachars (denylist still applies to the raw command).
   - Add the `bash <exact-worktree-manager-path> <allowlisted-subcommand>` pattern (literal path prefix, subcommand from P0.1).
   - Add `&&`-decomposition in `isBashCommandSafe`: IF the trimmed command contains `&&` (and no other metachar after carving out the allowed trailing redirect), split on `&&`, trim each segment, and return true iff EVERY segment matches a `SAFE_BASH_PATTERNS` entry. Relax the `SHELL_METACHAR_DENYLIST` for `&` ONLY when it appears exactly as the `&&` operator between safe segments — implement by stripping a recognized trailing `2>/dev/null`/`2>&1` first, then checking `&&`-only composition, NOT by removing `&`/`>`/`<` from the denylist (keep the denylist intact for the raw single-command path and re-apply per-segment).
   - Add the trailing-redirect carve-out: recognize a single trailing `2>/dev/null` or `2>&1` suffix, strip it, then evaluate the remainder. File-path redirects (`>`, `>>`, `<`) remain denied.
   - Update (do not delete) the `SHELL_METACHAR_DENYLIST` / `PATH_TRAVERSAL_DENYLIST` doc comments to document the two new carve-outs and their security reasoning.
3. `permission-callback.ts` Bash-branch ordering unchanged (`isBashCommandBlocked` first). Confirm the blocklist is applied to the full raw command before any decomposition (it already is).

### Phase 3 — Commit 3: Issue B part 2 schema + server helpers (contract before consumer)

1. Migration `<NNN>_workspace_bash_autonomous.sql` + `.down.sql`: `ADD COLUMN bash_autonomous boolean NOT NULL DEFAULT false`; restrictive RLS (no permissive UPDATE on this column); two SECURITY DEFINER RPCs — `get_workspace_bash_autonomous(p_workspace_id uuid) RETURNS boolean` (member-checked) and `set_workspace_bash_autonomous(p_workspace_id uuid, p_value boolean)` (owner-checked via `is_workspace_member` + owner role). Both `SET search_path = public, pg_temp`; `REVOKE ALL … FROM PUBLIC, anon, authenticated, service_role` then `GRANT EXECUTE … TO authenticated`. COMMENT documenting the authz semantics. R8 composite-key invariant: the write RPC scopes by `(p_workspace_id, auth.uid())` membership — no cross-workspace write.
2. RED then GREEN: `resolve-bash-autonomous.ts` (read, mirrors `resolve-installation-id.ts` structure incl. `resolveCurrentWorkspaceId` fallback) returning `false` fail-closed on error/null; `set-bash-autonomous.ts` (write). Both `reportSilentFallback` on error.

### Phase 4 — Commit 4: Issue B part 2 permission-callback wiring (consumer)

1. RED: `permission-callback-safe-bash.test.ts` (or new `permission-callback-autonomous.test.ts`) — autonomous+non-blocked then allow, autonomous+blocked then deny, non-autonomous then unchanged (AC16).
2. GREEN: add `bashAutonomous?: boolean` to `CanUseToolDeps`; in the Bash branch, after `isBashCommandBlocked` (deny) and after the `isBashCommandSafe` allow + near-miss telemetry, insert: `if (deps.bashAutonomous) { log + logPermissionDecision("autonomous-bypass"); return allow(toolInput); }` BEFORE the batched-cache/review-gate. Thread `bashAutonomous: await resolveBashAutonomous(args.userId)` into `ccDeps` in `cc-dispatcher` (join the existing `Promise.all` or resolve alongside the mint — both key off `args.userId`).

### Phase 5 — Commit 5: Issue B part 2 UI toggle + risk interstitial

1. Pencil wireframe (BLOCKING — see Domain Review + Deepen Gate 4.9). Produce `knowledge-base/product/design/product/concierge-autonomous-toggle.pen` (run `pencil-setup --auto` first if Pencil self-stops) before coding the component. Must show the OFF then ON confirm interstitial, not just the toggle. Commit the `.pen` and reference it in the AC17 FRs.
2. Settings component + interstitial confirm + API route calling `setBashAutonomous`; component test at `test/components/settings/<name>.test.tsx` (jsdom project glob). Risk copy reviewed (copywriter if CMO/CPO flags).

### Phase 6 — Commit 6: Issue B part 2 agent-native MCP tool pair

1. `workspace_get_autonomous` (auto-approve tier) + `workspace_set_autonomous` (gated tier, risk text in description) in a new `server/workspace-settings-tools.ts`, registered in `agent-runner.ts` platform-tools assembly; `tool-tiers.ts` `TOOL_TIER_MAP` entry for the setter (gated). Tests for both tool handlers. Doc comment notes the cc-router asymmetry.

## Test Scenarios (Given/When/Then)

- Given a workspace connected via the Soleur GitHub App (installation id present, no BYOK GitHub PAT), When the Concierge dispatches an agent turn, Then the agent env contains `GH_TOKEN` = a freshly-minted short-lived installation token and `gh issue list` succeeds without `gh auth login`.
- Given no connected repo, When dispatch runs, Then no `GH_TOKEN` is injected and dispatch completes (no throw).
- Given the safe-bash widening, When the agent emits `gh pr list && git status`, Then it auto-approves (both segments safe); When it emits `gh pr list && gh pr merge 5`, Then it falls to the review-gate (segment 2 not read-only).
- Given `bash_autonomous = false` (default), When the agent emits `ls`, Then it auto-approves via safe-bash; When it emits `git push`, Then the review-gate fires.
- Given an owner enables the autonomous toggle (through the risk interstitial), When the agent emits `git push`, Then it auto-approves; When it emits `sudo rm -rf /`, Then the blocklist still denies it.
- Given a settings-read RPC error, When `resolveBashAutonomous` runs, Then it returns `false` (fail-closed) and mirrors to Sentry.

## Domain Review

**Domains relevant:** engineering, product, legal (data-exposure surface), operations (migration apply).

### Engineering

**Status:** reviewed (inline — no Task subagent available in this pipeline context)
**Assessment:** Security-surface change on two axes (live write-capable token in agent env; approval-bypass toggle). Mitigations: blocklist stays authoritative under the toggle; safe-bash widening is read-only + per-segment-verified; `&&`-decomposition and redirect carve-outs are additive to (not replacements of) the denylists; token never logged; fail-closed settings read.

**Precedent-diff (deepen-plan Phase 4.4 — verified against live repo, no novel patterns):**

| New construct | Precedent | Verified |
| --- | --- | --- |
| `get/set_workspace_bash_autonomous` SECURITY DEFINER RPC, `SET search_path = public, pg_temp`, REVOKE-then-GRANT | `resolve_workspace_installation_id` (migration 079:103-134) | yes — copy the structure verbatim |
| Membership gate in the read RPC | `is_workspace_member(p_workspace_id, auth.uid())` (053:116) | yes — function exists, REVOKE'd from PUBLIC |
| Owner-only gate in the write RPC | `workspace_members.role = 'owner'` predicate (092:104, 091:159) | yes — owner-role check is an established shape |
| `resolveBashAutonomous` server helper (active-workspace resolve + fallback) | `resolveInstallationId` / `resolveCurrentWorkspaceId` (`resolve-installation-id.ts`, `workspace-resolver.ts:190`) | yes — mirror structurally |
| `GH_TOKEN` env injection | cron `buildSpawnEnv(installationToken)` (`cron-daily-triage.ts`) | yes — but inject via `buildAgentEnv` opts param, NOT a parallel spawn-env (see Reconciliation row 2) |
| `bashAutonomous` deps threading | `bashApprovalCache` in `CanUseToolDeps` (`permission-callback.ts:154`) | yes — same injection seam |

No novel patterns. The `&&`-decomposition in `safe-bash.ts` is the only construct with no exact in-repo sibling (the file's single-command allowlist is the closest); scrutinize its per-segment re-application of the denylists at review.

### Product/UX Gate

**Tier:** blocking — new interactive surface (settings toggle + risk interstitial/confirmation flow with persuasive/cautionary copy).
**Decision:** auto-accepted (pipeline) — pipeline/subagent context; ux-design-lead wireframe is a non-skippable producer (Phase 5).
**Agents invoked:** none yet (pipeline; ux-design-lead + spec-flow-analyzer + cpo to run at deepen-plan / work Phase 2.5 per the gate).
**Skipped specialists:** none — `ux-design-lead` MUST produce a committed `.pen` in Phase 5 (`wg-ui-feature-requires-pen-wireframe`); hard-block if Pencil unprovisionable.
**Pencil available:** TBD at deepen-plan (run `pencil-setup --auto` if the tool self-stops).

#### Findings

The toggle is a destructive-capability gate; the interstitial copy is brand-survival-load-bearing (it is the user's informed-consent surface). Wireframe must show the OFF then ON confirm interstitial explicitly, not just the toggle.

### Legal

**Status:** reviewed (inline)
**Assessment:** No new processor/vendor; no new personal-data category. The autonomous toggle expands the agent's unattended action capability over the user's own connected repo — within existing AUP/processing scope. GDPR gate (Phase 2.7) skipped: no schema touching personal data beyond a boolean preference column, no new external processing. If deepen-plan's gdpr-gate disagrees at single-user threshold, fold in its findings.

## Infrastructure (IaC)

Skip — no new infrastructure (server, secret, vendor, persistent process). The migration applies through the existing `web-platform-release.yml#migrate` path; the GitHub App + installation tokens are pre-existing infra.

## Observability

```yaml
liveness_signal:
  what: "auto-approved-safe-bash / autonomous-bypass / mint-gh-token decisions land in permission-log + structured pino logs (sec:true)"
  cadence: per-Bash-tool-call and per-dispatch
  alert_target: "Sentry (existing reportSilentFallback/warnSilentFallback sinks)"
  configured_in: "apps/web-platform/server/permission-callback.ts, cc-dispatcher.ts, resolve-bash-autonomous.ts"
error_reporting:
  destination: "Sentry via reportSilentFallback (mint failure, RPC error) + warnSilentFallback (existing near-miss)"
  fail_loud: "mint failure mirrored under {feature: cc-dispatcher, op: mint-gh-token}; settings-read failure under {feature: resolve-bash-autonomous, op: rpc-read}; both non-fatal but logged"
failure_modes:
  - mode: "installation-token mint throws"
    detection: "Sentry op:mint-gh-token"
    alert_route: "existing Sentry project"
  - mode: "settings-read RPC error then fail-closed false"
    detection: "Sentry op:rpc-read (resolve-bash-autonomous)"
    alert_route: "existing Sentry project"
  - mode: "safe-bash widening over-approves a write verb"
    detection: "permission-log decision=auto-approved-safe-bash on an unexpected verb; regression tests are the primary gate"
    alert_route: "pre-merge test suite"
logs:
  where: "pino structured logs (sec:true fields) + permission-log; Sentry for fallbacks"
  retention: "existing platform retention"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/permission-callback-safe-bash.test.ts test/safe-bash.test.ts"
  expected_output: "all safe-bash positive/negative + autonomous-bypass assertions pass (NO ssh)"
```

## Open Code-Review Overlap

None checked via `gh issue list --label code-review` (no GitHub query run in this pipeline context — deepen-plan should run the overlap check against the finalized Files-to-Edit list).

## Files to Edit

- `apps/web-platform/server/cc-dispatcher.ts` — mint + inject `GH_TOKEN`; thread `bashAutonomous` into `ccDeps`.
- `apps/web-platform/server/agent-env.ts` — `buildAgentEnv` third `opts?: { ghToken?: string }` param; inject `GH_TOKEN`.
- `apps/web-platform/server/agent-runner-query-options.ts` — `ghToken?: string` arg, thread to `buildAgentEnv`.
- `apps/web-platform/server/safe-bash.ts` — read-only `gh` verbs, worktree-manager allowlist, `&&`-decomposition, trailing-redirect carve-out; updated denylist comments.
- `apps/web-platform/server/permission-callback.ts` — `CanUseToolDeps.bashAutonomous`; autonomous-bypass branch after blocklist+safe-bash.
- `apps/web-platform/server/agent-runner.ts` — register `workspace_*_autonomous` platform tools.
- `apps/web-platform/server/tool-tiers.ts` — `workspace_set_autonomous` then gated.
- `apps/web-platform/components/settings/` — new toggle component + interstitial; `settings-content.tsx` add section.
- `apps/web-platform/app/(dashboard)/dashboard/settings/` — API route for set/get.
- Test files: `test/agent-env.test.ts` (or existing buildAgentEnv test), `test/permission-callback-safe-bash.test.ts`, new `test/safe-bash.test.ts`, new `test/permission-callback-autonomous.test.ts`, `test/resolve-bash-autonomous.test.ts`, `test/set-bash-autonomous.test.ts`, `test/components/settings/<toggle>.test.tsx`, `test/workspace-settings-tools.test.ts`; `agent-runner-query-options.test.ts` (only if shared snapshot changes).

## Files to Create

- `apps/web-platform/supabase/migrations/<NNN>_workspace_bash_autonomous.sql` + `.down.sql`
- `apps/web-platform/server/resolve-bash-autonomous.ts`
- `apps/web-platform/server/set-bash-autonomous.ts`
- `apps/web-platform/server/workspace-settings-tools.ts`
- `knowledge-base/product/design/product/concierge-autonomous-toggle.pen` (Phase 5)

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- Do NOT reuse `mintInstallationToken()` from `_cron-shared.ts` — it is hardcoded to `jikig-ai/soleur`. Use `resolveInstallationId(userId)` + `generateInstallationToken`.
- `GH_TOKEN` is NOT `GITHUB_TOKEN`. `gh` prefers `GH_TOKEN`. Inject as `GH_TOKEN` via the new `buildAgentEnv` param, NOT the `serviceTokens` map (which keys to `GITHUB_TOKEN` and is BYOK-clobberable).
- The cc-router exposes NO platform MCP tools (`platformToolNames: []`). Agent-native parity for the toggle lives on the legacy `agent-runner.ts` tool surface + the HTTP route, NOT the cc-router. Document so review does not flag a false "missing tool" gap.
- `&&`-decomposition must NOT be implemented by removing `&`/`>`/`<` from `SHELL_METACHAR_DENYLIST`. Strip the recognized trailing redirect, split on `&&`, re-apply per-segment safe checks. `;`/`|`/`||`/`$`/backtick stay fully denied.
- Settings read MUST fail-closed (`false`) — a read error enabling bypass is the inverse of the intended safety posture.
- Test runner is vitest (`bun test` is blocked by `bunfig.toml pathIgnorePatterns=["**"]`). Component tests go in `test/**/*.test.tsx` (happy-dom project), NOT co-located, or vitest skips them.
- The autonomous toggle does NOT bypass `isBashCommandBlocked` — the blocklist (`curl|wget|nc|sh -c|eval|base64 -d|/dev/tcp|sudo`) stays authoritative even under autonomy.
