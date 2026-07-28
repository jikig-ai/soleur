# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-27-perf-infra-suite-terraform-copy-exclusion-plan.md
- Status: complete

### Errors
- Self-caught gate violation (fixed): first draft set `Brand-survival threshold: none` without the required reason bullet. `apps/web-platform/infra/` matches the canonical sensitive-path regex via the `apps/[^/]+/infra/` arm, so deepen-plan Phase 4.6 rejected it (and `/soleur:preflight` Check 6 would have failed at ship). Fixed by adding `threshold: none, reason: …`.
- Two prescriptions falsified by measurement before shipping: `find -exec cp \;` and the copy/diff pin placed per-mutation. A third — "the helper without a cold-root fast path regresses CI's only shape 9.8s → 11.0s" — was itself falsified at /work: it did not reproduce under an interleaved A/B, and review showed the sign is not physically possible (the fast path is strictly less work). The fast path is NOT shipped; it was removed for a coverage reason instead.
- No blocking errors remain.

### Decisions
- **Premise corrected by measurement.** The 8.5 min infra runner is NOT bounded by `.terraform` copying: the runner measured 8m49.96s in a worktree where `.terraform` does not exist at all. It is bounded end-to-end by `ci-deploy.test.sh` (529.9s vs this suite's 9.6s), already tracked as #6665.
- **Kept the commissioned fix, changed its justification** — justified on a tmpfs-exhaustion hazard (peak temp 3,980 MB against a 4.0 GB tmpfs `/tmp`, 6 suites sharing it), not wall-clock. No acceptance criterion asserts a runner wall-clock improvement; that gate could only pass by noise. Recorded as a Decision Challenge with a stated default so it cannot block merge.
- **Two fixes, not one:** size (exclude `.terraform`) AND lifetime (sandboxes were never reclaimed until the `EXIT` trap). Each alone is a wall-clock regression; combined they bound the peak at ONE resident sandbox instead of 24 — measured 3,980 MB -> ~5 MB (~800x; the `du -sm` denominator rounds 4.5 MB up, so quoting 796x is over-precise). Wall-clock re-derived at /work: 9.79s -> 5.71s warm, 5 interleaved pairs.
- **Rejected hardlinking** (suggested in the task): five mutations append with `>>`, which writes *through* a hardlink into the developer's real source. `sed -i` is hardlink-safe, which makes the hazard easy to miss in review.
- **Corrected the premise "several infra suites"** — an exhaustive sweep found exactly one; the other `cp -r` sites copy synthetic fixtures.

### Components Invoked
- `soleur:plan`, `soleur:deepen-plan`
- `Explore` (exhaustive copy-site sweep), `learnings-researcher`
- `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`, scoped strong-model advisor consult
- Deepen-plan gates 4.4–4.10 (4.6 rejected then fixed; 4.7/4.8 pass; 4.5/4.55/4.9/4.10 skip; 4.4 → no precedent, pattern is novel)
- Empirical benchmarking outside the repo (`/var/tmp/credbench`, disk-backed `TMPDIR`, cleaned up); full 72-suite runner timed with per-suite breakdown

## Work Phase
- Status: complete
- Suite: `PASS=34 FAIL=0` (was 28 pre-PR; +1 copy/diff pair pin, +1 decoy-root pin, +1 scanner
  walk-prune pin, +1 exclusion-effect assertion, +1 nested-terraform tripwire, +1
  sandbox-reclamation invariant).
- Measured: warm peak `TMPROOT` 3,980 MB -> 5 MB; warm wall-clock 9.79s -> 5.71s (5 interleaved
  pairs); infra runner 543s, unchanged as predicted (72/72 green).
- Benchmark harness committed as `apps/web-platform/infra/credential-persist-home-guard.bench.sh`
  so every measured claim in the code comments is re-derivable.

### Review outcome
8-agent panel. All findings fixed inline; zero scope-outs filed. Six guards were empirically
proven to be shipping green while asserting nothing — including that deleting the ENTIRE mutation
battery reported `PASS=6 FAIL=0` and exit 0, because the only merge gate reads `FAIL` alone.

Two claims of mine were corrected by review:
- The fast-path removal is justified by COVERAGE, not speed. My 5-pair whole-suite A/B had an
  impossible sign; the suite's ~590ms noise floor cannot resolve an ~89ms primitive-level effect.
- "keeps the last sandbox alive for post-mortem" was false — the EXIT trap is unconditional.

One agent-prescribed fix was rejected after testing it: `GLOBIGNORE="$1/.terraform:$1/*/.terraform"`
does not exclude a nested cache (GLOBIGNORE filters glob expansion; `cp -r` recurses on its own).
Shipped a nested-root tripwire instead.
