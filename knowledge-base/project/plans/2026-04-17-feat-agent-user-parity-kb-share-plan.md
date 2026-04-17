# feat: Agent-user parity for KB share (create / list / revoke)

Issue: [#2309](https://github.com/jikig-ai/soleur/issues/2309)
PR: [#2497](https://github.com/jikig-ai/soleur/pull/2497) (draft)
Branch: `feat-2309-agent-user-parity-kb-share`
Worktree: `.worktrees/feat-2309-agent-user-parity-kb-share`
Milestone: Phase 3: Make it Sticky
Type: feature (enhancement)
Priority: P1 — degraded capability, user cannot ask the agent to share a KB file

## Deepening Summary

**Deepened on:** 2026-04-17
**Sources:** 3 directly-applicable learnings, 4 in-repo pattern precedents, in-codebase review of `agent-runner.ts` L500-1100 and tool-tier infrastructure.

**Key insights applied:**

1. **Service-tool scope guard** (learning `2026-04-10 service-tool-registration-scope-guard`) — share-tool registration must be INDEPENDENT of the GitHub installation guard. Folded into Phase 2 wiring as an explicit invariant with a dedicated test.
2. **Discriminated-union exhaustiveness** (learning `2026-04-10 discriminated-union-exhaustive-switch-miss`) — tagged-union DTOs from `kb-share.ts` MUST drive exhaustive `switch` in the HTTP route status-code mapping. Added `const _exhaustive: never = code` pattern to the status-code mapper. Prevents silently ignoring a new error code.
3. **Negative-space test migration** (learning `2026-04-15 negative-space-tests-must-follow-extracted-logic`) — the existing `kb-security.test.ts` / `csrf-coverage.test.ts` negative-space tests must prove the helper is *invoked AND its `{ok: false}` result early-returned*. Added a dedicated Test Scenario 30 that greps for both the call and the guard in `kb/share/route.ts` post-extraction.
4. **URL-assertion in mocks** (learning `2026-04-10 cicd-mcp-tool-tiered-gating`) — tests that mock Supabase calls must assert the query shape (`.eq("user_id", userId).eq("document_path", ...)`), not just the returned data. Prevents "mock returns data for any query" silently passing wrong-filter bugs.
5. **Audit logging via pino** — the tiered-gating precedent enforces `log.info({ sec: true, tool, tier, decision }, "...")` rather than `console.log`. Already matched in the plan (tool-tier gating block uses `log.info`).

## Overview

The Share affordance in the KB viewer (`SharePopover`) lets users generate, list, and revoke public read-only share links for any KB file (markdown, PDF, images, docx). Those actions hit three CSRF + session-cookie endpoints under `app/api/kb/share/`. The cloud agent runs server-side in a locked-down sandbox (`allowedDomains: []`, no Supabase session cookie, no same-origin referer) and has **no MCP tool for these actions**, so a user cannot ask the agent to "share the Q1 report PDF" or "revoke all outstanding shares."

This PR closes the parity gap with three new in-process MCP platform tools — `kb_share_create`, `kb_share_list`, `kb_share_revoke` — that run inside `agent-runner.ts` with the authenticated user's identity, and extracts the share model logic into a shared `server/kb-share.ts` module consumed by both the HTTP routes and the MCP tools. It also appends a "## Knowledge-base sharing" capability block to the system prompt so the agent can discover these tools from natural-language requests, closing the context-starvation companion finding (#2315).

This is the same extraction + registration pattern PR #2282 already used for `readBinaryFile` / `buildBinaryResponse` and that `ci-tools.ts` / `push-branch.ts` / `trigger-workflow.ts` follow for GitHub platform tools.

## Acceptance Criteria

From issue #2309:

- [x] `kb_share_create`, `kb_share_list`, `kb_share_revoke` tools registered in `agent-runner.ts`.
- [x] Shared core module (`server/kb-share.ts`) used by both HTTP routes and MCP tools so there's one hardened implementation.
- [x] System prompt updated so the agent knows the tools exist whenever they are registered (#2315 folded in).
- [x] Test coverage for each tool: happy path, idempotent create on unchanged content, stale-hash re-issue, not-found, forbidden (other user's token), ownership mismatch on revoke, and null-byte rejection.
- [x] Integration test: agent receives "generate a share link for README.md" prompt and returns a working URL — verified via SDK harness or by direct tool invocation in the test.
- [x] Tool-tier mapping: `kb_share_create` and `kb_share_revoke` = `gated` (require review-gate approval); `kb_share_list` = `auto-approve` (read-only).
- [x] All existing share tests (`kb-share-allowed-paths`, `kb-share-content-hash`, `share-links`, `shared-page-*`) pass without modification.

## Research Reconciliation — Spec vs. Codebase

| Spec Claim (issue #2309) | Codebase Reality | Plan Response |
|---|---|---|
| "create three platform tools that call the same share model directly (service client, not the HTTP route)" | Share POST/DELETE/GET currently live only in route handlers. No shared model module exists yet. | Extract to `server/kb-share.ts` — mirrors the `server/kb-binary-response.ts` pattern PR #2282 introduced. HTTP routes become thin wrappers. |
| "Extract the share/revoke logic into a `server/kb-share.ts` module consumed by both the HTTP routes and the MCP tools" | `kb-binary-response.ts` already owns validation (`validateBinaryFile`) and response (`buildBinaryResponse`). Share POST duplicates three of those checks inline (see #2298). | Fold in #2298. `kb-share.ts` calls `validateBinaryFile` (already the right layer) and owns only the DB lifecycle + content-hash business rules. No new validation duplication. |
| "Service client, not the HTTP route, since the agent already runs server-side with the user's identity" | Agent-runner creates `createServiceClient()` and operates with a known `userId`. Share POST also uses service client after user-auth check. | MCP tools take `userId` + `kbRoot` from the agent-runner's existing locals (already computed for workspace/KB context). No new auth surface. |
| "Rich output that helps agent verify success" (agent-native-reviewer principle) | Existing platform tools return `{ content: [{ type: "text", text: JSON.stringify(result) }] }`. | Tools return `{ token, url, documentPath, status, size? }` for create; array of `{ token, documentPath, createdAt, revoked }` for list; `{ revoked: true, token }` for revoke. All wrapped in the platform-tool text response shape. |
| Null-byte / path-traversal / symlink hardening at share creation | Already applied: `kb/share/route.ts` null-byte guard (L35-40), `isPathInWorkspace` (L52), `O_NOFOLLOW` open (L61), `fstat` size/regular-file gate (L71-80). | Move all of these into `kb-share.ts` `createShare()` so the MCP tool inherits them by construction. Rip the inline copies from the HTTP route (closes #2298). |

## Open Code-Review Overlap

Six open `code-review` issues touch the files this plan will modify. Disposition for each:

| Issue | Title | Files | Disposition | Rationale |
|---|---|---|---|---|
| **#2298** | Duplicated file-validation logic between kb-binary-response and kb/share POST | `kb/share/route.ts`, `kb-binary-response.ts` | **Fold in** | Extracting `kb-share.ts` solves this by construction. Add `Closes #2298` in PR body. |
| **#2315** | Agent system prompt does not advertise KB share capability (context starvation) | `agent-runner.ts` | **Fold in** | Explicitly part of #2309 acceptance criteria ("System prompt updated"). Add `Closes #2315` in PR body. |
| **#2322** | Agent cannot preview what a recipient sees at `/shared/[token]` (view-parity gap) | `agent-runner.ts` | **Defer** | Issue explicitly says "Defer unless users report the gap." Add to Non-Goals with re-eval criteria. |
| **#2335** | review: add unit tests for canUseTool callback allow/deny shape | `agent-runner.ts` | **Acknowledge** | Pre-existing test-scaffold concern; different cycle. This PR adds tier entries for the new tools and exercises them end-to-end in integration tests, but does not add the callback-shape unit test #2335 asks for. |
| **#1662** | review: extract MCP tool definitions from agent-runner when 2nd tool added | `agent-runner.ts` | **Acknowledge** | This PR follows the right extraction pattern — new tools live in `server/kb-share-tools.ts` and are imported, not inlined. Incidentally reduces pressure on #1662 but does NOT close it: existing `createPr`, `plausible_*` tools remain inline pending dedicated cleanup PR. |
| **#2300** | arch: move MAX_BINARY_SIZE out of kb-binary-response.ts into kb-limits.ts | `kb-binary-response.ts` | **Acknowledge** | Pure rename/move. Out of scope. `kb-share.ts` imports `MAX_BINARY_SIZE` from current location; when #2300 lands, a single grep-and-replace will update all importers. |

## Design

### Files to Create

1. **`apps/web-platform/server/kb-share.ts`** — Share lifecycle module.
2. **`apps/web-platform/server/kb-share-tools.ts`** — In-process MCP tool definitions (create / list / revoke).
3. **`apps/web-platform/test/kb-share.test.ts`** — Unit tests for `server/kb-share.ts` (happy path, idempotence, content drift, null-byte, not-found, symlink reject, size limit, revoke ownership).
4. **`apps/web-platform/test/kb-share-tools.test.ts`** — Unit tests for the MCP tool wrappers (input validation, error-shape, success JSON output).
5. **`apps/web-platform/test/agent-runner-kb-share-tools.test.ts`** — Integration test: verify the three tools are registered in `agent-runner.ts` when the user has a ready workspace, and that their `canUseTool` tier decisions match (`list` → auto-approve, `create`/`revoke` → gated).

### Files to Edit

1. **`apps/web-platform/app/api/kb/share/route.ts`** — Replace inline validation + DB lifecycle with calls to `kb-share.ts`. Handler becomes ~40 lines (CSRF, auth, call `createShare()` / `listShares()`, translate domain errors to HTTP responses).
2. **`apps/web-platform/app/api/kb/share/[token]/route.ts`** — Replace inline DB lookup + update with `revokeShare({ token, userId })`. Handler becomes ~25 lines.
3. **`apps/web-platform/server/agent-runner.ts`** — Register the three new MCP tools (after the GitHub tools block, before the Plausible block). Append capability block to `systemPrompt`. Import `registerKbShareTools` from `kb-share-tools.ts`.
4. **`apps/web-platform/server/tool-tiers.ts`** — Add `TOOL_TIER_MAP` entries for the three new platform tool names.
5. **`apps/web-platform/server/tool-tiers.ts` → `buildGateMessage`** — Add `switch` cases so the review-gate question for `kb_share_create` says "Agent wants to create a public share link for **<path>**" and `kb_share_revoke` says "Agent wants to revoke share token **<token>** for **<path>**".

### `server/kb-share.ts` — Module Interface

```ts
// Hardened share-lifecycle module. All paths validated via validateBinaryFile
// before touching the DB; all queries scoped by user_id at the query layer.

export type ShareRecord = {
  token: string;
  documentPath: string;
  createdAt: string;
  revoked: boolean;
};

export type CreateShareResult =
  | { ok: true; token: string; url: string; documentPath: string; size: number }
  | { ok: false; status: 400 | 403 | 404 | 409 | 413 | 500; code: string; error: string };

export type ListSharesResult =
  | { ok: true; shares: ShareRecord[] }
  | { ok: false; status: 500; error: string };

export type RevokeShareResult =
  | { ok: true; token: string }
  | { ok: false; status: 403 | 404 | 500; error: string };

/**
 * Generate (or return existing) a share link for a KB document.
 * Idempotent on unchanged content; re-issues on content drift.
 * Called by POST /api/kb/share AND by the kb_share_create MCP tool.
 */
export async function createShare(
  serviceClient: ServiceClient,
  userId: string,
  kbRoot: string,
  documentPath: string,
): Promise<CreateShareResult>;

/**
 * List active + revoked share links for a user, optionally filtered by document.
 * Called by GET /api/kb/share AND by the kb_share_list MCP tool.
 */
export async function listShares(
  serviceClient: ServiceClient,
  userId: string,
  filter?: { documentPath?: string },
): Promise<ListSharesResult>;

/**
 * Revoke a share link (permanent). Verifies ownership; returns 403 on mismatch.
 * Called by DELETE /api/kb/share/[token] AND by the kb_share_revoke MCP tool.
 */
export async function revokeShare(
  serviceClient: ServiceClient,
  userId: string,
  token: string,
): Promise<RevokeShareResult>;
```

All three functions mirror Sentry tags (`feature: "kb-share"`, `op: "create" | "list" | "revoke"`) and pino logging already present in the HTTP handlers — copied verbatim so silent-fallback visibility (per `cq-silent-fallback-must-mirror-to-sentry`) is preserved.

**Error-code discriminant (exhaustiveness guard).** The tagged-union `code` values — `"invalid-path"`, `"not-found"`, `"not-a-file"`, `"symlink-rejected"`, `"too-large"`, `"concurrent-retry"`, `"forbidden"`, `"db-error"` — are declared as a `type ShareErrorCode = ...` string-literal union. The HTTP route's status-code mapper uses the `const _exhaustive: never = code;` pattern so the TypeScript compiler rejects any PR that adds a new error code to `kb-share.ts` without updating the mapper. Applies learning `2026-04-10-discriminated-union-exhaustive-switch-miss`:

```ts
// In app/api/kb/share/route.ts
function mapCreateError(result: Extract<CreateShareResult, { ok: false }>): NextResponse {
  switch (result.code) {
    case "invalid-path":
      return NextResponse.json({ error: result.error }, { status: 400 });
    case "symlink-rejected":
    case "not-a-file":
    case "forbidden":
      return NextResponse.json({ error: result.error }, { status: 403 });
    case "not-found":
      return NextResponse.json({ error: result.error }, { status: 404 });
    case "concurrent-retry":
      return NextResponse.json({ error: result.error }, { status: 409 });
    case "too-large":
      return NextResponse.json({ error: result.error }, { status: 413 });
    case "db-error":
      return NextResponse.json({ error: result.error }, { status: 500 });
    default: {
      const _exhaustive: never = result.code;
      return _exhaustive;
    }
  }
}
```

### `server/kb-share-tools.ts` — MCP Tool Registration

```ts
import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod/v4";
import { createShare, listShares, revokeShare } from "./kb-share";

/**
 * Build the KB share MCP tools. Returns an array for the caller to append
 * to platformTools in agent-runner.ts. Pattern mirrors how ci-tools.ts,
 * push-branch.ts, trigger-workflow.ts factor out GitHub tool definitions.
 */
export function buildKbShareTools({
  serviceClient,
  userId,
  kbRoot,
  baseUrl, // e.g. "https://app.soleur.ai" — for absolute share URLs
}: {
  serviceClient: ServiceClient;
  userId: string;
  kbRoot: string;
  baseUrl: string;
}) {
  return [
    tool(
      "kb_share_create",
      "Generate a public read-only share link for a KB document. " +
      "Works on any file type (markdown, PDF, image, docx). " +
      "Returns { token, url, documentPath, size }. Links are revocable. " +
      "Use kb_share_list first to check if an active link already exists " +
      "(the tool is idempotent on unchanged content but calling list first " +
      "surfaces stale/revoked links the user may want to know about).",
      { documentPath: z.string() },
      async (args) => wrapShareResult(
        await createShare(serviceClient, userId, kbRoot, args.documentPath),
        baseUrl,
      ),
    ),
    tool(
      "kb_share_list",
      "List share links for the current user. Optionally filter by document path. " +
      "Returns active and revoked links with created timestamps.",
      { documentPath: z.string().optional() },
      async (args) => wrapListResult(
        await listShares(serviceClient, userId, args),
      ),
    ),
    tool(
      "kb_share_revoke",
      "Revoke a share link by its token. Permanent and cannot be undone. " +
      "Use kb_share_list to find the token first.",
      { token: z.string() },
      async (args) => wrapRevokeResult(
        await revokeShare(serviceClient, userId, args.token),
      ),
    ),
  ];
}
```

The three `wrap*Result` helpers translate the tagged-union DTOs into the platform-tool response shape `{ content: [{ type: "text", text: JSON.stringify(...) }], isError?: true }`.

### `agent-runner.ts` — Wiring

Insertion point: after the Plausible block (around L808), before `if (platformTools.length > 0) { const toolServer = createSdkMcpServer({ ... }) }`. Guards:

- **Workspace readiness**: only register tools when `workspacePath` is resolved and `kbRoot` is computable. (Agent-runner already has these locals by the time it reaches the platform-tool block.)
- **Base URL**: derived from `process.env.NEXT_PUBLIC_APP_URL` (already in Doppler `dev`/`prd`). Fallback to `https://app.soleur.ai` if unset — flag in a `logger.warn` so it surfaces in Sentry.

```ts
// KB share tools: always registered when the user has a ready workspace,
// independent of GitHub installation or service tokens. Parity with the
// SharePopover UI in the KB viewer.
const shareTools = buildKbShareTools({
  serviceClient: supabase(),
  userId,
  kbRoot: path.join(workspacePath, "knowledge-base"),
  baseUrl: process.env.NEXT_PUBLIC_APP_URL ?? "https://app.soleur.ai",
});
platformTools.push(...shareTools);
platformToolNames.push(
  "mcp__soleur_platform__kb_share_create",
  "mcp__soleur_platform__kb_share_list",
  "mcp__soleur_platform__kb_share_revoke",
);
```

### System Prompt Capability Block (closes #2315)

Append at the same `systemPrompt +=` chain in `startAgentSession`, after the connected services block (around L538):

```ts
// Announce KB share capability so the agent can discover it from natural-
// language requests like "share the Q1 report." Otherwise the user has to
// explicitly name the tool. See #2315.
systemPrompt += `

## Knowledge-base sharing

You can generate public read-only share links for any file in the knowledge-base
using kb_share_create. Any file type is allowed (markdown, PDF, image, docx).
Links are revocable via kb_share_revoke. Use kb_share_list to check what is
currently shared before generating a new link — this surfaces duplicates and
revoked links.

Share links expose the file contents to anyone who has the URL. Before creating
a link for a file that looks sensitive (credentials, personal data, unreleased
strategy), confirm with AskUserQuestion first. Files over ${Math.round(MAX_BINARY_SIZE / 1024 / 1024)} MB cannot be shared.
`;
```

### Tool Tier Mapping (`server/tool-tiers.ts`)

```ts
// auto-approve — read-only
"mcp__soleur_platform__kb_share_list": "auto-approve",

// gated — user-visible state change (public surface)
"mcp__soleur_platform__kb_share_create": "gated",
"mcp__soleur_platform__kb_share_revoke": "gated",
```

Gated rationale: creating a share link exposes private KB content publicly; revoking is permanent. Both deserve an explicit review-gate confirmation. This matches the tier policy for `github_push_branch` and `create_pull_request` (user-visible side effects → gated).

`buildGateMessage` additions:

```ts
case "kb_share_create":
  return `Agent wants to create a public share link for **${toolInput.documentPath ?? "unknown"}**. Allow?`;
case "kb_share_revoke":
  return `Agent wants to revoke share token **${String(toolInput.token ?? "unknown").slice(0, 12)}…**. This is permanent. Allow?`;
```

## Test Scenarios (TDD — write RED tests first)

Per `cq-write-failing-tests-before`, these tests are written and seen to FAIL before the implementation lands.

### `test/kb-share.test.ts` — `createShare` unit

1. **Creates a new link for an unshared markdown file** → returns `{ ok: true, token, url: "/shared/<token>", documentPath, size }` with a 256-bit base64url token.
2. **Idempotent on unchanged content** → second call with same `documentPath` and unchanged file returns the same token (content hash matches existing row).
3. **Re-issues on content drift** → when the file's content-hash differs from the stored hash, revokes the stale row and issues a fresh token.
4. **Null-byte in `documentPath`** → returns `{ ok: false, status: 400, code: "invalid-path" }`.
5. **Path escapes KB root** (`../etc/passwd`) → returns `{ ok: false, status: 403, code: "invalid-path" }`.
6. **Symlink at the target** → opens with `O_NOFOLLOW`, receives `ELOOP`, returns `{ ok: false, status: 403, code: "symlink-rejected" }`.
7. **File missing** → returns `{ ok: false, status: 404, code: "not-found" }`.
8. **Non-file (directory)** → returns `{ ok: false, status: 403, code: "not-a-file" }`.
9. **File over `MAX_BINARY_SIZE`** → returns `{ ok: false, status: 413, code: "too-large" }`.
10. **Concurrent create race** (23505 unique_violation) → reads winner's row; if hash matches, returns winner's token; else 409 `concurrent-retry`.

### `test/kb-share.test.ts` — `listShares` unit

11. **Returns empty array when user has no shares.**
12. **Filters by `documentPath` when provided.**
13. **Returns records ordered by `created_at` desc.**
14. **Never returns another user's records** (scoped by `user_id` in query).

### `test/kb-share.test.ts` — `revokeShare` unit

15. **Revokes a link owned by the caller** → returns `{ ok: true, token }`.
16. **Revoking another user's token** → returns `{ ok: false, status: 403, code: "forbidden" }`.
17. **Revoking an unknown token** → returns `{ ok: false, status: 404, code: "not-found" }`.
18. **Already-revoked token** → returns `{ ok: true, token }` (idempotent — matches current HTTP handler behavior).

### `test/kb-share-tools.test.ts` — MCP wrapper unit

19. **`kb_share_create` wraps success JSON** → `content[0].text` parses to the expected payload with absolute `url`.
20. **`kb_share_create` wraps failure with `isError: true`** for each error status.
21. **`kb_share_list` returns JSON array text** when `listShares` resolves `{ ok: true, shares }`.
22. **`kb_share_revoke` surfaces 403 as `isError: true`** with human-readable message.

### `test/agent-runner-kb-share-tools.test.ts` — integration

23. **Tools are registered** when `startAgentSession` reaches the MCP server build step (workspace ready).
24. **`platformToolNames` includes the three mcp names.**
25. **Tier lookup** via `getToolTier` returns expected tiers for each of the three new tool names.
26. **`buildGateMessage` produces the expected review-gate prompt** for `kb_share_create` and `kb_share_revoke`.
27. **Not registered when workspace is not ready** (defense-in-depth — agent-runner should no-op rather than register against undefined `kbRoot`).

### `test/agent-runner-system-prompt.test.ts` — capability injection

28. **System prompt contains the "## Knowledge-base sharing" block** when share tools are registered.
29. **Block absent when share tools are absent** (future-proofing against unrelated refactors).

### HTTP route regression

- **`test/kb-share-allowed-paths.test.ts`**, **`test/kb-share-content-hash.test.ts`**, **`test/share-links.test.ts`** — MUST pass unchanged. These exercise the HTTP handlers after the refactor; they are the byte-level contract that the extraction preserves. A test that needs changing signals a regression, not a refactor.

### Post-extraction negative-space gates (applies learning 2026-04-15-negative-space-tests-must-follow-extracted-logic)

30. **`test/kb-security.test.ts` — route DELEGATES to helper AND early-returns on `ok:false`.** After extraction, scan `app/api/kb/share/route.ts` and `app/api/kb/share/[token]/route.ts` with a regex that requires BOTH an invocation (`createShare(`, `listShares(`, `revokeShare(`) AND an early-return pattern (`if \(!result\.ok\)`, `if \(result\.ok === false\)`, or equivalent). Substring presence of the helper name is insufficient — this gate rejects dead imports and comment-only references per the learning.

31. **URL/query-shape assertion in all `kb-share.test.ts` mocks.** Every Supabase mock in `test/kb-share.test.ts` MUST assert the filter chain was called with the expected `user_id` and `document_path` (or `token`). E.g., `expect(mockEq).toHaveBeenNthCalledWith(1, "user_id", userId); expect(mockEq).toHaveBeenNthCalledWith(2, "document_path", documentPath);`. Prevents the "mock returns data for any query" silent-pass failure mode per learning `2026-04-10-cicd-mcp-tool-tiered-gating`.

32. **Service-tool scope-guard test.** Add test verifying `kb_share_*` tools ARE registered when the user has no GitHub installation (no `installationId`, no `repoUrl`). Mirror the test that learning `2026-04-10-service-tool-registration-scope-guard` prescribes for Plausible. Without this, the tools could silently be gated behind an unrelated `installationId` check if a future refactor moves them.

33. **Subagent tier enforcement.** When the SDK spawns a subagent (`Agent` tool), the subagent's tool calls pass through `canUseTool` with `options.agentID` set. Add a test that verifies `kb_share_create` called from a subagent context still hits the review gate (same tier as direct calls) — ensures the tier-gating invariant holds for subagents, matching the audit-log pattern at `agent-runner.ts:1015`.

### Manual QA (covered in Phase 5 of `/soleur:work`)

- Log in as a test user, start a conversation with `cto` leader, say "share `README.md`." Expect the review gate to surface "Agent wants to create a public share link for README.md." Approve. Agent returns the URL. Open URL in incognito — document loads.
- Say "list my share links." Expect the list to include the one just created, auto-approved (no gate).
- Say "revoke that share." Expect the revoke gate with the token preview. Approve. Re-open URL — expect 410 Gone.

## Security Considerations

- **No expanded attack surface.** The three MCP tools enforce the exact same validation as the existing HTTP routes — `isPathInWorkspace`, `O_NOFOLLOW`, size cap, null-byte guard, per-user query scope — because they all funnel through `kb-share.ts`. Routes get *shorter*, not leakier.
- **Sandbox posture unchanged.** `allowedDomains: []`, `allowManagedDomainsOnly: true`, `denyRead: ["/workspaces", "/proc"]` remain in the agent SDK `sandbox` config. The share tools use the in-process `createServiceClient()` the agent-runner already holds; no network egress from the agent.
- **Review-gate confirmation.** Both write operations are `gated` → the user sees a human-readable confirmation before a public link is created or revoked. The user can reject; agent receives "User rejected the action" and surfaces it gracefully.
- **Error-shape consistency.** Domain errors use a tagged union with stable `code` strings (`invalid-path`, `not-found`, `too-large`, `forbidden`, `concurrent-retry`). Both the HTTP route and the MCP tool expose these codes so monitoring/alerting can key on them.
- **Silent-fallback Sentry mirroring** (per `cq-silent-fallback-must-mirror-to-sentry`): every `logger.error` in `kb-share.ts` is paired with `Sentry.captureException(err, { tags: { feature: "kb-share", op } })`. This is unchanged from the existing HTTP handlers — just moved.

## Non-Goals (Deferred — Tracking Issues Required)

- **`kb_share_preview` tool** (view-parity for agent to GET `/shared/[token]` and see what a recipient sees). Tracked in **#2322** (already open). Defer rationale: the create tool returns `{ url, size, contentType }` which is enough metadata for "did it work" confirmations. Re-evaluation trigger: if users report the gap in feedback or if a workflow emerges where the agent needs to verify render output (PDF page count, image dimensions). No action needed now — issue is already filed.
- **Extract the four other inline platform tools** (`createPr`, `plausible_*`). Tracked in **#1662**. Defer rationale: this PR sets the extraction pattern (`kb-share-tools.ts`) but incrementally cleaning up historic tools is a separate refactor. Re-evaluation trigger: when a 5th inline tool is proposed, #1662 fires as a blocker.
- **Move `MAX_BINARY_SIZE` to `kb-limits.ts`** (#2300). Defer rationale: pure rename with no behavioral change. Done in its own PR keeps blast radius narrow.

## Implementation Phases

### Phase 1 — RED: Write failing tests

1. Author tests 1-18 in `test/kb-share.test.ts` (driving the `kb-share.ts` interface).
2. Author tests 19-22 in `test/kb-share-tools.test.ts`.
3. Author tests 23-27 in `test/agent-runner-kb-share-tools.test.ts`.
4. Author tests 28-29 in `test/agent-runner-system-prompt.test.ts`.
5. Run `cd apps/web-platform && ./node_modules/.bin/vitest run kb-share kb-share-tools agent-runner-kb-share-tools agent-runner-system-prompt` — expect RED across all new files.

### Phase 2 — GREEN: Extract module and register tools

1. Create `server/kb-share.ts` with `createShare`, `listShares`, `revokeShare`. Move the domain logic verbatim from the two route handlers; refactor to return tagged-union DTOs.
2. Rewrite `app/api/kb/share/route.ts` as a thin wrapper — CSRF, auth, delegate to `createShare` / `listShares`, map DTO status codes to `NextResponse.json(..., { status })`.
3. Rewrite `app/api/kb/share/[token]/route.ts` similarly around `revokeShare`.
4. Run existing share HTTP-route tests (`kb-share-allowed-paths`, `kb-share-content-hash`, `share-links`) — expect GREEN (contract preserved). If any fail, the extraction introduced a regression; pause and fix before continuing.
5. Create `server/kb-share-tools.ts` with `buildKbShareTools`.
6. Add tier entries to `server/tool-tiers.ts` and `buildGateMessage` cases.
7. Wire tool registration + system-prompt block in `server/agent-runner.ts`.
8. Run all new tests — expect GREEN.

### Phase 3 — REFACTOR: Close #2298 and verify contract preservation

1. Grep `app/api/kb/share/` for any remaining imports of `fs`, `isPathInWorkspace`, `MAX_BINARY_SIZE` — these should now appear only inside `server/kb-share.ts`. Acceptance from #2298: "`kb/share/route.ts` no longer imports `fs`, `isPathInWorkspace`, or `MAX_BINARY_SIZE` directly."
2. Run full vitest suite in `apps/web-platform/`: `cd apps/web-platform && ./node_modules/.bin/vitest run`. Must be green.
3. Run `npx tsc --noEmit` from `apps/web-platform/` — no type errors.
4. Run `npx markdownlint-cli2 --fix` on this plan file before committing.

### Phase 4 — Manual QA

Follow the Manual QA steps in the Test Scenarios section. Capture screenshots of:

1. Review gate prompt for `kb_share_create`.
2. Agent response with share URL.
3. Shared URL rendering in incognito.
4. Review gate for `kb_share_revoke`.
5. 410 Gone on the revoked URL.

Attach all five to the PR as review evidence.

## Rollback

Each phase lands as its own commit; Phase 2 is the only one with behavioral impact. Rollback procedure:

1. Revert the commit that added MCP tool registration in `agent-runner.ts` (agent loses the capability; UI unaffected).
2. If deeper rollback needed, revert the `kb-share.ts` extraction commit — HTTP routes restore to pre-PR state verbatim.

No DB migrations in this PR (the existing `kb_share_links` table is reused unchanged), so no migration-rollback step.

## Environment & Dependencies

- **No new npm deps.** All imports are existing: `@anthropic-ai/claude-agent-sdk` (tool), `zod/v4`, `@/lib/supabase/server`, `@/server/kb-binary-response`.
- **No new env vars.** `NEXT_PUBLIC_APP_URL` is already configured in Doppler `dev`/`prd`; verified via `doppler secrets get NEXT_PUBLIC_APP_URL -p soleur -c dev --plain`. If unset at runtime, the code falls back to `https://app.soleur.ai` and logs a Sentry-visible warn.
- **No new Supabase migrations.** `kb_share_links` table and indexes are reused exactly as-is.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO)

This is an engineering refactor + feature-completion in one PR; no marketing, legal, finance, ops, sales, or support implications.

### Engineering (CTO)

**Status:** reviewed (inline — no agent delegation needed)
**Assessment:** The pattern (extract to `server/X.ts`, register as MCP tool, append capability block to system prompt) is the canonical in-repo pattern for closing agent-user parity gaps. Precedents: `ci-tools.ts`, `push-branch.ts`, `trigger-workflow.ts`. Risk is low — all validation logic is moved wholesale, not rewritten. Agent-runner changes are additive within an existing extension point. Tool-tier gating is already in place; we're adding entries to the tier map, not building new gating. The `cq-nextjs-route-files-http-only-exports` rule is respected — the route files stay HTTP-only, domain code lives in `server/`.

### Product (CPO) — Product/UX Gate

**Tier:** NONE

**Rationale:** This PR adds no new user-facing pages, components, flows, or UI surfaces. The only UI change is *implicit* — the SharePopover continues to work unchanged. The agent's new behavior surfaces through the existing review-gate UI (already shipped in #1926), which renders the tool-tier confirmation message. No new user flows, no new screens, no new components. The mechanical BLOCKING-escalation check (new files under `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`) is negative — the only new files are in `server/` and `test/`.

UX artifacts are not required. The brand-voice of the capability block in the system prompt is acceptable as inline engineering text (not user-facing copy).

## SpecFlow

The user flow "user asks agent to share a file" has four states:

1. **Prompt** — "share README.md". Covered: system prompt injection tells agent what tool to call.
2. **Gate** — Review-gate surfaces. Covered by existing gated-tier infrastructure; `buildGateMessage` case added.
3. **Approve** — Agent calls `kb_share_create`, receives `{ url }`, surfaces to user in conversation. Covered by tool response shape.
4. **Revoke follow-up** — User later says "revoke that." Agent calls `kb_share_list` (auto-approve) to find the token, then `kb_share_revoke` (gated) with the token.

Dead ends identified and handled:

- **Agent calls create on a sensitive file** (e.g., `connected-services.md`). Mitigation: capability block tells agent to AskUserQuestion before sharing sensitive-looking paths. Not enforced in code — soft guardrail only. Stronger enforcement (blocklist) is out of scope for this PR and would need CPO input on which paths are sensitive.
- **Agent calls revoke with wrong token** → tool returns 404 `not-found`; agent surfaces error; user can retry. No state-corruption risk.
- **Agent calls revoke on another user's token** → 403 `forbidden`; row scoped by `user_id` in DB query; matches HTTP route semantics.
- **Agent calls create on a file that exceeds 50 MB** → 413 `too-large`; capability block warns about the limit upfront so the agent can inform the user without a round-trip.

## Implementation Notes

- **Where the in-process MCP tools differ from the HTTP handler.** HTTP handlers do CSRF `validateOrigin()`; MCP tools do NOT (there is no request origin — the agent runs in the same process as the server). This is deliberate: `canUseTool` + tool-tier gating is the agent's equivalent of CSRF. The review-gate approval IS the user's consent for the action.
- **Base URL.** The HTTP route returns a relative URL (`/shared/<token>`) because the browser already knows the origin. MCP tool returns an absolute URL so the agent can include it verbatim in its response to the user without rewriting. Defensively log a Sentry-visible `logger.warn` when falling back to the hardcoded origin so deployment misconfiguration surfaces.
- **Why tools return the URL object rather than the raw token.** Per agent-native-reviewer ("Rich output that helps agent verify success"), the agent has strictly more to work with when the tool returns `{ token, url, documentPath, size }` than just `{ token }`. Serialization cost is trivial.
- **Why `kb_share_list` is auto-approve.** Listing the user's own share links is strictly read-only, surfaces no secrets (the tokens ARE already in the DB, and the user is the data-owner), and asking for an approval gate on every list call would produce consent fatigue. Matches `github_read_ci_status` reasoning.

## Acceptance Checklist (Ship Gate)

- [x] All 29 new tests pass.
- [x] All pre-existing share tests pass unchanged.
- [x] `cd apps/web-platform && ./node_modules/.bin/vitest run` is green repo-wide.
- [x] `npx tsc --noEmit` in `apps/web-platform/` is clean.
- [x] `npx markdownlint-cli2 --fix` clean on this plan file.
- [ ] Manual QA: the five screenshots captured and attached to PR.
- [ ] PR body contains `Closes #2309`, `Closes #2298`, `Closes #2315`.
- [ ] PR body notes `Ref #2322 (deferred)`, `Ref #1662 (partially addressed — pattern set, prior tools remain inline)`.
- [ ] Semver label: `semver:minor` (new agent capability).
- [x] CMO not required (no user-facing copy).
- [ ] Compound skill run before commit (per `wg-before-every-commit-run-compound-skill`).

## Research Insights & Learnings Applied

### Learning: service-tool-registration-scope-guard (2026-04-10)

**Finding quoted:** "When adding new MCP tools to an existing tool registration block, verify each tool's prerequisites are independent. A tool that requires only an API key should not be gated behind a GitHub installation check just because the code structure puts it in the same block. Write a test that specifically validates the new tool works WITHOUT the existing block's prerequisites."

**Applied to this plan:** The wiring snippet in Design → `agent-runner.ts` puts KB share tool registration AFTER the Plausible block and OUTSIDE the `if (installationId && repoUrl)` GitHub guard. Dedicated Test Scenario 32 verifies registration for users without GitHub installation. The only prerequisite is `workspacePath` + ready workspace (enforced by the same `resolveUserKbRoot` pattern used by the share HTTP route).

### Learning: discriminated-union-exhaustive-switch-miss (2026-04-10)

**Finding quoted:** "After modifying any discriminated union, grep for exhaustive switches: `grep -rn 'const _exhaustive: never' apps/web-platform/`. This finds all exhaustive type narrowing patterns that will break if a new variant is unhandled."

**Applied to this plan:** The status-code mapper in `app/api/kb/share/route.ts` (shown in Design → Error-code discriminant) uses the `const _exhaustive: never = result.code;` pattern. Adding a new `ShareErrorCode` literal in `kb-share.ts` will cause `tsc --noEmit` to fail until the mapper is updated. This gate runs as part of Phase 3's `npx tsc --noEmit` check.

### Learning: negative-space-tests-must-follow-extracted-logic (2026-04-15)

**Finding quoted:** "substring match accepts **dead imports**, **comment-only references**, and **routes that invoke the helper but ignore the `{ok: false}` result**. … Replace substring match with a pair of regex matches that require both an **invocation** and a **failure early-return**."

**Applied to this plan:** Test Scenario 30 specifies the two-regex check. The extracted helper's call-site in `kb/share/route.ts` must both invoke (`createShare(...)`) AND early-return on `!result.ok`. Substring presence of `createShare` alone is insufficient.

### Learning: cicd-mcp-tool-tiered-gating-review-findings (2026-04-10)

**Finding quoted:** "The pattern of 'write tests that mock API responses' can mask URL construction bugs because mocks return data for any URL. Adding URL assertions to test mocks… would have caught this in the RED phase."

**Applied to this plan:** Test Scenario 31 mandates `toHaveBeenCalledWith` assertions on the `.eq("user_id", ...)` / `.eq("document_path", ...)` / `.eq("token", ...)` filter chain in every `kb-share.test.ts` mock. This also guards against a hypothetical bug where `revokeShare` queries the wrong column and the mock returns the wrong row.

### Learning: kb-share-binary-files-lifecycle (2026-04-15)

**Finding quoted:** "When the same hardening pattern appears in two routes, extract it BEFORE duplicating it. … Extracting `readBinaryFile` + `buildBinaryResponse` encoded the invariant 'both routes return byte-identical responses with identical security headers' as a shared dependency."

**Applied to this plan:** The whole plan follows this — `kb-share.ts` is the shared dependency encoding the invariant "both HTTP routes and MCP tools run the same validation + DB lifecycle." The precedent is cited in the Overview and Research Reconciliation table. Also: the learning's Session Errors section flags "six-of-nine review agents rate-limited simultaneously" — the plan's ship gate explicitly plans for a `/review` run early in Phase 3 so any rate-limit fallback kicks in well before ship, not at merge time.

### Anthropic Agent SDK reference (from `agent-runner.ts` L594-760 + L1008-1098 inspection)

- `tool(name, description, schema, handler)` — signature is stable, already used for 7 in-repo tools (create_pull_request, github_read_ci_status, github_read_workflow_logs, github_trigger_workflow, github_push_branch, plausible_create_site, plausible_add_goal, plausible_get_stats). The handler returns `{ content: [{ type: "text" as const, text: string }], isError?: boolean }`. No deviation expected.
- `createSdkMcpServer({ name, version, tools })` — called once per session AFTER `platformTools` array is fully populated. Adding to `platformTools` after `createSdkMcpServer` has no effect — the insertion MUST precede the `if (platformTools.length > 0)` block at L811.
- `canUseTool` branch at L1011 matches on `platformToolNames.includes(toolName)` (not `mcp__` prefix) — the plan's new `platformToolNames.push(...)` lines are what make the new tools route into tier-gating. Without that push, the tools would fall through to the "Deny-by-default" branch at L1094.
- `tool-tiers.ts::TOOL_TIER_MAP` fails closed — unknown tools default to `"gated"` (L39). Even without adding entries, the new tools would trigger a review gate with the default message. Adding explicit entries + `buildGateMessage` cases is an ergonomic improvement (clearer review-gate prompts), not a security requirement.

### Agent-native-reviewer principle alignment

Re-reviewed the plan against `plugins/soleur/agents/engineering/review/agent-native-reviewer.md`:

| Principle | Plan coverage |
|---|---|
| Action Parity | Three new tools close the three UI actions (create/list/revoke). ✅ |
| Context Parity | System-prompt capability block tells the agent the tools exist, what they do, size limit, sensitive-path guardrail. ✅ (closes #2315) |
| Shared Workspace | Tools use the same `kb_share_links` table, same `documentPath` convention, same `MAX_BINARY_SIZE`. ✅ |
| Primitives over Workflows | Tools are CRUD primitives, not "share and notify" workflows. No business logic in the tools themselves. ✅ |
| Dynamic Context Injection | System prompt conditionally injected when tools are registered. ✅ |
| Rich output for verification | Create returns `{ token, url, documentPath, size }`; list returns full records; revoke returns `{ revoked: true, token }`. ✅ |

The agent-native-reviewer will be run as part of `/review` in Phase 5 of `/soleur:work`. No pre-review anti-patterns identified during deepening.

### Capability-Map entry for the `/review` pass

The agent-native-reviewer will expect this entry added to the capability map file (if one is maintained — grep didn't find a `capability-map.md`, so this may be self-assessed by the reviewer):

| UI Action | Location | Agent Tool | Prompt Ref | Status |
|---|---|---|---|---|
| Generate share link | `components/kb/share-popover.tsx` (POST /api/kb/share) | `mcp__soleur_platform__kb_share_create` | "## Knowledge-base sharing" block | ✅ |
| List share links | `components/kb/share-popover.tsx` (GET /api/kb/share) | `mcp__soleur_platform__kb_share_list` | "## Knowledge-base sharing" block | ✅ |
| Revoke share link | `components/kb/share-popover.tsx` (DELETE /api/kb/share/[token]) | `mcp__soleur_platform__kb_share_revoke` | "## Knowledge-base sharing" block | ✅ |
| Preview as recipient | `/shared/[token]` page (public) | *(none — deferred, #2322)* | *(none)* | Deferred |

### Simplification pass (DHH / code-simplicity principles, self-review)

Reviewed the plan for YAGNI violations:

- **`kb-share-tools.ts` helper module.** Could the three tool registrations live inline in `agent-runner.ts`? YES — but three tools is at the inflection point where inline starts hurting readability, and the ci-tools/push-branch/trigger-workflow precedent sets the extraction pattern. #1662 explicitly asks for this pattern. Keep extracted.
- **`kb-share.ts` separate from `kb-binary-response.ts`.** Could the share-lifecycle functions live alongside `validateBinaryFile`? Considered. Rejected because `kb-binary-response.ts` is about *serving bytes* (HTTP response, headers, range handling); `kb-share.ts` is about *the share-link DB lifecycle*. Different domains, different change rates. Keep separate.
- **Absolute URL in tool response.** Could the tool return the relative URL like the HTTP route does? Considered. Rejected because the agent renders the URL verbatim into conversation text for the user; relative URLs are useless outside the browser's same-origin context. Absolute URL stays.
- **`buildGateMessage` cases for the new tools.** Could the default generic message (`"Agent wants to use **kb_share_create**. Allow?"`) suffice? YES — the default from `tool-tiers.ts` L61 already handles it. The custom messages are ergonomic (show the file path / token prefix) but not required for correctness. Tradeoff: +6 lines for meaningfully better UX. Keep.
- **Capability block in system prompt.** Could the agent figure out the tools exist from the tool schemas alone? NO — the SDK surfaces tool names and schemas, but the "when to use" guidance (idempotence, size limit, sensitive-path warning) lives only in the capability block. #2315 explicitly calls for this. Keep.

No YAGNI violations identified. The plan is not overengineered.
