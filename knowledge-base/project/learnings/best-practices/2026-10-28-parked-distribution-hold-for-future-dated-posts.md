---
module: Content Distribution Pipeline
date: 2026-10-28
problem_type: best_practice
component: development_workflow
symptoms:
  - "A distribution file for a post dated three weeks out would auto-promote on the next publisher run if filed as status: draft"
  - "The pipeline needed 'content ready now, publishes later' and no hold mechanism existed"
  - "The only inert status also forfeits the publish_date reservation"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: medium
tags: [distribution, content-publisher, follow-through, parked-status, blog]
status: open
synced_to: [social-distribute]
---

# Troubleshooting: Holding a future-dated distribution file without auto-promoting

## Problem

The arc-synthesis blog post (#11362) was content-complete on 2026-10-28 but
scheduled to publish 2026-11-19. Its distribution file had to exist now (the
post links and calendar row ship in the same PR) yet must NOT distribute until
the publish date. A `status: draft` file is picked up by the publisher cron's
`isReadyDraft` gate and would have promoted ~2026-10-29.

## Environment

- Module: Content Distribution Pipeline (`apps/web-platform/server/...` publisher cron + `knowledge-base/marketing/distribution-content/`)
- Affected Component: `cron-content-publisher.ts`, `content-promotion.ts`, the follow-through sweeper
- Date: 2026-10-28

## Symptoms

- `isReadyDraft` requires `status === "draft"` (`content-promotion.ts:181-187`), so `draft` promotes immediately — too early.
- A file with no draft status stays inert but also fails to reserve the publish date: `publish_date` is what occupies the slot in `cron-content-publisher.ts:292` (`occupied`).
- The flip from "held" to "schedulable" is a wall-clock event in a session that ends at merge — exactly the class the follow-through sweeper exists for.

## What Didn't Work

**Attempted Solution 1:** Ship the distribution file as `status: draft`.

- **Why it failed:** `isReadyDraft` admits drafts to the next publisher run — the Nov-19 post would have distributed ~Oct-29, three weeks early.

**Attempted Solution 2:** Leave the distribution file out of the PR entirely.

- **Why it failed:** The PR's campaign-calendar row and content-strategy pipeline row reference it; a follow-up PR would un-bundle the content unit and lose the review linkage to the post it promotes.

## Session Errors

**collision-precheck self-flagged the pipeline's own draft PR** — Recovery: verified the flagged PR was this pipeline's own #11378, not a foreign duplicate — Prevention: treat a collision-precheck hit against the session's own draft PR as advisory; verify ownership before aborting.

**markdownlint MD004 (inconsistent list marker) caught pre-commit** — Recovery: fixed the marker style and re-committed — Prevention: lint-sensitive prose edits belong in the same pass as the content edit, not a trailing commit.

**Sequential-fallback review coverage** — plan-phase research fan-out and the review panel ran inline because plugin subagents were unavailable in the spawn context — Recovery: `Reviewed-Coverage: sequential-fallback 11/11 agents` disclosed on the commit trailer and the PR `Review-Evidence:` comment — Prevention: carry the coverage token verbatim into ship-phase summaries; never let a degraded coverage read as `full`.

**seo-aeo-drift-guard asserts ogImage frontmatter presence, not file existence (null guardrail, step-3.6 finding)** — Recovery: a mutation deleting the og PNG leaves the guard green; flagged in the PR body and filed as a tracked `type/chore` follow-up at ship — Prevention: the drift guard should assert the referenced `ogImage` file exists on disk, not only that the frontmatter key is present (proposed: extend `seo-aeo-drift-guard.test.ts` + the guard's assertion set — filed, not auto-applied).

## Solution

**`status: parked` + `publish_date` + a notify-only follow-through probe.**

- `status: parked` is excluded by `isReadyDraft`, so the file can ship today and stay inert — while its `publish_date: 2026-11-19` still reserves the slot (`occupied`), so no sibling post double-books the window.
- `scripts/followthroughs/parked-green-synthesis-11362.sh` is a NOTIFY-ONLY probe: exit 2 pre-window, 5 in-window while `status: parked` persists, 3 if the file is missing — never 0/1 (0 would close the tracker, 1 reads as regression; the sweeper's 2/3/5 sub-vocabulary is `NOT YET` / `CANNOT ESTABLISH` / `ACTION REQUIRED`).
- The `<!-- soleur:followthrough script=... earliest=2026-11-19T00:00:00Z secrets= -->` directive goes on the tracker issue body **unfenced, at column 0** (`gh issue edit` bypasses the create-gate, so enrolment is verified by re-reading the body, and the sweeper parses bodies — never comments).
- The tracker issue must be **open** when `earliest` passes: the sweeper's closed-set lookback (14 d) is shorter than the parked window, so a tracker closed at merge-time is invisible by Nov 19. When the delivering PR body carries `Closes #N` for the same issue, reopen it post-merge with the enrolment comment.

**Commands run:**

```bash
# enrolment verification on the live issue
gh issue view 11362 --json body --jq .body | grep -c '^<!-- soleur:followthrough'
gh issue view 11362 --json labels --jq '.labels[].name' | grep -c '^follow-through$'
# real sweeper dry-run post-merge
gh workflow run scheduled-followthrough-sweeper.yml -f dry_run=true
```

## Why This Works

The contract splits into three independent mechanisms that compose: status (what the publisher may pick up), `publish_date` (what the calendar reserves), and the sweeper directive (who wakes the human). `parked` answers the first; `publish_date` answers the second; the notify-only probe answers the third without ever taking the close verb it is not entitled to.

## Prevention

- For any "content ready, publish later" item: `status: parked` + `publish_date`, never `draft` (drafts promote on the next cron run).
- A notify-only probe MUST assert the never-0/never-1 invariant in its own suite and say so in its header.
- Enrolment on a pre-existing issue: directive in the BODY at column 0 (comments enrol nothing), `follow-through` label, and the issue OPEN at `earliest` — reopen it if the delivering PR's `Closes #N` fired first.
- When the publish slot moves, ALL date sites move together: filename, frontmatter `date:`, redirect key, `publish_date:`, probe `WINDOW_DATE`, directive `earliest=`.

## Related Issues

- Convention: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`
- Tracker: issue #11362 (doubles as the follow-through tracker — opened for the parked window, closed by the responder at flip time per `tasks.md` 5.1)
- Epic: #10971 (twelve-child test-suite arc the post synthesizes)
