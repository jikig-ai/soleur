# Learning: a re-scope removed the event a post-merge probe was waiting for, and only running the probe live found it

## Problem

PR #10320 was re-scoped mid-flight (a sibling PR landed the host-template half), so it no longer changed any registry host
bytes and no registry boot could follow its merge. Its post-merge probe (`registry-clientip-alert-7530.sh`) still gated on
"the newest boot began after the merge" and its 136-row suite stayed green, because every fixture put a boot after the
merge. The first live run after the merge returned `n_no_post_merge_boot` (exit 2, NOT YET) and would have stayed there
forever, leaving the tracker open and the legal records "NOT in force".

## Solution

Anchor the gate on the registry template's last delivery (PR #10322) instead of this PR's merge; three exit-3 verdicts for an
unreadable, unmerged or untimed template PR; six cases and four mutants (PR #10411). The live run then passed
(`population=1152 as_written=0 control=1152`) and the sweeper closed #7530. A one-seat review of the fix found that the
case meant to pin the boot read's lookback start sat inside the lookback, so a regression of that line stayed green: the
case now places the template delivery outside it.

## Key Insight

A probe's gates encode an assumption about WHAT EVENT the PR causes (here: a host replace). Re-scoping a PR changes that
event without touching the probe, and fixtures built around the old event keep passing. After any re-scope, re-read every
post-merge probe's gates against what the PR now actually does, and run the probe once against the live world before merge
(its NOT-YET arms are cheap to read) rather than after.

## Session Errors

1. **Probe gate unreachable after the re-scope (found post-merge).** Recovery: PR #10411. **Prevention:** the re-scope
   checklist now includes "re-derive each post-merge probe's gates from the new diff".
2. **Merge queue dequeued #10320 once for a conflict with a sibling's new Better Stack alert** (adjacent-append conflicts in
   ADR-218, the runbook and the CI workflow, plus an exploration-count anchor in a mutation suite). Recovery: rebase, keep both
   sides, renumber the alert ordinal. **Prevention:** none beyond rebasing promptly; expected on append-only registries.
3. **A CI shard timed out once and a gitleaks download failed once** (unrelated infrastructure); each was re-run once.

## Tags

category: workflow-issues
module: post-merge follow-through probes, registry clientIP alert (#7530)
