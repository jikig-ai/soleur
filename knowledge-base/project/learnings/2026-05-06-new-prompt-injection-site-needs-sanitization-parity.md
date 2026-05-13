---
category: security-issues
module: cc-concierge / system-prompt builders
tags: [prompt-injection, sanitization-parity, sdk-read-tool, workspace-paths]
related-pr: 3384
related-issues: [3376, 3383]
prior-iterations: [3253, 3263, 3278, 3287, 3288, 3294, 3338, 3353]
---

# Learning: when adding a new path-injection site to a system prompt, audit sanitization parity with existing sites

## Problem

PR #3384 fixed the user-facing "I can't read this specific PDF — the file is outside my workspace boundary" reply (#3376) by widening `buildPdfGatedDirective(displayPath, absolutePath, noAskClause)` so the model receives an absolute Read path that satisfies the SDK's `FileReadInput.file_path` "absolute path" contract.

The implementation introduced a NEW prompt injection point (`Use the Read tool to read "${absolutePath}"`) without applying the same sanitization the existing display-path injection already had:

- **Display path** (`safeArtifactPath`) — sanitized via `sanitizePromptString` (strips control chars + U+2028 / U+2029 + 256-caps).
- **Absolute path** (`path.join(args.workspacePath, args.artifactPath)`) — UN-sanitized, intentionally because 256-cap would truncate long absolute paths mid-string.

This created two regressions caught only at multi-agent review:

1. **Prompt-injection vector** (security-sentinel + user-impact-reviewer): a malicious `artifactPath` containing `\n\nIGNORE PREVIOUS INSTRUCTIONS...` survives `validateConversationContext` (which checks `..`, leading `/`, null bytes — not control chars) and reaches the LLM as adjacent system instructions.
2. **Information-disclosure vector** (user-impact-reviewer P1): the absolute path embeds `users.workspace_path` (server FS topology + multi-tenant userId folder name). Model paraphrase could echo it to the user — a brand-degrading deployment-topology leak.

## Root Cause

When the existing PDF directive only injected the workspace-relative path, the in-place `sanitizePromptString` was sufficient. Adding the absolute-path injection changed the trust boundary without updating the sanitization contract — a classic "extend the surface, forget the existing guard" pattern.

The fact that `validateConversationContext` already rejects path-traversal (`..`, leading `/`) made it tempting to assume "the path is safe" — but that validator's threat model is FS escape, not prompt injection. Two different threat models collapse onto the same input.

## Solution

Two-layer fix applied in PR #3384 review commit `0a893c1c`:

1. **Sanitize the absolute path at the injection site** with a separator-strip-only sanitizer (no 256-cap so deep workspace paths survive intact):

```typescript
// eslint-disable-next-line no-control-regex -- intentional
const stripPromptSeparators = (v: string): string =>
  v.replace(/[\x00-\x1f\x7f  ]/g, "");
const absoluteReadPath = stripPromptSeparators(
  path.join(args.workspacePath, args.artifactPath),
);
```

Apply at both call-site shapes (`soleur-go-runner.ts buildSoleurGoSystemPrompt` and `agent-runner.ts startAgentSession`).

2. **Instruct the model to never echo the absolute path to the user** — defense-in-depth against paraphrase:

```typescript
`When referring to the document in your reply to the user, use the name "${displayPath}" — never the absolute filesystem path.`
```

Lock-step parity preserved by routing both call sites through `buildPdfGatedDirective`.

## Key Insight

**When introducing a new injection site into an LLM system prompt, audit ALL inputs to the new site for sanitization parity with existing injection sites in the same prompt.** The mental model "this input is already validated" is dangerous — most validators have a single threat model (FS escape, SQL injection, XSS), and prompt injection is a different threat model that requires its own sanitizer.

A useful litmus: for every interpolated value in a new system-prompt template, ask "if this value contained `\n\nIGNORE PREVIOUS INSTRUCTIONS`, would the prompt break?" If the answer requires consulting an upstream validator's source, your sanitization is implicit — make it explicit at the interpolation site.

## Edit-Tool Sharp Edge: U+2028/U+2029 in regex character classes

When applying the fix, the `Edit` tool silently rewrote literal U+2028 (e2 80 a8) and U+2029 (e2 80 a9) bytes in the new regex character class to ASCII spaces (0x20). The result `[\x00-\x1f\x7f<space><space>]/g` strips ALL spaces from sanitized content — a vacuous match.

This is the exact failure mode AGENTS.md rule `cq-regex-unicode-separators-escape-only` exists to prevent. The rule covers writing new regex character classes; this session shows it ALSO applies to comments next to such regexes (the rule fires on "U+2028/U+2029" appearing anywhere — and the comment in `soleur-go-runner.ts:732` has the exact substring).

**Recovery pattern:** when Edit silently strips U+2028/U+2029, use Python with byte-form replacement to swap raw bytes for `  ` escape form:

```python
broken = b'/[\\x00-\\x1f\\x7f\xe2\x80\xa8\xe2\x80\xa9]/g'
fixed  = b'/[\\x00-\\x1f\\x7f\\u2028\\u2029]/g'
content = content.replace(broken, fixed)
```

## Tags

category: security-issues
module: cc-concierge / system-prompt builders

## Session Errors

- **Edit tool silently rewrote literal U+2028/U+2029 to spaces in new regex char class** — Recovery: byte-form Python replacement to escape-form. Prevention: existing rule `cq-regex-unicode-separators-escape-only` already enforces this; the rule could note that the failure surfaces when *editing comments containing* the literal chars, not just when writing new regex source.
- **Test assertion drift** — `agent-runner-system-prompt.test.ts` asserted `"Read this file first"` substring, which was removed when the directive was rewritten to inject the absolute path. Recovery: updated assertion to grep for the new `Use the Read tool to read "${fullPath}"` substring with the actual workspace-relative test fixture. Prevention: when editing directive copy, grep the test corpus for substring assertions before committing.
- **Local Node 21.7.3 incompatibility with pdfjs-dist@5** — `process.getBuiltinModule is not a function`. Recovery: nvm-managed Node 22.22.2 via PATH override for test runs. Prevention: Bug C fix pins `engines.node ≥ 22.3` going forward; CI uses Node 22.

## Cross-references

- Plan: `knowledge-base/project/plans/2026-05-06-fix-sidebar-pdf-summarize-out-of-boundary-plan.md`
- AGENTS.md rule: `cq-regex-unicode-separators-escape-only`
- Related learning: `2026-04-15-multi-agent-review-catches-bugs-tests-miss.md` (this PR is another instance — multi-agent review caught a single-user incident-class vector that 3-agent plan-time review missed)
- Prior iterations on same surface: #3253, #3263, #3278, #3287, #3288, #3294, #3338, #3353 (this PR closes the gated-Read fallback that prior fixes left open)
