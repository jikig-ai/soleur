# Tasks — rotate X_API_SECRET and widen doppler-stdout trap

Derived from the implementation plan at
`../../plans/2026-05-18-security-rotate-x-api-secret-and-widen-doppler-stdout-trap-plan.md`.

## Phase 0 — Preconditions (verification only)

- [x] 0.1 Verify CWD = worktree root, branch = `feat-one-shot-rotate-x-api-secret-4029`.
- [x] 0.2 Verify `doppler secrets delete --help` flag set (`-y/--yes`, `--silent`).
- [x] 0.3 Verify `X_API_SECRET` exists at the GitHub repo level and consumed by `scheduled-content-publisher.yml` only.
- [x] 0.4 Verify hook regex shape (single existing `set`-only match).
- [x] 0.5 Verify baseline `prod-write-defer-gate.test.sh` exits 0.

## Phase 1 — Hook regex + tests (RED → GREEN)

- [x] 1.1 RED — add failing assertions to `.claude/hooks/prod-write-defer-gate.test.sh` for the widened surface (delete × {prd, prd_terraform, dev, ci}; set × {dev, ci}; env-prefixed delete; wrapped delete; chained && delete; negative cases for `list`, `download`, `--help`, `-h`, `prd-staging`, equals-form, echo substring).
- [x] 1.2 GREEN — widen `.claude/hooks/prod-write-defer-gate.sh` regex (verb `set` → `(set|delete)`; config `(prd|prd_terraform)` → `(prd|prd_terraform|dev|ci)`); rename rule_id `prod-write-defer-doppler-prd-secrets` → `prod-write-defer-doppler-secrets-stdout`; add `READONLY_FLAG_PATTERNS` entry for the new rule.
- [x] 1.3 Re-run tests; confirm GREEN.
- [x] 1.4 Update `.claude/hooks/README.md` starter-manifest table row + Secret-in-argv caveat paragraph.

## Phase 2 — Docs widening

- [x] 2.1 Amend `knowledge-base/project/learnings/2026-05-18-supabase-custom-access-token-hook-discriminator.md` Leak-2 entry: widen to `{set,delete}`, correct the false "no `--silent` flag exists" claim, document the `set`/`delete` asymmetric flag set.
- [x] 2.2 Runbook sweep: `>/dev/null 2>&1` + `--silent` on every `doppler secrets {set,delete}` invocation across `stripe-live-activation.md`, `tenant-offboarding.md`, `tenant-provisioning.md`, `github-app-drift.md`. Verification grep: `git grep -nE '(^|[[:space:]])doppler[[:space:]]+secrets[[:space:]]+(set|delete)[[:space:]]' ... | grep -vE '>/dev/null 2>&1|--silent|\| doppler secrets set|--name-transformer tf-var'` returns 0 lines.
- [x] 2.3 Add the cross-link to the Leak-2 entry on each amended runbook.

## Phase 3 — Plan-prescribed skills (run inline)

- [ ] 3.1 `/soleur:preflight` after Phase 1, before Phase 2.
- [ ] 3.2 `/soleur:gdpr-gate` after Phase 2 (advisory).
- [ ] 3.3 `/soleur:review` after Phase 2 (before push).

## Phase 4 — Bootstrap script (PR diff)

- [x] 4.1 Create `scripts/rotate-x-api-secret-bootstrap.sh` chaining AC8–AC13 (Doppler prd set + GH secret set + validate-credentials + workflow_dispatch smoke + shred). Marked executable.

## Phase 5 — Post-merge (operator)

- [ ] 5.1 AC8 — Regenerate X_API_SECRET at developer.x.com via Playwright `browser_evaluate(filename:)` no-leak pattern.
- [ ] 5.2 AC9 — Doppler `prd` updated.
- [ ] 5.3 AC10 — GitHub Actions `X_API_SECRET` updated (via `gh secret set --body -`).
- [ ] 5.4 AC11 — Live verification: `bash plugins/soleur/skills/community/scripts/x-setup.sh validate-credentials` returns 200 + account name.
- [ ] 5.5 AC12 — Cron pipeline smoke via `gh workflow run scheduled-content-publisher.yml`; no 401.
- [ ] 5.6 AC13 — Shred `.playwright-mcp/x-api-secret.txt`.
- [ ] 5.7 AC14 — Close issue: `gh issue close 4029 --comment "<run URL>"`.
- [ ] 5.8 AC15 — File scope-out tracking issue for moving X_API_* secrets to `doppler_secret` Terraform IaC.
