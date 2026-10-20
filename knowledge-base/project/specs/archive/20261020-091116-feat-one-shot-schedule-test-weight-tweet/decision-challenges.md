# Decision Challenges — feat-one-shot-schedule-test-weight-tweet

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| publish_date value | operator (schedule) | `2026-10-20` — operator-directed in the invocation; verified correct against publisher semantics (`content-publisher.sh:884-896`): today's 14:00 UTC run already passed (plan-time UTC = 2026-10-19 22:5x), `publish_date < today` flips to `stale`, so tomorrow's date is the minimum that publishes. |
| `validate-tweet-draft.sh` invocation ordering | technical | Ruled by CTO agent, 2026-10-19: run `validate-tweet-draft.sh` as the final gate while still `status: draft`, immediately before the flip; post-flip run `lint-distribution-content.sh` AND a parse-equivalence assertion replicating the publisher's `get_frontmatter_field` extraction (byte-equal `status`/`publish_date`, `^status: scheduled` at column 0, `publish_date >= $(date +%Y-%m-%d)` at ship time) — the publisher's whitespace/quote failure class (trailing space → silent `continue`, never stale, never publishes) is invisible to diff review and uncovered by any existing gate. Never run the validator post-flip (rc=1 by design); never dry-run `content-publisher.sh` (its `sed -i` stale-mutation and live-post paths are unsafe). Dissent: blast radius is a delayed marketing post — stale path self-announces via ops-email TSV — but the assertion is ~5 lines and covers the one silent failure class. |
