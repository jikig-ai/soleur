# Decision challenges: feat-one-shot-haiku-5-5-support

Persisted by the plan phase (headless). `ship` renders this into the PR body and files the action-required issue.

## 2026-10-08 Taste: Sonnet 5.5 cache-read correction rides along (billing constant)

- Stated direction: the brief asks for pricing and tier maps to be updated and verified from official docs.
- Finding: the official pricing page lists Sonnet 5.5 cache hits at $0.10 per MTok (0.05x base); the repo row carries $0.20. Plan review split: one seat says move it to its own PR, one seat says keep it as an isolated commit.
- Default taken: keep it in this PR as its own commit, applied only if the live refetch still shows $0.10, with the regime boundary (merge SHA and UTC time) recorded in the row comment. The ledger is append-only with no model column, so earlier rows are not restated.
- Reversible: drop the single commit; no other change depends on it.

## 2026-10-08 Taste: one-off release-age floor override for the CLI pin

- Finding: the first CLI release that knows `claude-haiku-5-5` is 2.1.293, published 2026-10-07T17:18Z, which is inside the repo's 3-day `min-release-age` floor until 2026-10-10T17:18Z.
- Default taken: use the documented one-off `--min-release-age=0` when regenerating the lockfile, leave `.npmrc` untouched, disclose it in the PR body with integrity evidence; skip the override if work resumes after the floor lapses. Alternative: wait about two days.
- Reversible: yes, until merge.
