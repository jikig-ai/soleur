# admin-merge-ready fixtures

Real-shape base for `plugins/soleur/scripts/admin-merge-ready.test.sh` (#8500). Captured read-only
on 2026-09-22 and trimmed with `jq` to the fields the script reads.

- `rules-branches-main.json`: `gh api --paginate --slurp repos/jikig-ai/soleur/rules/branches/main`,
  keeping every rule's `type` and `ruleset_id`, and `parameters` for `required_status_checks` only
  (the live set is two `required_status_checks` rules plus `deletion` and `non_fast_forward`).
  Rulesets 14145388 (CI Required, 11 contexts) and 13304872 (CLA Required, 2 contexts): 13 in total.
  2026-11-07 (#12276): the 16 folded context names were rewritten to the 3 umbrella names
  (`guards-ruleset`, `quality-guards`, `secret-guards`) that replaced them under the #12089
  consolidation — contexts are entries, so 24 − 16 + 3 = 11.
- `check-runs.json`: `gh api --paginate --slurp "repos/jikig-ai/soleur/commits/319c22bffa4c1785da52dd9af9471a9d8eef1310/check-runs?per_page=100&filter=all"`,
  the head of merged PR #8534. 77 runs; every required context is present and green. Fields
  kept: `id`, `name`, `head_sha`, `status`, `conclusion`, `started_at`, `app.id`, `check_suite.id`.
  2026-11-07 (#12276): the 16 folded-name runs were dropped and the 5 umbrella runs
  (`guards-ruleset`, `guards-advisory`, `quality-guards`, `quality-advisory`, `secret-guards`)
  appended — member guards now run as STEPS inside the umbrella jobs and no longer post
  their own check runs. 66 runs.

Every suite row is a `jq` edit of this base. To recapture, rerun both commands against a
recently merged PR whose required contexts are all green, trim the same way, and update this file.
The suite's H6 preconditions fail loudly if a recapture drops something a row relies on.

The base is the PRE-adoption shape (CodeQL/57789 required, no `merge_queue` rule), captured before #9454.
Rows R36/R37 DERIVE the post-adoption shape from it with `jq` (drop the `CodeQL` required context, append a
synthesized `merge_queue` rule) instead of recapturing, which is impossible before the apply. Recapture the
base after the apply if you want it to match the live rules exactly.
