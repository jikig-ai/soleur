---
title: Phase-1 instrumentation-only ship when a prior fix visibly missed
date: 2026-05-05
category: best-practices
module: cc-soleur-go
issue: 3287
prior_pr: 3278
prior_issue: 3253
related:
  - 2026-05-05-baseline-prompt-must-declare-capabilities-or-model-fabricates-missing-tools.md
  - 2026-05-04-cc-soleur-go-cutover-dropped-document-context-and-stream-end.md
tags: [sentry, breadcrumbs, observability, prompt-engineering, kb-pdf, multi-agent-review]
---

# Phase-1 instrumentation-only ship when a prior fix visibly missed

## Problem

PR #3278 shipped a positive PDF-capability directive to close the poppler-utils install cascade reported in #3253. The directive was string-shape-tested (5 scenarios in `read-tool-pdf-capability.test.ts`) and looked correct. Two weeks later #3287 was filed: the cascade still fires on a deployed `web-v0.64.9` against a freshly-archived KB conversation. The model not only emits the install cascade but fabricates a justification ("the Read tool requires poppler-utils, and the file path is sandbox-restricted from shell commands") — both clauses false against the codebase.

Three plausible causes, none falsifiable pre-merge:

- **A.** The strong directive isn't reaching the post-archive thread (client-side `context.path` delivery; resolver dropping the path; `hasActiveCcQuery` Map leak).
- **B.** Strong directive IS reaching it, model overrides anyway (positional weakness in the prompt).
- **C.** Positive framing is below the override threshold for this tool-class prior; needs a targeted named-tool exclusion list (positionally-pinned negation, not blanket negation).

Re-prompt-engineering blind would re-run the #3278 cycle: ship-a-guess → wait-for-#3288 report. The string-shape tests can't catch the failure because they don't reach the model.

## Solution

Ship Phase 1 ALONE: a Sentry breadcrumb at the cc-soleur-go cold-Query construction site (`apps/web-platform/server/ws-handler.ts:691-697`), no directive change. The breadcrumb's `data` payload pins the load-bearing state at the SINGLE point where directive-presence is decided:

```ts
{
  hasContextPath: boolean,           // A.1: client never sent context.path
  pathBasename: string | null,       // PII-safe; full path never logged
  pathExtension: string | null,      // lastIndexOf-guarded (no dotless-basename pollution)
  hasActiveCcQuery: boolean,         // A.4: warm Query dragged across archive
  documentKindResolved: "pdf" | "text" | null,  // A.3: resolver dropped the path
  documentContentBytes: number,      // length only, not content
  conversationId: string,
  routingKind: string,
}
```

Paired with a `level: "warning"` `captureMessage` ONLY when `hasContextPath && !hasActiveCcQuery && documentKindResolved === null` — the suspicious-skip case where a path arrived AND the resolver was actually invoked AND it returned nothing. Sentry breadcrumbs are scope-attached (only surface when an event is sent in the same scope), so the conditional captureMessage is the artifact that actually shows up in dashboards.

Phase 2 fix-shape (2A client-side rebind vs. 2B positional move + 2C named-tool exclusion list) is gated on what the FIRST production reproduction's breadcrumb data reveals. Two reproductions worth of data settles A vs B vs C; the fix lands narrow and falsifiable.

## Key Insights

1. **When a prior fix visibly missed, the next ship is instrumentation, not a second guess.** Re-prompt-engineering blind re-runs the cycle that produced the regression. Two reproductions of breadcrumb data is the difference between a 90-minute fix-shape decision and another 2-day prompt-A/B cycle. Phase 1 ship-and-watch is load-bearing: skipping it is the failure mode that produced #3287.

2. **The cold-Query system prompt is immutable across the conversation's lifetime** (`apps/web-platform/server/soleur-go-runner.ts:1-23`). A misbaked first turn cannot be repaired turn-2. This makes the cold-Query construction site the SINGLE point where directive-presence is decided — instrumenting that one site captures the maximally informative observation.

3. **Sentry tag taxonomy: split feature/op, never hyphen-suffix feature.** `{ feature: "cc-pdf-resolver", op: "skip" }` aligns with the ~30 in-tree feature/op precedents and lets dashboards filter by feature alone. `{ feature: "cc-pdf-resolver-skip" }` collapses two dimensions into one tag and breaks "show me all cc-pdf-resolver events" filters.

4. **`pathExtension` extraction must use `lastIndexOf(".")` with a `> 0` guard.** `"Makefile".split(".").pop()` returns `"makefile"`, not `null` — pollutes the dimension with the whole filename for any dotless basename. The lastIndexOf guard yields `null` cleanly.

5. **Breadcrumb-only emit is invisible. Pair with a conditional `captureMessage`.** Breadcrumbs only surface when an event (exception or message) is sent in the same scope. The pairing is structural: breadcrumb on every cold-Query construction (signal) + captureMessage only on the suspicious-skip branch (event that pulls the breadcrumbs into Sentry's UI).

## Files Changed

- `apps/web-platform/server/ws-handler.ts` — exported helper `emitConciergeDocumentResolutionBreadcrumb`, wired at the cold-Query construction site after `documentArgs` resolution.
- `apps/web-platform/test/ws-handler-cc-pdf-breadcrumb.test.ts` — 7 scenarios pinning category, message, level, payload, PII non-leak, suspicious-skip captureMessage shape, and the dotless-basename `pathExtension: null` guard.

## Session Errors

1. **CWD non-persistence lapse on a chained Bash call.** After `cd apps/web-platform && ./node_modules/.bin/vitest`, the next call (without `cd`) errored `No such file or directory` because the Bash tool doesn't persist CWD across calls. Recovery: re-ran from the worktree root. **Prevention:** already covered by AGENTS.md `hr-the-bash-tool-runs-in-a-non-interactive` and the work skill's Phase 2 sharp edge "always chain `cd <abs-path> && <cmd>` in a single Bash call." No new rule needed.

2. **Pattern reviewer false-positive P1 (Sentry try/catch guard).** Agent recommended wrapping every Sentry call in try/catch citing `observability.ts:99-114`, but five in-file precedents use unguarded direct calls (`api-messages.ts:104`, `concurrency.ts:31`, `rate-limiter.ts:285`, `ws-handler.ts:483`, `:509`). Verifying against precedent took one grep. **Prevention:** when a reviewer prescribes adding a defensive wrapper, grep the surrounding file/module for ≥3 sibling unwrapped invocations of the same primitive before applying. If precedent is consistent with the new code, the wrapper is the deviation, not the new code.

3. **Performance reviewer false-positive P2 (captureMessage on unsupported extensions).** Agent reasoned about resolver behavior without reading `kb-document-resolver.ts`. The resolver returns `documentKind: "pdf" | "text"` for ANY `knowledge-base/`-prefixed path; the only paths that yield `documentKind === null` are non-`knowledge-base/` paths, traversal attempts, and workspace-fetch failures — all genuinely suspicious. Verifying took one grep. **Prevention:** when a reviewer claims a code path "fires on every legit non-X case," read the upstream producer's actual return contract before applying the fix. The reviewer's mental model of the producer can be wrong by a major branch.

## Prevention

- **Workflow rule (skill-level):** when fixing a P1 user-facing regression where a prior fix visibly missed (`fix(*): #N fix insufficient — Y still does Z`), prefer "ship instrumentation only, gate fix on data" over "re-prompt-engineer blind." The instrumentation site is whichever single point in the codebase decides the regression's outcome — for cc-soleur-go, the cold-Query construction site.

- **Multi-agent review hygiene:** before applying a reviewer-prescribed defensive wrapper (try/catch, type-guard, validation), grep the same file/module for ≥3 sibling unwrapped invocations. When precedent is consistent and the new code mirrors it, the wrapper recommendation is precedent-contradicting and rejected unless the reviewer cites a specific incident the precedent does not address.

- **Reviewer agents are not omniscient about producer contracts.** When a reviewer describes downstream behavior conditional on an upstream producer's return shape, verify the producer's actual contract by reading the producer module. The 1-minute verification cost is dwarfed by the cost of applying a fix that masks the actual signal.

## Cross-References

- Issue: <https://github.com/jikig-ai/soleur/issues/3287>
- Prior PR (incomplete fix): <https://github.com/jikig-ai/soleur/pull/3278>
- Prior issue: <https://github.com/jikig-ai/soleur/issues/3253>
- Anticipated by: `knowledge-base/project/learnings/2026-05-05-baseline-prompt-must-declare-capabilities-or-model-fabricates-missing-tools.md` Prevention block ("if a third 'tool X doesn't seem installed' report appears post-merge...")
- Cutover history: `knowledge-base/project/learnings/2026-05-04-cc-soleur-go-cutover-dropped-document-context-and-stream-end.md`
