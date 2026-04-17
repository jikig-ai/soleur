# GitHub Issue Creation for Review Findings

## Label Prerequisite

Before creating the first issue, verify the `code-review` label exists:

```bash
gh label list --search "code-review" --json name --jq '.[0].name // empty'
```

If empty, create it:

```bash
gh label create code-review --description "Finding from code review" --color 0E8A16
```

## Issue Body Template

The body is written to a temporary file and passed via `--body-file` to avoid `$()` command substitution permission prompts and handle arbitrary markdown safely.

**Template content (write to `/tmp/review-finding-NNN.md`):**

```markdown
**Source:** PR #<pr_number> review | **Effort:** <Small|Medium|Large> | **Provenance:** <pr-introduced|pre-existing> | **Re-eval by:** <Phase N | trigger condition>

## Problem

<description>

**Location:** `<file_path>:<line_number>`

## Proposed Fix

<recommended fix>

## Acceptance Criteria

- [ ] <criterion_1>
- [ ] <criterion_2>
```

**Field rules:**

- `Provenance:` is required on every filed issue.
  - `pr-introduced` findings MUST be fixed inline — they should not reach the issue-creation step. If one does reach it, abort the filing and fix inline instead.
  - `pre-existing` findings MUST carry the `pre-existing-unrelated` scope-out criterion in the `## Scope-Out Justification` section.
- `Re-eval by:` is required only when `Provenance: pre-existing`. Value must be either a target phase milestone (e.g., `Phase 4`) or a concrete trigger condition (e.g., `revisit when syncWorkspace lands in #2244`). Open-ended scope-outs with no deadline are prohibited — `/ship` Phase 5.5 will block merge and `code-simplicity-reviewer` will flag the missing deadline at the confirmation gate.

Enforcement is instruction-level (this template) plus the Phase 5.5 exit gate. A pre-commit linter on issue bodies is deferred until violations are actually observed.

## Label Selection

| Review Severity    | Priority Label       | Domain Label          |
|--------------------|----------------------|-----------------------|
| P1 (CRITICAL)      | `priority/p1-high`   | `domain/engineering`  |
| P2 (IMPORTANT)     | `priority/p2-medium` | `domain/engineering`  |
| P3 (NICE-TO-HAVE)  | `priority/p3-low`    | `domain/engineering`  |

Default domain is `domain/engineering`. Override to `domain/product` for agent-native findings that are clearly product-scoped.

Every issue gets the `code-review` label in addition to priority and domain labels.

## Milestone Selection

P1 findings get the current active milestone. P2/P3 findings get `Post-MVP / Later`.

Detect the active milestone:

```bash
gh api repos/:owner/:repo/milestones --jq '[.[] | select(.state=="open") | select(.title | startswith("Phase"))] | sort_by(.due_on) | .[0].title // "Post-MVP / Later"'
```

## Duplicate Detection

Before creating an issue, check if one already exists for this finding from the same PR:

```bash
gh issue list --label code-review --search "review: <description>" --json number,title --jq '.[0].number // empty'
```

If a match exists, skip creation and reference the existing issue in the summary.

## Creation Command

```text
# 1. Write body to temp file (using Write tool, not echo/cat)
# 2. Create issue with --body-file
gh issue create \
  --title "review: <description>" \
  --body-file /tmp/review-finding-NNN.md \
  --label code-review \
  --label priority/p2-medium \
  --label domain/engineering \
  --milestone "Post-MVP / Later"
```

## Error Handling

If `gh issue create` exits non-zero for a finding, log the error and continue to the next finding. Do not block the entire review synthesis on one failed issue creation. Report failed creations in the summary.

## Batch Strategy

For reviews with 15+ findings, create issues sequentially to avoid GitHub API rate limits. For smaller batches, parallel creation via sub-agents is acceptable.

## Execution Strategy

1. Synthesize all findings into categories (P1/P2/P3)
2. Run label prerequisite check
3. Detect active milestone for P1 findings
4. For each finding:
   - Run duplicate detection
   - Write issue body to temp file
   - Create GitHub issue with appropriate labels and milestone
   - Record issue URL for summary
5. Present summary with all created issue URLs

## Severity Values

- `P1` - Critical (blocks merge, security/data issues)
- `P2` - Important (should fix, architectural/performance)
- `P3` - Nice-to-have (enhancements, cleanup)
