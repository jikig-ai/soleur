# Decision challenges (plan, headless)

Technical forks ruled by the CTO agent for the create-arm pre-filter (Ref #10550). The operator is not asked
any technical question; each row carries the ruling.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Where the ledger-owned pattern is removed in the create arm (before the single model call vs only at the post-call gate) | technical | Ruled by CTO agent, 2026-10-28: drop ledger-suppressed hashes from the offered list before the model call (decideSuppression with runNow), keep the post-call gate as a backstop, empty-because-of-ledger -> no_action/all-owned, no new marker field - the model otherwise picks the one owned pattern and six are never evaluated |
