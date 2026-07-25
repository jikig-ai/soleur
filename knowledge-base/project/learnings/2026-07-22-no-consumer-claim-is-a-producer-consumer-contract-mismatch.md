---
date: 2026-07-22
category: workflow-patterns
module: marketing-content-pipeline
issue: 6827
tags: [premise-validation, producer-consumer, cron-liveness, write-site-sweep, brainstorm]
---

# "Artifact X has no consumer" is a contract mismatch until proven otherwise

## Problem

Issue #6827 asserted that `knowledge-base/marketing/seo-refresh-queue.md` never drains because
it "has no consumer", and asked to "give the queue a consumer: the cascade should open one issue
per flagged page."

The queue had **two** consumers. The ask would have built a third writer for a pipeline whose
existing readers were already wired — and would have relocated a write-mostly backlog into an
`action-required` issue queue already 28 deep.

## Root cause

The queue failed to drain because the producer and the consumer disagreed on **two independent
axes**, neither of which is visible from "does a consumer exist?".

**Axis 1 — write target vs. read target.** The producer
`apps/web-platform/server/inngest/functions/cron-competitive-analysis.ts:166` appends dated
`## Stale Comparison Pages Flagged for Regeneration (YYYY-MM-DD)` blocks, which land at
`seo-refresh-queue.md:201` and `:219` — *below* `## Refresh Schedule` (`:191`). The consumer
`cron-content-generator.ts:103` reads only "Priority 1 … Priority 2 pillar … Priority 2
comparison" (§1.x / §2.2 / §2.1). Every flagged row was structurally unreachable.

**Axis 2 — selection predicate vs. artifact state.** The consumer selects "the highest-priority
item **without** a `generated_date` annotation". Sections §1.1–§1.7 are prose subsections with no
such field at all, and they sort first — so §1.1 Homepage was eligible on every fire, forever.
Meanwhile a published-but-stale page always *has* a `generated_date`, so it could never be
re-selected. "Stale" (what the queue tracks) and "never generated" (what the cron acts on) are
different predicates.

The pipeline was **mis-targeted, not stalled**.

## Solution

Two cheap probes, run before scoping any consumer:

1. **Grep for readers.** `grep -rn "<artifact-path>" --include="*.ts" --include="*.yml" .` —
   this alone falsified the issue's premise in one command.
2. **Diff write target against read predicate.** Read the producer's append instruction and the
   consumer's selection instruction side by side. They are usually a few lines of prompt text.

Only if both probes come back clean is "no consumer" the real diagnosis.

## Key insight

**A "no consumer" claim is a claim about a contract, and a contract has two sides.** An issue
author observing an undrained queue correctly identifies the symptom and then reliably guesses
the mechanism, because "nothing is reading this" is the intuitive explanation and "two things
are reading this but disagree about where rows live" is not. The guess is expensive: it scopes a
new producer instead of a prompt-level reconciliation.

Corollary that generalizes past this case: **when a producer and a consumer both exist, prefer
suspecting the contract over suspecting absence.**

## Second finding — a correction must sweep every write-site, including non-rendered twins

The comparison-page figure correction merged 2026-07-20 fixed
`plugins/soleur/docs/blog/2026-03-31-soleur-vs-paperclip.md` (→ "74,000+ stars") but not its
social twin `knowledge-base/marketing/distribution-content/2026-04-15-soleur-vs-paperclip.md`,
which carries `status: published` and still states **"14.6k GitHub stars" in six places** against
a true 74,282 — roughly 5x off.

The twin is **not** Eleventy-compiled (`eleventy.config.js:3` sets `INPUT = "plugins/soleur/docs"`),
so a "is it live on the site?" check returns clean while the social-distribution record stays
wrong. That is precisely what makes this class of miss survive a dedicated correction PR: the
verification question most reviewers ask ("is the bad copy live?") is answerable *and* answers
"no".

Cites `hr-write-boundary-sentinel-sweep-all-write-sites`. Durable gate filed as **#6838**.

**Prevention:** when correcting a factual claim, enumerate write-sites by grepping for the
*claim* (`grep -rn "14\.6k"`), never by grepping for the *rendered page*. A non-rendered record
is still a record, and `status: published` means it already shipped somewhere.

## Third finding — cron liveness is per-role, not per-artifact

An artifact's staleness does not tell you which side of its pipeline is dark. Here the
**producer** (`cron-competitive-analysis`) was dark ~90d and the **consumer**
(`cron-content-generator`) was live at 2x/week — the opposite of what the artifact's 42-day
frontmatter suggested, and the opposite of what was asserted mid-session.

Read liveness from the self-authorship column of
`knowledge-base/engineering/audits/2026-07-20-cron-liveness-cohort-audit.md` (`:151-153`) plus
the cron's own open audit issue (`#6818` for the consumer, `#4375` for the producer). The audit's
own thesis says it directly: cron self-authorship and artifact currency are different questions,
and on 2 of 9 rows they differ by more than two months.

**Why this mattered here:** it inverted the scope. If the consumer were dark, fixing the contract
would buy nothing until liveness was restored. Because the consumer is live, the contract fix
changes behaviour on the next fire.

## Session Errors

1. **Severity overstatement.** Characterized the stale distribution twin as "live, shipped, wrong
   copy." `distribution-content/` is never compiled by Eleventy, so it was never on soleur.ai.
   Recovery: corrected in-session before any artifact was written; the brainstorm and issue
   bodies carry the precise framing. **Prevention:** before assigning severity to stale content,
   trace the render path (`eleventy.config.js` `INPUT`) — "in the repo" and "on the site" are
   different claims.

2. **Cron liveness direction inverted.** Asserted `cron-content-generator` was dark; it fires
   twice weekly. Recovery: corrected by the CTO assessment, which read the audit's self-authorship
   column and found the open consumer audit issue. **Prevention:** see the third finding above —
   never infer which cron is dark from the artifact's `last_updated`.

3. **Subagent returned unverified claims.** The CPO assessment stated the consumer was dark and
   that "every §2.1 row carries `generated_date`"; direct inspection found two rows without it
   (Soleur vs. Cursor, Why Most Agentic Tools Plateau). Recovery: verified by direct grep before
   the claims reached any artifact. **Prevention:** already covered by the existing brainstorm
   guidance on cross-checking leader claims against repo research; no new rule warranted.

4. **Scratchpad directory did not exist.** `gh issue view … > $SP/6827.md` failed with "No such
   file or directory". Recovery: `mkdir -p`. **Prevention:** one-off; no rule warranted.

5. **Workflow-gate deviation — `wg-zero-agents-until-user-confirms`.** Six agents (4 domain
   leaders + 2 researchers) were spawned immediately after routing, from a bare `#6827` input,
   with no summary-and-confirm step. The rule reads: "Zero agents until user confirms direction.
   Present a concise summary first, ask if they want to go deeper, only then launch research.
   Exception: passive domain routing." Brainstorm Phase 0.5 mandates the leader spawns
   unconditionally, and the rule's only exception is passive domain routing — so the two are in
   direct conflict and the conflict is currently resolved by whichever instruction the agent
   weights higher. Recovery: none possible after the fact; the spawns produced the correct
   analysis, which is what makes the deviation easy to rationalize. **Prevention:** filed as a
   route-to-definition issue — resolving it requires either an explicit pipeline-skill exception
   in the AGENTS.md rule (a semantic change to a hard rule) or a confirm gate in brainstorm
   Phase 0.5 (contested design). Both exceed the bounded-surface budget for a direct edit.

6. **Roadmap drift left unreconciled.** `roadmap-reconcile.sh validate` reported
   `STALE_STATUS|phase 4|roadmap=43o/160c|milestone=56o/178c`. Not hand-edited: the script routes
   remediation through the `cron/roadmap-review` manual trigger, which opens a reviewed PR.
   **Prevention:** one-off; recorded so the drift is not lost.

## Rule budget at capture time

Always-loaded payload measured **22,973 bytes against a 23,000-byte commit-gate reject
threshold** — 27 bytes of headroom, with 99 rules unused over 8 weeks. Any new rule from this
session must route to a skill or agent file, never to `AGENTS.md`. Recorded because it is the
binding constraint on this learning's own routing decision.

## Related

- `knowledge-base/project/learnings/2026-05-12-brainstorm-write-mostly-artifact-diagnosis-and-lifecycle-prereq.md`
  — lifecycle-before-production; an artifact with entries and zero closures needs a closure path,
  not a bigger producer.
- `knowledge-base/project/learnings/2026-03-12-competitive-analysis-cascade-data-reconciliation.md`
  — the cascade must write back to the upstream source of truth, not only downstream. This is the
  same 14.6k figure, three months earlier.
- `knowledge-base/engineering/audits/2026-07-20-cron-liveness-cohort-audit.md` — the two
  independent freshness producers (self-authorship vs. artifact frontmatter).
- Issues: #6827 (tracker), #6838 (twin-drift gate), #6837 (non-affiliation disclaimer),
  #4375 (dark producer).
