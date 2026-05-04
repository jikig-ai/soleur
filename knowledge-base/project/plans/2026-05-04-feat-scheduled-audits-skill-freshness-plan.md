---
title: Scheduled audits + skill freshness telemetry (Theme C1+C3+C4)
date: 2026-05-04
issue: 3122
brainstorm: knowledge-base/project/brainstorms/2026-05-04-harness-engineering-review-brainstorm.md
brainstorm_pr: 3119
branch: feat-scheduled-audits-skill-freshness
worktree: .worktrees/feat-scheduled-audits-skill-freshness
draft_pr: 3124
type: feature
detail_level: more
requires_cpo_signoff: false
---

# Scheduled audits + skill freshness telemetry

## Overview

Convert two manually-invoked audits to GitHub Actions cron, add skill-invocation telemetry that surfaces idle skills, and ship a CI lint that verifies AGENTS.md `[hook-enforced]` / `[skill-enforced]` tags reference real hooks and skill directories. Sourced from `2026-05-04-harness-engineering-review-brainstorm.md` Theme C1+C3 (and C4 stretch, promoted to in-scope here because it shares the same review surface and is ~80 lines of Python with no test scaffolding — current AGENTS.md is its own self-test).

**Pre-implementation verification gates (ran 2026-05-04 during plan):**

- Skill hook input shape: confirmed `{tool_name: "Skill", tool_input: {skill: "<plugin:skill-name>", args: "..."}}` via direct inspection of `~/.claude/projects/.../subagents/*.jsonl`. Hook will use `jq -r '.tool_input.skill'`. (Resolves Kieran's load-bearing-unknown gate.)
- Audit-skill issue-filing capability: `agent-native-audit` and `legal-audit` SKILL.md files contain ZERO `gh issue create` invocations. They produce reports, not issues. C1 implementation MUST drive issue-filing via the workflow prompt (mirrors `scheduled-ux-audit.yml`'s explicit MILESTONE/CAP/INJECTION-SAFETY rules), NOT depend on the skills themselves. (Resolves Kieran's question 1.)

The brainstorm framed this as drift detection — Fowler's "ambiguous signals" and "orphaned controls" applied to Soleur's harness:

- **C1**: existing audits exist but most run only when an operator remembers to invoke them. Wire the missing two to cron.
- **C3**: AGENTS.md rules have firing telemetry (`incidents.sh`); skills do not. A skill unused for months is either dead, superseded, or has broken discovery — without telemetry we can't tell which.
- **C4**: the `[hook-enforced: <hook>]` and `[skill-enforced: <skill> <phase>]` tags in AGENTS.md are claims about the harness's enforcement surface. Today nothing verifies the claims — a renamed hook, deleted skill, or typo silently breaks the rule's promise. Lint at pre-commit and in CI.

## Research Reconciliation — Spec vs. Codebase

The issue body describes "wire each via /soleur:schedule" for five audits. Repo state diverges from this premise:

| Issue claim | Codebase reality | Plan response |
| --- | --- | --- |
| Schedule `/soleur:ux-audit` (weekly) | `.github/workflows/scheduled-ux-audit.yml` exists, cron `0 9 1 * *` (monthly) | Keep existing monthly cadence. File a follow-up issue if weekly is still wanted — bumping cadence is independent of this PR's wiring goal. |
| Schedule `/soleur:agent-native-audit` (monthly) | No workflow exists | Create `scheduled-agent-native-audit.yml` (this PR) |
| Schedule `/soleur:seo-aeo` (biweekly) | `scheduled-seo-aeo-audit.yml` exists, cron `0 10 * * 1` (weekly) | Keep existing weekly cadence. |
| Schedule `/soleur:legal-audit` (quarterly) | No workflow exists | Create `scheduled-legal-audit.yml` (this PR) |
| Schedule `/soleur:competitive-analysis` (monthly per competitor) | `scheduled-competitive-analysis.yml` exists, cron `0 9 1 * *` (monthly aggregate) | Keep existing monthly aggregate. Per-competitor split is a different scope — file follow-up issue. |

Net change for C1: **two new workflows, not five.** Cadence-tuning of the three existing workflows is deliberately out of scope.

## User-Brand Impact

**If this lands broken, the user experiences:** stale or duplicated audit issues clutter the project's issue tracker; skill-stale issues fire en masse on the first aggregator run and train operators to ignore the bot. Internal harness only — no Soleur-end-user surface.

**If this leaks, the user's data is exposed via:** N/A. Telemetry payload is `{ts, skill_name, session_id?}` — no user data, no credentials, no path arguments.

**Brand-survival threshold:** none. Internal tooling change; no data, auth, or money path. Threshold-rationale: hooks fire only on Skill tool calls (not Bash, not Read/Write); the hook script does not read tool inputs. Operator framing answer at brainstorm Phase 0.1 was "audit findings noise / false positives."

## Architecture

Three independent tracks share one PR because they address one theme (drift detection on the harness) and share a review surface (lefthook + GH Actions + AGENTS.md). Each track is independently revertable.

### Track C1 — missing audit cron workflows

Two new workflows mirror the established `.github/workflows/scheduled-*.yml` pattern (preflight job → claude-code-action job → notify-ops-email on failure):

- `scheduled-agent-native-audit.yml` — cron `0 9 15 * *` (monthly, 15th to avoid colliding with the four `0 9 1 * *` workflows already firing on the 1st)
- `scheduled-legal-audit.yml` — cron `0 11 1 1,4,7,10 *` (quarterly: Jan/Apr/Jul/Oct 1, 11:00 UTC — distinct hour from the two existing `0 9 1 * *` workflows `scheduled-ux-audit` and `scheduled-competitive-analysis` which would otherwise collide on Jan/Apr/Jul/Oct 1)

Each workflow invokes the corresponding skill via `claude-code-action@ab8b1e64...` with `Bash`, `Edit`, `Write`, `Read`, `Glob`, `Grep` allowlisted (matched to existing audit allowlists). **Issue filing is driven by the workflow prompt, not the skills** (the skills produce reports, not issues — verified pre-plan). The prompt embeds explicit `MILESTONE RULE`, `CAP_OPEN_ISSUES`, `CAP_PER_RUN`, and `Injection safety` clauses verbatim from `scheduled-ux-audit.yml`. Each workflow inline-creates its label via `gh label create scheduled-<name> 2>/dev/null || true` in a pre-step, mirroring sibling workflows.

### Track C3 — skill freshness telemetry

Mirrors the existing `incidents.sh` + `rule-metrics-aggregate.sh` infrastructure:

```
.claude/hooks/skill-invocation-logger.sh   ← new (PreToolUse on Skill matcher)
        ↓ appends JSONL
.claude/.skill-invocations.<pid>.jsonl     ← new (gitignored, per-PID to avoid append races across worktrees)
        ↓ aggregator reads
scripts/skill-freshness-aggregate.sh       ← new
        ↓ writes
knowledge-base/engineering/operations/skill-freshness.json   ← new (committed via PR)
        ↓ stale-detector reads
.github/workflows/scheduled-skill-freshness.yml              ← new (monthly cron)
        → opens PR with skill-freshness.json
        → files capped issues for skills idle ≥180/365 days
```

**Persistence stance (CTO call carried forward):** This PR matches the existing rule-incidents storage convention — gitignored JSONL, aggregator runs in CI, output JSON committed via PR. The aggregator running in a fresh GH Actions runner therefore sees only the runner's local invocations (i.e., near-empty), exactly like `rule-metrics-aggregate`. **This is a known gap**: local-operator invocations do not propagate to repo-committed metrics today, and this plan does NOT solve it. A follow-up issue is filed (see Deferrals) to close the gap once for both telemetry streams. Trying to solve it in this PR couples persistence redesign with skill-freshness rollout and risks the wrong choice ossifying across two streams.

**Hook design:**

- Single shared file `.claude/.skill-invocations.jsonl` (gitignored) with `flock -x 9` append, mirroring the established `.claude/hooks/lib/incidents.sh` pattern. Per-learning `2026-04-24-rule-metrics-emit-incident-coverage-session-gotchas.md`: cross-runtime `flock` is per-inode not per-path — the writer canonicalizes via `cd -P` + `pwd -P` so a symlinked `.claude/` cannot break interlocking. Per-PID files were considered; rejected to keep one consumption pattern (`flock` is load-bearing per the same learning's `PIPE_BUF`-only-applies-to-pipes warning).
- Kill-switch: `SOLEUR_DISABLE_SKILL_LOGGER=1` env var → hook returns immediately. Lets a misbehaving hook be defeated without a commit.
- Hook script logs only `{schema:1, ts, skill_name, hook_event, session_id}` from the hook input JSON via `jq -nc … 2>/dev/null || return 0` (fail-soft, mirrors `incidents.sh`). No tool arguments, no working-tree paths.
- `tool_input` JSON parse is guarded against invalid JSON via `jq` `2>/dev/null` (per learning `2026-03-18-stop-hook-jq-invalid-json-guard.md`).
- Settings.json `command:` value is `"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/skill-invocation-logger.sh"` — `$CLAUDE_PROJECT_DIR` prefix mandatory because hook commands run via `/bin/sh -c` with non-deterministic CWD across worktrees and agent isolation dirs (per learning `2026-04-12-hook-paths-must-use-claude-project-dir.md`).

**Aggregator design (DHH + simplicity cuts applied):**

- Walks `plugins/soleur/skills/*/SKILL.md` to build the canonical skill inventory.
- Reads `.claude/.skill-invocations.jsonl`; for each line, parses via `jq -c 'select(.skill != null)' 2>/dev/null` (tolerant of malformed lines). Groups by skill name.
- Computes per-skill `last_invoked`, `invocation_count`, `days_since_last`, `status`.
- Writes `knowledge-base/engineering/operations/skill-freshness.json` with shape `{schema:1, generated_at, skills: [{name, last_invoked, invocation_count, days_since_last, status}], summary: {total_skills, idle_180d, idle_365d, never_invoked}}`.
- Drops earlier draft's `first_seen`, `malformed_count`, and consumer-boundary schema assertion. Single writer + single reader + atomic PR-deploy obviates schema-versioning ceremony; the field is present (1 line of code) for forward-compat but consumers do not assert. If a future second consumer is added, the assertion is added then.
- `status ∈ {fresh, idle, archival_candidate}`: `idle` ≥180 days since `last_invoked`, `archival_candidate` ≥365 days. `never_invoked` is informational only — does NOT trigger issue filing.

**Stale-issue filer (DHH cuts applied):**

The plan originally specified four safety nets (dry-run + skiplist + per-run-cap + idempotency). DHH-review correctly observed the 180-day threshold + zero-baseline math: on day one, telemetry has been collecting for 0 days, so no skill has `last_invoked` 180+ days old → `idle` count is 0 → issue-filer fires 0 issues. The 30+ stale-skill day-one spam scenario does not exist with these thresholds. Stripping accordingly:

- **Per-run cap of 3 stale-skill issues** (`CAP_PER_RUN=3`). Mirrors the canonical CAP-pattern in `scheduled-ux-audit.yml` (which uses `CAP_PER_RUN=5`). Bounds blast radius to "max 3 issues/month" regardless of stale skill count.
- **Idempotency.** Before filing for skill `<name>`, query `gh issue list --label scheduled-skill-freshness --search "<name> in:title" --state all --limit 5`; if any issue exists (open OR closed within 30 days), skip. Prevents reopen-loops.
- **Filing semantics.** `idle` (≥180d since `last_invoked`) and `archival_candidate` (≥365d) trigger filing. `never_invoked` is informational only — does NOT trigger filing (otherwise the first run would file 67 issues for skills not invoked in the runner's own session).
- **No dry-run period, no skiplist.** Operators close any false-positive issue once; idempotency ensures it does not return for 30 days. If the false-positive rate proves >50% across two months, file a follow-up to add a skiplist or thresholds tuning — but ship without speculative ceremony.
- **Filed issues carry `scheduled-skill-freshness` AND `do-not-autoclose` labels** (latter prevents `scheduled-daily-triage` from autoclosing — per learning `2026-04-15-ux-audit-scope-cutting-and-review-hardening.md`).
- Issue body includes `--milestone "Post-MVP / Later"` per the canonical scheduled-audit milestone rule (visible in `scheduled-ux-audit.yml`'s prompt).

### Track C4 — AGENTS.md enforcement-tag lint

Mirror `scripts/lint-rule-ids.py` exactly:

- New script `scripts/lint-agents-enforcement-tags.py` parses AGENTS.md, extracts every `[hook-enforced: <hook-or-token>]` and `[skill-enforced: <skill> <rest>]` tag.
- **Lenient existence check only** (CTO call carried forward — strict phase-name match would couple AGENTS.md formatting to skill-internal heading style; today's 13 tagged rules use 5 different phase notations).
  - For `[hook-enforced: <hook>]`: assert the first whitespace-split token resolves to either (a) a path under `.claude/hooks/`, `scripts/`, or `plugins/soleur/hooks/` (per learning `2026-05-03-rule-audit-issue-remediation-worked-example.md` — `rule-audit.sh` had a known false-positive scoping only `.claude/hooks/`; this lint must look in all three), or (b) a token recognized in `lefthook.yml` (e.g., `lefthook lint-rule-ids.py` resolves to a `lefthook.yml` `pre-commit:commands:*:run` line containing `lint-rule-ids.py`).
  - For `[skill-enforced: <skill> <rest>]`: assert `plugins/soleur/skills/<skill>/SKILL.md` exists. Skip phase-name verification.
- **Honors `scripts/retired-rule-ids.txt`** — IDs listed there may be absent from AGENTS.md; the new lint does NOT fail on retired-but-still-tagged conditions (defensive; mirrors `lint-rule-ids.py`).
- **Honors pointer-preservation pattern** (per learning `2026-04-21-agents-md-rule-retirement-deprecation-pattern.md`): some AGENTS.md rules are one-line pointers with full body migrated to a skill/hook file. The lint inspects only the bracketed `[hook-enforced]` / `[skill-enforced]` content and does not require any companion text.
- Wired into `lefthook.yml` `pre-commit:commands:agents-enforcement-tag-lint`, glob `AGENTS.md`. Also runs in CI on every PR via the `lefthook` step that already exists in `.github/workflows/ci.yml` (verified at implementation time — if no such step exists, add a dedicated workflow step instead).

## Files to Create

- `.github/workflows/scheduled-agent-native-audit.yml`
- `.github/workflows/scheduled-legal-audit.yml`
- `.github/workflows/scheduled-skill-freshness.yml`
- `.claude/hooks/skill-invocation-logger.sh`
- `.claude/hooks/skill-invocation-logger.test.sh`
- `scripts/skill-freshness-aggregate.sh`
- `scripts/skill-freshness-aggregate.test.sh`
- `scripts/lint-agents-enforcement-tags.py` (no test wrapper — running against current AGENTS.md in CI is its own self-test; 13 existing tags must pass on every PR)
- `knowledge-base/engineering/operations/skill-freshness.json` (initial commit; aggregator updates monthly via PR)
- `knowledge-base/project/specs/feat-scheduled-audits-skill-freshness/tasks.md` (generated post-review)

## Files to Edit

- `.claude/settings.json` — add a `PreToolUse` matcher block for `Skill` that invokes `skill-invocation-logger.sh`. Place after the existing `mcp__pencil__open_document` block to keep the file diff small.
- `.gitignore` — add `.claude/.skill-invocations.jsonl` and `.claude/.skill-invocations-*.jsonl.gz` (rotation-friendly, mirrors `.claude/.rule-incidents.jsonl` precedent on lines 34-35).
- `lefthook.yml` — add `pre-commit:commands:agents-enforcement-tag-lint`, glob `AGENTS.md`, `run: python3 scripts/lint-agents-enforcement-tags.py AGENTS.md`. Priority `4` (alongside `rule-id-lint`).
- `AGENTS.md` — add `[hook-enforced: lefthook lint-agents-enforcement-tags.py]` to one existing `[skill-enforced]` rule (suggest `cq-rule-ids-are-immutable` already has `[hook-enforced: lefthook lint-rule-ids.py]` — keep that; the new lint protects a different surface). Alternatively, add no AGENTS.md edit — the lint is meta-enforcement, not a new rule. **Decision: no AGENTS.md edit in this PR.** The lint exists to verify existing claims; tagging itself with `[hook-enforced]` would be self-referential.

## Implementation Phases

**Phase ordering rationale:** C4 ships first because it's the lowest-risk track (~80 lines, no runtime dependencies) and the lint protects any new `[hook-enforced]` / `[skill-enforced]` tags added by later phases. Phase 2 (C1) and Phase 3 (C3) do NOT add new AGENTS.md tags in this PR; the lint is purely meta-protection. If a tag is added later in any phase, the lefthook pre-commit lint will validate it before commit. Phases 2 and 3 are independent and can run in either order.

**Per-phase mergeability:** Each phase is structured to be independently revertable. If Phase 3's empirical Skill-matcher verification fails at implementation time (the matcher key isn't `tool_input.skill` despite pre-plan transcript inspection), Phase 3 can be split out to a separate PR while Phases 1 and 2 ship.

### Phase 1 — Track C4 (lint script)

Smallest, lowest-risk track; ships first so the rest of the plan inherits a working lint that protects subsequent tag additions.

1. Read `scripts/lint-rule-ids.py` end-to-end. Mirror its CLI shape (`argparse`, `--retired-file` not needed, exit codes, error messages).
2. Write `scripts/lint-agents-enforcement-tags.py` (target ~80 lines):
   - Regex `r"\[hook-enforced: ([^\]]+)\]"` and `r"\[skill-enforced: ([a-z][a-z0-9-]*)( [^\]]*)?\]"` over AGENTS.md.
   - For each hook-enforced match: split on whitespace, check first token. If literal `lefthook`, grep `lefthook.yml` for the second token; else check `.claude/hooks/<token>` exists.
   - For each skill-enforced match: check `plugins/soleur/skills/<skill>/SKILL.md` exists.
   - Exit 1 with structured error per failure.
3. Verify against current AGENTS.md: `python3 scripts/lint-agents-enforcement-tags.py AGENTS.md` exits 0. The 13 existing tags collectively cover all 5 phase notations and serve as the lint's self-test (per DHH/simplicity convergent call to drop the dedicated `.test.sh` wrapper).
4. Wire into `lefthook.yml` `pre-commit:commands:agents-enforcement-tag-lint`, glob `AGENTS.md`, priority `5` (one above `rule-id-lint`'s priority `4` — runs after rule-id validity is established). Run `lefthook run pre-commit` locally to verify.
5. Sanity-check by temporarily inserting `[hook-enforced: ghost.sh]` into AGENTS.md, running the lint to confirm exit 1, then reverting.

### Phase 2 — Track C1 (audit cron workflows)

1. Read `.github/workflows/scheduled-ux-audit.yml` and `scheduled-competitive-analysis.yml` to extract the canonical pattern (preflight job, concurrency, label creation, claude-code-action invocation, notify-ops-email on failure).
2. Create `.github/workflows/scheduled-agent-native-audit.yml`:
   - cron `0 9 15 * *`
   - preflight via `./.github/actions/anthropic-preflight`
   - claude-code-action invokes `/soleur:agent-native-audit`
   - allowed-tools mirror the audit skill's needs (Bash, Edit, Write, Read, Glob, Grep, gh)
   - on-failure email via `./.github/actions/notify-ops-email`
   - timeout 45 minutes, max-turns 50 (ratio 0.9 — see learning `2026-03-20-claude-code-action-max-turns-budget.md`)
   - label `scheduled-agent-native-audit`, color `#0E8A16` (mirrors existing scheduled-* labels)
3. Create `.github/workflows/scheduled-legal-audit.yml`:
   - cron `0 9 1 1,4,7,10 *`
   - same shape as agent-native-audit
   - timeout 60 minutes, max-turns 60 (ratio 1.0 — legal-audit traverses more file surface)
   - label `scheduled-legal-audit`
4. Verify both files pass `actionlint` if installed locally; otherwise rely on CI.
5. Verify each cron expression with `python3 -c "from croniter import croniter; from datetime import datetime; c = croniter('<cron>', datetime.utcnow()); print([c.get_next(datetime) for _ in range(3)])"` if `croniter` is installed; otherwise document the next 3 fire dates inline.

### Phase 3 — Track C3 (telemetry hook + aggregator + cron)

1. Write `.claude/hooks/skill-invocation-logger.sh` (~50 lines, mirrors `incidents.sh` writer idiom):
   - First line after shebang: `[[ "${SOLEUR_DISABLE_SKILL_LOGGER:-}" == "1" ]] && exit 0`
   - Canonicalize repo root via `cd -P "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd -P` (matches `_incidents_repo_root` pattern; symlink-safe).
   - Read hook input JSON from stdin via `jq -r '.tool_input.skill // empty' 2>/dev/null` (invalid-JSON guard per learning `2026-03-18-stop-hook-jq-invalid-json-guard.md`; skill name lives in `tool_input.skill` per Skill tool schema — verify at implementation step 0 against a real Skill invocation).
   - Build line with `jq -nc --arg … '{schema:1, ts, skill, session_id, hook_event}' 2>/dev/null || exit 0` (fail-soft).
   - Append via `( flock -x 9; printf '%s\n' "$line" >&9 ) 9>>"$file"` (mirrors `incidents.sh`).
   - Always exit 0 — fire-and-forget, never block tool dispatch.
2. **Empirical Skill matcher key verification (REQUIRED before step 1 ships):** invoke a known skill (e.g., `/soleur:help`) with a `set -x` line at the top of the hook script. Confirm the hook fires AND `jq -r '.tool_input.skill'` extracts the skill name. If the JSON shape is different (key is `tool_input.name`, `skill_name`, or matcher behavior differs), update the script to match. **Document the actual key + a literal example payload in the script header comment** so future hook authors don't re-verify.
3. Write `.claude/hooks/skill-invocation-logger.test.sh` mirroring `pre-merge-rebase.test.sh` and `security_reminder_hook.test.sh`. Cover: kill-switch honored, skill-name extraction (input shape: `{tool_name:"Skill",tool_input:{skill:"<plugin>:<name>"}}` per pre-plan empirical verification), `schema:1` field present on output, fail-soft on invalid input JSON, no append-corruption under 100 concurrent fires (background loop + `jq -e '. | tostring | length > 0'` verification on every line).
4. Edit `.claude/settings.json` — add `PreToolUse` matcher `Skill` with command `"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/skill-invocation-logger.sh"`. Verify JSON validity via `jq . .claude/settings.json`. Note: `security_reminder_hook` may flag the first Edit on this file — retry once per learning `2026-04-15-rule-metrics-aggregator-pr-pattern-session-gotchas.md`.
5. Edit `.gitignore` — add the two skill-invocations patterns.
6. Write `scripts/skill-freshness-aggregate.sh`:
   - Walk `plugins/soleur/skills/*/SKILL.md` to build the canonical skill inventory.
   - Read `.claude/.skill-invocations.jsonl`. Parse line-by-line via `jq -c 'select(.skill != null)' 2>/dev/null` (tolerant of malformed lines). Group by skill name.
   - Compute per-skill metrics: `last_invoked`, `invocation_count`, `days_since_last`, `status`.
   - Write `knowledge-base/engineering/operations/skill-freshness.json` with top-level `schema: 1`. (Field present for forward-compat; consumers do not assert.)
7. Write `scripts/skill-freshness-aggregate.test.sh`. Cover: empty JSONL produces inventory-only output (all skills `never_invoked`); corrupted line is skipped without erroring; status thresholds correct at 179/180/364/365 days; `never_invoked` does not trigger filing.
8. Create `.github/workflows/scheduled-skill-freshness.yml` (mirrors `.github/workflows/rule-metrics-aggregate.yml` per learning `2026-04-15-rule-metrics-aggregator-pr-pattern-session-gotchas.md`):
   - cron `0 0 1 * *` (monthly, 1st 00:00 UTC — separate hour from the two `0 9 1 * *` workflows to avoid runner contention)
   - `permissions:` = `checks: write, contents: write, pull-requests: write` (NOT `statuses: write` — Status API ≠ Checks API per `2026-03-23-skip-ci-blocks-auto-merge-on-scheduled-prs.md`)
   - Run aggregator
   - Open PR via `./.github/actions/bot-pr-with-synthetic-checks` adding `knowledge-base/engineering/operations/skill-freshness.json`. The action handles all four synthetic check-runs (`test`, `cla-check`, `dependency-review`, `e2e`) automatically. Note: this composite action does NOT take a `--milestone` input — milestone applies to issue filing only (verified at `.github/actions/bot-pr-with-synthetic-checks/action.yml`).
   - Inline label-creation step: `gh label create scheduled-skill-freshness 2>/dev/null || true; gh label create do-not-autoclose 2>/dev/null || true`
   - Stale-issue filer step:
     - For each `idle`/`archival_candidate` skill, check idempotency via `gh issue list --label scheduled-skill-freshness --search "<name> in:title" --state all --limit 5`; skip if any hit (open or closed within 30 days).
     - File at most `CAP_PER_RUN=3` issues per run (env var, mirrors `scheduled-ux-audit.yml`'s CAP convention).
     - Filed issues carry labels `scheduled-skill-freshness` + `do-not-autoclose`, milestone `"Post-MVP / Later"`.
     - Issue body fields written to env vars or files BEFORE `gh issue create` — never interpolate agent output into `run:` directly (injection-safety per `scheduled-ux-audit.yml` precedent).
     - `never_invoked` status does NOT file (informational only).
   - notify-ops-email on failure
10. Manually run aggregator locally against the live `.claude/.skill-invocations.jsonl` (after a few `/soleur:foo` invocations) to confirm output shape.
11. `gh workflow run scheduled-skill-freshness.yml` is NOT possible pre-merge (`workflow_dispatch` requires default-branch presence — per learning `2026-04-21-workflow-dispatch-requires-default-branch.md`). Verification ships as **post-merge action** in Acceptance Criteria.
12. Deferred: `.github/workflows/test-pretooluse-skill-hook.yml` — DHH/simplicity reviewers split on need; combined with the empirical pre-plan verification (already done) and the fail-soft hook design, the regression net can be added once a real divergence appears. Tracked in Deferrals.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `python3 scripts/lint-agents-enforcement-tags.py AGENTS.md` exits 0 against current AGENTS.md (13 existing tags pass — this run is the lint's self-test; no separate `.test.sh`).
- [ ] `bash .claude/hooks/skill-invocation-logger.test.sh` passes; verifies kill-switch, skill-name extraction from real `tool_input.skill` shape, fail-soft on bad input JSON.
- [ ] `bash scripts/skill-freshness-aggregate.test.sh` passes; verifies empty-JSONL inventory output, malformed-line tolerance, threshold boundaries at 179/180/364/365 days.
- [ ] `lefthook run pre-commit` from a clean checkout executes the new lint successfully.
- [ ] `actionlint .github/workflows/scheduled-agent-native-audit.yml .github/workflows/scheduled-legal-audit.yml .github/workflows/scheduled-skill-freshness.yml` exits 0 (or equivalent CI step runs without warnings).
- [ ] Cron next-fire dates documented in PR body for at least 3 future fires per workflow.
- [ ] `jq . .claude/settings.json` exits 0 after the matcher edit.
- [ ] `git ls-files .claude/.skill-invocations` returns nothing (gitignore rule active).
- [ ] PR body uses `Closes #3122` and includes a quoted excerpt of the brainstorm's C1+C3+C4 sections (because brainstorm path resolves only on PR #3119 branch). PR body marks `depends-on: #3119` if #3119 is still open.
- [ ] Aggregator's `summary.never_invoked` count = total skill count (67 today) on first run — i.e., the empty-JSONL baseline produces a complete inventory.

### Post-merge (operator)

- [ ] `gh workflow run scheduled-skill-freshness.yml` triggers successfully on default branch; aggregator exits 0; PR opens with `skill-freshness.json` containing all 67 skills.
- [ ] `gh workflow run scheduled-agent-native-audit.yml` triggers manually; preflight succeeds; claude-code-action runs the skill and files at most CAP_PER_RUN issues per the workflow prompt.
- [ ] `gh workflow run scheduled-legal-audit.yml` triggers manually; same.
- [ ] `cron-scheduler-heartbeat` alerting: rely on existing `scheduled-cloud-task-heartbeat` workflow + `cloud-task-silence` label to detect if a new cron fails to fire within its expected window. (No new alerting added.)

## Test Strategy

- **Bash tests** for `skill-invocation-logger.test.sh` and `skill-freshness-aggregate.test.sh` — run via `bash <path>` directly. Existing precedent: `pre-merge-rebase.test.sh`, `rule-metrics-aggregate.test.sh`, `docs-cli-verification.test.sh`. No new test framework introduced.
- **Python lint self-test** — `python3 scripts/lint-agents-enforcement-tags.py AGENTS.md` against current AGENTS.md is the test; the 13 existing tags exercise all 5 phase notations and all hook-path lookup branches. No dedicated `.test.sh` (DHH/simplicity convergent call).
- **CI wiring**: lefthook is already invoked at pre-commit. The new lint runs there. CI re-runs lefthook on PRs via the existing CI workflow (verify path at implementation; if not present, add a step).
- **Workflow lint**: `actionlint` is the canonical YAML linter for GH Actions. If not installed locally, document the manual-spot-check procedure (compare against the canonical `scheduled-competitive-analysis.yml`).
- **Skill matcher verification at implementation**: before wiring the hook, invoke a known skill (e.g., `/soleur:help`) with the hook in place and a `set -x` line at the top. Confirm the hook runs and `jq -r '.tool_input.skill'` extracts the skill name. If the JSON shape is different (e.g., key is `tool_input.name` or `skill_name`), update the script to match. **Document the actual key in the script header comment.**

## Risks

- **Skill matcher key drift**: empirical verification done pre-plan (transcript inspection at 2026-05-04 confirmed `tool_input.skill = "<plugin>:<name>"`). If CC's hook contract changes post-merge, the hook silently logs nothing — fail-soft by design. Mitigation: implementation Phase 3 step 2 re-verifies with `set -x` against the live hook input; if the regression net `test-pretooluse-skill-hook.yml` is needed later, it can be added per the deferred-issues list.
- **Audit skills don't file issues per finding by default**: per learning `growth-audit-missing-issue-tracking-and-seo-score-20260325.md`, scheduled audits that produce reports without filing per-finding GH issues are a known anti-pattern. Implementation must verify that `agent-native-audit` and `legal-audit` skills produce per-finding issues (or that the workflow wires `--issue-per-finding`-equivalent behavior). If the skills don't support this today, file follow-up issues before merging.
- **JSONL line corruption under concurrent worktrees**: `flock -x 9` interlocks per inode (per learning `2026-04-24-rule-metrics-emit-incident-coverage-session-gotchas.md`). Symlinked `.claude/` would break this; the canonicalized `cd -P + pwd -P` repo-root resolution prevents the symlink case. Aggregator tolerates malformed lines via `2>/dev/null`. If observed corruption surfaces, add line-level checksums and a count-of-skipped-lines metric in a follow-up.
- **Stale-issue blast radius**: 67 skills, no dry-run, cap=3 issues per monthly run = max 36 stale-skill issues per year. With 180-day threshold + zero-baseline, day-one count is 0; realistic steady-state is ~5-10 idle skills surfacing over 6-12 months. Acceptable.
- **Brainstorm not yet merged**: The source brainstorm lives on PR #3119 (not yet merged). PR review may ask "where's the brainstorm?" — the path resolves only on the brainstorm branch. Mitigation: PR body includes a quote of the relevant brainstorm decisions; PR is marked `depends_on: #3119` and not auto-merged until #3119 lands.
- **claude-code-action max-turns / timeout drift**: Both new workflows obey the median 0.75 min/turn ratio per `2026-03-20-claude-code-action-max-turns-budget.md`. agent-native-audit at 45min/50turn=0.9, legal-audit at 60min/60turn=1.0 — both above median, conservative.
- **Cron expression validity**: GH Actions cron evaluator accepts standard 5-field syntax; verified at implementation. The `15 * *` field combination for agent-native-audit fires monthly on the 15th; the quarterly `1,4,7,10` legal-audit fires on Jan/Apr/Jul/Oct 1.
- **Existing 13 tag failures**: `lint-agents-enforcement-tags.py` is run pre-merge against current AGENTS.md. If any of the 13 tags fail (e.g., a referenced skill was renamed since the tag was written), the lint blocks the PR until the tag is updated. This is the right behavior — it's the lint's whole point.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan declares `none` with reasoning above.
- Hook scripts that read `tool_input` keys depend on the Claude Code hook contract; the contract is stable but undocumented per skill. Implementation Phase 3 step 1 verifies live; do not skip.
- `.claude/settings.json` is the source of truth for hooks. PR review should explicitly confirm the new matcher block lands in the right place (after existing matchers, valid JSON).
- `actionlint` is not installed in the repo's dev environment (verify at implementation). If absent, do not skip workflow validation — install via `brew install actionlint` or `go install github.com/rhysd/actionlint/cmd/actionlint@latest`.
- Pre-merge `gh workflow run` of any of the three new workflows fails with HTTP 404 because the workflow file does not exist on `main` until merge. This is a known GH Actions constraint — verification via `workflow_dispatch` is post-merge only. See `knowledge-base/project/learnings/integration-issues/2026-04-21-workflow-dispatch-requires-default-branch.md`.
- The skill-freshness aggregator runs in CI against an empty `.claude/.skill-invocations.jsonl` (gitignored, no committed telemetry). The first `skill-freshness.json` will show every skill as `never_invoked` — this is correct behavior, not a bug. The dashboard becomes useful as operators commit work that triggered skill invocations during their sessions (which currently do not propagate; see "known persistence gap" in Architecture).
- `bot-pr-with-synthetic-checks` does NOT accept a `milestone` input at all (verified — action.yml inputs are `add-paths`, `branch-prefix`, `commit-message`, `pr-title-prefix`, `pr-body`, `change-summary`, `gh-token`). Milestone applies only to issue-filer's `gh issue create --milestone "Post-MVP / Later"` calls. Earlier draft conflated the two — corrected here.
- `[skip ci]` in commit messages on bot PRs blocks auto-merge against required Check Runs (Status API ≠ Checks API per learning `2026-03-23-skip-ci-blocks-auto-merge-on-scheduled-prs.md`). The skill-freshness PR commit message MUST NOT include `[skip ci]`.
- claude-code-action SHA pin must stay synced with model bumps (per learning `2026-04-18-action-pin-sync-with-model-bump.md`). Both new audit workflows pin `@ab8b1e6471c519c585ba17e8ecaccc9d83043541` (v1.0.101) — matching existing siblings. If a model bump lands before this PR merges, rebase to the new SHA.

## Open Code-Review Overlap

Two open code-review issues had file-path substring matches; both are false positives:

- **#2348** (`vitest: mock-factory export drift when mocked module gains new named export`) — the body mentions `.claude/hooks/` as part of an unrelated investigation context. **Acknowledge — different concern, no action.**
- **#3002** (`review: add service-worker global error handler for cache.put quota failures`) — body mentions `AGENTS.md` for a rule citation. **Acknowledge — different concern, no action.**

Neither overlaps the actual planned files. No fold-in opportunities; no deferrals.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Carry the three structural calls forward into the plan. (a) Telemetry persistence stays mirror-of-existing-pattern; the rule-incidents-gap fix is a separate issue (deferred). (b) C4 lint is lenient existence-check only — strict phase-name match would couple AGENTS.md formatting to skill-internal heading style and the existing 13 tags use 5 different phase notations. (c) Three blast-radius mitigations baked in: kill-switch env var on the hook, per-PID JSONL files (no append races), and stale-issue filer with skip-list + idempotency + per-run cap.

### Product (CPO)

**Status:** reviewed
**Assessment:** Issue #3122 is correctly milestoned `Post-MVP / Later`; Phase 4 is overdue and harness work risks crowding user-facing work. CPO recommended Option B (C4-only). This plan ships full C1+C3+C4 because (1) C1 is small (2 workflows mirror an established pattern), (2) C3 mitigations cluster post-DHH-review around the math: 180-day threshold + zero-baseline → day-one issue count is 0, removing the dry-run period and skiplist as ceremony — what remains (per-run cap of 3 + idempotency) bounds blast radius regardless of stale skill count, and (3) C4 ships in 80 lines with no test scaffolding (current AGENTS.md is its own self-test). If post-merge experience proves CPO right and the issue-tracker noise becomes real, the lever is `CAP_PER_RUN=0` (one-line workflow edit) rather than reverting the PR.

### Product/UX Gate

**Tier:** none — no user-facing UI surface (internal harness tooling).

## Deferrals (tracking issues to file post-merge)

- **Per-competitor split for `scheduled-competitive-analysis.yml`** — brainstorm prescribed "monthly per tracked competitor"; current workflow is monthly aggregate.
- **Cadence change for ux-audit (monthly → weekly)** — brainstorm prescribed weekly; reality is monthly.
- **Cadence change for seo-aeo-audit (weekly → biweekly)** — brainstorm prescribed biweekly; reality is weekly.
- **Telemetry persistence gap (rule-incidents + skill-invocations)** — both gitignored JSONLs do not propagate from local sessions to repo-committed metrics. Solve once for both streams. Approach options: (a) commit JSONL with rotation, (b) session-end flush hook, (c) external sink. CTO-flagged scope-creep risk if bundled here.
- **`test-pretooluse-skill-hook.yml`** — deterministic CI guard test that the `Skill` matcher fires in `claude-code-action` runtime (per learning `2026-03-05-verify-pretooluse-hooks-ci-deterministic-guard-testing.md`). Empirical pre-plan verification + fail-soft hook design make this a regression net rather than a discovery mechanism; defer until a real divergence appears.
- **Audit-skill native issue-filing capability** — `agent-native-audit` and `legal-audit` produce reports today; the workflow prompt drives issue creation. Long-term, the skills should embed issue-filing semantics (matching `ux-audit`'s pattern). File issues to track moving the prompt logic into the skills themselves.

## Research Insights

- **Repo pattern:** scheduled audit workflows are standardized — preflight via `./.github/actions/anthropic-preflight`, claude-code-action with pinned `@ab8b1e6471c519c585ba17e8ecaccc9d83043541` (v1.0.101), notify-ops-email on failure, label creation via `gh label create ... 2>/dev/null || true`. Replicate exactly; do not invent a new pattern.
- **Aggregator + PR pattern:** `./.github/actions/bot-pr-with-synthetic-checks` already handles the PR-with-synthetic-checks dance for `rule-metrics-aggregate.yml`. Reuse for `scheduled-skill-freshness.yml`.
- **Lint precedent:** `scripts/lint-rule-ids.py` (~120 lines, argparse, regex over AGENTS.md, exit codes) is the canonical pattern. Mirror its CLI shape and bash test wrapper precedent (`pre-merge-rebase.test.sh`).
- **Cron-collision avoidance:** two existing workflows fire at `0 9 1 * *` (`scheduled-ux-audit`, `scheduled-competitive-analysis`). New `agent-native-audit` shifts to the 15th to avoid runner contention; new `legal-audit` shifts to `0 11 1 1,4,7,10 *` (avoids quarterly date-hour collision with the two existing 1st-of-month workflows). New `skill-freshness` uses `0 0 1 * *` (distinct hour from all other 1st-of-month workflows).
- **Heartbeat alerting exists:** `scheduled-cloud-task-heartbeat` + `cloud-task-silence` label already detect failed cron fires. No new alerting needed.
- **Hook contract** (verified at implementation): PreToolUse hooks receive `{tool_input, ...}` JSON on stdin; matcher patterns match tool name. The `Skill` matcher should resolve to `Skill` tool calls. Verify the exact `tool_input` key for skill name at implementation Phase 3 step 1.
- **AGENTS.md tag format inventory** (13 tags scanned 2026-05-04):
  - `[hook-enforced: guardrails.sh guardrails:block-stash-in-worktrees]`
  - `[hook-enforced: lefthook lint-rule-ids.py]`
  - `[skill-enforced: brainstorm Phase 0.5]`
  - `[skill-enforced: ship Phase 5.5]`
  - `[skill-enforced: plan Phase 1.4, deepen-plan Phase 4.5]`
  - `[skill-enforced: preflight Check 4]`
  - `[skill-enforced: brainstorm Phase 0.1, plan Phase 2.6, deepen-plan Phase 4.6, review user-impact-reviewer, preflight Check 6]`
  - `[skill-enforced: ship Phase 5.5 Retroactive Gate Application]`
  - `[skill-enforced: ship Phase 7]`
  - `[skill-enforced: work Phase 2 TDD Gate]`
  - `[skill-enforced: compound step 8]`
  - `[skill-enforced: compound Route-Learning-to-Definition]`
  - `[skill-enforced: ship Phase 5.5 Review-Findings Exit Gate]`

  All five phase-notation variants (`Phase X`, `Step X`, `Check X`, route-name, agent-name) explicitly tolerated by the lenient lint.
