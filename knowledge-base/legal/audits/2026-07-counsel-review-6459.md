---
title: "Counsel review audit — #6459 / PR #6919 (active-active web cluster IaC: Art. 30 register re-add of web-2 cx23/hel1 + DRAFTED cross-host replication advance-notice, ADR-143)"
type: counsel-review
date: 2026-07-25
issue: 6459
pr: 6919
adr: knowledge-base/engineering/architecture/decisions/ADR-143-active-active-web-ingress-drain-gated-host-lifecycle.md
related_adr:
  - knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md
  - knowledge-base/engineering/architecture/decisions/ADR-068 (Phase-3 GA multi-host web)
changed_artifact: knowledge-base/legal/article-30-register.md
status: "SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)"
signed_off_at: 2026-07-25
signed_off_by: "clo agent (Soleur legal domain leader) — reviewing authority for v1 per the agent-native company model; external counsel re-review reserved for the re-evaluation triggers below"
brand_survival_threshold: single-user incident
re_evaluation_triggers: "Re-classify + re-run the transfer / balancing analysis at the ADR-068 Phase-3 GA flip, when the DRAFTED cross-host-replication row becomes present-tense (this is the row's own instruction). PLUS: any web_hosts key added/moved to a non-hel1 EU DC (fsn1/nbg1) or — impossible under the validation pin but named for the record — a non-EU DC; web-2 (or any web host) taken into the serving rotation at weight>0 / added to a cloudflare_load_balancer pool / connector predicate (the lb-weight-gate.sh flip); any user personal data landing on web-2's /workspaces volume BEFORE its LUKS-at-rest cutover (#6931) completes; the inter-host replication leg activating on a lawful basis other than Art. 6(1)(b) or introducing a new recipient beyond Hetzner Online GmbH; a shared git-data topology (#6570) that moves bare git objects between hosts on any transport not already covered by the PA-2 (g)(17)-(20) controls; any EEA-out transfer not covered by the disclosed DPF/SCCs."
---

# Counsel review audit — #6459 / PR #6919 (Art. 30 register: active-active web cluster IaC)

> **STATUS: DISCHARGED — reviewed and attested by the `clo` agent on 2026-07-25.**
> The `clo` agent (Soleur legal domain leader) is the reviewing authority for the
> v1 Soleur-as-tenant-zero posture — this is an agent-native company; legal review
> is a CLO-agent function, not a task for the non-lawyer operator. The operator
> retains an optional veto; **external** counsel re-review is reserved for the
> frontmatter re-evaluation triggers. The agent cross-checked every
> implementation-detail claim in the amended register against the actual
> implementing IaC (`apps/web-platform/infra/variables.tf` `web_hosts`, `dns.tf`,
> `lb-weight-gate.sh`) and against ADR-143 (D1/D2/D5/R3) + ADR-119 + ADR-068, and
> **discharges the gate with no blocking condition**. One non-blocking forward
> condition is recorded below.

This audit is the load-bearing evidence for the ship-time Counsel-Review
CLO-Attestation gate on **PR #6919** (epic **#6459**, `feat-web-active-active-iac`,
ADR-143). The sole changed legal artifact is **`knowledge-base/legal/article-30-register.md`**.
The diff makes exactly **three classes of change**, all EU-Hetzner, `replicas=1`,
web-2 out-of-band at serving-weight 0:

1. **Factual host correction** to PA-1 (d)/(e) and PA-2 (d)/(e): the retired
   `fsn1`/`CX33` web-2 (#6538, retired 2026-07-17) is replaced in the prose by the
   re-added **web-2 = `cx23` (2c/4g x86/Intel), `hel1` (Helsinki, Finland),
   serving-weight 0, holding no personal data**.
2. **A new DRAFTED / NOT-YET-ACTIVE row** — "Cross-host workspace replication
   between web hosts" — an **Art. 13(3)-pattern advance-notice / prior-disclosure**
   that explicitly asserts **no present-tense inter-host transfer today** and
   instructs re-classification + re-analysis at the ADR-068 Phase-3 GA flip.
3. **`last_reviewed:` bump 2026-06-15 → 2026-07-24.**

The legal grain is **narrow**: **no new processing activity, no new lawful basis,
no new data subject, no new recipient / sub-processor, no new Chapter V transfer.**
The incremental change on top of the earlier AC10 CLO-reviewed work on this branch
is the `cpx32 → cx23` / `4c/8g → 2c/4g` SKU + spec factual update — no
residency/sub-processor/transfer/lawful-basis change. There are **no
`[DRAFT — pending CLO/counsel review]` markers** to clear in this diff.

## What the IaC actually is (cross-checked against the implementing code)

- **`variables.tf` `web_hosts` default** — `{ "web-1" = { location="hel1",
  private_ip="10.0.1.10" }, "web-2" = { location="hel1", private_ip="10.0.1.11",
  server_type="cx23" } }`. The register's (e) parenthetical claim ("web-2 =
  location `hel1`, server_type `cx23`, private_ip `10.0.1.11`") is **byte-accurate**
  to the map. The re-add comment (variables.tf:101–120) confirms this is a
  **different** host from the `fsn1`/10.0.1.11 warm standby RETIRED 2026-07-17
  (#6538), reusing the freed address. *Confirmed variables.tf:92–121.*
- **EU-DC validation pin** — `location ∈ {nbg1, fsn1, hel1}` (`alltrue` over
  `web_hosts`); a non-EU host is rejected at config-phase before it serves. Backs
  the "no new third-country transfer" claim as a technical guardrail. *Confirmed
  variables.tf:123–126.*
- **cx23 = 2 vCPU / 4 GB, x86** — matched against the sibling `registry_server_type`
  catalog note ("cx23 = 2 vCPU x86, 4GB") and ADR-143 D1 ("cx23 (2c/4g x86/Intel)").
  The register's "2c/4g x86/Intel" is correct. *ADR-143:58.*
- **Out-of-band / serving-weight 0 (ADR-143 D2)** — web-2 is NOT in the ingress
  rotation until the ADR-068 Phase-3 flip: `dns.tf` `cloudflare_record.app`
  `content = hcloud_server.web["web-1"].ipv4_address` (**web-1-only**); the single
  tunnel connector stays web-1-gated; `lb-weight-gate.sh` fail-closes any pre-flip
  pooling (serving-weight TOP-GUARD, Condition C asserts dns web-1-only + connector
  excludes web-2 + no `cloudflare_load_balancer` pools web-2). *Confirmed
  ADR-143:72–80, dns.tf:13–16, lb-weight-gate.sh header + ADR-143 R1.*
- **Sole-copy `/workspaces` is web-1's (ADR-119 / ADR-143 D2)** — a request to web-2
  pre-flip hits the empty `/workspaces` = "workspace-gone"; the single volume mounts
  to one host at a time. ADR-119 independently records "web-2 has never served user
  traffic and its volume is empty." *Confirmed ADR-119:44–45, ADR-143:74, variables.tf:116–117.*
- **Pre-Phase-3 failover = volume-preserving reprovision, NOT replication (ADR-143 D5)**
  — detach → recreate host → reattach → `luksOpen`; because the volume is the sole
  copy and mounts to one host at a time, no user workspace code crosses between
  hosts. The DRAFTED row's present-tense "no inter-host transfer" rests on this.
  *Confirmed ADR-143:88–92.*
- **web-2's own `/workspaces` volume is plaintext today (ADR-143 R3, #6931)** — the
  guest-side fresh-boot LUKS path is DEFERRed to the Phase-4 disposability-proof PR,
  made fail-CLOSED by a `WORKSPACES_LUKS_CUTOVER_AT` precondition on
  `lb-weight-gate.sh` Condition B (a plaintext web-2 **cannot be pooled**). ADR-143 R3
  makes the **same GDPR determination this audit reaches**: "web-2 holds NO user data
  pre-flip → no GDPR Art. 32 at-rest exposure." *Confirmed ADR-143:113–117.*

## Per-row verdict

| Register row (diff) | Claim(s) cross-checked against code | Verdict |
|---|---|---|
| Frontmatter `last_reviewed` 2026-06-15 → 2026-07-24 | A CLO-agent review actually occurred on-branch (this attestation, plus the earlier AC10 review) | **CONFIRMED** — accurate; the review is real, not a rubber-stamp. |
| **PA-1 (d) Recipients** — "web-2 cx23 in `hel1` — out-of-band standby at serving-weight 0 currently processing no personal data" | Replaces the stale "web-2 CX33 in `fsn1`"; Hetzner remains the single named processor; host-level detail only | **CONFIRMED** — matches variables.tf web-2 shape and ADR-143 D2; conservative (names the host, states it holds nothing). |
| **PA-1 (e) Third-country transfers** — web-2 = cx23/hel1/Finland, RE-ADDED by #6919/ADR-143 replacing the retired fsn1 web-2; "no new sub-processor and no new third-country transfer"; explicitly "verified against variables.tf web-2 = hel1/cx23/10.0.1.11"; serving-weight 0, sole-copy volume is web-1's | Both endpoints Hetzner Online GmbH, same EU account/AVV, both `hel1` (Finland, EU); EU-DC validation pin cited | **CONFIRMED** — legally sound (analysis (a) below); the in-prose code citation resolves exactly. |
| **PA-2 (d) Recipients** — "web-2 cx23 in `hel1` — out-of-band standby at serving-weight 0 currently holding no workspace files" | Replaces stale "web-2 CX33 in `fsn1`"; transient per-conversation workspace files only | **CONFIRMED** — accurate; web-2 routes no traffic so holds no transient workspace files. |
| **PA-2 (e) Third-country transfers** — web-1 (`hel1`) holds transient files; re-added web-2 (`hel1`, cx23) "currently holds **none** — at `replicas=1` the sole-copy `/workspaces` volume is web-1's and web-2 serves no traffic (serving-weight 0, ADR-143 D2)" | replicas=1 single-volume-single-host reality; ADR-119 sole-copy + ADR-143 D2 | **CONFIRMED** — accurate (analysis (b) below). |
| **NEW DRAFTED row** — "Cross-host workspace replication between web hosts — DRAFTED / NOT-YET-ACTIVE (activates at Phase 6; ADR-068 Phase-3 GA)"; Art. 13(3) advance-notice; asserts NO present-tense inter-host transfer; on activation → (c) end-users / workspace file content, (d) Hetzner only, (e) transfers = none, basis Art. 6(1)(b), (g) PA-2 (g)(17)-(20) extended + web-2 LUKS (#6931); instructs re-classify at GA flip | Present-tense no-transfer rests on ADR-143 D5 (reprovision ≠ replication) + D2 (out-of-band) + ADR-119 (sole-copy); future-tense scoping matches ADR-068/#6570 blockers | **CONFIRMED** — the present-tense assertion is accurate and the forward scoping is correct and conservative (analysis (b)/(c) below). |

## Resolution axes

### (a) "No new sub-processor / no new third-country transfer" — RESOLVED / correct
Both web hosts are **Hetzner Online GmbH** — a single processor already named in
PA-1/PA-2 (d), under one account and one Auftragsverarbeitungsvertrag (AVV/DPA).
Re-adding a host **within** that existing processor's EU footprint introduces:
- **No new sub-processor.** Hetzner is a **direct processor**, not a sub-processor,
  and the recipient category is unchanged. No Art. 28(2)/(4) sub-processor-change
  notice obligation is triggered by adding capacity inside the same processor.
- **No new Chapter V transfer.** Both `hel1` (Finland) and `web-1`'s `hel1` are **EU**
  datacentres; there is no export to a third country, so Art. 44 et seq. are not
  engaged. The `var.web_hosts` EU-DC validation pin (nbg1/fsn1/hel1) is the technical
  control that makes a non-EU placement structurally impossible before it serves.

The claim is **legally sound**.

### (b) DRAFTED advance-notice "no processing today" — RESOLVED / accurate
The register's present-tense assertion that **no inter-host transfer of personal data
occurs today** is accurate against the out-of-band, serving-weight-0, single-volume
reality:
- web-2 is at **serving-weight 0**, routed **no** traffic (`dns.tf` web-1-only, tunnel
  web-1-gated, `lb-weight-gate.sh` fail-closes pooling), and its `/workspaces` is
  **empty** (sole copy is web-1's).
- Pre-Phase-3 failover is a **volume-preserving reprovision, explicitly NOT
  replication** (ADR-143 D5) — the single volume mounts to one host at a time, so no
  user workspace code crosses between hosts.
- Listing web-2 in (d) with the explicit "currently processing no personal data"
  qualifier is a **conservative disclosure**, not an Art. 30 accuracy defect: it names
  the host and truthfully states it holds nothing. The Art. 13(3) advance-notice
  framing (disclose-before-you-process) is the right posture and does not overstate.

### (c) Lawful basis / retention / Art. 6(1)(f) LIA — RESOLVED / no gap
- **Lawful basis.** Today web-2 processes nothing → no basis required. On activation
  the register declares **Art. 6(1)(b)** (contract performance) for the replication
  leg — replicating user workspace code to deliver contracted HA/concurrent serving
  is necessary for the service, consistent with PA-2. Because the leg is 6(1)(b) (not
  6(1)(f)), **no new LIA is required**. No new special-category processing.
- **Retention.** No new retention period is introduced; on activation the replicated
  content is the **same** workspace-file category already covered by PA-2 and inherits
  its cascade. Today, web-2 holds nothing → no retention question arises.
- **Art. 6(1)(f) LIA.** Not triggered. The pre-existing 6(1)(f) bases (PA-2 co-member
  shared-asset retention; PA-4 viewer access logs) are unaffected by re-adding an
  empty standby host. The re-add is infrastructure under the existing 6(1)(b) plane.

## Non-blocking forward condition (not a ship blocker)

- **web-2's `/workspaces` volume is plaintext today (ADR-143 R3 / #6931).** This is
  **not** a present-tense Art. 32(1)(a) encryption-at-rest exposure, because the
  volume holds **no personal data** pre-flip (serving-weight 0, empty) — ADR-143 R3
  reaches the identical determination, and the plaintext-pooling path is **physically
  merge-gated**: a `WORKSPACES_LUKS_CUTOVER_AT` precondition on `lb-weight-gate.sh`
  Condition B reddens any flip until web-2's `/workspaces` is asserted LUKS-backed.
  The DRAFTED row discloses this honestly ("web-2's `for_each` volume is plaintext
  today per ADR-143 R3", tracked #6931). **Condition, not gap:** the LUKS-at-rest TOM
  (PA-2 (g)(13)/(17)) MUST extend to web-2's volume **before any user data lands / the
  GA flip** — already tracked (#6931) and gated. Named here for the record and carried
  into the frontmatter re-evaluation triggers.

## Overall disposition

**DISCHARGED — proceed to ship.** All three change classes are **factually accurate
against the implementing IaC** (every host/DC/SKU/IP/weight claim resolves to
`variables.tf`, `dns.tf`, `lb-weight-gate.sh`, ADR-143 D1/D2/D5/R3, ADR-119, and
ADR-068), **legally sound** (no new sub-processor, no new third-country transfer, no
new lawful basis, no new data subject, no new retention obligation), and
**conservatively disclosed** (the DRAFTED row's present-tense "no processing today"
assertion is correct and its re-classification instruction is precise). No prose
misstates the code — this diff is free of the disclosure-hallucinated-against-code
drift class of PR #4353/#4558. The single forward condition (web-2 LUKS-at-rest, #6931)
is non-blocking, requires no in-diff prose correction to ship, and is already
physically merge-gated. **There are no `[DRAFT — pending CLO/counsel review]` markers
to clear in this diff.** All output remains **draft material requiring professional
legal review**; this attestation is the v1 internal CLO-agent sign-off, with the
operator's optional veto retained and external counsel re-review reserved for the
frontmatter re-evaluation triggers — chief among them the ADR-068 Phase-3 GA flip, at
which the DRAFTED replication row becomes present-tense and MUST be re-classified and
re-analysed against the then-current infrastructure.
