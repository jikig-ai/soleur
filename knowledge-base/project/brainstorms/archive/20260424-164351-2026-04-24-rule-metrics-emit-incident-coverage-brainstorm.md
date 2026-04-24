---
title: Rule-metrics emit_incident coverage (hooks + skills)
date: 2026-04-24
issue: 2866
branch: feat-one-shot-2866-rule-metrics-emit-incident-coverage
status: ready-for-plan
---

# Rule-Metrics emit_incident Coverage — Brainstorm

## What We're Building

Close the telemetry gap that causes every AGENTS.md rule to show `hit_count=0, first_seen=null` in `knowledge-base/project/rule-metrics.json`. Two concrete silent surfaces:

1. **Silent hooks** — `pre-merge-rebase.sh`, `security_reminder_hook.py`, and `docs-cli-verification.sh` never call `emit_incident`. (`guardrails.sh`, `worktree-write-guard.sh`, `pencil-open-guard.sh` already emit.)
2. **Skill-enforced rules** — 10 rules tagged `[skill-enforced: <skill> Phase <N>]` have no self-report path. Skills are blind to the telemetry pipeline today.

Goal: make `scripts/rule-prune.sh --dry-run` output structurally usable. Today it would file ~101 false-positive retirement issues.

## Why This Approach

### Decision 1 — Skill emission surface: source `incidents.sh` directly, extend enum

Skills source `.claude/hooks/lib/incidents.sh` via a bash tool call at the entry of the phase that applies a `[skill-enforced]` rule, and invoke `emit_incident <rule-id> applied <prefix>`. No wrapper script, no separate Python path, no git-log scan aggregator.

- **Why not wrapper script:** Adds two files + a subprocess hop; no meaningful abstraction win over direct sourcing.
- **Why not git-log markers:** Only captures applications that land in a commit; misses phase-entry gates that don't produce a commit (e.g., `work` Phase 2 TDD Gate, `brainstorm` Phase 0.5 domain assessment — both fire before any commit exists).
- **Why not defer skill emission to a follow-up:** Issue #2866's stated scope explicitly includes "Define a skill-level incident-emission surface." Splitting would leave the main pain point (zero signal for skill-enforced rules) unfixed.

### Decision 2 — Extend `event_type` enum within schema v1 (no schema bump)

Add two new `event_type` values:

- `applied` — emitted by skills when they apply a `[skill-enforced]` rule
- `warn` — emitted by advisory hooks (`docs-cli-verification.sh`) that flag without denying

The existing `deny` and `bypass` values keep their semantics. `SCHEMA_VERSION` stays at `1`; the field is a free-form string — the enum is documentation, not a schema-enforced constraint. Aggregator gets a PR-coupled update to count `applied` and `warn` (both contribute to `hit_count`) but to keep them visible as separate columns in the summary (so rule-prune can distinguish "actively applied by a skill" from "hook denied a user").

### Decision 3 — Python emitter ported inline in `security_reminder_hook.py`

Port a minimal `emit_incident()` helper inline (same file) using `fcntl.flock` (POSIX; silent best-effort on non-POSIX). Duplicate `SCHEMA_VERSION=1` and the field layout. Python and bash emitters each carry a cross-reference comment.

- **Why not shell out to bash:** Adds a subprocess hop per `PreToolUse` fire (latency matters; this hook runs on every bash command). Also fragile: if `bash` is missing or sourcing fails, telemetry silently drops.
- **Why not shared JSON schema file:** Over-engineered for one Python caller. If/when a second Python hook or skill needs emission, we revisit.

### Decision 4 — `pre-merge-rebase.sh` reuses existing rule-ids

Source `incidents.sh` at top of the script. Emit under existing rule-ids rather than creating new ones:

- review-evidence-gate deny → `rf-never-skip-qa-review-before-merging`
- merge-conflict deny → `hr-when-a-command-exits-non-zero-or-prints`
- push-failure deny → `hr-when-a-command-exits-non-zero-or-prints`

Zero AGENTS.md byte growth (currently 36946 / 37000 budget). Precision trade-off accepted: `hr-when-a-command-exits-non-zero-or-prints` will receive events from two distinct paths, but that rule is already broad by intent.

### Decision 5 — `docs-cli-verification.sh` emits `warn`, source `incidents.sh`

Extend the hook to emit `warn` on each flagged CLI token under `cq-docs-cli-verification`. Without this, the only enforcement-signal rule for `cq-docs-cli-verification` never gets a hit and rule-prune would retire a load-bearing rule.

### Decision 6 — No historical backfill

`git log --all --oneline --grep="LEFTHOOK=0\|--no-verify"` returns 2 commits in the full history — both on feature branches, neither reflecting real bypass volume. Not worth the backfill script complexity. Live telemetry starts at merge and grows forward.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Skills source `incidents.sh` + call `emit_incident` | Lowest friction; matches hook pattern |
| 2 | Extend `event_type` with `applied`, `warn`; stay on schema v1 | Backward compat; no migration |
| 3 | Port minimal Python `emit_incident` into `security_reminder_hook.py` | Avoid bash subprocess hop in PreToolUse |
| 4 | `pre-merge-rebase.sh` reuses existing rule-ids | Zero AGENTS.md growth; broad rule already exists |
| 5 | `docs-cli-verification.sh` emits `warn` | Only signal that `cq-docs-cli-verification` is doing work |
| 6 | No backfill | History has 2 relevant commits total |
| 7 | Aggregator counts `applied`/`warn` as hits | Rule-prune needs these to avoid false-positive retirement |
| 8 | 10 skill-enforced rules each get a phase-entry emission | Surgical: only the tagged rules, only at the phase named in the tag |

## Scope (maps to issue acceptance criteria)

### FR1 — Silent-hook emission coverage

- `pre-merge-rebase.sh` sources `incidents.sh` and emits on all 3 deny paths
- `security_reminder_hook.py` carries a minimal Python emitter and emits on the workflow-injection deny
- `docs-cli-verification.sh` sources `incidents.sh` and emits `warn` on each flagged line

### FR2 — Skill-enforced emission surface

- Each of the 10 `[skill-enforced: <skill> Phase <N>]` rules gets a single emission point in the named skill at the named phase
- Emission shape: bash tool call running `source .claude/hooks/lib/incidents.sh && emit_incident <rule-id> applied "<prefix>"` at phase entry
- The skill's SKILL.md gets a one-line instruction in the relevant phase block ("Emit rule-application telemetry: …")

### FR3 — Aggregator handles new event types

- `scripts/rule-metrics-aggregate.sh` accepts `applied` and `warn` as valid `event_type` values
- `hit_count` includes applied+warn+deny; `bypass_count` stays narrow (only `bypass`)
- Summary exposes `applied_count` and `warn_count` as new per-rule columns
- Malformed-line tolerance preserved (unknown `event_type` values still emit `::warning::`)

### FR4 — rule-prune.sh output validation

- Run `scripts/rule-prune.sh --dry-run` in CI after merge; verify the orphan-id list is empty and unused-rule count drops from ~101 toward 0 (modulo rules that genuinely haven't been exercised yet in the short post-merge window)

## Non-Goals

- **Historical backfill** — skipped per Decision 6
- **New rule-ids for pre-merge-rebase.sh paths** — reuse existing per Decision 4
- **Schema v2** — extend enum within v1 per Decision 2
- **Bypass detection v2** (`--force` on main, `--no-gpg-sign`, `--amend` after deny) — deferred from prior cycle, stays deferred
- **Command-snippet mining** — `command_snippet` field stays empty; aggregator doesn't mine it
- **Automated rule retirement** — rule-prune stays human-driven
- **New skill for rule-telemetry dashboards** — one-shot read of `rule-metrics.json` is sufficient

## Open Questions

None that block the plan. Implementation detail for the planner:

- Exact PR structure for coupling `incidents.sh` enum extension + `rule-metrics-aggregate.sh` update — should ship in the same commit to avoid a window where new events are emitted but aggregator treats them as malformed.
- Whether to add a one-off script that greps `[skill-enforced: ...]` tags and verifies each has an emission call (drift guard against future skill-enforced rules that forget to emit). Recommended, but low-priority — can be a follow-up hook or a lint script.

## Domain Assessments

**Assessed:** Engineering (implicit — pure internal tooling/telemetry). Marketing, Operations, Product, Legal, Sales, Finance, Support are not relevant: this is a dev-tooling telemetry fix with zero user-facing surface, no external cost impact beyond CI minutes (aggregator cron runs unchanged), no compliance implications, no content generated.

No domain leaders spawned — scope is contained entirely within `.claude/hooks/`, `scripts/`, and `plugins/soleur/skills/*/SKILL.md` for the 10 tagged skills.

## References

- Issue #2866 (this work)
- PR #2865 (AGENTS.md shrink — the parent deferred this)
- PR #2754 (prior hybrid decision)
- `knowledge-base/project/learnings/2026-04-15-rule-metrics-aggregator-pr-pattern-session-gotchas.md`
- `knowledge-base/project/plans/2026-04-15-fix-rule-metrics-aggregator-pr-pattern-and-prune-backfill-plan.md`
- `.claude/hooks/lib/incidents.sh` (emitter)
- `scripts/rule-metrics-aggregate.sh` (aggregator)
- `scripts/rule-prune.sh` (consumer)
- `scripts/lib/rule-metrics-constants.sh` (schema constants)
