---
title: "feat: Enable GitHub Security and Quality"
type: feat
date: 2026-04-10
---

# feat: Enable GitHub Security and Quality

## Overview

Enable the three GitHub Security features currently disabled on the `jikig-ai/soleur` repository: code scanning alerts (via CodeQL), secret scanning alerts, and code quality findings. These features provide automated vulnerability detection, leaked credential alerting, and code quality analysis directly in the GitHub Security tab.

## Problem Statement / Motivation

The repository currently has:

- **Code scanning**: Not configured (no CodeQL analysis running)
- **Secret scanning**: Disabled (including push protection, non-provider patterns, and validity checks)
- **Code quality findings**: Not enabled (dependent on CodeQL being active)

This is a gap for a public repository that already had a [secret leak incident](../learnings/2026-02-10-api-key-leaked-in-git-history-cleanup.md) requiring full history rewrite. Enabling these features provides:

1. **Proactive vulnerability detection** -- CodeQL identifies security issues (XSS, injection, path traversal) in TypeScript, JavaScript, Python, and GitHub Actions workflows before they reach production
2. **Secret leak prevention** -- Secret scanning alerts on committed secrets; push protection blocks secrets at push time before they enter history
3. **Code quality signals** -- CodeQL quality queries catch bugs, dead code, and anti-patterns

The repository is public, so all three features are available at no cost.

## Proposed Solution

Use a two-pronged approach:

### 1. Enable CodeQL via Default Setup (API)

GitHub's CodeQL default setup is the recommended approach for repositories without custom build requirements. The repository's detected languages are: `actions`, `javascript-typescript`, `python`, `ruby`.

Enable via the REST API:

```bash
gh api -X PATCH repos/jikig-ai/soleur/code-scanning/default-setup \
  --field state=configured \
  --field query_suite=extended \
  --field languages='["actions","javascript-typescript","python"]'
```

**Why default setup over advanced setup (custom workflow)?**

- Default setup is fully managed by GitHub -- no workflow YAML to maintain
- Automatically runs on push to default branch and on pull requests
- Runs on a weekly schedule for continuous monitoring
- The `extended` query suite includes both security AND quality queries (covering the "code quality findings" requirement)
- The repository has no compiled languages requiring custom build steps
- Can be upgraded to advanced setup later if customization is needed

**Language selection:** Include `actions`, `javascript-typescript`, and `python`. Exclude `ruby` since the `.rb` files are only template assets in `plugins/soleur/skills/dspy-ruby/assets/`, not runtime code.

### 2. Enable Secret Scanning via Repository Settings API

Enable all secret scanning features via a single API call:

```bash
gh api -X PATCH repos/jikig-ai/soleur \
  --input - <<'JSONEOF'
{
  "security_and_analysis": {
    "secret_scanning": { "status": "enabled" },
    "secret_scanning_push_protection": { "status": "enabled" },
    "secret_scanning_non_provider_patterns": { "status": "enabled" },
    "secret_scanning_validity_checks": { "status": "enabled" }
  }
}
JSONEOF
```

This enables:

- **Secret scanning**: Detects secrets in all branches and git history
- **Push protection**: Blocks pushes that contain recognized secret patterns (developers can bypass with justification)
- **Non-provider patterns**: Detects generic secrets (private keys, connection strings) beyond named provider patterns
- **Validity checks**: Verifies with providers whether detected secrets are still active

### 3. Verify and Handle Existing Alerts

After enabling, check for pre-existing alerts from historical commits:

```bash
gh api repos/jikig-ai/soleur/secret-scanning/alerts --jq '.[].secret_type' | sort | uniq -c
gh api repos/jikig-ai/soleur/code-scanning/alerts --jq '.[].rule.id' | sort | uniq -c
```

Triage any alerts found -- dismiss false positives, revoke real secrets.

## Technical Considerations

### GitHub Actions Minutes

- CodeQL default setup uses GitHub Actions minutes for analysis
- Public repositories get unlimited Actions minutes
- The weekly schedule auto-disables after 6 months of inactivity (self-managing)

### Developer Experience Impact

- **Push protection** may block pushes containing test fixtures that look like secrets. Developers can bypass with a reason (false positive, used in test, will fix later)
- CodeQL annotations appear directly on PR diffs, providing inline feedback
- No additional CI jobs to maintain -- default setup is fully managed

### Branch Protection Considerations

CodeQL default setup does NOT automatically add itself to required status checks. If branch protection rules should require CodeQL to pass before merge, that must be configured separately. For initial rollout, keep it advisory-only (non-blocking) to avoid disrupting existing workflows.

### Existing Security Tooling

The repository already has:

- `dependency-review.yml` -- Reviews dependency changes on PRs for known vulnerabilities
- Dependabot security updates -- Enabled, auto-creates PRs for vulnerable dependencies
- `.gitignore` entries for sensitive files (added after the 2026-02-10 secret leak)

CodeQL and secret scanning complement these tools without overlap:

- Dependency review catches vulnerable *dependencies*; CodeQL catches vulnerable *code*
- Dependabot updates *existing* vulnerable deps; CodeQL finds *new* vulnerabilities in first-party code
- `.gitignore` prevents *future* commits of secrets; secret scanning catches *historical* and *missed* secrets

## Acceptance Criteria

- [ ] CodeQL default setup is configured with `extended` query suite for `actions`, `javascript-typescript`, and `python`
- [ ] CodeQL initial analysis completes successfully (check via API: `gh api repos/jikig-ai/soleur/code-scanning/default-setup --jq .state` returns `configured`)
- [ ] Secret scanning is enabled (`status: enabled`)
- [ ] Secret scanning push protection is enabled (`status: enabled`)
- [ ] Secret scanning non-provider patterns is enabled (`status: enabled`)
- [ ] Secret scanning validity checks is enabled (`status: enabled`)
- [ ] Any pre-existing secret scanning alerts are triaged (revoked or dismissed)
- [ ] Any pre-existing code scanning alerts are reviewed
- [ ] GitHub Security tab shows all three features as active

## Test Scenarios

- Given CodeQL default setup is configured, when checking setup status via API, then state is `configured` and languages include `actions`, `javascript-typescript`, `python`
- Given secret scanning is enabled, when checking repository settings via API, then `secret_scanning.status` is `enabled`
- Given push protection is enabled, when checking repository settings via API, then `secret_scanning_push_protection.status` is `enabled`
- Given CodeQL has run, when listing code scanning alerts via API, then the endpoint returns 200 (not 404 "no analysis found")
- Given all features are enabled, when viewing the GitHub Security tab in a browser, then code scanning, secret scanning, and code quality sections are visible and active

**API verification commands:**

- **CodeQL status:** `gh api repos/jikig-ai/soleur/code-scanning/default-setup --jq '{state, languages, query_suite}'`
- **Secret scanning status:** `gh api repos/jikig-ai/soleur --jq '.security_and_analysis | {secret_scanning: .secret_scanning.status, push_protection: .secret_scanning_push_protection.status, non_provider: .secret_scanning_non_provider_patterns.status, validity: .secret_scanning_validity_checks.status}'`
- **Code scanning alerts:** `gh api repos/jikig-ai/soleur/code-scanning/alerts --jq 'length'`
- **Secret scanning alerts:** `gh api repos/jikig-ai/soleur/secret-scanning/alerts --jq 'length'`

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Low architectural impact. This is standard DevOps security hygiene -- enabling GitHub's built-in scanning features via API calls. No code changes to the application. The only workflow artifact is CodeQL's managed default setup (no custom workflow YAML). The `extended` query suite is appropriate for catching both security vulnerabilities and code quality issues. No infrastructure or Terraform changes needed.

## Dependencies and Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| CodeQL initial scan surfaces many alerts | Medium | Low | Triage systematically; quality alerts are advisory |
| Push protection blocks legitimate pushes | Low | Low | Developers can bypass with reason; tune if noisy |
| Secret scanning finds historical secrets | Medium | Medium | Follow the existing revoke-and-cleanup procedure from the 2026-02-10 learning |
| API calls require admin permissions | Low | Low | Current `gh` token has admin access (verified) |

## References and Research

### Internal References

- Secret leak learning: `knowledge-base/project/learnings/2026-02-10-api-key-leaked-in-git-history-cleanup.md`
- Existing dependency review: `.github/workflows/dependency-review.yml`
- CI workflow: `.github/workflows/ci.yml`

### External References

- [CodeQL default setup docs](https://docs.github.com/en/code-security/code-scanning/enabling-code-scanning/configuring-default-setup-for-code-scanning)
- [Secret scanning docs](https://docs.github.com/en/code-security/secret-scanning/introduction/about-secret-scanning)
- [Code scanning default setup API](https://docs.github.com/en/rest/code-scanning/code-scanning#update-a-code-scanning-default-setup-configuration-for-a-repository)
- [Repository security settings API](https://docs.github.com/en/rest/repos/repos#update-a-repository)

### Related Issues

- Closes #1874
