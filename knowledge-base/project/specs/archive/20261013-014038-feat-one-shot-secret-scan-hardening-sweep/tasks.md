---
title: Tasks — Bundled secret-scan hardening sweep
plan: knowledge-base/project/plans/2026-05-15-fix-secret-scan-hardening-sweep-plan.md
branch: feat-one-shot-secret-scan-hardening-sweep
closes: [3759, 3322, 3323, 3160]
lane: cross-domain
---

# Tasks — Secret-scan hardening sweep

## Phase 0 — Preconditions

1.1. Create labels `secret-scan-allow-rename` and `secret-scan-allowlist-ack` via `gh label create` (Plan §Phase 0.1).
1.2. Local baseline: run `gitleaks git --no-banner --exit-code 1` and `bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh`; record results (Plan §Phase 0.2).
1.3. Update `.github/CODEOWNERS` to cover the three new helper scripts before they land (Plan §Phase 0.3 + §Phase 4.3 + §Phase 5.3).

## Phase 1 — Shared parser

2.1. Create `apps/web-platform/scripts/parse-gitleaks-allowlists.mjs` per spec (no-dep regex walker, JSON-array stdout, exit codes 0/2/3/4 per Plan §Phase 1).
2.2. Create `apps/web-platform/test/__synthesized__/parse-gitleaks-allowlists.test.sh` with 8 RED/GREEN cases (T1-T7 per Plan §Phase 1 + T8 v8.25-shape detection per Plan §Enhancement Summary).
2.3. Run the harness (`bash apps/web-platform/test/__synthesized__/parse-gitleaks-allowlists.test.sh`) — must report `Total: 8 pass, 0 fail`.
2.4. Verify dispatcher contract: `node apps/web-platform/scripts/parse-gitleaks-allowlists.mjs .gitleaks.toml | jq -e 'type == "array"'` exits 0.
2.5. Verify empirical baseline (AC22): `node apps/web-platform/scripts/parse-gitleaks-allowlists.mjs .gitleaks.toml | jq 'length'` returns ≥14.

## Phase 2 — JWT fixture synthesis (#3759)

3.1. Edit `plugins/soleur/skills/incident/test/fixtures/positive-corpus.md` line 13 to the placeholder-word form (Plan §Phase 2).
3.2. Re-run `bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh` — Test 2.JWT must remain green.
3.3. Re-run `gitleaks git --no-banner --exit-code 1` — must exit 0.

## Phase 3 — Linter glob extension (#3322)

4.1. RED test: stage `knowledge-base/project/learnings/best-practices/_red-test.md` with malformed waiver. Confirm lefthook lint-fixture-content does NOT fire (current bug). Confirm direct linter invocation DOES fire.
4.2. Edit `lefthook.yml` `lint-fixture-content` glob — add `"knowledge-base/project/learnings/**/*.md"`.
4.3. Edit `.github/workflows/secret-scan.yml` lines 107 and 115 grep -E patterns — add `|knowledge-base/project/learnings/.*\.md$` to alternation.
4.4. GREEN test: re-run lefthook; both fire on malformed waiver, accept on valid trailer.
4.5. Delete `_red-test.md` before commit.

## Phase 4 — Rename-laundering guard (#3160)

5.0. Update `.github/workflows/secret-scan.yml` `on:` block to `pull_request: types: [opened, synchronize, reopened, labeled, unlabeled]` (Plan §Phase 4.0). REQUIRED for label-based override path to react without empty-commit dance.
5.1. Create `apps/web-platform/scripts/rename-guard.sh` per spec.
5.2. Add `rename-guard` job to `.github/workflows/secret-scan.yml` (after `waiver-discipline`, before `smoke-tests`) calling `apps/web-platform/scripts/rename-guard.sh`.
5.3. Add 3 new smoke matrix cases: `rename-guard-fires`, `rename-guard-label-override`, `rename-guard-trailer-override`. Keep existing `rename-laundering` as canary.
5.4. Run `bash -c '<rename-guard.sh test-driver>'` locally with synthetic baseline + rename + trailer/label permutations to verify all 3 paths.
5.5. Verify trailer-key case-sensitivity: smoke fixture commit uses `Rename-Allowed-By: smoke-tests` (title-case-with-hyphens, mirroring `Co-Authored-By`). Script `--format='%(trailers:key=Rename-Allowed-By,valueonly)'` MUST match this exact case.

## Phase 5 — Allowlist-diff CI gate (#3323)

6.1. Create `apps/web-platform/scripts/allowlist-diff.sh` per spec.
6.2. Add `allowlist-diff` job to `.github/workflows/secret-scan.yml` (after `rename-guard`) calling `apps/web-platform/scripts/allowlist-diff.sh`. Permission: `pull-requests: write` ONLY (in addition to `contents: read`).
6.3. Add `allowlist-diff-fires` smoke matrix case.
6.4. Verify `gh api repos/.../issues/{N}/comments` contract (PR-comment endpoint accepts marker-keyed idempotent updates).

## Phase 6 — Runbook updates

7.1. Edit `knowledge-base/engineering/operations/secret-scanning.md` § Rename-laundering: replace "Follow-up tracked: #3160" with mitigation callout (Plan §Phase 6.1).
7.2. Add new § Allowlist-diff gate (Plan §Phase 6.2).
7.3. Update § `# gitleaks:allow` waivers to note learnings-glob coverage (Plan §Phase 6.3).
7.4. Update `last_updated:` frontmatter to 2026-05-15.

## Phase 7 — End-to-end CI verification

8.1. Push the branch; trigger PR.
8.2. Verify all jobs (scan, lint-fixture-content, waiver-discipline, rename-guard, allowlist-diff, smoke matrix) appear and produce expected outcomes.
8.3. AC18 (post-merge): verify both new jobs are required checks in branch protection.

## Phase 8 — Review + ship

9.1. Run `skill: soleur:review` (parallel multi-agent: DHH, Kieran, code-simplicity, security-sentinel, architecture-strategist).
9.2. Apply review fixes inline.
9.3. Run `skill: soleur:ship`. Verify `## Changelog` PATCH label, all 4 `Closes #N` lines on their own body lines.

## Done criteria

All 19 ACs in the plan green. PR merged. Issues #3759 #3322 #3323 #3160 auto-closed. Runbook reflects new gates. Operator runs AC18 + AC19 post-merge canary.
