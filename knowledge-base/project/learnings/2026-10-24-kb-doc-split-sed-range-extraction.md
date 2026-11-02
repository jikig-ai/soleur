---
title: KB doc split via line-range extraction + unescaped-pipe table split
date: 2026-10-24
category: implementation-patterns
---

# Splitting a large KB doc into index + shards

For `competitive-intelligence.md` (569 lines): extract verbatim sections by `sed -n 'a,bp'` line ranges (verify boundaries with `grep -nE '^#{1,3} '` first); split matrix rows on `(?<!\\)\|` (cells contain `\|` escapes); unescape `\|`→`|` when moving cell text into prose shards; depth-fix `](../project/` links by one `../` per level moved; carry a `Context-Reviewed:` trailer when `last_reviewed`-mentioning lines move. Dated records (intake blocks, audits, logs) shard; matrices/takeaways/recommendations stay in the index at its unchanged path.
