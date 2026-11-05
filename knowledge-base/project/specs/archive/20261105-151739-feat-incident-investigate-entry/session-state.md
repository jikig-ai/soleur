# Session state — feat-incident-investigate-entry

PANEL_SHA: `808ad378084e19931bb281b30006c31d0d4dc29f`
PR: 12143
Tier: single-user incident
structural-cause roll-up: none

## Dedup ledger

| raw finding | canonical defect key | reporting seat(s) | planned fix commit |
|---|---|---|---|
| Printed Better Stack table is a fixed literal; the query follows inherited `BS_TABLE` / `BS_TABLE_S3` | pr-introduced coverage-record table not pinned to the command | soleur:engineering:review:code-quality-analyst | review: pin the queried table and the shown card lines (P1) |
| Sentry run card keeps `exit=N` and drops `401` / `credential-refused` already computed for the marker | pr-introduced sentry run card drops the marker reason | soleur:engineering:review:pattern-recognition-specialist | same commit |
| Prose says the application line always carries `ref=` | pr-introduced ref prose overclaims skip lines | soleur:engineering:review:pattern-recognition-specialist | same commit |
| Spec FR3/FR4 and the goals line still promise ranked hypotheses, unverified, and a pull time | pr-introduced spec contradicts the fence | soleur:engineering:review:pattern-recognition-specialist | same commit |
| `mktemp` follows `TMPDIR` into the worktree | pr-introduced reader temp can land in the tree | soleur:engineering:review:code-quality-analyst | same commit |
| Unset `CLAUDE_PLUGIN_ROOT` dies mid-pull with no halt | pr-introduced unbound plugin root skips the halt | soleur:engineering:review:code-quality-analyst | same commit |
| `^[A-Za-z0-9_-]+$` accepts `--redact` and the fence execs it | pr-introduced leading-dash issue id is executed | soleur:engineering:review:code-quality-analyst | same commit |
| Inherited xtrace prints the complaint before the sentinel | pr-introduced complaint visible in an inherited trace | soleur:engineering:review:code-quality-analyst | same commit |
| "all three are wrapper" is false when Sentry has no id | pr-introduced wrapper prose overclaims sentry | soleur:engineering:review:code-quality-analyst | same commit |
| Suite never runs the Phase 0 fence, so the halt and the two-line ref are unpinned | pr-introduced fence behavior unpinned by the suite | soleur:engineering:review:test-design-reviewer | same commit |
| Supabase marker prints empty `reason=` when the stdout has no pair | pr-introduced empty supabase reason on a missing pair | soleur:engineering:review:pattern-recognition-specialist | same commit |
| INT/TERM/HUP deletes temps and the same shell continues into later readers | pr-introduced signal continues the pull | soleur:engineering:review:code-quality-analyst | same commit. CTO CONCUR: Phase 0 exits 130/143/129; EXIT stays rm-only; Phase 6 unchanged |
| Sentinel exit 1 emits a second marker trio | pr-introduced card-redaction-failed is a second trio | soleur:engineering:review:pattern-recognition-specialist | wontfix: code-quality says both facts stay |
| Sentry no-id card is `sentry: not-queried` rather than `verdict=not-queried` | pr-introduced sentry no-id grammar | soleur:engineering:review:pattern-recognition-specialist | wontfix: that string is the tested no-id contract |
| `hypotheses=none` is always what the shell executes | pr-introduced hypothesis comment is not a ranker | soleur:engineering:review:agent-native-reviewer | wontfix: safe card, not a ranker to add |
| Inherited xtrace prints the complaint at the assignment above `set +x` | pr-introduced complaint assignment traced before the sentinel | soleur:engineering:review:security-sentinel | review: hide the complaint assignment from an inherited trace (P2) |
| FR4 says a wrapper line names the table or ref | pr-introduced spec wrapper line overclaims the ref | soleur:engineering:review:pattern-recognition-specialist | same commit |
| `env -u BS_TABLE` needle also matches `env -u BS_TABLE_S3` | pr-introduced table-unset pin is a prefix | soleur:engineering:review:test-design-reviewer | same commit |
| Inside-worktree halt exits before the EXIT trap, leaving empty temps | pr-introduced halt leaves empty temps | soleur:engineering:review:code-quality-analyst | wontfix: files are empty, no reader has written them |

dedup: 19 raw → 19 unique. No two findings share one root cause.

## Disposition notes

- User-impact: no open failure mode. The four design-pass defects stay mitigated at PANEL_SHA.
- Security, performance, data-integrity, agent-native, git-history, semgrep: no P0/P1/P2.
- Do not collapse the card-redaction-failed trio. Do not add a fifth verdict token. Do not teach `pull-card.sh` the Sentry reason tokens.
- The trap decision is closed. Phase 0 exits 130/143/129. EXIT stays rm-only. Phase 6 is unchanged.
- Fix round 1 at `3002ff4aa6` closed the twelve rows above it. Security's remaining P2 is the complaint assignment, fixed in the next review commit. The empty-temp halt stays.
