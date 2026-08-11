---
title: "ADR-180: Guard Contract as a plan-time deliverable"
date: 2026-08-11
---

# ADR-180: Guard Contract as a plan-time deliverable

## Status

Accepted (2026-08-11)

## Context

The preflight Check 10 execution-boundary work (merged 2026-08-10) shipped a
bubblewrap sandbox plus a verb allowlist for a check that executes
attacker-authorable commands on the operator's workstation. It absorbed **five**
adversarial review rounds. Every round found real defects **inside the previous
round's fixes**, and roughly twenty findings reduce to a single class:

> A guard's WINDOW, CHOKEPOINT, or IDENTIFIER SET was narrower than the property
> it named.

The instances:

- The mount-set closure assertion scoped to `BWRAP_ARGS=( … )` via a
  `sandboxWindow()` helper, while `GIT_BIND`, `BWRAP_PROC` and the exec line ALSO
  injected mounts. Three separate one-line edits each re-opened the operator's
  credential surface **with the whole suite green** — verified against live bwrap
  reaching the Doppler token, `~/.ssh` and the gh token store.
- A parity floor counting ITERATIONS rather than distinct shapes.
- A suppression grep anchored on `test` / `it` / `describe`, which are rebindable
  (`const it = test.failing;` — and bun scores a failing `.failing` test as a
  PASS).
- An anti-vacuity gate with **no floor on its own dispatch**: neutering
  `pass()`/`fail()` printed "0 passed, 0 failed" and exited 0.

Those were not five independent discoveries. They were **one enumeration nobody
performed**, found five times by different means, at roughly 880k subagent tokens
and five CI cycles.

The root cause sits at plan time, not review time. That plan specified CONTROLS
("a bubblewrap sandbox with these mounts") and thirteen Test Scenarios all of the
shape "command X produces terminal Y". **Zero** had the shape "mutation M drives
guard G red". For a change whose deliverable WAS guards, the test scenarios
exercised the thing being guarded rather than the guards themselves. So the
guards were written as assertions about the implementation as it happened to be
shaped, and `sandboxWindow()` — a helper invented at work time — silently became
the operative definition of "the mount set".

Review-time countermeasures are structurally poor at this class. Adversarial
seats sample a defect space, which is right when defects are independent; here
every defect was the same one, so four agents found four instances and none
produced the enumeration that would have yielded all four at once.

## Decision

**When a plan's deliverable includes a guard, gate, lint, drift-check or
anti-vacuity control, the plan MUST carry a `## Guard Contract` section with one
entry per guard, and the entry MUST be written before the guard is.**

Each entry carries three fields:

1. **Property** — the invariant in one sentence.
2. **Assembly** — every code path, array, file and call site the property
   quantifies over. **Members drift; assembly is structural.** An "assembly"
   enumerated as the list of current members is a snapshot, and the next one-line
   edit invalidates it while the suite stays green. Name the chokepoint the
   members must flow through — and if there is more than one, say so.
3. **Mutation matrix** — at least three edits that MUST drive the guard RED,
   derived from the DESIGN rather than from the implementation as it happens to
   be shaped. At least one row targets the guard's **own dispatch**; at least one
   adds a **second** member after a compliant first.

Enforcement is layered, deliberately:

| Layer | Mechanism | Catches |
|---|---|---|
| Plan | `plan/SKILL.md` §2.12 + the template | Absent contract |
| Design-time verify | `deepen-plan/SKILL.md` §4.11 halt | Members-not-structure assembly; design-derived vs code-derived matrix |
| Mechanical | `scripts/lint-guard-contract.py` | Missing/placeholder fields, matrix under 3 rows, zero entries |
| Work | `work/SKILL.md` class-scoped fix rule | Fixing the instance the finding named instead of the class |
| Review | `review/SKILL.md` structural-enumeration seat | A path outside the guard's window |

The review seat **replaces** an adversarial seat rather than adding to the panel:
the goal is a cheaper panel, not a larger one.

## Alternatives Considered

- **Document the class as another learning.** Rejected. `review/SKILL.md` already
  documented it, and its own guidance states the disposition for a recurring
  documented class is a mechanical gate, not another learning. The class recurred
  anyway.
- **Put the rule in `AGENTS.rules.md`.** Rejected on two grounds that agree: the
  insight is domain-scoped and belongs in the owning skills, and the rule corpus
  was at WARN (`B_ALWAYS=44478` against a 46000 ratchet).
- **A lint that verifies semantic completeness of a window.** Rejected as
  impossible — no static checker can decide whether a regex-extracted window
  equals the assembly it stands for. Claiming otherwise would make the gate
  itself an instance of the class. `lint-window-closure-assertion.py` therefore
  enforces a DECLARATION per helper and says so.
- **More adversarial review seats.** Rejected. Four independent agents finding
  four instances of one structural gap is evidence that seat allocation, not seat
  count, was the problem.

## Consequences

**Positive.** The enumeration happens once, at design time, when it is cheapest.
A guard-shaped plan cannot reach `/work` without naming what its guard quantifies
over. The mutation matrix gives `/work` a RED-first target list derived from the
design instead of from the code it is about to write.

**Negative.** Guard-shaped plans get longer, and the Assembly field is real work
that is easy to fill in badly — a members-list will pass the lint and fail the
purpose. That gap is why `deepen-plan` §4.11 Step 4 is a human/agent judgement
step rather than another regex.

**Scope note.** This ADR covers the contract. ADR ordinal allocation at ship time
— the sibling pipeline-friction fix from the same session — is deliberately split
to its own issue: its reference sweep is itself guard-shaped work whose failure
mode is a narrow window, so it deserves its own contract rather than riding along
here.

**Self-application, and what it cost.** The PR introducing this ADR carries a
`## Guard Contract` for its own three guards. Its first revision then failed its
own contract in all three: the rename guard treated gitleaks' per-rule allowlist
as a global boolean and exempted a real laundering rename; the Guard Contract
lint exited 0 having examined nothing, swept non-recursively, matched its section
heading by exact equality, and counted rows from any table in the entry; and the
window lint's identifier set was a rebindable naming convention that missed 247
test files outright.

Every one of those is the same class — a window narrower than the property it
names — found in the guards built to catch it. They were surfaced by the
structural-enumeration seat this ADR introduces, which produced the complete map
in one pass where four adversarial seats had each found fragments.

That is the strongest available evidence for the decision and the strongest
available warning about it: a Guard Contract makes the assembly writable and
reviewable, and it does not make it correct. The contract is a prompt for the
enumeration, not a substitute for performing it. Note also that not every
mutation row is a code deletion — some are fixture-space proofs, and one asserts
a GREEN outcome (a relocated fixture must still be found); the matrix records
what must change the verdict, not uniformly what must go red.
