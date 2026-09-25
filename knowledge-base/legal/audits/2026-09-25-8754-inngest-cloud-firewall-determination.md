---
title: "CLO determination — the dedicated Inngest host ran without its declared deny-all cloud firewall (#8754)"
type: clo-attestation
date: 2026-09-25
issue: 8754
attestation-authority: clo
status: SIGNED-OFF PROVISIONAL (CLO-agent-attested, Soleur-as-tenant-zero v1, 2026-09-25)
disposition: "NO PERSONAL-DATA BREACH ESTABLISHED under Art. 4(12) on present facts. An Art. 32 control failure plus a record inaccuracy, not an outcome: no data-bearing surface became internet-reachable and there is no indicator of use. No Art. 33 duty and no Art. 34 duty. An Art. 33(5) register row is warranted. PROVISIONAL on limb L3 (the July 2026 key exposure), whose close-out depends on the separate determination tracked in #8867."
disposition_history: "SIGNED-OFF PROVISIONAL 2026-09-25. L1 narrowed the same day by a Better Stack read: RESOLVED (no successful SSH login) for intervals 2 and 3, INCONCLUSIVE for interval 1. L2 measured on the live host only. L3 PROVISIONAL."
signed_off_at: 2026-09-25
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; operator retains an optional veto)"
awareness_anchor: "2026-09-25 — the Hetzner API measurement recorded in ADR-100's 2026-09-25 addendum (firewall 11269127 `applied_to=[]`; server 167310350 `firewalls=[]`; TCP 22 answering on its public address). The condition had been recorded earlier as an accepted residual (an infrastructure code comment dated 2026-07-08) and in the 2026-07-27/28 incident response (apply run 30623984560, 2026-07-31), but it was not assessed against Art. 4(12) until this record."
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "not due — no Art. 33 duty arose on the facts established to date. Re-opens with a FRESH 72h from awareness of any evidence of use surfaced by a limb below, or by the #8867 determination."
open_limbs: "L1 INCONCLUSIVE for interval 1 only (no sshd record survives for 2026-07-09 to 2026-07-31); RESOLVED for intervals 2 and 3. L2 INCONCLUSIVE for destroyed hosts (nftables load measured on the live host only). L3 PROVISIONAL (whether a root session during the July key exposure could reach personal data), pending #8867."
exposure_window: "Three intervals with no cloud firewall on the dedicated Inngest host: 2026-07-09 22:28 to 2026-07-31 10:34 UTC (about 21.5 days, 18 replaces); 2026-08-12 22:21 to 2026-09-09 08:40 UTC (about 27.4 days, 5 replaces plus one failed); 2026-09-09 15:14 UTC to at least 2026-09-25 (13 replaces; still open at the date of this record, live host 167310350). About 65 of the 78 days since 2026-07-09."
tier_classification: "Tier 1 — an internal assessment record. No public document is edited, no right is narrowed, no processing is added. The mirror/SHA/heading gates are NOT engaged."
semver: "No TC_VERSION bump."
---

# CLO determination — #8754 the dedicated Inngest host without its cloud firewall

## Verdict — NO PERSONAL-DATA BREACH ESTABLISHED. PROVISIONAL on L3.

On the facts established to date this is **not a personal-data breach under Art. 4(12)**. It is
an Art. 32 control that was declared but not in force, plus records that described it as in
force. **Art. 33: No. Art. 34: No.** An Art. 33(5) register row is nonetheless warranted, because
both limbs of the register's inclusion predicate hold (see §Why this is indexed).

The determination is **PROVISIONAL on one limb, L3**. The first gap overlapped the 2026-07-27/28
laptop compromise, when the SSH key authorised on this host was treated as exposed. Whether a root
session in that interval could have reached personal data is not yet established. That question
belongs to the July incident's own determination, tracked in #8867.

This record applies the standing rule that the 2026-06-29 and 2026-09-23 rows of
`knowledge-base/legal/breach-register.md` already follow: **reachability alone does not start the
Art. 33 clock.**

## The fact pattern

`hcloud_firewall.inngest` (Hetzner firewall 11269127) is a **zero-rule deny-all** firewall on the
public interface of the dedicated Inngest host. Art. 30 Processing Activity 13, §(e) and §(g) TOM
(11)(a), record it as the control that denies public reachability.

It was bound by `hcloud_firewall_attachment.inngest`, whose `server_ids` held one server id. An
`inngest-host-replace` creates a new server and leaves the attachment pointing at the destroyed
one. Only the `inngest_host` birth job targeted the attachment, and the per-merge `apply` job's
allow-list never included it. So after each replace the new host ran with no cloud firewall until
a later apply happened to re-bind it. In the whole period only two applies did: run 30623984560
(2026-07-31 10:34 UTC) and run 34330222965 (2026-09-09 08:40 UTC).

Measured on 2026-09-25 through the Hetzner API: firewall 11269127 had `applied_to=[]`, the live
host 167310350 (created 2026-09-24 18:57 UTC by an `inngest-host-replace` run) had `firewalls=[]`,
and a TCP connect to its public address answered on port 22. The mechanism and the fix are recorded
in ADR-100's 2026-09-25 addendum.

## The measured intervals

Measured from the GitHub jobs API (36 successful `inngest_host_replace` jobs between 2026-07-09 and
2026-09-24) and the Terraform apply logs.

| Interval with no cloud firewall | Duration | Replaces in it |
|---|---|---|
| 2026-07-09 22:28 → 2026-07-31 10:34 UTC | about 21.5 days | 18 |
| 2026-08-12 22:21 → 2026-09-09 08:40 UTC | about 27.4 days | 5 (plus one failed on 2026-09-08) |
| 2026-09-09 15:14 UTC → at least 2026-09-25 (live host 167310350) | at least 15.7 days at measurement | 13 |

About 65 of the 78 days since 2026-07-09 had no cloud firewall on the host in service. Birth by
attachment also left a short gap after first boot on 2026-07-08 and on 2026-09-09.

**The condition was known twice before this record.** A code comment dated 2026-07-08 recorded the
stale attachment as an accepted residual. The 2026-07-31 apply recorded its reason as `Incident
2026-07-27/28: … soleur-inngest runs with NO firewall and sshd exposed to the public internet.`
Neither assessed the condition against Art. 4(12).

## What stayed protected

These controls do not depend on the cloud firewall. They held throughout, subject to the L2 limb
below.

- **Ingest ports `:8288`/`:8289`.** The host-local nftables chain (`cloud-init-inngest.yml`,
  `inngest-nftables.sh`) accepts them only from the web hosts' private addresses and drops them from
  every other source. It was measured in force on the live host on 2026-09-25.
- **Redis `:6379`.** Closed because `inngest-redis.conf` binds Redis to loopback
  (`bind 127.0.0.1 -::1`). This is not an nftables effect.
- **The run-history and event-payload read surface.** Inngest gates `/v1/*` (`/v1/functions`,
  `/v1/runs`, `/v1/events`) to loopback-origin requests in software, independent of the socket bind
  and of any firewall (measured 2026-05-31, #4708). This is the surface that bears personal data.
- **Forged events.** The forged-event conclusion rests on signature verification (Art. 30 PA-13
  TOM (7)), not on the network layer.

**A correction to the premise this assessment was commissioned on.** The nftables chain is a
`policy accept` table. It drops only `:8288`/`:8289` from non-web sources and filters nothing else.
No record may say "nftables blocked the data ports". No provisioning explaining `:9000` was found;
it did not answer from the internet on 2026-09-25.

**What became reachable.** Only sshd (TCP 22). It accepts keys only (`PasswordAuthentication no`)
and authorises `hcloud_ssh_key.default`. On the web host SSH is limited to `admin_ips`; on this host,
without the cloud firewall, it was open to the internet.

## Art. 4(12) analysis

Art. 4(12) requires a breach of security **leading to** the accidental or unlawful destruction,
loss, alteration, unauthorised disclosure of, or access to, personal data. A missing defence layer
is a vulnerability, not an outcome. Three facts support the finding:

1. No data-bearing surface became internet-reachable. The ingest ports, Redis and the `/v1/*` read
   surface stayed off the internet through independent host-local controls.
2. The one surface that became reachable, sshd, requires a private key that was not treated as
   exposed outside the July incident window (L3).
3. There is no indicator of use. For intervals 2 and 3 the SSH log records no successful login
   (L1).

## Art. 33 and Art. 34

**Art. 33: No.** No personal-data breach is established, so no notification to the supervisory
authority is due.

**Art. 34: No.** It is assessed on its own facts, not inherited from Art. 33. With no breach
established there is no risk to data subjects of the kind Art. 34 addresses.

## Why this is indexed

Both limbs of the register's inclusion predicate hold. **Limb 1:** a breach-shaped fact pattern
arose — a declared TOM was absent on a host holding personal data, and the absence partly overlapped
a credential exposure. **Limb 2:** it is assessed against Art. 4(12) here. The row is at
`knowledge-base/legal/breach-register.md`.

The personal data on the host is the dedicated Inngest store (event payloads, step input and output,
run state) shared by Processing Activity 13 and by PA-14, PA-21, PA-22, PA-27 and PA-31.

## Evidentiary limbs

### L1 — successful SSH logins while the firewall was absent

- **Intervals 2 and 3 — RESOLVED, no successful login.** Measured 2026-09-25 in Better Stack. For
  2026-08-12 to 2026-09-09 and 2026-09-09 to 2026-09-25, the Inngest host's sshd journal **was**
  shipped off-host. It carries thousands of rows of rejected internet scans (`Invalid user …`,
  `Connection closed by authenticating user root … [preauth]`). It carries **zero** `Accepted
  publickey` and **zero** `session opened for user` events from host `soleur-inngest`. All 105 and
  167 accepted logins in those two windows come from `soleur-web-platform`. Coverage verdict: Better
  Stack, sshd rows from host `soleur-inngest`, both windows.
- **Interval 1 — INCONCLUSIVE.** For 2026-07-09 to 2026-07-31 Better Stack holds no sshd rows from
  any Inngest host. sshd auth events were not shipped off-host before 2026-07-28. The host created
  2026-07-30 shipped zero rows (ADR-100, 2026-08-12 addendum). The replaced hosts' journals were
  destroyed with them. No instrument remains that could answer this interval. It is not certified
  clean.

### L2 — the nftables chain on destroyed hosts

INCONCLUSIVE. The chain was measured in force on the live host only, on 2026-09-25. It is installed
by `cloud-init-inngest.yml` and re-asserted on every boot by a oneshot, so every host born from the
same cloud-init carried it by design. Its load on the destroyed hosts cannot now be measured.

### L3 — the July 2026 key exposure (PROVISIONAL, pending #8867)

`knowledge-base/project/learnings/security-issues/2026-07-28-vscode-folderopen-task-rce-and-fleet-wide-key-rotation.md`
records that the operator key was the only root key on the Inngest host, that it was treated as
exposed from 2026-07-27 until its rotation on 2026-07-28, and that its evidence of non-use covers
**web-1 only**. In that window "key-only" was no barrier, and the Inngest host was in the first gap
and reachable from the internet.

Narrowing evidence measured 2026-09-25: the Hetzner project SSH key used for new hosts
(`hcloud_ssh_key.default`, id 115966111) was created 2026-07-28 11:12:39Z, after the July rotation.
Only hosts born before that time could carry the key treated as exposed, and those hosts were
destroyed by later replacements.

The limb stays **PROVISIONAL** until it is established whether a root session in that window could
reach personal data, either in the host's stores or through credentials provisioned to the host
(Doppler service tokens and the backend connection strings they read). That question is part of the
July incident's own Art. 4(12) determination, which does not yet exist and is tracked in #8867. This
record's L3 closes, or flips, on that determination.

## Findings

| Limb | Status | Coverage verdict (the surface actually queried) | Result |
|---|---|---|---|
| L1 intervals 2 and 3 | RESOLVED 2026-09-25 | Better Stack sshd rows, host `soleur-inngest`, 2026-08-12 to 2026-09-25 | Rejected scans only. 0 `Accepted publickey`, 0 `session opened for user`. |
| L1 interval 1 | INCONCLUSIVE | Better Stack, 2026-07-09 to 2026-07-31: no sshd rows from any Inngest host | Not shipped or not retained. Journals destroyed with the hosts. Not certified clean. |
| L2 nftables load | INCONCLUSIVE for destroyed hosts | live host 167310350 only, 2026-09-25 | In force on the live host. |
| L3 July key exposure | PROVISIONAL | Hetzner SSH key metadata (id 115966111, created 2026-07-28 11:12:39Z) | Only pre-rotation hosts could carry the exposed key; all destroyed. Reach of a root session not established. See #8867. |

**Evidence of use: none found.** No Art. 33 clock starts.

## The fix

The change tracked in #8754 binds the firewall at server creation through
`hcloud_server.inngest.firewall_ids = [hcloud_firewall.inngest.id]`. The provider sends it inside
ServerCreate, so every birth and every replace creates the host with the firewall already applied,
before first boot. `hcloud_firewall_attachment.inngest` becomes a `removed` block (forget, no
destroy). Guard 1 in `apps/web-platform/infra/inngest-host.test.sh` pins the binding.

The fix is effective for hosts born **after the change merges**. The live host 167310350 gains the
firewall only at its next `inngest-host-replace`, because any binding that references
`hcloud_server.inngest` pulls the server's pending replace into the plan. Until that replace runs
and the check below passes, the cloud-firewall layer is to be read as **absent** and TCP 22 as
reachable from the internet.

## Post-replace verification (Hetzner API, no SSH)

After the next `inngest-host-replace`:

1. The new server's `public_net.firewalls` lists firewall 11269127 with status `applied`.
2. Firewall 11269127's `applied_to` lists that server's id.

When both hold, **append a dated "restored" marker after that check** to this record, and to each
record that carries a 2026-09-25 (#8754) correction marker: the Art. 30 PA-13 (e) and TOM (11)(a)
markers, the three assessment addenda, the Inngest runbook and ADR-030. That measurement ends
interval 3. It does not change this determination.

## If the finding flips

A limb flips if it surfaces a successful SSH login on an Inngest host by anyone but the operator's
legitimate path, or if the #8867 determination finds that a root session during the July exposure
could reach personal data and did, or cannot be excluded to the standard that determination sets.

On a flip:

1. **A FRESH 72h Art. 33(1) clock** starts from awareness of that evidence. It does not run from the
   2026-09-25 anchor.
2. **Art. 34 is re-run, not inherited.** It requires *high* risk and is assessed on the facts of the
   flipped limb.
3. **Art. 33(2) processor notification** goes to each controller whose data the flipped limb reaches,
   where Jikigai acts as processor for it. That duty is not conditioned on the Art. 33(1) risk
   threshold.

## Conditions / residual actions

- **REQUIRED — run the replace and the post-replace check.** Interval 3 stays open until then.
  `firewall_ids` is not ForceNew, so an in-place apply is an engineering alternative; the choice is
  the CTO's.
- **REQUIRED — the disposition is not final while L3 is PROVISIONAL.** It closes on the #8867
  determination, recorded here as a dated addendum. L1 for interval 1 and L2 for destroyed hosts are
  expected to stay INCONCLUSIVE; the "inconclusive?" axis keeps its value.
- **RECOMMENDED — a standing rule.** A TOM claim that a provider firewall is attached should cite a
  measured `applied_to` value, not the resource declaration, and a drift assertion that it is
  non-empty would catch the next occurrence. The Art. 30 TOM was written on 2026-09-03 from the
  `.tf` declaration, after the gap was already known.
- **PROCESS — published documents.** No change is required by this finding. Clause (o) of
  `docs/legal/data-protection-disclosure.md` never claims a cloud firewall on the dedicated host, and
  its operative claim ("its ingest ports carry no public route") held throughout because of the
  nftables chain. A separate staleness in the same clause's parenthetical (it still describes the
  co-located deployment as the serving path, false since the 2026-09-15 cutover) is to be tracked in
  its own issue and fixed only after the post-replace check passes.
- **PROCESS — register cross-reference.** This determination is indexed at
  `knowledge-base/legal/breach-register.md`. That index is a pointer, not a copy. This file is the
  canonical record.

## Amendment convention

This record is **append-only**. A later limb result, the restored marker, a changed disposition or
a correction is added as a dated addendum below, citing the text it annotates and amending nothing
above it. That is the 2026-06-29 precedent's convention.
