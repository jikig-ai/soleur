# Decision challenges (plan-review, headless)

Persisted for `soleur:ship` Phase 6 to render. Operator direction is the default in every row.

## DC1 — User-Challenge: shrink or drop the test suite and its registrations

- Operator direction: enroll #9564 with a probe-style automated check; "keep it small".
- Challenge (DHH P0, CTO P1, code-simplicity P1 on the registration cost): the count is near-vacuous (crosses 3 about a day after merge), so a script plus mock-gh suite plus mutation matrix plus three runner registrations is out of proportion for a p3 deferred issue. Suggested alternatives: an inline ~20-line workflow in the `codeql-1537-revisit-watch.yml` style with no suite and no registrations; or a plain comment on #9564 carrying the 54.4 min arithmetic and no code.
- Plan default (kept): script + reduced suite (S1-S11, M1-M8) as the sibling `watch-live-verify-pass` shape, because exactly-once and never-close are exit-code contracts the convention says must be driven by a suite, and a new workflow cannot be dispatched before merge. Cut already applied: env seams, sanitization, re-arm, workflow-shape grep scenario, one mutation row.
- Cost of taking the challenge: loses local testability of dedup and never-close; saves three runner-file registrations and this PR's own PR-gated batteries.

## DC2 — Taste: threshold 3 is not a meaningful signal

- Reviewers: Kieran P1, simplicity P1, CTO P1, DHH P0.
- Applied mitigation (mechanical): count only commits with zero deleted lines across the two runner files, and report the excluded count.
- Not applied: raising THRESHOLD (for example to 10). The spec calls 3 and 20% proposed numbers to revise with the first measurement; `THRESHOLD` is a single constant.
