# Runbook — reboot one named web host and read the rows that follow (#9372)

**Status:** the workflow `.github/workflows/web-host-reboot.yml` is dispatch-only and had never been dispatched when this was written (2026-10-07). Its merge changes nothing in production.
**Applies to:** the `web-2` standby only. `web-1` is refused by id at four layers and cannot be reached by any input.

The workflow soft-reboots one allow-listed host through the Hetzner API (one ACPI request) and then reads Better Stack rows to report whether a boot began after the request and whether the daily luks-monitor probe row has landed on it. It exists so the graded reboot evidence for the web-2 rebirth (#9372, acceptance criterion 2) can be gathered by the dispatching agent, with the owner's environment approval as the only gate, and no SSH.

**What it reports, and what it does not.** It reports rows only: which boots the host's own journald rows show, and what the newest readiness and probe rows are. It makes no statement about the volume or what is on it, and a PASS from this workflow is never evidence for the encryption-posture ledger, the Article 30 record or any customer-facing sentence. Until the follow-through `scripts/followthroughs/web2-luks-live-6931.sh` reports PASS, web-2 is *provisioned, proof pending*, at weight 0, holding no workspace data. The same sentence is printed as a fixed footer by both scripts and in both summaries: "This run reports rows only. It makes no statement about the volume or its encryption; grading belongs to scripts/followthroughs/web2-luks-live-6931.sh." Do not write "LUKS-backed", "encrypted" or "reborn" about web-2 in any note on a run of this workflow.

## Authorization and approval

- Every dispatch needs the owner's explicit go-ahead for that specific dispatch, naming the production write (`hr-menu-option-ack-not-prod-write-auth`). The environment approval and the typed `confirm` are an approval gate and a typo guard, never the authorization. Do not dispatch from a menu answer or a "continue".
- The environment `web-platform-infra-apply` has one reviewer, the owner's own login, and `prevent_self_review` is off (measured 2026-10-07). The agent's `gh` identity is that same login, so the platform does not separate dispatching from approving. The separation is a rule, kept by the go-ahead above. Hardening it (`prevent_self_review` and a distinct agent identity, a `.tf` change) is outside this change; it is tracked as a follow-up issue linked from the PR for this change (#9372).
- **Cancel an unapproved dispatch promptly.** GitHub's concurrency documentation (read 2026-10-07) states that at most one job per group runs and at most one is pending, and that a newer pending job replaces the older pending one. It says nothing about how that interacts with an environment approval, and nothing about whether a job skipped by its `if:` still claims the group. **Both are UNVERIFIED.** If a run that is waiting for approval holds the `web-1-swap` group, it can block a release deploy or a host job, and a reboot dispatch could displace a pending deploy. So: dispatch only when the owner is ready to approve, and cancel with `gh run cancel <run id>` if the approval is not coming.

## Dispatch

1. Read the live server id from a read-only Hetzner GET, never from Terraform state. The typed id is compared with the live id and with the state id, and a replace that lands between dispatch and approval makes them differ.

   ```bash
   doppler run -p soleur -c prd_terraform -- sh -c 'curl --disable --noproxy "*" -sS -H "Authorization: Bearer ${HCLOUD_TOKEN_READONLY:-$HCLOUD_TOKEN}" "https://api.hetzner.cloud/v1/servers?name=soleur-web-2"' | jq -r '.servers | map({id, name, status, created}) '
   ```

   Exactly one server must come back, named `soleur-web-2`. Any other result stops the dispatch.
2. Dispatch from `main` only (a run from any other ref never starts the gated job):

   ```bash
   gh workflow run web-host-reboot.yml --ref main \
     -f host=web-2 -f confirm=REBOOT-web-2-<server id> -f reason='<why, 1 to 200 characters of letters, digits, space and . _ , : # / ( ) ->'
   ```

   The `validate` job checks the three inputs first, with no secrets and no environment, so a typo dies before any approval request exists. The run title (`web-host-reboot web-2 REBOOT-web-2-<id>`) names the host and the typed id; the reason is deliberately not in the title. It appears only in the run summary.
3. Arm a watch before doing anything else (`hr-dispatch-async-must-arm-watch`). Use a Monitor on the run, never a foreground `gh run watch`:

   ```bash
   gh run list --workflow web-host-reboot.yml --limit 1 --json databaseId,status,conclusion,url
   ```

   Poll that run id until it concludes. The `reboot` job shows as waiting until the owner approves the environment gate; the `observe` job follows it.

## What the run does

| Job | Holds | Does |
|---|---|---|
| `validate` | nothing (no environment, no secrets) | format-checks `host`, `confirm`, `reason` |
| `reboot` | the Tier-B credentials (environment `web-platform-infra-apply`, mutex `web-1-swap`, `main` only) | re-checks the inputs, loads the credentials, reads the never-pooled evidence (names only), prints the pre-request context, then runs `scripts/web-host-reboot.sh reboot`, the only step with a Hetzner call |
| `observe` | Better Stack read credentials only (no environment, no Hetzner token, no Doppler) | polls up to 40 minutes through `scripts/web-host-reboot-evidence.sh grade`, then reports; the grade step writes the step summary itself |

The script's refusals all run before the one write, in this order: xtrace or a missing token; a host off the allow-list; a malformed `confirm`; the never-pooled evidence not `absent`; the by-name lookup not returning exactly one server; the resolved id being web-1's; the resolved id differing from the typed id (the message prints the live id and the corrected `confirm`); the Terraform state not holding web-1 or holding a different web-2 id. The anchor epoch is written to the step outputs immediately before the POST, so a failure after the request still hands `observe` an anchor.

**An accepted request is a request.** Hetzner's action `success` means the ACPI request was sent. It does not show that the host restarted or came back. If the action ends in `error` or is still running after the poll, the message says the request was sent and may still happen: **do not re-dispatch**; grade the rows with the command in the log.

## Reading the result

`observe` ends with a `verdict:` line, a `next:` line and the fixed footer. PASS and FAIL are row-presence states.

| Exit | Verdict | `reason=` | Meaning | What to do |
|---|---|---|---|---|
| 0 | PASS (row presence only) | `probe_row_on_a_boot_that_began_after_the_request` | a boot began after the request and a probe row of the OK class sits on it | nothing further for this run. The strict grading (device type, mapper path, escrow, three soak days) stays with the #6931 follow-through. A boot that began after the request but was not caused by it still reads as PASS here; that is why PASS is row presence only. |
| 2 | NOT YET (green, with a notice) | `new_boot_seen_probe_pending` | a boot began and is shipping rows; the daily probe has not fired on it yet | the expected result on most days. The probe lands in the 00:00 to 00:30 UTC window, up to about 24.5 hours after a boot. **Do not re-dispatch to force a row.** Re-grade later (below). |
| 2 | NOT YET | `read_fault` | Better Stack could not be read; nothing was measured | re-grade later. A read fault is never a FAIL. |
| 2 | NOT YET | `instance_recreated_after_request` | a readiness row is newer than the request: the host was re-created, not rebooted | run the grade again after the new instance, with a new anchor |
| 4 (red) | NOT YET at the deadline | `request_not_acted_on` | no boot began and the old boot keeps shipping rows: the guest ignored the soft request. Nothing is dark | **Do not replace the host.** Record it on #9372 and let the owner decide: a replace is destructive and restarts the soak. |
| 4 (red) | NOT YET at the deadline | `host_silent_no_new_boot` | the old boot stopped shipping and no new boot appeared: still booting, or dark | the dark-host path below |
| 4 (red) | NOT YET at the deadline | `new_boot_seen_then_silent` | a boot began and then stopped shipping | the dark-host path below |
| 1 (red) | FAIL | `probe_fail_row_after_new_boot` | a FAIL-shaped or malformed probe row is younger than the new boot's first row | see the FAIL branch below |
| 3, 78, other (red) | cannot establish | n/a | credentials, helper or arguments missing; xtrace refused | read the `::error::` line; fix the cause; re-grade |

A FAIL needs a boot that began after the request AND a probe row younger than that boot's first row, so a late row from the pre-request boot cannot cause one (a margin of 120 seconds resolves toward NOT YET).

### Re-grading later (read-only, no second reboot, no second approval)

The anchor is the `anchor epoch` printed by the `reboot` job (also in its step output). From a checkout of the repo, as the dispatching agent:

```bash
doppler run --preserve-env -p soleur -c prd_terraform -- bash scripts/web-host-reboot-evidence.sh grade --anchor <anchor epoch> --window-min 0
```

`--window-min 0` is a single read. The same script's `snapshot` prints the current context (newest readiness row, probe row and journald boot, as ids and ages only).

Copy the run summary (run id, SHA, dispatcher, approver, anchor epoch, boot ids, verdict) into the closing change: run logs expire after about 90 days. A run summary is not evidence for any record.

## The FAIL branch

A FAIL probe row also spoils the #6931 soak by the grader's own rule (any non-green probe row at or after the readiness row). Recovery is a `web_host_replace` of web-2 (the dark-host path below, which carries the volume forward by design) and a re-grade from the new instance's readiness row. The owner decides; the replace is a production write needing its own go-ahead.

## The dark-host path (`host_silent_no_new_boot`, `new_boot_seen_then_silent` only)

The recovery is the API-driven `web_host_replace`, an owner-approved dispatch, with no SSH:

```bash
gh workflow run apply-web-platform-infra.yml \
  -f apply_target=web-host-replace -f web_host_key=web-2 -f confirm=REPLACE-web-2 \
  -f image_tag=<tag WITHOUT a leading v> -f reason='replace web-2 after a silent reboot (#9372)'
```

- **`image_tag` takes a bare tag, `3.1.2`, never `v3.1.2`,** until #9669 (open at the time of writing) is fixed: a `v`-prefixed tag passes validation and then fails after the environment approval (a doubled prefix). Take the tag from web-1's live `/health` `.version`, which is the tag the fleet is serving. See [web-host-replace.md](./web-host-replace.md) for the full procedure and its gates.
- Consequences to plan for before asking for the go-ahead: a **new server id** (a new `confirm` for any later reboot dispatch); the **SSH host-key pin re-capture** (closing row 3 of [web2-luks-rebirth-9372.md](./web2-luks-rebirth-9372.md)); the **`earliest` re-set** on the #6931 directive (closing row 4); a **restarted soak**; and a second reboot dispatch to gather the evidence again.

## The marker consequence

The never-pooled gate passes while `WORKSPACES_LUKS_CUTOVER_AT` is absent from `soleur/prd_workspaces_luks_marker` (absent when measured on 2026-10-07). The daily `web2_marker` verify job can earn that marker once a green readiness row and a probe row on a different boot exist. From then on the gate refuses every reboot of web-2 by design, because with the marker present web-2 may already hold data. That refusal is correct, not a defect; the evidence is then read with the re-grade command above.

## What the run never does

No SSH, no Doppler write, no token mint, no Terraform plan or apply, no ledger edit, no edit of the encryption-posture exception. It does not force the daily probe: no existing non-SSH path starts `luks-monitor.service` on web-2, and forcing one would be SSH by another name. NOT YET is the honest answer until the timer fires.

## Retirement

This workflow depends on `scripts/web2-rebirth-never-pooled.sh` and shares helper bodies with `scripts/web2-rebirth.sh`. It retires with them, in the rebirth closing change, after the graded #6931 PASS: closing row 5 of [web2-luks-rebirth-9372.md](./web2-luks-rebirth-9372.md) lists every file and registration to delete and states retire-versus-keep. A tombstone row in the workflow suite makes a half retirement fail CI (if either of those two scripts is gone, every `web-host-reboot*` file must be gone too). Keeping it past the rebirth is possible only by a recorded owner decision.

## References

ADR-263 (addendum 2026-10-07), ADR-241 (credential tiers), [web2-luks-rebirth-9372.md](./web2-luks-rebirth-9372.md), [web-host-replace.md](./web-host-replace.md), [infra-credential-tiers-8209.md](./infra-credential-tiers-8209.md), `.github/workflows/web-host-reboot.yml`, `scripts/web-host-reboot.sh`, `scripts/web-host-reboot-evidence.sh`, `knowledge-base/project/plans/2026-10-07-feat-web-host-reboot-workflow-plan.md`.
