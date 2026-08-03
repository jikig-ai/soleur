# Decision Challenges — feat-one-shot-7190-7173-hook-input-contract-hardening

Persisted at plan time (headless one-shot pipeline — no interactive gate available).
`/ship` renders these into the PR body and files them as `action-required` issues.
Per ADR-084, the operator's stated direction is the default; these are surfaced, not applied.

---

## DC-1 — Both plan reviewers recommend splitting this into 2–3 PRs

**Your stated direction:** "Implement and ship #7190 and #7173 together — both harden the
ADR-156 hook-input trust boundary … and both touch `.claude/hooks/lib/hook-input.sh` and
`.claude/hooks/hook-input-contract.test.sh`, so they share a worktree and a PR."

**What the reviewers said:** `architecture-strategist` and `code-simplicity-reviewer`
independently reached the same conclusion, without being prompted to consider scope
together. Architecture called the split point "unusually clean"; simplicity independently
named the same boundary.

**The argument:**

- The two issues share *files*, but not *risk*. #7190 (Phases 1–3) touches exactly one
  file — `.claude/hooks/hook-input-contract.test.sh` — contains zero production code and
  carries zero trust-boundary risk. It delivers the six highest-value items including the
  exit-code assertion the plan identifies as its single most important finding.
- #7173 (Phases 4–6) modifies `lib/hook-input.sh` — by the plan's own reckoning the
  highest-blast-radius file in the change set — plus four hooks and possibly
  `.claude/settings.json`. A defect there disarms live guards on your machine.
- Coupling them means the low-risk, high-value half cannot merge until the high-risk half
  is reviewed. If #7173 hits a problem at `/work` (for example, the Phase 5.2 `ask`-honored
  probe comes back negative), #7190 is held hostage to it.
- The shared-file argument for coupling is weaker than it looks: the two halves touch the
  suite in disjoint regions, and #7190 landing first is what makes its assertions police
  #7173's migrations — which works across two PRs exactly as well as within one.

**Proposed split** (both reviewers, same boundary):

| PR | Phases | Closes | Risk |
|---|---|---|---|
| 1 | 0–3 | `Closes #7190` | One file, test-only |
| 2 | 4–6 | `Closes #7173` | ADR + helper + hook migrations + parity |

Architecture additionally suggested a third PR isolating the OpenHands work; the plan's v2
revision reduces that surface to a README rationale and two parity test cases, which
removes most of the motivation for a third split.

**What the plan does:** follows your direction — one worktree, one PR, both issues closed —
and is sequenced so the split remains available at the Phase 3/4 boundary if you want it at
any point before merge.

**If you want the split:** say so and the pipeline stops after Phase 3, ships PR 1, and
opens a second branch for Phases 4–6. Nothing in the plan needs rewriting; the phase
boundary is already the cut line.

---

## DC-2 — #7173(b) is discharged by documentation rather than by convergence

**Context:** #7173's title says "extend the ADR-156 type assertion to … the OpenHands
mirror," which reads as a mandate to converge the mirror onto the shared extractor.

**What was found:** all three mirror hooks (`guardrails.sh`, `pre-merge-rebase.sh`, and
`worktree-write-guard.sh` — which the issue does not mention) **already carry a working
type assertion**, with the `//` falsy-trap already avoided. The gap is code duplication,
not an absent assertion. Converging would buy DRY and 3–4 jq forks → 1 on a non-primary
harness, and would pay for it with a cross-tree fail-hard `source` that the plan rates as
the riskiest single line in the change set.

**What the plan does:** keeps the mirror on its in-place assertion and discharges #7173(b)
under the issue's own acceptance criterion 2 ("any hook that stays exempt keeps its reason
in the README"), while still authoring the ADR-158 D3 decision the issue actually asked for
("make that decision deliberately rather than as a side effect") and adding two executable
parity cases.

**Why you might disagree:** if your intent was convergence-as-such — one extractor, both
harnesses, duplication eliminated on principle — then Phase 6.1 under-delivers against that
intent and should be reopened. Say so and it becomes a Phase 6 implementation task rather
than a documented exemption.
