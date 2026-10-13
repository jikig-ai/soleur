# Phase 0 notes (measured 2026-10-07, read-only)

Scratch notes for the runbook author. Values are a snapshot; none is copied into code or docs.

- Runs 37508997529 and 37516716515 (web2-luks-rebirth.yml): conclusion success; every step success (delete, forget, apply, readiness, reboot, summary). The rebirth runbook status line "inert until dispatched" is stale.
- Workflow states: web2-luks-rebirth.yml, apply-web-platform-infra.yml, apply-deploy-pipeline-fix.yml all `active`.
- Issues #9372, #6931, #9669, #9572: all OPEN.
- Marker `WORKSPACES_LUKS_CUTOVER_AT`: exact-name count 0 in soleur/prd_workspaces_luks_marker (config answered; names only).
- Live web-2 (read-only Hetzner GET): status running, locked false, rescue_enabled false, one volume.
- `actions/reboot` census (scripts, .github, apps; sh, yml, py): `scripts/web2-rebirth.sh`, `scripts/web2-rebirth.test.sh` only.
- Environment web-platform-infra-apply: required reviewer `deruelle` (sole), `prevent_self_review` false, custom branch policies true.
- Loader still exports AWS_* (AWS_ACCESS_KEY_ID writes in .github/actions/infra-credentials/action.yml).
- 0.5 / 0.6 GitHub concurrency page (docs.github.com/en/actions/using-jobs/using-concurrency, fetched 2026-10-07): SILENT on (a) how job-level concurrency interacts with environment-approval waiting, and (b) whether a job skipped by its `if:` claims the group. Record both as UNVERIFIED in the runbook; say to cancel an unapproved dispatch.
- 0.7 Row shapes through the helper (read-only): readiness rows and probe rows as the helper header describes; the probe row appears as two journal copies (plain, and `[luks-monitor] `-prefixed). `age_s` came back as a BARE number from the live query on this date (the helper accepts both bare and quoted-integer spellings; fixtures carry both). journald boot list: per-`_BOOT_ID` query returned four ids (32 lowercase hex, no dashes) with `n`, `newest_age_s`, `first_age_s` as bare numbers.
