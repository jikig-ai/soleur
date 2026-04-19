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

**Status:** Phase 1 spike complete. STOPPING at phase boundary per founder instruction. Waiting on path decision before Phase 2 code lands.
