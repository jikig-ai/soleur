# Tasks: fix GITHUB_OUTPUT newline injection

## Phase 1: Core Fix

- 1.1 Replace untrusted `echo "key=..."` with `printf 'key=%s\n'` + `tr -d '\n\r'`
  - 1.1.1 Line 77: `give_up` fallback title (sanitize `$COMMIT_MSG`)
  - 1.1.2 Line 118: PR title from `jq -r '.title'`
  - 1.1.3 Line 119: PR labels from `jq -r` join

## Phase 2: Consistency

- 2.1 Quote all `$GITHUB_OUTPUT` references as `"$GITHUB_OUTPUT"` throughout the workflow file

## Phase 3: Verification

- 3.1 Run compound skill before committing
- 3.2 Verify workflow YAML syntax is valid (basic parse check)
- 3.3 Confirm no behavioral change for clean inputs by reading the final diff
