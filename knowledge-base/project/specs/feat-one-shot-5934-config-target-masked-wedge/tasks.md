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
- [ ] 0.1 Re-read `atomic_git_config` + `ensure_bare_config` in `worktree-manager.sh`;
  re-derive line numbers for the `mv` (~419), give-up (~492), non-bare guard (~476-480),
  `NO_GIT_REPOSITORY` gate (~84-89), `SOLEUR_FEATURE_PUSH_FAILED` (~1243). Do not trust
  frozen numbers.
- [ ] 0.2 Read `session-state.sh:355-378` (the `headless_or_stderr` logfile sink + `[error] `
  prefix — the meta-bug) and `git-lock-marker-telemetry.ts` `MARKER_RE`/`WEDGE_RE` +
  `git-lock-marker-telemetry.test.ts:107-128` (drift-guard collection pattern).
- [ ] 0.3 Read the harness idiom in `worktree-manager-atomic-config.test.sh` (T1–T19) to
  mirror for T20–T23.
- [ ] 0.4 Confirm `#6191` and `#5934` are OPEN (`gh issue view`) before referencing them.

## Phase 1 — D1: observability meta-fix (highest priority)
- [ ] 1.1 (a) Emit a bare `echo "SOLEUR_… …"` stdout sentinel at the `ensure_bare_config`
  give-up (~492) AND the `atomic_git_config` rename-failure (~419-423), in addition to the
  existing `headless_or_stderr error` line — so the conclusion is scanner-visible under the
  headless logfile sink.
- [ ] 1.2 (b) `git-lock-marker-telemetry.ts`: add `SOLEUR_GIT_CONFIG_TARGET_MASKED`,
  `SOLEUR_FEATURE_PUSH_FAILED`, `NO_GIT_REPOSITORY` to `MARKER_RE`; classify the fatal ones
  in `WEDGE_RE` (paged). Broaden the drift-guard test's collection pattern to also match
  `echo "NO_GIT_REPOSITORY` and `echo "SOLEUR_FEATURE_*`.
- [ ] 1.3 (c) Relax `MARKER_RE`'s `worktree wedge:` arm to tolerate an optional leading
  `[<level>] ` prefix so the existing `[error] worktree wedge:` matches; add a test for the
  prefixed line + each new sentinel. `tsc --noEmit` clean.
- [ ] 1.4 Cite `hr-observability-as-plan-quality-gate` / `hr-observability-layer-citation`
  in the PR body.

## Phase 2 — D2: config-target-masked pre-check (`atomic_git_config`)
- [ ] 2.1 Add a masked-**target** guard: masked iff `[[ -c "$target" ]]` OR realpath
  mountpoint via the `:187-193` `stat -c%m` idiom. Primary check immediately before the
  `mv -f -- "$tmp" "$target"` (~419); defensive top-of-function check after symlink
  resolution (~383-389) to also cover the native `git config --file` branch (~377).
- [ ] 2.2 On masked target: emit `SOLEUR_GIT_CONFIG_TARGET_MASKED file=<base>
  reason=target-bind-mount` on stdout, clean up `$tmp`/`$tmp.lock`, do NOT attempt `mv`,
  return non-zero.

## Phase 3 — D3: bare-under-mask correctness (`ensure_bare_config`)
- [ ] 3.1 Non-bare / native-add-works → SKIP the surgery. Harden the non-bare guard
  (~476-480) so a masked-config non-bare workspace (empty `GIT_ROOT`, ambiguous
  `--is-bare-repository`) is not misread as bare; "indeterminate under mask" resolves to the
  safe non-bare skip when `git worktree add` can proceed natively.
- [ ] 3.2 Genuinely bare AND target masked → fail LOUD: emit the visible
  `SOLEUR_GIT_CONFIG_TARGET_MASKED` marker naming the host-seed remedy
  (`remedy=host-pre-seed-.git/config-before-bwrap-mask see=#6191,#5934`) and return 1 — never
  ship a `core.bare`-bleeding worktree.
- [ ] 3.3 Record the fail-loud-vs-soft-skip caller contract in the PR body for plan-review.

## Phase 4 — D4: self-heal stale `extensions.worktreeConfig`
- [ ] 4.1 EARLY (before the surgery block / readiness gate, alongside `sweep_stale_git_locks`
  ~453): if `extensions.worktreeConfig=true` in `.git/config` while `.git/config.worktree`
  is masked, unset it via `git config --file "$shared_config" --unset
  extensions.worktreeConfig` (the `--file` form does not read the masked worktree config),
  emitting a visible informational `SOLEUR_*` marker so a once-poisoned workspace self-heals.

## Phase 5 — D5: local mknod mask-simulation test (RED→GREEN)
- [ ] 5.1 T20: target masked (`mknod config c 1 3`, or `ln -s /dev/null config` for
  unprivileged CI). RED on pre-fix code (generic `atomic rename failed`, no sentinel); GREEN
  after D2 (distinct sentinel, no `mv`). Author to fail first (`cq-write-failing-tests-before`).
  Reproduces the verbatim EBUSY locally.
- [ ] 5.2 T21: mountpoint target (bind-mount `/dev/null`; privilege-aware skip if no
  `mount --bind`, keeping the `-c` arm load-bearing).
- [ ] 5.3 T22: regression lock — char-device `config.lock` + regular `config` → still routes
  around (no false `SOLEUR_GIT_CONFIG_TARGET_MASKED`). Pins the observed #5912/#6183 case so
  D2 can't over-trigger.
- [ ] 5.4 T23: stale `extensions.worktreeConfig=true` + masked `config.worktree` → the early
  self-heal (D4) unsets the key and emits its marker.
- [ ] 5.5 `shellcheck` clean on new code; full T1–T23 green.

## Phase 6 — Verify & ship
- [ ] 6.1 All ACs (AC1–AC11) satisfied; scoped `git diff` (worktree-manager.sh + telemetry
  + tests + docs/ADR only).
- [ ] 6.2 `git-lock-marker-telemetry.test.ts` + `tsc --noEmit` green; the telemetry drift
  guard passes with the new sentinels.
- [ ] 6.3 `gh issue comment 5934`: scope note (LIVE wedge = masked config TARGET; this PR
  adds visibility + graceful degrade; host-side durable seed remains #5934/#6191). PR body
  uses `Ref #5934` / `Ref #6191`, NOT `Closes`.
- [ ] 6.4 `gh issue comment 6191`: cross-reference D2/D3 as the in-sandbox sibling of the
  host-side pre-seed.
- [ ] 6.5 Amend `ADR-081-chardevice-config-lock-substrate-sweep.md` (masked config TARGET +
  telemetry-blindness + host-side durable locus). Read the three `.c4` files to confirm "no
  C4 impact".
- [ ] 6.6 `decision-challenges.md` (corrected premise) carried into `/ship` PR-body render +
  action-required issue.
