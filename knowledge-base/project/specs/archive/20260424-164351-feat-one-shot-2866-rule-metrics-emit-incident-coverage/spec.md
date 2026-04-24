# Feature: Rule-metrics emit_incident coverage (hooks + skills)

## Problem Statement

`scripts/rule-metrics-aggregate.sh` runs on cron but every AGENTS.md rule shows `hit_count=0, first_seen=null` in `knowledge-base/project/rule-metrics.json`. Two concrete silent surfaces cause this:

1. Three of seven hooks never call `emit_incident`: `pre-merge-rebase.sh`, `security_reminder_hook.py`, `docs-cli-verification.sh`. (The remaining four either already emit or are the emitter library itself.)
2. Ten AGENTS.md rules tagged `[skill-enforced: <skill> Phase <N>]` have no telemetry path — skills never emit when they apply a rule.

Consequence: `scripts/rule-prune.sh --dry-run` would file ~101 false-positive retirement issues against actively load-bearing rules.

## Goals

- Every `[hook-enforced]` rule receives at least one `deny` or `bypass` or `warn` event when its hook fires.
- Every `[skill-enforced]` rule receives an `applied` event when its skill enters the tagged phase.
- `scripts/rule-prune.sh --dry-run` output is structurally accurate after one week of post-merge activity (zero orphan rule-ids; unused-rule count reflects reality, not telemetry gaps).
- `scripts/rule-metrics-aggregate.sh` accepts the new `applied` and `warn` event types without regressing the malformed-line tolerance behavior.

## Non-Goals

- Historical backfill of incidents from git log (only 2 matching commits in full history — not worth the complexity).
- Schema v2 of the JSONL format (stay on `SCHEMA_VERSION=1`; extend the `event_type` enum only).
- New AGENTS.md rule-ids for `pre-merge-rebase.sh` deny paths (reuse existing `rf-never-skip-qa-review-before-merging` and `hr-when-a-command-exits-non-zero-or-prints`).
- Bypass detection v2 (`--force` on main, `--no-gpg-sign`, `--amend` after deny) — previously deferred, stays deferred.
- Automated rule retirement — `rule-prune.sh` stays human-driven.
- A drift-guard lint that enforces every `[skill-enforced]` tag has an emission call — out of scope, candidate follow-up.

## Functional Requirements

### FR1: Silent-hook emission coverage

- `pre-merge-rebase.sh` sources `.claude/hooks/lib/incidents.sh` at top and calls `emit_incident` on each of its three deny paths:
  - review-evidence gate → `rf-never-skip-qa-review-before-merging` / `deny`
  - merge-conflict exit → `hr-when-a-command-exits-non-zero-or-prints` / `deny`
  - push-failure exit → `hr-when-a-command-exits-non-zero-or-prints` / `deny`
- `security_reminder_hook.py` carries an inline Python `emit_incident()` that writes the same JSONL schema under `fcntl.flock`, and fires on the workflow-injection deny branch under `hr-in-github-actions-run-blocks-never-use` / `deny`.
- `docs-cli-verification.sh` sources `incidents.sh` and fires `warn` events under `cq-docs-cli-verification` on each flagged CLI token (non-blocking; hook still exits 0).

### FR2: Skill-enforced emission surface

- Each of the 10 `[skill-enforced: <skill> Phase <N>]` rules receives a single emission point placed in the named skill's SKILL.md at the named phase.
- Emission shape: a Bash tool invocation at phase entry sourcing `.claude/hooks/lib/incidents.sh` and calling `emit_incident <rule-id> applied "<first-50-chars-of-rule-text>"`.
- The SKILL.md prose for the relevant phase carries a one-line instruction directing the agent to emit telemetry (e.g., "Emit rule-application telemetry: run `source .claude/hooks/lib/incidents.sh && emit_incident cq-write-failing-tests-before applied \"Write failing tests...\"`").

### FR3: Aggregator handles new event types

- `scripts/rule-metrics-aggregate.sh` treats `applied` and `warn` as valid `event_type` values.
- `hit_count` = count of `deny` + `bypass` + `applied` + `warn` events (any event is a hit).
- `bypass_count` stays narrow (only `bypass` events).
- New per-rule fields in `rule-metrics.json`: `applied_count`, `warn_count`.
- Malformed-line tolerance preserved: unknown `event_type` values still emit `::warning::` to GitHub Actions and skip the bad line without failing the aggregation.

### FR4: rule-prune.sh output validation

- After merge + one cron cycle, `scripts/rule-prune.sh --dry-run` output contains zero orphan rule-ids and the unused-rule list shrinks from ~101 to only rules that genuinely have not fired in the post-merge window.

## Technical Requirements

### TR1: Schema stability (SCHEMA_VERSION stays at 1)

- No bump of `SCHEMA_VERSION` in `scripts/lib/rule-metrics-constants.sh`.
- `event_type` is a free-form string in JSONL; the enum is a convention, not schema-enforced. Extending it is backward-compatible.
- Aggregator update and enum extension ship in the same commit to avoid a window where new events are emitted but the aggregator treats them as malformed.

### TR2: Python emitter parity

- `security_reminder_hook.py` gets a ~30 LOC inline helper using `fcntl.flock` (best-effort on non-POSIX).
- Duplicates `SCHEMA_VERSION=1` and field layout from `incidents.sh` — cross-reference comment in both files.
- Writes to the same `.claude/.rule-incidents.jsonl` at the same repo-root resolution strategy.
- Fire-and-forget: any IO error is swallowed, hook never blocks.

### TR3: Skill emission ergonomics

- Emission is a single one-liner the agent executes via the Bash tool at phase entry.
- Skills do NOT ship a helper function — direct sourcing of `incidents.sh` keeps the code path uniform with hooks.
- Emissions occur before the phase's work begins, so even a phase that errors out still records the "rule was applied" signal.

### TR4: Tests

- Bash tests for `pre-merge-rebase.sh` emissions (one per deny path) using the existing `incidents.test.sh`-style harness or a new `pre-merge-rebase.test.sh`.
- Python test for `security_reminder_hook.py` emission on the workflow-injection branch (unit-level: mock the PreToolUse input, assert JSONL line written).
- Bash test for `docs-cli-verification.sh` `warn` emissions.
- Aggregator unit test: feed a fixture JSONL with `applied` and `warn` events, assert `rule-metrics.json` exposes `applied_count` and `warn_count` correctly.
- Drift check (optional, as a lint script): grep every `[skill-enforced: <skill> Phase <N>]` tag and verify the named skill's SKILL.md at the named phase contains an `emit_incident <rule-id>` reference. Fails build if a tagged rule has no emission call.

### TR5: AGENTS.md budget

- Net change to AGENTS.md from this PR: **0 bytes** (no new rules added; no existing rules modified). Current size 36946 / 37000 budget stays intact.

### TR6: Rollout order

1. Extend `incidents.sh` enum (documentation comment only — no code change needed since event_type is free-form).
2. Update `scripts/rule-metrics-aggregate.sh` to tally `applied`/`warn` and expose new summary fields.
3. Wire emissions into the 3 silent hooks.
4. Wire emissions into the 10 skill phases.
5. Run `scripts/rule-prune.sh --dry-run` locally; verify orphan-id list is empty.

Each step is testable independently; steps 1–2 must ship together (TR1).

## References

- Issue #2866
- Brainstorm: `knowledge-base/project/brainstorms/2026-04-24-rule-metrics-emit-incident-coverage-brainstorm.md`
- Prior plan: `knowledge-base/project/plans/2026-04-15-fix-rule-metrics-aggregator-pr-pattern-and-prune-backfill-plan.md`
- Prior learning: `knowledge-base/project/learnings/2026-04-15-rule-metrics-aggregator-pr-pattern-session-gotchas.md`
