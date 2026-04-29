---
date: 2026-04-29
category: build-errors
module: apps/web-platform
tags: [esbuild, typescript, unicode, regex, vitest]
related_pr: 3020
---

# U+2028/U+2029 literal characters in TypeScript source break esbuild

## Problem

While hardening `SHELL_METACHAR_DENYLIST` in `apps/web-platform/server/permission-callback.ts` to reject Unicode line/paragraph separators (U+2028, U+2029) — the project's documented Unicode-injection hardening pattern — I wrote the regex character class using literal Unicode codepoints:

```ts
const SHELL_METACHAR_DENYLIST = /[;&|`<>$\n\r\\<U+2028><U+2029>]/;
```

Vitest failed to load the module with:

```
Unexpected ">"
  120 | const SHELL_METACHAR_DENYLIST = /[;&|`<>$\n\r\\<U+2028><U+2029>]/;
  121 | // Belt-and-suspenders: a 4096-char input cap before regex matching keeps
  122 | // pathological-length inputs from amplifying any backtracking cost.
      |                                         ^
```

The error pointed to line 122, column 39 — which is `>` in the word "amplifying". That's a comment, not code.

## Root cause

**ECMA-262 treats U+2028 (LINE SEPARATOR) and U+2029 (PARAGRAPH SEPARATOR) as line terminators in source code.** When esbuild's lexer hits the literal U+2028 inside the regex, it terminates the line — but the regex literal `/[...]/` was still open. The lexer then resumed parsing at the next physical line, which was a comment. The `//` comment-start was already past, so esbuild parsed the comment text as code and failed at the first ambiguous token (`>` in "amplifying").

A literal U+2028 in the **comment** above the regex would also break the build for the same reason.

## Solution

Use the JavaScript escape sequences ` ` and ` ` everywhere — both inside the regex literal AND in any surrounding comments that need to reference the codepoints:

```ts
// `$` is in the metachar denylist so `echo "$VAR"` (which bash expands
// inside double quotes) is rejected. U+2028 / U+2029 (LINE/PARAGRAPH
// SEPARATOR) are included to match the project's Unicode line-separator
// hardening pattern.
const SHELL_METACHAR_DENYLIST = /[;&|`<>$\n\r\\  ]/;
```

The regex matches the same characters either way; only the source representation differs.

## Tests added

The new tests in `apps/web-platform/test/permission-callback-safe-bash.test.ts` use ` ` / ` ` in test strings:

```ts
test("Unicode line separators (U+2028/U+2029) are rejected as command-separator equivalents", () => {
  expect(isBashCommandSafe("pwd ls")).toBe(false);
  expect(isBashCommandSafe("pwd ls")).toBe(false);
});
```

## Prevention

When writing TypeScript that needs to match U+2028/U+2029 (or any other code-point ECMA-262 treats as a line terminator), **always use `\uXXXX` escape sequences in the source** — never the literal characters. This applies to:
- Regex character classes
- String literals
- Comments referencing the codepoints
- Test fixtures asserting on these characters

Editor configurations (e.g., VSCode "render whitespace") usually do not visibly distinguish U+2028 from a regular newline, making the bug invisible until build time. The cheapest gate is a `pre-commit` grep for literal U+2028/U+2029 in `*.ts` / `*.tsx` files: `git diff --cached -U0 | grep -P '[\x{2028}\x{2029}]'` exits non-zero if a literal slipped in.

## Session Errors

- **U+2028 literal in regex character class broke esbuild parse** — Recovery: use `  ` escape sequences in both the regex AND surrounding comments. Prevention: pre-commit grep gate for literal U+2028/U+2029 in `.ts`/`.tsx` source.
- **`@ts-expect-error` directives became unused after function signature widened to `unknown`** — Recovery: tsc's `noUnusedExpectErrors` flagged 3 directives in `permission-callback-safe-bash.test.ts` after `isBashCommandSafe(command: unknown)` accepted defensive runtime branches without TS errors. Removed the directives. Prevention: when widening a function to accept defensive inputs (`unknown`), grep its tests for `@ts-expect-error` and remove orphaned directives in the same edit.
- **4 test stub objects in `cc-dispatcher.test.ts` hid missing `notifyAwaitingUser` method via `as any`** — Recovery: pattern-recognition-specialist caught it during review; added explicit `notifyAwaitingUser: () => {}` to each stub. Prevention: when adding a method to an interface that has any test-stub consumers, search the test directory for `as any` casts of the same shape and patch each in the same edit. Stronger: replace `as any` with `satisfies SoleurGoRunner` where possible so future additions surface as compile errors at the stub site.
- **Sub-agent test-runner reporting mismatch** — Some review sub-agents reported running `bun test apps/web-platform/test/...` but the actual configured runner is `vitest` (`npm run test:ci`). Their reported pass/fail counts may have come from a different runner and shouldn't be load-bearing on the main agent's verification. Prevention: when delegating test-execution to sub-agents, name the exact command (e.g., `cd apps/web-platform && npx vitest run <files>`) in the prompt rather than letting the agent guess.

## References

- PR #3020 — Command Center QA fixes (the consolidated PR where this surfaced)
- ECMA-262 §11.3 — Line Terminators (lists U+2028 LINE SEPARATOR and U+2029 PARAGRAPH SEPARATOR as terminators)
- Project precedent: `cc-dispatcher.ts buildSoleurGoSystemPrompt` and `subagentStartPayloadOverride.sanitizer` already strip U+2028/U+2029 from user input — this learning extends the pattern to source code itself.
