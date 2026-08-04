# fix(pipeline): the artifact mirror rejected every push for four hours

Synthesized fixture (see `cq-test-fixtures-synthesized-only`). Rationale for what
this pins, and the list of words it must never contain, live in the test case —
NOT here. Prose in this file is haystack: an earlier draft explained its own
purpose and thereby matched the very vocabulary it was written to exclude.

brand_survival_threshold: aggregate pattern

## Summary

Every scheduled build from 09:00 UTC was rejected at the artifact mirror. The
queue drained but nothing was promoted, so production sat four releases behind
for the rest of the working day. The three fixes merged that morning were not
reachable by anyone using the deployed app until the mirror recovered.

## What we changed

The promotion step now reports the mirror verdict it measured, instead of naming
a credential the job never graded.
