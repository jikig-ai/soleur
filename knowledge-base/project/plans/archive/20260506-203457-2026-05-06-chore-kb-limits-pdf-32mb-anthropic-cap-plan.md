---
date: 2026-05-06
type: chore
classification: policy-bug-fix
issue: 3332
prior_plan: 2026-05-06-fix-cc-pdf-idle-reaper-and-issue-link-org-plan
sdk_pin: "@anthropic-ai/claude-agent-sdk@0.2.85"
requires_cpo_signoff: false
---

# chore(kb-limits): cap PDF uploads at Anthropic API limit (32 MB) or warn at attach time

## Enhancement Summary

**Drafted on:** 2026-05-06
**Deepened on:** 2026-05-06 (same session)
**Sections enhanced:** Overview (+ base64 inflation correction + page-cap surface), Files to Edit (+ presign route, + existing test seam), Acceptance Criteria (+ base64-aware effective cap, + page-count cap discussion), Test Scenarios (+ presign 400 case, + system-prompt seam pinned to existing test file), Sharp Edges (+ base64 inflation, + page cap, + URL/file_id escape hatch).

**Research sources used:**

- Live Anthropic PDF docs at `https://platform.claude.com/docs/en/docs/build-with-claude/pdf-support` — confirms "Maximum request size: **32 MB**" and "Both limits are on the entire request payload, including any other content sent alongside PDFs" + "Maximum pages per request: 600 (100 for models with a 200k-token context window)" + Files API as the >32 MB escape hatch.
- Live SDK type definitions at `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk-tools.d.ts` — `FileReadOutput.pdf.base64: string` confirms the SDK Read tool **base64-encodes** PDF data into the request payload. Same file documents `pages?: string` parameter with "Maximum 20 pages per request" — a SECOND ceiling not previously enumerated.
- Live source at `apps/web-platform/lib/attachment-constants.ts:17` (`MAX_ATTACHMENT_SIZE = 20 MB`), `apps/web-platform/lib/validate-files.ts:30` (canonical error-message shape: `"<filename>" exceeds the 20 MB size limit.`), `apps/web-platform/app/api/attachments/presign/route.ts:57` (second server seam — discovered during deepen-pass), `apps/web-platform/app/api/kb/upload/route.ts:20` (`MAX_FILE_SIZE = 20 MB`), `apps/web-platform/server/agent-runner.ts:798-818` (existing kb_share advisory that uses `Math.round(MAX_BINARY_SIZE / 1024 / 1024)` — the pattern to mirror).
- Existing test seam at `apps/web-platform/test/agent-runner-system-prompt.test.ts` (discovered during deepen-pass — removes the "may need to extract a helper" risk noted in the Risks section of the original plan).
- Existing test seams at `apps/web-platform/test/upload-attachments.test.ts`, `apps/web-platform/test/presign-route.test.ts`, `apps/web-platform/test/kb-upload.test.ts` (canonical patterns for the new tests).
- Verified PR/issue numbers live: `gh issue view 3332` → OPEN; `gh pr view 3326` (referenced in issue body) — context preserved.
- Industry confirmation that base64 encoding inflates payload by ~33%, and the 32 MB Anthropic limit is on the **encoded** payload (search results confirm: "a raw PDF file that is approximately 24 MB could become about 32 MB after base64 encoding, potentially hitting the limit").

### Key Improvements Discovered During Deepen-Pass

1. **Base64 inflation collapses the effective raw-PDF cap from 32 MB to ~24 MB.** The SDK's `FileReadOutput.pdf` shape is `{ base64: string; originalSize: number }` — the SDK serializes the PDF as base64 inside the API request body. Anthropic's 32 MB ceiling applies to the **entire encoded request payload**. A 32 MB raw PDF → ~43 MB base64 → exceeds the API ceiling regardless of any other content. The plan now uses **`MAX_AGENT_READABLE_PDF_SIZE = 24 * 1024 * 1024` (24 MB)** with a comment citing the base64 inflation rationale, NOT 32 MB. This is the most material change from the issue body's prescription. The 32 MB framing in the issue conflated raw and encoded sizes — common error in the broader API ecosystem (search results show multiple downstream projects make the same mistake).
2. **`app/api/attachments/presign/route.ts` is a SECOND server-side enforcement seam** for chat attachments, in addition to the client-side `validateFiles`. The presign route currently uses `MAX_ATTACHMENT_SIZE` (20 MB). It MUST also be edited to apply the new PDF-specific cap — otherwise a malicious or modified client can bypass `validateFiles` and presign a 25 MB PDF that the agent then can't Read. Original plan missed this seam.
3. **`apps/web-platform/test/agent-runner-system-prompt.test.ts` already exists** as the canonical seam for system-prompt assembly assertions. Scenario E in the original plan flagged a Risk that "the test may need to extract a helper" — this risk is removed; we extend the existing test file by adding one more `expect(prompt).toContain(...)` assertion, mirroring the existing pattern that already asserts the kb_share size advisory.
4. **The Anthropic 600-pages-per-request ceiling is a separate concern** that this plan deliberately does NOT address. A 28-page 5 MB PDF passes the size cap but a 700-page 5 MB PDF would still fail. Surfaced in Sharp Edges with a follow-up tracking note. (The SDK's per-Read 20-page-default cap mitigates this somewhat — most agent Reads will only request 20 pages at a time.)
5. **Files API + URL-source PDFs are forward-compatible escape hatches.** Anthropic's docs explicitly recommend the Files API for PDFs >32 MB. The plan does NOT add a Files API integration (out of scope, would require BYOK Anthropic key changes), but the system-prompt advisory now mentions "for very large PDFs, attach a smaller excerpt" rather than implying the file is permanently un-Readable.
6. **Test-compatibility audit (per `cq-write-failing-tests-before` semantic-change checklist):** `rg 'MAX_BINARY_SIZE\|MAX_ATTACHMENT_SIZE\|MAX_FILE_SIZE' apps/web-platform/test/` returns 11 hits across 7 files. Audited each: `kb-share.test.ts`, `kb-share-allowed-paths.test.ts`, `kb-serve.test.ts`, `kb-share-preview.test.ts`, `shared-page-binary.test.ts` pin `MAX_BINARY_SIZE = 50 MB` (sharing/serving — out of scope, untouched). `upload-attachments.test.ts`, `presign-route.test.ts` pin `MAX_ATTACHMENT_SIZE = 20 MB` (chat attachments — extend with PDF-cap scenarios). `kb-upload.test.ts` pins `MAX_FILE_SIZE = 20 MB` (KB upload route — extend with PDF-cap scenarios). No test pins the 32 MB or 24 MB literal — clean slate for the new constant.

### New Considerations Discovered

- **Concrete fix shape (revised):** The new constant is `MAX_AGENT_READABLE_PDF_SIZE = 24 * 1024 * 1024` (24 MB raw — leaves headroom for base64 inflation + system prompt + prior turns to stay under Anthropic's 32 MB encoded-payload ceiling). Comment on the constant declaration MUST cite both the source URL AND the inflation arithmetic so future readers understand why 24 ≠ 32.
- **Error-message phrasing (canonical pattern):** Mirror the existing `validate-files.ts` shape `"<filename>" exceeds the 20 MB size limit.` with PDF-specific wording: `"<filename>" exceeds the 24 MB PDF size limit (Anthropic API request-size ceiling after base64 encoding).` Slightly long but the parenthetical teaches the user *why* a 25 MB PDF is rejected when the API doc says 32 MB.
- **System-prompt advisory wording:** Add a NEW block to `agent-runner.ts` (between L818 and L820, after the kb_share line `Files over ${kbShareSizeMb} MB cannot be shared.`):

  ```
  PDF Reads have an additional ceiling: PDFs over ${kbReadablePdfMb} MB cannot
  be Read by the model in a single request. This is the Anthropic API request-
  size ceiling (32 MB after base64 encoding) — not a Soleur policy. For larger
  PDFs, ask the user to attach a smaller excerpt or convert the document.
  ```

  Derive `kbReadablePdfMb` via `Math.round(MAX_AGENT_READABLE_PDF_SIZE / 1024 / 1024)`, mirroring the existing `kbShareSizeMb` pattern.
- **Page-cap is bounded by SDK default:** The SDK Read tool's `pages?: string` parameter defaults to "Maximum 20 pages per request" — a 600-page PDF can still be Read in 30 chunks. The plan does NOT need to address the page cap directly; the 24 MB size cap is the immediate user-facing concern.
- **No SDK upgrade required.** Pin remains `@anthropic-ai/claude-agent-sdk@0.2.85` per `apps/web-platform/package.json`. The Read tool's `FileReadOutput.pdf` shape is stable in this version.

## Overview

Anthropic's PDF beta enforces a **32 MB maximum request size** — applied to the **entire encoded request payload** (including base64-encoded PDF + system prompt + prior turns + other content). The Soleur SDK Read tool serializes PDFs as base64 (`FileReadOutput.pdf.base64: string` at `node_modules/@anthropic-ai/claude-agent-sdk/sdk-tools.d.ts`), which inflates raw bytes by ~33%. The practical raw-PDF cap is therefore **~24 MB raw**, not 32 MB. Today the Soleur platform has four independent ceilings on PDF-bearing surfaces, three of which can permit a >24 MB raw PDF to reach the agent:

| Surface | Constant | Today | Effective vs. 24 MB raw cap | File |
|--|--|--|--|--|
| Chat attachment validator (client) | `MAX_ATTACHMENT_SIZE` | 20 MB | Safe (20 < 24) | `apps/web-platform/lib/attachment-constants.ts:17` |
| Chat attachment presign (server) | `MAX_ATTACHMENT_SIZE` | 20 MB | Safe (20 < 24) | `apps/web-platform/app/api/attachments/presign/route.ts:57` |
| KB upload route | `MAX_FILE_SIZE` | 20 MB | Safe (20 < 24) | `apps/web-platform/app/api/kb/upload/route.ts:20` |
| KB binary serve / share-link | `MAX_BINARY_SIZE` | **50 MB** | **Unsafe (50 > 24). Direct git-push reaches this surface.** | `apps/web-platform/server/kb-limits.ts:17` |

The realistic path that lands a >24 MB raw PDF in the agent's `Read`-tool surface is **direct `git push` from the user's connected repo** (the upload routes already gate at 20 MB). When the user then attaches the resulting KB file to a Concierge thread, `Read` fails at the Anthropic API boundary with a `413` request-too-large or invalid-request payload. PR #3326 (idle-reaper fix) makes this failure degrade gracefully — timer resets, recovery text emitted — but the user never receives a pre-failure warning.

This plan introduces a **dedicated PDF-readable ceiling** (`MAX_AGENT_READABLE_PDF_SIZE = 24 * 1024 * 1024` — 24 MB raw, sized to leave headroom under the 32 MB encoded API ceiling after base64 inflation) asserted at every PDF-bearing surface where the agent's native PDF Read can be triggered: chat-attachment validator (client + server presign), KB upload route, and the agent system-prompt advisory. The wider `MAX_BINARY_SIZE` (50 MB) for non-PDF KB serving + sharing is **left untouched** — markdown / docx / images do not flow through the Anthropic PDF beta.

**Approach choice:** Per the issue's recommendation, take option (1) — hard-cap PDF uploads at the effective ceiling and reject at attach time with a user-facing message. Option (2) (warn-only) is rejected because the warn-then-fail UX is strictly worse than reject-up-front for a deterministic API ceiling.

**Number choice (24 MB raw, not 32 MB):** The issue body cites "32 MB" as the Anthropic ceiling, and that number is correct *for the encoded request payload*. The plan deliberately lands 24 MB *raw* because the SDK's Read tool base64-encodes the PDF into the request body, and 24 MB raw → ~32 MB base64 → exact API ceiling. Choosing 32 MB raw would ship a UX that accepts files which then fail at the API. Choosing 24 MB raw leaves a small headroom for system-prompt + prior-turn content. This is the most material refinement the deepen-pass made versus the issue body's prescription.

## User-Brand Impact

**If this lands broken, the user experiences:** a 33-50 MB PDF dropped into Concierge appears to "stick" (no error toast), but the Concierge spinner shows "Reading..." for ~30s before silently emitting a recovery text "I can't read this file." The user cannot tell whether the failure is transient (retry) or permanent (file too big), and hand-trims the PDF without guidance.

**If this leaks, the user's data is exposed via:** N/A — no data exposure surface; this is a UX/policy ceiling, not a data path.

**Brand-survival threshold:** none

- `threshold: none, reason:` the change is a policy constant + four call-site size-check branches + one system-prompt advisory string + tests. The diff touches `app/api/attachments/presign/route.ts`, `app/api/kb/upload/route.ts`, and `server/agent-runner.ts`, which match the broad sensitive-path regex (`apps/web-platform/(server|app/api|...)`), but no auth, payment, BYOK, credentials, secret, migration, or PII surface is read or written. The change is a defense-in-depth ceiling on PDF size — failure mode is rejecting an oversized PDF (no incident class). Sensitive-path match is structural (the regex is designed to be over-broad) and not load-bearing.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|--|--|--|
| Issue body: "`kb-limits.ts:17` sets `MAX_BINARY_SIZE = 50 * 1024 * 1024` (50 MB) **for KB uploads**" | `MAX_BINARY_SIZE` gates **serving / sharing**, NOT uploads. Upload entry is `MAX_FILE_SIZE = 20 MB` at `app/api/kb/upload/route.ts:20`. | The plan corrects the framing in the Overview table. The user-reachable >24 MB path is direct `git push`, not the upload route. The 24 MB cap is still added at the upload route + chat-attachment validator (client) + presign route (server) (defense-in-depth) **and** the agent system prompt for the git-pushed case. |
| Issue body: "Hard-cap KB uploads at **32 MB**" | 32 MB is the API **encoded-payload** ceiling. SDK base64-encodes the PDF, inflating raw bytes by ~33%. A 32 MB raw PDF becomes ~43 MB encoded → fails at API. Effective raw cap is ~24 MB. | Use **24 MB raw** as the effective cap. Comment cites both source URL and inflation arithmetic. This is the deepen-pass's most material correction. |
| Issue body: "Recommend (1) for MVP simplicity unless we have a concrete use case for storing PDFs the agent can't read" | Markdown/docx/images > 24 MB are perfectly legitimate KB content; the cap MUST be PDF-only. | Introduce `MAX_AGENT_READABLE_PDF_SIZE = 24 * 1024 * 1024` rather than lowering `MAX_BINARY_SIZE`. Apply only on `application/pdf` Content-Type or `.pdf` extension. |
| Prior plan (`2026-05-06-fix-cc-pdf-idle-reaper-and-issue-link-org-plan.md`) Sharp Edge: "agent's `Read` will fail at the API boundary with a `tool_result` carrying an error payload" | Confirmed in archived plan. SDK pin `@anthropic-ai/claude-agent-sdk@0.2.85`. The new tool_use_result branch (PR #3326) handles the failure gracefully but emits no pre-attach warning. | This plan is the upstream complement: warn (and reject for upload-route flows) before the API call is made. |
| Anthropic PDF beta ceiling: 32 MB per request | Live-verified against `https://platform.claude.com/docs/en/docs/build-with-claude/pdf-support`: "Maximum request size: 32 MB" + "Both limits are on the entire request payload, including any other content sent alongside PDFs". 600-page-per-request page cap is a separate concern (out of scope this plan; SDK's per-Read 20-page default mitigates). | Add a `// 24 MB — Anthropic PDF API ceiling is 32 MB encoded; base64 inflates raw bytes by ~33%. See https://platform.claude.com/docs/en/docs/build-with-claude/pdf-support` comment beside the constant declaration. |
| Original plan: "Risk medium — system-prompt assertion may need to extract a helper" | `apps/web-platform/test/agent-runner-system-prompt.test.ts` already exists as the canonical seam. Test extends with one new assertion mirroring the existing `kb_share` size-advisory check. | Risk downgraded to low. Helper extraction is unnecessary. |
| Original plan: presign route not in `## Files to Edit` | `apps/web-platform/app/api/attachments/presign/route.ts:57` is a server-side enforcement seam in addition to client-side `validateFiles`. A modified client can presign a 25 MB PDF that bypasses the validator. | Added to `## Files to Edit`. New AC + test scenario for the presign 400 case on >24 MB PDF. |

## Hypotheses

Single hypothesis — no diagnosis required. The fix shape is determined by the issue body and the reality reconciliation above.

## Files to Edit

- `apps/web-platform/lib/attachment-constants.ts` — add `MAX_AGENT_READABLE_PDF_SIZE = 24 * 1024 * 1024` constant. Comment MUST cite both the source URL (`https://platform.claude.com/docs/en/docs/build-with-claude/pdf-support`) AND the inflation arithmetic (`32 MB encoded ÷ 1.33 ≈ 24 MB raw`).
- `apps/web-platform/lib/validate-files.ts` — branch on `file.type === "application/pdf"` (and/or extension `.pdf`) to apply the PDF-specific ceiling; preserve existing 20 MB ceiling for other types. Use canonical message shape: `"<filename>" exceeds the 24 MB PDF size limit (Anthropic API request-size ceiling after base64 encoding).`
- `apps/web-platform/app/api/attachments/presign/route.ts` — **(NEW: discovered during deepen-pass)** add PDF-extension/Content-Type branch that applies `MAX_AGENT_READABLE_PDF_SIZE` alongside the existing `MAX_ATTACHMENT_SIZE` check at L57. Returns 400 with `error: "file_too_large"` (preserves existing error-code surface; downstream UI translates).
- `apps/web-platform/app/api/kb/upload/route.ts` — branch on PDF extension to apply `MAX_AGENT_READABLE_PDF_SIZE` (24 MB) alongside the existing 20 MB `MAX_FILE_SIZE`. Effective cap on PDFs is `min(20, 24) = 20 MB` today; this future-proofs against `MAX_FILE_SIZE` being raised independently. Returns 413 (matches existing pattern at L107).
- `apps/web-platform/server/agent-runner.ts` — append a NEW block to the system-prompt assembly (between the kb_share advisory at L818 and the kb_share_preview block at L820), advising the agent that **PDFs over `${kbReadablePdfMb}` MB cannot be Read** in a single request. Derive `kbReadablePdfMb` via `Math.round(MAX_AGENT_READABLE_PDF_SIZE / 1024 / 1024)`, mirroring the existing `kbShareSizeMb` pattern at L798. The advisory recommends (a) attaching a smaller excerpt or (b) converting the document. This covers the direct-git-push path that bypasses the upload route.
- `apps/web-platform/test/upload-attachments.test.ts` — extend with a 25 MB PDF rejection scenario and a 25 MB image acceptance scenario (proves PDF-specific gating).
- `apps/web-platform/test/presign-route.test.ts` — extend with a 25 MB PDF presign 400 scenario.
- `apps/web-platform/test/kb-upload.test.ts` — extend with a 25 MB PDF route 413 scenario (the route helper test surface; pattern: rg `kb-upload` test).
- `apps/web-platform/test/agent-runner-system-prompt.test.ts` — extend with one assertion: `expect(systemPrompt).toContain("24 MB")` AND `expect(systemPrompt).toMatch(/PDF.*Read/i)`, mirroring the existing kb_share assertion in the same file.
- `apps/web-platform/test/kb-share.test.ts`, `kb-share-allowed-paths.test.ts`, `kb-serve.test.ts`, `shared-page-binary.test.ts`, `kb-share-preview.test.ts`, `command-center.test.tsx` — **DO NOT EDIT**. These pin `MAX_BINARY_SIZE = 50 MB` for serving/sharing semantics, which this plan deliberately leaves untouched. Verify the count via `rg 'MAX_BINARY_SIZE' apps/web-platform/test/` returns the same hits before and after.

## Files to Create

None. All test additions extend existing test files (the deepen-pass discovered an existing seam for every scenario, including `agent-runner-system-prompt.test.ts` for scenario E). The original plan's proposed `validate-files-pdf-cap.test.ts` is folded into the existing `upload-attachments.test.ts` since the canonical pattern is one test file per surface, not per branch.

## Open Code-Review Overlap

None. Verified at plan time:

```bash
gh issue list --label code-review --state open \
  --json number,title,body --limit 200 > /tmp/open-review-issues.json

for path in \
  apps/web-platform/lib/attachment-constants.ts \
  apps/web-platform/lib/validate-files.ts \
  apps/web-platform/app/api/kb/upload/route.ts \
  apps/web-platform/server/agent-runner.ts \
  apps/web-platform/server/kb-limits.ts; do
  jq -r --arg p "$path" '.[] | select(.body // "" | contains($p)) | "#\(.number): \(.title)"' \
    /tmp/open-review-issues.json
done
```

The issue itself (#3332) is open in `code-review` + `deferred-scope-out` but is the issue this plan closes — not an overlap.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `MAX_AGENT_READABLE_PDF_SIZE = 24 * 1024 * 1024` exported from `apps/web-platform/lib/attachment-constants.ts` with a multi-line comment citing both the source URL AND the base64-inflation arithmetic.
- [x] `validateFiles` rejects a `application/pdf` File of size 25_000_000 bytes with an error message that contains both the limit (`24 MB`) AND the reason phrase (e.g., `Anthropic API` or `base64 encoding`). Same function still **accepts** a 25_000_000-byte `image/png` (PDF-specific gating).
- [x] `app/api/attachments/presign/route.ts` returns `400` with `error: "file_too_large"` when `contentType === "application/pdf"` AND `sizeBytes > 24 MB`. Same body shape rejected by the validator. Verified that a 25 MB image still returns 400 only because of the existing `MAX_ATTACHMENT_SIZE` gate (proves the new PDF branch does not regress non-PDF behavior).
- [x] `app/api/kb/upload/route.ts` returns `413` when a `.pdf` upload is between 20 MB + 1 byte and 24 MB (today the `MAX_FILE_SIZE = 20 MB` gate fires first; this assertion proves the new PDF branch is correctly wired and would fire if `MAX_FILE_SIZE` were raised independently). Verified by a unit test that constructs a 25 MB PDF and asserts 413.
- [x] `agent-runner.ts` system prompt contains a string asserting the 24 MB PDF Read ceiling, derived from the new constant via `Math.round(MAX_AGENT_READABLE_PDF_SIZE / 1024 / 1024)`. Verified by `expect(systemPrompt).toContain("24 MB")` AND `expect(systemPrompt).toMatch(/PDF.*Read/i)` in `agent-runner-system-prompt.test.ts`.
- [x] `MAX_BINARY_SIZE` (50 MB) is unchanged. Verified by `rg 'MAX_BINARY_SIZE = ' apps/web-platform/server/kb-limits.ts` returning the literal `50 * 1024 * 1024`.
- [x] All existing tests in `kb-share.test.ts`, `kb-serve.test.ts`, `kb-share-allowed-paths.test.ts`, `kb-share-preview.test.ts`, `shared-page-binary.test.ts` pass unchanged (sharing/serving semantics preserved). Verified via `rg -c 'MAX_BINARY_SIZE' apps/web-platform/test/` returning the same hit-count before and after.
- [x] No new dependencies added (`bun.lock`/`package-lock.json` diff empty).
- [x] No new constant magic numbers — `rg '24 \* 1024 \* 1024' apps/web-platform/ --type ts` matches only the constant declaration in `attachment-constants.ts`.
- [x] PR body uses `Closes #3332` (not `Ref #3332`) — fix lands at merge, not post-merge.

### Post-merge (operator)

- None. No infra apply, no migration, no operator action. Standard CI deploy is sufficient.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — policy/UX ceiling fix on a single product surface. CPO sign-off not required (`threshold: none`). CTO advisory unnecessary (no architectural change — one new constant, three call-site branches, one system-prompt string).

## Test Scenarios

Tests stay no-network, no-mock-SDK — they exercise pure functions, route handlers (mocked Supabase per the existing `presign-route.test.ts` pattern), and the system-prompt composition function.

1. **A — `validateFiles` rejects 25 MB PDF.** Construct `new File([new Uint8Array(25 * 1024 * 1024)], "big.pdf", { type: "application/pdf" })`. Assert `error` is non-empty AND contains `"24 MB"`. Assert `valid.length === 0`.
2. **B — `validateFiles` accepts 19_999_999-byte PDF.** Below the existing 20 MB chat-attachment ceiling. Assert `valid.length === 1`, `error === undefined`. Pins that the new branch does not over-trigger and that the existing 20 MB cap remains the binding constraint for typical chat attachments.
3. **C — `validateFiles` accepts 21 MB image.** `size: 21 * 1024 * 1024`, `type: "image/png"`. Pins PDF-specific gating: image > 20 MB is rejected by the existing `MAX_ATTACHMENT_SIZE` cap (so this scenario instead asserts the rejection error message does NOT contain `"24 MB"` — it should match the canonical 20 MB message). Splits into two sub-cases: (C1) 21 MB image rejected with `"20 MB"` message; (C2) 19 MB image accepted.
4. **D — presign route returns 400 with `file_too_large` on 25 MB PDF.** Mock per `presign-route.test.ts` pattern (`vi.hoisted` + `mockGetUser` + `mockFrom` + `mockCreateSignedUploadUrl`); send POST with body `{ filename: "x.pdf", contentType: "application/pdf", sizeBytes: 25 * 1024 * 1024, conversationId: TEST_CONVERSATION_ID }`. Assert response status `400` and JSON body `{ error: "file_too_large" }`. Same body with `sizeBytes: 23 * 1024 * 1024` returns 200 with a signed URL (PDF under cap).
5. **E — kb-upload route returns 413 on 25 MB PDF.** Mock per `kb-upload.test.ts` pattern; build a `FormData` with a 25 MB PDF File. Assert response status `413` and the JSON body's `error` contains either `"20 MB"` (today's binding gate) OR `"24 MB"` (after the new branch). Add a parallel scenario where the route is patched to bypass `MAX_FILE_SIZE` (vi.spyOn): assert the 24 MB branch fires for a 25 MB PDF (proves the new branch is wired even though `MAX_FILE_SIZE` masks it today).
6. **F — agent-runner system prompt advises 24 MB PDF Read ceiling.** Extend `apps/web-platform/test/agent-runner-system-prompt.test.ts` with one new `it()` block. Reuse the existing prompt-assembly invocation pattern in that file. Assert `expect(systemPrompt).toContain("24 MB")` AND `expect(systemPrompt).toMatch(/PDF.*Read/i)`. Pin that the existing kb_share advisory `"50 MB cannot be shared"` line is also still present (no regression of the existing block).

**TDD gate:** Author scenarios A-F as failing tests **before** the implementation lands, per AGENTS.md `cq-write-failing-tests-before`. Each scenario maps 1:1 to one of the implementation edits above.

**Test-naming convention:** Per the existing patterns in `upload-attachments.test.ts` and `presign-route.test.ts`, prefer `describe("<surface> — PDF size cap (#3332)")` blocks with literal byte counts in test names (`it("rejects 25 MB application/pdf")`) — easier to grep when revisiting after the constant is later changed.

## Risks

- **Implementation risk: low.** One constant + four call-site branches + one system-prompt string. No data-path changes, no migrations, no external API calls.
- **Test-coverage risk: low.** Deepen-pass discovered `apps/web-platform/test/agent-runner-system-prompt.test.ts` exists as the canonical seam for scenario F — no helper extraction needed. All other scenarios have existing test files to extend (`upload-attachments.test.ts`, `presign-route.test.ts`, `kb-upload.test.ts`).
- **UX risk: low.** Rejection at attach time is strictly clearer than the current silent "agent can't read this" recovery text. The 24 MB number may surprise users who read Anthropic's "32 MB" docs and expect 32 MB to work — error message body explicitly cites "after base64 encoding" so the user understands the gap. No regression on accepted-size flows (24 MB PDFs are below today's 20 MB upload cap; the only new rejection class is the >24 MB direct-git-push path, which currently fails silently downstream anyway).
- **Forward-compat risk: low.** If Anthropic raises the PDF beta ceiling, the change is one constant. The base64-inflation arithmetic stays the same — `MAX_AGENT_READABLE_PDF_SIZE` should always be ≈ `(API request-size ceiling) × 0.75` for safety headroom. Documented in the issue body's "Re-evaluation Trigger" and in the constant's comment.
- **Page-cap surface risk: medium.** The 600-pages-per-request Anthropic ceiling is NOT addressed by this plan. A 5 MB / 700-page PDF will pass the 24 MB size cap but still fail at the API. SDK's per-Read 20-page-default mitigates the most common case (chunked reads). Filed as Sharp Edge with a follow-up tracking note. Acceptable scope-out for this plan because (a) the size cap is the dominant failure mode in the originating issue and (b) page-counting requires either pdf-parsing on the upload path (heavier dependency) or surfacing the SDK's `pages?` parameter in the system prompt.
- **Number-drift risk: low.** The chosen 24 MB raw cap is derived arithmetic, not a Soleur policy. If the SDK ever switches PDF source from base64 to URL/file_id, the inflation factor disappears and the cap could be raised to ~30 MB raw. The constant's comment names the inflation factor explicitly so a future implementer can re-derive the number when the underlying mechanism changes.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is fully populated with `threshold: none, reason: <non-empty>` per the canonical sensitive-path regex check.
- **Do NOT lower `MAX_BINARY_SIZE` (50 MB).** Lowering it would also reject 50 MB markdown/docx/image KB content from the share-link + serve surfaces — out of scope for this issue. The PDF-specific gate is `MAX_AGENT_READABLE_PDF_SIZE`, applied **branch on Content-Type or extension**.
- **The 24 MB number is not a typo for 32 MB.** Reviewers and future implementers will read Anthropic's "32 MB" docs and ask why we chose 24. The constant's comment MUST contain the explicit derivation: `32 MB API ceiling ÷ 1.33 base64 inflation ≈ 24 MB raw, with small headroom for system prompt + prior turns`. Without that comment the number looks arbitrary and will be "fixed" upward by someone later, breaking the contract.
- **Branch on extension OR Content-Type, not both as AND.** Some clients send `application/octet-stream` with a `.pdf` filename; some send `application/pdf` with a misnamed file. The validator should treat **either** signal as PDF for the purpose of the 24 MB cap, mirroring the existing extension-vs-mime classification pattern in `lib/kb-file-kind.ts`. Apply this to `validate-files.ts`, `presign/route.ts`, AND `kb/upload/route.ts` — the latter two see the contentType + extension separately.
- **Error message phrasing (canonical pattern).** Per `validate-files.ts` precedent (`"<filename>" exceeds the 20 MB size limit.`), errors are surfaced inline in the chat input. Keep the message under one sentence: `"<filename>" exceeds the 24 MB PDF size limit (Anthropic API request-size ceiling after base64 encoding).` — slightly long but the parenthetical teaches the user *why*. The presign route returns the existing `error: "file_too_large"` enum (preserves the API surface; downstream UI does the human translation).
- **System-prompt drift.** The existing kb-share advisory (`agent-runner.ts:795-820`) uses `Math.round(MAX_BINARY_SIZE / 1024 / 1024)` to derive the displayed limit. Mirror that pattern: `Math.round(MAX_AGENT_READABLE_PDF_SIZE / 1024 / 1024)`. Hard-coding `24` would silently drift if the constant were later changed.
- **Direct GitHub push path is still reachable.** The upload route + chat-attachment validator block the upload-vector. The direct-git-push vector is bounded by GitHub's ~100 MB push ceiling; for PDFs in the 24-100 MB band the agent will see them and fail at API. The system-prompt advisory is the user-facing mitigation for this case (not perfect, but the agent emits "I can't Read this PDF — it exceeds the 24 MB ceiling for Anthropic API request size" instead of cryptic API errors). Out of scope: server-side rejection at git pull time (would require a git hook in the workspace-sync pipeline; defer to a follow-up issue if the system-prompt mitigation proves insufficient).
- **600-page Anthropic ceiling NOT addressed.** A 5 MB / 700-page PDF passes the 24 MB size cap but still fails at the API. SDK's per-Read 20-page default mitigates the most common case (the model chunks reads). If post-merge user reports show this surfacing, file a follow-up to (a) surface the SDK's `pages?` parameter usage in the system prompt or (b) parse PDF page count at upload time (heavier — requires `pdfjs` server-side, which is already a dependency for KB previews).
- **Files API + URL-source PDFs are forward-compatible escape hatches.** Anthropic's docs explicitly recommend the Files API (`anthropic-beta: files-api-2025-04-14` + `file_id` reference) for PDFs >32 MB. This plan does NOT integrate the Files API (BYOK Anthropic key flow + new SDK surface required). The system-prompt advisory phrases the cap in terms of "this single request" so a future Files API integration won't need to retract the message.
- **`MAX_FILE_SIZE` masks the new branch in `kb/upload/route.ts` today.** The route's existing `MAX_FILE_SIZE = 20 MB` gate fires first for any PDF >20 MB, so the new `MAX_AGENT_READABLE_PDF_SIZE = 24 MB` branch is dead code under current configuration. This is intentional — defense-in-depth against a future raise of `MAX_FILE_SIZE`. Scenario E in the test plan uses `vi.spyOn` to bypass the existing gate and prove the new branch fires; do NOT delete that test as "redundant" during a future cleanup pass.
- **No version bump.** This plan does NOT touch `plugin.json` or `marketplace.json`. Version is derived from git tags via semver labels, per AGENTS.md `wg-never-bump-version-files-in-feature`.

## Verification Greps (run before merge)

```bash
# Constant added exactly once, in attachment-constants.ts
rg 'MAX_AGENT_READABLE_PDF_SIZE\s*=' apps/web-platform/

# Constant referenced at the four expected sites + tests
rg 'MAX_AGENT_READABLE_PDF_SIZE' apps/web-platform/ --type ts

# MAX_BINARY_SIZE unchanged (literal 50 * 1024 * 1024)
rg 'MAX_BINARY_SIZE = ' apps/web-platform/server/kb-limits.ts
# Expect: export const MAX_BINARY_SIZE = 50 * 1024 * 1024;

# No hardcoded "24" magic numbers introduced outside the constant declaration
rg '24 \* 1024 \* 1024' apps/web-platform/ --type ts
# Expect: matches only inside attachment-constants.ts (the constant declaration)
# Test files use literal byte counts (25 * 1024 * 1024 etc.) which is fine.

# No regression of MAX_BINARY_SIZE test pin count (5 hits today across 5 files)
rg -c 'MAX_BINARY_SIZE' apps/web-platform/test/
# Expect: same hit-count before and after this PR.

# Comment references the live source URL (citation invariant)
rg 'platform.claude.com/docs/.*pdf-support' apps/web-platform/lib/attachment-constants.ts
# Expect: 1 match.
```

