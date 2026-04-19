# SDK Probe Notes — Phase 1 findings (2026-04-19)

**Purpose:** Resolve Kieran plan-review C1 + C2 before committing to the Phase 2+ harness shape.

**SDK version inspected:** `@anthropic-ai/claude-agent-sdk@0.2.85` (from `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/package.json`).

---

## Question 1 — Is there a deterministic SDK tool-invocation entry?

**Answer: No.**

All exported entry points in `sdk.d.ts` route tool execution through an LLM-mediated query:

- `query()` — streaming agent query; tool calls are LLM-decided.
- `unstable_v2_prompt()`, `unstable_v2_createSession()`, `unstable_v2_resumeSession()` — session-scoped variants, still LLM-mediated.
- `tool()` — defines a new MCP tool, not an invocation API.
- `createSdkMcpServer()` — registers user MCP servers.
- Session helpers (`forkSession`, `listSessions`, `getSessionInfo`, `getSessionMessages`, `renameSession`, `tagSession`).

There is no `runTool(name, input)` or direct Bash/Read/LS invocation surface. Built-in tool names (Bash, Read, Write, Edit, LS, Glob, Grep, NotebookRead, NotebookEdit, Task) are addressable via `tools: string[]` / `allowedTools: string[]` / `disallowedTools: string[]` for *gating*, but not for direct *invocation*.

**Option (a) from the plan (SDK direct tool entry) is eliminated.**

## Question 2 — Under `permissionMode: "bypassPermissions"` + no PreToolUse hooks, does bwrap still apply our `sandbox.filesystem.allowWrite` / `denyRead` restrictions?

**Answer: Uncertain — and the SDK docs suggest not.**

`sdk.d.ts:1180-1186` states:

> **Important:** Filesystem and network restrictions are configured via permission rules, not via these sandbox settings:
>
> - Filesystem access: Use `Read` and `Edit` permission rules
> - Network access: Use `WebFetch` permission rules
>
> These sandbox settings control sandbox behavior (enabled, auto-allow, etc.), while the actual access restrictions come from your permission configuration.

And `sdk.d.ts:3614` describes `sandbox.filesystem.allowWrite` as "Additional paths to allow writing within the sandbox. Merged with paths from `Edit(...)` allow permission rules."

The plan's architecture assumed `bypassPermissions` disables tier 3 (canUseTool) while leaving tier 4 (bwrap) intact. The docs suggest that bwrap's filesystem restrictions are *primarily* derived from permission rules (Read / Edit allow/deny) and that `sandbox.filesystem.*` is additive. If `bypassPermissions` strips the permission-rule-derived mounts, the resulting bwrap invocation could have *looser* restrictions than production — potentially no `--ro-bind` for `/workspaces` at all.

**This contradicts the plan's tier-isolation design.** An empirical probe is required before committing to any `query()`-based tier-4 assertion, and even then the test would be exercising a bwrap configuration unlike production.

## Question 3 — Do structured-path tools (LS, NotebookRead) have internal validators?

**Answer: Cannot determine without runtime instrumentation.** Tool input schemas in `sdk-tools.d.ts` are JSON-schema-shape descriptors for input validation (type / required / format), not security validators. Whether an LS call with `path: "/workspaces/other-tenant"` is rejected at tool-entry (before bwrap) vs. passed through to OS-level syscall depends on SDK-internal routing, which is closed-source. The defense-in-depth learning `2026-03-20-canuse-tool-sandbox-defense-in-depth.md` names LS and NotebookRead as tier-3 (`canUseTool` + `isPathInWorkspace`) defenders, implying tool-internal validation is minimal-to-none.

## Question 4 — `allowDangerouslySkipPermissions`

The plan's scaffolding missed a required SDK option: `permissionMode: "bypassPermissions"` requires `allowDangerouslySkipPermissions: true` (per `sdk.d.ts:1108`). Without this, the SDK rejects `bypassPermissions` at startup.

## Question 5 — Production config comparison

`apps/web-platform/server/agent-runner.ts:719-787` uses:

- `permissionMode: "default"` (NOT `bypassPermissions`)
- `disallowedTools: ["WebSearch", "WebFetch"]`
- `allowedTools: [...]` (MCP tools only, built-ins not listed)
- `sandbox: { enabled: true, filesystem: { allowWrite: [workspacePath], denyRead: ["/workspaces", "/proc"] } }`
- `hooks.PreToolUse` with `createSandboxHook(workspacePath)` matching `Read|Write|Edit|Glob|Grep|LS|NotebookRead|NotebookEdit|Bash`
- canUseTool callback (comment at line 788-789)

Production relies on **all four tiers active** for defense-in-depth. Disabling any in test changes the bwrap configuration fed to the SDK — we wouldn't be testing production bwrap.

---

## Recommended path: REVISE the plan

The plan's original assumption — that `bypassPermissions` gives us a clean tier-4-only test environment — is at best uncertain and at worst incorrect. Two viable alternatives, each with tradeoffs:

### Path A — Direct `spawn("bwrap", argv, ...)` (deterministic, SDK-independent)

- Tests use `child_process.spawn` to invoke `bwrap` directly with argv that matches SDK's *production* mount configuration (derived from reading the SDK's bwrap argv via strace/instrumentation in one capture pass).
- Fully deterministic. No LLM in the loop. No API key needed for most cases.
- Tests what matters: "does bwrap with these mounts isolate workspaces."
- **Weakness:** Does not prove the SDK actually invokes bwrap with these argv in production — our captured argv could drift from SDK's if the SDK changes.
- **Mitigation:** Re-capture argv on every SDK minor bump (pin SDK version; add argv-capture task to dependabot PR review checklist).

### Path B — `query()` with production config + `permissionMode: "default"` + hooks active (tests full stack)

- Tests use the same SDK config as production: hooks + canUseTool + bwrap all active.
- A green test proves **the system** (all four tiers together) isolates workspaces — which is what MU3 actually cares about.
- Does not isolate tier 4 from tiers 1-3. A failing test doesn't say *which* tier broke.
- **Non-determinism:** LLM still chooses whether to execute the attack. Mitigation: retry on ambiguous outputs, accept some flake rate, mark cases with low retry count.
- **Acceptance caveat:** Plan's AC5 ("top-of-file comment names tier-4 isolation rationale") becomes a rationale about the full stack, not bwrap alone.

### Path C — Hybrid (recommended)

- **Majority of cases (FR2, FR3, FR4, FR5, FR7, FR10, FR11):** Path A direct bwrap spawn. Deterministic, fast, proves OS isolation.
- **FR8, FR9 (shared `/tmp`, session files):** Path B real `query()` with production-equivalent config. These are SDK-specific artifacts — direct bwrap argv wouldn't exercise them.
- **SDK integration smoke (NEW case):** one `query()` call per suite run proving the SDK still invokes bwrap. Can reuse existing `assert_bwrap_canary_check` pattern.

**Path C replaces the plan's "pick one invocation" with "pick the right invocation per case." Total harness complexity lower than original plan because most cases skip the LLM entirely.**

## Actions required before Phase 2

1. **Founder review of this file.** The plan's tier-isolation design assumed a simpler SDK contract than exists. Confirm Path A / B / C preference.
2. **If Path A or C:** add a one-time "capture bwrap argv from SDK" step. Instrument `child_process.spawn` via a preload script, run `query()` once with production-equivalent sandbox config, record the argv. Commit capture notes here.
3. **If Path B or C:** add explicit retry-and-flake-tolerance policy for query()-based cases. Document acceptable retry count and how to distinguish flake from real failure.
4. **Plan edit.** Amend the plan's Phase 2-8 scaffolding to match chosen path. Research Reconciliation table gets a new row about tier-4 isolation not being achievable via `bypassPermissions` alone.
5. **Update spec TR4 and FR14.** Remove references to `permissionMode: "bypassPermissions"` as the tier-isolation primitive. Either: (a) name direct-spawn as the tier-4 isolation mechanism, or (b) drop the "isolate tier 4" framing and frame the suite as "prove system-level isolation" (Path B).

## Question 6 — ANTHROPIC_API_KEY availability

- Not verified this session (blocked on deciding whether API key is needed per Path choice).
- If Path A selected: only needed for FR8/FR9 and one smoke case.
- If Path B or C: needed for multiple cases.
- `gh secret list --repo jikig-ai/soleur | grep -i anthropic` to confirm CI availability (defer until path chosen).

---

## Captured bwrap argv structure (2026-04-19, from SDK source reverse-engineering)

**Method:** Grepped `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/cli.js` (minified bundle, 12.9MB) for bwrap-related flags and extracted the argv-construction function (`ou_`) via Python brace-matching. Source-only — no live `query()` run yet.

### Base argv (always present when sandbox.enabled=true)

```text
bwrap --new-session --die-with-parent
      --dev /dev
      --unshare-pid
      [--proc /proc]                       # SKIPPED when enableWeakerNestedSandbox=true (our prod config)
      [--unshare-net]                      # when network sandboxed
      [--bind <http-bridge> <same>]        # when network sandboxed + bridges exist
      [--bind <socks-bridge> <same>]
      [--setenv HTTP_PROXY ... SOCKS_PROXY ...]
      -- <shell> -c "<command>"
```

Note: **no `--unshare-user`.** The SDK does NOT create a new user namespace. Files are accessed as the invoking user (same UID inside/outside the sandbox). This has implications for root-owned file cleanup (noted in plan risks).

### Filesystem bind construction (`ou_` function)

The filesystem portion of argv is assembled by an async helper `ou_(q, K, ...)` where:

- **`K`** = sandbox.filesystem config (our `allowWrite` → `K.allowOnly`).
- **`q`** = permission-rule-derived filesystem rules (our `sandbox.filesystem.denyRead` merges here as `q.denyOnly`; permission rules from Read/Edit allow/deny also merge here).

Argv assembly order when `K` is present:

1. `--ro-bind / /` — mount entire host read-only
2. For each `allowOnly` path (our `allowWrite: [workspacePath]`):
   - `fs.realpathSync`, symlink-outside check, non-existent skip
   - Push `--bind <path> <path>` (writable)
   - Track in internal `j` (allowed set)
3. For each `denyWithinAllow` / auto-derived deny:
   - If path is a symlink pointing outside allowed set: `--ro-bind /dev/null <symlink-path>` (symlink-replacement-attack guard — a comment in the bundle explicitly names this)
   - If path doesn't exist but ancestor is allowed: mount empty tempdir or `/dev/null` to block creation
   - Else `--ro-bind <path> <path>` (read-only overlay in writable region)

Then processing `q.denyOnly` (OUR `denyRead` lands here):

4. For each denyOnly path `H`:
   - If `H` is a directory: `--tmpfs <H>` (replace with empty tmpfs)
   - Then for each `allowWithinDeny` (OUR `allowRead`) `X` starting with `H+"/"`: `--ro-bind <X> <X>` (re-allow within denied region)
   - If `H` is a file: `--ro-bind /dev/null <H>` (hide file)
   - If `H` is re-allowed: skip

### The ordering mystery

With our production config (`allowWrite: [workspacePath]`, `denyRead: ["/workspaces", "/proc"]`, no `allowRead`), the argv order is:

```text
--ro-bind / /
--bind /workspaces/<uuid> /workspaces/<uuid>     (from allowWrite)
--tmpfs /workspaces                              (from denyRead, since /workspaces is a directory)
--tmpfs /proc                                    (from denyRead — but /proc already absent due to enableWeakerNestedSandbox)
--dev /dev
--unshare-pid
-- bash -c ...
```

The `--tmpfs /workspaces` comes AFTER `--bind /workspaces/<uuid>`. In bwrap, a later `--tmpfs` on a parent directory typically **shadows** earlier bind mounts of children — meaning the workspace-owner's writable bind would be hidden by the tmpfs.

**Yet production works.** The agent CAN write to its own workspace. So either:

- bwrap's order-of-operations is different from my reading (later parent mounts don't shadow earlier child binds),
- the SDK reorders argv before spawning (some subsequent post-processing in `cli.js` I haven't found),
- our production config includes a matching `allowRead: [workspacePath]` (or permission-rule-derived equivalent) I haven't traced, OR
- `denyRead: ["/workspaces"]` is NOT actually passing through to `q.denyOnly` as I traced — it may be filtered out when it overlaps with an allowWrite.

**This is the mystery that Phase 2A empirical capture must resolve.** Constructing direct-spawn argv from the traced structure without confirming order would produce tests that behave differently from production bwrap.

### Recommendation (revised for Phase 2A)

Before constructing `spawnBwrap()` argv for Phase 3+, do a one-time live capture via one of:

- **Preferred:** `strace -f -e trace=execve -s 8192 -o /tmp/strace.out node --require spawn-capture.js capture-bwrap-argv.js` — captures execve in the SDK's child process.
- **Alternative:** monkey-patch `child_process.spawn` in the CLI subprocess via `NODE_OPTIONS=--require ./spawn-capture.js`.
- **Cheapest:** run `query()` under `strace -p $(pgrep -f 'node.*claude-agent-sdk') -e trace=execve -f` attached externally after first few messages.

Output: the **actual argv bwrap received in production config**. Compare to the traced structure above. If they match, plan Phase 3+ `spawnBwrap()` can template on it. If they diverge, document the divergence and either (a) update traced structure, (b) fall back to Path B (full-stack `query()` for all cases).

### Open follow-up action

Phase 2A (as documented in plan and tasks.md) is unchanged in spirit but now has a specific goal: **verify the traced argv order against real execve, document the resolution of the tmpfs/bind ordering mystery, then template spawnBwrap() on the confirmed argv.**

---

**Status:** Phase 1 extended. SDK source reverse-engineered; argv structure captured; one ordering question remains. Next concrete step: Phase 2A empirical capture. Handing back for founder review — specifically whether to invest in the empirical capture now, or pivot to Path B (full-stack query() for all cases, sidestepping the argv-ordering question entirely).
