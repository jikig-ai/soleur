# Learning: Use heredoc (not Python) to write GitHub Actions workflow files

## Problem
The `security_reminder_hook` blocks Edit/Write tools on `.github/workflows/*.yml` files. The documented workaround is to use Python via Bash. However, Python's string escaping mangles YAML `${{ }}` expressions containing single quotes (e.g., `${{ inputs.bump_type || '' }}` becomes `${{ inputs.bump_type || '''''' }}`).

## Solution
Use bash heredoc with quoted delimiter (`cat > file << 'EOF'`) instead of Python. The quoted delimiter prevents all shell expansion, so `${{ }}` expressions pass through verbatim.

## Key Insight
Heredoc with `'EOF'` (quoted) is the safest way to write files containing shell-like syntax (`${{ }}`) because it disables all interpolation. Python `write_text()` requires escaping single quotes inside single-quoted strings, which compounds with YAML's own quoting rules.

## Tags
category: build-errors
module: ci
