# Learning: verify disk-fullness / write-health on a deny-all-public host WITHOUT SSH

> **⚠️ Correction (2026-07-08, #6240/#6244):** the source-3 signal below ("last CI push succeeded ⇒ disk accepted writes ⇒ not full") is **NOT** a fill-level proof. zot dedups blobs and a partial write can still fit, so a push can succeed on a nearly-full or full fs. In the follow-up incident the disk **was** full: the block device was 30 GB but `resize2fs` had silently failed (`|| true`), leaving the ext4 fs at ~10 GB. Block-device size (Volume API, source 1) ≠ filesystem size — for "disk full?" you MUST see the guest `df%`. This triangulation remains valid for *host-down vs cron-not-installed vs full*, but corroborate fullness with a shipped `df%` marker (`SOLEUR_ZOT_DISK`). See [best-practices/2026-07-08-disk-full-reads-as-not-full-when-you-check-block-device-not-filesystem.md](best-practices/2026-07-08-disk-full-reads-as-not-full-when-you-check-block-device-not-filesystem.md).

**Date:** 2026-07-08
**Feature:** registry-host-replace CI dispatch path + Better Stack `ops@` recipient IaC (`feat-one-shot-registry-redeploy-path-ops-alerting`). Plan `2026-07-08-fix-registry-host-replace-ci-path-and-ops-alerting-plan.md`; amends ADR-096.
**Context:** one-shot pipeline. The `soleur-registry-disk-prd` Better Stack missed-heartbeat incident had to be diagnosed on a host with **no SSH** (deny-all-public firewall), and the redeploy verified without ever touching the box.
**Rule served:** `hr-no-dashboard-eyeball-pull-data-yourself`.

## Problem

A Better Stack **missed-heartbeat** incident (`soleur-registry-disk-prd | Missed heartbeat`) fired for the self-hosted zot registry host. The heartbeat is disk-gated: `zot-disk-heartbeat.sh` pings only while `/var/lib/zot < 85%` used. A missed heartbeat is therefore **ambiguous** — it means *either*:

- the disk-gating cron was never installed / not yet running (a benign false positive — e.g. right after a host `-replace`), **or**
- the disk genuinely crossed the 85% fill threshold (a real, urgent condition).

The registry host is **deny-all-public with no SSH**, so the obvious disambiguator — shelling in and running `df -h /var/lib/zot` — is unavailable. A single missed-heartbeat presence/absence signal cannot, alone, separate host-down vs cron-not-installed vs disk-full (the H2 discrimination limit noted in the plan's Observability block).

## Key Insight — triangulate disk-fullness/write-health from cloud-provider APIs + last-write outcome, never from the heartbeat alone

The incident was resolved **without touching the host** by self-pulling three independent observability sources and corroborating them. No SSH, no dashboard eyeballing.

### 1. Hetzner Volume API → block-device size + attach status
`GET /v1/volumes?name=soleur-registry-store` confirms the backing block device's **size** (30 GB) and that it is **attached** to the server. This establishes the denominator of "percent full" and rules out a detached/missing volume — facts the heartbeat cannot convey.

### 2. Hetzner server disk *metrics* → write activity (is it actively filling?)
`GET /v1/servers/{id}/metrics?type=disk` shows disk I/O over time. **Near-idle write activity = the disk is not actively filling.** A disk racing toward 85% looks different from a quiescent one; the metrics series is a cloud-side, SSH-free proxy for "is this trending toward full right now."

### 3. The last CI release run's zot-mirror step logs → the last *write attempt's outcome*
The most recent CI release run mirrors blobs into zot. Its logs showed **many `pushed blob: sha256:...` lines with ZERO `500 no space left on device`.** A successful push is a **positive write-success signal**: the disk *accepted writes* at that moment, so it was **not full**. The success/failure of the last actual write attempt is the single most decisive SSH-free signal.

**Generalizable rule:** for a blind / deny-all host, disk-fullness and write-health are verifiable from **(a)** the cloud provider's volume API (size + attach), **(b)** the provider's server disk metrics (fill trend / write activity), and **(c)** the success-or-failure of the **last real write attempt** in CI/app logs. Triangulate all three — no SSH, no dashboard.

### Corroboration discipline (the deadlock breaker)
A never-pinged disk-gated heartbeat (`last_event_at` absent → cron simply not installed yet) is **NOT proof of disk-full.** Before concluding *either* "false positive" *or* "genuinely full," corroborate with an **independent write-success signal** (source 3 above). Absence of a ping is diagnostic-inconclusive on its own — the same fail-safe-output-is-not-proof discipline as `hr-verify-repo-capability-claim-before-assert`.

### Better Stack heartbeat API shape (verify liveness via `status`, not a ping timestamp)
The Better Stack heartbeat API exposes `attributes.status ∈ {paused, pending, up, down}` but has **NO `last_event_at` field.** Liveness must be read from `attributes.status`, and only `status == "up"` proves the redeploy's first ping actually arrived (`paused`/`pending`/`down` must NOT pass a redeploy gate). Any verification that computes `last_event_at >= APPLY_START` is unimplementable against this API — this was a P0 caught in plan review and is the authoritative bounded-poll in Phase 5.3.

```bash
# SSH-free liveness read (status, NOT a ping timestamp):
TOKEN=$(doppler secrets get BETTERSTACK_API_TOKEN -p soleur -c prd_terraform --plain)
curl -fsS --max-time 10 -H "Authorization: Bearer $TOKEN" \
  https://uptime.betterstack.com/api/v2/heartbeats \
  | jq -r '.data[] | select(.attributes.name=="soleur-registry-disk-prd") | .attributes.status'
# expected: up
```

## Session Errors

1. **IaC-routing PreToolUse `systemctl`-prose flag (plan phase).** The IaC-routing hook flagged an infra-prose edit; resolved via a reviewed `iac-routing-ack` marker. One-off.
   **Prevention:** already hook-enforced — inline the `<!-- iac-routing-ack: … -->` marker per-edit when the edit carries `systemctl` / `doppler secrets set` prose (the hook scans each edit in isolation).

2. **`spec-flow-analyzer` needed the `soleur:product:` prefix (plan phase).** The agent spawn failed without the fully-qualified `soleur:product:spec-flow-analyzer` name; relaunched with the prefix. One-off.
   **Prevention:** spawn domain agents by their fully-qualified `soleur:<domain>:<name>` id; a bare agent name does not resolve.

3. **Stale plan premise: assumed a pending 10→30 GB `hcloud_volume.registry` `["update"]` resize (RECURRING).** The plan assumed a pending volume resize would ride into the scoped `-replace`; the live Phase-0.5 dry-run showed the volume is **ALREADY 30 GB** (`no-op`). Gate design was unaffected (it permits no-op) but two post-merge ACs asserting "resized to 30 GB" had to be reworded to "30 GB (update or no-op)."
   **Prevention:** plan-time live-infra state (volume sizes, resource existence, `["update"]` vs `no-op`) are **preconditions to re-derive at `/work` via a scoped `terraform plan`**, never quoted facts. Reinforces the plan-quoted-numbers rule (`hr-when-a-plan-specifies-relative-paths` class): the plan is authoritative for intent, never for live numbers.

4. **Duplicate-block artifacts (one-off, both caught).** A concurrent linter/process inserted a duplicate `betteruptime_team_member.ops` HCL block (impl agent removed it), and the ADR-096 amendment was written twice (architecture review caught it).
   **Prevention:** after authoring a new HCL resource or an ADR amendment, `grep` the file for the resource label / amendment heading to confirm **exactly one** occurrence before moving on.

5. **Vacuous gate fixtures for 3 load-bearing clauses (RECURRING).** The initial 6 destroy-guard fixtures were vacuous for `firewall_ok`, volume-no-op PASS, and `server_replaced` — each would survive deletion of its clause with the suite still green. Review (test-design + security concurring) expanded to 12. A non-vacuity learning already existed and was even cited in the plan, but was not applied at fixture-authoring time.
   **Prevention:** for **every** gate clause, author one isolating fixture that flips to PASS iff that clause is deleted (mutation-matrix completeness) — at **authoring time**, not left for review to catch.

## Tags
category: best-practices
module: apps/web-platform/infra (zot registry, Better Stack heartbeats, Hetzner volume/metrics)
related: ADR-096, hr-no-dashboard-eyeball-pull-data-yourself, hr-verify-repo-capability-claim-before-assert, #6122
tags: [observability, deny-all-host, no-ssh, disk-full, betterstack, hetzner-api, heartbeat, write-health]
