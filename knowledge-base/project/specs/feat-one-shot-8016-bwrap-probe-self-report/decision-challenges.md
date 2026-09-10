# Decision challenges — feat-one-shot-8016-bwrap-probe-self-report

Recorded at plan time under ADR-084 because this ran headless: taste and scope forks are surfaced,
never silently auto-applied. `/ship` renders these into the PR body and files them as
`action-required` where they need an answer.

## 1. Should the Article 30 register bracket ship in this PR? (scope, taste)

**Decision class:** taste. Two reviewers split on it, both with real arguments.

**Current plan position:** retained. `knowledge-base/legal/article-30-register.md` is in
`## Files to Edit` and Phase 6 appends one additive dated bracket to PA-8 §(g).

**Against (DHH).** The GDPR gate returned this at `Suggestion` severity and explicitly declined to
promote it. The plan then put the remedy in `## Files to Edit`, gave it its own phase and made it a
hard pre-merge acceptance criterion — which is the promotion it just declared it was not doing. The
substance is thin: the plan's own producer-corpus analysis concludes this is not personal data, and
the channel already carries `docker logs soleur-web-platform-canary --tail 30` **unsanitized**, so
the change is a strict *reduction* in unsanitized bytes per byte on that channel.

**For (Kieran).** Not creep. PA-8 §(g) already carries three dated `**[YYYY-MM-DD UPDATE (#N): …]**`
brackets, so the plan follows an established additive contract rather than inventing a ritual. The
three deferral costs the plan cites — #6474, #7455, #7500 — are all real, all closed, and all are
literally currency-correction work caused by a register lagging the code. One paragraph appended to
a file already in the neighbourhood is cheaper than an issue plus a triage plus a future PR plus a
re-derivation of the analysis.

**What changes if it is cut:** one file leaves the diff, one acceptance criterion goes, and the
net-issue-flow justification list loses nothing (the bracket is not a filing). Nothing in the code
change depends on it.

## 2. Plan length versus gate-mandated sections (taste)

**Decision class:** taste, and it is really a challenge to the gates, not to this plan.

Two reviewers argued that `## Encryption Posture`, `## Infrastructure (IaC)`,
`## Architecture Decision (ADR/C4)` and `## Domain Review` are ceremony for an eight-line shell
change: four sections whose content is a reasoned "not applicable". The counter-argument is
mechanical rather than aesthetic — `deepen-plan` halts on their absence, so removing them from this
plan would fail the next gate rather than save anything.

They have been compressed substantially rather than cut. If the operator agrees the ratio is wrong
for a change this size, the thing to change is the gate's trigger conditions (a size or
change-class predicate), not this plan.

## 3. Not a challenge, recorded so it is not re-litigated

Three things that *look* like taste forks and are not — each was settled by a measurement, and the
measurement is in the plan:

- **Whether to classify exit codes 125/126/127 in the blocking probe.** Settled against, but the two
  reasons an earlier draft gave were both false (bwrap does not use those codes; #5889's soak is
  closed, not pending). The surviving reason is #4932: branching on rc without an observed
  distribution rolled back every web-platform deploy once already.
- **Whether `<empty>` alone is enough.** Settled no — the probe emitted zero bytes in both observed
  occurrences, so `err=<empty>` would have named nothing. The exit code is the discriminator.
- **Whether to re-emit the captured output to stdout.** Settled yes, outside the failure branch and
  sanitized. Inside the branch it swallows a passing probe's warning on 97.6% of runs; raw, it
  routes the same bytes off-box around the redaction applied one line later.
