# Decision Challenges — feat-one-shot-7450-git-root-anchor-untrusted

Raised at plan time, headless. Recorded rather than asked, per the decision-principles
headless arm. `ship` renders these into the PR body and files an `action-required` issue.

---

## DC-1 — Should the two `preflight/SKILL.md` git-root sites be folded into this PR?

**Decision class:** user-challenge (challenges the operator's stated scoping rule).

**The operator's stated direction (the default, and what the plan follows).** The brief says:
*"Any non-secret-gate sites found go to #7453, not this PR."* The two sites are not
secret-emission gates, so the plan routes them to #7453 and migrates only the five named
gate sites.

**What was found that the direction did not anticipate.** The plan-time sweep found a site
class the brief did not name and ADR-179 does not list: two **unconditional**
`$(git rev-parse --show-toplevel)/plugins/soleur/…` anchors in `preflight/SKILL.md` —
`parse-form-a.awk` and `probe-verb-gate.sh`. They have no `${CLAUDE_PLUGIN_ROOT}` arm at all.

**Why the challenge.** The plan-time CTO consult assessed these as carrying the same threat
in a **more severe form**. The redact-sentinel vector is a gate *bypass* — a planted script
exits 0 and a secret is emitted. These two are direct *arbitrary code execution*:
`awk -f "$FORM_A_AWK"` and `bash "$PROBE_GATE"` run contributor-supplied program text after
`gh pr checkout`. Under the issue title's own framing — "puts contributor code behind
5 redaction gates" — an RCE site arguably outranks a gate-bypass site.

**Why the operator's direction may still be right.** Reachability is weaker.
`gh pr checkout` is instructed by `review/SKILL.md`, not by preflight, and no invocation of
preflight from the review path was found. Preflight is a pre-ship check the operator runs on
their **own** branch, so the hostile-tree precondition is not established for it the way it
is for the review path. That gap is real and was not closed at plan time.

**What the plan does.** Follows the operator's direction: the two operands stay unmigrated
and are routed to #7453 with a severity flag. **One part is folded in regardless** — the
committed comment above `FORM_A_AWK` that argues *for* git-root resolution. It reasons from a
true premise to ADR-179's explicitly-rejected option (d), and leaving a persuasive committed
rebuttal of the doctrine this PR ratifies is rule-corpus contamination independent of the
security question: the next agent reads it as authority and propagates it.

**What would change the answer.** Evidence that any review-path or `gh pr checkout`-adjacent
flow invokes preflight. If so, fold both operands in.

---

## DC-2 — AC #1 asked for a decision that was already made

**Decision class:** mechanical (applied; recorded for visibility, not for adjudication).

The brief framed the anchor mechanism as undecided and required producing or amending an ADR
as a plan deliverable. Measured, **ADR-179 (accepted 2026-08-11) already decided it**, lists
`7450` in its `related:` frontmatter, and its §R5 names these exact five sites as the subset
that "goes first". It also already rejected all three alternatives the brief asked to weigh
(fail-closed `:?`, a trusted-anchor resolver, and the git-root form itself).

The plan therefore delivers an **amendment extending ADR-179's scope** rather than a new
decision record, and cuts the "write a new ADR" mechanism per the minimality gate. Flagged so
the scope reduction reads as a finding rather than as the plan quietly under-delivering an
acceptance criterion.

Two related citation corrections carried into the downstream comments: **#7453's title cites
ADR-177**, which is the test-runner result-taxonomy ADR, not the anchor ADR; and **#6222's
cited `domain-model-drift.sh` sites are already remediated**, so its remedy is re-scoped
against ADR-179 §R4's re-derived member list.
