---
feature: feat-one-shot-5934-concierge-config-lock-chardevice
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-03-infra-concierge-config-lock-chardevice-durable-fix-plan.md
closes: 5934
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Tasks — durable char-device `.git/config.lock` fix (#5934)

> Derived from the finalized plan. Origin pinned at plan time: the char device is a
> container filesystem/mount **substrate** artifact (origin (c)); the repo sandbox config
> masks no `.lock` (origins (a)/(b) ruled out) → single-path, de-risks #5912.

## Phase 0 — Setup & preconditions

- [ ] 0.1 Read the plan + the sibling brainstorm (`origin/feat-config-lock-wedge-fix`)
      and PR #5932 current diff. **#5932 MUST merge first** (it is +160/−19 on the same
      `worktree-manager.sh` sweep function); Phase 1 is an additive rebase on top of it.
- [ ] 0.1b Confirm the bare-repo mount topology at `ci-deploy.sh:899`
      (`-v /mnt/data/workspaces:/workspaces`, persistent bind-mount — NOT container overlay2)
      and the KNOWN bare-repo root path the Phase 2 sweep will bound to.
- [ ] 0.2 Confirm the shell-test runner for `plugins/soleur/test/*.test.sh` (do NOT
      hardcode `bats`); confirm `mknod`/char-device fixture capability + skip-guard.
- [ ] 0.3 Re-run the Open Code-Review Overlap check
      (`gh issue list --label code-review --state open`) against the plan's file set.
- [ ] 0.4 CPO sign-off confirmation (threshold = single-user incident) before implementing.

## Phase 1 — Sharpen the in-repo forensic (ships regardless)

- [ ] 1.1 (RED) Add a diag-test fixture forcing a char device at `config.lock`, asserting
      `type=chardevice` + well-formed `rdev` (fails against current code).
- [ ] 1.2 Add `[[ -c "$path" ]] → ftype=chardevice` branch in `sweep_stale_git_locks`
      (before `-d`/`-f`/`other`); capture `rdev=$(stat -c '%t:%T' …)` + mountpoint state
      (`stat -c%m`); extend `SOLEUR_GIT_LOCK_DIAG` with `rdev=` + `mount=`. For a REGULAR
      lock, also probe `getfattr -n trusted.overlay.whiteout` (zero-size whiteout form).
- [ ] 1.3 Preserve UNREMOVABLE behavior for `chardevice` (non-regular → unremovable, never
      auto-`rm` on the blind surface).
- [ ] 1.4 (GREEN) Diag test passes; regression-assert it fails if the `-c` branch is removed.
- [ ] 1.5 Coordinate/rebase with PR #5932 (same file/function) — additive only.

## Phase 2 — Durable substrate remediation (in-repo IaC, gated on Phase 1 evidence)

- [ ] 2.1 Scope the sweep to the persistent volume `/mnt/data/workspaces` (host-side), NOT
      the container overlay — bind-mount does not get overlaid. Confirm rdev evidence from
      Phase 1 before removal semantics.
- [ ] 2.2 Create `apps/web-platform/infra/git-lock-chardevice-sweep.sh` — root, idempotent,
      char-device-scoped (`test -c` on `config.lock`/`config.worktree.lock`), bounded to
      KNOWN bare-repo roots (no unbounded `find`). Removal is rdev-aware: plain inode →
      `rm -f`; **mountpoint (bind, e.g. `/dev/null` `rdev 1:3`) → `umount` THEN `rm -f`**
      (bare `rm` → `EBUSY`). Structured no-SSH marker per removal (path+rdev+branch).
- [ ] 2.3 Sweep `.test.sh`: (i) removes plain char-device lock, (ii) `umount`s-then-`rm`s a
      bind-mounted device node, (iii) leaves regular lock, (iv) leaves `index.lock`; no-op
      when clean.
- [ ] 2.4 Stage via base64 in `infra-config-apply.sh` (mirror
      `INNGEST_WIPED_VOLUME_VERIFY_SH_B64`); invoke ONLY at a quiescent window (first-boot
      `cloud-init.yml` runcmd / container-entrypoint before agent runtime) — NEVER a
      periodic timer (would race a future shared-git-data writer).
- [ ] 2.5 Wire liveness marker (state file via `cat-*-state.sh` pattern + Sentry/Better
      Stack); confirm discoverability without SSH.

## Phase 3 — External-substrate fallback (only if Phase 1 proves outside-repo layer)

- [ ] 3.1 If Phase 2 layer is unreachable from repo IaC: file scoped upstream/host
      prerequisite issue with `rdev` evidence + re-evaluation criteria + roadmap milestone.
      Mark browser/console steps `automation-status: UNVERIFIED` (Playwright attempt first).

## Phase 4 — Architecture record + soak enrollment

- [ ] 4.1 Create **ADR-081** (080 is taken — verify next free number), substrate root cause
      + privileged non-blind sweep remediation, status `adopting`; `## Alternatives
      Considered` per plan; note the SDK-pin dependence of the (a)/(b) ruling. Verify C4 (no
      impact — cite actors/systems/relationships checked). Run C4 validation tests.
- [ ] 4.2 Add `scripts/followthroughs/chardevice-wedge-nonrecurrence-5934.sh` (Sentry-rate
      soak, `start=` after deploy; mirror `reconcile-ff-only-sentry-4977.sh`).
- [ ] 4.3 Add the `<!-- soleur:followthrough … -->` directive + `follow-through` label to
      #5934; wire any new `secrets=` into `scheduled-followthrough-sweeper.yml`.

## Phase 5 — Verify & acceptance

- [ ] 5.1 All Pre-merge ACs (AC1–AC8) satisfied; run the full shell-test suite exit gate.
- [ ] 5.2 Typecheck any TS touched: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
      (NOT `npm run -w`).
- [ ] 5.3 PR body: `closes #5934`; Pre-merge / Post-merge AC split; origin-determination
      summary; coordination note with PR #5932.
