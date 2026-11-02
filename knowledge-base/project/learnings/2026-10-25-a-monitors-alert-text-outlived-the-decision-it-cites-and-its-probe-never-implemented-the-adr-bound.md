# Learning: a monitor's alert text outlived the decision it cites, and its probe never implemented the ADR bound

## Problem

#8856 (rehearsal skip monitor red) said "the deferred pre-baked image (#7535) is owed". #7535 had been closed 2026-09-17 as "image cut on measurement" ($0 saving on a public repo with standard runners; 0 operator-visible seconds). The alert text, probe comments, ADR-188 and the probe's tests kept saying the image was owed. Separately, ADR-188 bounds skips at "more than 1 in 20 post-merge runs", but `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` FAILs on any single hit (`hits -gt 0`, counting marker lines, not runs). One apt blip therefore keeps the monitor red until it ages out of a 20-run window.

## Solution

Brainstorm re-framed #8856 with the operator: count runs with a skip, drop "#7535 owed" from every text site, and point the alert at the decline named in the skip lines. Bundled with #10918 (escalation gets its own title) as PR B; the release cache fix (#10917) is PR A. The 11-seat review and four CTO rulings settled the final predicate: FAIL needs at least 2 skipping runs and more than 1 in 20 observed; below 10 observed runs the verdict is TRANSIENT (a lone skip is ADR-188's accepted transient); only push/dispatch runs count; the one alert issue is retitled when the verdict class changes.

## Key Insight

A monitor is two artifacts that drift independently: the code that decides, and the prose that says what to do about it. Check both against the record they cite. For any alert that quotes an ADR bound, read the verdict line and confirm the bound is what the code computes; for any alert that names a remedy issue, run `gh issue view <N> --json state,closedAt,title` before treating the remedy as owed.

Four more shapes surfaced at review, each invisible to a green suite: (1) a ratio `skips * N > observed` degenerates to any-hit exactly when the sample is thin, which is the case that motivated the change, so give the ratio a minimum-sample floor and make a lone skip non-alerting; (2) an alert issue shared across verdicts with a frozen title buries the next, different verdict as a comment under the wrong title, so retitle on a verdict change and open every comment with the verdict; (3) a population filter keyed on a branch name (`--branch main`) admits fork PR runs whose output the PR author controls, so filter on the event; (4) a probe exit code reused from another contract (rc 3 is the sweeper's CANNOT ESTABLISH) should carry that contract's words.

## Session Errors

- **Inherited framing** ("image owed") copied through alert text, tests and an ADR — Recovery: premise probe at brainstorm Phase 1.0.5. Prevention: the closed-remedy and ADR-rate checks in Key Insight.
- **Review briefs described the skip FAIL as exiting rc 3** (only the consecutive-TRANSIENT escalation does) — Recovery: the architecture seat corrected it. Prevention: write the exit-code table into a seat brief from the code, not from memory.
- **Provenance misjudged for the CONCUR gate**: a gap was called pre-existing although the PR edits that very filter line — Recovery: the gate dissented and the gap became a documented accepted bound. Prevention: judge provenance with `git diff origin/main...HEAD | grep '^+' | grep <pattern>`, not "the file is unchanged".
- **A hand-written Monitor read a cleared `autoMergeRequest` as a dequeue** (GitHub clears it on enqueue) — Recovery: confirmed with `sync-pr-behind.sh --queue-state`. Prevention: use the canonical Phase 7 loop or the queue-state script; do not infer queue membership from one field.
- **A ratchet regression** (`fixture-relative-assert`, +2 sites from a test helper writing to `"$root/..."`) shipped in an early code commit and surfaced only at ship because the affected-tests gate was budget-deferred — Recovery: rooted the helper at the `mktemp` sandbox. Prevention: run the repo-global ratchets over a changed test file before the first push.

## Tags

category: workflow-issues
module: ci-monitoring
