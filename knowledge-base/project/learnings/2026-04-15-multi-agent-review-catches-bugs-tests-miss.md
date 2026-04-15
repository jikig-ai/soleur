---
title: Multi-Agent Pre-Merge Review Catches Real Bugs That Tests Miss
date: 2026-04-15
category: workflow
tags:
  - code-review
  - multi-agent-review
  - module-level-state
  - input-validation
  - data-integrity
  - test-coverage-gaps
  - postgres-partial-index
module: plugins/soleur/skills/review
---

# Learning: Multi-Agent Pre-Merge Review Catches Real Bugs That Tests Miss

## Problem

On PR #2347 (KB chat sidebar), 12 parallel review agents caught **three P1
blockers** in code that had passed 1463 vitest tests and clean `tsc` over
seven phased commits. All three bugs were real, user-affecting defects
shipped across Phases 3–7 with green CI:

1. **MarkdownRenderer module-level state race** (review #2380) — two
   `let` bindings at module scope mutated per render, but
   `DEFAULT_COMPONENTS` was built once at module load and closed over the
   bindings. Any two co-mounted `<MarkdownRenderer>` instances (sidebar
   + full chat route, two assistant bubbles in the message list) raced;
   whichever rendered last silently flipped `wrapCode`/`nofollow` for
   both. Shipped in Phase 3 commit `e7c898ac`; lived in the codebase
   for two more commits before review caught it.
2. **`resumeByContextPath` WS field lacked validation** (review #2381)
   — unvalidated client string flowed straight into a Supabase `.eq()`
   predicate and onto persisted session state. DoS surface (arbitrarily
   long strings fill the partial UNIQUE index with no per-user cap) and
   type-confusion surface (`.eq()` coerces non-string types). Shipped
   in Phase 2 commit `6c19ce68`.
3. **UNIQUE partial index predicate mismatch** (review #2382) —
   migration 024's index was `WHERE context_path IS NOT NULL`, but the
   ws-handler lookup filtered `.is("archived_at", null)`. Archiving a
   KB conversation left the row holding the unique slot; next open hit
   23505, fallback lookup couldn't find the archived row, threw
   `"Failed to resolve"`. The KB path was permanently bricked for that
   user. Shipped in Phase 2 commit `6c19ce68`.

None of the three bugs triggered a test failure. All three have clear
attack paths or user-visible break conditions.

## Root causes

### Bug #1 — Module-level mutable state closed over by a once-built object

`components/ui/markdown-renderer.tsx` looked like:

```ts
let linkRel = "noopener noreferrer";
let preWrap = false;

function buildComponents(): Components {
  return {
    pre: ({children}) => <pre className={preWrap ? "wrap" : "scroll"}>...</pre>,
    a:   ({href, children}) => <a rel={linkRel} ...>...</a>,
  };
}

const DEFAULT_COMPONENTS = buildComponents();  // ← built ONCE at import

export function MarkdownRenderer({ content, nofollow, wrapCode }: Props) {
  linkRel = nofollow ? "nofollow ..." : "...";   // ← shared mutation
  preWrap = !!wrapCode;
  return <Markdown components={DEFAULT_COMPONENTS} ...>{content}</Markdown>;
}
```

The `pre` and `a` component factories inside `DEFAULT_COMPONENTS` close
over the `let` bindings **by reference**, not by value. So:

1. Sidebar `MarkdownRenderer` runs, writes `preWrap = true`.
2. Before React commits, a full-variant `MarkdownRenderer` in the same
   tree runs, writes `preWrap = false`.
3. Both components commit using `DEFAULT_COMPONENTS`, which now reads
   `preWrap = false`. Sidebar renders `overflow-x-auto` instead of
   `whitespace-pre-wrap`. Silent.

Tests passed because they only mounted one renderer at a time.

### Bug #2 — Sibling-field validator scope

`validateConversationContext(msg.context)` rigorously validated the
`context` field of `start_session` messages. But `resumeByContextPath` is
a **sibling** top-level field on the same message, added later. No one
audited whether the existing validator covered it. It didn't.

The name `validateConversationContext` correctly describes its scope but
gives no hint that sibling fields might also need validation.

### Bug #3 — Partial index predicate ≠ application query predicate

The migration author thought: "only non-null `context_path` rows need
uniqueness." Correct. The handler author thought: "when looking up an
existing thread, exclude archived ones." Also correct. Neither author
noticed that the predicates disagreed. The index happily allows a row
pair `(non-null path, non-null path)` when one is archived — but the
application's 23505-fallback lookup filters archived rows, so when the
insert hits 23505, the fallback can't find the conflicting row.

The bug is silent until a user archives a KB conversation — then it
manifests as a confusing "Failed to resolve" error on their next open
of that doc. Tests didn't cover archive-then-reopen.

## Solution

### Fix #1 — Per-render `useMemo` with explicit options bag

```ts
function buildComponents({ linkRel, preWrap }: BuildOptions): Components {
  return { /* ... reads linkRel/preWrap as params, not closure ... */ };
}

export function MarkdownRenderer({ content, nofollow, wrapCode }: Props) {
  const components = useMemo(
    () => buildComponents({
      linkRel: nofollow ? "nofollow ..." : "...",
      preWrap: !!wrapCode,
    }),
    [nofollow, wrapCode],
  );
  return <Markdown components={components} ...>{content}</Markdown>;
}
```

No module-level mutable state. Each instance owns its own `components`
object; React memoizes re-renders via `useMemo`.

Regression test: `test/markdown-renderer.test.tsx` co-mounts a sidebar
renderer (`wrapCode=true, nofollow=false`) next to a full renderer
(`wrapCode=false, nofollow=true`) in the same tree, asserts each `<pre>`
and each `<a>` keeps its own classes + rel.

### Fix #2 — `validateContextPath()` helper applied at both use sites

```ts
const CONTEXT_PATH_MAX_LEN = 512;
const CONTEXT_PATH_PREFIX = "knowledge-base/";
const CONTEXT_PATH_ALLOWED = /^[\w\-./]+$/;

function validateContextPath(v: unknown): string | null {
  if (typeof v !== "string") return null;
  if (v.length === 0 || v.length > CONTEXT_PATH_MAX_LEN) return null;
  if (!v.startsWith(CONTEXT_PATH_PREFIX)) return null;
  if (!CONTEXT_PATH_ALLOWED.test(v)) return null;
  return v;
}
```

Applied before the DB lookup AND before `session.pending.contextPath =
validResumePath`. Invalid input produces `{ type: "error", message:
"Invalid resumeByContextPath" }` — fail fast, no DB round-trip.

Four new rejection tests cover non-string, >512-char, missing-prefix,
and disallowed-char inputs.

### Fix #3 — Migration 025 aligns index predicate with query filter

```sql
DROP INDEX IF EXISTS public.conversations_context_path_user_uniq;

CREATE UNIQUE INDEX conversations_context_path_user_uniq
  ON public.conversations (user_id, context_path)
  WHERE context_path IS NOT NULL AND archived_at IS NULL;
```

Archiving now frees the unique slot so a fresh conversation can take
it. Also tightened the 23505 disambiguation in
`ws-handler.ts:createConversation` to match by index name
(`conversations_context_path_user_uniq`) before falling through — so an
unrelated unique constraint can't silently route through the
context_path lookup.

## Key Insight

**Review agents catch whole classes of defects that unit tests
structurally cannot see.** Each of the three P1 bugs has a distinct
test-invisibility signature:

+ **Shared mutable state across co-mounted instances.** Tests mount one
  instance per file; a race needs two simultaneous mounts in a tree
  with a shared module. Unit tests rarely set this up. A
  pattern-recognition agent reading the source can spot the closure
  capture in seconds.
+ **Untrusted input shape on sibling fields.** Tests cover the happy
  path shape they see documented. A security agent asks "what if the
  client sends X?" for every permutation — non-string, oversize,
  prefix-missing, SQL-injection-like — without waiting for the test
  author to imagine it.
+ **Predicate drift between DB constraints and application queries.**
  Tests either hit the index predicate OR the application filter, rarely
  both in the same scenario. A data-integrity agent reads both files
  and compares WHERE clauses symbolically.

The practical consequence: **multi-agent pre-merge review is a
first-class correctness gate for this codebase, not a nice-to-have.**
The cost — 12 agents × ~100k tokens ≈ $0.50–$1 per review — is minor
compared to the cost of shipping a user-visible bug (archive-bricks-KB)
or a DoS surface (unvalidated resumeByContextPath).

### Corollary rules for future work

1. **Never use module-level `let` that a function mutates in a file
   that also exports a cached object constructed at module load.** The
   object closes over the `let` binding by reference. Either (a) pass
   options explicitly and memoize per-render, or (b) move the cached
   construction inside the function body.
2. **When adding a new field to a schema with an existing validator,
   audit whether the validator covers the new field.** Validator names
   describe what they validate, not what they don't — a field named
   `resumeByContextPath` needs its own guard if `validateConversationContext`
   only covers `context`.
3. **When writing a partial UNIQUE index, list every application query
   filter that relies on its semantics and confirm they agree.** The
   index predicate must be a **subset** of every dependent query's
   filter, or archived/soft-deleted rows become invisible ghosts that
   block inserts.

## Session Errors

1. **`cd apps/web-platform` in fresh Bash tool invocation returned "No
   such file or directory"** — Bash tool does not persist CWD across
   invocations. Happened 4× across phases. Already covered by existing
   rule `cq-for-local-verification-of-apps-doppler`. No new rule needed.
   **Prevention:** rely on the existing rule; use absolute paths in
   Bash invocations that follow a directory change.

2. **`npx markdownlint-cli2 --fix "knowledge-base/**/*.md"`** modified
   ~100 unrelated files on first run. Recovery: `git checkout --` on
   unrelated subtrees. **Prevention:** Target specific files, not
   repo-wide globs. Proposal: add a `cq` rule.

3. **`gh issue create --label "security"`** failed — actual label is
   `type/security`. Same class: `"P3"` vs `priority/p3-low`.
   **Prevention:** always `gh label list --limit 100 | grep <keyword>`
   before asserting a label's name. Proposal: add a `cq` rule.

4. **`node node_modules/vitest/vitest.mjs run` from bare repo root**
   returned `Cannot find module` — bare repo has no `node_modules`.
   Same class as #1. Already covered by `cq-for-local-verification-of-apps-doppler`.
   **Prevention:** always `cd apps/web-platform` first.

5. **`require("@/components/kb/selection-toolbar")` inside a test harness**
   — Vite transform rejected dynamic `require()` in ESM test file.
   Recovery: replaced with top-level `import`. **Prevention:** never
   use `require()` in Vite/ESM test files — use ESM `import` or
   dynamic `await import()`. Proposal: add a `cq` rule.

6. **First banner-dismiss implementation used a `baselineMessageCount`
   field that didn't match WS client `messages` semantics** — on resume,
   the client starts with empty `messages` (no server replay), so the
   baseline should be 0, not the historical message count. Recovery:
   simplified to "dismiss on any `count > 0`". **Prevention:** before
   implementing a behavior that reads WS-client state, check what the
   client-side state actually contains on the relevant event (vs
   server-side counterparts). Narrow; learning only, no rule.

7. **Reliance on `flashQuote` setTimeout without cleanup** —
   surfaced by review #2384 rather than during implementation. Already
   tracked as a P2 follow-up.

## Related Learnings

+ `2026-04-07-code-review-batch-ws-validation-error-logging-concurrency-comments.md`
  — prior WS-payload validation gap; same pattern as Bug #2 above.
+ `2026-04-10-multi-agent-review-catches-info-disclosure.md` — canonical
  multi-agent-review-catches-tests-miss precedent (info-disclosure
  variant). This learning extends it to three new defect classes:
  module-level state race, input validation on siblings, and partial
  index predicate drift.
+ `2026-04-13-push-notification-review-findings-batch.md` — similar
  batch-of-review-findings shape to the 12 issues filed from this PR.
+ `2026-04-06-vitest-module-level-supabase-mock-timing.md` — prior
  module-level mutable-state pitfall, test-side. Bug #1 here is the
  runtime-side mirror.
+ `integration-issues/2026-04-14-atomic-webhook-idempotency-via-in-filter.md`
  — 23505 unique-violation handling pattern; Bug #3 is a predicate-drift
  variant of the same theme.

## Related Issues + PR

+ PR #2347 (kb-chat-sidebar)
+ Parent issue #2345
+ Fixed P1 issues: #2380, #2381, #2382
+ Open P2 follow-ups: #2383, #2384, #2385
+ Open P3 follow-ups: #2386, #2387, #2388, #2389, #2390, #2391
+ Deferred flag-removal follow-up: #2377
