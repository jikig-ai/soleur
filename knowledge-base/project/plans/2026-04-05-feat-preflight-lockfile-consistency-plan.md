---
title: "feat: preflight lockfile consistency check"
type: feat
date: 2026-04-05
---

# feat: preflight lockfile consistency check

Add a lockfile consistency check to the preflight skill. In dual-lockfile directories, if either lockfile changed in the PR diff, the other must also have changed. Enforces the AGENTS.md rule that broke production in #1293.

## Problem Statement

The AGENTS.md rule requiring both `bun.lock` and `package-lock.json` to be regenerated has no automated enforcement. In #1293, `bun.lock` was updated but `package-lock.json` was not, breaking all Docker builds for hours (`npm ci` requires synced `package-lock.json`).

## Proposed Solution

Add "Check 3: Lockfile Consistency" to `plugins/soleur/skills/preflight/SKILL.md`, running in parallel with existing checks. The check:

1. Diffs `origin/main...HEAD` for `bun.lock` and `package-lock.json` files (NOT `package.json` — avoids false positives on non-dep edits like scripts/name/engines)
2. Groups changed lockfiles by directory (dynamic from diff, not hardcoded)
3. For each directory where a lockfile changed: checks if that directory is a dual-lockfile directory (both `bun.lock` and `package-lock.json` exist in working tree)
4. If dual-lockfile and only one changed: **FAIL** with the specific directory and missing lockfile
5. If both changed or directory is single-lockfile: **PASS**
6. If no lockfiles in diff: **SKIP**

### Dual-lockfile directories (current)

- `apps/web-platform/` (both `bun.lock` + `package-lock.json`)
- `apps/telegram-bridge/` (both `bun.lock` + `package-lock.json`)
- Root `/` (both `bun.lock` + `package-lock.json`)

### Key design decisions from spec-flow analysis

| Gap Found | Resolution |
|-----------|-----------|
| Trigger on package.json creates false positives | Trigger only on lockfile changes, not package.json |
| Missing reverse direction (package-lock without bun.lock) | Symmetric rule: either lockfile triggers the check |
| Root-level lockfiles unhandled | Dynamic directory detection from diff includes root |
| Lockfile refresh without package.json change | Both lockfiles changed → PASS (legitimate refresh) |
| Hardcoded app directories | Extract unique directories from diff results |

## Acceptance Criteria

- [ ] AC1: PR where `apps/web-platform/bun.lock` changed but NOT `apps/web-platform/package-lock.json` → FAIL naming the directory and missing file
- [ ] AC2: PR where both `apps/web-platform/bun.lock` and `apps/web-platform/package-lock.json` changed → PASS
- [ ] AC3: PR where `apps/web-platform/package-lock.json` changed but NOT `apps/web-platform/bun.lock` → FAIL (reverse direction)
- [ ] AC4: PR with no lockfile changes → SKIP
- [ ] AC5: PR where root `bun.lock` changed but NOT root `package-lock.json` → FAIL
- [ ] AC6: PR where only `spike/package-lock.json` changed (single-lockfile directory) → PASS (not a dual-lockfile directory)
- [ ] AC7: Check runs in parallel with existing migration and security header checks
- [ ] AC8: Phase 2 aggregation table includes the new check row
- [ ] AC9: PR where `apps/web-platform/bun.lock` changed (FAIL) AND both `apps/telegram-bridge/` lockfiles changed (PASS) → overall FAIL (mixed per-directory results)

## Test Scenarios

- Given a PR that modifies `apps/web-platform/bun.lock` only, when preflight runs, then Check 3 reports FAIL with message naming `apps/web-platform/` and `package-lock.json`
- Given a PR that modifies both lockfiles in `apps/telegram-bridge/`, when preflight runs, then Check 3 reports PASS
- Given a PR that modifies only `package.json` (scripts section), when preflight runs, then Check 3 reports SKIP (no lockfiles in diff)
- Given a PR that modifies root `package-lock.json` without root `bun.lock`, when preflight runs, then Check 3 reports FAIL
- Given a PR that modifies `spike/package-lock.json` only, when preflight runs, then Check 3 reports PASS (spike has no `bun.lock`)

## Implementation

### File to modify

`plugins/soleur/skills/preflight/SKILL.md`

### Changes

1. **Add Check 3 section** after Check 2 (Security Headers), before Phase 2. Follow the existing check pattern. **CRITICAL:** The SKILL.md has a "no command substitution" rule — each step must be a separate Bash tool call, never `$()` or piped substitutions:
   - Step 3.1: Detect lockfile changes in diff (one Bash call)
   - Step 3.2: Group by directory (agent logic, not bash)
   - Step 3.3: For each directory, check if dual-lockfile — test if both files exist (separate Bash calls per directory)
   - Step 3.4: If dual-lockfile and only one changed, FAIL

2. **Update Phase 1 header** to say "four validations" instead of "three validations"

3. **Update Phase 2 aggregation table** to add the Lockfile Consistency row:

```markdown
| Check | Result | Details |
|-------|--------|---------|
| Not-Bare-Repo | PASS/FAIL | <details> |
| DB Migration Status | PASS/FAIL/SKIP | <details> |
| Security Headers | PASS/FAIL/SKIP | <details> |
| Lockfile Consistency | PASS/FAIL/SKIP | <details> |
```

4. **Update skill description** in YAML frontmatter to mention lockfile validation

## Domain Review

**Domains relevant:** Engineering, Product, Marketing

Carried forward from brainstorm domain assessments (2026-04-05). No scope change since brainstorm — all findings still apply.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** LOW risk, pure bash. No agent budget impact. Lockfile check is highest-value, lowest-risk v2 addition.

### Product (CPO)

**Status:** reviewed
**Assessment:** Lockfile check is the highest-leverage move — real outage backing (#1293). Other v2 items are speculative. Ship this, defer the rest.

### Marketing (CMO)

**Status:** reviewed
**Assessment:** Ship silently. No announcement warranted for internal quality gate. Changelog entry only.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-05-preflight-v2-lockfile-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-preflight-v2-1532/spec.md`
- Current preflight: `plugins/soleur/skills/preflight/SKILL.md`
- Production outage: #1293
- Tracking issue: #1532
- AGENTS.md lockfile rule: line ~71 (dual-lockfile regeneration requirement)
