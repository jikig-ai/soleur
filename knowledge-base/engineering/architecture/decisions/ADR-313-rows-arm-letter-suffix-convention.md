---
title: The --rows arm-split convention — boundary in the flag, letter in the label
status: adopting
date: 2026-11-01
supersedes: none
issue: 11647
related: [11562, 11556]
related_adrs: [ADR-240, ADR-276]
tags: [test-runner, ci, sharding]
---

# ADR-313: The `--rows` arm-split convention — the boundary lives in the flag argument, never the label

## Context

When one suite registration is too long for a shard leg (#11562), the battery
is split into `run_suite`-registered arms or a `ci.yml` `rows:` matrix. The
convention was load-bearing in two places with no ADR:
`regenerate-shard-manifest.py`'s `separate_arm_groups` groups same-stem
`-<letter>` siblings and pins them to distinct legs (LPT co-location would
emit a manifest the totality guard refuses), and
`plugins/soleur/test/scripts-shard-totality.test.sh` asserts the label
shape, the contiguous tiling of 1..DECLARED_TOTAL, the distinct-legs pins,
and both literal censuses.

## Decision

- An arm label carries the `<stem>-<letter>` suffix (`-a`, `-b`, `-c`, `-d`).
  The stem stays the battery's suite name.
- The split boundary lives ONLY in the `--rows A-B` flag argument of each
  registration (`run_suite "<stem>-a" bash <file> --rows A-B`) or in a
  `ci.yml` `rows:` matrix entry consumed as `--rows "${{ matrix.rows }}"`.
  A label never encodes its range.
- The registered ranges must tile `1..DECLARED_TOTAL` contiguously — no
  gaps, no overlaps.
- The battery declares `DECLARED_TOTAL` in-file, sources
  `scripts/lib/rows-range.sh`, calls `rows_parse_args "$@"`, gates every
  row/block through `in_range` in file order, and reconciles at EOF through
  `rows_gate_floor` plus its battery-specific extras.
- A `DECLARED_TOTAL` bump and the registered-range re-split land in the
  SAME commit — a range overshooting the declared total is refused by
  `rows_parse_args`' bounds check while a gap executes nowhere.
- Census constraints on the lib and every battery: no line-start
  `DECLARED_TOTAL=` spelling outside the declaring battery files
  (Direction-2 census), and no literal `--rows <digits>-<digits>` outside
  registrations/comments (Direction-1 literal census).

## Consequences

- `separate_arm_groups` performs a distinct-legs post-pass; the totality
  guard verifies committed and realized legs are distinct per arm set.
- Two split styles coexist: `run_suite … --rows` arms (replay, lint-orphan,
  test-all-affected) and a `ci.yml` `rows:` matrix (totality-mutations).
  Both feed the same `in_range`/`rows_gate_floor` contract.
- The arm-split checklist lives in
  `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`.
- Seeding an arm price by hand stamps `src=estimate` in the durations
  table — never `measured` (#11647 S1): an estimate supplies weight but
  stays out of the floor median and the measured-only drift accounting,
  and upgrades to `measured` only when a real timings pass carries it.
