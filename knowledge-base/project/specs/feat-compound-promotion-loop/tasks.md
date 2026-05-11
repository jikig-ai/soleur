# Tasks: feat-compound-promotion-loop (#2720)

Derived from `knowledge-base/project/plans/2026-05-11-feat-compound-promotion-loop-plan.md` (post-plan-review v2). Brand-survival threshold: `single-user incident`. CPO sign-off carried forward from brainstorm.

## Phase 0 — Pre-flight

- [ ] 0.1 Verify `self-healing/auto` label state via `gh label list --limit 200 | grep self-healing/auto` (workflow's idempotent step covers creation; AC14)

## Phase 1 — `bot-pr-with-synthetic-checks` extension

- [ ] 1.1 Create `.github/actions/bot-pr-with-synthetic-checks/CHANGELOG.md` documenting v2 inputs
- [ ] 1.2 Edit `action.yml` — add `draft`, `skip-auto-merge`, `labels` optional inputs with `'false'`/`''` defaults (AC1)
- [ ] 1.3 Add boolean normalization at top of run block (`tr '[:upper:]' '[:lower:]'` + reject non-boolean) — preserve `set -eo pipefail` (NOT `-euo`) (AC2, AC2b)
- [ ] 1.4 Wire `--draft` arg + label loop + auto-merge skip into existing run block
- [ ] 1.5 Add new env vars (`DRAFT`, `SKIP_AUTO_MERGE`, `LABELS`) to action's env block
- [ ] 1.6 Backward-compat verify: read `scheduled-rule-prune.yml` and `rule-metrics-aggregate.yml`; defaults preserve their behavior

## Phase 2 — `scripts/compound-promote.sh` driver (TDD)

- [ ] 2.1 Create `scripts/compound-promote.test.sh` with 3 test cases (no-config, disabled, GDPR-pre-pass-excludes-PII) — RED gate (AC4)
- [ ] 2.2 Create `tests/fixtures/compound-promote/learnings/*.md` with synthesized PII only (`@example.com`, zero-UUIDs) (AC24)
- [ ] 2.3 Implement `scripts/compound-promote.sh` — pipeline: opt-in → week-cap → GDPR pre-pass → retired-rule pre-pass → Anthropic API call → emit clusters JSON sentinel
- [ ] 2.4 Hard slice at `WEEK_REMAINING` via `jq '.[0:$cap]'` (AC12, Architecture #2)
- [ ] 2.5 GDPR shell pre-pass uses canonical PII regex (emails, IPv4, IBAN); excludes matching files (AC13)
- [ ] 2.6 Retired-rule shell pre-pass reads `scripts/retired-rule-ids.txt` field-4 breadcrumbs; excludes referenced learning paths
- [ ] 2.7 Anthropic API call via plain `curl` (NOT claude-code-action wrapper); model `claude-sonnet-4-6`; CORPUS = path + first-10-lines per file
- [ ] 2.8 Validate response JSON shape via `jq -e 'type == "array"'` (defensive equivalent of v1 FR12)
- [ ] 2.9 Run `bash scripts/compound-promote.test.sh` — GREEN (AC10a)
- [ ] 2.10 Mirror `rule-prune.sh` CLI conventions (env override, stdout sentinels, set -euo) (AC3)

## Phase 3 — `scheduled-compound-promote.yml` workflow

- [ ] 3.1 Create `.github/workflows/scheduled-compound-promote.yml` — single `promote` job (no matrix), cron `0 0 * * 0`, concurrency `scheduled-compound-promote`, `cancel-in-progress: false` (AC5)
- [ ] 3.2 Add `preflight` job using `./.github/actions/anthropic-preflight`
- [ ] 3.3 Add idempotent `Ensure self-healing/auto label exists` step (AC14)
- [ ] 3.4 Wire driver step that captures `clusters_b64` output sentinel
- [ ] 3.5 Add per-cluster bash loop (`while IFS= read -r cluster`) — NOT a matrix
- [ ] 3.6 Add cluster-hash integrity verification step (recompute via `sha256sum` + compare to claimed; refuse on mismatch) (AC11, Architecture #3)
- [ ] 3.7 Inline PR creation: `git apply` → audit-log append → `gh pr create --draft` → `gh pr edit --add-label` → synthetic check-runs (4 + cla-check)
- [ ] 3.8 Provenance trailer: `Bot-Author:` + `Source-Learnings:` + `Threshold-Hit:` + `Cluster-Hash:` + `Tier:` (NO `Promoted-By:`) (AC18)
- [ ] 3.9 `email-on-failure` job covers preflight + promote failures
- [ ] 3.10 Permissions explicitly declared: `contents: write`, `pull-requests: write`, `checks: write`, `issues: write`

## Phase 4 — Config + audit-log scaffolds

- [ ] 4.1 Create `knowledge-base/project/promotion-config.yml.example` with 4-line data-flow disclosure comment (AC6)
- [ ] 4.2 Edit `.gitignore` — add `knowledge-base/project/promotion-config.yml` + defensive `.github/promotion-*.json` (AC7)
- [ ] 4.3 Create `knowledge-base/project/learnings/promotion-log.md` (append-only audit log scaffold; AC22)
- [ ] 4.4 Read `knowledge-base/legal/compliance-posture.md` (per `hr-always-read-a-file-before-editing-it`); add Active Item row for #2720 with DPIA candidacy note (AC9)

## Phase 5 — Compound skill cross-reference

- [ ] 5.1 Edit `plugins/soleur/skills/compound/SKILL.md` — append Layer 2 cross-reference subsection (≤4 lines) (AC8)

## Phase 6 — Operator runbook

- [ ] 6.1 Create `knowledge-base/engineering/runbooks/compound-promote-runbook.md` — opt-in (3 cmds), opt-out (1 cmd), review heuristic (5 bullets), revert path (1 sentence), sharp edges (5 bullets)

## Phase 7 — Pre-merge verification

- [ ] 7.1 `bash scripts/compound-promote.test.sh` GREEN
- [ ] 7.2 Hand-test driver with fixtures: `COMPOUND_PROMOTE_FIXTURE_ROOT=... GH_BIN=... CURL_BIN=... ANTHROPIC_API_KEY=fake bash scripts/compound-promote.sh`
- [ ] 7.3 PR #3559 body: `Closes #2720` (own line) + `Ref #2718` + `Ref #421` + `## Changelog` section (AC15)
- [ ] 7.4 Run `pr-auto-close-scanner.yml` regex check on PR body — only `Closes #2720` matches (AC15b)
- [ ] 7.5 Operator: invoke `/soleur:review #3559` before mark-as-ready; resolve `user-impact-reviewer` findings (AC10b)

## Phase 8 — Issue updates + ADR

- [ ] 8.1 Create `knowledge-base/engineering/architecture/decisions/ADR-021-stateless-self-modifying-cron.md` (Architecture #5 advisory; AC17)
- [ ] 8.2 File pre-existing Anthropic-DPA gap as separate `compliance/improvement` issue; reference in AC23/AC26
- [ ] 8.3 Verify Anthropic processor row exists in `compliance-posture.md` Vendor DPAs BEFORE merge (AC23)
- [ ] 8.4 Post-merge: `gh workflow run scheduled-compound-promote.yml` and `gh run watch`; investigate failures per `wg-after-merging-a-pr-that-adds-or-modifies` (AC16)

## Phase 9 — Plan-review consensus completion

- [ ] 9.1 5-agent plan-review consensus changes applied (this v2 plan); findings resolved or scoped out (AC19)

## Acceptance criteria summary

Total: 28 ACs (AC1-AC24 with AC2b / AC10a / AC10b / AC15b sub-IDs). See plan §Acceptance Criteria for measurable definitions.

## Notes

- /work MUST follow phase ordering (1 → 2 → 3 → 4-6 → 7 → 8). Phase 1 (composite extension) is the contract change; Phase 3 (workflow) is the consumer. Per AGENTS.md `2026-05-10-plan-phase-order-load-bearing-when-contract-changes`.
- Phase 2 follows TDD: write failing test (2.1), implement (2.3), verify GREEN (2.9). Per AGENTS.md `cq-write-failing-tests-before`.
- All shell scripts use `set -euo pipefail`. Composite action preserves `set -eo pipefail` (NOT upgraded to `-u`).
