---
module: Web Platform
date: 2026-04-02
problem_type: test_failure
component: testing_framework
symptoms:
  - "Structural test with lazy regex passed when it should have failed (RED phase)"
  - "Regex /const githubLogin[\\s\\S]*?;/ matched at semicolons inside TypeScript type annotations instead of the assignment terminator"
root_cause: logic_error
resolution_type: test_fix
severity: medium
tags: [regex, structural-test, typescript, tdd, lazy-quantifier]
---

# Troubleshooting: Lazy Regex Quantifiers Match Prematurely at TypeScript Type Annotation Semicolons

## Problem

When writing a structural test to verify that `user_metadata?.user_name` was absent from a TypeScript `githubLogin` assignment, a lazy regex `/const githubLogin[\s\S]*?;/` matched too early — stopping at a semicolon inside the inline type annotation `{ provider: string; identity_data?: ... }` rather than at the assignment's terminating semicolon.

## Environment

- Module: Web Platform (install route)
- Affected Component: `apps/web-platform/test/install-route.test.ts`
- Date: 2026-04-02

## Symptoms

- Structural test intended to FAIL in TDD RED phase passed instead
- The regex captured only `const githubLogin = user.identities?.find( (i: { provider: string;` — stopping at `string;`
- The captured substring did not include the `user_metadata` fallback that the test was meant to detect

## What Didn't Work

**Attempted Solution 1:** Lazy regex `/const githubLogin[\s\S]*?;/` to extract the assignment block

- **Why it failed:** TypeScript inline type annotations contain semicolons (`{ provider: string; identity_data?: { user_name?: string } }`). The lazy `*?` quantifier stops at the *first* semicolon, which is inside the type — not at the assignment terminator.

## Session Errors

**setup-ralph-loop.sh path was wrong on first attempt**

- **Recovery:** Changed path from `./plugins/soleur/skills/one-shot/scripts/` to `./plugins/soleur/scripts/`
- **Prevention:** The one-shot skill instructions reference the correct path; verify script paths exist before running.

## Solution

Replaced the block-extraction regex with a whole-file pattern match:

```typescript
// Before (broken — matches too early at type annotation semicolons):
const match = routeSource.match(/const githubLogin[\s\S]*?;/);
expect(match).not.toBeNull();
expect(match![0]).not.toMatch(/user_metadata/);

// After (fixed — simple whole-file assertion):
expect(routeSource).not.toMatch(/user_metadata\?\.user_name/);
```

## Why This Works

1. **Root cause:** Lazy quantifiers (`*?`) are greedy-minimal — they match the shortest string that satisfies the pattern. When the source contains semicolons inside type annotations, the first `;` satisfies the lazy match before reaching the actual end of the assignment.
2. **The fix avoids block extraction entirely.** Since the goal is to assert absence of a specific pattern (`user_metadata?.user_name`) from the entire file, there is no need to extract the assignment block first. A direct whole-file regex is simpler and immune to TypeScript syntax edge cases.
3. **The structural test pattern in this codebase** (reading source with `readFileSync` and asserting on content) already uses whole-file assertions for the ordering test at line 250-259. The new test follows the same approach.

## Prevention

- When writing structural tests against TypeScript/JavaScript source, prefer whole-file assertions over block-extraction regexes. TypeScript's type system introduces semicolons, colons, and braces inside expressions that break naive delimiters.
- If block extraction is genuinely needed, use a greedy quantifier with a more specific terminator (e.g., match to end-of-line with `$` flag) or use an AST parser instead of regex.
- Always verify the RED phase of TDD — if a test passes when it should fail, the test is not testing what you think it is.

## Related Issues

- See also: [nonce-based-csp-nextjs-middleware](../2026-03-20-nonce-based-csp-nextjs-middleware.md) — another structural test that reads middleware source to enforce security invariants
