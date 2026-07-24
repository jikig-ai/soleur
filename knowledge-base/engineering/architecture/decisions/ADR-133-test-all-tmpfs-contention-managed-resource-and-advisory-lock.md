---
title: The local test runner treats the shared tmpfs as a managed resource and serialises worktrees via an advisory lock
status: active
date: 2026-07-22
---

# ADR-133: `test-all.sh` — managed tmpfs + advisory cross-worktree lock

## Context

Parallel worktrees are this repo's documented workflow, but two sessions running
`scripts/test-all.sh` concurrently could produce failures that look like real
regressions (#6789, prior data points #6726, #4096, #3817/#4128). The only
mitigation was prose in `plugins/soleur/skills/work/SKILL.md` telling the agent
to run `ps -ef | grep test-all` and wait — detection guidance for a human, not
isolation. Every overlap was serialised by hand, and a contended run read as a
bug that did not exist.

The recorded cause in `work/SKILL.md` named `skill-security-scan`'s
`.scan-meta.json` plus the semgrep bootstrap as "the known pair" of colliding
shared paths. Both halves were refuted by measurement (see Alternatives
Considered). The actual contended resource is **capacity**, not a name: every
suite's `mktemp` lands in the same machine-global, RAM-backed 4 GiB `/tmp`
tmpfs, measured at 86% full with swap exhausted. A second run competes for the
memory the first is holding, which is exactly the condition under which the two
implicated suites' documented timeout-flake class fires.

## Decision

1. **Instrumentation ships ahead of every fix.** `scripts/lib/test-contention.sh`
   is observe-only (creates no files, takes no locks, deletes nothing). It prints
   a contention preamble (`/tmp` + runtime-dir headroom, sibling `test-all.sh`
   runs resolved to their worktrees via `/proc/<pid>/cwd`, machine load) and
   named banners (`LOW_TMP_HEADROOM` / `SIBLING_RUN_DETECTED`) so a contended run
   is self-identifying and a false RED is never again diagnosed as a regression.
   A per-suite `/tmp` entry-count delta, appended to the existing
   `TEST_TIMING_LOG` channel, is the probe for a residual shared-tempfile
   hypothesis.

2. **The shared tmpfs is a managed, reaped resource — not unbounded scratch.**
   `scripts/tmpfs-guard.sh` (already a 5-minute cron) is extended beyond its
   `.output`-only scope to reap stale, large, own-uid `/tmp` scratch entries,
   gated on age **and** size **and** ownership **and** liveness, never protected
   session dirs. `skill-security-scan`'s per-pid `meta_dir` — a measured 12,889
   leaked dirs with no cleanup — is age-reaped at run-scan startup.

3. **Worktrees serialise via a git-common-dir ADVISORY lock.** `test-all.sh`
   reuses `session-state.sh`'s `acquire_lock` (no new primitive, no modification
   to the shared one). The lock is advisory: on timeout it proceeds with a
   `LOCK_CONTENDED_PROCEEDING` banner and NEVER aborts, so no failure mode of the
   lock can prevent or wedge a test run. CI is exempt; the kill switch and
   fail-open behaviour of the primitive are inherited.

## Alternatives Considered

- **`.scan-meta.json` collides across worktrees (the recorded H2).** REFUTED.
  `run-scan.sh` PID-scopes it to `${XDG_RUNTIME_DIR:-/tmp}/skill-security-scan-$$`;
  `git log -S'skill-security-scan-$$'` returns a single commit — the skill's
  original one. It was PID-scoped from birth, so the attribution was wrong when
  written, not stale-after-a-fix. Its real defect was an unbounded directory
  leak, not a collision.

- **The semgrep bootstrap is the other colliding half (the recorded H1).**
  REFUTED by reachability. `ensure-semgrep.sh` is invoked only by agent-driven
  paths (`review/SKILL.md`, the workflow, the `semgrep-sast` agent); a grep over
  the exact suite globs `test-all.sh` enumerates returns zero hits. No suite the
  runner reaches can run the bootstrap.

- **Reap `.scan-meta.json` with an `EXIT` trap.** REJECTED. The file is GDPR
  Art. 32 evidence with a documented post-exit consumer (`override-mechanism.md`),
  so an EXIT trap would delete the artifact the override flow references.
  Age-reaping older siblings at startup bounds the leak without touching the
  current run's artifact.

- **Make the lock blocking (abort on timeout).** REJECTED. Aborting converts
  today's silent wait into a hard failure — strictly worse than the status quo.
  An advisory lock that proceeds-with-announcement preserves the worst case (an
  interleaved run) while making it attributable, which is the actual defect.

- **Implement stale-holder detection on the lock.** REJECTED as dead code.
  `flock` is kernel-managed and inode-bound, released automatically once the last
  fd holder dies (measured with a positive control; a "dead pid still holds the
  lock" state is unreachable with real `flock`). Stale detection is only needed
  for hand-rolled `mkdir`/PID-file schemes.

- **Reap the many small `/tmp` entries (by count).** REJECTED. 4,294 small
  entries held 160 MB (4.5%) while three trees held 3.1 GiB (88%). Reaping by
  count recovers 4.5% of the problem while feeling thorough; the reaper sorts by
  bytes.

## Consequences

- A false RED from contention is now self-announced, not hand-diagnosed.
- The 4 GiB tmpfs cap (Layer 3 of the 2026-03-28 tmpfs guard) stays intact; what
  was missing was a reaper for the artifact class filling it, now added.
- Concurrent runs serialise, adding wait for a second run — announced and
  bounded, with a kill switch, rather than the silent interleave-or-manual-wait
  it replaces.
- No product runtime surface, user data, or tenant boundary is touched; this is
  local developer tooling on the operator's own machine.
