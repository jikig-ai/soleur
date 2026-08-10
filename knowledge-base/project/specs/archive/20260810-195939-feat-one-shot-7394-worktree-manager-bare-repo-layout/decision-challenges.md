# Decision Challenges — `feat-one-shot-7394-worktree-manager-bare-repo-layout`

Persisted for operator adjudication. This pipeline ran **headless**, so per ADR-084 these were
recorded rather than asked. `/soleur:ship` Phase 6 renders this file into the PR body and files it
as an `action-required` issue.

---

## DC-1 — Scope: cut Phase 4 and Phase 5? (`decisionClass: taste`)

**Raised by:** `code-simplicity-reviewer`, at plan-review on
`knowledge-base/project/plans/2026-08-10-fix-worktree-manager-bare-in-dotgit-config-poison-plan.md`.

**The challenge.** The plan stacks three independent defensive layers against one hazard:
delete-the-writer (Phase 3), per-worktree immunization (Phase 4), and per-session self-heal
(Phase 5). The reviewer's position is that the plan's own measurement shows
`worktree-manager.sh:653-654` is the **sole** setter of `extensions.worktreeConfig` in the entire
repository, so once Phase 3 deletes it the hazard has no surviving entry point from this codebase —
making Phases 4 and 5 defenses against an eliminated threat. Proposed cut: Phases 4 and 5 entirely,
two of three telemetry markers, three test cases, two ACs, and folding `ADR-173` into the `ADR-099`
amendment. Estimated ~30–35% scope reduction.

**What the plan did instead:** kept both phases; applied the marker reduction (3→2) but not the
phase cuts or the ADR fold-in.

**Evidence against the cut, from the same panel:**

1. `dhh-rails-reviewer` — the panel's *other* simplification lens — reached the opposite conclusion
   independently: Phase 5 *"is not optional"*. `IS_BARE` / `IS_IN_WORKTREE` are computed once at
   script-source time, so an already-poisoned worktree refuses **every** subcommand including
   `create` and `cleanup-merged` — the very commands that would run the Phase 3 repair. Without
   Phase 5 that is a permanent catch-22 with no automated exit, on a plugin whose users are
   explicitly non-technical.
2. `spec-flow-analyzer` verified against the script that `create_draft_pr` (`:2419`) calls
   `require_working_tree` and never `ensure_bare_config`. **`draft-pr` is the subcommand the issue
   was filed against.** Phase 5 is the only phase reachable from it. Cutting Phase 5 means shipping
   a fix that does not fix the reported symptom.
3. The "no surviving entry point" premise is scoped to *this repo*. Nothing proves herdr, the
   Concierge runtime, or an operator's own hand never runs `git config extensions.worktreeConfig
   true`. Phase 3's defensive `--unset-all` and Phase 5's self-heal defend the one channel an
   outside actor can reach.
4. `architecture-strategist` explicitly endorsed the two-ADR structure as "architecturally sound
   and appropriately scoped", against the fold-in half of the proposal.

**If the operator disagrees:** the cheapest partial concession is Phase 4 alone (keep Phase 5).
Phase 4 is prophylactic and does not backfill the fourteen existing worktrees anyway — its value is
forward-only immunity for tool-created worktrees. Phase 5 should not be cut without also accepting
that `draft-pr` stays broken on a poisoned worktree.

---

## DC-2 — The plan reverses the direction the issue proposed (`decisionClass: user-challenge`)

**The challenge.** Issue #7394 proposes *unblocking* the existing surgery so it can run (ending at
"extension on, `core.bare` in `config.worktree`" — measured row 5). The plan **reverses** that,
normalizing instead to "extension absent, `core.bare` stays in the shared config" (row 1), and
retires the issue's own hand workaround (`--unset core.bare`) as unsafe.

This changes the operator's stated direction, so it is surfaced rather than applied silently.

**Evidence for the reversal:** row 5 is a correct *steady* state, but reaching it from where the
repo stands today transits **through row 3** — the exact state that took fourteen worktrees down on
2026-08-09. The reversal dissolves the hazard window by construction instead of sequencing around
it. Separately, the `git worktree add` corruption that justified writing the extension in the first
place is **not reproducible** on git 2.53.0 (fact 3), so the key's original justification is gone.
And the issue's hand workaround is measured (fact 7) to make the bare root report as a normal
working tree, flipping `IS_BARE` at the root.

**`cpo` sign-off assessment:** APPROVED — judged a technical implementation-state decision rather
than a product one (no user-visible behaviour, pricing, or roadmap change), and judged
well-evidenced (5-row matrix, independently re-measured, explicit `## Alternatives Considered`
carrying the issue's approach as option A). Noted that the plan flags the reversal openly in a
"**The design turn**" paragraph rather than smuggling it through.

**Operator action:** none required if you agree. This entry exists so the reversal is a decision you
made, not one that happened to you.
