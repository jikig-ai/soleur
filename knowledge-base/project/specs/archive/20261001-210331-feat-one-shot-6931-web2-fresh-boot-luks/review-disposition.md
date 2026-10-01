# Review disposition: PR #9352 (#6931, ADR-263), 13-seat review at 4441c06fd5

Reports: `/var/tmp/rv6931-<seat>.md` (working notes; this file is the durable record). Counts are as the seat reported them.
Order of authority for the fixes below: the lead's decided facts, then the seat reports.

## Seats

| Seat | P1 | P2 | P3 | Headline |
|---|---|---|---|---|
| agentnative | 1 | 5 | 4 | runbook readiness-row command is invalid; replace remedy circular; follow-through enrollment stale |
| dataint | 0 | 4 | 6 | no data-destroying path; recovery arm unreachable; escrow never retried; reboot breaks the join |
| githistory | 0 blocking | - | - | removed gate was never invoked; #9348 textual overlap flagged |
| observability | 6 | 4 | 2 | no page on the new stages; provisioner row not shipped; reboot join; warn rows silent; no web2_marker alarm; failure_modes name no layer |
| sast | 0 blocking | - | low | 0 semgrep findings; 4 shellcheck nits in new test lines |
| simplicity | 2 | 2 | 7 | reboot join and escrow claim (P1); recommends peeling the evidence cluster |
| userimpact | 0 | 3 | 10 | threshold met; F1 reboot/escrow claims, F2 marker consumer unpinned, F4 shared escrow credential |
| arch | 1 | 7 | 7 | boot_id join breaks on reboot (P1); D6 contradicts ledger; replace-before-conversion loops; #9348 conflict |
| security | 0 | 1 | 8 | populated volume with damaged metadata reads as raw; marker forgeable by a root-equivalent host user |
| structural | - | - | - | sink and guard enumerations (facts, no severity); spellings outside the static greps |
| pattern | 1 | 4 | 6 (7 reported) | per-instance readiness vs per-boot join (P1); 20 assertions with a dead second conjunct; runbook triage wrong |
| quality | 3 | 6 | 14 | 3 templatefile suites red on the new var; F8 SIGPIPE flake; reboot join |
| testdesign | 3 | 9 | 5 | red suite; 18 dead second halves; Guard 1 zero-write grep is spelling-based |

## Decision: "peel the marker and evidence work out" is DECLINED

The simplicity seat recommends shipping the provisioner now and moving the evidence cluster (the `web2_marker` job, the rows
library, the follow-through, the marker config and token, the readiness `boot_id`/`host=`/`luks_arm`/`escrow` fields) to a later
PR. Declined: items 3 (the `WORKSPACES_LUKS_CUTOVER_AT` marker writer) and 5 (live verification on web-2) of the issue require
that cluster, and splitting would leave the issue's own acceptance criteria unmet by this PR. Accepted from the same report:
its P1s (the reboot join, the escrow claim), its line-trimming P3s where low-risk, and the observation that the cluster cannot be
validated until the first live row exists, which is why the live conversion (#9372) carries the first-row review and the
follow-through enrollment. The "not live yet" notice stays, and the escalation for a host that never produces rows is owned by
#9372 (a ceiling on the follow-through).

## Decided facts applied across the documents

- The readiness row is emitted once per **instance**; the probe row is daily and per boot. The verify join is instance-level
  (probe newer than the green readiness row); `boot_id` is diagnostic only; `luks_arm` exists only in the first-boot row.
- Escrow is attempted once at birth; `escrow=missing` persists and withholds the soak marker. Recovery of an interrupted format is by
  host replace through a LUKS2 label carried on the volume.
- The soak-marker value is advisory and shape-only (#9358); a present marker is kept while GREEN and removed on a non-GREEN run.
- The live web-2 conversion, ledger flip (floor 2 to 3), follow-through `earliest` and host-key pin re-capture are #9372.
  Replacing web-2 before #9372 powers the new host off by design (fail closed, weight 0, no user impact).

## Fixed

- Documents (two passes): ADR-263 D3 arm list and recovery/escrow description, D5 (join, issue, Sentry check-in, default-branch
  custody), D6, live-conversion, residual and consequences sections; ADR-119 and ADR-143 addenda; web-host-replace runbook (valid
  no-SSH query, stage table incl. `key`/`mount`/`workspaces_luks_not_mounted`/`wire_warn`/`result`, the reason-to-action table
  matching the workflow and rows library, `discriminate` circularity); plan correction notes and observability block; C4 edges
  (`github -> doppler` marker write token, `github -> betterstack` web-2 verify leg); register wording conditioned on #9372;
  stale comments (server.tf, workspaces-luks.tf, lb-weight-gate.sh, apply-web-platform-infra-job-rationale).
- Code and tests, by outcome:
  - the verify join is instance-level (probe row not older than the green readiness row; `boot_id` diagnostic only; judge faults
    leave the marker untouched);
  - three cloud-init-rendering suites that lacked the new `vars` key; the F8 SIGPIPE flake;
  - about 20 dead `expect ... && ...` assertion halves, each with a mutation row; destructive-binary trap-stubs and a read-only
    allow-list in the provisioner suite;
  - interrupted-format recovery by a LUKS2 label on the volume (`soleur-formatting`, then `soleur-workspaces`; a failed relabel is
    fatal `format`) plus a local intent file bound to the volume's `luksUUID`; the zero-content probe (first and last 16 MiB, window
    at 128 MiB); a failed enable of the reopen units is fatal `wire`; fstab mode 0644; `ulimit -c 0`;
  - Sentry routing for the boot-fatal (13 stages, pages) and boot-warning (4 stages, NoOne) stages; new stages
    `workspaces_luks_provision_wire_warn` and `fresh_boot_ready_bs_egress` (a skipped or failed readiness POST is observable);
  - `web2_marker` alarm layers: a `[ci/luks-verify-web2]` issue (distinct RED and unavailable titles) and a Sentry Crons check-in
    (schedule-only; the monitor is declared unrouted until its first measured check-in);
  - the follow-through grades from rows alone (no Doppler token; directive carries the three `BETTERSTACK_QUERY_*` names) and FAILS
    when a non-green row follows the readiness row or its window closes unmet;
  - an occurrence-based marker-writer census; the cloud-init hard-gate predicate executed under stubs; the birth gate binds web-1's
    key to Terraform and aborts on a missing `after_unknown`; escrow is verified by md5/ETag (Escrow idempotency: quality P2-6,
    dataint F8, security P3-7).
- The provisioner rows are retagged to the journald tag `workspaces-luks-reopen`, which Vector already allowlists. The obs F2
  `vector.toml` allowlist edit was NOT made: `vector.toml` is baked into the inngest-bootstrap image, so a change needs an image
  rebuild and a pin bump.

## Deferred (tracked)

- Live web-2 rebirth and everything gated on it: #9372.
- Marker sourcing into `lb-weight-gate.sh` and validation of its value: #9358.
- Splitting the web-host escrow credential from web-1's backup-bucket access (per-host credential, bucket versioning or object
  lock): #9377.
- Provisioner hardening (`flock`, `PATH` pin, a test seam, fstab fsync and atomic replace), an nft-runtime egress test, and the
  provisioner suite's runtime and maintainability: #9378. The code-simplicity seat CONCURRED with deferring #9377 and #9378.

## Coordinated, not tracked by an issue

- Land order with PR #9348 and its 10-file conflict surface (arch P2-7): recommend #9348 first, then rebase this branch and
  re-point the ADR, ledger and replace-gate text; the ADR's "Relationship to other ADRs" paragraph records the reconciliation.
- Replace-gate arm for a non-raw `hcloud_volume.workspaces[k]` (arch P2-3): documented in the web-host-replace runbook rather than
  built. Replacing web-2 before #9372 powers the new host off by design (fail closed, serving weight 0, no user impact).

## Declined

- Peeling the marker/evidence work out of this PR (above).
- Renaming the readiness `escrow=` token to `header_escrow=` (pattern F7): the field grammar of the two evidence rows is frozen.
- The `vector.toml` allowlist edit (obs F2): see above; solved by the retag instead.
- A `_UID` predicate in the probe SQL (security P3-1): not verifiable offline; the SQL stays pinned to `_SYSTEMD_UNIT`.
