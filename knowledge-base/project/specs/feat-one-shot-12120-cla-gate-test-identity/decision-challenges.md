# Decision Challenges: feat-one-shot-12120-cla-gate-test-identity

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Setup-commit identity: per-command env vs. restore/unset `user.email` around the commit | technical | Ruled by CTO agent, 2026-11-05: per-command env `setup_commit` helper (author+committer via `env`), repo config untouched - restore/unset mutates the state T15/T16 test and is order-fragile; no suite-wide `GIT_CONFIG_GLOBAL=/dev/null` hardening (out of scope). |
| Suite-wide `GIT_CONFIG_GLOBAL=/dev/null` hardening so dev machines reproduce CI | taste | Not applied (outside the "about 4 lines" scope); candidate follow-up only if the operator wants hermetic local runs. |

No User-Challenges: the operator's stated direction is followed unchanged.
