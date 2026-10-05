# Decision Challenges — feat-one-shot-test-pipeline-efficiency

Persisted by `plan-review` running headless (invoked with a plan-file-path argument inside a Task
subagent). `ship` Phase 6 renders these into the PR body and files an `action-required` issue.

---

## UC-1 — Item 5 (the session "already green" memo) is deferred, not delivered

**Class:** User-Challenge. The operator explicitly requested Item 5 as one of six deliverables, so
dropping it is never-Mechanical under ADR-084 and is surfaced rather than auto-applied.

**The operator's stated direction (the default):** "Build a memo that records suite -> (input hash,
result, commit) and skips a re-run when the inputs are unchanged and the prior result was green."

**What review found.** Both the simplification panel (DHH, code-simplicity) and the correctness
lens converged on the same scope, which the `plan-review` skill says should bias to delete over fix.
The decisive finding is concrete and was independently verified against the tree, not argued:

- `scripts/validate-blog-links.sh:7-12` documents a **co-location invariant**: it reads `_site/`,
  which `plugins/soleur/test/seo-aeo-drift-guard.test.ts` builds (`:8-10`, `:48-51`).
- `_site/` is **untracked** (`git ls-files _site` → empty).
- Therefore the proposed memo key has two horns and both are fatal. With a **tracked-only** tree
  hash, memoising `plugins/soleur` skips the build, and `blog-link-validation` then validates a
  stale `_site/` from a previous session — a green that was never earned, which is the exact harm
  class the rest of this plan exists to prevent. With an **untracked-inclusive** tree hash, `_site/`
  is thousands of generated files that change every build, so the memo self-invalidates on every run
  and never fires.
- None of the seven proposed negative controls could see either horn: all seven test
  invalidation-on-change, none tests an input the key *omits*. That is a positive-only oracle — the
  precise defect class of the learning this plan cites as binding on itself
  (`2026-07-17-every-hole-was-a-claim-quantified-over-a-set-sampled-once.md`).

**Cost/benefit as it now stands.** The plan itself concedes the fan-out payer evaporates once Item 6
lands (Phase A). The single surviving payer — re-running the gate after a flake on an unchanged tree
— is also the scenario where replay is *least* valid, because the prior run is by definition the one
known to have been interfered with. And that payer is already served by output the runner prints: the
FAIL line carries the failing suite's re-run command.

**What ships instead:** the epilogue prints a consolidated re-run roster for failed suites, so the
"I re-ran 45 minutes to confirm one flake" loop is addressed directly rather than by caching.

**How to overrule.** If you want the memo regardless, the minimum honest version needs an input model
that can see untracked producer/consumer pairs like `_site/` — not a tracked-tree hash. Say so and it
goes back in scope; a tracked issue is filed either way so it is not lost.

---

## UC-2 — Item 2 delivers a measurement and an ADR amendment, not a mechanism change

**Class:** User-Challenge (lower confidence than UC-1 — flagged because the operator asked for a
mechanism replacement and gets a measurement).

**The operator's stated direction:** "Replace the global mutex with admission control on actual /tmp
headroom … That is strictly better than a global mutex." — qualified by "If the measurement says the
lock is still load-bearing, keep it and record the numbers that justify it. Data decides."

**Why the plan lands on "keep the lock."** The cross-cutting budget sanctions exactly one full-gate
run. n=1 measures the *uncontended* case, while the lock protects the *contended* one, so one run
cannot clear any honest bar for replacing a mutex. Two mechanism-level objections were also raised
that no amount of measurement removes: admission control is a point-in-time prediction about a
15-minute future (two runners both sample abundant headroom, both admit, both allocate — fixing that
requires a reservation, i.e. re-inventing the mutex), and it degrades to ENOSPC mid-suite rather than
to "slow", producing a RED that reads as a code regression.

**This is the operator's own stated fallback**, so it is recorded rather than treated as a deviation.
The measurement ships, the numbers are recorded in the ADR-133 amendment, and the named follow-up
candidate is a headroom *bypass* on top of the mutex rather than a replacement.
