# Operator Holds — evaluating a recorded hold at the draft exit and again before arming

Procedure behind `/ship` Phase 6 step 5. A recorded operator HOLD is a condition, not an outcome. It is evaluated by
evidence, from the plan file, never from conversation and never by re-reading prose.

## 1. Where holds live

If the operator asked to hold ("wait for the earlier change", "after the soak", "once the migration applies"), record it
in the plan file under `## Operator Holds` the moment it is given. A hold that lives only in context is gone after
compaction and was never present when `soleur:ship` is invoked standalone (entry via `soleur:plan` or `soleur:work`), and
"no hold in context" is then indistinguishable from "no hold was given" — the reports-clean-because-it-could-not-look shape
this gate exists to end. If the plan file is unreachable, say so and stop; never read its absence as an all-clear.

Format (the `Gate:` grammar is defined once, in
[standing-delegation.md](../../brainstorm-techniques/references/standing-delegation.md) section 3):

```text
## Operator Holds

Delegation: <comment url>
Envelope: <path>

- Hold: <the operator's words, verbatim>
  Gate: pr-merged <N>
  Gate: no-inflight-run <workflow-file>
```

The operator's wording stays beside the gates so a gate that weakens a hold is visible in review. Whether a gate
faithfully encodes a hold is the CTO's authoring and review's check; the evaluator only measures the gate.

## 2. Evaluate

Run, from the repository root:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/hold-gate-eval.sh" --plan <plan file>
```

| Exit | Meaning | Action |
|---|---|---|
| 0 | Every hold is discharged, or none is recorded (an absent or empty section is a no-op) | Continue to Phase 6.45 and the arming in Phase 6.5 |
| 1 | At least one hold STANDS | Stop and name that condition, in one plain sentence to the operator |
| 2 | A hold could not be evaluated (unknown gate kind, unreadable probe, unreadable or revoked delegation, a section that parses to zero holds) | It STANDS. Say so in one plain sentence; never retry it into a pass |
| 3 | No delegation is recorded | Evaluate by hand per section 3 |

A hold with no `Gate:` line is reported "Needs a person": route it to the Undeferred Operator-Step Gate rather than
improvising a gate. A condition only a human can settle (a subjective call, an external party) is a genuine operator gate,
because a PR body is not an operator-visible surface. The standing delegation is verified first, through
`plugins/soleur/scripts/delegation-verify.sh`; anything but `valid` leaves every hold standing, and the gates are not probed.

Record each hold's verdict line and the command that produced it in the PR body, so a discharge is auditable and "three
conditions probed green" is distinguishable from "no conditions found".

## 3. No delegation recorded (exit 3): the prose path

Evaluate each condition now. A sibling change is `MERGED` **and** `git merge-base --is-ancestor <its-sha> HEAD`; a named
verification is green **on the current tree** (re-run it — an inherited "it was green" describes a tree that may no longer
exist); a state change (migration applied, flag flipped) is confirmed by probing the state, not by assuming the step ran.
**If you cannot evaluate a condition — for any reason, including a failed probe — the hold STANDS.** Scope that rule
precisely: if `## Operator Holds` is absent or empty, no hold was recorded and the step is a no-op. It is only once a hold IS
recorded that an empty or unevaluated condition set must never be treated as discharged. A hold recorded with no stated
test is not dischargeable here either.

## 4. Timing: twice

Evaluate at the draft exit AND again immediately before arming in Phase 6.5, through the same command. A predicate such as
`no-inflight-run` is true only at that instant: a run that starts between the two looks makes the hold stand again.

All conditions discharged ⇒ continue. The merge remains gated by review having run (`rf-never-skip-qa-review-before-merging`)
and by the required checks; those are the merge authority, not the hold. Any condition unmet ⇒ stop and name **that
condition** ("the earlier change has not gone live yet"), never "the change is not ready".

**Why:** PR #7470 — a hold transcribed as "the PR stays a draft" outlived its cleared conditions. The mechanical evaluator
exists because prose re-evaluation by the model is the failure mode a hold guards against (CTO ruling T4, ADR-288).

## 5. What the evaluator prints

One plain line per hold (`Done:`, `Still waiting:`, `Needs a person:` or `Could not check:`, each with the hold's own
words and a plain reason) and a final machine line `holds: N discharged: M standing: K`. The human lines carry no jargon;
a test checks them against the same denylist as the confirmation wording.
