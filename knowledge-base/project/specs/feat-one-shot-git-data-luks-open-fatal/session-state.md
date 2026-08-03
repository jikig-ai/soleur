# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-03-fix-git-data-luks-open-boot-fatal-plan.md
- Tracking issue: #7204
- Status: complete

### Errors
- `gh issue create` blocked once for a missing `--milestone`; retried with `Phase 4: Validate + Scale`. The blocked call had bundled the heredoc writing the issue body, so the body file was re-written before the retry succeeded.
- First-draft plan asserted that a `.tf`-free merge does not fire `apply-web-platform-infra.yml`. False — the filter is `apps/web-platform/infra/**`. Caught by reading `on.push.paths`, corrected in the plan, independently confirmed by a review agent and a pre-existing learning file for the identical mistake.
- No local repro of the kernel condition was possible: forcing `modprobe` to fail would require writing to the operator's host config, and a container cannot simulate it (`request_module` runs in the init namespace). Recorded as open assumption A1; the fix is required to be correct either way.

### Decisions
- **Root cause is a genuine template defect, not a rehearsal artifact.** The rehearsal died at `mount(2) → ESRCH` (rc=32): the birth's `mkfs.ext4 -q -O quota,project` sets the ext4 `quota` superblock feature, forcing `ext4_enable_quotas()` at every mount, but the stock Ubuntu 24.04 cloud image ships `linux-modules-*-generic` without `linux-modules-extra-*`, where `quota_v2.ko` lives. Only `git_data_luks_volume_id` of the 8 divergence vars reaches the LUKS block and it demonstrably resolved; server type, location, both volume sizes and the image are byte-identical to prod defaults. The real birth would die identically.
- **Probe-first phase ordering is load-bearing.** Phase 0 ships alone and measures five candidates before Phase 1 picks one, because deepen-plan research refuted the "migration-forcing" premise that pinned the unmountable flags (`tune2fs` can set both `quota` and `project` post-creation).
- **The regression guard cannot be a mount test.** Measured directly: all four mkfs arms mount fine on a `quota_v2`-bearing kernel, so a container test cannot fail for the real reason. R1 asserts a classified superblock-feature allowlist instead, with an in-test mutation plus a committed pre-fix literal as negative controls.
- **Re-aim guard B16 rather than delete it**, with an AP-018 authority split qualified by the docker-less caveat (B16 is the only local coverage when the runtime suite self-skips).
- **Do not dispatch.** The plan spends no paid host and hands the operator all three verdict branches with a two-dispatch cap, including the #7116 TRANSIENT mis-report warning.

### Components Invoked
- `Skill: soleur:plan`, `Skill: soleur:deepen-plan`
- `gh issue create` -> #7204; `gh` (runs, PRs, issues, labels, milestones)
- Self-pulled telemetry: `scripts/betterstack-query.sh` under `doppler run` (the decisive `detail` row), plus a background agent for the Sentry stage timeline
- Local probes: privileged Docker four-arm LUKS/mkfs/mount repro; Ubuntu `noble` Contents index; Ubuntu 24.04 cloud-image package manifest
- Agents: `general-purpose` (telemetry), `architecture-strategist`, `spec-flow-analyzer`, scoped Fable advisor consult, `best-practices-researcher`, `learnings-researcher`, `git-history-analyzer`, `test-design-reviewer`
- Gates run: plan 2.5-2.11; deepen-plan 4.5 (triggered/dispositioned), 4.6, 4.7, 4.8, 4.9 (skip), 4.10, 4.55 (no trigger); rule-application telemetry emitted for `hr-ssh-diagnosis-verify-firewall`

### Findings flagged beyond the fix
- The rehearsal's FAIL artifact carries a verdict with **no cause** — the capture SQL never selects `detail`. The decisive row had to be recovered by a hand-written query.
- The capture script's header contains a **false capability claim** that Sentry search is unavailable. This materially affects how #7116 gets planned.
