---
title: Discover diagnostic marker filenames before hashing evidence
date: 2026-10-19
category: workflow-patterns
tags: [codex, diagnostic, evidence, review]
---

The independent source verifier guessed `redirect-diagnostic-once.marker` while
checking the consumed attempt and received a missing-file error. Discover names
from the source constants or `rg --files --hidden --no-ignore` within the exact
private attempt directory. The real `.redirect-diagnostic-consumed` file then
matched its previously reviewed SHA-256. No evidence was modified and no retry
was performed. A filename guess is not evidence of a missing marker.

Preserve spent attempt files unchanged. When a replacement manifest pins a clean
source HEAD, keep subsequent review records untracked until the attempt/evidence
boundary permits committing them and regenerating bindings.

## Addendum — 2026-10-20

The approved classified attempt stopped at `content_length_count`. A first-failed
predicate identifies only that cardinality was not one; it does not establish
absence, duplication, chunking or the validity of later headers. Preserve this
uncertainty. CTO ruled source-only bounded framing compatibility, retaining
duplicate/ambiguous-header rejection, rather than another count-only request.

## Synthetic request race — 2026-10-20

Full offline discovery reproduced a BrokenPipeError in the resource-cleanup
fixture. Isolated tests passed, but the same failure was already recorded on
October 19. Tracked as #10621 before fixing. The HTTP client sent headers and body
separately; the cleanup-only proxy can deny a POST and close before reading its
body. Coalesce the bounded synthetic request and close the response/client in
`finally`; preserve the proxy and the denial assertions. A regression failed on
the old helper and passed after the fixture-only repair.

The first issue-creation attempt was visibly refused: this repository requires
a milestone plus a filing exit. Verified `Post-MVP / Later` and `meta/machinery`,
then created #10621 with both. No additional global rule is needed for this
discoverable requirement.

An approval was accidentally cancelled while the fixture repair was being
applied. The patch had landed but the green test command had not started.
Inspect the actual source and logs before resuming; never assume a cancelled
multi-call tool completed or rolled back all of its operations.
