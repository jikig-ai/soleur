---
date: 2026-06-16
category: workflow-patterns
module: operations/expenses, finance/cost-model, ship/SKILL.md, AGENTS
tags: [expense-ledger, cost-model, ship-gate, agents-budget, derived-doc-refresh]
branch: feat-one-shot-record-resend-pro-expense-and-ledger-gate
pr: 5408
---

# Learning: recording a missed recurring-vendor expense + closing the ledger gap

## Problem

A merged PR (the 2026-06-15 outbound-email go-live, #5325 / #5365) subscribed us to the
Resend Pro plan (~$20/mo) by adding a second sending domain (`outbound.soleur.ai`), but the
cost was never recorded in `knowledge-base/operations/expenses.md`. The operator caught it
manually. Two-part fix: (1) record the expense + refresh the downstream cost-model, (2) add
a workflow gate so a recurring vendor cost cannot slip past `gh pr ready` again.

## Key Insights

### 1. Refreshing a derived financial doc means re-deriving EVERY downstream figure — and dated review notes are immutable

The plan's acceptance criterion was `grep -c '121.08' cost-model.md returns 0`. That was
**wrong**: `121.08` appeared 6 times, two of them inside dated historical review notes
(`[2026-06-02 Review note]`, `[2026-06-11 Review note]`) that are point-in-time records and
must NOT be rewritten. Blindly satisfying the AC would have corrupted the audit trail.

Adding one $20 COGS line cascaded far beyond the subtotal: Product COGS 121.08→141.08,
all-in 531.08→551.08, **all-in gross break-even 11→12 users** (⌈551.08/49⌉), four margin
figures (§5), the §4 Stripe-fee-drag narrative (gross and net now both round to 12, closing
the prior one-user gap), and the §6 Pricing-Gate prose. The correct pattern (matching the
existing 2026-06-02 / 2026-06-11 notes): **append a new dated review note** documenting the
before→after transition, re-derive every dependent figure with `bc`/`python3`, and leave
prior dated notes untouched. Verify with `grep -nE '<old-figure>'` and confirm every
surviving hit is inside a dated review note.

### 2. Before adding a ship Phase 5.5 gate, grep for an existing sibling gate

The plan said to model the new "Recurring-Vendor-Expense Gate" on the Undeferred
Operator-Step Gate and add it after that gate. But `ship/SKILL.md` Phase 5.5 already had a
**COO Expense-Tracking Gate** — a soft, advisory gate that spawns the COO agent and
recommends ledger updates. Adding a second expense gate blind would have read as a
duplicate. Resolution: position the new gate as the **deterministic-blocking counterpart**
(COO gate discovers/recommends; new gate blocks-before-ready), place it adjacent to the COO
gate, and cross-reference both. Always `grep -nE '^### .*Gate' <skill>` for siblings before
adding a new gate.

### 3. A gate-prescription bash block must be self-contained

The first draft of the new gate's detection bash referenced `$PR_BODY_FILE` "from the
sibling gate's stripper" — but the sibling gate that defines `$PR_BODY_FILE` lives ~360
lines LATER in the file. Executed in document order, the variable is unset, the grep reads
an empty path, and `|| true` swallows it → the gate **silently no-ops** (the exact
silent-bypass class the sibling's fail-closed awk was built to prevent). Multi-agent review
(pattern-recognition) caught it. Fix: each gate's bash captures + fence-strips the PR body
itself (fail-closed on unbalanced fence), never depending on a variable defined elsewhere in
the same SKILL.md.

### 4. At-cap AGENTS budget: trim rationale prose, preserve provenance

B_ALWAYS was 22994/23000; the new 65-byte index pointer would have pushed it to 23059
(hard lint FAIL). The lever (#4599 / #5349): trim ≥65 bytes of **rationale prose** from core
rule `**Why:**` tails — never directive prose, and never drop the `#issue` / learning-date
provenance. Two trims (`hr-bulk-delete-...`, `hr-no-dashboard-...`) freed ~95 bytes; net
B_ALWAYS fell to 22964. A new wg-* rule body lives in `AGENTS.rest.md` (not core, so it
doesn't count toward B_ALWAYS) and must stay ≤600 bytes per the per-rule cap.

## Session Errors

1. **Edit-before-Read on expenses.md** — Recovery: Read the file first. Prevention: injected
   system-reminder file content is not a tool Read; always Read before Edit. (one-off)
2. **`git stash list` denied by `hr-never-git-stash-in-worktrees`** — Recovery: dropped it.
   Prevention: probe stash with `git rev-parse --verify --quiet refs/stash`. (already
   hook-covered)
3. **AGENTS.rest.md body exceeded the 600-byte cap (716→616→584)** — Recovery: trimmed twice.
   Prevention: measure body bytes (`len(line.encode())`) before running the budget lint. (recurring)
4. **Push rejected (non-fast-forward) after rebase** — Recovery: `git push --force-with-lease`.
   Prevention: expected when a branch with an existing remote draft-PR is rebased. (one-off)
5. **Plan AC `grep -c '121.08' == 0` was wrong** — Recovery: re-derived all figures, preserved
   dated review notes. Prevention: Insight #1. (recurring)
6. **Plan didn't account for the existing COO Expense-Tracking Gate** — Recovery: positioned as
   the blocking counterpart. Prevention: Insight #2. (recurring)
7. **New gate bash referenced `$PR_BODY_FILE` defined 360 lines later (silent no-op)** —
   Recovery: made self-contained, caught at review. Prevention: Insight #3. (recurring)
