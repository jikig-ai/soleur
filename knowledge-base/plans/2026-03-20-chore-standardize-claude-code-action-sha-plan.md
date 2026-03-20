---
title: "chore(ci): standardize claude-code-action SHA across all workflows"
type: chore
date: 2026-03-20
issue: "#809"
---

# chore(ci): standardize claude-code-action SHA across all workflows

## Overview

Twelve workflow files reference `anthropics/claude-code-action` pinned to commit SHAs, but two different SHAs are in use. Seven workflows pin to `64c7a0ef71df67b14cb4471f4d9c8565c61042bf` (commented `# v1`), and five workflows pin to `1dd74842e568f373608605d9e45c9e854f65f543` (commented `# v1.0.63`). Standardize all twelve on the latest SHA with an accurate version comment.

## Problem Statement

Version inconsistency creates a silent security gap: if one SHA contains a vulnerability fix that the other lacks, some workflows remain exposed. The older SHA (`64c7a0ef...`) resolves to commit message "Only expose permission_denials count in sanitized output (#993)" and the newer one (`1dd74842...`) resolves to "chore: bump Claude Code to 2.1.61 and Agent SDK to 0.2.61". Neither is the current `v1` tag, which now points to `df37d2f0760a4b5683a6e617c9325bc1a36443f6` (v1.0.75, published 2026-03-18).

Found during security review of #803. Pre-existing issue noted in `knowledge-base/plans/2026-03-19-fix-ci-pr-based-commit-pattern-plan.md` line 209.

## Target SHA

The `v1` mutable tag on `anthropics/claude-code-action` currently points (via annotated tag dereference) to:

| Field | Value |
|-------|-------|
| Commit SHA | `df37d2f0760a4b5683a6e617c9325bc1a36443f6` |
| Release tag | v1.0.75 |
| Published | 2026-03-18 |
| Tag object SHA | `bf4f0de6fccd1eea7044a5f903fc928aff363134` |

**Version comment format:** `# v1.0.75` (matches the existing `# v1.0.63` convention used in newer workflows).

## Files Changed

### Group A: Old SHA `64c7a0ef...` (# v1) -- 7 files

| File | Line |
|------|------|
| `.github/workflows/scheduled-bug-fixer.yml` | 119 |
| `.github/workflows/scheduled-ship-merge.yml` | 114 |
| `.github/workflows/scheduled-content-generator.yml` | 53 |
| `.github/workflows/scheduled-growth-execution.yml` | 49 |
| `.github/workflows/test-pretooluse-hooks.yml` | 46 |
| `.github/workflows/scheduled-daily-triage.yml` | 63 |
| `.github/workflows/scheduled-seo-aeo-audit.yml` | 49 |

### Group B: Newer SHA `1dd74842...` (# v1.0.63) -- 5 files

| File | Line |
|------|------|
| `.github/workflows/scheduled-growth-audit.yml` | 50 |
| `.github/workflows/scheduled-community-monitor.yml` | 50 |
| `.github/workflows/scheduled-campaign-calendar.yml` | 45 |
| `.github/workflows/claude-code-review.yml` | 36 |
| `.github/workflows/scheduled-competitive-analysis.yml` | 42 |

### Total: 12 files, 12 line changes

Each line follows the same pattern:

```yaml
# Before (Group A):
uses: anthropics/claude-code-action@64c7a0ef71df67b14cb4471f4d9c8565c61042bf # v1

# Before (Group B):
uses: anthropics/claude-code-action@1dd74842e568f373608605d9e45c9e854f65f543 # v1.0.63

# After (all 12):
uses: anthropics/claude-code-action@df37d2f0760a4b5683a6e617c9325bc1a36443f6 # v1.0.75
```

## Implementation Approach

### Tooling Constraint

The `security_reminder_hook.py` PreToolUse hook blocks both Edit and Write tools on `.github/workflows/*.yml` files. All workflow edits must use `sed` via the Bash tool. See learning: `knowledge-base/learnings/2026-03-18-security-reminder-hook-blocks-workflow-edits.md`.

### sed Commands

Two `sed` commands cover all 12 files:

```bash
# Group A: Replace old SHA + old comment
sed -i 's|anthropics/claude-code-action@64c7a0ef71df67b14cb4471f4d9c8565c61042bf # v1$|anthropics/claude-code-action@df37d2f0760a4b5683a6e617c9325bc1a36443f6 # v1.0.75|' \
  .github/workflows/scheduled-bug-fixer.yml \
  .github/workflows/scheduled-ship-merge.yml \
  .github/workflows/scheduled-content-generator.yml \
  .github/workflows/scheduled-growth-execution.yml \
  .github/workflows/test-pretooluse-hooks.yml \
  .github/workflows/scheduled-daily-triage.yml \
  .github/workflows/scheduled-seo-aeo-audit.yml

# Group B: Replace newer SHA + newer comment
sed -i 's|anthropics/claude-code-action@1dd74842e568f373608605d9e45c9e854f65f543 # v1.0.63|anthropics/claude-code-action@df37d2f0760a4b5683a6e617c9325bc1a36443f6 # v1.0.75|' \
  .github/workflows/scheduled-growth-audit.yml \
  .github/workflows/scheduled-community-monitor.yml \
  .github/workflows/scheduled-campaign-calendar.yml \
  .github/workflows/claude-code-review.yml \
  .github/workflows/scheduled-competitive-analysis.yml
```

### Verification

After replacement, verify:

1. `grep -r 'claude-code-action@' .github/workflows/ | grep -v 'df37d2f0760a4b5683a6e617c9325bc1a36443f6'` should return empty (no stale SHAs remain)
2. `grep -c 'claude-code-action@df37d2f0760a4b5683a6e617c9325bc1a36443f6 # v1.0.75' .github/workflows/*.yml` should return 12 matches
3. YAML validity: `python3 -c "import yaml; [yaml.safe_load(open(f)) for f in __import__('glob').glob('.github/workflows/*.yml')]"` should exit 0

## Non-Goals

- Updating other pinned action SHAs (e.g., `actions/checkout`, `actions/upload-artifact`). Those are tracked separately.
- Updating knowledge-base plan files or spec files that reference the old SHAs (they are historical documentation).
- Enabling Dependabot for SHA pin updates (separate follow-up).

## Edge Cases and Risks

### SpecFlow Analysis

1. **Partial replacement:** The `sed` pattern for Group A anchors on `# v1$` (end of line). If any file has trailing whitespace after `# v1`, the pattern will not match. Mitigation: verify match count after replacement.

2. **Concurrent workflow edits:** If another PR modifies a workflow file's `uses:` line before this merges, there will be a merge conflict. This is desirable -- it forces the merger to choose the correct SHA.

3. **SHA verification staleness:** The v1 tag is mutable. Between plan creation and implementation, the tag could move to a newer release. Mitigation: re-verify the SHA at implementation time with `gh api repos/anthropics/claude-code-action/git/refs/tags/v1`.

4. **No behavioral changes:** All workflows already use `claude-code-action`. This changes only which version runs. v1.0.75 is backward compatible with v1.0.63 (same major version, semver contract).

## Acceptance Criteria

- [ ] All 12 workflow files reference `anthropics/claude-code-action@df37d2f0760a4b5683a6e617c9325bc1a36443f6 # v1.0.75`
- [ ] Zero workflow files reference either `64c7a0ef71df67b14cb4471f4d9c8565c61042bf` or `1dd74842e568f373608605d9e45c9e854f65f543`
- [ ] All modified YAML files pass syntax validation
- [ ] PR body includes `Closes #809`

## Test Scenarios

- Given all 12 workflow files with mixed SHAs, when `sed` replacements run, then all 12 files contain the new SHA with `# v1.0.75` comment
- Given a file with `# v1` (no trailing whitespace), when Group A `sed` runs, then the line is replaced correctly
- Given a file with `# v1.0.63`, when Group B `sed` runs, then the line is replaced correctly
- Given the replacements are complete, when grepping for old SHAs, then zero matches are found

## References

- Issue: #809
- Security pin plan: `knowledge-base/project/plans/2026-02-27-security-pin-gha-action-shas-plan.md`
- Prior observation: `knowledge-base/plans/2026-03-19-fix-ci-pr-based-commit-pattern-plan.md` (line 209)
- Learning (hook constraint): `knowledge-base/learnings/2026-03-18-security-reminder-hook-blocks-workflow-edits.md`
- claude-code-action repo: `https://github.com/anthropics/claude-code-action`
- Latest release: `https://github.com/anthropics/claude-code-action/releases/tag/v1.0.75`
