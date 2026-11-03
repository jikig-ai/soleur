# Decision Challenges — feat-one-shot-codeql-dedupe-fix

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Mass-close of ~185+ existing duplicate `sec: CodeQL alert` trackers | operator (scope) | deferred to operator — bulk issue mutation is outside this fix's blast radius; the repaired dedupe prevents recurrence. Needs a separate triage decision (close-with-comment vs bulk label sweep) |

Technical A-vs-B items on top of the prescribed fix (`--author app/github-actions`
scope, fail-closed-vs-fail-open read semantics, jq match form) are deferred to a
CTO ruling — filed as issue #12004 per the `technical-ruling-gate.sh` fallback
(the planning subagent has no agent-spawn capability). The plan's
`## Alternative Approaches Considered` records the adopted brief-verbatim
defaults for each.
