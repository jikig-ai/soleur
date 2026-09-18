---
title: "Three sentences I pasted from the plan were inherited, not measured"
date: 2026-09-18
category: workflow-issues
module: inngest cutover records / one-shot plan→work handoff / review
issue: 7695
pr: 8314
tags: [inherited-claims, plan-prose, citations, runbook, adr, review, measurement]
problem_type: workflow_issue
component: development_workflow
root_cause: missing_workflow_step
severity: medium
symptoms:
  - "ADR-100 addendum and an archived plan addendum cited #7761 as a probe_schema fix; it is the Doppler-name root-exec fix (PR #7768)"
  - "Runbook callout and a posted #7777 comment said G3.7 refuses into terminal aborted; G3.7 exits before any write"
  - "Plan said third host across two replaces; probe rows' instance_id showed the ninth host across eight"
synced_to: [work]
---

# Learning: three sentences I pasted from the plan were inherited, not measured

## Problem

PR #8314 reconciles the `inngest-volume-recut` records (#7695) against the 2026-09-15
dedicated-host cutover. It is docs-only, and the plan (written by the one-shot planning
subagent, then deepened by four research agents and reviewed by a four-agent panel) carried a
paste-ready runbook callout, an ADR-100 addendum spec and a 2026-09-02 plan addendum spec. Three
sentences in that prose were wrong, and all three reached durable records before anything caught
them:

- **A count.** "the third host since 2026-09-04, across two more replaces". The probe rows'
  `instance_id` over 15 days list nine dedicated hosts since Merge B — five on 09-09 (the
  `probe_schema` 4→7 iterations), one on 09-10, two on 09-17. Caught at /work Phase 0 only
  because the callout named a figure I could re-derive from a read I was already running.
- **A citation.** "the two later gate fixes #7761/#8019". #7761 is *"a Doppler secret NAME is
  an arbitrary-command-as-root path"* (2026-09-02, fixed by PR #7768) — nothing to do with the
  probe. It went into the ADR-100 addendum and the archived plan's addendum verbatim; the
  git-history and pattern seats both caught it at review.
- **A mechanism.** "`op=arm` G1 admits the flag but G3.7 and the on-host latch refuse into
  terminal `aborted`". `scripts/cutover-inngest.sh`'s G3.7 `latched` branch prints its refusal
  and `exit 1`s BEFORE G4/G5 write anything, so the flag stays `rolled-back`; only the on-host
  latch (reached if `FLUSH_LATCH_SINCE` is narrowed) drives `aborted`. It went into the runbook
  callout, the plan, and a comment I posted on #7777 — an outward-facing record that needed a
  correction comment. The security seat caught it by reading the script.

Each sentence had the same provenance: the planning subagent wrote it, deepen re-verified
attribution for commits and run ids (16/16 "confirmed") but not the *label* attached to #7761
nor the *order of operations* inside G3.7, and /work pasted it because it read as established.

## Solution

- Re-measured the count from the rows (`betterstack-query.sh --since 15d`, grouped by
  `instance_id`) and used the measured figures in every record; the plan's five stale sites got
  inline amendment markers rather than silent edits.
- Replaced "#7761, #8019" with "the later `probe_schema` fixes through #8019" in ADR-100 and the
  archived addendum.
- Rewrote the mechanism sentence in the runbook and the plan, and appended a correction comment
  to #7777 (the outward record) rather than editing the original.
- Recorded the pattern reviewer's F6 disambiguation in the runbook so the 2026-08-25 "latch
  preserved" clause is scoped to the file's *location* (the 2026-09-09 row read
  `flush_latched=false`).

## Key Insight

**A plan's paste-ready prose is a set of inherited sentences, and the pipeline's re-derivation
reflexes cover numbers, not labels or mechanisms.** `work/SKILL.md` already says plan-quoted
numbers and issue-comment claims are preconditions; deepen's attribution pass confirms that a
cited id *exists*. Neither asks whether the id is *the thing the sentence says it is*, nor
whether a "X refuses/drives Y" sentence matches the code's control flow. Three cheap gates
before pasting any plan sentence into a runbook, ADR, or issue comment:

1. `gh issue view N --json title` (or `gh pr view N --json title`) for every `#N` the sentence
   labels — the title is the label's falsifier.
2. For every mechanism sentence ("G3.7 refuses into `aborted`", "the timer stops X"), read the
   code path and name the line that performs the transition; if the transition is a different
   component's, the sentence is wrong even when its conclusion holds.
3. For every count, name the read that produces it and run it (the count is the one class the
   existing rules already cover — and it was the only one of the three /work caught).

Outward-facing records (issue comments) are the highest-cost place for this class: they cannot
be amended in place, so a wrong mechanism sentence costs a correction comment that readers of
the original will not see.

## Session Errors

1. **(fwd) `gh issue create` for #8316 refused by the filing hook (no `Mandated-By:` line);
   retried OK.** — Recovery: added the line. — Prevention: the filing template in
   `review/SKILL.md` §5 names it; read the hook's deny text before retrying.
2. **(fwd) CTO domain review claimed `article-30-register.md` is not in PR 8248's set; measured
   false.** — Recovery: plan records the correction; file not edited either way. — Prevention:
   an agent's file-set claim is verified with `gh pr diff N --name-only`, never trusted.
3. **(fwd) Playwright MCP failed to connect (unused this phase).** — Recovery: none needed. —
   Prevention: n/a.
4. **Plan's "third host / two replaces" was false (nine / eight).** — Recovery: measured from
   probe rows at /work Phase 0; records use measured figures; plan sites amended. — Prevention:
   gate 3 above.
5. **#7761 cited as a probe/gate fix in ADR-100 + archived addendum.** — Recovery: review
   caught it; replaced with "through #8019". — Prevention: gate 1 above (routed to
   `work/SKILL.md`).
6. **"G3.7 … refuse into terminal `aborted`" in runbook, plan and a posted #7777 comment.** —
   Recovery: rewritten; correction comment on #7777. — Prevention: gate 2 above.
7. **Runbook commit failed markdown-lint MD004: a wrapped line began with `+`.** — Recovery:
   rewrapped. — Prevention: after `textwrap`, grep the result for lines starting `+`/`-`/`*`
   inside a blockquote.
8. **A process-name probe with the full-command-line flag was blocked by the self-match hook.**
   — Recovery: used the bare-name form. — Prevention: documented; use the name form.
9. **`test-all.sh` REFUSED rc=4 (sibling run in another worktree).** — Recovery: consumer-derived
   substitute suites (11/12 green; the red is pre-existing #8263). — Prevention: documented path;
   `--capacity` first.
10. **`guardrails.test.sh` 122/123 — "lone kb-index sentinel" fails on a pristine copy of
    origin/main's hooks too.** — Recovery: confirmed pre-existing, tracked as #8263. —
    Prevention: none new.
11. **Plan AC2 literal `redis_keys=1081` stale at /work (1261).** — Recovery: AC amended in place
    with the measured value and a marker. — Prevention: ACs quoting a moving row value should
    reference `measurements.md`, not a literal.
12. **Plan's paste-ready text contained "not retired" while its own Sharp Edge required
    `grep -ci retired` → 0.** — Recovery: "retire-or-keep undecided". — Prevention: run a plan's
    own Sharp-Edge greps against its own paste-ready blocks at deepen.
13. **git-history seat reported "four moves deferred, files remain on main" and "#7761 opened
    2026-09-18" — both false.** — Recovery: verified with `ls` and `gh issue view` before acting.
    — Prevention: an agent-reported fact is verified against the tree before it changes a
    disposition (`review/SKILL.md` already says so).
14. **`$$` in a scratch filename differed between Bash calls → file not found.** — Recovery:
    fixed name under `/var/tmp`. — Prevention: `mktemp` and echo the path, or a fixed
    session-scoped name; never `$$` across calls.
15. **`closingIssuesReferences` read `[]` immediately after `gh pr edit --body`.** — Recovery:
    re-queried after ~8 s → `[7695,8015,8017]`. — Prevention: treat the first read after a body
    edit as unsettled; re-query before asserting.

## Related

- `knowledge-base/project/learnings/2026-09-18-the-measured-facts-my-resume-brief-handed-me-were-the-defects.md`
  — the resume-brief instance of the same class (inherited "measured" facts).
- `knowledge-base/project/learnings/2026-09-14-the-sweep-that-retired-false-sentences-wrote-new-ones-from-my-own-issue-comment.md`
  — the issue-comment instance.
- `knowledge-base/project/learnings/2026-09-11-every-sentence-my-runbook-inherited-was-false-when-measured.md`
  — runbook prose inherited without measurement.
