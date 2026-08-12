---
title: Plan artifacts checkpoint before research; completion is asserted from content, not a cursor key
status: accepted
date: 2026-08-10
amends: [ADR-015]
related_adrs: [ADR-015, ADR-026, ADR-032, ADR-083, ADR-089, ADR-112, ADR-121, ADR-126, ADR-132, ADR-151]
related: [7418, 7420, 7421]
related_plans:
  - knowledge-base/project/plans/2026-08-10-chore-plan-skeleton-checkpoint-before-research-fanout-plan.md
related_specs:
  - knowledge-base/project/specs/feat-one-shot-7418-plan-skeleton-checkpoint/tasks.md
brand_survival_threshold: aggregate pattern
---

# Plan artifacts checkpoint before research; completion is asserted from content, not a cursor key

## Context

`soleur:plan` performed its entire Phase 1 research fan-out — `repo-research-analyst`,
`learnings-researcher`, community discovery, `functional-discovery`, and conditionally
`best-practices-researcher` and `framework-docs-researcher` — plus the domain-leader spawns of
Phase 2.5, before writing a single byte to the plan file. The first write was the
`## Open Code-Review Overlap` section, well after every expensive spawn. Nothing in the skill
documented when the plan file first came into existence; in practice it was created by that write.

The window between "work begins" and "work becomes durable" was therefore the most expensive
stretch of the pipeline, and nothing survived it. `one-shot`'s partial-artifact recovery could not
help: it recognised an artifact only when the file already carried frontmatter, an Overview and
Acceptance Criteria, so anything less was discarded and the phase re-ran from scratch.

The failure was observed, not hypothesised. On 2026-08-10 a planning subagent was terminated by a
stalled response after 44 tool calls and roughly 268k subagent tokens — about 19 minutes in, having
reached the domain-leader review stage. The recovery check found no plan dated that day, no specs
directory for the branch, and no uncommitted changes. The run survived only because the subagent's
context happened to still be resumable through a harness affordance, which is not a pipeline
guarantee. The operator is billed for those tokens.

## Considered Options

1. **Reserve values inside the existing free-text `status:` frontmatter field.** Rejected on
   measurement: **321 of 1531** plans carry `status:`, across **41 distinct values**, and both
   `planning` and `complete` are already in use with human draft-state meaning. Reserving tokens
   inside a free-text field is a migration — validator, out-of-enum arm, corpus sweep — and it would
   still collide with the other `status:` enums elsewhere in the repo (`file-todos`, `resolve-debt`,
   the ADR template, distribution-content). *(Measured 2026-08-10 with the frontmatter-bounded
   reader this ADR mandates. An earlier revision cited 338/1531 across 44+ values; that figure was
   produced by the unbounded line-anchored reader this ADR condemns, and over-counted by 16 files.
   The rejection never rested on the magnitude — the collision of `planning` and `complete` with
   human meaning is the load-bearing part, and it survives the correction unchanged.)*
2. **An HTML comment marker (`<!-- planning in progress -->`), as the originating issue proposed.**
   Rejected: invisible when rendered, so a leaked marker is silent, and `preflight` scrubs HTML
   comments.
3. **Have the consumer scan for "the first missing section".** Rejected: the expected heading set
   varies by detail level, which is chosen *after* research, and the conditional sections are
   gate-triggered — so every section a plan legitimately skips reads as missing.
4. **Two fields (`status:` plus a `resume_from:`).** Rejected: two fields create states that can
   disagree.
5. **A dedicated `pipeline_resume:` cursor key, deleted at finalization.** **Implemented, reviewed,
   and rejected before merge.** A 12-agent review found twelve blocking defects behind a fully green
   suite, and every one reduced to the same shape: a second progress signal that could disagree with
   the file's own content, with the disagreement resolving to a fail-open arm. Two are worth naming,
   because they are the general argument in concrete form. The verdict table routed `deepening` and
   `finalize` *with sections present* — the only shapes those states can actually have — to
   "re-plan from scratch", so every late-stage stall discarded a completed plan: the exact loss this
   ADR exists to prevent. And because a cap-trip and every `deepen-plan` HALT *deleted* the key, a
   designed refusal became indistinguishable from success and advanced a stub into `/work`. That the
   table was **conjunctive** was the tell: ANDing the cursor with a content assertion concedes that
   the content is the real predicate and the cursor is advisory.
6. **No dedicated key: assert completion from `## Acceptance Criteria`, the one heading present in
   all three detail-level templates and written last.** **Adopted.** Unlike option 3 this is a single
   fixed *positive* assertion, not a scan for the first missing section across a variable heading
   set — and it is the assertion `one-shot` already used before this decision. Measured at adoption:
   `## Acceptance Criteria` is present in all three templates in
   `plan/references/plan-issue-templates.md`; `## Overview` is **absent from MINIMAL** and was
   therefore removed from the conjunct, because the old predicate re-planned finished minimal plans
   from scratch.

## Decision

**`plan` writes first and researches second.** A new Phase 0.7 runs after premise validation and
before the Phase 1 fan-out. It derives the path from the issue title Phase 0.6 has already fetched,
resolves the plans directory from `git rev-parse --show-toplevel` rather than the ambient CWD, and
writes a minimal skeleton: frontmatter plus `## Overview`, and nothing else.

**The skeleton carries only what Phase 0.6 already knows** — `title`, `date`, `slug`, `branch`, and
a provisional `issue`. `lane`, `type`, `closes`, `priority`, `domain`, `brand_survival_threshold`
and `requires_cpo_signoff` are derived after research and are deliberately absent. Pre-seeding
`lane:` is actively harmful: it would bake in the fail-closed `cross-domain` value, widening the
very domain fan-out this checkpoint exists to protect.

**Phase 1.7 persists the research, in a single Edit.** The skeleton alone would still lose
everything to a stall inside the fan-out, because `plan` previously wrote no research section at
all. Phase 1.7 now writes `## Research Insights` to the plan file. It must be one Edit at the end of
consolidation: Phase 0.7 reads that section's presence as "the fan-out completed", so a half-written
section would be read as a whole one.

**Completion is asserted from content, never from a progress key.** A plan is finished when it
carries `## Acceptance Criteria`. The skeleton writes `## Overview` and nothing else, so a stub
cannot forge the predicate. An interrupted run's checkpoint is continued in place rather than
duplicated or overwritten.

**Any frontmatter key a skill both reads and writes must have its writer prescribed at the same site
as its reader** — same fenced block, quoting and whitespace normalisation included — **or the key
must not exist.** A pinned reader with an invented-per-site writer is not a contract; it is a reader
and an unbounded set of producers, and every disagreement between them resolves to the reader's
fail-open arm. This is the stated reason the cursor was dropped rather than repaired: it had five
write sites across three skills and no prescribed write format anywhere.

**Every read is frontmatter-bounded.** This now applies to `branch:`, the one key this feature both
produces and consumes. Reads use an `awk` state machine that skips line 1 and **exits at the second
`---`**. A `sed` range does not suffice: ranges re-arm, so a document with real frontmatter plus a
`---`-delimited example in its body re-enters the range and harvests the body value — and any
document that *documents* this mechanism has exactly that shape.

**The recovery runs at most once.** If `plan` returns and the artifact still lacks
`## Acceptance Criteria`, `one-shot` stops and files an `action-required` issue rather than
re-invoking planning again. The bound lives in `one-shot` because that is the only place where two
attempts occur inside one process and can therefore be counted at all.

## Consequences

- A stall costs one phase instead of an entire run. The research spend the operator paid for
  survives on disk and is reused by the continuing run.
- `one-shot`'s recovery branch is upgraded from all-or-nothing to **artifact granularity**: the
  research survives and is reused. *Phase* granularity was considered and not delivered — measured,
  the checkpoint boundaries do not subdivide either expensive block, so a stall inside the Phase 1
  fan-out or inside the Phase 2.5 domain fan-out still re-runs that block in full.
- No skill learns a progress vocabulary, so there is no boundary to police and no table to invert.
- **Cost on the happy path is small and bounded, not zero:** two additional Write calls (the
  Phase 0.7 skeleton and the Phase 1.7 research section) and one bounded selector loop over
  `plans/*.md`. No new agents, no new spawns, no additional model calls.
- The skeleton is untracked for the duration of the research window. `ls` and the frontmatter
  selector find it, but a worktree removal would not — `worktree-manager.sh`'s
  `git worktree remove --force` is the path that destroys it. Checkpoint-committing the skeleton is
  deferred to **#7420**: it changes commit shape and `one-shot`'s empty-branch cleanup semantics.
  Accepted residual risk, recorded rather than papered over.
- Phase reordering inside `plan` carries a maintenance cost, since position, the completion
  predicate's agreement with the templates, and the bounded reader are asserted by
  `plugins/soleur/test/plan-skeleton-checkpoint.test.ts`.

## Relationship to prior decisions

**Amends ADR-015, and does not rewrite it.** ADR-015's Decision governs `work`'s Phase-4 exit on the
`work → {one-shot|ship}` leg; this governs the `plan → one-shot` leg. Orthogonal legs of one
lifecycle, so the relationship is an `amends:` edge rather than an edit to ADR-015's body — ADR-112
rejected the amend-instead-of-new-ADR shape for decisions of separable scope. Per ADR-112's operative
ground (an amendment must be discoverable *from* the amended ADR), ADR-015 carries the reciprocal
`amended_by: [ADR-175]`.

**ADR-126 is why the cursor is gone.** Its rule is to assert the artifact the consumer actually
reads. Once the consumer asserts the content, a parallel key contributes nothing the content does
not already carry — and everything it can contribute is a way to disagree with it.

**Inherits ADR-121's posture — malformed is not the same as absent — by construction.** There is no
key that can be malformed; the surviving predicate is purely positive. **ADR-089's
malformed→absent collapse is explicitly not inherited**: collapsing an unreadable signal to "absent"
would mean collapsing it to "complete", the one verdict that advances a stub into implementation.

**ADR-032 is satisfied by construction rather than by a prose rule.** It records that *"a plan
recovered from disk after a subagent crash carries its 'verify X before shipping' Phase-0 gates as
UNVERIFIED claims — re-run the empirical probes, do not inherit them as done."* Because recovery
re-invokes `plan` rather than jumping into its middle, every gate re-runs.

**Reconciles ADR-026 with ADR-151.** ADR-026 makes the canonical plan template the single source of
truth for required controls, which is why `plan-issue-templates.md` documents the full key set and
its two stages. ADR-151 treats plans as point-in-time records excluded from corpus sweeps — a
tension that disappears entirely once no mutable machine key lives in one.

**ADR-083's second ground applies here, and is mitigated.** ADR-083 declined to edit `one-shot` on
two grounds: redundancy, and that *"a third nudge risks its CONTINUATION-GATE anti-stop logic."* The
redundancy ground does not transfer — a recovery branch has nowhere else to live — but the second
does, and this change inserts re-invocation arms directly above those gates. Mitigation: every arm
terminates in "continue to step 3", with the single escalation arm called out explicitly as terminal.

**ADR-132 is cited for practice, not authority.** ADR-132 decides filename-neutralisation in
`lint-infra-no-human-steps.py`; its region markers appear there as evidence carve-outs rather than as
a decision about marker form. This change follows that practice — the `plan-artifact-recovery` region
in `one-shot/SKILL.md` is an HTML comment pair.

## Cost Impacts

Two additional Write calls and one bounded directory loop per planning run. No new agents, no new
spawns, no additional model calls. The intended effect is a reduction in wasted spend: a stalled
planning phase no longer discards a fan-out that has already been paid for.

## NFR Impacts

Reliability and recoverability of the autonomous planning pipeline. No security, privacy or
availability surface is touched: prompt text plus a markdown artifact in an existing directory. No
network calls, no new persisted user data, no credential handling.

The detection surface for a mis-recovery is the `Plan artifact:` line `one-shot` writes into
`knowledge-base/project/specs/<branch>/session-state.md`, committed with the branch. This is
observability layer 7 — the code executes on the operator's own self-hosted CLI, so the observable
surface is the artifact the run leaves on disk, not a server-side sink.

## Principle Alignment

The operator is billed for these tokens and cannot see the breakdown, so discarding a completed
research fan-out because of a transient stall is a direct cost to them. The single-attempt recovery
bound serves the same principle from the other side — an unbounded retry loop would multiply that
spend with no re-disclosure, against `hr-autonomous-loop-skill-api-budget-disclosure`. And the
reason the cursor was dropped rather than repaired is the same principle again: its worst failure
was not a wasted fan-out but a stub plan advanced into `/work`, producing a pull request against the
operator's own repository implementing nothing they asked for.
