---
title: "chore: automated rule audit CI"
type: chore
date: 2026-03-30
---

# chore: automated rule audit CI

## Overview

Implement a bi-weekly GitHub Actions workflow that audits always-loaded
governance rules for budget compliance and cross-layer duplication, then creates
GitHub issues and PRs with tier migration proposals. Uses fingerprint-based
deduplication for idempotent issue/PR creation.

## Problem Statement / Motivation

Always-loaded rules (AGENTS.md: 62 + constitution.md: 251 = 313 total) exceed
the 300 threshold defined in #451. Growth rate is ~3.7 rules/day. The compound
Phase 1.5 warning at 250 is advisory-only and depends on human action. Without
automated cleanup, context cost will continue to grow unchecked.

## Proposed Solution

Four modular shell scripts in `scripts/rule-audit/` orchestrated by a GitHub
Actions workflow (`rule-audit.yml`), following patterns from existing scheduled
workflows (e.g., `scheduled-cf-token-expiry-check.yml`).

### File Structure

```text
scripts/rule-audit/
  count-rules.sh         # FR1: Count always-loaded rules
  detect-duplication.sh  # FR2: Cross-reference tiers for duplication
  generate-report.sh     # FR3: Build issue body + PR branch
  fingerprint.sh         # FR4: SHA256 dedup check

.github/workflows/
  rule-audit.yml         # FR5: Bi-weekly scheduled workflow
```

## Technical Considerations

### Rule Counting (count-rules.sh)

The current compound Phase 1.5 uses `grep -c '^- '` which counts ALL top-level
bullet points including non-rule items (section descriptions, list preambles).
This is acceptable for a warning but the CI audit should be more precise.

**Approach:** Count lines matching `^-` in rule sections only:

- AGENTS.md: Count under `## Hard Rules`, `## Workflow Gates`, `## Code Quality`,
  `## Review & Feedback`, `## Communication` headings
- constitution.md: Count all `^-` lines (entire file is rules/conventions)

Output format: JSON for machine consumption by downstream scripts.

```json
{"total": 313, "agents_md": 62, "constitution_md": 251, "threshold": 300, "over": true}
```

### Duplication Detection (detect-duplication.sh)

Cross-reference always-loaded rules against cheaper enforcement tiers:

**Tier 1 (hooks) vs Tier 2/3 (AGENTS.md/constitution.md):**

- Extract key phrases from `[hook-enforced: ...]` annotations in AGENTS.md and
  constitution.md
- For each annotated rule, verify the referenced hook script still exists and
  the guard still functions
- Flag rules with `[hook-enforced]` annotation that could migrate from Tier 2
  (AGENTS.md) to Tier 3 (constitution.md) — they're already hook-enforced, so
  the always-loaded AGENTS.md copy is redundant defense-in-depth

**Tier 2/3 vs Tier 4/5 (agent descriptions/skill instructions):**

- Extract key phrases (3+ word sequences after stripping common words) from each
  always-loaded rule
- Search `plugins/soleur/agents/**/*.md` and `plugins/soleur/skills/*/SKILL.md`
  for matching phrases
- Flag matches where the agent/skill instruction duplicates an always-loaded rule

**Output format:** JSON array of findings.

```json
[
  {
    "source_tier": 2,
    "source_file": "AGENTS.md",
    "source_line": 7,
    "target_tier": 1,
    "target_file": ".claude/hooks/guardrails.sh",
    "matched_phrase": "never commit directly to main",
    "recommendation": "migrate_to_tier3",
    "type": "hook_superseded"
  }
]
```

### Report Generation (generate-report.sh)

Takes count JSON + findings JSON as input. Produces:

1. **Issue body** (Markdown): Budget stats table, findings table with migration
   recommendations, tier model reference, deletion candidates
2. **PR branch**: Creates `chore/rule-audit-YYYY-MM-DD` branch with proposed
   file edits (rule movements between AGENTS.md and constitution.md)

PR changes are limited to:

- Moving rules from AGENTS.md to constitution.md (adding `[hook-enforced]`
  annotation if migrating due to hook coverage)
- Adding `[CANDIDATE FOR DELETION]` comments next to potentially obsolete rules
- Never deletes rules — human review required

### Fingerprint Deduplication (fingerprint.sh)

1. Sort findings JSON keys alphabetically
2. SHA256 hash the sorted output
3. Take first 12 characters as fingerprint
4. Search open issues: `gh issue list --label "rule-audit:<fingerprint>" --state open`
5. If match found: exit 0 with "skip" status
6. If no match: exit 0 with "create" status

GitHub label length limit is 50 characters. `rule-audit:` (12) + hash (12) = 24
characters — well within limit.

### Workflow (rule-audit.yml)

```yaml
name: "Scheduled: Rule Audit"
on:
  schedule:
    - cron: '0 9 1,15 * *'
  workflow_dispatch:
concurrency:
  group: scheduled-rule-audit
  cancel-in-progress: false
permissions:
  contents: write
  issues: write
  pull-requests: write
```

Steps:

1. Checkout repo
2. Run `count-rules.sh` → save output to `$GITHUB_OUTPUT`
3. Run `detect-duplication.sh` → save findings to temp file
4. Run `fingerprint.sh` with findings → check dedup status
5. If skip: exit early with summary annotation
6. If create: run `generate-report.sh` → create issue + PR via `gh`
7. Pre-create `rule-audit:<fingerprint>` label if missing
8. Apply label to issue

**Edge cases handled:**

- Branch `chore/rule-audit-YYYY-MM-DD` already exists: delete remote branch
  first (`git push origin --delete`)
- No findings: create issue with "clean audit" body, no PR
- `gh` rate limited: retry once after 60s, then fail workflow (visible in
  Actions UI)
- Files don't exist: `count-rules.sh` checks file existence, exits 1 with
  clear error message

### Security

- No untrusted user input in `run:` blocks (scheduled trigger only)
- Uses `${{ github.token }}` (GITHUB_TOKEN) — no additional secrets
- No heredoc indentation in workflow YAML (per AGENTS.md rule)
- Shell scripts use `set -euo pipefail`

## Acceptance Criteria

- [ ] `scripts/rule-audit/count-rules.sh` counts always-loaded rules from
  AGENTS.md and constitution.md, outputs JSON
- [ ] `scripts/rule-audit/detect-duplication.sh` finds cross-layer duplicates
  between all 5 tiers, outputs JSON findings
- [ ] `scripts/rule-audit/generate-report.sh` produces issue body and PR branch
  from findings
- [ ] `scripts/rule-audit/fingerprint.sh` computes SHA256 fingerprint and checks
  for existing open issues with matching label
- [ ] `rule-audit.yml` runs bi-weekly (1st and 15th at 09:00 UTC) and supports
  manual dispatch
- [ ] Workflow creates GitHub issue with findings when fingerprint is new
- [ ] Workflow creates PR with tier migration proposals when duplicates found
- [ ] Workflow skips issue/PR creation when fingerprint matches existing open issue
- [ ] All scripts independently executable with `bash scripts/rule-audit/<name>.sh`
- [ ] `workflow_dispatch` manual trigger verified working after merge

## Test Scenarios

- Given a clean repo with 313 rules, when `count-rules.sh` runs, then output
  JSON shows `total: 313, over: true`
- Given AGENTS.md has 7 `[hook-enforced]` rules, when `detect-duplication.sh`
  runs, then findings include 7 `hook_superseded` entries
- Given findings JSON with 3 entries, when `fingerprint.sh` runs and no matching
  label exists, then exit status is "create"
- Given findings JSON identical to previous run, when `fingerprint.sh` runs and
  matching label exists on open issue, then exit status is "skip"
- Given `generate-report.sh` runs with findings, when the issue body is created,
  then it contains budget stats table and tier model reference
- Given workflow runs via `workflow_dispatch`, when all scripts succeed, then a
  GitHub issue and PR are created with the fingerprint label

## Alternative Approaches Considered

| Approach | Why Rejected |
|----------|-------------|
| Single monolithic script | Harder to test individual pieces, doesn't match modular pattern |
| Node.js/Bun scripts | Heavier CI setup, no build-step advantage for text parsing |
| Inline shell in workflow | Too much code for workflow `run:` blocks, not testable locally |
| Extend compound Phase 1.5 | Different contexts (in-session vs headless CI), coupling risk |

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (carry-forward from brainstorm)
**Assessment:** CI/CD infrastructure feature using established GitHub Actions and
shell script patterns. No architectural concerns — follows existing scheduled
workflow patterns. Key technical risks: grep pattern precision for rule counting,
fingerprint collision (mitigated by 12-char prefix = 48 bits), PR branch
conflicts on concurrent runs (mitigated by concurrency group).

## Dependencies & Risks

| Risk | Mitigation |
|------|-----------|
| `grep '^- '` matches non-rule bullets | Section-scoped counting in AGENTS.md |
| Keyword matching has false positives | Require 3+ word phrase match, human review of PR |
| PR branch name collision | `concurrency` group prevents parallel runs; delete stale branch before creating |
| GitHub API rate limits | Retry once after 60s; workflow failure is visible in Actions UI |
| Hook script format changes | Detect-duplication reads `[hook-enforced: ...]` annotations, not hook internals |

## Success Metrics

- Rule audit creates actionable issues bi-weekly with migration proposals
- Always-loaded rule count trends downward after migration PRs are merged
- No duplicate issues created (fingerprint deduplication works)

## References & Research

- Prior brainstorm: `knowledge-base/project/brainstorms/archive/20260305-153210-2026-03-05-rule-retirement-brainstorm.md`
- Current brainstorm: `knowledge-base/project/brainstorms/2026-03-30-rule-audit-ci-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-rule-audit-ci/spec.md`
- Compound Phase 1.5: `plugins/soleur/skills/compound/SKILL.md:194`
- Scheduled workflow pattern: `.github/workflows/scheduled-cf-token-expiry-check.yml`
- Shell script pattern: `scripts/weekly-analytics.sh`
- Hook scripts: `.claude/hooks/guardrails.sh`
- Related issues: #422 (rule retirement v1), #451 (this issue), #1304 (deferred semantic matching)
- PR #450 (compound Phase 1.5 implementation)
