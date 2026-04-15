---
title: Rule Utility Scoring for AGENTS.md Rules and Learnings
date: 2026-04-14
issue: 2210
pr: 2213
branch: rule-utility-scoring
worktree: .worktrees/rule-utility-scoring/
brainstorm: knowledge-base/project/brainstorms/2026-04-14-rule-utility-scoring-brainstorm.md
spec: knowledge-base/project/specs/feat-rule-utility-scoring/spec.md
status: complete
detail: A LOT
---

# Plan: Rule Utility Scoring

## Summary

Instrument every `AGENTS.md` rule and every hook deny with telemetry so the repo can tell which rules earn their keep. Four moving pieces:

1. **Rule IDs** — stable slugs (`[id: hr-<slug>]`, `[id: wg-<slug>]`) on every rule, lint-enforced.
2. **Hook telemetry** — `.claude/hooks/*.sh` append jsonl events to a single `flock`-guarded file on deny and on minimal bypass-flag usage (`--no-verify`, `LEFTHOOK=0`).
3. **Aggregator** — weekly GitHub Actions cron rolls jsonl + rule metadata into committed `knowledge-base/project/rule-metrics.json`.
4. **Rule-prune surface** — `/soleur:sync rule-prune` files GitHub issues for rules with `hit_count = 0` after N weeks.

Counters live in `rule-metrics.json` as the single source of truth (see [Architectural Decisions](#architectural-decisions--open-tensions) — this deviates from the spec's frontmatter-per-learning choice; user approves during plan review).

Closes #2210.

## Problem Statement

`AGENTS.md` has rules across 6 sections (currently ~71 bullets; drifts as rules are added/consolidated). `knowledge-base/project/learnings/` has 507 top-level files plus nested subdirectories. Phase 1.5 Deviation Analyst warns at a 100-rule budget, but the 2026-04-07 "budget false alarm" learning proved raw counts without utility data desensitize users: rules that never fire look identical to rules that prevent production outages weekly. We need data-driven pruning signals — not auto-retirement.

## Goals

- **G1** — Every rule in `AGENTS.md` carries a stable, human-readable slug ID.
- **G2** — Every hook deny and v1 bypass flags (`--no-verify`, `LEFTHOOK=0`) produce structured events in a single `flock`-guarded `.claude/.rule-incidents.jsonl`.
- **G3** — A weekly aggregator writes counters (hit, bypass, derived prevented) into committed `knowledge-base/project/rule-metrics.json`.
- **G4** — `/soleur:sync rule-prune` surfaces pruning candidates (rules with `hit_count = 0` after N weeks) and files GitHub issues.
- **G5** — No existing workflow (compound, `/ship`, hooks, lefthook) regresses.

## Non-Goals

- **NG1** — No runtime skill rewriting or auto-retirement.
- **NG2** — No "was this a real prevention?" prompts — derived from `bypass_count` instead.
- **NG3** — No dashboard/visualization in v1 — plain markdown report only.
- **NG4** — No multi-repo utility pool.
- **NG5** — No rewrite of `scripts/rule-audit.sh` (existing bi-weekly audit stays; this feature adds a separate metrics lens).

## Background & Research Findings

### Current state (from repo research)

- **AGENTS.md sections** (worktree `AGENTS.md`): Hard Rules (24), Workflow Gates (25), Code Quality (12), Review & Feedback (5), Passive Domain Routing (2), Communication (3) → **71 total bullets**. Existing `[hook-enforced: ...]` / `[skill-enforced: ...]` tags placed inline at end-of-first-clause (9 existing instances).
- **Hook scripts** at `.claude/hooks/`: `guardrails.sh` (6 internal guards), `pencil-open-guard.sh` (1 deny), `worktree-write-guard.sh` (1 deny), `pre-merge-rebase.sh`. Plus Stop/SessionStart hooks in `plugins/soleur/hooks/hooks.json`. All denies use `jq -n '{hookSpecificOutput: {permissionDecision: "deny", permissionDecisionReason: "BLOCKED: ..."}}'` then `exit 0`.
- **Compound Phase 1.5** at `plugins/soleur/skills/compound/SKILL.md:138-198` — reads AGENTS.md rules + session evidence, detects deviations, proposes enforcement. Step 8 already does `grep -c '^- ' AGENTS.md` budget check.
- **Learnings schema** at `plugins/soleur/skills/compound-capture/schema.yaml:115-133` (optional_fields block) + mirror at `references/yaml-schema.md`. Schema drift is real — many learnings use ad-hoc frontmatter.
- **`/soleur:sync` is a command**, not a skill — `plugins/soleur/commands/sync.md`. `argument-hint` at line 3; valid-areas list at lines 18-21; Phase 1.2 sub-analyses; Phase 4 gate at line 326.
- **Existing templates to mirror**: `scripts/backfill-frontmatter.py` (PyYAML + body-hash idempotency), `scripts/rule-audit.sh` + `.github/workflows/rule-audit.yml` (bash aggregator + cron pattern), `.github/actions/notify-ops-email` (failure notification).
- **Lefthook** at `lefthook.yml` — 10 pre-commit commands keyed by glob. Closest precedent for AGENTS.md-specific check: `markdown-lint` (priority 4) and `kb-structure-guard` (priority 9).
- **`.gitignore`** — `.claude/settings.local.json`, `.claude/soleur-welcomed.local`, `.claude/ralph-loop.*.local.md` are ignored. Most of `.claude/hooks/` is committed. New `.claude/.rule-incidents.*.jsonl` needs an explicit entry.
- **Adjacent prior art**: `scripts/rule-audit.sh` (bi-weekly duplicate detection, issue filing via notify-ops-email on failure) — same category of work. New aggregator borrows structure.

### Spec/reality deltas (MUST resolve in plan review)

- **Rule count** — spec says "71 hard rules"; actual `Hard Rules + Workflow Gates` = 49. Spec's 71 likely counts all `^-` bullets across AGENTS.md. **CTO recommends tagging all 6 sections**; plan assumes this unless user rejects.
- **Learnings count** — spec says 651; actual top-level `ls` gives 507 files. Including nested subdirs (e.g., `integration-issues/`, `runtime-errors/archive/`, `workflow-patterns/`) likely pushes closer to 651. Migration must recurse.

### Relevant institutional learnings

| Learning | Applies to | Takeaway |
|---|---|---|
| `2026-04-07-rule-budget-false-alarm-fix.md` | G3 | Only count always-loaded rules. Don't conflate AGENTS.md with constitution.md. |
| `2026-02-25-lean-agents-md-gotchas-only.md` | G4 | Prefer consolidation + `[skill-enforced: ...]` over deletion. Prune criterion should honor "gotcha" status. |
| `2026-03-05-plan-review-scope-reduction-and-hook-enforced-annotations.md` | G1 | `[id: ...]` placement: inline at end-of-rule, grep-able. Don't invent a new location. |
| `2026-03-05-bulk-yaml-frontmatter-migration-patterns.md` | G2 migration | PyYAML not bash/awk. Pre/post MD5 body-hash check. Idempotency on re-run. Schema-drift-tolerant reads. |
| `2026-03-18-stop-hook-toctou-race-fix.md` | G2 hook writes | `2>/dev/null` on reads, `-s` check before `mv`, empty-output guards under `set -euo pipefail`. |
| `2026-03-18-stop-hook-jq-invalid-json-guard.md` | G2 jsonl | `jq // ""` handles missing keys, not invalid JSON. Parse errors exit 5 and trap sessions — always `2>/dev/null \|\| true` on jq against external input. |
| `2026-03-30-compound-headless-issue-filing-over-auto-accept.md` | G4 | Headless mode should file issues, not skip or auto-accept. Record issue number in `synced_to` frontmatter. |
| `2026-03-16-scheduled-skill-wrapping-pattern.md` | G3 cron | Three-layer: workflow authorizes commit-to-main, skill detects `--headless`, one-skill-per-workflow. |
| `2026-03-21-github-actions-heredoc-yaml-and-credential-masking.md` | G3 cron | No HEREDOCs inside `run: \|`. Use `printf > file` + `--body-file`. |
| `2026-03-05-verify-pretooluse-hooks-ci-deterministic-guard-testing.md` | G2 hooks | Add `workflow_dispatch` test to `test-pretooluse-hooks.yml` for every new hook branch. |

## Architectural Decisions & Open Tensions

CTO review surfaced 5 deviations from the spec's decisions. Each is presented as a tension, not an override — user confirms during plan review.

### ADR-1: Counter storage — rule-metrics.json ONLY (CTO override)

| Aspect | Spec (brainstorm decision 2) | CTO recommendation |
|---|---|---|
| Location | `hit_count` / `bypass_count` in every learning's frontmatter (507+ files) | `rule-metrics.json` as sole source of truth |
| Diff surface | 507 files mutate weekly | Single-file diff per aggregation |
| Bulk mutation risk | High (body-hash check mandatory) | None |
| Grep UX | `grep hit_count knowledge-base/project/learnings/` | `jq '.rules[] \| select(.hit_count==0)' rule-metrics.json` |
| Git-visible drift | Yes (per-file) | Yes (aggregated) |

**Plan assumes CTO's recommendation** — learnings get a `rule_id` reference only (immutable); counters live exclusively in `rule-metrics.json`. This eliminates FR7 (PyYAML counter backfill) as a correctness-critical migration. The migration instead adds `rule_id: null` (or ties learning → rule via the existing `tags` field) only for learnings authored from a specific deny. Most learnings have no direct rule link.

**Rejection path:** If user insists on brainstorm decision 2, revert to spec's FR7 — bulk migration adds `hit_count: 0` + `bypass_count: 0` to all learnings, body-hash verified.

**Spec → Plan Acceptance Criteria delta:**

| Spec AC | Plan AC | Reason |
|---|---|---|
| "`schema.yaml` + `references/yaml-schema.md` extended with `hit_count` / `bypass_count`" | Schema adds optional `rule_id` only; no counter fields | ADR-1: counters in rule-metrics.json |
| "Compound Phase 1.5 increments frontmatter counts on matched learnings end-to-end" | Compound Phase 1.5 Step 3.5 surfaces jsonl events as evidence; no frontmatter mutation | ADR-1 |
| "PyYAML migration script runs cleanly on 651 learnings, body-hash check passes" | No bulk learnings migration in v1 — `rule_id` is optional, added ad-hoc going forward | ADR-1 makes FR7 unnecessary |
| Implicit: severity-aware pruning (from brainstorm Decision 12) | Not in v1 — human review sufficient | ADR-5: deferred |

### ADR-2: Hook telemetry — side-effect write, not payload extension

Existing contract: `echo '{hookSpecificOutput: {permissionDecision: "deny", permissionDecisionReason: "..."}}'` then `exit 0`. Options:

| Option | Risk | Verdict |
|---|---|---|
| Add `ruleId` as sibling of `hookSpecificOutput` | Claude Code may reject/ignore unknown top-level fields; untested | Skip |
| Add `ruleId` inside `hookSpecificOutput` | CC schema validation may fail silently; behavior undefined | Skip |
| **Write jsonl as side-effect BEFORE the `echo`** — CC contract untouched | None (telemetry decoupled) | **Chosen** |

Every hook calls `emit_incident "<rule_id>" "<event_type>" "<rule_text_prefix>"` helper (new: `.claude/hooks/lib/incidents.sh`) before the deny `echo`. The helper handles the jsonl write, timestamp, session id extraction. No change to the CC JSON response.

### ADR-3: jsonl concurrency — single `flock`-guarded file

Brainstorm's original CTO-advised per-session + rollup was over-engineered for scale (~10 sessions/day). A single append-only `.claude/.rule-incidents.jsonl` guarded by `flock -x` on the file itself adds microseconds per hook invocation and eliminates: per-session filename generation, weekly concat, gzip rotation, 7-day truncation, `CLAUDE_SESSION_ID || $$` fallback.

- Filename: `.claude/.rule-incidents.jsonl` (single file, gitignored).
- Writer: `flock -x "$file" -c "jq -nc ... >> $file"` inside `emit_incident`.
- Rotation: after successful weekly aggregation, aggregator moves current file to `.claude/.rule-incidents-YYYY-MM.jsonl.gz` and truncates. No session-based logic.
- Orphan cleanup: not applicable (single file).

### ADR-4: `[id: ...]` tagging scope — all 6 sections

Every enforceable instruction is a candidate for utility scoring. Code Quality rules (e.g., `LEFTHOOK=0` workaround) deserve the same measurement lens. **Assumption: all rules across 6 sections get IDs** (`hr-*` for Hard Rules, `wg-*` for Workflow Gates, `cq-*` for Code Quality, `rf-*` for Review & Feedback, `pdr-*` for Passive Domain Routing, `cm-*` for Communication). Rule count drifts as AGENTS.md evolves; backfill script is idempotent and re-runnable on rebase to catch any rules added on main.

### ADR-5: Severity metadata — **deferred to v2** (YAGNI)

Originally proposed a `rule-severity.yaml` sidecar so `hit_count = 0` on critical rules (e.g., `never git stash in worktrees`) would not trigger prune candidacy. Deferred: the prune surface is human review via GitHub issues (NG1 — never auto-retires), and a human reading a list of zero-hit rules is perfectly capable of not retiring `git stash in worktrees`. Ship without severity; revisit if the first prune cycle actually misclassifies a critical rule.

Tracking issue filed under deferrals: D-severity-sidecar → milestone "Post-MVP / Later".

### Open tensions for plan review

1. **Are rule IDs immutable under rewording?** Plan assumes yes — rewording preserves ID. Lint check rejects ID *removal*, allows text changes. Needs explicit rule in `AGENTS.md` itself after rollout.
2. **Learnings migration — needed at all under ADR-1?** Under ADR-1 (counters in rule-metrics.json), the bulk PyYAML migration becomes optional. Plan keeps it OUT of v1 scope; learnings get a `rule_id` field only if/when they're authored from a specific deny, going forward.
3. **Bypass false positives** — `--force` on `git push` to feature branches is legitimate. Bypass detection scopes to `main`/`master` only OR requires a prior deny in the same session window.

## Architecture Overview

```mermaid
flowchart LR
    A[AGENTS.md rules<br/>with id: hr-slug] -->|grep on startup| C[compound Phase 1.5]
    B[.claude/hooks/*.sh<br/>PreToolUse deny] -->|emit_incident| D[.claude/.rule-incidents.SESSION.jsonl]
    B -->|bypass flag detected| D
    D -->|weekly| E[.github/workflows/<br/>rule-metrics-aggregate.yml]
    E -->|reads rules + jsonl tail| F[knowledge-base/project/<br/>rule-metrics.json]
    F -->|committed| G[/soleur:sync rule-prune]
    G -->|files issues for<br/>hit_count=0 after N weeks| H[GitHub Issues<br/>milestone: Post-MVP / Later]
    C -.->|Step 3.5: reads jsonl<br/>informs deviation analysis| D
    I[lefthook rule-id-lint] -->|blocks commits adding<br/>untagged rules| A
    J[scripts/backfill-rule-ids.py<br/>one-time] -->|seeds IDs| A
```

## Files to Create / Modify

| # | Path | Action | Source |
|---|------|--------|--------|
| 1 | `AGENTS.md` | Add `[id: hr-<slug>]` / `[id: wg-<slug>]` / `[id: cq-<slug>]` / `[id: rf-<slug>]` / `[id: pdr-<slug>]` / `[id: cm-<slug>]` tags to all 71 bullets; add a rule about ID immutability | repo-research |
| 2 | `.claude/hooks/lib/incidents.sh` | **New** helper — `emit_incident <rule_id> <event_type> <rule_text_prefix>`; also `detect_bypass <command>` helper | CTO ADR-2 |
| 3 | `.claude/hooks/guardrails.sh` | Call `emit_incident` before each of 6 `jq -n` deny payloads; call `detect_bypass` in the Bash preflight | repo-research |
| 4 | `.claude/hooks/pencil-open-guard.sh` | Same (1 deny site, line ~29) | repo-research |
| 5 | `.claude/hooks/worktree-write-guard.sh` | Same (1 deny site, lines 40-46) | repo-research |
| 6 | `.claude/hooks/README.md` | **New** — document hook contract, incident emission, bypass flag list, rule-id convention | brainstorm |
| 7 | `plugins/soleur/skills/compound/SKILL.md` | Extend Phase 1.5 with **Step 3.5: Ingest Recent Incidents** (reads tail of jsonl, feeds deviation detector); NO counter-increment side-effect (ADR-1) | repo-research |
| 8 | `plugins/soleur/skills/compound-capture/schema.yaml` | Add optional `rule_id: string` field to learnings (maps to `hr-*` / `wg-*` / etc.); no counter fields | ADR-1 |
| 9 | `plugins/soleur/skills/compound-capture/references/yaml-schema.md` | Mirror schema.yaml change | repo-research |
| 10 | `plugins/soleur/commands/sync.md` | Add `rule-prune` to `argument-hint`, valid-areas list (line ~20), Phase 1.2 sub-analysis (`#### Rule Prune Analysis`); exclude from `all` area | repo-research |
| 11 | `scripts/backfill-rule-ids.py` | **New** — PyYAML script reads AGENTS.md, proposes slug for each untagged rule, writes `[id: <slug>]` inline preserving body; body-hash check; dry-run mode; idempotent | pattern from `backfill-frontmatter.py` |
| 12 | `scripts/rule-metrics-aggregate.sh` | **New** — bash aggregator: parse AGENTS.md IDs, read `.rule-incidents.jsonl`, write `rule-metrics.json` sorted by utility; validates its own JSON output via `jq`; exits non-zero on malformed | pattern from `rule-audit.sh` |
| 13 | `.github/workflows/rule-metrics-aggregate.yml` | **New** — weekly cron `0 0 * * 0`, checkout + run aggregator + commit if changed + notify-ops-email on failure | pattern from `.github/workflows/rule-audit.yml` |
| 14 | `lefthook.yml` | Add inline `rule-id-lint` (priority 4, glob `AGENTS.md`) — rejects untagged rules. Inline grep per Code Simplicity review; no separate script | repo-research |
| 15 | `.gitignore` | Add `.claude/.rule-incidents.jsonl`, `.claude/.rule-incidents-*.jsonl.gz`, `.claude/.last-deny*` | repo-research |
| 16 | `knowledge-base/project/rule-metrics.json` | **New** — first committed snapshot after first aggregator run; CI validates shape on every PR | spec |

## Implementation Phases

Each phase is independently revertible. TDD gates apply where Test Scenarios exist.

### Phase 0 — Prerequisites (Phase 1.5 budget protection)

- [x] Verify PyYAML availability in GitHub Actions (`ubuntu-latest` has it pre-installed; local dev uses `pip install pyyaml` in the migration script's venv shim).
- [x] Confirm `flock` is available on target shells (Linux default; macOS dev machines need `brew install flock` — documented in README).
- [x] Confirm `scripts/rule-audit.sh` and this aggregator can coexist (both read AGENTS.md; no write collision).

### Phase 1 — Rule ID Infrastructure (G1, no telemetry yet)

1. **Write `scripts/backfill-rule-ids.py`** (TDD: failing test first — `tests/scripts/test_backfill_rule_ids.py`)
   - Read `AGENTS.md`, tokenize by section header (`## Hard Rules`, `## Workflow Gates`, ...).
   - For each `^-` bullet: extract first 50 chars of rule text, slugify (kebab-case, alphanumeric + hyphens, 3-40 chars), assign prefix by section.
   - Detect collisions; on collision append numeric suffix (`hr-slug-2`).
   - Insert `[id: <slug>]` at end of first clause (matching existing `[hook-enforced: ...]` placement — before any trailing `.` or `. **Why:**`).
   - MD5 body-hash pre/post excluding frontmatter. Abort on mismatch. Idempotent re-run (skip bullets with existing `[id: ...]`).
   - Dry-run mode (`--dry-run`) prints proposed tags without writing.
2. **Run** `python scripts/backfill-rule-ids.py --dry-run` → inspect → commit output to PR description → run without `--dry-run` → commit.
3. **Add lint to `lefthook.yml`** — new `rule-id-lint` command:

   ```yaml
   rule-id-lint:
     glob: "AGENTS.md"
     priority: 4
     run: |
       python scripts/lint-rule-ids.py AGENTS.md || exit 1
   ```

4. **Write `scripts/lint-rule-ids.py`** — for each `^-` under `## Hard Rules` / `## Workflow Gates` / ..., require `[id: <prefix>-<slug>]`; flag duplicates; flag removed IDs via diff-aware check.
5. **Add rule to `AGENTS.md`**: "Rule IDs (`[id: hr-<slug>]`) are immutable once assigned. Rewording preserves the ID; removing the ID or reassigning it requires an issue and a deprecation note. [hook-enforced: lint-rule-ids.py]"

### Phase 2 — Hook Telemetry (G2)

1. **Write `.claude/hooks/lib/incidents.sh`** (TDD: `tests/hooks/test_incidents.sh`)

   ```bash
   # emit_incident <rule_id> <event_type> <rule_text_prefix> [command_snippet]
   emit_incident() {
     local rule_id="$1" event="$2" prefix="$3" cmd="${4:-}"
     local ts repo_root file
     ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
     # BASH_SOURCE resolves the sourced script path, unlike $0 which is the caller (Kieran review)
     repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
     file="$repo_root/.claude/.rule-incidents.jsonl"
     flock -x "$file" -c "jq -nc \
       --arg ts '$ts' --arg r '$rule_id' \
       --arg e '$event' --arg p '$prefix' --arg c '$cmd' \
       '{timestamp:\$ts,rule_id:\$r,event_type:\$e,rule_text_prefix:\$p,command_snippet:\$c}' \
       >> '$file'" 2>/dev/null || true
   }

   # detect_bypass <tool> <command>  →  echoes rule_id if --no-verify or LEFTHOOK=0 present
   detect_bypass() {
     local cmd="$2"
     case "$cmd" in
       *--no-verify*)  echo "cq-never-skip-hooks" ;;
       *LEFTHOOK=0*)   echo "cq-lefthook-worktree-hang" ;;
     esac
   }
   ```

   - Source resolution via `${BASH_SOURCE[0]}` (not `$(dirname "$0")`) per Kieran review — `$0` is the caller of the sourced script, not the script itself.
   - Per learning 2026-03-18 TOCTOU: `2>/dev/null || true` guards all jq invocations; `set -euo pipefail` compatible.
   - **Bypass v1 scope is deliberately minimal**: `--no-verify` + `LEFTHOOK=0` only. `--force`, `--no-gpg-sign`, `--amend` deferred to v2 once data justifies (YAGNI per Code Simplicity review). Avoids session-window amend tracking complexity.
2. **Wire into `guardrails.sh`** — each of 6 deny blocks gets `emit_incident "<rule_id>" "deny" "<first 50 chars>"` before `echo`. Add top-of-script `source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"`.
3. **Wire into `pencil-open-guard.sh`** — same pattern, 1 deny site.
4. **Wire into `worktree-write-guard.sh`** — same pattern, 1 deny site.
5. **Add bypass detection pass** — at top of `guardrails.sh` Bash preflight, call `ruleid=$(detect_bypass "$TOOL_NAME" "$COMMAND")`; on non-empty, `emit_incident "$ruleid" "bypass" "..." "$COMMAND"` (fire-and-forget — does NOT block).
6. **Write `.claude/hooks/README.md`** — document: deny contract, `emit_incident` API, v1 bypass flag list, rule-id convention, jsonl rotation policy, macOS `flock` install note.
7. **Add `.gitignore` entries**:

   ```text
   .claude/.rule-incidents.jsonl
   .claude/.rule-incidents-*.jsonl.gz
   ```

8. **Extend `.github/workflows/test-pretooluse-hooks.yml`** — add assertion that each deny writes a line to `.claude/.rule-incidents.jsonl` with correct `rule_id`. Retained per AGENTS.md learning 2026-03-05-verify-pretooluse-hooks; Code Simplicity flagged this as YAGNI but new deny branches warrant CI coverage.

### Phase 3 — Schema Extension (G3 prep)

1. **Update `plugins/soleur/skills/compound-capture/schema.yaml`** — add optional `rule_id: { type: string, pattern: "^(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]{3,40}$" }` to `optional_fields`. No counters (ADR-1). No severity (ADR-5 deferred).
2. **Mirror in `references/yaml-schema.md`**.
3. Severity sidecar file is **not** created in v1 (ADR-5 deferred). Prune surface is pure human review.

### Phase 4 — Compound Phase 1.5 Extension (G3)

1. **Edit `plugins/soleur/skills/compound/SKILL.md:138-198`** — insert new **Step 3.5: Ingest Recent Incidents**:
   - Read `.claude/.rule-incidents.jsonl` (single file, all sessions — aggregator handles cross-time rotation).
   - Filter by timestamp newer than the session start (compound runs at session end; session_start env or last N minutes heuristic).
   - Surface recent denies + bypasses to the Deviation Analyst as evidence.
   - Do NOT mutate learning frontmatter (ADR-1).
2. Update existing Step 8 (rule-budget) to call `scripts/rule-metrics-aggregate.sh --dry-run | jq '.summary'` and warn if `rules_unused_over_8w > 0`.
3. No subagent added — Phase 1.5 stays sequential.

### Phase 5 — Aggregator Workflow (G3)

1. **Write `scripts/rule-metrics-aggregate.sh`** (TDD: `tests/scripts/test-rule-metrics-aggregate.sh`)
   - Parse `AGENTS.md`: extract every `^-` with `[id: ...]` → list of rules with ID + first-50-char prefix + section.
   - Read single `.claude/.rule-incidents.jsonl` (if absent, empty set).
   - For each rule: count matching events by `rule_id` (primary) or `rule_text_prefix` (fallback). Compute `hit_count`, `bypass_count`, `prevented_errors = max(0, hit_count - bypass_count)`, `last_hit`, `first_seen`.
   - Output `knowledge-base/project/rule-metrics.json`:

     ```json
     {
       "generated_at": "2026-04-14T00:00:00Z",
       "rules": [
         {"id": "hr-stash-in-worktrees", "section": "Hard Rules",
          "hit_count": 3, "bypass_count": 0, "prevented_errors": 3,
          "last_hit": "2026-04-10T14:22:00Z", "first_seen": "2026-02-01T..."}
       ],
       "summary": {"total_rules_tagged": 71, "rules_unused_over_8w": 12, "rules_bypassed_over_baseline": 0}
     }
     ```

   - No `severity` field (ADR-5 deferred).
   - Sort rules by `hit_count` ASC (least-used first, i.e., prune candidates at top).
   - Only write if output materially differs from existing file (diff-noise mitigation — R4 from spec).
   - **After write, validate via `jq empty < rule-metrics.json`**; exit non-zero on malformed output (Kieran review: aggregator schema CI gate).
   - **After successful aggregation**, rotate: `mv .claude/.rule-incidents.jsonl .claude/.rule-incidents-YYYY-MM.jsonl && gzip .claude/.rule-incidents-YYYY-MM.jsonl && touch .claude/.rule-incidents.jsonl`. Uses month-based naming so a rollup mid-month appends to existing archive.
2. **Write `.github/workflows/rule-metrics-aggregate.yml`** (mirrors `rule-audit.yml`):

   ```yaml
   name: "Scheduled: Rule Metrics Aggregate"
   on:
     schedule:
       - cron: '0 0 * * 0'   # Sunday 00:00 UTC
     workflow_dispatch:
   concurrency:
     group: scheduled-rule-metrics-aggregate
     cancel-in-progress: false
   permissions:
     contents: write
   jobs:
     aggregate:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         - run: bash scripts/rule-metrics-aggregate.sh
         - name: Commit if changed
           run: |
             git config user.name "github-actions[bot]"
             git config user.email "github-actions[bot]@users.noreply.github.com"
             git add knowledge-base/project/rule-metrics.json
             if ! git diff --cached --quiet; then
               git commit -m "chore(rule-metrics): weekly aggregate"
               git push
             fi
         - name: Notify on failure
           if: failure()
           uses: ./.github/actions/notify-ops-email
           with:
             subject: "Rule Metrics Aggregate Failed"
             body: "Run ${{ github.run_id }} failed. See logs."
             resend-api-key: ${{ secrets.RESEND_API_KEY }}
   ```

   **CI heredoc rule:** no HEREDOCs inside `run: |`. Use `printf > file` if body exceeds one line.
3. **Rotation**: aggregator also invokes rotation — gzip any session jsonl older than 7 days to `.claude/.rule-incidents-YYYY-MM.jsonl.gz`, truncate source. (Gzipped archives stay local per `.gitignore`.)

### Phase 6 — `/soleur:sync rule-prune` Subcommand (G4)

1. **Edit `plugins/soleur/commands/sync.md`**:
   - Extend `argument-hint: conventions|architecture|testing|debt|project|rule-prune|all`.
   - Add `rule-prune` to valid-areas list (line ~20).
   - Exclude `rule-prune` from the `all` dispatch (gate at Phase 4, line 326).
   - Add Phase 1.2 sub-analysis (`#### Rule Prune Analysis`):
     - Read `knowledge-base/project/rule-metrics.json`.
     - Filter: `hit_count = 0` AND `generated_at - first_seen > N weeks` (N default 8, configurable via `--weeks=<n>` arg).
     - Exclude rules with `severity: critical`.
     - For each candidate: check if a `rule-prune: consider retiring <id>` issue already exists (idempotent via `gh issue list --search "rule-prune: consider retiring <id> in:title"`).
     - If not, file issue milestoned to "Post-MVP / Later":

       ```
       Title: rule-prune: consider retiring hr-<slug>
       Body:
       - Rule: "<first 50 chars of rule text>..."
       - hit_count: 0 over <N> weeks
       - First seen: <date>
       - Severity: <high|medium>
       - Reassessment criteria: re-run after 4 more weeks; if still hit_count=0 and no recorded bypass, propose removal in AGENTS.md.
       - This issue does NOT authorize removal — a human must edit AGENTS.md.
       ```

     - Record issue numbers in a run report (markdown output).
2. **Write test**: `tests/commands/test-sync-rule-prune.sh` — fixture `rule-metrics.json` with 3 candidates, assert 3 issues filed (dry-run), re-run asserts 0 new issues (idempotent).

### Phase 7 — End-to-End Validation

1. **Manual e2e** (documented, not automated):
   - Start a session, trigger `guardrails.sh`'s `git stash` block → verify `.claude/.rule-incidents.<session>.jsonl` has a line with `rule_id: hr-stash-in-worktrees`, `event_type: deny`.
   - Same session, run `git push --no-verify` → verify bypass event emitted.
   - `gh workflow run rule-metrics-aggregate.yml` → verify `rule-metrics.json` written, commit pushed.
   - `/soleur:sync rule-prune --weeks=0` (force-match-all) → verify issue filed, re-run verifies no duplicate.
2. **Post-merge workflow verification** (AGENTS.md rule `wg-workflow-post-merge-verify`): after PR merges, manually trigger the aggregator, poll `gh run view --json status,conclusion`.

## Test Scenarios

| # | Scenario | Expected | Owner |
|---|---|---|---|
| T1 | `scripts/backfill-rule-ids.py --dry-run` on AGENTS.md with 0 IDs | Proposes 71 IDs, no writes, body-hash unchanged | Phase 1 |
| T2 | `scripts/backfill-rule-ids.py` re-run on already-tagged AGENTS.md | No-op (idempotent); body unchanged | Phase 1 |
| T3 | `scripts/lint-rule-ids.py` on AGENTS.md with a rule missing `[id:]` | Exit 1, error naming the offending line | Phase 1 |
| T4 | `scripts/lint-rule-ids.py` on AGENTS.md with duplicate IDs | Exit 1, names both occurrences | Phase 1 |
| T5 | `emit_incident "hr-test" "deny" "prefix"` in isolation | Writes 1 valid JSON line to jsonl; no stderr | Phase 2 |
| T6 | Two concurrent `emit_incident` calls (simulated via `&` bg) | Both lines present, valid JSON, no interleave (flock works) | Phase 2 |
| T7 | `emit_incident` sourced from different hook directories resolves same jsonl path | Both hooks write to identical `.claude/.rule-incidents.jsonl` (BASH_SOURCE works) | Phase 2 |
| T8 | `guardrails.sh` blocks `git stash` → jsonl receives deny event | `rule_id: hr-stash-in-worktrees` | Phase 2 |
| T9 | `git commit --no-verify` after prior deny → bypass event emitted | `event_type: bypass`, `rule_id` matches the bypassed guard | Phase 2 |
| T10 | `git push --force` to feature branch → no bypass event | `--force` not in v1 bypass list; no false positive | Phase 2 |
| T10b | `git commit --no-verify` on any branch → bypass event emitted | `cq-never-skip-hooks` recorded | Phase 2 |
| T10c | `LEFTHOOK=0 git commit` → bypass event emitted | `cq-lefthook-worktree-hang` recorded | Phase 2 |
| T10d | Malformed `rule-metrics.json` (simulated via fixture) → aggregator exits non-zero | `jq empty` validation trips | Phase 5 |
| T11 | Aggregator with empty jsonl set → writes valid rule-metrics.json with `hit_count: 0` for all rules | No crash; `summary.rules_unused_over_8w == total` | Phase 5 |
| T12 | Aggregator with synthetic jsonl (3 denies for hr-stash) → rule-metrics.json shows hit_count=3 | Correct count, sort order | Phase 5 |
| T13 | Aggregator re-run with no new events → no-op (no commit) | diff-noise mitigation works | Phase 5 |
| T14 | `/soleur:sync rule-prune --weeks=0` with 2 synthetic zero-hit rules → 2 issues filed | Issue titles and bodies correct | Phase 6 |
| T15 | Same invocation re-run → 0 new issues | Idempotent via issue search | Phase 6 |
| T16 | `/soleur:sync rule-prune` respects existing GH issue for same rule → no duplicate | Idempotent issue filing | Phase 6 |

## Acceptance Criteria

- [x] All rules in AGENTS.md (across 6 sections) carry `[id: <prefix>-<slug>]` tags; backfill re-runnable on rebase.
- [x] Lefthook `rule-id-lint` rejects commits adding untagged rules or duplicate IDs.
- [x] `AGENTS.md` gains a new rule mandating ID immutability, referencing the inline lint.
- [x] `.claude/hooks/lib/incidents.sh` exists with `emit_incident` + minimal `detect_bypass` (`--no-verify`, `LEFTHOOK=0`); all hook scripts (`guardrails.sh`, `pencil-open-guard.sh`, `worktree-write-guard.sh`) source it via `${BASH_SOURCE[0]}` resolution.
- [x] `.claude/hooks/README.md` documents the contract, flock behavior, and macOS `flock` install step.
- [x] `.gitignore` excludes `.claude/.rule-incidents.jsonl` and `.claude/.rule-incidents-*.jsonl.gz`.
- [x] `plugins/soleur/skills/compound-capture/schema.yaml` + `references/yaml-schema.md` include optional `rule_id` field (no counters, no severity in v1).
- [x] No `rule-severity.yaml` shipped in v1 — severity sidecar deferred (ADR-5).
- [x] Compound Phase 1.5 Step 3.5 reads single `.claude/.rule-incidents.jsonl`; no counter side-effects.
- [x] `scripts/rule-metrics-aggregate.sh` produces valid `rule-metrics.json` from empty input and from synthetic input; exits non-zero on malformed output (`jq empty` gate).
- [x] `.github/workflows/rule-metrics-aggregate.yml` runs on schedule + `workflow_dispatch`; commits when materially changed; notifies ops-email on failure.
- [x] A CI check on every PR validates `rule-metrics.json` shape via `jq` (prevents malformed file from merging).
- [x] `/soleur:sync rule-prune` files GitHub issues for candidates; idempotent; never auto-edits AGENTS.md.
- [x] First post-merge scheduled run completes successfully (AGENTS.md workflow-post-merge-verify rule).
- [x] T1–T16 + T10b/c/d all pass.

## Risks & Mitigations

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Slug collisions across sections produce ambiguous IDs | Low | Medium | Prefix by section (`hr-`, `wg-`, `cq-`, `rf-`, `pdr-`, `cm-`) — collisions require same-section + same-slug |
| R2 | Hook jsonl concurrency races corrupt lines | Low | Medium | ADR-3 single `flock`-guarded file; `jq -c` output is single-line |
| R3 | Bypass false positives | Very low | Low | v1 scope is `--no-verify` + `LEFTHOOK=0` only — both unambiguous skip signals |
| R4 | PyYAML migration mangles AGENTS.md body during ID insertion | Low | High | Body-hash MD5 pre/post (mandatory); dry-run output inspected in PR description; rollback via `git revert` |
| R5 | Aggregator commit loop (every Sunday creates noise even when counts unchanged) | Medium | Low | Only write `rule-metrics.json` when output differs from committed version by more than timestamp |
| R6 | CC hook contract change breaks downstream (CC reads unknown JSON fields) | Very low | High | ADR-2 — no payload changes; telemetry is side-effect only |
| R7 | macOS dev machines lack `flock` | Medium | Low | Document `brew install flock` in `.claude/hooks/README.md`; `\|\| true` on flock failure means hook never blocks |
| R8 | Weekly cron's git push conflicts with concurrent merges to main | Low | Medium | `concurrency: group: scheduled-rule-metrics-aggregate, cancel-in-progress: false` serializes |
| R9 | Aggregator writes malformed `rule-metrics.json` | Low | High | Post-write `jq empty` gate; CI check on every PR validates shape |
| R10 | Lint blocks legitimate AGENTS.md edits during rollout (IDs not yet assigned on a branch) | Low | High during Phase 1 | Lint runs in check-only mode during Phase 1; enforcement flips on at end of Phase 1 commit |
| R11 | Pruning pressure retires load-bearing-but-rare rules | Medium | High | Issue body explicitly says "does NOT authorize removal"; human review only; 4-week reassessment gate |
| R12 | `/soleur:sync` dispatch change breaks existing `conventions`/`architecture`/etc. areas | Low | High | Regression test: run `/soleur:sync conventions` in fixture before & after, assert identical behavior |
| R13 | Source path resolution via `$0` fragile when script is sourced | Low | High | Use `${BASH_SOURCE[0]}` — Kieran review caught this |

## Rollback Plan

Each phase commits independently, but **phases have forward dependencies**. Rollback in **reverse dependency order** (Kieran review):

| Reverse order | Phase | Action | Why last / first |
|---|---|---|---|
| 1 | Phase 6 (rule-prune) | Revert `sync.md` edit. Any filed GH issues stay (close manually). | No downstream consumers |
| 2 | Phase 5 (aggregator) | Delete `rule-metrics.json`, revert workflow + script. | Phase 6 read this file |
| 3 | Phase 4 (compound) | Revert `SKILL.md` edit. Phase 1.5 returns to prior behavior. | Phase 4 read jsonl from Phase 2 |
| 4 | Phase 3 (schema) | Revert `schema.yaml` + `yaml-schema.md`. No learnings yet depend on `rule_id`. | Phase 5 referenced schema for validation |
| 5 | Phase 2 (hooks) | Revert hook changes + `.gitignore` entries. Incident jsonl is local-only; no cleanup needed. | Phase 4 read the jsonl |
| 6 | Phase 1 (IDs + lint) | `git revert <commit>` restores unannotated AGENTS.md. | Every later phase reads the IDs |

Full-feature rollback after the aggregator has already committed N weekly snapshots: revert the squash-merge PR + `git rm knowledge-base/project/rule-metrics.json` in the revert. Because `.claude/.rule-incidents.jsonl` is gitignored, no cleanup needed on user machines.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** CTO advisory produced 5 architectural recommendations (ADR-1 through ADR-5 above) that deviate from the brainstorm's 9 decisions. Key deltas:

1. Counters in `rule-metrics.json` only, NOT learning frontmatter — eliminates 507-file weekly diff churn.
2. Hook telemetry is a side-effect write, NOT a CC payload contract extension — protects against CC version drift.
3. jsonl concurrency handled via per-session files + rollup, NOT `flock` — avoids latency tax on every PreToolUse.
4. Tag all 6 AGENTS.md sections, not just Hard Rules + Workflow Gates — every enforceable instruction deserves measurement.
5. Add `severity` metadata separate from AGENTS.md (`rule-severity.yaml`); critical rules exempt from prune candidacy.

Additional CTO risks incorporated: ID immutability lint (R10), jsonl rotation policy (Phase 5), bypass false-positive guards (R3), pruning criterion must honor severity (R12).

**Complexity:** Medium (days, not weeks). Prerequisites (PyYAML, hook infrastructure, compound Phase 1.5, `.github/actions/notify-ops-email`) are all in place.

### Product/UX Gate

**Tier:** NONE — infrastructure/tooling change with no user-facing surfaces. No new components, pages, or modals. Purely agent-internal governance telemetry.

## Out of Scope / Deferrals

| Item | Why deferred | Reassessment criteria | Target milestone |
|---|---|---|---|
| Dashboard/visualization of `rule-metrics.json` trends | No UI in v1; data first | After 2 months of committed `rule-metrics.json` snapshots | Post-MVP / Later |
| Cross-project rule utility pooling | Multi-repo scoping adds significant complexity | After internal utility proves value | Post-MVP / Later |
| AI-assisted pruning proposals during compound | Human-gated via GH issues is sufficient for v1 | After first rule-prune cycle produces signal | Post-MVP / Later |
| Bulk backfill of `rule_id` references on existing learnings | Under ADR-1 not required for correctness | Ad-hoc — only if future grep UX demands it | Not tracked |
| Structured JSON output from `/soleur:sync rule-prune` | Markdown report sufficient for v1 | On first consumer need | Post-MVP / Later |

Each deferral will get a tracking issue filed during implementation per AGENTS.md `wg-deferral-tracking`.

## References

- **Issue**: [#2210](https://github.com/soleur-ai/soleur/issues/2210)
- **PR**: #2213
- **Brainstorm**: `knowledge-base/project/brainstorms/2026-04-14-rule-utility-scoring-brainstorm.md`
- **Spec**: `knowledge-base/project/specs/feat-rule-utility-scoring/spec.md`
- **Existing aggregator pattern**: `scripts/rule-audit.sh`, `.github/workflows/rule-audit.yml`
- **Existing PyYAML migration pattern**: `scripts/backfill-frontmatter.py`
- **Compound Phase 1.5**: `plugins/soleur/skills/compound/SKILL.md:138-198`
- **Hook conventions**: `.claude/hooks/guardrails.sh:8-14` (rule-id convention)
