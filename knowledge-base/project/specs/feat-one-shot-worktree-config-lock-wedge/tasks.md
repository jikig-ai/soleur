---
feature: feat-one-shot-worktree-config-lock-wedge
issue: 6184
lane: single-domain
plan: knowledge-base/project/plans/2026-07-07-fix-nonbare-concierge-worktree-identity-wedge-plan.md
deferred_followups: [6186]
---

# Tasks — non-bare Concierge worktree-identity wedge (#6184)

Derived from the finalized (post-plan-review) plan. RED-first. Closes #6184.

## Phase 1 — Setup / RED

- [ ] 1.1 Write RED test T14 in `plugins/soleur/test/worktree-manager-atomic-config.test.sh`: non-bare repo + linked worktree; seed shared config with a distinctive OWNER identity; set a DIFFERENT global; place a non-regular `.git/config.lock` (dir stand-in; char-device variant guarded on `mknod`/root). Assert current behavior fails (RC≠0), then that after the fix `ensure_worktree_identity` returns 0 and local identity read-back is STILL the OWNER.
- [ ] 1.2 Confirm the primary claim locally: `git -C <wt> config --local user.email` targets `rev-parse --path-format=absolute --git-common-dir`/config on both worktreeConfig on/off (already verified in planning; re-assert in test).

## Phase 2 — Core: respect the host-seeded owner (Plan Phase 1)

- [ ] 2.1 Rewrite `ensure_worktree_identity` (`worktree-manager.sh:600-619`): read local identity first; if non-empty local `user.email` AND `user.name` present → `return 0` (no write). Only when local absent, set from global.
- [ ] 2.2 Resolve common config absolute: `git -C "$worktree_path" rev-parse --path-format=absolute --git-common-dir`/config. On empty/failure → emit `common-dir-unresolved` sentinel + `return 1` (NO `$GIT_ROOT/.git/config` fallback).
- [ ] 2.3 Route the set-when-absent write through `atomic_git_config "$common_config" user.email/name` as explicit per-write guards: `if ! atomic_git_config … || ! atomic_git_config …; then emit sentinel; return 1; fi` (do NOT rely on errexit — the `if !` call-site wrap disarms it inside the function).
- [ ] 2.4 Wrap BOTH bare call sites (`:1011`, `:1097`) in `if ! ensure_worktree_identity "$worktree_path"; then <red error>; exit 1; fi`.
- [ ] 2.5 Rewrite the stale NOTE at `:588-599` to document the non-bare owner-authoritative reality.
- [ ] 2.6 Run the corrected self-check grep: `grep -nE "git (-C [^ ]+ )?config " worktree-manager.sh | grep -vE "(--get|--file|--global|^ *#)"` → zero raw shared-config write sites.

## Phase 3 — Observability (Plan Phase 2)

- [ ] 3.1 `worktree-manager.sh`: emit STDOUT `SOLEUR_GIT_LOCK_IDENTITY_WEDGED source=ensure_worktree_identity reason={native-eexist|common-dir-unresolved} file=config` on the two failure paths (device/path forensic only — never identity values, no un-derivable errno).
- [ ] 3.2 `worktree-manager.sh`: emit a benign DIAG-class identity-drift marker when the set-from-global branch is taken (local absent), regardless of success.
- [ ] 3.3 `apps/web-platform/server/git-lock-marker-telemetry.ts`: extend `MARKER_RE` to match the new sentinel + benign marker; extend `WEDGE_RE` to match ONLY the wedge reasons (not the benign marker).
- [ ] 3.4 Verify `apps/web-platform/test/git-lock-marker-telemetry.test.ts` drift guard passes (auto-discovers the new echo literals).

## Phase 4 — Citation correction (Plan Phase 3)

- [ ] 4.1 `#4826`→`#6184` in the wedge-diagnosis citations of edited files ONLY: `worktree-manager.sh:455,816-817`; `git-repo-readiness-diag.sh:2,9`; `worktree-manager-atomic-config.test.sh:249,250,262,270`; `one-shot/SKILL.md:52`; `git-lock-marker-telemetry.ts:1,13,37`; `git-lock-marker-telemetry.test.ts:1`. Preserve prior-PR-number comments. Do NOT sweep host-side-heal-saga citations.

## Phase 5 — Tests + ADR (Plan Phase 4 + Architecture Decision)

- [ ] 5.1 T15 (set-when-absent robustness), T16 (set -e ordering via the wrapped call site under active `set -e`), T17 (bare regression). Update test header comment.
- [ ] 5.2 `git-worktree/SKILL.md`: add Sharp Edges (never re-add a raw `git config` write; identity-authority inversion).
- [ ] 5.3 Amend `ADR-081` `## Decision` (identity authority on non-bare) + `## Alternatives Considered` (Layer A rejected: misattribution).

## Phase 5b — Canonical topology docs (coordinator-directed)

- [ ] 5b.1 Create `knowledge-base/engineering/architecture/decisions/ADR-098-git-surface-topology.md` (provisional ordinal): three surfaces (server-side bare git-data / non-bare agent workspace / local-dev bare) + the non-bare-guard consequence (`worktree-manager.sh:478`); cross-link ADR-081 + `post-mortems/concierge-worktree-creation-stale-lock-wedge-postmortem.md`.
- [ ] 5b.2 AGENTS.rest.md `rf-after-merging…`: append non-bare caveat + ADR-098 pointer (budget-free).
- [ ] 5b.3 AGENTS.core.md `hr-when-in-a-worktree…` + `wg-at-session-start…`: add concise non-bare caveat + ADR-098 pointer, NET-BYTE-NEUTRAL (or free room via a loader-class-fit-verified wg-* demotion; `sed -n '88,126p' .claude/hooks/session-rules-loader.sh`). Keep one line per rule; do NOT rename ids.
- [ ] 5b.4 `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` exits 0 (B_ALWAYS ≤ 23000).

## Phase 6 — Verify

- [ ] 6.1 `bash plugins/soleur/test/worktree-manager-atomic-config.test.sh` green (1–13 + T14–T17).
- [ ] 6.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/git-lock-marker-telemetry.test.ts` green.
- [ ] 6.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` green.
- [ ] 6.4 AC8 residual-`4826` grep (scoped to edited files) = zero.
- [ ] 6.5 `bash scripts/test-all.sh` (from worktree) green for touched shards.

## Post-merge (automatable — /ship + postmerge, no manual steps)

- [ ] 7.1 After web-platform image rebuild deploys: `scripts/betterstack-query.sh --since 48h --grep SOLEUR_GIT_LOCK_IDENTITY_WEDGED` shows the benign precondition marker on real creates and no wedge reasons on successful runs.

## Deepen-plan deliverables (before /work)

- [ ] D.1 Precedent-diff: does "don't clobber local" regress the bare CLI dev repo case? (bare-repo-bot-local behavior)
- [ ] D.2 Layer-B decision: remove/replace the `Dockerfile:212` bot global, or set sandbox `--global` = owner at provision (audit `push-branch.ts`/`inflight-checkpoint.ts` reliance first). Land here or spawn an issue.
