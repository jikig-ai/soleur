---
title: "feat: Enable GitHub Security and Quality"
type: feat
date: 2026-04-10
deepened: 2026-04-10
---

# feat: Enable GitHub Security and Quality

## Enhancement Summary

**Deepened on:** 2026-04-10
**Sections enhanced:** 6
**Research sources:** GitHub REST API (live queries), GitHub docs (CodeQL setup, secret scanning, query suites, supported patterns), project learnings (3 relevant)

### Key Improvements

1. Added `threat_model` recommendation (`remote_and_local`) for GitHub Actions workflow analysis where environment variables and CLI args are common taint sources
2. Added concrete push protection gotcha from project learning -- UX agent placeholder secrets (Stripe keys in .pen files) already triggered push protection on 2026-04-07
3. Added API pagination note for alert triage -- `gh api --paginate` outputs concatenated arrays requiring `jq -s 'add // []'` (constitution rule)
4. Added extended query suite precision tradeoff details and recommendation to start with `extended` and tune down if false positive rate is too high
5. Added secret scanning coverage scope -- 500+ token types, non-provider patterns for private keys and connection strings, validity checks contact providers to verify active secrets
6. Documented current branch protection ruleset (`CI Required`: test, dependency-review, e2e) confirming CodeQL is NOT a required check

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
  --field languages='["actions","javascript-typescript","python"]' \
  --field threat_model=remote_and_local
```

**Why default setup over advanced setup (custom workflow)?**

- Default setup is fully managed by GitHub -- no workflow YAML to maintain
- Automatically runs on push to default branch and on pull requests
- Runs on a weekly schedule for continuous monitoring
- The `extended` query suite includes both security AND quality queries (covering the "code quality findings" requirement)
- The repository has no compiled languages requiring custom build steps
- Can be upgraded to advanced setup later if customization is needed

### Research Insights: CodeQL Configuration

**Query suite selection -- `extended` over `default`:**
The `extended` suite is a superset of `default`, adding queries with "slightly lower precision and severity." This means more findings but also more potential false positives. For a project that values catching code quality issues (not just security), `extended` is the right choice. If false positive noise becomes problematic, downgrade to `default` via the same API call.

**Threat model -- `remote_and_local` recommended:**
The default threat model (`remote`) only considers network requests as taint sources. For this repository, `remote_and_local` is more appropriate because:

- GitHub Actions workflows heavily use environment variables and CLI arguments as data sources
- Shell scripts (81 in the repo) process command-line arguments and environment variables
- The `remote_and_local` model adds "command-line arguments, environment variables, file systems, and databases" as potential tainted data sources
- This catches issues like unsanitized environment variable injection in workflow `run:` blocks

**Language selection:** Include `actions`, `javascript-typescript`, and `python`. Exclude `ruby` since the `.rb` files are only template assets in `plugins/soleur/skills/dspy-ruby/assets/`, not runtime code. The API PATCH endpoint uses combined identifiers (`javascript-typescript`, not separate `javascript` + `typescript`).

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

- **Secret scanning**: Detects secrets in all branches and git history across 500+ token types from major providers (GitHub, AWS, Stripe, Azure, Google Cloud, and hundreds more)
- **Push protection**: Blocks pushes that contain recognized secret patterns (developers can bypass with justification)
- **Non-provider patterns**: Detects generic secrets beyond named providers -- elliptic curve private keys, RSA/SSH/PGP private keys, MongoDB connection strings with credentials, HTTP Bearer tokens, and generic API keys with `-----BEGIN PRIVATE KEY-----` headers
- **Validity checks**: Contacts the issuing provider to verify whether detected secrets are still active, helping prioritize remediation (revoked secrets are lower priority than active ones)

### Research Insights: Secret Scanning Coverage

**Scope:** Secret scanning runs automatically for free on public repos. It scans all Git history across all branches, plus issue/PR descriptions, comments, discussions, and wikis.

**Push protection limitations:** Push protection and validity checks are NOT supported for passwords or most non-provider patterns. They work best for structured secrets from known providers (API keys with recognizable prefixes like `sk_live_`, `AKIA`, `ghp_`).

**Known project gotcha:** On 2026-04-07, the ux-design-lead agent generated a Pencil wireframe containing a realistic Stripe API key placeholder (`sk_live_[REDACTED]`) that triggered push protection and required history rewriting to fix (see `knowledge-base/project/learnings/2026-04-07-ux-agent-placeholder-secrets-trigger-push-protection.md`). This confirms push protection works but highlights that realistic-looking test data in non-code files can trigger false positives.

### 3. Verify and Handle Existing Alerts

After enabling, check for pre-existing alerts from historical commits:

```bash
gh api --paginate repos/jikig-ai/soleur/secret-scanning/alerts | jq -s 'add // []' | jq '.[].secret_type' | sort | uniq -c
gh api --paginate repos/jikig-ai/soleur/code-scanning/alerts | jq -s 'add // []' | jq '.[].rule.id' | sort | uniq -c
```

**Note:** Use `--paginate` with `jq -s 'add // []'` because `gh api --paginate` outputs separate JSON arrays per page (concatenated, not merged). Without the `jq -s` wrapper, multi-page responses produce invalid JSON (constitution rule).

Triage any alerts found:

- **Secret scanning alerts:** For each alert, check validity status. Active secrets must be revoked immediately (follow the procedure in `knowledge-base/project/learnings/2026-02-10-api-key-leaked-in-git-history-cleanup.md`). Revoked secrets can be dismissed as "revoked." False positives (test fixtures, placeholder values) can be dismissed as "false positive."
- **Code scanning alerts:** Review by severity. Critical/high findings need immediate attention. Medium/low findings from the `extended` suite may include code quality suggestions that can be tracked as follow-up issues.

## Technical Considerations

### GitHub Actions Minutes

- CodeQL default setup uses GitHub Actions minutes for analysis
- Public repositories get unlimited Actions minutes
- The weekly schedule auto-disables after 6 months of inactivity (self-managing)

### Developer Experience Impact

- **Push protection** may block pushes containing test fixtures that look like secrets. Developers can bypass with a reason (false positive, used in test, will fix later). Real-world example: on 2026-04-07, a Pencil wireframe file containing `sk_live_` placeholder triggered push protection (learning: `2026-04-07-ux-agent-placeholder-secrets-trigger-push-protection.md`)
- CodeQL annotations appear directly on PR diffs, providing inline feedback
- No additional CI jobs to maintain -- default setup is fully managed
- **Initial scan notification:** Enabling default setup triggers an immediate analysis workflow. Results appear in the Security tab once the first run completes. The tool status page shows timestamps and scan coverage percentages

### Branch Protection Considerations

CodeQL default setup does NOT automatically add itself to required status checks. The current `CI Required` ruleset (id: 14145388) requires three checks: `test`, `dependency-review`, and `e2e`. CodeQL is not in this list.

For initial rollout, keep CodeQL advisory-only (non-blocking) to avoid disrupting existing workflows. After running for a few weeks and confirming a low false-positive rate, consider adding the CodeQL check to the ruleset via:

```bash
gh api -X PUT repos/jikig-ai/soleur/rulesets/14145388 \
  --field 'rules[0].parameters.required_status_checks[3].context=CodeQL' \
  --field 'rules[0].parameters.required_status_checks[3].integration_id=15368'
```

**Sharp edge:** If CodeQL is added as a required check, every PR will need a passing CodeQL analysis. Since default setup only runs on push to the default branch and on PRs, this should work. But if the analysis fails (timeout, infrastructure issue), it will block all merges. Keep it advisory until confidence is established.

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

- [ ] CodeQL default setup is configured with `extended` query suite for `actions`, `javascript-typescript`, and `python` with `remote_and_local` threat model
- [ ] CodeQL initial analysis completes successfully (check via API: `gh api repos/jikig-ai/soleur/code-scanning/default-setup --jq .state` returns `configured` and `updated_at` is non-null)
- [ ] Secret scanning is enabled (`status: enabled`)
- [ ] Secret scanning push protection is enabled (`status: enabled`)
- [ ] Secret scanning non-provider patterns is enabled (`status: enabled`)
- [ ] Secret scanning validity checks is enabled (`status: enabled`)
- [ ] Any pre-existing secret scanning alerts are triaged (revoked or dismissed)
- [ ] Any pre-existing code scanning alerts are reviewed
- [ ] GitHub Security tab shows all three features as active

## Test Scenarios

- Given CodeQL default setup is configured, when checking setup status via API, then state is `configured`, languages include `actions`, `javascript-typescript`, `python`, query_suite is `extended`, and threat_model is `remote_and_local`
- Given secret scanning is enabled, when checking repository settings via API, then `secret_scanning.status` is `enabled`
- Given push protection is enabled, when checking repository settings via API, then `secret_scanning_push_protection.status` is `enabled`
- Given CodeQL has run, when listing code scanning alerts via API, then the endpoint returns 200 (not 404 "no analysis found")
- Given all features are enabled, when viewing the GitHub Security tab in a browser, then code scanning, secret scanning, and code quality sections are visible and active

**API verification commands:**

- **CodeQL status:** `gh api repos/jikig-ai/soleur/code-scanning/default-setup --jq '{state, languages, query_suite, threat_model, updated_at}'`
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
| CodeQL initial scan surfaces many alerts | Medium | Low | Triage systematically; `extended` suite has slightly lower precision -- downgrade to `default` if false positive rate is too high |
| Push protection blocks legitimate pushes | Medium | Low | Already happened on 2026-04-07 (Stripe placeholder in .pen file). Developers bypass with reason; add pre-push grep for common API key patterns in non-code files |
| Secret scanning finds historical secrets | Medium | Medium | Follow revoke-and-cleanup procedure from 2026-02-10 learning; validity checks help prioritize (active > revoked) |
| API calls require admin permissions | Low | Low | Current `gh` token has admin access (verified via `gh api repos/jikig-ai/soleur --jq .permissions`) |
| `remote_and_local` threat model produces more findings than `remote` | Medium | Low | Local sources (env vars, CLI args) are common in this repo's shell scripts; findings are more relevant, not noise |

## References and Research

### Internal References

- Secret leak learning: `knowledge-base/project/learnings/2026-02-10-api-key-leaked-in-git-history-cleanup.md`
- Push protection gotcha: `knowledge-base/project/learnings/2026-04-07-ux-agent-placeholder-secrets-trigger-push-protection.md`
- Actions workflow security patterns: `knowledge-base/project/learnings/2026-02-21-github-actions-workflow-security-patterns.md`
- Security agent output policy: `knowledge-base/project/learnings/2026-02-16-inline-only-output-for-security-agents.md`
- Existing dependency review: `.github/workflows/dependency-review.yml`
- CI workflow: `.github/workflows/ci.yml`
- CI Required ruleset (id: 14145388): requires `test`, `dependency-review`, `e2e`

### External References

- [CodeQL default setup docs](https://docs.github.com/en/code-security/code-scanning/enabling-code-scanning/configuring-default-setup-for-code-scanning)
- [Secret scanning docs](https://docs.github.com/en/code-security/secret-scanning/introduction/about-secret-scanning)
- [Code scanning default setup API](https://docs.github.com/en/rest/code-scanning/code-scanning#update-a-code-scanning-default-setup-configuration-for-a-repository)
- [Repository security settings API](https://docs.github.com/en/rest/repos/repos#update-a-repository)

### Related Issues

- Closes #1874
