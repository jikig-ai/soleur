---
feature: feat-one-shot-5934-config-target-masked-wedge
plan: knowledge-base/project/plans/2026-07-07-fix-worktree-config-target-masked-defense-in-depth-plan.md
lane: cross-domain
tracking_issue: 5934
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Tasks — worktree config-target-masked self-diagnosis (defense-in-depth) + #5934 reconciliation

> **Evidence-first framing (do not skip).** Phase-1 telemetry showed the supplied premise
> is stale: the user-facing wedge was fixed by #6183 (`696aa4649`, on `main`); the
> `ensure_bare_config`/config-target path has zero telemetry over 30d. This work delivers
> a defense-in-depth self-diagnosis sentinel + test + issue reconciliation ONLY. Do NOT
> re-patch `ensure_bare_config:492`, do NOT touch `ensure_worktree_identity`, `#4826`, or
> close `#5934`. See plan §"Explicit non-goals".

## Phase 0 — Preconditions
- [ ] 0.1 Confirm `main` includes `696aa4649` (`git merge-base --is-ancestor 696aa4649 origin/main`).
- [ ] 0.2 Re-grep `atomic_git_config`: confirm no `[[ -c ]]`/`stat -c%m` guard exists yet; re-derive current line numbers (do not trust frozen numbers).
- [ ] 0.3 Read the harness idiom in `plugins/soleur/test/worktree-manager-atomic-config.test.sh` (T1–T19) to mirror for new tests.
- [ ] 0.4 Re-run the two confirming Better Stack queries (chardevice DIAG present on `config.lock`; zero `IDENTITY_WEDGED` in 7d) to confirm diagnosis unchanged: `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 7d --grep SOLEUR_GIT_LOCK_IDENTITY_WEDGED`.

## Phase 1 — D1: target-masked guard + sentinel (`worktree-manager.sh`)
- [ ] 1.1 Add masked-target guard at the **top** of `atomic_git_config` (after target/symlink resolution, before the FR2/native/lockless fork): masked iff `[[ -c "$target" ]]` OR realpath mountpoint via the `:187-193` `stat -c%m` idiom.
- [ ] 1.2 On masked target: emit `SOLEUR_GIT_CONFIG_TARGET_MASKED file=<base> reason=target-bind-mount`, clean up temp, and **return non-zero** (Option A — fail-loud). Do NOT attempt `mv`.
- [ ] 1.3 Add a cheap defensive re-check before the `mv` at ~419 (belt-and-suspenders).
- [ ] 1.4 Record the Option A vs B graceful-degrade decision in the PR body; leave `ensure_bare_config:492` block unchanged (the non-bare guard at ~478 already short-circuits non-bare).

## Phase 2 — D2: mask-simulation tests (`worktree-manager-atomic-config.test.sh`, RED→GREEN)
- [ ] 2.1 T20: char-device target (`mknod config c 1 3`, or symlink→`/dev/null` for unprivileged CI). RED on pre-guard code (only generic "atomic rename failed", no new sentinel); GREEN after D1 (distinct sentinel, no `mv`). Author to fail first (`cq-write-failing-tests-before`).
- [ ] 2.2 T21: mountpoint target (bind-mount `/dev/null`; privilege-aware skip with logged reason if CI can't `mount --bind`).
- [ ] 2.3 T22: regression lock — char-device `config.lock` + regular `config` → still routes around (no false `SOLEUR_GIT_CONFIG_TARGET_MASKED`). Pins the observed #6183/#5912 case so D1 can't over-trigger.
- [ ] 2.4 `shellcheck` clean on new code; full T1–T22 green.

## Phase 3 — D3/D4: telemetry mirror + issue/docs reconciliation
- [ ] 3.1 `git-lock-marker-telemetry.ts`: add `SOLEUR_GIT_CONFIG_TARGET_MASKED` to **both** `MARKER_RE` (~48) and `WEDGE_RE` (~57). Add coverage in `git-lock-marker-telemetry.test.ts`. `tsc --noEmit` clean.
- [ ] 3.2 `gh issue comment 5934`: scope-broadening note (user-facing wedge fixed by #6183/#6184; #5934 now = durable substrate fix + sweep telemetry gap: zero `SOLEUR_CHARDEV_SWEEP_*` in 14d while char-device keeps appearing). PR body uses `Ref #5934`, not `Closes`.
- [ ] 3.3 `gh issue comment 6191`: cross-reference D1 as the in-sandbox sibling of #6191's host-side raw-config-write hardening.
- [ ] 3.4 Amend `ADR-081-chardevice-config-lock-substrate-sweep.md` with the per-session-bwrap-mask finding (deploy-time host sweep can't prevent a per-session mask; durable prevention is bwrap-config-side; char-device now benign post-#6183). Read all three `.c4` files to confirm "no C4 impact" per completeness mandate.

## Phase 4 — Verify & ship
- [ ] 4.1 All ACs (AC1–AC10) satisfied; scoped `git diff` (atomic_git_config + tests + telemetry + docs/ADR only).
- [ ] 4.2 `decision-challenges.md` (UC-1, already on disk) carried into `/ship` PR-body render + action-required issue.
- [ ] 4.3 plan-review panel (DHH/Kieran/code-simplicity + architecture-strategist + user-impact-reviewer at single-user threshold) adjudicates Option A vs B before implementation freeze.
