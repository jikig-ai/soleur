---
title: A documented cause is a claim with an author and a date, not a fact — re-derive before building on it
date: 2026-07-22
category: best-practices
tags: [debugging, root-cause, test-infrastructure, measurement, tmpfs]
issue: 6789
---

# A documented cause is a claim with an author and a date, not a fact

## Context

`work/SKILL.md` recorded that concurrent `test-all.sh` false REDs came from two
suites colliding on shared paths — `skill-security-scan`'s `.scan-meta.json`
plus the semgrep bootstrap, named as "the known pair". #6789 was scoped to fix
that contention. The issue body itself flagged that the `.scan-meta.json` half
did not survive inspection and asked for the real cause to be re-derived first.

## What happened

**Both halves of the recorded cause were refuted in minutes, by two mechanical
checks that required no judgement:**

- `git log -S'skill-security-scan-$$'` returned a single commit — the skill's
  original one. `.scan-meta.json` was PID-scoped from birth, so it cannot
  collide across worktrees. The attribution was *wrong when written*, not
  stale-after-a-fix.
- A grep over the exact suite globs `test-all.sh` enumerates returned zero hits
  for the semgrep bootstrap. No suite the runner reaches can invoke it.

The actual contended resource was neither: it was **capacity**. Every suite's
`mktemp` lands in the same machine-global, RAM-backed 4 GiB `/tmp` tmpfs
(measured 86% full, swap exhausted), so a second run competes for the memory
the first is holding — and the failure both implicated suites already document
in-repo is a TIMEOUT, never a path collision. `.scan-meta.json` *did* have a
real defect at that same path, but it was an unbounded directory leak (12,889
leaked dirs), not a collision — a different defect class entirely.

## The transferable lesson

A documented cause carries an author and a date. It was true-enough to write
down once; it is not a fact you may build a fix on without re-deriving it. The
cheapest possible check often settles it:

- **`git log -S<token>`** on the allegedly-colliding symbol — when was this
  scoping introduced, and has it ever changed?
- **A reachability grep** over the runner's *own* enumeration — can the
  implicated code even run in this path?

Neither needed a repro, and both are seconds of work. The same defect class
(treating a stale documented attribution as fact) is what the issue this closed
existed to correct — so it applies recursively, to the plan and the fix as well
as to the bug.

## Corollaries surfaced while fixing it

- **Refute by mechanism, not by plausibility.** The semgrep hypothesis was
  refuted because no suite *can* reach the bootstrap (reachability), not because
  interleaving seemed unlikely. Where the deciding datum is unavailable, record
  UNKNOWN — do not upgrade a strong hypothesis to "sole cause".
- **A probe with no positive control answers the wrong question confidently.**
  Establishing that `flock` needs no stale-holder detection took three attempts;
  the first two produced coherent-looking BLOCKED results from a malformed probe
  and an irrelevant confound. Only a probe that first acquired a *known-free*
  lock — proving the probe itself worked — gave the true answer. Any probe whose
  negative result would change a design decision must carry a positive control.
- **The entry count is not the occupancy.** 4,294 leaked entries held 160 MB;
  three entries held 3.1 GiB. Sort by bytes before choosing what to reap.
- **Verify what consumes an artifact before deleting it.** `.scan-meta.json`
  looks like scratch and is in fact GDPR Art. 32 evidence with a post-exit
  consumer, so its leak fix had to age-reap, not `trap … EXIT`.

See [[2026-07-19-my-own-mutation-battery-was-the-false-confidence]] for the
sibling lesson about a passing test battery that proved nothing.
