---
title: "ADR-240: Shard assignment is checked-in derived data — an offline label→leg manifest, a runtime lookup, a deterministic fallback"
status: Accepted
date: 2026-09-23
supersedes: []
amends:
  - ADR-238
tags: [ci, test-sharding, fail-closed, generated-artifact, adr-235]
---

# ADR-240: Shard assignment is checked-in derived data

## Status

Accepted — 2026-09-23. Delivers the duration-aware arm of #8006 that
ADR-238 deferred; amends ADR-238's rejected-alternative entry for LPT.

**Amended 2026-09-23 (phase 2):** per-group manifests are now ADOPTED —
`scripts/suite-shard-legs-heavy.tsv` covers `TEST_GROUP=scripts-heavy` under
the same contract, and the "Per-group manifests" rejected-alternative entry
below records why the earlier deferral stopped holding.

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

1. **Assignment data is generated offline and committed — per group.**
   `scripts/regenerate-shard-manifest.py` merges the `suite-timings-scripts-*`
   artifacts of a chosen green CI run, drops boundary/skip/failed
   rows, filters to the runner's own enumerated registered set, and emits
   `scripts/suite-shard-legs.tsv` via **sticky-LPT**: least-loaded leg wins,
   but a label keeps its incumbent leg when that leg is within 5% of the
   minimum — so each regeneration diffs only what rebalancing requires.
   `--group heavy` repeats the same mechanics over the
   `suite-timings-scripts-heavy-*` artifacts and the `scripts-heavy`
   registered set, writing `scripts/suite-shard-legs-heavy.tsv` with the
   heavy job's own `n` (3). Two files, one parser, one contract — a heavy
   regen never rewrites the light table's insertion-stable surface, and a
   wrong-group label can never land in the wrong file (each run filters to
   its own enumerate).

2. **The runner does a lookup, never a computation.** `_shard_selects`
   gains the registration label and runs two modes: manifest-active (table
   lookup; untabled labels fall back to a deterministic `cksum` hash) and
   positional (the original `ordinal % N`, verbatim). The manifest engages
   only when `SCRIPTS_SHARD` is set, `TEST_GROUP` is `scripts` or
   `scripts-heavy`, and THAT group's file declares `n` equal to the spec's
   N; every other shape degrades to positional. Each group binds its own
   override (`SOLEUR_SHARD_MANIFEST` / `SOLEUR_SHARD_MANIFEST_HEAVY`) with
   identical fail-closed semantics. Malformed, duplicated, or out-of-range
   tables exit 2 at parse; absent/stale/n-mismatched tables degrade with a
   stderr notice — coverage is a property of the registration walk, never
   of the table.

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
- `SOLEUR_SHARD_MANIFEST` / `SOLEUR_SHARD_MANIFEST_HEAVY` are test/debug
  seams (`off` disables; set-but-empty, non-absolute, or missing paths all
  exit 2); each is consumed and unset with `SCRIPTS_SHARD` so fixture paths
  cannot reach nested runners.
- Manifest-mode assignment is collation-INDEPENDENT — the LC_COLLATE caveat
  that made positional membership non-portable no longer applies to tabled
  or hashed labels.
- The `test-scripts-heavy` job now runs duration-aware too (phase-2
  amendment): its own `n=3` table engages only when the manifest's n
  equals `_SHARD_N`; without the file it degrades to positional exactly
  like the light group.
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
- ~~**Per-group manifests (heavy included).**~~ **ADOPTED in the 2026-09-23
  amendment.** The original rejection rested on "3 suites / 3 legs is
  already optimal", which confused the PARTITION's shape with the
  ASSIGNMENT's provenance: positional was optimal only by ordinal luck,
  the heavy leg measured 8m32s against a 6m42s sibling, and the
  registration-order dependence re-rolls the split on the next heavy
  suite. Separate files (not an n-keyed section in one file) preserve the
  light table's insertion stability — a heavy regen diffs zero light rows —
  and keep one uniform parse contract per file rather than teaching the
  loader a second grammar.
