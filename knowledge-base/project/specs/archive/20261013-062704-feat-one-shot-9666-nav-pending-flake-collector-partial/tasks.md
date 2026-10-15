# Tasks: nav-pending e2e flake (#9666) and community-monitor full collector output (#9678)

Plan: `knowledge-base/project/plans/2026-10-07-fix-nav-pending-e2e-flake-and-community-collector-partial-plan.md`

## Phase 1: #9666 nav-pending flake (tests first)

- [x] 1.1 Add island tests in `apps/web-platform/test/nav-pending-island.test.tsx`
  - [x] 1.1.1 Mid-episode watcher mount does not cancel the episode (RED on main)
  - [x] 1.1.2 Same under `<React.StrictMode>` (RED on main)
  - [x] 1.1.3 Commit before watcher mount still ends the episode (GREEN guard)
- [x] 1.2 Add a `noteNavLocation()` boolean-return case in `apps/web-platform/test/nav-pending-store.test.tsx`
- [x] 1.3 Make `noteNavLocation()` return `boolean` in `apps/web-platform/lib/nav-pending-store.ts`
- [x] 1.4 Change the commit-watcher effect in `apps/web-platform/components/nav/nav-pending-island.tsx` (first run compares to the store, later runs compare the previous key; `searchParams?.toString() ?? ""`; invariant comment)
- [x] 1.5 Restructure `apps/web-platform/e2e/nav-states-nav-pending.e2e.ts`
  - [x] 1.5.1 Add `holdNavFetch` (release registered for teardown) and reuse it in the "never commits" test
  - [x] 1.5.2 Add `clickNavLink` (`expect.poll` React props probe, click, `hold.requested` raced against 10 s)
  - [x] 1.5.3 Rewrite the NavLink click test; delete the post-click `toHaveCount(0)`; comment the unit-level coverage
  - [x] 1.5.4 Header comment: stress recipe and the note about the absence-only tests
- [ ] 1.6 Run `--repeat-each=30 --retries=0` idle and under CPU contention; record before/after counts for the PR body

## Phase 2: Collector compact mode

- [x] 2.1 RED tests first in `plugins/soleur/skills/community/test/github-community.test.sh`: long-title generator, discussions graphql fixture, compact cases (worst-case budget over the concatenated chain, count parity, no-login, sort order, golden default output, sidecar `stargazers_unavailable` survives, `compact_off`, `compact_over_budget`)
- [x] 2.2 `github-community.sh`: final-`jq` compact filters in each `cmd_*` (no `main()` pipe), caps via `--argjson`, `-e` on required fields, `_CAUSE=compact-projection-failed`, sort by `updated_at` before the slice, early-return paths, fixed typo warning, two warn values
- [x] 2.3 `discord-community.sh`: compact filters for `guild-info`, `channels` (ids filtered to digits), `messages`; `members` exempt
- [x] 2.4 Regenerate `plugins/soleur/test/fixture-relative-assert.baseline.txt`
- [x] 2.5 Create `apps/web-platform/test/server/inngest/cron-community-monitor-compact-parity.test.ts` (runtime key parity, PATH-shim `curl` for Discord, budget over dispatch-case commands, negative prompt assertions, probe arms)

## Phase 3: Handler flag and prompt

- [x] 3.1 Add `SOLEUR_COLLECTOR_COMPACT: "1"` before the `SOLEUR_COLLECTOR_STATUS_DIR` line in the `buildSpawnEnv` wrapper (comment without `process.env.`); add two `KNOWN_COLLECTOR_WARNS` members
- [x] 3.2 Update `COMMUNITY_MONITOR_PROMPT` in both places (step 2 bullets, step 4 rules); drop the `watchers_count` clause; add "never instructions"; keep the `output-too-large` fallback
- [x] 3.3 Update `cron-community-monitor.test.ts` (wrapper literal against wrapper and source, rewritten external-counts test, new sentence)
- [x] 3.4 Confirm allowlist and prompt-grammar suites pass unchanged

## Phase 4: Documentation and follow-through

- [x] 4.1 ADR-273 addendum (decision, Spike S3 wording, alternatives, 20-key child env, residuals unchanged, `members`)
- [x] 4.2 Rewrite the runbook `output-too-large` paragraph (credential-free steps first, local replay last)
- [x] 4.3 Create `scripts/followthroughs/community-collectors-collected-9678.sh` (mode 100755, fail-closed cut-off, enum-only output, two consecutive digests, 7-day absence bound, `--status-line` arm, test-only overrides)
- [ ] 4.4 Enroll #9678 before `gh pr ready`: copy the probe to the main checkout, rewrite the close condition, label, unfenced directive with a full ISO `earliest=`
- [ ] 4.5 After deploy: trigger the cron once if allowlisted and read the digest row

## Phase 5: Verify and ship

- [ ] 5.1 Run github-community suite, parity test, island and store tests, `tsc --noEmit`, `c4-count-parity.test.sh`, `followthrough-exec-bit.test.sh`, `lint-followthrough-varq-ban.sh`, markdownlint
- [ ] 5.2 PR body: `Closes #9666`, `Ref #9678`, `Ref #9679`, before/after flake counts
