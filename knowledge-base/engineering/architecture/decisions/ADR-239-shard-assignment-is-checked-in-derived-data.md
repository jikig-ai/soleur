---
title: "ADR-239: Shard assignment is checked-in derived data — an offline label→leg manifest, a runtime lookup, a deterministic fallback"
status: Accepted
date: 2026-09-23
supersedes: []
amends:
  - ADR-238
tags: [ci, test-sharding, fail-closed, generated-artifact, adr-235]
---

# ADR-239: Shard assignment is checked-in derived data

## Status

Accepted — 2026-09-23. Delivers the duration-aware arm of #8006 that
ADR-238 deferred; amends ADR-238's rejected-alternative entry for LPT.

## Context

ADR-238's carve-out + K=5 cut the worst `test-scripts*` leg from 31–39 min
to 13m50s (run 35840517639). The remainder is positional luck: leg 5/5
carried 797s of suite time against 237s on the best leg because three
network-bound suites happened to land adjacent. Positional round-robin
cannot separate them — membership is registration order, not cost, and the
composition re-drifts on every suite addition.

ADR-238 rejected duration-aware partitioning for two reasons:

1. The shard chokepoint cannot compute it — `_shard_selects` is invoked once
   per streaming registration and never sees the set.
2. A static weights table is a second, driftable copy of the suite registry.

Both objections are about WHERE assignment is computed, not WHETHER it can
be. #8006's own analysis sketched the resolution: move the computation
offline and let the runtime do a lookup.

Meanwhile ADR-235 supplies the artifact rule: a generated file with a
product reader is a product — committed, regenerated on conflict, never
hand-merged. Its cautionary data (rule-metrics.json conflicted on ~every
main landing) constrains the shape: minimal, stable diffs only.

## Decision

1. **Assignment data is generated offline and committed.**
   `scripts/regenerate-shard-manifest.py` merges the `suite-timings-scripts-*`
   artifacts of a chosen green CI run (light legs only — the heavy group's
   three suites are already optimally spread), drops boundary/skip/failed
   rows, filters to the runner's own enumerated registered set, and emits
   `scripts/suite-shard-legs.tsv` via **sticky-LPT**: least-loaded leg wins,
   but a label keeps its incumbent leg when that leg is within 5% of the
   minimum — so each regeneration diffs only what rebalancing requires.

2. **The runner does a lookup, never a computation.** `_shard_selects`
   gains the registration label and runs two modes: manifest-active (table
   lookup; untabled labels fall back to a deterministic `cksum` hash) and
   positional (the original `ordinal % N`, verbatim). The manifest engages
   only when `SCRIPTS_SHARD` is set, `TEST_GROUP=scripts`, and the file's
   declared `n` equals the spec's N; every other shape degrades to
   positional. Malformed, duplicated, or out-of-range tables exit 2 at
   parse; absent/stale/n-mismatched tables degrade with a stderr notice —
   coverage is a property of the registration walk, never of the table.

3. **Insertions are stable by construction.** A new suite is not in the
   table, so it hash-falls-back to a leg no other suite moved off; the
   committed diff shows exactly which assignments a refresh moved and why.

4. **The guard stays mechanism-agnostic; a lint owns table hygiene.**
   `scripts-shard-totality.test.sh` still unions independently-enumerated
   legs against the independently-derived reference — it does not know or
   care how legs were chosen. The new `scripts-shard-manifest.test.sh`
   asserts the table's contract: `n` equals ci.yml's declared leg count,
   legs in range, no duplicates, labels ⊆ registered (strict — a phantom is
   a stale-table defect the runtime deliberately tolerates), every leg
   pinned. Six new mutation rows score the fallback contract: absent label
   covered, phantom inert, empty table total, untabled labels on distinct
   legs, dropped label argument refused, skip/run label parity.

5. **Refresh is manual and named.** The repo convention for generated
   artifacts is an explicit `--write` command plus drift *detection*, not
   scheduled auto-commit (stale-bot-PR learning). Regenerate on leg skew or
   when the ⊆ lint/N-pin reds; a merge conflict on the TSV resolves by
   regeneration, not hand-merge.

## Consequences

- Predicted light-leg load: ~449s each vs measured 237–797s positional —
  worst `test-scripts` leg ~9 min including setup (vs 13m50s).
- `SOLEUR_SHARD_MANIFEST` is a test/debug seam (`off` disables; set-but-
  empty, non-absolute, or missing paths all exit 2); it is consumed and
  unset with `SCRIPTS_SHARD` so fixture paths cannot reach nested runners.
- Manifest-mode assignment is collation-INDEPENDENT — the LC_COLLATE caveat
  that made positional membership non-portable no longer applies to tabled
  or hashed labels.
- The `test-scripts-heavy` job is unaffected (n-mismatch → positional).
- A K bump on `test-scripts` without a regen degrades quietly at runtime
  but reds the lint's n-pin — fail-safe at runtime, loud in CI.

## Rejected alternatives

- **Runtime LPT in `_shard_selects`.** Still rejected (ADR-238): the
  chokepoint sees one registration at a time and cannot know the set, and
  an order-dependent global re-optimization would move arbitrary labels on
  every insertion. The manifest is the offline form of the same algorithm,
  minus both defects.
- **Hash-of-path for everything (no table).** ~24 registrations name no
  bash path at all, and a pure hash scatters adjacent slow suites onto the
  same leg with no recovery path.
- **Auto-committed refresh workflow.** Rejected per the scheduled-PR
  learnings: bot diffs go stale and encode drift; detection-and-file is the
  house pattern.
- **Per-group manifests (heavy included).** Unneeded today: 3 suites / 3
  legs is already optimal. The single-`n` header leaves room if that
  changes.
