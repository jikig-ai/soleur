# Learning: GitHub Actions env indirection for context values

## Problem

GitHub Actions `${{ github.base_ref }}` and similar context values interpolated directly in `run:` blocks create script injection vulnerabilities. Even values like `base_ref` that seem safe (must be an existing branch) can contain shell metacharacters if an attacker creates a specially-named branch.

## Solution

Pass all `${{ }}` expressions through `env:` blocks instead of direct interpolation in `run:` scripts:

```yaml
# UNSAFE - direct interpolation
run: git diff origin/${{ github.base_ref }}...HEAD

# SAFE - env indirection
env:
  BASE_REF: ${{ github.base_ref }}
run: git diff "origin/${BASE_REF}...HEAD"
```

When the value flows through an environment variable, bash treats it as data, not code. Double-quoting the expansion prevents word splitting and glob expansion.

## Key Insight

The repo already follows this pattern in `version-bump-and-release.yml` and `reusable-release.yml`. The security-sentinel review agent caught the inconsistency. All new workflows should use env indirection for ALL `${{ }}` expressions in `run:` blocks, even seemingly safe ones like `github.event_name`, for consistency and defense-in-depth.

## Tags

category: security-issues
module: ci
