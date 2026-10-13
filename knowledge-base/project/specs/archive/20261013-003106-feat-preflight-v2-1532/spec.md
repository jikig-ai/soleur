# Spec: Preflight v2 — Lockfile Consistency Check

**Issue:** #1532
**Branch:** preflight-v2-1532
**Brainstorm:** [2026-04-05-preflight-v2-lockfile-brainstorm.md](../../brainstorms/2026-04-05-preflight-v2-lockfile-brainstorm.md)

## Problem Statement

The AGENTS.md rule requiring both `bun.lock` and `package-lock.json` to be regenerated when dependencies change has no automated enforcement. In #1293, `bun.lock` was updated but `package-lock.json` was not, breaking all Docker builds for hours because `npm ci` requires a synced `package-lock.json`.

## Goals

- G1: Catch lockfile inconsistencies before PRs merge
- G2: Enforce the existing AGENTS.md dual-lockfile rule automatically
- G3: Integrate seamlessly with the existing preflight/ship pipeline

## Non-Goals

- NG1: Conditional agent spawning (deferred — #1532)
- NG2: Playwright CSP console checks (deferred — #1532)
- NG3: 4-tier severity system (deferred — #1532)
- NG4: Full-repo lockfile scanning (diff-scoped only)

## Functional Requirements

- FR1: Diff `origin/main...HEAD` for changes to `package.json`, `bun.lock`, and `package-lock.json` files
- FR2: Group changed files by app directory (e.g., `apps/web-platform/`, `apps/telegram-bridge/`)
- FR3: For each app directory where any of the three files changed: if `package.json` or `bun.lock` changed but `package-lock.json` did not, report FAIL with the specific app and missing file
- FR4: SKIP if no lockfile-related files appear in the diff
- FR5: PASS if all apps with lockfile changes have consistent updates

## Technical Requirements

- TR1: Implement as an additional Phase 1 parallel check in `plugins/soleur/skills/preflight/SKILL.md`
- TR2: Use `git diff --name-only origin/main...HEAD` filtered for `package.json`, `bun.lock`, `package-lock.json`
- TR3: Report results using the existing PASS/FAIL/SKIP format
- TR4: FAIL message must name the specific app directory and which lockfile is missing from the diff

## Acceptance Criteria

- AC1: PR that changes `apps/web-platform/package.json` and `apps/web-platform/bun.lock` but NOT `apps/web-platform/package-lock.json` produces FAIL
- AC2: PR that changes both lockfiles alongside package.json produces PASS
- AC3: PR with no lockfile/package.json changes produces SKIP
- AC4: Root-level `package.json` changes (no app-level lockfiles) produce SKIP
- AC5: Check runs in parallel with existing migration and security header checks
