---
title: "Zot private-network accepted-risk record (#10136)"
status: record
date: 2026-11-05
related: [10136, 10538, 10479, 8624, 6897]
---

# Zot private-network accepted-risk record (#10136)

## Provenance

Filed on 2026-11-05 by a Claude Code agent. It is not a human-typed record. The accepted-risk text was
posted by an agent on #10136 for the owner's in-session confirmation — the A7 mechanism, and this
PR's single named operator step. The literal line "SIGNED BY OWNER (human, not an agent)" is not used
and is not claimed.

## The record

- Accepted-risk record: <https://github.com/jikig-ai/soleur/issues/10136#issuecomment-6645392554>
  (agent-posted, 2026-11-05, for owner confirmation). Scope: the two zot links only — (1) web hosts ->
  zot registry (`10.0.1.30:5000`), plain HTTP on the Hetzner private network by design; (2) the GitHub
  Actions runner -> zot registry over the CF Tunnel, whose final leg (origin connector <->
  `10.0.1.30:5000`) is plain HTTP on the private network — the runner<->CF edge and CF
  edge<->origin connector legs are TLS 1.2+.
- Accepted until 2027-01-31 (inside the CLO maximum of 2027-04-24) — the same bound the 2026-10-18
  record set. Voids on a server beyond the five attached to 10.0.1.0/24, a new tenant joining
  10.0.1.0/24, or any public or cross-network exposure of the registry (the issue's own re-evaluation
  triggers).
- Prior record: <https://github.com/jikig-ai/soleur/issues/10136#issuecomment-6251081172>
  (agent-posted 2026-10-18T14:28:29Z at the owner's in-session instruction "sign the accepted-risk";
  the rulings it rests on are at comment 6244056425). It was conditional on three compensating-control
  measurements it recorded as NOT YET MEASURED, and this record supersedes it now that all three are
  discharged:
  - **nftables re-read from the host:** discharged by the 2026-10-18 CTO correction itself — the
    registry carries NO nftables rule (`cloud-init-registry.yml` carries none; Hetzner firewalls
    filter only the public interface), so the control is network membership of the five
    Terraform-defined hosts. The two zot ledger rows' compensating-control prose is reworded to say so
    in this change.
  - **Read-only Hetzner enumeration:** measured 2026-11-02 for the A7 record — 5 servers, all
    Jikigai's, on 10.0.1.0/24 (`2026-11-02-a7-leg2-accepted-risk-ledger-inngest-sdk-url-poll.md`). The
    same enumeration is the network-membership read this record relies on.
  - **Ledger reword:** done in this change — the two zot connection rows point at this record and the
    2026-11-05 ruling, carry a concrete `expires_on` of 2027-01-31, and no longer read "pending the
    CLO ruling".
- Ruling basis: **Ruled by CTO agent, 2026-11-05** — the ruled-acceptance path, not a zot-TLS build.
  TLS-terminating zot on the private NIC is a multi-week arc (cert provisioning, rotation, client
  config on every fresh web boot and five CI callers) wholly disproportionate to a link whose only
  exposure is a passive on-net attacker on a 5-server private segment already carrying @sha256
  digest-pinned pulls and a read-only credential. Recorded at
  `knowledge-base/project/specs/feat-one-shot-10390-ci-hygiene-batch/decision-challenges.md`; dissent
  there is moderate (the zot pull credential stays readable by a future on-net peer), bounded by the
  void triggers above.
- Data on the link: image bytes + a read-only pull credential; no user content. Integrity (not
  confidentiality) comes from the @sha256 digest pin on every pull plus the cosign signature check on
  the deploy path; a fresh web boot sends only @sha256-pinned refs.

## Owner confirmation

Pending — the ci-hygiene-batch PR's single named operator step. Per the A7 mechanism (CLO ruling
2026-11-02, quoted at `2026-11-02-a7-leg2-accepted-risk-ledger-inngest-sdk-url-poll.md`):

> an owner's in-session instruction and confirmation suffice for A7; the literal "SIGNED BY OWNER
> (human, not an agent)" line is not used for an agent-posted record.

Until the owner confirms, the ledger rows cite the ruling plus this posted-for-confirmation record.

## What this does not do

- It does not cover leg 2 of the Inngest channel (the A7 record covers it, until 2026-11-12 and
  extendable to 2026-12-10 only if the #10538 replacement merges by then), the Cloudflare
  flexible-SSL finding (#10479), or any other link.
- It does not close #10136; the issue closes when the owner confirmation lands and the ledger PR
  merges.
