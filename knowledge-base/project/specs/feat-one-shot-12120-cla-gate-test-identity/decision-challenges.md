# Decision Challenges: feat-one-shot-12120-cla-gate-test-identity

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Setup-commit identity: per-command env vs. restore/unset `user.email` around the commit | mechanical | Resolved by the brief's own constraint, not by a CTO spawn (no genuine fork): the brief states T15 tests the hook with the repo identity unset, so mutating `user.email` around setup would alter the state under test; per-command env chosen. |
| Suite-wide `GIT_CONFIG_GLOBAL=/dev/null` hardening so dev machines reproduce CI | taste | Not applied (outside the "about 4 lines" scope); candidate follow-up only if the operator wants hermetic local runs. |

No User-Challenges: the operator's stated direction is followed unchanged.
