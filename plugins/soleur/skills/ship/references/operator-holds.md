# Operator Holds — evaluating a recorded hold at the draft exit and again before arming

Procedure behind `/ship` Phase 6 step 5. A recorded operator HOLD is a condition, not an outcome. It is evaluated by
evidence, from the plan file, never from conversation and never by re-reading prose.

**Plugin root in this file:** every command below is written with `${CLAUDE_PLUGIN_ROOT}`. If it is unset (cloud shells do
not export it), resolve it as the Cloud Mode paragraph of `ship/SKILL.md` does, never with a path relative to the checked-out
repository, which would run that repository's copy of the script.

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

The grammar has two kinds, `pr-merged` and `no-inflight-run`. `command` and `run-green` are deferred: the first real
consumer re-adds them, and only by CTO ruling. A `Gate:` line of any other kind is an unknown kind, and the hold stands.

Rules the evaluator applies to this section:

- **The heading** is `Operator Holds` at level 2, 3 or 4, in any case. A hold or a gate that sits outside a section it can
  read (a heading of another level, a misspelling, no section at all) is exit 2, never the all-clear.
- **`Delegation:`** appears at most once. Two lines are exit 2. **`Envelope:` is required** beside it, exactly once: a
  delegation with no runbook to check it against leaves every hold standing, because the verifier has nothing to compare the
  Scope with.
- **Markers** (`Hold:`, `Gate:`, `Delegation:`, `Envelope:`) are read in any case, with or without the list dash and with a
  space before the colon. A line inside a code fence is an example and is ignored; only a fence of the same character, at
  least as long, closes it.
- A hold with no `Gate:` line is "Needs a person" (section 2).

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
| 2 | A hold could not be evaluated (unknown gate kind, unreadable probe, unreadable or revoked delegation, no `Envelope:` line, two `Delegation:` lines, a hold outside a readable section, a section that parses to zero holds, no time-limit tool) | It STANDS. Say so in one plain sentence; never retry it into a pass |
| 3 | No `Delegation:` line is recorded: legacy prose holds | Evaluate by hand per section 3 |
| any other status (127 script not found, 124 timed out, 137 killed) | The check did not run | Treat it as 2: the hold STANDS and was not checked. Say so; never read it as a no-op |

Exit 3 is decided before every other structure and tool check, so a plan written in the earlier prose format keeps the prose
path whatever else it contains.

A hold with no `Gate:` line is reported "Needs a person": route it to the Undeferred Operator-Step Gate rather than
improvising a gate. A condition only a human can settle (a subjective call, an external party) is a genuine operator gate,
because a PR body is not an operator-visible surface. The standing delegation is verified first, through
`${CLAUDE_PLUGIN_ROOT}/scripts/delegation-verify.sh` (its exit status AND its first line must both say valid); anything else
leaves every hold standing, and the gates are not probed. When it does not verify, the evaluator's first line is the
verifier's verdict, `delegation: <invalid|unverifiable> reason=<token>`. Say the plain sentence for that token from
[standing-delegation.md](../../brainstorm-techniques/references/standing-delegation.md) section 7 (Reason tokens), never the
token itself.

Record each hold's verdict line and the command that produced it in the PR body, so a discharge is auditable and "three
conditions probed green" is distinguishable from "no conditions found". A `Done:` line carries the gate text that was true
(`Done: <the hold> - checked: pr-merged 55; no-inflight-run example-release.yml`), so the PR body shows which evidence
discharged which hold.

## 3. No delegation recorded (exit 3): the prose path

Evaluate each condition now. A sibling change is `MERGED` **and** `git merge-base --is-ancestor <its-sha> HEAD`; a named
verification is green **on the current tree** (re-run it — an inherited "it was green" describes a tree that may no longer
exist); a state change (migration applied, flag flipped) is confirmed by probing the state, not by assuming the step ran.
**If you cannot evaluate a condition — for any reason, including a failed probe — the hold STANDS.** Scope that rule
precisely: if `## Operator Holds` is absent or empty, no hold was recorded and the step is a no-op. It is only once a hold IS
recorded that an empty or unevaluated condition set must never be treated as discharged. A hold recorded with no stated
test is not dischargeable here either.

**Headless** (`HEADLESS_MODE=true`, no TTY, `soleur:one-shot`, `soleur:go --headless`): nobody can be asked for a standing
delegation, so none exists and every production act stays a hold. Do not ask. File ONE `action-required` issue that names the
ACTION (what the operator is being asked to approve, in plain words), print one plain sentence, and continue to the draft PR.

## 4. Timing: twice, and the receipt after a delegated act

Evaluate at the draft exit AND again immediately before arming in Phase 6.5, through the same command
(`hold-gate-eval.sh --plan <plan file>`; exit 1 or 2 stops the arming). A predicate such as `no-inflight-run` is true only at
that instant: a run that starts between the two looks makes the hold stand again.

All conditions discharged ⇒ continue. The merge remains gated by review having run (`rf-never-skip-qa-review-before-merging`)
and by the required checks; those are the merge authority, not the hold. Any condition unmet ⇒ stop and name **that
condition** ("the earlier change has not gone live yet"), never "the change is not ready".

A delegated act (a merge or dispatch the CTO ran under the delegation) leaves a receipt: one comment on the epic whose first
line is `<!-- soleur-delegated-act v1 delegation=<url> envelope=<path> sha256=<fingerprint> result=ok|rolled-back run=<url|none> -->`
(format: [standing-delegation.md](../../brainstorm-techniques/references/standing-delegation.md) section 8). The ship gate
requires it for any decision-challenges row that says the act ran; see
[decision-challenges-render.md](./decision-challenges-render.md).

**Why:** PR #7470 — a hold transcribed as "the PR stays a draft" outlived its cleared conditions. The mechanical evaluator
exists because prose re-evaluation by the model is the failure mode a hold guards against (CTO ruling T4, ADR-288).

## 5. What the evaluator prints

When a delegation was checked, its verdict line comes first (`delegation: valid reason=ok`, or the failing state and
reason). Then one plain line per hold (`Done:`, `Still waiting:`, `Needs a person:` or `Could not check:`, each with the
hold's own words and a plain reason) and a final machine line `holds: N discharged: M standing: K`. The human lines carry no
jargon; the evaluator's suite checks them against a jargon denylist (the two machine lines are excluded). Control characters,
bidi marks and line separators in a hold's words are stripped before they are printed.
