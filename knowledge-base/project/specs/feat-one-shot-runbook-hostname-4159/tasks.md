---
issue: 4159
lane: single-domain
plan: knowledge-base/project/plans/2026-05-20-fix-runbook-inngest-hostname-app-soleur-ai-plan.md
---

# Tasks — fix Inngest verification hostname (#4159)

## Phase 1 — Edit (the only phase)

- [ ] **1.1** Edit `knowledge-base/engineering/ops/runbooks/inngest-server.md` — replace `web-platform.soleur.ai` with `app.soleur.ai` (single occurrence at line 301).
- [ ] **1.2** Edit `knowledge-base/project/plans/2026-05-20-feat-one-shot-inngest-cloud-init-iac-plan.md` — replace `web-platform.soleur.ai` with `app.soleur.ai` (three occurrences at lines 177, 237, 379). Use `Edit` with `replace_all=true` since the string is uniquely wrong in this file.
- [ ] **1.3** Verify AC1: `grep -rE 'web-platform\.soleur\.ai' knowledge-base/` returns empty (exit code 1).
- [ ] **1.4** Verify AC2: `grep -cE 'app\.soleur\.ai/api/inngest' knowledge-base/engineering/ops/runbooks/inngest-server.md` returns `1`.
- [ ] **1.5** Verify AC3: `grep -cE 'app\.soleur\.ai/api/inngest' knowledge-base/project/plans/2026-05-20-feat-one-shot-inngest-cloud-init-iac-plan.md` returns `3`.
- [ ] **1.6** Verify AC4: `git diff --name-only main...HEAD` shows only the 2 edited files plus this plan/spec scaffold.

## Phase 2 — Ship

- [ ] **2.1** Update PR body to use `Closes #4159` (per AC5).
- [ ] **2.2** Mark PR ready (`gh pr ready`).
- [ ] **2.3** Auto-merge (`gh pr merge --squash --auto`).

## No tests

Per issue body: "One-line fix; do not require new acceptance tests." Greps in 1.3–1.5 are the post-conditions.

## No post-merge operator action

No deploy, migration, apply, or follow-up verification required.
