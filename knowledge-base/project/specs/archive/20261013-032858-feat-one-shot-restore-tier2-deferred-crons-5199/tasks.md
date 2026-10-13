# Tasks — Restore Tier-2 deferred crons (scoped to cron-ux-audit)

Plan: `knowledge-base/project/plans/2026-06-12-feat-restore-tier2-deferred-crons-plan.md`
Issue: #5199 (Ref, not Closes — durable anchor for the remaining 8) · Gated-by: #5138
lane: cross-domain · brand_survival_threshold: single-user incident · requires_cpo_signoff: true

**Scope:** restore ONLY `cron-ux-audit` (the one cron with no PR/auto-merge surface → un-gated by #5138). The other 8 stay deferred (6 PR-flow + community-monitor are `mergeMode:auto` → #5138-gated; bug-fixer shares the auto-merge silent-disarm risk).

## Phase 0 — Preconditions
- [ ] 0.1 `gh issue view 5138 --json state,closedByPullRequestsReferences` → still OPEN + zero closing PRs. If landed, RE-SCOPE to include auto crons.
- [ ] 0.2 Read `plugins/soleur/skills/ux-audit/SKILL.md` + `references/route-list.yaml`; enumerate EVERY bash verb the prompt can emit (incl. any `gh api -f body=@file` attachment — the hook's `argumentInjectionReason` denies `=@`). Confirm the `CRON_BASH_ALLOWLISTS` entry finitely covers all of them.
- [ ] 0.3 Confirm `route-list.yaml` targets resolve via `NEXT_PUBLIC_APP_URL` → `app.soleur.ai`/`soleur.ai` (already in `cron-egress-allowlist.txt:56-58`). No firewall edit.
- [ ] 0.4 Confirm whether the prod image pre-installs `@playwright/mcp` (decides pin+bake vs allowlist `registry.npmjs.org` — NOT currently allowlisted).
- [ ] 0.5 Read `cron-bash-allowlist-hook.mjs:316-428` — confirm hook input is `argv[2]` allowlist file ONLY (no cronName); design the file-driven MCP-allow extension.

## Phase 1 — Token narrowing + dry-run flip (`cron-ux-audit.ts`)
- [ ] 1.1 Narrow mint at `:227` → `{ permissions: ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS, repositories: [REPO_NAME] }` (import from `_cron-shared.ts`).
- [ ] 1.2 Flip `UX_AUDIT_DRY_RUN` from hardcoded `"true"` (`:308`) to live (confirm intent). Adopt output-aware heartbeat (`resolveOutputAwareOk`) or `ensureScheduledAuditIssue` FAILED self-report so a 0-issue run is not silent-green.
- [ ] 1.3 Pin `@playwright/mcp` to an exact version (not `@latest`, `:256`); image-bake or allowlist `registry.npmjs.org`.

## Phase 2 — File-driven MCP-allow hook relaxation (LOAD-BEARING)
- [ ] 2.1 Extend `cron-allow.txt` format with an MCP-allow section; add a `CRON_MCP_ALLOWLISTS` map (or extend per-cron entry) listing ux-audit's 5 Playwright tools. Wire through the allowlist write path (`_cron-claude-eval-substrate.ts:403-408`).
- [ ] 2.2 Hook: parse MCP-allow lines into `mcpAllowPrefixes`; in `default:` (`:397`), allow `mcp__` tools in the set, else deny. Keep `WebFetch`/`WebSearch` denied.
- [ ] 2.3 Hook: `browser_navigate` URL-origin guard — deny non-`NEXT_PUBLIC_APP_URL`-origin + secret-bearing query strings. Pass the origin via the allowlist file.
- [ ] 2.4 Add `storage-state.json` + `tmp/ux-audit/` to `SECRET_PATH_PATTERNS` (`:74-86`).
- [ ] 2.5 Extend `runHookSelfTest` (`:426`): positive (app-origin navigate allowed for ux-audit) + negative (off-origin/off-list mcp/WebFetch denied). Fail-open aborts cron.

## Phase 3 — Allowlist + defer-set edits
- [ ] 3.1 Add `cron-ux-audit` to `CRON_BASH_ALLOWLISTS` (`_cron-claude-eval-substrate.ts:145`).
- [ ] 3.2 Remove `cron-ux-audit` from `TIER2_DEFERRED_CRONS` (`_cron-shared.ts:337-347`).
- [ ] 3.3 Update the deferral block comment (`:311-336`) + runbook (`cloud-scheduled-tasks.md`): 8 deferred; correct the bug-fixer/community-monitor "firewall-dependent" prose to "#5138-gated auto-merge".

## Phase 4 — Tests (RED first)
- [ ] 4.1 Hook unit test (ux-audit allowlist): denies exfil bash, allows `gh issue create` + 5 Playwright tools (app origin), denies off-origin navigate, denies off-list mcp + WebFetch, denies Read of `storage-state.json`.
- [ ] 4.2 CROSS-CRON NEGATIVE: hook + `cron-legal-audit` allowlist → `mcp__playwright__browser_navigate` DENIED.
- [ ] 4.3 Parity test: `cron-ux-audit` in `CRON_BASH_ALLOWLISTS` (+ MCP map) ⇔ absent from `TIER2_DEFERRED_CRONS`.
- [ ] 4.4 Token test: ux-audit mints `ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS`.
- [ ] 4.5 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; `./node_modules/.bin/vitest run <touched paths>` green.

## Phase 5 — Live validation (post-merge)
- [ ] 5.1 After deploy (`web-platform-release.yml` restarts container on merge), `/soleur:trigger-cron cron/ux-audit.manual-trigger` live: hook self-test passes, Playwright reaches the app, a `scheduled-ux-audit` issue files (or clean cap-out), GREEN monitor, no `egress-blocked:`/`egress-dns-exfil:` log.

## Ship
- [ ] PR body: `Ref #5199` (NOT Closes — #5199 stays open for the 8 deferred); note #5138 must land before the auto crons + bug-fixer's auto-merge risk.
- [ ] CPO sign-off (single-user-incident threshold) before /work; security review of the MCP-allow + URL-origin guard.
