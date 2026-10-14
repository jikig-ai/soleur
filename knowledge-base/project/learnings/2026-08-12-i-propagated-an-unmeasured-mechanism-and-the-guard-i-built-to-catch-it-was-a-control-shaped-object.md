---
title: I propagated an unmeasured mechanism into seven files and a public README, and the guard I built was a control-shaped object
date: 2026-08-12
issue: 7471
category: workflow-patterns
tags: [measurement, mutation-testing, guards, review, propagation]
---

# I propagated an unmeasured mechanism, and the guard I built to catch it was a control-shaped object

Two failures from one session on #7471 (the plugin delivery path). Both are documented classes in
this repo. I committed both anyway, while executing the plan whose entire thesis is that unverified
delivery claims are the bug.

## 1. A correlation I never tested became a mechanism in seven artifacts

An earlier agent reported a defect and asked which of two `version` keys mattered. I answered with a
**mechanism**: *"a `version` key's presence suppresses `gitCommitSha` tracking."* It came from a
correlation in `installed_plugins.json` — six keyless official plugins carrying a SHA, two versioned
ones showing `sha=NONE`.

I never tested it. I sent it into six governance files and pushed it to a **public** README.

Two counterexamples were already in my own notes:

- `code-review` — keyless manifest, yet `sha=NONE`, with its SHA recorded in `version`.
- My own gate 1.0 run — a **versioned** manifest that *did* record a `gitCommitSha`.

One counterexample in each direction means the correlation is not the mechanism. The controlled
two-arm experiment (identical but for the key) took minutes: **both arms record a SHA.** What the key
changes is the recorded *version string* — the manifest constant with it, the commit SHA without.

The real mechanism is simpler and explains the evidence the false one never did: `plugin update`
compares **version strings**; a constant always compares equal, so the update short-circuits and
exits 0 having delivered nothing. That is exactly what the issue reported — `already at the latest
version (0.0.0-dev)`, exit 0 — and "suppresses SHA tracking" never accounted for it.

**What made it expensive was not being wrong; it was being wrong upstream of a fan-out.** A sweep
went out, then I authored the drift workflow *after* the sweep and reintroduced the same claim in
three more places — two of them strings the workflow **publishes into a filed GitHub issue**, so the
refuted cause would have been the operator's explanation at the moment they decided whether the
drift mattered.

**The rule I already had:** *verify a measurement before it propagates, at the granularity you will
claim it.* I applied it to the numbers in `measurements.md` and not to the causal sentence, because a
mechanism does not feel like a measurement. It is one. The tell was available for free: my own record
contained a row that contradicted the claim, and I did not read my own file before restating it.

## 2. The guard I built had six surviving mutations, two of them the ones it existed to catch

`scheduled-marketplace-drift.yml` is the **only** control on a public repo with no CI, no review and
no CODEOWNERS. I wrote it with three assertions, 34 passing tests, and ran four mutations — all
killed. I reported it as well built.

Review drove the real step body and found it reporting `OK` on:

| mutation | why it matters |
|---|---|
| `source.source: git-subdir → github` | restores the 181 MiB whole-repo clone — defect 2, the thing the PR fixes |
| add `"ref": "v0.9.0"` | freezes every new install — defect 1 by another route |
| append a 2nd entry → `attacker/evil` | a marketplace carrying the Soleur name serves an arbitrary plugin |
| rename `.plugins[0].name` | the `@` half of every install id |

Both load-bearing properties were carried **only by the remediation prose in the issue body** —
which is documentation, not an assertion. The workflow told the operator the contract and asserted a
strict subset of it.

Three more fail-opens the same review found: drift detected + filing failed = **green run, no
issue**; deleting every assertion left `0 passed, 0 failed` **exit 0** (the exit code is all
`test-all.sh` reads); and no Sentry heartbeat, so a job that stops being scheduled produced no signal
at all — while every sibling scheduled workflow carries one.

**My four mutations measured the mutations I imagined.** Every one perturbed bytes an assertion
already read. The axes I never touched — the assertion *dispatch*, the fixture *set cardinality*, the
alarm's *destination* — are where all six survivors lived.

## What to do differently

- **A causal sentence is a measurement.** Before writing "X causes Y" into any artifact, name the
  experiment that would falsify it, and run it if it is cheap. Two arms differing only in X.
- **Grep your own record before restating a claim from it.** The contradiction was already written
  down, by me, one section away.
- **Audit a mutation battery by AXIS, not by count.** N mutations of one shape is one mutation. Ask:
  does it mutate the dispatch? the fixture shapes? the fixture *directions*? the set's cardinality?
  If every row perturbs bytes an assertion reads, the battery is silent on everything else.
- **For any guard, ask what the prose promises that the code does not assert.** The remediation text
  is the best available checklist of properties, and it is exactly where unasserted ones hide.
- **A guard needs an anti-vacuity floor.** `[[ "$FAIL" -eq 0 ]]` alone passes a suite that asserted
  nothing. A `MIN_ASSERTIONS` floor, calibrated from a green run, is two lines.

## Related

- `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`
- `2026-08-04-the-safety-rationale-i-wrote-was-false-and-the-gate-it-justified-failed-open-three-ways.md`
- `measurements.md` §1.9 (the controlled experiment), ADR-182, ADR-178's 2026-08-12 corrections
