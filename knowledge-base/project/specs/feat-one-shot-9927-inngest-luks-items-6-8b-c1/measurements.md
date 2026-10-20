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

Measured 2026-10-20 (UTC) under the owner's personal CLI identity (not the Tier-A service token). Names only; `--only-names --json`, never `--plain`, never `secrets get`; the captured text was never echoed. Verdict computed from separate return codes (Doppler rc, shape check, membership).

| # | Question | Command (text) | Result | Evidence class |
|---|---|---|---|---|
| M8b.1a | Is `HCLOUD_TOKEN_READONLY` listed in `soleur/prd_terraform`? | `doppler secrets --only-names --json -p soleur -c prd_terraform`, then `jq -e 'type=="object"'`, then `jq -r 'keys[]'` and an exact-line membership test | Doppler rc 0, shape ok, **listed** (168 names in the config) | measured |
| M8b.1b | Is `HCLOUD_TOKEN` (the read/write name) still listed (operator step O10 status)? | same call, same membership test | **absent** | measured |
| M8b.1c | Does the Tier-A identity corroborate it? | `gh run view <id> --log` greps; the step's own `echo "::warning ..."` text appears once per log as echoed script (a positive control that the step ran and is present) and was emitted 0 times in 3 recent `infra-validation` PR runs (39385810029, 39373339112, 39371615429, all success); the latest drift run (39377917525) emitted `source=tier_b exported=10` for 6 of 6 loader steps and 0 `source=legacy` lines; its `sole-copy-protection-check` job concluded success | consistent with a non-empty readable secret; a read-only token that exists but is empty or read/write cannot be seen this way | measured (indirect) |
| M8b.1d | Was the secret ever proved read-only? | `infra-credential-tiers-8209.md` O5 row and its dated note: the write-probe expects `forbidden`, measured 2026-09-29 (#8209) | recorded 2026-09-29; NOT re-run today (it would call the Hetzner API) | documented, not re-measured |

Reading: the read-only name is listed and the read/write name is gone from `prd_terraform`, which matches the runbook's own "after O10" notes of 2026-10-01 and the `admin-ip-refresh` skill sentence ("`prd_terraform` carries only `HCLOUD_TOKEN_READONLY`"). The ADR-282 addendum sentence of 2026-10-16 ("`DOPPLER_TOKEN` could still read the read/write token until the O10 eviction") describes the state before O10 and is superseded by this listing. The fallback to `HCLOUD_TOKEN` in sites A, B and D is therefore dead code today; removing it changes behaviour only if the read-only secret disappears. Gate result: **proceed with item 8b**. A mis-minted read/write secret stored under the read-only name remains undetectable here (accepted residual; control is the O5 write-probe).


### Caller table (item 8b)

Command: a PyYAML walk of `.github/workflows/*.yml` for jobs with a step whose `uses:` starts with `./.github/actions/infra-credentials`; the Hetzner column is a job-text search for `HCLOUD_TOKEN`, `hcloud_token`, `api.hetzner.cloud` or `hcloud` (it does not follow scripts the job calls, so "no" means "no reference in the job text", not "never reaches Hetzner"). Measured 2026-10-20: 32 jobs, one loader step each. Cross-check: the independent raw scan the census row G1j uses (a `uses:` line, comments excluded) must equal the YAML walk; it did on the live tree (the census prints both counts). Every job declares a Tier-B `environment:` (census G1j), so on `main` each takes the Tier-B arm, not the legacy arm whose behaviour changed.

| Workflow | Job | environment | Hetzner reference in job text | Tag |
| --- | --- | --- | --- | --- |
| apply-deploy-pipeline-fix.yml | apply | infra-privileged | yes |  |
| apply-git-data-root-key.yml | apply | web-platform-infra-apply | yes |  |
| apply-github-infra.yml | apply | infra-privileged | no (by job text) |  |
| apply-sentry-infra.yml | apply | infra-privileged | no (by job text) |  |
| apply-web-platform-infra.yml | apply | infra-privileged | yes |  |
| apply-web-platform-infra.yml | inngest_host | infra-privileged | yes |  |
| apply-web-platform-infra.yml | inngest_host_replace | infra-privileged | yes | incident-response |
| apply-web-platform-infra.yml | registry_host_replace | infra-privileged | yes | incident-response |
| apply-web-platform-infra.yml | registry_region_migrate | infra-privileged | yes | incident-response |
| apply-web-platform-infra.yml | registry_pull_path_gate | infra-privileged | yes | incident-response |
| apply-web-platform-infra.yml | registry_luks_recut | infra-privileged | yes | incident-response |
| apply-web-platform-infra.yml | registry_store_restore | infra-privileged | no (by job text) | incident-response |
| apply-web-platform-infra.yml | git_data_host_replace | infra-privileged | yes | incident-response |
| apply-web-platform-infra.yml | workspaces_luks_cutover | infra-privileged | yes | incident-response |
| apply-web-platform-infra.yml | workspaces_luks_recut | workspaces-luks-cutover | yes | incident-response |
| apply-web-platform-infra.yml | web_host_create | web-platform-infra-apply | yes | incident-response |
| apply-web-platform-infra.yml | web_host_replace | web-platform-infra-apply | yes | incident-response |
| apply-web-platform-infra.yml | git_data_host_create | web-platform-infra-apply | yes | incident-response |
| apply-web-platform-infra.yml | ci_ssh_token_replace | infra-privileged | yes | incident-response |
| apply-web-platform-infra.yml | inngest_link_flag | infra-privileged | no (by job text) |  |
| apply-web-platform-infra.yml | vector_redeliver | web-platform-infra-apply | no (by job text) |  |
| apply-web-platform-infra.yml | entrypoint_audit | infra-privileged | no (by job text) |  |
| git-data-cutover.yml | wipe | web-platform-infra-apply | yes | incident-response |
| git-data-rung2-rehearsal.yml | rehearse | web-platform-infra-apply | yes | incident-response |
| git-data-rung2-rehearsal.yml | teardown | infra-privileged | yes | incident-response |
| inngest-provision-rehearsal.yml | rehearse | web-platform-infra-apply | yes | incident-response |
| inngest-provision-rehearsal.yml | teardown | infra-privileged | yes | incident-response |
| scheduled-terraform-drift.yml | drift-check | infra-privileged | yes |  |
| scheduled-terraform-drift.yml | heartbeat-live-reconcile | infra-privileged | no (by job text) |  |
| scheduled-terraform-drift.yml | rung2-rehearsal-orphan-sweep | infra-privileged | yes |  |
| scheduled-terraform-drift.yml | inngest-rehearsal-orphan-sweep | infra-privileged | yes |  |
| web-host-escrow-diagnose.yml | escrow-check | infra-privileged | no (by job text) | incident-response |

Consumer empty-token handling (the legacy arm now exports nothing): the ten `[[ -z "$HCLOUD_TOKEN" ]]` guards in `apply-web-platform-infra.yml` sat in steps that run under `set -u`, so an unset variable would have aborted with `unbound variable` instead of the named abort; all ten now read `${HCLOUD_TOKEN:-}` (file 488,959 -> 488,999 bytes against the 490,000-byte ADR-231 gate; loader suite rows "consumers"). The drift and rehearsal-sweep jobs read the loader token through their own helpers and were NOT driven with an empty token here: an accepted gap, mitigated by G1j (they cannot reach the legacy arm on `main`). `scripts/cutover-inngest.sh` is unchanged (site C, #10664).

## Item C1: surviving source for the affected-user list

(filled in Phase 3)
