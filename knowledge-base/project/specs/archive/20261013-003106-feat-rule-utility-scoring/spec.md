---
feature: rule-utility-scoring
issue: 2210
branch: rule-utility-scoring
created: 2026-04-14
status: spec
brainstorm: knowledge-base/project/brainstorms/2026-04-14-rule-utility-scoring-brainstorm.md
---

# Spec: Rule Utility Scoring

## Problem Statement

`AGENTS.md` holds 71 hard rules and the learnings directory holds 651 entries. Phase 1.5 warns at a 100-rule budget, but there is no signal for *which* rules earn their keep. Prior pruning efforts (2026-02-25 lean-AGENTS.md, 2026-04-07 budget false alarm) relied on judgment alone. Without utility data, rule growth compounds and desensitization is inevitable.

## Goals

- G1. Every hard rule in `AGENTS.md` carries a stable, human-readable slug ID.
- G2. Every hook deny and every known bypass flag produces a structured event in `.claude/.rule-incidents.jsonl`.
- G3. Compound Phase 1.5 increments `hit_count` / `bypass_count` on the matched learning's frontmatter using jsonl events plus session evidence.
- G4. A weekly cron aggregates jsonl + frontmatter into committed `knowledge-base/project/rule-metrics.json`.
- G5. `/soleur:sync rule-prune` surfaces pruning candidates (rules with `hit_count = 0` after N weeks) and files GitHub issues for them.

## Non-Goals

- NG1. No runtime skill rewriting or auto-retirement.
- NG2. No human-prompted "was this a real prevention?" UX (derived from bypass_count instead).
- NG3. No dashboard/viz in v1 — plain markdown report only.
- NG4. No multi-repo scoring pool.

## Functional Requirements

- **FR1** — Every rule in `AGENTS.md` `## Hard Rules` and `## Workflow Gates` sections carries an `[id: hr-<slug>]` tag inline with the existing `[hook-enforced: ...]` / `[skill-enforced: ...]` convention.
- **FR2** — A lefthook rule-id-lint check rejects commits that add a hard rule without an `[id: ...]` tag, or introduce duplicate IDs.
- **FR3** — Every PreToolUse deny hook emits a JSON event to `.claude/.rule-incidents.jsonl` with shape `{timestamp, session_id, rule_id, event_type: "deny", rule_text_prefix, tool, command_snippet}`.
- **FR4** — Every PreToolUse hook also detects bypass flags (`--no-verify`, `--no-gpg-sign`, `--force`/`-f` on push/checkout, `LEFTHOOK=0`, `HUSKY=0`, `git commit --amend` immediately after a prior deny) and emits an `event_type: "bypass"` event to the same jsonl.
- **FR5** — Schema (`plugins/soleur/skills/compound-capture/schema.yaml` + `references/yaml-schema.md`) is extended with optional `hit_count: 0` and `bypass_count: 0` fields. `prevented_errors` is not stored — derived as `max(0, hit_count - bypass_count)`.
- **FR6** — Compound Phase 1.5 reads `.claude/.rule-incidents.jsonl` entries newer than the learning's last compound run, matches each event to a learning via `rule_id` (fallback: `rule_text_prefix`), and increments the learning's frontmatter `hit_count` / `bypass_count`. Events are marked processed (file rotated or water-marked).
- **FR7** — A PyYAML migration script backfills `hit_count: 0` and `bypass_count: 0` on all existing learnings, using body-hash idempotency (per 2026-03-05 pattern) so re-runs are safe.
- **FR8** — `.github/workflows/rule-metrics-aggregate.yml` runs weekly (Sunday 00:00 UTC), reads all learnings' frontmatter + tail of jsonl, writes `knowledge-base/project/rule-metrics.json` (rules sorted by utility), and commits if changed.
- **FR9** — `/soleur:sync rule-prune` reads `rule-metrics.json`, finds rules with `hit_count = 0` older than N weeks (default 8), and for each files a GitHub issue titled `rule-prune: consider retiring <rule-id>` milestoned to `Post-MVP / Later` — never auto-edits `AGENTS.md`.

## Technical Requirements

- **TR1** — Jsonl writes are append-only (`>>`) with per-session files optional if concurrency issues emerge. Guard against jq parse errors per 2026-03-18 TOCTOU learning.
- **TR2** — Hook payload additions must not break the existing `{hookSpecificOutput: {permissionDecision, permissionDecisionReason}}` contract — only *add* `ruleId` alongside it.
- **TR3** — Rule ID slugs are lowercase-kebab-case, prefixed `hr-` (hard rule) or `wg-` (workflow gate). Pattern: `hr-[a-z0-9-]{3,40}`.
- **TR4** — Backfill migration writes via PyYAML (not sed/awk), preserves body verbatim (MD5 body-hash check pre/post), idempotent on re-run.
- **TR5** — Aggregator workflow uses the existing `.github/actions/notify-ops-email` pattern on failure (not Discord).
- **TR6** — `rule-metrics.json` is committed and diff-visible. Schema: `{rules: [{id, hit_count, bypass_count, prevented_errors, last_hit, first_seen}], learnings: [...], generated_at}`.
- **TR7** — `.claude/.rule-incidents.jsonl` is gitignored (per-machine). Aggregated data in `rule-metrics.json` and frontmatter counts are committed.
- **TR8** — .jsonl rotation: monthly snapshot to `.claude/.rule-incidents-YYYY-MM.jsonl.gz`, active file truncated after successful rollup.

## Acceptance Criteria

- [ ] All 71+ rules in `AGENTS.md` Hard Rules + Workflow Gates carry `[id: hr-<slug>]` or `[id: wg-<slug>]` tags.
- [ ] Lefthook rejects commits adding untagged hard rules or duplicate IDs.
- [ ] `schema.yaml` + `references/yaml-schema.md` extended with `hit_count` / `bypass_count`.
- [ ] All 4 hooks emit structured jsonl events on deny and bypass.
- [ ] Compound Phase 1.5 increments frontmatter counts on matched learnings end-to-end (verified via integration test).
- [ ] PyYAML migration script runs cleanly on 651 learnings, body-hash check passes, re-run is no-op.
- [ ] `rule-metrics-aggregate.yml` workflow runs, writes `rule-metrics.json`, auto-commits.
- [ ] `/soleur:sync rule-prune` subcommand exists and files GitHub issues for candidates.
- [ ] First post-merge scheduled run completes successfully (per AGENTS.md workflow-verification rule).

## Dependencies

- Existing: Phase 1.5 Deviation Analyst (compound), `.claude/hooks/*.sh` guardrail infrastructure, `guardrails.sh` rule-id convention, existing `[hook-enforced: ...]` / `[skill-enforced: ...]` tag pattern.
- New: PyYAML (likely already in repo for other migrations — verify during plan phase).

## Risks

- **R1** — Slug assignment across 71 rules is manual and tedious. Mitigation: do it in a single focused session with the canonical tag-placement rules from `2026-03-05-plan-review-scope-reduction-and-hook-enforced-annotations.md`.
- **R2** — Bypass detection false positives (e.g., `--force` used legitimately). Mitigation: scope bypass detection to contexts where a prior deny fired in the same session window.
- **R3** — PyYAML migration could corrupt 651 learnings. Mitigation: body-hash verification, backup branch, dry-run mode, explicit user confirmation before writing.
- **R4** — Weekly cron could write noisy diffs if counts shift incrementally. Mitigation: only write if rule-metrics.json materially changed (diff > noise threshold).

## Out of Scope

- Visualization dashboard (later, after a few months of data)
- Cross-project utility pooling
- AI-authored pruning proposals
