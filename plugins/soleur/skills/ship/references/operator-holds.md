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
Envelope: <path>[#<title>]

- Hold: <the operator's words, verbatim>
  Gate: pr-merged <N>
  Gate: no-inflight-run <workflow-file>
- Hold: Operator-reserved: <a decision only the operator may make, in their words>
```

**A gate says WHEN a hold's condition is true, never WHO the hold is reserved to.** Some holds reserve a decision to the
operator ("do not release until Dana approves the pricing page copy", brand copy, spend). A gate such as `pr-merged 1`
can be true while that approval has not been given, so such a hold must not carry a discharging gate at all. Write it as
`- Hold: Operator-reserved: <words>`. A hold whose words BEGIN with `Operator-reserved:` (any case) always STANDS: the
evaluator prints `Reserved for you: <words> - only you can clear this`, does not probe its gates, and exits 2. It is cleared
only by the operator saying so, and the CTO then removes or rewrites the line. Words in the middle of a hold do not reserve
it.

The grammar has two kinds, `pr-merged` and `no-inflight-run`. `command` and `run-green` are deferred: the first real
consumer re-adds them, and only by CTO ruling. A `Gate:` line of any other kind is an unknown kind, and the hold stands.

Rules the evaluator applies to this section:

- **The heading** is `Operator Holds` at level 2, 3 or 4, in any case. EVERY `Hold:` or `Gate:` line in the file (fenced
  examples excepted) must sit inside such a section. One that does not (a heading of another level, a misspelling, a second
  misspelt section, text under the next heading, no section at all) is exit 2, never the all-clear and never silently
  dropped, even when another section reads fine.
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
| 1 | At least one hold STANDS (a gate is false, or the delegation is invalid) | Stop and name that condition, in one plain sentence to the operator |
| 2 | A hold could not be evaluated or is reserved to the operator (unknown gate kind, unreadable probe, unreadable delegation, no `Envelope:` line, two `Delegation:` lines, a hold outside a readable section, a section that parses to zero holds, no time-limit tool, an `Operator-reserved:` hold) | It STANDS. Say so in one plain sentence; never retry it into a pass |
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
token itself. The evaluator adds two tokens of its own: `no-answer` (the verifier printed nothing, or timed out) and
`verifier-error` (its exit status and its first line disagree); for both say "I could not get a clear answer when I checked
your standing approval, so I have not done anything."

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

Evaluate at the draft exit AND again immediately before arming, through the same command
(`hold-gate-eval.sh --plan <plan file>`; any exit other than 0 stops the arming). The second look runs BEFORE the plan is
archived (Phase 6.45), because after archiving the plan file is no longer at its live path and the evaluator would answer 2. A predicate such as `no-inflight-run` is true only at
that instant: a run that starts between the two looks makes the hold stand again.

All conditions discharged ⇒ continue. The merge remains gated by review having run (`rf-never-skip-qa-review-before-merging`)
and by the required checks; those are the merge authority, not the hold. Any condition unmet ⇒ stop and name **that
condition** ("the earlier change has not gone live yet"), never "the change is not ready".

A delegated act (a merge or dispatch the CTO ran under the delegation) leaves a receipt: one comment on the epic whose first
line is `<!-- soleur-delegated-act v1 delegation=<url> envelope=<path> sha256=<verified-envelope-sha256> result=ok|rolled-back run=<url|none> -->`
(format: [standing-delegation.md](../../brainstorm-techniques/references/standing-delegation.md) section 8). After each delegated
act the CTO ALSO records the row `Authorized by delegation <url>, envelope <path>, ran <ISO UTC time>` (class
`operator (production-mutating)`) in `decision-challenges.md`: that row is what makes the receipt check fire, because the
gate cannot know about an act no row names. The ship gate then requires the receipt, and stops the ship with
`receipt-missing` (none left for that delegation; one receipt satisfies one row), `receipt-mismatch` (one exists but not for
that envelope, fingerprint, result or author, or it was edited, posted by a bot, written outside the delegation's life or
dated in the future) or `receipt-unreadable` (the epic's comments could not be read); see
[decision-challenges-render.md](./decision-challenges-render.md). Do not edit the envelope file after the act: the receipt
carries the fingerprint of the whole committed file, so a later edit makes the receipt mismatch.

**Why:** PR #7470 — a hold transcribed as "the PR stays a draft" outlived its cleared conditions. The mechanical evaluator
exists because prose re-evaluation by the model is the failure mode a hold guards against (CTO ruling T4, ADR-288).

## 5. What the evaluator prints

When a delegation was checked, its verdict line comes first (`delegation: valid reason=ok`, or the failing state and
reason). Then one plain line per hold (`Done:`, `Still waiting:`, `Needs a person:` or `Could not check:`, each with the
hold's own words and a plain reason) and a final machine line `holds: N discharged: M standing: K`. The human lines carry no
jargon; the evaluator's suite checks them against a jargon denylist (the two machine lines are excluded). Control characters,
bidi marks and line separators in a hold's words are stripped before they are printed.
