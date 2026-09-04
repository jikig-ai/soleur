---
title: "Corporate CLA Register"
type: counterparty-ledger
custodian: clo
template: docs/legal/corporate-cla.md
schema_version: 1
last_reviewed: 2026-09-04
related:
  - docs/legal/corporate-cla.md
  - docs/legal/individual-cla.md
  - docs/legal/gdpr-policy.md
  - knowledge-base/legal/article-30-register.md
  - knowledge-base/legal/audits/2026-09-04-clo-ruling-ccla-register-siting-and-coverage-map-basis-3210.md
  - knowledge-base/legal/side-letter-register.md
  - apps/cla-evidence/roster/ccla-roster.json
---

# Corporate CLA Register

This register records each executed Soleur Corporate Contributor License Agreement (per
`docs/legal/corporate-cla.md`) between Jikigai and a corporate counterparty. It is the
operator-facing index of corporate IP-license grants and the join point between an executed
instrument and the public coverage map.

**This register is an INDEX. It is not the evidence.** The evidence is the executed
instrument, which is held off-repo (see Notes). This file is tracked in a **public**
repository — `jikig-ai/soleur`, `visibility=PUBLIC` — and every row committed to it is
world-readable, is copied into every clone and fork, and cannot afterwards be erased. The
schema below is constructed on that assumption, per the CLO ruling of 2026-09-04
(`knowledge-base/legal/audits/2026-09-04-clo-ruling-ccla-register-siting-and-coverage-map-basis-3210.md`,
option B1-c with amendments B1-c-1 and B1-c-2).

## Schema

| Column | Description |
|---|---|
| Record ref | Opaque, stable reference for the counterparty, assigned in order of execution (`CCLA-0001`, `CCLA-0002`, ...). It identifies the row, not a person. For a counterparty covered by the sole-trader rule below, this is the **only** identifier published. |
| Organisation legal name | The counterparty's registered legal name — **only where that name is not a natural person's name**. See the sole-trader rule below. Leave blank where the rule applies. |
| CCLA version hash | SHA-256 of `docs/legal/corporate-cla.md` at the base commit against which the instrument was executed. Identifies *which text* the counterparty agreed to. |
| Instrument hash | SHA-256 of the executed instrument **as received**, over the bytes as received. Gives the off-repo copy git-grade tamper-evidence without publishing anything about a data subject. |
| Signatory on file | `yes` / `no`. A boolean assertion that an authorised signatory executed the instrument. **No name, title, email or address.** Authority to sign is proven by the instrument, not by a row in this file. |
| Authorized from | ISO 8601 date (UTC) from which the grant is effective — the legally operative date stated in the instrument, **not** a commit timestamp. |
| Withdrawn at | Optional ISO 8601 date (UTC) recording that the counterparty's participation ended. A **withdrawal-of-designation marker**, not erasure — see Notes. |

**Prohibited fields — permanent, not gated.** Signatory name, title, email address, postal
address, telephone number and signature image **may never be written to this file or to any
other file tracked in this repository.** This is not a condition awaiting discharge; those
fields are removed from the schema and rest only in the executed instrument. A proposal to
reinstate one re-opens the CLO ruling.

**Sole-trader rule (amendment B1-c-2).** An organisation's legal name is not unconditionally
non-personal. It is non-personal for a *société* or an incorporated company; it is a natural
person's name for a sole trader, or for anyone trading under their own name. Where the
counterparty's legal name **is** a natural person's name, leave `Organisation legal name`
blank and publish the `Record ref` alone; the legal name is held off-repo with the
instrument.

**What this register does NOT carry.** The employer-to-representative association — which
GitHub accounts an organisation has designated as covered under Corporate CLA Section 4(c) —
lives in the public coverage map at `apps/cla-evidence/roster/ccla-roster.json`, not here.
That association **is personal data under Art. 4(1)**; it is published under the Art. 6(1)(f)
basis recorded at `docs/legal/gdpr-policy.md` Section 3.4 (third balancing test) and at PA-7
of `knowledge-base/legal/article-30-register.md`, and entry into it is
**contribution-triggered** (see Notes).

Additional columns (executed-instrument media type, countersignature date, external-counsel
re-review trigger fired) are derivable from the instrument plus this ruling file and are
intentionally NOT in the schema until the register has more than one row — the same
convention as `side-letter-register.md`. Add columns the first time they matter.

## Register

| Record ref | Organisation legal name | CCLA version hash | Instrument hash | Signatory on file | Authorized from | Withdrawn at |
|---|---|---|---|---|---|---|
| (none yet) | | | | | | |

## Notes

- This is a SINGLE LEDGER FILE — not a directory of per-counterparty files. Append rows; do
  not split. Do not rewrite a landed row; append a dated correction, as the Art. 30 register
  does.
- **The executed instrument lives off-repo, on the encrypted operator drive.** The
  repository carries only `docs/legal/corporate-cla.md` and this index. Custody by the
  controller is not disclosure to a recipient.
- **Receipt path, measured 2026-09-04 (not assumed by analogy):** executed instruments are
  received by email at <legal@jikigai.com>, whose mailbox is hosted on **Proton Mail (Proton
  AG, Switzerland)** — MX `mail.protonmail.ch` and `mailsec.protonmail.ch`, SPF
  `include:_spf.protonmail.ch`, `protonmail-verification` TXT present. Switzerland is
  covered by an EC adequacy decision, so no Chapter V mechanism is required for this leg.
  **A mailbox is transport, not custody**: on receipt, the instrument is moved to the
  encrypted operator drive, which is the custody of record and the surface against which an
  Art. 15 or Art. 17 request is answered. Proton AG is recorded as a processor at PA-7 (d);
  its Art. 28(3) instrument is an open item there and is not asserted here.
- **Contribution-triggered entry.** A representative's account identifier and employer
  association are committed to `apps/cla-evidence/roster/ccla-roster.json` only at or after
  that representative has themselves signed the Individual CLA on a pull request in this
  repository. The organisation's Section 4(c) designation list is held off-repo and does not
  by itself write a row. A first pull request may therefore be annotated `covered: false`
  until the map catches up — a latency on an annotation, not a gate on a merge; Corporate
  CLA Section 1 covers future contributions with no cut-off.
- **`Withdrawn at` and `removed_at` are withdrawal-of-designation markers. They are not
  erasure and must never be described as erasure**, in this file, in a data-subject response,
  or in any published document. The surface is a public git repository from which erasure is
  not possible. Do not call either field a "tombstone" — that word already denotes something
  erasure-shaped in this codebase (`tombstones/<sha>.deleted.json` on the R2 evidence path).
- **Art. 17 posture.** Art. 17(3)(b) is not available for this record: no statute obliges a
  contributor roster, and the obligation is contractual and self-imposed. Art. 17(3)(e) is
  available per record for a representative who contributed. Whether indefinite retention of
  the employer-to-account association is proportionate under Art. 5(1)(e), on a surface from
  which it cannot be erased, is open and tracked at #7668.
- The CLO ruling recording why this schema holds no identity field, and the external-counsel
  re-review triggers (more than ten organisations; the first counterparty whose instrument
  must be jointly auditable; the first sole-trader counterparty; any proposal to reinstate an
  identity field), is at
  `knowledge-base/legal/audits/2026-09-04-clo-ruling-ccla-register-siting-and-coverage-map-basis-3210.md`.
