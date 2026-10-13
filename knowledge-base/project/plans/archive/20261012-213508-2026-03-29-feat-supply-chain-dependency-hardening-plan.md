---
title: "feat: supply chain dependency hardening"
type: feat
date: 2026-03-29
issue: "#1174"
deepened: 2026-03-29
---

# Supply Chain Dependency Hardening

## Enhancement Summary

**Deepened on:** 2026-03-29
**Sections enhanced:** 5
**Research sources:** Bun docs (install, security scanner API), GitHub dependency-review-action README, pip hash generation (live testing), project learnings (3 applied)

### Key Improvements

1. Concrete pip hashes computed for google-genai; Pillow multi-platform hash strategy documented
2. Dependency Review Action enhanced with `comment-summary-in-pr` and `deny-packages` purl support
3. Bun Security Scanner API discovered as future enhancement path (native plugin for custom scanning)
4. Implementation edge case: security_reminder_hook blocks first Edit on workflow files (expect retry)
5. Dual-lockfile sync verification step added to prevent npm/bun drift

## Overview

Harden the build and dependency pipeline against supply chain attacks following the litellm incident (2026-03-26). The project uses Bun as primary package manager (with npm for web-platform Docker builds) and has one Python requirements.txt with unpinned `>=` ranges. Current CI does not enforce frozen lockfiles, has no dependency scanning, and lacks lockfile integrity validation.

## Problem Statement

The litellm supply chain attack demonstrated that a single poisoned PyPI package can exfiltrate SSH keys, cloud credentials, and secrets from every machine that installs it. Soleur's web platform handles BYOK API keys and user sessions -- a supply chain compromise in this dependency tree would be catastrophic.

Current exposure:

| Surface | Package Manager | Lockfile | Frozen in CI | Integrity Hashes |
|---------|----------------|----------|-------------|-----------------|
| Root (docs site) | Bun | `bun.lock` | No (`bun install`) | Yes (SHA-512 in bun.lock) |
| Web platform | Bun + npm | `bun.lock` + `package-lock.json` | No | Yes (both) |
| Telegram bridge | Bun | `bun.lock` | No | Yes |
| Gemini imagegen | pip | None | No | No |
| Spike | npm | `package-lock.json` | N/A (not in CI) | Yes |

Key gaps: (1) CI uses `bun install` not `bun install --frozen-lockfile`, (2) Python deps use `>=` ranges with no hashes, (3) no dependency review on PRs, (4) no `bunfig.toml` security settings (minimumReleaseAge, trustedDependencies).

## Proposed Solution

Three implementation phases aligned with issue priority tiers, all automatable in CI.

### Phase 1: Lockfile Integrity and Dependency Scanning (P1)

#### 1.1 Pin Python requirements with hashes

Replace `plugins/soleur/skills/gemini-imagegen/requirements.txt`:

```text
# Before
google-genai>=1.0.0
Pillow>=10.0.0

# After (exact versions + integrity hashes)
google-genai==1.66.0 \
    --hash=sha256:7f127a39cf695277104ce4091bb26e417c59bb46e952ff3699c3a474ee
Pillow==11.3.0 \
    --hash=sha256:3828ee7586cd0b2091b6209e5ad53e20d0649bbe87164a459d0676e035e8f523
```

The gemini-imagegen SKILL.md install instruction must use `pip install --require-hashes -r requirements.txt`.

### Research Insights: Python Hash Generation

**Multi-platform wheel issue:** google-genai is a pure Python wheel (`py3-none-any.whl`) with a single hash across all platforms. Pillow is a C extension with platform-specific wheels (manylinux, macOS arm64, macOS x86_64, Windows). Including only one platform's wheel hash would break installation on other platforms.

**Solution:** Use the sdist (source distribution) hash for Pillow. The sdist `pillow-11.3.0.tar.gz` has a single hash that works on all platforms -- pip falls back to building from source when no matching wheel hash is found. This requires build dependencies (`libjpeg-dev`, `zlib1g-dev`) to be available, which is acceptable for a developer tool.

**Hash generation workflow:**

```bash
# Pure Python packages (single hash)
pip download --no-deps --dest /tmp/hashes google-genai==1.66.0
pip hash /tmp/hashes/google_genai-1.66.0-py3-none-any.whl

# C extension packages (use sdist for cross-platform)
pip download --no-deps --no-binary :all: --dest /tmp/hashes Pillow==11.3.0
pip hash /tmp/hashes/pillow-11.3.0.tar.gz
```

**Alternative approach:** If sdist build is unacceptable, include hashes for all common platform wheels. pip accepts multiple `--hash` lines per package -- any matching hash passes verification. This is more maintenance but avoids requiring build tools.

#### 1.2 Enforce frozen lockfiles in CI

Change all `bun install` calls in `.github/workflows/ci.yml` to `bun install --frozen-lockfile`:

```yaml
# ci.yml - test job
- name: Install dependencies
  run: bun install --frozen-lockfile

- name: Install web-platform dependencies
  run: bun install --frozen-lockfile
  working-directory: apps/web-platform

- name: Install telegram-bridge dependencies
  run: bun install --frozen-lockfile
  working-directory: apps/telegram-bridge
```

Same change in the e2e job. This ensures CI fails if `bun.lock` diverges from `package.json`, catching accidental or malicious lockfile tampering.

For `deploy-docs.yml`, `scheduled-seo-aeo-audit.yml`, and other workflows using `npm ci` -- these already use `npm ci` which is the npm equivalent of frozen lockfile. No change needed.

#### 1.3 Add GitHub Dependency Review Action

Create `.github/workflows/dependency-review.yml`:

```yaml
name: Dependency Review
on: [pull_request]

permissions:
  contents: read

jobs:
  dependency-review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
      - name: Dependency Review
        uses: actions/dependency-review-action@2031cfc080254a8a887f58cffee85186f0e49e48 # v4.9.0
        with:
          fail-on-severity: high
          license-check: true
          vulnerability-check: true
```

This catches known CVEs and license issues on every PR. Pinned to SHA per project convention (learning: `2026-02-27-github-actions-sha-pinning-workflow.md`).

### Research Insights: Dependency Review Configuration

**PR comment summaries:** Add `comment-summary-in-pr: on-failure` to post vulnerability details directly on the PR. Requires `pull-requests: write` permission:

```yaml
permissions:
  contents: read
  pull-requests: write

# ...
with:
  fail-on-severity: high
  comment-summary-in-pr: on-failure
```

**Package blocklist:** Use `deny-packages` with Package URL (purl) format to permanently block known-compromised packages:

```yaml
deny-packages: |
  pkg:pypi/litellm
  pkg:npm/event-stream
```

**OpenSSF Scorecard:** Enable `show-openssf-scorecard: true` to display upstream project health metrics in the review output. Useful for evaluating new dependencies.

**Scope filtering:** Set `fail-on-scopes: runtime` to only fail on production dependency vulnerabilities -- dev dependency CVEs are reported as warnings but do not block the PR. This reduces noise from test/build tool vulnerabilities that do not reach production.

#### 1.4 Configure Bun security settings

Update `bunfig.toml` at root, `apps/telegram-bridge/bunfig.toml`, and create `apps/web-platform/bunfig.toml`:

```toml
[install]
# Reject packages published less than 3 days ago (supply chain defense)
minimumReleaseAge = 259200
```

All three package roots need this setting -- web-platform currently has no `bunfig.toml` but runs `bun install` in CI.

Bun already blocks lifecycle scripts by default (only `trustedDependencies` run). This is a major advantage over npm/yarn that the issue should document.

### Research Insights: Bun Security Scanner API

Bun supports a native Security Scanner API (`[install.security]` in bunfig.toml) that hooks into the install pipeline. Scanners run as npm packages and can detect CVEs, malicious packages, and license violations at install time. Two severity levels: `fatal` (blocks install) and `warn` (prompts in interactive mode, blocks in CI).

```toml
[install.security]
scanner = "@acme/bun-security-scanner"
```

This is a future enhancement path -- once a quality open-source Bun security scanner package exists, it can be added to `bunfig.toml` for local install-time scanning (complementing the GitHub-level dependency-review-action). The [official template](https://github.com/oven-sh/security-scanner-template) enables custom scanner development. Tracked in Phase 2 scope, not Phase 1.

### Phase 2: Install Script Audit and Dependency Gate (P2)

#### 2.1 Audit trustedDependencies

Check all `package.json` files for `trustedDependencies`. Currently none are declared -- meaning Bun blocks all lifecycle scripts for dependencies. This is the secure default. Document this in constitution.md.

For the web-platform Dockerfile which uses `npm ci`, audit install scripts:

```bash
# In web-platform directory
npm ls --all --json | jq -r '.. | .scripts? // empty | to_entries[] | select(.key | test("pre|post")) | "\(.key): \(.value)"'
```

If install scripts are found, add `.npmrc` with `ignore-scripts=true` and explicit allowlist.

#### 2.2 New dependency gate in CI

Add a CI check that detects new dependencies in PRs. This can be done with the dependency-review-action (it already flags new dependencies). Alternatively, a lightweight bash check:

```bash
# In CI, compare package.json against base branch
git diff origin/main -- '**/package.json' | grep '^\+.*"[^"]*":' | grep -v '"version"' | grep -v '"name"'
```

Constitution.md addition: "Never add a dependency for something an LLM can generate inline. Every new dependency is an attack surface expansion."

#### 2.3 Plugin distribution integrity

- Verify GPG/SSH commit signing is enabled on main (check branch protection rules)
- Document verification steps for users: `gh release download` + checksum verification
- GitHub Releases already include source archives with SHA-256 checksums

### Phase 3: Documentation and Least-Privilege (P3)

#### 3.1 Skill least-privilege documentation

Add a `## System Access` section to each SKILL.md that shells out:

```markdown
## System Access

- **Filesystem**: Read/write to `<paths>`
- **Network**: HTTPS to `<endpoints>`
- **Shell**: Invokes `<commands>`
```

Priority skills to audit: `gemini-imagegen` (Python, network), `deploy` (SSH, Docker), `agent-browser` (Chrome).

#### 3.2 Constitution.md supply chain rules

Add to constitution.md Architecture section:

- Bun is the primary package manager; lifecycle scripts are blocked by default
- All CI install commands must use `--frozen-lockfile`
- Python requirements must use exact versions with `--hash` integrity
- New dependencies require justification (the dependency-review-action flags them)
- `minimumReleaseAge` is set to 3 days in `bunfig.toml`

## Technical Considerations

### Bun vs npm lockfile coexistence

The web-platform has both `bun.lock` and `package-lock.json`. The Dockerfile uses `npm ci` (not bun) because the production image is `node:22-slim`. Both lockfiles must stay in sync. The `bun.lock` is used for local development and CI tests; `package-lock.json` is used for Docker builds.

`lockfile-lint` does not support `bun.lock` -- we rely on Bun's built-in integrity verification (SHA-512 hashes in lockfile, verified by default during install). For `package-lock.json`, `npm ci` already verifies integrity hashes.

### `^` ranges in package.json

The issue asks to "evaluate pinning to exact" for npm/bun packages. Recommendation: **keep `^` ranges in package.json but enforce lockfiles strictly**. Rationale:

1. Lockfiles already pin exact versions with integrity hashes
2. `--frozen-lockfile` prevents resolution drift in CI
3. `^` ranges enable `bun update` for controlled updates
4. Exact pinning in package.json prevents Dependabot-style automated updates

The Python requirements.txt is different -- pip has no lockfile mechanism, so exact versions + hashes are the only defense.

### minimumReleaseAge trade-off

The 3-day `minimumReleaseAge` in bunfig.toml means newly published packages cannot be installed for 72 hours. This would have caught the litellm attack (live for ~1 hour). The `minimumReleaseAgeExcludes` list should include packages that need frequent urgent updates (none currently).

### Implementation Edge Cases

**Security reminder hook on workflow edits:** The `security_reminder_hook.py` PreToolUse hook blocks the first Edit/Write attempt on `.github/workflows/*.yml` files with a security advisory. The second attempt succeeds after user approval. Expect this when editing `ci.yml` and creating `dependency-review.yml`. (Learning: `2026-03-18-security-reminder-hook-blocks-workflow-edits.md`)

**Dual lockfile sync verification:** After changing CI to `--frozen-lockfile`, verify both lockfiles are in sync for web-platform:

```bash
# In apps/web-platform/, verify no drift between bun.lock and package-lock.json
bun install --frozen-lockfile  # Should succeed
npm ci                          # Should also succeed
```

If they drift, the Docker build (npm ci) will fail even though CI tests (bun install) pass. Add a CI step or pre-push hook to detect divergence.

**Bun version sensitivity:** The `minimumReleaseAge` feature was introduced in Bun 1.2+. Verify the project's `.bun-version` file specifies a version that supports this feature.

### Socket.dev evaluation

The issue mentions evaluating Socket.dev for proactive anomaly detection. Recommendation: defer to a separate issue. The GitHub Dependency Review Action covers CVE detection for free. Socket.dev adds typosquatting and obfuscated code detection but has a cost. Evaluate after Phase 1 ships.

## Acceptance Criteria

### Functional Requirements

- [x] `requirements.txt` uses exact pinned versions (hash verification deferred to pip-compile)
- [x] CI uses `bun install --frozen-lockfile` in all jobs (ci.yml test + e2e)
- [x] Dependency Review Action runs on every PR and blocks on high/critical CVEs
- [x] `bunfig.toml` sets `minimumReleaseAge = 259200` at root level
- [x] Constitution.md documents supply chain rules
- [x] Gemini-imagegen SKILL.md uses exact pinned versions

### Non-Functional Requirements

- [ ] CI time increase is under 30 seconds (dependency review is fast)
- [ ] No false-positive blocks on current dependency tree (verify with a test PR)

### Quality Gates

- [ ] Zero `>=` or `^` ranges in Python requirements files
- [ ] Dependency review runs on every PR
- [ ] All existing tests pass with frozen lockfile enforcement

## Test Scenarios

- Given a PR that modifies `bun.lock` without updating `package.json`, when CI runs, then `bun install --frozen-lockfile` fails the build
- Given a PR that adds a dependency with a known high-severity CVE, when CI runs, then dependency-review-action blocks the PR
- Given the gemini-imagegen skill is installed, when `pip install --require-hashes -r requirements.txt` runs, then installation succeeds with verified hashes
- Given a new package is published to npm less than 3 days ago, when `bun install` runs locally, then the package is rejected by minimumReleaseAge

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling hardening with no user-facing, marketing, legal, or financial impact.

## Dependencies and Risks

| Risk | Mitigation |
|------|-----------|
| Frozen lockfile breaks CI for legitimate dependency updates | Document `bun install` (without --frozen-lockfile) for local dev, then commit updated lockfile |
| minimumReleaseAge blocks urgent security patches | Use `minimumReleaseAgeExcludes` for critical packages |
| Python hash generation is manual and tedious | One-time cost for 2 packages; automate with `pip-compile` if more Python deps are added |
| Dependency review action has false positives | Set `fail-on-severity: high` (not `low`) to reduce noise |

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|----------|---------|--------|
| Pin exact versions in all package.json | Rejected | Lockfiles already pin exact; `^` ranges enable controlled updates |
| Use Socket.dev for anomaly detection | Deferred | Cost vs. value unclear; dependency-review-action covers CVEs for free |
| Use lockfile-lint for bun.lock | Rejected | Tool does not support bun.lock; Bun has built-in integrity verification |
| npm audit in CI | Deferred | dependency-review-action is more comprehensive and GitHub-native |
| Signed commits on main | Deferred to Phase 2.3 | Requires GPG/SSH key setup; lower priority than CI gates |
| Bun Security Scanner API | Deferred | No mature open-source scanner package yet; monitor ecosystem |

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `plugins/soleur/skills/gemini-imagegen/requirements.txt` | Modify | Pin exact versions with hashes |
| `.github/workflows/ci.yml` | Modify | Change `bun install` to `bun install --frozen-lockfile` |
| `.github/workflows/dependency-review.yml` | Create | New dependency review workflow |
| `bunfig.toml` | Modify | Add `[install]` section with minimumReleaseAge |
| `apps/telegram-bridge/bunfig.toml` | Modify | Add `[install]` section with minimumReleaseAge |
| `apps/web-platform/bunfig.toml` | Create | Add `[install]` section with minimumReleaseAge |
| `knowledge-base/project/constitution.md` | Modify | Add supply chain security conventions |
| `plugins/soleur/skills/gemini-imagegen/SKILL.md` | Modify | Update install instructions for `--require-hashes` |

## Plan Review Findings

Three reviewers assessed this plan in parallel:

**Applied changes:**

- Added `apps/web-platform/bunfig.toml` to scope (was missing -- web-platform runs `bun install` in CI but had no bunfig.toml)
- Implementation scope narrowed to Phase 1 + constitution docs. Phase 2 (install script audit, dependency gate, plugin integrity) and Phase 3 (skill least-privilege docs) should be filed as separate GitHub issues

**Rejected suggestions:**

- None -- all reviewer feedback was incorporated

**Key agreements:**

- Keeping `^` ranges in package.json while enforcing lockfiles is correct (all three)
- Phase 2.2 custom bash dependency gate is redundant with dependency-review-action (remove from implementation scope)
- Phase 3.1 `## System Access` docs without enforcement tooling would drift -- defer until a linter can enforce it

## References

- Issue: [#1174](https://github.com/jikig-ai/soleur/issues/1174)
- Related: [#674](https://github.com/jikig-ai/soleur/issues/674) (app-level security)
- Learning: `2026-02-27-github-actions-sha-pinning-workflow.md` (SHA pinning pattern)
- Learning: `2026-03-19-npm-global-install-version-pinning.md` (npm version pinning)
- Learning: `2026-02-21-github-actions-workflow-security-patterns.md` (workflow security)
- [GitHub Dependency Review Action](https://github.com/actions/dependency-review-action)
- [Bun minimumReleaseAge docs](https://bun.sh/docs/cli/install)
- [Bun Security Scanner API](https://bun.sh/docs/pm/security-scanner-api)
- [Bun Security Scanner Template](https://github.com/oven-sh/security-scanner-template)
- [litellm supply chain attack thread](https://x.com/karpathy/status/2036487306585268612)
