# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-09-20-feat-kb-glossary-rejected-register-plan.md`
- Status: complete (plan → plan-review → deepen-plan, all gates pass; HEAD `dfe303c82` pushed)
- Scope verified by the parent: `git diff origin/main...HEAD --name-only` lists only `plans/`, `specs/<branch>/` and the hook-regenerated `knowledge-base/INDEX.md` — no product code touched during planning.

### Errors
None fatal. Six recoverable, each fixed and recorded as a numbered revision in the plan:

1. Two tool calls denied by hooks: `iac-plan-write-guard.sh` matched prose *describing the absence* of infrastructure patterns (the #7003 class), and a `bash` call was blocked for containing a secret-write literal. Both fixed by rewording — never via the `iac-routing-ack` opt-out, which would have asserted a reviewed infrastructure step that does not exist.
2. A standing-AC check was declared clean on ambient machine state but never tested against a sibling branch moving a shared constant. Nine ACs now pin absolute literals.
3. The first rule-pointer design was unreachable (see Decisions).
4. A liveness probe pointed the lint at the one path its glob excludes, so it would have stayed green with every entry check deleted.
5. Five stale references survived the revisions (the pre-relocation battery path ×3; the removed `requester` field's legal values ×2).
6. R28 — the naming decision was never propagated: `register` appeared 64× and "the store" 19× still naming the new artifact, including the `title:` frontmatter and Overview, while `tasks.md` already used the corrected names, so plan and task list disagreed. Caught by an independent pass, not by the author's own sweep (which grepped for dropped symbols rather than made decisions).

### Decisions
- **The rule pointer lands in the hook, and rung 5 alone was insufficient.** `cq-agents-md-tier-gate` routes an already-enforced rule's body into its enforcer, so the pointer became rung 5 of `pre-ask-technical-fork-gate.sh` — zero `B_ALWAYS` bytes, no WORM ack. But the classifier evaluates `AUTHORITY_RE` first and wins outright, matching `cost|budget|price|scope|schedule`; an accountant question carries one, so the hook would allow and rung 5 would never fire. A dedicated `EXTERNAL_EXPERT_RE` arm now precedes that short-circuit, and AC11 became a behavioural deny assertion.
- **Four briefed premises were stale.** Bundle 1 shipped `operator-rephrase`, not `operator-explain` — and its `## Vocabulary` already reserves the slot naming #8289, making the rewrite mandatory. ADR-231 is claimed on a sibling ref, so this bundle's ordinal is **232**. `triage/SKILL.md` triages local `todos/`. The Tier-1 audit entry never landed.
- **Zero external filers reframed G2.** Three authors across a 300-issue sample, all internal; `wontfix` never used in 3,182 closures. v1 is an internal dedup index and is **advisory-only** — severing a verified path where a false entry became a permanently-closed issue attributed to a human decision that never happened.
- **Two deliverables had no producer.** `compound`/`compound-capture` and a fourth `triage` Step 2 branch now supply them; the questionnaire gained an address and a return leg.
- **Two scope challenges surfaced, not applied** (DC-2 cut `kb-glossary` as a skill; DC-3 defer the store). Defaults held; `ship` Phase 6 files them from `decision-challenges.md` (DC-1…DC-6, 180 L).

### Components Invoked
- Skills: `soleur:plan`, `soleur:plan-review`, `soleur:deepen-plan`
- Research: `repo-research-analyst`, `learnings-researcher`, `functional-discovery`, two `Explore` deepen passes
- Domain review: `cto`, `cco`, `clo`, `cpo`, `cmo`
- Plan-review panel: `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`, `architecture-strategist`, `spec-flow-analyzer`
- Gates passed: plan 0.6, 0.6b, 0.6c, 0.7, 1.7, 1.7.5, 1.8, 2.5–2.12; deepen 4.4, 4.45, 4.6–4.11

## Collision Gate
- Step 0a.5 (pre-plan): #8289 OPEN, `closedByPullRequestsReferences` empty, zero linked PRs in any state. Body-probe hits #6664 (merged 2026-07-18) and #3940 (merged 2026-05-17) both predate the issue (created 2026-09-18) and intersect none of its named paths → citations, not collisions. Title probe and `git log --grep` empty. Duplicate-open-issue search over glossary / ubiquitous language / rejected request / questionnaire / out-of-scope surfaced nothing on this scope (#6008 is product-onboarding questionnaires, unrelated).
- Post-plan re-probe (this step, against the plan's `closes: 8289`): still OPEN, still no linked PR, and no open PR other than this branch's own #8405 references it.
- ADR ordinal re-derived across every `origin/*` ref: highest is ADR-231 (claimed on a sibling ref), so this bundle uses **ADR-232**. Re-derive again immediately before merge.
