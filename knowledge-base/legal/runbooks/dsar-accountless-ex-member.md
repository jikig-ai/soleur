---
title: DSAR Runbook — Accountless Ex-Workspace-Member
status: draft
date: 2026-05-22
related: [4230, 4229, 4319, 4294, 4289]
related_adrs: [ADR-039, ADR-026]
brand_survival_threshold: single-user incident
review_cadence: quarterly + event-driven (first accountless-ex-member request)
---

# DSAR Runbook — Accountless Ex-Workspace-Member

This runbook covers the operator response when a person who **was** a
member of a Soleur workspace but **no longer has an active Soleur
account** files a GDPR Art. 15 / 17 / 20 request.

The authenticated path is the canonical surface: an ex-member who
**still has** an active Soleur account uses
`/dashboard/settings/privacy` (PA-1 + PA-19 covered by the
`workspace_member_removals` ledger landed in PR #4294 / migration
062). This runbook handles the **accountless** edge case — the
person deleted their Soleur account and is requesting access to data
that survived the cascade because they appear in another active
user's records (e.g., as the **inviter** in an attestation row, as
the **removed_by_user_id** in a removal-event row before that
attribution was anonymised, etc.).

Operator's prospect ICP (10-person team, post-onboarding) makes
this scenario **rare-but-load-bearing**: <5 lifetime accountless
ex-members expected through the umbrella #4229 horizon, but each
single instance is brand-survival-relevant. If volume crosses
~10 lifetime / quarter the operator triggers re-evaluation toward a
public/email-proof DSAR intake form per #4302.

---

## Intake channels

Accountless DSAR requests arrive through one of:

1. **`legal@jikigai.com` inbox** — direct email. Most common.
2. **GitHub issue with `label:legal`** — programmatic; primarily for
   security researchers + journalists.
3. **Discord support** — escalated by community-manager to operator.
4. **Hand-off from another workspace member** — the requester reached
   out to a current member who forwarded.

There is **no** unauthenticated public form at v1. Public-form
re-evaluation tracker: #4302.

---

## Art. 12(6) ID-verification template

GDPR Art. 12(6) authorises controllers to request additional
information to confirm the identity of a data subject when there is
"reasonable doubt" — for an accountless ex-member, identity proof is
load-bearing because (a) the account is gone, (b) the email address
of record may be re-used or compromised, (c) any false-positive
release exposes another live user's data via the requester's claimed
prior membership.

Send the following email reply (subject: **"DSAR identity
verification — please reply within 14 days"**):

> Hello,
>
> Thank you for your data subject access request received on
> **{received_at_utc}**. We have logged this request under
> reference **{audit_ref}**.
>
> Because the Soleur account associated with the email address you
> contacted us from is no longer active, GDPR Art. 12(6) permits us
> to request additional information to confirm your identity before
> we release any data. Please reply to this email and provide
> **one** of the following:
>
> 1. A scanned photo or PDF of a government-issued ID (passport,
>    national ID card, or driving licence) with **the photograph and
>    document number redacted** — we only need your full name and
>    date of birth to be visible.
> 2. A signed declaration on letterhead of your current employer
>    confirming your full name and date of birth, including the
>    employer's contact phone number.
> 3. **If your former workspace owner is still a Soleur user**: a
>    forwarded email from that workspace owner confirming your full
>    name, the workspace name, and the approximate date you joined
>    and left.
>
> Once we receive verification material we will process your request
> within the remainder of the 30-day window (GDPR Art. 12(3)),
> counted from your original request date of **{received_at_utc}**.
>
> If we do not receive verification material within **14 days from
> the date of this email**, we will close the request without
> action under Art. 12(6); you may re-open it at any time by replying
> with the requested material.
>
> Verification material is retained for **90 days** after request
> resolution under Art. 6(1)(c) (legal obligation — Art. 5(2)
> accountability), then deleted.
>
> Kind regards,
> Jikigai SARL — Data Protection contact

The redaction guidance (photograph + document number) is intentional:
we need identity attribution, not biometric data or document-level
ID. The retained material falls under PA-1 §(f) retention (90 days
post-resolution).

---

## 30-day SLA per Art. 12(3)

The clock starts at **{received_at_utc}** — the timestamp of the
original request, NOT the verification reply. This is load-bearing:
if the verification round-trip consumes 10 days, the operator has 20
days remaining to fulfil the request after verification lands.

Art. 12(3) permits one **30-day extension** "where necessary,
taking into account the complexity and number of the requests";
extension MUST be communicated to the data subject within the first
30 days with reasons. If invoking, send:

> We are extending the response window for your request
> **{audit_ref}** by an additional 30 days per GDPR Art. 12(3). The
> extension is necessary because **{reason}**. We will respond by
> **{extended_deadline_utc}** at the latest.

The operator-action gate on extension is **"have I touched the
fulfilment work at least once?"** — extensions used to defer
starting are not legally defensible. If the request will be denied
(e.g., verification material insufficient), respond within the
original 30-day window.

---

## Fulfilment

Once identity is verified:

1. Identify the deleted user's `auth.users.id` via a service-role
   query against `dsar_export_audit_pii` (or, if pre-PA-PII audit,
   the operator's pre-2026 `legal@` archive) for prior DSAR exports
   under the same email — the auth_id is the lookup key.
2. If no `dsar_export_audit_pii` row exists (the user never
   self-exported pre-deletion), the operator runs a one-shot
   service-role bundle directly:

   ```bash
   doppler run -p soleur -c prd -- \
     env DSAR_OPERATOR_FALLBACK=1 \
     ./node_modules/.bin/tsx scripts/operator-dsar-bundle.ts \
     --user-id <auth_id> \
     --requester-email <requester_email>
   ```

   (Path TBD — the operator-fallback script is filed as a follow-up
   for the first accountless request that needs it. Until it exists,
   the operator runs `exportSqlTable(<auth_id>, signal)` from a
   one-shot Node script + manually assembles the bundle.)

3. **Workspace_member_removals + attestations rows survive
   `auth.admin.deleteUser()` via the anonymise cascade** — both PII
   columns are NULL post-deletion. The operator's bundle therefore
   shows **only** the lineage columns (workspace_id, removed_at /
   accepted_at, id). This IS the Art. 15 disclosure: the data subject
   sees that a removal/join event existed, but the identity of the
   other party has been NULLed for their privacy.

4. Deliver bundle to the requester via the verification email
   thread, password-protected ZIP (password sent via a separate
   channel — e.g., SMS to the phone number in their verification
   material).

---

## Audit log template

For every accountless request, append to
`knowledge-base/legal/audits/accountless-dsar-log.md` (create on
first request) under the following row schema:

| Field | Example |
|---|---|
| `audit_ref` | `ACCT-DSAR-2026-001` (incrementing, year-prefixed) |
| `received_at_utc` | `2026-XX-XXTHH:MM:SSZ` |
| `intake_channel` | `legal@jikigai.com` \| `github-issue` \| `discord` \| `member-forward` |
| `requester_email_at_intake` | `<email>` (redact for public-facing audit copies) |
| `identity_verified_at_utc` | `2026-XX-XXTHH:MM:SSZ` OR `not-verified` |
| `verification_material_type` | `gov-id-redacted` \| `employer-letter` \| `member-forward` \| `insufficient` |
| `responded_at_utc` | `2026-XX-XXTHH:MM:SSZ` (fulfilment OR rejection) |
| `decision` | `fulfilled` \| `rejected-verification` \| `rejected-no-data` \| `extended-30d` |
| `bundle_sha256` | `<hex>` if fulfilled; `n/a` otherwise |
| `notes` | brief context (e.g., "ex-member of workspace X, removed 2026-04-15") |

The audit row is Art. 5(2) accountability evidence. Retention: 6
years per the longest-jurisdiction floor (UK Limitation Act 1980
§11A); see ADR-039 §Retention for the limitation-horizon analysis.

---

## CLO escalation clause

Escalate to the operator-as-CLO (currently founder, Jean Deruelle,
Jikigai SARL gérant) **immediately** if **any** of the following:

1. The request is from a **regulatory authority** (CNIL, ICO, BfDI,
   etc.) — Art. 31 cooperation obligation; CLO responds directly.
2. The request includes a **complaint about Soleur's processing**
   beyond access — possible Art. 77 supervisory-authority complaint
   precursor; CLO drafts response with counsel sign-off.
3. The request alleges **wrongful removal** (the requester
   challenges the removal event itself, not just the data) — this
   shifts the request from Art. 15 fulfilment to potential Art. 82
   damages claim; CLO loops in counsel before any substantive reply.
4. Verification material **fails** but the requester insists — CLO
   weighs the Art. 12(6) "manifestly unfounded or excessive"
   threshold against rejection. Default: extend verification window
   one additional 14-day cycle before rejecting.
5. The bundle **contains material affecting another live user's
   rights** (e.g., the requester's anonymised attestation row shows
   workspace_id that the live owner has marked confidential) — Art.
   15(4) "rights of others" predicate applies; CLO weighs the
   redaction-vs-disclosure balance per the predicate landed in
   #4319.
6. Volume of accountless requests crosses **3 in a 30-day rolling
   window** — operator-as-CLO triggers re-evaluation of public-form
   intake per #4302.

CLO contact: `legal@jikigai.com` (escalation routes via founder).

---

## Cross-document references

- `knowledge-base/legal/article-30-register.md` PA-19 — the
  `workspace_member_removals` processing activity this runbook
  serves.
- `knowledge-base/legal/compliance-posture.md` DSAR Active Item row
  for #4230 — operational status + cascade-order extension reference.
- `knowledge-base/engineering/architecture/decisions/ADR-039-departed-member-removal-ledger.md`
  — WORM-ledger invariant + 36-mo retention rationale + cascade-order
  requirement + RLS deviation note.
- `apps/web-platform/server/dsar-export.ts` — the export pipeline
  the bundle assembly script invokes.
- `apps/web-platform/server/account-delete.ts:368-412` — the
  cascade-order context this runbook operates downstream of.
- Cross-PR: legal-scaffolding refresh at PR #4289; redaction
  predicate at #4319.

---

> **DRAFT — This document was generated by AI and requires
> professional legal review before use. It does not constitute
> legal advice.**
