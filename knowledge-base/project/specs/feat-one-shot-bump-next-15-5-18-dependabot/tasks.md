---
title: "Tasks — bump next to 15.5.18"
plan: knowledge-base/project/plans/2026-05-16-fix-bump-next-15-5-18-dependabot-plan.md
lane: single-domain
---

# Tasks — bump next to 15.5.18

## Phase 1 — Preconditions

- [ ] 1.1 Verify worktree: `pwd` must end in `.worktrees/feat-one-shot-bump-next-15-5-18-dependabot`.
- [ ] 1.2 Verify branch: `git branch --show-current` returns `feat-one-shot-bump-next-15-5-18-dependabot`.
- [ ] 1.3 Snapshot baseline of open `next` alerts to `/tmp/pre-bump-open-alerts.txt` (expect 13 IDs).

## Phase 2 — Bump pins

- [ ] 2.1 Edit `apps/web-platform/package.json`: `dependencies.next` → `"^15.5.18"`.
- [ ] 2.2 Edit `apps/web-platform/package.json`: `devDependencies."eslint-config-next"` → `"^15.5.18"`.

## Phase 3 — Regenerate lockfiles

- [ ] 3.1 From `apps/web-platform/`: `bun install` (regenerates `bun.lock`).
- [ ] 3.2 From `apps/web-platform/`: `npm install --package-lock-only` (regenerates `package-lock.json`).
- [ ] 3.3 Verify `bun.lock` contains `next@15.5.18` and no `next@15.5.15` entries.
- [ ] 3.4 Verify `package-lock.json` `.packages."node_modules/next".version == "15.5.18"`.

## Phase 4 — Local verification gates

- [ ] 4.1 From `apps/web-platform/`: `bun install --frozen-lockfile` → exit 0 (AC3).
- [ ] 4.2 From `apps/web-platform/`: `npm ci` → exit 0 (AC4, mirrors Dockerfile).
- [ ] 4.3 From `apps/web-platform/`: `bun run typecheck` → exit 0 (AC5).
- [ ] 4.4 From `apps/web-platform/`: `bun run build` → exit 0 (AC6).
- [ ] 4.5 From `apps/web-platform/`: `bun run test:ci` → exit 0 (AC7).

## Phase 5 — Commit, push, PR

- [ ] 5.1 Run `/soleur:compound` (wg-before-every-commit).
- [ ] 5.2 `git add apps/web-platform/package.json apps/web-platform/bun.lock apps/web-platform/package-lock.json`.
- [ ] 5.3 `git commit -m "fix(deps): bump next to 15.5.18 to close 13 dependabot alerts"`.
- [ ] 5.4 `git push -u origin feat-one-shot-bump-next-15-5-18-dependabot`.
- [ ] 5.5 Open PR with title `fix(deps): bump next to 15.5.18 to close 13 Dependabot alerts` and body listing the 13 GHSA IDs + `Closes` references.
- [ ] 5.6 Apply labels `dependencies`, `domain/engineering`, `priority/p1-high` (AC10).

## Phase 6 — Review + QA + Ship

- [ ] 6.1 `/soleur:review` — fix P1/P2 inline.
- [ ] 6.2 `/soleur:qa` — full functional QA.
- [ ] 6.3 `/soleur:ship` — apply `chore` semver label, mark ready, auto-merge.

## Phase 7 — Post-merge verification

- [ ] 7.1 Wait for default-branch CI to complete.
- [ ] 7.2 Wait up to 10 min for Dependabot post-merge re-scan.
- [ ] 7.3 Run AC11 query: `gh api repos/jikig-ai/soleur/dependabot/alerts --paginate -q '.[] | select(.state == "open" and .dependency.package.name == "next") | .number' | wc -l` — expect 0.
- [ ] 7.4 If non-zero after 30 min: `git commit --allow-empty -m "chore: trigger dependabot re-scan" && git push`.
- [ ] 7.5 `/soleur:postmerge` — production health check on `app.soleur.ai`.
