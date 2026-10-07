# Tasks: nav-pending e2e flake (#9666) and community-monitor full collector output (#9678)

Plan: `knowledge-base/project/plans/2026-10-07-fix-nav-pending-e2e-flake-and-community-collector-partial-plan.md`

## Phase 1: #9666 nav-pending flake (tests first)

- [ ] 1.1 Add RED island tests in `apps/web-platform/test/nav-pending-island.test.tsx`
  - [ ] 1.1.1 Mid-episode watcher mount does not cancel the episode (RED on main)
  - [ ] 1.1.2 Same under `<React.StrictMode>` (RED on main)
  - [ ] 1.1.3 Commit before watcher mount still ends the episode (GREEN guard)
- [ ] 1.2 Add a `noteNavLocation()` boolean-return case in `apps/web-platform/test/nav-pending-store.test.tsx`
- [ ] 1.3 Make `noteNavLocation()` return `boolean` in `apps/web-platform/lib/nav-pending-store.ts`
- [ ] 1.4 Change the commit-watcher effect in `apps/web-platform/components/nav/nav-pending-island.tsx` (first-run compare to store, later runs compare previous key; invariant comment)
- [ ] 1.5 Restructure `apps/web-platform/e2e/nav-states-nav-pending.e2e.ts`
  - [ ] 1.5.1 Add `holdNavFetch` and reuse it in the "never commits" test
  - [ ] 1.5.2 Add `clickNavLink` (React props hydration probe, click, `await hold.requested`)
  - [ ] 1.5.3 Rewrite the NavLink click test; delete the post-click `toHaveCount(0)`; comment the unit-level coverage
  - [ ] 1.5.4 Add the stress recipe as a header comment
- [ ] 1.6 Run `--repeat-each=30 --retries=0` idle and under CPU contention; record before/after counts for the PR body

## Phase 2: Collector compact mode

- [ ] 2.1 RED tests first: extend `plugins/soleur/skills/community/test/github-community.test.sh` with compact cases (worst-case fixtures, count parity, no-login, golden default output)
- [ ] 2.2 `github-community.sh`: `_emit_compact`, caps via `--argjson`, five projections, sort by `updated_at` before slice, discussions not-enabled path, typo warning
- [ ] 2.3 `discord-community.sh`: `_emit_compact` and four projections (`guild-info`, `channels`, `messages`, `members`)
- [ ] 2.4 Create `apps/web-platform/test/server/inngest/cron-community-monitor-compact-parity.test.ts` (PATH-shim `curl` for Discord, budget over dispatch-case commands, field and cap parity, probe arms)

## Phase 3: Handler flag and prompt

- [ ] 3.1 Add `SOLEUR_COLLECTOR_COMPACT: "1"` to the `buildSpawnEnv` wrapper in `cron-community-monitor.ts`
- [ ] 3.2 Update `COMMUNITY_MONITOR_PROMPT` field sentences; keep the `output-too-large` fallback
- [ ] 3.3 Update `cron-community-monitor.test.ts` (wrapper literal, rewritten GitHub external-counts test, compact fields)
- [ ] 3.4 Confirm allowlist and prompt-grammar suites pass unchanged

## Phase 4: Documentation and follow-through

- [ ] 4.1 ADR-273 addendum (compact collector mode; supersedes the Spike S3 accepted-partial wording; alternatives)
- [ ] 4.2 Rewrite the runbook `output-too-large` paragraph (include how to see what the agent saw)
- [ ] 4.3 Create `scripts/followthroughs/community-collectors-collected-9678.sh` (self-derived cut-off, two-digest PASS, TRANSIENT default, `--status-line` arm)
- [ ] 4.4 Add the follow-through directive and label to #9678

## Phase 5: Verify and ship

- [ ] 5.1 Run github-community suite, parity test, island and store tests, `tsc --noEmit`, `c4-count-parity.test.sh`, markdownlint
- [ ] 5.2 PR body: `Closes #9666`, `Ref #9678`, `Ref #9679`, before/after flake counts
