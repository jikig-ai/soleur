# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-fix-realtime-phoenix-join-3049/knowledge-base/project/plans/2026-05-11-fix-realtime-phoenix-join-verify-and-determinism-gate-plan.md
- Status: complete

### Errors
None during planning. Key discovery: the fix for #3049/#3052 already landed via PR #3058 on 2026-04-29 (`globalThis.WebSocket = ws` polyfill helper at `apps/web-platform/test/helpers/node-websocket-polyfill.ts`). Integration test was re-verified at plan time — 3/3 green against dev in 11s. The four hypotheses from the brief (Phoenix vsn, CF WS quirk, supabase-js version pin, apikey-in-join) were all investigated and ruled out in the original #3052 cycle; the actual root cause was `@supabase/realtime-js@2.99.2`'s factory returning `{ type: 'unsupported' }` on Node <22.

### Decisions
- **Scope** the PR to: (1) re-verify contract holds locally and link in PR body, (2) implement the deferred #3060 nightly determinism gate as `.github/workflows/scheduled-realtime-probe.yml` (mirrors `scheduled-oauth-probe.yml` pattern), (3) breadcrumb the workflow into the existing learning file. No production code changes; the polyfill helper is unchanged.
- **Doppler scope correction (deepen-pass)**: original draft referenced non-existent `DOPPLER_TOKEN_DEV_CI`. Live `gh secret list` + `doppler configs -p soleur` discovery showed no dev-scoped scheduled token and no `dev_scheduled` config exist. Plan now requires operator pre-merge step to create both (Phase 2.0) with graceful `secret_unset` failure mode if absent at first run.
- **Reject prd creds reuse**: GitHub-stored `NEXT_PUBLIC_SUPABASE_*` secrets are prd values (`api.soleur.ai`). Workflow must fetch dev creds via Doppler at runtime per `hr-dev-prd-distinct-supabase-projects`. Workflow asserts `doppler configs get dev_scheduled -p soleur --json | jq -r .environment` returns `dev` before probing.
- **#3060 chose option 1** (nightly probe, not pre-merge integration job) — bounded to 1 run/day, no synthetic-user create/destroy, exercises the regression signal directly.
- **PR title MUST NOT contain auto-close keywords**: per `wg-use-closes-n-in-pr-body-not-title-to` and #3185 precedent, title is `chore(realtime): nightly determinism gate for cross-tenant isolation` (no `close|fix|resolve` + `#N`).
- **Issue close lifecycle**: use `Ref #3049` / `Ref #3060` in PR body, manually `gh issue close` post-merge after PM1 confirms green run — matches ops-remediation pattern from `2026-04-24-pr-body-ref-not-closes-for-ops-remediation`.

### Components Invoked
- `Bash` (verifications: gh issue/PR/secret/label/api, doppler configs/secrets, file existence, rule-ID audit, integration test run, probe run)
- `Read` (existing learning file, integration test source, scheduled-oauth-probe.yml template)
- `Write` (plan file, tasks.md)
- `Edit` (plan enhancements during deepen-pass)
- `Skill` (soleur:plan, soleur:deepen-plan)
- Live API verification: `gh api repos/actions/checkout/git/refs/tags/v4.3.1` (SHA pin confirmed)
- Gate enforcement: Phase 4.6 User-Brand Impact halt (PASS), Phase 4.5 Network-Outage Deep-Dive (triggered by `timeout`/`handshake`; L3-L7 layer-by-layer documented as retrospective gate-fire)
