---
title: Large-PDF Chapter-Chunking PDF Resolver (durable fix for #3429)
date: 2026-05-07
issue: 3436
related: 3429, 3430, 3437
supersedes_approach: Anthropic Files API (originally scoped in #3436)
status: captured
user_brand_critical: true
brand_survival_threshold: single-user incident
---

# Large-PDF Chapter-Chunking PDF Resolver

Brainstorm for #3436 — durable fix for the trust-breach surfaced in #3429 (silent timeout when a founder uploads a 400-page Manning book to KB and asks "summarize this"). The issue originally scoped "Anthropic Files API" as the durable mechanism; this brainstorm pivots to a chapter-chunking resolver after domain-leader assessment surfaced structural cost, legal, and capability gaps in the Files API path.

Implementation blocks on PR #3430 (bridge fix, WIP) and #3437 (leader-path symmetry, parallel session) merging — both introduce the partition rails and shared-resolver seam this work depends on.

## What We're Building

A new resolution path in the Concierge PDF flow that:

1. Extracts the PDF's outline (TOC) using pdfjs `getOutline()` (already-bundled API).
2. When a PDF exceeds the inline cap **and** has a usable outline, returns a `chapter-chunked` artifact shape via the shared `resolvePdfArtifactContext` module introduced by #3437.
3. Lazy-loads the relevant chapter per turn based on the user's question (cheap Sonnet-200K TOC-routing turn), attaching `cache_control: { type: "ephemeral" }` to the document content block so subsequent turns within the same chapter hit cache (~3× cheaper).
4. Falls back to #3430's `too_many_pages` directive when the PDF has no outline (scanned books, un-bookmarked PDFs).
5. Hard-stops on existing `cc-cost-caps.ts` per-conv ($2 BYOK / $0.50 Soleur) + per-day ($25 / $1) USD caps. Silent enforcement; a running cost indicator surfaces in chat (existing `api-usage.ts`).

## User-Brand Impact

**Artifact at risk:** Founder-uploaded PDF (unpublished manuscript, purchased book, reference doc).

**Vectors:**
- **Silent BYOK billing burn** if a single turn balloons past expectation. Mitigated by `cc-cost-caps.ts` hard cap (existing infra). Per-chapter turns on Sonnet 4.6 at <50K input keep per-turn cost under $0.20 typical.
- **Trust-breach via fabricated answer** if the wrong chapter is loaded and the model answers confidently from a different section. Mitigated by surfacing the loaded chapter in the response ("Answering from chapter 3: 'X' — ask about a different chapter to switch") and by chapter-router fallback to "which chapter?" on ambiguity.
- **Data-exposure surprise** if uploaded text persists at the LLM vendor beyond the conversation. Mitigated **structurally** by not using the Files API path: chapter content goes through the standard `messages.create` ephemeral cache, no third-party file storage, no sub-processor reclassification, no DPA renegotiation.

**Brand-survival threshold:** `single-user incident`. A founder uploading their unpublished manuscript and getting a $50 surprise bill, a fabricated answer with no warning, or a sub-processor disclosure surprise — any one qualifies. Plan derived from this brainstorm inherits this threshold.

## Why This Approach (vs Alternatives)

| Approach | Verdict | Reason |
|---|---|---|
| **Chapter-chunking + Opus-1M as needed + cache_control** (chosen) | Selected | Reuses pdfjs (already hardened, #3410/#3424). No new SDK, no DPA, no sub-processor disclosure update, no file lifecycle. Per-chapter Sonnet-200K turns are cheaper than full-book Opus-1M turns. |
| Anthropic Files API (originally scoped in #3436) | Rejected | (1) 100-page cap on 200K-context models means even Files API doesn't deliver "400pg book → grounded summary" on Sonnet 4.6; needs Opus 4.7-1M routing. (2) Requires adding `@anthropic-ai/sdk` direct dep + bypassing agent SDK. (3) **Not ZDR-eligible**, retained-until-deleted on uploader's account → CLO required Anthropic DPA verification + 3 legal-doc updates (privacy policy §5, GDPR Art 30 register, data-protection-disclosure sub-processor reclassification) for Soleur-key mode. (4) Beta API stability risk. |
| Gemini 2.5 Flash for PDFs | Rejected | ~10× cheaper input than Sonnet 4.6, native multimodal PDF, 1-2M context. But: introduces a second LLM vendor to a Claude-Agent-SDK-first stack, shifts the legal sub-processor problem from Anthropic to Google rather than removing it, requires a parallel BYOK Gemini key story, and forces a code path outside the agent SDK. Architectural cost > unit-cost savings at current scale. Revisit if usage data justifies. |
| Inline whole book to Opus 4.7-1M with cache | Partial — this is what chapter-chunking does for the small-book happy path (≤200K tokens / ≤100 pages). For larger docs, chapter-chunking decomposes the cost rather than paying full-book input on every cache miss. |
| Defer entirely (do nothing) | Rejected | Bridge fix (#3430) bounds the trust-breach to a refusal but does not deliver the founder's expectation of summarization on books. Without a durable path, the bridge becomes the permanent answer and the "Concierge can read my KB" promise stays partly unfulfilled. |

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Provider | Anthropic-only | Stack alignment; no second-vendor DPA; cache_control gives multi-turn cost relief |
| Mechanism | In-process pdfjs extraction + outline-based chunking | Reuses hardened code path; no third-party file storage |
| Model routing | Sonnet 4.6 / 200K per chapter; escalate to Opus 4.7-1M only if a single chapter exceeds 200K | Cost-first; full-book Opus rare |
| Overflow when no outline | Fall through to #3430 bridge `too_many_pages` directive | Single source of truth for "this PDF is too large" UX |
| Cost UX | Silent caps via existing `cc-cost-caps.ts` + post-hoc indicator | Per CPO + CFO: lowest friction that preserves brand-survival floor; no new infra |
| Mode availability | Both BYOK + Soleur-key | Existing caps already protect Soleur margin ($0.50/conv ≈ 10 chapter turns); no new legal scope since no Files API |
| Code-path scope | Use shared `resolvePdfArtifactContext` introduced by #3437 | Avoid divergence (per learning `2026-05-05-image-placeholder-leak-and-cc-attachment-drop`) |
| Sequencing | Block implementation on #3430 + #3437 merging | Build on stable rails; spec captured now |
| Chapter routing v1 | Cheap Sonnet-200K turn over TOC titles → pick relevant chapter; ambiguous → ask user | LLM-routed has ~$0.001/turn cost + <1s latency; embedding-based retrieval deferred |
| Chapter scope of answer | Surface loaded chapter in response ("Answering from chapter X") | Fabrication mitigation; no extra infra |
| `cache_control` on chapter | `{ type: "ephemeral" }` on document content block | 5-min TTL; first turn pays full input, subsequent ~0.1× |

## Open Questions

1. **Agent SDK 0.2.85 + cache_control:** the codebase has zero `cache_control` usage today. Plan-time spike must verify whether `claude-agent-sdk@0.2.85` exposes per-content-block cache annotation, or whether this requires a side path that calls `messages.create` directly. CTO flagged.
2. **pdfjs outline coverage on real founder PDFs:** assumption is "Manning/O'Reilly/published books reliably have outlines." Plan-time empirical check against ≥5 fixture PDFs (1 published book, 1 academic paper, 1 scanned book, 1 self-published, 1 manual) before committing to chapter-chunking as the main path.
3. **TOC routing latency:** budgeting one extra Sonnet-200K turn per question (~$0.001, <1s). If chat UX feels sluggish, alternative is keyword-match against chapter titles (free, but worse on synonyms). Decide post-prototype.
4. **Multi-chapter questions ("compare chapter 3 and chapter 7"):** v1 explicitly does NOT handle these; bridge refusal copy or "ask about one chapter at a time." Tracked as separate issue.
5. **Cache TTL surprise:** ephemeral cache is 5 minutes. A founder who pauses for >5 min between turns re-pays full chapter input. Acceptable for v1; document in user-facing copy.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Originally recommended parking the Files API approach because the bridge fix was assumed live (it isn't — PR #3430 is WIP). With chapter-chunking instead, the cost / legal scope drops materially, but the sequencing call still holds: gate implementation on bridge + leader-symmetry merging so we build on stable rails. Update #3436 acceptance to reflect the chapter-chunking pivot.

### Legal (CLO)

**Summary:** Files API path required 3 legal-doc updates + Anthropic DPA verification because Files API uploads make Anthropic our sub-processor (we are processor of record for Soleur-key uploads). **Chapter-chunking eliminates this entire surface** — no third-party file storage, no retained-until-deleted artifact, no ZDR concern. Anthropic remains a data processor under existing DPA terms (already covered for `messages.create` flows). No new legal-doc updates required for this work.

### Engineering (CTO)

**Summary:** Files API would have required adding `@anthropic-ai/sdk` direct dep, bypassing the agent SDK for first-turn PDF context, and a 100-page cap on 200K-context models. Chapter-chunking reuses the hardened pdfjs extraction path, the shared resolver from #3437, and existing `messages.create` flow. Main risk: `cache_control` is zero-use in the codebase — plan-time spike must verify agent SDK 0.2.85 supports per-block cache annotation. ADR worth recording at plan time (CTO-track decision: cache annotation strategy + chapter-routing).

### Finance (CFO)

**Summary:** Files API worst case was $6.75 / 5-turn convo on Opus uncached, $500/mo single Soleur-key power user. Chapter-chunking shifts the typical case to Sonnet-200K per chapter (~$0.15-$0.20/turn first hit, ~$0.05 cached) and only escalates to Opus when a single chapter exceeds 200K tokens (rare). Existing `cc-cost-caps.ts` ($2 BYOK / $0.50 Soleur per-conv, $25 / $1 daily) is sufficient — no new `usage_ledger` table required. CFO no longer recommends BYOK-only-from-day-1; both modes are economically viable under existing caps.

## Capability Gaps

None blocking this scope. CTO-flagged spike (agent SDK + `cache_control` interaction) is in-scope for plan time, not a missing capability.

Evidence for "no shared PDF resolver today":
- `git grep -n "resolveConciergeDocumentContext\|buildPdfGatedDirective" -- apps/web-platform/server/` returns the function in `kb-document-resolver.ts:74` and the factory in `soleur-go-runner.ts:117` imported by `agent-runner.ts:48-49` — but the leader path (`agent-runner.ts:842-878`) calls `buildPdfGatedDirective` directly without going through `resolveConciergeDocumentContext`. The resolver is Concierge-only today; #3437 introduces the seam.

Evidence for "no `cache_control` usage today":
- `git grep -n "cache_control\|cacheControl" -- apps/web-platform/` returns zero hits in `server/` and `lib/`. Currently the agent SDK manages caching internally with no explicit annotation from the Soleur layer.

## Scope-Out (Filed as Separate Issues)

| Item | Why deferred | Re-evaluation criterion |
|---|---|---|
| Anthropic Files API integration | This brainstorm rejected the path on cost/legal grounds | Revisit only if (a) ZDR-eligible Files API ships, (b) Anthropic DPA terms shift, **or** (c) chapter-chunking proves insufficient for ≥3 founder use cases |
| Gemini multi-vendor | Architectural cost exceeds unit-cost savings at current scale | Revisit if monthly Anthropic spend exceeds $X (TBD by CFO) **or** if a feature genuinely requires Gemini-only capability |
| Pre-turn cost confirmation modal | Silent caps + indicator chosen for v1 | Revisit if BYOK billing complaints surface in support |
| Cross-chapter / multi-PDF Q&A | Out of scope for v1 chapter-chunking | After v1 ships and usage data shows ≥3 founders attempting cross-chapter queries |
| Pre-flight `count_tokens` API | Existing post-hoc tracking + `cc-cost-caps.ts` enforce hard stop | Revisit if cap-hit-after-the-fact UX produces complaints |
| New `usage_ledger` table | `api-usage.ts` already tracks per-conv tokens/cost | Revisit if BYOK admin dashboard or top-N spender view becomes a requirement |
| Anthropic DPA verification + privacy policy / GDPR / DPD updates | Not required for chapter-chunking (no sub-processor change). Originally scoped for Files API; preserved as separate audit issue regardless | Independent of this work |
