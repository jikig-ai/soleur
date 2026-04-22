# Tasks: Pre-deploy CI guard for required NEXT_PUBLIC_* secrets

**Plan:** `knowledge-base/project/plans/2026-04-22-feat-app-url-ci-guard-plan.md`
**Closes:** #2769
**Bundle parent spec:** `knowledge-base/project/specs/feat-app-url-hardening/spec.md` (FR3 + TR3)

## 1. Setup

- [x] 1.1 Confirm worktree `.worktrees/feat-app-url-ci-guard/` on branch `feat-app-url-ci-guard` off latest `main`.
- [x] 1.2 Verify exhaustiveness grep returns the 7 expected keys — plan Research Reconciliation table. Abort if the set differs from `{AGENT_COUNT, APP_URL, GITHUB_APP_SLUG, SENTRY_DSN, SUPABASE_ANON_KEY, SUPABASE_URL, VAPID_PUBLIC_KEY}`.

## 2. Guard script

- [x] 2.1 Create `apps/web-platform/scripts/verify-required-secrets.sh` with the exact body in plan §Implementation/Guard script (6-key `REQUIRED` array, enumerate-all-missing semantics, no `-e`/`-u`).
- [x] 2.2 `chmod +x` the script.
- [x] 2.3 Shellcheck locally — zero findings before proceeding.
- [x] 2.4 Run negative smoke: `env -i PATH="$PATH" bash apps/web-platform/scripts/verify-required-secrets.sh` — expect exit 1, 6 per-key `::error::` lines, and the `::error::6 required ...` summary.
- [x] 2.5 Run happy-path smoke via `doppler run -p soleur -c prd -- bash scripts/verify-required-secrets.sh` — exit 0, six `ok <KEY>` lines. (Plan AC adjusted to `prd` after dev was found to lack 3 keys. Read-only.)

## 3. Workflow wiring

- [x] 3.1 Edit `.github/workflows/web-platform-release.yml`: add `verify-doppler-secrets` job per plan §Workflow diff. Copy the `dopplerhq/cli-action@014df23b...` digest verbatim from the existing `migrate` job.
- [x] 3.2 Extend `deploy.needs` to `[release, migrate, verify-doppler-secrets]`.
- [x] 3.3 Extend `deploy.if` to require `needs.verify-doppler-secrets.result == 'success'`. Add the inline comment explaining the skip-asymmetry with `migrate`.
- [x] 3.4 Validate workflow: `python3 -c 'import yaml; yaml.safe_load(...)'` + `actionlint` both pass. (yamllint is not in lefthook for this repo; actionlint is the authoritative semantic check.)

## 4. Verification

- [x] 4.1 Pre-merge AC complete per plan (negative/happy smokes pass, workflow diff scoped, regression + exhaustiveness greps clean).
- [ ] 4.2 Open PR with `Closes #2769` in body, title like `feat(ci): pre-deploy guard for required NEXT_PUBLIC_* secrets in Doppler prd`.
- [ ] 4.3 Merge via `/ship`.
- [ ] 4.4 Post-merge: watch the auto-fired `web-platform-release.yml` run; confirm the `verify-doppler-secrets` job reports `conclusion: success` via `gh run list --workflow=web-platform-release.yml --limit 1 --json conclusion,jobs`.
- [ ] 4.5 If auto-fire skipped, use the fallback: `gh workflow run web-platform-release.yml --ref main -f bump_type=patch -f skip_deploy=true`.
- [ ] 4.6 Bundle close-out (out of scope for this PR body, tracked separately): comment-close #2773 and #2774 citing passive Sentry evidence per brainstorm Pre-Work Findings.
