# Decision Challenges — feat-one-shot-12579-enqueue-rejection

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Finding 2 semantics — document precondition in script comment vs. move enqueue to retry-on-check-complete | technical | pending - assumed: document precondition + defer retry to tracking issue #12652 — GitHub docs confirm `enqueuePullRequest` refuses unmet protection (`Pull request Required status check "<name>" is expected.`), consistent with the #12562 refusal on pending `quality-guards`; when protection is met, armed auto-merge already self-enqueues (ADR-270 addendum 2026-10-07 measurement), so a retry surface buys no observed property. Resolved by research (docs + script source + ADR-270), not a CTO spawn — no agent-spawn tool available in this planning subagent. |
| Capture shape — `2>&1` into `enq_out` vs. separate stderr temp file | technical | pending - assumed: `2>&1` — issue's suggested ~3-line shape; `gh api graphql` writes only the body to stdout on success and the jq position-parse already tolerates noise (`\|\| echo '?'`). A second file adds cleanup surface for zero behavioral gain. |
| Sanitization shape — bash parameter expansion vs. repo-canonical `tr` pipeline | technical | pending - assumed: `tr '\n' ' ' <<<"$enq_out" \| tr -d '[:cntrl:]' \| cut -c1-300` — deepen-pass precedent-diff (§4.4): same-script precedent at :294/:377 (`tr '\n' ' '`), stronger `tr -d '[:cntrl:]'` at `vinngest-digest-freshness.sh:149`/`:279`; empirical: `${x//[$'\n\r']/ }` leaves `\t` and `\x1b` live. Bound kept at 300 per issue's ask vs. the 200 precedent. |
| Lane — no spec.md exists to carry `lane:` forward | technical | pending - assumed: `cross-domain` per the fail-closed default in `plan/SKILL.md` Save-Tasks step; domain sweep assessed all 8 domains as NONE (pure CI/tooling change) so the widening is moot. |

## Limitations of this planning run (no agent-spawn tool in subagent)

- Research fan-out (repo-research-analyst, learnings-researcher), SpecFlow analyzer, scoped advisor consult (Phase 4.5), and the plan-review named panel could not be spawned — all were performed inline by the planner instead. Defer only after inline triage: findings are recorded in the plan's Research Insights; the `soleur:review` phase remains the multi-agent gate.
- `## Open Code-Review Overlap`: None — queried 200 open `code-review` issues for all three Files-to-Edit paths; zero hits.
