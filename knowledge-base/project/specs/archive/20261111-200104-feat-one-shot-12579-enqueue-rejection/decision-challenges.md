# Decision Challenges — feat-one-shot-12579-enqueue-rejection

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Finding 2 semantics — document precondition in script comment vs. move enqueue to retry-on-check-complete | technical | Ruled by CTO agent, 2026-11-11: document precondition + defer retry to tracking issue #12652 - armed auto-merge self-enqueues once protection is met (ADR-270:624-646 measured); the arm covers the #12489 gap (ADR-270:1185-1194) whenever required checks are already met at arm time; a retry surface's only incremental coverage is "armed + green + still not queued" recurring post-arm, a class with zero observed instances. Dissent: if #12489's stall was a general App-authored self-enqueue regression (unmeasured at ADR-270:1214-1215), the re-evaluation triggers in #12652 are the tripwire. |
| Capture shape — `2>&1` into `enq_out` vs. separate stderr temp file | technical | Ruled by CTO agent, 2026-11-11: `2>&1` into `enq_out` - `gh api graphql` writes body to stdout / errors to stderr (stub contract `test-bump-inngest-bootstrap-pin.sh:354-357`, sibling `merge-queue-jump.sh:133`); jq position-parse tolerates noise (`\|\| echo '?'` at :652); a second file adds cleanup surface for zero behavioral gain. Dissent: none material — stdout-contract verified via stub/sibling, not a live failing call. |
| Sanitization shape — bash parameter expansion vs. repo-canonical `tr` pipeline | technical | Ruled by CTO agent, 2026-11-11: `tr '\n' ' ' <<<"$enq_out" \| tr -d '[:cntrl:]' \| cut -c1-300` - stricter on the merits: `${x//[$'\n\r']/ }` empirically leaves `\t`/`\x1b` live (annotation-injection class, PR #3007); repo-canonical at :294/:377 + `vinngest-digest-freshness.sh:149`/`:279`; bound 300 per issue's ask vs. 200 precedent (recorded divergence). Dissent: minor — `tr -d '[:cntrl:]'` strips legitimate TABs too; cosmetic. |
| Lane — no spec.md exists to carry `lane:` forward | technical | Ruled by CTO agent, 2026-11-11: `cross-domain` - no spec.md exists (verified: specs dir holds only tasks/decision-challenges/session-state); `plan/SKILL.md:983` fail-closed default applies; a domain lane would narrow review authority for zero benefit on an out-of-domain CI change. Dissent: none. |

## Limitations of this planning run (no agent-spawn tool in subagent)

- Research fan-out (repo-research-analyst, learnings-researcher), SpecFlow analyzer, scoped advisor consult (Phase 4.5), and the plan-review named panel could not be spawned — all were performed inline by the planner instead. Defer only after inline triage: findings are recorded in the plan's Research Insights; the `soleur:review` phase remains the multi-agent gate.
- `## Open Code-Review Overlap`: None — queried 200 open `code-review` issues for all three Files-to-Edit paths; zero hits.
