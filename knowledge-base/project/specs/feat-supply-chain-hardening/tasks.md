# Tasks: Supply Chain Dependency Hardening

Source: `knowledge-base/project/plans/2026-03-29-feat-supply-chain-dependency-hardening-plan.md`
Issue: #1174

## Phase 1: Lockfile Integrity and Dependency Scanning (P1)

### 1.1 Pin Python requirements with hashes

- [ ] 1.1.1 Generate SHA-256 hashes: google-genai (pure Python, single hash: `7f127a39...`), Pillow (use sdist hash: `3828ee75...` for cross-platform)
- [ ] 1.1.2 Update `plugins/soleur/skills/gemini-imagegen/requirements.txt` with exact versions and `--hash` lines
- [ ] 1.1.3 Update `plugins/soleur/skills/gemini-imagegen/SKILL.md` install instructions to use `pip install --require-hashes -r requirements.txt`
- [ ] 1.1.4 Test: `pip install --require-hashes -r requirements.txt` succeeds in a clean venv on current platform

### 1.2 Enforce frozen lockfiles in CI

- [ ] 1.2.1 Change `bun install` to `bun install --frozen-lockfile` in `.github/workflows/ci.yml` test job (3 occurrences)
- [ ] 1.2.2 Change `bun install` to `bun install --frozen-lockfile` in `.github/workflows/ci.yml` e2e job (2 occurrences)
- [ ] 1.2.3 Verify: existing CI passes with frozen lockfile (no lockfile drift)

### 1.3 Add GitHub Dependency Review Action

- [ ] 1.3.1 Resolve SHA for `actions/dependency-review-action@v4.9.0` (already resolved: `2031cfc080254a8a887f58cffee85186f0e49e48`)
- [ ] 1.3.2 Create `.github/workflows/dependency-review.yml` with SHA-pinned actions
- [ ] 1.3.3 Configure: `fail-on-severity: high`, `license-check: true`, `vulnerability-check: true`, `comment-summary-in-pr: on-failure`
- [ ] 1.3.4 Add `pull-requests: write` permission for PR comment summaries
- [ ] 1.3.5 Verify: trigger workflow on a test PR

### 1.4 Configure Bun security settings

- [ ] 1.4.1 Add `[install]` section to root `bunfig.toml` with `minimumReleaseAge = 259200`
- [ ] 1.4.2 Add `[install]` section to `apps/telegram-bridge/bunfig.toml` with `minimumReleaseAge = 259200`
- [ ] 1.4.3 Create `apps/web-platform/bunfig.toml` with `[install]` section and `minimumReleaseAge = 259200`
- [ ] 1.4.4 Verify `.bun-version` supports minimumReleaseAge (requires Bun 1.2+)
- [ ] 1.4.5 Verify: `bun install` still works locally with the new settings

## Phase 2: Documentation and Constitution Updates

### 2.1 Constitution.md supply chain rules

- [ ] 2.1.1 Add supply chain security conventions to `knowledge-base/project/constitution.md` Architecture > Always section
- [ ] 2.1.2 Document: Bun blocks lifecycle scripts by default, CI must use `--frozen-lockfile`, Python requires exact versions + hashes, new deps need justification

### 2.2 Audit trustedDependencies

- [ ] 2.2.1 Verify no `trustedDependencies` in any `package.json` (confirm secure default)
- [ ] 2.2.2 Audit web-platform npm install scripts: `npm ls --all --json` for pre/postinstall hooks

## Phase 3: Deferred Items (Tracked Separately)

These items are tracked as separate GitHub issues per project convention:

- Socket.dev evaluation (deferred -- evaluate after Phase 1 ships)
- Signed commits on main (deferred -- requires GPG/SSH setup)
- Skill least-privilege documentation (P3 -- separate pass over all skills)
- New dependency gate CI check (partially covered by dependency-review-action)
- Bun Security Scanner API integration (deferred -- no mature scanner package yet)
