---
title: Rule Utility Scoring for AGENTS.md Rules and Learnings
date: 2026-04-14
issue: 2210
status: brainstormed
---

# Rule Utility Scoring

## What We're Building

A utility-scoring pipeline that measures which AGENTS.md hard rules and `knowledge-base/project/learnings/` entries actually earn their keep, and surfaces pruning candidates.

Two counters per rule/learning:

- `hit_count` — how many times the rule's guard (hook or skill instruction) has fired
- `bypass_count` — how many times the user escaped via a known bypass flag (`--no-verify`, `LEFTHOOK=0`, `--force`, etc.)

Derived: `prevented_errors = hit_count - bypass_count` — implicit preventions (the agent was stopped and complied).

Wired at three choke points:

1. **Hook scripts** (`.claude/hooks/*.sh`) append structured events to `.claude/.rule-incidents.jsonl` on deny — carry the `ruleId`, the `event_type` (`deny` or `bypass`), timestamp, session id, and first 50 chars of the rule text for fuzzy fallback.
2. **Compound Phase 1.5 Deviation Analyst** — already iterates rules against session evidence; extended to read recent `.jsonl` events and increment `hit_count` / `bypass_count` in matched learnings' frontmatter.
3. **Weekly cron** (GitHub Actions) aggregates `.jsonl` + frontmatter into `knowledge-base/project/rule-metrics.json` and surfaces pruning candidates (rules with `hit_count = 0` after N weeks) via a new `/soleur:sync rule-prune` sub-command.

## Why This Approach

Today `AGENTS.md` has 71 hard rules and 651 learnings. Phase 1.5 already warns at a 100-rule budget but we have no signal for what to prune. The 2026-04-07 "rule budget false alarm" incident showed raw counts alone desensitize users — we need *utility-weighted* data.

Evaluated but rejected: Memento-Teams' runtime self-rewrite loop. Contradicts our human-gated, git-as-source-of-truth model (per 2026-03-30 headless-compound-files-issues learning).

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| **V1 scope** | Full spec (both counters + .jsonl + cron + rule-metrics.json + rule-prune subcommand) | User prefers committed solution; open questions all resolvable within one PR |
| **Hit storage** | Frontmatter per learning, updated by compound | Git-visible drift, simple grep queries, accepted ~1-session lag |
| **Prevented_errors capture** | Derived from `bypass_count`, not prompted | Fully automated, avoids subjective human-confirmation prompts. Prevention = deny fired and user complied (didn't bypass) |
| **Bypass detection** | Enumerated flag list in hooks | Matches `--no-verify`, `--no-gpg-sign`, `--force` on push/checkout, `LEFTHOOK=0`, `HUSKY=0`, `git commit --amend` after rejection. Aligns with existing "never skip hooks" hard rule |
| **Rule ID scheme** | Slug-based, manually assigned (`[id: hr-stash-in-worktrees]`) | Human-readable, stable across rewords, matches existing `guardrails.sh:block-stash-in-worktrees` pattern |
| **ID enforcement** | Lint hook rejects new AGENTS.md rules without IDs and duplicates | Same tier as existing lefthook guards |
| **Aggregator** | Weekly GitHub Actions cron writes `rule-metrics.json` | Committed artifact, diff-visible trends, per issue |
| **Backfill strategy** | PyYAML migration script adds `hit_count: 0 / bypass_count: 0` to all 651 learnings | Uniform schema from day 1; reuses 2026-03-05 body-hash idempotency pattern to avoid bulk-YAML failure mode |
| **Identity fallback** | `{ruleId, first_50_chars_of_rule}` in jsonl — text match if ID missing | Survives AGENTS.md refactors where ID is dropped |
| **Headless mode** | `/soleur:sync rule-prune` files GitHub issues for pruning candidates; never auto-edits AGENTS.md | Per 2026-03-30 headless-compound learning |
| **Retirement threshold** | `hit_count = 0` after N weeks surfaces as candidate — N configurable, default 8 weeks | Candidates are surfaced, not auto-retired |

## Non-Goals

- No runtime skill rewriting (Memento's core mechanism — contradicts human-gated model)
- No abandoning `grep` for semantic retrieval (out of scope)
- No auto-retirement of rules (always human-in-loop via GitHub issue)
- No rich UI (plain markdown report from `rule-prune` subcommand)

## Open Questions

None remaining from issue — all three resolved:

1. **Counter staleness** → resolved (frontmatter + weekly cron; ~1-session lag accepted)
2. **Prevented-errors subjectivity** → resolved (derive from bypass; no prompts)
3. **Rule ID churn** → resolved (slugs + text-hash fallback; orphans accumulate as no-ops)

New questions surfaced and deferred to implementation:

- **N-weeks threshold default**: 8 weeks proposed, revisit after 2 months of data
- **.jsonl retention**: append-only, rotate monthly to `.claude/.rule-incidents-YYYY-MM.jsonl.gz`
- **Rule-prune report format**: plain markdown in v1, structured JSON output can follow

## Capability Gaps

None. All components (Bash hooks, jq, PyYAML, GitHub Actions cron, existing Phase 1.5 detector) are in place.

## Impact

- **Rule governance**: first time we have data-driven pruning signals
- **Learnings directory**: schema extended; 651 files get uniform counters via one migration
- **Compound**: Phase 1.5 gains a counter-increment side-effect (small, sequential, no new subagent)
- **Hooks**: 4 scripts touch to emit richer payloads; contract documented in `.claude/hooks/README.md` (new)

## Out-of-Scope Follow-ups

- Dashboard/visualization of `rule-metrics.json` trends (can build later from committed JSON)
- Cross-project rule utility pooling (multi-repo scoring)
- AI-assisted pruning proposals during compound
