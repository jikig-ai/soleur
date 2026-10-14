---
feature: rule-utility-scoring
issue: 2210
pr: 2213
branch: rule-utility-scoring
plan: knowledge-base/project/plans/2026-04-14-feat-rule-utility-scoring-plan.md
created: 2026-04-14
status: complete
---

# Tasks: Rule Utility Scoring

Task ordering encodes dependencies. Phases 1–6 are sequential; phase-internal subtasks can parallelize where noted.

## Phase 0 — Prerequisites

- [x] 0.1 Verify `$CLAUDE_SESSION_ID` exposure in hook env (echo test in `guardrails.sh`)
- [x] 0.2 Confirm PyYAML available in CI (`ubuntu-latest`) and local dev path
- [x] 0.3 Confirm `scripts/rule-audit.sh` and new aggregator can coexist (no write collision on AGENTS.md)

## Phase 1 — Rule ID Infrastructure

- [x] 1.1 Write failing test `tests/scripts/test_backfill_rule_ids.py` (TDD gate)
  - [ ] 1.1.1 Fixture AGENTS.md with 3 untagged rules → expect 3 IDs proposed, section prefixes correct
  - [ ] 1.1.2 Collision fixture → expect suffix disambiguation
  - [ ] 1.1.3 Idempotency fixture → expect no-op on already-tagged input
  - [ ] 1.1.4 Body-hash mismatch fixture → expect abort with error
- [x] 1.2 Implement `scripts/backfill-rule-ids.py`
  - [ ] 1.2.1 Slugify first-50-chars → kebab-case, 3-40 chars
  - [ ] 1.2.2 Section → prefix map (`hr-`, `wg-`, `cq-`, `rf-`, `pdr-`, `cm-`)
  - [ ] 1.2.3 Collision detection + numeric suffix
  - [ ] 1.2.4 Inline insertion at end-of-first-clause (matches `[hook-enforced: ...]` placement)
  - [ ] 1.2.5 MD5 body-hash pre/post (excluding frontmatter)
  - [ ] 1.2.6 `--dry-run` mode
- [x] 1.3 Run `python scripts/backfill-rule-ids.py --dry-run` → paste output into PR draft → run without flag → commit
- [x] 1.4 Write `scripts/lint-rule-ids.py`
  - [ ] 1.4.1 Detect missing `[id: ...]` on any rule under tagged sections
  - [ ] 1.4.2 Detect duplicate IDs across file
  - [ ] 1.4.3 Detect removed IDs (diff-aware against HEAD)
- [x] 1.5 Add `rule-id-lint` command to `lefthook.yml` (priority 4, glob `AGENTS.md`)
- [x] 1.6 Add ID-immutability rule to `AGENTS.md` (references `lint-rule-ids.py`)
- [x] 1.7 Verify lefthook blocks a test commit that removes an ID

## Phase 2 — Hook Telemetry

- [x] 2.1 Write failing tests for `incidents.sh`
  - [ ] 2.1.1 `tests/hooks/test_incidents.sh` — `emit_incident` writes valid JSON line
  - [ ] 2.1.2 Concurrency test — two bg `emit_incident &` calls → both lines present, flock serializes
  - [ ] 2.1.3 `BASH_SOURCE` resolution: source `incidents.sh` from two different hook paths → both resolve same jsonl file
  - [ ] 2.1.4 `detect_bypass` returns rule_id for `--no-verify` and `LEFTHOOK=0`; empty for `--force`
- [x] 2.2 Implement `.claude/hooks/lib/incidents.sh`
  - [ ] 2.2.1 `emit_incident <rule_id> <event_type> <rule_text_prefix> [command_snippet]` using `flock -x`
  - [ ] 2.2.2 `detect_bypass <tool> <command>` — v1 scope: `--no-verify` + `LEFTHOOK=0` only
  - [ ] 2.2.3 Source resolution via `${BASH_SOURCE[0]}` → repo root → `.claude/.rule-incidents.jsonl`
  - [ ] 2.2.4 TOCTOU guards per 2026-03-18 learning (`2>/dev/null || true` on jq)
- [x] 2.3 Wire `emit_incident` into `.claude/hooks/guardrails.sh` (6 deny sites + bypass preflight); source via `${BASH_SOURCE[0]}`
- [x] 2.4 Wire `emit_incident` into `.claude/hooks/pencil-open-guard.sh` (1 deny)
- [x] 2.5 Wire `emit_incident` into `.claude/hooks/worktree-write-guard.sh` (1 deny)
- [x] 2.6 Write `.claude/hooks/README.md` documenting contract + v1 bypass flags + rotation policy + macOS `brew install flock` note
- [x] 2.7 Update `.gitignore` with `.claude/.rule-incidents.jsonl`, `.claude/.rule-incidents-*.jsonl.gz`
- [x] 2.8 Extend `.github/workflows/test-pretooluse-hooks.yml` — assert jsonl line on each deny
- [x] 2.9 Run full hook smoke test: trigger each deny, verify jsonl contents

## Phase 3 — Schema Extension

- [x] 3.1 Add optional `rule_id` field to `plugins/soleur/skills/compound-capture/schema.yaml` (pattern `^(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]{3,40}$`)
- [x] 3.2 Mirror in `plugins/soleur/skills/compound-capture/references/yaml-schema.md`
- [x] 3.3 Severity sidecar: **skipped in v1** (ADR-5 deferred). File tracking issue D-severity-sidecar instead.
- [x] 3.4 Schema validation: run a sample learning through existing compound-capture validator

## Phase 4 — Compound Phase 1.5 Extension

- [x] 4.1 Edit `plugins/soleur/skills/compound/SKILL.md:138-198` — insert Step 3.5 "Ingest Recent Incidents"
  - [ ] 4.1.1 Read single `.claude/.rule-incidents.jsonl`; filter by recent timestamps
  - [ ] 4.1.2 Surface denies + bypasses as evidence to Deviation Analyst
  - [ ] 4.1.3 Explicitly state: no counter-increment side-effects (references ADR-1)
- [x] 4.2 Update Step 8 (rule-budget) to call aggregator with `--dry-run` and surface `rules_unused_over_8w` warning
- [x] 4.3 Verify Phase 1.5 still runs sequentially (no new subagents)

## Phase 5 — Aggregator Workflow

- [x] 5.1 Write failing test `tests/scripts/test-rule-metrics-aggregate.sh`
  - [ ] 5.1.1 Empty jsonl → valid JSON, all rules `hit_count: 0`
  - [ ] 5.1.2 Synthetic 3 denies for one rule → hit_count=3
  - [ ] 5.1.3 Re-run without changes → no-op (diff-noise mitigation)
  - [ ] 5.1.4 Malformed fixture → aggregator exits non-zero via `jq empty` gate
- [x] 5.2 Implement `scripts/rule-metrics-aggregate.sh`
  - [ ] 5.2.1 Parse AGENTS.md IDs + prefixes + section
  - [ ] 5.2.2 Read single `.claude/.rule-incidents.jsonl`
  - [ ] 5.2.3 Count per rule_id (primary) / rule_text_prefix (fallback)
  - [ ] 5.2.4 Compute `prevented_errors = max(0, hit_count - bypass_count)`
  - [ ] 5.2.5 Sort rules by `hit_count` ASC
  - [ ] 5.2.6 Write `knowledge-base/project/rule-metrics.json` only if materially changed
  - [ ] 5.2.7 Post-write `jq empty` validation; exit non-zero on malformed output
  - [ ] 5.2.8 Rotation: `mv jsonl → .rule-incidents-YYYY-MM.jsonl.gz` then truncate; month-based naming allows append within same month
- [x] 5.3 Write `.github/workflows/rule-metrics-aggregate.yml`
  - [ ] 5.3.1 Cron `0 0 * * 0` + `workflow_dispatch`
  - [ ] 5.3.2 `concurrency: scheduled-rule-metrics-aggregate`
  - [ ] 5.3.3 `permissions: contents: write`
  - [ ] 5.3.4 Commit step (no HEREDOCs — use `printf > file`)
  - [ ] 5.3.5 `notify-ops-email` on failure
- [x] 5.4 Add PR CI check that validates `rule-metrics.json` shape via `jq empty` on every change
- [x] 5.5 Manual `gh workflow run rule-metrics-aggregate.yml` → verify output committed
- [x] 5.6 Verify `rule-metrics.json` diffs as expected; update schema docs if shape drifts

## Phase 6 — /soleur:sync rule-prune Subcommand

- [x] 6.1 Write failing test `tests/commands/test-sync-rule-prune.sh`
  - [ ] 6.1.1 Fixture with 3 candidates → 3 issues filed (dry-run)
  - [ ] 6.1.2 Re-run → 0 new issues
  - [ ] 6.1.3 Existing issue (via `gh issue list --search`) → skipped (idempotent)
  - [ ] 6.1.4 `--weeks=0` with no candidates → 0 issues filed
- [x] 6.2 Edit `plugins/soleur/commands/sync.md`
  - [ ] 6.2.1 Extend `argument-hint` with `rule-prune`
  - [ ] 6.2.2 Add `rule-prune` to valid-areas
  - [ ] 6.2.3 Exclude from `all` dispatch (Phase 4 gate)
  - [ ] 6.2.4 Add Phase 1.2 sub-analysis `#### Rule Prune Analysis`
  - [ ] 6.2.5 Support `--weeks=<n>` override (default 8)
- [x] 6.3 Implement issue body template (rule text, counts, reassessment criteria; no severity in v1)
- [x] 6.4 Manual run: `/soleur:sync rule-prune --weeks=0` → verify issue filed; re-run verifies idempotent
- [x] 6.5 Regression test: run `/soleur:sync conventions` before + after; assert no behavior change

## Phase 7 — End-to-End Validation + Ship

- [x] 7.1 E2E: session → trigger `git stash` block → verify jsonl line
- [x] 7.2 E2E: session → `git commit --no-verify` after deny → verify bypass event
- [x] 7.3 E2E: `gh workflow run rule-metrics-aggregate.yml` → verify commit
- [x] 7.4 E2E: `/soleur:sync rule-prune --weeks=0` → verify issue filed
- [x] 7.5 Review gate: push branch + run `/soleur:review` per AGENTS.md `rf-push-before-review`
- [x] 7.6 QA gate: run `/soleur:qa` — screenshots N/A (no UI)
- [x] 7.7 Compound: capture learnings (likely: hook side-effect pattern, `flock` single-file jsonl, `BASH_SOURCE` resolution, simplified bypass scope)
- [x] 7.8 Ship via `/soleur:ship` — semver label `feat` (minor bump)
- [x] 7.9 Post-merge workflow verification: `gh workflow run rule-metrics-aggregate.yml` on main, poll until complete
- [x] 7.10 File deferral issues for Out of Scope items (dashboard, cross-project pooling, AI-assisted pruning)

## Deferrals to File During Implementation

- [x] D1 Dashboard/viz of `rule-metrics.json` trends → milestone "Post-MVP / Later"
- [x] D2 Cross-project rule utility pooling → milestone "Post-MVP / Later"
- [x] D3 AI-assisted pruning proposals → milestone "Post-MVP / Later"
- [x] D4 Structured JSON output from `rule-prune` → milestone "Post-MVP / Later"
- [x] D5 Severity sidecar (`rule-severity.yaml`) — re-evaluate if first prune cycle misclassifies a critical rule → milestone "Post-MVP / Later"
- [x] D6 Expanded bypass detection (`--force` on main, `--no-gpg-sign`, `--amend` after deny) — re-evaluate once baseline deny/bypass data accumulates → milestone "Post-MVP / Later"
