---
title: "Is per-feature KB archival worth keeping at all?"
date: 2026-08-10
branch: feat-kb-archival-convention
pr: 7398
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm
supersedes_question_from: PR 7396 "Known limits — not claimed fixed"
related:
  - knowledge-base/engineering/architecture/decisions/ADR-084-decision-classification-taxonomy-for-autonomous-question-surfacing.md
  - knowledge-base/project/learnings/2026-08-09-my-suites-were-hermetic-so-they-certified-a-gate-reached-through-a-dead-read.md
  - knowledge-base/project/learnings/2026-03-13-archive-kb-stale-path-resolution.md
---

# Is per-feature KB archival worth keeping at all?

The question PR #7396 raised in its own "Known limits" section, asked before another
gate gets built. PR #7396 built an archival gate, review found it would break
ADR-084, and it was reverted. The correct next move is not a better gate — it is
deciding whether the thing the gate enforces should exist.

## What We're Deciding

Per-feature archival (`archive-kb.sh`) `git mv`s a feature's spec dir, plan, and
brainstorm into sibling `archive/` directories with a timestamp prefix. Git history
already holds every version of every one of those files. So: **what does archival buy
that `git log --follow` does not, and is it worth the mechanism?**

## Answer to Question 1 — archival buys exactly one thing, and it is real

**It removes rows from `knowledge-base/INDEX.md`, the discovery surface agents read.**

`scripts/generate-kb-index.sh` excludes `*/archive/*` (lines 39, 136). Archiving is
the *only* mechanism that removes an INDEX row. That matters because INDEX.md has
live consumers:

- `kb-search` SKILL.md:146 — Tier 1 greps INDEX.md
- `learnings-researcher.md:15` — Step 0 greps it "across ALL domains … including
  specs, brainstorms, plans"
- `scripts/learning-retrieval-bench.sh:462` — ranks INDEX.md lines

`git log --follow` retrieves a path you already know. It does nothing about
*discovery-surface* pollution. So "git history is sufficient, delete the convention"
is wrong — it forfeits a measured benefit.

**But note precisely what the benefit is attached to: INDEX.md membership, not the
directory move.** That distinction is the whole decision.

### The measurement

INDEX.md **as committed on main is stale by 3,711 rows.** Regenerated from the same
tree it is **7,507 rows**, not 3,801. Real figures:

| Slice | Rows | Share of INDEX.md |
|---|---|---|
| INDEX.md total (regenerated) | 7,507 | 100% |
| `project/specs/**` rows | 2,842 | 38% |
| `project/plans/**` rows | 1,530 | 20% |
| **specs + plans combined** | **4,372** | **58%** |

And the spec-dir rows are overwhelmingly **not specs**:

| File class inside spec dirs | Rows |
|---|---|
| `tasks.md` | 1,241 |
| `session-state.md` | 1,077 |
| `spec.md` | 320 |
| `decision-challenges.md` | 90 |

**2,408 of 2,842 spec-dir rows (85%) are per-feature ephemeral working state.**
`session-state.md` is session scratch. `tasks.md` is a branch-lifetime checklist.
Neither is knowledge, and neither should ever have been indexed.

Disk is a non-argument: 4.5 MB archived specs vs 33 MB live, 6.4 MB vs 54 MB. And
INDEX.md is not session-start loaded, so the cost is **search precision and agent
discovery quality**, not a per-turn token tax. Stated plainly so it is not
overclaimed later.

## The premise, corrected

The framing that opened this session was mostly right and wrong in one place that
changes the diagnosis.

| Claim | Verdict |
|---|---|
| ~1,527 live spec dirs / ~1,527 live plans | Confirmed — 1,530 live spec dirs, 1,530 live plans |
| 27 live `fix-*` spec dirs, zero archived | **Confirmed.** `derive_slug()` strips `fix-`, then `discover_artifacts()` probes only `specs/feat-${slug}`. Structurally unreachable. |
| "that path appears never to have worked once" | True of `fix-*` specs. **False of the convention.** |
| The convention isn't real | **False.** `specs/archive/` holds 266 archived `feat-*` dirs, `plans/archive/` 283, `brainstorms/archive/` 123 — ~672 successful archivals, still firing 7–75/month through Aug 2026. |

So this is **not** a convention that never existed. It is one that works on the happy
path and silently no-ops on every other shape:

- `fix-*` branches — structurally unreachable (27 live, 0 archived)
- topic-named plans — found by `*<slug>*` glob, so a plan named from its title rather
  than its branch is missed. `2026-08-09-my-suites-were-hermetic…` records exactly
  this: archival took the spec dir, left the plan, and printed `Archived 1
  artifact(s)`. **Half-archived reads as complete.**

Different diagnosis, different fix. "Never worked" implies build it; "works on half
the shapes and misreports" implies the mechanism is wrong.

**And no stated purpose survives.** Zero ADRs govern archival. Zero rules in
`AGENTS.rules.md` mention it. The only rationale anywhere in the repo is
`archive-kb.sh`'s header comment, which describes mechanism, not purpose. The
convention's benefit had to be re-derived from scratch in this session.

## Why the reverted gate was right to be reverted

ADR-084 §5 mandates `knowledge-base/project/specs/<branch>/decision-challenges.md`,
read by `ship` Phase 6 to render Model Dissents into the PR body and file the
`action-required` issue. ADR-084's premise is that **the operator has not seen those
dissents.**

So the spec dir is *live working state* until ship Phase 6 completes. A gate forcing
archival before that inverts the ordering and silently drops dissents. That is not a
defect in the gate's implementation — it is `git mv` colliding with a live read. Any
gate built on the move inherits the collision.

## Why This Approach — keep the benefit, drop the move

Neither "keep" nor "delete". The benefit is INDEX.md exclusion; the move is what
generates every failure in this record. Separate them: **exclude from the index
directly, and retire the move.**

It dominates on every axis that produced this session:

- **No ADR-084 conflict.** Nothing moves, so `specs/<branch>/decision-challenges.md`
  never breaks. The revert's entire reason evaporates and a gate becomes buildable.
- **The 3,054-artifact backlog costs one generator change plus one regeneration** —
  not a 3,054-path rename commit, no `git log --follow` breakage, no half-archived
  states.
- **Fixes `fix-*` structurally.** An exclusion predicate does not care about the
  `feat-`/`fix-` prefix; `archive-kb.sh`'s exact-path probe structurally cannot.
- **The half-archive failure mode disappears.** A predicate applies uniformly to spec
  and plan; a two-step `git mv` cannot.

### Two tiers, because they carry different risk

**Tier 1 — never index per-feature ephemeral working state.** No predicate, no
judgment call: `session-state.md`, `tasks.md`, `decision-challenges.md` are
branch-lifetime scratch. Removes **2,408 rows, 32% of INDEX.md**, deterministically.
`spec.md` is untouched, so prior-art sweeps keep working.

**Tier 2 — exclude merged features' `spec.md` and plans.** A further 1,850 rows
(25%). This one needs a reliable merged signal and is genuinely harder: only 176 of
320 live `spec.md` carry a `status:` key, so frontmatter alone is unreliable, and a
`gh`/`ls-remote` check makes index generation network-dependent. **Deferred to its
own issue** rather than guessed at here.

Together the tiers reach 4,258 rows — 57% of INDEX.md.

Tier 1 is most of the benefit at none of the risk, and it changes the economics of
Tier 2. `archive-kb.sh` cannot be retired for specs/plans until Tier 2 lands; until
then it stays as-is, neither enforced nor removed.

## Key Decisions

| Decision | Rationale |
|---|---|
| Per-feature archival is **not** worth keeping as a `git mv` convention | Its only real benefit is INDEX.md exclusion, achievable directly and more reliably |
| Do **not** delete the convention outright | That forfeits a measured 58%-of-INDEX.md discovery benefit; git history does not substitute |
| Do **not** build the reverted gate, reworked or otherwise | Any gate on the move inherits the ADR-084 collision |
| Ship Tier 1 (ephemeral-class exclusion) now | 32% of INDEX.md, zero predicate, zero risk, no backlog migration |
| Defer Tier 2 (merged-feature exclusion) to its own issue | Needs a reliable local merged signal; guessing it here would repeat the gate's mistake |
| `archive-kb.sh` stays untouched for now | Retirement is Tier 2's exit criterion, not Tier 1's |
| The 3,054 backlog is **not** migrated | Under index-exclusion there is nothing to migrate — that is the point |

## Open Questions

- **Tier 2's merged signal.** Frontmatter `pr:`/`branch:`/`status:` is present on
  only ~55% of live `spec.md`. Candidates: backfill frontmatter; derive from
  `git ls-remote` (network); derive from branch-deleted state at merge time and stamp
  it into the spec. Deferred issue should evaluate all three.
- **Brainstorms.** 315 live / 123 archived. Unlike `tasks.md`, a brainstorm *is*
  knowledge and arguably belongs in INDEX.md forever. This decision does not touch
  them; archival of brainstorms may be worth keeping on its own merits.
- **INDEX.md is stale on main by 3,711 rows.** Nothing regenerates it on merge. This
  is a separate defect from archival — the discovery surface is both polluted *and*
  out of date. Should be filed independently.

## Session Errors

- The opening framing asserted the archival path "appears never to have worked once."
  It has run ~672 times. The `fix-*` sub-claim was exactly right; generalising it to
  the convention would have justified deleting a mechanism that delivers a real
  benefit. Corrected before any option was scoped.
- The first cost measurement used the committed INDEX.md (3,801 rows) and understated
  the problem by ~half. Regenerating revealed 7,507. A generated artifact's committed
  state is not a measurement of the generator's output.

## User-Brand Impact

- **Artifact:** `knowledge-base/INDEX.md` and the KB discovery path (`kb-search`,
  `learnings-researcher`) that Soleur operators' agents rely on to find prior art.
- **Vector:** A discovery surface that is 58% per-feature scratch degrades the prior-art
  sweeps that prevent agents from re-deriving or contradicting decisions already made —
  the failure is silent and surfaces as an agent confidently acting on a false
  greenfield premise in a customer's repo.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

Domain leaders were **not** spawned. Per `wg-zero-agents-until-user-confirms` the
evidence was gathered inline and presented first; the operator elected to skip the
triad on the grounds that this is internal KB tooling with no user-facing, legal,
sub-processor, or recurring-cost surface. Recorded here so the omission is a decision,
not a gap.
