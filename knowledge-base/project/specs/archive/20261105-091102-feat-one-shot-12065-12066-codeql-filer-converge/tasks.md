# Tasks — feat-codeql-filer-convergence (issues #12065, #12066)

Plan: `knowledge-base/project/plans/2026-11-04-feat-codeql-filer-convergence-plan.md`
Reviewed-Coverage: sequential-fallback (harness cannot spawn subagents).

## Phase 1 — Gate script sweep mode (`scripts/codeql-main-alert-gate.sh`)

- [x] 1.1 Add `SWEEP="${SWEEP:-false}"` to the env inputs block; validate `true|false` (exit 2, before any API call) alongside the existing `DRY_RUN` check. Update the header INPUTS doc.
- [x] 1.2 Make `SHA` validation mode-aware: `SWEEP=false` → `^[0-9a-f]{40}$` required (unchanged); `SWEEP=true` + non-empty → same validation; `SWEEP=true` + empty → permitted pending resolution.
- [x] 1.3 Add the mode branch after `WORK`/`trap` setup (~line 213), phases 1–2 kept at column 0 inside `else` so `mutants.sh` `^`-anchors keep landing. Sweep arm: `fetch_page "main HEAD" "$WORK/main-head.json" "repos/${GH_REPO}/commits/main"` → `jq -r '.sha // empty'` → re-validate 40-hex, else `degrade "api-error"`.
- [x] 1.4 Make `upsert_degraded` mode-aware: title `codeql-gate-degraded` (push) / `codeql-sweep-degraded` (sweep); body names the trigger and the correct sibling signal as the backstop. Same `LABELS_P2`.
- [x] 1.5 Update the header: INPUTS documents `SWEEP` + SHA optional-in-sweep; VERDICT notes both modes.

## Phase 2 — Workflow rewiring (`.github/workflows/codeql-to-issues.yml`)

- [x] 2.1 `check-alerts`: replace the inline run block with a pinned-SHA `actions/checkout` step (`persist-credentials: false`, `sparse-checkout: scripts/codeql-main-alert-gate.sh`, `sparse-checkout-cone-mode: false` — same pinned SHA as `codeql-main-alert-gate.yml`) + `run: bash scripts/codeql-main-alert-gate.sh`. Env: `GH_TOKEN`, `GH_REPO`, `SWEEP: 'true'`, `GITHUB_RUN_ID`, `DEADLINE_SECONDS: '240'`, `DRY_RUN: ${{ inputs.dry_run == true && 'true' || 'false' }}`. `timeout-minutes: 10`.
- [x] 2.2 Add `dry_run` boolean input to `workflow_dispatch`; add `contents: read` to `permissions`; update the header comment.
- [x] 2.3 `close-orphans`: `ALL_DISMISSED` predicate accepts `dismissed|fixed` explicitly; `REASONS` records `- alert #${AN}: ${STATE}`; close comment reads "dismissed or fixed"; `keep-open` unchanged.

## Phase 3 — Gate suite + fixtures

- [x] 3.1 Shim `plugins/soleur/test/fixtures/codeql-main-alert-gate/shim/gh`: add `*/commits/main` endpoint key `main-head` (failure injection free via `fail_if_injected`).
- [x] 3.2 Fixtures: `base/main-head.json` (synthesized commit object, `.sha` = `GOOD_SHA`), `scenarios/issue-sweep-degraded.json` (open issue titled `codeql-sweep-degraded`, `_author` bot, `_labels` per LABELS_P2).
- [x] 3.3 `sw*` rows in `codeql-main-alert-gate.test.sh`: sweep happy path (zero check-runs/analyses calls), SHA-unset resolution, resolve failure degrades, `codeql-sweep-degraded` title + second-run comment, dedupe GREEN, invalid `SWEEP`/invalid-`SHA` exit 2, `DRY_RUN` in sweep, phase-3 API failure non-green.
- [x] 3.4 `s1`: pin sanctioned `fetch_page` label set (`analyses` + `main HEAD`). `s2`: exempt `codeql-to-issues.yml` as the sanctioned caller.
- [x] 3.5 `mutants.sh`: re-anchor any broken patterns; add sweep mutants (guard dropped, SHA unvalidated, title not mode-aware, SHA still required).
- [x] 3.6 Re-derive `FLOOR`/`MUTANT_FLOOR` from a green run.

## Phase 4 — New sweep wiring suite

- [x] 4.1 `plugins/soleur/test/fixtures/codeql-to-issues-sweep-wiring/sweep_facts.py` — parsed-YAML facts helper (job `check-alerts` + `close-orphans` facts; env evaluation per event incl. dispatch `dry_run`).
- [x] 4.2 `plugins/soleur/test/codeql-to-issues-sweep-wiring.test.sh` — assertions per Guard 2/3 + mutation battery; self-contained verdict/floor machinery mirroring the gate wiring suite.
- [x] 4.3 Register in `scripts/suite-shard-legs.tsv` (appropriate leg) + `scripts/suite-durations.tsv` (`floor` entry).
- [x] 4.4 `.github/CODEOWNERS` rows for the new suite + fixture dir.

## Phase 5 — Records + verification

- [x] 5.1 ADR-270 addendum (dated): one filer/two triggers; `|| true` residual retired; two degraded titles; `fixed`-state reaper.
- [x] 5.2 Accuracy-check `knowledge-base/engineering/operations/runbooks/codeql-bot-coverage.md`; edit only if its machinery description is stale.
- [x] 5.3 Run `bun test plugins/soleur/test/components.test.ts` — confirm `findUnboundedEnumerations` does not flag `gh api repos/.../commits/main` (coded exemption if flagged).
- [x] 5.4 Run `bash plugins/soleur/test/codeql-main-alert-gate.test.sh`, `bash plugins/soleur/test/codeql-main-alert-gate-workflow-wiring.test.sh`, the new suite, `GATE_MUTANTS=1` battery, and `bash scripts/test-all.sh --affected` (or the owning shard leg).
- [x] 5.5 Acceptance criteria AC1–AC11 checked.
