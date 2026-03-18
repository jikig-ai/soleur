# Learning: Ralph loop stuck detection hardening

## Problem

A ralph loop with the prompt "finish all slash commands" became stuck in an infinite cycle. The assistant's responses were substantive-looking ("All slash commands are finished. Nothing pending.") but unproductive. The 20-char stuck detection threshold was too low to catch these responses, and the exact-hash repetition detector missed them because each response was slightly different.

The loop ran for ~45 minutes before manual intervention (deleting the state file).

## Solution

Three changes to `plugins/soleur/hooks/stop-hook.sh`:

1. **Raised stuck detection threshold from 20 to 150 chars.** Formulaic "I'm done" responses typically fall under 150 stripped chars. Real productive work (describing changes, listing files, explaining decisions) consistently exceeds 150 chars.

2. **Added Jaccard word-similarity detection.** Tokenize each response into a unique word set, compute Jaccard similarity (`|intersection| / |union|`) against the previous response. Three consecutive responses sharing >=80% words trigger termination. Uses `comm -12` for intersection and arithmetic (`|A| + |B| - |intersection|`) for union.

3. **Simplified union calculation.** Initial implementation used `comm` bare output piped through `sort -u` — a non-obvious trick. Replaced with the standard set-theory formula `|A union B| = |A| + |B| - |A intersect B|`, which is self-documenting.

## Key Insight

When building loop detection for LLM agents, exact-match detection (hashing) catches only the simplest failure mode. LLMs produce natural variation in phrasing even when functionally stuck. Word-set similarity (Jaccard) catches the real failure mode: semantically identical responses with surface-level variation. The 150-char threshold complements this by catching formulaic acknowledgments that are too short to be real work.

## Session Errors

- Test boundary string counted wrong (140 chars instead of 150) — always verify exact char counts with `echo -n "..." | wc -c` before committing boundary tests
- `replace_all` in Edit tool was more aggressive than expected — matched all instances of a substring across the file rather than the intended subset. Result was correct but unintentional.

## Tags
category: runtime-errors
module: ralph-loop
