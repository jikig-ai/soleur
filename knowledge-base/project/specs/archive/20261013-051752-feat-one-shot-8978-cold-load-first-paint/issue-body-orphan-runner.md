Mandated-By: wg-when-a-workflow-gap-causes-a-mistake-fix
User-Impact: developer velocity — an orphaned `test-all.sh --affected` run holds the repo-global flock for hours, serially blocking every sibling commit gate.
Fix-Size: 60 lines / 1 file (scripts/test-all.sh parent-death watchdog or PID liveness check on the flock holder).

## Summary

Observed during PR #8984 (2026-09-26): `git commit` under lefthook spawned `test-all.sh --affected`. The lefthook wrapper was terminated while the runner kept executing — orphaned, holding the repo-global flock, and invisible to the dead parent that would have consumed its result. The commit silently never landed; a second commit queued behind the orphan's lock for ~1.5 h.

## Suggested fix

- Have `test-all.sh` exit when its parent process dies (PPID poll or PR_SET_PDEATHSIG via a wrapper), OR
- Have the flock holder record its liveness so waiters can detect a dead holder and reclaim.

## Reproduction notes

`ps` showed the suite continuing after the parent lefthook process was gone; run output accumulated under /var/tmp/soleur-run.<pid>.*/ with no consumer. Killed manually via `kill <pid>`; flock released immediately.

Refs #8940 (adjacent test-all observability issue)
