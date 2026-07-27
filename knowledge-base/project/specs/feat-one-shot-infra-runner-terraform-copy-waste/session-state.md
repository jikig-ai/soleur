# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-27-perf-infra-suite-terraform-copy-exclusion-plan.md
- Status: complete

### Errors
- Self-caught gate violation (fixed): first draft set `Brand-survival threshold: none` without the required reason bullet. `apps/web-platform/infra/` matches the canonical sensitive-path regex via the `apps/[^/]+/infra/` arm, so deepen-plan Phase 4.6 rejected it (and `/soleur:preflight` Check 6 would have failed at ship). Fixed by adding `threshold: none, reason: …`.
- Three prescriptions falsified by measurement before shipping: `find -exec cp \;` (44.6s vs 10.4s baseline), the copy/diff pin placed per-mutation (16.5–17.9s), and the helper without a cold-root fast path (regressed CI's only shape 9.8s → 11.0s).
- No blocking errors remain.

### Decisions
- **Premise corrected by measurement.** The 8.5 min infra runner is NOT bounded by `.terraform` copying: the runner measured 8m49.96s in a worktree where `.terraform` does not exist at all. It is bounded end-to-end by `ci-deploy.test.sh` (529.9s vs this suite's 9.6s), already tracked as #6665.
- **Kept the commissioned fix, changed its justification** — justified on a tmpfs-exhaustion hazard (peak temp 3,980 MB against a 4.0 GB tmpfs `/tmp`, 6 suites sharing it), not wall-clock. No acceptance criterion asserts a runner wall-clock improvement; that gate could only pass by noise. Recorded as a Decision Challenge with a stated default so it cannot block merge.
- **Two fixes, not one:** size (exclude `.terraform`) AND lifetime (sandboxes were never reclaimed until the `EXIT` trap). Each alone is a wall-clock regression; combined they measure 7.5s / 5 MB peak vs 10.4s / 3,980 MB — a 796x peak reduction.
- **Rejected hardlinking** (suggested in the task): five mutations append with `>>`, which writes *through* a hardlink into the developer's real source. `sed -i` is hardlink-safe, which makes the hazard easy to miss in review.
- **Corrected the premise "several infra suites"** — an exhaustive sweep found exactly one; the other `cp -r` sites copy synthetic fixtures.

### Components Invoked
- `soleur:plan`, `soleur:deepen-plan`
- `Explore` (exhaustive copy-site sweep), `learnings-researcher`
- `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`, scoped strong-model advisor consult
- Deepen-plan gates 4.4–4.10 (4.6 rejected then fixed; 4.7/4.8 pass; 4.5/4.55/4.9/4.10 skip; 4.4 → no precedent, pattern is novel)
- Empirical benchmarking outside the repo (`/var/tmp/credbench`, disk-backed `TMPDIR`, cleaned up); full 72-suite runner timed with per-suite breakdown
