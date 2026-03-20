---
title: "fix: add pr_number integer validation to scheduled-ship-merge workflow"
type: fix
date: 2026-03-20
---

# fix: add pr_number integer validation to scheduled-ship-merge workflow

`scheduled-ship-merge.yml` passes the `pr_number` workflow_dispatch input directly to `$GITHUB_OUTPUT` and downstream `gh pr checkout` without validating that it is a positive integer. `scheduled-bug-fixer.yml` already validates its equivalent `issue_number` input with a `^[0-9]+$` regex check (line 79). This inconsistency is a defense-in-depth gap.

## Acceptance Criteria

- [ ] The `Select PR` step in `.github/workflows/scheduled-ship-merge.yml` validates `$OVERRIDE` against `^[0-9]+$` before writing to `$GITHUB_OUTPUT`
- [ ] Invalid input produces a `::error::` annotation and exits with code 1
- [ ] The error message matches the pattern used in `scheduled-bug-fixer.yml` (field name adjusted to `pr_number`)
- [ ] Existing behavior for valid integer input and empty input (auto-select mode) is unchanged

## Test Scenarios

- Given a valid integer override (e.g., `pr_number=42`), when the workflow runs, then PR #42 is selected and shipped normally
- Given an empty override (no `pr_number` input), when the workflow runs, then the auto-select logic picks the oldest qualifying PR (unchanged behavior)
- Given a non-integer override (e.g., `pr_number=abc`), when the workflow runs, then the step fails with `::error::pr_number must be a positive integer, got: abc` and exit code 1
- Given a malicious override (e.g., `pr_number=42; echo pwned`), when the workflow runs, then the step fails with the integer validation error before any shell expansion occurs

## Context

Found during security review of #860. The practical risk is low since `workflow_dispatch` is restricted to collaborators and `gh pr checkout` would reject invalid input, but consistency with `scheduled-bug-fixer.yml` closes the defense-in-depth gap.

## MVP

### .github/workflows/scheduled-ship-merge.yml (Select PR step, lines 67-71)

**Before:**

```yaml
run: |
  if [[ -n "$OVERRIDE" ]]; then
    printf "pr_number=%s" "$OVERRIDE" | tr -d '\n\r' >> "$GITHUB_OUTPUT"
    echo "Override: shipping PR #$OVERRIDE"
    exit 0
  fi
```

**After:**

```yaml
run: |
  if [[ -n "$OVERRIDE" ]]; then
    if [[ ! "$OVERRIDE" =~ ^[0-9]+$ ]]; then
      echo "::error::pr_number must be a positive integer, got: $OVERRIDE"
      exit 1
    fi
    printf "pr_number=%s" "$OVERRIDE" | tr -d '\n\r' >> "$GITHUB_OUTPUT"
    echo "Override: shipping PR #$OVERRIDE"
    exit 0
  fi
```

## References

- Issue: [#870](https://github.com/jikig-ai/soleur/issues/870)
- Reference implementation: `.github/workflows/scheduled-bug-fixer.yml:79-82`
- Security review: #860
