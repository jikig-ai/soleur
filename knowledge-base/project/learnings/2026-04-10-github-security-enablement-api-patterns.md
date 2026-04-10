# Learning: GitHub Security Feature Enablement via API

## Problem

Enabling GitHub security features (CodeQL code scanning, secret scanning, push protection, non-provider patterns, validity checks) via the GitHub REST API has several non-obvious failure modes that silently succeed without applying changes.

## Solution

### CodeQL Default Setup

Use `--input -` with a heredoc JSON body, not `--field` for array parameters:

```bash
# WRONG: --field passes arrays as strings
gh api -X PATCH repos/OWNER/REPO/code-scanning/default-setup \
  --field languages='["actions","javascript-typescript","python"]'
# Error: "is not of type array" (HTTP 422)

# CORRECT: use --input with JSON body
gh api -X PATCH repos/OWNER/REPO/code-scanning/default-setup \
  --input - <<'JSONEOF'
{
  "state": "configured",
  "query_suite": "extended",
  "languages": ["actions", "javascript-typescript", "python"],
  "threat_model": "remote_and_local"
}
JSONEOF
```

### Secret Scanning: Repo API vs Org Code Security Configuration

The repo-level PATCH API (`repos/OWNER/REPO`) accepts `secret_scanning` and `secret_scanning_push_protection` but **silently ignores** `secret_scanning_non_provider_patterns` and `secret_scanning_validity_checks`. These return 200 OK but the settings remain disabled.

To enable non-provider patterns and validity checks, use the **org-level code security configuration API**:

```bash
# Requires admin:org OAuth scope
gh api -X POST orgs/ORG/code-security/configurations/ID/attach \
  --input - <<'JSONEOF'
{"scope": "selected", "selected_repository_ids": [REPO_ID]}
JSONEOF
```

The org's "GitHub recommended" configuration (id discoverable via `gh api orgs/ORG/code-security/configurations`) has all features enabled.

### Label Discovery

Always verify labels exist before creating issues with `--label`:

```bash
gh label list --limit 100 --json name --jq '.[].name' | sort
```

## Key Insight

GitHub's REST API has a split-brain for secret scanning features: basic features (scanning + push protection) are repo-level settings, while advanced features (non-provider patterns + validity checks) are org-level code security configurations requiring `admin:org` scope. The repo API silently accepts but ignores the advanced feature parameters — this is a silent failure, not an error.

## Session Errors

1. **CodeQL `--field` array type mismatch** — `gh api --field` wraps values in quotes, turning JSON arrays into strings. Recovery: switched to `--input -` with heredoc. **Prevention:** Always use `--input -` with heredoc for GitHub API calls that include arrays or nested objects.

2. **Secret scanning settings silently ignored** — Repo PATCH API returned 200 but did not apply `non_provider_patterns` or `validity_checks`. Recovery: investigated org-level API, discovered `admin:org` scope requirement. **Prevention:** After any GitHub settings PATCH, immediately re-read the settings to verify the change was applied. Treat 200 OK without state change as a failure.

3. **Org code security config attach: 403 Forbidden** — Current `gh` token has `read:org` but needs `admin:org`. Recovery: documented as pending user action (`gh auth refresh -s admin:org`). **Prevention:** Check `gh auth status` for required scopes before attempting org-level API calls.

4. **Playwright GitHub 404** — Isolated browser has no GitHub session. Recovery: closed browser, fell back to API verification. **Prevention:** For authenticated GitHub pages, check `gh auth status` scope coverage first; only use Playwright if API is insufficient AND browser has an active session.

5. **Label `security` not found** — `gh issue create --label "security"` failed because the label doesn't exist. Recovery: listed labels with `gh label list`, used `domain/engineering`. **Prevention:** Always verify label existence before `gh issue create` with a custom label.

## Tags

category: integration-issues
module: github-api
