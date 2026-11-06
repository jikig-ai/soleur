---
title: Bounding gh probes with --paginate/--limit breaks recorded-argv oracles in sibling suites
date: 2026-11-01
category: workflow-patterns
tags: [test-suites, gh-mock, enumeration-bound, PR-11782]
---

# Learning: bounds on gh probes must update every argv oracle that recorded the old call

## Problem

#8593's enumeration gate required `-L`/`--limit`/`--paginate` on unbounded
`gh api`/`gh issue list` corpus probes. Landing the bound on the *script* is
the easy half; every test suite whose `gh` mock, recorded-argv oracle, or
query-shape assertion pattern-matched the old argv went red — in suites the
edit never touched:

- `watch-lint-ratchet-reeval-10515.test.sh`: the mock's `[[ "$#" -eq 1 ]]` API
  arm denied `gh api --paginate <endpoint>`; `searches_made` (grep
  `^api search/issues`), `decode_q` (strip `api search/issues?q=`), `S7`'s
  `base_queries`, `S8e`, and `argv_ok` all keyed on the old prefix.
- `roadmap-reconcile.test.sh`: the fake `gh` case matched
  `api repos/...milestones...` positionally; `--paginate` shifted every arg.
- `run-report-exit-first-contact-8076.test.sh`: the stub's endpoint-token
  parse needed a `--paginate` shift.

The fix pattern is uniform: shift a leading `--paginate` before the argv-shape
check; carry `(--paginate )?` in call-record greps; strip `api --paginate `
before `api ` in decoders; accept `api --paginate <path>` as a GET in write/verb
oracles.

## Key Insight

A flag-level contract change is a CLASS change: the corpus sites are the
visible consumers, but mocks and argv oracles are the invisible second consumer
set. When a PR lands a bound on N sites, grep the test tree for the *old* argv
prefix before declaring green — the failures surface in whichever CI shard
holds each mock, never under the edited file's name.

Two adjacent traps from the same PR:

- `lint-skill-body-budget` (inside required `rule-body-lint`) byte-counts
  lifecycle SKILL.md bodies; a `--limit 100` example pushed `postmerge` 9
  bytes over. Use `-s`/`-L` shorthands at the byte edge.
- A new floor-bearing test suite is THREE write sites, not two:
  `suite-durations.tsv` (weight), `suite-shard-legs.tsv` (placement —
  regenerate only places *timed* suites, so a new suite needs a manual leg
  row), and `guard-vacuity-floor.test.sh`'s `PROMOTED_FILES` alternation when
  it lands under a deferred directory.

## Tags

symptoms: mock deny / argv oracle violations / missing-query decode after
landing gh flag bounds; `infra-suite-registration` label-set mismatch;
`pipe-into-early-exit-grep` when the bound is written as `| grep -q`.
