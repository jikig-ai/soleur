---
feature: feat-one-shot-cron-community-monitor-spawn-liveness
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-03-fix-cron-community-monitor-max-turns-exhaustion-plan.md
status: planned
---

# Tasks — fix cron-community-monitor max-turns exhaustion

Root cause (confirmed from live Sentry event eff0bef435664f4d929d2ac3aa3e6a7e):
`stdoutTail: "Error: Reached max turns (50)"`, exitCode 1, empty stderr, ~6 min elapsed
(turn-count exhaustion, NOT wall-clock). The output-aware liveness assertion is correct;
the producer's 50-turn budget is too small. Fix = raise to daily-triage parity (80).

## Phase 0 — Preconditions
- [ ] 0.1 Read `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` in full.
- [ ] 0.2 Read `apps/web-platform/test/server/inngest/cron-community-monitor.test.ts` in full;
      confirm the 27 prompt anchors + `MAX_TURN_DURATION_MS` assertion (enumerated in plan
      Research Insights) are the edit blast radius.
- [ ] 0.3 Confirm daily-triage comparator (`--max-turns 80`, `MAX_TURN_DURATION_MS 60min`).

## Phase 1 — Raise the turn budget (confirmed fix)
- [ ] 1.1 Edit `CLAUDE_CODE_FLAGS` `--max-turns` `50` → `80` in cron-community-monitor.ts.
- [ ] 1.2 Update the header-comment rationale (line ~35 `--max-turns 50 (was 40)`) to the new
      value + add the timeout-to-turns ratio line (50 min / 80 = 0.625 min/turn, in-band),
      citing the max-turns-budget learning + daily-triage comparator.
- [ ] 1.3 Decide `MAX_TURN_DURATION_MS`: keep 50 min (ratio in-band) → keep test assertion
      `toBe(50 * 60 * 1000)`. If raised, update the test assertion in the SAME commit.

## Phase 2 — Prompt turn-efficiency (secondary lever; keep minimal)
- [ ] 2.1 Conservative default: budget bump alone may suffice (AC9 is the empirical gate). If
      editing the prompt, avoid all 27 anchored substrings OR update the matching test anchor
      in lockstep. Any reorder of the Persist-via-PR (step 5) / Create-Issue (step 6) steps is
      anchor-affecting — treat as test-touching.

## Phase 3 — Tests
- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-community-monitor.test.ts` — green.
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.
- [ ] 3.3 Confirm `#4730` heartbeat block still green: `SUT_SOURCE.not.toContain("ok: spawnResult.ok")`
      + `toContain("resolveOutputAwareOk(")` hold.

## Phase 4 — Live verification (post-merge / automated)
- [ ] 4.1 Trigger one live run via `/soleur:trigger-cron` (event
      `cron/community-monitor.manual-trigger`).
- [ ] 4.2 Confirm a `[Scheduled] Community Monitor - <date>` issue (label
      `scheduled-community-monitor`) was created in the run window
      (`gh issue list --label scheduled-community-monitor --state open --search 'Community Monitor in:title'`).
- [ ] 4.3 Confirm the Sentry monitor posted `status=ok` for that fire (check-ins API). If still
      `Reached max turns (N)`, the prompt-efficiency lever was insufficient — re-open with the
      new stdoutTail evidence.

## Out of scope (do NOT fold in)
- `ensure-labels: 3/3 failed` (WEB-PLATFORM-B) — belongs to `cron-follow-through-monitor`, a
  separate cron (the `gh auth login` unauth class, learning 2026-06-01-inngest-cron-gh-cli).
- Relaxing the `artifact-required` heartbeat contract — the monitor is correct.
- Narrowing `--allowedTools` (bucket-ii security-surface change).
- Sandbox / `DEFAULT_CLAUDE_SETTINGS` widening — refuted hypothesis.
