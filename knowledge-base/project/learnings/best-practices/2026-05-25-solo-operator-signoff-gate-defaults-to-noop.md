---
date: 2026-05-25
category: workflow
status: applied
session_pr: "#4417"
plan_ref: knowledge-base/project/plans/2026-05-25-feat-attachments-workspace-shared-pr2-plan.md
---

# Solo-operator sign-off gates default to no-op

## The friction

Plans with `requires_cpo_signoff: true` (or `requires_<role>_signoff:`) frontmatter are designed to pause `/work` between Phase 0 and Phase 2 so a separate domain owner can review the reconciliation table before implementation begins. The pattern was lifted from multi-role org workflows where CPO, CTO, CLO are distinct humans.

In a solo-operator org, the operator IS the CPO + CTO + CLO. Routing back to them for sign-off on a 5-panel-reviewed plan's technical reconciliations (R-1 predicate semantics, R-3 policy split mechanics, R-5 RPC-folding pattern) is a context switch with no signal — they already approved the plan at commit time.

## The rule

**At plan creation:** Setting `requires_<role>_signoff: true` is appropriate ONLY when the named role is held by a person OTHER than the operator running `/work`. For solo-operator orgs, do NOT set the flag — the 5-panel plan-review IS the sign-off. Roadmap-pattern multi-role flags (`requires_cpo_signoff`, `requires_cto_signoff`, `requires_clo_signoff`) should be opt-in per-org, not template defaults.

**At `/work` execution:** When a plan carries the flag AND the operator is the same person who would have to sign off, treat the flag as already-satisfied for the named role. Proceed into Phase 2 without an additional pause prompt. Surface the technical reconciliations as a one-line acknowledgement ("Plan-time R-1/R-3/R-5 reconciliations validated by Phase 0 probes; proceeding") rather than a question.

**When Phase 0 surfaces an emergent finding** (e.g., "the plan's `member_<hex>` pseudonym design is FK-invalid; codebase convention is `user_id = NULL`"), classify the finding:
- **Strict simplification matching codebase convention** → proceed inline with a clear inline doc note; do NOT pause for sign-off. Document the redesign in the commit + the spec worklog.
- **User-visible behavior change** → DO pause and ask the operator; this affects product surface area, not just implementation detail.
- **Compliance / lawful-basis change** → DO pause and ask; legal posture is binding.

The pseudonym redesign for #4318 (E-1) was case 1: strict simplification, no user-visible change, matches mig 051/048/044/053 precedent. Pausing would have cost a round-trip without changing the outcome.

## Why

The operator (Jean) explicitly flagged this mid-session at PR #4417 ("Why can't you keep going without my approval on this? Soleur users will have no clue about this if they aren't technical and it will make our system unusable."). The system is unusable when every technical reconciliation requires an operator sign-off they can't meaningfully evaluate — the 5-panel review at plan time IS the meaningful evaluation.

## How to apply

- **`/soleur:plan`**: when generating a new plan template, default `requires_*_signoff: false` unless the operator explicitly opts in. The frontmatter field can stay (preserves the multi-role org future), but the default flips.
- **`/soleur:work`**: when reading the plan's frontmatter, treat `requires_<role>_signoff: true` as a hard pause ONLY if a `signoff_received_at: <timestamp>` companion key is absent AND a `signoff_routed_to:` value names a person other than the current operator. Otherwise, log "plan-time review covers <role> sign-off; proceeding" and continue.
- **`/soleur:work` for Phase 0 emergent findings**: classify per the table above. Don't pause for case 1 (strict simplification) findings.

## Related rules / learnings

- AGENTS.md core `hr-weigh-every-decision-against-target-user-impact` — user impact is binding; technical-only findings are not.
- AGENTS.md core `cm-when-proposing-to-clear-context-or` — same shape: unilaterally proposing pauses that the operator can't meaningfully act on is friction.
- AGENTS.md core `wg-zero-agents-until-user-confirms` — the existing "ask before spawning agents" gate is the correct shape (binding, observable); sign-off gates without binding routing are not.

## Files touched (none by this learning)

This is a process learning. Implementation lands in `/soleur:plan` template defaults + `/soleur:work` frontmatter-handling logic when the next plan-class change goes through.
