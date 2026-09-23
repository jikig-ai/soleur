---
title: "Art. 5(2) destruction record — web-1 root-disk snapshot images (inngest-cutover-pre-*)"
status: pending
date: 2026-09-23
related: [8532, 6178, 8617, 8620]
related_adrs: [ADR-100, ADR-140]
ledger_store: hetzner.web1_inngest_cutover_snapshots
brand_survival_threshold: single-user incident
---

# Art. 5(2) destruction record — web-1 root-disk snapshot images

## What this file is

This is a **precondition**, not yet a record. It is committed dated and with an empty outcome
before any image is deleted. It is completed in the same session as each deletion, in a follow-up
commit made in the operator-gated PR (#8532 PR-4b). Nothing has been deleted as of this commit.

It follows the precedent of `inngest-aof-destruction-record.md`, which says why the template comes first:
a record drafted after a destructive act is a justification, and one drafted before it is a
precondition. That template cannot be reused here. It was written for an empty-store volume recut and
is itself superseded (#8296). These images are populated copies of an unencrypted root disk.

Art. 5(2) makes the controller responsible for demonstrating compliance with Art. 5(1). Deleting
an image that holds personal data is an Art. 5(1)(e) act. Once the image is gone, only a record
made at the time can evidence what was destroyed, when, and on whose authority.

**Status rule.** `status: pending` until the first deletion. It becomes `partial` when some but not
all rows below are executed, and `complete` only when the last row is executed. Each row is filled
**at the moment of deletion**, under the operator's authorization of that exact command. A row
is never filled in advance, and no row is filled from memory afterwards.

This record makes no personal-data breach determination. It records destruction only.

## What the images hold

All four are full snapshot images of **web-1's root disk** (server `123931471`), taken before the
Inngest cutovers (ADR-100). They carry the label `purpose=inngest-cutover-pre`, and delete protection
was off when measured. The root disk is not encrypted, so each image holds, unencrypted, what that
disk held on its creation date:

- the persistent journal: the web app's stdout and stderr, the stream in which #8617 found outbound
  recipient e-mail addresses (Article 30 register PA-8 (f), 2026-09-23 amendment);
- the Inngest state then co-located on web-1, as far as it sat on the root disk, including the
  `/var/lib/inngest` directory (PA-13 (f); the state is shared with PA-14, PA-21, PA-22, PA-27 and PA-31);
- the root-disk credentials of the time (Doppler service tokens and baked monitor configuration).
  Among them is the web app's `prd` Doppler service token, which fetches `SUPABASE_SERVICE_ROLE_KEY`
  (read and write access to the production database, with Row-Level Security bypassed) and
  `BYOK_ENCRYPTION_KEY` (which decrypts the users' stored third-party API keys). For as long as the
  token captured in an image is valid, the image reaches the whole production database and every
  stored BYOK key.
- **Added 2026-09-23, measured from read-only Doppler token metadata and the GitHub run history:**
  - **The `prd` token in the images is dead.** It is web-1's first-boot token, from
    `/etc/default/webhook-deploy`, and it was revoked on 2026-07-30 (`apps/web-platform/infra/server.tf`,
    the rationale comment for the soleur-doppler-token file). The current `prd` token,
    `terraform-prd-20260730`, was minted after the last image. The path the images gave to
    `SUPABASE_SERVICE_ROLE_KEY` and `BYOK_ENCRYPTION_KEY` is therefore closed.
  - **Image `411798619` very likely holds a live credential that fetches a key.** The
    `prd_workspaces_luks` token `workspaces-luks-boot` was created on 2026-07-18 and is still live.
    Cutover runs installed it into `/etc/default/luks-monitor` on 2026-07-20 and at 09:33Z on
    2026-07-23. `411798619` was taken at 15:34Z on 2026-07-23, so it very likely holds that token,
    which fetches `WORKSPACES_LUKS_KEY`. This is inferred from install and image times, not measured
    inside the image. Rotation is tracked at #8632 and is operator-gated. Deleting `411798619` does
    not revoke that token.

Source of the image facts: a read-only Hetzner API listing, `GET /v1/images?type=snapshot`,
on 2026-09-23.

## Disposition and authority, per image

| Image id | Name | Created | Size | Disposition | Hard expiry |
|---|---|---|---|---|---|
| `398857857` | `inngest-cutover-pre-20260618T093102Z` | 2026-06-18 | 23.0 GB | `delete-now`, superseded by `411798619` and not a rollback path; determination: ADR-100 "## Addendum — 2026-09-23 (#8532) — only one of the four `inngest-cutover-pre-*` images is rollback substrate" | 2026-10-06 |
| `406654994` | `inngest-cutover-pre-20260709T180819Z` | 2026-07-09 | 26.9 GB | `delete-now`, superseded by `411798619` and not a rollback path; determination: ADR-100 "## Addendum — 2026-09-23 (#8532) — only one of the four `inngest-cutover-pre-*` images is rollback substrate" | 2026-10-06 |
| `407991378` | `inngest-cutover-pre-20260713T095907Z` | 2026-07-13 | 8.9 GB | `delete-now`, superseded by `411798619` and not a rollback path; determination: ADR-100 "## Addendum — 2026-09-23 (#8532) — only one of the four `inngest-cutover-pre-*` images is rollback substrate" | 2026-10-06 |
| `411798619` | `inngest-cutover-pre-20260723T153403Z` | 2026-07-23 | 23.8 GB | `retained-until` the two UNEXPLAINED groups in the #6178 day-7 soak reading (2026-09-22T20:38Z) are attributed and a SOAK CLEAN reading lands, then released in ADR-100's verb order, before #6178 closes | 2026-10-06 (the soak probe's `horizon_passed` date) |

**Hard expiry means deletion is due on that date whatever the soak says.** Retention past it
requires an Article 30 amendment dated before it that records a new purpose and a new date.
Silence does not extend it.

**Release order.** ADR-100's 2026-09-19 addendum listed all four images under one release step
that follows a clean day-7 reading. The engineering determination that splits the set is ADR-100's
"## Addendum — 2026-09-23 (#8532) — only one of the four `inngest-cutover-pre-*` images is
rollback substrate". It finds that the older three are outside the #6178 rollback substrate,
because no runbook, workflow or rollback arm restores from them, and each of the three
`delete-now` rows above cites it. The #6178 spec pins only `411798619`
(`knowledge-base/project/specs/feat-one-shot-6178-verify-window-decouple/tasks.md`).
**[2026-09-23 (#8532): the determination is recorded.** It is in ADR-100, `## Addendum — 2026-09-23
(#8532) — only one of the four inngest-cutover-pre-* images is rollback substrate`. The listing
it relies on was a read-only `GET /v1/images?type=snapshot`, which returned exactly four
snapshots, all from server 123931471. `type=backup` returned 0. Cite that addendum in each
`delete-now` row.**]**

## Record (empty until the moment of deletion)

| Image id | Authorised by (operator, per command) | Command (verbatim, as authorised) | Executed at (UTC) | API verification of absence |
|---|---|---|---|---|
| `398857857` | | | | |
| `406654994` | | | | |
| `407991378` | | | | |
| `411798619` | | | | |

Rules for filling a row:

- **Authorised by:** the operator's own message in the session that authorised this exact command.
  A menu acknowledgement is not authorization of a production write.
- **Command:** the exact command run, copied verbatim, with any token shown as a variable name
  and never as its value.
- **Executed at:** the completion time reported by the command or API response.
- **API verification of absence:** a read-only `GET /v1/images/<id>` made after the delete, with
  its result recorded (expected: HTTP 404, `not_found`). A delete command's exit status alone is
  not verification.
- For `411798619` only, also cite the #6178 comment carrying the SOAK CLEAN reading that released
  it, or state that the hard expiry was reached without one.
- For the three `delete-now` rows, the determination is the ADR-100 2026-09-23 addendum cited in
  the disposition table; record the ADR-100 commit it was read at.

## Lawful basis for destruction

- **Art. 5(1)(e), storage limitation.** The only purpose these images serve is rollback of an
  Inngest cutover. The three older images are superseded by `411798619` and serve no purpose.
  `411798619` serves that purpose only until the #6178 soak reads clean or the probe's horizon
  passes. Beyond that point, keeping any of them keeps personal data longer than necessary.
- **Art. 17(1)(a).** The data in them is no longer necessary for the purpose for which it was
  collected or otherwise processed. Deleting the whole image is the only erasure available for
  these copies (register PA-8 (f): no erasure path reaches them).
- **Art. 5(1)(f) and Art. 32.** Each image is an unencrypted copy of a root disk that held
  credentials and personal data. While the images exist, that exposure exists at the provider.

## Recoverability

None. Deleting a Hetzner image is permanent, and no copy is kept elsewhere. Deleting
`411798619` removes the #6178 rollback substrate. That is why it waits for the soak or the expiry,
and why the three older images are not held as its substitutes.

## What deletion does not do

- **It does not revoke any credential.** This record makes no statement about whether the Doppler
  tokens and other credentials held on the root disk at each image's date have since been rotated.
  A credential still valid today stays valid after the image is deleted.
  *(Added 2026-09-23:* the `prd` token in the images is revoked; the `prd_workspaces_luks` token
  very likely in `411798619` is live, and its rotation is tracked at #8632. See "What the images hold".)
- **It does not reach the rest of the class.** Deleting the images leaves the following untouched
  (see register PA-8 (f)):
  - the live persistent journals on the root disks of web-1, web-2, the registry host and the
    Inngest host, which are bounded by capacity, not by time (the git-data host's journal is not
    measured);
  - Better Stack (90 days);
  - Sentry (90 days).

## Completion checklist

- [ ] Each executed row has all four blank fields filled with measured values, not estimates.
- [ ] Each executed row's absence was verified by a read-only API call after the delete.
- [ ] `status:` in the frontmatter reads `partial` or `complete` according to the status rule above.
- [ ] Register PA-8 (f) receives a dated marker recording each deletion, and the ledger row
      `hetzner.web1_inngest_cutover_snapshots` is amended or retired in the same PR once no image remains.
- [ ] If 2026-10-06 passes with any image still present and no amendment dated before it, that is
      recorded here and in PA-8 (f) as an expired retention, not left silent.
