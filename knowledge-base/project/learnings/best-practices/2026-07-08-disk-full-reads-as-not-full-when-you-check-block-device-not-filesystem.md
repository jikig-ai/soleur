---
module: apps/web-platform/infra (zot registry, cloud-init, registry-host-replace Terraform gate, Better Stack observability)
date: 2026-07-08
problem_type: best_practice
component: tooling
symptoms:
  - "zot returned HTTP 500 + `connection reset by peer` on blob-upload PATCH/PUT (#6240)"
  - "`soleur-registry-disk-prd` missed-heartbeat incident fired at the same time"
  - "prior post-mortem concluded 'disk not full' by reading the Hetzner Volume API (block-device size = 30 GB), never the guest ext4 filesystem size"
  - "`resize2fs ... || true` silently failed so the fs stayed at ~10 GB on a 30 GB block device and filled"
root_cause: config_error
resolution_type: code_fix
severity: critical
status: open  # defaults to open — close via /soleur:resolve-debt
rule_id: hr-no-dashboard-eyeball-pull-data-yourself
tags: [disk-full, resize2fs, block-vs-filesystem, zot-registry, observability, no-ssh, fail-loud, destroy-guard]
synced_to: [betterstack-log-query]
---

# Troubleshooting: A full disk on a blind host reads as NOT-full if you check the block device instead of the filesystem — and `resize2fs || true` masks the real cause

## Problem

The `soleur-registry-disk-prd` missed-heartbeat incident AND the zot `500`-on-blob-upload failure (#6240) were BOTH caused by the single fact that `/var/lib/zot` was full. The first remediation's post-mortem concluded "disk not full" — a **falsified** conclusion — because it read the Hetzner **Volume API** (block-device size = 30 GB), not the guest ext4 **filesystem** size. The block device had been grown to 30 GB, but `resize2fs` had silently failed (guarded by `|| true`), so the filesystem stayed at its original ~10 GB and was full.

## Environment

- Module: apps/web-platform/infra — self-hosted zot registry host (Hetzner), deny-all-public firewall, no SSH
- Affected Component: `cloud-init` volume-resize step, `zot-disk-heartbeat.sh`, the `registry-host-replace` Terraform gate, Better Stack Logs (`SOLEUR_ZOT_DISK` marker)
- Date: 2026-07-08
- Issues: #6240 (zot 500 on blob upload), #6244 (blind-host disk observability). Amends ADR-096.

## Symptoms

- zot returned HTTP `500` + `connection reset by peer` on the blob-upload PATCH/PUT (a **write** failure).
- The disk-gated heartbeat (`zot-disk-heartbeat.sh` pings only while `/var/lib/zot < 85%`) correctly **skipped** its ping → missed-heartbeat incident.
- The prior post-mortem read the Hetzner Volume API, saw 30 GB, and concluded "disk not full."
- On the guest, `df` showed the ext4 fs was still ~10 GB and full — the 30 GB was the block device, never the filesystem.

## What Didn't Work

**Attempted Solution 1 (prior remediation): infer disk-fullness from the Hetzner Volume API.**
- **Why it failed:** the Volume API reports the **block-device** size (30 GB). The guest **filesystem** was never grown to match it (see root cause). Block-device size ≠ filesystem size; the API answer was true but irrelevant to "is the fs full."

**Attempted Solution 2 (prior remediation): treat "the last CI push still succeeded" as proof the disk is <85%.**
- **Why it failed:** a successful push does NOT prove <85% used. zot dedups blobs and a partial write can still fit; "some writes succeed" is consistent with a nearly/actually-full fs. A write-success signal is necessary corroboration but is NOT sufficient to clear disk-full.

**Attempted Solution 3 (original provisioning): `resize2fs <dev> || true`.**
- **Why it failed:** the `|| true` converted a genuine resize failure into a **phantom success** — the provisioning step reported OK while the fs silently stayed at ~10 GB. A load-bearing step was made unobservable.

## Session Errors

**1. Prior post-mortem's "disk not full" was wrong — it read block-device size, not filesystem size (RECURRING).**
- **Recovery:** re-diagnosed by shipping guest `df%` telemetry (`SOLEUR_ZOT_DISK` marker) instead of inferring from the provider API.
- **Prevention:** for any "is the disk full?" question you MUST see the **guest `df`**, not the cloud provider's volume/block-device API. On a deny-all/no-SSH host that means shipping df% telemetry (the #6244 `SOLEUR_ZOT_DISK` marker), never inferring from the provider API (`hr-no-dashboard-eyeball-pull-data-yourself`, `hr-no-ssh-fallback-in-runbooks`).

**2. A destroy-guard allow-set member lacked a preserve-backstop (sev-7, review-caught, RECURRING).**
- **Recovery:** test-design review caught it; added a dedicated `registry_betterstack_logs_token_destroyed==0` backstop + a paired FAIL fixture.
- **Prevention:** adding an address to a scoped-`-replace` destroy-guard ALLOW-SET silences BOTH create AND delete for that address. If deleting the member is catastrophic, add a dedicated `<member>_destroyed==0` backstop and a paired FAIL fixture — exactly like the volume `store_destroyed` backstop the gate's own authors documented (see Secondary Learning below).

**3. Duplicate `zotRegistry -> betterstack` C4 edge added; c4 freshness/syntax/render tests did NOT catch it (RECURRING gate-gap).**
- **Recovery:** review caught the duplicate parallel relation manually.
- **Prevention:** LikeC4 permits parallel relations between the same pair, so the c4 tests are structurally blind to a duplicate edge. Before adding a C4 edge, `grep model.c4` for an existing `<A> -> <B>` first. (Candidate, NOT built here: a c4-test enhancement to flag duplicate relations between the same pair.)

**4. Implementation subagent ended twice without its Session Summary (mid-wait on a background test-all) (RECURRING workflow friction).**
- **Recovery:** re-spawned / reconstructed the summary from the transcript.
- **Prevention:** a subagent whose final step waits on a background command should poll-to-completion inline (or emit its Session Summary before backgrounding), never end the turn on the background launch.

**5. A background verification command ending in `grep -c '[FAIL]'` returned exit 1 on ZERO matches → the harness reported the whole command "failed" though the suite was clean (RECURRING foot-gun).**
- **Recovery:** re-read the actual test-all output; suite was green.
- **Prevention:** never let a trailing `grep -c` be the exit-status of a background command; append `|| true` or restructure so test-all's own exit code is the signal.

**6. `scripts/test-all.sh` exceeds the 2-min foreground Bash cap (one-off/known).**
- **Recovery:** re-ran backgrounded.
- **Prevention:** run `test-all` backgrounded or via Monitor, never as a foreground Bash call.

## Solution

One PR combined the observability + the fail-loud hardening, verified by one `registry-host-replace` redeploy:

**Fail-loud, non-wedging resize (cloud-init):**
```bash
# Before (silent phantom-success — a resize failure looks like success):
resize2fs "$DEV" || true

# After (capture exit, emit to telemetry, still launch zot — fail-loud, not fail-wedge):
if resize2fs "$DEV"; then RESIZE_OK=true; else RESIZE_OK=false; fi
# ... assert post-resize fs size ≈ block-device size; persist /var/lib/zot/.resize-result
# ... a persistent fs_size_gb≈10 on a 30 GB device confirms the fs-never-grew hypothesis
```

**Guest-df telemetry to Better Stack (SSH-free, the real disk-full signal):**
```bash
# ONE structured line per run, POSTed to Better Stack Logs; queryable via betterstack-query.sh --grep SOLEUR_ZOT_DISK
SOLEUR_ZOT_DISK pcent=… fs_size_gb=… block_size_gb=… resize_ok=… zot_restarts=… ping_rc=…
```

**Commands to verify (post-redeploy, no SSH):**
```bash
doppler run -p soleur -c prd_terraform -- \
  scripts/betterstack-query.sh --since 30m --grep SOLEUR_ZOT_DISK
# expect: resize_ok=true, fs_size_gb≈28 GiB, pcent<85
```

## Why This Works

1. **Root cause:** the ext4 fs on the 30 GB volume was full because `resize2fs` had silently failed (`|| true`) and the fs never grew past ~10 GB. Both the zot `500`-on-write and the skipped heartbeat are downstream of that one fact.
2. **Why the fix addresses it:** removing the silent-swallow makes the resize outcome observable (`resize_ok`), and the guest-df telemetry answers "is the filesystem full?" directly instead of asking the block-device API a different question.
3. **Underlying issue:** a category error (block-device size vs filesystem size) compounded by a masked provisioning failure (`|| true`).

## Prevention

- **Block-device size ≠ filesystem size.** For "is the disk full?" you MUST see the guest `df` (filesystem), not the cloud provider's volume API (block device). On a blind/no-SSH host, ship df% telemetry — do not infer from the provider API.
- **No `|| true` on a load-bearing provisioning step.** `resize2fs ... || true` (and any `|| true` on a step whose failure is load-bearing) silently converts a failure into a phantom success. Make it fail-loud (capture exit code, emit to telemetry) but non-wedging on a blind host.
- **A registry 500-on-write + a skipped disk heartbeat that START TOGETHER are the SAME disk-full root cause**, not two independent bugs. Correlate their start times before opening two investigations.
- **"Pushes still succeed" does NOT prove <85%.** Dedup + partial fits mean writes can succeed on a nearly/actually-full fs. Corroborate any write-success signal with an independent df signal before clearing disk-full.

## Secondary Learning — a destroy-guard allow-set member needs its own preserve-backstop if its destruction is catastrophic

When `doppler_secret.registry_betterstack_logs_token` was added to the `registry-host-replace` gate's ALLOW-SET (so its **create** rides the scoped `-replace` dispatch), a **DELETE** of it became invisible to the `out_of_scope` filter and would PASS the gate — then brick the host on boot, because the amended 3-secret boot guard FATALs without the token.

**Lesson:** allow-set membership silences BOTH create AND delete for that address. If deleting the member is catastrophic, add a dedicated `<member>_destroyed==0` backstop plus a paired FAIL fixture — symmetric to the volume `store_destroyed` backstop the gate's own authors already documented. The test-design agent caught this as sev-7.

## Related Issues

- Corrects (same feature lineage, prior remediation): [2026-07-08-verify-disk-fullness-write-health-on-deny-all-host-without-ssh.md](../2026-07-08-verify-disk-fullness-write-health-on-deny-all-host-without-ssh.md) — its "Key Insight" concluded the disk was NOT full using write-success (source 3) as proof; this learning documents why that conclusion was falsified (block-device ≠ filesystem; pushes-succeed ≠ <85%).
- See also: [2026-06-10-betterstack-quota-diagnosis-host-metrics-dominate-generic-http-sink.md](../2026-06-10-betterstack-quota-diagnosis-host-metrics-dominate-generic-http-sink.md) — sibling observability-diagnosis learning.
