---
title: "Tasks: gdpr-gate trust-hardening drain (#3535 + #3536 + #3540)"
branch: feat-gdpr-gate-trust-hardening-drain
plan: knowledge-base/project/plans/2026-05-11-refactor-gdpr-gate-trust-hardening-drain-plan.md
---

# Tasks

Derived from `knowledge-base/project/plans/2026-05-11-refactor-gdpr-gate-trust-hardening-drain-plan.md`. Phase order is contract-first; do NOT reorder.

## Phase 1 — Parser contract extension (#3535)

- [ ] 1.0 Add `make_gh_stub` helper to `plugins/soleur/test/test-helpers.sh` (or local equivalent) per plan §1.4. Used by TS-cron-2..5.
- [ ] 1.1 Write failing test `TS-cron-1` in `plugins/soleur/test/notice-frontmatter.test.sh`: `cron-run-stale` with `GH_TOKEN=""` AND `GITHUB_TOKEN=""` → emits `999`, exits 0.
- [ ] 1.2 Write failing test `TS-cron-2`: `cron-run-stale` with stub `gh` on `PATH` emitting `2026-02-01T00:00:00Z` → emits an integer in range 90-110.
- [ ] 1.3 Write failing test `TS-cron-3`: `cron-run-stale` with stub `gh` emitting `null` → emits `999`.
- [ ] 1.4 Write failing test `TS-cron-4`: `cron-run-stale` with stub `gh` emitting `"2026-02-01"` (missing `T...Z`) → emits `999`.
- [ ] 1.5 Write failing test `TS-cron-5`: `cron-run-stale` with stub `gh` that `sleep 10` → emits `999`, wall clock <6s.
- [ ] 1.6 Write failing test `TS12` (mirrors TS11 p95 timing): `cron-run-stale` with `GH_TOKEN=""` (no-network path) → p95 < 100ms over 100 invocations.
- [ ] 1.7 Implement `cron-run-stale` per plan §1.1 (full shell function listing). NOT the env-export-sentinel design — MIN computed in caller frame (`gdpr-gate.sh`).
- [ ] 1.8 Confirm `cmd_days_stale` is UNCHANGED (per plan §1.2 — MIN moved to caller).
- [ ] 1.9 Run tests; all TS-cron-1..5 + TS12 must pass. Run existing `bash plugins/soleur/test/notice-frontmatter.test.sh` — all TS1-TS11 still pass.

## Phase 2 — Gate caller wiring (#3535)

- [ ] 2.1 Modify `plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh` per plan §2.1 full listing. Invoke parser twice with both `NOTICE_FILE` (per R9) AND `GH_TOKEN` (or `GITHUB_TOKEN` fallback) propagated. MIN computed in caller frame.
- [ ] 2.2 Emit operator-attested-mode banner per plan §2.2 — exact literal string (load-bearing — self-test asserts verbatim). Triple-condition: `cron == 999 AND notice != 999` (NOT when both are 999).
- [ ] 2.3 Emit `gdpr-gate-cron-binding` incident via `incidents.sh` (variants: `applied`, `unavailable`, `min-wins`). All emits wrapped with `2>/dev/null || true`.
- [ ] 2.4 Manual smoke per plan §2.4 — four env combos, all must `echo "exit=0"`.

## Phase 3 — CODEOWNERS row (#3535)

- [ ] 3.1 Append the NOTICE row to `.github/CODEOWNERS` in the secret-scanning-floor block with the documented comment: `# Trust-binding gate — protects last-verified from drive-by edits (issue #3535).`
- [ ] 3.2 Verify the row order with `grep -nE '/plugins/soleur/skills/gdpr-gate/NOTICE' .github/CODEOWNERS` — confirm it lands between existing secret-floor rows, not the `*` fallback line.

## Phase 4 — SKILL.md docs (#3535)

- [ ] 4.1 Edit `plugins/soleur/skills/gdpr-gate/SKILL.md` §"Runtime staleness banner" to document the GH_TOKEN auth contract, MIN precedence, and operator-attested-mode banner.
- [ ] 4.2 Add the workflow-rename Sharp Edge: "`cron-run-stale` hard-codes the workflow filename; renaming silently breaks the binding — update both call sites in `notice-frontmatter.sh` and `gdpr-gate.sh` in the same PR."

## Phase 5 — Stale fixture + self-test workflow (#3536)

- [ ] 5.1 Create `plugins/soleur/test/fixtures/gdpr-gate-stale/NOTICE` per plan §5.1 with synthetic upstream paths (NOT real `pii-detector/*` paths — per R7) and synthetic SHAs. Verify `node apps/web-platform/scripts/lint-fixture-content.mjs plugins/soleur/test/fixtures/gdpr-gate-stale/NOTICE` passes.
- [ ] 5.2 Create `plugins/soleur/test/fixtures/gdpr-gate-stale/gh-stub/gh` (used by self-test Case B). Executable shell script that emits a valid RFC 3339 timestamp on `gh run list` and `exit 1` otherwise.
- [ ] 5.3 Write `plugins/soleur/test/gdpr-gate-self-test.test.sh` per plan §5.2 — three cases (A: no-token operator-attested banner; B: stub-gh present, no banner; C: exit 0 preserved).
- [ ] 5.4 Create `.github/workflows/gdpr-gate-self-test.yml` per plan §5.3. Two jobs: `without-token` (explicit `env: { GH_TOKEN: "", GITHUB_TOKEN: "" }`) and `with-token` (`env: { GH_TOKEN: ${{ github.token }} }`). `actions/checkout@692973e3d937129bcbf40652eb9f2f61becf3332 # v4.1.7` (mirrors vendor-pin-verify.yml). `timeout-minutes: 5`. `permissions: contents: read`.
- [ ] 5.5 Include the workflow file in its own `paths:` filter (self-bootstrap — runs against itself on this PR).
- [ ] 5.6 Negative-path verification (AC10): one-shot edit `gdpr-gate.sh` to drop the operator-attested banner; confirm `without-token` job fails. Revert before commit. DO NOT commit the break.

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
