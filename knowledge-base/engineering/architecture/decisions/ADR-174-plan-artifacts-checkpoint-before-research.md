---
title: Plan artifacts checkpoint before research; a plan-owned cursor key mediates resume
status: accepted
date: 2026-08-10
amends: [ADR-015]
related_adrs: [ADR-015, ADR-026, ADR-032, ADR-083, ADR-089, ADR-112, ADR-121, ADR-126, ADR-132, ADR-151]
related: [7418]
related_plans:
  - knowledge-base/project/plans/2026-08-10-chore-plan-skeleton-checkpoint-before-research-fanout-plan.md
related_specs:
  - knowledge-base/project/specs/feat-one-shot-7418-plan-skeleton-checkpoint/tasks.md
brand_survival_threshold: aggregate pattern
---

# Plan artifacts checkpoint before research; a plan-owned cursor key mediates resume

## Context

`soleur:plan` performed its entire Phase 1 research fan-out — `repo-research-analyst`,
`learnings-researcher`, community discovery, `functional-discovery`, and conditionally
`best-practices-researcher` and `framework-docs-researcher` — plus the domain-leader spawns of
Phase 2.5, before writing a single byte to the plan file. The first write was the
`## Open Code-Review Overlap` section, well after every expensive spawn. Nothing in the skill
documented when the plan file first came into existence; in practice it was created by that first
section write.

The window between "work begins" and "work becomes durable" was therefore the most expensive
stretch of the whole pipeline, and nothing survived it. `one-shot`'s partial-artifact recovery
could not help: it recognised an artifact only when the file already carried frontmatter, an
Overview and Acceptance Criteria, so anything less was discarded and the phase re-ran from scratch.

The failure was observed, not hypothesised. On 2026-08-10 a planning subagent was terminated by a
stalled response after 44 tool calls and roughly 268k subagent tokens — about 19 minutes in,
having reached the domain-leader review stage. The recovery check found no plan dated that day, no
specs directory for the branch, and no uncommitted changes. The run survived only because the
subagent's context happened to still be resumable through a harness affordance, which is not a
pipeline guarantee. The operator is billed for those tokens.

## Considered Options

1. **Reserve values inside the existing free-text `status:` frontmatter field.** Rejected on
   measurement: 338 of 1531 plans carry `status:`, across 44+ distinct values, and both `planning`
   and `complete` are already in use with human draft-state meaning. Reserving tokens inside a
   free-text field is a migration — it needs a validator, an out-of-enum arm, and a corpus sweep —
   and it would still collide with six other `status:` enums elsewhere in the repo.
2. **An HTML comment marker (`<!-- planning in progress -->`), as the originating issue proposed.**
   Rejected: it is invisible when rendered, so a leaked marker is silent, and `preflight` scrubs
   HTML comments.
3. **Have the consumer scan for "the first missing section".** Rejected: the expected heading set
   varies by detail level, which is chosen *after* research, and the conditional sections are
   gate-triggered — so every section a plan legitimately skips reads as missing.
4. **Two fields (`status:` plus a `resume_from:`).** Rejected: two fields create states that can
   disagree, and finalization deletes the cursor anyway.
5. **A dedicated `pipeline_resume:` key, deleted at finalization.** Adopted.

## Decision

**`plan` writes first and researches second.** A new Phase 0.7 runs after premise validation and
before the Phase 1 fan-out. It derives the path from the issue title Phase 0.6 has already
fetched, resolves the plans directory from `git rev-parse --show-toplevel` rather than the ambient
CWD, and writes a minimal skeleton: frontmatter plus `## Overview`, and nothing else.

**The skeleton carries only what Phase 0.6 already knows** — `title`, `date`, `slug`, `branch`, a
provisional `issue`, and the cursor. `lane`, `type`, `closes`, `priority`, `domain`,
`brand_survival_threshold` and `requires_cpo_signoff` are all derived after research and are
deliberately absent. Pre-seeding `lane:` in particular is actively harmful: it would bake in the
fail-closed `cross-domain` value, widening the very domain fan-out this checkpoint exists to
protect.

**Phase 1.7 persists the research.** The skeleton alone would still lose everything to a stall
*inside* the fan-out — the modal case, and the shape of the motivating incident — because `plan`
previously wrote no research section at all. Phase 1.7 now writes `## Research Insights` to the
plan file. This is the write that converts "we saved a filename" into "we saved the research".

**Progress is carried by a dedicated `pipeline_resume:` frontmatter key, and presence is the
boolean.** Key present means unfinished; key absent means finished. One field, one owner per
value, no two-field invariant that can disagree with itself. The cursor advances only *behind* the
content it claims: persist the section, then move the cursor.

**Finalization deletes the key.** This is what makes the committed artifact inert. A merged or
archived plan carries no cursor, so no future reader can mistake it for in-flight — which
dissolves the archive and worktree-cleanup hazards without modifying either of those paths.

**Every read is frontmatter-bounded.** Reads use the leading-`---`-guarded `sed` range adopted
verbatim from `.github/workflows/review-reminder.yml`, never a line-anchored scan.

**The consumer's completeness test is conjunctive on both paths, and its table is total.**
`one-shot` ANDs the cursor state with the positive section assertion it already used, and applies
it on the success path as well as the recovery path.

**Resume is bounded.** `resume_attempts` caps at 2 with a strict-advance requirement, and every
designed halt deletes the cursor.

## Consequences

- A stall costs one phase instead of an entire run. The research spend the operator paid for
  survives on disk.
- `one-shot`'s recovery branch is upgraded from all-or-nothing to phase granularity — the branch
  becomes reachable rather than nominal.
- `plan` keeps sole ownership of its phase vocabulary. `one-shot` recognises exactly one token by
  name, `deepening`, which selects *which* skill to re-invoke; every other value is opaque to it.
  Duplicating the vocabulary would couple two files through nothing but a test.
- The skeleton is untracked for the duration of the research window. `ls` and the frontmatter
  selector find it, but worktree recreation and `worktree-manager.sh`'s plain `mv` would not.
  Checkpoint-committing the skeleton is deferred: it changes commit shape and `one-shot`'s
  empty-branch cleanup semantics. This is an accepted residual risk, recorded rather than papered
  over.
- Phase reordering inside `plan` now carries a maintenance cost, since position and vocabulary
  ownership are asserted by `plugins/soleur/test/plan-skeleton-checkpoint.test.ts`.
- No new agents, no new gates, and no added cost on the happy path — the change is pure ordering
  plus incremental persistence.

## Relationship to prior decisions

**Amends ADR-015, and does not rewrite it.** ADR-015's Decision governs `work`'s Phase-4 exit on
the `work → {one-shot|ship}` leg. This decision governs the `plan → one-shot` leg. The two are
orthogonal legs of the same lifecycle, so the relationship is an `amends:` edge rather than an
edit to ADR-015's body — ADR-112 explicitly rejected the "amend instead of a new ADR" shape for
decisions of separable scope.

**ADR-032 is the basis for re-running gates on resume.** It records that *"a plan recovered from
disk after a subagent crash carries its 'verify X before shipping' Phase-0 gates as UNVERIFIED
claims — re-run the empirical probes, do not inherit them as done."* Resume therefore skips the
expensive work already on disk but re-runs Phase 0.6 and the conditional gates 2.7–2.11 and
Phase 3 unconditionally. Those are grep/read gates costing near nothing beside a fan-out, and
skipping the GDPR gate would silently bypass `hr-gdpr-gate-on-regulated-data-surfaces`.

**Inherits ADR-121's posture: malformed is not the same as absent.** A cursor holding an
unrecognized value resolves to Undetermined and a full re-run — never to "treat as finished". The
carrier differs from ADR-121's (a frontmatter key, not an HTML comment in a table cell), and
**ADR-089's malformed-collapses-to-absent behaviour is explicitly not inherited**: collapsing an
unreadable cursor to "absent" would mean collapsing it to "complete", which is the one verdict
that advances a stub into implementation.

**ADR-126 is why every arm is conjunctive.** Its rule is to assert the artifact the consumer
actually reads. "Cursor absent implies complete" is a negative assertion, and absence has causes
other than completion — an interrupted write, a clobber, a revert. Each is ANDed with a positive
assertion about the content the cursor claims exists.

**Reconciles ADR-026 with ADR-151.** ADR-026 makes the canonical plan template the single source
of truth for required controls, which is why `plan-issue-templates.md` documents the full key set
rather than leaving three competing definitions. ADR-151 treats plans as point-in-time records
excluded from corpus sweeps, which sits in tension with a *mutable* key living in one — and that
tension is precisely why the key is deleted at finalization rather than left in a terminal state.

**Records that CONTINUATION-GATE is un-ADR'd.** The gate exists only as prose in
`one-shot/SKILL.md`. ADR-083 rejected editing `one-shot` on grounds of *redundancy* — the guidance
already lived elsewhere. That reasoning does not transfer to a recovery branch, which has nowhere
else to live. Every arm of the recovery table therefore terminates in "continue to step 3"; a
re-invocation is a step within an arm, never an arm's end.

**Respects ADR-132.** Region markers must be HTML comments. `pipeline_resume:` is a YAML
frontmatter key and collides with neither `lint-infra-ignore` regex.

## Cost Impacts

None. No new agents, no new spawns, no additional model calls on the happy path. The intended
effect is a reduction in wasted spend: a stalled planning phase no longer re-runs a fan-out that
has already been paid for.

## NFR Impacts

Reliability and recoverability of the autonomous planning pipeline. No security, privacy, or
availability surface is touched: the change is prompt text plus a markdown artifact written to an
existing directory. No network calls, no new persisted user data, no credential handling.

## Principle Alignment

The operator is billed for these tokens and cannot see the breakdown, so discarding a completed
research fan-out because of a transient stall is a direct cost to them. Bounding the resume at two
attempts serves the same principle from the other side — an unbounded retry loop would multiply
that spend with no re-disclosure, against `hr-autonomous-loop-skill-api-budget-disclosure`. The
conjunctive completeness test protects the more serious failure: a stub plan advanced into `/work`
would produce a pull request against the operator's own repository implementing nothing they asked
for.
