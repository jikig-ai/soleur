---
name: feat-one-shot-3711
issue: 3711
lane: cross-domain
brand_survival_threshold: aggregate pattern
date: 2026-05-13
plan: knowledge-base/project/plans/2026-05-13-feat-ops-hash-user-id-cli-pa8-retention-pin-plan.md
---

# Tasks — Operator hash-user-id CLI + PA8 §(f) retention pin + compliance-posture refresh (#3711)

Hierarchical task list derived from the plan. Phases run sequentially; tasks within a phase may run in parallel where noted.

## Phase 0 — Setup & Verification

- 1.1 — Verify branch is `feat-one-shot-3711` and worktree path matches.
- 1.2 — Re-run `Open Code-Review Overlap` query (plan §Open Code-Review Overlap) to confirm no scope-outs touch the planned file list.
- 1.3 — Verify cloud-init `daemon.json` source-of-truth is still at `apps/web-platform/infra/cloud-init.yml:303-310` (line numbers may drift between plan-write and /work). Re-anchor if shifted.
- 1.4 — Verify `apps/web-platform/server/observability.ts:36` still exports `hashUserId` with `(userId: string, pepper?: string) => string` signature.
- 1.5 — Verify Bun is installed locally (`bun --version` returns non-error). Required for AC1.3 dev verification.

## Phase 1 — Operator CLI (Item 1)

### 1.1 — Write failing test (RED)

- 2.1.1 — Add a Bun test (or shell-based assertion in `apps/web-platform/test/scripts/`) that invokes `bun apps/web-platform/scripts/hash-user-id.ts <fixture-uuid>` with `SENTRY_USERID_PEPPER=test-pepper` and asserts the stdout equals the reference HMAC. Test must fail because the script does not yet exist.
- 2.1.2 — Add a test for the no-argv case: stdin closed, no argv → exit non-zero, stderr contains `usage:`.
- 2.1.3 — Add a test for the no-pepper case: no `SENTRY_USERID_PEPPER` env var → exit non-zero, stderr contains "pepper not set" (or equivalent fail-loud message — exact wording fixed in 1.2.2).

### 1.2 — Implement CLI (GREEN)

- 2.2.1 — Create `apps/web-platform/scripts/hash-user-id.ts` with `#!/usr/bin/env bun` shebang. Import `hashUserId` from `../server/observability`.
- 2.2.2 — Implement: validate argv[2] present (else `usage:` to stderr + exit 1); validate `process.env.SENTRY_USERID_PEPPER` non-empty (else "pepper not set: SENTRY_USERID_PEPPER env var required (use `doppler run -p soleur -c prd -- npm run ...`)" to stderr + exit 1); call `hashUserId(argv[2])`; assert output length === 64 (sharp-edge sanity guard); `console.log(hash)`.
- 2.2.3 — Add `"hash-user-id": "bun scripts/hash-user-id.ts"` to `apps/web-platform/package.json` `scripts`.
- 2.2.4 — Run `bun test apps/web-platform/test/scripts/` — RED tests now GREEN.
- 2.2.5 — Run `cd apps/web-platform && tsc --noEmit` — passes.

### 1.3 — Refactor

- 2.3.1 — If the test files duplicate the reference HMAC computation, extract to a single fixture helper in `apps/web-platform/test/__fixtures__/hash-user-id.ts` (synthesized data only — `cq-test-fixtures-synthesized-only`).

## Phase 2 — PA8 §(f) doc update (Item 2 — structural cap only)

- 3.1 — Read `knowledge-base/legal/article-30-register.md` and locate the PA8 §(f) row (Processing Activity 8, Retention cell). Note actual line number for /work edit.
- 3.2 — Replace the §(f) cell text per the template in plan §Proposed Solution Item 2. MUST include:
    - `"30 MB rolling per container (max-size=10m × max-file=3)"` literal
    - `apps/web-platform/infra/cloud-init.yml:303-310` source-of-truth citation
    - `__TBD_OBSERVED_VOLUME__` sentinel for the post-merge fill
    - `Re-verification triggers:` enumeration (annual + 3 change-event triggers)
    - `"No off-host copies are taken."` clause
- 3.3 — Verify ACs:
    - 3.3.1 — `grep -F 'short rolling window' knowledge-base/legal/article-30-register.md` → 0 matches (AC2.1).
    - 3.3.2 — `grep -F '30 MB rolling per container' knowledge-base/legal/article-30-register.md` → 1 match (AC2.2).
    - 3.3.3 — `grep -F 'Re-verification triggers' knowledge-base/legal/article-30-register.md` → 1 match (AC2.3).
    - 3.3.4 — `grep -F '__TBD_OBSERVED_VOLUME__' knowledge-base/legal/article-30-register.md` → 1 match (AC2.4).

## Phase 3 — Compliance-posture refresh (Item 3)

- 4.1 — Read `knowledge-base/legal/compliance-posture.md` and re-anchor the "Article 30 Register (RoPA) — initial draft" row line number (issue body's "line 88" is stale — actual line near 91).
- 4.2 — Append `"PA8 §(f) Hetzner pino retention concretised in PR #<N> (2026-05-13)."` sentence to the Notes cell of that row, where `<N>` is filled at PR-creation time (or use `#TBD-PR-NUMBER` sentinel and replace post-PR-create).
- 4.3 — Verify ACs:
    - 4.3.1 — `grep -F 'PA8 §(f) Hetzner pino retention concretised' knowledge-base/legal/compliance-posture.md` → 1 match (AC3.1).
    - 4.3.2 — `grep -cF 'outstanding items: controller legal form' knowledge-base/legal/compliance-posture.md` → 1 match (AC3.2; outstanding-items scope unchanged in count).

## Phase 4 — Operator runbook (Item 4)

- 5.1 — Create `knowledge-base/engineering/ops/runbooks/recover-userid-from-pino-stdout.md` with YAML frontmatter (`category: support`, `tags: [pino, userid, hash, observability, gdpr]`, `date: 2026-05-13`).
- 5.2 — Document the canonical operator flow (UUID → hash → docker logs grep). Explicit note: CLI is operator-local, not inside the prod container (one-line `tsx` reason).
- 5.3 — Embed the Phase 2 SSH measurement procedure verbatim (5 steps) so the runbook IS the operator script for the post-merge §(f) fill.
- 5.4 — Cross-reference `admin-ip-drift.md` and `ssh-fail2ban-unban.md`.
- 5.5 — Verify ACs 4.1-4.4.

## Phase 5 — Pre-merge verification

- 6.1 — `cd apps/web-platform && bun test` — all tests pass, including the new hash-user-id tests.
- 6.2 — `cd apps/web-platform && tsc --noEmit` — clean.
- 6.3 — `cd apps/web-platform && npm run lint` — clean (no new ESLint warnings on the script).
- 6.4 — Manual smoke: `cd apps/web-platform && SENTRY_USERID_PEPPER=test-pepper bun scripts/hash-user-id.ts 11111111-2222-3333-4444-555555555555` → exactly 64-hex output.
- 6.5 — All AC checks from plan §Acceptance Criteria (Pre-merge) green.
- 6.6 — Run `/soleur:review` (multi-agent review) and address any P0/P1 findings inline.

## Phase 6 — PR

- 7.1 — Push branch + `gh pr create` with:
    - Title: `feat(ops): operator hash-user-id CLI + PA8 §(f) Hetzner retention pin + compliance-posture refresh (#3711)`
    - Body: `Ref #3711` (NOT `Closes` — closure happens post-measurement, see plan AC5.1)
    - `## Changelog` section with `semver:patch` rationale
    - Labels carried from issue: `priority/p3-low`, `domain/operations`, `type/security`, `deferred-scope-out`
- 7.2 — Replace `#TBD-PR-NUMBER` sentinel in `compliance-posture.md` with the actual PR number from `gh pr view --json number`. Amend commit.
- 7.3 — Run `/soleur:ship` Phase 5.5 preflight; address any blockers inline.

## Phase 7 — Post-merge (operator)

- 8.1 — `/soleur:admin-ip-refresh` if ADMIN_IPS allowlist drift detected.
- 8.2 — Follow runbook (Phase 2 / `recover-userid-from-pino-stdout.md`) SSH measurement steps. Capture three 8-h-spaced samples on a representative weekday.
- 8.3 — Compute observed daily bytes → MB/day, convert to `<Y> days effective retention`.
- 8.4 — Open follow-up PR replacing `__TBD_OBSERVED_VOLUME__` in `article-30-register.md` with the measured value + date.
- 8.5 — After follow-up PR merges: `gh issue close 3711 --reason completed --comment "Operator-side §(f) measurement complete; observed <X> MB/day → ~<Y> days. Follow-up PR #<M> applied the value."`.
