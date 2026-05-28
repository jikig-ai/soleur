---
title: "Inserting U+2028/U+2029 into source: construct escapes from char codes, never type them"
date: 2026-05-28
category: best-practices
tags: [editing-tools, unicode, log-injection, regex, cq-regex-unicode-separators-escape-only]
module: tooling
related:
  - cq-regex-unicode-separators-escape-only
pr: 4568
---

# Learning: Unicode line/paragraph separators need char-code-constructed escapes

## Problem

A security review (`security-sentinel`) required replacing a bare `/[\r\n]/g` log-injection
strip with the codebase-canonical class `/[\x00-\x1f\x7f  ]/g` in
`apps/web-platform/server/github/probe-octokit.ts`. The intent was for the SOURCE FILE to
literally contain the 12 ASCII characters `  ` (backslash-u-2028…), which JS then
interprets as U+2028 / U+2029.

Every attempt that involved *typing* the separators or the escape failed:

1. **Edit tool, literal escape:** writing `  ` in the `new_string` landed as raw
   UTF-8 bytes `e2 80 a8 e2 80 a9` inside the regex (`cat -A` showed `M-bM-^@M-(M-bM-^@M-)`).
2. **Python heredoc, raw string:** `r'...  ...'` inside a `python3 - <<'PY'` heredoc
   ALSO landed as raw bytes — the literal-separator transcoding happens at the text-generation
   layer, before the bytes reach either the Edit tool or the heredoc.

A regex char class containing raw U+2028/U+2029 (or, worse, the mangled `[\x00-\x1f...]` that
became literal control bytes) is both a correctness bug and a re-introduction of the exact
log-injection vector the strip was meant to close — `cq-regex-unicode-separators-escape-only`
warns about precisely this.

## Solution

Construct the escape TEXT from character codes in a script, so no literal separator and no
ambiguous backslash-escape is ever typed:

```python
python3 - <<'PY'
bs  = chr(92)                      # a single backslash
sep = bs+'u2028'+bs+'u2029'       # the 12 ASCII chars:    
line = '    .replace(/[' + bs+'x00-' + bs+'x1f' + bs+'x7f' + sep + ']/g, " ")'
# write `line` into the target file by stable anchor match
PY
```

Verify the bytes are pure ASCII escapes afterward:

```bash
grep -nE 'replace\(/\[' <file> | cat -A     # must show \x00-\x1f\x7f  , no M-b…
grep -nP '\xe2\x80[\xa8\xa9]' <file> && echo "RAW BYTES (bad)" || echo "clean"
```

## Key Insight

For U+2028/U+2029 (and other zero-width / separator code points), the safe path is
**char-code construction in a script** (`chr(92)+'u2028'`), checked with `cat -A` + a raw-byte
grep. Do not rely on typing the `\uXXXX` escape into the Edit tool or a heredoc — the literal
separator can be emitted by the text layer and silently transcoded before it reaches the file.
This is the operational companion to `cq-regex-unicode-separators-escape-only`: the rule says
"use escapes, not literals"; this learning says "you cannot reliably TYPE the escape — build it."

## Session Errors

1. **Bare-repo direct Read of `github-app.ts`** — the bare root has no working tree, so
   `Read` failed. Recovery: `git show main:<path>`. Prevention: already enforced by
   `hr-when-in-a-worktree-never-read-from-bare`; no new action.
2. **`/soleur:one-shot` args carried hash-prefixed contextual citations** (`#4498`, `#4543`,
   `#4557`, `#4565`); `#4543` is a CLOSED issue that would trip the closed-issue collision
   gate even though it was only a citation. Recovery: re-invoked with non-hash forms
   ("PR 4565", "closed bug 4543"). Prevention: already documented in
   `2026-05-25-one-shot-closed-issue-gate-fires-on-contextual-refs.md` — scrub `#N` from
   prose args; only OPEN work-target refs use `#N`.
3. **Edit tool + heredoc transcoded `  ` to raw bytes (3 attempts).** Recovery:
   char-code construction (`chr(92)+'u2028'`). Prevention: this learning — build separator
   escapes from char codes; verify with `cat -A` + raw-byte grep.
4. **Bash CWD drift** to worktree root after a heredoc broke `./node_modules/.bin/tsc`
   (relative path → "No such file"). Recovery: prefix the command with an absolute
   `cd <worktree>/apps/web-platform`. Prevention: the Bash tool does not reliably persist CWD
   across calls — always absolute-`cd` in test/typecheck commands run from a worktree.
