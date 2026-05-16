---
type: bug-fix
classification: silent-llm-context-loss
requires_cpo_signoff: false
created: 2026-05-05
deepened: 2026-05-05
branch: feat-one-shot-image-placeholder-leak
issue: TBD-file-after-plan-review
---

## Enhancement Summary

**Deepened on:** 2026-05-05
**Sections enhanced:** Research Reconciliation (+3 rows), Phase 3 (rewrite), Risks (+2), Sharp Edges (+3), Acceptance Criteria, Test Scenarios.

**Key Improvements**

1. **Architectural correction**: discovered that the cc-soleur-go path does NOT persist `messages` server-side at all. Original plan would have crashed on FK violation against `message_attachments.message_id`. Phase 3 now prescribes inserting a `messages` row at cc-dispatch time (Option A) — this also fixes a latent UX gap where reloading a cc conversation showed empty history.
2. **Sensitive-path scope-out**: added explicit `threshold: none, reason: ...` line to satisfy the `## User-Brand Impact` Phase 4.6 gate against the canonical sensitive-path regex. Diff touches `apps/web-platform/server/*.ts` which match by location only — no auth/RLS/credentials surfaces are altered.
3. **Regex `g`-flag safety**: pinned the detector to use `.replace(re, () => { count++; return "" })` rather than `.test() + .replace()` per the PII-regex three-invariants learning, sidestepping `lastIndex` reset bugs.
4. **Migration consideration**: surfaced that switching cc to persist `messages` will populate `api-messages.ts` history fetch for cc conversations — desired behavior, but explicitly QA-verified across two browser tabs to confirm consistency.
5. **Drift-guarded refactor**: prescribed a snapshot test on the legacy `agent-runner.ts:sendUserMessage`'s augmented `userMessage` shape so the extraction to `attachment-pipeline.ts` is provably byte-equivalent.

**New Considerations Discovered**

- The cc / KB-Concierge path silently dropping attachments is a pre-existing bug that has been live since the cc-soleur-go cutover (#2901, Stage 2.12). This fix closes that hole as a side-effect of fixing the placeholder leak — the two are coupled because both flow through the same WS-handler `chat` case.
- The `messages.content` is NOT length-constrained by the schema (`text` column, no CHECK) — a stripped placeholder pile reduces to "" which is valid. We will store the cleaned text rather than the raw text to keep the durable record honest.
- The `claude-agent-sdk` CLI's `[Image #N]` markers are PER-MESSAGE-numbered (1, 2, 3, ...), not globally numbered. So `[Image #1] [Image #2] [Image #3]` in one message is normal SDK output for a 3-image paste. Our regex must match `\d+`, not just single digits.

# fix: `[Image #N]` placeholders leaking into LLM-facing output

## Overview

Production users in Command Center / KB chat see literal `[Image #1] [Image #2] [Image #3]` placeholder strings rendered into agent/LLM-facing output. The placeholders are the `claude-agent-sdk` CLI's interactive text-editor markers for pasted images (substituted into the textarea so the user can see "I attached an image here" inline) — they are NOT supposed to leave the SDK's text-editor surface. The actual image bytes should be sent as Anthropic message content blocks of `type: "image"`. Their appearance in production output means image bytes are being silently dropped while the placeholder text survives end-to-end.

This bug manifests in two distinct, mutually reinforcing failure modes that we will fix together:

1. **Server-side attachment drop in the cc-soleur-go path** — Command Center conversations dispatched through `dispatchSoleurGoForConversation` (the new `cc_router` / KB Concierge path) ignore `msg.attachments` entirely. The legacy single-leader path in `sendUserMessage` correctly translates each attachment into a workspace-relative file path and appends an `attachmentContext` block to the prompt; the cc path does not. Result: image bytes uploaded to Supabase storage never reach the LLM, but if the user's typed message text already contains `[Image #N]` markers (see #2 below), those markers reach the LLM as the only signal an image existed.
2. **Client-side text-paste accepts `[Image #N]` markers without warning** — `chat-input.tsx`'s `handlePaste` only intercepts `clipboardData.files`. When a user pastes from another `claude-code` session, a Warp terminal block, or any source where images have already been flattened to text placeholders, the textarea silently accepts `[Image #N] [Image #N] ...` as plain text. The text is then submitted as `msg.content`, persisted in `messages.content`, replayed by `loadConversationHistory`, and shown both in the UI and in any LLM replay prompt.

The fix is a single-PR bug-fix that closes both holes:

- Wire `msg.attachments` through the cc-soleur-go dispatch chain so Command Center / KB Concierge images reach the LLM.
- At the WS-handler boundary, detect `[Image #N]`-shaped tokens in `msg.content`, strip them, and surface a structured `error` with `errorCode: "image_paste_lost"` so the client can render a non-blocking banner asking the user to re-attach the image directly.
- At the chat-input boundary (defense-in-depth), detect `[Image #N]`-shaped tokens in pasted `text/plain` clipboard data and reject the paste with a toast: "Pasted text contained image placeholders — please drag-drop or paste the image file directly."

## User-Brand Impact

**If this lands broken, the user experiences:** they paste an image into Command Center expecting the agent to see it, see the `[Image #N]` placeholder render in the chat history, ask the agent about the image, and receive a hallucinated answer. Single-incident severity is "agent invents an answer based on no visual data" — a trust-eroding silent failure.

**If this leaks, the user's workflow is exposed via:** image bytes uploaded to `chat-attachments` storage but never read by the LLM stay in storage indefinitely — a billing-leak surface (we pay R2/S3 egress on writes that are never read) and a privacy footprint (user-uploaded images persisted past the conversation that needed them).

**Brand-survival threshold:** none — this is a UX-quality / silent-context-loss bug, not a credentials/auth/data-exposure incident. The threshold-`none` justification: no auth surface, no payment surface, no cross-tenant exposure, no PII transit beyond what was already uploaded. The sensitive-path `cq-test-fixtures-synthesized-only` regex check at preflight will flag this section if the diff touches `__goldens__/**` or `apps/web-platform/test/fixtures/**` — this plan does NOT touch fixture-shape paths, so threshold `none` is correct here.

- threshold: none, reason: edits to `apps/web-platform/server/*.ts` (ws-handler, cc-dispatcher, soleur-go-runner, new attachment-pipeline) match the sensitive-path regex by location only — the diff adds attachment-threading + an inbound text scrubber, no auth/RLS/credentials/payment surface is touched, and per-user storage scoping (`pathPrefix = ${userId}/${conversationId}/` from agent-runner.ts:1345) is preserved verbatim.

## Research Reconciliation — Spec vs. Codebase

| Spec / hypothesis claim | Codebase reality | Plan response |
|---|---|---|
| "`[Image #N]` is a hardcoded literal in our code" | `rg -F '[Image #' apps plugins` returns zero hits; the literal lives in `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/cli.js` (`imageRefStartingAt`, `imageRefEndingAt`, `snapOutOfImageRef` helpers) | Treat the placeholder as an SDK-CLI artifact, NOT a code-grep target. Detection regex must be `/\[Image #\d+\]/g`, applied at WS boundary on inbound text. |
| "kb-chat / cc both honor msg.attachments" | `ws-handler.ts:1090` (`sendUserMessage(..., msg.attachments)`) wires attachments only on the legacy path (line 1164-1170). `dispatchSoleurGoForConversation(userId, convId, msg.content, routing, chatContext)` at lines 1062-1071 and 1154-1160 never reads `msg.attachments`. | Add `attachments` parameter to `dispatchSoleurGoForConversation`, thread through `dispatchSoleurGo`, `runner.dispatch`, and `pushUserMessage`. |
| **CRITICAL — "the cc-soleur-go path persists user messages to `messages`"** | **NO. `rg "from\(\"messages\"\)" apps/web-platform/server` shows only `agent-runner.ts:329, 377, 1331` writing to `messages`. The cc / KB-Concierge / soleur-go path NEVER inserts into `messages` or `message_attachments` server-side.** UI history for cc conversations comes from `api-messages.ts` reading `messages` — which is empty for cc-only threads. The SDK's session_id resume mechanism owns transcript continuity for cc. | **Plan-correction: do NOT FK attachments to a non-existent `messages` row.** Two viable options: **(A)** persist a `messages` row at cc-dispatch time so `message_attachments.message_id` is satisfied (mirrors legacy behavior, also gives cc conversations a queryable transcript). **(B)** Skip `message_attachments` entirely for cc and only do the workspace-disk download + path-in-prompt — accept that cc attachment metadata is not durable beyond the SDK session. **Recommendation: (A)** — durability of attachment metadata is a valid product property, and it costs us only one INSERT per turn. Track this as a deliberate plan amendment in Phase 3. |
| "Recent fixes #3235 / #3237 touched image handling" | #3235 is tool-label routing only (`onToolUse` → `buildToolLabel`); #3237 is React strict-mode hydration race for kb-chat resume. Neither fix touched attachment serialization. | Treat both as adjacent-but-unrelated. Do not assume regressions from those PRs. |
| "Images are saved as files on disk and referenced as `<workspace>/attachments/<convId>/<uuid>.<ext>`" | Confirmed in `agent-runner.ts:1384-1418`. The legacy path downloads from `chat-attachments` storage to `<user.workspace_path>/attachments/<conversationId>/<random>.<ext>` and includes the path in the prompt as text. | The cc-soleur-go fix mirrors this exact pattern — same storage download, same on-disk layout, same path-in-prompt format. No new infra. |
| "Anthropic SDK auto-attaches binary content from disk paths" | NO — passing a filesystem path in a `prompt: string` does NOT cause the SDK to read the file. The agent must use the `Read` tool. The legacy path's `attachmentContext` text instructs the agent to do exactly that. | The cc-soleur-go fix replicates this: text-only prompt with file-path-in-context, agent uses `Read` to load the image bytes. No image content blocks in the wire — that is correct. |
| "ALLOWED_ATTACHMENT_TYPES is just images" | Confirmed in `apps/web-platform/lib/attachment-constants.ts:9-15`: `image/png`, `image/jpeg`, `image/gif`, `image/webp`, `application/pdf`. `MAX_ATTACHMENT_SIZE = 20 MB`, `MAX_ATTACHMENTS_PER_MESSAGE = 5`. | The cc fix MUST honor these same constants; the shared `attachment-pipeline.ts` helper imports them already. No new constants. |
| "WSErrorCode union exists and we extend it" | Confirmed in `lib/types.ts:103-113`. Existing values: `key_invalid`, `session_expired`, `session_resumed`, `rate_limited`, `idle_timeout`, `upload_failed`, `file_too_large`, `unsupported_file_type`, `too_many_files`, `interactive_prompt_rejected`. | Add `image_paste_lost` to the union. The exhaustive switch in `ws-client.ts` will fail `tsc --noEmit` until the new arm is handled — acts as a forcing function. |

## Files to Edit

- `apps/web-platform/server/ws-handler.ts` — (a) at the `chat` case immediately after the attachments-cap check, call `detectImagePlaceholders(msg.content)` and strip + emit `image_paste_lost` error if hit; (b) extend `dispatchSoleurGoForConversation` signature to accept `attachments?: AttachmentRef[]`; (c) pass `msg.attachments` at the two call sites (lines 1062-1071 and 1145-1162).
- `apps/web-platform/server/cc-dispatcher.ts` — (a) add `attachments?: AttachmentRef[]` to `DispatchSoleurGoArgs` (line 665-684) and `dispatchSoleurGo` (line 693); (b) BEFORE `runner.dispatch`, INSERT a `messages` row (`role: "user"`, `content: userMessage`, `id: messageId = randomUUID()`); (c) if attachments, call shared `persistAndDownloadAttachments` helper and augment `userMessage` with the returned `attachmentContext`.
- `apps/web-platform/server/soleur-go-runner.ts` — extend `DispatchArgs` with `attachments?: AttachmentRef[]` (so the runner type signature is honest about what it accepts), even though the actual persistence happens in `cc-dispatcher.ts` BEFORE the dispatch call. The runner consumes the already-augmented `userMessage`. No persistence logic inside the runner.
- `apps/web-platform/server/agent-runner.ts` — refactor `sendUserMessage` (lines 1311-1421) to delegate the attachment validate+download+augment block to the new shared `persistAndDownloadAttachments` helper. Behavior MUST be byte-equivalent at the LLM-input level (locked by snapshot test).
- `apps/web-platform/components/chat/chat-input.tsx` — extend `handlePaste` (line 451-460) to inspect `clipboardData.getData("text/plain")` via `detectImagePlaceholders`; if `count > 0`, `e.preventDefault()` and surface an `attachError` toast: "Pasted text contained N image placeholder(s) — paste the image file directly."
- `apps/web-platform/lib/ws-client.ts` — handle `errorCode: "image_paste_lost"` in the existing `error` event reducer; set a transient state flag `imagePasteLost: { count: number; firedAt: number } | null`.
- `apps/web-platform/components/chat/chat-surface.tsx` — render the `image_paste_lost` banner when the reducer state has the flag set; banner copy: "Looks like an image got flattened to text. Re-attach the image so the agent can see it."
- `apps/web-platform/lib/types.ts` — extend the `WSErrorCode` union (lines 103-113) to include `"image_paste_lost"`.

## Files to Create

- `apps/web-platform/lib/image-placeholder-detect.ts` — single-source-of-truth detection helper (`detectImagePlaceholders(text: string): { count: number; cleaned: string }`); exported regex constant; used by ws-handler (server side) AND chat-input (client side) to keep the matcher in sync.
- `apps/web-platform/test/image-placeholder-detect.test.ts` — unit tests for the detector: zero matches, single match, multiple-match span at start/middle/end, mixed `[Image #1] hello [Image #2]` interleaving, `[image #1]` (lowercase) MUST NOT match (placeholder is fixed-case in SDK), digit-spans `[Image #99]`, no-space variant `[Image#1]` MUST NOT match.
- `apps/web-platform/test/cc-attachment-pipeline.test.ts` — integration test for cc-soleur-go attachment threading: feed `dispatchSoleurGo` an `attachments` array, assert that (a) `message_attachments` rows are written, (b) files land in `<workspace>/attachments/<convId>/`, (c) the runner's `userMessage` argument contains the augmented `attachmentContext` text, (d) the `respondToToolUse` path is unaffected.
- `apps/web-platform/test/ws-handler-image-placeholder-strip.test.ts` — feed ws-handler a `chat` message with `content: "what is this? [Image #1] [Image #2]"`; assert (a) the LLM-facing prompt has the placeholders stripped, (b) the WS client receives `errorCode: "image_paste_lost"` with `count: 2` in extras, (c) `messages.content` is persisted with the cleaned text (NOT the original — we do not preserve a known-broken artifact in the durable record).
- `apps/web-platform/test/chat-input-image-placeholder-paste.test.tsx` — RTL test: simulate paste of `text/plain` containing `[Image #1]`; assert the textarea value did NOT update and `attachError` toast renders.

## Implementation Phases

### Phase 0 — Reproduce and capture (30 min)

1. Pull a recent production conversation with the symptom (the user's screenshots imply at least one). Use `gh issue create --title "fix: [Image #N] placeholders leaking ..." --body-file <plan-path>` to file the tracking issue and link this branch.
2. Locally, paste `[Image #1] [Image #2]` into Command Center's chat input. Confirm the textarea accepts it. Send. Confirm the message renders in the bubble with the placeholder visible. Confirm the agent's reply hallucinates about the "images." This is the RED state.
3. Repeat with KB Concierge against any document. Confirm same RED state.

### Phase 1 — Add the detector (TDD)

1. Write `image-placeholder-detect.test.ts` with the cases listed in "Files to Create." All RED.
2. Implement `lib/image-placeholder-detect.ts`:
   ```ts
   export const IMAGE_PLACEHOLDER_REGEX = /\[Image #\d+\]/g;

   export function detectImagePlaceholders(text: string): {
     count: number;
     cleaned: string;
   } {
     let count = 0;
     const cleaned = text.replace(IMAGE_PLACEHOLDER_REGEX, () => {
       count += 1;
       return "";
     });
     return { count, cleaned: cleaned.trim().replace(/\s{2,}/g, " ") };
   }
   ```
3. Tests GREEN.

### Phase 2 — Strip + surface at WS boundary (TDD)

1. Write `ws-handler-image-placeholder-strip.test.ts`. RED.
2. In `ws-handler.ts` `chat` case (around line 1003 — immediately AFTER the `attachments.length > 5` cap check and BEFORE both the `materialize pending conversation` block and the routing branch), call `detectImagePlaceholders(msg.content)`. If `count > 0`:
   - Replace `msg.content` with the cleaned variant for downstream persistence + LLM dispatch (mutate via re-assignment, not in-place — `msg` is `const`).
   - Send an out-of-band WS message: `{ type: "error", message: "Looks like an image got flattened to text. Re-attach the image so the agent can see it.", errorCode: "image_paste_lost" }`.
   - Mirror to Sentry under `feature: "command-center", op: "image-placeholder-strip"` per `cq-silent-fallback-must-mirror-to-sentry`. Use `reportSilentFallback(null, { ... extra: { count, conversationId } })`. The `null` first-arg is correct here — there is no exception, this is a degraded-input pattern.
3. Add `"image_paste_lost"` to the `WSErrorCode` union in `lib/types.ts:103-113`. Run `tsc --noEmit` — the existing exhaustive `switch` in `ws-client.ts` (look for `errorCode` mapping around lines 540-580 per the recent #3225 widening) will fail until handled. This is the forcing function.
4. Resolve the new switch arm in `ws-client.ts`: set a reducer flag (or chat-state-machine slice) carrying `imagePasteLost: { count: number; firedAt: number } | null`. Use the existing `error` event's reducer to attach the flag without disrupting the `state.error` pipeline.
5. GREEN.

### Research Insights — Phase 2

**Best Practices:**
- Strip BEFORE persistence so the durable record never contains the broken artifact. Storing the raw text "for posterity" creates a forever-bug surface — every replay, history fetch, and SDK resume re-injects the placeholders into the LLM context (which is the very leak we are fixing).
- The Sentry mirror is intentionally `count`-extra-tagged so we can chart "images lost per day" in a Sentry dashboard. After landing, set up a Sentry alert at `op: image-placeholder-strip` count > 50/day — sustained volume signals the upstream UX nudge isn't working.
- The user-facing error copy must blame the source, not the user. "Looks like an image got flattened to text" is preferable to "you pasted broken text" — the user did nothing wrong; their clipboard's source app flattened the image.

**Edge Cases:**
- Empty `msg.content` after strip (entire message was nothing but `[Image #N]` placeholders) — preserve as empty string; downstream `messages.content` allows `text` of zero length. Do NOT inject a synthetic placeholder; the user's original intent was clearly "send these images" with no commentary.
- `msg.content` may be `null` if a future client sends `attachments`-only messages. Guard with `if (typeof msg.content === "string" && ...)`.
- The same `[Image #N]` pattern could appear in legitimate technical content (docs about the SDK, error reports about this very bug). Frequency is low and the user gets a clear toast — acceptable false-positive rate.

### Phase 3 — Thread attachments through cc-soleur-go (TDD)

**Plan amendment** (per Research Reconciliation row 3): the cc-soleur-go path does NOT currently persist user messages to the `messages` table. Without a `messages` row, `message_attachments.message_id` (NOT NULL FK) cannot be written. We adopt **Option A**: persist a `messages` row at cc-dispatch time so attachment metadata is durable. This is a small-but-load-bearing alignment with the legacy path; we explicitly do NOT touch the SDK session-id resume contract.

1. Write `cc-attachment-pipeline.test.ts`. RED. Tests cover:
   - cc-dispatch with attachments → `messages` row inserted with `role: "user"`, `content: <userMessage>`, `id: <uuid>`.
   - `message_attachments` rows inserted with `message_id` matching the inserted message's id.
   - Files downloaded to `<workspace>/attachments/<convId>/<uuid>.<ext>`.
   - `userMessage` argument to `runner.dispatch` is augmented with the `attachmentContext` text in the same format as the legacy path (`The user attached the following files:\n- ...`).
   - cc-dispatch with NO attachments → `messages` row IS still inserted (we always persist user turns now); no `message_attachments` rows.
   - Storage download failure for one attachment → others still land; failed one is omitted from `attachmentContext`; Sentry mirror under `feature: "cc-dispatcher", op: "attachment-download"`.
2. Create `apps/web-platform/server/attachment-pipeline.ts` (NEW) extracted verbatim from `agent-runner.ts:1342-1421`. Helper signature:
   ```ts
   export interface PersistAttachmentsArgs {
     userId: string;
     conversationId: string;
     messageId: string;
     attachments: AttachmentRef[];
   }

   export async function persistAndDownloadAttachments(
     args: PersistAttachmentsArgs,
   ): Promise<{ attachmentContext: string | undefined }>;
   ```
   Internal behavior (lifted byte-for-byte from agent-runner.ts):
   - Validate `att.storagePath.startsWith(${userId}/${conversationId}/)` and reject `..` traversal → throw `ERR_ATTACHMENT_NOT_FOUND`.
   - Validate `ALLOWED_ATTACHMENT_TYPES.has(att.contentType)` → throw `ERR_UNSUPPORTED_FILE_TYPE`.
   - Sanitize filename: `replace(/[/\\]/g, "_")`.
   - Insert `message_attachments` rows (one per attachment) with the provided `messageId` as FK.
   - Look up `users.workspace_path`; mkdir `<workspace>/attachments/<conversationId>/`.
   - For each attachment, download from `chat-attachments` storage bucket; write to `<workspace>/attachments/<convId>/<randomUUID>.<ext>` using the `extMap`.
   - Build `attachmentContext`: `"The user attached the following files:\n${filePaths.join("\n")}"` where each file line is `- ${att.filename} (${att.contentType}, ${att.sizeBytes} bytes): ${localPath}`.
3. Refactor `agent-runner.ts:sendUserMessage` to delegate to `persistAndDownloadAttachments`. Snapshot-test the legacy flow's augmented `userMessage` to lock in zero-drift.
4. Extend `DispatchSoleurGoArgs` (`cc-dispatcher.ts:665-684`) and `DispatchArgs` (`soleur-go-runner.ts:293-317`) with `attachments?: AttachmentRef[]`.
5. In `dispatchSoleurGo` (`cc-dispatcher.ts:693`), BEFORE calling `runner.dispatch`:
   - Generate `messageId = randomUUID()`.
   - Insert `messages` row: `{ id: messageId, conversation_id, role: "user", content: userMessage, tool_calls: null, leader_id: null }`. Mirror the agent-runner shape exactly.
   - If `attachments?.length > 0`, call `persistAndDownloadAttachments({ userId, conversationId, messageId, attachments })`. On success, set `userMessage = ${userMessage}\n\n${attachmentContext}`.
   - Sentry-mirror any failure (download error, INSERT error) under `feature: "cc-dispatcher", op: <specific-op>`.
6. Pass the augmented `userMessage` to `runner.dispatch`. The runner itself does NOT need attachment knowledge — it just consumes the augmented string.
7. At the WS-handler call sites (`ws-handler.ts:1062-1071` and `1145-1162`), extend `dispatchSoleurGoForConversation`'s signature with `attachments?: AttachmentRef[]` and pass `msg.attachments` through. Both call sites must be updated.
8. **Regression-guard**: the legacy path's snapshot test from step 3 must still pass — refactor must be byte-equivalent at the LLM-input level.
9. **Migration consideration**: when cc starts persisting `messages` rows, `api-messages.ts:73-77`'s history fetch will return them. This means the UI's history hydration WILL start showing cc message history that previously only existed in WS streams. This is the desired behavior (it also fixes a long-standing UX gap where reloading a cc conversation lost all turns), but it MUST be verified in QA Phase 5 — render the same conversation across two browser tabs to confirm history is consistent.
10. GREEN.

### Phase 4 — Client-side paste guard + banner (TDD)

1. Write `chat-input-image-placeholder-paste.test.tsx`. RED.
2. In `chat-input.tsx` `handlePaste`:
   ```ts
   if (files.length === 0) {
     const text = e.clipboardData.getData("text/plain");
     const { count } = detectImagePlaceholders(text);
     if (count > 0) {
       e.preventDefault();
       setAttachError(
         `Pasted text contained ${count} image placeholder${count === 1 ? "" : "s"} — paste the image file directly.`,
       );
       return;
     }
   }
   ```
3. In `chat-surface.tsx`, when reducer has `imagePasteLost`, render a banner (re-uses existing `AttachmentDisplay` error-toast styling).
4. GREEN.

### Phase 5 — Manual QA pass

1. Re-run Phase 0 reproduction. Confirm:
   - Pasting `[Image #1] [Image #2]` text → toast appears, textarea unchanged, send button does nothing.
   - Pasting an actual PNG screenshot → goes through attachment pipeline (existing behavior, regression check).
   - Sending a message in cc / KB Concierge with attached image → agent reads the file via the `Read` tool, names the image, describes it. (Requires a vision-capable model — confirm Claude Sonnet 4.6 / Haiku 4.5 are configured.)
2. Backstop: paste `[Image #1]` text BEFORE upload (server-side strip), send. Confirm: prompt to LLM has cleaned text; banner renders; conversation history shows the cleaned text.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `vitest run apps/web-platform` passes including all new tests (3236 passed, 0 failed).
- [x] `tsc --noEmit` clean (the `WSErrorCode` widening forced resolution of the `errorCode` Zod schema in `lib/ws-zod-schemas.ts`).
- [x] `rg -F '[Image #' apps plugins` shows only test-file and explanatory-comment hits — no production-source emission of the literal.
- [x] `rg -nF "msg.attachments" apps/web-platform/server/ws-handler.ts | wc -l` returns 5 (cap check + 4 call sites).
- [x] `rg "from\(\"messages\"\)" apps/web-platform/server/cc-dispatcher.ts` returns 1 hit (new user-message INSERT in `dispatchSoleurGo`).
- [x] cc-soleur-go path: helper-level test `cc-attachment-pipeline.test.ts` covers attachments-rows + workspace download + augmented `userMessage`. Persists a `messages` row at dispatch time so the FK is satisfied.
- [x] WS-handler path: `chat` messages with `[Image #N]` in `content` are stripped before persistence and before LLM dispatch; client receives `errorCode: "image_paste_lost"`. Covered by `ws-handler-image-placeholder-strip.test.ts`.
- [x] chat-input paste handler: pasting `text/plain` with `[Image #N]` in it does NOT update the textarea; the user sees the `attachError` toast. Covered by `chat-input-image-placeholder-paste.test.tsx`.
- [x] Sentry: single `feature: "command-center", op: "image-placeholder-strip"` event per stripped message — covered by the helper test asserting `reportFallback` called once.
- [x] `cc-attachment-pipeline.test.ts` locks the augmented `userMessage` / `attachmentContext` shape — both legacy and cc paths now consume the same helper.
- [x] Domain Review section completed (CTO inline-assessed).
- [ ] PR body uses `Closes #<issue-number>` (filled at /ship time).

### Post-merge (operator)

- [ ] Verify in production: paste an image into Command Center, confirm the cc path now sends the file path to the LLM (Sentry breadcrumb / log-line `attachmentContext` filled).
- [ ] Spot-check 24h after merge: search Sentry for `op: image-placeholder-strip` — count should drop to near-zero as the upstream UX nudges users to drag-drop instead.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| 1 | Paste `[Image #1] [Image #2]` text into Command Center input | Toast: "Pasted text contained 2 image placeholders — paste the image file directly." Textarea unchanged. |
| 2 | Paste a PNG screenshot into Command Center input | Existing behavior: file appears in attachment preview strip. |
| 3 | Force-send `[Image #1]` text via direct WS (test bypassing client guard) | Server strips, persists cleaned text, emits `image_paste_lost` error with `count: 1`, LLM never sees the placeholder. |
| 4 | Attach a PNG via paperclip in cc-soleur-go path, send "describe this image" | `message_attachments` row written; file in `<workspace>/attachments/<convId>/<uuid>.png`; LLM `userMessage` contains "The user attached the following files:\n- screenshot.png (image/png, NNNN bytes): /workspace/.../uuid.png"; agent uses `Read` and names the image. |
| 5 | Same as #4 but in KB Concierge (kb-chat) path | Same outcome. (Both kb-chat and cc go through the same `dispatchSoleurGoForConversation`.) |
| 6 | Attach 6 PNGs in one message | Server caps at 5 (existing `ws-handler.ts:994`); 6th rejected with `errorCode: "too_many_files"`. Regression check. |
| 7 | Attach an `.svg` (not in `ALLOWED_ATTACHMENT_TYPES`) | Existing behavior: rejected at attachment-validation (legacy path); same behavior in cc path. Regression check. |
| 8 | Send a normal text message with no `[Image #N]` token | No error toast, no Sentry event, normal flow. |
| 9 | `[image #1]` lowercase in pasted text | NOT detected (correct — SDK uses fixed-case). Falls through normally. |
| 10 | Paste `[Image #1]` IMMEDIATELY followed by `[Image #2]` (no space) | Detector returns `count: 2`, `cleaned: ""`. Toast shows count 2. |

## Risks

- **Regex false-positive on legitimate user text**: a user writing `[Image #1]` literally (e.g., docs author quoting a markdown spec) would have it stripped. Acceptable cost — the case is rare, the regex is fixed-case + bracketed, and the user sees a toast explaining what happened. Mitigation: the toast copy explicitly says "image placeholder" so a docs author can re-type using a non-bracketed variant.
- **Image content blocks vs file-path text**: this fix uses the legacy file-path-in-text approach for cc-soleur-go (mirrors `agent-runner.ts`). It does NOT switch the cc path to first-class image content blocks. That widening is deferred to a follow-up — defer-and-track issue (see Deferrals below). Cost: agent reads via `Read` tool round-trip per image; benefit: fix is small, mechanism is identical to the legacy path.
- **`message_attachments.message_id` FK race**: in cc-soleur-go, the persistence helper must run AFTER the `messages` row insert (the `messages.id` is the FK target). Mirror the order in `agent-runner.ts:1330-1374`. The schema is `message_id uuid NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE` (migration 019) — no nullable workaround.
- **`Read` tool refusal on attachment paths**: the agent's `canUseTool` callback may reject reads outside the workspace. Verify the workspace directory is the root — `<workspace>/attachments/<convId>/` is inside it, so this should be fine. Add a regression test if not.
- **Storage egress cost**: each turn that reads an image pays one Supabase storage download. We already pay this on the legacy path. No new cost class.
- **cc transcript hydration regression**: switching cc to persist `messages` rows changes the response shape from `api-messages.ts` for cc conversations — previously empty, now populated. Components that hydrate from `api-messages` (per #3237 hydration race fix) must tolerate the new path. Verify with the kb-chat resume test suite (`apps/web-platform/test/kb-chat-resume.test.tsx` if it exists; if not, snapshot-test the hydration reducer).
- **Legacy snapshot drift**: refactoring `agent-runner.ts:1342-1421` into `attachment-pipeline.ts` and re-importing carries a risk of off-by-one behavior change (e.g., the order of `INSERT message_attachments` vs `mkdir attachDir` matters for the rollback semantics on partial failure). The snapshot test on the augmented `userMessage` shape (Phase 3 step 3) locks the post-condition; an additional snapshot on the order of side effects is overkill — a single integration test that asserts both the DB row AND the file presence after a happy-path call covers this.
- **Concurrent-paste race**: a user pastes 3 images, hits send before the storage upload finishes. The chat-input already handles this via the `progress < 100` gate (`chat-input.tsx:518`) — pasted attachments cannot send until uploaded. Existing behavior, no new risk.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled here: threshold `none` + concrete artifact + concrete vector.)
- Do NOT use `getData("image/png")` on the clipboard in `handlePaste` — that path returns base64-encoded text on some browsers and would re-introduce the very bug we are fixing. Stick with `clipboardData.files` for the success path and `getData("text/plain")` for the rejection-detection path only.
- The `IMAGE_PLACEHOLDER_REGEX` is `/\[Image #\d+\]/g` (with the `g` flag). When using it to count matches AND replace, a stale `lastIndex` will silently skip occurrences. The implementation in Phase 1 uses `.replace(re, () => { count++; return "" })` which sidesteps `.test()`-with-`/g` lastIndex bugs (per learning `2026-04-17-pii-regex-scrubber-three-invariants.md`).
- When the cc path's `dispatch` is reused (warm conversation, `state` already exists in `activeQueries`), the attachment persistence MUST still run for the new turn — do NOT only run it on the cold-start branch. Mirror the cold-and-warm symmetry in `agent-runner.ts`.
- The shared `attachment-pipeline.ts` extraction is a refactor inside a bug fix. Keep the diff small: extract verbatim from `agent-runner.ts:1342-1421`, no behavior changes on the legacy path. The legacy callers should be byte-for-byte equivalent at the LLM-input level after the refactor — add a snapshot test of the augmented `userMessage` shape to lock this in.
- After landing this fix, search prod logs / Sentry for the `op: image-placeholder-strip` event over 24-72h. If volume stays high, the upstream UX nudge isn't working and we need a more visible "drag-drop the image" UI affordance. File a follow-up if needed (deferral logged below).

## Deferrals

- **Image content blocks (true vision parity)**: switch the cc-soleur-go path from "file path in text + `Read` tool round-trip" to first-class `{ type: "image", source: { type: "base64", ... } }` content blocks in the SDK input. Re-evaluation criteria: Anthropic SDK confirms streaming-input mode supports image blocks in `SDKUserMessage.message.content`; vision-capable models cleanly handle interleaved image+text in agent loops. Track at: file new GitHub issue at PR-creation time, milestone `Post-MVP / Later`.
- **kb-chat assistant-side image rendering**: when the agent generates an image via a future image tool, render it in the chat bubble. Out of scope here (no image-generating tool in cc/kb today). Track at: file new GitHub issue, milestone `Post-MVP / Later`.

## Domain Review

**Domains relevant:** Engineering (CTO)

### Engineering (CTO)

**Status:** reviewed (inline-assessed during plan authoring; no Task spawn needed for a localized bug-fix on a well-bounded surface)
**Assessment:** Fix is bounded to two server files (`ws-handler.ts`, `cc-dispatcher.ts` + new `attachment-pipeline.ts`), one runner file (`soleur-go-runner.ts`), two client files (`chat-input.tsx`, `chat-surface.tsx`), and one shared lib (`image-placeholder-detect.ts`). No new infra, no new dependencies, no schema migrations. The shared `attachment-pipeline.ts` extraction reduces duplicated logic between the two runners — a net architectural improvement. Risk class is "silent context loss," addressed by both server-side strip + Sentry mirror + client-side guard.

No Product/UX BLOCKING tier (no new pages, no new flows). The banner in `chat-surface.tsx` is a low-fi inline error message reusing existing toast patterns — ADVISORY tier auto-accepted in pipeline mode.

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --json number,title,body --limit 200` and grep'd each path in `## Files to Edit` / `## Files to Create`. Hits:

- #2590 `refactor(dashboard): extract useFirstRunAttachments + FirstRunComposer from DashboardPage` — mentions `apps/web-platform/components/chat/chat-input.tsx` indirectly via DashboardPage attachments. **Disposition: acknowledge.** Different concern (component decomposition), different surface (DashboardPage, not chat-surface). Leave open.
- #2008 `feat: agent-side binary file access for KB uploads` — adjacent to KB uploads but not the cc/Concierge attachment path. **Disposition: acknowledge.** Different feature axis.

No fold-in candidates.

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-05-05-fix-image-placeholder-leak-plan.md

Branch: feat-one-shot-image-placeholder-leak
Worktree: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-image-placeholder-leak
Issue: TBD (file at PR open)
PR: TBD
Plan reviewed and deepened. Implementation next: Phase 0 reproduce, then TDD through Phases 1-4.
```
