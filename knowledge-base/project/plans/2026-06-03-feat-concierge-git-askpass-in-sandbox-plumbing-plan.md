<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
---
title: "Concierge in-sandbox git GIT_ASKPASS credentialing + gh-auth-status prompt + userId-log hygiene"
type: feat
date: 2026-06-03
branch: feat-one-shot-concierge-git-askpass-plumbing
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Feat: Concierge in-sandbox git GIT_ASKPASS plumbing (per-user / per-repo)

> Spec lacks valid `lane:` (no spec.md for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-06-03
**Gates passed:** 4.6 User-Brand Impact (present, threshold `single-user incident`),
4.7 Observability (all 5 fields present, no SSH in discoverability_test), 4.8 PAT-shaped
var halt (none — the token is the already-minted App installation token, never a
`var.*_token`/PAT literal), 4.9 UI-wireframe (all Files-to-Edit/Create are
`server/` + `test/` — no UI surface → skip, `wg-ui-feature-requires-pen-wireframe`
does not fire). PR #4868 + #4890 live-verified MERGED; issue #3698 live-verified
CLOSED (the `userid-bypass-lint` guard JOB lives on regardless).

### Key Improvements (over the as-planned draft)

1. **Verify-the-negative confirmed (Phase 4.45).** The three negative security
   claims hold against current code: (a) `buildAgentEnv` injects `GH_TOKEN` only as
   a dedicated key (`agent-env.ts:127`) — the new `GIT_INSTALLATION_TOKEN` is a
   second dedicated key, so "token in no OTHER env key" is structurally true;
   (b) `ASKPASS_SCRIPT_BODY` reads the token from `${GIT_INSTALLATION_TOKEN}` via
   `printf` (`git-auth.ts:34-37`) — NEVER interpolated into the file, so "token not
   in script body" is guaranteed by reuse, not asserted; (c) `cc-dispatcher.ts` has
   ZERO `ghToken`-value log/console/Sentry-extra sites — "never logged" holds.
2. **Precedent-diff confirmed (Phase 4.4).** The askpass env block has a canonical
   sibling: `git-auth.ts gitWithInstallationAuth` (`:230-242`) sets exactly the same
   six `GIT_*` vars (`GIT_ASKPASS`, `GIT_INSTALLATION_TOKEN`, `GIT_USERNAME=x-access-token`,
   `GIT_TERMINAL_PROMPT=0`, `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`)
   plus `HELPER_RESET`. Item 1's `buildAgentEnv` block MUST mirror this set verbatim
   — no novel credential path. The script body is single-sourced via
   `writeAskpassScriptTo` delegation (drift-free).
3. **Scheduled-work check (Phase 4.4):** this plan introduces NO scheduled job
   (the askpass write + ensure-repo run inline on cold dispatch) — Inngest/ADR-033
   precedent is N/A. Recorded so /work does not add a cron.
4. **Sandbox-path containment verified (load-bearing Phase 0.2).** Confirmed at
   `sandbox.ts:146` (`realPath.startsWith(resolvedWorkspace + "/")`) +
   `sandbox-hook.ts:24` (`isPathInWorkspace`): a file written UNDER `workspacePath`
   is sandbox-readable/executable; `denyRead:["/workspaces"]` denies only sibling
   tenants. This is why the askpass script lives under `workspacePath`, not `$HOME`.

### New Considerations Discovered

- **SDK managed-domain source verification is deferred to /work.** The
  `@anthropic-ai/claude-agent-sdk` type defs are not installed in this worktree's
  `node_modules` (workspace-hoisted). The prior plan cited `sdk.d.ts:3597-3599` for
  the `allowManagedDomainsOnly` semantics. The Outcome-A determination does NOT
  depend on re-reading the SDK — it is settled by the **empirical prod signal**
  (the in-sandbox `gh auth status` 401-from-`/user` verdict), which is the
  authoritative probe per `hr-verify-repo-capability-claim-before-assert` and the
  learning `2026-06-03-self-heal-on-brand-path-only-acts-on-safe-symptom`. /work
  may re-confirm against the installed SDK but is not blocked on it.
- **The `.git/config` token-absence test (1e) is best done at unit level over
  synthesized fixtures** (`cq-test-fixtures-synthesized-only`) — no live github.com
  in the test path. The invariant is structurally guaranteed (clean positional URL
  arg + token via env in `ASKPASS_SCRIPT_BODY`); the test pins it against regression.

## Overview

Follow-up to MERGED predecessors **PR #4868** (per-workspace GitHub App
installation token minted + injected as `GH_TOKEN`) and **PR #4890** (session-start
ensure-repo self-heal that clones a connected repo into a workspace that has NO
`.git`). **Both are contextual citations, NOT work targets.** With those two
landed, the Concierge (cc-soleur-go / cc-dispatcher) now: (a) has a real clone of
the user's connected repo on cold dispatch (ensure-repo), and (b) has `GH_TOKEN`
in the agent env for `gh`. Three gaps remain so the agent can do git work
**end-to-end** in **every** Soleur user's **own** connected repo:

1. **(PRIMARY) In-sandbox raw `git` has no credentials.** `GH_TOKEN` authenticates
   the `gh` CLI but NOT raw `git push`/`fetch`/`pull`. The Phase 0.1 sandbox-network
   spike is **ALREADY RESOLVED — Outcome A**: the agent sandbox CAN reach
   `github.com` (prod evidence: in-sandbox `gh auth status` returned a 401-from-
   `/user` "token invalid" *verdict*, which requires reaching `api.github.com`; a
   blocked network gives a connection error, not an auth verdict; `github.com` is
   in the SDK managed dev-domain allow-set, no `managed-settings.json` ships). So
   in-sandbox `GIT_ASKPASS` git is network-viable → wire it.
2. **Concierge self-blocks on `gh auth status`.** GitHub App **installation**
   tokens cannot call `GET /user`, which `gh auth status` probes, so it ALWAYS
   reports an installation token "invalid" — though the same token works for
   `gh issue view -R owner/repo`, `gh pr create`, and git-over-HTTPS. The agent
   trusts the false negative and refuses to proceed. Fix: system-prompt guidance.
3. **`userId`-log source-hygiene.** `ensure-workspace-repo.ts` (from PR #4890)
   emits a direct `log.info({ userId, action: ... })` breadcrumb. The advisory
   CI guard "Block direct userId emissions in apps/web-platform (#3698)" (in
   `.github/workflows/pr-quality-guards.yml`) flags raw-`userId` direct-logger
   sites. Runtime is already safe (pino `formatters.log` hashes top-level
   `userId`); this is source-hygiene that clears the guard.

The fix MUST be generic per-user / per-repo — owner/repo + installation token
are always derived from the requesting user's **membership-checked active
workspace**; **never hardcode `jikig-ai/soleur`**. Honor
`hr-github-app-auth-not-pat`, `cq-silent-fallback-must-mirror-to-sentry`,
`cq-write-failing-tests-before`. **NEVER log the token.**

This plan does **research and design only** for /work. **No code is written
during planning.**

## Premise Validation (Phase 0.6)

| Cited reference | Probe | Result |
| --- | --- | --- |
| PR #4868 (GH_TOKEN mint predecessor) | `gh pr view 4868 --json state` | **MERGED** — `fix(chat): Concierge gh-auth (GH_TOKEN mint) + Bash permission posture`. Context, not a work target. |
| PR #4890 (ensure-repo self-heal predecessor) | `gh pr view 4890 --json state` | **MERGED** — `fix(chat): session-start ensure-repo self-heal for the Concierge workspace (per-user)`. Context, not a work target. |
| Issue #3698 (userId-emission guard) | `gh issue view 3698 --json state` | **CLOSED** — `feat(observability): migrate direct logger.error({userId}) pino sites to helpers OR add pino-level redaction`. The guard JOB lives on in `pr-quality-guards.yml#userid-bypass-lint`; the issue being closed does not remove the guard. |
| `apps/web-platform/server/agent-env.ts` `buildAgentEnv` + `BuildAgentEnvOptions{ghToken}` | `Read` | Exists (152 lines). `BuildAgentEnvOptions` already has `ghToken`; `buildAgentEnv(credential, serviceTokens, opts)`. |
| `apps/web-platform/server/git-auth.ts` askpass pattern | `Read` | Exists (259 lines). `ASKPASS_SCRIPT_BODY`, `HELPER_RESET`, `writeAskpassScript()` (writes to `$HOME`/`/tmp`), `cleanupAskpassScript()`, `gitWithInstallationAuth`. |
| `apps/web-platform/server/agent-runner-query-options.ts` `AgentQueryOptionsArgs` → `buildAgentQueryOptions` → `buildAgentEnv` | `Read` | Exists (203 lines). `AgentQueryOptionsArgs` already carries `ghToken` + `workspacePath`; calls `buildAgentEnv(credential, serviceTokens, { ghToken })` at :152. |
| `apps/web-platform/server/cc-dispatcher.ts` `realSdkQueryFactory` cold path | `Read` `:919-1180` | Exists. `Promise.all` (:970) resolves `[workspacePath, serviceTokens, installationId, bashAutonomous, repoUrl]`; `ensureWorkspaceRepoCloned` at :988; `ghToken` minted :1008-1022; `buildAgentQueryOptions({ workspacePath, ghToken, mcpServers: readCcMcpAllowlist() })` at :1170. |
| `apps/web-platform/server/agent-runner-sandbox-config.ts` `buildAgentSandboxConfig` | `Read` | Exists. `network.allowedDomains:[] + allowManagedDomainsOnly:true`; `filesystem.allowWrite:[workspacePath]` + `denyRead:["/workspaces","/proc"]`. |
| `apps/web-platform/server/sandbox-hook.ts` / `sandbox.ts` path validation | `Read` | `createSandboxHook(workspacePath)` PreToolUse hook validates every tool path via `isPathInWorkspace(filePath, workspacePath)` (realpath containment). Anything under `workspacePath` is permitted; `/workspaces` denyRead is the cross-tenant sibling guard. |
| `buildSoleurGoSystemPrompt` (item 2 target) | `grep` `soleur-go-runner.ts:1038` | Exists. `baseline` string array at :1041-1051 is the insertion point. Unit-tested by `soleur-go-runner-narration.test.ts` (`toContain` substring pattern). |
| `ensure-workspace-repo.ts` direct `log.info({userId})` site | `grep -nE 'log\.(info\|warn\|error\|debug)'` | **ONE site** at `:91` `log.info({ userId, action: "cloned" }, ...)`. See Research Reconciliation — the ARGUMENTS says "two breadcrumbs"; only one exists. |
| Cold-start test sweep | `grep -rln realSdkQueryFactory apps/web-platform/test/` | `cc-dispatcher-real-factory.test.ts`, `cc-dispatcher-prefill-guard.test.ts` (cold-path mocks); also `agent-runner-helpers.test.ts`, `agent-runner-query-options.test.ts` (drift-guards, single ref each). |

**Net premise note:** All cited file/symbol paths hold. The Phase 0.1 spike is
resolved to **Outcome A** by the ARGUMENTS (in-sandbox git is network-viable),
so item 1 commits to the GIT_ASKPASS-in-sandbox path with no B-branch carried.
**Two divergences from the ARGUMENTS** are captured in Research Reconciliation
below: (i) item 3 has ONE `log.info({userId})` site, not two; (ii) the askpass
**script-write location** must be under `workspacePath`, and the verification of
that constraint is the load-bearing Phase 0.2 finding.

## Research Reconciliation — ARGUMENTS vs. Codebase

| ARGUMENTS claim | Codebase reality | Plan response |
| --- | --- | --- |
| Item 3: "the **two** `log.info({ userId, action: ... })` breadcrumbs emit raw userId — drop `userId` from those payloads." | `grep -nE 'log\.(info\|warn\|error\|debug)\(' ensure-workspace-repo.ts` returns exactly **ONE** match: `:91 log.info({ userId, action: "cloned" }, …)`. The two `reportSilentFallback(…, { extra: { userId, hasInstallation: true } })` sites at `:80` and `:96` are NOT direct-logger sites — they route through the helper that `hashExtraUserId`-pseudonymizes `userId` → `userIdHash` (`observability.ts:204,260`), and the CI guard explicitly **allowlists** `reportSilentFallback`. | Item 3 edits the **single** `log.info` site at `:91`: drop `userId`, keep `action: "cloned"`. Do NOT touch the two `reportSilentFallback` sites (already compliant). RED test asserts the success-breadcrumb no longer carries a raw `userId` key. |
| Item 1 (Phase 0.2): the askpass script must be written UNDER `workspacePath` (the only verified `allowWrite` dir) and passed as `GIT_ASKPASS`. | Confirmed and refined: `buildAgentSandboxConfig` sets `allowWrite:[workspacePath]` AND `denyRead:["/workspaces","/proc"]`. The `denyRead:["/workspaces"]` is the **cross-tenant sibling guard** (deny reading *other* users' workspaces under `/workspaces/`), NOT a deny on the agent's own `workspacePath` — `createSandboxHook(workspacePath)` permits any path that `isPathInWorkspace(filePath, workspacePath)` (realpath containment, `sandbox.ts:146` `realPath.startsWith(resolvedWorkspace + "/")`). `git`/GIT_ASKPASS run as a bwrap Bash subprocess whose fs bind-mounts the workspace; `$HOME`/`/tmp` are NOT in `allowWrite` and their bwrap-visibility is unverifiable. | The existing `writeAskpassScript()` writes to `$HOME`/`/tmp` — correct for the **server-side** `gitWithInstallationAuth`, WRONG for in-sandbox use. Item 1 adds a `writeAskpassScriptTo(dir)` variant in `git-auth.ts`, invoked **server-side** from `cc-dispatcher.ts` with `dir = workspacePath`. The resulting absolute path is passed as `GIT_ASKPASS`. |
| Item 1: "reusing the already-minted `ghToken` + `installationId` resolved in the cold-start `Promise.all`." | `installationId` is resolved in the `Promise.all` (:974); `ghToken` is minted AFTER it (:1008-1022, conditional on `installationId !== null`). The askpass script needs the **token value** (the minted `ghToken`), not the installation id — the token rides `GIT_INSTALLATION_TOKEN` env. | Item 1 reuses the already-minted `ghToken` string. The askpass script is written only when `ghToken !== undefined` (a connected, membership-checked repo). When no token → no askpass env (graceful degradation parity with the existing `GH_TOKEN` no-op). |
| Optional: "wire the existing server-side `github_*` MCP tools into the cc path — `mcpServers: readCcMcpAllowlist()` returns `{}`." | `readCcMcpAllowlist()` is **Phase-1 deny-by-default by design**; it returns `{}` even for valid non-denylist names. Populated-server promotion is explicitly tracked by **#3722** (`CC_MCP_ALLOWLIST` Phase-2). Wiring it touches `tool-tiers.ts`, `permission-callback.ts`, the registered-tool catalog, and CPO write-tool sign-off — a self-contained effort. | **DEFER to #3722** (decided in plan, CPO-gated). Outcome A makes in-sandbox git the working path, so this is a robustness add, not required. Recorded as a Non-Goal + deferral note; no tracking issue created here (it already lives at #3722). |

**Implication:** This follow-up is small and well-bounded. The center of gravity
is item 1 (in-sandbox GIT_ASKPASS, Outcome A). Items 2 and 3 are a prompt-string
add and a one-line log-payload drop. The optional MCP-tool wiring is deferred to
its existing tracking issue #3722.

## User-Brand Impact

**If this lands broken, the user experiences:** the Concierge can `gh` but still
cannot `git push` / `git fetch` against *their own* connected repo from the
sandbox (the agent branches+commits locally, then the push silently fails or it
self-blocks on `gh auth status`) — so the headline promise ("an AI team that does
git work in your repo") fails at the push step.

**If this leaks, the user's GitHub installation token is exposed via:** (a) the
token written into a `.git/config` remote URL or echoed into a log / transcript /
Sentry payload; (b) an askpass **script** that interpolates the token into its
body (instead of reading it from env) — readable via `/proc` or a co-tenant; (c)
the askpass script written to a path a *different* user's sandbox could read
(cross-tenant) — mitigated because the script lives under the requesting user's
own membership-resolved `workspacePath` and `denyRead:["/workspaces"]` denies
sibling reads.

**Brand-survival threshold:** **single-user incident.** One installation token
leaking into a transcript, or one user's askpass script being readable by
another tenant, is an unrecoverable trust breach. → `requires_cpo_signoff: true`.

## Root Causes (verified)

1. **In-sandbox raw `git` has no credential path (item 1).** `GH_TOKEN` is for
   `gh`, not `git`. With Outcome A confirming the sandbox reaches `github.com`,
   the missing piece is a `GIT_ASKPASS` helper + `GIT_INSTALLATION_TOKEN` env in
   the agent subprocess env, with the helper script written to a sandbox-readable
   path (under `workspacePath`).
2. **`gh auth status` false-negative (item 2).** App installation tokens cannot
   call `GET /user`; the agent trusts the "invalid" verdict and self-blocks.
3. **`userId`-log source-hygiene (item 3).** The PR #4890 success breadcrumb at
   `ensure-workspace-repo.ts:91` emits a raw `userId` key, tripping the advisory
   `userid-bypass-lint` guard (diff-scan of added lines in
   `apps/web-platform/(server|app)/**`).

## Goals

- **Generic, per-user / per-repo.** Installation token + workspacePath are the
  requesting user's membership-checked values (`resolveInstallationId` → ADR-044
  RPC; `fetchUserWorkspacePath`); the token is the already-minted `ghToken`.
  Never `jikig-ai/soleur`. Honor `hr-github-app-auth-not-pat`.
- **Token never persisted, never logged.** Not in `.git/config` remote URLs; not
  interpolated into the askpass script body; not in any pino/Sentry payload.
- **Sandbox-readable askpass.** The askpass script lives under `workspacePath`
  (the only verified `allowWrite` + sandbox-readable dir), with a bounded
  lifecycle (cleanup per dispatch).
- **Concierge stops self-blocking on `gh auth status`** and passes `-R owner/repo`.
- **Source-hygiene clears the `userid-bypass-lint` guard.**

## Non-Goals

- Hardcoding any specific repo. (Anti-goal.)
- Wiring the server-side `github_*` MCP tools into the cc path — **deferred to
  the existing #3722** (`CC_MCP_ALLOWLIST` Phase-2 promotion). Outcome A makes
  in-sandbox git the working path; this is a robustness add, CPO-gated.
- Any DB migration (none expected).
- Changing the ensure-repo self-heal scope (PR #4890; conservative-by-design).
- Changing the "Start Fresh" empty-repo behavior.

---

## Phase 0 — Preconditions (verification only; no production code)

> Phase 0.1 (sandbox-network) is ALREADY RESOLVED = **Outcome A** — do NOT
> re-spike. Record the Outcome-A evidence in the PR body verbatim.

0.1 **Sandbox network = Outcome A (resolved, recorded).** github.com reachable
   from the agent sandbox; in-sandbox GIT_ASKPASS git is network-viable. Evidence
   in PR body: prod in-sandbox `gh auth status` returned a 401-from-`/user`
   "token invalid" verdict (a network-reaching auth verdict, not a connection
   error); github.com is in the SDK managed dev-domain allow-set; no
   `managed-settings.json` ships. No probe needed.

0.2 **Askpass-script path (RESOLVED — write under `workspacePath`).** Confirmed:
   `createSandboxHook(workspacePath)` + `isPathInWorkspace` permit any path
   contained in `workspacePath`; `allowWrite:[workspacePath]`; `$HOME`/`/tmp`
   bwrap-visibility unverifiable. **/work writes the askpass script under
   `workspacePath`** and passes that absolute path as `GIT_ASKPASS`. Verify at
   /work the chosen filename does not collide with a repo-tracked path (use a
   `randomUUID()` suffix like the existing `writeAskpassScript`, and a dot-prefix
   e.g. `.askpass-<uuid>.sh` so it is unobtrusive in the working tree).

0.3 **Token source.** Reuse the already-minted `ghToken` (`cc-dispatcher.ts:1008-1022`)
   — the membership-checked per-user installation token. Do NOT re-mint; do NOT
   derive from anything other than the cold-path `installationId`.

0.4 **Cold-start mock sweep (TDD precondition).** `grep -rln realSdkQueryFactory
   apps/web-platform/test/` → cold-path mocks live in
   `cc-dispatcher-real-factory.test.ts` AND `cc-dispatcher-prefill-guard.test.ts`.
   `cc-dispatcher.ts` does NOT currently import `git-auth`. If item 1 makes
   `cc-dispatcher.ts` import the askpass-writer (`writeAskpassScriptTo` /
   `cleanupAskpassScript` from `git-auth.ts`, or a new module), that module MUST
   be `vi.mock`'d in BOTH files or the suite throws on import. `agent-env` is
   already mocked in both (via `mockBuildAgentEnv`), so a new `buildAgentEnv`
   parameter alone needs no new mock — but a new direct `cc-dispatcher` import does.

0.5 **Test runner + path discovery.** Runner is **vitest** (`bunfig.toml` blocks
   bun discovery). New `.test.ts` files MUST match `apps/web-platform/vitest.config.ts`
   `include: ["test/**/*.test.ts", "lib/**/*.test.ts"]` — so they live under
   `apps/web-platform/test/`. Run form: `./node_modules/.bin/vitest run <path>`.

---

## Phase 1 — In-sandbox git GIT_ASKPASS credentialing (item 1, PRIMARY)

> Outcome A is confirmed; this is the single B-free branch. Write the failing
> test first (`cq-write-failing-tests-before`).

### 1a — `buildAgentEnv` extension (`agent-env.ts`)

- **RED** (`test/agent-env-git-askpass.test.ts`, vitest — mirror the existing
  `describe("ghToken injection")` block in `agent-env.test.ts`):
  - `buildAgentEnv(cred, svc, { gitAskpassScriptPath: "<abs>", gitInstallationToken: "ghs_x" })`
    injects: `GIT_ASKPASS=<abs>`, `GIT_USERNAME=x-access-token`,
    `GIT_INSTALLATION_TOKEN=ghs_x`, `GIT_TERMINAL_PROMPT=0`,
    `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`.
  - **Token never appears in any other env key** — iterate `Object.entries(env)`,
    assert no value other than `GIT_INSTALLATION_TOKEN` equals the token, and
    `GH_TOKEN` (if also set) is the only other token-bearing key (it is the same
    family but a distinct key; assert the askpass token is not duplicated into an
    unexpected key).
  - **Absent entirely** when `gitAskpassScriptPath`/`gitInstallationToken` is
    undefined (graceful-degradation parity — mirror the `omits GH_TOKEN when
    absent` test).
  - **Partial-input guard:** when only one of the two askpass inputs is present,
    inject NEITHER (both-or-nothing; a half-wired askpass is a silent auth
    failure). Assert this.
- **GREEN:** extend `BuildAgentEnvOptions` with
  `gitAskpassScriptPath?: string; gitInstallationToken?: string`. After the
  `GH_TOKEN` block (and outside the auth switch), add a both-present guard that
  sets the six vars. Mirror `git-auth.ts` `ASKPASS_SCRIPT_BODY` semantics: the
  token rides `GIT_INSTALLATION_TOKEN` (env), `GIT_USERNAME=x-access-token`, and
  `GIT_TERMINAL_PROMPT=0 + GIT_CONFIG_NOSYSTEM=1 + GIT_CONFIG_GLOBAL=/dev/null`
  are the defense-in-depth set the learning `2026-04-23-git-askpass-over-shell-helper-for-headless-auth`
  documents. Document at the injection site: never logged; `hr-github-app-auth-not-pat`.

### 1b — Askpass-script writer (`git-auth.ts`)

- **GREEN:** add `export function writeAskpassScriptTo(dir: string): string` that
  writes the **byte-identical** `ASKPASS_SCRIPT_BODY` (token NOT interpolated;
  read from `GIT_INSTALLATION_TOKEN` env) to `join(dir, ".askpass-<randomUUID()>.sh")`
  mode `0o700`, returns the absolute path. Refactor the existing
  `writeAskpassScript()` to delegate to `writeAskpassScriptTo(getAskpassDir())`
  so the script body stays single-sourced (drift-free). `cleanupAskpassScript`
  is reused as-is.
- **RED** (extend `test/git-auth.test.ts` if present, else co-locate in the
  item-1 test): `writeAskpassScriptTo(tmpDir)` writes a `0o700` file under
  `tmpDir`, body is `ASKPASS_SCRIPT_BODY` verbatim, and **the token is NOT in the
  file** (the body references `${GIT_INSTALLATION_TOKEN}`, never a literal token).

### 1c — Thread askpass inputs (`agent-runner-query-options.ts`)

- `AgentQueryOptionsArgs` already carries `ghToken` + `workspacePath`. Add
  `gitAskpassScriptPath?: string` (the token reuses `ghToken` — it IS the
  installation token, so pass `gitInstallationToken: args.ghToken` into
  `buildAgentEnv`). At :152, extend the `buildAgentEnv(…, { ghToken })` call to
  `{ ghToken, gitAskpassScriptPath: args.gitAskpassScriptPath, gitInstallationToken: args.ghToken }`.
  This is per-call divergent (cc sets it; legacy leaves undefined) — NOT part of
  the shared-field drift snapshot, mirroring how `ghToken` is documented.
- **RED:** extend `agent-runner-query-options.test.ts` — when
  `gitAskpassScriptPath` + `ghToken` are passed, the built `opts.env` carries the
  askpass vars; when omitted, it does not (drift-guard parity).

### 1d — Wire from `realSdkQueryFactory` (`cc-dispatcher.ts`)

- After the `ghToken` mint block (:1022), and only when `ghToken !== undefined`,
  write the askpass script under `workspacePath`:
  `const gitAskpassScriptPath = writeAskpassScriptTo(workspacePath)`. Pass
  `gitAskpassScriptPath` into the `buildAgentQueryOptions({ … })` call at :1170.
- **Lifecycle / cleanup (bounded per-dispatch):** the factory constructs the
  `Query` once per cold conversation. Clean up the askpass script when the
  dispatch ends. Decide the cleanup owner at /work — preferred: a `finally`/close
  hook on the runner's per-conversation lifecycle (where `workspacePath` +
  `gitAskpassScriptPath` are in scope), falling back to `cleanupAskpassScript` in
  the factory's error path. A leaked `0o700` random-named file under a single
  user's own `workspacePath` is low-severity (token TTL ≤ 1h, no cross-tenant
  read), but prefer cleanup. Document the chosen owner in the PR body.
- **Mocks:** if `cc-dispatcher.ts` now imports `writeAskpassScriptTo` /
  `cleanupAskpassScript` from `git-auth.ts`, add a `vi.mock("@/server/git-auth", …)`
  to BOTH `cc-dispatcher-real-factory.test.ts` and `cc-dispatcher-prefill-guard.test.ts`
  (Phase 0.4). Stub `writeAskpassScriptTo` to return a fixed path,
  `cleanupAskpassScript` to a `vi.fn()`.
- **RED** (extend `cc-dispatcher-real-factory.test.ts`): when `installationId !==
  null` (token minted), the factory calls `writeAskpassScriptTo(workspacePath)`
  once and the built options carry the askpass env (assert via the
  `mockBuildAgentEnv` call args — it receives `gitAskpassScriptPath` +
  `gitInstallationToken`). When `installationId === null`, no askpass write,
  no askpass env.

### 1e — `.git/config` token-absence invariant

- **RED:** after a credentialed in-sandbox op against a local fixture repo (or a
  unit-level assertion on the helper output), assert the workspace `.git/config`
  remote URL contains **no token** — the token rides env, never the URL. This is
  structurally guaranteed by reusing the `ASKPASS_SCRIPT_BODY` pattern (token via
  env, clean positional URL arg); the test pins the invariant so a future
  URL-cred regression fails. Place at unit level over `git-auth` output / a
  synthesized `.git/config` (no live network, per `cq-test-fixtures-synthesized-only`).

---

## Phase 2 — Concierge stops gating on `gh auth status` (item 2)

- **Locate:** `buildSoleurGoSystemPrompt` (`soleur-go-runner.ts:1038`), `baseline`
  string array (:1041-1051) is the insertion point.
- **GREEN:** add a directive (a named exported `const` for testability, mirroring
  `PRE_DISPATCH_NARRATION_DIRECTIVE`) to the baseline conveying:
  - GitHub App **installation** tokens cannot call `GET /user`, so `gh auth
    status` reports "invalid" even when the token works — do NOT self-block on it.
  - Repo `gh` operations MUST pass `-R owner/repo` (the token resolves the repo
    server-side per the connected workspace; `gh` cannot infer it without `-R`).
- **RED** (new `test/soleur-go-runner-gh-auth-status.test.ts` OR extend
  `soleur-go-runner-narration.test.ts`): assert `buildSoleurGoSystemPrompt()`
  `.toContain(<directive const>)` AND a **paren-safe substring** of the guidance
  (per the CI-sentinel Sharp Edge — pick a phrase spanning NO punctuation
  boundary, e.g. `"gh auth status"` and `"-R owner/repo"` as two separate
  `toContain` checks rather than one phrase straddling parens/colons).

---

## Phase 3 — userId-log source-hygiene (item 3)

- **Edit the SINGLE direct-logger site** at `ensure-workspace-repo.ts:91`:
  `log.info({ userId, action: "cloned" }, "ensure-workspace-repo: cloned connected repo")`
  → drop `userId`, keep `action`: `log.info({ action: "cloned" }, "ensure-workspace-repo: cloned connected repo")`.
  Do NOT touch the two `reportSilentFallback(…, { extra: { userId, hasInstallation: true } })`
  sites at `:80` / `:96` — those are guard-allowlisted (helper hashes via
  `hashExtraUserId`) and runtime-safe.
- **RED** (extend the existing `ensure-workspace-repo` test, or a small new
  assertion): capture the child-logger `info` call args on the success path and
  assert the first arg object has `action: "cloned"` and **no `userId` key**.
- **Guard parity check (AC):** `gh pr diff` of THIS PR shows no ADDED
  `(log|logger)\.(error|warn|info|debug)\(.*\buserId\b` line in
  `apps/web-platform/(server|app)/**` outside the
  `reportSilentFallback|warnSilentFallback|mirrorP0Deduped` allowlist —
  i.e. the `userid-bypass-lint` job passes.

---

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **Phase 0.1 = Outcome A recorded in PR body** with the 401-from-`/user`
      evidence (no re-spike).
- [ ] **Item 1 (`buildAgentEnv`):** injects `GIT_ASKPASS` +
      `GIT_USERNAME=x-access-token` + `GIT_INSTALLATION_TOKEN` +
      `GIT_TERMINAL_PROMPT=0` + `GIT_CONFIG_NOSYSTEM=1` + `GIT_CONFIG_GLOBAL=/dev/null`
      when BOTH askpass inputs are present; injects NONE when either is absent;
      token appears in no env key other than `GIT_INSTALLATION_TOKEN` and in no
      argv. (vitest)
- [ ] **Item 1 (`writeAskpassScriptTo`):** writes a `0o700` script under the
      given dir with body byte-identical to `ASKPASS_SCRIPT_BODY`; the token is
      NOT in the file; `writeAskpassScript()` still works (delegates). (vitest)
- [ ] **Item 1 (wire):** factory writes the askpass script under `workspacePath`
      (NOT `$HOME`/`/tmp`) only when `ghToken` is minted; cleanup is bounded
      per-dispatch (owner documented in PR body). New `git-auth` import (if any)
      is `vi.mock`'d in BOTH `cc-dispatcher-real-factory.test.ts` AND
      `cc-dispatcher-prefill-guard.test.ts`. (vitest)
- [ ] **Item 1 (`.git/config`):** remote URL contains no token after a
      credentialed op (synthesized-fixture assertion). (vitest)
- [ ] **Item 2:** `buildSoleurGoSystemPrompt()` contains the guidance NOT to gate
      on `gh auth status` for App tokens AND to use `-R owner/repo` (two paren-safe
      `toContain` substrings). (vitest)
- [ ] **Item 3:** the `ensure-workspace-repo.ts:91` success breadcrumb no longer
      carries a raw `userId` key (keeps `action`); the two `reportSilentFallback`
      sites are unchanged. (vitest) The `userid-bypass-lint` CI job passes for
      this PR's diff.
- [ ] **Generic per-user/repo:** `git grep -n "jikig-ai\|jikigai/soleur"
      apps/web-platform/server` shows NO **new** hardcoded repo introduced by this
      PR (pre-existing cron/probe-infra references are out of scope).
- [ ] **Token never logged:** `git grep -n "GIT_INSTALLATION_TOKEN\|ghToken\|gitAskpass"
      apps/web-platform/server` shows no `log.*`/`console`/Sentry-extra carrying
      the token value; askpass script body interpolates no literal token.
- [ ] `./node_modules/.bin/vitest run` green for all new + touched suites;
      `npx tsc --noEmit` clean (catches discriminated-union / exhaustiveness rails).
- [ ] PR body uses `Ref` (not `Closes`) for #4868 / #4890 (contextual, MERGED) and
      cross-refs #3722 as the home for the deferred MCP-tool wiring.

### Post-merge (no human-driven step)

- [ ] None expected. In-sandbox git credentialing takes effect on the next cold
      Concierge dispatch for every connected-repo user — the fix is in the
      dispatch path; there is no external step. **Automation: fully in-band.**
      A deploy-time verify, if wanted, is a read-only Sentry check that no
      token-leak / askpass error fires — **no SSH**.

## Test Scenarios (TDD order — RED before GREEN, `cq-write-failing-tests-before`)

1. `test/agent-env-git-askpass.test.ts` (item 1a — `buildAgentEnv` askpass injection + absence + partial-guard + token-not-in-other-keys).
2. `git-auth` askpass-writer test (item 1b — `writeAskpassScriptTo` body/mode/no-token).
3. `agent-runner-query-options.test.ts` extension (item 1c — env threading).
4. `cc-dispatcher-real-factory.test.ts` extension (item 1d — factory writes askpass under workspacePath; `.git/config` invariant item 1e) + mock-add in BOTH cc-dispatcher test files.
5. Concierge-prompt guidance test (item 2).
6. `ensure-workspace-repo` success-breadcrumb test (item 3).

## Logically-separated commits (one worktree)

1. `test+feat: in-sandbox git GIT_ASKPASS credentialing (item 1)` — `agent-env.ts` (`BuildAgentEnvOptions` + injection), `git-auth.ts` (`writeAskpassScriptTo`), `agent-runner-query-options.ts` (thread), `cc-dispatcher.ts` (write under workspacePath + wire + cleanup), tests + BOTH cold-start mock files. **Contract-changing edits FIRST** (`buildAgentEnv` signature, `writeAskpassScriptTo`) before the `cc-dispatcher` consumer (per `2026-05-10-plan-phase-order-load-bearing-when-contract-changes`).
2. `feat: Concierge stops gating on gh auth status + uses -R owner/repo (item 2)` — `soleur-go-runner.ts` + prompt test.
3. `chore(observability): drop raw userId from ensure-workspace-repo success breadcrumb (item 3)` — `ensure-workspace-repo.ts:91` + test.

## Risks & Mitigations

- **Askpass script unreadable in-sandbox (the load-bearing risk).** If the script
  is written to `$HOME`/`/tmp` (the existing `writeAskpassScript` default), the
  bwrap sandbox may not bind-mount it → `git` falls through to the
  `GIT_TERMINAL_PROMPT=0` deterministic "terminal prompts disabled" stderr.
  Mitigation: write under `workspacePath` (verified sandbox-readable via
  `createSandboxHook`/`isPathInWorkspace` + `allowWrite:[workspacePath]`); this is
  the explicit Phase 0.2 decision.
- **Token leak (brand-survival single-user-incident).** Mitigation: token rides
  `GIT_INSTALLATION_TOKEN` env (never URL, never in the script body); AC greps;
  reuse the byte-identical `ASKPASS_SCRIPT_BODY` (no interpolation);
  `hr-github-app-auth-not-pat` (App token, never PAT); never logged.
- **Cross-tenant askpass read.** Mitigation: script under the requesting user's
  own membership-resolved `workspacePath`; `denyRead:["/workspaces"]` denies
  sibling reads; random-named `0o700` file.
- **Cold-start suite import-throw.** New `git-auth` import in `cc-dispatcher.ts`
  not mocked in BOTH test files → import-time throw. Mitigation: Phase 0.4 sweep
  + explicit AC.
- **Both-or-nothing askpass.** A half-wired askpass (script path without token,
  or vice versa) is a silent auth failure. Mitigation: both-present guard in
  `buildAgentEnv` + RED test.
- **Leaked askpass file.** Low-severity (token TTL ≤ 1h, single-tenant dir).
  Mitigation: bounded per-dispatch cleanup (`cleanupAskpassScript`).
- **Precedent diff (deepen-plan Phase 4.4):** the askpass env block + script body
  must mirror `git-auth.ts` `ASKPASS_SCRIPT_BODY` / `gitWithInstallationAuth` env
  block (no URL-embedded creds, `x-access-token`, the four `GIT_*` guards).
  No novel credential path.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty / `TBD` / omits the
  threshold fails `deepen-plan` Phase 4.6. (This plan fills it: single-user incident.)
- The ARGUMENTS says item 3 has **two** `log.info({userId})` breadcrumbs; the
  codebase has **ONE** (`ensure-workspace-repo.ts:91`). The two
  `reportSilentFallback` sites are guard-allowlisted, NOT direct-logger sites —
  do NOT "fix" them.
- The askpass script MUST be written under `workspacePath` (the only verified
  sandbox-readable `allowWrite` dir). `$HOME`/`/tmp` (the existing
  `writeAskpassScript` default) is for the **server-side** `gitWithInstallationAuth`,
  whose `$HOME` is the server's, not the sandbox's. A helper the sandbox can't
  read+exec is useless.
- `denyRead:["/workspaces"]` is the cross-tenant **sibling** guard, NOT a deny on
  the agent's own `workspacePath` — `createSandboxHook` permits any contained path.
- The token rides `GIT_INSTALLATION_TOKEN` env; NEVER interpolate it into the
  askpass script body or a `.git/config` remote URL.
- The optional `github_*` MCP-tool wiring is **deferred to #3722** (`readCcMcpAllowlist`
  is Phase-1 deny-by-default by design; promotion is Phase 2). Do NOT partially
  wire it here.
- CI-sentinel paren-safety: the item-2 prompt assertion must use substrings that
  span no punctuation boundary (`"gh auth status"`, `"-R owner/repo"` as separate
  `toContain` checks), per the CI-sentinel Sharp Edge.
- Any new module in the factory cold path must be `vi.mock`'d in BOTH
  `cc-dispatcher-real-factory.test.ts` AND `cc-dispatcher-prefill-guard.test.ts`.
- Runner is **vitest**, not bun (`bunfig.toml` blocks bun discovery). New test
  paths must match `vitest.config.ts include` (`test/**/*.test.ts`).
- `#4868` / `#4890` are MERGED predecessors (context) — use `Ref`, not `Closes`.

## Open Code-Review Overlap

Checked open `code-review` issues (`gh issue list --label code-review --state open
--json number,title,body --limit 200` → 71 issues) against this PR's edited files
(`agent-env.ts`, `git-auth.ts`, `agent-runner-query-options.ts`, `cc-dispatcher.ts`,
`soleur-go-runner.ts`, `ensure-workspace-repo.ts`):

- **#3243** — `arch: decompose cc-dispatcher.ts into focused modules (Ref #3235)` — touches `cc-dispatcher.ts`. **Acknowledge:** different concern (module decomposition vs. a small cold-path wire-in). This PR adds a few lines to the existing cold path; it does not block or get blocked by the decomposition. Scope-out remains open.
- **#3242** — `review: tool_use WS event lacks raw name field for agent consumers (Ref #3235)` — touches `cc-dispatcher.ts`. **Acknowledge:** unrelated WS-event-shape concern. Scope-out remains open.

No fold-in: both overlaps are orthogonal to git-credential plumbing.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — brand-survival
single-user-incident threshold).

### Engineering (CTO)

**Status:** reviewed (plan-author assessment; deepen-plan will spawn the triad).
**Assessment:** Small, well-bounded server-side plumbing change against
already-provisioned surfaces. The load-bearing decision (askpass script under
`workspacePath`) is verified against the sandbox-hook containment logic, not
assumed. Reuse of the `ASKPASS_SCRIPT_BODY` / `gitWithInstallationAuth` env-block
pattern keeps the credential path single-sourced (no novel URL-cred path). No new
infrastructure, no migration. Mirrors `cq-silent-fallback-must-mirror-to-sentry`,
`hr-github-app-auth-not-pat`. The optional MCP-tool wiring is correctly deferred
to its existing tracking issue #3722.

### Product/UX Gate

**Tier:** none (server plumbing; no UI surface in `## Files to Edit` — no
`components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`).
**Decision:** auto-accepted (pipeline). `wg-ui-feature-requires-pen-wireframe`
does not fire (no UI surface). **CPO sign-off** is required per
`requires_cpo_signoff: true` for the brand-survival token-handling surface (item 1).

#### Findings

No UI changes. Brand-survival concern is the installation-token leak / cross-tenant
askpass-read vector (item 1), handled via env-only token delivery + workspace-scoped
askpass + `user-impact-reviewer` at review time.

## Infrastructure (IaC)

No new infrastructure (no server, service, secret, vendor, DNS, cron, or runtime
process). Pure code change against already-provisioned surfaces
(`apps/web-platform/server/`). Phase 2.8 skip conditions met. The fix takes effect
automatically on the next cold dispatch; there is no provisioning step.

## Observability

```yaml
liveness_signal:
  what: "in-sandbox git ops succeed on cold Concierge dispatch (push/fetch authenticate via GIT_ASKPASS)"
  cadence: "per cold conversation that does git work"
  alert_target: "Sentry feature:cc-dispatcher op:mint-gh-token error rate (existing) + absence of git AUTH_FAILED in agent transcripts"
  configured_in: "existing reportSilentFallback at cc-dispatcher.ts mint site; git-auth GIT_TERMINAL_PROMPT=0 deterministic stderr"
error_reporting:
  destination: "Sentry via reportSilentFallback (pino + Sentry), feature-tagged; token NEVER in payload"
  fail_loud: "gh-token mint failure mirrors to Sentry then degrades gracefully (no askpass wired); git auth failure surfaces as deterministic 'terminal prompts disabled' stderr to the agent transcript, never silent fall-through"
failure_modes:
  - mode: "askpass script unreadable in-sandbox (wrong path)"
    detection: "git AUTH_FAILED 'terminal prompts disabled' / 'could not read Username' in agent transcript"
    alert_route: "agent transcript + (if wired) Sentry on git error classification"
  - mode: "gh-token mint fails (no askpass wired)"
    detection: "existing reportSilentFallback feature:cc-dispatcher op:mint-gh-token"
    alert_route: "Sentry"
  - mode: "token leak into log/URL/script body"
    detection: "AC grep gate at PR time; userid-bypass-lint guard; never-logged invariant test"
    alert_route: "CI fail at PR time (pre-merge)"
logs:
  where: "pino child loggers (cc-dispatcher, git-auth, ensure-workspace-repo); token NEVER logged"
  retention: "per existing log pipeline"
discoverability_test:
  command: git grep -l GIT_INSTALLATION_TOKEN apps/web-platform/server/agent-env.ts
  expected_output: "agent-env.ts"
```

## Files to Edit

- `apps/web-platform/server/agent-env.ts` — extend `BuildAgentEnvOptions` with
  `gitAskpassScriptPath?` + `gitInstallationToken?`; inject the six `GIT_*` vars
  under a both-present guard; document never-logged / `hr-github-app-auth-not-pat`.
- `apps/web-platform/server/git-auth.ts` — add `writeAskpassScriptTo(dir)`;
  refactor `writeAskpassScript()` to delegate (single-source the body).
- `apps/web-platform/server/agent-runner-query-options.ts` — add
  `gitAskpassScriptPath?` to `AgentQueryOptionsArgs`; thread askpass inputs into
  the `buildAgentEnv` call (token = `args.ghToken`).
- `apps/web-platform/server/cc-dispatcher.ts` — after the `ghToken` mint, write
  the askpass script under `workspacePath` when minted; pass
  `gitAskpassScriptPath` into `buildAgentQueryOptions`; bounded per-dispatch
  cleanup; (if new `git-auth` import) ensure mocked in both cc-dispatcher tests.
- `apps/web-platform/server/soleur-go-runner.ts` — add the `gh auth status`
  guidance directive to `buildSoleurGoSystemPrompt` baseline (item 2).
- `apps/web-platform/server/ensure-workspace-repo.ts` — drop `userId` from the
  `:91` `log.info` success breadcrumb (item 3).
- `apps/web-platform/test/agent-runner-query-options.test.ts` — askpass env
  threading assertion (item 1c).
- `apps/web-platform/test/cc-dispatcher-real-factory.test.ts` — `vi.mock`
  `@/server/git-auth` (if newly imported by cc-dispatcher); factory askpass-write
  assertion.
- `apps/web-platform/test/cc-dispatcher-prefill-guard.test.ts` — same mock add.
- `apps/web-platform/test/agent-env.test.ts` OR new test (below) — askpass cases.
- `apps/web-platform/test/soleur-go-runner-narration.test.ts` OR new prompt test
  (below) — item 2 guidance assertion.
- The existing `ensure-workspace-repo` test file (locate at /work) — item 3
  breadcrumb assertion.

## Files to Create

- `apps/web-platform/test/agent-env-git-askpass.test.ts` — item 1a RED tests
  (askpass injection, absence, partial-guard, token-not-in-other-keys,
  `.git/config` token-absence invariant).
- (Possibly) `apps/web-platform/test/soleur-go-runner-gh-auth-status.test.ts` —
  item 2 RED prompt test (if not folded into the narration test).

## GDPR / Compliance

Trigger (b) fires: brand-survival threshold `single-user incident`. No new
regulated-data schema / migration / auth surface; the installation token is an
existing processed credential (PR #4868). The token-leak / cross-tenant askpass
vector is the relevant surface — handled by env-only token delivery +
workspace-scoped askpass + membership-checked `installationId`/`workspacePath`.
No Art. 9 special-category data. Invoke `/soleur:gdpr-gate` at /work only if a new
data-movement surface emerges; otherwise advisory-only.
