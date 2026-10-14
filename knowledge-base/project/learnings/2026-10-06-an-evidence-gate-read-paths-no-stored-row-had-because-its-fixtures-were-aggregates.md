---
title: An evidence gate read JSON paths no stored row had, because its fixtures were aggregates, and my fix pinned only the half of the SQL I was looking at
date: 2026-10-06
category: test-failures
tags: [guards, mutation-testing, fixtures, better-stack, review, irreversible-delete]
related: ["#9372", "#9532", "#6944", "#9628"]
---

# Learning: fixtures that model a query's OUTPUT cannot see a wrong path in the query, and a pin over "everything else" is only as exact as its exemption

## Problem

`scripts/web2-rebirth-emptiness.sh` is the 7-day Better Stack evidence gate whose PASS lets the web-2 rebirth workflow delete a
plaintext volume. Its first live plan-only dispatch went RED `used_bytes_absent_or_host_dark`: the SQL filtered on `host_name`,
`source_kind`, `metric.name` and `metric.value`, none of which exists in a stored row (the stored row is the bare Vector metric:
`tags.host`, `namespace`, `tags.mountpoint`, `name`, `gauge.value`). The suite had been green the whole time: 29 verdict fixtures
fed hand-written AGGREGATE rows to the jq judge, so nothing could notice a wrong RAW path. The gate failed closed, which is why
this cost a re-dispatch and not a volume.

## Solution

Query side: read the real paths; add a one-device `HAVING` that also requires a non-empty device and `AND dt <= now()`.
Verified read-only against live Better Stack (PASS, 168 to 169 h, spread 471,040).

Test side, in the order review forced it:

1. Real-shape rows plus a strict-grammar extractor that resolves the SQL's own JSON paths against them.
2. Pin everything OUTSIDE the WHERE conjuncts by exact text (aggregates, both FROM arms, GROUP BY, HAVING), because the extractor
   saw only the conjuncts. Six review seats reported the same gap; the first draft of the pin had a hole of its own, below.
3. Classify a mutant that BREAKS the battery as BROKE, not as a kill, and pin the classifier with known-crash controls.
4. Record what `main` actually sends to the query helper and require EXACT equality with the builder's output on both runs.

## Key Insight

- **A fixture shaped like the query's output cannot see a wrong path inside the query; the fixture must have the shape of the
  STORED row.** The defect and the blind spot were the same thing. Any gate that reads from a store needs one row, in the store's
  own shape, that the gate's own paths are resolved against.
- **"Pin everything except X" is exact only if X is exempted by position, not by shape.** My pin removed every line that LOOKED
  like a conjunct (a prefix match) from the whole SQL, so a prefix-shaped line after `FORMAT`, between `GROUP BY` and `HAVING` or
  before `WHERE` was invisible to both the grammar and the pin. Remove only the lines between the two anchors.
- **A mutation scorer must not credit a crash.** A mutant that killed the SQL builder reddened 15 of 68 assertions and read as
  "killed"; a syntax error reddened 55. Count by what broke: an explicit CRASH line, a RAN count that differs from the baseline,
  or a mass-red bound, and pin the BROKE branch with rows that must classify BROKE.
- **Prose I wrote in the same PR was wrong in the places a second reader checks.** "A device other than the one on record" (the SQL
  records no device), "about 60 times" (it is 67), "measured empty baseline" (the volume's own reading, not an independent empty
  reference), "no weaker than host_name" (a Terraform-rendered constant versus an OS hostname) and "reproduces the control" (it
  prints half of it) each fell to one command. Name the command that would falsify every causal sentence the diff adds.

## Session Errors

1. **Shell started on a stale detached checkout lacking the files the brief named** (`scripts/web2-rebirth.sh` not found).
   Recovery: a detached worktree at `origin/main`. **Prevention:** one-off; check `git merge-base --is-ancestor` of the brief's SHA
   against `HEAD` before reading files.
2. **The shipped gate had never read real data** (the incident itself): fixtures were aggregates. **Prevention:** a real-shape row
   resolved against the query's own paths (now in the suite).
3. **My exact-text pin exempted lines by prefix over the whole SQL.** Found by the security and test-design fix-round seats.
   **Prevention:** exempt by position (awk between the two anchors) and mutate a prefix-shaped line into each region.
4. **The first mutation classifier credited a crash as a kill.** **Prevention:** `mut_verdict` with CRASH, RAN and mass-red
   signals plus known-crash controls.
5. **Doc claims I wrote were wrong in five places** (listed above). **Prevention:** falsify each added causal sentence; sweep the
   corrected claim repo-wide by subject, not by phrasing.
6. **A scripted multi-edit aborted midway** (`ValueError: substring not found` on a phrase the plan wrapped across two lines) and
   left the first edit applied. Recovery: re-ran only the unapplied edits. **Prevention:** assert each anchor, then `git status`
   the touched files, as the work skill already prescribes.
7. **Review panels run concurrently with my own edits would have corrupted evidence;** I held the tree until all seats returned.
   No loss. **Prevention:** none needed beyond the existing report-only rule.
