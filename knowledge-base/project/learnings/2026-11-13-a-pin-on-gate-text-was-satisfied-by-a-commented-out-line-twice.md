---
title: A pin on gate text was satisfied by a commented-out line, in two review rounds running
date: 2026-11-13
category: workflow-issues
module: review fix rounds, static guards over skill prose
tags: [review, fix-round, pin-test, gate-text, whole-block, residuals]
issue: 12656
pr: 12706
---

# Learning: a pin on gate text was satisfied by a commented-out line, in two review rounds running

## Problem

PR #12706 routes the last agent arm sites through the review-evidence arm check, and adds a static guard,
`plugins/soleur/test/arm-check-sites.test.sh`, over the skill prose that holds the gate text. Two pieces of that text
matter most: the canonical arm-check statement in `review-evidence-comment.md` `## Arm check`, which every site pastes,
and the admin-merge hatch's two readiness fences in `settle-then-admin-merge.md`, which tie the evidence head to the
head being merged.

The first guard checked each of them by **presence**: `grep -F` for a fragment, or `str.find` for a line, anywhere in
the file or the fence. Two consecutive targeted fix rounds each found that a presence check is satisfied by a line that
no longer runs:

- Round 1 (A7, the hatch): the tie `[ "${H:?…}" = "$SHA" ] || { …; exit 4; }` commented out, `exit 4` changed to
  `true`, a `true ||` prefix, or the line wrapped in `echo '…'` all stayed green. With the tie gone, an agent that never
  pastes the check reaches `admin-merge-ready.sh` and step 4 runs `--admin` on an unreviewed head.
- Round 2 (A3, the canonical check): the refusal line `|| { echo "ARM_CHECK refused…"; exit 1; }` commented out, or a
  `|| true \` line inserted above it, stayed green. Run under stubs with no evidence comment, both versions armed. Every
  site inherits the bypass.

Round 1's fix compared whole LINES. Round 2 then found the cross-line version of the same shape (a `true || \` on the
line above the tie, a `trap 'exit 0' EXIT`), which line-by-line equality cannot see.

## Solution

Pin each gate block as a **whole block**: the fence's lines with indentation stripped, compared line for line against a
literal in the test, plus a cardinality check (exactly one bash fence in `## Arm check`, and the canonical file assigns
`H` exactly once). Any added, removed, commented or neutered line in the block is a red row naming the first differing
line. The per-line and per-fragment checks stay, because their failure messages are more specific.

Then state the test's contract and residuals in its header (R1–R5: text hidden by a construct that keeps it intact,
quote-state tricks inside a joined line, sites outside the list, runtime properties the dry runs own, and A6 prose
synonyms), so that a later shape inside a residual is recorded as "covered by R<n>" rather than starting another round.

## Key Insight

When the guarded artifact is gate text that an agent pastes or runs, a pin that checks for **presence** (a substring, a
line anywhere, a fragment) is satisfied by a commented or neutered copy of exactly the text it looks for. Pin the
whole block on the first round. Each finer grain (fragment, then line) only moves the bypass one level out, and each
round finds the next level.

This is a recurrence. `2026-11-11-each-fix-round-found-the-next-sibling-until-the-test-stated-its-residuals.md` already
said to rule a pin test's contract once a round's findings are siblings of the last round's. I applied that only at
round 2. Its rule is about WHEN to stop adding shapes. This learning adds WHAT to pin, so the sibling rounds do not start.

## Session Errors

1. **Plan-phase advisor spawned with a placeholder prompt** (forwarded from session-state.md). Recovery: re-sent the
   real payload via SendMessage. **Prevention:** build the curated payload file before the spawn call and pass its path.
2. **deepen-plan's post-run menu skipped** (forwarded). Recovery: the brief said to skip it. **Prevention:** none
   needed; recorded so the skip is visible.
3. **A python edit run as a nested heredoc was blocked by the git-commit hook parser.** Recovery: wrote the patch to a
   scratchpad `.py` file and ran it. **Prevention:** for multi-line patches, write a script file first.
4. **Escapes lost in a python patch** (`\'`, `$'\n'` in rows m22a/m22b). Recovery: raw-string patch. **Prevention:**
   use raw strings for patches that carry shell quoting.
5. **A6 false positive on `net-issue-flow.sh`** ("exempt pr="). Recovery: case-sensitive grep, later a left boundary
   and site-file scoping. **Prevention:** run a new denylist regex over its whole scope before committing it.
6. **M16d anchor matched more than once.** Recovery: anchored on `\n## Arm check\n`. **Prevention:** the `edit`
   helper's exactly-once check caught it; keep that helper.
7. **admin-merge-ready-wiring went red on a literal `PUT /pulls/{n}/merge`** in the canonical file, a repo-wide
   lint no selected suite referenced. Recovery: reworded. **Prevention:** already covered by the work skill's
   "a file-selected suite set cannot see a repo-global ratchet"; run `scripts/test-all.sh --affected` before push.
8. **Rule-body lint failed after the `AGENTS.rules.md` edit.** Recovery: `lint-rule-bodies.py --write` plus an ack
   line. **Prevention:** lint-enforced already.
9. **Long suites hit the 590 s tool timeout** (ci-head-verdict, monitor-pr-checks). Recovery: background run with a
   1500 s bound and an `RC=` line in the log. **Prevention:** start known-long suites in the background up front.
10. **`MIN_CASES` set one above the rows that ran** (60 vs 59). Recovery: corrected in the same commit. **Prevention:**
    the floor check caught it; count rows by grep, not by arithmetic.
11. **`emit-review-trailer.sh --agents-ran` given names instead of a count.** Recovery: read its usage. **Prevention:**
    read a script's usage before the first call.
12. **A trailing `ls` glob exited 2** on missing files. One-off.
13. **Hatch prose claimed the refusal is "the block's only line"** without running it; git prints a `fatal:` line first
    when the PR has no evidence (security fix-round F1). Recovery: route on "exit 1 whose last line is
    `ARM_CHECK refused`". **Prevention:** run the refusal path and read its full stdout before describing it in prose.
14. **Presence pins on gate text, found in two rounds running** (the subject of this learning). Recovery: whole-block
    pins plus a stated contract. **Prevention:** the bullet routed to
    `plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md` step 4.

## Tags
category: workflow-issues
module: review fix rounds
