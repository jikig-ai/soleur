## Gap

`tests/scripts/lib/destroy-guard-filter-rundevoo.jq` (added in PR #12968) emits a `plan_ok` key that `scripts/rundevoo-destroy-counts.sh` uses to fail closed on a non-plan-JSON input ("an unread input must never score 0").

The sentry original it was copied from — `tests/scripts/lib/destroy-guard-filter-sentry.jq` / `scripts/sentry-destroy-counts.sh` — has no such check: a malformed or non-plan JSON document yields all-zero counters and greens the destroy gate.

## Fix

Port the `plan_ok` field + the counts-script refuse-on-missing-plan-docs check from the rundevoo pair to the sentry pair, plus a counter-suite row feeding a non-plan document.

User-Impact: route — a malformed plan JSON could green the sentry destroy gate and let an unreviewed destroy reach apply.
Fix-Size: ~30 lines / 3 files.
