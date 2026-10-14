# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-21-fix-deploy-arm-selection-by-resolve-target-plan.md
- Status: complete

### Errors
None (brief called #8490 a PR; it is an open issue).

### Decisions
- Rule lives in a new shared script plugins/soleur/scripts/deploy-arm.sh (find / contains / served), called with literal args from ship and postmerge.
- head_sha= kept as a fast first guess, confirmed through resolve-target.
- Exact match only after merge CI completes; descendant accepted only when no earlier candidate is unread; skipped vs blocked vs superseded distinguished.
- /health build_sha passes when merge is ancestor-or-equal; unreadable -> "could not measure".
- web-platform-release.yml unchanged; DC-1..DC-3 recorded in decision-challenges.md.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, plus research/review agents.
