---
title: "Property-Based Testing Adopted — First Property Found a Real Bug"
type: feature-tweet
publish_date: ""
channels: x, discord
status: draft
---

## X/Twitter Thread

New: property-based testing is now a first-class test class in Soleur.

The first fast-check suite we wrote found a real defect on its first run — a normalizer that wasn't idempotent: `"foo .git"` normalized to `"foo "` (a suffix strip exposed the whitespace it was shielding).

Example tests sample the cases you remember. Properties find the one you don't.

Round-trip, invariant, and idempotency suites + a seeded shell harness, codified in ADR-293.

## Discord

Shipped: property-based testing adoption (fast-check + seeded shell harness).

Worth knowing: the very first idempotency property caught a genuine bug — `normalizeRepoUrl` could emit trailing whitespace after stripping `.git`/`/` suffixes, so `f(f(x)) != f(x)`. Fixed in the same PR; the SQL twin gets its own backfill follow-up.
