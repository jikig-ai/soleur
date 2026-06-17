---
title: "mig 112 DROP broke verify/031 + verify/110 (stale users.* column refs) → deploy pipeline blocked"
date: 2026-06-18
brand_survival_threshold: single-user incident
art_33_personal_data_breach: false
art_33_rationale: "Availability/CI-pipeline incident only — no personal data was accessed, exfiltrated, altered, or lost. The DROP applied as designed against a verified COUNT=0 prod state; the failure was a CI verify-job error on two sibling verify files."
art_34_high_risk_to_individuals: false
art_34_rationale: "n/a — no personal-data breach (see Art. 33). No user-facing outage: prod kept serving the prior build, which has zero readers of the dropped columns."
severity: P1
status: resolved
issue: 5437
pr: 5508
---

# PIR — migration 112 DROP broke two sibling verify files → deploy pipeline blocked

## Summary

PR #5508 (ADR-044 PR-2b) dropped `users.{github_installation_id, repo_url, workspace_path}`
via migration 112. The `migrate` job applied the DROP to prod successfully and all five
`verify/112` sentinels passed. But the **`verify-migrations` job runs EVERY verify file on
every deploy**, and two pre-existing sibling verify files — `verify/031_normalize_repo_url.sql`
and `verify/110_workspace_repo_error_and_comember_reconcile.sql` — still referenced the
just-dropped `users.repo_url` / `users.github_installation_id` columns. Those files errored
(`column u.repo_url does not exist`), failing `verify-migrations`, which **gated `deploy`**
(skipped) → the web-platform deploy pipeline was blocked for ALL subsequent PRs.

## Impact

- **Severity:** P1 (deploy-pipeline blocked) — NOT a user-facing outage.
- **User-facing:** none. `deploy` was skipped, so prod kept serving the **prior** build, which
  was already cut over to `workspaces.*` and has **zero readers** of the dropped columns. The
  DROP + a no-readers build = a healthy prod that simply didn't advance to the newest build.
- **Pipeline:** every web-platform release after the #5508 merge would have failed at
  `verify-migrations` (stale 031/110) and skipped `deploy` until fixed.
- **Window:** ~from the #5508 merge (2026-06-17T23:25Z) to the hotfix merge.

## Root cause

The pre-merge "exhaustive sweep" for live references to the dropped columns covered
`apps/web-platform/{app,server,lib}` (app readers/writers) and
`apps/web-platform/supabase/migrations/` (DB function/trigger/view/policy bodies — which
caught the `handle_new_user` P1). It did **NOT** cover
`apps/web-platform/supabase/verify/` — the sibling verify files that the CI `verify-migrations`
job re-runs on every deploy. `verify/031` (the repo_url normalization sentinel) and `verify/110`
(the ADR-044 pre-drop SOLO drift gate) both query `users.repo_url` / `users.github_installation_id`;
once the columns were dropped those queries error at parse time, failing the job.

This is the same class as the `handle_new_user` P1 (a surviving DB-side reference the app-layer
sweep missed) — extended one directory further: **a column DROP's pre-drop sweep must include
`supabase/verify/` AND `supabase/migrations/`, not just app code + migrations.**

## Resolution

`verify/031` and `verify/110` are pre-drop assertions about columns that no longer exist —
vacuously satisfied post-DROP. The check bodies were rewritten to a named `0::int AS bad`
(preserving each `check_name` for verify-summary stability) with a comment pointing at mig 112.
The `conversations.repo_url` checks in 031 and the `workspaces.*` checks in 110 were left live
(those columns were not dropped). Both files were re-run against **prod** (post-DROP):
`031 = 4 checks bad=0`, `110 = 5 checks bad=0`, no errors. The hotfix PR re-runs
`verify-migrations` green → `deploy` proceeds → the #5508 build deploys.

## Detection

The `web-platform-release` run for the #5508 merge was monitored to its terminal state and
reported `failure`; reading `--log-failed` pinpointed `verify-migrations` failing on `verify/110`
(`column u.repo_url does not exist`), with `verify/112` itself all-green and `migrate` succeeded.

## Action Items & Follow-ups

_No action items — incident fully resolved in this PR (verify/031 + verify/110 corrected, prod-verified bad=0; deploy pipeline unblocked). The recurrence-prevention lesson (a DROP's pre-drop sweep must include `supabase/verify/`) is captured in the session learning and folded into the existing "sweep DB-side writers" learning._
