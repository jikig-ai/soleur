---
title: feat: automated rule retirement - CI audit and compound gate
type: feat
date: 2026-03-05
---

# Automated Rule Retirement: CI Audit + Compound Gate

## Overview

Two complementary mechanisms to control governance rule growth across 5 enforcement tiers:

1. **Scheduled Rule Layer Audit** -- GitHub Action that cross-references constitution.md, AGENTS.md, and PreToolUse hooks to detect duplication and hook supersession. Creates a GitHub issue with findings and a PR with proposed migrations.
2. **Compound Rule Budget Gate** -- New Phase 1.6 in compound SKILL.md that warns about rule budget growth and auto-files GitHub issues for tracked follow-up.

## Problem Statement / Motivation

Governance rules accumulate across 5 layers without deduplication. Constitution.md (197 rules, ~7,800 tokens) and AGENTS.md (22 rules) are loaded every turn. The same rule can exist as a hook, a prose rule, an agent description, and a skill instruction. Context files cost 10-22% extra reasoning tokens per interaction (ETH Zurich research). Nine prose rules are currently superseded by 6 PreToolUse hook guards across 3 scripts.

## Proposed Solution

### Component 1: Scheduled Rule Layer Audit (`scheduled-rule-audit.yml`)

**Workflow architecture:** Shell script invoked by GitHub Actions on `workflow_dispatch` (cron added after validation, per constitution rule line 150).

**Parsing:**
- Constitution.md: Count `^- ` bullets per `## Domain` > `### Always/Never/Prefer` section
- AGENTS.md: Count bullets under `## Hard Rules`, `## Workflow Gates`, `## Communication`
- Hooks: Parse `.claude/settings.json` for registered hooks, read each script's comment headers

**Hook-to-prose matching:** Hardcoded mapping table in the audit script. With only 6 guards mapping to 9 prose rules, a static table is more reliable than semantic matching. The table must be updated when hooks are added/removed (same maintenance burden as the hooks themselves).

```text
# Mapping table format (inside audit script):
# guard_id | hook_script | prose_file | prose_line_pattern
guard1|guardrails.sh|AGENTS.md|Never commit directly to main
guard1|guardrails.sh|constitution.md|Never allow agents to work directly on the default branch
guard2|guardrails.sh|AGENTS.md|Never.*rm -rf.*worktree
guard3|guardrails.sh|AGENTS.md|Never.*--delete-branch
guard4|guardrails.sh|constitution.md|grep staged content for conflict markers
pre-merge|pre-merge-rebase.sh|AGENTS.md|Before merging any PR.*merge origin/main
pre-merge|pre-merge-rebase.sh|constitution.md|Merge latest origin/main
write-guard|worktree-write-guard.sh|AGENTS.md|Never edit files in.*main repo.*worktree
write-guard|worktree-write-guard.sh|constitution.md|Never edit files in the main repo root.*worktree
```

**Idempotency:** Search for open issues with label `rule-audit/report`. If findings changed since the last issue, close the old issue with "Superseded by #N" comment and create a new one. If findings are identical, skip. Same pattern for PRs: search by label `rule-audit/migration`, close-and-replace if findings differ.

**Output:**
- GitHub issue with markdown table: rule text, location, enforcement tier, proposed action
- PR that adds `[hook-enforced]` annotation to superseded rules in constitution.md and shortens AGENTS.md entries to cross-references (e.g., "See guardrails.sh Guard 1")
- Labels: `rule-audit/report` (issue), `rule-audit/migration` (PR), pre-created in workflow

**Token cost reduction mechanism:** The net savings come from shortening AGENTS.md entries. A rule like "Never commit directly to main. Create a worktree..." (20 words) becomes "[hook-enforced: guardrails.sh Guard 1]" (5 words). Nine such shortenings across AGENTS.md save ~135 words (~180 tokens per turn). Constitution.md rules get annotated but not removed -- they serve as human-readable documentation of what hooks enforce.

### Component 2: Compound Rule Budget Gate (Phase 1.6)

**Placement:** New Phase 1.6 after Deviation Analyst (Phase 1.5), before Constitution Promotion. This is a separate phase, not mixed into Phase 1.5, because it's a different concern (budget vs. deviation detection).

**Procedure:**
1. Count rules per layer:
   - Constitution.md: count `^- ` bullets (same parser as CI audit)
   - AGENTS.md: count bullets under Hard Rules + Workflow Gates + Communication
   - Hooks: count registered hooks from `.claude/settings.json`
2. Compute always-loaded total: constitution rules + AGENTS.md rules
3. If total > 250: display warning with breakdown by domain and category
4. Cross-reference Deviation Analyst proposals (from Phase 1.5 output) against hook mapping table: if a proposed enforcement hook already exists, flag as "already covered"
5. If warnings found: auto-file GitHub issue with label `rule-audit/compound-finding`

**Warn-only:** Never blocks compound. Output format:

```text
Phase 1.6: Rule Budget Check
  Constitution.md: 197 rules (~7,800 tokens)
  AGENTS.md: 22 rules (~880 tokens)
  Always-loaded total: 219 rules (~8,680 tokens)
  Budget: 219/250 (87%)
  Hook-superseded rules: 9 (candidates for migration)
  [OK] Budget within threshold.
```

Or if over threshold:

```text
Phase 1.6: Rule Budget Check
  Constitution.md: 212 rules (~8,400 tokens)
  AGENTS.md: 24 rules (~960 tokens)
  Always-loaded total: 236 rules (~9,360 tokens)
  Budget: 236/250 (94%) [WARNING: approaching threshold]
  Hook-superseded rules: 12 (candidates for migration)
  [WARNING] Filed GitHub issue #N for rule budget review.
```

**Headless mode:** Warnings print to output but do not prompt. Issue creation runs in both headless and interactive modes.

**Issue deduplication:** Search for open issues with label `rule-audit/compound-finding`. If one exists with the same rule count and supersession count, skip. If counts differ, close-and-replace.

### Shared Infrastructure

**Labels (pre-created in workflow):**
- `rule-audit/report` -- CI audit issue
- `rule-audit/migration` -- CI audit PR
- `rule-audit/compound-finding` -- compound gate issue
- `domain/engineering` -- all three

**Deduplication key:** Label + rule count fingerprint in issue body (e.g., `<!-- audit-fingerprint: constitution=197,agents=22,superseded=9 -->`). Hidden HTML comment enables exact matching without affecting readability.

## Technical Considerations

### Architecture

- Audit script: standalone shell script at `plugins/soleur/skills/rule-retirement/scripts/rule-audit.sh`
- Workflow: `.github/workflows/scheduled-rule-audit.yml`
- Compound gate: inline in `plugins/soleur/skills/compound/SKILL.md` as Phase 1.6
- Mapping table: embedded in audit script (shared via sourcing or copy)

### Edge Cases (from SpecFlow)

1. **0 findings:** Clean exit, no issue/PR. Compound shows clean stats.
2. **Constitution format change:** Parser validates expected `## Domain` > `### Category` structure. Fails loudly with descriptive error if structure doesn't match, rather than silently miscounting.
3. **Hook added between audit runs:** Compound gate catches it immediately. CI audit catches it next run.
4. **Same finding from both components:** Different labels (`rule-audit/report` vs `rule-audit/compound-finding`) but shared fingerprint format allows cross-checking. The CI audit takes precedence since it creates actionable PRs.
5. **`gh` CLI fails during issue creation:** Audit script checks exit code explicitly. If issue creation succeeds but PR creation fails, the issue body notes "PR creation pending."
6. **First run, all 9 superseded rules:** Single PR with all 9 migrations. Documented as expected first-run behavior.

### Security

- Pin all action references to commit SHAs with version comments
- Sanitize `$GITHUB_OUTPUT` writes with `printf` + `tr -d '\n\r'`
- No user-controlled input flows into `gh` CLI arguments (rule text is repo-controlled)
- Explicit `permissions:` block: `contents: write`, `issues: write`, `pull-requests: write`

### Learnings Applied

- Pre-create labels (`gh label create ... 2>/dev/null || true`) -- constitution line 101
- Start with `workflow_dispatch` only, add cron after validation -- constitution line 150
- `set -euo pipefail` with `${N:-}` for optional args and `|| true` for grep pipelines
- `gh --jq` does not support `--arg`; use `export` + `$ENV.var` instead
- Guard commits with `git diff --cached --quiet` before committing
- Concurrency group to prevent parallel runs
- Token revocation: any persistence from claude-code-action happens inside agent prompt

## Acceptance Criteria

- [ ] `rule-audit.sh` parses constitution.md, AGENTS.md, and hook scripts, producing correct rule counts
- [ ] Audit detects all 9 currently hook-superseded prose rules via mapping table
- [ ] Audit creates GitHub issue with markdown report when findings exist
- [ ] Audit creates PR with `[hook-enforced]` annotations and AGENTS.md cross-references
- [ ] Running audit twice with no changes creates no duplicate issues/PRs (idempotent)
- [ ] Running audit after partial fix closes old issue and creates new one with updated findings
- [ ] Compound Phase 1.6 displays rule budget stats every session
- [ ] Compound warns when always-loaded rules exceed 250
- [ ] Compound auto-files GitHub issue when warnings found
- [ ] Compound issue deduplication prevents noise from repeated sessions
- [ ] Both components use consistent label namespace (`rule-audit/*`)
- [ ] Workflow starts with `workflow_dispatch` only (no cron until validated)

## Test Scenarios

- Given no hook-superseded rules exist, when audit runs, then it exits cleanly with no issue or PR
- Given 9 superseded rules exist, when audit runs for the first time, then it creates 1 issue and 1 PR with all 9 findings
- Given an open audit issue exists with 9 findings, when audit runs and finds 6 (3 were fixed), then it closes the old issue and creates a new one with 6 findings
- Given an open audit issue exists with identical findings, when audit runs again, then it skips issue creation (idempotent)
- Given constitution.md has 219 always-loaded rules, when compound runs, then Phase 1.6 shows "219/250 (87%)" without warning
- Given constitution.md grows to 255 always-loaded rules, when compound runs, then Phase 1.6 warns and files a GitHub issue
- Given compound already filed an issue with count 255, when compound runs again with same count, then it skips issue creation
- Given a hook is added in a session, when compound runs, then Phase 1.6 detects the new supersession immediately

## Dependencies & Risks

**Dependencies:**
- Existing PreToolUse hook infrastructure (3 scripts, 6 guards)
- Compound SKILL.md Phase 1.5 (Deviation Analyst) -- must not break existing flow
- `gh` CLI available in CI and local environments

**Risks:**
- **Mapping table staleness:** If hooks are added/removed without updating the mapping table, the audit reports incorrectly. Mitigated by: adding a comment in hook scripts pointing to the mapping table, and the compound gate catching new hooks by parsing `.claude/settings.json` directly.
- **Constitution format drift:** If the heading structure changes, parsers break. Mitigated by: structural validation that fails loudly.
- **Warning fatigue:** If the threshold is too low, warnings become noise. Mitigated by: starting at 250 (current is 219, giving 14% headroom).

## References & Research

### Internal References

- Brainstorm: `knowledge-base/brainstorms/2026-03-05-rule-retirement-brainstorm.md`
- Spec: `knowledge-base/specs/feat-rule-retirement/spec.md`
- Self-healing workflow brainstorm: `knowledge-base/brainstorms/2026-03-03-self-healing-workflow-brainstorm.md`
- Deviation Analyst scope reduction: `knowledge-base/learnings/2026-03-03-deviation-analyst-scope-reduction.md`
- Worktree hook enforcement: `knowledge-base/learnings/2026-02-26-worktree-enforcement-pretooluse-hook.md`
- Guardrails bypass learning: `knowledge-base/learnings/2026-02-24-guardrails-chained-commit-bypass.md`
- CI hook testing: `knowledge-base/learnings/2026-03-05-verify-pretooluse-hooks-ci-deterministic-guard-testing.md`

### Existing Patterns

- `scheduled-daily-triage.yml` -- label pre-creation, agent prompt pattern
- `scheduled-bug-fixer.yml` -- label dedup, cascading selection, idempotency
- `scheduled-competitive-analysis.yml` -- monthly cron, issue creation, claude-code-action
- Compound SKILL.md Phase 1.5 -- Deviation Analyst, Constitution Promotion gates

### Related Issues/PRs

- #422 (this feature)
- #397 / PR #416 (Deviation Analyst v1)
- PR #450 (draft PR for this feature)
