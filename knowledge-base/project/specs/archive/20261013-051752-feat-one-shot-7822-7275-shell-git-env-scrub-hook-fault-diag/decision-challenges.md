# Decision challenges — feat-one-shot-7822-7275-shell-git-env-scrub-hook-fault-diag

Raised during planning, in a headless run, so recorded here rather than asked. Each challenges a
direction the operator stated. The operator's direction is the default; these are for review.

---

## Challenge 1 — two of #7275's three Asks ship; the other one and a half are deferred

**What you asked for.** All three of #7275's Asks in scope, plus the `rule-metrics-aggregate.sh`
orphan-gate blocker resolved in the same pass, quoting the issue: *"it is the reason the metric is
not being written at all."*

**What the plan does instead.** Ask 1's first half ships — the `HOOK_INPUT_REASON` value becomes
diagnostic, which is what actually answers "the log cannot say why" for all seven measured rows.
Deferred to a tracked follow-up: Ask 1's second half (the JSON type vector), Ask 2 (unconditional
ask), Ask 3 (consume the signal), and the orphan gate.

**Why.** Four reasons, three of them correctness findings rather than scoping preferences.

*The type vector.* Every one of the seven observed faults was the zero-output path, where no field
types exist to report — so the enum split answers all seven and the vector answers a path that has
fired **zero** times in the retained log. Shipping it means editing `_HOOK_INPUT_JQ`, the constant
program whose fragility is the entire reason the first PR ships alone. Security review also found
that the vector cannot emit `null` as the plan's own example claimed (`d()` maps null to `""` before
the type is taken), and that composing the reason from jq output for the first time removes the
closed-enum property that makes two unescaped sinks safe today — one of which, on a crafted reason,
flips the `ask` envelope into `allow`. That is a real design, not a suffix.

*The ask posture.* ADR-157 rejected all-hook escalation because 19 hooks fire per Bash call and the
repair for a persistent fault is itself a Bash call. Review found `empty` is a *persistent* class —
a harness or dispatch condition, not a per-call payload fault — so escalating it unconditionally
produces N prompts per call until Claude Code itself changes, with an escape hatch (`SOLEUR_DISABLE_HOOK_INPUT_ASK=1`)
that is an environment variable a Bash call cannot set. Multi-hook `ask` behaviour is also unprobed.
And the precedent this plan was going to cite — that `prod-write-defer-gate.sh` already denies on a
parse fault — is **false**: on that axis it fails open like every other hook.

*Ask 3.* As specified it cannot work: ADR-091 makes `rule-metrics.json` a *local* producer, so a CI
gate failing on a non-zero committed count is unclearable by CI — any contributor whose hooks faulted
once commits a red metric and `main` stays red until someone runs `/compound` locally.

*The orphan gate.* It belongs to none of #7822, #7835 or #7275, and reworking its notion of "known"
is the change most likely to silently mask a real orphan.

**What it costs you.** #7275 closes with its diagnostic gap fixed and three refinements tracked. The
orphan gate keeps leaving a rejected `rule-metrics.json` in the working tree until the follow-up
lands — and, more importantly, keeps starving log rotation, which is the most plausible reason the
August evidence for this very issue no longer exists.

**If you disagree.** The orphan gate is well-diagnosed and its remedy is written; it can fold into
PR 2 at modest risk. The type vector and the ask posture should not be rushed — both acquired
concrete defects under review, and both edit the hot path.

---

## Challenge 2 — the work ships as two PRs, not one

**What you asked for.** Close the residual work on two open issues.

**What the plan does instead.** PR 1 repairs the hook-input classifier alone; PR 2 does the shell
containment work.

**Why.** `.claude/hooks/lib/hook-input.sh` is sourced by 22 non-test hooks, 19 firing on every Bash
tool call. ADR-157's core argument is that a persistent fault there is unrecoverable *because the
repair is itself a Bash call*, and that applies to this change. The repair also activates a branch
that has never executed and carries a corruption mode where the return code lands in the last field —
`HOOK_FILE_PATH` — while the field count stays at six, so a count assertion passes over it. Review
traced that to two live guards (`no-memory-write.sh`, `kb-domain-allowlist-guard.sh`) that would
silently stop reading commands on every call.

**What it costs you.** Two review cycles instead of one, and the twice-realized index truncation
stays live through PR 1. The plan states that cost rather than burying it.

**If you disagree.** They share no files, so merging them together is possible — but PR 1 is the one
that can brick a session, and it is small.

---

## Challenge 3 — the shell sweep is five files, not twenty-five

**What you asked for.** Re-derive the population with the issue's filter and report the measured
count; the issue's suggested fix has three parts, all in scope.

**What the plan does instead.** Reports the measured population and the fact that it is not stable
(three defensible predicates returned 42, 45 and 47 for adoption; 41 vs 66 for candidates), then
sweeps **five** files and ships neither the proposed scrub wrapper nor the proposed lint.

**Why.** The issue's suggested fix was already adjudicated. The merged #7833 plan explicitly **cut**
the shell scrub wrapper and the file-scale lint, choosing to guard ~4 entry points rather than ~900
files, and deferred the per-suite sweep to #7849 — which carries a *named exit condition*:
`plugins/soleur/test/*.test.sh` reaching full `test-helpers.sh` adoption. Measured against that
condition, five unadopted suites create a git fixture. Separately, the wrapper as literally specified
in #7822 is a six-name list where three entry points already deploy a nine-name list, so adopting it
verbatim would *reduce* coverage.

Two replacement guards were then proposed and both cut under review — a per-file guard whose verdict
would have certified "contained **or** refuses to run", and an adoption ratchet that at its own
baseline of zero could not detect the regression it named.

**What it costs you.** The remaining uncovered suites stay with #7849, which this plan advances
rather than closes.

**If you disagree.** The wider sweep can fold into PR 2, but it is ~39 near-identical diffs — the
rubber-stamp review #7849 itself gave as a reason for deferring. The vacuity repairs, which are the
part that actually makes those assertions mean something, are in scope either way.
