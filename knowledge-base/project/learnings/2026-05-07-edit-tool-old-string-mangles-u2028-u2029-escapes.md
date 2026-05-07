---
title: "Edit tool silently rewrites U+2028/U+2029 in old_string, breaking matches against regex escape forms"
date: 2026-05-07
problem_type: tooling_quirk
severity: medium
component: claude-code-edit-tool
tags: [edit-tool, unicode, regex, sanitization, prompt-injection-mitigation]
related_rules:
  - cq-regex-unicode-separators-escape-only
synced_to: []
---

# Edit tool silently rewrites U+2028/U+2029 in `old_string`, breaking matches against regex-escape source

## Problem

While implementing `apps/web-platform/server/agent-runner.ts` for #3437 (cc-leader PDF page-gate symmetry), I needed to replace a block of code that contained the regex character class `/[\x00-\x1f\x7f  ]/g`. The TypeScript source on disk contains the LITERAL ESCAPE BYTES — 12 ASCII chars: `\`, `u`, `2`, `0`, `2`, `8`, `\`, `u`, `2`, `0`, `2`, `9`. The `Read` tool faithfully shows them as `  `.

When I copied that escape form into the `Edit` tool's `old_string` parameter, the edit failed with "String to replace not found in file." The error included a render of my old_string that showed the regex character class as `[\x00-\x1f\x7f  ]` — TWO ASCII SPACES where the escape sequences should have been.

Two failed Edit attempts before pivoting to a Python script via Bash.

## Root Cause

The Edit tool's parameters are JSON-encoded by the harness. When my `old_string` contains the JSON literal `  `, the JSON parser produces the actual U+2028 / U+2029 unicode chars (this is correct JSON behavior). The Claude Code harness's anti-prompt-injection sanitizer THEN rewrites those unicode chars to ASCII spaces (`0x20`) before passing the string to the matcher.

Result:

- **Source file bytes:** `  ` as 12 ASCII chars (escape sequence text).
- **My old_string after JSON-decode + harness sanitize:** two ASCII spaces.
- **Match result:** no match.

There is an existing rule [`cq-regex-unicode-separators-escape-only`](../../../AGENTS.md) that covers the WRITE direction (the harness rewriting literal U+2028/U+2029 chars in `new_string`/`Write` content into ASCII spaces). The MATCH direction has the same root cause but a different visible symptom — silent failure-to-match instead of silent body-corruption.

## Solution

For Edit operations whose `old_string` straddles a regex character class containing `  ` escape sequences:

1. **Try smaller edits that don't include the regex line** — if the lines around the regex are stable and unique, anchor the Edit on those instead.
2. **Use a Python script via the Bash tool** — Python's text manipulation is byte-exact and the script's source bytes (read from disk) preserve the literal escape sequence faithfully:

   ```bash
   cat > /tmp/patch.py << 'EOF'
   import re
   PATH = "server/agent-runner.ts"
   src = open(PATH, "r", encoding="utf-8").read()
   old_block = (
       "...\n"
       "        .replace(/[\\x00-\\x1f\\x7f\\u2028\\u2029]/g, \"\");\n"
       "...\n"
   )
   new_block = "..."
   src = src.replace(old_block, new_block, 1)
   open(PATH, "w", encoding="utf-8").write(src)
   EOF
   python3 /tmp/patch.py
   ```

   Note the `\\u2028\\u2029` doubled-backslash form: in the Python string literal, `\\u` is the two-char escape that produces a literal `\u` in the runtime string; that runtime string contains the same 6-char escape sequence the file contains, so byte-exact match.

3. **Last resort: rewrite the whole file via `Write`** — `Write` is subject to the same sanitization on its `content` parameter, so this only works if you pre-construct the file content via a separate Bash heredoc + `cat >` pattern, NOT via Claude Code tool params.

## Prevention

- Before invoking `Edit` on TypeScript/JavaScript source containing prompt-sanitization regexes (sites that strip `  ` for prompt-injection mitigation), grep the candidate `old_string` for ` ` or ` `. If present, either (a) shrink the edit window to exclude the regex line, or (b) reach for Python via Bash.
- The existing `cq-regex-unicode-separators-escape-only` rule warns about writing literal U+2028/U+2029 to files. Extend the operator's mental model to the symmetric `match` direction — `Edit` cannot match an `\uXXXX`-form region because the parameter's sanitizer collapses the chars before matching.

## Session Errors

This learning was driven by errors encountered while implementing PR #3442 (#3437 leader PDF page-gate symmetry):

1. **Edit tool U+2028/U+2029 escape-sequence mangling on `old_string`.** First two Edit attempts on `agent-runner.ts:822-883` failed with "String to replace not found in file" because my old_string's escape sequences got rewritten to ASCII spaces. Recovery: pivoted to a Python script via the Bash tool. **Prevention:** grep candidate old_string for `  ` before invoking Edit; shrink window or use Python.
2. **Mid-edit introduced calls to undefined helpers (`applyPdfInlineOrFallback`, `applyTextInlineOrFallback`)**. The first wire-in attempt referenced helpers I hadn't written, and left a dead `if (false)` block. Caught by reading the file back and noticing the orphan calls. Recovery: `git checkout HEAD -- agent-runner.ts` and re-apply via Python. **Prevention:** when a planned helper extraction is partial, either complete it before the consumer Edit OR inline the body into the consumer; never reference future helpers from current Edit output.
3. **`mockReadFile` not mocked in `context-injection.test.ts`** — after wiring the new resolver into agent-runner, the existing PDF test threw `Cannot read properties of undefined` because the resolver tried to call `extractPdfText` on an undefined buffer. Recovery: mock the resolver in the existing test file via `vi.mock("../server/leader-document-resolver")`. **Prevention:** when introducing a new server module that's called by an already-tested code path, the test files for the consumer must mock the new module; grep `vi.mock` in the consumer's test file as part of the wire-in.
4. **First `git push` failed** because the draft PR's bootstrap commit was on remote and I rebased locally onto fresh main (PR #3430 merged mid-session). Recovery: `git push --force-with-lease`. **Prevention:** standard force-with-lease for feature branches; not actionable as a rule beyond existing convention.
5. **`code-simplicity-reviewer` DISSENT on the shared-helper scope-out filing.** I claimed `contested-design` but the dissent correctly noted the architecture-strategist had RESOLVED the tradeoff in favor of R4 rather than recommending a design cycle. Recovery: closed as wontfix instead. **Prevention:** when filing `contested-design`, verify the agent's quote includes "design cycle" / "two valid approaches with tradeoffs" wording, NOT a one-sided resolution of the tradeoff.

## Refs

- PR #3442 (#3437 leader PDF page-gate symmetry)
- AGENTS.md `cq-regex-unicode-separators-escape-only`
- PR #3294 (origin of the `  ` strip pattern in soleur-go-runner.ts and agent-runner.ts)
