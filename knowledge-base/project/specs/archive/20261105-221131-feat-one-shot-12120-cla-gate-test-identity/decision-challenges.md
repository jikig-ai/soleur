# Decision Challenges: feat-one-shot-12120-cla-gate-test-identity

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Setup-commit identity: per-command env vs. restore/unset `user.email` around the commit | technical | Ruled by CTO agent, 2026-11-05: per-command env `setup_commit` helper (author+committer via `env`), repo config untouched - restore/unset mutates the state T15/T16 test and is order-fragile; no suite-wide `GIT_CONFIG_GLOBAL=/dev/null` hardening (out of scope). |
| Suite-wide `GIT_CONFIG_GLOBAL=/dev/null` hardening so dev machines reproduce CI | taste | Not applied (outside the "about 4 lines" scope); candidate follow-up only if the operator wants hermetic local runs. |
| Review dissent (test-design seat, P2): hermetic dev runs - `export HOME/GIT_CONFIG_GLOBAL/GIT_CONFIG_SYSTEM` + a no-identity canary so a bare-commit revert also reds on dev machines | technical | Ruled by CTO agent, 2026-11-05: uphold the no-hardening ruling for this PR - CI already catches the regression (that is how it surfaced), the export changes ambient state for all 26 cases and does not address the inherited-`GIT_DIR` worktree class. Deferral documented here in place (no issue, per `wg-when-deferring-a-capability-create-a`): the proper follow-up is adopting `plugins/soleur/test/lib/git-fixture-env.sh` in this suite (it is absent from `fixture-env-adoption.test.sh` WAIVED/DEFERRED) with its own canary; flip trigger = a second CI-only identity regression in this suite. |
| Review finding (test-design seat, P3, pre-existing): T15's `git config --unset user.email` is non-discriminating (deleting it leaves 26/26) | technical | Ruled by CTO agent, 2026-11-05: wontfix for this PR - not touched by this diff, redesigning T15 is separate from the CI identity flake; recorded with the fixture-env follow-up above as test-discrimination debt in this file. |

No User-Challenges: the operator's stated direction is followed unchanged.
