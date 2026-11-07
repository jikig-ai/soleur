---
title: "feat: sign off the founder-acceptance-record text (CLO-agent ruling stands in for counsel)"
date: 2026-11-07
slug: founder-acceptance-record-text-draft-signoff
branch: feat-one-shot-12197-founder-acceptance-record-text-draft
issue: 12197
type: feat
priority: p2
domain: legal
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: planned (sign-off continuation of PR #12342)
---

# feat: sign off the `founder-acceptance-record` text

> **Read this first: what the sign-off is and is not.** The company has no external counsel. On 2026-11-07 the operator ruled that the CLO agent's ruling (`soleur:legal:clo`) stands in for counsel sign-off on this text. That is the ONLY reason an agent ruling closes the "counsel sign-off" item. It is a v1 internal position, not a lawyer's opinion. No human lawyer has read the text, the retention period or the card deck. The residual risks are listed under "Rulings, D" and must be carried into the PR body. The CLO's own words: "It is a v1 internal position and not a lawyer's opinion."

## Overview

Continuation plan for the open DRAFT PR #12342 (Ref #12197, #12011). The first plan, `2026-11-07-feat-founder-acceptance-record-text-draft-plan.md`, produced the held draft. It is history; this plan supersedes its `## HOLD procedure` and splits its `## Operator Holds` (see "Operator Holds, rewritten"). Both plans carry the `branch:` of this worktree; the Phase 0.7 selector tie-break picks this one (it sorts later by name at the same date).

The work phase does, in this order:

1. Apply the CLO's final wording edits (A1 to A8) to the text and fill the retention period (5 years from the date of the decision, extended only while a legal claim, a complaint or an official inquiry about the record is open) in the text, in `LEGAL_COPY.cardNotice` and in `LEGAL_COPY.requestChangesNotice`, and in the counsel note sections (c) and (c-2) that the deck test pins byte for byte.
2. Fix #12344 inside this PR: kind-keyed card copy (`terms` / `acknowledgement`), fail-closed for an undeclared key, label from the text's own first line, the CLO's acknowledgement wording, and the pinned tests.
3. Delete the CI-only merge guard, its real-data control and the retention-clause test; replace them with an always-on unfinished-marker check and a retention single-source test; add the registry-wide `{version: sha256}` pin with the exact key set in `registry-pins.test.ts`; pin the third table's columns.
4. Record the sign-off (append-only addenda, no edit of the blank attestation block), rewrite the holds, then get the FULL CI battery by dispatching `ci.yml` on the branch (not a local full run), and only then mark the PR ready.

Out of scope, stays with #12197 and the founder: the founder's first acceptance, the post-deploy registry smoke, the `approval-queue` flag, the roadmap CP2 wording, any merge or enqueue. Before any flag change the founder checks `select count(*) from public.legal_acceptance;` with their own login: it must be 0.

## Research Reconciliation: spec/brief vs. codebase

| Brief claim | Reality (verified 2026-11-07) | Plan response |
|---|---|---|
| "bump version if the bytes changed after a first merge (it has not merged yet, so likely no bump; verify)" | `git ls-tree origin/main apps/web-platform/server/legal-acceptance/texts/` lists only `.gitattributes` and `README.md`; `git log origin/main -- .../texts/` shows only the PR-B and PR-C commits. Never merged. | No bump. `version: 2026-11-07` stays. The pin's first row is `2026-11-07`. Bump rule starts at the first merge (CTO item 5). |
| "replace the placeholder in the text file AND in `LEGAL_COPY.cardNotice`" | The card notice is also pinned byte for byte to `knowledge-base/legal/audits/2026-11-founder-legal-acceptance-dsar-and-notice-note.md` section (c-2) by `legal-copy.test.ts`; `requestChangesNotice` is pinned to section (c). The test currently also asserts the placeholder is present. | Edit sections (c) and (c-2) of the note in the same commit; replace the placeholder-present assertion. The note is outside `plans/` and `specs/`, so it is a work-phase edit, not a planning-phase edit. |
| "delete the CI-only merge guard, its real-data control and the retention-clause test" | Matches: four `it` blocks in the last describe, plus the registry tripwire. The tripwire message names the deleted guard. | Delete per the CTO verdict table (Item 4); replace as ruled. |
| "add the published `{version: sha256}` pin and the exact key set" | No such file exists. | New `test/legal-acceptance/registry-pins.test.ts` (CTO item 2). |
| "run the full CI battery ... only then mark the PR ready" vs. the earlier CTO ruling "never mark ready to obtain full CI" | `ci.yml` declares `workflow_dispatch`; the `draft-light` job runs only on `pull_request`; every gated job tests `light != 'true'`. A dispatch run on the branch is therefore a full run with no variable change. | Dispatch `ci.yml` on the branch; then ready. Both statements hold (CTO item 3). |
| "#12344 ... fold it into this PR" | #12344 (widened by a comment) lists every card string that presumes terms. The deck is a pure leaf shared by the card, the dialog and two pages. | CTO + CLO rulings below; Closes #12344 only if every row lands (CLO C). |
| CLO scope: "consequential edits" to the register, LIA, ADR-319, published trio | The published Privacy Policy 4.17 / GDPR Policy 3.19 / Data Protection Disclosure still say "no period confirmed (proposal: life plus 5, max 10)". | Records edited in this PR as append-only superseded markers; the published trio is a precondition of the card being answerable beyond the operator and is tracked as its own issue (Scope Check, S5). |

## Research Insights

**Premise validation (Phase 0.6).** Cited items checked: PR #12342 is OPEN and DRAFT; #12197, #12080, #12344 and #12011 are OPEN; no cited blocker is closed. `origin/main` has moved 5 commits (none touch `legal-acceptance`). Collision pre-check: PR #12342 only, plus unrelated `test-all.sh` runs in other worktrees (the memory pressure the brief mentions): no duplicate work.

**Property list and cut list (Phase 0.6b).** Properties: (P1) the text the founder is shown states a concrete retention period, true on the day it ships; (P2) the same period appears on the card; (P3) no unfinished marker can reach main; (P4) a later byte change to a published text cannot pass without a version bump; (P5) the card never claims "terms accepted" for an acknowledgement text and never renders a card for a text with no declared meaning; (P6) full CI is green on the exact head before the PR is marked ready. Cuts: (a) a `meaning:` front-matter line (Option B) buys P5 but changes the hashed bytes and the loader for a presentation concern; the leaf map buys the same property (CTO). (b) A base-ref `git show` check for "bytes changed => version changed" buys P4 but is flaky on shallow and merge-queue checkouts; the append-only pin history plus a review rule covers it (CTO). (c) Flipping the `approval-queue` flag and filling the attestation sign-off cells: not needed for any property.

**Value-proposition measurement (0.6c).** The only cost claim is "avoid a second full CI run": not measured, and not relied on: the operator's order outweighs it (CTO dissent recorded).

**Institutional learnings applied** (from the learnings researcher):
- `2026-11-07-a-guard-for-a-held-legal-text-detects-the-draft-state-not-the-signoff.md`: the deleted guard never proved sign-off; the hold was the PR state and the operator. After deletion the DRAFT state no longer protects the text, so the merge hold stays Operator-reserved.
- `2026-08-02-the-retraction-pr-was-itself-over-claiming-and-its-counsel-signoff-certified-a-diff-that-no-longer-existed.md`: a sign-off is evidence about one byte state. The ruling record pins the text sha256; after any later edit or rebase the ruling is re-verified, not assumed. Merge `origin/main` (never rebase: review-evidence trailers sit on the commits).
- `2026-10-09-an-amendment-cited-a-chat-direction-as-the-approval-the-next-paragraph-said-it-was-not.md`: word the CLO ruling as a stand-in with human-lawyer review still owed; no status row may say the text "may now ship to customers".
- `2026-10-29-a-ruling-cited-from-a-task-brief-is-not-on-the-issue-...md`: cite a ruling only where it is persisted. Persist the CLO ruling as an audit file and quote the CTO rulings in `decision-challenges.md`.
- `2026-05-25-pr1-of-sequenced-legal-disclosures-needs-temporal-qualifiers.md` and `2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md`: a period stated in user-facing copy needs the enforcing code or an honest temporal qualifier. The CLO's A4 sentence does exactly that ("has not yet built the step that deletes ..."); #12080 is the hard stop.
- `2026-10-12-docs-only-ci-skip-premise-is-false-when-tests-read-the-kb.md`: tests here read the KB (the counsel note); a docs-only skip would be wrong. Use the dispatch run, no path filters, no synthetic statuses (ADR-276).
- `2026-11-06-a-guard-on-the-registrar-result-is-not-a-guard-on-the-published-set-...md`: the pin must assert the published set as the loader serves it AND via an independent read of the bytes.

## Rulings (verbatim)

The rulings below are the authority for the work phase. Where a CLO string and a CTO string disagree, the CLO owns wording and the CTO owns mechanism. Strings are ASCII.

### Standing

Operator ruling, 2026-11-07 (quoted from the brief): "the company has no external counsel, so the CLO agent's ruling (soleur:legal:clo) stands in for counsel sign-off." Recorded in the PR as `Ruled by CLO agent, 2026-11-07`.

### CLO agent, A: final wording of `founder-acceptance-record.md`

Apply each edit as exact OLD to exact NEW. Each OLD must match exactly once before and each NEW exactly once after.

**A1. Acknowledgement sentence.**
- OLD: `Saying Yes here records that you acknowledge this description.`
- NEW: `Saying Yes here records that you were shown this description and that you acknowledge it. It is not consent and it does not affect your rights: Jikigai keeps the record on the grounds stated under How long it is kept, whatever you answer.`

**A2. Legal basis.**
- OLD: `Jikigai relies on its legitimate interest (Article 6(1)(f) GDPR) in being able to show later what was decided; Article 17(3)(e) GDPR lets it keep data that may be needed for legal claims.`
- NEW: `Jikigai relies on its legitimate interest (Article 6(1)(f) GDPR) in being able to show later what was decided. Jikigai considers that it may need the record to establish, exercise or defend a legal claim, and keeps it after an erasure request on that ground (Article 17(3)(e) GDPR).`

**A3. Account identifier.**
- OLD: `The account identifier is not anonymous: someone who holds other Jikigai records could link it to you, so Jikigai treats it as personal data.`
- NEW: `The account identifier is pseudonymous, not anonymous: someone who holds other Jikigai records could link it to you. It is personal data, and Jikigai handles it as such.`

**A4. Retention.**
- OLD: `How long the record is kept: [period to be confirmed by counsel].`
- NEW: `How long the record is kept: 5 years from the date of the decision, and then Jikigai deletes it. This covers the whole record, including any note and the marker described above. If a legal claim, a complaint or an official inquiry about the record is open when the 5 years end, Jikigai keeps it until that matter is closed. Jikigai has not yet built the step that deletes a record at the end of this period; it will build it before any record reaches that age, and until then records are kept as they are. Copies in database backups may last for a further period that Jikigai has not measured.`
- When #12080 ships, the "has not yet built" sentence comes out in a new `version`.

**A5. Code-request records (name them).** Insert this paragraph immediately after the paragraph beginning `The record also holds fixed technical labels`:
`Each decision also uses a short-lived request record, kept apart from the decision record. It holds your account identifier, the name, version and fingerprint of the text, the identifier of the sign-in session, the number of attempts, and the times of the request. It never holds the code. Jikigai deletes request records older than 30 days when the next request for a decision is made, so one can last longer than 30 days. A request record is not deleted when you delete your account, and it is not covered by the 5 years above.`

**A6. Ack marker.**
- OLD: `A separate marker, linked to the record's identifier, may note when the web service reported the decision to Jikigai's monitoring; it can be missing.`
- NEW: `A separate marker, linked to the record's identifier, may note the time the web service reported the decision to Jikigai's monitoring; it can be missing. Because it can be linked to your record, it is personal data too, and it is kept and deleted together with the record.`

**A7. Note statement.**
- OLD: `If you choose Request changes, the note is saved with your decision and kept even if you later delete your account.`
- NEW: `If you choose Request changes, the note is saved with your decision and kept for as long as the decision record is kept (5 years from the date of the decision, see How long it is kept), even if you later delete your account. It cannot be removed on its own: it is deleted together with the record.`

**A8. Rights.**
- OLD: `You can ask what Jikigai holds, or object, by writing to <legal@jikigai.com> (Articles 15 and 21 GDPR), and you can complain to the CNIL.`
- NEW: `You can ask what Jikigai holds, ask for erasure or restriction, or object, by writing to <legal@jikigai.com> (Articles 15, 17, 18 and 21 GDPR), and you can complain to the CNIL. Jikigai decides each request or objection case by case and tells you its decision; the record is kept where it is needed for a legal claim, and a note cannot be removed from it on its own.`

No change: the first paragraph apart from A1, the stored-fields list, "How a decision is given", "Who can read it", the checksum paragraph.

Ruled by CLO agent, 2026-11-07: Edits A1 to A8 are the final wording of founder-acceptance-record.md. The text may state the 5-year period as a commitment together with the plain statement that the deletion step is not yet built. The Art. 6(1)(f) and Art. 17(3)(e) framing is adopted as Jikigai's v1 position for the operator-first stage only, and it is not a counsel review.

Effects the CLO named: the LIA keeps `status: draft-requires-counsel-review` (record the ruling in an addendum, do not edit the status); the A5 paragraph makes the text describe `legal_reauth_event`, so that table's columns get a pin (CTO 4b).

### CLO agent, B: the concrete retention period (#12080 question)

Ruled by CLO agent, 2026-11-07: The retention period for the decision record and for the Request-changes note is 5 years from the date of the decision, extended only while a legal claim, a complaint or an official inquiry about the record is open. The start event is the decision date, not the life of the text. The card notice and the Request-changes notice carry that period word for word.

Stated basis (the CLO's, to be carried into the audit record): Code civil art. 2224 (5-year general limitation; the repo's own Art. 30 register applies it in the `tc_acceptances` row and the `workspace_member_removals` row; it also covers Art. 82 GDPR claims per that register row). It is the lowest period with a legal anchor, meets Art. 5(1)(e), and a numeric period beats a "criteria" statement under Art. 13(2)(a). The hold covers interruption of limitation by a pending claim. Rejected: 10 years (L123-22, accounting documents; Art. 17(3)(b) is not claimed here), 7 years (the `tc_acceptances` precedent is B2B commercial terms), 20 years (art. 2232 is an outer limit, not a need), anything under 5 (below the limitation period). Fixed-from-decision start was chosen over a variable start because registry texts have no `valid_until`, the database has no text lifecycle, and `created_at` is the row's own column. The note gets the same period because it cannot be separated from the row today (checksum, write-once guard).

Exact strings:
- Text body phrase: `5 years from the date of the decision`.
- Card notice: replace `[period to be confirmed by counsel]` with `5 years from the date of the decision (longer only while a legal claim, a complaint or an official inquiry about it is open)`. The sentence then reads: "Jikigai keeps this record to be able to show later what was decided, even if you delete your account, for 5 years from the date of the decision (longer only while a legal claim, a complaint or an official inquiry about it is open)."
- Request-changes notice: ending `...up to 1000 characters, and is kept even if you later delete your account.` becomes `...up to 1000 characters, and is kept for 5 years from the date of the decision, even if you later delete your account.`

Trigger restated for #12080: build the deletion path before the first non-Jikigai founder, or before any row is 4 years old (12 months before the 5-year date); note redaction is no longer separate because the note is deleted with the row; the request-record purge on erasure and the ack-row deletion stay in scope.

Consequential records (edit in place with `> **Superseded 2026-11-07 (#12197; fires on the merge of the pull request that carries it): ...**` markers, append-only): PA-40 (f) and register item 17(a); LIA "Retention proposal" and its counsel item 1; attestation section 2 ("retention lawful"); DSAR note (b) ("For how long" and the code-request bracket) and sections (c), (c-2); ADR-319 retention paragraphs (as a dated amendment); the compliance-posture row. Do not edit migration 184/185 comments. Source check on citations: art. 2224, L123-22 and the 7-year precedent were verified in the repo's own records; art. 2232, L110-4 and CNIL archiving guidance are from the CLO's memory and flagged unverified.

### CLO agent, C: card deck wording (#12344)

Two deck-owned wordings selected by a declared kind. A single neutral wording for all texts is not acceptable (CLO). Heading for both kinds: `exactTextHeading` becomes `The exact text your answer covers` (the old heading overstates: only the sha256 is stored, never the text; ADR-319 property 4).

| Field (current `LEGAL_COPY` path) | terms kind | acknowledgement kind |
|---|---|---|
| `pending.title(label)` | `Accept the updated ${label}?` | `Acknowledge "${label}"?` |
| `yesRow.body` | `Soleur treats these terms as accepted by you, starting today. Clicking again does not undo it. To change it later you would ask for a new version.` | `Your Yes is recorded as your acknowledgement of this text. It does not accept any terms and it is not consent. Clicking again does not undo it. To change it later you would ask for a new version.` |
| `noRow.body` | `Nothing changes. The current terms stay in place.` | `Your No is recorded as your answer. The text stays as it is and nothing is acknowledged.` |
| `changesRow.body` | `Your note is saved with your decision. Nothing is accepted by asking for changes.` | `Your note is saved with your decision. Nothing is acknowledged by asking for changes.` |
| `changes.footer` | `Nothing is accepted by saving this. Your note is saved with your decision.` | `Nothing is acknowledged by saving this. Your note is saved with your decision.` |
| `pending.nothingAccepted` | `Nothing has been accepted.` | `Nothing has been acknowledged.` |
| `pending.notAvailable` | `Answering is not available yet. Nothing has been accepted.` | `Answering is not available yet. Nothing has been acknowledged.` |
| `accepted.badge` | `Accepted` | `Acknowledged` |
| `accepted.title(label)` | `You accepted the updated ${label}` | `You acknowledged "${label}"` |
| `accepted.body` | `Soleur now treats this version as accepted by you. To change this later, ask for a new version.` | `Your Yes is recorded as your acknowledgement of this version. It does not accept any terms. To change this later, ask for a new version.` |
| `declined.title(label)` | `You said No to the updated ${label}` | `You said No to "${label}"` |
| `declined.body` | `Nothing changed. The current terms stay in place. This answer is final: to change it, your team sends a new version of the text.` | `Nothing changed. Your No is recorded and the text stays as it is. This answer is final: to change it, your team sends a new version of the text.` |
| `changesRequested.body` | `Nothing is accepted. Your note is saved with your decision. This answer is final: to change it, your team sends a new version of the text.` | `Nothing is acknowledged. Your note is saved with your decision. This answer is final: to change it, your team sends a new version of the text.` |
| `expired.body` | `Nothing was accepted. Ask your team to send it again if you still want it.` | `Nothing was acknowledged. Ask your team to send it again if you still want it.` |
| `dialog.answerDetail(label, version)` | `` `Accept the updated ${label}, version ${version}. Nothing is recorded until your code is checked.` `` | `` `Acknowledge "${label}", version ${version}. Nothing is recorded until your code is checked.` `` |
| `index.state.accepted` | `You accepted it` | `You acknowledged it` |

Shared change, both kinds (follow-up ruling): `dialog.codeBody` becomes `The code works for a few minutes. Nothing is recorded until your code is checked.` ("accepted" about a code is ambiguous next to accepted terms; "verified" is on the forbidden list; an exact-string allowlist is NOT permitted.) The terms-kind `answerDetail` tail changes from "accepted" to "checked", the one deliberate deviation from "today's wording byte for byte".

Neutral, no change: `choices.*`, `decline.*`, `replaced.*`, `finalNote`, `page.*`.

Quotes: straight ASCII double quotes around the full first-line title are fine. Test requirement: the first line of an acknowledgement text contains no double quote and no newline.

Ruled by CLO agent, 2026-11-07: The deck takes two deck-owned wordings, terms and acknowledgement, selected by a declared type with no default. The heading `The exact text your answer covers` replaces `The exact text that will be recorded` for both types. A single neutral wording for all texts is not acceptable. #12344 is closable by the PR that carries every row of the table, the selection and the pinned tests.

Ruled by CLO agent, 2026-11-07: `dialog.codeBody` is "The code works for a few minutes. Nothing is recorded until your code is checked." The code sentence in `dialog.answerDetail` ends "Nothing is recorded until your code is checked." in both kinds. No exact-string allowlist is permitted, and quoted full-title labels in the acknowledgement titles are acceptable.

Left open by the CLO (tracked, not fixed here): the terms variant still says "the updated" for a first-ever terms text (fix before the first terms-type text is published); the CPO's deck sign-off is outstanding; `PROVISIONAL` stays true.

### CLO agent, D: sign-off hygiene

- `LEGAL_COPY.signOff.clo` becomes exactly `Ruled by CLO agent, 2026-11-07: v1 internal sign-off, not external counsel` in the same commit as the wording. `signOff.cpo` stays `null`. `PROVISIONAL` stays `true` (no human lawyer; CPO sign-off outstanding; the flag is global; first-real-row and non-Jikigai-founder conditions open). `legal-copy.test.ts` pins `signOff` to `{ cpo: null, clo: "<that string>" }` and `PROVISIONAL` to `true`. The string must pass `FORBIDDEN_CLAIMS` (the deck walker collects it).
- Deck header comment: no longer says the retention placeholder stays until counsel confirms; says the period is the CLO-agent v1 ruling of 2026-11-07 and cites the persisted ruling file.
- Attestation record section 6 (counsel sign-off block): every cell stays blank. The block is for counsel; filling it with an agent would contradict `status: DRAFTED, NOT COUNSEL-REVIEWED`. Add a dated append-only addendum below it, conditioned on the carrying PR's merge, that records the operator's no-external-counsel ruling, the register items the ruling closes as v1 positions (17(a), 17(b) operator-first, 17(c) note, 17(f) 30-day value), and that 17(d), 17(e), 17(g) and the final-form trio stay expressly deferred (that deferral is the operator's act under Condition 3 of the 2026-11-04 audit, not the CLO's). Add a frontmatter pointer key; the re-evaluation trigger "retention period confirmed or changed" has fired and is recorded there.
- Persist the ruling as `knowledge-base/legal/audits/2026-11-07-clo-ruling-founder-acceptance-record-12197.md`; add a pointer addendum to `2026-11-counsel-review-12011.md`; LIA and PA-40 addenda with in-cell superseded markers. Cite code by function or constant name, never by line number.

Residual risk of an agent standing in for counsel (the CLO's 8 points, carried into the PR body):
1. Whether Art. 17(3)(e) covers keeping a record for a foreseeable but not pending claim is contestable; a human or the CNIL might prefer anonymising the founder id on erasure while keeping hash, choice and time.
2. The limitation reasoning rests on the repo register plus recall of art. 2232 and L110-4; not checked against Legifrance; suspension and interruption not reviewed.
3. Evidential weight in a French court (Code civil art. 1366 and 1367, eIDAS) is unassessed; a click plus an email code is not a qualified signature. Needs a human before any terms-type text.
4. Art. 13 sufficiency and the Art. 21(4) separate presentation were tested with no reader other than the drafter; the operator is the only data subject, so Art. 13(4) is the fallback and it fails for any other founder.
5. Matching a bare uuid to a requester after account deletion (Art. 11, 12(6)) is unresolved.
6. The 5 years is a commitment, not a control. If #12080 is not built, Art. 5(1)(e) and the notice are both breached. Backup retention is unmeasured. The note may carry third-party personal data (Art. 14 disproportionate-effort position).
7. The published Privacy Policy, GDPR Policy and Data Protection Disclosure still carry the old proposal and draft markers until the trio is updated; a human must review the final-form trio before any non-Jikigai founder.
8. The operator is both a controller principal and the only data subject. Nothing here is reached for a customer founder.

Ruled by CLO agent, 2026-11-07: Set `LEGAL_COPY.signOff.clo` to exactly "Ruled by CLO agent, 2026-11-07: v1 internal sign-off, not external counsel" in the same commit as the final wording. Leave `signOff.cpo` null and `PROVISIONAL` true. Leave the attestation sign-off block blank, and record the ruling in dated addenda. Founder acceptance, the approval-queue flag and production changes remain operator-reserved, and I do not rule on them.

### CTO agent, 1: card-copy mechanism (#12344)

Ruled by CTO agent, 2026-11-07: Option A (key-keyed map in the pure leaf `apps/web-platform/lib/legal-acceptance-copy.ts`), not Option B (a `meaning:` front-matter line: front matter is inside the hashed bytes, the loader reads only `^([a-z_]+):` lines so an unknown line would be silently ignored today, and every cosmetic deck change would force a text version bump) and not Option C (weakens the Yes row for real terms texts).

Ruled by CTO agent, 2026-11-07 (follow-up, supersedes the earlier "default = acknowledgement" so that it meets the CLO's "no default"): no default kind. `legalTextKind(key, declared)` and `legalKindCopy(key, declared)` return `null` for an undeclared key (own-property lookup via `Object.prototype.hasOwnProperty.call`; `"constructor"` and `"__proto__"` pass `KEY_RE` and must give `null`). An undeclared key never renders a card. The refusal sits in the render path, not in `canonical.ts`, so a presentation fault cannot take the registry or the verify and decide routes down.

Export shape (no imports in the leaf):

```ts
export const LEGAL_TEXT_KINDS = ["terms", "acknowledgement"] as const;
export type LegalTextKind = (typeof LEGAL_TEXT_KINDS)[number];
export interface LegalKindCopy {
  pendingTitle(label: string): string;      // pending.title
  yesBody: string;                          // yesRow.body
  noBody: string;                           // noRow.body
  changesBody: string;                      // changesRow.body
  changesFooter: string;                    // changes.footer
  pendingNothing: string;                   // pending.nothingAccepted
  pendingNotAvailable: string;              // pending.notAvailable
  acceptedBadge: string;                    // accepted.badge
  acceptedTitle(label: string): string;     // accepted.title
  acceptedBody: string;                     // accepted.body
  declinedTitle(label: string): string;     // declined.title
  declinedBody: string;                     // declined.body
  changesRequestedBody: string;             // changesRequested.body
  expiredBody: string;                      // expired.body
  answerDetail(label: string, version: string): string; // dialog.answerDetail
  indexAccepted: string;                    // index.state.accepted
}
export const LEGAL_KIND_COPY = { terms: { /* today's strings, moved */ }, acknowledgement: { /* CLO strings */ } } as const satisfies Record<LegalTextKind, LegalKindCopy>;
export const LEGAL_TEXT_KIND: Readonly<Record<string, LegalTextKind>> = { "founder-acceptance-record": "acknowledgement" };
export function legalTextKind(key: string, declared = LEGAL_TEXT_KIND): LegalTextKind | null;
export function legalKindCopy(key: string, declared = LEGAL_TEXT_KIND): LegalKindCopy | null; // a member of LEGAL_KIND_COPY, never a new object
export function legalIndexState(key: string, state: LegalCardStateWire): string;
export function legalDisplayLabel(key: string, body: string, kind: LegalTextKind): string;
```

Delete from `LEGAL_COPY` the 16 moved members (so `tsc` finds every unmigrated consumer): `yesRow.body`, `noRow.body`, `changesRow.body`, `changes.footer`, `pending.{title,nothingAccepted,notAvailable}`, `accepted.{badge,title,body}`, `declined.{title,body}`, `changesRequested.body`, `expired.body`, `dialog.answerDetail`, `index.state.accepted`. `yesRow.label`, `noRow.label`, `declined.badge` and the rest stay. `exactTextHeading` stays shared with the new string.

Label (follow-up ruling): `legalDisplayLabel` for `acknowledgement` returns the first non-empty body line, trimmed, if 1 to 120 characters, else `legalTextLabel(key)`; for `terms` it returns `legalTextLabel(key)` (pinned wording unchanged). Derived server-side (both pages already hold the entry body) and passed as a required `label` prop on `LegalAcceptanceCard`; the card stops calling `legalTextLabel`. The "replaced" cards (empty body) get the current entry's label, computed once. Anchor test: the real text gives `How your decisions are recorded and kept`; mutation row: change the text's first line, anchor and pin go red.

Consumers:
- `apps/web-platform/app/(dashboard)/dashboard/approvals/legal/[key]/page.tsx`: if `legalKindCopy(key)` is null, `reportLegalOp("pageReadFailed", null, {extra:{read:"legal_kind_undeclared"}})` then `notFound()`; compute the label and pass it.
- `.../legal/page.tsx` (index): filter out undeclared keys before building items, mirror to Sentry; use `legalIndexState(i.key, i.state)` and `legalDisplayLabel`.
- `components/approvals/legal-acceptance-card.tsx`: `const kc = legalKindCopy(keyName)`; return `null` after the hooks if null (no on-card string). Replace the uses of the 16 moved strings and the `[yesRow, noRow, changesRow]` row builder.
- `components/approvals/legal-reauth-dialog.tsx`: new required prop `answerDetail: string` resolved by the card; the dialog does no kind lookup.
- `lib/legal-acceptance-client.ts` and the rest of the `[key]` page: neutral strings only.
- Residual (state in the PR body): the decide and verify routes still accept any registered key by direct API call. That is not a card. The CI declaration test (below) is what stops an undeclared key reaching prod.

Tests (wording-agnostic where possible):
- `legal-copy.test.ts`: extend `collect()` probes with `["founder-acceptance-record"]`, `["unknown-key"]`, `["constructor"]`; assert `Object.keys(LEGAL_KIND_COPY)` equals `LEGAL_TEXT_KINDS` as a set; each kind yields more than 8 strings and every one is in `all`; for declared keys `legalKindCopy(k)` is `toBe` a member of `Object.values(LEGAL_KIND_COPY)` (identity, so an inline-built variant fails); unknown, `"zzz"`, `"constructor"`, `"__proto__"` give `toBeNull`; one ban `/\bterms?\b|\baccept(ed|s|ance)?\b|accept the|\bupdated\b/i` applies to the ack variant and to the shared deck (`collect(LEGAL_COPY)` has more than 40 strings and none match), with the two deliberate negations in the ack `yesBody`/`acceptedBody` ("It does not accept any terms") as the only exact exceptions, each pinned; the terms variant matches `/terms/` (non-vacuity); forbidden-claims, em dash and notice tests keep walking `all` (now including both variants); `cardNotice` and `requestChangesNotice` still equal the note's blockquotes byte for byte, no placeholder; `signOff`/`PROVISIONAL` pins per CLO D; the first line of an acknowledgement text has no double quote and no newline.
- `card.test.tsx`, `page.test.tsx`: `customer-terms` and `other-terms` are now undeclared; wrap with `vi.mock("@/lib/legal-acceptance-copy")` using `importActual` and `declared = {"customer-terms":"terms","other-terms":"terms"}`; use `const KC = legalKindCopy("customer-terms")` instead of literal strings; add an index assertion that an accepted row shows `legalKindCopy(key).indexAccepted`.
- New card test file for the real key `founder-acceptance-record` with a body without "terms": assert `container.textContent` matches none of `/\bterms?\b|accepted by you|Accept the updated/i`, again after opening the dialog (the open-dialog DOM control covers `codeBody`).
- New `card-kind.test.tsx`: terms wording renders for a declared terms key.

Mutation rows (each must turn red, then be reverted): M1 default becomes `terms` or a lookup returns non-null for unknown/`constructor`/`__proto__`; M2 drop `hasOwnProperty`; M3 remove `founder-acceptance-record` from `LEGAL_TEXT_KIND` (three-way key-set equality in `registry-pins.test.ts` reds); M4 put "these terms" into the ack variant; M5 put "verified" into the ack-only `acceptedBody` (proves variants are walked); M6 add a third entry to `LEGAL_KIND_COPY`; M7 hard-code "Accept the updated" in the dialog; M8 print `LEGAL_COPY.index.state.accepted` on the index; M9 add a terms-presuming string to the shared deck; M10 `[key]` page with an undeclared registry key must reject with NotFound and mirror to Sentry (skip the check, red); M11 index omits an undeclared key (drop the filter, red); M12 the card with an undeclared key renders `textContent === ""` (remove the null return, red).

### CTO agent, 2: published pin and exact key set

Ruled by CTO agent, 2026-11-07: one registry-wide test file `apps/web-platform/test/legal-acceptance/registry-pins.test.ts`, app-local so it runs in the gated project:

```ts
const PUBLISHED = {
  "founder-acceptance-record": { kind: "acknowledgement", versions: { "2026-11-07": "<64 hex, from sha256sum of the final bytes>" } },
} as const;
```

`versions` is an append-only history. Key set by three-way set equality: `[...loadLegalTexts().keys()].sort()` equals `Object.keys(PUBLISHED).sort()` equals `Object.keys(LEGAL_TEXT_KIND).sort()`, non-empty, messages naming which of the three to update. Per key: (1) `entry.version` equals the maximum pinned version (ISO strings compared as strings); (2) `entry.textHash` equals `versions[entry.version]`; (3) an independent `createHash("sha256").update(readFileSync(file)).digest("hex")` equals the same pin (no child process; `registry-embedding.test.ts` already proves loader to `sha256sum` parity); (4) pinned shas match `/^[0-9a-f]{64}$/` and are unique across versions (catches a bump with no byte change); (5) `LEGAL_TEXT_KIND[key]` own property equals the pinned `kind`. A pure `checkPins(entries, pins, declared) => string[]` runs the real data (expects `[]`) and synthetic control rows: changed bytes with the same version, an unpinned new key, a pinned key whose file is missing, a lower version than the maximum, a duplicate sha, an undeclared kind. Mutation rows: flip one byte in the text; add `texts/zz.md`; delete the `LEGAL_TEXT_KIND` entry; change the pinned `kind`. No base-ref `git show` check (flaky on shallow and merge_group checkouts; the hash, not the version label, is the authority because of `UNIQUE (founder_id, key, text_hash)`; the append-only shape makes an in-place edit visible in the diff). The rule goes in `texts/README.md`: after the first merge to main a changed byte comes with a new version and a new appended row; editing an existing row's sha is rejected in review. If that is judged insufficient, upgrade to a base-SHA CI guard modelled on `tc-document-sha-guard`; if declined now, file a deferral issue with trigger "second text added" per `wg-when-deferring-a-capability-create-a`.

### CTO agent, 3: CI sequencing and holds

Ruled by CTO agent, 2026-11-07: get the full battery before "ready" by dispatching `ci.yml` on the branch (`gh workflow run ci.yml --ref feat-one-shot-12197-founder-acceptance-record-text-draft`). Why it works and is not a trick: `ci.yml` declares `workflow_dispatch:`; the `draft-light` job runs only `if: github.event_name == 'pull_request'`; every gated job tests `light != 'true'`; no variable is touched (`CI_DRAFT_LIGHT` stays `on`); nothing is marked ready to obtain CI. The earlier "never mark ready to obtain full CI" is honoured literally; its premise (the hold) is lifted by the operator's explicit instruction, so marking ready after green is now correct.

Exact steps for the work phase:
1. All file changes first, in this order, so the head SHA does not move after the dispatch: text and card notice; `legal-acceptance-copy.ts`, card, dialog, index and `[key]` pages; tests; `registry-pins.test.ts`; the counsel note (c) and (c-2) edits; READMEs and stale header comments; the records and addenda; the old plan's `## Operator Holds` rewrite; append (never rewrite) supersede rows in `decision-challenges.md`.
2. `git merge origin/main` (not rebase). Commit and push; `git rev-list origin/<branch>..HEAD` must be empty.
3. No local full vitest or full `tsc` (memory pressure). Optional, not a gate: `npx vitest run --no-file-parallelism --maxWorkers=1` on the three node-only files (`legal-copy.test.ts`, `registry-pins.test.ts`, `founder-acceptance-record.test.ts`). Cheap local checks: `sha256sum`, `markdownlint-cli2` on touched `.md` files, `git`. The jsdom files (`card.test.tsx`, `page.test.tsx`) go to CI only.
4. Dispatch and arm a watch in the same turn (`hr-dispatch-async-must-arm-watch`): `gh workflow run ci.yml --ref <branch>`; find the run with `gh run list --workflow ci.yml --branch <branch> --event workflow_dispatch --limit 1 --json databaseId,headSha`; confirm `headSha` equals `git rev-parse HEAD`; watch with Monitor and an until-loop on `gh run view <id> --json status,conclusion` (not `run_in_background` polling).
5. Pass criteria, all required: run `conclusion=success`; the `test-webplat` shards `success` and not `skipped` (`gh run view <id> --json jobs --jq '.jobs[]|select(.name|test("test-webplat|^test$"))|"\(.name) \(.conclusion)"'`); `test` is `success`.
6. A red dispatch: fix, commit, push, re-dispatch. No `--undo`, no ready-first route to chase green.
7. Pre-ready edits that do not move the head: rewrite the PR title (`feat(legal-acceptance): add the founder-acceptance-record text (Ref #12197)`; the old "DRAFT ... HOLD" title would become the squash subject) and body (replace the "HOLD: DRAFT ... do NOT mark ready" banner with the stand-in statement; new sha256; updated checklist; the residual-risk list; `Closes #12344` only if every row of CLO C landed; keep `Ref #12197`/`Ref #12011` and also add `Refs #12197`/`Refs #12011` (the companion check's accepted forms are unverified); avoid an `Operator:` prefix and any phrasing that assigns a step to a person, which `ship-operator-step-gate.sh` GROUP_A matches; do not set `SOLEUR_SKIP_OPERATOR_STEP_GATE`).
8. Ready, in one Bash call with `timeout: 420000`, per `ready-run-wait.md`: `K=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/ci-head-verdict.sh" ready-count 12342) && gh pr ready 12342 && bash "$CLAUDE_PLUGIN_ROOT/scripts/ci-head-verdict.sh" wait-ready-run 12342 --before-count "$K"`, then Monitor until `ci-head-verdict.sh verdict 12342` reports `full-decided`. Rollback `gh pr ready 12342 --undo` only on `no-run` or a genuine head-red. A red ready run after a green dispatch means investigate drift, do not undo reflexively. The ready run is a second full run on the same tree: the cost of honouring the operator's order (CTO dissent: skipping the dispatch saves one run).
9. Never `gh pr merge`, never `--auto`, never enqueue.

Gates: `ship-operator-step-gate.sh` (PreToolUse on `gh pr ready`; see step 7). `hold-gate-eval.sh --plan` is skill-enforced at ship Phase 6 step 5 (the draft exit before arming), not a hook on `gh pr ready`; any line beginning `Operator-reserved:` always stands (exit 2). Do not run ship through its arming phase; keep the merge hold standing so ship correctly refuses to arm. `operator-holds.md`: a hold is cleared only by the operator saying so; the CTO rewrites the line. Authority for the rewrite is the operator's 2026-11-07 instruction, quoted verbatim in "Operator Holds, rewritten". Run `soleur:review` on the delta (card, dialog, pages, leaf, tests) before any merge (not needed before ready).

### CTO agent, 4: the deleted guard (verdict per `it` in `founder-acceptance-record.test.ts`)

Ruled by CTO agent, 2026-11-07: KEEP: LF-only printable ASCII audit; "the audit bites"; loader shape (real date, no expiry); forbidden claims on the whole file; "the forbidden-word check bites"; character quantity equals `REQUEST_CHANGES_MAX`; stored-fields list tripwire; "the column pin bites". DELETE: "the committed registry holds only the keys this file guards" (replaced by the three-way set equality); "CI is visible to this run"; "detector sees open items in real data"; "the retention clause is the placeholder sentence"; the CI-only merge guard. DELETE AND REPLACE: "the placeholder detector bites" becomes a permanent always-on (not `skipIf(!CI)`) "no unfinished marker" check over the text body, `cardNotice` and `requestChangesNotice`, using the existing `PLACEHOLDER` pattern minus `\bcounsel\b` (draft-specific) with a planted-string bite test. Add a retention single-source test with a literal `RETENTION_PERIOD` const (the CLO phrase `5 years from the date of the decision`): it appears in the body, appears exactly once in `cardNotice` and once in `requestChangesNotice`, every `N years` duration token in the body equals `5 years`, and the only other duration token allowed in the body is `30 days` inside the request-record paragraph. (The CTO's "exactly once in the body" is relaxed because CLO edits A4 and A7 both carry the phrase; the single-source property holds by the all-tokens-equal rule.) Also update the stale header comments (`founder-acceptance-record.test.ts`, `legal-acceptance-copy.ts`), rewrite the held-draft paragraph of `texts/README.md` into the pin rule, remove the held-draft paragraph of `server/legal-acceptance/README.md`, update `test/feature-map.md`.

### CTO agent, 4b: third table column pin

Ruled by CTO agent, 2026-11-07: add a column-set pin for `legal_reauth_event` next to the two existing pins in `founder-acceptance-record.test.ts` (table created in `supabase/migrations/184_legal_acceptance.sql`, the file the test already reads). Pin 12 columns, sorted: `attempts`, `consumed_at`, `created_at`, `expires_at`, `id`, `key`, `session_id`, `superseded_at`, `text_hash`, `user_id`, `verified_at`, `version`. Extend `alteringMigrations`' table regex to `legal_(acceptance(_ack)?|reauth_event)` (the only ALTER today is `ENABLE ROW LEVEL SECURITY`, which the `(add|drop|rename|alter)` pattern does not match). Add a bite row to "the column pin bites" (a later `ALTER TABLE legal_reauth_event ADD COLUMN` is detected). The failure message says to review the text's code-request paragraph (A5).

### CTO agent, 5: version bump

Ruled by CTO agent, 2026-11-07: no bump; the file is not on main. All edits for this sign-off keep `version: 2026-11-07`, even though the hash changes from `76d2d115...` once the period is filled. The pin's first row uses `2026-11-07`. The bump rule starts at the first merge: any later byte change bumps `version` and appends a pin row; an old row is never edited. If the merge slips past 2026-11-07, do not bump for calendar reasons (the version is an identifier).

## Implementation Phases

**Phase 0 (setup).** Confirm cwd; `git fetch`. Re-verify the premises: text not on main (`git ls-tree`), `ci.yml` has `workflow_dispatch`, PR #12342 still DRAFT. The `select count(*) from public.legal_acceptance;` check is NOT run by the agent: it is the founder's own-login check before any flag.

**Phase 1 (RED).** Before touching product files, write the new tests and run only the node-only files once with the single-worker flags; they must fail for the right reasons (placeholder still in the text, pin absent, kind map absent). Cite the output in the PR body (`cq-write-failing-tests-before`).

**Phase 2 (text and notices).** Apply A1 to A8 by exact OLD/NEW; verify each OLD occurs once before and each NEW once after (a small script in the scratchpad, not committed). Edit the card notice, request-changes notice and the note sections (c), (c-2) together. Check: LF only, printable ASCII, markdownlint on the committed path, `sha256sum` equals loader `textHash`.

**Phase 3 (deck, consumers, label).** Implement the CTO mechanism and the CLO table. `tsc` (in CI) is the sweep for unmigrated consumers.

**Phase 4 (tests).** Rewrite per the CTO verdicts: delete guard tests, add always-on checks, `registry-pins.test.ts`, the third-table pin, card and page tests with the `declared` mock, the new ack card test. Mutation rows: run the node-side ones once each and cite; for the jsdom ones (M7, M8, M10 to M12) run single-file with `--maxWorkers=1`, one at a time, and say in the PR body which were run.

**Phase 5 (records).** CLO ruling audit file; addenda (attestation, counsel-review, LIA, PA-40, register item 17, compliance-posture row, ADR-319 dated amendment); `texts/README.md`, `server/legal-acceptance/README.md`, `test/feature-map.md`; held-draft language removed. File the follow-up issues (S5, S6 in Scope Check) with a roadmap milestone.

**Phase 6 (holds, PR body).** Rewrite the old plan's `## Operator Holds` and `## HOLD procedure`; append supersede rows to `decision-challenges.md`; rewrite the PR title and body (CTO step 7).

**Phase 7 (CI and ready).** CTO steps 2 to 8. Stop after `full-decided`; do not merge.

## Files to Create

- `apps/web-platform/test/legal-acceptance/registry-pins.test.ts`
- `apps/web-platform/test/legal-acceptance/card-kind.test.tsx` (terms variant renders for a declared terms key)
- `apps/web-platform/test/legal-acceptance/card-ack.test.tsx` (real `founder-acceptance-record` key, no-terms DOM assertions, open-dialog control, undeclared key renders nothing)
- `knowledge-base/legal/audits/2026-11-07-clo-ruling-founder-acceptance-record-12197.md` (the persisted CLO ruling, verbatim, with the stand-in statement and the residual-risk list)

## Files to Edit

- `apps/web-platform/server/legal-acceptance/texts/founder-acceptance-record.md` (A1 to A8; version unchanged)
- `apps/web-platform/lib/legal-acceptance-copy.ts` (kind map and functions, 16 members moved, `exactTextHeading`, `dialog.codeBody`, `cardNotice`, `requestChangesNotice`, `signOff.clo`, header comment)
- `apps/web-platform/components/approvals/legal-acceptance-card.tsx`, `apps/web-platform/components/approvals/legal-reauth-dialog.tsx`
- `apps/web-platform/app/(dashboard)/dashboard/approvals/legal/page.tsx`, `apps/web-platform/app/(dashboard)/dashboard/approvals/legal/[key]/page.tsx`
- `apps/web-platform/test/legal-acceptance/founder-acceptance-record.test.ts`, `legal-copy.test.ts`, `card.test.tsx`, `page.test.tsx`; `canonical.test.ts` and `registry-embedding.test.ts` only if the byte change touches a fixture (verify; expected no change)
- `apps/web-platform/server/legal-acceptance/texts/README.md`, `apps/web-platform/server/legal-acceptance/README.md`, `apps/web-platform/test/feature-map.md`
- `knowledge-base/legal/audits/2026-11-founder-legal-acceptance-dsar-and-notice-note.md` (sections (b), (c), (c-2)), `2026-11-founder-legal-acceptance-attestation.md` (addendum, block stays blank), `2026-11-counsel-review-12011.md` (pointer), `knowledge-base/legal/legitimate-interest-assessments/2026-11-founder-legal-acceptance-lia.md` (addendum), `knowledge-base/legal/article-30-register.md` (PA-40 (f), item 17(a)), `knowledge-base/legal/compliance-posture.md` (row), `knowledge-base/engineering/architecture/decisions/ADR-319-*.md` (dated amendment)
- `knowledge-base/project/plans/2026-11-07-feat-founder-acceptance-record-text-draft-plan.md` (`## Operator Holds` and `## HOLD procedure` rewrite only)
- `knowledge-base/project/specs/feat-one-shot-12197-founder-acceptance-record-text-draft/decision-challenges.md` (rows appended in the planning phase; the work phase appends further rows only), `session-state.md`
- The PR title and body (not a file)

Glob check: the existing paths above were taken from `git ls-files`/direct reads in the planning phase; the three new test files and the audit file do not exist yet by design.

## Open Code-Review Overlap

None. Queried open `code-review` issues for every file path above (deck, card, dialog, pages, tests, text); no match.

## Guard Contract

### Guard 1 — pin and key-set guard (`registry-pins.test.ts`)

**Property.** For every key the loader serves, the committed bytes equal a published `{version: sha256}` entry for that exact version, the highest pinned version is the served version, every served key is pinned and has a declared card kind, and a bytes-changed-version-unchanged edit cannot go green.

**Assembly.** Every code path that defines the published set: the loader's `loadLegalTexts()` (the served set), the `PUBLISHED` const (the pin), `LEGAL_TEXT_KIND` (the card kind declaration), and the raw file bytes read independently with `createHash`. Chokepoint: `checkPins(entries, pins, declared)` gets all three; the real-data test and every control row call the same function. A guard scoped to one of the three sources is the defect.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Flip one byte in the committed text, version unchanged | RED (loader hash and independent hash differ from the pin) |
| 2 | Add `texts/zz.md` (valid front matter) | RED (served keys exceed the pinned set) |
| 3 | Delete the `LEGAL_TEXT_KIND` entry for the key | RED (three-way set equality) |
| 4 | Make `checkPins` iterate zero keys (empty loader result) | RED (explicit non-empty assertion; a guard reporting "0 checked" is vacuous) |
| 5 | Append a second pinned version equal to the first sha | RED (uniqueness) |
| 6 | Change the pinned `kind` | RED (declared kind equals pinned kind) |

**Harness rows:** edit the suite, not the guard: make the independent `createHash` read the wrong file (the README) and require RED; and a must-PASS control that is not the canonical: a synthetic registry with two keys, each pinned with two versions (history), highest served, must return `[]`.

**Anchor.** The pin and the text can be edited in one diff, so the guard proves consistency, not integrity. What must also move for a weakening to pass: the append-only shape makes an in-place sha edit a visible modified row in review (review rule in `texts/README.md`), and the database `UNIQUE (founder_id, key, text_hash)` records the hash of every actual decision. A base-ref check was ruled out (flaky); the upgrade path is named above.

### Guard 2 — kind-copy guard (`legal-copy.test.ts` plus card tests)

**Property.** No string a founder can see for a declared acknowledgement text says "terms" or "accepted", no card renders for a key with no declared kind, and every variant is walked by the forbidden-claims and em-dash checks.

**Assembly.** The leaf's `LEGAL_KIND_COPY` (both variants), the shared `LEGAL_COPY`, and the four consumers (card, dialog, index page, `[key]` page). Chokepoint: `legalKindCopy`. A consumer bypassing it with a literal is the defect (M7, M8).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | M1 (default becomes terms, or non-null for `constructor`) | RED |
| 2 | M5 (planted "verified" in an ack-only string) | RED (proves the variant is walked) |
| 3 | M6 (third variant added after two compliant ones) | RED (second-member row) |
| 4 | `collect()` returns fewer than 50 strings (own-dispatch row) | RED (non-vacuity floor) |
| 5 | M7, M8, M9, M10, M11, M12 | RED each, as ruled above |

**Harness rows:** the ban regex run against a planted "accepted by you" string must match; must-PASS: the terms variant (differs from the canonical ack variant) passes the forbidden-claims walk but is excluded from the terms ban.

**Anchor.** The wording is pinned word for word in `legal-copy.test.ts` against the CLO table; changing wording needs a CLO ruling (header comment) and the test edit in the same diff, so the anchor is review plus the persisted ruling file, not an automated external source.

## Observability

No new server-side surface, route or infrastructure. The only runtime observability added is the CTO-ruled Sentry mirror for an undeclared kind: `reportLegalOp("pageReadFailed", null, {extra:{read:"legal_kind_undeclared"}})` in the `[key]` page and the index (`hr-observability-as-plan-quality-gate`).

```yaml
liveness_signal:
  what: the legal-acceptance copy and registry guards run in CI on every PR touching apps/web-platform
  cadence: per PR (test-webplat shards)
  alert_target: CI check status on the PR
  configured_in: .github/workflows/ci.yml
error_reporting:
  destination: Sentry via reportLegalOp (feature legal-acceptance), extra.read = legal_kind_undeclared
  fail_loud: the page calls notFound() after the Sentry mirror, so an undeclared key is a 404 plus an event, never a silent card
failure_modes:
  - mode: a registered text has no declared card kind
    detection: registry-pins.test.ts red in CI; at runtime the Sentry event above
    alert_route: CI red on the PR; Sentry issue for feature legal-acceptance
  - mode: text bytes changed with no pin or version change
    detection: registry-pins.test.ts red
    alert_route: CI red on the PR
logs:
  where: CI run logs; Sentry
  retention: GitHub Actions default; Sentry plan default
discoverability_test:
  command: bash plugins/soleur/scripts/ci-head-verdict.sh verdict 12342
  expected_output: full-decided
```

## Encryption Posture

Not triggered: no persistent store, no new connection, no `.tf`, migration, cloud-init or compose file in the plan. The text only describes stores that already exist (migrations 184 and 185); their encryption posture is unchanged and not claimed in the text.

## Architecture Decision (ADR/C4)

### ADR
A dated amendment to ADR-319 (existing ADR, retention paragraphs): the retention decision changes from "unconfirmed proposal (life of the instrument plus 5, cap 10)" to "5 years from the date of the decision, extended while a claim, complaint or inquiry is open; CLO-agent v1 ruling 2026-11-07". Also record in ADR-319's Alternatives Considered the rejected variable-start period. The `LEGAL_TEXT_KIND` declaration is recorded as a design property (a text with no declared kind renders no card). This is a task in Phase 5, not a follow-up issue.

### C4 views
No C4 impact, with the check to be made: the work phase READS all three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` before this conclusion is written into the PR. Actors/systems/relationships enumerated for this change: the external human actor is the founder (already modeled as the approval-card user); external systems: none new (the email-code sender and Sentry were modeled for PR-C and PR-D); data stores: `legal_acceptance`, `legal_acceptance_ack`, `legal_reauth_event` (already modeled); access relationships: unchanged. Run `plugins/soleur/test/c4-count-parity.test.sh` and the C4 validation tests in CI.

### Sequencing
None: the decision is true on merge (the deletion path is the honest "not yet built" qualifier, with #12080 as the hard stop).

## User-Brand Impact

- **If this lands broken, the user experiences:** the founder opens `/dashboard/approvals/legal` (flag on) and sees a card for the acknowledgement text that still says "these terms" or "Accept the updated Founder acceptance record?", or a retention period on the card that differs from the text, then gives a final Yes that cannot be taken back; or a card renders for a text with no declared meaning.
- **If this leaks, the user's data is exposed via:** the text holds no personal data; the exposure vector is the pseudonymous account uuid, the code-request records (which outlive erasure) and the Request-changes note (up to 1000 characters, may carry third-party personal data) that the text describes. A text that understated who can read them or how long they last would mislead the data subject. The period is a commitment with no enforcing code until #12080.
- **Who can answer (scope):** the `approval-queue` flag is effectively global; once merged with the flag on, any signed-in user can record a final row. The merge and flag exposure stay Operator-reserved.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** carried from the first plan and ADR-319. A final, unretractable Yes on a text that misstates retention, under copy that says "terms accepted", is a one-person Art. 13 and trust failure. CPO plan-time sign-off for the earlier plan (conditions A to D) is carried; this plan satisfies D (#12344) and changes A (counsel) to the operator-ordered CLO-agent stand-in; B (flag state read first) stays. Because the CLO states the CPO deck sign-off is outstanding, `soleur:product:cpo` is invoked in deepen-plan to review the deck change; `signOff.cpo` stays `null` regardless.

## GDPR / compliance

Trigger (b) of Phase 2.7 fires (single-user incident). The substantive assessment is the CLO ruling above (Art. 5(1)(e), 5(2), 6(1)(f), 13, 17(3)(e), 21; a 5-year period with a stated basis; the text now names the third table). The deterministic `soleur:gdpr-gate` pass is run by deepen-plan. The planned edits touch no migration or schema; the register items 17(d), 17(e), 17(g) and DPIA screening stay expressly deferred (the operator's act, not the CLO's). Published trio: see Scope Check S5.

## Domain Review

**Domains relevant:** Legal, Product, Engineering

### Legal
**Status:** reviewed
**Assessment:** CLO agent (two rounds, 2026-11-07): rulings A to D above, quoted verbatim, standing in for counsel on the operator's instruction. Residual risks 1 to 8 carried.

### Engineering
**Status:** reviewed
**Assessment:** CTO agent (two rounds, 2026-11-07): rulings 1 to 5 above. Technical forks were never put to the operator.

### Product/UX Gate
**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none in this planning pass (CPO and `soleur:product:spec-flow-analyzer` are run in deepen-plan)
**Skipped specialists:** none
**Pencil available:** N/A (no new layout; the change is copy strings and a null-render guard inside the existing screens covered by `knowledge-base/product/design/approvals/founder-approval-cards.pen` wireframes 10 to 16; the mechanical UI-surface override matches the edited `components/approvals/*.tsx` paths, so deepen-plan must decide whether the tier is raised to blocking and a wireframe note is needed; the `.pen` text still says "these terms", a design artifact, not blocking per CTO)

#### Findings
Copy-only change to an existing, wireframed flow; no new interactive surface. Flag for deepen-plan: the override match, and CPO review of the acknowledgement wording and the `Acknowledge "<title>"?` title shape.

## Scope Check

| Ask item | Mapping |
|---|---|
| CLO rules on final wording | Rulings A, edits A1 to A8 |
| CLO rules on retention period (#12080 question) | Ruling B |
| #12344 ruled by CTO and CLO, key-dependent wording preferred, fold in, Closes only if fully resolved | CTO 1, CLO C; PR body `Closes #12344` conditional |
| Replace placeholder in text and `LEGAL_COPY.cardNotice` | A4, B; plus the request-changes notice and the note sections (pinned byte for byte) |
| Delete CI-only merge guard, real-data control, retention-clause test | CTO 4 |
| Add `{version: sha256}` pin and exact key set | CTO 2 |
| Version bump if bytes changed after a first merge | CTO 5: no bump |
| Full CI battery on CI, not local; then mark ready | CTO 3 |
| Out of scope: first acceptance, registry smoke, flag | Operator Holds |

Provenance of items not in the brief (all `inferred`, each justified): (S1) `legal_reauth_event` column pin: required because CLO edit A5 makes the text describe that table. (S2) Label from the text's first line: CLO C asks for it ("if the CTO can supply it"), CTO ruled it cheap. (S3) Fail-closed render for an undeclared key: CLO C ("no default is permitted"). (S4) Records and addenda (audit file, attestation addendum, register, LIA, ADR-319, compliance posture): CLO B and D name them; they are append-only supersede markers. (S5) The published trio (Privacy Policy 4.17, GDPR Policy 3.19, Data Protection Disclosure 2.3(aj), 5.3(a), 10.3(l), with mirrors, SHA pins and the DSAR lockstep gate): the CLO says they must change before the card is answerable. NOT folded in: five CI gates and public wording are a separate cycle, and the card is answerable only when the operator-controlled flag is on. File a tracking issue as a precondition of the flag being on for anyone but the operator, and say so in the PR body. The plan takes this default and records it in `decision-challenges.md` as an operator (scope) row the operator may redirect. (S6) Deferral issues: the terms-variant "updated for a first text" wording, and the base-SHA pin guard upgrade (trigger: second text added). Split assessment: one PR; the changes are coupled by the pinned byte-for-byte notice tests.

## Acceptance Criteria

- [ ] AC1: the text file contains each NEW of A1 to A8 exactly once and no OLD; `version: 2026-11-07`; LF-only printable ASCII; `markdownlint-cli2` on the committed path exits 0; `sha256sum` equals loader `textHash` and the `registry-pins.test.ts` pin (cite the value in the PR body).
- [ ] AC2: `grep -c '\[period to be confirmed by counsel\]'` over the text, `legal-acceptance-copy.ts`, the DSAR note and the tests prints 0 everywhere except inside superseded markers.
- [ ] AC3: `cardNotice` and `requestChangesNotice` equal the note's (c-2) and (c) blockquotes byte for byte and carry `5 years from the date of the decision`.
- [ ] AC4: the merge guard describe, "CI is visible", "real data control", "retention clause" and the registry tripwire are gone; the always-on unfinished-marker check, the retention single-source test, the third-table column pin and `registry-pins.test.ts` exist and pass in CI; no `skipIf(!process.env.CI)` remains in the file.
- [ ] AC5: `LEGAL_COPY` no longer exposes the 16 moved members; `tsc` (CI) is clean; the four consumers use `legalKindCopy`, `legalIndexState`, `legalDisplayLabel`; an undeclared key renders no card, 404s the page and mirrors to Sentry.
- [ ] AC6: the acknowledgement variant renders none of `/\bterms?\b|accepted by you|Accept the updated/i` in the real-key card test, including with the dialog open; the shared deck has no `\bterms?\b` and no "updated"; `dialog.codeBody` is the CLO string.
- [ ] AC7: `LEGAL_COPY.signOff` is `{cpo: null, clo: "Ruled by CLO agent, 2026-11-07: v1 internal sign-off, not external counsel"}`; `PROVISIONAL` is `true`; the attestation block cells are unchanged (blank); the addenda say "stand-in", never "counsel reviewed".
- [ ] AC8: no string in text, deck, tests or records says verified, reviewed, certified, legally binding, audit-ready or compliant about the text (the shared forbidden list passes).
- [ ] AC9: a `workflow_dispatch` run of `ci.yml` on the final head SHA has `conclusion=success` with the `test-webplat` shards `success` (not `skipped`) and `test` `success`; then the PR is marked ready; the ready run's verdict is `full-decided` and green. No local full test or build was run.
- [ ] AC10: PR #12342 has a non-DRAFT/HOLD title, a body with the stand-in statement and the 8 residual risks, the new sha256, `Closes #12344` only if every CLO C row landed, and in the checklist the pre-flag check `select count(*) from public.legal_acceptance;` must be 0 (founder's own login); the PR is not merged and not enqueued.
- [ ] AC11: the old plan's `## Operator Holds` and `## HOLD procedure` are rewritten as ruled; `decision-challenges.md` carries a row for each ruling and each operator-reserved item; no flag, Doppler, Supabase production or `legal_acceptance` row was touched.
- [ ] AC12: tracking issues exist for S5 (published trio, precondition of the flag beyond the operator) and S6 (terms "updated" wording, base-SHA pin guard), each with re-evaluation criteria and a roadmap milestone; #12080's re-evaluation criterion is restated (before the first non-Jikigai founder, or before any row is 4 years old).

## Test Scenarios

1. Placeholder gone: the unfinished-marker check finds nothing in the text body, `cardNotice`, `requestChangesNotice`; planted `[x]`, `TBD`, `to be confirmed` strings are caught.
2. Retention single source: the phrase appears in the body, once in each notice; planting `7 years` in the body fails.
3. Pin: flipping a byte fails all three pin legs; a new key with no pin fails; a version bump with the same bytes fails.
4. Kind copy: the ack key renders acknowledgement wording; `customer-terms` (mocked as terms) renders today's wording; `constructor` renders nothing.
5. `[key]` page for an undeclared key: NotFound plus a Sentry event; the index omits it.
6. Third table: adding a column to `legal_reauth_event` in a later migration fails the pin with the A5 message.
7. Label: the first line `How your decisions are recorded and kept` is the card title; a first line over 120 characters falls back to the key-derived label.

## Operator Holds, rewritten

Authority and quote: the operator's 2026-11-07 instruction: "the company has no external counsel, so the CLO agent's ruling (soleur:legal:clo) stands in for counsel sign-off", and "run the full CI battery ... only then mark the PR ready". The CTO rewrites the old plan's three `Operator-reserved:` lines accordingly (operator-holds.md).

- **Sign-off record (replaces old Hold 1; not a `Hold:` line):** the CLO agent signed off the wording, the retention period (5 years from the date of the decision, extended while a claim, complaint or inquiry is open) and the card wording as a stand-in for counsel on the operator's instruction of 2026-11-07, with human-lawyer review still owed (residual risks 1 to 8).
- **Cleared (old Hold 2, first half):** marking PR #12342 ready after the full CI battery is green on the final head.
- Hold: Operator-reserved: merging or enqueuing PR #12342, and the `approval-queue` flag state in prd. Merge deploys the text where it becomes answerable by any signed-in user once the global flag is on; the flag state is read first (CPO condition B) and the published trio (S5) is a precondition for the flag being on for anyone but the operator.
- Hold: Operator-reserved: the first real acceptance of this text, the registry smoke and the roadmap CP2 wording (#12197 stays open; wording stays "In progress (legal-acceptance slice)"). Before any flag: `select count(*) from public.legal_acceptance;` must be 0, checked by the founder with their own login.

Categories: irreversible / production-mutating authorization (merge, flag, first acceptance). The legal-risk category (wording) is discharged by the operator's stand-in ruling.

## Non-goals

No flag change, no recorded decision, no merge or enqueue, no migration, no change to published legal documents (tracked S5), no deletion path (#12080 stays open; its trigger is restated), no external anchor, no change to the card layout.

## Risks

- The 5 years is a commitment with no enforcing code; Art. 5(1)(e) and the notice are both breached if #12080 is not built before any row is 4 years old. Mitigation: A4's plain statement, the restated #12080 trigger (4 years), no row exists.
- The stand-in is not a lawyer: residual risks 1 to 8; `PROVISIONAL` stays true.
- The shared `requestChangesNotice` and `cardNotice` now state a text-specific period for every text; a later text with a different period needs its own CLO ruling and a notice change (CLO B).
- Moving 16 deck strings touches the card, dialog and two pages; mitigated by `tsc` and the real-key DOM test, but the jsdom suites run only in CI.
- The A4 sentence promises a deletion step "before any record reaches that age"; if ownership of that commitment changes, it must be re-ruled.
- A ready run is a second full CI run on the same tree; accepted per the operator's order.
- Whether `Refs` counts for the companion closing-keyword check is unverified (CTO step 7).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this one is filled.
- The text is hashed as raw bytes: never let an editor, formatter or `markdownlint --fix` rewrite it. Apply edits with a script or exact-match Edit, then `cmp`/`sha256sum`.
- Two plans carry this `branch:`; the Phase 0.7 selector tie-break picks the later-sorting name (this one). Do not rename either.
- The note's blockquote lines are pinned byte for byte by `legal-copy.test.ts`: the note edit and the deck edit must be one commit or CI is red between them.
- The CLO's A5 paragraph and the `legal_reauth_event` column pin must land together: the pin's failure message points at the paragraph.
- The ack-ban regex must be applied to the DOM with the dialog open; `dialog.codeBody` is shared and the ban only holds after the CLO's "checked" rewrite.
- Cite code by function or constant name in every record, never by line number.
- The sha256 in the PR body from the first draft (`76d2d115...`) is stale after A1 to A8; replace it.
