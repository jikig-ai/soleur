# Tasks: CI claude CLI pins below the Bun 1.4.4 fix (Closes #12102)

Plan: `knowledge-base/project/plans/2026-11-05-fix-ci-claude-cli-pins-bun-1-4-4-plan.md`
Branch: `feat-one-shot-12102-ci-claude-cli-pins` | Draft PR 12136 | PR body uses `Closes #12102`.

## Phase 0 - Baseline (read-only)

- 0.1 `date -u`; confirm #12026 CLOSED; run `bash scripts/followthroughs/ci-claude-cli-pins-bun-12073.sh` (expect exit 5).
- 0.2 Confirm 2.1.311 and 0.3.311 resolve on npm.

## Phase 1 - marketplace-drift CLI pin (CTO F1)

- 1.1 Scratch-install `@anthropic-ai/claude-code@2.1.311` into a temp prefix; record sha256; run `strings <bin> | grep -m1 -E '^Bun v[0-9]+\.[0-9]+\.[0-9]+'` (expect `Bun v1.4.4`).
- 1.2 `CANARY_CLI=<scratch>/bin/claude bash scripts/plugin-delivery-canary.sh`: exit 0, `compared` > 0, no `installpath_unresolved`. Red blocks the merge.
- 1.3 Edit `CLI_VERSION` in `.github/workflows/scheduled-marketplace-drift.yml` to `"2.1.311"`.
- 1.4 Run `adhoc-npm-install-pin-table.test.ts` unchanged (no test edit).

## Phase 2 - claude-code-action v1.0.263 (CTO F2)

- 2.1 Re-resolve tag object `3b7e1a45ca6f231c62605aabcf79e6a41b08c7da` and CLI/Bun versions at v1.0.263.
- 2.2 Diff `action.yml` inputs/outputs v1.0.236 to v1.0.263; confirm every `with:` key in the five files exists.
- 2.3 Replace `20f0b248c5003db4b9ca43c45e17949bcdc36d2d # v1.0.236` in the four workflows and `constraint-scaffold/references/fix-constraints-stage-a.template`.
- 2.4 Check `knowledge-base/legal/article-30-register.md` for a current-fact mention of the pinned version.
- 2.5 Run `claude-code-action-auth.test.sh`, constraint-scaffold `parity.test.sh`, `audit-models.sh` section 2.
- 2.6 Push; dispatch `test-pretooluse-hooks.yml` on the branch; arm a Monitor on the run.

## Phase 3 - pen-cli lock (CTO F3)

- 3.1 Add exact `overrides` entry to `pen-cli/package.json`.
- 3.2 Regenerate lock with `npx --yes npm@11.21.1 install --package-lock-only --ignore-scripts --no-audit --no-fund`; confirm diff is the nine SDK entries plus SDK `engines.node`.
- 3.3 Run `engine-contract-probe.sh` via Doppler dev (read-only); on failure to run, drop Phase 3 and say why.
- 3.4 Run `check-deps-adapter-drift.test.sh`, `lint-dual-lockfile.test.sh`, `pencil-adapter-sentinels`.

## Phase 4 - Ship wiring

- 4.1 File the follow-up issue for `operator-digest.workflow.yml` (v1.0.101); net-issue-flow override marker with justification and `Filed:` line if the gate demands.
- 4.2 PR body: `Closes #12102`, Brotli statement, canary/probe/dispatch results, expected-non-required `claude-code-review` note, customer reinstall note. Label `meta/machinery`.
- 4.3 Read non-required `infra-validation` and `sandbox-canary-capture-gate` on the pushed head; required checks: test, lockfile-sync, markdown-lint, tenant-integration-required.
- 4.4 Registry files: no rows expected; any added row goes in sorted position.

## Phase 5 - Post-merge

- 5.1 Probe script with ambient `gh` token exits 0 against `main`.
- 5.2 `gh workflow run scheduled-marketplace-drift.yml` on `main`; Monitor the run; read the canary verdict.
- 5.3 #12102 closed by the merge.
