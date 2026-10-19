# Decision Challenges — feat-one-shot-schedule-test-weight-tweet

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| publish_date value | operator (schedule) | `2026-10-20` — operator-directed in the invocation; verified correct against publisher semantics (`content-publisher.sh:884-896`): today's 14:00 UTC run already passed (plan-time UTC = 2026-10-19 22:5x), `publish_date < today` flips to `stale`, so tomorrow's date is the minimum that publishes. |
| `validate-tweet-draft.sh` invocation ordering | technical | Ruled inline, 2026-10-19: run pre-flip only — the script asserts `status: draft` (`validate-tweet-draft.sh:60-63`) and exits 1 on `scheduled`; verified by running it at plan time (exit 0). |
