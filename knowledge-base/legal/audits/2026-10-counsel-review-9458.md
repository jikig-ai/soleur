---
title: "Counsel review audit — #9458 / PR #9456 (inbound email routing table `email_inbox_routes` + `recipients` on the Inngest event: Article 30 register PA-27)"
type: counsel-review
date: 2026-10-04
issue: 9458
pr: 9456
status: "SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)"
signed_off_at: 2026-10-04
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "BLOCKED. The register prose is accurate on the table (columns, RLS, cascade, empty-at-ship, operator-only resolution) and the lawful-basis / Art. 17 / Chapter V / Art. 9 answers are adequate. One implementation defect makes the register's Sentry-scrub sentence false for the new field: `recipients` is not in SENSITIVE_KEY_NAMES, so third-party To-line addresses reach Sentry as event-data extras on any captured pipeline error."
blocking_findings:
  - "B1 — `recipients` is not scrubbed from Sentry (server/sensitive-keys.ts; server/sentry-scrub.ts is key-name-based; server/inngest/middleware/sentry-correlation.ts ships `ctx.event.data` as the `inngest.event_data` extra). Violates TR3 and falsifies PA-27 §(d) 'Sentry/Better Stack are NOT recipients of content'."
applied_in_review:
  - "W1 — PA-27 §(d): the parenthetical 'metadata-first statutory checking requires them in the event' now covered `recipients`, which statutory checking does not use. Rewritten: statutory checking requires `subject` + `sender`; `recipients` is there because the routing lookup runs inside the claim step from event data. Also added: `received_for` + `To` only (never cc/bcc), <=20 addresses, third-party status of co-addressees, and that `recipients` is never sent to Anthropic, Resend or the notification path (grep: its only consumer is resolveInboundRoute)."
  - "W2 — PA-27 §(d) Sentry sentence: `recipients` added to the list of scrubbed keys, with an in-cell statement that the sentence is true only once the key is in the list (B1). The cell is written to the post-fix state on purpose; it must not merge ahead of the code fix."
  - "W3 — PA-27 §(b)(ii): co-addressees named on a `To` line were an unnamed data-subject category; now named, with a pointer to (d)."
  - "W4 — PA-27 §(f): Art. 30(1)(f) limb had no entry for the routing table. Added: retained while configured, no purge job, removed by the workspace_members cascade or an operator delete (its Art. 17 path), DSAR-exclusion pointer, and that `recipients` in the event store follows the existing no-automatic-deletion limb (#5150)."
conditions:
  - "C1 — Public-surface lockstep (open). Privacy Policy §4.13, GDPR Policy §3.10 and DPD §2.3(aa) say 'Subject and sender values additionally persist' in the self-hosted Inngest store and that they are scrubbed from monitoring sinks. Recipient addresses (including co-addressees) now persist there too. Either extend the three documents (canonical + Eleventy mirror, re-pin legal-doc-shas.ts) in this PR, or file a tracked issue and cite it from the PA-27 Active Items row before merge. Not done."
  - "C2 — Event-store retention (open, pre-existing, now wider). The self-hosted Inngest store has no automatic deletion (#5150). `recipients` inherits that gap; the gap's content is now wider by third-party addresses. Closing #5150 is the minimization fix; until then Art. 5(1)(e) rests on the existing accepted-residual posture at single-operator scale."
  - "C3 — Non-operator routes (open, by design). Before any non-operator route exists (#9459): remove the DSAR exclusion for `email_inbox_routes` and move it to the allowlist, replace the operator fallback with quarantine, re-run this review, and run the full DPIA the ADR already names (screening triggers 1 and 2 of the 2026-06-11 memo)."
re_evaluation_triggers: "First non-operator route (#9459) OR first arms-length user whose address could be a route key OR any widening of `recipients` (cc/bcc, higher cap) OR EEA-out data subject OR regulated-industry user — plus a scope change to anything the summarizer or notification path receives."
---

# Counsel review audit — #9458 (inbound email routing table + `recipients`)

This is the v1 internal counsel-review attestation for PR #9456, a `single-user incident` PR that amends `knowledge-base/legal/article-30-register.md` PA-27. The attestation authority is the CLO agent (Soleur-as-tenant-zero v1); the operator keeps an optional veto; external counsel is reserved for the re-evaluation triggers in the frontmatter. Output is draft material.

**Method.** Each register claim was checked against the implementing artifact, not against the plan: `apps/web-platform/supabase/migrations/155_email_inbox_routes.sql`, `server/dsar-export-allowlist.ts`, `server/email-triage/events.ts`, `app/api/webhooks/resend-inbound/route.ts`, `server/email-triage/resolve-inbound-route.ts`, `server/inngest/functions/email-on-received.ts`, `server/sensitive-keys.ts`, `server/sentry-scrub.ts`, `server/inngest/middleware/sentry-correlation.ts`, and ADR-269. Code is cited by function or constant name, not by line.

## Artifact 1 — Article 30 register, PA-27 (c) routing-table limb and (d) event-store limb

**File:** `knowledge-base/legal/article-30-register.md`

| Claim in the diff | Checked against | Verdict |
|---|---|---|
| Columns exhaustively `id`, `address`, `workspace_id`, `owner_user_id`, `created_at` | `CREATE TABLE email_inbox_routes` has exactly those five | TRUE |
| Composite FK to `workspace_members`, ON DELETE CASCADE | `email_inbox_routes_owner_member_fk` | TRUE |
| Service-role only (RLS on, no policies) | `ENABLE ROW LEVEL SECURITY`, no policy, `REVOKE ALL ... FROM PUBLIC, anon, authenticated` | TRUE |
| Ships empty | no INSERT in the migration | TRUE |
| `address` is an operator-owned mailbox, never a correspondent's | Not enforceable in schema (the CHECK is shape-only); enforced behaviourally: `resolveInboundRoute` honours only the operator pair, and ADR-269 defers agent/user mailboxes to #9459 | TRUE as a statement about today's rows; a design claim, not a constraint. Covered by C3 |
| 'Holds no correspondent data and no message content' | Table holds a mailbox address, two uuids, a timestamp. `owner_user_id` is the operator's user id, a category already present as `email_triage_items.user_id` | TRUE; adds no new category |
| `recipients` normalized: lowercased, display names stripped | `normalizeInboundAddress` (angle-bracket extraction, lowercase, strict regex, 320-char cap) | TRUE |
| `recipients` content | `buildRecipients(data?.received_for, data?.to)`: envelope first, `To` second, deduped, sorted, at most `MAX_INBOUND_RECIPIENTS` = 20 valid addresses. `cc` and `bcc` are not read | TRUE after W1 (the diff did not say cc/bcc are excluded or give the cap) |
| `recipients` carries third-party To addresses into the Inngest store | A mail whose `To` names several people yields all of them in the event; the event is persisted by the self-hosted store | TRUE and sufficiently stated after W1 |
| `recipients` required by statutory checking | The prior parenthetical said 'requires them in the event'. Statutory checking uses `subject`, `sender`, attachment names. `recipients` is consumed only by `resolveInboundRoute` inside `claim-insert` | FALSE as written; corrected (W1) |
| Sentry/Better Stack are not recipients of content because `SENSITIVE_KEY_NAMES` scrubs event-data extras | `SENSITIVE_KEY_NAMES` holds `subject`, `sender`, `from`, `to`, `attachments`, `filename`, `email`, `recipient`; it does not hold `recipients`. The scrubber matches key names only (`SENSITIVE_LOWER.has(key.toLowerCase())`), so `recipients` is not redacted. `sentry-correlation.ts` attaches `ctx.event.data` as `inngest.event_data` on captured pipeline errors | FALSE for the new field. **B1** |
| `recipients` does not reach Anthropic, Resend or notifications | Only reference to `data.recipients` in `email-on-received.ts` is the call to `resolveInboundRoute`. The route-degraded Sentry report carries `reason` and a pg code only | TRUE |

**Disposition for this artifact:** BLOCKED on B1 only. W1-W4 are applied in-cell.

**B1 fix (one line plus a test).** Add `"recipients"` to `SENSITIVE_KEY_NAMES` in `apps/web-platform/server/sensitive-keys.ts` (this also extends pino's derived `REDACT_PATHS`), and add a case to `test/sentry-scrub.test.ts` asserting that `{ recipients: ["a@b.example"] }` under an `inngest.event_data`-shaped extra is redacted. The register cell is already written to that post-fix state. Closing B1 does not need a second legal rewrite; it needs a re-check that the key is in the list.

## Artifact 2 — Lawful basis and retention (Art. 6(1)(f), Art. 5(1)(e))

**Lawful basis.** Reusing PA-27's Art. 6(1)(f) LIA (`2026-06-11-operator-inbox-triage-lia.md`) is adequate for the routing table and for `recipients`. The table is operator service configuration with no correspondent data, so it needs no independent basis. `recipients` is metadata of mail the LIA already covers, used for a purpose (finding the owner of the mailbox the mail was sent to) that is necessary to claim mail under the right owner and is within the original purpose. The migration's `LAWFUL_BASIS` comment points at PA-27 and matches. **Verdict: adequate.**

**Art. 13/14.** Co-addressees are involuntary data subjects of the same kind as inbound senders: Art. 14(5)(b) disproportionate-effort, public notice via Privacy Policy §4.13. They were not a named category in PA-27 (b); named now (W3). The public notice does not yet say recipient addresses persist in the event store (C1).

**Retention.** The register had no limb for the table (Art. 30(1)(f)); added (W4). For `recipients` in the event store, retention is the existing 'no automatic deletion' limb (#5150). That is a pre-existing named gap, not a new one, but it now holds third-party addresses (C2). **Verdict: adequate with named gap C2.**

**Art. 5(1)(c) minimization.** Acceptable. The event carries only `To` and envelope addresses (not cc/bcc), capped at 20, normalized with display names stripped; storing the full address list is needed because the routing match happens after the event is emitted. Any widening (cc/bcc, higher cap) is a re-evaluation trigger.

## Artifact 3 — Art. 17 handling and the DSAR exclusion (`server/dsar-export-allowlist.ts`)

- **Erasure.** The composite FK is `ON DELETE CASCADE` from `workspace_members`, and account deletion removes the member row, so a route cannot block Art. 17 and is deleted with the member. This is the right choice for configuration that is not statutory evidence. The migration, ADR-269 and the register agree. The consequence (a deleted route re-routes that address to the operator) is stated in the migration, the ADR and now the register, and is a hard #9459 precondition. **Adequate.**
- **DSAR exclusion wording.** The reason text states what the table is, that only operator rows are honoured, that it ships empty, and that `owner_user_id` is a user identifier and a per-user address could derive from a personal name; it says to revisit and remove the exclusion before any non-operator route is enabled. Today the only user identifier is the operator's, who has the data through the application, so the exclusion does not impair an Art. 15 right in practice. The wording is accurate and carries its own removal trigger. **Adequate; the trigger is carried into C3.**

## Artifact 4 — Chapter V (Arts. 44-49) and Art. 9

- **Chapter V.** No new transfer. The routing table sits in Supabase (EU). `recipients` sits in the self-hosted Inngest store on Hetzner (EU). `recipients` is not part of the Anthropic call (subject, sender, truncated sanitized body only) and not part of any Resend call. The existing PA-27 (e) transfers are unchanged. **No finding.**
- **Art. 9.** Not engaged by the new surfaces: a mailbox address and two uuids, and normalized recipient addresses. Incidental revealing power of a third party's address (a clinic or union domain) is not special-category processing by this pipeline, which performs no inference on it. The pre-existing Art. 9 residual in PA-27 (summary) is untouched. **N/A.**

## Artifact 5 — ADR-269 cross-check

ADR-269 matches the code on every implementation claim checked: normalized addresses only in the event; `received_for` first then `To`; cap of 20 valid addresses; resolution inside `claim-insert` with `ownerId` carried in the step return; operator-pair-only honouring; degrade-to-operator on lookup error or refused route, reporting reason and pg code only; the table ships empty. The ADR records the third-party-address consequence ('noted against PA-27') and the #9459 preconditions, including a DPIA and a Resend DPA before any per-user custody. It does not mention the Sentry scrub of `recipients`; that gap is B1.

## Overall

| Artifact | Verdict |
|---|---|
| PA-27 (c)/(d) prose (table limb, `recipients`) | Accurate after W1-W3; Sentry sentence true only after B1 |
| Lawful basis / retention / Art. 13-14 | Adequate; gaps C1, C2 named |
| Art. 17 + DSAR exclusion | Adequate; C3 |
| Chapter V / Art. 9 | No finding / N/A |
| ADR-269 | Consistent with the code |

**Disposition: BLOCKED** on B1. To discharge: add `recipients` to `SENSITIVE_KEY_NAMES` with a scrub test, then re-check that the register's Sentry sentence matches the code; the CLO attestation may then be recorded as DISCHARGED without further legal edits, with C1-C3 open as named conditions (C1 must be resolved or issue-tracked before merge).

*Draft material for internal attestation; not legal advice. External counsel re-review follows the frontmatter triggers.*

## Addendum 2026-10-04 — B1 closed, disposition DISCHARGED

B1 was fixed in the same PR: `"recipients"` was added to `SENSITIVE_KEY_NAMES` in `apps/web-platform/server/sensitive-keys.ts` and `test/sentry-scrub.test.ts` gained a case asserting `extra.event_data.recipients` is `[Redacted]` and that a co-addressee address does not survive in the serialized event (suite green). The register's Sentry sentence (PA-27 §(d)) is now true as written. The original BLOCKED disposition above is retained as the record of what the review found; the attestation is recorded as **DISCHARGED**, with C1-C3 open as named conditions tracked in #9459.
