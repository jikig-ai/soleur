# ADR-173: KB index exclusion supersedes per-feature archival

- **Status:** Adopting
- **Date:** 2026-08-10
- **Issue:** #7399 (Tier 1). Tier 2: #7400. Related: #7401 (INDEX.md freshness gate), #7402 (orphan suites).
- **Relationship to ADR-084:** **constrained by** it. ADR-084 §5 requires `knowledge-base/project/specs/<branch>/decision-challenges.md` to be readable at its live path until `ship` Phase 6 renders Model Dissents. That requirement is what makes `git mv` archival unusable as an index-hygiene mechanism, and index-exclusion is what satisfies both.

## Context

`knowledge-base/INDEX.md` is the discovery surface agents grep for prior art:
`learnings-researcher.md:15` Step 0 greps it across all domains, and any agent may
grep it raw. (`kb-search/SKILL.md:146` Tier 1 and `learning-retrieval-bench.sh` also
read it, but both restrict to `knowledge-base/project/learnings/`, so neither ever saw
the rows this ADR removes.)

Regenerated from the tree on 2026-08-10 it enumerated **7,481 rows**, of which
**1,282 were per-feature working state** inside `knowledge-base/project/specs/*/` —
`session-state.md` plus roughly ninety other one-off working filenames, about
seventy-six of which occur exactly once.

The pre-existing mechanism for removing a row was **per-feature archival**:
`archive-kb.sh` `git mv`s a feature's spec dir, plan, and brainstorm into sibling
`archive/` directories, which `generate-kb-index.sh` excludes. Archival is the only
thing that removed an INDEX row.

Three findings made that mechanism the wrong one:

1. **It had no recorded purpose.** No ADR governed it and no rule in `AGENTS.rules.md`
   mentioned it. The only rationale in the repository was `archive-kb.sh`'s header
   comment, which describes mechanism, not purpose. Its benefit had to be re-derived
   from scratch.

2. **It only ever worked on the happy path.** `derive_slug()` strips a `fix-` prefix
   and `discover_artifacts()` then probes `specs/feat-${slug}`, so a `fix-*` spec dir
   is structurally unreachable — 27 live, zero archived. Plans are found by a
   `*<slug>*` glob, so a plan named from its title rather than its branch is missed;
   `2026-08-09-my-suites-were-hermetic…` records archival taking a spec dir, leaving
   its plan, and printing `Archived 1 artifact(s)`. Half-archived reads as complete.
   It did run — 266 archived `feat-*` spec dirs, 283 plans, 123 brainstorms — which is
   why "it never worked" is the wrong diagnosis and "it works on one shape" is the
   right one.

3. **The move collides with ADR-084 §5.** A spec directory is live working state until
   `ship` Phase 6 has read `decision-challenges.md` from it. `ship/SKILL.md:2361`
   already documents the consequence: *"compound is the last point at which archival
   can happen. If compound's consolidation is skipped or deferred — a legitimate
   choice when Phase 6 still needs `specs/<branch>/decision-challenges.md` at its live
   path — then archival does not happen at all."* The repository's own documentation
   describes a sanctioned path on which archival silently never runs.

A gate to enforce archival was built and reverted for exactly this reason: the
carve-out was per-file, so a normal spec dir failed the gate, the agent archived the
whole directory, and Phase 6 could no longer find the file — dropping Model Dissents
the operator has not seen. Any gate built on the move inherits that collision.

## Decision

**Remove rows at index-generation time rather than by moving files.**

Inside `knowledge-base/project/specs/<feature>/`, `generate-kb-index.sh` indexes
`spec.md` and `tasks.md` — the two files that name a feature — and nothing else.
Implemented as one group in the `find` that already carries the `archive/` exclusion:

```bash
\( -not -path '*/project/specs/*' -o -name 'spec.md' -o -name 'tasks.md' \)
```

**An allowlist, not a denylist.** Filename invention is the norm in these
directories, so any enumerated deny set is stale the next time someone writes a
`phase0-evidence.md`. Three named classes would have left ~113 long-tail rows.

**`tasks.md` is kept because 79% of live spec dirs (1,209 of 1,530) have no
`spec.md`.** Indexing only `spec.md` would have removed the sole INDEX row for those
features, whose `tasks.md` titles are real labels carrying issue numbers. 264 dirs
still lose their row under this decision; 250 of them contain nothing but
`session-state.md`.

**The patterns are single-quoted and not interpolated with `$KB_DIR`.** Interpolation
makes the predicate depend on the textual form of the variable: a trailing slash
yields a `//` no `find`-emitted path contains, so the exclusion evaluates true for
everything and the feature no-ops with exit 0 and a green suite. `KB_DIR` is also
normalized once (`${KB_DIR%/}`), which fixes a pre-existing bug in the `rel=` strip
that emitted absolute paths into every row on the same input.

Measured on the live corpus, generating twice from one copy: **7,481 → 6,199 rows**,
plan rows unchanged at 1,532, surviving spec-dir basenames exactly `spec.md` (321) and
`tasks.md` (1,242).

## Status: adopting, not accepted

This decision is only fully true after Tier 2 (#7400), which excludes merged features'
`spec.md` and plans and is what makes `archive-kb.sh`'s spec/plan discovery paths
retirable. Until then `archive-kb.sh` is unchanged — neither enforced nor removed,
which is also its state today. `archive-kb/SKILL.md` carries a pointer here so the
supersession is discoverable from the tool it supersedes.

Tier 2's own open question is the merged signal: only 176 of 320 live `spec.md` carry
a `status:` key, so frontmatter alone is unreliable, and a `gh`/`ls-remote` check makes
index generation network-dependent.

## Consequences

- The discovery surface loses 1,282 rows of branch-lifetime scratch. `learnings-researcher` Step 0 is the consumer that benefits; `kb-search` Tier 1 and the retrieval bench are learnings-anchored and unaffected either way.
- Nothing moves on disk, so `git log --follow` is unaffected and ADR-084 §5's read path is untouched — `ship/SKILL.md:1458` reads that file by filesystem existence, never via the index.
- A contributor who puts durable content flat in a spec directory will not see it indexed. The remedy is self-service and stated in `spec-templates/SKILL.md`: name it `spec.md`/`tasks.md`, or file it under the domain it belongs to.
- 107 flat long-tail files leave the index, including `migration-checklist.md` (×21) and `dpa-verification-memo.md` (×2). These are durable-looking records misfiled as per-feature scratch; the decision accepts their removal from the index rather than widening the predicate to chase them, since they remain on disk and `git grep`-able.
- Reversible in one line: revert the `find` group.

## Alternatives considered

| Alternative | Rejected because |
|---|---|
| Keep `git mv` archival and fix its holes | Inherits the ADR-084 §5 collision that `ship/SKILL.md:2361` records as sanctioned; costs a rename across ~3,000 paths; does not fix half-archival, which reports success |
| Delete the convention outright, rely on git history | Forfeits the only real benefit. `git log --follow` retrieves a path you already know; it does nothing about discovery-surface pollution, which is what the rows cost |
| Denylist the three named ephemeral classes | Leaves ~113 long-tail rows and cannot catch the next invented filename; ~76 basenames occur exactly once |
| Allowlist `spec.md` only | De-indexes 1,209 whole features (79% of spec dirs have no `spec.md`) |
| Allowlist `spec.md` + anything at depth ≥3 | Bought 7 rows, 2 of which are themselves per-feature evidence captures, at the cost of a third predicate arm plus the fixtures and mutations to pin it |
| Rebuild the reverted archival gate | Any gate on the move inherits the same collision |
