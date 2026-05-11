---
title: "Tasks: gdpr-gate trust-hardening drain (#3535 + #3536 + #3540)"
branch: feat-gdpr-gate-trust-hardening-drain
plan: knowledge-base/project/plans/2026-05-11-refactor-gdpr-gate-trust-hardening-drain-plan.md
---

# Tasks

Derived from `knowledge-base/project/plans/2026-05-11-refactor-gdpr-gate-trust-hardening-drain-plan.md`. Phase order is contract-first; do NOT reorder.

## Phase 1 — Parser contract extension (#3535)

- [ ] 1.1 Write failing test `TS-cron-1` in `plugins/soleur/test/notice-frontmatter.test.sh`: `cron-run-stale` with `GH_TOKEN=""` → emits `999`, exits 0.
- [ ] 1.2 Write failing test `TS-cron-2`: `cron-run-stale` with `GH_TOKEN=<token>` against a stubbed `gh` wrapper → emits expected integer.
- [ ] 1.3 Write failing test `TS-cron-3`: `days-stale` MIN behavior — `last-verified: today` + stubbed cron-run at ~100d ago → emits `100`.
- [ ] 1.4 Write failing test `TS-cron-4`: `days-stale` with absent token + valid last-verified → emits last-verified value (fallback).
- [ ] 1.5 Implement `cron-run-stale` subcommand in `plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh`. Reads `GH_TOKEN`/`GITHUB_TOKEN`; absent → `999`. Calls `gh run list --workflow=scheduled-content-vendor-drift.yml --status=success --limit=1 --json updatedAt --jq '.[0].updatedAt'` wrapped in `timeout 5s`. Parses RFC 3339 timestamp via `date -u -d`. Handle `null`/empty array → 999. Always exit 0.
- [ ] 1.6 Extend `cmd_days_stale` to compute MIN of (last-verified-days, cron-run-days) **only when both are non-999**. Otherwise return the non-999 value, or 999 if both are 999.
- [ ] 1.7 Run tests; all four TS-cron-* must pass. Run existing `bash plugins/soleur/test/notice-frontmatter.test.sh` — all TS1-TS5 still pass.

## Phase 2 — Gate caller wiring (#3535)

- [ ] 2.1 Modify `plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh` to invoke parser twice: once for `days-stale` (MIN'd), once for `cron-run-stale` (sentinel only). Propagate `GH_TOKEN` (or `GITHUB_TOKEN`) via `env GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}" bash "$NOTICE_PARSER" ...`.
- [ ] 2.2 When `cron-run-stale` returns 999 AND `days-stale` is non-999, prepend an operator-attested-mode banner line to stdout: `ℹ gdpr-gate running in operator-attested mode (no GH_TOKEN available — cron-run timestamp unverified)`.
- [ ] 2.3 Emit `gdpr-gate-cron-binding` incident via `incidents.sh` (variants: `applied`, `unavailable`, `min-wins`). Always wrap with `2>/dev/null || true` to preserve advisory exit 0.
- [ ] 2.4 Manual smoke: run `bash plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh apps/web-platform/lib/auth/foo.ts` with and without `GH_TOKEN`. Confirm exit 0 in all paths; confirm banner presence/absence matches expected.

## Phase 3 — CODEOWNERS row (#3535)

- [ ] 3.1 Append the NOTICE row to `.github/CODEOWNERS` in the secret-scanning-floor block with the documented comment: `# Trust-binding gate — protects last-verified from drive-by edits (issue #3535).`
- [ ] 3.2 Verify the row order with `grep -nE '/plugins/soleur/skills/gdpr-gate/NOTICE' .github/CODEOWNERS` — confirm it lands between existing secret-floor rows, not the `*` fallback line.

## Phase 4 — SKILL.md docs (#3535)

- [ ] 4.1 Edit `plugins/soleur/skills/gdpr-gate/SKILL.md` §"Runtime staleness banner" to document the GH_TOKEN auth contract, MIN precedence, and operator-attested-mode banner.
- [ ] 4.2 Add the workflow-rename Sharp Edge: "`cron-run-stale` hard-codes the workflow filename; renaming silently breaks the binding — update both call sites in `notice-frontmatter.sh` and `gdpr-gate.sh` in the same PR."

## Phase 5 — Stale fixture + self-test workflow (#3536)

- [ ] 5.1 Create `plugins/soleur/test/fixtures/gdpr-gate-stale/NOTICE` with `last-verified: 2025-11-01`, synthetic SHAs (`aaa...` / `bbb...`), 5 mirror `lifted-files:` entries. Verify `node apps/web-platform/scripts/lint-fixture-content.mjs` passes.
- [ ] 5.2 Write `plugins/soleur/test/gdpr-gate-self-test.test.sh` with three test cases mirroring TS5/TS6: (a) stale banner fires, (b) POSTURE_FAIL fires, (c) operator-attested banner fires when `GH_TOKEN=""`. Use `NOTICE_FILE=` env override.
- [ ] 5.3 Create `.github/workflows/gdpr-gate-self-test.yml`. Trigger: `pull_request` on `plugins/soleur/skills/gdpr-gate/scripts/**`, `plugins/soleur/test/fixtures/gdpr-gate-stale/**`, `lefthook.yml`. Pin `actions/checkout` to 40-char SHA. `timeout-minutes: 5`. Two jobs (or matrix): with-token, without-token. Route any `${{ }}` through `env:`.
- [ ] 5.4 Verify locally (`act` if available; else scratch-branch CI run) that the workflow fails when `gdpr-gate.sh` is temporarily broken to always echo zero days-stale. Revert the break before commit.

## Phase 6 — Lefthook cross-link (#3536)

- [ ] 6.1 Update `lefthook.yml` lines 94-100 comment to cross-link `.github/workflows/gdpr-gate-self-test.yml` as the load-bearing self-test. Do NOT add a fixture-based pre-commit stanza.

## Phase 7 — Runbook §1 rewrite (#3540)

- [ ] 7.1 Replace `knowledge-base/engineering/ops/runbooks/vendor-pin-drift-resolution.md` §1 with the cron-failure-path test (mutate one `upstream-blob-sha` to `0000...`, dispatch, assert `vendor/cron-failure` issue).
- [ ] 7.2 Validate the `sed` snippet against the live NOTICE indent on a scratch branch (4-space prefix on `upstream-blob-sha:`). Do not commit the scratch mutation.
- [ ] 7.3 Add a one-sentence scope note: the new §1 validates the cron-failure path only; the happy-path auto-PR requires real upstream content change.

## Phase 8 — Review

- [ ] 8.1 Run `bun test plugins/soleur/test/components.test.ts` — green.
- [ ] 8.2 Run `bash plugins/soleur/test/notice-frontmatter.test.sh` — green (all TS1-TS5 + TS-cron-1..4).
- [ ] 8.3 Run `bash plugins/soleur/test/gdpr-gate-self-test.test.sh` — green.
- [ ] 8.4 Push branch.
- [ ] 8.5 Run `/soleur:review` against the PR. `user-impact-reviewer` triggers via `requires_cpo_signoff: true` + `compliance/critical` label inheritance from closed issues.
- [ ] 8.6 Resolve all review findings inline.

## Phase 9 — Ship

- [ ] 9.1 Update PR body using the template in plan §"PR Body Template". Confirm `Closes #3535`, `Closes #3536`, `Closes #3540` each on its own line. Title must contain NO close/fix/resolve keywords.
- [ ] 9.2 Mark PR ready, run `gh pr merge 3541 --squash --auto`. Poll until MERGED.
- [ ] 9.3 Post-merge: `gh workflow run gdpr-gate-self-test.yml --ref main`. Poll. Verify green.
- [ ] 9.4 Post-merge: execute runbook §1 dry-run once against main. Close the test issue afterwards.
- [ ] 9.5 `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged`.
