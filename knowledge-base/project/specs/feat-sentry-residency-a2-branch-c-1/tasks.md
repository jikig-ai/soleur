---
feature: sentry-residency-a2-branch-c
date: 2026-05-16
plan: knowledge-base/project/plans/2026-05-16-feat-sentry-residency-a2-branch-c-plan.md
spec: knowledge-base/project/specs/feat-sentry-residency-a2-branch-c-1/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-16-sentry-residency-a2-branch-c-brainstorm.md
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
requires_cpo_signoff: true
---

# Tasks: Sentry Residency A2 — Branch C

Derived from `knowledge-base/project/plans/2026-05-16-feat-sentry-residency-a2-branch-c-plan.md`. Three sibling worktrees ship three PRs in sequence: PR-α (legal+docs deadline gate) → PR-β (runtime+IaC+audit-gate) → PR-γ (cleanup+vendor).

## PR-α — Legal + Docs Deadline Gate (this worktree, ships 2026-05-17/18)

### 1. Setup
- 1.1. Confirm branch `feat-sentry-residency-a2-branch-c-1` and draft PR #3904.
- 1.2. Copy CLO-drafted PA8 §5(2) wording from brainstorm Decision #8 into editor.

### 2. Core implementation
- 2.1. Append phantom-ingest disclosure paragraph to PA8 §(d) Recipients cell at `knowledge-base/legal/article-30-register.md:160` (FR1; AC1).
- 2.2. Replace stale URL at `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md:95` (`de.sentry.io/settings/account/api/auth-tokens/` → `eu.sentry.io/...`) (FR2 part 1; AC3 part 1).
- 2.3. Add `## Cluster / Host Glossary` section to ADR-031 before `## Decision` heading (FR2 part 2; AC3 part 2).
- 2.4. Update ADR-031 L101 prose to reference `eu.sentry.io/api/` canonical EU API base_url.
- 2.5. Add Active Compliance Items row to `knowledge-base/legal/compliance-posture.md` cross-referencing PIR + plan + #3861 + PR #3904 (FR3; AC4).

### 3. Verification
- 3.1. Run AC1 grep: `grep -nE "phantom-ingest|destination-unreachable" knowledge-base/legal/article-30-register.md` returns ≥1.
- 3.2. Run AC3 greps: `grep -c "de.sentry.io/settings" knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` returns 0; `grep -c "## Cluster / Host Glossary" ...` returns 1.
- 3.3. Run AC4 grep: `grep -nE "sentry-residency-a2|phantom-ingest|3861" knowledge-base/legal/compliance-posture.md` returns ≥1.

### 4. CLO sign-off + merge
- 4.1. Capture CLO sign-off in PR-α body (AC2).
- 4.2. `gh pr ready 3904 && gh pr merge 3904 --squash --auto`.
- 4.3. Confirm merge timestamp before 2026-05-19T12:50Z (AC5).

### 5. Post-merge sibling-worktree scaffolding
- 5.1. `git fetch origin main`.
- 5.2. `git worktree add .worktrees/feat-sentry-residency-a2-branch-c-2 -b feat-sentry-residency-a2-branch-c-2 origin/main`.
- 5.3. `git worktree add .worktrees/feat-sentry-residency-a2-branch-c-3 -b feat-sentry-residency-a2-branch-c-3 origin/main`.
- 5.4. Open draft PR for `-2` via `gh pr create --draft --base main --head feat-sentry-residency-a2-branch-c-2`.
- 5.5. Open draft PR for `-3` via `gh pr create --draft --base main --head feat-sentry-residency-a2-branch-c-3`.

## PR-β — Runtime Atomic Swap + IaC + Audit-Gate (sibling `-2`, ships next week)

### 6. Pre-flight
- 6.1. **TR2:** `pgrep -fa chromium | grep -- --headless` MUST return empty. If non-empty, pin `@playwright/mcp` in `.mcp.json` and restart MCP, OR hand off C1 credential entry to operator-driven manual signup.
- 6.2. **TR3 (slug collision):** `curl -s -o /dev/null -w '%{http_code}' https://eu.sentry.io/organizations/jikigai/` — record 404 (use `jikigai`) or 200/302 (rename to `jikigai-eu`).
- 6.3. Capture pre-flight tfstate manifest: `cd apps/web-platform/infra/sentry && terraform state list > /tmp/pre-drop-state.txt`.

### 7. C1 — Provision new DE org
- 7.1. Playwright navigates to https://eu.sentry.io/auth/register/; operator at keyboard for credentials.
- 7.2. Set org slug per TR3 outcome; keep `web-platform` project slug.
- 7.3. Mint new DE-scoped `SENTRY_AUTH_TOKEN` (scopes: `project:read`, `project:releases`, `project:write`, `org:read`).
- 7.4. **FR6 verify probe:** `curl -H "Authorization: Bearer $NEW_TOKEN" https://eu.sentry.io/api/0/users/me/` returns 200 (target `eu.sentry.io`, NOT `de.sentry.io`).

### 8. C2 — Write-new-everywhere (do NOT revoke old yet)
- 8.1. Doppler `prd`: rotate 12 keys per plan Phase 2 step 1.
- 8.2. GH repo secrets: rotate 11 keys (parity minus `SENTRY_CSP_REPORT_URI`).
- 8.3. Vercel envs: rotate to Doppler `prd` shape.
- 8.4. `apps/web-platform/.env.example` — update commented templates.
- 8.5. `apps/web-platform/Dockerfile` — verify ARG block carries new values; inject `ENV SENTRY_URL=https://eu.sentry.io/`.
- 8.6. `apps/web-platform/next.config.ts` Sentry block — inject `SENTRY_URL` if absent.
- 8.7. `.github/workflows/reusable-release.yml` — audit-script env block + Docker build-args block: inject `SENTRY_URL`.
- 8.8. 9 scheduled workflows: verify each consumes `SENTRY_INGEST_DOMAIN`/`SENTRY_PROJECT_ID`/`SENTRY_PUBLIC_KEY` from GH repo secrets (no inline literals): `grep -rE 'SENTRY_(INGEST_DOMAIN|PROJECT_ID|PUBLIC_KEY).*:.*[0-9]' .github/workflows/scheduled-*.yml` returns 0.
- 8.9. `apps/web-platform/infra/sentry/main.tf:30` — flip `base_url = "https://eu.sentry.io/api/"`.
- 8.10. **TR5:** Cloudflare cache purge via `POST /client/v4/zones/<zone>/purge_cache` with body `{"files":["https://app.soleur.ai/"]}`.
- 8.11. Trigger deploy: `gh workflow run reusable-release.yml` or push commit to main pipeline; wait for Vercel propagation.

### 9. TR1 — 2h observation window
- 9.1. Trigger synthetic event: `curl -X POST` against new DSN with minimal test payload.
- 9.2. Trigger real prod event (operator-driven: feature interaction or organic).
- 9.3. After 2h: confirm both events land in new DE org dashboard `eu.sentry.io/organizations/<slug>/issues/`.
- 9.4. **HALT** if either event missing — investigate before Phase 11.

### 10. C5 — Audit-gate triple-expansion
- 10.1. Edit `apps/web-platform/scripts/sentry-monitors-audit.sh`: insert 3 gates between L58 (region-probe success) and L60 (DSN cluster check). Code per plan Phase 4 block.
- 10.2. Extend region-probe loop at L46: `for candidate in eu.sentry.io de.sentry.io sentry.io`.
- 10.3. Create `.github/workflows/sentry-audit-gate.yml` per plan Phase 5 block.
- 10.4. Extend `infra/github/main.tf` ruleset to include `Sentry Audit Gate` as required-check on main-bound PRs (separate small commit on this PR).

### 11. C4 — tfstate drop + serial reimport
- 11.1. Capture pre-drop manifest: `bash apps/web-platform/scripts/sentry-monitors-audit.sh > knowledge-base/legal/audits/sentry-migration-audit-<YYYY-MM-DD>.md`.
- 11.2. Drop all resources serially: `xargs -a /tmp/pre-drop-state.txt -n1 terraform state rm`.
- 11.3. Verify state empty: `terraform state list` returns nothing.
- 11.4. Update `var.sentry_org` default in `variables.tf` if TR3 forced rename.
- 11.5. Re-import each resource **strictly serial** (no `-P2+`, no `&`, no parallel). Capture each `terraform import` stdout to `/tmp/sentry-import-<N>.log`.
- 11.6. Between imports: `terraform state list | grep -F "<just-imported-address>"` MUST return the resource.
- 11.7. `terraform plan` MUST show 0 changes.
- 11.8. Capture post-import manifest; diff against pre-drop in PR body (AC10).

### 12. Phase 7 — revoke old token
- 12.1. Confirm Phase 10 (audit-gate green), Phase 11 (tfstate clean), Phase 9 (2h observation passed) all GREEN.
- 12.2. Revoke US-shadow-org token via `sentry.io/settings/jikigai/auth-tokens/` (the controllable old token).
- 12.3. Verify revocation: `curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer <OLD_TOKEN>" https://eu.sentry.io/api/0/users/me/` returns 401 (AC9).

### 13. Verification (PR-β)
- 13.1. AC6: `echo "$NEXT_PUBLIC_SENTRY_DSN" | grep -oE 'o[0-9]+'` returns new org-id `≠ 4511123328466944`.
- 13.2. AC7: CI run of `sentry-audit-gate.yml` green; required-check present in ruleset.
- 13.3. AC8: per-surface verification per plan AC8 (Doppler + GH secrets + Vercel + .env.example + Dockerfile + next.config.ts + reusable-release.yml + 9 workflows).
- 13.4. AC9: phantom org-id substring not present in current deploy: `grep -rn "4511123328466944" apps/web-platform/ .github/workflows/scheduled-*.yml` returns 0.
- 13.5. AC10: `terraform state list | wc -l` returns 13; `terraform plan` 0 changes; pre/post manifest diff in PR body.

### 14. Post-merge verification (PR-β)
- 14.1. AC11: Wait for first scheduled run of each of 9 workflows; confirm cron-checkin events in new DE org's `crons/` dashboard.
- 14.2. Capture timestamps in PR-γ PR body or PR-β post-merge follow-up comment.

## PR-γ — Cleanup + Vendor (sibling `-3`, ships when refund processes)

### 15. Pre-flight
- 15.1. Confirm PR-β merged and 9 scheduled workflows have ≥1 successful cron-checkin to new DE org.

### 16. C8a — US shadow org documentation
- 16.1. Document state in PR-γ body: Team subscription cancelled effective 2026-06-14; free plan during forensics.
- 16.2. After Sentry support response on Ticket 2: if third-party ownership confirmed, close US org via `sentry.io/settings/jikigai/general-settings/` → "Close Account"; else document residual.

### 17. C8b — Sentry support tickets
- 17.1. Ticket 1 (billing) — operator submits via `sentry.io/support/` per Decision #9 wording.
- 17.2. Ticket 2 (forensics) — SEPARATE submission, not threaded on Ticket 1.
- 17.3. Capture both ticket IDs in PR-γ body (AC13).

### 18. C6 backfill
- 18.1. Edit `knowledge-base/legal/article-30-register.md` PA8 §(d) cell: replace `<pending C2 merge>` with PR-β merge ref (FR12; AC14).

### 19. PIR Phase 8 flip
- 19.1. Edit `knowledge-base/engineering/ops/runbooks/sentry-phantom-ingest-destination-unreachable-postmortem.md`: L8 `status: open` → `status: resolved`.
- 19.2. Append `## Phase 8 — Recovery Completeness` section before `## Who was affected (by role)` at L75. Body per plan Phase 4 template (TR4; AC15).
- 19.3. Verify: `grep -c "## Phase 8 — Recovery Completeness"` returns 1.

### 20. W1-W5 follow-up issues
- 20.1. Verify labels exist: `gh label list | grep -E "^domain/process|^domain/engineering|^skill:brainstorm|^skill:compound|^priority/p2-medium|^priority/p3-low|^chore"`.
- 20.2. Substitute closest existing label if any missing.
- 20.3. `gh issue create` for W1, W2, W4, W5 per plan Phase 5 wording (W3 absorbed into C5; do NOT file).
- 20.4. Capture 4 issue numbers in PR-γ body (AC16).

### 21. Verification (PR-γ)
- 21.1. AC12: US shadow org status row in PR-γ body.
- 21.2. AC13: Both ticket IDs captured.
- 21.3. AC14: `grep -c "<pending C2 merge>" knowledge-base/legal/article-30-register.md` returns 0.
- 21.4. AC15: `grep -nE "^status: resolved" knowledge-base/engineering/ops/runbooks/sentry-phantom-ingest-destination-unreachable-postmortem.md` returns L8; Phase 8 section present.
- 21.5. AC16: 4 W-issues open with matching titles.

### 22. Post-merge gate (PR-γ)
- 22.1. AC15-post: Sentry support response received OR T+14d elapsed; residual evidence ceiling documented.
- 22.2. AC12-post: US org closed (or documented residual).
