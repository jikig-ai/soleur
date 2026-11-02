---
title: "A6 no-known-access record for the dedicated Inngest keys (incident #11294)"
status: record
date: 2026-11-02
related: [11294, 10136, 10382, 10205]
---

# A6 no-known-access record (dedicated Inngest keys, #11294)

## Provenance

Drafted and filed on 2026-11-02 by a Claude Code agent at the owner's explicit in-session delegation
("I give you my delegation to do it"; "Soleur should do that for Soleur users autonomously"). It is not
a human-typed record. The owner's own statement of what they know is recorded separately below and is
not made by the agent.

## What was exposed and what was done

- The dedicated `INNGEST_SIGNING_KEY` and `INNGEST_EVENT_KEY` pairs were printed as `random_id` values in
  public Terraform run logs (#11294). The cleanup and its counts are in
  `2026-10-31-11294-run-log-evidence-preservation.md` (686 run logs and 498 PR bot comments deleted; 74
  issue bodies and 234 issue comments redacted in place; edit history of the edited items stays readable).
- Both pairs were rotated on 2026-11-02: run 41411331535 (`apply1` succeeded; its reboot-verify job failed
  on a boot_id format read, fixed in #11853) and converge run 41461246883 (reboot, `apply2` and redeploy
  succeeded; `converge_ok`). After the redeploy the event-key rejections stopped: 0 rows after 14:30Z,
  against 85 rows in the 30 minutes 12:59Z to 13:29Z. Source: Better Stack rows from the Inngest server
  matching "event key not recognized". Attribution: Jikigai's own web app, still holding the old key (the
  app logged matching 401 responses for its own events); the sender of each row was not individually
  verified.

## Measured evidence (2026-11-02, read-only)

- Hetzner server list, read-only: 5 servers, all attached to 10.0.1.0/24, all Jikigai's (web-platform
  10.0.1.10, web-2 .11, git-data .20, registry .30, inngest .40). No foreign server on the network.
- Host nftables re-read through the `tls-health` emit on the current boot: `nft_rules=7`,
  `nft8443_sha256` present, `legacy_8288_packets=0`.
- TLS soak PASS over 48 h from 2026-10-30T15:15:48Z (568 rows, one host, one boot id).

## Known access

None is known to the recorder on the evidence cited here. This is a statement about what is known, not a
claim that nobody read the exposed values. Use-of-key signals and who read the logs remain inconclusive
(CLO position of 2026-11-01), the known gaps in the 2026-10-31 evidence record apply (16 unreadable logs,
unscanned artifacts, expired logs), and the edit history of the edited items remains readable. This
concerns the revoked pre-rotation values of the dedicated Inngest pair only.

## Not covered

The other exposed keys are not yet rotated (CTO order: `inngest_manual_trigger_secret_prd`, then
`github_webhook_secret`, `kb_drift_ingest_signing_key`, `egress_audit_ingest_token`, the `_dev` keys,
`tunnel_secret` last and separate). This record covers the dedicated Inngest pair only. The CLO
re-assesses on 2026-11-08 if the remaining rotations are not recorded complete in #11294.

## Owner confirmation

Typed by the owner (Jean Deruelle, owner) in the Claude Code session on 2026-11-02 and quoted verbatim:

> I know of no access to, or use of, the exposed Inngest keys by anyone other than Jikigai

The agent that filed this record did not write the sentence and does not vouch for what the owner knows.
The S6-A6-DONE line is posted on #10136 once this record is merged and linked from #10382 and #10136.

## CLO attestation

2026-11-02, CLO agent attestation (not external counsel): I attest that this record, as corrected, states
only what its cited evidence supports and does not claim that no one read the exposed values.
