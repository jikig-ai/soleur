# Decision challenges: feat-one-shot-harness-parity-hardening

## DC-1: Split the bundle into four PRs (User-Challenge, from the CTO at plan Phase 2.5)

- **Operator's direction (default, kept):** ship the harness-parity items as one bundle. The parent allowed splitting only where needed, such as #7453's migration. The plan splits off the #7453 migration, the #8317 agent-body half and the #8574 required-check pin, and ships items 1–7 in one PR.
- **Challenge:** the CTO recommends four PRs.
  - A: items 2 and 3.
  - B: items 1 and 4, plus the ratchet.
  - C: item 7 (the OpenHands/Gemini retirement, which is its own revert unit and touches the hook suites).
  - D: item 6 (vendor-CLI CI).

  The reason: a ~250-file PR gets shallow review, and a single revert would undo unrelated work.
- **Mitigation in the plan:** per-item commits (Technical Approach, with named dependencies), so any item reverts on its own. Item 6 ships non-required, so vendor flakiness cannot block merges.
- **Operator decision needed:** whether to keep the bundle or split it before `soleur:work` starts, or at review.

## DC-2: Ship Phase 7 (Codex/Devin discovery CI) as its own PR (User-Challenge, from DHH at plan-review)

- **Operator direction (default, kept):** item 6 (Codex and Devin tested in CI) ships in this bundle.
- **Challenge:** DHH says the vendor-CLI job is the only fragile, novel piece and should ride separately under #8574, so that vendor flakiness never touches the doc/gate fixes. This converges with DC-1's option D.
- **Mitigation in the plan:** the job ships non-required and has its own commit, and exit 3 (UNRESOLVED) carries a reason taxonomy.
- **Operator decision needed:** whether to keep item 6 in this PR.
