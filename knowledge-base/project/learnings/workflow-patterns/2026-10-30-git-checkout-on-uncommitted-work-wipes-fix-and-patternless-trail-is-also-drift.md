---
date: 2026-10-30
branch: feat-one-shot-11600-job-log-step-attribution
issue: 11600
pr: 11603
category: workflow-patterns
---

# Two learnings from the UNKNOWN STEP recovery fix

## 1. `git checkout <file>` to revert a mutation test wipes uncommitted work

While mutation-testing the probe (BOM single-strip, dropped `ts >= ps` gate),
I reverted each mutant with `git checkout scripts/.../probe.sh` — which
restores the file from the index, i.e. HEAD, i.e. the PRE-FIX version, because
the fix had not been committed yet. Both mutation rounds silently ran against
the pre-fix probe (the "6 RED" I measured was the original RED state, not the
mutant's). Recovery: re-apply the fix and commit BEFORE mutation testing.

**Prevention:** mutation-test a guard either (a) after committing the
implementation, so `git checkout` reverts to the fix, or (b) with a file
backup (`cp probe.sh /tmp/p.bak; ...; mv /tmp/p.bak probe.sh`). Never
`git checkout` a file carrying uncommitted work you intend to keep — this is
the same class as the "worktree hard-reset eats a sibling's commit" scars,
one level down (single file, same mechanism).

## 2. A patternless-but-nonempty trail is the same degraded channel as an empty one

The first cut triggered UNKNOWN STEP recovery only on an EMPTY named-attributed
trail. Four review seats converged on the gap: partial attribution (or a
truncated section) leaves emitted lines under the step name while the
pointer/ready lines sit under UNKNOWN STEP — a success job could then drop a
proven boot quietly (rc=2, owed=0). The trigger must be "the trail lacks
trail-pattern lines", and a success job with no pattern lines post-recovery is
CANNOT ESTABLISH regardless of how many other lines it emitted.

Corollary verified during the same fix: the recovered region must REPLACE the
named trail, not merge — the `##[group]Run` region is the step's whole emitted
output, a superset of whatever survived attribution.

Also measured: `date -u -d "<ISO> - 10 minutes"` misparses the relative clause
on this platform (yielded +10h, not -10m); go through epoch arithmetic
(`date -d "@$((epoch - 600))"`) in fixtures.
