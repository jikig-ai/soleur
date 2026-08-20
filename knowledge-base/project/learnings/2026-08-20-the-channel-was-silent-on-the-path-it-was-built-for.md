---
title: The channel was silent on the path it was built for
date: 2026-08-20
category: logic-errors
module: infra/apply-web-platform-infra
tags: [github-actions, notification-channel, mutation-testing, guard-vacuity, timeout-ladder, incident-suppression, self-clearing]
related_issues: [7586, 7587, 7228]
related_prs: [7642]
related_learnings:
  - knowledge-base/project/learnings/2026-08-17-the-artifact-that-proves-a-refusal-happened-could-not-be-written.md
  - knowledge-base/project/learnings/2026-08-17-the-lint-that-was-meant-to-make-the-class-mechanical-was-never-pointed-at-the-repo.md
  - knowledge-base/project/learnings/2026-08-14-my-gate-reserved-its-reassuring-message-for-its-alarming-condition.md
  - knowledge-base/project/learnings/2026-08-06-my-correction-overshot-into-a-new-wrong-claim-in-a-compliance-artifact.md
  - knowledge-base/project/learnings/2026-08-02-my-comments-defeated-three-gates-and-an-unlinked-email-read-as-a-cla-outage.md
  - knowledge-base/project/learnings/2026-08-11-arming-a-guard-and-running-it-are-the-same-event-unless-you-split-them.md
---

# Learning: the channel was silent on the path it was built for

## Problem

#7586 ("a red apply notifies nobody") and #7587 ("the ARM gate's deadlines do not fit its
job") were fixed on one branch. Every finding below is a defect found *inside* a fix, by a
gate other than the one that shipped it.

Five of the six lessons here are **recurrences** of classes the corpus already names, and
each has been folded into its host file rather than restated. This file carries the two that
are new — §2 and §5 — plus the deltas the recurrences added.

## 1. `failure()` cannot see a cancellation, so #7586's own proposed fix was blind to #7587

The issue proposed an `if: failure()` step arm on the `apply` job. A job that exceeds its
`timeout-minutes` concludes **`cancelled`**, not `failure`, so a `failure()`-gated arm is
structurally silent on exactly the path #7587 describes. The fix is a downstream **job**
reading `needs.apply.result`, which is a value rather than a status function.

The mechanism is already documented — see
[the artifact that proves a refusal happened](./2026-08-17-the-artifact-that-proves-a-refusal-happened-could-not-be-written.md) §2,
strengthened with this instance. **What is new here is the citation discipline**, and it is
the more transferable half.

The branch first cited run `32168637847` as measuring the whole premise. It measures
**half**: `Main Health Monitor` ran 70m43s against `timeout-minutes: 70`, concluded
`cancelled`, and its `always()` siblings still ran, consuming 43 s past the timeout instant.
It does **not** measure the `failure()` half — the step it was cited for is gated
`if: ${{ !cancelled() && … }}`, and that run contains no `failure()`-gated step at all. Both
premises were then re-measured from this repo's own run history, each recorded with what its
evidence covers *and what it does not*:

- **A downstream `always()` job runs when an upstream job is cancelled** — `infra-validation.yml`
  runs `32272435663` / `32294251707` / `32296436704`; the `always()` job concluded `failure`,
  not `skipped`, and its log printed `RESULT: cancelled`. **Narrow spot:** the ceiling there
  was GitHub's 6h platform default, not a declared `timeout-minutes`; that the two ceilings
  are one code path is measured separately (`deploy-script-tests`, `timeout-minutes: 14`).
- **A step exceeding its own `timeout-minutes` concludes `failure` and the job carries on** —
  `web-platform-release.yml` runs `32293304541` / `32283291347`, step "Install psql". The
  continuation half comes from a different workflow. **No single run gives both.**

**The generalizable form:** a premise assembled from two half-measurements is legitimate
provided the artifact says so. "VERIFIED, in two halves from two workflows. NOT IN HISTORY:
a single run joining them" is a stronger record than a citation that reads as one measurement
and is not. Write what the evidence does **not** cover next to what it does, or the next
reader inherits a whole from two halves.

**And a correction does not chase the prose already downstream of it.** The corrected framing
landed in the workflow at review time, but the pre-correction sentence was still travelling in
the pipeline's phase-to-phase handoff prose afterwards. When a review overturns a claim, grep
the *session artifacts* — `session-state.md`, `tasks.md`, handoff prompts — for the retracted
wording, not only the code. Same shape as
[correcting a fabricated claim by grepping its phrasing](./2026-08-17-i-corrected-a-fabricated-claim-by-grepping-its-phrasing-and-missed-a-site.md).

## 2. My mutation battery only knew how to delete

Found in QA, after every other gate on the branch was green. **This is the new one.**

`arm_one` writes the monitor id to the `always()` sweep's state file **immediately after the
unpause**, not at the point it gives up — and the script says so in a comment: *"the id is on
the sweep's books from the instant the monitor is live, not from the instant we decide to
give up: everything between those two points is exactly the window in which an
externally-imposed cut leaves it unpaused-and-unfed."* That window is the entire reason the
sweep exists.

**Measured:** moving `state_add "$id"` from before the poll loop to just before the rollback
left **190 of 190 assertions green**. Mutation row M3 already *deleted* `state_add` and
reddened. Deleting it reds because every case reads the state file at all; **moving** it reds
nothing, because every case reads the state file *after `arm_one` has returned* — which is
the one instant the property can never be violated at.

**The generalizable form: a delete-only mutation battery certifies an ordering property it
never tested.** For any property of the shape "X is recorded *before* Y" or "the record
exists *during* window W", at least one mutation row must **reorder** rather than delete, and
at least one case must observe **inside** the window rather than after it. Deletion and
reordering are different mutations of different properties, and a battery that only knows how
to delete cannot tell you which one it proved.

`arm-heartbeats.test.sh` T11 now stops the SUT mid-poll — the `sleep` stub SIGKILLs its own
`$PPID`, which is the SUT's bash, so the cut is deterministic against the fake clock — reads
the books at that instant, and hands them to the real `--sweep`. Row M18 drives the reorder
and requires T11 to red.

Two smaller members of the "the assertion is not about what it says" family, fixed in the
same pass: the sweep's `mint-unreadable` branch was asserted on its prose but not on its
`::error::` prefix (the annotation is the only machine-readable signal, and the notify job's
`cause` step reads it over the annotations REST API); and the self-clearing property was
covered in *halves* — one case for the beat landing, a **different** case for the no-op on an
untouched monitor — rather than as the sequence the property actually claims.

## 3. A bare-token anchor, found twice, one row apart

Two fresh instances of `cq-assert-anchor-not-bare-token` in the same guard block, discovered
on separate review rounds:

1. **G2-M8** — a `|| true` assertion was a bare token satisfied by the step's own Doppler
   line, so deleting `|| true` from the rollback `PATCH` left the guard green. Found **by
   executing the mutation matrix against the real artifact, restoring from a pristine backup
   between rows** — not by reading it. 15 of 16 rows behaved; this one survived.
2. **The neighbour** — `expect(body).toMatch(/^\s*exit 1\s*$/m)`, satisfied by an unrelated
   `exit 1` in the `mint-unreadable` branch several lines away, so deleting the entire
   fail-not-annotate block left the suite green. Found a round later.

Instance 2 is a **sub-variant the existing bullets do not name**: `/^\s*exit 1\s*$/m` *is*
anchored on syntax a comment cannot produce. It failed anyway because it was **file-wide
rather than block-scoped**, and a legitimate non-comment sibling satisfied it. Folded into
[my comments defeated three gates](./2026-08-02-my-comments-defeated-three-gates-and-an-unlinked-email-read-as-a-cla-outage.md)
`### The rules` as a fifth bullet.

**The generalizable form:** anchoring is necessary but not sufficient — an anchored pattern
must also be **scoped to the construct it is about**, or a legitimate sibling occurrence
satisfies it. And finding an instance of a class is not sweeping the class: round one fixed
the `|| true` anchor and moved on; the anchor immediately beside it had the identical shape
and survived another round. The block was written in one sitting, by one author, in one
idiom, so the defect distribution is not independent — re-derive **every** assertion in a
block once one of them is found vacuous
([the rework that removed three instances shipped four more](./2026-08-13-the-rework-that-removed-three-instances-shipped-four-more.md)).

Both instances also argue for the remedy the branch took: the sweep stopped being ~45 lines
of bash inside a YAML scalar guarded by ten regexes and became `arm-heartbeats.sh --sweep`,
driven behaviourally. A regex over a YAML scalar cannot be anchored on syntax, because the
scalar has none.

## 4. The plan failed its own guard: it sized from the reachable Σ and asserted the nominal Σ

The ARM gate calls `arm_one` once per monitor, hand-written, no `for_each`. At plan time two
sums existed:

| | Σ |
|---|---|
| **Nominal** — every hand-written call site | **1660 s** |
| **Reachable** — only the sites present in tfstate today | **1430 s** |

The plan **sized** its ladder from 1430 (`arm_step_timeout ≥ 1430 × 1.1 = 1573`, so 27 min)
and **wrote its guard** against `sum(arm_one deadlines)`, which is 1660. `1620 < 1660 × 1.1
= 1826`: the plan's own ladder fails the plan's own acceptance criterion. Phase 0's
measurement pass caught it before any code was written.

This is [the PR that broke a rule stated in the learning file it shipped](./2026-08-17-the-lint-that-was-meant-to-make-the-class-mechanical-was-never-pointed-at-the-repo.md) §2
again, with a mechanism that file lacked: the two sides disagreed not by an arithmetic slip
but because **guard and sizing quantified over different populations**.

**The generalizable form: size from nominal.** A call site absent from tfstate today is still
a call site on the day it is not. Whenever a budget is computed over "the members that exist"
and asserted over "the members that are declared", name the two sets separately and write the
inequality against the larger. A plan that quotes one number for both has not noticed there
are two.

## 5. A shortened deadline suppresses better than a short-circuit, because it keeps re-testing

**Also new** — nothing in the corpus covers the *choice between two suppression mechanisms*
on the grounds that one re-tests and one does not.

The brief asked to **short-circuit** the `inngest_consumer` arm while #7228 stays open, and
to "make the short-circuit self-expiring or loudly self-reporting so it cannot silently
outlive #7228." What shipped is a **deadline resize**: 230 s → 30 s, no short-circuit.

The argument that decided it: `arm_one` returns 0 via `already armed (status=…)` the first
time the monitor is live-`up`. **A short-circuit never re-tests**, so once #7228 closes
nothing arms the monitor — the "shipped inert and forgotten" shape (#6537). A 30 s deadline
still attempts the measurement on every apply, so arming stays automatic and **self-clearing**,
and there is nothing to expire because nothing was added that could outlive the incident. It
also avoided adding `issues: read` to the job holding production Doppler secrets and the
fleet-wide apply mutex.

**The generalizable form: prefer shrinking a measurement's budget over skipping the
measurement.** A skip needs an expiry mechanism, and expiry mechanisms rot — ADR-185 records
the anti-pattern (a one-shot verification literal that silently became a permanent ceiling
nobody decided on), and
[a rider is only valid while its vehicle is still pending](./2026-08-13-a-rider-is-only-valid-while-its-vehicle-is-still-pending.md)
records a deferred change sitting inert for 45h because its vehicle had departed. A shortened
budget needs nothing: it is self-clearing by construction, because the measurement it shortens
is still running. This is the same instinct
[arming a guard and running it are the same event](./2026-08-11-arming-a-guard-and-running-it-are-the-same-event-unless-you-split-them.md)
applies to guard rollout — "a self-clearing mechanism, never a condition the normal workflow
may never satisfy" — applied to incident suppression.

**The cost is owned, including its tail.** 30 s against a 180 s feeder period gives p = 1/6
per attempt; at 2.71 merge-applies/day that is a **mean of 6 attempts ≈ 2.2 days, median 1.5
days, p95 ≈ 6.3 days**, and P(still unarmed after 2 days) ≈ 37%. Quoting only the mean of a
geometric buries the half that matters. Reclaimed: ~200 s per merge apply, on a step that was
98.8% of the ARM gate and 78.5% of the whole apply job.

## 6. Two operator-facing defects, both folded into their host files

**The alarming state got the reassuring sentence.** The failure email branches on the sweep's
conclusion. The producer emits four values plus a floor; the body branched on **two**, so
`cancelled`, `skipped` and `unknown` all landed in *"the sweep did not run, so nothing was
left half-armed."* `cancelled` is precisely when the sweep **was** cut mid-loop and monitors
**are** live-and-unfed. `unknown` is reached when the jobs-API read *failed* — so the same
step that emits `::warning::Could not read the jobs API` then asserted, two elements later, a
fact it had just said it could not read. Folded into
[my gate reserved its reassuring message for its alarming condition](./2026-08-14-my-gate-reserved-its-reassuring-message-for-its-alarming-condition.md)
insight 2, which until now never left the gate/CI frame. **The delta:** there the benign
branch was *unreachable*; here it is reachable and carries **a claim the job never measured**.

**The recovery lever could not clear the item it called urgent.** The only action the email
offered was `gh workflow run … apply_target=manual-rerun`. On the next run `arm_one`'s
op/state gate no-ops any monitor that is not `paused` — and a live-and-unfed monitor is not
`paused`. The lever was **provably inert for the exact condition the email flagged as the one
urgent item**. Folded into
[a runbook prescribed a command the repo's own hook denies](./2026-08-06-my-correction-overshot-into-a-new-wrong-claim-in-a-compliance-artifact.md) §2.
**The delta:** there the command was *denied*; here it is permitted, exits 0, and is still
inert. Grepping the hooks cannot see this — the check is to **execute the prescribed lever
against the exact state the message flags**.

Both are now asserted structurally in `terraform-target-parity.test.ts`: every value
`sweep_conclusion` can take must have its own sentence, read from the producer's own
validating `case` rather than restated; no sentence may assert a fact the job did not measure;
and any branch that calls an item urgent must prescribe a lever whose premise is read out of
the shipped script.

## Session Errors

**The `failure()` citation carried a pre-correction sentence into the next phase.**
- *Recovery:* the corrected two-halves record was read out of the workflow before any learning
  prose was written, so the over-claim never reached this file.
- *Prevention:* when a review overturns a factual claim, grep the session artifacts for the
  retracted wording, not only the code. See §1.

**A hand-run verification mutation used `\&` inside single quotes and produced a syntactically
invalid script.** 87 assertions failed at once and briefly read as a broken suite rather than
a broken experiment.
- *Recovery:* the suite's own first assertion — "the SUT is syntactically valid bash" — was in
  the failure list and named the cause; the mutation was re-applied with Python.
- *Prevention:* run `bash -n` on any hand-built mutant **before** reading the suite's verdict.
  A suite that keeps a syntax-validity assertion at the top of its run makes this
  self-diagnosing; keep it there.

**Mutation row M18 was declared with the wrong landed-line count.** `mutate`'s count is
**deletions only**, and a move is one delete plus one pure insertion, so the count it can see
is 1, not 2.
- *Recovery:* the helper's own landing assertion caught it immediately.
- *Prevention:* a deletions-only count cannot distinguish a *move* from a *delete*, which is a
  different mutation row entirely. Any reorder row must additionally assert the re-insertion
  landed (`grep` the moved construct in the mutant), or it silently degrades into the delete
  row beside it.

**Forwarded from earlier phases** (`session-state.md`):
- `soleur:*` skills and `soleur:engineering:*` agents were deregistered mid-run; every phase
  read its `SKILL.md` from disk and substituted `general-purpose` agents. *Prevention:*
  recorded as harness degradation in `session-state.md`; procedures were followed verbatim
  rather than improvised.
- `iac-plan-write-guard.sh` rejected the first plan write on the literal `out-of-band`;
  reworded at source rather than using the `iac-routing-ack` opt-out. *Prevention:* already
  hook-enforced — the hook worked and the opt-out was correctly declined.
- A Guard 2 rewrite broke the required `**Assembly.**` field marker and
  `lint-guard-contract.py` failed. *Prevention:* already gate-enforced; caught in-session.
- Deepen Phase 5 fan-out was scoped to 8 of ~23 agents, omitting agents whose domain is
  provably absent from a YAML/TS-test/Markdown diff. Recorded as a deliberate deviation.

## Related

- ADR-117 (executable heartbeat arming), ADR-180 (guard contract as a plan-time deliverable),
  ADR-185 (self-expiry mechanisms rot).
- [2026-07-24-followthrough-soak-must-arm-every-new-member-monitor.md](./2026-07-24-followthrough-soak-must-arm-every-new-member-monitor.md)
  — the Better Stack arming mechanics §6's lever defect turns on.
- [2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md](./2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md)
  — the vacuous-guard class §2 and §3 extend.
