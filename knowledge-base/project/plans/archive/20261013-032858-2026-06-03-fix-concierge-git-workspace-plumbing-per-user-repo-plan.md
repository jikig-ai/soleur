<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
---
title: "Fix Concierge git + workspace plumbing so the agent can do git work in every user's own connected repo"
type: fix
date: 2026-06-03
branch: feat-one-shot-concierge-git-credentials
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# 🐛 Fix: Concierge git + workspace plumbing (per-user / per-repo, generic)

> Spec lacks valid `lane:` (no spec.md for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-06-03
**Gates passed:** 4.6 User-Brand Impact (present, threshold `single-user incident`),
4.7 Observability (all 5 fields present, no SSH in discoverability_test), 4.8 PAT-shaped
var halt (none), 4.9 UI-wireframe (no UI surface → skip). Cited rule IDs verified ACTIVE
(`cq-silent-fallback-must-mirror-to-sentry`, `cq-write-failing-tests-before`,
`hr-github-app-auth-not-pat`, `hr-verify-repo-capability-claim-before-assert`,
`wg-ui-feature-requires-pen-wireframe`). PR #4868 live-verified MERGED; issue #4826
live-verified OPEN (symptom trigger, not a work target).

### Key Improvements (over the as-planned draft)

1. **Precedent-diff confirmed (Phase 4.4).** `git-auth.ts` embeds NO credentials in the
   git remote URL — the token rides `GIT_INSTALLATION_TOKEN` env consumed by a fixed
   askpass script; the clone/push URL is a clean positional arg (`workspace.ts:173`,
   `push-branch.ts:115-117`). The plan's "token never persisted into `.git/config`" claim
   is structurally guaranteed by reusing this helper, not just asserted. ensure-repo MUST
   reuse `gitWithInstallationAuth` / `provisionWorkspaceWithRepo` verbatim — no novel
   URL-cred path.
2. **Verify-the-negative confirmed (Phase 4.45).** Zero token-value-in-log sites exist in
   `cc-dispatcher.ts` / `agent-env.ts`; the existing mint-failure mirror carries only
   `{ userId, hasInstallation: true }` (`cc-dispatcher.ts:997-1000`) — never the token.
   The "never logged" claim holds against current code; new code MUST preserve it.
3. **Scheduled-work check (Phase 4.4):** 38 Inngest `cron-*` functions exist, but this
   plan introduces NO scheduled job (ensure-repo runs inline on cold dispatch) — Inngest
   precedent is N/A. Recorded so /work does not mistakenly add a cron.

### New Considerations Discovered

- The **load-bearing risk remains the Phase 0.1 sandbox-network spike.** Until /work runs
  it, the plan cannot commit to Outcome A vs B for item 1. This is correct by design — the
  spike is cheap and gates the whole item-1 shape (`hr-verify-repo-capability-claim-before-assert`).
- ensure-repo (item 2) is fully server-side and independent of the spike outcome — it is
  the safe, highest-leverage first commit regardless of how 0.1 resolves.

## Overview

Follow-up to merged PR **#4868** (which injected a per-workspace GitHub App
installation token as `GH_TOKEN` — **contextual citation, NOT a work target**).
`GH_TOKEN` is now minted and injected into the agent env for the cc-soleur-go
(Concierge) path (`cc-dispatcher.ts realSdkQueryFactory` → `buildAgentEnv` →
`GH_TOKEN`). Three downstream gaps remain that block the Concierge from doing
git work in a Soleur user's **own** connected repo. The fix MUST be generic
per-user / per-repo — derive owner/repo + installation token from the requesting
user's connected workspace; **never hardcode `jikig-ai/soleur`**.

**Prod symptom:** a user "Working on: `<their-repo>`" asked the Concierge to fix
an issue; the agent reported (1) *"No Git repository found — /workspaces/`<uuid>`
… No .git directory was found"* and (2) *"gh auth status reports The token in
GH_TOKEN is invalid"*.

This plan does **research and design only** for /work. **No code is written
during planning.**

## Premise Validation (Phase 0.6)

| Cited reference | Probe | Result |
| --- | --- | --- |
| PR #4868 (GH_TOKEN mint predecessor) | `gh pr view 4868 --json state,title` | **MERGED** — `fix(chat): Concierge gh-auth (GH_TOKEN mint) + Bash permission posture`. Holds as context, not a work target. |
| Issue #4826 (the issue the prod user asked Concierge to fix) | `gh issue view 4826 --json state` | **OPEN** — `feat: nav-rail position resume`. This is the *trigger of the symptom*, NOT a work target. The work target is the Concierge git plumbing. |
| `apps/web-platform/server/workspace.ts:115-221` `provisionWorkspaceWithRepo` | `Read` | Exists (396 lines). Clones via `gitWithInstallationAuth`. |
| `apps/web-platform/server/git-auth.ts` GIT_ASKPASS pattern | `Read` | Exists (259 lines). Canonical askpass helper (`x-access-token` user, token via `GIT_INSTALLATION_TOKEN` env, `credential.helper=` reset). |
| `apps/web-platform/app/api/repo/setup/route.ts:165` clone-on-connect | `Read` | Exists (316 lines). |
| Sandbox config `buildAgentSandboxConfig` | `Read` `agent-runner-sandbox-config.ts` | Exists. **`network.allowedDomains: []` + `allowManagedDomainsOnly: true`** — see Research Reconciliation. |
| `realSdkQueryFactory` cold-start `Promise.all` | `Read` `cc-dispatcher.ts:965-973` | Already resolves `installationId`, mints `ghToken`. |
| Cold-start test files | `grep -rln realSdkQueryFactory test/` | `cc-dispatcher-real-factory.test.ts`, `cc-dispatcher-prefill-guard.test.ts`, `agent-runner-query-options.test.ts`, `agent-runner-helpers.test.ts`. |

**Net premise note:** All cited file/symbol paths hold. The ARGUMENTS'
root-cause framing is correct on items 1 and 2; item 3 (raw `git push` in the
sandbox) is **partially superseded** by an existing server-side MCP-tool
architecture that the cited diagnosis did not account for — see Research
Reconciliation below. The plan's primary fix (item 1) is therefore re-shaped
from "raw git in the sandbox" toward "make the server-side write path reachable
+ credential the sandbox git for the operations that genuinely run in-sandbox
(read/fetch/clone-repair)". This is the single most important finding from
planning and the reason for the Research Reconciliation section.

## Research Reconciliation — ARGUMENTS Diagnosis vs. Codebase

| ARGUMENTS claim | Codebase reality | Plan response |
| --- | --- | --- |
| "Raw git has no credentials in the agent sandbox; wire GIT_ASKPASS inside the SDK/bubblewrap sandbox so raw `git push`/`fetch`/`clone` against github.com works." | The sandbox config sets **`network.allowedDomains: []` + `allowManagedDomainsOnly: true`** (`agent-runner-sandbox-config.ts:66-69`). Per the SDK (`sdk.d.ts:3597-3599`), this means only managed-allowed domains are reachable — **outbound network from sandboxed Bash is restricted**. A GIT_ASKPASS helper alone does NOT make `git push` to `github.com` succeed if the sandbox blocks the TCP connection. **CRITICAL VERIFICATION REQUIRED at /work Phase 0** (see Phase 0). | Phase 0 spike: empirically determine whether sandboxed Bash can reach `github.com:443`. **If blocked** → the credential-helper-in-sandbox approach cannot push/fetch/clone; the agent MUST use the server-side write path (item below). **If reachable** (managed-domains includes github, or the helper + a domain allow makes it reachable) → wire GIT_ASKPASS env into `buildAgentEnv` so in-sandbox git authenticates. The plan carries BOTH branches; Phase 0 picks one. |
| "The agent then has nothing to branch/commit/PR." | **Branch/commit are LOCAL git ops** (no network) — they work in-sandbox once a `.git` exists. **Push/PR go through a server-side MCP tool family** (`github-tools.ts` → `mcp__soleur_platform__github_push_branch`, `…create_pull_request`, `…github_read_issue`, etc.) that runs `gitWithInstallationAuth`/`createPullRequest` **server-side, outside the sandbox**, using the installation token. | The real gap for push/PR is that **the cc-soleur-go (Concierge) path registers NO platform MCP tools**: `mcpServers: readCcMcpAllowlist()` returns `{}` (`cc-dispatcher.ts:1159`, `readCcMcpAllowlist` Phase-1 default). So the Concierge cannot call `github_push_branch`/`create_pull_request`/`github_read_issue` at all. **Item 4 (gh-gating) and the "branch/commit/PR" capability are really about wiring these existing server-side tools into the Concierge path** — re-scoped in Phase 4. |
| "`gh issue view N` without -R cannot resolve the repo." | True — but the codebase ALSO exposes `github_read_issue` / `github_read_pr` MCP tools that resolve owner/repo **server-side** and never touch the sandbox network. | Phase 4 wires the read tools into the Concierge path AND updates the Concierge system prompt to prefer them (and to pass `-R owner/repo` when shelling `gh`). |
| "Workspace is not a usable clone (`provisionWorkspace` git-inits an empty repo with no origin); fire-and-forget clone leaves no `.git`." | Confirmed for the "Start Fresh" path. For the connect-repo path, `provisionWorkspaceWithRepo` DOES clone with origin. The clone at `repo/setup/route.ts:165` is "fire-and-forget" only in that the **HTTP response returns before the clone finishes** (line 315) — but the `.then/.catch` chain DOES write `repo_status` and DOES mirror failures to Sentry (`reportSilentFallback` at :277). | Item 3 is therefore "**make completion observable + add a clone-status field item 2 can read**", not "add error handling that's missing". Item 2 (session-start ensure-repo) is the genuinely-new self-heal. |

**Implication:** The plan's center of gravity shifts from "GIT_ASKPASS for raw
push in sandbox" to: **(A)** self-healing ensure-repo so a `.git` of the
connected repo is present (item 2 — the highest-leverage fix for symptom #1);
**(B)** wiring the existing server-side GitHub MCP tools into the Concierge path
so push/PR/issue-read work without sandbox network (item 4 expanded); **(C)**
credentialing in-sandbox git for the ops that genuinely run there
(fetch/pull/clone-repair) **iff** Phase 0 shows the sandbox can reach github —
otherwise those ops move server-side too.

## User-Brand Impact

**If this lands broken, the user experiences:** the Concierge says "No Git
repository found" / "GH_TOKEN is invalid" and refuses to do any git work in
*their own* connected repo — the headline product promise ("an AI team that
works in your repo") visibly fails on the first real task.

**If this leaks, the user's code / GitHub installation token is exposed via:**
(a) the installation token written into `.git/config` remote URLs or echoed
into a log/transcript; (b) a credential-helper script readable by a co-tenant
workspace; (c) an ensure-repo path that clones the WRONG user's repo into a
workspace (cross-tenant) because owner/repo or installationId was resolved from
anything other than the requesting user's membership-checked active workspace.

**Brand-survival threshold:** **single-user incident.** One user seeing another
user's private repo cloned into their workspace, or one installation token
leaking into a transcript, is an unrecoverable trust breach. → `requires_cpo_signoff: true`.

## Root Causes (verified, re-framed)

1. **Workspace not a usable clone (item 2 target — self-heal).** If the
   connect-repo clone never ran or failed (race, transient GitHub hiccup,
   container/workspace-dir reset on prod), `/workspaces/<uuid>` has no `.git` of
   the connected repo. There is **no session-start repair** — the broken state
   persists across every future conversation. The agent has nothing to
   branch/commit, and `gh issue view N` (no `-R`) cannot resolve the repo.

2. **`gh auth status` false-negative (item 4 target — prompt + tool wiring).**
   GitHub App **installation** tokens cannot call `GET /user`, which `gh auth
   status` probes — so it ALWAYS reports an installation token "invalid", though
   the same token works for `gh issue view -R owner/repo`, `gh pr create`, and
   git-over-HTTPS. The agent ran `gh auth status`, trusted it, and self-blocked.

3. **In-sandbox git/gh network + credentials (item 1 target — Phase-0-gated).**
   `GH_TOKEN` authenticates the `gh` CLI but NOT raw `git`. AND the sandbox
   network policy (`allowedDomains: []` + `allowManagedDomainsOnly: true`) may
   block the TCP connection to github.com entirely, making any in-sandbox
   git/gh **network** op (push/fetch/clone) fail regardless of credentials.
   Local ops (branch/commit/status/diff) work once a `.git` exists.

## Goals

- **Generic, per-user / per-repo.** owner/repo + installation token are always
  derived from the requesting user's **membership-checked active workspace**
  (`resolveInstallationId` → ADR-044 RPC; `users.repo_url` / workspace repo
  cols → owner/repo). Never `jikig-ai/soleur`. Honor `hr-github-app-auth-not-pat`.
- **Self-healing.** A workspace that is "connected but not cloned" repairs
  itself on the next Concierge conversation automatically — zero out-of-band
  intervention (the `/workspaces` dir lives on prod).
- **Token never persisted, never logged.** Not in `.git/config` remote URLs;
  not in any pino/Sentry payload; mint failures fail-soft (degrade, never crash
  the conversation).
- **Agent-native end-to-end:** clone present → credentialed git for in-sandbox
  ops → server-side MCP tools for push/PR/issue-read → Concierge no longer gates
  on `gh auth status`.

## Non-Goals

- Hardcoding any specific repo. (Anti-goal.)
- Any out-of-band re-provision / manual step (the self-heal eliminates it).
- DB migration (none expected — see Phase 0 for the clone-status field
  decision; prefer reusing `users.repo_status` / workspace mirror cols).
- Changing the "Start Fresh" empty-repo behavior (it correctly has no origin).

---

## Phase 0 — Preconditions & the load-bearing sandbox-network spike (MUST run first)

> No production code in Phase 0 — these are verification spikes whose outcomes
> select between Phase 1 branches. Record every result in the PR body.

0.1 **Sandbox network reachability spike (DECIDES Phase 1 shape).** Empirically
   determine whether sandboxed Bash on the cc-soleur-go path can open a TCP
   connection to `github.com:443`. Approaches, cheapest first:
   - Read the SDK sandbox implementation for how `allowManagedDomainsOnly: true`
     + `allowedDomains: []` is enforced for non-WebFetch network (bwrap netns?
     proxy? socat?). Grep the installed package:
     `grep -rn "allowManagedDomainsOnly\|managed.*domain\|netns\|--unshare-net\|proxy" node_modules/@anthropic-ai/claude-agent-sdk/`.
   - Identify what "managed domains" resolves to in our deploy (is `github.com`
     ever in the managed set? Check Dockerfile / managed-settings / any
     `ANTHROPIC_*` managed-settings file).
   - If inconclusive from source, write a throwaway probe: a sandboxed Bash
     command (`getent hosts github.com` / `timeout 5 bash -c 'cat < /dev/null > /dev/tcp/github.com/443'; echo $?`)
     executed through the SAME sandbox config (`buildAgentSandboxConfig`) used by
     the runner, and observe exit code. **Do NOT ship the probe** — it is a spike.
   - **Outcome A (sandbox CAN reach github.com):** in-sandbox GIT_ASKPASS is
     viable → Phase 1 wires the askpass env into `buildAgentEnv`. Still verify
     the askpass SCRIPT PATH is sandbox-readable+executable (see 0.2).
   - **Outcome B (sandbox CANNOT reach github.com):** in-sandbox raw git
     push/fetch/clone is impossible. The credential-helper-in-sandbox fix is
     moot for push; push/PR/clone-repair MUST be server-side (Phase 2 ensure-repo
     runs server-side already; push/PR via Phase 4 MCP tools). Record this and
     **drop the in-sandbox-push portion of item 1** with a one-line rationale
     in the PR body. This is the `hr-verify-repo-capability-claim-before-assert`
     gate firing.

0.2 **GIT_ASKPASS sandbox-path reachability (only meaningful under Outcome A).**
   `git-auth.ts writeAskpassScript()` writes to `$HOME` (or `/tmp`). The sandbox
   sets `filesystem.allowWrite: [workspacePath]` and `denyRead: ["/workspaces",
   "/proc"]`. Verify: (a) is `$HOME` readable+executable inside the sandbox? (b)
   is `/tmp` (`TMPDIR`) readable+executable inside the sandbox? A helper the
   sandbox can't `exec` is useless (ARGUMENTS' explicit CRITICAL note). Read
   `sandbox-hook.ts` + `bash-sandbox.ts` to see how Bash PreToolUse validates
   paths. **If neither `$HOME` nor `/tmp` is sandbox-execable**, the askpass
   script must live under `workspacePath` (the only `allowWrite` dir) — but
   `denyRead: ["/workspaces"]` may then deny it. Resolve this concretely; record
   the chosen path.

0.3 **Owner/repo derivation source.** Confirm the per-user owner/repo source for
   the ensure-repo (item 2) clone-target and for wiring `github_*` tools (item 4):
   read `users.repo_url` (and the ADR-044 workspace mirror cols) via the
   membership-checked path the legacy runner already uses. Grep how
   `agent-runner.ts startAgentSession` resolves `owner`/`repo`/`defaultBranch`
   for `buildGithubTools` — REUSE that resolver verbatim; do not re-derive.
   `git grep -n "buildGithubTools\|defaultBranch\|owner,\s*repo" apps/web-platform/server/agent-runner.ts`.

0.4 **Clone-status field decision (item 3).** Determine how item 2 detects
   "connected but not cloned". Prefer reusing existing signal:
   `users.repo_status` (`cloning|ready|error`) is already written by
   `repo/setup/route.ts`. Decide: is `repo_status === "ready"` a sufficient
   "should-have-a-clone" signal, with the actual `.git` presence + origin match
   checked on disk at session start? **If yes → NO new column, NO migration.**
   Only introduce a column if disk-check + `repo_status` cannot disambiguate.
   Record the decision; "No migration expected" is the default per ARGUMENTS.

0.5 **Cold-start mock sweep (TDD precondition).** `grep -rln realSdkQueryFactory
   test/` → `cc-dispatcher-real-factory.test.ts` AND
   `cc-dispatcher-prefill-guard.test.ts` BOTH `vi.mock` the cold-start deps
   (`resolve-installation-id`, `github-app`, `resolve-bash-autonomous`,
   `agent-runner` `getUserServiceTokens`, `agent-env`, `byok-lease`,
   `supabase/tenant`, etc.). **Any NEW module added to the factory's `Promise.all`
   or cold path MUST be `vi.mock`'d in BOTH files** or the suite throws on import.
   Enumerate the new modules this plan introduces (ensure-repo helper, askpass-env
   builder, owner/repo resolver if new) and list each as a mock-add in both files.

0.6 **Test runner + path discovery.** Runner is **vitest** (NOT bun test —
   `apps/web-platform/bunfig.toml` blocks bun discovery). New test files MUST
   match `apps/web-platform/vitest.config.ts` `include:` globs (`test/**/*.test.ts`).
   Verify before writing: `grep -n "include" apps/web-platform/vitest.config.ts`.
   Run form: `./node_modules/.bin/vitest run <path>`.

---

## Phase 1 — In-sandbox git credentialing (item 1) — **Phase-0-gated**

> Run ONLY the branch Phase 0.1 selected. Write the failing test first
> (`cq-write-failing-tests-before`).

### Outcome A (sandbox reaches github.com): wire GIT_ASKPASS env into the agent env

- **RED:** new test `test/agent-env-git-askpass.test.ts` (vitest) asserting
  `buildAgentEnv(..., { ghToken, gitAskpass: { scriptPath } })` (or equivalent
  signature) injects `GIT_ASKPASS`, `GIT_USERNAME=x-access-token`,
  `GIT_INSTALLATION_TOKEN=<token>`, `GIT_TERMINAL_PROMPT=0`,
  `GIT_CONFIG_NOSYSTEM=1` and that **the token never appears in any other env
  key and never in argv**. Assert these vars are ABSENT when `ghToken`/askpass
  is undefined (graceful degradation parity).
- **GREEN:** extend `buildAgentEnv` (`agent-env.ts`) `BuildAgentEnvOptions` with
  the askpass inputs. Mirror `git-auth.ts` `ASKPASS_SCRIPT_BODY` (fixed body,
  token via env, `x-access-token` username) and `HELPER_RESET` semantics
  (`credential.helper=` reset). The script is written by the **server** (reuse
  `writeAskpassScript()` from `git-auth.ts`) to the Phase-0.2-chosen
  sandbox-readable+executable path; the path is passed as `GIT_ASKPASS` env.
  Token rides `GIT_INSTALLATION_TOKEN` (NOT interpolated into the file, NOT in
  the remote URL).
- **Cleanup:** the askpass script's lifecycle must be bounded (the runner GC's
  per-dispatch). Decide cleanup owner (factory `finally` vs runner close hook);
  a leaked `0o700` file is low-severity (token TTL ≤ 1h) but prefer cleanup.
- **Wire:** `cc-dispatcher.ts realSdkQueryFactory` passes the askpass inputs to
  `buildAgentQueryOptions` → `buildAgentEnv`, reusing the already-minted
  `ghToken` + `installationId`. Add the askpass-builder module to BOTH cold-start
  test mocks (Phase 0.5).
- **NEVER persist token into `.git/config`.** Explicitly assert the remote URL
  in the workspace `.git/config` does NOT contain the token after a credentialed
  op (test).

### Outcome B (sandbox cannot reach github.com): drop in-sandbox push; document

- Do NOT wire GIT_ASKPASS for push/fetch/clone. Add a code comment at the
  `GH_TOKEN` injection site (`agent-env.ts:122-128`) documenting: (a) the
  installation-token `/user` limitation (`gh auth status` false-negative), AND
  (b) that in-sandbox raw-git network ops are blocked by the sandbox network
  policy, so push/PR/clone go through the server-side `github_*` MCP tools +
  server-side ensure-repo. This satisfies item 4's "document the limitation
  where GH_TOKEN is wired".
- In-sandbox git is still credentialed for **read/local** ops only IF any
  in-sandbox network read (e.g., `git fetch` for status freshness) is desired
  and reachable — otherwise skip entirely.

---

## Phase 2 — Session-start ensure-repo self-heal (item 2) — generic, idempotent, fail-soft

> The highest-leverage fix for symptom #1. Runs **server-side** (no sandbox
> network dependency). Write the failing test first.

- **New module:** `apps/web-platform/server/ensure-workspace-repo.ts` exporting
  `ensureWorkspaceRepoCloned({ userId, workspacePath, installationId, repoUrl })`.
  - **Detect:** workspace has a connected repo (`installationId !== null` AND a
    recorded `repo_url`) but `workspacePath` is NOT a clone of it — either no
    `<workspacePath>/.git`, OR `git -C <workspacePath> remote get-url origin`
    does not match the connected `repoUrl` (normalize via `normalizeRepoUrl`
    before compare; tolerate `.git` suffix). Use `existsSync(join(workspacePath, ".git"))`
    + an `execFileSync` origin read (no network).
  - **Repair:** clone/repair via the installation token by **reusing
    `provisionWorkspaceWithRepo`** (or `gitWithInstallationAuth` directly for an
    in-place `git remote add origin` + `git fetch` if a `.git` exists but origin
    mismatches). Generic per-user/repo. Token never persisted into the remote URL
    (the helper uses GIT_ASKPASS, not URL-embedded creds — confirm).
  - **Idempotent:** already-cloned + origin-match → **no-op** (return early,
    cheap disk check only).
  - **Fail-soft:** clone failure → `reportSilentFallback(err, { feature:
    "ensure-workspace-repo", op: "clone", message: …, extra: { userId } })`
    (honor `cq-silent-fallback-must-mirror-to-sentry`) AND **graceful degrade —
    never throw into the conversation**. The Concierge proceeds (degraded), it
    does not crash.
  - **NEVER log the token.**
- **RED tests** (`test/ensure-workspace-repo.test.ts`, vitest):
  1. connected-but-not-cloned (no `.git`) → calls clone/repair exactly once.
  2. connected + origin mismatch → repairs origin (or re-clones) once.
  3. already-cloned + origin match → **no-op** (clone/repair NOT called).
  4. not connected (`installationId === null` / no `repo_url`) → no-op, no error.
  5. clone failure → `reportSilentFallback` called once AND function resolves
     (does NOT throw) — graceful degrade.
  6. token never appears in any mock log/Sentry payload arg (assert on captured
     `reportSilentFallback`/logger args).
- **Wire-in (dispatch entry):** call `ensureWorkspaceRepoCloned` **before
  dispatch** on the cold path. Best insertion: inside `realSdkQueryFactory`
  alongside the existing `installationId`/`workspacePath` resolution (both are
  already awaited there at `cc-dispatcher.ts:965-973`), OR in `dispatchSoleurGo`
  before `runner.dispatch`. **Decide at /work** based on warm-vs-cold: ensure-repo
  should run on cold dispatch (when the Query is constructed), not every turn —
  prefer the factory so it is naturally per-cold-conversation (mirrors the
  factory's "only invoked once per cold conversation" contract,
  `cc-dispatcher.ts:891-895`). Trace the value end-to-end
  (`hr` precedent: `2026-05-05-trace-callgraph-from-entrypoint-when-placing-guards.md`):
  confirm `installationId` + `workspacePath` + `repoUrl` are all in scope at the
  chosen site.
- **Add the new module to BOTH cold-start test mocks** (Phase 0.5) so
  `cc-dispatcher-real-factory.test.ts` and `cc-dispatcher-prefill-guard.test.ts`
  don't break on import.

---

## Phase 3 — Harden clone-on-connect (item 3) — observable completion + status

> Re-scoped per Research Reconciliation: the `.catch` already mirrors to Sentry.
> The gap is **completion observability** + a signal item 2 can read.

- **Track completion / surface failures:** the clone at `repo/setup/route.ts:165`
  already writes `repo_status: ready|error` and mirrors failures via
  `reportSilentFallback`. Verify this is sufficient; the ARGUMENTS' "await /
  track completion" is satisfied by the existing `.then/.catch` + `repo_status`
  write — do **not** convert to a blocking `await` (it would stall the HTTP
  response; the background pattern is intentional). Instead:
  - Ensure a **clear, queryable "clone completed"** signal exists that Phase 2
    can read. Per Phase 0.4, prefer the existing `repo_status === "ready"` +
    on-disk `.git` check (no migration). Confirm `repo_status: error` is set on
    every failure arm (it is, at `:299`).
  - Add a one-line code comment at `:165` cross-referencing
    `ensure-workspace-repo.ts` as the self-heal for the "ready-but-no-.git"
    drift class (so a future reader connects the two halves).
- **RED test (if any code changes here):** assert that on clone success
  `repo_status` is `ready` AND on failure it is `error` with the Sentry mirror
  fired. If Phase 0.4 concludes no code change is needed here, record that and
  skip — do not add ceremony.

---

## Phase 4 — Stop gating on `gh auth status` + wire server-side GitHub tools (item 4, expanded)

> Re-scoped per Research Reconciliation: the real push/PR/issue-read capability
> for the Concierge is the **server-side `github_*` MCP tools**, which the cc
> path does not currently register.

### 4a — Concierge guidance (system prompt)

- Locate the cc-soleur-go system-prompt builder (`buildSoleurGoSystemPrompt` /
  the Concierge guidance). The prompt MUST NOT treat `gh auth status` as
  authoritative for App tokens. Add explicit guidance: installation tokens
  cannot call `GET /user`, so `gh auth status` reports "invalid" even when the
  token works; the agent must NOT self-block on it. Repo `gh` ops MUST pass
  `-R owner/repo` (or prefer the `github_*` tools).
- **RED test:** a prompt-content assertion (the cc prompt builder is unit-tested
  elsewhere — find the pattern) that the guidance string is present. Use a
  paren-safe substring (per Sharp Edge on CI sentinels) that spans no punctuation
  boundary.

### 4b — Wire the existing server-side GitHub MCP tools into the Concierge path

- Today `cc-dispatcher.ts:1159` passes `mcpServers: readCcMcpAllowlist()` which
  returns `{}` (Phase-1 deny-by-default). The legacy runner builds
  `buildGithubTools({ installationId, owner, repo, defaultBranch, workspacePath,
  workflowRateLimiter })` and registers them as `mcp__soleur_platform__github_*`.
  **Wire the read-tools (and push/PR per CPO sign-off) into the cc path** so the
  Concierge can `github_read_issue` / `github_read_pr` (resolve owner/repo
  server-side, no sandbox network), `github_push_branch`, `create_pull_request`.
  - owner/repo/defaultBranch/installationId come from the Phase-0.3 resolver —
    **generic per-user**, never hardcoded.
  - This crosses tool-tier/permission surfaces (`tool-tiers.ts`,
    `permission-callback.ts`). **Verify** that adding these tools to the cc path
    respects the existing tier-gating (push/PR are review-gated;
    `github_push_branch` already requires founder approval via canUseTool).
    Read `tool-tiers.ts` `TOOL_TIER_MAP` scope before extending (Sharp Edge:
    maps are usually prefix-scoped).
  - **`CC_PATH_DISALLOWED_TOOLS`** currently hard-blocks `Edit`/`Write` (not
    Bash). MCP tools are not in that list — confirm wiring them does not require
    changing `allowedTools`/`disallowedTools` semantics.
- **RED tests:** the cc factory registers the `github_*` tool names when a repo
  is connected (`installationId !== null`); registers NONE when not connected;
  and the tools are absent from the legacy-only surfaces. Reuse the
  `agent-runner-query-options.test.ts` drift-guard pattern. **Add any new dep to
  BOTH cold-start mock files.**

> **CPO sign-off gate (`requires_cpo_signoff: true`):** wiring write-capable
> tools (`github_push_branch`, `create_pull_request`) into the Concierge path is
> a single-user-incident-threshold change (a misrouted owner/repo = cross-tenant
> push). The Phase-0.3 resolver MUST be the membership-checked one; an
> AskUserQuestion or explicit CPO ack is required before /work wires the
> write tools. The read tools (`github_read_issue/pr/comments`,
> `github_read_ci_status`, `github_read_workflow_logs`) are lower-risk and may
> proceed; write tools gate on sign-off.

---

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **Phase 0.1 sandbox-network spike outcome recorded in PR body** (Outcome A
      or B) with the evidence (source read or probe exit code). The chosen
      Phase 1 branch matches the outcome.
- [ ] **Item 1 (Phase 1):** under Outcome A, `buildAgentEnv` injects
      `GIT_ASKPASS` + `GIT_USERNAME=x-access-token` + `GIT_INSTALLATION_TOKEN` +
      `GIT_TERMINAL_PROMPT=0`; token absent from every other env key and from
      argv; absent entirely when no token. Under Outcome B, no askpass env is
      wired and the `agent-env.ts` GH_TOKEN comment documents both the `/user`
      limitation and the sandbox-network constraint. (vitest)
- [ ] **Token never persisted into `.git/config`** remote URL after a
      credentialed op (asserted by test under Outcome A; N/A under Outcome B).
- [ ] **Item 2 (ensure-repo):** all 6 RED tests pass — detect-and-clone,
      origin-mismatch repair, already-cloned no-op, not-connected no-op,
      failure→Sentry+graceful, token-never-logged. (vitest)
- [ ] **Item 2 wired** into the cold dispatch path (factory or `dispatchSoleurGo`),
      runs once per cold conversation, and is mocked in BOTH
      `cc-dispatcher-real-factory.test.ts` and `cc-dispatcher-prefill-guard.test.ts`.
- [ ] **Item 3:** `repo_status` is `ready` on clone success and `error` on
      failure (already true — confirmed by test or by explicit "no change
      needed" note in PR body per Phase 0.4); cross-reference comment added at
      `repo/setup/route.ts:165`.
- [ ] **Item 4a:** the Concierge system prompt contains guidance NOT to gate on
      `gh auth status` for App tokens and to use `-R owner/repo`. (prompt test)
- [ ] **Item 4b:** the cc factory registers `github_*` read tools when a repo is
      connected and none when not connected; owner/repo derived from the
      membership-checked Phase-0.3 resolver (never hardcoded). Write tools
      (`github_push_branch`, `create_pull_request`) wired ONLY after CPO sign-off.
      (vitest)
- [ ] **Generic per-user/repo:** `git grep -n "jikig-ai\|jikigai/soleur" apps/web-platform/server`
      shows NO new hardcoded repo introduced by this PR.
- [ ] **Token never logged:** `git grep -n "GIT_INSTALLATION_TOKEN\|ghToken\|installation.*token" apps/web-platform/server`
      shows no `log.*\(.*token` / `console` / Sentry-extra carrying the token value.
- [ ] `./node_modules/.bin/vitest run` green for all new + touched suites;
      `npx tsc --noEmit` clean (catches discriminated-union / exhaustiveness rails).
- [ ] PR body uses `Ref` (not `Closes`) for #4826 — #4826 is the symptom trigger,
      not resolved by this PR.

### Post-merge (operator)

- [ ] None expected. The `/workspaces` self-heal (item 2) runs automatically on
      the next Concierge conversation for every affected user — the fix is in the
      dispatch path; there is no manual step. **Automation: fully in-band.** A
      deploy-time verify, if wanted, is a read-only Sentry check that the
      `ensure-workspace-repo` op fires — no SSH.

## Test Scenarios (TDD order — RED before GREEN, `cq-write-failing-tests-before`)

1. `test/ensure-workspace-repo.test.ts` (item 2 — write FIRST; highest leverage).
2. `test/agent-env-git-askpass.test.ts` (item 1, Outcome A only).
3. Concierge-prompt guidance test (item 4a).
4. cc-factory github-tools registration test (item 4b).
5. Update `cc-dispatcher-real-factory.test.ts` + `cc-dispatcher-prefill-guard.test.ts`
   mocks for every new cold-path dep (sweep `grep -rln realSdkQueryFactory test/`).

## Logically-separated commits (one worktree, per ARGUMENTS)

1. `test+feat: session-start ensure-repo self-heal (item 2)` — module + tests + wire + both mock files.
2. `test+feat: in-sandbox git credentialing OR document constraint (item 1)` — Phase-0-gated branch.
3. `fix: clone-on-connect completion signal + cross-ref comment (item 3)`.
4. `feat: Concierge stops gating on gh auth status + wires server-side github_* tools (item 4)`.

(Adjust ordering so contract-changing edits precede consumers per
`2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md`:
`buildAgentEnv` signature change (item 1) before its cc-dispatcher consumer;
ensure-repo module before its wire-in.)

## Risks & Mitigations

- **Sandbox blocks github.com (Outcome B).** Highest-probability risk; the whole
  "raw git in sandbox" framing collapses if true. Phase 0.1 spike resolves it
  BEFORE any code. Mitigation: server-side MCP tools (Phase 4b) + server-side
  ensure-repo (Phase 2) work regardless of sandbox network.
- **Cross-tenant clone (brand-survival).** ensure-repo or github-tools resolving
  owner/repo or installationId from anything other than the requesting user's
  membership-checked active workspace = cross-tenant breach. Mitigation: reuse
  `resolveInstallationId` (ADR-044 RPC) + the legacy owner/repo resolver
  verbatim; AC greps for hardcoded repos; CPO sign-off on write-tool wiring.
- **Token leak via `.git/config` / logs / transcript.** Mitigation: GIT_ASKPASS
  (token in env, never in URL); AC greps; ensure-repo reuses
  `gitWithInstallationAuth` (which already uses askpass, not URL creds).
- **Cold-start suite breakage.** New cold-path deps not mocked in BOTH files →
  import-time throw. Mitigation: Phase 0.5 sweep + explicit AC.
- **ensure-repo on every turn (latency).** Mitigation: gate to cold dispatch
  (factory), cheap disk-check early-return on already-cloned.
- **Precedent diff (deepen-plan Phase 4.4):** ensure-repo's clone/repair must
  mirror `provisionWorkspaceWithRepo` + `git-auth.ts` patterns (no URL-embedded
  creds, GIT_ASKPASS, identity set). Diff against those precedents.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. (This plan fills it: single-user incident.)
- The sandbox network policy (`allowedDomains: []` + `allowManagedDomainsOnly:
  true`) is the load-bearing constraint; do NOT assume a GIT_ASKPASS helper makes
  `git push` work in-sandbox — verify network reachability first (Phase 0.1).
- The push/PR/issue-read capability already exists server-side
  (`github-tools.ts`); the cc path just doesn't register it (`readCcMcpAllowlist()
  → {}`). Do NOT re-implement a raw-git push path when a server-side tool exists.
- `repo/setup/route.ts:165` is "fire-and-forget" only for the HTTP response; it
  DOES write `repo_status` and mirror failures. Do NOT "add missing error
  handling" — it exists. Item 3 is about an observable completion signal item 2
  can read.
- Any new module in the factory `Promise.all` must be `vi.mock`'d in BOTH
  `cc-dispatcher-real-factory.test.ts` AND `cc-dispatcher-prefill-guard.test.ts`.
- Runner is **vitest**, not bun test (`bunfig.toml` blocks bun discovery). New
  test paths must match `vitest.config.ts` `include:` globs.
- `#4826` is the symptom trigger, NOT a work target — use `Ref #4826`, not `Closes`.

## Open Code-Review Overlap

Checked open `code-review` issues against the files this plan edits
(`cc-dispatcher.ts`, `agent-env.ts`, `agent-runner-query-options.ts`,
`workspace.ts`, `repo/setup/route.ts`, `github-tools.ts`, new
`ensure-workspace-repo.ts`). **To be confirmed at /work** via:
`gh issue list --label code-review --state open --json number,title,body --limit 200`
then `jq` per-path. Recorded here so the next planner sees the check is scheduled.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — brand-survival
single-user-incident threshold).

### Engineering (CTO)

**Status:** reviewed (plan-author assessment; deepen-plan will spawn the triad).
**Assessment:** Server-side plumbing change. The load-bearing architectural
decision (in-sandbox git vs. server-side MCP tools) is gated on the Phase 0.1
spike. Reuse of `gitWithInstallationAuth`, `provisionWorkspaceWithRepo`,
`resolveInstallationId` (ADR-044), and `buildGithubTools` keeps the blast radius
contained to wiring + one new self-heal module. No new infrastructure, no
migration (Phase 0.4 confirms). Mirrors `cq-silent-fallback-must-mirror-to-sentry`
and `hr-github-app-auth-not-pat`.

### Product/UX Gate

**Tier:** none (server plumbing; no UI surface in `## Files to Edit`).
**Decision:** auto-accepted (pipeline) — no `components/**`, `app/**/page.tsx`,
or `app/**/layout.tsx` files. `wg-ui-feature-requires-pen-wireframe` does not
fire (no UI surface). **CPO sign-off** is required per `requires_cpo_signoff:
true` for the WRITE-tool wiring (Phase 4b) — not a UI gate, a brand-survival gate.

#### Findings

No UI changes. Brand-survival concern is the cross-tenant clone/push vector,
handled via membership-checked resolvers + CPO sign-off on write-tool wiring +
`user-impact-reviewer` at review time.

## Infrastructure (IaC)

No new infrastructure (no server, service, secret, vendor, DNS, cron, or runtime
process). Pure code change against already-provisioned surfaces
(`apps/web-platform/server/`, `apps/web-platform/app/api/`). Phase 2.8 skip
conditions met. The plan introduces ZERO out-of-band / manual steps — the
self-heal (item 2) runs automatically in the dispatch path; the "re-provision"
mention is the thing this plan ELIMINATES, not a step it adds.

## Observability

```yaml
liveness_signal:
  what: "ensure-workspace-repo op fires on cold Concierge dispatch (clone/repair/no-op)"
  cadence: "per cold conversation"
  alert_target: "Sentry feature:ensure-workspace-repo op:clone error rate"
  configured_in: "reportSilentFallback in ensure-workspace-repo.ts + existing repo-setup mirror"
error_reporting:
  destination: "Sentry via reportSilentFallback (pino + Sentry), feature-tagged"
  fail_loud: "clone failure mirrors to Sentry then graceful-degrades the conversation (never silent, never crash)"
failure_modes:
  - mode: "clone/repair fails (network, access revoked, token mint)"
    detection: "reportSilentFallback feature:ensure-workspace-repo op:clone"
    alert_route: "Sentry"
  - mode: "GH_TOKEN mint fails (Outcome A askpass + gh)"
    detection: "existing reportSilentFallback feature:cc-dispatcher op:mint-gh-token"
    alert_route: "Sentry"
  - mode: "owner/repo resolves to wrong/empty repo (cross-tenant guard)"
    detection: "github_* tool error response + canUseTool review-gate; resolver returns null for non-members"
    alert_route: "Sentry + tool isError"
logs:
  where: "pino child loggers (cc-dispatcher, ensure-workspace-repo, push-branch); token NEVER logged"
  retention: "per existing log pipeline"
discoverability_test:
  command: "./node_modules/.bin/vitest run test/ensure-workspace-repo.test.ts && git grep -n 'feature: \"ensure-workspace-repo\"' apps/web-platform/server"
  expected_output: "tests green; Sentry mirror call site present (NO ssh)"
```

## Files to Edit

- `apps/web-platform/server/agent-env.ts` — (Outcome A) extend
  `BuildAgentEnvOptions` + inject `GIT_ASKPASS`/`GIT_USERNAME`/
  `GIT_INSTALLATION_TOKEN`/`GIT_TERMINAL_PROMPT`; (always) add the
  installation-token `/user`-limitation + sandbox-network comment at the
  `GH_TOKEN` site.
- `apps/web-platform/server/agent-runner-query-options.ts` — thread askpass
  inputs through to `buildAgentEnv` (Outcome A).
- `apps/web-platform/server/cc-dispatcher.ts` — call `ensureWorkspaceRepoCloned`
  on cold dispatch; pass askpass inputs (Outcome A); wire `github_*` tools into
  `mcpServers` for the cc path when a repo is connected (item 4b).
- `apps/web-platform/server/git-auth.ts` — possibly export a sandbox-path
  variant of `writeAskpassScript` (Outcome A, Phase 0.2 path).
- `apps/web-platform/app/api/repo/setup/route.ts` — cross-ref comment at `:165`;
  confirm `repo_status` arms (item 3).
- The cc-soleur-go system-prompt builder (`buildSoleurGoSystemPrompt` — locate
  at /work) — gh-auth-status guidance + `-R owner/repo` (item 4a).
- `apps/web-platform/test/cc-dispatcher-real-factory.test.ts` — add mocks for
  every new cold-path dep.
- `apps/web-platform/test/cc-dispatcher-prefill-guard.test.ts` — same mock adds.

## Files to Create

- `apps/web-platform/server/ensure-workspace-repo.ts` — the self-heal module (item 2).
- `apps/web-platform/test/ensure-workspace-repo.test.ts` — item 2 RED tests.
- `apps/web-platform/test/agent-env-git-askpass.test.ts` — item 1 (Outcome A) RED tests.
- (Possibly) `apps/web-platform/test/cc-github-tools-wiring.test.ts` — item 4b.

## GDPR / Compliance

Trigger (b) fires: brand-survival threshold `single-user incident`. No new
regulated-data schema/migration/auth surface; the installation token is an
existing processed credential (PR #4868). The cross-tenant clone vector is the
relevant compliance surface — handled by membership-checked resolvers. Invoke
`/soleur:gdpr-gate` at /work if the ensure-repo path touches any new
data-movement surface; otherwise advisory-only. No Art. 9 special-category data.
