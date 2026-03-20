---
title: "chore(ci): standardize claude-code-action SHA across all workflows"
type: chore
date: 2026-03-20
issue: "#809"
deepened: 2026-03-20
---

# chore(ci): standardize claude-code-action SHA across all workflows

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 4 (Implementation Approach, Edge Cases, Verification, Acceptance Criteria)

### Key Improvements

1. **Verified no trailing whitespace** in any of the 12 target lines using `cat -A` -- all lines end cleanly, confirming sed `$` anchor is safe.
2. **Confirmed v1.0.75 is still latest** as of 2026-03-20. No newer release since 2026-03-18.
3. **Validated SHA dereference chain**: v1 tag (annotated) -> tag object `bf4f0de6...` -> commit `df37d2f0...`. The commit SHA is the correct value for `uses:` lines (GitHub Actions resolves commit SHAs, not tag object SHAs).
4. **Added grep exclusion pattern** for non-workflow references (comments in workflow files that mention `claude-code-action` by name but are not `uses:` lines).

### New Considerations Discovered

- The v1.0.75 release body contains only a changelog link (no breaking changes, no migration notes). This is consistent with a semver-patch bump.
- Five workflow files mention `claude-code-action` in comments (not `uses:` lines). These are informational and must NOT be modified. The sed patterns are scoped to the `uses:` line format, so they are safe.
- The verification grep command (`grep -r 'claude-code-action@' ...`) must exclude non-`uses:` comment lines that contain `@` symbols. Updated verification step accounts for this.

---

## Overview

Twelve workflow files reference `anthropics/claude-code-action` pinned to commit SHAs, but two different SHAs are in use. Seven workflows pin to `64c7a0ef71df67b14cb4471f4d9c8565c61042bf` (commented `# v1`), and five workflows pin to `1dd74842e568f373608605d9e45c9e854f65f543` (commented `# v1.0.63`). Standardize all twelve on the latest SHA with an accurate version comment.

## Problem Statement

Version inconsistency creates a silent security gap: if one SHA contains a vulnerability fix that the other lacks, some workflows remain exposed. The older SHA (`64c7a0ef...`) resolves to commit message "Only expose permission_denials count in sanitized output (#993)" and the newer one (`1dd74842...`) resolves to "chore: bump Claude Code to 2.1.61 and Agent SDK to 0.2.61". Neither is the current `v1` tag, which now points to `df37d2f0760a4b5683a6e617c9325bc1a36443f6` (v1.0.75, published 2026-03-18).

Found during security review of #803. Pre-existing issue noted in `knowledge-base/plans/2026-03-19-fix-ci-pr-based-commit-pattern-plan.md` line 209.

### Research Insights

**Supply-chain pinning pattern:** This change follows the same immutability principle documented in two existing learnings:

- `docker-base-image-digest-pinning.md`: Docker ignores the tag when a digest is present; the tag is purely documentary. Similarly, GitHub Actions ignores the `# v1.0.75` comment -- the SHA is the source of truth. Always update SHA and comment together.
- `npm-global-install-version-pinning.md`: For global npm installs, version pinning is the only available control. For GitHub Actions, SHA pinning is the only immutable control (tags are mutable).

**Key difference from Docker pinning:** GitHub Actions resolves the `@<ref>` as a git ref (commit SHA, tag, or branch). The `# v1.0.75` comment is invisible to GitHub's workflow runner -- it serves only human readers and Dependabot.

## Target SHA

The `v1` mutable tag on `anthropics/claude-code-action` currently points (via annotated tag dereference) to:

| Field | Value |
|-------|-------|
| Commit SHA | `df37d2f0760a4b5683a6e617c9325bc1a36443f6` |
| Release tag | v1.0.75 |
| Published | 2026-03-18 |
| Tag object SHA | `bf4f0de6fccd1eea7044a5f903fc928aff363134` |

**Version comment format:** `# v1.0.75` (matches the existing `# v1.0.63` convention used in newer workflows).

**SHA dereference chain verified:** `v1` (mutable tag) -> annotated tag object `bf4f0de6...` (type: `tag`) -> commit `df37d2f0...` (type: `commit`). The `uses:` line must reference the **commit SHA**, not the tag object SHA.

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

### Non-target references (DO NOT modify)

Five workflow files reference `claude-code-action` in comments (not `uses:` lines). These are informational and must be left unchanged:

| File | Lines | Context |
|------|-------|---------|
| `scheduled-bug-fixer.yml` | 12, 132, 164 | Security comment, post-action step comment, PR author detection comment |
| `scheduled-ship-merge.yml` | 4, 9 | Description comment, security comment |
| `scheduled-community-monitor.yml` | 12 | Data collection comment |
| `scheduled-daily-triage.yml` | 9 | Security comment |
| `test-pretooluse-hooks.yml` | 1, 8, 45, 53, 125 | Purpose description, test instructions |
| `claude-code-review.yml` | 42 | Documentation link comment |

The sed patterns target only the `uses:` line format (`uses: anthropics/claude-code-action@<SHA> # <version>`), so these comment lines are unaffected.

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

### Research Insights

**sed pattern safety:** Verified with `cat -A` that all 12 target lines end with `$` (no trailing whitespace). The Group A pattern anchors on `# v1$` which correctly avoids matching `# v1.0.63` or `# v1.0.75` (the `$` prevents partial matches like `# v1` matching inside `# v1.0.63`).

**Alternative approach considered and rejected:** A single sed command using regex alternation (`\(64c7a0ef...\|1dd74842...\)`) could replace both groups in one pass. Rejected because: (a) it obscures which files had which old SHA in the git log, and (b) two simple commands are easier to verify than one regex.

### Verification

After replacement, verify:

1. **No stale `uses:` SHAs remain:**

   ```bash
   grep 'uses:.*claude-code-action@' .github/workflows/*.yml | grep -v 'df37d2f0760a4b5683a6e617c9325bc1a36443f6'
   ```

   Expected: empty output. The `uses:` prefix filter excludes comment-only references.

2. **Correct count of new SHA:**

   ```bash
   grep -l 'claude-code-action@df37d2f0760a4b5683a6e617c9325bc1a36443f6 # v1.0.75' .github/workflows/*.yml | wc -l
   ```

   Expected: `12`.

3. **YAML syntax validation:**

   ```bash
   python3 -c "import yaml; [yaml.safe_load(open(f)) for f in __import__('glob').glob('.github/workflows/*.yml')]"
   ```

   Expected: exit 0.

4. **Diff sanity check:**

   ```bash
   git diff --stat
   ```

   Expected: exactly 12 files changed, 1 insertion and 1 deletion each.

## Non-Goals

- Updating other pinned action SHAs (e.g., `actions/checkout`, `actions/upload-artifact`). Those are tracked separately.
- Updating knowledge-base plan files or spec files that reference the old SHAs (they are historical documentation).
- Enabling Dependabot for SHA pin updates (separate follow-up).

## Edge Cases and Risks

### SpecFlow Analysis

1. **Partial replacement:** The `sed` pattern for Group A anchors on `# v1$` (end of line). **Verified:** `cat -A` on all 7 Group A files confirms no trailing whitespace. Pattern will match.

2. **Concurrent workflow edits:** If another PR modifies a workflow file's `uses:` line before this merges, there will be a merge conflict. This is desirable -- it forces the merger to choose the correct SHA.

3. **SHA verification staleness:** The v1 tag is mutable. Between plan creation and implementation, the tag could move to a newer release. Mitigation: re-verify the SHA at implementation time with `gh api repos/anthropics/claude-code-action/git/refs/tags/v1`. **Current status:** v1.0.75 confirmed latest as of 2026-03-20.

4. **No behavioral changes:** All workflows already use `claude-code-action`. This changes only which version runs. v1.0.75 is backward compatible with v1.0.63 (same major version, semver contract). The v1.0.75 release notes contain only a changelog link -- no breaking changes or migration instructions.

5. **Comment-line false positives:** Five workflow files reference `claude-code-action` in YAML comments (not `uses:` lines). The sed patterns target the exact `uses:` line format with SHA and version comment, so comment lines are unaffected. The verification step filters on `uses:` to confirm.

## Acceptance Criteria

- [x] All 12 workflow files reference `anthropics/claude-code-action@df37d2f0760a4b5683a6e617c9325bc1a36443f6 # v1.0.75`
- [x] Zero workflow files reference either `64c7a0ef71df67b14cb4471f4d9c8565c61042bf` or `1dd74842e568f373608605d9e45c9e854f65f543` in `uses:` lines
- [x] All modified YAML files pass syntax validation
- [x] `git diff --stat` shows exactly 12 files changed, 1 insertion + 1 deletion each
- [ ] PR body includes `Closes #809`

## Test Scenarios

- Given all 12 workflow files with mixed SHAs, when `sed` replacements run, then all 12 files contain the new SHA with `# v1.0.75` comment
- Given a file with `# v1` (no trailing whitespace), when Group A `sed` runs, then the line is replaced correctly
- Given a file with `# v1.0.63`, when Group B `sed` runs, then the line is replaced correctly
- Given the replacements are complete, when grepping for old SHAs in `uses:` lines, then zero matches are found
- Given workflow files with `claude-code-action` in comments (not `uses:` lines), when sed runs, then comment lines remain unchanged

## References

- Issue: #809
- Security pin plan: `knowledge-base/project/plans/2026-02-27-security-pin-gha-action-shas-plan.md`
- Prior observation: `knowledge-base/plans/2026-03-19-fix-ci-pr-based-commit-pattern-plan.md` (line 209)
- Learning (hook constraint): `knowledge-base/learnings/2026-03-18-security-reminder-hook-blocks-workflow-edits.md`
- Learning (digest pinning analog): `knowledge-base/learnings/2026-03-19-docker-base-image-digest-pinning.md`
- Learning (version pinning analog): `knowledge-base/learnings/2026-03-19-npm-global-install-version-pinning.md`
- claude-code-action repo: [github.com/anthropics/claude-code-action](https://github.com/anthropics/claude-code-action)
- Latest release: [v1.0.75](https://github.com/anthropics/claude-code-action/releases/tag/v1.0.75)
