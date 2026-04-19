# sec: set sandbox.failIfUnavailable=true in production agent-runner.ts

**Issue:** [#2634](https://github.com/jikig-ai/soleur/issues/2634)
**Priority:** P1
**Type:** security hardening
**Detail level:** MINIMAL (≤3 line config change + 1 Dockerfile comment + 1 regression test)

## Enhancement Summary

**Deepened on:** 2026-04-19
**Sections enhanced:** Test sketch (corrected entry-point name), Implementation (reuse existing mock helper), Research Insights (exact SDK error strings).

### Key Improvements

1. **Test entry-point correction.** The initial plan referenced `runAgent(...)` — which does not exist. Actual agent-runner entry is `startAgentSession(userId, conversationId, leaderId, resumeSessionId?, message?, context?, routeSource?, ...)` (confirmed via `grep -n "startAgentSession" apps/web-platform/server/agent-runner.ts`).
2. **Mock-helper reuse.** Discovered `apps/web-platform/test/helpers/agent-runner-mocks.ts` exports `createSupabaseMockImpl`, `createQueryMock`, and `DEFAULT_API_KEY_ROW`. Plan now reuses these instead of duplicating ~60 lines of `vi.mock()` preamble.
3. **SDK error-text confirmation.** The SDK throws the exact strings `"sandbox required but unavailable: <reason>"` and `"refusing to start without a working sandbox"` (confirmed via `grep` against `node_modules/@anthropic-ai/claude-agent-sdk/cli.js`). Useful for any future Sentry matcher, but NOT asserted in the vitest regression (mock-level assertion on the option is more deterministic).

### New Considerations Discovered

- The `apps/web-platform/test/helpers/agent-runner-mocks.ts` helper exists but does NOT currently mock the sandbox block. Keeping the regression test narrow — it only needs the existing mock scaffolding plus a single assertion on `options.sandbox.failIfUnavailable`.
- The `sandbox-isolation.test.ts` file already uses `failIfUnavailable: true` in its test harness config (line 422). The production code path lags the test harness — this PR closes that gap.

## Overview

`apps/web-platform/server/agent-runner.ts` configures the Claude Agent SDK sandbox with `sandbox: { enabled: true, ... }` but does NOT set `sandbox.failIfUnavailable: true`.

Per `@anthropic-ai/claude-agent-sdk@0.2.85`'s `sdk.d.ts:3586-3588`, the default when `enabled=true` and dependencies are missing is a **silent unsandboxed fallback** — the SDK prints a log warning and runs commands directly under `/bin/bash -c ...` with no bwrap wrapping, no filesystem isolation, no network isolation.

This was confirmed empirically during #1450 Phase 1 probing (see `knowledge-base/project/specs/feat-verify-workspace-isolation/sdk-probe-notes.md`): on a dev host with `bubblewrap` installed but `socat` missing, `query()` completed successfully with zero `/usr/bin/bwrap` execve calls in the process tree. The defect only surfaced after adding `failIfUnavailable: true`, which turned the silent fallback into an explicit startup error.

If a future Dockerfile cleanup removes `socat` (or any dependency the SDK's sandbox adds in a minor bump), production agents will silently execute unsandboxed. No Sentry event, no alert, no metric — tier-4 defense-in-depth collapses invisibly.

This plan:

1. Adds `failIfUnavailable: true` to the sandbox config at `agent-runner.ts:748`.
2. Annotates the Dockerfile `apt install bubblewrap socat` line explaining `socat` is load-bearing (not just networking — required for ANY bwrap wrapping because the SDK's argv unconditionally includes socat-backed HTTP/SOCKS bridge scaffolding even when network isolation is configured tight).
3. Adds a vitest regression test that asserts the `mockQuery` call carries `options.sandbox.failIfUnavailable === true` so a future edit that silently drops it fails CI.

## Research Reconciliation — Spec vs. Codebase

The issue body is factually accurate against the codebase (verified 2026-04-19):

| Issue claim | Reality in codebase | Plan response |
| --- | --- | --- |
| `agent-runner.ts:748-764` configures sandbox without `failIfUnavailable` | Confirmed at line 748-764 in current HEAD. `failIfUnavailable` is absent. | Add `failIfUnavailable: true` inside the `sandbox:` object, adjacent to `enabled: true`. |
| SDK default is silent unsandboxed fallback | Confirmed — `sdk.d.ts:3586-3588` and `cli.js` sandbox bootstrap confirm this. | No code drift; fix is valid. |
| Dockerfile line installs `bubblewrap socat` | Confirmed at `apps/web-platform/Dockerfile:39-40`. Comment at line 37 says "(Agent SDK sandbox)" but does not name why `socat` is load-bearing. | Extend comment with explicit load-bearing rationale. |

No scope delta vs. issue.

## Open Code-Review Overlap

None. Ran `jq` against `gh issue list --label code-review --state open --limit 200` for both touched paths (`apps/web-platform/server/agent-runner.ts`, `apps/web-platform/Dockerfile`) — zero matches.

## Files to Edit

- `apps/web-platform/server/agent-runner.ts` — add `failIfUnavailable: true` at line 749 (inside the existing `sandbox:` block, alongside `enabled: true`).
- `apps/web-platform/Dockerfile` — extend the comment at line 37 to explicitly name `socat` as load-bearing for bwrap invocation (not just network bridging).

## Files to Create

- `apps/web-platform/test/agent-runner-sandbox-config.test.ts` — regression test asserting `options.sandbox.failIfUnavailable === true` on the SDK `query()` call. Pattern-matches existing `agent-runner-*.test.ts` files (see `agent-runner-tools.test.ts:164` for `mockQuery.mock.calls[0][0].options` access pattern).

## Implementation

### Change 1 — agent-runner.ts

At the sandbox block (currently lines 748-764), insert `failIfUnavailable: true` immediately after `enabled: true`. Final shape:

```ts
// apps/web-platform/server/agent-runner.ts
sandbox: {
  enabled: true,
  // Refuse to start if sandbox deps (bubblewrap, socat) are missing.
  // Without this, the SDK silently runs unsandboxed on dependency drift
  // (per @anthropic-ai/claude-agent-sdk sdk.d.ts:3586). Tier 4 defense-
  // in-depth disappears without alert. See #2634.
  failIfUnavailable: true,
  autoAllowBashIfSandboxed: true,
  allowUnsandboxedCommands: false,
  // Docker containers cannot mount proc inside user namespaces ...
  enableWeakerNestedSandbox: true,
  network: { ... },
  filesystem: { ... },
},
```

### Change 2 — Dockerfile

At `apps/web-platform/Dockerfile:37`, replace the one-line comment with the load-bearing annotation:

```dockerfile
# Install git (workspace provisioning) + bubblewrap/socat (Agent SDK sandbox)
# ca-certificates: required for git HTTPS clone -- node:22-slim omits it (#1645)
#
# IMPORTANT: `socat` is load-bearing for the Agent SDK sandbox. The SDK's
# bwrap argv unconditionally includes socat-backed HTTP/SOCKS bridge listeners
# in the sandbox shell script (captured 2026-04-19 via strace) -- so without
# socat, `sandbox.failIfUnavailable: true` (agent-runner.ts) refuses to start
# the agent. Do NOT remove socat in future cleanups. See #2634.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git bubblewrap socat qpdf \
    && rm -rf /var/lib/apt/lists/*
```

### Change 3 — regression test

Create `apps/web-platform/test/agent-runner-sandbox-config.test.ts` following the exact pattern of `apps/web-platform/test/agent-runner-tools.test.ts` and reusing helpers from `apps/web-platform/test/helpers/agent-runner-mocks.ts`:

```ts
// apps/web-platform/test/agent-runner-sandbox-config.test.ts
import { vi, describe, test, expect, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";

const { mockFrom, mockQuery, mockReadFileSync } = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockQuery: vi.fn(),
  mockReadFileSync: vi.fn(),
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: mockQuery,
  tool: vi.fn((_n: string, _d: string, _s: unknown, h: Function) => ({ name: _n, handler: h })),
  createSdkMcpServer: vi.fn((opts: { name: string; tools: unknown[] }) => ({
    type: "sdk", name: opts.name, instance: { tools: opts.tools },
  })),
}));
vi.mock("fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("fs")>();
  return { ...actual, readFileSync: mockReadFileSync };
});
vi.mock("@supabase/supabase-js", () => ({ createClient: vi.fn(() => ({ from: mockFrom })) }));
vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));
vi.mock("../server/ws-handler", () => ({ sendToClient: vi.fn() }));
vi.mock("../server/logger", () => ({
  createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }),
}));
vi.mock("../server/byok", () => ({
  decryptKey: vi.fn(() => "sk-test-key"),
  decryptKeyLegacy: vi.fn(),
  encryptKey: vi.fn(),
}));
vi.mock("../server/error-sanitizer", () => ({
  sanitizeErrorForClient: vi.fn(() => "error"),
}));
vi.mock("../server/sandbox", () => ({ isPathInWorkspace: vi.fn(() => true) }));
vi.mock("../server/tool-path-checker", () => ({
  UNVERIFIED_PARAM_TOOLS: [], extractToolPath: vi.fn(),
  isFileTool: vi.fn(() => false), isSafeTool: vi.fn(() => false),
}));
vi.mock("../server/agent-env", () => ({ buildAgentEnv: vi.fn(() => ({})) }));
vi.mock("../server/sandbox-hook", () => ({ createSandboxHook: vi.fn(() => vi.fn()) }));
vi.mock("../server/review-gate", () => ({
  abortableReviewGate: vi.fn().mockResolvedValue("Approve"),
  validateSelection: vi.fn(), extractReviewGateInput: vi.fn(),
  buildReviewGateResponse: vi.fn(),
  MAX_SELECTION_LENGTH: 200, REVIEW_GATE_TIMEOUT_MS: 300_000,
}));
vi.mock("../server/domain-leaders", () => {
  const leaders = [{ id: "cpo", name: "CPO", title: "Chief Product Officer", description: "Product" }];
  return { DOMAIN_LEADERS: leaders, ROUTABLE_DOMAIN_LEADERS: leaders };
});
vi.mock("../server/domain-router", () => ({ routeMessage: vi.fn() }));
vi.mock("../server/session-sync", () => ({ syncPull: vi.fn(), syncPush: vi.fn() }));
vi.mock("../server/github-api", () => ({
  githubApiGet: vi.fn().mockResolvedValue({ default_branch: "main" }),
  githubApiGetText: vi.fn().mockResolvedValue(""),
  githubApiPost: vi.fn().mockResolvedValue(null),
}));
vi.mock("../server/service-tools", () => ({
  plausibleCreateSite: vi.fn(), plausibleAddGoal: vi.fn(), plausibleGetStats: vi.fn(),
}));
vi.mock("../server/observability", () => ({
  reportSilentFallback: vi.fn(), reportSilentFallbackWarning: vi.fn(),
}));

import { startAgentSession } from "../server/agent-runner";
import { createSupabaseMockImpl, createQueryMock } from "./helpers/agent-runner-mocks";

describe("agent-runner sandbox hardening (#2634)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockReadFileSync.mockImplementation(() => JSON.stringify({ mcpServers: {} }));
    createSupabaseMockImpl(mockFrom, {
      userData: {
        workspace_path: "/tmp/test-workspace",
        repo_status: null,
        github_installation_id: null,
        repo_url: null,
      },
    });
    createQueryMock(mockQuery);
  });

  test("passes sandbox.failIfUnavailable=true to SDK query()", async () => {
    await startAgentSession("user-1", "conv-1", "cpo");

    expect(mockQuery).toHaveBeenCalledOnce();
    const options = mockQuery.mock.calls[0][0].options;
    expect(options.sandbox).toBeDefined();
    expect(options.sandbox.enabled).toBe(true);
    // Core invariant — if this silently flips to false/undefined,
    // the SDK falls back to unsandboxed execution (see #2634).
    expect(options.sandbox.failIfUnavailable).toBe(true);
  });
});
```

Per `cq-mutation-assertions-pin-exact-post-state`, the invariant is asserted with `.toBe(true)` — not `toBeTruthy()` — so a silent flip to `undefined` fails the test deterministically.

**Entry point:** `startAgentSession(userId, conversationId, leaderId, ...)` is the production entry (confirmed at `apps/web-platform/server/agent-runner.ts:377`). It is the function that eventually calls the SDK `query({ prompt, options: { sandbox: ... } })`. Existing tests at `agent-runner-tools.test.ts:161` use the same call shape; this test inherits that pattern.

**Helper reuse:** `createSupabaseMockImpl` and `createQueryMock` live in `apps/web-platform/test/helpers/agent-runner-mocks.ts` and set up the chainable Supabase mock + immediate-return query mock. No new helper needed.

## Test Strategy

**Unit test (above):** vitest mock-based assertion on the SDK `query()` argument. Runs in-process, deterministic, no sandbox host required. This is the primary CI regression guard for the config.

**Manual smoke (local, one-time):** cannot be automated in CI without a test image that deliberately removes socat. Deferred to future work if dependency-drift resistance is desired beyond the unit assertion — the AC is satisfied by the unit test.

**Why NOT a dockerized integration test in this PR:** building a socat-less variant of the production image, running it, and asserting startup failure costs ~3-4 minutes per CI run for a single boolean invariant already asserted at the config-shape level. Unit test + Dockerfile comment are sufficient. If we later see socat drift slip past the unit test via a different code path, file a follow-up to add a container-level regression.

**Invariant covered by the unit test:** `agent-runner.ts` MUST pass `failIfUnavailable: true` to SDK `query()`. A future edit that removes or flips this flag fails CI immediately.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/server/agent-runner.ts` sandbox config includes `failIfUnavailable: true` inside the `sandbox:` block (adjacent to `enabled: true`).
- [ ] `apps/web-platform/Dockerfile` line installing `bubblewrap socat` has a comment block explicitly stating `socat` is load-bearing for bwrap wrapping (not just networking) and referencing #2634.
- [ ] `apps/web-platform/test/agent-runner-sandbox-config.test.ts` exists, asserts `options.sandbox.failIfUnavailable === true` with `.toBe(true)`, passes locally via `cd apps/web-platform && ./node_modules/.bin/vitest run test/agent-runner-sandbox-config.test.ts`.
- [ ] All existing agent-runner tests still pass (regression check).

### Post-merge (operator)

- [ ] Verify next production deploy succeeds (sandbox deps are installed, startup does not throw). Observability: Sentry should NOT receive a "sandbox required but unavailable" error. If it does, the deploy is broken and must be rolled back — this is the new fail-loud behavior working as intended.
- [ ] No follow-up infrastructure changes. The Dockerfile already installs both deps; this change only surfaces their absence as a hard error.

## Risks & Mitigations

**Risk 1: startup breakage if Dockerfile drift already present.**

If the production image somehow shipped without socat at merge time (unlikely — the apt install line is present at `Dockerfile:40` in HEAD), every new agent session would throw at startup. Mitigation: the pre-merge AC includes a deploy-verification step. Sentry coverage on the agent-runner bootstrap path catches this within the first session post-deploy; operator rolls back and installs socat before re-deploying.

**Risk 2: false positives from transient dependency unavailability.**

`failIfUnavailable: true` applies at process startup. It does not re-probe between sessions. If socat is removed on a running container, existing sessions continue; the next startup fails. This is acceptable — the failure mode we're preventing (silent post-drift fallback) is worse than occasional startup restarts.

**Risk 3: test file duplicates vi.mock() preamble.**

The new test still inherits the ~50-line `vi.mock()` block from `agent-runner-tools.test.ts` (vitest hoists `vi.mock` to the top of the file, so each test file needs its own declarations). The expensive Supabase/query mock bodies are now reused via `apps/web-platform/test/helpers/agent-runner-mocks.ts` (`createSupabaseMockImpl`, `createQueryMock`). This is the same pattern all sibling tests use — accepting the small preamble duplication is consistent with house style, not new debt.

## Non-Goals

- **Runtime sandbox probing.** Not adding a `/health`-endpoint check for `bwrap` / `socat` presence. The SDK's `failIfUnavailable` path covers process startup; a health check would duplicate it without adding signal.
- **Sentry breadcrumb on startup success.** Not adding a "sandbox ready" breadcrumb — the agent-spawn log path already emits session metadata; adding another event on every spawn is noise.
- **Production SDK version bump.** The current `@anthropic-ai/claude-agent-sdk@0.2.85` already exposes `failIfUnavailable` in its types. No dependency update needed.
- **Integration test covering "remove socat, observe startup fail."** Deferred per Test Strategy rationale above. File a follow-up only if the unit assertion proves insufficient in practice.

## Alternative Approaches Considered

| Alternative | Outcome | Why rejected |
| --- | --- | --- |
| Add a runtime `which bwrap && which socat` probe at app startup | Rejected | Duplicates what `failIfUnavailable` already does — at the SDK's native probe site — with less coverage (SDK may add deps beyond `bwrap`/`socat` in future minors). |
| Add a Sentry monitor on missing-sandbox log lines | Rejected | Works only after an unsandboxed session has already executed. We want fail-closed, not fail-loud-after-the-fact. |
| Promote all sandbox-config assertions into the existing `agent-runner-tools.test.ts` | Rejected | Mixes concerns. A dedicated `-sandbox-config.test.ts` signals intent; `-tools.test.ts` is about tool allowlisting. |
| Containerized regression test (socat-less image) | Deferred | See Test Strategy rationale. File follow-up if unit assertion drifts. |

## Domain Review

**Domains relevant:** CTO (engineering / security)

### CTO (engineering / security)

**Status:** self-assessed (config-only change, issue pre-scoped by Phase 1 spike of #1450; no additional cross-domain surface)
**Assessment:** Single-line config flag that turns a silent failure mode into an explicit startup failure. Zero API surface change. Zero user-facing change. Primary axis is defensive depth — Tier-4 isolation becomes enforceable against dependency drift. The Dockerfile annotation is comment-only. The regression test is narrow (asserts one boolean in the SDK call argument) and follows established patterns in `apps/web-platform/test/agent-runner-*.test.ts`. No new dependencies, no migration risk, no runtime-perf impact (the flag is checked once at SDK startup).

**Brainstorm-recommended specialists:** none (no brainstorm for this specific issue; parent #1450 brainstorm pre-assessed domains).

**Product/UX Gate:** N/A — no user-facing surface. Tier: NONE.

## Research Insights

- **SDK surface confirmed.** `@anthropic-ai/claude-agent-sdk@0.2.85` exposes `failIfUnavailable?: boolean` at `sdk.d.ts:3588`. Docstring at line 3586: _"Exit with an error at startup if sandbox.enabled is true but the sandbox cannot start (missing dependencies, unsupported platform, or platform not in enabledPlatforms). When false (default), a warning is shown and commands run unsandboxed. Intended for managed-settings deployments that require sandboxing as a hard gate."_
- **SDK error text verbatim.** The SDK's thrown message when the flag trips (grep against `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/cli.js`):
  - `"sandbox required but unavailable: ${reason}"`
  - `"refusing to start without a working sandbox"`
  Useful as a Sentry fingerprint matcher if we ever want alert-level routing, but NOT asserted in the vitest regression (too implementation-detail for a config-shape test).
- **Empirical capture 2026-04-19** (documented in `knowledge-base/project/specs/feat-verify-workspace-isolation/sdk-probe-notes.md` sections "Empirical capture attempt" and "Captured bwrap argv post-socat install"): without `socat`, `query()` runs `/bin/bash -c` directly — zero `/usr/bin/bwrap` execve. With `failIfUnavailable: true` and socat missing, the SDK throws the exact error above.
- **socat is load-bearing beyond networking.** Captured production bwrap argv includes socat listeners inside the bwrap shell script (lines 297-303 of `sdk-probe-notes.md`: `socat TCP-LISTEN:3128,fork,reuseaddr UNIX-CONNECT:<http-sock>` etc.) — confirming socat is not optional for ANY sandboxed run, even when network isolation is configured tight (our `network.allowManagedDomainsOnly: true`).
- **Current Dockerfile state.** `apt-get install ... bubblewrap socat qpdf` already installs both dependencies at `apps/web-platform/Dockerfile:40`. This PR does NOT change runtime behavior of the deployed image — it only changes behavior when those deps are ever removed.
- **Production entry point.** `startAgentSession(userId: string, conversationId: string, leaderId: string, resumeSessionId?, message?, context?, routeSource?, ...)` at `apps/web-platform/server/agent-runner.ts:377` is what eventually calls SDK `query({ prompt, options: { sandbox: ... } })` at line 719 onward. All existing `agent-runner-*.test.ts` files invoke this entry and assert on `mockQuery.mock.calls[0][0].options`.
- **Existing test-harness already uses the flag.** `apps/web-platform/test/sandbox-isolation.test.ts:422` passes `failIfUnavailable: true` to query() in its isolation harness. The production code path is the outlier. Closing this gap is a one-line consistency fix.

## References

- Spike notes: `knowledge-base/project/specs/feat-verify-workspace-isolation/sdk-probe-notes.md` (sections "Empirical capture attempt (2026-04-19) — critical finding" and "Critical production risks surfaced").
- SDK docs: `@anthropic-ai/claude-agent-sdk@0.2.85` `sdk.d.ts:3586`.
- Parent context: #1450 (MU3 cross-workspace isolation test harness, discovery PR for this gap).
- Learning on silent fallback defense-in-depth: `knowledge-base/project/learnings/2026-03-20-canuse-tool-sandbox-defense-in-depth.md`.

## Implementation Phases

### Phase 1 — RED: regression test

1. Create `apps/web-platform/test/agent-runner-sandbox-config.test.ts` with the test above.
2. Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/agent-runner-sandbox-config.test.ts`.
3. Expect: test FAILS (production code has no `failIfUnavailable`, assertion on `.toBe(true)` fails with `expected undefined to be true`).

### Phase 2 — GREEN: code + Dockerfile

1. Edit `apps/web-platform/server/agent-runner.ts` — insert `failIfUnavailable: true` at line 749 (inside sandbox block, after `enabled: true`).
2. Edit `apps/web-platform/Dockerfile` — extend the bubblewrap/socat comment block at line 37 with the load-bearing annotation.
3. Re-run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/agent-runner-sandbox-config.test.ts`.
4. Expect: test PASSES.
5. Re-run full agent-runner test surface: `cd apps/web-platform && ./node_modules/.bin/vitest run test/agent-runner-*.test.ts`. Expect: no new failures vs. main.

### Phase 3 — REFACTOR / ship

1. `skill: soleur:compound` (required pre-commit per `wg-before-every-commit-run-compound-skill`).
2. `skill: soleur:ship` — handles review gate, QA gate, PR body formatting. PR body MUST include `Closes #2634` per `wg-use-closes-n-in-pr-body-not-title-to`.
3. Post-merge: verify Sentry for absence of `sandbox required but unavailable` events on next deploy cycle.

## PR Body Template

```markdown
## Summary
- Add `sandbox.failIfUnavailable: true` at `apps/web-platform/server/agent-runner.ts:749` — turns silent unsandboxed fallback into hard startup failure.
- Annotate `apps/web-platform/Dockerfile:37` comment block: `socat` is load-bearing for bwrap invocation, not just network bridging.
- Add vitest regression in `apps/web-platform/test/agent-runner-sandbox-config.test.ts` asserting the flag is passed to SDK `query()`.

## Why
Per empirical capture during #1450 Phase 1 spike: when `socat` is missing, the SDK silently runs Bash tool calls without bwrap wrapping. No Sentry event, no metric, no alert. Tier-4 defense-in-depth disappears invisibly. `failIfUnavailable: true` promotes silent fallback to an explicit startup error that Sentry WILL catch.

## Test plan
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/agent-runner-sandbox-config.test.ts` — new test passes.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/agent-runner-*.test.ts` — no regressions in existing tests.
- [ ] Post-merge: next production deploy shows no "sandbox required but unavailable" Sentry events.

Closes #2634
```
