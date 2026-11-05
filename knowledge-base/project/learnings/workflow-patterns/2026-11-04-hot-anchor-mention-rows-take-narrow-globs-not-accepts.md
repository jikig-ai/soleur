---
title: "Drain mention pairs on hot anchors take narrow globs, not accept rows"
date: 2026-11-04
tags: [affected-index, drain, review-catch]
---

# Hot-anchor mention pairs take narrow globs, not accept rows

During the S4 affected-index PR5d slice (#10861), 10 accept rows were written for mention pairs whose boundary lines anchor on `plugins/soleur/test/preflight-discoverability-test.test.ts` — a file churning **111 commits/90d**. The slice's own `sweep-decisions.tsv` recorded the 111 count and shipped the rows anyway; the data-integrity review seat flagged it as P1.

**Rule (already in tasks.md 1.2, easy to miss at write time):** an accept row anchored on a file with >8 commits/90d is refused — the line drifts, the row goes stale, the pair re-lives as `new-pair`/`stale` on an unrelated future PR. The vehicle for such pairs is a narrow `dir`-class glob `glob:<dir>/*<tail>` in the suite's `AFFECTED_*_PATHS` array ("declared-not-scanned input" — PR5c convention, 123 installed), with comment `mention pair; every boundary line anchored on >8-commits/90d file — accept rows refused`.

**Check:** when writing an accept row, count `git log --since=90.days --oneline -- <anchor-file>` first. If >8, glob instead. The 4 pairs moved accept-row → glob and the audit stayed `gap_refs=0`.
