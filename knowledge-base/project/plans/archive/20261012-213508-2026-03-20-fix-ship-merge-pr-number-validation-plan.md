---
title: "fix: add pr_number integer validation to scheduled-ship-merge workflow"
type: fix
date: 2026-03-20
---

# fix: add pr_number integer validation to scheduled-ship-merge workflow

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 4
**Research sources:** repo analysis (3 sibling workflows), 3 institutional learnings, security review

### Key Improvements

1. Confirmed this is the only unvalidated numeric input across all workflow_dispatch workflows in the repo
2. Verified the existing env-indirection pattern (`OVERRIDE: ${{ inputs.pr_number }}`) already follows the project's security convention -- no additional changes needed there
3. Validated that `::error::` annotations work correctly here (runs in a `run:` block on the runner, not via SSH)

### New Considerations Discovered

- The `review-reminder.yml` workflow also validates its override input (date format via `^[0-9]{4}-[0-9]{2}-[0-9]{2}$`), confirming validation-on-override is the established project convention
- The regex `^[0-9]+$` accepts `0` and leading-zero values like `007` -- both are harmless since `gh pr checkout` rejects nonexistent PR numbers, and matching the bug-fixer's exact pattern is more valuable than adding stricter validation

---

`scheduled-ship-merge.yml` passes the `pr_number` workflow_dispatch input directly to `$GITHUB_OUTPUT` and downstream `gh pr checkout` without validating that it is a positive integer. `scheduled-bug-fixer.yml` already validates its equivalent `issue_number` input with a `^[0-9]+$` regex check (line 79). This inconsistency is a defense-in-depth gap.

## Acceptance Criteria

- [x] The `Select PR` step in `.github/workflows/scheduled-ship-merge.yml` validates `$OVERRIDE` against `^[0-9]+$` before writing to `$GITHUB_OUTPUT`
- [x] Invalid input produces a `::error::` annotation and exits with code 1
- [x] The error message matches the pattern used in `scheduled-bug-fixer.yml` (field name adjusted to `pr_number`)
- [x] Existing behavior for valid integer input and empty input (auto-select mode) is unchanged

### Research Insights

**Consistency audit across all workflows:**

All three sibling workflows with override inputs validate before use:

| Workflow | Input | Validation | Status |
|---|---|---|---|
| `scheduled-bug-fixer.yml` | `issue_number` | `^[0-9]+$` regex | Validated (line 79) |
| `review-reminder.yml` | `date_override` | `^[0-9]{4}-[0-9]{2}-[0-9]{2}$` regex | Validated (line 33) |
| `scheduled-ship-merge.yml` | `pr_number` | None | **Gap -- this fix** |

**Security pattern (from institutional learning `github-actions-env-indirection`):**

The workflow already follows the env-indirection pattern correctly -- `OVERRIDE: ${{ inputs.pr_number }}` passes the input through an env var rather than direct `${{ }}` interpolation in the `run:` block. The integer validation adds a second layer of defense-in-depth on top of the env-indirection layer.

**`::error::` annotation validity (from institutional learning `github-actions-error-annotations-require-runner`):**

The `::error::` annotation is appropriate here because this code runs in a `run:` block directly on the GitHub Actions runner (not via SSH or Docker exec). The runner's stdout parser will correctly render it as an error annotation in the Actions UI.

## Test Scenarios

- Given a valid integer override (e.g., `pr_number=42`), when the workflow runs, then PR #42 is selected and shipped normally
- Given an empty override (no `pr_number` input), when the workflow runs, then the auto-select logic picks the oldest qualifying PR (unchanged behavior)
- Given a non-integer override (e.g., `pr_number=abc`), when the workflow runs, then the step fails with `::error::pr_number must be a positive integer, got: abc` and exit code 1
- Given a malicious override (e.g., `pr_number=42; echo pwned`), when the workflow runs, then the step fails with the integer validation error before any shell expansion occurs

### Research Insights

**Edge cases considered and ruled out:**

- `pr_number=0` -- accepted by regex, rejected by `gh pr checkout` ("Could not resolve to a PullRequest"). Adding `^[1-9][0-9]*$` would diverge from the bug-fixer pattern for no practical benefit.
- `pr_number=99999999` -- accepted by regex, rejected by `gh pr checkout`. Same reasoning.
- `pr_number=` (empty string) -- handled by the outer `[[ -n "$OVERRIDE" ]]` check before reaching validation. Not a concern.
- Whitespace-only input -- GitHub's workflow_dispatch UI trims whitespace from string inputs. Even if whitespace reached the regex, `^[0-9]+$` would reject it.

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

### Implementation Notes

- The change is 3 lines inserted between the existing `if [[ -n "$OVERRIDE" ]]` and `printf` lines
- No other steps in the workflow need modification -- the validation fires before the value reaches `$GITHUB_OUTPUT`
- The `Post-run cleanup` step (line 127) uses `${{ steps.select.outputs.pr_number }}` which is only set if validation passes, so downstream steps are unaffected

## References

- Issue: [#870](https://github.com/jikig-ai/soleur/issues/870)
- Reference implementation: `.github/workflows/scheduled-bug-fixer.yml:79-82`
- Security review: #860
- Related learnings:
  - `knowledge-base/project/learnings/2026-03-19-github-actions-env-indirection-for-context-values.md` (env-indirection already applied)
  - `knowledge-base/project/learnings/2026-03-20-github-actions-error-annotations-require-runner.md` (`::error::` valid in `run:` blocks)
