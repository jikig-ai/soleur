# Decision challenges — feat-one-shot-7822-7275-shell-git-env-scrub-hook-fault-diag

Raised during planning, in a headless run, so recorded here rather than asked. Each challenges a
direction the operator stated. The operator's direction is the default; these are for review.

---

## Challenge 1 — the rule-metrics orphan gate and the signal consumer are deferred, not fixed in this pass

**What you asked for.** All three of #7275's Asks in scope, and the `rule-metrics-aggregate.sh`
orphan-gate blocker resolved in the same pass, quoting the issue: *"it is the reason the metric is
not being written at all."*

**What the plan does instead.** Asks 1 and 2 ship. Ask 3 (consume the signal) and the orphan gate are
deferred to a new tracking issue, filed in the same pass with the remedy fully specified.

**Why.** Three reasons, one of which is a correctness finding rather than a scoping preference.
(a) The orphan gate belongs to none of #7822, #7835 or #7275 — it is a different subsystem, and
reworking its notion of "known" is the change most likely to silently mask a real orphan.
(b) Ask 3 as specified cannot work: ADR-091 makes `rule-metrics.json` a *local* producer, so a CI
gate failing on a non-zero committed count is unclearable by CI — any contributor whose local hooks
faulted once commits a red metric and `main` stays red until someone runs `/compound` locally. It
needs to be a threshold-and-delta signal that files an issue, and that redesign is not a small
addendum.
(c) The measured evidence changed the urgency: **zero** `hook_self_fault` rows are retained anywhere,
so there is currently nothing for a consumer to consume. The split enum has to ship and start
recording before a consumer has a signal to escalate on.

**What it costs you.** #7275 closes with Asks 1 and 2 met and Ask 3 tracked, rather than fully
closed. The orphan gate keeps leaving a rejected `rule-metrics.json` in the working tree until the
follow-up lands.

**If you disagree.** Say so and the orphan gate folds into PR 3; it is well-diagnosed and the remedy
is written. The Ask-3 consumer should still not ship as a hard CI gate in any case — that part is a
correctness objection, not a scoping one.

---

## Challenge 2 — the work ships as three PRs, not one

**What you asked for.** Close the residual work on two open issues.

**What the plan does instead.** Three PRs: the hook-library discriminator repair alone; then the
classification and telemetry work; then the shell containment work.

**Why.** `.claude/hooks/lib/hook-input.sh` is sourced by ~30 hooks, ~19 of which fire on every Bash
tool call. ADR-157's own core argument is that a persistent fault there is unrecoverable *because the
repair is itself a Bash call* — and that argument applies to this change. The repair also activates a
branch that has never executed, and carries a corruption mode (the return code landing on the wrong
side of the sentinel appends digits to `HOOK_FILE_PATH` while the record count stays at 6, so a
slot-count assertion passes over it). That belongs in a small PR that can be reasoned about and
reverted alone.

**What it costs you.** Three review cycles instead of one; the two issues close on PRs 2 and 3.

**If you disagree.** PRs 2 and 3 could merge together — they are independent of each other. PR 1
should stay separate regardless.

---

## Challenge 3 — the shell sweep is three files, not twenty-five

**What you asked for.** Re-derive the population with the issue's filter and report the measured
count; the issue's suggested fix has three parts, all in scope.

**What the plan does instead.** Reports the measured population (41 or 66 depending on the predicate;
25 or 39 uncovered), then sweeps **three** files and ships an adoption ratchet instead of the
proposed lint and scrub wrapper.

**Why.** The issue's suggested fix was already adjudicated. The merged #7833 plan explicitly **cut**
the shell scrub wrapper and the file-scale lint, choosing to guard ~4 entry points rather than ~900
files, and deferred the per-suite sweep to #7849 — which carries a *named exit condition*:
`plugins/soleur/test/*.test.sh` reaching full `test-helpers.sh` adoption. Measured against that
condition, exactly three unadopted suites create a git fixture. Also: the wrapper as literally
specified in #7822 is a six-name list, where the repository already deploys a nine-name list at all
three entry points — adopting it verbatim would *reduce* coverage.

**What it costs you.** The other ~22 uncovered suites stay with #7849, which this plan advances
rather than closes.

**If you disagree.** The wider sweep can fold into PR 3, but it is ~39 near-identical diffs, which is
the rubber-stamp review #7849 itself gave as a reason for deferring. The vacuity repairs — which are
semantic, and are the part that actually makes those assertions mean something — are in scope either
way.
