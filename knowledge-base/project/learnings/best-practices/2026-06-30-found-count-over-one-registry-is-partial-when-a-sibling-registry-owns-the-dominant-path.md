# Learning: a found-count over ONE registry is a partial signal when a sibling registry owns the dominant path

## Problem

Phase 1 of the multi-host `/workspaces` epic (#5274) widened `abortSession`
(`agent-session-registry.ts`) from `void → number`, returning the count of
sessions it aborted, to give a future Phase-3 coordinator a "is this conversation
live on THIS host?" affordance (ADR-068 §4: local-resolve → found 0 → RPC-forward
to the lease-holder). The docstring asserted: *"0 ⇒ the turn finished locally OR
lives on another host."*

That claim is **false for the dominant path.** `abortSession` only ever inspects
`activeSessions` — the legacy `sendUserMessage` lineage. The cc-soleur-go lineage
(the dominant production path since #3270) is tracked in a **separate** registry
(`activeQueries`) and aborted via `closeCcConversation`, and is **never** registered
in `activeSessions`. So for a live cc-soleur-go turn on this host, `abortSession`
returns **0** — a false zero in the exact direction the affordance exists to serve.

- **Phase-1 impact: none.** All 6 call sites discard the return value (the
  type-widening sweep confirmed this), so the contract is latent today.
- **Phase-3 risk: real.** A coordinator routing its forward decision on this count
  alone would treat a locally-live cc conversation as "not here" and forward it —
  a wasted RPC at best, a missed abort at worst.

This was caught by `data-integrity-guardian` at **PR review**, and missed by all
four plan-review agents (spec-flow + DHH/Kieran/Simplicity) **and** the author.

## Solution

The code is correct (it counts what it counts); the **contract/docstring** was
wrong. Fix applied inline: scope the return-value claim explicitly to the legacy
`activeSessions` lineage and warn that a complete "live here?" predicate must `OR`
this with a cc-registry found-count — i.e. `closeCcConversation` needs the same
widening, or introduce a unified `isConversationLiveHere(uid, conv)` spanning both
registries before Phase 3 builds the forward decision on it.

## Key Insight

The dual-lineage rule from
[[2026-06-14-ws-lifecycle-hook-must-cover-both-legacy-and-cc-soleur-go-turn-boundaries]]
— *any turn-boundary signal must cover BOTH the legacy and cc-soleur-go lineages* —
applies to **count-affordances and predicates**, not just lifecycle hooks. Any
function that answers "is this conversation X on this host?" (live, aborting,
gated, checkpointing) by reading a single registry is a **partial** signal when a
sibling registry governs the dominant path. The tell is right there in the code:
`runDisconnectGraceAbort` itself signals BOTH surfaces (`abortSession` AND
`closeCcConversation`) — so a *count* derived from only one of them cannot be a
complete answer for the same question.

**Reviewer takeaway:** when a PR widens a function to return a count/boolean that a
future consumer will treat as a "live/present here?" predicate, grep for sibling
registries of the same entity (`activeSessions` ↔ `activeQueries`,
`pendingDisconnects` ↔ cc gates) and require the predicate to span every registry
that holds the dominant path — or scope the docstring to the single lineage and
name the gap so the downstream consumer cannot build on a false-complete contract.
This is a **review-time / data-integrity** strength: plan-review panels
(simplicity/taste/convention lenses) reliably miss cross-registry contract
completeness; the count-contract correctness lens lives in `data-integrity-guardian`.

## Session Errors

1. **`abortSession` count docstring overclaimed completeness** (blind to the cc
   lineage). Recovery: docstring scoped to the legacy lineage + Phase-3 obligation
   named, at PR review. **Prevention:** this learning + the reviewer takeaway above;
   when widening a registry-derived count into a predicate, enumerate sibling
   registries first.
2. **Grace guard initially framed "belt-and-suspenders / behaviour-identical"** when
   it actually closes a real `replicas=1` race (`sessions.set` precedes the
   `pendingDisconnects`-cancel by three awaited DB calls). Recovery: reframed at
   plan review (Kieran + spec-flow). **Prevention:** for a "no-op seam" claim, trace
   the await-ordering between the state-set and the cancel before asserting race-free.
3. **Seam comments cited absolute line numbers** (`:2843`/`:2893`) that the comment's
   own 19-line insertion immediately invalidated. Recovery: replaced with
   grep-stable symbol anchors at PR review. **Prevention:** same-file instance of
   [[2026-06-18-doc-insertion-stales-cross-artifact-line-citations]] — never cite
   `:N` for code in the same file you are editing; use function/symbol anchors.
4. (one-off) A `perl` checkbox-flip regex missed `Widen \`abortSession(`; fixed with
   a targeted second sub. 5. (one-off) A `server/**/*.ts` pathspec grep returned
   empty from the app cwd; broader grep found the consumers. 6. (one-off) An Edit
   failed because the file was `sed`-inspected not `Read` first (already a hard rule;
   self-corrected). 7. (one-off) An Edit old_string mismatch; re-read and matched.

## Tags
category: best-practices
module: web-platform/agent-session-registry
related: [5274, 3270, 5240]
see-also: 2026-06-14-ws-lifecycle-hook-must-cover-both-legacy-and-cc-soleur-go-turn-boundaries, 2026-06-18-doc-insertion-stales-cross-artifact-line-citations
