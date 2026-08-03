---
title: "An issue's diagnosis is a hypothesis — measure the failure set before adopting its remedy"
date: 2026-08-03
category: workflow-patterns
tags: [linting, agents-md, gates, vacuous-gate, measurement, net-issue-flow, adr-155]
module: scripts/lint-agents-enforcement-tags.py
symptom: "A gate reports OK while validating nothing; the issue describing it prescribes the wrong fix"
root_cause: "The issue's remedy was derived from the failure COUNT, not from reading the failure SET"
related_prs: [7194]
related_issues: [7172, 7174, 6751, 4622]
---

# An issue's diagnosis is a hypothesis — measure the failure set first

## What happened

Issue #7172 reported, correctly, that `scripts/lint-agents-enforcement-tags.py` had validated zero
tags since the ADR-151 corpus split, and prescribed a remedy: *"Resolve the 10 wording drifts (align
tag ↔ heading; decide per case which side is authoritative)"* and *"decide `components` /
`workflow-fidelity`: retire the rule, or repoint the tag."*

The issue was written by a competent agent from a real measurement. Both halves of its remedy were
wrong, and following it would have made the repo worse.

Running the linter against the corpus and **reading the 13 errors** — rather than acting on the
count — split them very differently than the issue did:

| Class | Count | The issue said |
|---|---|---|
| Parser-grammar limits (`/`, ` + `, file-form enforcers) | 10 | "wording drift — align the tag to the heading" |
| Genuine wording drift (both on one line; one a single capital letter) | 2 | — |
| The linter parsing its own tag-legend blockquote | 1 | not mentioned (issue said 12, live was 13) |
| Skills that genuinely do not exist | **0** | "two — retire the rule or repoint the tag" |

10 + 2 + 1 = 13. This table first published `9 + 2 + 1 = 12` — see rule 6 below; the
miscount was mine, in the artifact arguing for measurement.

**Every enforcer named by all 13 tags existed and actually enforced.** Not one tag was factually
wrong. The two tags the issue said named nonexistent skills (`components`, `workflow-fidelity`) named
no skill at all — `SKILL_TAG_RE` captured the leading `[a-z][a-z0-9-]*` of `components.test.ts` and
`workflow-fidelity.ts` and mistook the prefix for a skill slug. Both already pointed at the file that
enforces the rule.

Following the issue would have rewritten ten accurate rule bodies — ten ADR-092 ack rows, each
escalating to mandatory human review — to satisfy a deficient parser. The actual fix (ADR-160)
extends the parser and needs **one** ack row, for an unrelated operator decision. (Two `cq-*`
bodies were edited for the two real wording drifts; `cq-*` is outside the `^(hr|wg)-` ack gate,
so those cost zero ack rows.)

## The transferable rules

**1. An issue's diagnosis is a hypothesis; its remedy inherits every error in it.** A correct
symptom ("the gate validates nothing") does not imply a correct cause. Re-run the failing command and
read the *set*, not the count, before adopting a prescribed fix — especially when the fix is "edit N
human-gated files."

**2. When a gate and its corpus disagree, fix the ungated side.** Rule bodies cost an ack row and a
human review per edit; a linter is ungated code with a test suite. If the corpus is *accurate about
reality* and the parser cannot express it, the parser is the defect. Rewriting documentation to make
a tool pass makes the documentation worse to make the tool green.

**3. A gate that documents its own syntax will lint its own documentation.** The 13th error was a
`> **Tag legend.**` blockquote containing `[hook-enforced: …]`, added by the very PR that discovered
the vacuity. Any linter whose regex matches prose must read only real body lines — and this one now
does, mirroring `lint-rule-bodies.py`.

**4. `argparse` `default=` hides wiring; it does not create it.** The default here *was* vacuous, and
`lefthook.yml` *did* pass the right files. Diagnosing from the default alone would have "fixed" a
gate that still ran nowhere in CI. The real defect was the invocation graph: grep `lefthook.yml`,
`test-all.sh`, and `.github/` before concluding a gate is unwired.

**5. "Everything resolved" and "there was nothing to resolve" must not share an exit code.** Only a
cardinality floor separates them, and the silent one reads as safety. Precedent: `MIN_ASSERTIONS` in
`plugins/soleur/test/net-issue-flow.test.sh`.

**6. Your own count is a claim too — and this file got it wrong twice.** The acceptance criterion
asserted `12 hook + 32 skill` tags from a naive `grep -oE '\[hook-enforced:'`; the derived figure
is `10 + 30` (the naive count included the legend line, plus one empty-bodied `[hook-enforced:]`
and one `[skill-enforced:]` prose mention at `AGENTS.rules.md:120` that the full-tag regex
correctly ignores). Separately, the classification table above first published a breakdown summing
to **12** while describing 13 failures. Both were caught by review, not by me, in the document
whose thesis is "measure the set." Publish the command next to the number
(`cq-assert-anchor-not-bare-token`) — and re-add your own columns.

## The #7174 measurement (preserved here because the issue asked for it)

Issue #7174 named a measurement nobody had taken: *of issues filed against merged PRs in the last 30
days, what fraction would satisfy `Mandated-By` + `Refs` + OPEN?* — with the stated bar that **above
half** would mean the `[mandates-filing]` exemption had made the net-issue-flow gate advisory.

Measured 2026-08-03 over the preceding 30 days: **442 merged PRs, 729 issues filed.** Of 256 merged
PRs with any closing-or-filing activity, **138 would block** at `NET > 0`. Simulating the exemption
against them:

| | tag rule #1 only | tag both rules |
|---|---|---|
| blocked PRs flipping to PASS (strict, label-only) | 2 (1.4%) | 8 (5.8%) |
| blocked PRs flipping to PASS (upper bound, label + keyword proxy) | 10 (7.2%) | 32 (23.2%) |

**Method, stated honestly:** classification used the `deferred-scope-out` / `deferred-automation`
labels plus a keyword proxy; **178 of 256** deferral classifications came from the proxy rather than
the label, which is why this is a bounded range and not a point estimate.

**The bar was not met.** 77–94% of blocked PRs still block under either tagging, so the gate does not
become advisory. The reviewers' *framing* was refuted — but their conclusion was still right, for a
different reason: **nothing writes the claim.** Every writer emits the first rule id literally
(`ship/SKILL.md` Phase 5.5, `work/SKILL.md` operator-only deferral row); no writer anywhere emits
`Mandated-By: wg-when-deferring-a-capability-create-a`, so an agent citing it would be hand-authoring
exactly the free-form reason the closed vocabulary exists to prevent.

The lesson is the shape, not the numbers: **a measurement can refute an argument's stated reason and
still confirm its conclusion.** Report both halves. Recording only "the reviewers were right" would
have lost the fact that the advisory-gate fear was unfounded — and that fear is what the next person
will reach for when deciding whether to tag a third rule.

## Prevention

- `scripts/lint-agents-enforcement-tags.py` now carries the grammar, the body-line filter, and the vacuity floor.
- Registered in `scripts/test-all.sh` as `-live` + `-unit`, so it runs in CI rather than pre-commit only.
- `scripts/lint-orphan-test-suites.sh` exclusion list is now **empty** — the goal state.
- ADR-160 records the corpus-is-authoritative decision and the supported tag vocabulary.

## Session Errors

1. **AC3 asserted `12 hook + 32 skill` tags from a naive `grep -oE '\[hook-enforced:'` prefix count; the derived figure is `10 + 30`.** The naive count included the tag-legend blockquote and two empty-bodied `[hook-enforced:]` prose mentions the full-tag regex correctly ignores. — **Recovery:** reconciled exactly (full-regex 11/31, body-line 10/30, one excluded line) and rewrote the AC to publish the command beside the number. — **Prevention:** already covered by `cq-assert-anchor-not-bare-token` and the work-skill "counts must be derived from the as-written file" bullet; this was a one-off failure to apply a known rule, not a gap.

2. **`tr -d '`- '` emitted `range-endpoints … in reverse collating sequence order`** in a path-extraction one-liner. — **Recovery:** re-extracted with `sed 's/^- `//; s/`.*//'`. — **Prevention:** one-off; a `-` inside a `tr` set must be first or last, or escaped.

3. **Three `test-all.sh` runs were reaped mid-flight** (`status: killed`, then `exit 144`, then a `Monitor` script reaped on the same clock), and a fourth sat lock-queued behind five sibling worktrees at load 55 on 16 cores. Each reaped run was clean — 459-470 suites `[ok]`, zero `[FAIL]`. — **Recovery:** distinguished reap-vs-failure mechanically (no `[FAIL]`, no terminal marker, no rc file), then relaunched detached with `setsid nohup` and sharded via `TEST_GROUP=`. — **Prevention:** routed to `plugins/soleur/skills/work/SKILL.md` as a bullet on the full-suite exit gate, since the failure is domain-scoped to that gate and `AGENTS.rules.md` is at its per-rule cap.

4. **A `Monitor` watching for the run's rc file was itself killed at 144**, reporting a monitor failure that reads like a suite failure. — **Recovery:** re-armed under a ~9-minute timeout so it exits on its own clock. — **Prevention:** same routed bullet as #3.

5. **Edited `plugins/soleur/skills/work/SKILL.md` via the bare-repo path while worktrees existed; the PreToolUse guard denied the write.** — **Recovery:** re-applied against the worktree-absolute path and verified with `git status --short` that the file was listed as modified. — **Prevention:** already hook-enforced (the guard fired and named the correct path) and already documented in compound's Route-to-Definition step; no new rule warranted.
