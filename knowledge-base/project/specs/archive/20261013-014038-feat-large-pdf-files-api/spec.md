---
title: Chapter-Chunking PDF Resolver
issue: 3436
related: 3429, 3430, 3437, 3442
brainstorm: knowledge-base/project/brainstorms/2026-05-07-large-pdf-chapter-chunking-brainstorm.md
status: ready
unblocked_on: 2026-05-07
brand_survival_threshold: single-user incident
---

> **[Updated 2026-05-07]** — Prerequisites landed during the brainstorm session. PR #3430 (bridge fix) merged at 12:49 (`c502e0a5`); #3442 (leader symmetry, closes #3437) merged at 14:25 (`c8949366`). However, #3442 shipped `apps/web-platform/server/leader-document-resolver.ts` as a **parallel** resolver rather than a shared module, so the CTO-recommended shared `resolvePdfArtifactContext` does not exist. FR2 is updated below to reflect this reality. Plan-time decision: extend both resolvers in parallel, OR fold in the shared-resolver refactor as part of this work (FR2.alt below).


# Chapter-Chunking PDF Resolver

Durable fix for the trust-breach in #3429 (silent timeout when a founder uploads a 400-page Manning book to KB and asks "summarize this"). Repurposes #3436 from "Anthropic Files API" to "chapter-chunking via in-process pdfjs extraction + outline-based lazy load + `cache_control` ephemeral cache". See brainstorm for path-rejection rationale.

## Problem Statement

The Concierge PDF flow today inlines PDF text up to `CONCIERGE_INLINE_CAP_BYTES` (~50KB) and falls through to the SDK Read-tool fanout for larger docs. The SDK Read tool reads at most 20 pages per request, which produces a multi-second native-tool spike per page (per learning `2026-05-06-sdk-forward-progress-tool-use-result-resets-per-block-idle.md`) and silent timeouts on book-grade PDFs (#3429). PR #3430's bridge fix turns the silent timeout into a specific refusal with `too_many_pages` directive, but does not deliver summarization on books — the founder's actual expectation when uploading a manuscript or reference doc.

## Goals

1. A founder uploading a typical published book (Manning, O'Reilly, academic press; 200-1000pg with TOC) to KB can ask "what's in here?" and "what does chapter 4 say about X?" via Concierge and receive grounded, content-cited answers.
2. Per-conversation cost stays under existing `cc-cost-caps.ts` ceilings ($2 BYOK / $0.50 Soleur-key) without operator intervention.
3. No new third-party data processor introduced (no Files API upload, no Gemini, no external embedding service).
4. Both BYOK and Soleur-key users get the path; existing caps protect Soleur-key margin.
5. Implementation reuses the shared `resolvePdfArtifactContext` module introduced by #3437.
6. PDFs without a usable outline fall through cleanly to #3430's `too_many_pages` directive (single source of truth for "too big for Concierge to summarize").

## Non-Goals

- **Anthropic Files API integration** — rejected in brainstorm on cost / legal / capability grounds.
- **Multi-LLM vendor (Gemini, OpenAI)** — defer; revisit only if Anthropic cost economics shift or a feature genuinely requires non-Anthropic capability.
- **Cross-chapter / multi-PDF Q&A** ("compare ch 3 and ch 7", "find the same concept across these 3 PDFs") — v1 explicitly does not handle these; track as separate issue.
- **Embedding-based chapter retrieval** — v1 uses LLM-routed TOC selection (cheap Sonnet-200K turn over chapter titles). Embedding retrieval deferred unless TOC routing proves insufficient.
- **Pre-turn cost confirmation modal** — silent caps via `cc-cost-caps.ts` + post-hoc indicator chosen.
- **Pre-flight `count_tokens` API call** — existing post-hoc tracking + caps enforce hard stop.
- **New `usage_ledger` table** — extend `api-usage.ts` only if v1 telemetry proves insufficient.
- **Leader-path-only or Concierge-only divergence** — must use shared `resolvePdfArtifactContext` from #3437.
- **Anthropic DPA verification, privacy policy / GDPR / DPD updates** — not required for this work (no sub-processor change). Track as separate legal-audit issue regardless.

## Functional Requirements

- **FR1 — Outline extraction.** `pdf-text-extract.ts` exposes `extractPdfOutline(buffer): Promise<PdfOutline | null>` that returns a normalized chapter list `{ title, pageStart, pageEnd, depth }[]` derived from `pdfjs.getDocument().getOutline()`. Returns `null` when the PDF has no bookmarks or the outline is too shallow to be useful (heuristic: ≥3 entries OR top-level entries cover ≥80% of pages).
- **FR2 — Resolver shape.** Each resolver (`kb-document-resolver.ts` for Concierge, `leader-document-resolver.ts` for Leader, both shipped via #3430 + #3442) gets a new return variant `{ kind: "chapter-chunked", outline, fullExtractedText }` for "extracted but too long, has outline." Existing variants `{ kind: "inlined", text }` and `{ kind: "directive", directive }` are preserved as-is.
- **FR2.alt — Optional shared-resolver refactor.** Plan-time may choose to extract a shared `resolvePdfArtifactContext` module covering both Concierge + Leader, folding the chapter-chunked variant into the shared shape. CTO's original recommendation; deferred at #3442 implementation time. Plan-time tradeoff: one larger PR vs duplicated chapter-chunking logic across two resolvers. Recommendation: keep duplicated for v1 to keep the PR scoped; file a follow-up to extract shared module when a third consumer or third variant arrives.
- **FR3 — Chapter routing.** When `kind === "chapter-chunked"` and the user's turn is a question, the runner invokes a Sonnet-200K routing turn with prompt: "Given this TOC and user question, return the chapter title most likely to contain the answer, or 'AMBIGUOUS' if multiple chapters apply." On `AMBIGUOUS`, the response surfaces "I can answer from chapter X or chapter Y — which would you like?" without firing the answer turn.
- **FR4 — Chapter content attachment.** The selected chapter's text is attached as a `document` content block on the user message with `cache_control: { type: "ephemeral" }`. Subsequent turns within the same chapter reuse the cache; chapter switches incur a fresh cache write.
- **FR5 — Loaded-chapter surfacing.** Every assistant response generated from a chapter-chunked context begins with a system-injected prefix `[Answering from chapter X: "<title>"]` so the founder sees which chapter was used and can correct ("actually try chapter 7").
- **FR6 — Overflow on no outline.** When `extractPdfOutline` returns `null` AND text exceeds inline cap, the resolver returns `{ kind: "directive", directive: too_many_pages }` reusing PR #3430's factory.
- **FR7 — Single-chapter overflow.** When a single chapter exceeds 200K tokens (rare for typical books), escalate that turn's model to Opus 4.7-1M. If the chapter exceeds 1M tokens, return the bridge directive with a chapter-too-large variant.
- **FR8 — Cost cap interaction.** All chapter-chunking turns flow through existing `cc-cost-caps.ts` per-conv + per-day USD caps. Cap-hit returns the bridge `cost_cap_reached` directive (existing path).

## Technical Requirements

- **TR1 — Outline heuristic constants.** `MIN_OUTLINE_ENTRIES = 3`, `OUTLINE_PAGE_COVERAGE_MIN = 0.8`. Tune via fixture sweep at plan time.
- **TR2 — Cache annotation.** `cache_control: { type: "ephemeral" }` on the chapter content block. Plan-time spike must verify `claude-agent-sdk@0.2.85` exposes per-content-block cache annotation; if not, the chapter-chunking path uses a side `messages.create` call rather than the agent SDK's `query()`.
- **TR3 — Chapter routing model.** Default Sonnet 4.6 / 200K context. Routing prompt is constant + small (TOC titles only ≈ <1K tokens), eligible for prompt cache after first turn of conversation.
- **TR4 — Single source of truth for caps.** No new constants for "max PDF size" — reuse `MAX_AGENT_READABLE_PDF_SIZE` from `agent-runner.ts:911`. The chapter-chunking path raises the **effective** answerable size by decomposing it, not by raising the upload cap.
- **TR5 — Failure tagging.** New `PdfExtractErrorClass` member `outline_unusable` (treated as soft failure → routes to bridge directive). Outline extraction failures (pdfjs internal) → existing `parse_error` class.
- **TR6 — Cache-eligible vs cache-bust.** Each chapter switch re-keys the document content block (different bytes), incurring a fresh cache write. Document this in user-facing copy: "switching chapters re-loads context (one-time cost)."
- **TR7 — Brand-survival threshold.** This work is tagged `single-user incident`. Plan must include a `## User-Brand Impact` section per `hr-weigh-every-decision-against-target-user-impact`. `user-impact-reviewer` agent must sign off pre-merge.
- **TR8 — Sequencing.** ~~Implementation does not start until #3430 (bridge) and #3437 (leader symmetry / shared resolver seam) are merged to main.~~ **[Resolved 2026-05-07]** Both prerequisites landed during the brainstorm session; implementation may proceed.

## Acceptance Criteria

1. A 400pg published PDF with a TOC uploaded to KB, with the user asking "summarize chapter 3," produces a content-grounded summary citing chapter 3 specifically. Round-trip latency < 8s p95.
2. The same PDF with the user asking "summarize this" produces a TOC-derived overview ("This book has N chapters covering X, Y, Z. Ask about a specific chapter for detail.") on the first turn — not a refusal.
3. A 1000pg PDF with no outline (scanned book) produces the bridge `too_many_pages` directive; the user sees the same refusal copy as without this feature.
4. Per-conversation cost on Sonnet 4.6 stays under $0.50 across a 10-turn chapter-Q&A session (cache hits on chapter content block dominate).
5. Loaded-chapter prefix appears in every chapter-grounded response. A misrouted chapter is correctable in one user turn ("actually chapter 7") without breaking conversation context.
6. `cc-cost-caps.ts` per-conv cap, when hit mid-conversation, produces the existing `cost_cap_reached` bridge directive — no silent failure, no fabricated answer.
7. Both BYOK and Soleur-key users have access; Soleur-key cap of $0.50/conv keeps margin within projected envelope per CFO.
8. No new direct dependency on `@anthropic-ai/sdk` (Files API rejection enforced).
9. Leader path (`agent-runner.ts:842`) gets the same chapter-chunking via the shared `resolvePdfArtifactContext` from #3437 — no path divergence.

## Plan-Time Spikes

- **S1.** Verify `claude-agent-sdk@0.2.85` exposes `cache_control` on content blocks. If not, design the bypass-to-`messages.create` path. (CTO-flagged.)
- **S2.** Empirical pdfjs `getOutline()` coverage on ≥5 fixture PDFs (1 published book, 1 academic paper, 1 scanned book, 1 self-published, 1 manual). Tune `MIN_OUTLINE_ENTRIES` and `OUTLINE_PAGE_COVERAGE_MIN`.
- **S3.** Latency budget for Sonnet-200K chapter-routing turn — measure end-to-end p95 across the fixture set. If >2s, evaluate keyword-match fallback.

## Open Issues to File at Capture Time

1. **Multi-chapter Q&A** — track as separate v2 feature.
2. **Anthropic DPA + privacy/GDPR/DPD audit** — independent of this work; CLO deliverable.
3. **Files API revisit criterion** — track conditions under which Files API would be reconsidered.
4. **Embedding-based chapter retrieval** — alternative to LLM-routed TOC selection if v1 proves fragile.
