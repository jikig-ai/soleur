# Tasks — feat-one-shot-3015-trigger-prod-build

Issue: #3015
Plan: `knowledge-base/project/plans/2026-04-29-chore-trigger-prod-build-after-doppler-correction-plan.md`

## Phase 1 — Pre-trigger verification (read-only)

- [ ] 1.1 Confirm latest `web-platform-release.yml` run is success on `main`
  (`gh run list --workflow=web-platform-release.yml --limit 3 --json
  status,conclusion,headSha,createdAt,event,headBranch`).
- [ ] 1.2 Pull Sentry digest for `feature:dashboard-error-boundary` /
  `feature:supabase-validator-throw` over 24h (Doppler `prd` token →
  Sentry REST API; web-UI fallback if token absent).
- [ ] 1.3 Run `bash apps/web-platform/infra/canary-bundle-claim-check.sh
  https://app.soleur.ai`; record pass/fail and which assertion failed.

## Phase 2 — Trigger build (contingent on Phase 1.2 OR 1.3 finding fault)

- [ ] 2.1 If Doppler is wrong: `doppler secrets set
  NEXT_PUBLIC_SUPABASE_ANON_KEY=<canonical> -p soleur -c prd` (per-command
  ack required).
- [ ] 2.2 If GitHub repo secret is wrong: `gh secret set
  NEXT_PUBLIC_SUPABASE_ANON_KEY -R jikig-ai/soleur < /dev/stdin`.
- [ ] 2.3 `gh workflow run web-platform-release.yml --ref main`; capture
  `RUN_ID` via `gh run list --workflow=... --limit 1 --json databaseId
  --jq '.[0].databaseId'`; `gh run watch "$RUN_ID" --exit-status`.

## Phase 3 — Render-time verification (always runs)

- [ ] 3.1 `ssh prod-web journalctl -u docker -n 200 | grep DEPLOY | tail -20`;
  must contain `final_write_state 0 "ok"`. (If SSH fails: run
  `/soleur:admin-ip-refresh` first per AGENTS.md
  `hr-ssh-diagnosis-verify-firewall`.)
- [ ] 3.2 Playwright MCP: navigate to `https://app.soleur.ai/dashboard`,
  screenshot, assert HTML does NOT contain `data-error-boundary=`.
- [ ] 3.2b (Optional) Signed-in render check via Doppler-stored test
  fixture (runbook D2).
- [ ] 3.3 Re-run `bash apps/web-platform/infra/canary-bundle-claim-check.sh
  https://app.soleur.ai`; must pass.
- [ ] 3.4 Edit
  `knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md`
  Recovery Verification block; replace each `TBD`; flip frontmatter
  `status:` to `closed: 2026-04-29`.

## Phase 4 — Close follow-through

- [ ] 4.1 `gh issue close 3015 --comment "<phase-1/2/3 evidence summary>"`.
- [ ] 4.2 Verify issue state via `gh issue view 3015 --json state` returns
  `CLOSED`.

## Notes

- PR body MUST use `Ref #3015` (not `Closes #3015`) per AGENTS.md
  `wg-use-closes-n-in-pr-body-not-title-to` ops-remediation extension.
- Every Phase 2 / Phase 3.1 command is destructive or sensitive prod read;
  per-command ack required (AGENTS.md `hr-menu-option-ack-not-prod-write-auth`).
