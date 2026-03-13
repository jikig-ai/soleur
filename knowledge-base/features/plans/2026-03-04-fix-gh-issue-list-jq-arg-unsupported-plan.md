---
title: "fix: inline shell variable in gh issue list jq expression"
type: fix
date: 2026-03-04
---

## Enhancement Summary

**Deepened on:** 2026-03-04
**Sections enhanced:** 4 (Fix Approach, Test Scenarios, Context, Acceptance Criteria)
**Research performed:** gh CLI jq flag behavior, `$ENV` vs quote-unquote-quote approaches, shell injection surface analysis, edge case validation with actual jq binary

### Key Improvements
1. Identified `export` + `$ENV.OPEN_FIXES` as the preferred approach over quote-unquote-quote shell interpolation -- cleaner, no quoting gymnastics, no shell injection surface
2. Validated all edge cases (empty, single value, comma-separated) with actual jq binary execution
3. Identified that the learnings doc must also be updated to prevent the same mistake recurring

### New Considerations Discovered
- `gh` CLI's internal jq (go-jq) supports `$ENV` for reading environment variables, eliminating the need for shell string interpolation entirely
- The `OPEN_FIXES` variable must be `export`ed before the `gh issue list` call since `$ENV` only reads exported environment variables, not shell-local variables

---

# fix: inline shell variable in gh issue list jq expression

The scheduled bug-fixer workflow (`scheduled-bug-fixer.yml`) fails at the "Select issue" step because `gh issue list --jq` does not support jq flags like `--arg`. The `--arg skip "$OPEN_FIXES"` is parsed as unknown positional arguments to `gh issue list`, not forwarded to jq.

**Error from CI run [#22657970844](https://github.com/jikig-ai/soleur/actions/runs/22657970844/job/65671713661):**

```
unknown arguments ["skip" "" "\n ($skip | split(\",\") ..."]
```

## Acceptance Criteria

- [x] The `Select issue` step in `scheduled-bug-fixer.yml` no longer uses `--arg` with `--jq`
- [x] The `OPEN_FIXES` shell variable is exported and accessed via `$ENV.OPEN_FIXES` in the jq expression
- [x] The jq filter logic (split, tonumber, IN exclusion) remains functionally identical
- [x] The learnings doc `knowledge-base/learnings/2026-03-03-scheduled-bot-fix-workflow-patterns.md` is updated to reflect the correct pattern (no `--arg`, use `$ENV`)
- [ ] Workflow runs successfully on `workflow_dispatch` trigger (or at next scheduled run)

## Test Scenarios

- Given `OPEN_FIXES` is empty (`""`), when the jq filter runs, then `split(",")` produces `[""]`, `map(select(length > 0))` filters it to `[]`, and no issues are excluded
- Given `OPEN_FIXES` is `"42,99"`, when the jq filter runs, then issues #42 and #99 are excluded from selection, and the oldest remaining qualifying bug is returned
- Given `OPEN_FIXES` contains a single number `"42"`, when the jq filter runs, then issue #42 is excluded
- Given no qualifying issues exist at any priority, when the step completes, then it prints "No qualifying issues found" and exits 0 (the `// empty` produces no output, which means `ISSUE` is empty)

### Validated Results

All edge cases tested locally with actual `jq` binary:

| `OPEN_FIXES` | Input issues | Expected output | Actual output |
|---|---|---|---|
| `"42,99"` | `[42, 55, 99]` (99 also has bot-fix/attempted) | `55` | `55` |
| `""` | `[42, 55]` | `42` (oldest) | `42` |
| `"42"` | `[42, 55]` | `55` | `55` |

## Context

### Root Cause

`gh` CLI's `--jq` flag (`-q`) accepts a single jq expression string. It does not support passing additional jq flags like `--arg`, `--argjson`, etc. These extra tokens are consumed by `gh`'s own argument parser, which rejects them as unknown arguments.

The `gh issue list --help` output confirms: `--jq expression   Filter JSON output using a jq expression` -- it takes one string argument.

### Fix Approach: `export` + `$ENV` (Preferred)

Two approaches were evaluated:

**Option A: Quote-unquote-quote shell interpolation**
```bash
--jq '("'"$OPEN_FIXES"'" | split(",") | ...'
```
Pros: No code change outside the `--jq` line. Cons: Fragile quoting, potential shell injection if `OPEN_FIXES` ever contains unexpected characters, harder to read.

**Option B: `export` + `$ENV.OPEN_FIXES` (CHOSEN)**
```bash
export OPEN_FIXES
# ...
--jq '
  ($ENV.OPEN_FIXES | split(",") | map(select(length > 0)) | map(tonumber? // empty)) as $skip_nums |
  ...'
```
Pros: Clean separation of shell and jq concerns, no quoting gymnastics, `$ENV` is a standard jq feature, no shell injection surface. Cons: Requires adding `export OPEN_FIXES` after the variable assignment.

**Option B is preferred** because:
1. The jq expression stays in a single-quoted string (no shell expansion inside it)
2. `$ENV` is the standard jq mechanism for reading environment variables
3. `gh` CLI's internal go-jq implementation supports `$ENV` (verified locally)
4. No risk of shell injection -- the variable value never appears in the jq expression string

### Implementation Detail

**Before (broken):**
```yaml
          OPEN_FIXES=$(gh pr list \
            --state open \
            --json headRefName \
            --jq '[.[].headRefName | select(startswith("bot-fix/")) | split("/")[1] | split("-")[0]] | unique | join(",")')
          echo "Issues with open bot-fix PRs: ${OPEN_FIXES:-none}"

          for PRIORITY in priority/p3-low priority/p2-medium priority/p1-high; do
            ISSUE=$(gh issue list \
              --label "$PRIORITY" \
              --label "type/bug" \
              --state open \
              --json number,title,labels,createdAt \
              --jq --arg skip "$OPEN_FIXES" '
                ($skip | split(",") | map(select(length > 0)) | map(tonumber? // empty)) as $skip_nums |
                [.[] | select(
                  (.labels | map(.name) | index("bot-fix/attempted") | not) and
                  (.number | IN($skip_nums[]) | not)
                )] | sort_by(.createdAt) | .[0].number // empty')
```

**After (fixed):**
```yaml
          OPEN_FIXES=$(gh pr list \
            --state open \
            --json headRefName \
            --jq '[.[].headRefName | select(startswith("bot-fix/")) | split("/")[1] | split("-")[0]] | unique | join(",")')
          export OPEN_FIXES
          echo "Issues with open bot-fix PRs: ${OPEN_FIXES:-none}"

          for PRIORITY in priority/p3-low priority/p2-medium priority/p1-high; do
            ISSUE=$(gh issue list \
              --label "$PRIORITY" \
              --label "type/bug" \
              --state open \
              --json number,title,labels,createdAt \
              --jq '
                ($ENV.OPEN_FIXES | split(",") | map(select(length > 0)) | map(tonumber? // empty)) as $skip_nums |
                [.[] | select(
                  (.labels | map(.name) | index("bot-fix/attempted") | not) and
                  (.number | IN($skip_nums[]) | not)
                )] | sort_by(.createdAt) | .[0].number // empty')
```

Key changes:
1. Add `export OPEN_FIXES` after the variable assignment (line after the `gh pr list` call)
2. Remove `--arg skip "$OPEN_FIXES"` from the `--jq` flag
3. Replace `$skip` with `$ENV.OPEN_FIXES` in the jq expression

### Security Note

`OPEN_FIXES` is derived from `gh pr list --jq` output, which produces comma-separated numbers extracted from branch names. It is not user-controlled input. Even so, the `$ENV` approach is safer than shell interpolation because the variable value never appears in the jq expression string -- it's read from the process environment at jq evaluation time.

### Files to Change

1. `.github/workflows/scheduled-bug-fixer.yml` (lines 67-84) -- add `export OPEN_FIXES`, remove `--arg`, use `$ENV.OPEN_FIXES`
2. `knowledge-base/learnings/2026-03-03-scheduled-bot-fix-workflow-patterns.md` (lines 40-46) -- update code example to use `$ENV` pattern and add a note that `gh --jq` does not support `--arg`

### Relevant Learnings Applied

- **`2026-02-21-github-actions-workflow-security-patterns.md`**: Reinforces checking `gh` CLI exit codes and being precise about how `gh` processes arguments. The `--jq` flag's limitation is consistent with `gh`'s argument parsing model.
- **`2026-03-03-scheduled-bot-fix-workflow-patterns.md`**: The source of the broken pattern. Section 3 documents the `--arg` approach which this fix corrects.

## References

- Failed CI run: https://github.com/jikig-ai/soleur/actions/runs/22657970844/job/65671713661
- `gh issue list --help`: `--jq expression` accepts a single expression string, no extra jq flags
- jq `$ENV` documentation: standard jq feature for reading environment variables
- Existing learning: `knowledge-base/learnings/2026-03-03-scheduled-bot-fix-workflow-patterns.md`
