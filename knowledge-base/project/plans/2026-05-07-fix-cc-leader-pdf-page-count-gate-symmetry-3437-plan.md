---
title: cc-leader Path PDF Page-Count Gate Symmetry (follows #3429)
issue: "#3437"
related_issues: ["#3429", "#3405", "#3430"]
branch: feat-one-shot-3437-cc-leader-pdf-page-gate
date: 2026-05-07
type: bug-fix
classification: leader-path-symmetry
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
depends_on_pr: "#3430 (page-count gate factory + LARGE_PDF_PAGE_THRESHOLD + extractPdfMetadata must land first)"
---

# Plan: cc-leader Path PDF Page-Count Gate Symmetry (#3437)

## Enhancement Summary

**Deepened on:** 2026-05-07
**Sections enhanced:** 6 (Overview, Research Reconciliation, Acceptance Criteria, Files to Edit, Implementation Phases §3, Sharp Edges)
**Research surfaces consulted:** SDK type-defs (verbatim), repo grep on existing partition rails, Sentry tagging precedent, line-range verification, label-inventory, existing agent-runner test inventory, learnings library (4 files cross-referenced).

### Key Improvements

1. **SDK-pin verification.** `@anthropic-ai/claude-agent-sdk@0.2.85`'s `FileReadInput.pages` docstring confirmed verbatim from `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk-tools.d.ts:381-383` — "Maximum 20 pages per request" is the load-bearing constraint. The 150-page threshold reuse is consistent with this cap (~8 fanout calls for a 150-page PDF; ~21 for a 400-page book).
2. **Line-range correction.** Issue body cited `agent-runner.ts:842-858`. Verified against on-disk source: the artifact-directive block is `agent-runner.ts:822-882` (initial assignment line 822; closes at line 882). The PDF-specific subbranch is line 858 (cited correctly in issue). Plan §Files to Edit updated.
3. **Sentry feature-tag conflict surfaced.** `pdf-text-extract.ts:115` hardcodes `feature: "kb-concierge-context"` on the `lazy_import_failed` mirror. After the leader resolver lands, lazy-import failures from leader sessions will mirror with the wrong feature tag. Resolution prescribed inline (Phase 2.4 below).
4. **Existing leader-test inventory mapped.** 11 existing `agent-runner-*.test.ts` files. The new `agent-runner-pdf-page-gate.test.ts` and `agent-runner-pdf-partition.test.ts` slot into the existing convention without naming collision.
5. **Discriminated-union grep audit pre-cleared.** Repo-wide grep for `_exhaustive: never`, `\.kind === "`, `\?\.kind === "`, `_AssertPartitionTotal` returns 16 hits; none on `PdfExtractErrorClass` consumers outside `soleur-go-runner.ts:236` and the partition rail at line 312-318. After the leader resolver lands, the new consumer is added; the type-level rail catches missing partition entries.
6. **GitHub label sweep — no new labels prescribed.** This plan introduces no `gh issue create --label` AC. Verified `gh label list --limit 200` inventory; no action required.

### New Considerations Discovered

- The leader path has NO idle-reaper today (unlike `soleur-go-runner.ts DEFAULT_WALL_CLOCK_TRIGGER_MS = 90s`). Risk R2 is updated to reflect this — the 150-page threshold's load-bearing constraint shifts from "fits within reaper window" (Concierge) to "fits within model-side prompt-tail re-ingest budget" (leader). The threshold is over-conservative on the leader path, but per-path tuning is deferred to a follow-up issue (filed at /work Phase 6).
- `pdfjs-dist` lazy-import failure (`lazy_import_failed`) is tagged `feature: "kb-concierge-context"` at `pdf-text-extract.ts:115` — a single tag for both paths is wrong post-symmetry; the extractor needs an optional `featureTag` arg, OR the resolver wrappers each catch the import-failure class and re-mirror with the correct tag.
- The brainstorm carry-forward is intact for CPO + CTO; no new domain assessments needed.

## Overview

Bring `apps/web-platform/server/agent-runner.ts` (the **leader path**) under the same PDF partition + page-count gate as the cc-concierge path landed in PR #3430.

Today, the leader's `startAgentSession` opens a 400+ page PDF the same way Concierge did pre-#3429: it goes straight to `buildPdfGatedDirective` (the SDK Read fanout path), which fanout-bombs the SDK Read tool's 20-page-per-request cap. The leader has no idle-reaper today because it's not on the cc-soleur-go runner — but it still hits the same model-side scaling wall: ~21 sequential `Read({pages})` turns, each prompt-tail re-ingest, each large-PDF chunk decode. The user-visible failure mode is "leader appears to hang for 5+ minutes on a Manning-scale book before producing a partial summary or refusing."

The fix: extract the shared resolver pattern out of `kb-document-resolver.ts` so both Concierge AND leader resolve PDFs through the SAME partition + page-count gate, then reuse PR #3430's `buildPdfTooLongDirective` factory.

This is the **symmetry follow-up** filed by #3429 / spec NG2. The Anthropic Files API (Option B) is the durable destination for both paths and remains a separate architecture-track issue (`feat-large-pdf-files-api` branch).

### Research Insights — Overview

**SDK constraint (verbatim, pinned):**

```ts
// apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk-tools.d.ts:378-383
// (SDK pin: "@anthropic-ai/claude-agent-sdk": "0.2.85" — apps/web-platform/package.json)
export interface FileReadInput {
  /** The absolute path to the file to read */
  file_path: string;
  // ...
  /** Page range for PDF files (e.g., "1-5", "3", "10-20"). Only applicable to PDF files. Maximum 20 pages per request. */
  pages?: string;
}
```

This is the load-bearing constraint that motivates the page-count gate on BOTH paths. A 400-page PDF requires ~21 sequential `Read({pages: "1-20"})` calls × per-call wall-clock cost (base64 chunk + model ingestion). The Concierge path's 90s idle-reaper trips before completion (#3429); the leader path's lack of an idle-reaper means the user just sees a several-minute hang before either a partial summary or a refusal.

**Architectural pattern reuse:**

The Concierge resolver (`apps/web-platform/server/kb-document-resolver.ts:67-329`) is the established pattern. Its load-bearing components — `fetchUserWorkspacePath` (with per-process workspace-path memo at lines 39-58), `extractPdfText` integration (lines 152-230), `read_failed` ENOENT carve-out (lines 269-280), Sentry breadcrumb category `cc-pdf-extractor` — all transfer to the leader path AS-IS. The only thing the leader resolver MUST drop is the `knowledge-base/` prefix gate at line 99 (because leaders read across the whole workspace).

## Research Reconciliation — Spec vs. Codebase

| Issue body claim | Reality on disk (verified 2026-05-07) | Plan response |
|---|---|---|
| "leader uses `buildPdfGatedDirective` unconditionally" | True — `agent-runner.ts:858` calls `buildPdfGatedDirective(safeContextPath, safeFullPath, CONTEXT_NO_ASK)` with no `documentExtractError` plumbing. | Replace inline branch with shared resolver + partition. |
| "leader does NOT go through `kb-document-resolver.ts`" | True — `grep "resolveConciergeDocumentContext\|kb-document-resolver" apps/web-platform/server/agent-runner.ts` returns zero. Only `ws-handler.ts` (the cc-soleur-go path) calls the resolver. | Extract a workspace-scoped resolver sibling, OR widen `resolveConciergeDocumentContext` to accept a "no-kb-prefix-gate" mode. (See Decision §1.) |
| "Use the shared `buildPdfTooLongDirective` factory introduced by PR #3430" | PR #3430's branch (`feat-large-pdf-soft-route-timeout`) currently contains spec + brainstorm + RED test commit `ef6bc3c0` only. Implementation NOT yet merged. The factory `buildPdfTooLongDirective`, `PDF_TOO_LONG_DIRECTIVE_LEAD`, `extractPdfMetadata`, `LARGE_PDF_PAGE_THRESHOLD = 150` are referenced in the RED tests but not yet defined. | This plan SEQUENCES AFTER #3430. Plan Phase 0 verifies #3430 merged. If #3430 stalls, this plan is rebased on top of `feat-large-pdf-soft-route-timeout` instead of `main`. |
| "Leader path uses `documentExtractError` plumbing" | False — leader uses `context: ConversationContext { path, type, content? }` from `lib/types.ts:179`. No typed extractor failure surface today. | Add `documentExtractError` + optional `documentExtractMeta { numPages }` plumbing to `startAgentSession`'s context handling (or to the new leader-resolver helper output). |
| `READ_TOOL_PDF_CAPABILITY_DIRECTIVE` already shared between leader + Concierge | True — both `agent-runner.ts:710` (in `leaderBaselineRest`) and `soleur-go-runner.ts:801` reference the shared `READ_TOOL_PDF_CAPABILITY_DIRECTIVE` constant. | No baseline-prompt changes needed; only the artifact-frame branch needs partition awareness. |

## User-Brand Impact

**If this lands broken, the user experiences:** A leader (CPO/CTO/etc.) opens silently for 90s+ on a 400-page Manning book PDF before either producing a hallucinated summary, paraphrasing a sandbox-deny, or surfacing "Agent stopped responding." Trust in domain-leader output collapses on first encounter.

**If this leaks, the user's [data / workflow / money] is exposed via:** Silent BYOK / Anthropic credit burn on ~21 doomed `Read({pages})` calls per leader turn × N retries. A founder running CPO + CTO simultaneously on a long PDF could burn 40+ Read calls before the runner gives up.

**Brand-survival threshold:** `single-user incident` — one founder asking the CPO to "summarize this Manning book" and watching it hang is the brand-breaking moment. Same threshold + treatment as #3429 per `hr-weigh-every-decision-against-target-user-impact`.

**Carve-outs disclosed at review time (PR #3442):**

- **>60MB byte-ceiling case:** the page-count gate is bounded by `METADATA_READ_BYTE_CEILING_BYTES = 40 MiB` (post perf-oracle review of #3430). PDFs exceeding that ceiling fail-close to existing `oversized_buffer` soft-route routing — i.e. the legacy `buildPdfGatedDirective` Read fanout. A 80MB image-heavy book still hangs the leader. The fix is page-count-bounded, NOT byte-bounded. Per-path tuning of the metadata ceiling deferred to a follow-up tracking issue per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`.
- **Leader text-fallback divergence from Concierge:** when a non-PDF text file fails to read (ENOENT after rename, EACCES, EISDIR), the leader resolver returns `{ kind: "text" }` (no content) and the runner emits a Read directive against the absolute path. Concierge's #3353 fix returns `{}` (silent-drop) on the same shape. This is the legacy leader behavior preserved per AC8; the resulting Read directive may surface a stale/permission-denied path in the model's context. Risk is lower than the original #3376 sandbox-deny-cascade (the leader has no router-prompt fallback to mis-paraphrase) but the divergence is real and named here so a future symmetry pass has a documented anchor.

CPO sign-off required at plan time before `/work` begins (per `requires_cpo_signoff: true` carry-forward from #3429 brainstorm). `user-impact-reviewer` will be invoked at review-time.

## Hypotheses

Not applicable — this is a structural symmetry fix, not an outage diagnosis. The root cause was already established in #3429 (Read-tool 20-page-per-request cap × ~21 sequential turns × per-turn prompt-tail re-ingest). This plan's only open hypothesis is the architectural choice (R1 vs R2 vs R3 vs R4 in §Decision Notes).

## Acceptance Criteria

### Pre-merge (PR)

- **AC1.** A 403-page PDF (>24MB, hits `oversized_buffer`) opened on a leader (CPO is canonical test) produces `buildPdfTooLongDirective` output with the page count named, NOT a Read fanout. Manual repro on Manning Book reaches a refusal-with-next-step in <5s of metadata-read latency.
- **AC2.** A 57-page PDF (<24MB) opened on a leader continues to produce the inline-content success path (no directive, body inlined via `<document>` wrapper). Manual repro on Au Chat Pôtan succeeds.
- **AC3.** A synthesized 60-page image-heavy PDF (>24MB, hits `oversized_buffer`, but page count below the 150-page threshold) continues to route to `buildPdfGatedDirective` with the existing copy on the leader path.
- **AC4.** A 200-page PDF whose `extractPdfText` returns `{ error: "encrypted" }` routes to `buildPdfUnreadableDirective` (HARD class — encryption prevents Read recovery), NOT to `buildPdfTooLongDirective` (the page-count gate must NOT override hard-failure routing).
- **AC5.** A synthesized 80MB PDF (exceeds the 60MB metadata ceiling) falls through to existing soft-failure routing (`buildPdfGatedDirective`) on the leader path — fail-closed.
- **AC6.** A synthesized PDF whose metadata-read times out (mocked) falls through to existing soft-failure routing on the leader path — fail-closed.
- **AC7.** Sentry shows `cc-pdf-extractor` breadcrumbs from leader sessions with `op: "metadataRead"`, `data: { class: "too_many_pages" }` when the gate fires on the leader path. Tag the breadcrumb with `feature: "leader-context"` (NOT `kb-concierge-context`) so operators can filter leader-path fires from Concierge fires.
- **AC8.** Existing leader PDF success paths (small PDFs, KB-resident PDFs, client-provided `context.content`) unchanged — no regression on the inline-content branch or the in-workspace text branch.
- **AC9.** Multi-agent review parity with the cc-path PR per `rf-review-finding-default-fix-inline`: `architecture-strategist`, `agent-native-reviewer`, `user-impact-reviewer`, `code-simplicity-reviewer`. PR-time `user-impact-reviewer` enumerates failure modes against the diff per `hr-weigh-every-decision-against-target-user-impact`.
- **AC10.** `bun run typecheck` passes with zero new errors. The compile-time `_AssertPartitionTotal` rail in `soleur-go-runner.ts` continues to assert `SOFT ∪ HARD = PdfExtractErrorClass` (no new union member added by this PR; `too_many_pages` was added by #3430).
- **AC11.** RED-first per `cq-write-failing-tests-before`: failing tests committed before implementation. Test scaffolding mirrors `kb-document-resolver-pdf-page-gate.test.ts` (added in commit `ef6bc3c0`) for the leader path.
- **AC12.** `## Open Code-Review Overlap` audit (Phase 1.7.5): documented in plan body §"Open Code-Review Overlap" below. Disposition for each match recorded.
- **AC13.** PR body uses `Closes #3437` on its own body line. The fix lands at merge time (no post-merge operator action), so `Closes` (not `Ref`) is correct per `wg-use-closes-n-in-pr-body-not-title-to`.
- **AC14.** Leader path's `buildPdfTooLongDirective` text MUST NOT name `pdftotext`/`pdfplumber`/`pdf-parse`/`PyPDF2`/`PyMuPDF`/`fitz`/`apt-get`/`pip3 install` (apt-get cascade defense). Mirrors the Concierge AC the cascade learning enshrined.
- **AC15.** Pino `logger.error/warn` mirrored to Sentry per `cq-silent-fallback-must-mirror-to-sentry` for every degraded leader-path PDF condition (metadata-read failure, oversized-buffer fail-through, page-gate fire). The breadcrumb category `cc-pdf-extractor` is reused; add `feature: "leader-context"` to disambiguate from Concierge fires.

### Post-merge (operator)

- **PM1.** Sentry filter `feature: leader-context AND op: metadataRead` produces zero events in the 24h window after deploy unless a real long-PDF leader session occurred (verifies the breadcrumb plumbing).
- **PM2.** Manual smoke: open Manning Book on CPO leader; verify the new directive renders, the page count appears, and no `Read` calls are issued. Capture screenshot + Sentry event link in the PR comment thread.

## Files to Edit

- `apps/web-platform/server/agent-runner.ts` — replace the inline three-tier file injection at **lines 822-882** (the artifact-directive block; verified on disk 2026-05-07, NOT 842-858 as the issue body cites — the issue cites only the PDF-specific subbranch at line 858) with a call to the shared resolver helper. Thread `documentExtractError` + `documentExtractMeta` through the artifact-directive branch and apply the partition (soft → gated, hard-encrypted → unreadable, hard-too-many-pages → too-long).
- `apps/web-platform/server/pdf-text-extract.ts` — change the hardcoded `feature: "kb-concierge-context"` tag at line 115 (`lazy_import_failed` mirror) to accept a `featureTag?: string` arg on `extractPdfText` (default `"kb-concierge-context"` for backward-compat). The leader resolver passes `"leader-context"`. Also applies to a similar tag in `pdf-text-extract.ts` if `extractPdfMetadata` (added by #3430) hardcodes the same. Verified at deepen-time: `grep -n "kb-concierge-context" apps/web-platform/server/pdf-text-extract.ts` returns one hit (line 115). After #3430 lands and adds `extractPdfMetadata`, re-grep — if a second hardcoded tag appears, surface it via the same `featureTag` arg.
- `apps/web-platform/server/kb-document-resolver.ts` — promote `resolveConciergeDocumentContext` into a shared function OR add a sibling `resolveLeaderDocumentContext` that takes a `prefixGate?: string` arg (default `"knowledge-base/"` for Concierge parity, `null` for leader's broader workspace scope). All other plumbing (extractPdfText + extractPdfMetadata + Sentry breadcrumb + workspace-path memo + the `read_failed` ENOENT carve-out) is reused. See Decision §1 for choice between approaches.
- `apps/web-platform/server/soleur-go-runner.ts` — no functional change. The artifact-directive branch already partitions via `isPdfSoftFailure(safeErrorClass)` and routes `too_many_pages` to `buildPdfTooLongDirective` (per #3430). The leader's new resolver call surfaces the same shape; the helper that builds the PDF directive moves to a shared location (see §Files to Create).
- `apps/web-platform/lib/types.ts` — extend `ConversationContext` interface (lines 179-183) to optionally carry the resolved-document fields (`documentKind`, `documentExtractError`, `documentExtractMeta`). OR keep `ConversationContext` as the wire-input shape and surface the resolved shape only inside `agent-runner.ts`'s closure. Decision §3.
- `apps/web-platform/server/ws-handler.ts` — IF the leader-path WS entrypoint at line 1415 (`startAgentSession(userId, session.conversationId, pendingLeader, undefined, undefined, pendingContext)`) is changed to pre-resolve the document via `resolveLeaderDocumentContext`, this file is touched. ELSE the resolver call lives inside `agent-runner.ts`. Decision §2.
- `apps/web-platform/test/agent-runner-pdf-page-gate.test.ts` — NEW test (RED-first), mirrors `kb-document-resolver-pdf-page-gate.test.ts` (committed as part of `ef6bc3c0`) but covers the leader path's `startAgentSession` artifact-injection branch.
- `apps/web-platform/test/agent-runner-pdf-partition.test.ts` — NEW test, asserts the leader-path system prompt for each of the seven `PdfExtractErrorClass` members routes to the correct directive (gated for soft, unreadable for `encrypted`/`empty_text`, too-long for `too_many_pages`).
- `knowledge-base/project/learnings/2026-05-07-cc-leader-pdf-page-gate-symmetry.md` — NEW learning file, post-merge. Captures the architectural choice (which approach R1/R2/R3/R4 was chosen and why) + the deferral structure to Files API (Option B).
- `knowledge-base/project/specs/feat-one-shot-3437-cc-leader-pdf-page-gate/spec.md` — NEW; derived from this plan during /work.
- `knowledge-base/project/specs/feat-one-shot-3437-cc-leader-pdf-page-gate/tasks.md` — NEW; derived from this plan during /work.

## Files to Create

- `apps/web-platform/server/leader-document-resolver.ts` (chosen if Decision §1 → R4) — workspace-scoped sibling to `resolveConciergeDocumentContext`. Reads files server-side, calls `extractPdfText` then `extractPdfMetadata` for the page-count gate, surfaces `{ artifactPath, documentKind, documentContent?, documentExtractError?, documentExtractMeta? }`. NO `knowledge-base/` prefix gate. Reuses `fetchUserWorkspacePath` from `kb-document-resolver.ts` (single workspace-path cache).

(If Decision §1 → R3 — widen the existing resolver — this file is NOT created and the new function lives in `kb-document-resolver.ts` instead.)

## Decision Notes (Open Questions for Deepen-Plan)

These are the four architectural choices that need to be resolved during /soleur:deepen-plan with input from `architecture-strategist`. Default selections are noted; a reviewer may overturn.

### Decision §1 — Where does the page-count gate live for the leader?

| Approach | Description | Pro | Con | Default? |
|---|---|---|---|---|
| **R1** | Refactor: extract leader's inline three-tier injection AND Concierge's resolver into a single shared function | One source of truth | Larger blast radius; touches Concierge in same PR | No |
| **R2** | Inline the partition + gate in `agent-runner.ts:822-882` | Minimal blast radius | Drift risk; duplicates partition logic | No |
| **R3** | Widen `resolveConciergeDocumentContext` with `prefixGate?: string \| null` arg | Single resolver, single workspace-path cache | Function name is misleading once it serves leader too; rename across consumers | Maybe |
| **R4** | New `resolveLeaderDocumentContext` in new `server/leader-document-resolver.ts`, sharing `fetchUserWorkspacePath`, `extractPdfText`, `extractPdfMetadata` from existing modules | Clean boundary; future Files API integration lands in two parallel resolvers OR one further refactor | Two resolvers; potential drift surface | **Yes** |

**Default: R4.** Rationale: Concierge resolver enforces `knowledge-base/` prefix as a security guard for the cc-soleur-go path (defense-in-depth on top of `validateConversationContext`). The leader is a different trust boundary — leaders read across the whole workspace. Conflating the two paths into one resolver couples two unrelated invariants. R4 keeps the partition/gate/extractor implementation shared at the helper level (`extractPdfText`, `extractPdfMetadata`, `fetchUserWorkspacePath`) without conflating the resolvers' security contracts.

**Architecture-strategist gate (deepen-plan Phase 4.6):** If R4 is contested, the alternative chosen MUST be named in the plan body at deepen-plan time — do NOT defer this to /work pivots. (Per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`-class learning extension to architecture choices.)

### Decision §2 — Where does the resolver call site live (ws-handler vs agent-runner)?

- **Option A:** Pre-resolve in `ws-handler.ts` line 1415 (parallel to how cc-soleur-go pre-resolves at line ~891). Pass the resolved bundle into `startAgentSession`. Pro: All file I/O done before the BYOK lease scope. Con: changes the leader-path call signature.
- **Option B:** Resolve inside `agent-runner.ts startAgentSession` itself, replacing the existing inline file-read block. Pro: minimal call-signature changes. Con: I/O now happens inside the BYOK lease — already true today (`readFile(fullPath, "utf-8")` at line ~870); no regression.

**Default: Option B.** Rationale: minimizes signature churn; the existing code already does I/O inside `startAgentSession`. The shared resolver call replaces the inline file-read; same observability surface.

### Decision §3 — Wire shape: extend `ConversationContext` or surface internally?

- **Option A:** Extend `ConversationContext` (in `lib/types.ts`) with optional resolved fields. Pro: single shape across wire + agent-runner. Con: client-shaped type now carries server-resolved fields it never sets.
- **Option B:** Keep `ConversationContext` as the WS wire input. Surface a NEW internal shape `ResolvedLeaderDocumentContext` that `agent-runner.ts` builds from the resolver output. Pro: clean wire/server separation. Con: two shapes to keep aligned.

**Default: Option B.** Rationale: `ConversationContext` is the WS-protocol type; server-resolved fields don't belong there. Mirrors the cc-soleur-go pattern (`DispatchSoleurGoArgs` in `cc-dispatcher.ts:733-755` is the server-resolved bundle, distinct from the WS `ConversationContext`).

### Decision §4 — Should the leader's `buildPdfTooLongDirective` copy include leader identity ("As your CPO, I see…")?

- **Option A:** Reuse `buildPdfTooLongDirective` verbatim (no leader identity injection in the directive). Identity already established by `leaderIdentityOpener`.
- **Option B:** Pass leader title/name into the factory so the refusal copy says "As your CPO, I see 250 pages…".

**Default: Option A.** Rationale: copy parity with Concierge; minimizes per-leader surface area; identity-already-established. Reviewer may flip if CPO domain-leader assessment indicates the leader-voice variant is brand-load-bearing.

## Implementation Phases

### Phase 0 — Sequencing Gate (BLOCKING)

PR #3430 MUST land first. This PR's surface-area depends on `buildPdfTooLongDirective`, `PDF_TOO_LONG_DIRECTIVE_LEAD`, `extractPdfMetadata`, `LARGE_PDF_PAGE_THRESHOLD`, and the `too_many_pages` partition member. These are referenced in the RED tests committed at `ef6bc3c0` but the GREEN implementation is not yet on main (verified 2026-05-07 via `grep buildPdfTooLongDirective apps/web-platform/server/`).

**Gate:** Before `/work` begins, verify `git log main --oneline -- apps/web-platform/server/soleur-go-runner.ts | head -5` shows a commit that adds `buildPdfTooLongDirective`. If absent, EITHER:

- (a) wait for #3430 to merge and rebase this branch on main, OR
- (b) rebase this branch on top of `feat-large-pdf-soft-route-timeout` and stack the PRs.

Default: (a) — sequential is simpler. (b) is acceptable if #3429 is delayed beyond 24h after this plan's PR is opened.

### Phase 1 — RED tests (mirrors `cq-write-failing-tests-before`)

1. Create `apps/web-platform/test/agent-runner-pdf-page-gate.test.ts`. Mirror the structure of `kb-document-resolver-pdf-page-gate.test.ts` (committed at `ef6bc3c0`) but invoke the leader-path entry point. Mock the new resolver helper (or `extractPdfText` + `extractPdfMetadata` directly). Cover:
   - oversized_buffer + numPages > 150 → `documentExtractError: "too_many_pages"` + `documentExtractMeta: { numPages }`.
   - oversized_buffer + numPages ≤ 150 → `documentExtractError: "oversized_buffer"` (soft, falls through).
   - oversized_buffer + metadata oversized → soft fall-through.
   - oversized_buffer + metadata timeout → soft fall-through.
   - encrypted (HARD, not page-gate eligible) → `documentExtractError: "encrypted"` (page-gate does NOT override hard).
2. Create `apps/web-platform/test/agent-runner-pdf-partition.test.ts`. Mirror `read-tool-pdf-capability.test.ts` partition walk but build the LEADER system prompt (extract or import the leader's prompt-builder once it's helper-extracted in Phase 3). Each `PdfExtractErrorClass` member routes to its expected directive lead.
3. Run `bun test apps/web-platform/test/agent-runner-pdf-*` — all new cases RED.

### Phase 2 — Resolver-Helper Extraction (per Decision §1 default R4)

1. Create `apps/web-platform/server/leader-document-resolver.ts`:
   - `export async function resolveLeaderDocumentContext(args: { userId: string; contextPath: string | null | undefined; providedContent?: string | null; }): Promise<ResolvedLeaderDocumentContext>`.
   - NO `knowledge-base/` prefix gate (leader-scope is the whole workspace).
   - Reuse `fetchUserWorkspacePath` (re-exported from `kb-document-resolver.ts`).
   - Reuse `extractPdfText` + `extractPdfMetadata` from `pdf-text-extract.ts`.
   - Mirror the partition + gate flow from `kb-document-resolver.ts` PDF branch.
   - Sentry breadcrumb category `cc-pdf-extractor`, `feature: "leader-context"` to disambiguate from Concierge.
   - Unit-test stubs (mock-driven), shape-parity with Concierge resolver tests.
2. Define `ResolvedLeaderDocumentContext` type (per Decision §3 Option B):
   - `{ artifactPath?: string; documentKind?: "pdf" | "text"; documentContent?: string; documentExtractError?: PdfExtractErrorClass; documentExtractMeta?: { numPages?: number } }`.
   - Lives in `leader-document-resolver.ts` (NOT exported to wire).

### Phase 2.4 — Sentry Feature-Tag Disambiguation (NEW from deepen-pass)

`apps/web-platform/server/pdf-text-extract.ts:115` hardcodes `feature: "kb-concierge-context"` on the `lazy_import_failed` Sentry mirror. Once the leader path calls the same extractor, lazy-import failures from leader sessions will mirror with the wrong feature tag — operators filtering by `feature: leader-context` will see zero events even when the leader is failing.

1. Extend `extractPdfText` (and `extractPdfMetadata` once #3430 lands it) with an optional `featureTag?: string` arg, default `"kb-concierge-context"` for backward-compat.
2. Concierge resolver passes `featureTag: "kb-concierge-context"` (existing behavior, explicit). Leader resolver passes `featureTag: "leader-context"`.
3. Verify post-#3430 rebase: `grep -n "kb-concierge-context\|leader-context" apps/web-platform/server/pdf-text-extract.ts apps/web-platform/server/kb-document-resolver.ts apps/web-platform/server/leader-document-resolver.ts` shows tag-symmetric usage.
4. Test: extend `apps/web-platform/test/pdf-text-extract.test.ts` with a "lazy-import failure mirrors with caller-provided feature tag" assertion (mock the dynamic import to throw; assert `reportSilentFallback` was called with the expected `feature` value).

### Phase 3 — Leader Prompt-Builder Extraction (preparatory refactor)

The leader's three-tier injection block (`agent-runner.ts:822-882`) is currently inline inside `startAgentSession`. To enable partition-aware testing per Phase 1.2, extract it into a pure helper:

1. Create `buildLeaderArtifactDirective(args: { resolved: ResolvedLeaderDocumentContext; workspacePath: string }): string` — pure function, mirrors `buildSoleurGoSystemPrompt`'s artifact-directive sub-block. Lives in `agent-runner.ts` (or a new `agent-runner-prompt.ts` if `agent-runner.ts` exceeds size budget).
2. Replace the inline block with a single call. Verify byte-identical output for all current branches (client-provided content, server-read text, PDF-via-`buildPdfGatedDirective`).
3. The helper now accepts `documentExtractError` + `documentExtractMeta` and dispatches:
   - `documentExtractError === "too_many_pages"` → `buildPdfTooLongDirective(safeContextPath, safeNumPages, CONTEXT_NO_ASK)` (factory from #3430).
   - `documentExtractError` ∈ `PDF_SOFT_FAILURE_CLASSES` (excluding `too_many_pages`) → `buildPdfGatedDirective(...)`.
   - `documentExtractError` ∈ `PDF_HARD_FAILURE_CLASSES` (`encrypted`, `empty_text`, ...) → `buildPdfUnreadableDirective(...)`.
   - No `documentExtractError`, has `documentContent` ≤ 50KB → inline body via `<document>` wrapper (existing path).
   - No `documentExtractError`, has `documentContent` > 50KB → fall-through to `buildPdfGatedDirective` (existing path).
   - No `documentExtractError`, no `documentContent`, PDF kind → fall-through to `buildPdfGatedDirective` (existing path).

### Phase 4 — Wire the Resolver into `startAgentSession`

1. Replace the inline `if (context?.content) { ... } else if (context?.path && safeContextPath.length > 0) { ... }` block (lines ~822-882) with:
   - Call `resolveLeaderDocumentContext({ userId, contextPath: context?.path, providedContent: context?.content })`.
   - Pass the result into `buildLeaderArtifactDirective`.
   - Append the directive to `systemPrompt` per existing assembly.
2. Preserve all existing observability + sanitization (control-char strip + U+2028/U+2029 strip + `</document>` escape + 256-cap on path display).
3. `bun test apps/web-platform/test/agent-runner-pdf-*` — turn GREEN.

### Phase 5 — Smoke + E2E

1. Existing leader-path tests must continue passing (`bun test apps/web-platform/test/agent-runner-*`).
2. Manually reproduce on Manning Book + Au Chat Pôtan — paste Sentry event links in PR thread.
3. Run multi-agent review per AC9.

### Phase 6 — Compound + Ship

1. Compound capture: write `2026-05-07-cc-leader-pdf-page-gate-symmetry.md` learning. Capture which Decision §1 approach (R1/R2/R3/R4) was chosen + why; the deferral relationship to Files API.
2. Per `wg-when-fixing-a-workflow-gates-detection`: this PR closes the symmetry gap that #3429's brainstorm explicitly deferred. No retroactive remediation needed (this IS the retroactive remediation of NG2).
3. Ship via standard pipeline.

## Open Code-Review Overlap

(Per Phase 1.7.5 of `/soleur:plan` skill — verifies open code-review issues touching planned files.)

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
for path in apps/web-platform/server/agent-runner.ts apps/web-platform/server/kb-document-resolver.ts apps/web-platform/server/soleur-go-runner.ts apps/web-platform/lib/types.ts apps/web-platform/server/ws-handler.ts; do
  echo "=== $path ==="
  jq -r --arg path "$path" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

**Result (to be run at /work Phase 0; recorded here as a placeholder for deepen-plan to verify):**

- TBD — verified at deepen-plan Phase 4. Default disposition for any match: **Acknowledge** unless the open issue is in the same partition+gate code area, in which case **Fold in**.

If the audit returns no matches, this section will be updated to `None` and the check noted as run.

## Sharp Edges

1. **Sequence with #3430.** Phase 0 is the load-bearing gate. If a /work agent skips Phase 0 and starts implementing against `main` while #3430 is still WIP, the imports of `buildPdfTooLongDirective` / `extractPdfMetadata` / `LARGE_PDF_PAGE_THRESHOLD` will fail at typecheck. The /work skill's TDD Gate catches this on the RED test file's import block — but only if the agent doesn't auto-comment the imports out.

2. **Discriminated-union exhaustive switch parity** (per `cq-union-widening-grep-three-patterns`). #3430 widens `PdfExtractErrorClass` with `too_many_pages`. Both Concierge (`soleur-go-runner.ts:888`) and the new leader-resolver consumer MUST `grep -n "\.kind === \\\"\|\\?\\.kind === \\\"\|_exhaustive: never"` after the rebase to catch silent-drop sites. The compile-time `_AssertPartitionTotal` rail should fail loudly if the new value isn't in either partition set.

3. **Sentry breadcrumb namespace collision.** Concierge fires `category: "cc-pdf-extractor"` with `feature: "kb-concierge-context"`. The leader path reuses `category: "cc-pdf-extractor"` with `feature: "leader-context"`. Operators relying on category-only filters will see both. AC7 prescribes the `feature` distinguisher; ensure the `extra` field is reliably set on every fire.

4. **Workspace-path memo cross-tenant safety.** `_workspacePathCache` in `kb-document-resolver.ts` is keyed by `userId`. The new leader resolver MUST share that cache (re-use `fetchUserWorkspacePath` directly, not duplicate the logic) so a single per-process memo serves both paths. A second cache would be a tenant-isolation footgun.

5. **R4's tenancy boundary parity.** The Concierge resolver enforces `knowledge-base/` prefix BEFORE `isPathInWorkspace`. The leader resolver drops the prefix gate but MUST keep `isPathInWorkspace`. A path-traversal attempt (`../../../etc/passwd` style) on the leader path is blocked by `isPathInWorkspace` alone — no defense-in-depth from the prefix gate. Per `hr-weigh-every-decision-against-target-user-impact`, ensure `isPathInWorkspace` is exercised by at least one Phase 1 test case (synthetic `..`-traversal context.path → resolver returns `{}`).

6. **Files API supersession.** Per the issue body's "Note": if the Files API integration (separate `feat-large-pdf-files-api` branch / issue) ships first and covers BOTH paths, this issue closes as a duplicate. The plan must include a check at /work Phase 0: `gh issue view <files-api-issue-number> --json state` — if MERGED and covers leader path, abort this work.

7. **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** Already filled — `single-user incident` per #3429 carry-forward.

8. **CLI-form-bug-class verification grep scope.** No CLI invocations are introduced by this plan — the change is internal TS only. AC11 covers RED-test scaffolding; no docs surface gets new CLI tokens.

9. **Sentry feature-tag drift on `lazy_import_failed`** (deepen-pass discovery). `pdf-text-extract.ts:115` is shared by both paths post-symmetry but tags `feature: "kb-concierge-context"` regardless of caller. Phase 2.4 closes this with an optional `featureTag?: string` arg. If a /work agent skips Phase 2.4, the leader resolver will work end-to-end but operators won't be able to filter leader-side lazy-import failures from Concierge ones. Mirror to AC15 verification: `grep -n "feature: \"leader-context\"" apps/web-platform/server/leader-document-resolver.ts apps/web-platform/server/pdf-text-extract.ts` MUST return at least one hit per file post-implementation.

10. **Existing leader-test naming convention** (deepen-pass discovery). 11 existing `agent-runner-*.test.ts` files. The new `agent-runner-pdf-page-gate.test.ts` and `agent-runner-pdf-partition.test.ts` follow the same naming convention — no collision. `agent-runner-system-prompt.test.ts` already exists; verify at /work Phase 1 that it does NOT cover the artifact-directive PDF branch (a quick grep should show it covers the leader baseline + identity opener but NOT the per-context PDF dispatch). If it DOES cover the PDF branch, fold the new partition tests into it instead of creating a new file.

11. **Discriminated-union `_AssertPartitionTotal` rail tautology** (per learning `2026-05-07-type-level-partition-rail-tautology-from-typed-set-infer.md`). The partition rail at `soleur-go-runner.ts:308-318` is driven off literal arrays, NOT off `infer T` from the `Set` — so widening `PdfExtractErrorClass` without adding to one of the literal arrays fails the build. This protects the leader resolver too. No new partition rail needed for the leader; the same one guards both consumers.

## Risks

- **R1.** **Resolver extraction touches a hot path.** `agent-runner.ts startAgentSession` is on every leader turn. A regression in the helper extraction (Phase 3) breaks every leader, not just PDF cases. **Mitigation:** Phase 3 is a pure refactor with byte-identical output assertion as a test gate; the resolver call (Phase 4) lands ONLY after Phase 3 is GREEN.
- **R2.** **Threshold mis-calibration carry-over from #3429.** `LARGE_PDF_PAGE_THRESHOLD = 150` was math-derived from the cc-soleur-go reaper window (90s). The leader path doesn't have an idle reaper today, so the threshold's load-bearing constraint shifts to "model-side prompt-tail re-ingest cost growing nonlinearly with fanout depth." If the leader can actually process a 200-page PDF in 25 turns without the user perceiving a hang, the 150-page threshold is over-conservative on this path. **Mitigation:** Phase 5 manual repro on a synthetic 180-page PDF. If it succeeds gracefully, file a follow-up to per-path tune the threshold; do NOT block this PR on it. Default 150 stays for symmetry with #3430.
- **R3.** **Architecture-choice contention** (Decision §1). If `architecture-strategist` at deepen-plan time recommends R3 (widen the existing resolver) over the default R4 (sibling resolver), the plan needs to be rewritten BEFORE /work starts. The branch name `feat-one-shot-3437-cc-leader-pdf-page-gate` is implementation-agnostic, so no rebase needed.
- **R4.** **Per `cq-when-a-plan-prescribes-extension-of-a-tool-tier-...`-style sibling**: the page-count gate is a defensive rule applied at TWO call sites (Concierge + Leader). If a future call site appears (e.g., a third agent-runner for a new modality), the gate must be applied there too. Mitigation: the resolver-helper extraction in Phase 2 means the gate lives in TWO resolver functions. Acceptable today; if a third resolver materializes, refactor to one shared private helper.
- **R5.** **`ConversationContext` extension drift** (Decision §3 Option A risk). If Decision §3 flips from default Option B to Option A, the wire-shape gains server-resolved fields that clients never set. WS validation in `validateConversationContext` would need an "ignore extra fields" stance — historically a security smell. Default Option B avoids this entirely.
- **R6.** **Sequencing risk.** If #3430 stalls, this PR can't progress to GREEN. Phase 0 makes this explicit. Worst case: this branch sits open for 24-48h waiting for the upstream bridge fix — acceptable given the underlying user impact is the same as #3429 today (silent timeout vs silent timeout).
- **R7.** **Trust-breach if Files API doesn't ship next phase** (carry-forward from #3429 R5). If the Files API durable fix isn't milestoned within the same phase, both paths still have the bridge-fix taste of "I refuse big books." Mitigation: file Files API issue and milestone it before this PR merges. Verify in plan/work.
- **R8.** **Threshold semantic shifts between paths** (deepen-pass refinement of R2). On the Concierge path, `LARGE_PDF_PAGE_THRESHOLD = 150` is bound by the 90s `DEFAULT_WALL_CLOCK_TRIGGER_MS` reaper (per #3429 brainstorm decision #2: `floor(90s / ~10s per Read call) * 20 pages/call - safety margin`). The leader path has NO equivalent reaper, so the 150-page threshold's load-bearing constraint shifts to "model-side prompt-tail re-ingest budget growing nonlinearly with fanout depth." This means the threshold is potentially OVER-conservative on the leader path — a 200-page PDF might process gracefully if the user is patient, where on Concierge it would always trip the reaper. Per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`-style analysis: this plan deliberately does NOT relax the threshold on the leader path; same value, same partition member. A follow-up issue will measure leader-path per-Read wall-clock and decide whether per-path tuning makes sense. Filing the follow-up in /work Phase 6 mirror of #3429 brainstorm Open Question #1.

### Research Insights — Risks

**Defense-relaxation tax (per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`):** The threshold is NOT being relaxed in this PR. Both paths use `LARGE_PDF_PAGE_THRESHOLD = 150` (set by #3430). If a future PR per-path tunes the leader threshold UP, that PR MUST enumerate the threats the 150-cap was bounding on the leader path (model-side fanout cost, BYOK token-burn ceiling, user perception of hang) and name the new ceiling for each. This Risk R8 establishes the baseline so the future PR's defense-relaxation analysis has a documented anchor.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO), Operations (COO via observability surface)

**Brainstorm carry-forward:** Yes. The #3429 brainstorm at `knowledge-base/project/brainstorms/2026-05-07-large-pdf-soft-route-timeout-brainstorm.md` covers Engineering + Product domain assessments. Both apply to this symmetry follow-up:

### Engineering (CTO) — carried forward from #3429 brainstorm

**Status:** reviewed (carry-forward)
**Assessment:** Recommends R4 (sibling resolver) over R3 (widen Concierge resolver). Same critical-path risk bounded by same fail-closed pattern. Capability gaps: none. Files API (Option B) remains the durable destination but warrants its own architecture cycle. Decision §1 default (R4) is consistent with this assessment; deepen-plan's `architecture-strategist` gate is the load-bearing check on the choice.

### Product (CPO) — carried forward from #3429 brainstorm

**Status:** reviewed (carry-forward)
**Assessment:** Same A-as-bridge / B-as-destination framing applies to the leader path. Target user (founder asking CPO/CTO leader to summarize a Manning book) is in exploratory mode; clean refusal is acceptable IF the directive teaches them how to extract value now. Reject auto-summarize-first-N-pages on leader path too (same rationale: useless preface summary reinforces "leader is shallow"). Threshold reuse (150 pages) is acceptable initially per Risk R2; per-path tune later if measurement supports it.

**Sign-off lifecycle:** Per `hr-weigh-every-decision-against-target-user-impact` and the brainstorm's `single-user incident` threshold:
- Brainstorm phase (CPO + CLO + CTO): completed in #3429 brainstorm.
- Plan phase (this gate, CPO sign-off only): required before /work. CPO confirms the leader-path framing is consistent with the Concierge framing and the Decision §1 default (R4) is the right architectural choice.
- Review phase (`user-impact-reviewer`): enumerates failure modes against the diff at PR time.
- Ship phase (preflight Check 6): mechanical gate that section exists + threshold valid.

### Operations (COO) — auto-included

**Status:** reviewed
**Assessment:** Sentry breadcrumb namespace (AC7) keeps Concierge vs leader filterable. Cost surface (AC8: no new metadata-read fires beyond the page-gate trigger; bounded at 60MB/3s per Phase 0 of #3430). No paging or runbook update required — this is a structural fix, not an outage.

### Product/UX Gate

**Tier:** advisory (modifies existing user-facing leader behavior on a bug path; no new UI surface)
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline mode, ADVISORY tier)
**Skipped specialists:** none
**Pencil available:** N/A

**Findings:** No new UI surfaces. Copy from the inherited `buildPdfTooLongDirective` factory is brand-reviewed by #3429 / #3430.

**Brainstorm-recommended specialists:** none beyond what #3429 brainstorm carried.

## References

- Issue #3437 — this issue
- Issue #3429 — bridge fix for cc-concierge (parent)
- PR #3430 — page-count gate factory + `LARGE_PDF_PAGE_THRESHOLD` + `extractPdfMetadata` (dependency)
- PR #3405 — `PdfExtractErrorClass` partition (foundation for both #3429 and this fix)
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-07-large-pdf-soft-route-timeout-brainstorm.md`
- Spec for #3429: `knowledge-base/project/specs/feat-large-pdf-soft-route-timeout/spec.md`
- Learning: `knowledge-base/project/learnings/2026-05-06-cc-concierge-pdf-summary-cascade-structural-fix.md`
- Learning: `knowledge-base/project/learnings/2026-04-18-pdfjs-metadata-on-node-without-canvas.md`
- Learning: `knowledge-base/project/learnings/2026-04-18-discriminated-union-widening-if-ladders-and-config-map-parity.md`
- Learning: `knowledge-base/project/learnings/2026-05-07-type-level-partition-rail-tautology-from-typed-set-infer.md`
- `apps/web-platform/server/agent-runner.ts:822-882` — leader artifact-directive block (the surface to refactor)
- `apps/web-platform/server/kb-document-resolver.ts` — Concierge resolver (the mirror to share with)
- `apps/web-platform/server/soleur-go-runner.ts:840-915` — partition + factory dispatch (already partition-aware post #3430)
- `apps/web-platform/server/pdf-text-extract.ts` — extractor + (post #3430) `extractPdfMetadata`
- Test commit `ef6bc3c0` — RED test scaffolding for #3429; mirror for leader-path Phase 1.

