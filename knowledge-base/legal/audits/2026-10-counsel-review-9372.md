---
title: "Counsel review audit — #9372 (web-2 LUKS rebirth closeout: dated supersession markers in the Article 30 register and compliance posture, destruction-record pointer, encryption-posture ledger row)"
type: counsel-review
date: 2026-10-11
issue: 9372
pr: PENDING
status: DRAFT — pending CLO-agent attestation (this record is not signed off until that line is replaced)
signed_off_at: null
signed_off_by: null
reviewed_commit: PENDING
disposition: PENDING
blocking_findings: []
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
| `workspaces-plaintext-destruction-record.md` | "Other copies of workspace data" | dated pointer note below the table |

The three "IF AND WHEN … describe it as encrypted." spans are 314 characters and byte-identical after bold removal, and the marker inserted after each is byte-identical after bold removal (checked once at authoring time; the markers are append-only, so no committed test guards them).

## 2. The marker and its evidence

Marker (as inserted; the lead-in varies per placement):

> **Superseded 2026-10-11 (#9372), …:** web-2's `/workspaces` volume (Hetzner id 107059048, born raw 2026-10-06) is LUKS-formatted and was opened by the running instance (readiness row `luks=1 luks_arm=opened escrow=ok`, boot dd08ac9d, 2026-10-07T20:07Z), and the daily luks-monitor probe rows read `crypto_LUKS` on `/dev/mapper/workspaces` on three distinct days (the #6931 grader returned PASS on 2026-10-10). That is formatted/opened plus green probes; it does not show that the volume can be reopened after a host restart, which has not been exercised (ADR-263 addendum 2026-10-08). web-2 still holds no personal data and sits at serving weight 0. The recovery sentences in this cell are unchanged and stay conditioned on the data-bearing period (#9948, #9949, #7992).

| Claim in the marker | Evidence (read 2026-10-11, no SSH, no dashboard) |
|---|---|
| volume 107059048, born raw 2026-10-06 | Hetzner API read with the read-only token: name `soleur-web-platform-data-web-2`, created 2026-10-06T18:21:50Z, size 20, attached to the web-2 server, `format` null (no Hetzner-side filesystem format), `protection.delete` false |
| LUKS-formatted and opened by the running instance | Better Stack: `SOLEUR_FRESH_BOOT_READY` row `luks=1 luks_arm=opened escrow=ok`, boot dd08ac9d, 2026-10-07T20:07Z (read through the grader) |
| probe rows read `crypto_LUKS` on three distinct days | host-side luks-monitor rows `device_type=crypto_LUKS mount_source=/dev/mapper/workspaces`; the grader reported three distinct green days at its 2026-10-10 PASS, and four distinct days when re-run on 2026-10-11 (`scripts/followthroughs/web2-luks-live-6931.sh`, exit 0, newest probe row about 12 hours old) |
| grader PASS 2026-10-10 | sweeper run 38083925201 |
| holds no personal data, serving weight 0 | unchanged premise; the anti-pooling gate (`lb-weight-gate.sh`) keeps web-2 out of the pool; not re-measured by this change |

## 3. Bounded Art. 5(2) statement for web-2's deleted plaintext volume

- Volume: Hetzner id 106466179, `soleur-web-platform-data-web-2`, 20 GB, `ext4`, attached to the web-2 server (id 168119324).
- Deleted through the Hetzner API by the gated rebirth workflow, run 37508997529 (2026-10-06): the delete step started at 2026-10-06T18:21:04Z and the apply completed at 18:22:40Z. The run's summary records the volume delete as "404 and an empty name lookup proven". A read on 2026-10-11 returns 404 for that id.
- Dispatch and approval: dispatched by the repository owner and approved by the repository owner (the workflow records the same actor in both roles), after plan-only run 37508066236 (2026-10-06T18:03Z) returned the same emptiness verdict.
- Emptiness evidence: size only. The gate read used bytes over 169 hours (newest sample 94 seconds old): maximum 16,027,648 bytes, minimum 15,556,608 bytes, spread 471,040 bytes, against a 1 GiB ceiling, volume not detached. No probe read the volume's contents, and this record does not interpret what the 16 MB consists of.
- No zeroing step ran; the volume was deleted, not wiped.
- No workspace data was ever routed to web-2 (serving weight 0, never pooled).
- **Not claimed:** that the deleted volume was verified empty. The statement is that the available evidence (size, serving weight, absence of routing) is consistent with it holding no personal data, and that no stronger evidence exists because the volume no longer exists.

## 4. NOT DISCHARGED — lapses when web-2 receives serving weight or personal data

- Passphrase-loss recovery for a data-bearing web-class host (Art. 32(1)(c)): not verified; the passphrase has two copies (Doppler and unversioned Terraform state) and the header restore path has never been exercised (#9948).
- `escrow=missing` has no re-escrow step (#9949; related #9472, an owner-gated fail-closed decision).
- State restore substrate: Terraform state is one of the two passphrase copies and its R2 backend has no object versioning (#7992; condition C6 of the 2026-10-04 record).
- Condition C3 of the 2026-10-04 record (#9372 items): item 1 (escrow preflight before the first destructive step) is verified done in the workflow step order and its census test; items 2 and 3 are tracked as #9948 and #9949 above.
- Reopen after a host restart: not exercised and not claimed (ADR-263 addendum 2026-10-08).
- The volume has no Hetzner delete protection.
- A future web host key is covered by static evidence only until its own probe exists.

## 5. Owner decision pending (not decided here)

#9642 asks how strict the emptiness evidence must be before a rebirth is allowed to destroy a volume. The real dispatches already ran on 2026-10-06 under the unchanged 1 GiB ceiling and 64 MiB spread, so the gating question passed before it was decided. What remains open is whether the owner accepts that history retrospectively (and closes #9642), keeps it open for a future rebirth tool, or wants the thresholds tightened before the cleanup change retires the code that carries them. The cleanup change waits for that ruling.

## 6. Attestation

PENDING — to be replaced by the CLO-agent attestation line and the owner-veto note when the review below has run.
