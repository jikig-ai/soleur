# Decision Challenges — feat-one-shot-codeql-dedupe-fix

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Mass-close of ~185+ existing duplicate `sec: CodeQL alert` trackers | operator (scope) | deferred to operator — bulk issue mutation is outside this fix's blast radius; the repaired dedupe prevents recurrence. Needs a separate triage decision (close-with-comment vs bulk label sweep) |
| `--author app/github-actions` on the dedupe list | technical | Ruled at review (PR #12000, P1): ADOPTED — the plan-time rejection premise ("strangers cannot self-apply labels") was refuted by `auto-label-security.yml`, which applies `type/security` to any `^sec:` title on this public repo. security-sentinel + git-history converged; matches sibling `codeql-main-alert-gate.sh:142` |
| `jq -e 'type == "array"'` shape guard + `length >= 200` saturation warning | technical | Ruled at review (PR #12000, P3 ×4 seats): ADOPTED — one-token/two-line ports of the sibling's stronger guards |

Remaining technical A-vs-B items deferred to a CTO ruling — filed as issue #12004
per the `technical-ruling-gate.sh` fallback (the planning subagent has no
agent-spawn capability): bare-prefix anchor asymmetry, failure semantics
(green `exit 0` vs durable degraded issue), and the adjacent pre-existing
`ALERTS=$(gh api … 2>&1) || true` fail-open fetch (same class, one read upstream).
