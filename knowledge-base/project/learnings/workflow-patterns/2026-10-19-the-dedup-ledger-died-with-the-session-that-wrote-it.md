# Learning: the dedup ledger died with the session that wrote it — persist it to session-state.md

## Problem

A `soleur:review <PR> --fix-round --since <sha>` invoked from a RESUMED session (fresh context, resume prompt carrying only SHAs) has no access to the dedup ledger the prior session's panel emitted. The fix-round contract degrades gracefully — `fix-round-seats.sh` falls back to path-mapped seats only, the fail-safe direction — but the `--finding-seats` union is lost: a fix commit closing a finding no longer re-spawns the seat that reported it, which is the strongest signal in the round (the reporter re-checks its own finding against the fix).

Measured on #9771's fix round: the ledger existed only in the compacted session's conversation. Neither `session-state.md` nor the fix commit's body named the reporting seats, and no review summary was posted to the PR, so the union could not be reconstructed — the round ran path-mapped and disclosed the degradation.

The reference already documented the degrade as "known, fail-safe" — but documented-safe is still lossy every time a pipeline resumes, which is every non-trivial fix round.

## Solution

`skills/review/references/risk-tier-and-fix-rounds.md` now prescribes appending the dedup ledger to `knowledge-base/project/specs/<feature>/session-state.md` at panel synthesis — the same file that already carries `status`, forwarded errors, and resume context, so the write rides an existing carrier rather than inventing one.

## Key Insight

A durable artifact is only durable if it survives the context boundary the mechanism is designed for. `--finding-seats` exists precisely for the cross-session case; keeping its input conversation-scoped meant the flag could never do its job in the scenario it exists to serve. The generalization: any "emitted artifact" a later session consumes must land on disk at emission time — session-state.md is this repo's carrier.

## Session Errors

- **`found_code` mutation-verify pattern typo (this session).** A verify-by-mutation probe passed `&\$` where the suite uses `&\s*$` — in ERE `\$` is a literal dollar, so the probe read 0 for a line it should have matched. Re-ran with the suite's own pattern shape; result 1 as expected. — Recovery: re-ran with correct pattern. — Prevention: none (one-off typo; the want-vs-got line caught it in seconds — discoverability exit applies, no rule warranted).
- **Dedup ledger unpersisted across the resume (this session, recurring).** See Problem. — Recovery: ran the round path-mapped and disclosed it in the trailer summary. — Prevention: `risk-tier-and-fix-rounds.md` now prescribes persisting the ledger to `session-state.md` at synthesis (fixed inline in this branch).
- **`TEST_GROUP=affected` capacity contended at verification time (this session).** `test-all.sh --capacity` reported `CAPACITY_CONTENDED` (17 sibling runs, including stale ones in this worktree). Per the #9505 learning, the lead relied on the targeted suite directly (`test-pyramid-fixtures.test.sh` 84/84) rather than queueing — disclosed, not hidden. — Prevention: already covered by the fix-round reference's #9505 bullet; no new machinery.
- **Forwarded from session-state.md (prior phases, recorded there):** `gh pr view --json merged` field renamed (`mergedAt`); missing spec.md → `lane: cross-domain` fail-closed default; markdownlint MD032 ×4 on the plan draft (fixed); deepen-plan Phase 4.7 observability detection remedied with an honest `## Observability` block. — Prevention: all already diagnosed at their source; nothing new warranted.

## Prevention

- The reference's new "Persist the ledger" paragraph is the enforcement surface (skill instruction tier — the ledger is written by the orchestrating lead, not a hookable tool call).
- `emit-review-trailer.sh --fix-round` already forces `--since`; the remaining gap was upstream of it and is now closed by convention.
