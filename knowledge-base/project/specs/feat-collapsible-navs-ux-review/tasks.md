# Tasks: soleur:ux-audit recurring UX-review agent loop

Derived from `knowledge-base/project/plans/2026-04-15-feat-ux-audit-skill-plan.md`. Owns #2341. Blocks #2342.

## Phase 1: Foundation (Supabase bot + Doppler + fixture)

- [x] 1.1 Provision Supabase auth user `ux-audit-bot@jikigai.com` — id `7dff92fd-3460-4ccf-bfa6-5be6f631cdb1`
  - [x] 1.1.1 Generate password: `openssl rand -base64 32`
  - [x] 1.1.2 Create user via Supabase Admin API (`email_confirm: true`, `user_metadata.synthetic=true`)
  - [x] 1.1.3 Verify user can sign in via `/auth/v1/token?grant_type=password`
- [x] 1.2 Add bot secrets to Doppler `prd_scheduled`
  - [x] 1.2.1 `UX_AUDIT_BOT_EMAIL = ux-audit-bot@jikigai.com`
  - [x] 1.2.2 `UX_AUDIT_BOT_PASSWORD = <generated>`
  - [x] 1.2.3 GH Actions secret `DOPPLER_TOKEN_SCHEDULED` exists (created 2026-03-25)
- [x] 1.3 Write `plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts` (**DB-only v1**)
  - [x] 1.3.1 `seed` subcommand (idempotent — uses `conversations.session_id` as idempotency key)
    - [x] 1.3.1.1 T&Cs at `TC_VERSION='1.0.0'`, `onboarding_completed_at=NOW()`, `subscription_status='active'`
    - [ ] 1.3.1.2 ~~Seed KB: 6 files~~ **Deferred to #2351** (files live in GitHub workspace, not Supabase)
    - [ ] 1.3.1.3 ~~Seed team: 2 synthetic members~~ **No team-members table exists** (single-user Phase 1 schema); closed here
    - [x] 1.3.1.4 Seed chat: 2 conversations (`session_id='ux-audit-fixture-conv-1|2'`), 3 + 4 messages
    - [ ] 1.3.1.5 ~~Seed services: Cloudflare integration stub~~ **No services table** (config stored elsewhere); closed here
    - [x] 1.3.1.6 Billing: `users.subscription_status='active'` + synthetic `cus_ux_audit_fixture` / `sub_ux_audit_fixture` placeholders
  - [x] 1.3.2 `reset` subcommand — deletes fixture conversations + messages, clears T&C/billing on bot `users` row
  - [x] 1.3.3 Fixture-invariant audit: only bot's own email appears; placeholder Stripe IDs (`cus_ux_audit_fixture`) don't match any real `cus_[A-Za-z0-9]{14,}` pattern
- [x] 1.4 Acceptance: RED→GREEN test suite (`plugins/soleur/test/ux-audit/bot-fixture.test.ts`) — 5/5 pass against prod Supabase: seed is idempotent (run twice → identical state), bot signs in post-seed, middleware guards (`tc_accepted_version`, `subscription_status`) cleared; reset restores clean state.

## Phase 2: Skill + audit-mode agent extension

- [x] 2.1 Create `plugins/soleur/skills/ux-audit/SKILL.md`
  - [x] 2.1.1 Frontmatter: `name: ux-audit`, third-person description (165 chars, 25 words)
  - [x] 2.1.2 Inline 5-category audit rubric (real-estate, ia, consistency, responsive, comprehension — no 6th)
  - [x] 2.1.3 Inline bot-fixture spec (DB-only v1 with KB deferral note)
  - [x] 2.1.4 Linked `route-list.yaml`, `bot-fixture.ts`, `bot-signin.ts`, `dedup-hash.ts` via proper markdown links
  - [x] 2.1.5 `CAP_OPEN_ISSUES = 20` and `CAP_PER_RUN = 5` documented inline
  - [x] 2.1.6 Cumulative skill description budget under 1800 words (verified via `bun test plugins/soleur/test/components.test.ts`)
- [x] 2.2 Create `plugins/soleur/skills/ux-audit/references/route-list.yaml`
  - [x] 2.2.1 Schema: `{path, auth, fixture_prereqs, viewport}`
  - [x] 2.2.2 11 routes (anonymous: landing/login/signup; bot: dashboard, kb, chat/new, 4 settings, accept-terms)
  - [x] 2.2.3 `auth: anonymous` for logged-out surfaces
  - [x] 2.2.4 `fixture_prereqs` accurate per route; `/dashboard/kb` marked `kb_workspace_deferred` per #2351
- [x] 2.3 Create `plugins/soleur/skills/ux-audit/scripts/bot-signin.ts` (GREEN: 2/2 tests)
  - [x] 2.3.1 `signInWithPassword` against prod Supabase via `/auth/v1/token?grant_type=password`
  - [x] 2.3.2 Writes storage state to `${GITHUB_WORKSPACE:-.}/tmp/ux-audit/storage-state.json` (absolute); override via `UX_AUDIT_STORAGE_STATE`
  - [x] 2.3.3 Cookie shape mirrors `apps/web-platform/e2e/global-setup.ts`: `sb-<project-ref>-auth-token`, JSON-stringified session, domain from `NEXT_PUBLIC_SITE_URL`
- [x] 2.4 Edit `plugins/soleur/agents/product/design/ux-design-lead.md`
  - [x] 2.4.1 Mode-branch documentation at top of `## Workflow` (routes on `mode: audit` in prompt)
  - [x] 2.4.2 New `## UX Audit (Screenshots)` section AFTER existing HTML-audit section
  - [x] 2.4.3 5-category rubric documented with examples per category
  - [x] 2.4.4 JSON output contract: `{route, selector, category, severity, title, description, fix_hint, screenshot_ref}`, explicit "no prose" instruction
  - [x] 2.4.5 `description:` frontmatter unchanged
- [ ] 2.5 ~~Build golden-set test~~ **DEFERRED to #2352** — zero `ux`-labeled closed issues with screenshots exist. Phase 3 Calibration becomes single validation path.
- [x] 2.6 Implement skill workflow steps in SKILL.md (all 10 sub-steps documented as executable instructions for claude-code-action)
  - [x] 2.6.1 Global cap check inline bash snippet
  - [x] 2.6.2 Per-route screenshot capture with absolute paths under `${GITHUB_WORKSPACE}/tmp/ux-audit/`
  - [x] 2.6.3 Task-tool invocation contract with `mode: audit`, `screenshots`, `routes`, `viewport`
  - [x] 2.6.4 Parse-guard: `::error::malformed agent output for route <path>`, skip route
  - [x] 2.6.5 Single-call dedup via `gh issue list --search "ux-audit-hash: $HASH"`
  - [x] 2.6.6 Severity-rank + `CAP_PER_RUN=5` cap
  - [x] 2.6.7 Dual-mode: `UX_AUDIT_DRY_RUN=true` → stdout + artifact; `false` → `gh issue create`
  - [x] 2.6.8 Issue body template with `ux:` title prefix, labels, milestone by title, hash comment
  - [x] 2.6.9 `browser_close` in cleanup step
  - [x] 2.6.10 `--route <path>` documented as dev affordance
- [x] 2.7 Unit test: dedup hash `sha256({route}|{selector}|{category})` (GREEN: 6/6 tests, empty selector coarsens to `*`, rejects invalid category)
- [ ] 2.8 Acceptance: local dry-run invocation — **moved to Phase 3** (requires Playwright MCP + live web-platform; natural fit with Phase 3 calibration)

## Phase 3: Workflow + governance + calibration

- [x] 3.1 Scaffold `.github/workflows/scheduled-ux-audit.yml` from `scheduled-competitive-analysis.yml` + `scheduled-community-monitor.yml` patterns
  - [x] 3.1.1 Template source mirrored
  - [x] 3.1.2 Pinned action SHAs (checkout, claude-code-action, Doppler, setup-bun, upload-artifact, DopplerHQ/cli-action)
- [x] 3.2 Workflow triggers
  - [x] 3.2.1 `push: branches: [main]` + `paths: [apps/web-platform/app/**, apps/web-platform/components/**]`
  - [x] 3.2.2 `schedule: cron: '0 9 1 * *'`
  - [x] 3.2.3 `workflow_dispatch: inputs: dry_run: {type: boolean, default: true}`
- [x] 3.3 Workflow job config (`timeout-minutes: 45`, permissions, concurrency group)
- [x] 3.4 Doppler load (two steps — `prd_scheduled` for bot creds via `DOPPLER_TOKEN_SCHEDULED`, `prd` for Supabase URL/keys via `DOPPLER_TOKEN_PRD`, both with `::add-mask::` + `$GITHUB_ENV`)
- [x] 3.5 Playwright setup with version read from `apps/web-platform/package.json` `devDependencies["@playwright/test"]`
- [x] 3.6 Skill invocation via `claude-code-action` with `UX_AUDIT_DRY_RUN` env; `claude_args` includes `Task` + targeted `mcp__playwright__*` tools; prompt forbids direct inline interpolation of agent output
- [x] 3.7 Labels pre-creation step (`ux-audit`, `agent:ux-design-lead`, `domain/product`)
- [x] 3.8 Failure notification — HTML body constructed in preceding step via env vars (per `hr-in-github-actions-run-blocks-never-use`), then passed to `notify-ops-email`
- [x] 3.9 `.github/workflows/scheduled-daily-triage.yml` — `gh issue list --jq 'map(select(.labels | map(.name) | index("ux-audit") | not))'` inline filter
- [x] 3.10 `.github/workflows/scheduled-bug-fixer.yml` — extended `select()` with `index("ux-audit") | not` clause
- [x] 3.11 Expense ledger line added to `knowledge-base/operations/expenses.md` (Anthropic API / ux-audit / $15/mo)
- [x] 3.12 TR4 decision pinned on #2343 via `gh issue comment`
- [x] 3.13 Plugin metadata
  - [x] 3.13.1 `plugin.json`: added `ux-audit` keyword (description stays domain-level per constitution convention)
  - [x] 3.13.2 `marketplace.json`: description suffix mentions `soleur:ux-audit`
  - [ ] 3.13.3 `plugins/soleur/README.md` skill count — will run `/soleur:release-docs` during ship
- [ ] 3.14 Calibration
  - [ ] 3.14.1 `gh workflow run scheduled-ux-audit.yml --ref collapsible-navs-ux-review --field dry_run=true`
  - [ ] 3.14.2 Download findings JSON artifact
  - [ ] 3.14.3 Assess top-5: does a `real-estate` or `ia` finding reference sidebars / nav / fixed-width real estate?
  - [ ] 3.14.4 **PASS path:** flip cron/push default to `dry_run=false`; commit `knowledge-base/project/learnings/2026-04-<day>-ux-audit-calibration.md` with passing rubric phrasing
  - [ ] 3.14.5 **MISS path:** tune rubric once; re-run dry
  - [ ] 3.14.6 **STILL MISS path:** ship with `dry_run` default permanently `true` (filing disabled); `gh issue create --title "ux-audit calibration failed" --milestone "Post-MVP / Later"` with rubric attempts; unblock #2342 manually on founder judgment
- [ ] 3.15 Acceptance: workflow `gh workflow run` success within 45 min; calibration resolves via one of the 3 paths; `ux-audit` labels do NOT appear in next run of `scheduled-daily-triage.yml` or `scheduled-bug-fixer.yml` candidate lists

## Phase 4: Testing

- [ ] 4.1 Acceptance test suite (workflow-level)
  - [ ] 4.1.1 Dry-run produces JSON artifact with ≥ 1 finding/route, no `gh issue create` calls
  - [ ] 4.1.2 Dedup: run #1 files N → run #2 (unchanged UI) reports `dedup-suppressed: N, filed: 0`
  - [ ] 4.1.3 Global cap: 20 open issues → 21st finding suppressed with `::warning::`
  - [ ] 4.1.4 Failure email: inject deliberate failure step on test branch → verify `ops@jikigai.com` receives email
  - [ ] 4.1.5 Auto-triage exclusion: open test `ux-audit` issue → run `scheduled-daily-triage.yml` → verify not in candidate list
  - [ ] 4.1.6 Auto-fix exclusion: open test `ux-audit` issue with `priority/p1` → run `scheduled-bug-fixer.yml` → verify not selected
  - [ ] 4.1.7 Branch filter: push to feature branch touching `apps/web-platform/app/**` → verify workflow does NOT trigger
- [ ] 4.2 Regression tests
  - [ ] 4.2.1 `ux-design-lead` without `mode: audit` → Pencil flow unchanged
  - [ ] 4.2.2 `/soleur:qa` on UI diff → behaves identically to pre-ux-audit baseline
- [ ] 4.3 Edge cases
  - [ ] 4.3.1 Unmet `fixture_prereqs` → route skipped, logged, not aborted
  - [ ] 4.3.2 Expired bot creds → fast-fail → notify-ops-email
  - [ ] 4.3.3 Malformed agent JSON → `::error::` logged, route skipped
  - [ ] 4.3.4 Empty selector → hash coarsens to `{route}|*|{category}`
- [ ] 4.4 Integration verification (for `/soleur:qa`)
  - [ ] 4.4.1 `gh issue list --label ux-audit --state open --jq 'length'` ≤ 20
  - [ ] 4.4.2 `doppler secrets get UX_AUDIT_BOT_EMAIL --config prd_scheduled --plain` = `ux-audit-bot@jikigai.com`
  - [ ] 4.4.3 Browser: bot sign-in → `/dashboard/kb` → ≥ 6 KB files visible
  - [ ] 4.4.4 `gh workflow run scheduled-ux-audit.yml --ref main --field dry_run=true` → `conclusion=success` ≤ 45 min
- [ ] 4.5 NFR verifications
  - [ ] 4.5.1 Run `/soleur:architecture assess` vs `knowledge-base/engineering/architecture/nfr-register.md`; attach output to PR
  - [ ] 4.5.2 Verify `/ship` Phase 5.5 CMO content-opportunity gate fires at this PR (file-path match)

## Phase 5: Ship

- [ ] 5.1 Commit artifacts
- [ ] 5.2 PR body: `Closes #2341`, `Ref #2343`, `Ref #2344`, `## Changelog` section
- [ ] 5.3 Apply `semver:minor` label (new skill)
- [ ] 5.4 Run `/soleur:review` before marking ready
- [ ] 5.5 Run `/soleur:qa` with screenshots if any UI-adjacent changes
- [ ] 5.6 Run `/soleur:ship` — enforces compound + CMO/COO gates
- [ ] 5.7 Post-merge: `gh workflow run scheduled-ux-audit.yml --ref main --field dry_run=true` and verify (per `wg-after-merging-a-pr-that-adds-or-modifies`)
- [ ] 5.8 Verify release workflow green (per `wg-after-a-pr-merges-to-main-verify-all`)
- [ ] 5.9 File follow-up issues
  - [ ] 5.9.1 `feat(marketing-site): "Built by agents, in public" link to ux-audit issue query`
  - [ ] 5.9.2 If calibration passed: draft blog post "We gave our UX reviewer a cron job" via copywriter (CMO content-opportunity gate)
