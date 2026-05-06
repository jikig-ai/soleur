---
type: bug-fix
issue: 3376
branch: feat-one-shot-sidebar-pdf-summarize-out-of-boundary
prior_issues: [3253, 3263, 3278, 3287, 3288, 3294, 3338, 3353]
related_open_issues: [3383, 3342]
follow_through_for: 3376
requires_cpo_signoff: true
sentry_event_origin: 9e0a3888fd3849cd87cb83cdcecca199
---

# fix(cc-concierge): sidebar PDF summary fails with "outside my workspace boundary" — close the gated-Read fallback path and align local Node engine

## Enhancement Summary

**Drafted on:** 2026-05-06 (initial plan).
**Deepened on:** 2026-05-06 (same session, immediately after initial draft).
**Sections enhanced:** Root-Cause Analysis (Bug A split into A1-directive + A2-sandbox), Files to Edit (added directive injection sites), Phase 3 (added directive-side fix), Acceptance Criteria (added relative-path scope-out coverage).

### Key Improvements Discovered During Deepen-Pass

1. **SDK Read tool contract REQUIRES absolute paths.** `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk-tools.d.ts:367-371` — `FileReadInput.file_path` is documented as "The absolute path to the file to read". Yet our `buildPdfGatedDirective` (soleur-go-runner.ts:105) and the text-too-large branch (agent-runner.ts:763, soleur-go-runner.ts:722) all instruct the model with the workspace-relative `context.path` ("knowledge-base/foo.pdf"). The model dutifully passes the relative string as `file_path`, the sandbox-hook resolves against process CWD, and denies. **Bug A has two halves:** A1 (directive injection-site bug) and A2 (sandbox-hook resolution bug). Both must be fixed; the A1 fix is sufficient to close the user-facing reproduction, and the A2 fix is the defense-in-depth that prevents any future relative-path Read from re-introducing the same failure.

2. **Three directive injection sites need patching, not one.** Initial plan listed only `soleur-go-runner.ts buildPdfGatedDirective`. Grep confirms three sites with the relative-path pattern: `soleur-go-runner.ts:105` (PDF gated, both runners use it), `soleur-go-runner.ts:722` (text-too-large fallback), `agent-runner.ts:763` (legacy leader text-too-large fallback). Per `cq-when-a-plan-prescribes-a-fix-based-on-extension-grep`, all three must be updated in lockstep — leaving any one with a relative path silently re-introduces Bug A on its trigger surface.

3. **`pdfjs-dist@5.4.296` declares `engines.node ≥ 22.3.0` AND `≥ 20.16.0`.** The disjunction means BOTH 20.16+ and 22.3+ work — the library uses `process.getBuiltinModule()` which exists in Node 20.16+ via backport (Node 22.0-22.2 are explicitly excluded). For our use, we should pin `>=22.3.0` (NOT `>=22.0.0`) because the Dockerfile uses `node:22-slim` (always ≥22.x, currently 22.18) and contributors should not fall onto Node 20 paths that are tested less. Per the plan SKILL Sharp Edges entry on engine constraints, an `engines` field with a wrong floor is silent — `bun install` and `npm install` both warn-only on mismatch by default.

4. **`buildPdfUnreadableDirective` does NOT prevent the model from calling Read** — it instructs ("do not attempt to discover or open the file via other tools") but does not HARD-BLOCK at the SDK level. The cc-soleur-go path uses `extraDisallowedTools: CC_PATH_DISALLOWED_TOOLS` to hard-block Bash/Edit/Write but Read remains allowed. This is intentional — Read is needed for text files — but it means a model that confused-paraphrases the unreadable directive can still call Read on the same path and trip the sandbox. The Phase 4.2 test asserts the unreadable directive has fired; a follow-through item should consider whether to ALSO drop Read from `allowedTools` when `documentExtractError` is set (decided: not in this PR — the system prompt instruction is sufficient when the directive copy is right).

5. **The `users.workspace_path` value matters for path resolution.** `agent-runner-query-options.ts:114` sets the SDK Query `cwd` to `args.workspacePath`. This means the AGENT'S filesystem-tool calls operate from that directory (the agent sees a relative `Read("knowledge-base/foo.pdf")` as `<workspacePath>/knowledge-base/foo.pdf`). The SECURITY GUARDS, however, use Node's `path.resolve(filePath)` which uses `process.cwd()` (the Next.js server's CWD) — divergent from the agent's CWD. The SDK does not normalize relative paths to absolute before invoking PreToolUse hooks; the responsibility lives entirely in our sandbox/permission code.

### New Considerations Discovered

- **Defense-in-depth: directive copy MUST never include the user-facing security-internal substring "outside" or "workspace boundary".** Even if the directive is correct and the model follows it, model paraphrase can hallucinate. Acceptance test 4.2 should also assert that the model OUTPUT does not contain those strings post-fix. Add a model-output post-filter as a follow-through item if the e2e Playwright test reveals paraphrase regressions.

- **Backwards compatibility: existing absolute-path callers of `isPathInWorkspace` must continue to work.** The Phase 3.1 widening MUST be a strict superset of existing behavior — `path.isAbsolute(filePath) ? filePath : path.resolve(workspacePath, filePath)` preserves the absolute-path code path 1:1 and only changes the relative-path code path. Audited 4 call sites in §Phase 3.3 — all pass absolute paths today, so the widening is no-op for them.

- **The `engines.node` pin may interact with Vercel build-image selection.** Vercel reads `engines.node` to choose the Node runtime for serverless functions and the build image. Pinning `>=22.3.0` is compatible with Vercel's "22.x" runtime (currently 22.18). Verify the Vercel project doesn't have a project-level Node version override that conflicts (`vercel project inspect` if needed).

- **Test coverage for the directive injection-site fix must NOT depend on a real Anthropic API call.** Mock the queryFactory and assert on the exact `systemPrompt` substring. The SDK's Read-tool contract verification test (Phase 4.1/4.2) is sufficient — the model's actual behavior given the directive is empirically tested via Playwright e2e (Phase 4.3) only.

- **The legacy `agent-runner.ts:763` text-too-large directive is currently unreachable in the cc-soleur-go path** (the cc path goes through `kb-document-resolver.ts` which doesn't have a "text too large" directive — it just falls through to `documentKind: "text"` with no body). It IS still reachable in the legacy domain-leader path (`startAgentSession`). Phase 3 must update both because a future cc-path refactor that mirrors the agent-runner flow will silently re-import the relative-path bug.

## Overview

**User-reported regression (post-#3353).** Opening a workspace PDF in the KB sidebar (`Au Chat Potan - Presentation Projet-10.pdf`, ~57 pages) and asking "Can you please summarize this document?" returns:

> I can't read this specific PDF — the file is outside my workspace boundary and I can't access it right now

with a suggestion to paste text or re-upload. The "Continue thread" button is active (the sidebar is on a warm conversation) and the PDF is fully ingested — visible in the KB tree, opened in the viewer pane.

This plan closes the workflow-level gap that PRs #3338 (typed extractor failure classes) and #3353 (cap alignment) did not eliminate — there is still an unguarded fallback path that lands the agent at `buildPdfGatedDirective` with a relative file path, which the canUseTool/sandbox-hook layers reject as "outside workspace boundary" because path resolution is anchored on the Node process CWD, not the SDK Query's `cwd`.

## Root-Cause Analysis (Three Reinforcing Bugs)

### Bug A1 — Directive injection sites pass workspace-relative paths to the model, which the SDK contract rejects

**Code:** Three sites:
- `apps/web-platform/server/soleur-go-runner.ts:102-110` (`buildPdfGatedDirective` — PDF Read instruction)
- `apps/web-platform/server/soleur-go-runner.ts:722` (text-too-large fallback in cc-soleur-go runner)
- `apps/web-platform/server/agent-runner.ts:763` (text-too-large fallback in legacy leader runner)

All three substitute `${path}` from `safeArtifactPath` / `safeContextPath`, which is the workspace-relative `context.path` (e.g., `"knowledge-base/foo.pdf"`). The directive then says: `Use the Read tool to read "${path}"`. The model dutifully passes that exact relative string as `Read({ file_path: "knowledge-base/foo.pdf" })`. The SDK's `FileReadInput.file_path` contract (`sdk-tools.d.ts:367-371`) documents this field as **"The absolute path to the file to read"** — passing a relative path is a contract violation that the SDK does not normalize.

The agent's invocation of Read with a relative path then routes through the sandbox-hook (Bug A2 below).

### Bug A2 — `sandbox.ts: resolveRealPath()` resolves relative paths against the Node process CWD, not the agent's workspace

**Code:** `apps/web-platform/server/sandbox.ts:21-35`.

```typescript
function resolveRealPath(filePath: string): string | null {
  const resolved = path.resolve(filePath);  // ← uses process.cwd(), NOT agent's cwd
  try {
    return fs.realpathSync(resolved);
  } catch ...
}
```

When the agent (whose SDK `cwd` is set to `users.workspace_path` via `agent-runner-query-options.ts:114`) calls `Read({ file_path: "knowledge-base/overview/Au Chat Potan - Presentation Projet-10.pdf" })` with a workspace-relative path:

1. Layer 1 (sandbox-hook) → `extractToolPath` returns the relative string → `isPathInWorkspace` calls `path.resolve(filePath)` → Node resolves against the Next.js server's process CWD (`/app` in the container, or `/home/user/repo/apps/web-platform` locally) → joined absolute path is NOT inside `users.workspace_path` → deny with `"Access denied: file path outside workspace boundary"` (sandbox-hook.ts:34).
2. Layer 2 (canUseTool, `permission-callback.ts:347-360`) — same path-resolution shape, same deny reason.

The model receives the deny reason as a tool result and paraphrases it as "the file is outside my workspace boundary and I can't access it right now" — exactly what the user is seeing.

**Why this matters even though `cwd` is set in SDK options:** the SDK passes `cwd` to the AGENT (so its tool calls behave correctly relative to that directory), but our SECURITY GUARDS (sandbox-hook + canUseTool) call Node's `path.resolve` independently from the SDK lifecycle, anchored on `process.cwd()`. The two CWDs diverge by design.

The combination of A1 (directive feeds the agent a relative path) + A2 (sandbox-hook can't safely accept a relative path) is the **proximate cause** of the user-facing reply. Fixing A1 alone closes the specific user reproduction (the directive will hand the model an absolute path); fixing A2 alone closes the defense-in-depth side (any future relative-path Read won't false-positive-deny). Both should land together.

### Bug B — `kb-document-resolver.ts:235-240` swallows `readFile` failures into the gated-Read fallback (no `documentExtractError`)

**Code:** `apps/web-platform/server/kb-document-resolver.ts:155-240`.

```typescript
try {
  const buffer = await readFile(fullPath);
  const result = await extractPdfText(buffer, CONCIERGE_INLINE_CAP_BYTES);
  ...
} catch {
  // readFile failed (missing file, permission denied) — let the agent
  // try Read. No Sentry mirror: this is not a degraded extractor, just
  // an absent file the UI may have stale-referenced.
  return { artifactPath: contextPath, documentKind: "pdf" };
}
```

The bare `{ artifactPath, documentKind: "pdf" }` return (no `documentExtractError`) routes the runner to `buildPdfGatedDirective` (soleur-go-runner.ts:703) — the apt-get-cascade-prone Read directive. PR #3353 worked specifically to KILL the Read-fallback path on extractor failure; this `catch` is a parallel survival route that bypasses the kill switch.

**Production trigger surfaces** (any of these exercises the catch):
- Filename normalization mismatch (NFC vs NFD on macOS-uploaded PDFs; the disk path uses one form, `conversations.context_path` was persisted in the other).
- Whitespace handling: the user's filename has spaces (`Au Chat Potan - Presentation Projet-10.pdf`). If any UI/upload path URL-encodes spaces to `%20` and the resolver does not decode, `path.join(workspacePath, contextPath)` produces a path that does not exist on disk → `readFile` ENOENT → catch.
- Symlinked workspaces where the symlink target is not yet realized at request time.
- Race window where the file is being written/replaced when the resolver opens it.

The catch ALSO does not mirror to Sentry, so this entire failure class is invisible to operators (violates `cq-silent-fallback-must-mirror-to-sentry`).

### Bug C — Local dev/CI Node version mismatch with `pdfjs-dist@5.4.296` engine requirement

**Code:** `apps/web-platform/package.json` lacks an `engines.node` constraint; `apps/web-platform/node_modules/pdfjs-dist/package.json` declares `engines.node: ">=20.16.0 || >=22.3.0"`. The library uses `process.getBuiltinModule()` (added in Node 22.0) and Web APIs (`DOMMatrix`, `ImageData`, `Path2D`).

Local Node v21.7.3 lacks `process.getBuiltinModule` → the lazy `import("pdfjs-dist/legacy/build/pdf.mjs")` throws → `extractPdfText` returns `{ error: "lazy_import_failed" }`.

This is the **mechanism for issue #3383** (4 pre-existing test failures on main). It would also fire for any production container where the resolved Node version drops below 22.3 (e.g., a future base-image refresh that pins to a slim 22.0/22.1 tag). The Dockerfile uses `node:22-slim@sha256:...` which currently resolves to Node 22.18.x — fine — but the absence of an explicit `engines.node` floor means a future SHA bump can silently introduce the regression.

### Hypothesis Tree (which bug is firing in production?)

| Scenario | Resolver path | Runner directive | User-facing reply | Matches user report? |
|---|---|---|---|---|
| Extractor inlined body | `documentContent` set | inline-body branch (`<document>...`) | Direct summary | No |
| Extractor failure (typed) | `documentExtractError` set | `buildPdfUnreadableDirective` | "I can't read this specific PDF — `<canned reasonClause>`" | Partial — user message format matches but reason is wrong |
| `readFile` ENOENT (Bug B) | bare `{ artifactPath, documentKind: "pdf" }` | `buildPdfGatedDirective` → model calls Read → Bug A denies | "I can't read this specific PDF — the file is outside my workspace boundary" | **YES** |

Bug B + Bug A is the only path that produces the EXACT user message. Bug C is the parallel local-dev/CI failure mode that prevents tests from validating the production fix.

## User-Brand Impact

**If this lands broken, the user experiences:** a re-occurrence of the post-#3353 "I can't read this specific PDF — the file is outside my workspace boundary" reply when summarizing any KB PDF whose disk path mismatches the persisted `context_path` (filename whitespace, NFC/NFD, race), with no Sentry event for operators to triage. This is the FIFTH regression iteration in the same code path (#3253/#3263/#3278/#3287/#3288/#3294/#3338/#3353); each prior fix tightened a specific failure class while leaving an adjacent fallback path open. A user who has already re-tried the same PDF four+ times will not retry a fifth.

**If this leaks, the user's workflow is exposed via:** a degraded Concierge experience that silently falls back to a Read attempt that the sandbox denies, causing the model to paraphrase a security-internal error message ("outside workspace boundary") to the end user. This leaks security guard internals (the workspace boundary concept) into the user-facing reply, which is brand-degrading even when not data-leaking.

**Symmetric leak introduced by the Bug A1 fix (added during PR #3384 review):** every Read directive now embeds `users.workspace_path` (an absolute server filesystem path, e.g., `/srv/workspaces/<userId>/knowledge-base/foo.pdf`) into the LLM-visible system prompt. If the model paraphrases the directive into its reply, the user sees deployment FS topology (mount layout, hosting prefix, potentially userId in the path component). Mitigations landed in this PR: (1) `buildPdfGatedDirective` now instructs the model to refer to the document by its workspace-relative `displayPath` in user-facing replies, never the absolute path; (2) the absolute-path string is stripped of control chars / U+2028 / U+2029 before injection so a crafted `artifactPath` cannot smuggle adjacent instructions into the prompt; (3) follow-through: a deferred Playwright assertion (Phase 4.3 in the plan) should grep the model's reply for `/srv/`, `/home/`, `/var/`, `/app/` prefixes once the e2e harness is wired to a real Supabase instance.

**Brand-survival threshold:** single-user incident.

The user is the SAME user who hit Sentry event `9e0a3888fd3849cd87cb83cdcecca199` and filed the original reproduction. They have shipped four prior fixes for the same surface and the bug is still present on the same PDF. This is not a "first incident" — it is the ongoing failure mode of the KB Concierge product itself, which is a Soleur core surface. CPO sign-off required at plan-time per `hr-weigh-every-decision-against-target-user-impact`.

`user-impact-reviewer` will be invoked at review-time per `plugins/soleur/skills/review/SKILL.md` conditional-agent block.

## Research Reconciliation — Spec vs. Codebase

| Spec/Issue claim | Codebase reality | Plan response |
|---|---|---|
| "PR #3353 aligned the PDF extractor cap with upload cap and surfaced typed failure classes" | True — `MAX_AGENT_READABLE_PDF_SIZE` is shared, `PdfExtractErrorClass` exists with 6 classes, runner has typed-payload exhaustive switch | Build on #3353 — do NOT regress its typed-failure surface; ADD the `readFile`-error class to it |
| "Sandbox / workspace boundary check is correct" | False — `path.resolve()` uses process CWD; relative paths from agent always resolve outside workspace unless absolute | Fix Bug A as a separate concern; resolve relative paths against `workspacePath` |
| "Resolver mirrors all PDF failures to Sentry" | False — the `readFile` catch (line 235-240) is silent | Add Sentry mirror + new `read_failed` typed error class |
| "Sidebar 'Continue thread' button reuses the existing Query (warm path)" | Conditional — `hasActiveCcQuery` returns true ONLY if the runner singleton has the conversation in `activeQueries`. After idle reap (10 min) or process restart, the next turn is cold → resolver fires. The user's reproduction is most likely a cold path because they've left the tab idle | Cold-path fix is the load-bearing change; warm-path is a separate plan (out-of-scope) |
| "Issue #3383 — 4 pre-existing pdf-text-extract test failures on main" | Confirmed — running `vitest run test/pdf-text-extract.test.ts` returns 8 failures, all because pdfjs-dist lazy-import throws on local Node 21.x (`process.getBuiltinModule is not a function`) | Fix Bug C in this PR — without it, the regression test for the production fix cannot run on contributor machines |

## Open Code-Review Overlap

Run after Files-to-Edit list is finalized (Phase 2 issue planning). Pre-emptive grep based on touched files:

- `apps/web-platform/server/kb-document-resolver.ts` → no open review issues match
- `apps/web-platform/server/sandbox.ts` → no open review issues match
- `apps/web-platform/server/pdf-text-extract.ts` → #3342 ("kb-preview-metadata.ts passes Buffer to pdfjs which rejects it") is adjacent — same library/pattern, different file. **Disposition: acknowledge.** Different file, different concern (Buffer-vs-Uint8Array shape, already handled in `pdf-text-extract.ts` by the `Buffer.isBuffer` check at line 104-112). Closing it requires a `kb-preview-metadata.ts` edit which is out of scope for THIS user-facing regression.
- `apps/web-platform/test/pdf-text-extract.test.ts` → #3383 is the tracking issue — **Disposition: fold in.** This plan's Bug C fix closes #3383 in the same PR.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO).

### Engineering / CTO

**Status:** reviewed (carry-forward from #3338 + #3353 plans + this plan's research)
**Assessment:** This is the fifth iteration of the same regression class (PDF Concierge). The architectural pattern (extractor → typed error class → directive picker) is the right shape; the gap is that the resolver has TWO failure-injection points (extractor failure → typed class; readFile failure → bare context → gated directive) and only one is wired to the kill switch. Treat the resolver's failure surface as the authoritative source for "what the runner needs to know" and unify both injection points to use the typed class. The sandbox-hook relative-path bug (Bug A) is a security-adjacent defect that has been latent because every other code path in the codebase passes absolute paths to Read; the agent (which sees `cwd` from the SDK) is the first natural producer of relative paths that hit our guards.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline mode; carry-forward from prior PDF-fix plans)
**Skipped specialists:** none
**Pencil available:** N/A

#### Findings

User-facing surface is a chat reply only — no new UI components. Existing chat bubble + markdown render path is reused. No copy that requires brand review. CPO sign-off requirement is from the `single-user incident` threshold (User-Brand Impact section), NOT from a new UX concern.

## Plan

### Phase 0 — Verification (RED)

#### 0.1 Confirm Bug C locally (issue #3383)

```bash
cd apps/web-platform && ./node_modules/.bin/vitest run test/pdf-text-extract.test.ts
```

Expected pre-fix: 8 failures with `lazy_import_failed`. After Bug C fix: 0 failures or 1-2 failures unrelated to lazy-import (which then become Bug A/B regression coverage).

#### 0.2 Confirm Bug A by direct unit test

Add a failing test in `apps/web-platform/test/sandbox.test.ts` (or add to existing `sandbox-resolveparent-realpath.test.ts`):

```typescript
it("isPathInWorkspace REJECTS a workspace-relative path even when it identifies a real workspace file", () => {
  const fakeWorkspace = "/tmp/test-workspace-abc";
  fs.mkdirSync(`${fakeWorkspace}/knowledge-base`, { recursive: true });
  fs.writeFileSync(`${fakeWorkspace}/knowledge-base/test.pdf`, "");
  // BUG A: relative path is path.resolve()-d against process.cwd(),
  // not against fakeWorkspace, so this returns false even though the
  // file IS in the workspace.
  expect(isPathInWorkspace("knowledge-base/test.pdf", fakeWorkspace)).toBe(false);  // pre-fix
  // POST-fix expectation: same call returns true (or the API gains a
  // workspaceCwd parameter and returns true when passed)
});
```

This test is RED pre-fix and GREEN post-fix.

#### 0.3 Confirm Bug B via resolver unit test

Add a test in `apps/web-platform/test/kb-document-resolver-pdf-extract.test.ts`:

```typescript
it("returns documentExtractError='read_failed' (NOT bare PDF context) when readFile throws ENOENT", async () => {
  // Mock fetchUserWorkspacePath to return a real dir; mock readFile to throw ENOENT.
  // Assert: result.documentExtractError === 'read_failed' AND Sentry was called.
});
```

RED pre-fix, GREEN post-fix.

### Phase 1 — Fix Bug C (Node engine alignment + minimal test repair)

**Objective:** make `pdf-text-extract.test.ts` runnable on contributor machines AND pin the production Node floor so the lazy-import never silently regresses post-deploy.

#### 1.1 Pin `engines.node` in `apps/web-platform/package.json`

```json
"engines": {
  "node": ">=22.3.0"
}
```

Per the Sharp Edges note in the plan skill ("when a plan asserts behavior of a third-party action / lib, grep the same repo for prior usage and reconcile"), check root `package.json` and `apps/cc-loader/package.json` for engine constraints — align with the strictest.

**Verified via Node.js docs (https://nodejs.org/api/process.html#processgetbuiltinmoduleid):** `process.getBuiltinModule(id)` is "Added in: v22.3.0, v20.16.0". This is also the exact engine disjunction `pdfjs-dist@5.4.296` declares (`>=20.16.0 || >=22.3.0`).

We pick the 22.3.0 floor (NOT 20.16.0) because:
- The Dockerfile already uses `node:22-slim` (`apps/web-platform/Dockerfile:2`), which currently resolves to Node 22.18.x. The 22.3 floor is consistent with the production runtime; allowing Node 20.x in package.json would create a tested-vs-allowed gap.
- Local-dev on Node 21.x (currently broken, e.g., this dev box) MUST upgrade. Node 21 is end-of-life (per Node release schedule) and was a non-LTS release; Node 22 LTS is the right floor.
- Allowing Node 20.16+ would split the matrix: contributors on Node 20.x would need a separate test-run (Node 20.x lacks features used elsewhere in the codebase). Single-version contract is simpler.

#### 1.2 Document the Node floor in `apps/web-platform/CONTRIBUTING.md` (or `README.md` if no CONTRIBUTING)

Verify which file exists via `ls apps/web-platform/CONTRIBUTING.md apps/web-platform/README.md`. Add a one-line note: "Local Node ≥ 22.3 is required (pdfjs-dist@5 lazy-imports `process.getBuiltinModule`)."

#### 1.3 Add a runtime guard in `extractPdfText` for clearer Sentry diagnosis

When the lazy-import fails, capture the underlying error message and Node version into the Sentry mirror so the next failure event diagnoses itself:

```typescript
} catch (importErr) {
  const nodeVersion = process.versions.node;
  reportSilentFallback(importErr, {
    feature: "kb-concierge-context",
    op: "extractPdfText.import",
    extra: { nodeVersion, message: (importErr as Error)?.message },
  });
  return { error: "lazy_import_failed" };
}
```

Decision: keep the current `lazy_import_failed` class (already in the union; user-facing copy already maps to UNREADABLE_COPY_GENERIC). No directive copy changes.

#### 1.4 Verify Phase 0.1 tests now pass

`vitest run test/pdf-text-extract.test.ts` → 0 failures. If a non-lazy-import failure surfaces, the fix is incomplete — DO NOT mark Phase 1 done.

### Phase 2 — Fix Bug B (resolver `readFile` failure must use the typed-error path)

**Objective:** unify the resolver's two failure injection points (extractor failure + readFile failure) so both surface a typed `documentExtractError` to the runner. Eliminates the "bare PDF context → gated Read directive" fallback that currently bypasses #3353's kill switch.

#### 2.1 Extend `PdfExtractErrorClass` with a new `read_failed` member

`apps/web-platform/server/pdf-text-extract.ts:56`:

```typescript
export type PdfExtractErrorClass =
  | "oversized_buffer"
  | "lazy_import_failed"
  | "encrypted"
  | "corrupted"
  | "parse_error"
  | "empty_text"
  | "read_failed";  // NEW
```

Per `cq-union-widening-grep-three-patterns`, the discriminated-union widening must be checked against three consumer patterns:

```bash
# (a) const _exhaustive: never — switch rails (safe)
rg "const _exhaustive: never" apps/web-platform/server/ apps/web-platform/lib/

# (b) .kind === "<literal>" — if-ladders (silent-drop risk)
rg "\.error === \"" apps/web-platform/server/ apps/web-platform/lib/

# (c) ?.kind === "<literal>" — optional-chained (silent-drop risk)
rg "\?\.error === \"" apps/web-platform/server/ apps/web-platform/lib/
```

Two known consumers:
- `soleur-go-runner.ts:164` `unreadableCopyForClass()` — switch with `: never` rail. Add a `case "read_failed":` mapping. **No silent drop** — TS will fail build until added.
- `kb-document-resolver.ts:186-189` (`empty_text` op-tagging) — if-ladder. Audit + extend if appropriate (likely no change needed; `read_failed` op tag would be a separate `readFile` op).

#### 2.2 Add `read_failed` user-facing copy in `unreadableCopyForClass()`

`soleur-go-runner.ts:164`:

```typescript
case "read_failed":
  return {
    reasonClause: "I couldn't open this PDF on my end — the file path may have changed or the document is being updated",
    suggestionClause: "Could you reload the page or paste the section you'd like me to work with?",
  };
```

The reason text NEVER mentions "workspace", "boundary", or sandbox-internal concepts. The model is told to use this exact phrasing.

#### 2.3 Rewrite the `kb-document-resolver.ts:235-240` catch to surface the typed error

Replace:

```typescript
} catch {
  // readFile failed (missing file, permission denied) — let the agent
  // try Read. No Sentry mirror: this is not a degraded extractor, just
  // an absent file the UI may have stale-referenced.
  return { artifactPath: contextPath, documentKind: "pdf" };
}
```

With:

```typescript
} catch (err) {
  Sentry.addBreadcrumb({
    category: "cc-pdf-extractor",
    message: "readFile failed",
    level: "warning",
    data: {
      ok: false,
      errorClass: "read_failed",
      errno: (err as NodeJS.ErrnoException)?.code ?? null,
      pathBasename: path.basename(contextPath),
    },
  });
  reportSilentFallback(err, {
    feature: "kb-concierge-context",
    op: "extractPdfText.readFile",
    extra: {
      userId,
      pathBasename: path.basename(contextPath),
      errorClass: "read_failed",
      errno: (err as NodeJS.ErrnoException)?.code ?? null,
    },
  });
  return {
    artifactPath: contextPath,
    documentKind: "pdf",
    documentExtractError: "read_failed",
  };
}
```

This forces the runner to pick `buildPdfUnreadableDirective` instead of `buildPdfGatedDirective`. The model is told the file cannot be opened AND told NOT to attempt to discover or open the file via other tools (existing directive copy).

#### 2.4 Defense-in-depth: also gate the text-file branch's catch

`kb-document-resolver.ts:254-266` has the same shape for text files (catches readFile error, falls through to text Read directive). Audit whether the text Read directive ALSO hits Bug A (the agent calls Read on a text path → sandbox denies → "outside workspace boundary"). Likely yes — Bug A applies to any Read with a relative path.

Decision: extend the typed-error pattern to text files. Either (a) treat text-file readFile failure as a no-context return (`{}`) so the runner emits a generic "I cannot find that document" reply, or (b) introduce a parallel `text_read_failed` directive. **Choose (a)** for simplicity — text files are not subject to the apt-get cascade so the ROI of a parallel directive is low; falling through to no-context (router prompt only) plus a Sentry mirror is the smallest correct fix.

```typescript
} catch (err) {
  reportSilentFallback(err, {
    feature: "kb-concierge-context",
    op: "readFile",
    extra: { userId, pathBasename: path.basename(contextPath), errno: (err as NodeJS.ErrnoException)?.code ?? null },
  });
  return {};  // CHANGED from { artifactPath: contextPath, documentKind: "text" }
}
```

NOTE: this changes existing behavior. Verify against `apps/web-platform/test/cc-dispatcher-concierge-context.test.ts` and update any test that depended on the old shape.

### Phase 3 — Fix Bug A (directive sends absolute paths + sandbox tolerates relative paths)

**Objective (A1):** every directive that instructs the model to call Read MUST inject a workspace-absolute path, matching the SDK's `FileReadInput.file_path` contract.

**Objective (A2):** the sandbox guard correctly resolves workspace-relative paths so any future relative Read does not false-positive-deny.

#### 3.0 (A1) Pass workspace-absolute paths to the directive builders

Three injection sites need updating:

**Site 1: `soleur-go-runner.ts buildPdfGatedDirective` (line 102-110).** Today the function takes `path: string` (the relative artifact path). Widen the signature to take both the relative path (for human-readable display) AND the absolute path (for the `Use the Read tool to read "${absolutePath}"` instruction):

```typescript
export function buildPdfGatedDirective(
  displayPath: string,
  absolutePath: string,
  noAskClause: string,
): string {
  return (
    `${PDF_GATED_DIRECTIVE_LEAD}: ${displayPath}\n\n` +
    `This is a PDF file. Use the Read tool to read "${absolutePath}" — ` +
    // ... rest unchanged
  );
}
```

**Site 2: `soleur-go-runner.ts:722` (text-too-large branch).** Same shape — embed the absolute path in the Read instruction, the display path in the human-readable header.

**Site 3: `agent-runner.ts:763` (legacy leader).** Same.

Caller updates: `soleur-go-runner.ts:703` (cc path) and `agent-runner.ts:752, 763` (legacy path). The caller already has `workspacePath` in scope; compute `path.join(workspacePath, displayPath)` once and pass both.

**Tests:** Phase 4 e2e tests must assert the system prompt contains the ABSOLUTE path in the `Use the Read tool to read "..."` substring, not the relative path. Add this assertion to both 4.1 and 4.2.

**Lock-step parity:** per `cq-when-a-plan-prescribes-a-fix-based-on-extension-grep` and the `agent-runner.ts ↔ soleur-go-runner.ts` lock-step parity invariant (#3294), all three sites move in lockstep. Run `git grep "Use the Read tool to read"` post-edit; confirm every match injects the absolute-path variable.

#### 3.1 (A2) Widen the `isPathInWorkspace` API to accept the workspace-relative anchor

`apps/web-platform/server/sandbox.ts`:

```typescript
export function isPathInWorkspace(
  filePath: string,
  workspacePath: string,
): boolean {
  if (!filePath) return false;

  // Resolve relative paths against the workspace, NOT process.cwd().
  // The agent's SDK Query is configured with cwd=workspacePath; relative
  // paths it produces (e.g., "knowledge-base/foo.pdf") refer to files
  // in the workspace, but Node's path.resolve() would anchor on the
  // Next.js server's process.cwd() and produce a path outside the
  // workspace, causing a false-positive sandbox denial.
  const absoluteFilePath = path.isAbsolute(filePath)
    ? filePath
    : path.resolve(workspacePath, filePath);

  const realPath = resolveRealPathFromAbsolute(absoluteFilePath);
  ...
}
```

Refactor `resolveRealPath` to accept a pre-resolved absolute path (rename to `resolveRealPathFromAbsolute`), or split into two callers — one keeps the legacy "resolve-then-realpath" shape for non-workspace callers, one accepts already-absolute and only realpaths.

#### 3.2 Verify both layers (sandbox-hook + canUseTool) reach the new code

`apps/web-platform/server/sandbox-hook.ts:24` and `apps/web-platform/server/permission-callback.ts:347-360` both call `isPathInWorkspace(filePath, workspacePath)`. The widening is API-compatible (both args were already required). Verify with the Phase 0.2 test that the same call now returns true for relative paths inside the workspace.

#### 3.3 Audit existing absolute-path callers for behavior preservation

```bash
rg "isPathInWorkspace\(" apps/web-platform/server/
```

Each call site must continue to behave correctly:
- `sandbox-hook.ts:24` — file tools, paths come from agent input. Today these paths could be either form; the fix accepts both. ✓
- `permission-callback.ts:347-360` — same. ✓
- `kb-document-resolver.ts:143` — `fullPath` is constructed via `path.join(workspacePath, contextPath)` so it's already absolute. ✓

#### 3.4 Add a fixture-level integration test exercising the agent-relative-path scenario

`apps/web-platform/test/sandbox-relative-paths.test.ts` (new file):

- Set up a fake workspace under `/tmp`.
- Place a `knowledge-base/test.pdf` inside it.
- Invoke `isPathInWorkspace("knowledge-base/test.pdf", fakeWorkspacePath)` — expect `true`.
- Invoke with `"../../etc/passwd"` — expect `false` (path traversal still blocked by the post-resolve realpath check).
- Invoke with absolute `/etc/passwd` — expect `false`.

These are the canonical behaviors the production agent depends on.

### Phase 4 — End-to-end regression test (workspace PDF summarize via Concierge)

**Objective:** lock in the user-reported reproduction so it cannot silently re-regress.

#### 4.1 Vitest integration test (`apps/web-platform/test/cc-concierge-pdf-summarize-e2e.test.ts`)

This test runs the runner against a real (synthesized) PDF in a temp workspace, with the resolver wired to the real `extractPdfText` and the runner wired to a mock `queryFactory` that captures the system prompt:

1. Build a minimal PDF via `makeMinimalPdf(["Page 1 content from a workspace PDF"])` (reused from `pdf-text-extract.test.ts`).
2. Write it to `<tmp>/knowledge-base/test.pdf`.
3. Set up a fake `users.workspace_path` row pointing to `<tmp>` (mock the Supabase service client).
4. Call `dispatchSoleurGo(...)` with `documentKind: "pdf"` (from the resolver) and `contextPath: "knowledge-base/test.pdf"`.
5. **Assert on the system prompt the queryFactory received:**
   - It contains `<document>` (inline body — extractor succeeded).
   - It DOES NOT contain `PDF_GATED_DIRECTIVE_LEAD` ("The user is currently viewing the PDF document").
   - It DOES NOT contain `PDF_UNREADABLE_DIRECTIVE_LEAD` ("the in-process reader could not extract its text").

This is the LOAD-BEARING regression test. If any future change re-introduces the gated path on a successful-extraction case, this test fails.

#### 4.2 Vitest test for the `read_failed` path

Same shape as 4.1, but the PDF file does NOT exist at the expected path (simulate filename drift):

1. Set `contextPath: "knowledge-base/test.pdf"` but write the file at `knowledge-base/test%20renamed.pdf`.
2. **Assert:**
   - System prompt contains `PDF_UNREADABLE_DIRECTIVE_LEAD` (unreadable directive fired).
   - System prompt DOES NOT contain `PDF_GATED_DIRECTIVE_LEAD`.
   - The user-facing copy substring "I couldn't open this PDF on my end" is in the prompt (from the new `read_failed` mapping).
   - Sentry mirror was called with `op: "extractPdfText.readFile"`.

#### 4.3 Playwright e2e test (deferred to follow-through if existing e2e harness too brittle)

Run via `bun test:e2e` if applicable. Open a KB PDF in the sidebar, ask "Can you please summarize this document?", assert that:
- The reply DOES NOT contain "outside" or "workspace boundary" (case-insensitive).
- Either the reply contains a real summary OR it contains a content-grounded "I cannot read this PDF" reply with one of the canned reasonClauses.
- Zero `review_gate` WS frames are observed on the wire (no Bash modal).

If the existing e2e harness is not wired to a real Supabase instance, this is deferred to a follow-through issue and the Vitest tests in 4.1/4.2 are the primary acceptance gate.

### Phase 5 — Observability + follow-through closure

#### 5.1 Verify Sentry mirroring on the new paths

After deploy, exercise each path manually (or wait for organic traffic):
- `read_failed`: rename a workspace PDF mid-session, ask for summary → Sentry event with `op: "extractPdfText.readFile"`.
- `lazy_import_failed`: not exercisable in production (Node ≥ 22.3 required by package.json); verify the breadcrumb shape via the unit test.

#### 5.2 Close issue #3376 (re-run user's PDF reproduction post-#3353)

After this PR merges, run the user's exact reproduction (`Au Chat Potan - Presentation Projet-10.pdf`, prompt "Can you please summarize this document?") and post the result on issue #3376. Either (a) successful summary OR (b) the new content-grounded `read_failed` reply with no "workspace boundary" string.

#### 5.3 Close issue #3383 (4 pre-existing pdf-text-extract test failures)

After Phase 1 lands, all 8 tests pass. Add `Closes #3383` to the PR body.

#### 5.4 Mention issue #3342 in PR body as `Ref #3342` (do NOT close it)

The `kb-preview-metadata.ts` Buffer-passing concern is adjacent but not addressed by this plan.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Phase 0.1 RED → GREEN: `vitest run test/pdf-text-extract.test.ts` passes 8/8 tests on local Node ≥ 22.3 (no `lazy_import_failed` failures).
- [ ] Phase 0.2 RED → GREEN: new sandbox test asserts `isPathInWorkspace("knowledge-base/test.pdf", "/tmp/fake-workspace")` returns `true` post-fix.
- [ ] Phase 0.3 RED → GREEN: resolver test asserts `documentExtractError === "read_failed"` when `readFile` throws ENOENT, AND Sentry mirror was called.
- [ ] `apps/web-platform/package.json` has `"engines": { "node": ">=22.3.0" }`.
- [ ] `extractPdfText.import` Sentry mirror is on the lazy-import catch (Phase 1.3).
- [ ] `PdfExtractErrorClass` includes `"read_failed"`; `unreadableCopyForClass` has the new case (TS exhaustiveness rail at line 201 fires red until added).
- [ ] `kb-document-resolver.ts` readFile catch returns `{ ..., documentExtractError: "read_failed" }` AND mirrors to Sentry.
- [ ] `kb-document-resolver.ts` text-file readFile catch returns `{}` (no-context) AND mirrors to Sentry.
- [ ] `sandbox.ts isPathInWorkspace` resolves relative paths against `workspacePath`, not `process.cwd()`. New test in `apps/web-platform/test/sandbox-relative-paths.test.ts` covers (a) relative inside workspace → true, (b) relative `..`-traversal → false (post-realpath containment must still reject escape), (c) absolute outside workspace → false, (d) absolute inside workspace → true (existing semantic preserved).
- [ ] **Bug A1: every `Use the Read tool to read "..."` substring in the runner-built system prompts contains an ABSOLUTE path** (matches `^/`), verified via grep on the prompt strings emitted by `buildPdfGatedDirective`, the cc-soleur-go text-too-large branch, and the agent-runner text-too-large branch. Test: spy the queryFactory's `systemPrompt` arg and `expect(systemPrompt).toMatch(/Use the Read tool to read "\/[^"]+"/)` for each.
- [ ] **Bug A1 lock-step parity:** `git grep "Use the Read tool to read"` post-edit shows 3 source matches, all injecting the absolute-path variable. No remaining `"${path}"` or `"${safeContextPath}"` substitutions in a Read-instruction string.
- [ ] Phase 4.1 e2e: assertion that successful PDF extraction → inline-body directive, NOT gated directive. Path-shape lock-in.
- [ ] Phase 4.2 e2e: assertion that `readFile` failure → unreadable directive with `read_failed` copy, NOT gated directive. The user-facing reply NEVER contains "outside" / "workspace boundary".
- [ ] PR body contains `Closes #3383, #3376` and `Ref #3342`.
- [ ] `## User-Brand Impact` section completed; CPO sign-off captured (per `single-user incident` threshold).
- [ ] `compound` skill run before commit; `preflight` passes (Check 6 user-brand-impact gate).

### Post-merge (operator)

- [ ] Re-run the user's reproduction on production (file: `Au Chat Potan - Presentation Projet-10.pdf`, prompt: `Can you please summarize this document?`). Expected: successful summary (Hypothesis A) OR `read_failed` content-grounded reply with no "outside workspace boundary" string.
- [ ] Confirm `extractPdfText.readFile` Sentry op is wired (will only fire on a future organic incident — note in #3377 follow-through).
- [ ] Close #3376 with the re-run result.
- [ ] Verify post-deploy `vercel deploy` succeeded and the new `engines.node` constraint did not break the build (Vercel uses package.json engines for build-image selection).

## Files to Edit

- `apps/web-platform/package.json` (add `engines.node ≥ 22.3.0`)
- `apps/web-platform/server/pdf-text-extract.ts` (add `read_failed` to `PdfExtractErrorClass`; instrument lazy-import Sentry mirror)
- `apps/web-platform/server/kb-document-resolver.ts` (rewrite both readFile catches; mirror to Sentry; surface typed error class)
- `apps/web-platform/server/soleur-go-runner.ts` (add `read_failed` case to `unreadableCopyForClass`; widen `buildPdfGatedDirective` to take absolute path; update caller at line 703; update text-too-large directive at line 722)
- `apps/web-platform/server/agent-runner.ts` (update text-too-large directive at line 763 to inject absolute path; update PDF gated directive caller at line 752)
- `apps/web-platform/server/sandbox.ts` (`isPathInWorkspace` resolves relative paths against workspace; refactor `resolveRealPath` to accept a pre-resolved absolute path or split into two callers)
- `apps/web-platform/test/pdf-text-extract.test.ts` (no edits expected — Bug C fix should make existing tests pass; verify)
- `apps/web-platform/test/cc-dispatcher-concierge-context.test.ts` (update if the text-file `readFile`-catch behavior change broke any assertion; assert system-prompt absolute-path substitution post-fix)
- `apps/web-platform/test/agent-runner-system-prompt.test.ts` (or equivalent) — assert legacy leader text-too-large directive uses absolute path
- `apps/web-platform/CONTRIBUTING.md` OR `apps/web-platform/README.md` — note the Node ≥ 22.3 floor (verify which file exists first via `ls`)

## Files to Create

- `apps/web-platform/test/sandbox-relative-paths.test.ts` (Phase 0.2 + 3.4)
- `apps/web-platform/test/kb-document-resolver-pdf-extract.test.ts` extended OR new — verify if the existing file covers Phase 0.3 / 4.2; if not, add OR extend
- `apps/web-platform/test/cc-concierge-pdf-summarize-e2e.test.ts` (Phase 4.1, 4.2)

## Test Strategy

- **Vitest** (`apps/web-platform`) for all new tests. Use existing `makeMinimalPdf(...)` from `pdf-text-extract.test.ts` for PDF synthesis (per `cq-test-fixtures-synthesized-only`).
- **Mock the queryFactory** for system-prompt assertion tests — no real SDK call needed; we only verify the prompt the runner WOULD have sent.
- **Mock `fs.readFile`** for the `read_failed` test — `vi.spyOn(fs, "readFile").mockRejectedValue(new Error("ENOENT"))`.
- **No new test framework dependencies** — vitest is already used; minimal-PDF byte synthesis is already in the codebase.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled here at plan time.
- When widening `PdfExtractErrorClass`, the three consumer-grep patterns from `cq-union-widening-grep-three-patterns` MUST be run before merging (Phase 2.1). The exhaustive-switch rail at `unreadableCopyForClass`:201 is the load-bearing protection.
- The widening of `isPathInWorkspace` semantic (relative-path resolution) is a security-adjacent change. The test in 3.4 MUST cover the path-traversal case (`../../etc/passwd`) so the post-realpath containment check still rejects escape attempts.
- `engines.node ≥ 22.3.0` may require the contributor README to reflect the floor and may surface CI-environment-image issues. Verify in CI the new constraint does not block any existing workflow that pins a lower Node version (`rg "node-version" .github/workflows/`).
- Do NOT regress the "extractor inlined body → no Read call" path. Phase 4.1 is the lock-in; if that test ever flips to GREEN-without-the-`<document>`-prompt, the `read_failed` extension or the directive picker drifted.
- A `read_failed` reply still says "I can't read this specific PDF — I couldn't open this PDF on my end…". If the model paraphrases and re-introduces "workspace boundary" (because that string is not in the directive copy but is in the model's training prior on sandbox errors), Phase 4.3 Playwright assertion catches it. If 4.3 is deferred, file a follow-through issue to add a model-output post-filter that strips "workspace boundary" from cc-router replies.
- A `read_failed` event in Sentry should be alarming AND ACTIONABLE — it likely indicates a real upload-vs-context_path drift. Alert threshold: file an issue if it fires more than once per user per week post-deploy.
- Bug A (sandbox relative-path resolution) has been latent. Fixing it MAY surface other agent-side relative-path patterns that were SILENTLY denied. Run the e2e suite full-pass post-fix and compare error counts to a baseline run from main.

## Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-05-06-fix-sidebar-pdf-summarize-out-of-boundary-plan.md. Branch: feat-one-shot-sidebar-pdf-summarize-out-of-boundary. Worktree: .worktrees/feat-one-shot-sidebar-pdf-summarize-out-of-boundary/. Issue: #3376 (post-#3353 reproduction follow-through). Plan reviewed, 5-phase fix: Bug A sandbox relative-paths + Bug B resolver readFile-error typed surface + Bug C Node engine pin. Ready for /work.
```
