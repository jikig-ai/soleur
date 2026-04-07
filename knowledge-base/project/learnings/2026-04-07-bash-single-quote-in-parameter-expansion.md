---
title: "Single quotes in bash parameter expansions inside bash -c strings"
category: build-errors
module: scripts
tags: [bash, quoting, shell, parameter-expansion]
date: 2026-04-07
---

# Learning: Single quotes in bash parameter expansions inside bash -c strings

## Problem

When fixing review findings in `scripts/generate-kb-index.sh`, two bash quoting issues surfaced:

1. **Bracket escaping in parameter expansion**: `${title//[/\\[}` causes a syntax error because `[` is a glob character in bash parameter expansion patterns. Bash interprets it as opening a character class rather than a literal bracket.

2. **Single quotes inside single-quoted `bash -c` strings**: You cannot use literal single quotes inside a single-quoted `bash -c '...'` string. The common `'"'"'` concatenation trick works for literal text but **fails inside `${var#pattern}` and `${var//pattern/replacement}` parameter expansions**. The inner bash parser treats the injected `'` from the concatenation as opening a new quoted string within the expansion context, producing broken syntax rather than matching a literal quote character.

## Solution

1. **Escape glob characters in parameter expansion patterns** -- prefix `[` with a backslash:

   ```bash
   # Broken -- [ starts a character class
   ${title//[/\\[}

   # Fixed -- \[ is a literal bracket
   ${title//\[/\\[}
   ```

2. **Use a variable for the quote character** instead of concatenation tricks:

   ```bash
   # Broken -- '"'"' inside parameter expansion confuses the parser
   bash -c '... ${title#'"'"'} ...'

   # Fixed -- store the character in a variable via printf
   bash -c 'sq=$(printf "\x27"); title=${title#$sq}; title=${title%$sq}; ...'
   ```

   `printf "\x27"` produces a literal single-quote character and assigns it to `sq`. The variable `$sq` can then be used safely in parameter expansion patterns without any quoting ambiguity.

## Key Insight

When embedding parameter expansions that reference quote characters inside single-quoted `bash -c` strings, avoid concatenation tricks (`'"'"'`). Instead, use a variable holding the character via `printf "\x27"`. The `'"'"'` trick works for literal text because the shell pastes the segments together before evaluation, but inside `${var//pattern/replacement}` and `${var#pattern}` the inner bash's parser treats the injected quote as a syntactic element within the expansion context -- breaking the parse rather than matching a literal character.

More broadly: glob characters (`[`, `]`, `*`, `?`) in parameter expansion patterns must always be escaped, and quote characters in parameter expansion patterns within `bash -c` strings require the variable approach.

## Session Errors

1. **Script syntax error from unescaped `[` in parameter expansion pattern** -- `${title//[/\\[}` failed because `[` opens a character class in bash globbing. **Prevention:** Always escape glob characters (`[`, `]`, `*`, `?`) in bash parameter expansion patterns.

2. **Single-quote quoting failure with `'"'"'` inside parameter expansion** -- The concatenation trick produced valid-looking shell text that broke at parse time because the inner `bash -c` shell treated the injected quote as syntax within the `${var#pattern}` expansion. **Prevention:** Use `printf "\x27"` variable approach for quote characters needed in parameter expansions within `bash -c` strings.

3. **Worktree disappeared between review and fix phases** -- The worktree was cleaned up by `worktree-manager.sh cleanup-merged` between the review agent completing and the fix phase starting. **Prevention:** Check worktree existence before attempting to work in it; worktree cleanup runs at session start per AGENTS.md.
