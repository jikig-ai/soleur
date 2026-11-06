## Summary

Adds a read-only wrapper so the CTO agent can run four live checks. It is a draft and unarmed.

## Needs you

- Arm the pull request and merge it, the one change to the live product (operator: production-mutating)

## Rulings

- Write-capable tokens used for reads. Ruled by CTO agent, 2026-11-03: accepted, because the wrapper is hardcoded to GET and the exception ends when read-only tokens exist.
- Brand-survival threshold raised to single-user incident. Ruled by CTO agent, 2026-11-03: raised; the CPO agent is spawned for its sign-off, not the owner.
- Post-merge workflows run when the pull request merges; no action is needed.

## Model Dissents

- The stricter option (keep these reads unverified until read-only tokens exist) was recorded and not chosen.
