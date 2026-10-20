# Measurements: Inngest LUKS arc items 6, 8b and C1

Names, counts, timestamps and shapes only. No secret value, diff, version content, identifier or payload appears in this file, and none was printed, logged or stored. Evidence classes: `measured`, `documented, not measured`, `could-not-measure(<reason>)`.

Guard used for every Doppler command: `set +x`, `set -o pipefail`, `2>/dev/null` on both sides of every pipe, exact-key allowlist with a value filter on `jq`, no `--debug`, no `secrets get`, no `doppler run`, no `configs logs get`, no `configs logs rollback`, no write command of any kind.

## Item 6: Doppler version history of `soleur-inngest/prd`

Measured 2026-10-20 (UTC), Doppler CLI v3.77.0.

| # | Question | Command (text) | Result | Evidence class |
|---|---|---|---|---|
| M6.1 | Which credential ran the reads? | `doppler me --json`, key names, then the `type` value through `test("^[a-z_ -]{1,32}$")` | keys: created_at, last_seen_at, name, slug, token_preview, type, workplace; type = `cli` (a personal CLI login, not a service token) | measured |
| M6.2a | Does the CLI expose a plan field? | `doppler settings --json` key names; `doppler projects get soleur-inngest --json` key names | settings keys: billing_email, id, name; project keys: created_at, description, id, name; no plan or tier field | could-not-measure(cli_exposes_no_plan_field) |
| M6.2b | What does the vendor document per plan? | WebFetch of `https://www.doppler.com/pricing`, 2026-10-20 | Developer: free for 3 users, activity log retention "3 days". Team: "$21/mo per user", "90 Days of activity logs". Enterprise: custom. The page does not mention version history or rollback. | documented, not measured |
| M6.3 | How far back does the config log of this one config reach? | `doppler configs logs -p soleur-inngest -c prd -n 100 --page 1 --json`, key names first (config, created_at, diff, environment, html, id, project, text, user), then only `created_at` through a timestamp-shape filter | 68 entries on one page; page 2 returned `null` with rc 0 (end of data); oldest 2026-07-23T15:46:21Z, newest 2026-10-20T07:01:08Z; oldest-entry age 89 days. The project was created 2026-07-08T00:10:18Z (104 days old) | measured (a LOWER bound on retention, not the retention) |
| M6.4 | What does a rollback restore, and for whom? | WebFetch of `https://docs.doppler.com/docs/versioning`, 2026-10-20 | Per log entry, not a whole config; supported for secret add, update and delete and for Trusted IP create and delete; a rollback adds a new log entry; "Every version of a secret is retained for the lifetime of that secret"; redacting a version blocks rolling back to it. The page names no plan limit. | documented, not measured; `rollback` never run (documented, not rehearsed) |

Reading of M6.2 and M6.3 together (inference, not a measurement): the oldest entry is 89 days old, the free Developer plan documents a 3-day activity log and Team documents 90 days, and the oldest entry sits one day inside a 90-day window (2026-07-22 would be the cut). That is consistent with the Team plan and inconsistent with the free plan, which contradicts the `knowledge-base/operations/expenses.md` Doppler row ("Developer plan (free)"). The activity log and the config log may not share one retention, so the tier stays unmeasured. The owner dashboard plan page is the single arbiter (tracked in the follow-up issue).

Route A rule (applied): Route A is "available" only if the tier is MEASURED as paid, the documented rollback scope covers the key, and the oldest-entry age meets the repair horizon. The horizon is derived here: the 12-hour drift cadence plus one working week for the owner to respond, rounded to 7 days (a derived figure, no existing repo figure). The age (89 days) meets it and the scope covers a secret update, but the tier is not measured, so Route A stays **unverified; treat as unavailable; Route B (the Terraform state value) is the only independent recovery planned on**.

Sweep (one pass, case-sensitive `Route A` and Doppler version-history mentions outside plan artifacts and counsel audits): 2 sites carry the Inngest recovery claim (ADR-282 loss-mode table; runbook "Doppler secret overwritten" row), both updated with an in-cell Superseded marker. 4 other hits (`breach-register.md`, `compliance-posture.md`, ADR-241, two audits) concern a different Doppler config (`soleur/prd`, the App key) and the documented fact that Doppler keeps old values in version history; they are consistent with the 2026-10-20 documentation read and are left unchanged.

## Item 8b: names-only listing

(filled in Phase 2)

## Item C1: surviving source for the affected-user list

(filled in Phase 3)
