# Decision Challenges — feat-one-shot-7160-release-timeout-and-c4-count-parity

Persisted at plan time (headless / one-shot pipeline — no operator was attached to ask).
`ship` renders these into the PR body and files them as an `action-required` issue.

---

## DC1 — The issue's own framing is factually wrong, and the plan does not adopt it (User-Challenge)

**Operator's stated direction (from #7160):** "That makes the strictly *provable* commit-to-deployed
bound 555 minutes rather than the 195 the drift checker uses… Analyse what the legitimate ceiling for
`release` actually is, then declare it."

**What the plan does instead:** declares the ceiling as asked, but **drops the "strictly provable"
claim entirely** and records why.

**Why the challenge:** `timeout-minutes` caps a job's *execution*. The drift checker's clock starts
at the **committer epoch** of the oldest undeployed commit (`scripts/prod-version-drift-check.sh`,
`git log --format='%H %ct'`, `age_s = now_epoch - oldest_epoch`). Between commit and job start sit
three terms no job timeout caps:

1. runner queue wait (excluded from job duration by construction);
2. **concurrency serialization** — `cancel-in-progress: false` on all five groups
   (`release-${component}`, `migrate-web-platform`, `verify-migrations-web-platform`,
   `verify-secrets-web-platform`, `web-1-swap`), so close-together merges serialize while the second
   commit's age accrues;
3. push-to-workflow-start latency.

No `timeout-minutes` value makes 195 a provable bound. Verified directly, not inherited from review.

**Cost of the plan's choice:** the deliverable is narrower than the issue promises. It removes 300
minutes of *declared* slack (495 → 195) and converts five silently-green regressions into red CI —
real value — but it does not close the wall-clock residual, which is filed as a deferral.

**What the operator may want to overrule:** if #7160's "provable bound" language was load-bearing
for some downstream commitment, the honest remedy is bounding queue/concurrency latency (a different
and larger piece of work), not a timeout value. Say so and it becomes its own issue.

**Also corrected:** the issue's 555-minute figure is arithmetically wrong — `release` runs *parallel*
to `await-ci`, so the undeclared figure is **495**.

---

## DC2 — Gate-mandated plan sections vs. proportionality on a p3-low chore (Taste)

**Simplicity panel's finding:** the plan is ~690 lines for ~75 lines of implementation (9:1). It
recommended deleting `## Hypotheses`, `## Domain Review`, the C4 (a)–(d) completeness enumeration,
and parts of `## User-Brand Impact` — roughly a 48% document reduction.

**Why not auto-applied:** every one of those sections is *required* by a plan-skill gate —
Phase 1.4 (network-outage keyword trigger), Phase 2.5 (domain review), Phase 2.6 (user-brand
impact), Phase 2.10 (C4 completeness mandate). Deleting them to satisfy a proportionality argument
would be a workflow-gate violation, and the plan author is not the right person to unilaterally
decide a gate does not apply.

**What was done instead:** each section was trimmed to its load-bearing content and the redundant
third-tellings (`## Research Reconciliation` restating `## Premise Validation`, `## Domain Review`
restating `## Risks`) were collapsed.

**The real tension for the operator:** several of these gates fire on *keyword* rather than
*substance* — `## Hypotheses` exists here only because the word "timeout" appears in a plan that
declares a `timeout-minutes:`. That is a false positive in the gate, not in the plan. If p3-low
chores should skip keyword-triggered gates, that is a change to the plan skill, worth making once
rather than re-litigating per plan.

---

## DC3 — Fixing a stale count found by the sweep, vs. keeping the chore small (Taste)

**Context:** #7160 asked to "sweep `model.c4` for OTHER edges carrying embedded counts". The sweep
found one: `hetzner -> tunnel` claims "12 `connection{}` inlines" — the actual count is **18**
(server.tf 16, ci-ssh-key.tf 1, tunnel.tf 1). It also found "THREE ingress rules" against four
`ingress_rule {` blocks (three carry `hostname =`).

**Plan v1** fixed it inline. **Plan v2 defers it**, per the simplicity panel: it is a different edge,
unasked-for by the issue's two named edges, and correcting the prose regenerates
`model.likec4.json` — non-trivial scope on a p3-low chore.

**The judgement call:** finding a stale count and then *not* fixing it can read as leaving a known
defect on the floor. The counter-argument is that the prose is ambiguous enough that "correcting" it
requires deciding what it was trying to say — a decision better made by whoever next edits that edge.
Deferral 1 in the plan carries the finding so it is not lost.
