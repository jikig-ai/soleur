# Decision Challenges — feat-one-shot-7190-7173-hook-input-contract-hardening

Persisted at plan time (headless one-shot pipeline — no interactive gate available).
`/ship` renders these into the PR body and files them as `action-required` issues.
Per ADR-084, the operator's stated direction is the default; these are surfaced, not applied.

---

> **Updated after deepen-plan.** A third reviewer (`security-sentinel`) reached the same
> split conclusion independently, and added a reason the first two did not have — see the
> "What changed at deepen-plan" block inside DC-1. DC-2 is **withdrawn**: its premise was
> refuted by measurement.

## DC-1 — Three independent reviewers now recommend splitting this into 2 PRs

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

### What changed at deepen-plan — this recommendation got materially stronger

`security-sentinel` and `test-design-reviewer` ran against plan v2 and **measured** rather
than reasoned. Twenty-two findings; two blocking. The relevant fact for this decision:

**Every blocking and high-severity finding lands in Phases 4–6. None touches Phases 1–3.**

- **F1 (blocking)** — the OpenHands mirror aborts on malformed JSON at rc 5 with no deny and
  no incident row, *before* its type check. The plan's v2 claim that the mirror had "no
  trust-boundary hole" was refuted by measurement. A lone surrogate in a sibling field
  induces it while the command itself stays a clean `rm -rf $HOME`.
- **F2 (blocking)** — the widened-slot design, as drafted, would let a non-string
  `.tool_input.content` disarm the skill-security scanner **silently** (no ask, no prompt),
  which is a regression against that hook's current posture.
- **F3, F4, F13** — three further design corrections in the same half.

The trust-boundary half therefore needs **another design pass and three more probes**
(OpenHands runtime semantics for a non-0/2 exit code; Claude Code's resolution order when
one hook emits `allow` and another emits `ask` on the same call; plus the two already
planned). Phases 1–3 need none of that: they were reviewed clean on substance, they touch
exactly one file, and they carry the exit-code assertion that is the single highest-value
item in either issue.

Holding #7190 behind that work is the concrete cost of the single-PR shape. That is the
whole of the argument — the decision remains yours.

---

## DC-2 — WITHDRAWN: #7173(b)'s premise was refuted by measurement

**Status: withdrawn at deepen-plan. No decision needed from you.**

This challenge asked whether discharging #7173(b) by documentation under-delivered against
an intent of convergence-as-such. It rested on the finding that all three mirror hooks
"already type-assert, so the gap is duplication rather than an absent assertion."

**That premise is false.** Measured: `.openhands/hooks/guardrails.sh` dies at line 19 on any
document jq rejects, before reaching its type check — no deny, no decision JSON, no incident
row (F1). And its `$t == null` conjunct is unsatisfiable, so it denies every payload with an
absent or null `tool_input` (F13). The mirror has both a bypass and an availability bug.

The plan's Phase 6.1 has been rewritten accordingly: the mirror is **fixed in this PR**
(6.1b explicit parse-failure branches, 6.1c the type-conjunct correction) with a runtime
probe (6.1a) preceding any ADR claim about exit-code semantics. Whether the mirror
additionally adopts the shared extractor remains the documented in-place decision, but it is
now a decision about *duplication* rather than one resting on a false safety claim.

Retained here as a record: the original DC-2 reasoning was sound given v2's facts, and it
was the measurement — not the argument — that moved.

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
