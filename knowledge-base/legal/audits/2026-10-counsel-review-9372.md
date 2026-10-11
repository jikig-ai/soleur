---
title: "Counsel review audit — #9372 (web-2 LUKS rebirth closeout: dated supersession markers in the Article 30 register and compliance posture, destruction-record pointer, encryption-posture ledger row)"
type: counsel-review
date: 2026-10-11
issue: 9372
pr: 10014
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1) — CONDITIONAL, effective only if PR #10014 merges; the owner retains an optional veto, not yet exercised
signed_off_at: 2026-10-11
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the owner retains an optional veto)"
reviewed_commit: "CLO pass at the working tree of commit 5f81147782 (its six corrections applied in 1ccdab0a80); panel pass at 3b71c0ce5b (its findings applied in 8eb89db42b; the CLO re-review of that delta, with six further precision corrections, is applied in the commit after it)"
disposition: "DISCHARGED for the bounded claims in section 2 (formatted/opened plus green probes on a volume that web-2 is not routed any personal data on, its contents not probed); two open conditions below"
blocking_findings: []
applied_in_review:
  - "CLO pass (2026-10-11), six corrections: lead-ins naming the falsified present-tense sentences; each marker disclaims the boot-time consequent; the recovery sentence corrected where a cell has none; routing statement narrowed; reopen wording narrowed; ledger defends_against and does_not_defend narrowed."
  - "Panel pass (2026-10-11, five seats), wording only: the reopen statement now says 'has not been graded' instead of 'no controlled test has exercised', the reboot requests and the three server ids are recorded in section 2, 'holds no personal data' became 'is not routed any personal data (the volume contents have not been probed)', the recovery sentence now says 'not verified; the position is recorded in', and the destruction-record note says 'deleted, not wiped; emptiness not verified'. Dated markers were added to web-host-replace.md. No claim was added; every change narrows one."
conditions:
  - "C-9372-1 — Not discharged, lapses when web-2 receives serving weight or personal data: passphrase-loss recovery for a data-bearing web-class host (Art. 32(1)(c)), #9948; the escrow=missing re-escrow step, #9949; state restore substrate (unversioned Terraform state is one of two passphrase copies), #7992; and the open conditions C3 and C6 of the 2026-10-04 record for #9377 (2026-10-counsel-review-9377.md)."
  - "C-9372-2 — Owner decision pending, not decided here: how strict the emptiness evidence must be before a rebirth destroys a volume (#9642)."
re_evaluation_triggers: "web-2 takes any serving weight or any personal data; a reboot test of a LUKS-backed web volume is run and recorded; a second web host key is added."
---

# Counsel review — #9372 closeout records

Scope: the records changed by the change that flips the `hcloud_volume.workspaces` ledger row from `plaintext-exception` to `luks`. Nothing here changes a premise, a recovery sentence, a conditional that stays open, Residual R4, an EU-pin row, an earlier dated marker, or the privacy policy.

## 1. What was changed and why (append-only)

The Article 30 register and the compliance posture each carried a conditional of the form "IF AND WHEN web-2 has been rebuilt on that path … and the daily on-host probe has read `crypto_LUKS` on the live host … until then it is plaintext-but-empty". The condition has been met on the measured rows below. Each affected cell received a dated, appended supersession marker; the superseded text stays in place. Four cells (the TS-1 row, its "not a statement about web-2 today" clause, T-1, and the PA-1 "Once converted" clause) carry the same evidence sentence with a one-line lead-in naming the sentence they supersede. The destruction record received a dated pointer note under its table; its "Other copies of workspace data" field value is not rewritten.

| Placement | Anchor (content, not line number) | Action |
|---|---|---|
| Article 30, PA-1 (e) | "no register entry may describe it as encrypted." | marker |
| Article 30, PA-1 (e) | "not to a new recipient." (the "Once converted" sentence) | marker |
| Article 30, cross-host replication row | the same "IF AND WHEN … describe it as encrypted." span | marker |
| Compliance posture, Hetzner DPA-scope row | the same span | marker |
| Compliance posture, TS-1 row | "Until the single-use rebirth (#9372) has run" | marker |
| Compliance posture, TS-1 row | "not a statement about web-2 today" | marker |
| Compliance posture, T-1 row | "Once web-2 has been converted" | marker |
| `web-host-replace.md` | the discriminate-fatal section, its "Until #9372 has run" notice and the rebirth-runbook index entry | three dated markers |
| ADR-263 | the 2026-10-08 "Status of the claim" paragraph, and a 2026-10-11 addendum | marker, addendum (status left at `adopting`, owner decision) |
| `nfr-register.md`, `web2-luks-rebirth-9372.md` row 2, `model.c4` and `model.likec4.json` | the web-2 plaintext-but-empty sentences | dated pointer, `[Done]` line, `[Updated]` sentence, regenerated JSON |
| `workspaces-plaintext-destruction-record.md` | "Other copies of workspace data" | dated pointer note below the table |

The three "IF AND WHEN … describe it as encrypted." spans are 314 characters and byte-identical after bold removal. The marker inserted after each carries the same evidence sentence; the cross-host replication row and the Hetzner DPA-scope row additionally name the present-tense sentence they supersede in their lead-in (CLO correction, 2026-10-11), so the three markers are no longer byte-identical (checked at authoring time; the markers are append-only, so no committed test guards them).

## 2. The marker and its evidence

Marker (as inserted; the lead-in varies per placement):

> **Superseded 2026-10-11 (#9372), …:** web-2's `/workspaces` volume (Hetzner id 107059048, born raw 2026-10-06) is LUKS-formatted and was opened by the running instance (readiness row `luks=1 luks_arm=opened escrow=ok`, boot dd08ac9d, 2026-10-07T20:07Z), and the daily luks-monitor probe rows read `crypto_LUKS` on `/dev/mapper/workspaces` on three distinct days (the #6931 grader returned PASS on 2026-10-10). That is formatted/opened plus green probes; it does not show that the volume can be reopened after a host restart, which has not been graded (ADR-263 addendum 2026-10-08). This marker records that the condition's two limbs are met; it does not adopt the boot-time consequent of the sentence it supersedes. web-2 is not routed any personal data (serving weight 0, no DNS or load-balancer route; the volume's contents have not been probed). The recovery sentence wording differs by placement: the cross-host replication row and the Hetzner DPA-scope row carry recovery sentences and say "The recovery sentences in this cell are unchanged and stay conditioned on the data-bearing period (#9948, #9949, #7992)."; the other five placements carry no recovery sentence and instead say "Recovery for the data-bearing period is not verified; the position is recorded in the cross-host replication row of the Article 30 register and the Hetzner DPA-scope row of the compliance posture, and stays conditioned on that period (#9948, #9949, #7992)."

| Claim in the marker | Evidence (read 2026-10-11, no SSH, no dashboard) |
|---|---|
| volume 107059048, born raw 2026-10-06 | Hetzner API read with the read-only token: name `soleur-web-platform-data-web-2`, created 2026-10-06T18:21:50Z, size 20, attached to the web-2 server, `format` null (no Hetzner-side filesystem format), `protection.delete` false |
| LUKS-formatted and opened by the running instance | Better Stack: `SOLEUR_FRESH_BOOT_READY` row `luks=1 luks_arm=opened escrow=ok`, boot dd08ac9d, 2026-10-07T20:07Z (read through the grader) |
| probe rows read `crypto_LUKS` on three distinct days | host-side luks-monitor rows `device_type=crypto_LUKS mount_source=/dev/mapper/workspaces`; the grader reported three distinct green days at its 2026-10-10 PASS, and four distinct days when re-run on 2026-10-11 (`scripts/followthroughs/web2-luks-live-6931.sh`, exit 0, newest probe row about 12 hours old) |
| grader PASS 2026-10-10 | sweeper run 38083925201 |
| web-2's volume was formatted by one instance and later opened by others | Better Stack readiness rows (read 2026-10-11): boot 77985247 `luks_arm=formatted` (2026-10-06T18:24Z); boots 479cd3f3 (2026-10-06T19:36Z) and dd08ac9d (2026-10-07T20:07Z) `luks_arm=opened`. Run logs: the rebirth run requested a reboot of server 169085156 at 2026-10-06T18:26Z; run 37671563967 requested a reboot of server 169095540 (created 2026-10-06T19:32Z) at 2026-10-07T19:04Z and its observer reported NOT YET. Hetzner read 2026-10-11: the volume is attached to server 169271252 | the rows are self-reported and instance identity is a weak anchor (ADR-263 addendum 2026-10-08); this record does not treat them as a reopen test, does not claim boot dd08ac9d as one, and does not establish which action caused each boot |
| is not routed any personal data (serving weight 0) | `dns.tf` has a web-1-only A record, `web_tunnel_connector` is web-1 only, no load balancer exists (declared configuration; live DNS not re-read); `lb-weight-gate.sh` is shape-only (#9358) and is not weight evidence | not re-measured by this change; the volume's contents were never probed |

## 3. Bounded Art. 5(2) statement for web-2's deleted plaintext volume

- Volume: Hetzner id 106466179, `soleur-web-platform-data-web-2`, 20 GB, `ext4`, attached to the web-2 server (id 168119324).
- Deleted through the Hetzner API by the gated rebirth workflow, run 37508997529 (2026-10-06): the delete step started at 2026-10-06T18:21:04Z and the apply completed at 18:22:40Z. The run's summary records the volume delete as "404 and an empty name lookup proven". A read on 2026-10-11 returns 404 for that id.
- Dispatch and approval: dispatched by the repository owner and approved by the repository owner (the workflow records the same actor in both roles), after plan-only run 37508066236 (2026-10-06T18:03Z) returned the same emptiness verdict.
- Emptiness evidence: size only. The gate read used bytes over 169 hours (newest sample 94 seconds old): maximum 16,027,648 bytes, minimum 15,556,608 bytes, spread 471,040 bytes, against a 1 GiB ceiling, volume not detached. No probe read the volume's contents, and this record does not interpret what the 16 MB consists of.
- No zeroing step ran; the volume was deleted, not wiped.
- No routing of workspace data to web-2 is recorded (serving weight 0, anti-pooling gate); the routing history was not re-read by this review.
- **Not claimed:** that the deleted volume was verified empty. The statement is that the available evidence (size, serving weight, absence of routing) is consistent with it holding no personal data, and that no stronger evidence exists because the volume no longer exists.

## 4. NOT DISCHARGED — lapses when web-2 receives serving weight or personal data

- Passphrase-loss recovery for a data-bearing web-class host (Art. 32(1)(c)): not verified; the passphrase has two copies (Doppler and unversioned Terraform state) and the header restore path has never been exercised (#9948).
- `escrow=missing` has no re-escrow step (#9949; related #9472, an owner-gated fail-closed decision).
- State restore substrate: Terraform state is one of the two passphrase copies and its R2 backend has no object versioning (#7992; condition C6 of the 2026-10-04 record).
- Condition C3 of the 2026-10-04 record (#9372 items): item 1 (escrow preflight before the first destructive step) is verified done in the workflow step order and its census test; items 2 and 3 are tracked as #9948 and #9949 above.
- Reopen after a host restart: not graded and not claimed (ADR-263 addendum 2026-10-08).
- The volume has no Hetzner delete protection.
- A future web host key is covered by static evidence only until its own probe exists.

## 5. Owner decision pending (not decided here)

#9642 asks how strict the emptiness evidence must be before a rebirth is allowed to destroy a volume. The real dispatches already ran on 2026-10-06 under the unchanged 1 GiB ceiling and 64 MiB spread, so the gating question passed before it was decided. What remains open is whether the owner accepts that history retrospectively (and closes #9642), keeps it open for a future rebirth tool, or wants the thresholds tightened before the cleanup change retires the code that carries them. The cleanup change waits for that ruling.

## 6. Attestation

On 2026-10-11 the CLO agent, as v1 internal attestation authority, reviewed the append-only supersession markers, the destruction-record pointer and the `hcloud_volume.workspaces` ledger flip against the evidence table, and attests them as bounded to formatted/opened plus green probes on a volume that web-2 is not routed any personal data on (contents not probed), with reopen after a host restart, passphrase-loss recovery and the emptiness of the deleted volume expressly not claimed, subject to corrections 1 to 6 being applied; external counsel re-review stays reserved for the frontmatter triggers.

Corrections applied after that review (2026-10-11): (1) the lead-ins of the cross-host replication row and the Hetzner DPA-scope row now name the present-tense sentences they supersede; (2) every marker states that it records the condition's two limbs as met and does not adopt the boot-time consequent of the superseded sentence; (3) the recovery sentence wording was corrected in the five placements that carry no recovery sentence; (4) the routing statement in section 3 was narrowed to what is recorded; (5) "has not been exercised" became "no controlled test has exercised", with an evidence row for the three readiness rows (one `formatted` boot, two later `opened` boots) that this record does not treat as a reopen test; (6) the ledger row's `defends_against` and `does_not_defend` now say web-2 holds no workspace data and that no at-rest claim is made for workspace data on it. Bold nesting in three compliance-posture markers was also corrected. The owner's veto is not assumed: it is surfaced in the pull request.

> **Superseded 2026-10-11 (#9372):** items (5) and (6) above were narrowed again by the panel pass, to 'has not been graded' and 'is not routed any'; see `applied_in_review`.

**Re-attestation of the panel-fix delta (2026-10-11).** On 2026-10-11 the CLO agent re-reviewed the panel-fix delta (3b71c0ce5b..8eb89db42b). Every change narrows a claim and none weakens a disclaimer. The agent re-attests the bounded claims: formatted/opened plus green probes; web-2 not routed any personal data, contents unprobed; reopen not graded; recovery and emptiness not claimed. The re-attestation was subject to six precision corrections (the frontmatter and section 6 wording, the section 2 routing row now citing declared configuration only, the section 4 reopen bullet, a supersession note under the corrections paragraph, the pinned commit, and the ADR-263 addendum no longer tying the formatting boot to a server id), all applied; it stays conditional on the merge of PR #10014.
