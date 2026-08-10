# ADR-174: KB index exclusion supersedes per-feature archival

- **Status:** Adopting — scoped to `project/specs/` only. Plans and brainstorms are untouched, so `archive-kb.sh` remains the sole de-indexing mechanism for those two classes. Flips to `accepted` when #7400 retires its spec/plan discovery paths.
- **Date:** 2026-08-10
- **Issue:** #7399 (Tier 1). Tier 2: #7400. Related: #7401 (INDEX.md freshness gate), #7402 (orphan suites).
- **Relationship to ADR-084:** **constrained by** it. ADR-084 §5 requires `knowledge-base/project/specs/<branch>/decision-challenges.md` to be readable at its live path until `ship` Phase 6 renders Model Dissents. That requirement is what makes `git mv` archival unusable as an index-hygiene mechanism, and index-exclusion is what satisfies both.

## Context

`knowledge-base/INDEX.md` is the discovery surface agents grep for prior art:
`learnings-researcher.md:15` Step 0 greps it across all domains, and any agent may
grep it raw. (`kb-search/SKILL.md:146` Tier 1 and `learning-retrieval-bench.sh` also
read it, but both restrict to `knowledge-base/project/learnings/`, so neither ever saw
the rows this ADR removes.)

Measured 2026-08-10 by generating twice from one corpus copy, pre-edit script vs
post-edit script — a differential, because an absolute post-count is unstable by
construction here: this ADR is itself a file in the corpus it counts.

**1,275 rows removed**, all inside `knowledge-base/project/specs/*/`: 1,078
`session-state.md`, 90 `decision-challenges.md`, and 107 others across 69
distinct basenames, 58 of which occur exactly once.

The discovery value of what leaves is close to zero for the dominant class:
**535 of the 538 `session-state.md` rows on `main` carried the literal title
"Session State".** The exclusion is aimed at uninformative titles.

The pre-existing mechanism for removing a row was **per-feature archival**:
`archive-kb.sh` `git mv`s a feature's spec dir, plan, and brainstorm into sibling
`archive/` directories, which `generate-kb-index.sh` excludes. Archival is the only
thing that removed an INDEX row.

Three findings made that mechanism the wrong one:

1. **It had no recorded purpose.** No ADR governed it and no rule in `AGENTS.rules.md`
   mentioned it, so its benefit had to be re-derived from scratch for this decision.

   Git history records why the *script* exists, not why archival does. Commit
   `31c2f4070` (2026-02-25) introduced `archive-kb.sh` to "eliminate the recurring
   'Command contains $() command substitution' safety prompt that blocked automated
   workflows" — an extraction rationale. It states in the same breath that consumer
   skills were *already* "embedding shell logic in their SKILL.md files" to do the
   same `git mv`, and the first `archive/` artifacts date to 2026-01-29, four weeks
   earlier. So archival predates its script, and the one commit that explains
   anything explains the wrapper.

2. **It only ever worked on the happy path.** `derive_slug()` strips a `fix-` prefix
   and `discover_artifacts()` then probes `specs/feat-${slug}`, so a `fix-*` spec dir
   is structurally unreachable — 27 live, zero archived. Plans are found by a
   `*<slug>*` glob, so a plan named from its title rather than its branch is missed;
   `2026-08-09-my-suites-were-hermetic…` records archival taking a spec dir, leaving
   its plan, and printing `Archived 1 artifact(s)`. Half-archived reads as complete.
   It did run — 267 archived `feat-*` spec dirs, 283 plans, 123 brainstorms — which is
   why "it never worked" is the wrong diagnosis and "it works on one shape" is the
   right one.

3. **The move collides with ADR-084 §5.** A spec directory is live working state until
   `ship` Phase 6 has read `decision-challenges.md` from it. `ship/SKILL.md` already
   documents the consequence, under the sentence beginning *"The practical
   consequence: compound is the last point at which archival can happen"*:

   > If compound's consolidation is skipped or deferred — a legitimate choice when
   > Phase 6 still needs `specs/<branch>/decision-challenges.md` at its live path to
   > render Model Dissents — then archival does not happen at all, and completing it
   > later costs a follow-up PR.

   The repository's own documentation describes a sanctioned path on which archival
   silently never runs. (Cited by sentence rather than line number per
   `cq-cite-content-anchor-not-line-number` — an earlier draft of this ADR cited
   `:2361`, which was wrong by six lines when written.)

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
\( -not -path '*/project/specs/*' -o -name 'spec.md' -o -name 'tasks.md' \
   -o -path '*/project/specs/*/*/*' \)
```

**The rule is flat-scoped.** The fourth arm needs two literal `/` after `specs/`,
so a file sitting flat beside `spec.md` is excluded while a file the author
deliberately organised into a subdirectory is kept. Without it the exclusion is
depth-unbounded and silently de-indexes nested durable content.

**An allowlist, not a denylist.** Filename invention is the norm in these
directories, so any enumerated deny set is stale the next time someone writes a
`phase0-evidence.md`. Three named classes would have left ~113 long-tail rows.

**`tasks.md` is kept because 79% of live spec dirs (1,209 of 1,530) have no
`spec.md`.** Indexing only `spec.md` would have removed the sole INDEX row for those
features, whose `tasks.md` titles are real labels carrying issue numbers. 261 dirs
still lose every row under this decision; 250 of them contain nothing but
`session-state.md`, so the genuine residual is 11.

**The patterns are single-quoted and not interpolated with `$KB_DIR`.** Interpolation
makes the predicate depend on the textual form of the variable: a trailing slash
yields a `//` no `find`-emitted path contains, so the exclusion evaluates true for
everything and the feature no-ops with exit 0 and a green suite. `KB_DIR` is also
normalized once (`${KB_DIR%/}`), which fixes a pre-existing bug in the `rel=` strip
that emitted absolute paths into every row on the same input.

Measured on the live corpus, generating twice from one copy: **−1,275 rows**, plan rows
unchanged at 1,532, and the surviving basenames under `project/specs/` exactly
`spec.md` (321), `tasks.md` (1,242), plus the deliberately-nested files below.

## Status: adopting, not accepted

This decision is only fully true after Tier 2 (#7400), which excludes merged features'
`spec.md` and plans and is what makes `archive-kb.sh`'s spec/plan discovery paths
retirable. Until then `archive-kb.sh` is unchanged — neither enforced nor removed,
which is also its state today. `archive-kb/SKILL.md` carries a pointer here so the
supersession is discoverable from the tool it supersedes.

Tier 2's own open question is the merged signal: only 177 of 321 live `spec.md` carry
a `status:` key, so frontmatter alone is unreliable, and a `gh`/`ls-remote` check makes
index generation network-dependent.

## Consequences

- The discovery surface loses 1,275 rows of branch-lifetime scratch. `learnings-researcher` Step 0 is the consumer that benefits; `kb-search` Tier 1 and the retrieval bench are learnings-anchored and unaffected either way.
- Nothing moves on disk, so `git log --follow` is unaffected and ADR-084 §5's read path is untouched — `ship` Phase 6 step 2.5 reads that file by filesystem existence (`If knowledge-base/project/specs/<branch>/decision-challenges.md exists and is non-empty`), never via the index.
- A contributor who puts durable content flat in a spec directory will not see it indexed. The remedy is self-service and stated in `spec-templates/SKILL.md`: name it `spec.md`/`tasks.md`, or file it under the domain it belongs to.
- 107 flat long-tail files leave the index, including `migration-checklist.md` (×21) and `dpa-verification-memo.md` (×2). These are durable-looking records misfiled as per-feature scratch; the decision accepts their removal rather than widening the predicate to chase them, since they remain on disk and `git grep`-able. For the two DPA memos specifically the retrievability chain survives without them: both spec dirs keep an indexed `tasks.md`, and `knowledge-base/legal/compliance-posture.md` cites the vendor-ops memo by full path and stays indexed. Relocating them to `knowledge-base/legal/` would break five committed path citations and is deliberately NOT done.
- **Two directories under `project/specs/` are not feature directories at all and lose every row**: `specs/external/{claude-code,codex,opencode}.md` (vendor interface reference, "Last verified: 2026-01-21") and `specs/openhands-portability/*.md`. They hold flat files, no `spec.md`/`tasks.md`, and no `session-state.md`, so the flat rule does not reach them and the "261 dirs, 250 of them scratch" framing does not describe them. Named here rather than left implicit; the right fix is relocating them out of `project/specs/`, not another predicate arm.
- The 90 `decision-challenges.md` files are the second-largest dropped class. `ship` Phase 6 reads the current branch's own file by path, so that is unaffected — but cross-feature discovery ("has this decision been challenged before?") is knowingly sacrificed.
- Reversible in one line: revert the `find` group.

## Alternatives considered

| Alternative | Rejected because |
|---|---|
| Keep `git mv` archival and fix its holes | Inherits the ADR-084 §5 collision `ship/SKILL.md` records as sanctioned; costs a rename across ~3,000 paths; does not fix half-archival, which reports success. It would also have broken every stored `/dashboard/kb/<path>` deep link, since the web KB browser serves `knowledge-base/` from the **filesystem** — index-exclusion moves nothing and cannot |
| Delete the convention outright, rely on git history | Forfeits the only real benefit. `git log --follow` retrieves a path you already know; it does nothing about discovery-surface pollution, which is what the rows cost |
| Denylist the ephemeral classes by name | Leaves ~107 long-tail rows and cannot catch the next invented filename; 58 of the 69 dropped basenames occur exactly once |
| Allowlist `spec.md` only | De-indexes 1,209 whole features (79% of spec dirs have no `spec.md`), whose `tasks.md` row was their only presence |
| Depth-unbounded exclusion (no fourth arm) | Simpler predicate, but silently de-indexes nested durable content — the `feat-product-strategy/case-studies/*` set and `feat-6538-web2-fsn1-orphan/measurements/*`. Three independent reviewers flagged that the docs described the rule as "flat" while the code was not |
| Rebuild the reverted archival gate | Any gate on the move inherits the same collision |
