---
title: "I shipped two unmeasured causal claims inside the header of the lint that forbids them"
date: 2026-08-06
category: workflow-patterns
module: CI
issue: 7310
pr: 7315
filed: 7318
tags: [adr-166, guard-building, mutation-testing, inherited-framing, fixture-axes, measurement-discipline]
---

# Learning: I shipped two unmeasured causal claims inside the lint that forbids them

## Problem

#7310 widened `scripts/lint-diagnosis-claims.sh` — the ADR-166 gate whose whole thesis is
*an operator-facing CI message may not name a cause the job did not measure* — to scan
`apps/web-platform/infra/`, plus one `CLAIM` regex alternative for the `X is the fix` shape.

The code was correct. The **prose I wrote into the lint's own header** contained two causal
claims I had not measured, and a five-agent review caught both.

## The two claims

**1. "one of them spent a production-recovery window telling the operator…"**

Measured refutation, from `gh` timestamps:

| Event | Time |
|---|---|
| #7280 merged — the strip was applied | 2026-08-05 **08:18Z** |
| **#7287 opened** | 2026-08-05 **08:38Z** |
| #7283 merged — the message reached `main` | 2026-08-05 **14:40Z** |

#7287 predates the message on `main` by six hours, so it cannot have been mis-steered by it.
I had inferred an operator incident from issue archaeology and written it in the past tense.
What the record *does* support is narrower and still worth saying: a false hard-blocker stood
on `main` for ~10.5 h prescribing a remedy applied 6 h earlier, and unwinding it took two PRs.

**2. "~70 operator-facing shell gates that no lint read"**

False. `scripts/lint-trap-tempfile-ownership.py` walks **all 166** tracked `.sh` files there
via `git ls-files "*.sh"` and runs in CI at `ci.yml:174`. The true statement is "no lint read
it *for this rule class*."

## The mechanism worth naming: inherited framing

Claim 2 did not come from nowhere. ADR-166's Consequences section says `.github/actions/**`
"was unlinted by every other tool here" — **true of that directory**. I reused the sentence
shape for a different directory without re-checking its premise.

> A framing inherited from a sibling artifact is a claim about the context it was written
> for, not about the context you paste it into. The words survive the move; the evidence
> does not.

This is the prose sibling of the plan-quoted-number rule. We already re-derive inherited
*numbers*; inherited *sentences* get no such treatment, and they are the ones that read as
established because they were established — somewhere else.

The cheapest gate is the one the lint itself implements: for each causal or universal claim
in the diff's prose, name the command that would falsify it, and run it. `gh pr view --json
mergedAt` and `grep -n ls-files` were the two commands here, ~15 seconds total.

## Second theme: my mutation battery could not reach any of the real defects

I ran a battery before review and it reported every mutation caught. It perturbed the **SUT**
(the `DIRS` entry, the `CLAIM` alternative). Every axis that was actually broken lived in the
**fixtures**:

| Axis | Mutation | Result before review |
|---|---|---|
| fixture LOCATION | relocate the fixture out of `apps/web-platform/infra/` | **survived 12/12** |
| fixture DIRECTION | drop either `\b`, drop both, open the adjective slot | **survived ×4** |
| assertion COUNT | delete the PR's own new assertion | **survived** (`MIN_ASSERTIONS=9` vs a 12-assertion suite) |
| harness DISPATCH | `assert_eq` → `if true` | **survived** (12 passed, exit 0, every comparison disabled) |

The fixture-location one is the sharpest. My assertion was `census_of == 1` — a **cardinality**
claim. It reads as pinning "an offender in this directory trips the lint" and pins only "some
offender somewhere trips the lint." My revert-DIRS control reddened purely because the fixture
*happened* to live in the directory; nothing asserted that it did. So the property held on the
day and was unenforced from the next commit onward.

> When a test's description names a **place** or a **kind**, and its assertion is a **count**,
> the description is prose and the count is the contract. Assert the identity.

Generalization of the battery point, which the repo has now hit from several directions:
**ask which LAYER each mutation edits.** N mutations of the implementation is one axis however
many rows the table has. See [[2026-08-01-my-mutation-battery-inferred-the-verdict-from-the-input-under-test]],
[[2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it]],
and [[2026-08-05-every-green-signal-certified-something-other-than-what-it-claimed]].

## Third: a floor left trailing its population re-opens the hole it guards

`MIN_ASSERTIONS=9` against a suite that had grown to 12. I updated the *comment* from 11 to
12 and left the *value* — so the anti-vacuity floor could not see the deletion of the very
assertion this PR existed to add. Raised to the full current count (17), still `-lt` so adding
assertions stays free and only deletion reds.

Same shape one file over: `MIN_FILES` is a floor over the **total**, so it cannot detect
per-directory scope loss. Measured — renaming the `DIRS` entry to `infras` dropped all 71 of
its files and still printed `OK — 1 unmeasured causal claims`. A floor over a sum can never
answer a question about a member; the fix is a per-entry `os.path.isdir` hard-error.

## Fourth: a test that passes for the wrong reason

My first `partial_root` case for that scope guard used an **empty** tree. Empty trees exit 2
via the *vacuity* floor whether or not the scope guard exists — so deleting the guard left the
case green. It needed a real file, so that its exit 2 could only come from the missing
directory. Verified by mutation both ways.

The same error in a different key: my plan's risk row claimed the `MIN_FILES` floor had "no
interaction" with the widened walk, citing the floor firing on an **empty root**. Empty-root
was never the case at issue. I verified a proposition adjacent to the one I asserted.

## Fifth: the scope sweep's unit is the claim, not the file

I reasoned correctly that the lint's `SCOPE.` header and its `DIRS` comment both enumerate the
scanned directories and must move together — then applied that only *within the file*, leaving
`ADR-166:93` (the normative document the lint enforces) and a post-mortem still asserting the
old three-directory scope. Extends [[2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim]];
the novelty is that the sweep principle was *stated in the plan* and still scoped to one file.

## What went right, and is worth copying

The review measured rather than argued about regex breadth. The open adjective slot
`(?:[a-z]+ )?` costs **+2** (a prior-art citation and a separate real offender); the closed
enumeration costs **+0**. That turned a taste debate into a table. It also surfaced the real
defect in my narrow form: one intervening word defeated it, so the *hedged* `is the likely
cause` was caught (by a pre-existing alternative) while the *confident* `is the root cause`
was not — the asymmetry ran exactly the wrong way.

One agent also **withdrew its own finding** mid-review as an unmeasured causal attribution.
That is the behaviour the ADR asks for, performed on the reviewer's own output.

## Session Errors

1. **Planning subagent died twice on `API Error: Connection closed mid-response`** (forwarded
   from `session-state.md`). Recovery: verified no partial artifacts, resumed once via
   `SendMessage`, then took the documented inline fallback. **Prevention:** already covered by
   one-shot's partial-artifact recovery path; no rule change needed.
2. **Two unmeasured causal claims in the lint header** (above). **Prevention:** for each causal
   or universal claim in a diff's prose, name and run the falsifying command. Routed to
   `plugins/soleur/skills/compound/SKILL.md` as an inherited-framing bullet.
3. **A gloss presented in quote marks** as text from #7287; the string appears nowhere in it.
   **Prevention:** quote marks are a claim about provenance — `gh issue view N | grep -F` it or
   drop the quotes.
4. **`#7247` cited where `#7242` was correct.** **Prevention:** `gh issue view` every `#N` before
   it lands in prose.
5. **`11/11` for a 10-row table; `~99` for exactly 100.** **Prevention:** counts in prose get
   re-derived from the artifact, never from memory of writing it.
6. **`cq-test-fixtures-synthesized-only` miscited** — it is secrets hygiene, not fixture
   construction. **Prevention:** read the rule body before citing its id.
7. **Called the issue's AC set "mutually exclusive"** when #7310 is internally consistent and
   the deviation was mine. **Prevention:** when a plan deviates from an issue, the reconciliation
   row says "this plan deviates", never "the issue contradicted itself".
8. **AC2 was vacuous** — its bare-literal `grep -cF` returned 1 on a file with the regex line
   *deleted*. **Prevention:** already `cq-assert-anchor-not-bare-token`; the new instance is
   that the collision appears the moment a task requires both asserting X and documenting X.
9. **`MIN_ASSERTIONS` comment updated, value left behind** (above).
10. **`partial_root` passed for the wrong reason** (above).
11. **Mutation anchor not unique** — an `M1` replacement matched 2 sites and silently did not
    apply on the first attempt. **Prevention:** assert `count == 1` before replacing; a
    mutation that does not land reports the baseline, which is indistinguishable from a pass.
12. **The harness self-check printed a misleading `FAIL:` line** that was not a failure.
    **Prevention:** silenced both probes; a `FAIL` in a log that is not a failure is this
    lint's own defect class.
13. **Probe copies initially reported `walked 0 files`** because `REPO_ROOT` resolves from the
    script's own directory. Self-corrected via `LINT_DIAGNOSIS_ROOT`. One-off.

## Recurring-vs-one-off triage

| Item | Recurring? | Disposition |
|---|---|---|
| Unmeasured causal claims in own prose (2) | recurring | fix-now-inline + route to compound |
| Inherited framing not re-checked (2) | recurring | route-to-definition |
| Fixture-axis blindness in self-run batteries (9–11) | recurring | route to review skill; cross-link existing learnings |
| Floor trailing its population (9) | recurring | fixed inline; pattern already in review SKILL.md |
| Test passing for the wrong reason (10) | recurring | fixed inline |
| Citation/count slips (3–6) | recurring | one prevention bullet, not five |
| Subagent API drops (1) | one-off | already handled by the documented fallback |
| Probe `REPO_ROOT` confusion (13) | one-off | none |

## Related

- [[2026-08-06-a-wrong-measurement-propagated-into-three-artifacts-and-my-fix-reproduced-its-defect]] — the sibling issue (#7299/#7300) that removed the very message this PR's fixture now pins
- [[2026-08-06-the-gate-i-built-to-catch-a-blind-spot-had-the-same-blind-spot]] — same self-referential class, different mechanism (errexit)
- [[2026-07-20-i-swept-by-file-when-the-unit-of-truth-was-the-claim]]
- [[2026-08-01-my-mutation-battery-inferred-the-verdict-from-the-input-under-test]]
- ADR-166 — the decision this lint enforces
- #7318 — the deferred `OPERATOR_LINE` anchor gap plus the baseline-semantics/scope-default decision
