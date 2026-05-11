---
name: Rename the fixture, don't regex the assertion — RNG-substring-collision flake class
description: When `not.toContain("<literal>")` flakes because rendered output embeds RNG-derived strings, prefer renaming the fixture literal to a character outside the RNG's alphabet over adding word-boundary regex semantics.
type: best-practices
category: test-design
module: apps/web-platform/test
related: 2026-04-15-multi-agent-review-catches-bugs-tests-miss.md
---

# Rename the fixture, don't regex the assertion (RNG-substring-collision flake class)

## Problem

`apps/web-platform/test/cc-attachment-pipeline.test.ts:233` asserted that an
attachment context did NOT contain the substring `"b.png"` (the filename of an
attachment whose download failed). The rendered context embedded a per-line
`randomUUID()` suffix: `…/<uuid>.png`. When the UUID happened to end in `b`
(1/16 hex nibbles), the rendered path was `…<hex>b.png` and the negative
assertion tripped on the UUID suffix — not on a real `b.png` filename token.
~6.25% post-merge flake rate.

The original issue body (#3611) and the deepened plan both proposed a
word-boundary regex fix: `expect(...).not.toMatch(/\bb\.png\b/)`. The regex
works (verified against an empirical truth-table) — but introduces:

- `\b` semantics to audit (UUID-internal `<hex>b.png` is word→word, no boundary fires).
- Template-shape risk: if a future render places `_b.png` adjacent (underscore is a word char), `\b` suppresses the boundary.
- A 320-line plan justifying the regex with truth-tables, probability math, and a deferred deterministic-UUID-spy follow-up.

## Solution (strictly simpler)

Rename the failing-download fixture from `b.png` to a filename whose first
character is OUTSIDE the RNG's alphabet. Since `node:crypto.randomUUID()` v4
emits ONLY `[0-9a-f]`, any non-hex letter (`g`–`z`) makes the substring
assertion **collision-proof by construction**:

```diff
-    if (storagePath.endsWith("b.png")) {
+    if (storagePath.endsWith("z.png")) {
         return { data: null, error: new Error("storage 404") };
     }
-      filename: "b.png",
-      storagePath: `${userId}/${conversationId}/b.png`,
+      filename: "z.png",
+      storagePath: `${userId}/${conversationId}/z.png`,
-    expect(attachmentContext).not.toContain("b.png");
+    expect(attachmentContext).not.toContain("z.png");
```

No `\b`. No regex. No truth-table. No deferred spy. The data side does the
work the assertion side was being twisted into doing.

## Key Insight

**When a test asserts `not.toContain("<short literal>")` over output that
embeds RNG-derived strings, the cheapest fix is on the data side, not the
assertion side.**

Before reaching for regex/word-boundaries:

1. What is the RNG's alphabet? (`randomUUID()` v4 → `[0-9a-f]`,
   `nanoid` default → `[A-Za-z0-9_-]`, `Math.random().toString(36)` → `[0-9a-z]`.)
2. Pick a fixture literal whose first character cannot appear in the RNG
   output, OR is followed by a separator the RNG cannot emit.
3. Keep the assertion in its simplest form.

This generalizes:

- `randomUUID()` (hex) → use any letter `g`–`z` as the fixture's first char.
- `nanoid` (Base64URL-ish) → use a literal containing `.` immediately after a
  character class member, or a non-alphanumeric separator.
- `Date.now()` (digits) → use a non-digit literal.

The plan-time precedent search ran the existing best-practice from
work-skill prose ("prefer word-boundary regex or line-anchored regex over
`toContain`") and stopped there. That precedent enumerates **two
assertion-side fixes** and zero data-side fixes. Update it.

## Meta-Learning: Simplicity-Reviewer DISSENT Is Load-Bearing

Multi-agent review on this PR returned **10 approvals + 1 DISSENT**:

- git-history-analyzer, pattern-recognition, architecture-strategist,
  security-sentinel, performance-oracle, data-integrity-guardian,
  agent-native-reviewer, code-quality-analyst, test-design-reviewer (8.9/10
  Grade B), semgrep-sast — all "No findings" on the regex fix.
- code-simplicity-reviewer surfaced the fixture rename as strictly simpler.

If the reviewer fleet had voted by majority, the regex would have shipped.
The DISSENT was the load-bearing signal. The framework rule
`cm-challenge-reasoning-instead-of` exists precisely for this case:
challenge the proposed approach (even when the user proposed it in the
issue body) when a simpler alternative is concretely identified.

Existing learning
`2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` documents the
"bugs in green-CI code" pattern. This is the sibling pattern:
**simplifications in green-review code**.

## Prevention

For future plans involving negative assertions over RNG-rendered output,
the plan author MUST:

1. Enumerate the RNG's emitted alphabet explicitly.
2. Weigh at least one **data-side fix** (fixture rename / fixture seed)
   against any **assertion-side fix** (regex, word-boundary, line-anchor).
3. If choosing the assertion-side fix, justify why the data-side fix is
   infeasible (it almost never is — fixture filenames carry no semantic
   meaning beyond "trigger this code path").

Proposed work-skill prose update (route-to-definition target —
`plugins/soleur/skills/work/SKILL.md`, search-key: "Negative substring
assertions over RNG-derived strings"): add option (c) **rename the fixture
literal to a character outside the RNG's alphabet** ahead of options (a)
word-boundary regex and (b) line-anchored regex. Mark (c) as the default;
(a) and (b) as fallbacks when the literal must be a real production value.

## Session Errors

1. **CWD drift after chained `cd && ...` Bash call.** The first targeted-test
   invocation used `cd apps/web-platform && bun run test:ci -- …`; the
   second invocation re-issued the same `cd apps/web-platform && …` from
   what the model believed was the worktree root but was actually
   `apps/web-platform` already, producing `cd: apps/web-platform: No such
   file or directory`. **Recovery:** drop the `cd` prefix and rely on the
   already-drifted CWD, or restart with an absolute `cd /home/jean/.../<worktree>`.
   **Prevention:** the project rule already exists in work-skill prose
   ("Bash tool does NOT persist CWD across calls; chain `cd <abs-path> &&
   <cmd>` in a single call"). Hook-enforceable via a Bash pre-tool guard
   that rejects relative `cd` after a previous chained `cd`, but the cost
   of the false-positive prompt outweighs the savings — leave as prose.

2. **Same CWD drift recurred at `git add apps/web-platform/...`** later in
   the session. Identical root cause and identical recovery. Same rule;
   the rule fired in prose but the model momentarily ignored it.
   **Prevention:** when issuing any path-prefixed Bash command in a
   worktree pipeline, prefix with `cd /home/jean/.../<worktree-root> &&`
   unconditionally rather than gambling on the prior CWD.

## Tags

category: test-design, best-practices
module: apps/web-platform/test, work-skill
prs: #3615
closes: #3611
related-prs: #3617 (closed wontfix)
