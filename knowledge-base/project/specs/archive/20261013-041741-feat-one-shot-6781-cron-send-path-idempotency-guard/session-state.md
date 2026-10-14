# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-07-20-fix-cron-statutory-repin-idempotency-guard-plan.md`
- Status: complete

### Errors
Review caught seven author errors in the planning subagent's own drafts; all corrected in-session and recorded in the plan rather than quietly fixed:

- Fabricated claim — the existing cron test's fake was said to throw `unexpected table` as a Risks mitigation. Verified zero occurrences; the fake accepts any table and returns a clean insert, so the guard would have been exercised but entirely unverified.
- False observability claim — step-return counters were claimed to reach Better Stack. `vector.toml` keeps only `level_int >= 40`, so they are dropped.
- False Sharp Edge — a `CHECK` constraint was said to break DSAR `parseTables`. Empirically false (51/51 tables parse).
- Vacuous AC — AC3's `grep -c 'statutory_repin_send'` self-matched the migration that creates the table.
- Contradictory ACs — AC5 ("dispatch only on a clean insert") forbade the fail-open AC6 required.
- Wrong verification form — AC13 used a two-dot diff and asserted filename-absence for a file the plan permits touching.
- Wrong justification — item-grain was claimed to be recipient-grain structurally; migration 111 makes items visible to every workspace Owner, so that holds only while the send path is single-recipient.

**CPO gate: RETURNED 2026-07-20.** C2 UPHELD (no code change), C5 AMENDED (T12 tripwire added, which blocks PR-ready). See the plan's CPO conditions table.

### Decisions
- Tick identity is branch-derived, not a single value. The repin has two cadences (one-shot T-7, daily band). `daysUntilDue` produces a same-day duplicate; a bare calendar date fixes the band but leaves the T-7 duplicate live, because `daysUntilDue === 7` spans a 24h window straddling two dates under ~5 min of jitter. Key is `'headsup'` (constant) or `'daily:YYYY-MM-DD'`.
- No `CREATE OR REPLACE` of existing RPCs. Security attributes don't survive a replace and both AP-018 guard tiers are blind to the drop; the anonymise `UPDATE` rebinds `GET DIAGNOSTICS`; the purge step's failure zeroes the entire danger band.
- `user_id` dropped, DSAR routed via exclusion. Retention-by-cascade was false (statutory parents are never purged), so the sweep is explicit. `joinVia` is not data-driven, so an allowlist entry would export nothing while hard-failing an unlisted test.
- Fail open on everything except a clean 23505, including thrown rejections — an unhandled throw escapes `step.run` and, under `retries: 0`, also kills the ingress liveness probe.
- A delivery-path hole changed the design: `sendPushNotifications` prunes 410 rows, so a two-run self-heal exists today and the guard destroys it. Added a zero-delivery signal, an operator release verb, and marker-placement-after-guards.

### Components Invoked
`soleur:plan` · `soleur:plan-review` · `soleur:deepen-plan` · `soleur:gdpr-gate` · agents: `cto`, `clo`, `cpo`, `dhh-rails-reviewer`, `kieran-rails-reviewer`, `code-simplicity-reviewer`, `architecture-strategist`, `spec-flow-analyzer`, `data-integrity-guardian`, `observability-coverage-reviewer`, `test-design-reviewer`, `user-impact-reviewer`, `Explore` ×2

## Work Phase
- Status: complete. Migration 135 + guard + tests + compliance surfaces landed.

## Review Phase
- Status: complete. Nine agents. One P1 found and fixed: the marker insert used
  `.select("id")` on a table with no `id` column, which would have made the guard
  permanently inert in production while 20/20 tests passed. Three agents converged on it
  independently. A second plan requirement — the operator release verb — was found to have
  been LOST in the Phase-4 renumbering rather than deferred, and was recovered.
  All findings were pr-introduced and fixed inline; zero filed as scope-out.
