---
feature: feat-one-shot-5934-config-target-masked-wedge
plan: knowledge-base/project/plans/2026-07-07-fix-worktree-config-target-masked-defense-in-depth-plan.md
lane: cross-domain
tracking_issue: 5934
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Tasks — worktree config-target-masked wedge: observability meta-fix + target-masked pre-check + bare-under-mask correctness + self-heal + local test

> **Ground truth (do not re-invert).** This wedge is LIVE on current `main`, proven by an
> operator-verbatim error: `mv: cannot move '.git/config.soleur-tmp.4' to '.git/config':
> Device or resource busy` + `[error] worktree wedge: could not apply shared-config
> prerequisites`. The `.git/config` rename TARGET is masked/bind-mounted; the fatal path
> was invisible to telemetry (`headless_or_stderr` per-PID logfile sink + `[error]` prefix
> failing `MARKER_RE` + allowlist gaps) — which is why four prior fixes (07-01 → 07-07)
> never converged. Do NOT close `#5934` (host-side durable seed remains its scope) and do
> NOT touch `#4826`. See plan §"Ground truth" and §"The meta-bug".

## Phase 0 — Preconditions
- [x] 0.1 Re-read `atomic_git_config` + `ensure_bare_config` in `worktree-manager.sh`;
  re-derive line numbers for the `mv` (~419), give-up (~492), non-bare guard (~476-480),
  `NO_GIT_REPOSITORY` gate (~84-89), `SOLEUR_FEATURE_PUSH_FAILED` (~1243). Do not trust
  frozen numbers.
- [x] 0.2 Read `session-state.sh:355-378` (the `headless_or_stderr` logfile sink + `[error] `
  prefix — the meta-bug) and `git-lock-marker-telemetry.ts` `MARKER_RE`/`WEDGE_RE` +
  `git-lock-marker-telemetry.test.ts:107-128` (drift-guard collection pattern).
- [x] 0.3 Read the harness idiom in `worktree-manager-atomic-config.test.sh` (T1–T19) to
  mirror for T20–T23.
- [x] 0.4 Confirm `#6191` and `#5934` are OPEN (`gh issue view`) before referencing them.

> **Scope change (operator, 2026-07-07): D4 CUT.** The self-heal of a stale
> `extensions.worktreeConfig` was removed from this PR — the flag is CONFIRMED UNSET on the
> affected (non-bare) workspace (refuted hypothesis), and its write targets the exact masked
> path, adding risk without addressing the real bug. Priority is now firmly: **D3 non-bare
> guard-repair is THE operator-facing fix** (workspace is non-bare; the guard misfired under
> the mask), D1 observability, D2 target-masked pre-check (secondary defense), D5 mask-sim test.

## Phase 1 — D1: observability meta-fix (highest priority)
- [x] 1.1 (a) Emit a bare `echo` stdout sentinel at the `ensure_bare_config` give-ups AND the
  `atomic_git_config` rename-failure/masked-target pre-check, in addition to the existing
  `headless_or_stderr error` line — so the conclusion is scanner-visible under the headless
  logfile sink. (`worktree wedge:` bare echoes at all four give-ups; `SOLEUR_GIT_CONFIG_TARGET_MASKED`
  on stdout at the pre-check + rename-failure.)
- [x] 1.2 (b) `git-lock-marker-telemetry.ts`: add `SOLEUR_GIT_CONFIG_TARGET_MASKED`,
  `SOLEUR_GIT_CONFIG_MASK_SKIP` (benign), `SOLEUR_FEATURE_PUSH_FAILED`, `NO_GIT_REPOSITORY` to
  `MARKER_RE`; the fatal ones are in `WEDGE_RE` (paged); `MASK_SKIP` is benign (mirrored, not
  paged). Broadened the drift-guard collection pattern to `SOLEUR_[A-Z_]+|NO_GIT_REPOSITORY`.
- [x] 1.3 (c) Relaxed `MARKER_RE`/`WEDGE_RE` to tolerate an optional leading `[<level>] `
  prefix so the existing `[error] worktree wedge:` matches; added tests for the prefixed line
  + each new sentinel. `tsc --noEmit` clean.
- [x] 1.4 Cite `hr-observability-as-plan-quality-gate` / `hr-observability-layer-citation`
  in the PR body.

## Phase 2 — D2: config-target-masked pre-check (`atomic_git_config`)
- [x] 2.1 Added a masked-**target** guard `_config_target_masked` (masked iff `[[ -c "$t" ]]`
  OR realpath is its own mount root via the `:187-193` `stat -c%m` idiom). Primary check AFTER
  FR2 read-first / BEFORE the native-vs-lockless decision (covers BOTH branches — the plan's
  literal "after symlink resolution" would miss the native branch, so this is the corrected
  placement); defensive re-check on the resolved target immediately before the `mv`.
- [x] 2.2 On masked target: emit `SOLEUR_GIT_CONFIG_TARGET_MASKED file=<base>
  reason=target-bind-mount branch=target-masked-precheck` on stdout, clean up `$tmp`/`$tmp.lock`,
  do NOT attempt the write/`mv`, return non-zero.

## Phase 3 — D3: NON-BARE GUARD-REPAIR (operator-facing fix) + bare-under-mask fallback
- [x] 3.1 Non-bare → SKIP the surgery via a mask-ROBUST filesystem probe: `git_dir` is a `.git`
  DIRECTORY (never reads the masked config), + a `$PWD/.git` fallback when GIT_ROOT resolves
  empty. `git rev-parse --is-bare-repository`/`--show-toplevel` are NO LONGER trusted first
  (they degrade under the mask — the round-6 misfire). On a masked non-bare clone, emit the
  benign `SOLEUR_GIT_CONFIG_MASK_SKIP branch=non-bare-skip` diagnostic.
- [x] 3.2 Genuinely bare (gitdir IS the root, no `.git` dir) AND config masked → fail LOUD:
  emit `SOLEUR_GIT_CONFIG_TARGET_MASKED reason=bare-under-mask branch=bare-fail
  remedy=host-pre-seed-.git/config-before-bwrap-mask see=#6191,#5934` + return 1. Rare fallback.
- [x] 3.3 Record the skip-vs-fail-loud caller contract + the branch-tagged markers in the PR body.

## Phase 4 — D4: self-heal stale `extensions.worktreeConfig` — CUT (out of scope)
- [x] 4.1 **CUT — out of scope** (operator, 2026-07-07; refuted: the flag is confirmed UNSET on
  the affected workspace, and its `.git/config` write targets the exact masked path → adds risk
  without fixing the real bug). Tracked-as-defensive-follow-up only if ever observed. Not
  implemented; no code or test shipped.

## Phase 5 — D5: local mask-simulation test (RED→GREEN)
- [x] 5.1 T20: masked TARGET (`mknod config c 1 3` when permitted, else `ln -s /dev/null config`
  — `-c` dereferences the symlink, the portable proxy). RED on pre-fix code (no sentinel); GREEN
  after D2 (distinct sentinel, target intact, no `mv`). Authored to fail first
  (`cq-write-failing-tests-before`). Documents the mknod/bind-mount privilege fallback.
- [x] 5.2 T21: direct `_config_target_masked` unit checks — TRUE for `/dev/null` (char device),
  FALSE for a regular config (no over-trigger), + bind-mount arm with a privilege-aware skip.
- [x] 5.3 T22: masked LOCK + regular `config` → still routes around (no false
  `SOLEUR_GIT_CONFIG_TARGET_MASKED`). Pins the observed #5912/#6183 case so D2 can't over-trigger.
- [x] 5.4 T23 (renumbered): the D3 guard-misfire — non-bare `.git`-dir + mask-degraded
  `git rev-parse` (`core.bare=true` + empty GIT_ROOT). RED on pre-fix (guard runs surgery →
  wedge → rc 1); GREEN after D3 (skips, rc 0, no surgery). This is the PRIMARY operator-facing
  scenario. (The old T23 self-heal test was removed with D4.)
- [x] 5.5 `shellcheck` clean on new code; full T1–T23 green (68 pass / 0 fail / 2 privilege-skips).

## Phase 6 — Verify & ship
- [x] 6.1 Scoped `git diff` (worktree-manager.sh + telemetry + tests + docs/ADR only); AC1–AC5,
  AC7–AC10 satisfied; AC6 obsoleted by the D4 cut.
- [x] 6.2 `git-lock-marker-telemetry.test.ts` (21) + `tsc --noEmit` green; drift guard passes
  with the new sentinels. Full suite: only an unrelated `pdf-text-extract` timeout flake
  (passes in isolation, not in this diff).
- [ ] 6.3 `gh issue comment 5934`: scope note. PR body uses `Ref #5934` / `Ref #6191`, NOT `Closes`.
- [ ] 6.4 `gh issue comment 6191`: cross-reference D2/D3 as the in-sandbox sibling of the host-side pre-seed.
- [x] 6.5 Amend `ADR-081-chardevice-config-lock-substrate-sweep.md` (masked config TARGET +
  telemetry-blindness + non-bare-guard round-6 + host-side durable locus). C4: no new
  actor/system/data store → no C4 impact.
- [ ] 6.6 `decision-challenges.md` (corrected premise) carried into `/ship` PR-body render.
