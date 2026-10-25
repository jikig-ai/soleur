# Learning: a monitor's alert text outlived the decision it cites, and its probe never implemented the ADR bound

## Problem

#8856 (rehearsal skip monitor red) said "the deferred pre-baked image (#7535) is owed". #7535 had been closed 2026-09-17 as "image cut on measurement" ($0 saving on a public repo with standard runners; 0 operator-visible seconds). The alert text, probe comments, ADR-188 and the probe's tests kept saying the image was owed. Separately, ADR-188 bounds skips at "more than 1 in 20 post-merge runs", but `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` FAILs on any single hit (`hits -gt 0`, counting marker lines, not runs). One apt blip therefore keeps the monitor red until it ages out of a 20-run window.

## Solution

Brainstorm re-framed #8856 with the operator: make the probe count runs with a skip and FAIL when `runs_with_skip * 20 > observed`, drop "#7535 owed" from every text site, and point the alert at diagnosing the rc 100/125 declines. Bundled with #10918 (escalation gets its own title) as PR B; the release cache fix (#10917) is PR A.

## Key Insight

A monitor is two artifacts that drift independently: the code that decides, and the prose that says what to do about it. Check both against the record they cite. For any alert that quotes an ADR bound, read the verdict line and confirm the bound is what the code computes; for any alert that names a remedy issue, run `gh issue view <N> --json state,closedAt,title` before treating the remedy as owed.

## Session Errors

- **Zero-width character in a path I typed** — Recovery: retyped the command. Prevention: none beyond reading the error; one-off.
- **Ended a turn naming a next action** (stop hook `unkept-promise-hook.sh`) — Recovery: ended with an explicit `Paused:` sentence. Prevention: already hook-enforced.
- **Inherited framing** ("image owed") copied through alert text, tests and an ADR — Recovery: premise probe at brainstorm Phase 1.0.5. Prevention: the closed-remedy and ADR-rate checks in Key Insight.

## Tags

category: workflow-issues
module: ci-monitoring
