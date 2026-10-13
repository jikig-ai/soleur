# Decision Challenges — feat-one-shot-6143-cron-dedup-cohort-followups

Recorded during plan + plan-review (headless). Surfaced by /ship into the PR body + an
`action-required` issue for operator visibility. Both are advisory Taste/User-Challenge items the
plan resolved with a stated decision + rationale; neither blocks the fix.

## 1. Should Part 2 (cohort-wide title-date pin) be done at all? — DHH plan-review (Taste)

- **Class:** taste (scope challenge).
- **Source:** DHH plan-review (MED / YAGNI).
- **DHH found:** the cross-UTC-midnight skew Part 2 fixes is near-unreachable on the actual
  schedules — the cohort crons fire at `0 8 * * *` / `0 9 * * 1` etc., nowhere near 00:00 UTC; the
  skew only bites a **manual trigger** fired within minutes of midnight, and its failure is a rare
  duplicate/over-suppressed digest (itself cosmetic). The plan dismisses the *identical* rarity for
  secondary dates as an accepted #5786 paper-cut, yet spends the bulk of the change pinning the
  title for the same near-midnight condition. "Do nothing on Part 2" is a legitimate option.
- **Decision: KEEP Part 2.** #6143 is the issue that explicitly judges the pin worth doing ("If
  determinism is later judged worth it, pin `runStartedAt.slice(0,10)` into all prompts … in one
  cohort-wide change"); it is the #6139 DHH-#2 deferral now being actioned. The pin is cheap
  (9 one-line title swaps + one 3-line helper), eliminates the skew class by construction, and the
  all-9-at-once cohort approach avoids the snowflake #6139's decision-record warned against. Doing
  it now (bundled atomically with the Part 1 bug fix that removes community-monitor's broader 24h
  prompt rule and thereby *exposes* the same-date skew) is the intended scope.
- **If the operator disagrees:** Part 2 can be dropped and #6143 closed on Part 1 alone, re-filing
  the pin as its own deferral. The Part 1 bug fix stands independently.

## 2. Tighten `verifyScheduledIssueCreated` to `created_at` per-cron? — scoped-advisor consult (Taste)

- **Class:** taste (design alternative; the source issue implied removing the updated_at path).
- **Source:** plan Step 4.5 scoped-advisor consult (fable).
- **Advisor proposed:** instead of blanket-keeping the shared `updated_at`/`since` filter, add a
  per-caller mode — `created` (`created_at`, the 8 create-only crons) vs `touched` (`updated_at`,
  campaign-calendar only). This faithfully answers #6143's implied "remove the updated_at-crediting
  path where unneeded" AND removes a false-GREEN exposure: an always-create cron that silently fails
  to create, while a stray comment touches an old same-label issue inside the run window, is
  credited green under the blanket updated_at filter.
- **Decision: KEEP the blanket `updated_at` filter (reject per-cron mode for this PR).** The whole
  eng panel converged against the tightening: (a) `updated_at ≥ created_at` always, so the current
  filter is a strict superset — it can only over-credit, never lose a needed signal (Kieran);
  (b) the one updated_at-specific false-GREEN vector (an OLD out-of-window issue bumped in-window)
  is narrow, pre-existing (exists on main for all 9 crons today), and *shrinks* for community-monitor
  post-Part-1; (c) the FAILED-audit-stub false-GREEN is **orthogonal** to the created_at/updated_at
  axis — a stub is *created* in-window, so `created_at` would credit it too; tightening fixes
  nothing there (architecture-strategist); (d) per-cron mode changes 8 crons' monitor semantics for
  a low-probability stray-comment race — scope creep on a p3 chore. **Instead** the plan adopts CTO
  P2: re-point the citation to campaign-calendar's *stable* comment-bump marker and add a
  `cron-shared.test.ts` assertion that campaign-calendar still carries that path — so if the coupling
  ever dissolves, CI goes red and tells the next engineer "the filter may now be removable." That
  test-enforced invariant is the durable version of the re-evaluation #6143 asked for.
- **If the operator wants the tightening:** it is recorded as plan Alternative A1 and can be a
  follow-up (created_at for the 8 create-only crons, updated_at for campaign-calendar) once the
  coupling-invariant test is in place to gate it.
