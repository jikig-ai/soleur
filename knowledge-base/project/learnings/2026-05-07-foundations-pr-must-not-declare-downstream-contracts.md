---
module: System
date: 2026-05-07
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "Foundations PR shipped a system-prompt directive that declared a content-block contract delivered by a downstream PR"
  - "Multi-agent review (architecture-strategist + data-integrity-guardian + user-impact-reviewer) converged on the same P1 BLOCK finding"
  - "Production-reachable interim window where the directive promised behavior the dispatch layer would not deliver"
  - "Brand-survival threshold (single-user incident) crossed: chapter prefix would have laundered fabrication"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: high
tags:
  - feature-splitting
  - foundations-pr
  - directive-without-delivery
  - multi-agent-review
  - atomic-delivery
  - brand-survival
synced_to: [plan]
---

# Foundations PRs MUST NOT declare contracts the dispatch layer does not yet deliver

When splitting a feature into a "foundations" PR (router module, devDep,
quiescent surfaces) and a downstream "wiring" PR (per-turn dispatch
integration, content-block attachment, prefix injection), the
foundations PR MUST NOT ship system-prompt directives, observability
events, schema fields with consumer expectations, or any other
**contract-declaring surface** whose delivery requires the downstream
PR. Either:

1. Land both PRs together (atomic delivery).
2. Gate the contract-declaring surface behind a feature flag that
   defaults closed until the downstream PR ships.
3. Fall through to the existing pre-feature behavior in the
   foundations PR (the chosen remediation here).

Shipping the directive ahead of delivery creates a production-reachable
interim window where the model honors the contract by fabricating the
data the contract promised.

## Problem

PR #3440 split feature #3436 (chapter-chunking PDF resolver) into:
- **Phase 3.A foundations:** router module (`pdf-chapter-router.ts`),
  `@anthropic-ai/sdk` devDep, system-prompt directive in both
  Concierge (`soleur-go-runner.ts`) and Leader (`agent-runner.ts`)
  declaring TOC + content-block contract + chapter-prefix instruction.
- **Phase 3.B (deferred to #3472):** the dispatch-time per-turn
  `selectChapter` invocation + buffer re-read + page-range slice +
  `document` content-block attachment on the SDK user message + state
  carry + assistant-text prefix injection.

The Phase 1+2 resolvers (already merged on this branch) emit
`documentExtractMeta.chapters` for outline-bearing oversized PDFs. With
Phase 3.A's directive added, an outline-bearing oversized PDF reaching
production would:

1. Resolver emits `chapters`.
2. Runner builds the chapter-chunked directive: "the most-relevant
   chapter for each of the user's questions will be routed and
   attached on that user turn as a `document` content block. Treat
   that block as the authoritative source for your answer."
3. Leader directive additionally forbids the SDK Read tool on this PDF.
4. User sends a question. **No chapter router runs. No content block
   is attached.** The user message reaches the model with only the
   question text.
5. Model honors the directive's prefix mandate (`Prefix every reply
   with [Answering from chapter <N>: "<title>"]`) by either fabricating
   a chapter number that satisfies the format or refusing with a
   confident-looking but ungrounded prefix.

The plan's `## User-Brand Impact` mitigation #1 (the chapter prefix as
"the load-bearing single-turn correction surface") was **inverted** by
this state — the prefix actively launders fabrication as grounded
retrieval. Crosses the `single-user incident` brand-survival threshold
(plan §User-Brand Impact, AGENTS.md
`hr-weigh-every-decision-against-target-user-impact`).

## Investigation

Phase 3.A unit tests passed (3940 vitest, tsc clean) because:
- Router module tests mock `query()` deterministically.
- System-prompt tests assert the directive content but do not verify
  the dispatch layer attaches the content block the directive promises.

The flaw is a contract-vs-delivery mismatch invisible to unit tests by
design — neither the directive code nor the dispatch code is wrong in
isolation; the gap is in the **interim window between two PRs**.
Discovery required full-context multi-agent review: three independent
agents (architecture-strategist F1, data-integrity-guardian P1+P2,
user-impact-reviewer F1+F3+F4+F5) converged on the same finding by
asking different questions of the same diff:
- *"Is the resolver→runner contract integrity preserved across PR
  boundaries?"* (architecture)
- *"What user-visible state is reachable in production at merge
  time?"* (data integrity)
- *"What is the worst single-user outcome implied by this diff?"*
  (user-impact, fired because the plan declares
  `brand_survival_threshold: single-user incident`)

## Solution

Reverted both runner directive branches to fall through to PR #3430's
existing `buildPdfTooLongDirective` bridge whenever
`documentExtractMeta.chapters` is present. The bridge gives the user a
deterministic refusal naming the page count — same UX as before
Phase 2 emitted chapters. Resolver chapter emission stays (useful
telemetry for Phase 3.B).

Updated #3472 body to require that the chapter-chunked directive
revival lands **in the same commit** as the dispatch wiring (atomic
delivery is now the load-bearing invariant, encoded in the issue
description).

```ts
// Before (Phase 3.A initial — declared contract without delivery):
if (chapters && chapters.length > 0) {
  artifactDirective = [
    `The user is currently viewing: ${safeArtifactPath}`,
    "",
    "This PDF is large but I have the table of contents. The most-",
    "relevant chapter for each of the user's questions will be",
    "routed and attached on that user turn as a `document` content",
    "block. Treat that block as the authoritative source for your",
    "answer.",
    // ... TOC + chapter-prefix instruction + NO-ASK
  ].join("\n");
}

// After (fall-through until #3472 atomically lands directive + dispatch):
if (chapters && chapters.length > 0) {
  const safeNumPages = args.documentExtractMeta?.numPages ?? 0;
  artifactDirective = buildPdfTooLongDirective(
    safeArtifactPath,
    safeNumPages,
    NO_ASK,
  );
}
```

## Key Insight

A PR's risk class is not determined by the PR's diff alone — it is
determined by the **state space the diff opens up in production**. A
diff that adds a contract-declaring surface (system prompt, schema
field, observability event, type signature with consumer expectations)
extends the production state space the moment it merges, regardless of
whether a downstream PR has shipped the contract's fulfillment.

Multi-agent review reliably catches this when at least one agent
asks "what user-visible state is reachable in production at merge
time?" Single-perspective review (the author's own "is this PR
correct?") cannot — the directive code is locally correct; the
dispatch code that would deliver the contract is locally absent. The
defect lives in the seam between the two.

## Prevention

- When splitting a feature into N PRs, label each surface in the
  foundations PR as either **inert** (router module with no callers,
  devDep with no imports, types with no consumers, tests asserting
  "the dispatch path that exists in #N delivers X") or
  **contract-declaring** (system prompt, schema field consumed by
  downstream, observability event consumers expect, behavior change
  in already-shipped resolvers/dispatchers). Inert surfaces are safe
  to ship; contract-declaring surfaces require atomic delivery,
  feature flag, or fall-through.
- When the plan's brand-survival threshold is `single-user incident`,
  the `user-impact-reviewer` agent fires automatically at review.
  Trust its enumeration even when the diff "feels safe to ship as
  foundations" — the agent's job is to surface user-facing failure
  modes the author rationalized away.
- Issue trackers for follow-up PRs MUST include the atomic-delivery
  invariant explicitly when applicable. #3472's body now contains
  "the chapter-chunked directive revival MUST land in the same commit
  as the dispatch wiring" — a future maintainer who lands the dispatch
  without reviving the directive will not silently regress the bridge
  fall-through.

## Session Errors

1. **Bash tool CWD silently persisted across calls.** Early `cd
   apps/web-platform && tsc --noEmit` worked, but a later `cd
   apps/web-platform` failed with "No such file or directory" because
   shell state from the prior call had already moved CWD.
   **Recovery:** switched to absolute paths.
   **Prevention:** already documented in
   `bug-fixes/2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban.md`
   session errors. Reinforces "use absolute paths or chain in a single
   `&&` call; do not assume CWD reverts between Bash invocations."

2. **`@anthropic-ai/sdk@^0.95.1` blocked by bun's `minimum-release-age`
   (259200s / 3 days).** `bun install` failed with
   `error: No version matching "@anthropic-ai/sdk" found for
   specifier "^0.95.1" (blocked by minimum-release-age: 259200
   seconds)`.
   **Recovery:** ran `npm view @anthropic-ai/sdk time --json` to find
   a release older than 3 days, pinned `^0.92.0`.
   **Prevention:** when adding a new dependency, check the publish
   date of the chosen version via `npm view <pkg>@<version> time` and
   choose a release ≥3 days old to satisfy bun's minimum-release-age
   constraint. (Note: this dep was later removed entirely as
   speculative dead surface — see error 5.)

3. **Phase 3.A directive shipped ahead of dispatch wiring** — the core
   subject of this learning. **Recovery:** see Solution section above.
   **Prevention:** see Prevention section above.

4. **Vacuous fuzzy-match test used exact-title equality (Levenshtein
   distance = 0).** test-design-reviewer caught: reply
   `"Authentication and authorization"` against `chapter[2].title ===
   "Authentication and authorization"` exercised the fuzzy code path
   but not the actual edit-distance arithmetic. The test would have
   passed identically against an implementation that short-circuited
   on `outline.findIndex(c => c.title === reply)` and skipped fuzzy
   matching entirely.
   **Recovery:** replaced the test reply with paraphrase
   `"Authentication and authz"` (distance > 0, ratio < 0.3). Added an
   out-of-range numeric case (`"999"`) to also exercise the fuzzy
   fallback path.
   **Prevention:** when writing tests for fuzzy/distance/threshold
   logic, the test input MUST produce a non-zero metric value — use a
   paraphrase, never exact equality. New variant of the vacuous-RED
   pattern (peer:
   `test-failures/2026-04-18-red-verification-must-distinguish-gated-from-ungated.md`).

5. **Speculative dead surface for Phase 3.B shipped in Phase 3.A.**
   The `@anthropic-ai/sdk` devDep was added for `MessageParam` typing
   that Phase 3.B will use; the `userId` arg in `SelectChapterArgs`
   was a placeholder for BYOK lease wiring deferred to Phase 3.B; the
   `alternates: number[]` and `candidates: number[]` fields on the
   result discriminants were always `[]`. code-quality-analyst P1 and
   pattern-recognition P1 caught all three.
   **Recovery:** removed all dead surface from Phase 3.A; #3472 will
   re-introduce them when the consumer code lands.
   **Prevention:** when splitting a feature into foundations + follow-
   up PRs, the foundations PR MUST not include types/args/deps whose
   only consumer is the follow-up PR. "Pre-wiring for the next PR" is
   the same anti-pattern as "declaring a contract before delivery"
   (this learning's main subject) — both leave dead surface that
   pretends to be load-bearing. Add the type/arg/dep in the PR that
   actually uses it.

## Cross-References

- Plan: `knowledge-base/project/plans/2026-05-07-feat-chapter-chunking-pdf-resolver-plan.md`
- Issue: #3436 (parent feature), #3440 (this PR), #3472 (Phase 3.B
  follow-up with atomic-delivery invariant)
- Peer learning: `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`
- Peer learning: `2026-05-03-user-impact-reviewer-catches-runtime-content-tamper-vectors.md`
- Peer learning: `2026-05-06-user-impact-section-by-role-not-surface.md`
- Peer learning: `2026-05-07-typed-optional-field-wire-drop-caught-by-user-impact-reviewer.md`
