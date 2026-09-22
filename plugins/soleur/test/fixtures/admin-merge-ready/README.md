# admin-merge-ready fixtures

Real-shape base for `plugins/soleur/scripts/admin-merge-ready.test.sh` (#8500). Captured read-only
on 2026-09-22 and trimmed with `jq` to the fields the script reads.

- `rules-branches-main.json`: `gh api --paginate --slurp repos/jikig-ai/soleur/rules/branches/main`,
  keeping only `required_status_checks` rules (`type`, `ruleset_id`, `parameters`). Rulesets
  14145388 (CI Required, 24 contexts) and 13304872 (CLA Required, 2 contexts): 26 in total.
- `check-runs.json`: `gh api --paginate --slurp "repos/jikig-ai/soleur/commits/319c22bffa4c1785da52dd9af9471a9d8eef1310/check-runs?per_page=100&filter=all"`,
  the head of merged PR #8534. 77 runs; every required context is present and green. Fields
  kept: `id`, `name`, `status`, `conclusion`, `started_at`, `app.id`, `check_suite.id`.

Every suite row is a `jq` edit of this base. To recapture, rerun both commands against a
recently merged PR whose required contexts are all green, trim the same way, and update this file.
The suite's H6 preconditions fail loudly if a recapture drops something a row relies on.
