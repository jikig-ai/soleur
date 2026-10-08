# Runbook — reboot one named web host and read the rows that follow (#9372)

**Status:** the workflow `.github/workflows/web-host-reboot.yml` is dispatch-only and had never been dispatched when this was written (2026-10-07; review-round additions the same day). Its merge changes nothing in production.
**Amendment, 2026-10-08 (owner decision, ADR-263 addendum of the same date): a reboot is no longer required for the #6931 grade or for the soak marker.** The principle is that a host is replaced, not rebooted, and the grader and the marker writer now accept the instance's readiness row (`luks_arm` `formatted` or `opened`) plus three green daily probe rows. This runbook stays accurate for the workflow's own mechanics until the workflow is retired in the rebirth cleanup PR; do NOT dispatch it to satisfy the grader or the marker. The first dispatch (2026-10-07, run 37671563967, owner-approved) was accepted by Hetzner, but no boot followed it within the 40-minute window (`host_silent_no_new_boot`, exit 4), so web-2 was replaced (server 169271252); that is the recorded case for the dark-host path below.
**Applies to:** the `web-2` standby only. `web-1` is refused at four layers (see "What the guards are, and are not"). That is a set of refusals in the workflow path, not a proof that no input can reach it.

The workflow soft-reboots one allow-listed host through the Hetzner API (one ACPI request) and then reads Better Stack rows to report whether a boot began after the request and whether the daily luks-monitor probe row has landed on it. It exists so the graded reboot evidence for the web-2 rebirth (#9372, acceptance criterion 2) can be gathered by the dispatching agent, with the owner's environment approval as the only gate, and no SSH (superseded for the grade, see the amendment above).

**What it reports, and what it does not.** It reports rows only: which boots the host's own journald rows show, and what the newest readiness and probe rows are. It makes no statement about the volume or what is on it, and a PASS from this workflow is never evidence for the encryption-posture ledger, the Article 30 record or any customer-facing sentence. Until the follow-through `scripts/followthroughs/web2-luks-live-6931.sh` reports PASS, web-2 is *provisioned, proof pending*, at weight 0, holding no workspace data. The same sentence is printed as a fixed footer by both scripts and in both summaries: "This run reports rows only. It makes no statement about the volume or its encryption; grading belongs to scripts/followthroughs/web2-luks-live-6931.sh." Do not write "LUKS-backed", "encrypted" or "reborn" about web-2 in any note on a run of this workflow.

## Authorization and approval

- Every dispatch needs the owner's explicit go-ahead for that specific dispatch, naming the production write (`hr-menu-option-ack-not-prod-write-auth`). The environment approval and the typed `confirm` are an approval gate and a typo guard, never the authorization. Do not dispatch from a menu answer or a "continue".
- **An agent never approves its own dispatch.** Approval is the owner's act, taken in the Actions UI after the owner has read the run title. The agent must not approve through the UI, the pending-deployments API or any other route, even though its `gh` identity could.
- The environment `web-platform-infra-apply` was measured on 2026-10-07: a custom deployment branch policy that lists exactly `main` (`deployment-branch-policies` returns one entry), a sole reviewer whose login is `deruelle` (the owner), and `prevent_self_review` false. The agent's `gh` identity is that same login, so the platform does not separate dispatching from approving. **The gate is a rule, not a platform control:** it is kept by the go-ahead above and by the owner doing the approving. Whether destructive dispatches should be two-party (`prevent_self_review` plus a distinct agent identity, a `.tf` change) is tracked on #8044, outside this change. The branch policy, unlike the reviewer rule, is enforced by the platform: a run from a ref other than `main` never starts the gated job.
- **Never dispatch while a `web-1-swap` workflow is running, and cancel an unapproved dispatch.** GitHub's concurrency documentation (read 2026-10-07) states that at most one job per group runs and at most one is pending, and that a newer pending job replaces the older pending one. It says nothing about how that interacts with an environment approval, and nothing about whether a job skipped by its `if:` still claims the group. **Both are UNVERIFIED.** If a run that is waiting for approval holds the `web-1-swap` group, it can block a release deploy or a host job, and a reboot dispatch could displace a pending deploy. Run this from a checkout of `main` immediately before every dispatch; any output means stop and ask the owner:

  ```bash
  for wf in $(grep -l 'group: web-1-swap' .github/workflows/*.yml | xargs -n1 basename); do
    for st in in_progress queued waiting; do
      gh run list --workflow "$wf" --status "$st" --json databaseId,workflowName,status,displayTitle \
        --jq '.[] | "\(.workflowName)\t\(.status)\t\(.databaseId)\t\(.displayTitle)"'
    done
  done
  ```

  Empty output means no run of a workflow that holds `web-1-swap` is active or waiting (one of the listed files, this workflow's own, answers HTTP 404 until it exists on the default branch; that is not a result). Dispatch only when the owner is ready to approve. If the approval is not coming, cancel with `gh run cancel <run id>`. A cancelled run starts no `observe` job; if a run is cancelled after the `reboot` job ran, a request may already have been sent: read the `reboot` job's log for its anchor before any new dispatch.
- **A re-run is refused by design.** `gh run rerun` of the whole run or of the `reboot` job would re-execute the guards at the original SHA and, with live state unchanged, issue a second request that reboots the host again. The workflow reads `github.run_attempt` in `validate` and in the `reboot` job's re-check step and refuses unless it is 1. Read the evidence and dispatch anew (after the owner's new go-ahead) instead.

## What the guards are, and are not

- **Four layers refuse web-1.** The workflow's `host` choice and allow-list (web-2 only); the typed `confirm`, whose id must equal the live Hetzner id of `soleur-web-2`; web-1's id as a constant in the script (the resolved id must not equal it); and web-1's id as the Terraform state holds it (the resolved id must not equal that either). A fifth check, the state holding the same id for web-2, runs alongside.
- **Calling `scripts/web-host-reboot.sh` directly skips the workflow layers** (the `validate` job, the environment approval, the `main`-only branch policy and the mutex). Refusals 1 to 10 in the script still apply. The script is an internal part of this workflow: nothing here supports invoking it outside the workflow.
- **`NEVER_POOLED` is asserted by the caller.** The script refuses unless it equals `absent`, but it cannot verify that; only the workflow's own never-pooled step produces it. `INFRA_DIR` selects which Terraform state the script reads; the workflow supplies it through the `env -i` allow-list.
- **Not covered, recorded as such:** the Better Stack password reaching `curl` in the argv of `scripts/betterstack-query.sh` (pre-existing); the infra-credentials token placement (pre-existing, see [infra-credential-tiers-8209.md](./infra-credential-tiers-8209.md)); clock skew between the runner and Better Stack (documented only, not guarded).

## Dispatch

1. Read the live server id from a read-only Hetzner GET, never from Terraform state. The typed id is compared with the live id and with the state id, and a replace that lands between dispatch and approval makes them differ. The command uses the read-only token only and fails loudly when it is absent. It never falls back to the write token `HCLOUD_TOKEN`; if the read-only token is missing from `prd_terraform`, stop and tell the owner.

   ```bash
   doppler run -p soleur -c prd_terraform -- bash -c '
     : "${HCLOUD_TOKEN_READONLY:?HCLOUD_TOKEN_READONLY is absent from prd_terraform: stop; never fall back to HCLOUD_TOKEN}"
     curl --disable --noproxy "*" -sS --config - "https://api.hetzner.cloud/v1/servers?name=soleur-web-2" \
       < <(printf "header = \"Authorization: Bearer %s\"\n" "$HCLOUD_TOKEN_READONLY")
   ' | jq '.servers | map({id, name, status, created})'
   ```

   Exactly one server must come back, named `soleur-web-2`. Any other result stops the dispatch.
2. Run the concurrency check above. Then dispatch from `main` only (a run from any other ref never starts the gated job):

   ```bash
   gh workflow run web-host-reboot.yml --ref main \
     -f host=web-2 -f confirm=REBOOT-web-2-<server id> -f reason='<why>'
   ```

   `reason` is 1 to 200 characters matching `[A-Za-z0-9 ._,:#/()-]`: letters, digits, space and the punctuation `.` `_` `,` `:` `#` `/` `(` `)` plus the hyphen `-` (the hyphen is one allowed character on its own; there is no arrow token). The `validate` job checks the three inputs first, with no secrets and no environment, so a typo dies before any approval request exists. The run title (`web-host-reboot web-2 REBOOT-web-2-<id>`) names the host and the typed id; the reason is deliberately not in the title. It appears only in the run summary.
3. Find the run that was just dispatched. Do not take "the latest run": another dispatch of the same workflow may exist. Match on the event and the exact title:

   ```bash
   gh run list --workflow web-host-reboot.yml --event workflow_dispatch --limit 10 \
     --json databaseId,displayTitle,status,conclusion,createdAt,url \
     --jq '.[] | select(.displayTitle == "web-host-reboot web-2 REBOOT-web-2-<server id>")'
   ```

   Exactly one fresh row (created after the dispatch) is the run. More than one means an earlier dispatch with the same title exists: read each `createdAt` and stop if it is unclear which is yours.
4. Arm a watch before doing anything else (`hr-dispatch-async-must-arm-watch`). Use a Monitor on the run, never a foreground `gh run watch`. Poll the run id until it concludes. Tell waiting from failed with the jobs' own state:

   ```bash
   gh run view <run id> --json status,conclusion,jobs \
     --jq '{status, conclusion, jobs: [.jobs[] | {name, id: .databaseId, status, conclusion}]}'
   ```

   `reboot` with status `waiting` is the environment gate: the run is waiting for the owner's approval, not failing. `queued` can also mean the `web-1-swap` slot is taken (UNVERIFIED which of the two a waiting approval looks like, see above). `completed` with conclusion `failure` or `cancelled` is a failure: read the error line before doing anything else.

## What the run does

| Job | Holds | Does |
|---|---|---|
| `validate` | nothing (no environment, no secrets) | format-checks `host`, `confirm`, `reason`; refuses a re-run |
| `reboot` | the Tier-B credentials (environment `web-platform-infra-apply`, mutex `web-1-swap`, `main` only) | re-checks the inputs (and refuses a re-run), loads the credentials, reads the never-pooled evidence (names only), prints the pre-request context, then runs `scripts/web-host-reboot.sh reboot`, the only step with a Hetzner call |
| `observe` | Better Stack read credentials only (no environment, no Hetzner token, no Doppler) | polls up to 40 minutes through `scripts/web-host-reboot-evidence.sh grade`, then reports; the grade step writes the step summary itself |

The script's refusals all run before the one write, in this order: xtrace, a missing token or a token of an unusable shape; a host off the allow-list; a malformed `confirm`; the never-pooled evidence not `absent`; the by-name lookup not returning exactly one server; the resolved id being web-1's; the resolved id differing from the typed id (the message prints the live id and the corrected `confirm`); the Terraform state not holding web-1, holding a different web-2 id, or holding the resolved id for web-1. The anchor epoch is written to the step outputs immediately before the POST, so a failure after the request still hands `observe` an anchor.

**An accepted request is a request.** Hetzner's action `success` means the ACPI request was sent. It does not show that the host restarted or came back. If the action ends in `error` or is still running after the poll (a poll answer that is not HTTP 200 counts as no answer), the message says the request was sent and may still happen: **do not re-dispatch**; grade the rows with the command in the log. Likewise a POST that ends in a transport error, an HTTP 5xx or a body with no action id keeps the anchor and says the request may have been sent.

**A definite refusal withdraws the anchor.** If Hetzner answers the POST with a 4xx, the script appends an empty `anchor_epoch=` (the last write wins: this relies on the Actions runner honouring a repeated key in `GITHUB_OUTPUT`, which the suite models with `tail -n 1` and which was not verified on a real runner; if it did not hold, the only effect is a 40-minute `observe` poll on a request that was never sent, ending red), the `observe` job is skipped, and the message says that none was sent. A 423 or 429 is such an answer. Fix the cause named in the message and re-dispatch. The log still contains an `anchor_epoch=<digits>` line in this case: read the error message before trusting it, and use no anchor when it says the anchor is withdrawn.

## Reading the result

`observe` ends with a `verdict:` line, a `next:` line and the fixed footer. PASS and FAIL are row-presence states.

**A green `observe` job is PASS or NOT YET, not necessarily PASS.** Exit 0 (PASS) and exit 2 (NOT YET, with a `::notice::`) both end the job green. Read the `verdict:` line. **Exit 5 is red:** nothing was measured, so the job must not read as an answer.

Read the run from the agent's side, with no browser. Take the job ids from the jobs command above (`id`), then:

```bash
# the anchor, from the finished reboot job (works while observe is still polling)
gh api repos/jikig-ai/soleur/actions/jobs/<reboot job id>/logs --allow-escape-sequences | grep -o -m1 'anchor_epoch=[0-9]\{1,10\}'

# the reboot job's error line, if any (the log shows an ::error:: annotation as ##[error]; read it: it says whether the anchor was withdrawn)
gh api repos/jikig-ai/soleur/actions/jobs/<reboot job id>/logs --allow-escape-sequences | grep -m5 -F '##[error]'

# the verdict and the next step, from the finished observe job
gh api repos/jikig-ai/soleur/actions/jobs/<observe job id>/logs --allow-escape-sequences | grep -E -m6 ' (verdict|next): '

# the annotations of a job (notice for NOT YET, error for red)
gh api repos/jikig-ai/soleur/check-runs/<observe job id>/annotations --jq '.[] | "\(.annotation_level) \(.message)"' | head -n 20
```

`gh run view --log` answers only after the whole run is complete; the `actions/jobs/<id>/logs` form works for any job that has finished. The `verdict:` and `next:` lines print boot ids, ages and counts only, never row text.

| Exit | Verdict | `reason=` | Meaning | What to do |
|---|---|---|---|---|
| 0 | PASS (row presence only) | `probe_row_on_a_boot_that_began_after_the_request` | a boot began after the request, a probe row of the OK class sits on it, that row passes the grading helper's own device, mount and escrow test, and no failing probe row is younger than the new boot's first row | nothing further for this run. The strict grading (three soak days) stays with the #6931 follow-through. A boot that began after the request but was not caused by it still reads as PASS here; that is why PASS is row presence only. |
| 2 | NOT YET (green, with a notice) | `new_boot_seen_probe_pending` | a boot began and is shipping rows; the daily probe has not fired on it yet. This is the only reason that exits 2 | the expected result on most days. The probe lands in the 00:00 to 00:30 UTC window, up to about 24.5 hours after a boot. **Do not re-dispatch to force a row.** Re-grade later (below). |
| 5 (red) | nothing measured | `read_fault` | Better Stack could not be read; nothing was measured | re-grade later. A read fault is never a FAIL and never a green run. |
| 5 (red) | nothing measured | `instance_recreated_after_request` | a readiness row is newer than the request: the host was re-created, not rebooted | nothing was measured about this request; run again after the new instance, with a new anchor |
| 4 (red) | NOT YET at the deadline | `request_not_acted_on` | no boot began and the old boot's newest row is recent (inside 10 minutes) and newer than the request: the guest ignored the soft request. Nothing is dark | **Do not replace the host.** Record it on #9372 and let the owner decide: a replace is destructive and restarts the soak. |
| 4 (red) | NOT YET at the deadline | `host_silent_no_new_boot` | no boot began and the old boot is no longer shipping recent rows (including an old boot whose last rows are only shutdown rows: those keep reading as `request_not_acted_on` until they are older than 600 seconds, so a `--window-min 0` re-grade within about ten minutes of the request can misread, and the 40-minute window converges): still booting, or dark | the dark-host path below |
| 4 (red) | NOT YET at the deadline | `new_boot_seen_then_silent` | a boot began and then stopped shipping | the dark-host path below |
| 1 (red) | FAIL | `probe_fail_row_after_new_boot` | a FAIL-shaped or malformed probe row is younger than the new boot's first row | see the FAIL branch below |
| 1 (red) | FAIL | `probe_row_not_green_after_new_boot` | a probe row after the new boot is OK-shaped but fails the grading helper's own device, mount and escrow test | see the FAIL branch below |
| 3, 64, 78, other (red) | cannot establish | n/a (`anchor_too_old` when the anchor is beyond the lookback) | credentials, helper or arguments missing or malformed; xtrace refused; an anchor older than the boot read can see | read the error line; fix the cause; re-grade |

A FAIL needs a boot that began after the request AND a probe row younger than that boot's first row, so a late row from the pre-request boot cannot cause one (a margin of 120 seconds resolves toward NOT YET).

**A green `observe` job is not an alert, and the rows can be forged.** Better Stack holds rows written by whoever holds an ingest token; every id is format-checked and no row text is echoed, but a PASS is still row presence on a host the dispatcher chose. Never wire the grade step's `verdict`, `reason` or `exit_code` outputs to automation, an alert or a ledger.

### Re-grading later (read-only, no second reboot, no second approval)

The anchor is the `anchor epoch` printed by the `reboot` job (read it with the log command above). From a checkout of the repo, as the dispatching agent:

```bash
doppler run --preserve-env -p soleur -c prd_terraform -- bash scripts/web-host-reboot-evidence.sh grade --anchor <anchor epoch> --window-min 0
```

`--window-min 0` is a single read. Bounds. The first is advice. The second and third are enforced by the script (exit 3, nothing read; only `anchor_too_old` is a named reason):

- **Not too early.** A single read taken within a few minutes of the POST usually sees no new boot yet: it reports `host_silent_no_new_boot` or `request_not_acted_on` (exit 4) because the host has not restarted or has not shipped a row, not because the request failed. Within the first minutes either wait or use `--window-min` greater than 0 (the default in the workflow is 40, polled every 60 seconds).
- **Not too late.** The anchor plus the window must stay inside 47 hours: the boot read looks back 48 hours, and beyond that a boot that began before the request cannot be told from one that began after it, which would make a false PASS. An older anchor is refused as `anchor_too_old`; the daily probe row, up to about 24.5 hours after the boot, still fits inside the bound.
- The anchor must be whole digits with no leading zero, and not in the future; `--window-min` and `--poll-s` are whole numbers with no leading zero.

The same script's `snapshot` prints the current context (newest readiness row, probe row and journald boot, as ids and ages only).

Copy the run summary (run id, SHA, dispatcher, approver, anchor epoch, boot ids, verdict) into the closing change: run logs expire after about 90 days. A run summary is not evidence for any record.

## The FAIL branch

A FAIL probe row also spoils the #6931 soak by the grader's own rule (any non-green probe row at or after the readiness row). Triage host-side versus volume-side first (below). Recovery, if the cause is host-side, is a `web_host_replace` of web-2 (the dark-host path below) and a re-grade from the new instance's readiness row. The owner decides; the replace is a production write needing its own go-ahead.

## The dark-host path (`host_silent_no_new_boot`, `new_boot_seen_then_silent` only)

**Triage host-side versus volume-side before asking for a replace.** A `web_host_replace` creates a new server and **re-attaches the same volume** (it carries the volume forward by design). A cause on the host (image, network, cloud-init) is cleared by a replace; a cause on the volume side, such as a failed reopen at boot, recurs on the new host, and the replace still costs a new server id, a re-keyed host and a restarted soak. Read what the rows and the boot trail say: whether the new boot shipped any row at all (`new_boot_seen_then_silent` against `host_silent_no_new_boot`), what the last replace's Sentry boot-trail named (see "Verify the result" in [web-host-replace.md](./web-host-replace.md)), and whether a FAIL-shaped or non-green probe row sits on a boot that did ship. If the evidence points at the volume, record it on #9372 and let the owner decide; do not replace on a guess.

The recovery is the API-driven `web_host_replace`, an owner-approved dispatch, with no SSH:

```bash
gh workflow run apply-web-platform-infra.yml \
  -f apply_target=web-host-replace -f web_host_key=web-2 -f confirm=REPLACE-web-2 \
  -f image_tag=<tag WITHOUT a leading v> -f reason='replace web-2 after a silent reboot (#9372)'
```

- **`image_tag` takes a bare tag, `3.1.2`, never `v3.1.2`,** until #9669 (open at the time of writing) is fixed: a `v`-prefixed tag passes validation and then fails after the environment approval (a doubled prefix). Take the tag from web-1's live `/health` `.version`, which is the tag the fleet is serving, with this read-only command (it printed `0.327.0` on 2026-10-07, already bare):

  ```bash
  curl --disable --noproxy '*' -sS --max-time 15 https://app.soleur.ai/health | jq -r '.version'
  ```

  See [web-host-replace.md](./web-host-replace.md) for the full procedure and its gates.
- Consequences to plan for before asking for the go-ahead: a **new server id** (a new `confirm` for any later reboot dispatch); the **SSH host-key pin re-capture** (closing row 3 of [web2-luks-rebirth-9372.md](./web2-luks-rebirth-9372.md)), which needs the owner's acknowledgement because the capture runs from an egress address that must be in `ADMIN_IPS` and the address refresh has its own acknowledgement (`scripts/capture-web-2-host-key.sh` refuses under CI by design); the **`earliest` re-set** on the #6931 directive (closing row 4); a **restarted soak**; and a second reboot dispatch to gather the evidence again.
- **Dates.** The decision is due 2026-10-15 and the owner needs the extension prepared by 2026-10-14; the encryption-posture exception on `hcloud_volume.workspaces` expires 2026-10-22 (closing rows 4 and 6 of the rebirth runbook). A dark host that needs a replace late in that window can make the 3-day soak miss 2026-10-22: raise it with the owner early, do not wait for NOT YET to resolve.
- **Expect web-2's own heartbeat alert during the window.** A soft reboot makes the host dark for minutes, and a dark host or a replace keeps it dark longer; the heartbeat alert for web-2 may fire and is expected for that window, not a fault.

## The marker consequence

The never-pooled gate passes while `WORKSPACES_LUKS_CUTOVER_AT` is absent from `soleur/prd_workspaces_luks_marker` (absent when measured on 2026-10-07). Since 2026-10-08 the daily `web2_marker` verify job can earn that marker without a reboot: a green readiness row whose `luks_arm` is `formatted` or `opened` and a green, fresh probe row are enough (ADR-263 addendum). From then on the gate refuses every reboot of web-2 by design, because with the marker present web-2 may already hold data. That refusal is correct, not a defect; the evidence is then read with the re-grade command above.

**Caveat: absent is not "never pooled".** The verify job deletes an earned marker when it judges RED (rows going missing after the marker exists, for example). The gate then reads `absent` for a host that was once certified. The gate proves only that the marker is absent now, by name. State this in the request for the go-ahead, and ask the owner whether web-2 has ever served weight or held data before relying on `absent`.

## What the run never does

No SSH, no Doppler write, no token mint, no Terraform plan or apply, no ledger edit, no edit of the encryption-posture exception. It does not force the daily probe: no existing non-SSH path starts `luks-monitor.service` on web-2, and forcing one would be SSH by another name. NOT YET is the honest answer until the timer fires.

## Retirement

This workflow depends on `scripts/web2-rebirth-never-pooled.sh` and shares helper bodies with `scripts/web2-rebirth.sh`. It retires with them, in the rebirth closing change, after the graded #6931 PASS: closing row 5 of [web2-luks-rebirth-9372.md](./web2-luks-rebirth-9372.md) lists every file and registration to delete and states retire-versus-keep. A tombstone row in each of the two suites (A5 and A5b in `apps/web-platform/infra/web-host-reboot-workflow.test.sh`, and the TOMBSTONE row in `scripts/web-host-reboot.test.sh`) is hard red: if either of those two rebirth scripts is gone, every `web-host-reboot*` file must be gone too, so a half retirement fails CI. **Keeping the workflow past the retirement of the rebirth scripts means editing the tombstone rows in the same PR**, together with the recorded owner decision naming a new home for the never-pooled gate. Without both the PR is red by design.

## References

ADR-263 (addendum 2026-10-07), ADR-241 (credential tiers, dated section 2026-10-07), [web2-luks-rebirth-9372.md](./web2-luks-rebirth-9372.md), [web-host-replace.md](./web-host-replace.md), [infra-credential-tiers-8209.md](./infra-credential-tiers-8209.md), #8044 (two-party dispatch decision), `.github/workflows/web-host-reboot.yml`, `scripts/web-host-reboot.sh`, `scripts/web-host-reboot-evidence.sh`, `knowledge-base/project/plans/2026-10-07-feat-web-host-reboot-workflow-plan.md`.
