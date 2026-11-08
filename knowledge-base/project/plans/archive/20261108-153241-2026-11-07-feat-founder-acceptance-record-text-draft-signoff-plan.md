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

## Enhancement Summary

**Deepened on:** 2026-11-07. **Agents and gates used:** soleur:legal:clo (two rounds), soleur:engineering:cto (three rounds), soleur:engineering:research:learnings-researcher, soleur:engineering:review:user-impact-reviewer, soleur:product:cpo, soleur:product:spec-flow-analyzer, soleur:engineering:review:code-simplicity-reviewer, soleur:engineering:review:test-design-reviewer, soleur:engineering:review:architecture-strategist, soleur:gdpr-gate (plan mode). The separate plan-review panel was folded into this pass.

### Key improvements

1. Rulings recorded verbatim: retention 5 years from the date of the decision (extended while a claim, complaint or inquiry is open), CLO wording A1 to A8 and the two-kind card deck, CTO mechanism (kind map in the leaf, no default, fail-closed render), pin design, CI dispatch route.
2. Two BLOCKING findings from the user-impact review were turned into mechanisms: a `parked` label enforced by the existing operator-step hook and the drain-prs triage (merge was otherwise one standing rule away once the PR is ready), and a server-side founder gate (the flag is global and cannot target one user).
3. Test design defects fixed before any code exists: the DOM ban contradicted the CLO's first Yes wording (rewritten with no "terms"), probes contaminated the ban walk, the dialog is portalled so `container` missed it, the mock could not reach internal lookups, retention tokens needed an exact multiset, and the vacuous founder-login `count(*)` was replaced.
4. The 12 residual risks of an agent standing in for counsel are listed once (audit file and PR body), not hidden.

### New considerations discovered

- The text must never promise a hard 30-day bound for request records (the purge runs only when someone requests a code).
- The emailed code uses the shared sign-in template (10 minutes, "sign in"); not changed, recorded as a scope-out.
- A deleted or de-declared text vanishes from the card pages by design (rows stay for a DSAR export).

## Overview

Continuation plan for the open DRAFT PR #12342 (Ref #12197, #12011). The first plan, `2026-11-07-feat-founder-acceptance-record-text-draft-plan.md`, produced the held draft. It is history; this plan supersedes its `## HOLD procedure` and splits its `## Operator Holds` (see "Operator Holds, rewritten"). Both plans carry the `branch:` of this worktree; the Phase 0.7 selector tie-break picks this one (it sorts later by name at the same date).

The work phase does, in this order:

1. Apply the CLO's final wording edits (A1 to A8) to the text and fill the retention period (5 years from the date of the decision, extended only while a legal claim, a complaint or an official inquiry about the record is open) in the text, in `LEGAL_COPY.cardNotice` and in `LEGAL_COPY.requestChangesNotice`, and in the counsel note sections (c) and (c-2) that the deck test pins byte for byte.
2. Fix #12344 inside this PR: kind-keyed card copy (`terms` / `acknowledgement`), fail-closed for an undeclared key, label from the text's own first line, the CLO's acknowledgement wording, and the pinned tests.
3. Delete the CI-only merge guard, its real-data control and the retention-clause test; replace them with an always-on unfinished-marker check and a retention single-source test; add the registry-wide `{version: sha256}` pin with the exact key set in `registry-pins.test.ts`; pin the third table's columns.
4. Record the sign-off (append-only addenda, no edit of the blank attestation block), rewrite the holds, then get the FULL CI battery by dispatching `ci.yml` on the branch (not a local full run), and only then mark the PR ready.

Out of scope, stays with #12197 and the founder: the founder's first acceptance, the post-deploy registry smoke, the `approval-queue` flag, the roadmap CP2 wording, any merge or enqueue. Before any flag change the pre-flag read is the CTO's non-vacuous pair (structural: no committed text on `main` so every key 404s; observable: the Sentry `accepted` event count is 0), not the founder-login SQL count, which only sees the founder's own rows (deepen-plan, CTO B2).

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

> **Superseded 2026-11-08 (CLO ruling L1, review round 1), as to "it is not covered by the 5 years above":** the served text now reads "it is not covered by the 5 years stated under How long it is kept", because the period is stated further down the text, not above this paragraph. The pinned text carries the amended sentence; this paragraph keeps the original wording as the record of what was first ruled.

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
- FINAL `cardNotice` and note (c-2) (deepen-plan CLO ruling 3, one bold line, supersedes the bullet above where they differ): "Your decision is saved with your account identifier, the text's version and fingerprint, the time, and (for Yes) the time you confirmed the emailed code. Jikigai keeps this record to be able to show later what was decided, even if you delete your account, for 5 years from the date of the decision (longer only while a legal claim, a complaint or an official inquiry about it is open). You can ask what we hold, ask for erasure or restriction, or object by writing to <legal@jikigai.com>, and you can complain to the CNIL."
- Request-changes notice: ending `...up to 1000 characters, and is kept even if you later delete your account.` becomes `...up to 1000 characters, and is kept for 5 years from the date of the decision, even if you later delete your account.`

Trigger restated for #12080: build the deletion path before the first non-Jikigai founder, or before any row is 4 years old (12 months before the 5-year date); note redaction is no longer separate because the note is deleted with the row; the request-record purge on erasure and the ack-row deletion stay in scope.

Consequential records (edit in place with `> **Superseded 2026-11-07 (#12197; fires on the merge of the pull request that carries it): ...**` markers, append-only): PA-40 (f) and register item 17(a); LIA "Retention proposal" and its counsel item 1; attestation section 2 ("retention lawful"); DSAR note (b) ("For how long" and the code-request bracket) and sections (c), (c-2); ADR-319 retention paragraphs (as a dated amendment); the compliance-posture row. Do not edit migration 184/185 comments. Source check on citations: art. 2224, L123-22 and the 7-year precedent were verified in the repo's own records; art. 2232, L110-4 and CNIL archiving guidance are from the CLO's memory and flagged unverified.

### CLO agent, C: card deck wording (#12344)

Two deck-owned wordings selected by a declared kind. A single neutral wording for all texts is not acceptable (CLO). Heading for both kinds: `exactTextHeading` becomes `The exact text your answer covers` (the old heading overstates: only the sha256 is stored, never the text; ADR-319 property 4).

> **Superseded 2026-11-08 (CLO follow-up 6, same ruling):** ADR-319 has Properties 1 to 3 only; the heading is grounded on property 4 of the ATTESTATION RECORD (verbatim text not stored, only its sha256), not on an ADR-319 property 4. The citation in this line is superseded by follow-up item 6 below.

| Field (current `LEGAL_COPY` path) | terms kind | acknowledgement kind |
|---|---|---|
| `pending.title(label)` | `Accept the updated ${label}?` | `Acknowledge "${label}"?` |
| `yesRow.body` | `Soleur treats these terms as accepted by you, starting today. Clicking again does not undo it. To change it later you would ask for a new version.` | `Your Yes is recorded as your acknowledgement that you were shown this text. That is all it means: it is not consent and it agrees to nothing. Clicking again does not undo it. To change it later you would ask for a new version.` |
| `noRow.body` | `Nothing changes. The current terms stay in place. Final once recorded.` | `Your No is recorded as your answer. The text stays as it is and nothing is acknowledged. Final once recorded.` |
| `changesRow.body` | `Your note is saved with your decision. Nothing is accepted by asking for changes. Final once recorded.` | `Your note is saved with your decision. Nothing is acknowledged by asking for changes. Final once recorded.` |
| `changes.footer` | `Nothing is accepted by saving this. Your note is saved with your decision.` | `Nothing is acknowledged by saving this. Your note is saved with your decision.` |
| `pending.nothingAccepted` | `Nothing has been accepted.` | `Nothing has been acknowledged.` |
| `pending.notAvailable` | `Answering is not available yet. Nothing has been accepted.` | `Answering is not available yet. Nothing has been acknowledged.` |
| `accepted.badge` | `Accepted` | `Acknowledged` |
| `accepted.title(label)` | `You accepted the updated ${label}` | `You acknowledged "${label}"` |
| `accepted.body` | `Soleur now treats this version as accepted by you. To change this later, ask for a new version.` | `Your Yes is recorded as your acknowledgement that you were shown this version. That is all it means: it is not consent and it agrees to nothing. To change this later, ask for a new version.` |
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

Export shape (no runtime imports in the leaf; `import type { LegalCardStateWire }` is allowed because it is erased):

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
export function legalIndexState(kc: LegalKindCopy, state: LegalCardStateWire): string; // accepted -> kc.indexAccepted, else LEGAL_COPY.index.state[state]
export function legalDisplayLabel(kind: LegalTextKind, key: string, body: string): string; // terms -> legalTextLabel(key); acknowledgement -> first non-empty line only if it matches /^[A-Za-z0-9][\x20\x21\x23-\x7e]{0,119}$/, else legalTextLabel(key)
```

Delete from `LEGAL_COPY` the 16 moved members (so `tsc` finds every unmigrated consumer): `yesRow.body`, `noRow.body`, `changesRow.body`, `changes.footer`, `pending.{title,nothingAccepted,notAvailable}`, `accepted.{badge,title,body}`, `declined.{title,body}`, `changesRequested.body`, `expired.body`, `dialog.answerDetail`, `index.state.accepted`. `yesRow.label`, `noRow.label`, `declined.badge` and the rest stay. `exactTextHeading` stays shared with the new string.

Label (follow-up ruling): `legalDisplayLabel` for `acknowledgement` returns the first non-empty body line, trimmed, if 1 to 120 characters, else `legalTextLabel(key)`; for `terms` it returns `legalTextLabel(key)` (pinned wording unchanged). Derived server-side (both pages already hold the entry body) and passed as a required `label` prop on `LegalAcceptanceCard`; the card stops calling `legalTextLabel`. The "replaced" cards (empty body) get the current entry's label, computed once. Anchor test: the real text gives `How your decisions are recorded and kept`; mutation row: change the text's first line, anchor and pin go red.

Consumers:
- `apps/web-platform/app/(dashboard)/dashboard/approvals/legal/[key]/page.tsx`: if `legalKindCopy(key)` is null, `reportLegalOp("pageReadFailed", null, {extra:{read:"legal_kind_undeclared"}})` then `notFound()`; compute the label and pass it. **[Superseded 2026-11-08: the implemented op is `kindUndeclared` (`kind_undeclared`, warn level, unpaged, `tags.key`), as the Observability block states; it fires on every render, after the surface gate.]**
- `.../legal/page.tsx` (index): filter out undeclared keys before building items, mirror to Sentry; use `legalIndexState(i.key, i.state)` and `legalDisplayLabel`.
- `components/approvals/legal-acceptance-card.tsx`: `const kc = legalKindCopy(keyName)`; return `null` after the hooks if null (no on-card string). Replace the uses of the 16 moved strings and the `[yesRow, noRow, changesRow]` row builder.
- `components/approvals/legal-reauth-dialog.tsx`: new required prop `answerDetail: string` resolved by the card; the dialog does no kind lookup.
- `lib/legal-acceptance-client.ts` and the rest of the `[key]` page: neutral strings only.
- Residual (state in the PR body): the decide and verify routes still accept any registered key by direct API call. That is not a card. The CI declaration test (below) is what stops an undeclared key reaching prod.

Tests (wording-agnostic where possible; where this list differs from the deepen-plan block, C7 and C8, the block wins: no negation stripping, `document.body`, neutral probes, no `card-kind.test.tsx`):
- `legal-copy.test.ts`: extend `collect()` probes with `["founder-acceptance-record"]`, `["unknown-key"]`, `["constructor"]`; assert `Object.keys(LEGAL_KIND_COPY)` equals `LEGAL_TEXT_KINDS` as a set; each kind yields more than 8 strings and every one is in `all`; for declared keys `legalKindCopy(k)` is `toBe` a member of `Object.values(LEGAL_KIND_COPY)` (identity, so an inline-built variant fails); unknown, `"zzz"`, `"constructor"`, `"__proto__"` give `toBeNull`; one ban `/\bterms?\b|\baccept(ed|s|ance)?\b|accept the|\bupdated\b/i` applies to the ack variant and to the shared deck (`collect(LEGAL_COPY)` has more than 40 strings and none match), with the two deliberate negations in the ack `yesBody`/`acceptedBody` ("It does not accept any terms") as the only exact exceptions, each pinned; the terms variant matches `/terms/` (non-vacuity); forbidden-claims, em dash and notice tests keep walking `all` (now including both variants); `cardNotice` and `requestChangesNotice` still equal the note's blockquotes byte for byte, no placeholder; `signOff`/`PROVISIONAL` pins per CLO D; the first line of an acknowledgement text has no double quote and no newline.
- `card.test.tsx`, `page.test.tsx`: `customer-terms` and `other-terms` are now undeclared; wrap with `vi.mock("@/lib/legal-acceptance-copy")` using `importActual` and `declared = {"customer-terms":"terms","other-terms":"terms"}`; use `const KC = legalKindCopy("customer-terms")` instead of literal strings; add an index assertion that an accepted row shows `legalKindCopy(key).indexAccepted`.
- New card test file for the real key `founder-acceptance-record` with a body without "terms": assert `container.textContent` matches none of `/\bterms?\b|accepted by you|Accept the updated/i`, again after opening the dialog (the open-dialog DOM control covers `codeBody`).
- A terms-declared key rendering today's wording is covered inside `card.test.tsx` (the former `card-kind.test.tsx` is folded in).

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
7. Pre-ready edits that do not move the head: rewrite the PR title (`feat(legal-acceptance): add the founder-acceptance-record text (Ref #12197)`; the old "DRAFT ... HOLD" title would become the squash subject) and body (replace the "HOLD: DRAFT ... do NOT mark ready" banner with the stand-in statement; new sha256; updated checklist; the residual-risk list; `Closes #12344` only if every row of CLO C landed; keep `Ref #12197`/`Ref #12011` only (the plural `Refs` suggestion is withdrawn, see the deepen-plan block D7); write no bullet that `ship-operator-step-gate.sh` GROUP_A matches; do not set `SOLEUR_SKIP_OPERATOR_STEP_GATE`).
8. Ready, in one Bash call with `timeout: 420000`, per `ready-run-wait.md`: `K=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/ci-head-verdict.sh" ready-count 12342) && gh pr ready 12342 && bash "$CLAUDE_PLUGIN_ROOT/scripts/ci-head-verdict.sh" wait-ready-run 12342 --before-count "$K"`, then Monitor until `ci-head-verdict.sh verdict 12342` reports `full-decided`. Rollback `gh pr ready 12342 --undo` only on `no-run` or a genuine head-red. A red ready run after a green dispatch means investigate drift, do not undo reflexively. The ready run is a second full run on the same tree: the cost of honouring the operator's order (CTO dissent: skipping the dispatch saves one run).
9. Never `gh pr merge`, never `--auto`, never enqueue.

Gates: `ship-operator-step-gate.sh` (PreToolUse on `gh pr ready`; see step 7). `hold-gate-eval.sh --plan` is skill-enforced at ship Phase 6 step 5 (the draft exit before arming), not a hook on `gh pr ready`; any line beginning `Operator-reserved:` always stands (exit 2). Do not run ship through its arming phase; keep the merge hold standing so ship correctly refuses to arm. `operator-holds.md`: a hold is cleared only by the operator saying so; the CTO rewrites the line. Authority for the rewrite is the operator's 2026-11-07 instruction, quoted verbatim in "Operator Holds, rewritten". Run `soleur:review` on the delta (card, dialog, pages, leaf, tests) before any merge (not needed before ready).

### CTO agent, 4: the deleted guard (verdict per `it` in `founder-acceptance-record.test.ts`)

Ruled by CTO agent, 2026-11-07: KEEP: LF-only printable ASCII audit; "the audit bites"; loader shape (real date, no expiry); forbidden claims on the whole file; "the forbidden-word check bites"; character quantity equals `REQUEST_CHANGES_MAX`; stored-fields list tripwire; "the column pin bites". DELETE: "the committed registry holds only the keys this file guards" (replaced by the three-way set equality); "CI is visible to this run"; "detector sees open items in real data"; "the retention clause is the placeholder sentence"; the CI-only merge guard. DELETE AND REPLACE: "the placeholder detector bites" becomes a permanent always-on (not `skipIf(!CI)`) "no unfinished marker" check over the text body, `cardNotice` and `requestChangesNotice`, using the existing `PLACEHOLDER` pattern minus `\bcounsel\b` (draft-specific) with a planted-string bite test. Add a retention single-source test with a literal `RETENTION_PERIOD` const (the CLO phrase `5 years from the date of the decision`): it appears in the body, appears exactly once in `cardNotice` and once in `requestChangesNotice`, every `N years` duration token in the body equals `5 years`, and the only other duration token allowed in the body is `30 days` inside the request-record paragraph. (The CTO's "exactly once in the body" is relaxed because CLO edits A4 and A7 both carry the phrase; the single-source property holds by the all-tokens-equal rule.) Also update the stale header comments (`founder-acceptance-record.test.ts`, `legal-acceptance-copy.ts`), rewrite the held-draft paragraph of `texts/README.md` into the pin rule, remove the held-draft paragraph of `server/legal-acceptance/README.md`, update `test/feature-map.md`.

### CTO agent, 4b: third table column pin

Ruled by CTO agent, 2026-11-07: add a column-set pin for `legal_reauth_event` next to the two existing pins in `founder-acceptance-record.test.ts` (table created in `supabase/migrations/184_legal_acceptance.sql`, the file the test already reads). Pin 12 columns, sorted: `attempts`, `consumed_at`, `created_at`, `expires_at`, `id`, `key`, `session_id`, `superseded_at`, `text_hash`, `user_id`, `verified_at`, `version`. Extend `alteringMigrations`' table regex to `legal_(acceptance(_ack)?|reauth_event)` (the only ALTER today is `ENABLE ROW LEVEL SECURITY`, which the `(add|drop|rename|alter)` pattern does not match). Add a bite row to "the column pin bites" (a later `ALTER TABLE legal_reauth_event ADD COLUMN` is detected). The failure message says to review the text's code-request paragraph (A5).

### CTO agent, 5: version bump

Ruled by CTO agent, 2026-11-07: no bump; the file is not on main. All edits for this sign-off keep `version: 2026-11-07`, even though the hash changes from `76d2d115...` once the period is filled. The pin's first row uses `2026-11-07`. The bump rule starts at the first merge: any later byte change bumps `version` and appends a pin row; an old row is never edited. If the merge slips past 2026-11-07, do not bump for calendar reasons (the version is an identifier).

## Deepen-plan rulings and reconciliation (2026-11-07; authoritative where it differs from the sections above)

Panel run in deepen-plan: `soleur:engineering:review:user-impact-reviewer`, `soleur:product:cpo`, `soleur:product:spec-flow-analyzer`, `soleur:engineering:review:code-simplicity-reviewer`, `soleur:engineering:review:test-design-reviewer`, `soleur:engineering:review:architecture-strategist`, plus `soleur:gdpr-gate` (plan mode), then a second CLO round and a third CTO round on the findings. The separate plan-review panel is folded into this pass. The CLO and CTO were asked every technical or legal fork; none went to the operator.

### CLO agent, second round (verbatim rulings)

1. Yes and accepted wording, positive first, no "terms" anywhere in the acknowledgement variant, so the ack ban is exact with NO exception pins. Final strings: `yesBody` = "Your Yes is recorded as your acknowledgement that you were shown this text. That is all it means: it is not consent and it agrees to nothing. Clicking again does not undo it. To change it later you would ask for a new version." and `acceptedBody` = "Your Yes is recorded as your acknowledgement that you were shown this version. That is all it means: it is not consent and it agrees to nothing. To change this later, ask for a new version." Ruled by CLO agent, 2026-11-07: the two strings above are final; the ack-variant ban is exact with no allowlist.
2. Finality on every row. Ruled by CLO agent, 2026-11-07: finality is stated on all three rows in both kinds, with the clause " Final once recorded." appended to `noBody` and `changesBody` (strings in the table above); `finalNote` stays on the pending card; `changes.footer` and the decline dialog unchanged.
3. Card rights sentence. Ruled by CLO agent, 2026-11-07: the sentence "You can ask what we hold, ask for erasure or restriction, or object by writing to <legal@jikigai.com>, and you can complain to the CNIL." replaces the old rights sentence in `cardNotice` and DSAR note (c-2) (full final string under CLO B).
4. Temporal qualifier. Ruled by CLO agent, 2026-11-07: no build-state clause in the notices (they state the commitment; a build-state clause would go stale the day #12080 ships and force a pinned-deck change). Required instead: (a) a dated test in `founder-acceptance-record.test.ts` that fails from 2030-11-07 while the text body still contains "has not yet built", failure message naming #12080; (b) #12080 acceptance criteria: the end-of-retention step deletes in ONE transaction the `legal_acceptance` row (so the note goes with it), its `legal_acceptance_ack` row and the founder's `legal_reauth_event` rows, with a test that ages a fixture decision with a note plus its ack row past 5 years, runs the step, asserts all three are gone together and that no other founder's rows are touched; (c) #12080 defines how a hold (claim, complaint, inquiry) is recorded, because "longer only while open" is unimplementable without one, and the step skips held rows.
5. Stored `accept`. Ruled by CLO agent, 2026-11-07: this sentence is required in the persisted ruling file and in `texts/README.md`: "For a text of kind acknowledgement, the stored choice value accept means only that the founder answered Yes to an acknowledgement of that exact text version; it records no acceptance of terms and no consent. Anything that reads a decision row or a check result must read the kind pinned for that text key in the registry before it interprets accept."
6. Heading citation. Ruled by CLO agent, 2026-11-07: `exactTextHeading` = "The exact text your answer covers" stands on property 4 of the ATTESTATION RECORD (verbatim text not stored, only its sha256), the ADR-319 Residual-risk bullet ("only its hash is stored in the row, and the text lives in the repository") and the `text_hash` column set of migration 184. ADR-319 Properties are 1 to 3: do not cite "ADR-319 property 4".
7. Residual risks 9 to 12 are added to the eight above: (9) the wording was authored and ruled on by the same agent role, no independent read exists; (10) the `approval-queue` flag is read with `workspaceId: null` and cannot target one user (mitigated in this PR by the founder gate below, but the flag itself is still global); (11) a pre-flag `count(*)` under the founder's own login sees only that founder's rows (replaced, see CTO B); (12) AP-009 "Never delete user data" (advisory) is in tension with deleting after 5 years: record a bounded, documented deviation in the ADR-319 amendment (only expired `legal_acceptance` rows, one controlled database-owner action, hold-aware), as ADR-119 documents its AP-009 carve-out.
8. Roadmap CP2 ceiling. Ruled by CLO agent, 2026-11-07: this PR does not edit the roadmap (it says "Not started" today). When edited later by the operator the ceiling is: "Started, operator only: a record of the founder's own decision on a legal text exists behind a feature flag, not enabled in production, on a v1 internal legal position with no external counsel. The batched approval queue for write and send actions is not started." It may not say approvals work for other users, that the record is counsel-cleared, or that it is enforceable.
9. Shared `dialog.codeBody` and the `answerDetail` code sentence: "Nothing is recorded until your code is checked." in both kinds (first-round follow-up, already in the table above). The CTO notes the emailed code expires in 10 minutes (shared sign-in template) while the card says "a few minutes"; reconciling is a wording call left as a known leftover (S6), not changed here.
10. A5 (request records): the migration's 30-day DELETE runs only inside `issue_legal_reauth`, when someone asks for a code. A5 already says "so one can last longer than 30 days"; the text must never promise a hard 30-day upper bound.

    > **Superseded 2026-11-08 (CLO ruling L6, review round 1), as to "runs only inside `issue_legal_reauth`, when someone asks for a code":** `issue_legal_reauth` runs its 30-day DELETE before any outcome branch and `decideLegal` calls `issueIntent` for Decline and Request changes too, so the purge runs on EVERY intent issuance (verified in migration 184). A5's "so one can last longer than 30 days" and the rule that the text never promises a hard 30-day bound both stand.

### CTO agent, third round (verbatim rulings; corrections to the CTO's own earlier text come first)

Corrections: the CTO withdrew its earlier suggestions of a plural `Refs #12197` in the PR body and of per-user flag targeting (the flag identifier is `role:prd` or `org:..:role`, never a user id, `lib/feature-flags/server.ts`).

**A. Merge barrier.** Ruled by CTO agent, 2026-11-07: use the EXISTING `parked` label (description: "Reviewed draft held until an approved window; do not merge or arm auto-merge"; no code reads it today), enforced mechanically in two places; no new hook, no AGENTS.md change.
1. Extend the already-registered `.claude/hooks/ship-operator-step-gate.sh` with a branch that matches any `gh pr merge` that is not `--disable-auto` (including chained forms and `--admin`), resolves the PR number as the hook already does, runs `gh pr view N --json labels`, and emits `permissionDecision` deny when `parked` is present, reason "merge and enqueue of this PR are reserved for the operator; the operator removes the `parked` label". It also denies `gh pr edit N --remove-label parked` and the equivalent `gh api` DELETE on the label. A resolved PR number with a failed label read fails closed. `gh pr ready` is not blocked. Test rows in `ship-operator-step-gate.test.sh`: plain merge, `--auto` merge and chained `ready && merge --auto` each denied while labelled; allowed after the label is removed; `--disable-auto` allowed; label-read failure denied; remove-label denied; an unlabelled PR unaffected. Mutation: drop the new branch and the first row goes red.
2. `plugins/soleur/skills/drain-prs/scripts/triage-prs.sh` classifies a `parked` PR into a new tier `parked`, never merged, evaluated before the `needs-review` and green tiers; test row with a green ready PR carrying `parked`.
3. Order: `gh pr edit 12342 --add-label parked`, verify with `gh pr view 12342 --json labels`, THEN `gh pr ready 12342`. Auto-merge stays off; never run `gh pr merge` on this PR. AGENTS rule `wg-after-marking-a-pr-ready-run-gh-pr-merge` is expressly overridden for this PR by the operator's hold: say so in the PR body and in the resume prompt.
4. PR body banner: "Parked: merge and enqueue are reserved for the operator (label `parked`)." Clearing: the operator removes the label (UI or their own terminal); then the CTO rewrites the hold line.
5. Limit, stated plainly: this stops accidental merges by agent sessions and by drain-prs. It does not stop a human or an admin UI merge. **[Superseded 2026-11-08 by CTO rulings T1 and T2: the barrier is a best-effort guardrail on a branch that carries it, not an access control; it is absent from origin/main (0 occurrences), so a session on a main-based checkout and the drain-prs run from the plugin root do not have it; the DRAFT status of the PR is the real hold; the bypasses (script files, `$GH`, `xargs`, `schedule` in Actions, the other merge sites) are listed in one follow-up issue. Do not claim it "stops drain-prs" without that scope.]**
6. Old plan: replace its whole `## Operator Holds` section (the three `- Hold:` lines and the "Operator-reserved by category" paragraph) with exactly: heading `## Superseded hold record` and the body "Superseded 2026-11-07. The live holds for PR #12342 are in knowledge-base/project/plans/2026-11-07-feat-founder-acceptance-record-text-draft-signoff-plan.md. Nothing in this plan is evaluated as a hold."; replace its whole `## HOLD procedure` section with heading `## Superseded procedure` and the body "Superseded 2026-11-07 by the sign-off plan (see above); the draft-hold steps no longer apply." Verify: `bash plugins/soleur/skills/ship/scripts/hold-gate-eval.sh --plan <old plan>` shows no holds (rc 0); the same on this plan returns rc 3 (no `Delegation:` line; the prose path; holds listed standing). In a headless run the prose path files ONE `action-required` issue naming "approve the merge of PR #12342, which deploys the signed-off text; the card stays dark until the operator turns the flag on and the founder-only gate applies": that issue is expected, not an error; no delegation covers an `Operator-reserved:` line.

**B. Flag scope.**
1. Ruled by CTO agent, 2026-11-07: add a server-side founder gate in this PR reusing `LEGAL_ACCEPTANCE_FOUNDER_ID` (already used by the verify route and set in Doppler prd; the value was checked to exist and not printed). New helper in `apps/web-platform/server/legal-acceptance/surface.ts`: `isLegalSurfaceEnabled(userId) = (await isApprovalQueueEnabled({userId, workspaceId:null})) && userId === legalFounderId()`, where `legalFounderId()` returns the env value only if it is a valid UUID and null otherwise (fails closed). Used in `[key]/page.tsx`, `legal/page.tsx` (as `flagOn`) and as `deps.isEnabled` in the decide and reauth routes. For a non-founder it behaves like the flag being off. AC: "With `approval-queue` ON for role prd, a signed-in user whose id is not `LEGAL_ACCEPTANCE_FOUNDER_ID` receives 404 from the decide and reauth routes and notFound from both legal pages, including when the variable is unset or not a UUID." Rows: flag on and another uid; env unset; env not a UUID; env equal to uid (enabled); flag off and env equal (disabled). Mutation: `&&` becomes `||` and the flag-on/other-uid row goes red. Flipping the flag stays operator-reserved. Prd flag state is unverified (`FLAG_APPROVAL_QUEUE` has no Doppler mirror).
2. Pre-flag check. Ruled by CTO agent, 2026-11-07: the founder-login `count(*)` is vacuous (RLS `legal_acceptance_founder_select`; `service_role` has no privilege on the table). Replace it in the records and PR body with two reads: (a) structural: `main` has no committed text and `guardLegalRequest` 404s every unknown key, so no row can have been recorded through the app for any user; (b) observable: the decide route emits one Sentry `accepted` event per recorded row (feature `legal-acceptance`, op `accepted`, `LEGAL_OPS` in `server/approval/ops.ts`); the agent reads that count itself with Sentry read access (`hr-no-dashboard-eyeball-pull-data-yourself`), expected 0 before and exactly 1 after the founder's own first acceptance; label it unverified if the work phase cannot run it. Admin SQL is the one blind spot and is stated.
3. In `guardLegalRequest`, right after the `getLegalText` try/catch: `if (legalKindCopy(key) === null) return {ok:false, status:404, error:"Not found"}` (same oracle-free 404; no Sentry in the guard; verify untouched). Rows: a registry key with no declared kind returns 404 on decide and on reauth. Mutation: delete the line, row goes red.

**C. Leaf and consumers (supersede the matching CTO 1 text).**
1. Signatures as in the export block above: `legalIndexState(kc, state)`, `legalDisplayLabel(kind, key, body)`; only `legalTextKind(key, declared)` and `legalKindCopy(key, declared)` take `declared`. A rejected-shape test row for each of: leading `#`, `-`, `*`, `>`, `+`; a double quote; a control character; non-ASCII; a line over 120 characters.
2. Mock: `vi.mock("@/lib/legal-acceptance-copy")` wrapping the two lookups with `importActual` and a `vi.hoisted` mutable `declared` map each test sets; do not register fixture keys on the real (Readonly) map. `card-kind.test.tsx` is folded into `card.test.tsx` (per-`describe` `declared`).
3. Leaf imports: `import type` only; a source-scan test asserts every import line in the leaf matches `^import type `; mutation: add a runtime import. Never import `KEY_RE` or anything from `server/`/`canonical`. Reword the header comment ("no runtime imports; type-only imports are erased").
4. `[key]/page.tsx` order: key regex, auth redirect, surface gate (flag AND founder), `getLegalText` try/catch (unknown or malformed key = plain notFound, no Sentry), then `const kc = legalKindCopy(key); if (kc === null) { reportLegalOp("kindUndeclared", null, {userId: user.id, tags: {key}}); notFound(); }` before the database read. Add `kindUndeclared` to `LEGAL_OPS` in `server/approval/ops.ts` (op `kind_undeclared`, level warn, message "Legal acceptance: a registry text has no declared card kind"); update `sentry-legal-acceptance-alert-op-contract.test.ts` and the README "Sentry ops" list. Index: filter entries right after `loadLegalTexts()` and before the flag-off notFound check; report once per undeclared key; the surface gate runs first so non-founders generate no events. Helpers live in the `lib/` leaf, never exported from `page.tsx`.
5. Card: `const kc = legalKindCopy(keyName); if (kc === null) return null;` after the `onRecorded` `useCallback` (the last hook) in `LegalAcceptanceCard` only; `badgeFor(state, kc)`, `PendingBody` and `ResolvedBody` take `kc` as a prop; delete the whole `LEGAL_COPY.accepted` key; the dialog drops the dead `label` prop, keeps `version`, and takes `answerDetail: string`; the new required `label` prop is passed at both `<LegalAcceptanceCard>` call sites in `[key]/page.tsx`; add `break-words` to the title for a 120-character label.
6. A key that later loses its declaration vanishes from page and index: accepted (the three-way equality test and the pin make it impossible without deleting the text; a deleted text's key is already `unknown_key`; rows stay for a DSAR export); record the residual once in the audit file.
7. Tests (supersede CTO 1 Tests where they differ): `collectForBan` with neutral probes (for example `["Policy text","3","4"]`), the wide `collect()` kept only for the forbidden-claims and em-dash walks; shared deck unique-string floor >= 120 (measured 132 unique / 152 total after the moves; re-measure on the final deck); `Object.keys(LEGAL_KIND_COPY.terms).sort()` equals `Object.keys(LEGAL_KIND_COPY.acknowledgement).sort()` equals a literal 16-name `EXPECTED_FIELDS`, every value a non-empty string or a function returning one; a table-driven literal wording pin of all 16 fields for BOTH kinds (including the terms `answerDetail` "checked" deviation); the DOM ban reads `document.body` (the dialog is portalled), runs over every card state and both dialog steps, and with the CLO's new strings needs NO negation stripping (the ack variant has zero matches for `/terms|accepted|accept the|updated/i`); the real-key card test also asserts the retention notice, the finality clause and the exact-text region all appear before the Yes row (CPO C2); retention token test: exact multiset equality with a generic duration regex (digits or number words incl. "twenty", "a year", weeks, "decade") over body, `cardNotice`, `requestChangesNotice`; body expected `5 years` x4 and `30 days` x2, the phrase "5 years from the date of the decision" exactly twice, `30 days` only in the A5 paragraph; `cardNotice` carries the phrase once; `requestChangesNotice` carries "5 years from the date of the decision" once; recompute the expected lists from the final bytes; a test tying the text's "30 days" to `interval '30 days'` of the `DELETE FROM public.legal_reauth_event` statement in migration 184; the dated 2030-11-07 test (CLO 4a); the first line of EVERY declared acknowledgement text has no double quote and no newline; delete the "ask counsel" bite row; the pin test asserts specific message substrings for the synthetic control rows.
8. Mutations: replace M8 with "make `legalIndexState` return `LEGAL_KIND_COPY.terms.indexAccepted` for `accepted` regardless of `kc`" (the unit test with the ack `kc` and the `page.test.tsx` index row go red); M2 caveat: exactly one lookup, `Object.prototype.hasOwnProperty.call(declared, key) ? declared[key] : null`, no second validation against `LEGAL_TEXT_KINDS.includes` (it would make M2 an equivalent mutant); M10/M11 fixtures: a third registry key in the `page.test` mock (the existing `h.secondKey` pattern) plus the hoisted `declared` map; assert no Sentry for a malformed or unknown key and exactly one `kindUndeclared` for the undeclared one. Run mutation rows in a scratch copy (`SBX=$(bash scripts/soleur-sandbox.sh new far-mut --link-node-modules)`; `rm "$SBX"` after), never on the tracked tree; the pristine suite must be green there first; node-only files single-worker, one file per invocation; jsdom rows that cannot run for memory are recorded as UNPROVEN in the PR body, never claimed.

**D. Sequencing (supersedes CTO 3 steps 1 to 4 and Phase 7 where it differs).**
1. Commit groups: (1) text, `cardNotice`, `requestChangesNotice`, note (c) and (c-2), `legal-copy.test.ts` pin updates, `registry-pins.test.ts` with key-set equality against the directory and the sha pin; (2) deck variants, consumers, the founder gate, the 404 guard, the `kindUndeclared` op and their tests (the `kind` field and the three-way equality arrive here); (3) records (audit file, addenda, `decision-challenges.md`, READMEs, ADR-319 amendment, old-plan banners); (4) the hold mechanism (hook branch, `triage-prs.sh`, tests, label). Only the final head must be green.
2. Required gates before dispatch: `sha256sum` of the text equals the `PUBLISHED` literal (hard gate); single-worker run of the three node-only files (`legal-copy.test.ts`, `registry-pins.test.ts`, `founder-acceptance-record.test.ts`); an OOM there is recorded as "unverified locally" and does not block the dispatch.
3. Dispatch discovery: `t0=$(date -u -d '-30 sec' +%FT%TZ)` before `gh workflow run`; loop at most 12 times, 10 s apart: `gh run list --workflow ci.yml --branch B --event workflow_dispatch --json databaseId,createdAt,headSha --jq "[.[]|select(.createdAt>\"$t0\" and .headSha==\"$HEAD\")][0].databaseId"`; if nothing appears, re-dispatch once, then stop.
4. Pre-ready assertions: the run's `headSha` equals `git rev-parse HEAD` equals `git rev-parse origin/<branch>`; record `MB=$(git rev-parse origin/main)` at dispatch; before ready `git fetch origin main` and, if `git diff --quiet "$MB" origin/main -- apps/web-platform knowledge-base/legal plugins/soleur .claude .github` fails, `git merge origin/main` and re-dispatch. The dispatch skips `pull_request`/`merge_group`-only jobs (`draft-light`, the affected-lane selectors, `oracle-selection`, the `oracle-index-check` family; `ci.yml` `if:` lines near 289, 391, 447, 520; not every `if:` was mapped, treat as unverified beyond those); required checks per `scripts/required-checks.txt`: `test`, `dependency-review`, `e2e`, `skill-security-scan PR gate`, `cla-check`, `cla-evidence`. Only the ready run proves the PR-level `test` aggregator on the merge ref; hence a ready run still follows.
5. `soleur:review` runs BEFORE the final push and dispatch (a review fix after the dispatch voids it), scoped to the delta with `user-impact-reviewer`, `security-sentinel` (founder gate) and `test-design-reviewer`; the single-user-incident threshold requires it.
6. Follow-up issues (S5 published trio, S6 terms "updated" wording and the reconcile of "a few minutes" vs 10 minutes, the base-SHA pin guard deferral) and a #12080 comment restating its trigger plus CLO 4(b)(c) are filed at the START of Phase 5 so the records cite real numbers.
7. PR body: keep `Ref #12197` and `Ref #12011`; write no bullet starting with `Operator:` or `Operator <run|create|provision|configure|paste|copy|verify|confirm|check|file|set|install|upload|audit|click>`, `manual gate` or `post-merge operator`; no `T+N<unit> ... verb` or `AC-PM<N>` lines (`ship-operator-step-gate.sh` GROUP_A). If one is unavoidable, put `Refs #N` (plural) on the same or an adjacent line pointing to an OPEN issue whose body contains `deferred-automation` or `automation gap`. The earlier plural `Refs` instruction is withdrawn.
8. AC8 is scoped to what `FORBIDDEN_CLAIMS` walks (the text body raw, the shared deck, both kind variants, `signOff`); records are exempt where they negate (they must still make no "reviewed by counsel" or "legally binding" claim).

**E. OTP email.** Ruled by CTO agent, 2026-11-07: do not edit `apps/web-platform/supabase/templates/magic-link.html` (shared login template; "Enter this code to sign in to your Soleur account", 10-minute expiry; names neither terms nor acceptance; the hosted setting is unverifiable from the repo). Add one scope-out line to the audit file and PR body: "The emailed code uses the shared sign-in template, which says 'sign in to your Soleur account' and '10 minutes'. The card says what the code is for. Not changed here."

**F. Simplicity dispositions.** Accepted: fold `card-kind.test.tsx` into `card.test.tsx`; a single authoritative Guard Contract; "No C4 impact: no new element" citing the architecture review that read `model.c4` (plus one ADR-319 amendment paragraph for the declared card kind and the founder-only gate); residual risks written once in the audit file and once in the PR body, addenda link to it; old plan banners; AC8 scoped; one floor set; the S5/S6 issues first. Rejected with reason: dropping CPO and spec-flow (both found real defects: the merge path, the DOM ban contradiction, the probe contamination); dropping `soleur:review` (CTO: required by the threshold; moved before the final push); the manual-mutation budget is narrowed only as the CTO ruled (sandbox copy, jsdom rows may be recorded UNPROVEN).

### CPO conditions (advisory; `signOff.cpo` stays null)

C1 positive-first wording: done (CLO 1). C2 real-key DOM test asserts the retention notice, the finality clause and the body before the Yes row: added (C7 above). C3 label guard: done (CTO C1 regex). C4 ninth residual risk: done. C5: exposure to non-Jikigai accounts is now blocked mechanically by the founder gate, and the human-lawyer review plus S5 remain preconditions for widening it. C6: CPO condition D ("do not change the card in this PR") is SUPERSEDED by the operator's instruction to fold #12344, not satisfied; carry the product note into the PR body: label the #12197 outcome "path verified with an acknowledgement text", never "terms acceptance verified"; the terms variant has no live text and is moved but unexercised (owner S6). C7 merge barrier: done (CTO A). C8 roadmap: CLO 8. C9: before `signOff.cpo` is ever set (a later PR), the CPO reviews the rendered acknowledgement card (DOM text with the dialog open); this PR attaches the real-key rendered DOM text to the PR body for that review.

### gdpr-gate (plan mode, 2026-11-07)

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.** Path scan complete: the planned files match the canonical regulated-data regex only through the two API route files `apps/web-platform/app/api/legal-acceptance/[key]/decide/route.ts` and `.../reauth/route.ts` (founder gate and 404 guard) and `server/legal-acceptance/reauth.ts`; no migration or `.sql` is edited. The five v1 checks have nothing to fire on (no new column, no new PII table, no FK, no non-EEA vendor, no Art. 9 column). No Critical finding, so no `compliance-posture.md` write and no `compliance/critical` issue. Substantive Art. 5(1)(e), 6(1)(f), 13, 17(3)(e) positions are the CLO's, already recorded.

## Implementation Phases

**Phase 0 (setup).** Confirm cwd; `git fetch`. Re-verify the premises: text not on main (`git ls-tree`), `ci.yml` has `workflow_dispatch`, PR #12342 still DRAFT. The `select count(*) from public.legal_acceptance;` check is NOT run by the agent: it is the founder's own-login check before any flag.

**Phase 1 (RED).** Before touching product files, write the new tests and run only the node-only files once with the single-worker flags; they must fail for the right reasons (placeholder still in the text, pin absent, kind map absent). Cite the output in the PR body (`cq-write-failing-tests-before`).

**Phase 2 (text and notices).** Apply A1 to A8 by exact OLD/NEW; verify each OLD occurs once before and each NEW once after (a small script in the scratchpad, not committed). Edit the card notice, request-changes notice and the note sections (c), (c-2) together. Check: LF only, printable ASCII, markdownlint on the committed path, `sha256sum` equals loader `textHash`.

**Phase 3 (deck, consumers, label).** Implement the CTO mechanism and the CLO table. `tsc` (in CI) is the sweep for unmigrated consumers.

**Phase 4 (tests).** Rewrite per the CTO verdicts and the deepen-plan block C: delete guard tests, add always-on checks, `registry-pins.test.ts`, the third-table pin, `surface.test.ts`, route rows, card and page tests with the hoisted `declared` mock, the new ack card test. Mutation rows: run the node-side ones once each and cite; for the jsdom ones (M7, M8, M10 to M12) run single-file with `--maxWorkers=1`, one at a time, and say in the PR body which were run.

**Phase 5 (records).** FIRST file the follow-up issues (S5, S6, the base-SHA pin deferral) and comment on #12080 (CLO 4b, 4c, trigger) so the records cite real numbers; then the CLO ruling audit file; addenda (attestation, counsel-review, LIA, PA-40, register item 17, compliance-posture row, ADR-319 dated amendment); `texts/README.md`, `server/legal-acceptance/README.md`, `test/feature-map.md`; held-draft language removed. File the follow-up issues (S5, S6 in Scope Check) with a roadmap milestone.

**Phase 6 (holds, PR body).** Rewrite the old plan's `## Operator Holds` and `## HOLD procedure`; append supersede rows to `decision-challenges.md`; rewrite the PR title and body (CTO step 7).

**Phase 6.5 (review).** `soleur:review` on the delta (user-impact-reviewer, security-sentinel for the founder gate, test-design-reviewer) BEFORE the final push.

**Phase 7 (CI and ready).** Add and verify the `parked` label, then the deepen-plan block D steps 2 to 4, then CTO 3 steps 5 to 8 in order (dispatch, discovery, pass criteria, pre-ready assertions, ready). Stop after `full-decided`; do not merge.

## Files to Create

- `apps/web-platform/test/legal-acceptance/registry-pins.test.ts`
- `apps/web-platform/test/legal-acceptance/card-ack.test.tsx` (real `founder-acceptance-record` key: DOM ban over `document.body` in every state and both dialog steps, retention notice, finality clause and exact-text region before the Yes row, undeclared key renders nothing)
- `apps/web-platform/server/legal-acceptance/surface.ts` (`isLegalSurfaceEnabled`, `legalFounderId`) and its test (`apps/web-platform/test/legal-acceptance/surface.test.ts`)
- `knowledge-base/legal/audits/2026-11-07-clo-ruling-founder-acceptance-record-12197.md` (the persisted CLO ruling, both rounds, verbatim, with the stand-in statement, the 12 residual risks, the stored-`accept` sentence, the OTP scope-out line and the vanish-on-undeclared residual)

## Files to Edit

Product code (work phase):
- `apps/web-platform/server/legal-acceptance/texts/founder-acceptance-record.md` (A1 to A8; version unchanged)
- `apps/web-platform/lib/legal-acceptance-copy.ts` (kind map and four functions, 16 members moved, `exactTextHeading`, `dialog.codeBody`, `cardNotice`, `requestChangesNotice`, `signOff.clo`, header comment)
- `apps/web-platform/components/approvals/legal-acceptance-card.tsx`, `apps/web-platform/components/approvals/legal-reauth-dialog.tsx`
- `apps/web-platform/app/(dashboard)/dashboard/approvals/legal/page.tsx`, `apps/web-platform/app/(dashboard)/dashboard/approvals/legal/[key]/page.tsx`
- `apps/web-platform/app/api/legal-acceptance/[key]/decide/route.ts`, `apps/web-platform/app/api/legal-acceptance/[key]/reauth/route.ts` (`deps.isEnabled` uses the founder gate), `apps/web-platform/server/legal-acceptance/reauth.ts` (`guardLegalRequest` null-kind 404)
- `apps/web-platform/server/approval/ops.ts` (`kindUndeclared` op) and the LEGAL_OPS contract test `sentry-legal-acceptance-alert-op-contract.test.ts` plus the README "Sentry ops" list
- Tests: `founder-acceptance-record.test.ts`, `legal-copy.test.ts`, `card.test.tsx`, `page.test.tsx`, and the decide/reauth route tests (`routes.test.ts`) in `apps/web-platform/test/legal-acceptance/`; `canonical.test.ts` and `registry-embedding.test.ts` only if the byte change touches a fixture (verify; expected no change)
- Docs: `apps/web-platform/server/legal-acceptance/texts/README.md` (pin rule, stored-`accept` sentence), `apps/web-platform/server/legal-acceptance/README.md`, `apps/web-platform/test/feature-map.md`
Hold mechanism (CTO A, commit 4):
- `.claude/hooks/ship-operator-step-gate.sh` and `ship-operator-step-gate.test.sh` (merge branch; a guardrail TIGHTENING reviewed like any hook change), `plugins/soleur/skills/drain-prs/scripts/triage-prs.sh` and its test
Records (work phase, outside `plans/`/`specs/`):
- `knowledge-base/legal/audits/2026-11-founder-legal-acceptance-dsar-and-notice-note.md` (sections (b), (c), (c-2)), `2026-11-founder-legal-acceptance-attestation.md` (addendum, block stays blank), `2026-11-counsel-review-12011.md` (pointer), `knowledge-base/legal/legitimate-interest-assessments/2026-11-founder-legal-acceptance-lia.md` (addendum), `knowledge-base/legal/article-30-register.md` (PA-40 (f), item 17(a)), `knowledge-base/legal/compliance-posture.md` (row), `knowledge-base/engineering/architecture/decisions/ADR-319-legal-acceptance-record.md` (ONE dated amendment, never editing the dated text; see the ADR section)
Plans/specs:
- `knowledge-base/project/plans/2026-11-07-feat-founder-acceptance-record-text-draft-plan.md` (the two superseded banners only)
- `knowledge-base/project/specs/feat-one-shot-12197-founder-acceptance-record-text-draft/decision-challenges.md` (rows appended in the planning phase; the work phase appends further rows only), `session-state.md`
- The PR title and body, and the `parked` label on PR #12342 (not files)

Glob check: the existing paths were taken from `git ls-files`/direct reads; the files under Files to Create do not exist yet by design.

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

## Review round 1 rulings (2026-11-08)

A thirteen-seat review of `a22578f5ad` found no P1 in the text and one P1 on the merge barrier. The CTO and the CLO ruled every finding that was a decision (`Ruled by CTO agent, 2026-11-08` / `Ruled by CLO agent, 2026-11-08`); the rows are in `decision-challenges.md` and the CLO's in the ruling file. Strength of the sign-off is unchanged: a v1 internal position standing in for counsel on the operator's instruction, human review owed.

| Item | Ruling |
|---|---|
| T1 | The barrier exists only on this branch (origin/main: 0 occurrences), so DRAFT with the `parked` label is the end state; a ready flip only inside a CI window, back to draft once green (the dispatch route also gives the full battery without leaving draft); the PR body calls the label a guardrail, not an access control |
| T2 | Harden the hook's text matcher inline (quoted payloads, `gh` boundary, case, unfused numbers, `/pull/N`, `--repo`, whole-token `--disable-auto`, unresolved targets held while any PR is parked, label delete/PUT/graphql, `timeout` and fail closed, no-cwd, incident row); the rest goes to ONE follow-up |
| T3 | `hold-gate-eval.sh` refuses `web-acceptance` gates on `WA_NON_TERMS_KEYS`; cross-checked in `registry-pins.test.ts`; ADR-319 says what is enforced |
| T4 | Founder compared first, once-per-process config report, decide route re-checks the gate per request, README says `service.ts` is deliberately ungated |
| T5 | Kind pinned per key, comments say every render, `data-kind`/`data-key`, `counsel` token restored, texts README how-to, every-text loops, one probe per alternative, shared `TERMS_PRESUMING`, dated rows |
| L1 | A5 points at "the 5 years stated under How long it is kept" |
| L2 | The text discloses the monitoring copies and says they are outside the 5 years (90 days only as the Privacy Policy's statement; on-host copy unmeasured) |
| L3 | Scope sentence unchanged |
| L4 | Hold clause in `requestChangesNotice` and DSAR note (c) |
| L5 | Ack marker: "finished trying to send ... (it does not show that monitoring received it)" |
| L6 | The 30-day purge runs on every intent; markers across the records; register 17(b), (c), (f) closed in the cell as v1 positions |
| L7 | Published trio unchanged, disclosed in the PR body; #12365 stays the precondition for any non-operator founder |
| L8 | Residual risk 13 and a per-hash pre-flag query in the ruling file |

### Fix round 2 (2026-11-08): the fix-commit round over `a22578f5ad..9f3cb5fba3`

Three seats (security, test design, data integrity) re-read the round-1 fixes. One P1 and the findings below, all fixed in the commits after `9f3cb5fba3`; the text bytes and the sha256 `10d283e0...` did not change.

| Finding | Disposition |
|---|---|
| Security P1-1: the rewritten hook denied commit messages, echoes, greps and `--body` text that only MENTION `gh pr merge N` | `gh` is recognised at command position only (awk statement splitter); the quoted payload of `bash -c` / `eval` still denies; 52 new rows (floor 154) |
| Security P2-1: flag values read as targets | value-taking flags and their values are skipped; a variable or branch-name target is still held while any PR is parked |
| Security P2-2: `gh api` PATCH/PUT/DELETE on `issues/N` or `pulls/N`, `labels/parked`, four more GraphQL names | covered |
| Security P3 (continuations, `2>&1`, `#N`, failed current-branch read, `$` targets, incident id, triage case and `parked` flag) | fixed; the incident id is `parked-merge-barrier` |
| Test design: 21 survivors | rows added (hook, hold-gate, drain-prs, TS); three accepted as equivalent (timeout shape check, redundant wrapper group, `\b` after `verif`) |
| Data integrity P2-1, P2-2 | DSAR "Who can see it" and compliance-posture markers (append-only) |
| Data integrity P3 | markers, the PA-40 cross-reference, the verbatim L2 strings in the ruling file; P3-1 and P3-2 (wording) accepted with no text change |

### Final bounded hook patch (2026-11-08): the one verification pass over the rewritten barrier

One verification pass re-drove the rewritten hook (about 480 command variants, stub `gh`). Every fix-round-1 item held. It found one P2 fail-open, one P2 false deny and eight P3 shapes. The patch below is the LAST hook-hardening round: the hook is a best-effort guardrail, server-side enforcement and the other merge sites are tracked in #12396, and no further hardening rounds are planned.

| Finding | Disposition |
|---|---|
| P2-1: a nested double quote inside `"$(...)"` or a backtick span ended the outer span early, so `out="$(gh pr merge "7" --squash)"` was allowed | the walker scans a substitution to its matching `)` (nested quotes included) or backtick, queues the body, and an unbalanced span fails closed while any PR is parked |
| P2-2: an escaped backtick or `\$(` inside double quotes (markdown code spans in a commit or PR text) was denied | a backslash pair is literal text and is never read as a substitution |
| P3-1 wrapper basename (`/bin/bash -c`, `/usr/bin/env gh`) | the prefix test accepts the word or its basename |
| P3-3 `--disable-auto` as the value of a value-taking flag | one pass skips flag values before it looks for the disarm flag |
| P3-4 leading-zero PR number (`012342`) | normalised before the label read |
| P3-7 GraphQL mutation names matched inside REST body fields; a query read from a file or stdin unreadable | names are read only for a `graphql` call; `query=@file` and `--input` hold while any PR is parked |
| P3-8 `xargs` before a gh write (targets come from stdin) | held while any PR is parked; `xargs gh pr view` (a read) is not held |
| P3-9 `gh pr merge N --help` | allowed |
| P3-2, P3-5, P3-6, P3-10 (unlisted or option-valued wrappers, a shell fed from a heredoc or `<(...)`, ANSI-C quoting with an escaped quote, the raw 200-character incident snippet) | ACCEPTED LIMITS, stated in the hook header and pinned as deliberate allows in the test suite; superseded by #12396 |

## Observability

No new route or infrastructure. Server-side code added in this PR: the founder gate (`server/legal-acceptance/surface.ts`) and the null-kind guard in `guardLegalRequest` (`hr-observability-as-plan-quality-gate`, `hr-observability-layer-citation`). The runtime signals, all through `reportLegalOp` (pino line mirrored to Sentry, feature `legal-acceptance`):

- `kindUndeclared` (op `kind_undeclared`, warn, unpaged, `tags.key` = the registry key): a registered text with no declared card kind. Fires on every render of the card page or the index, after the surface gate. The routes (decide, reauth) answer the same oracle-free 404 without an event.
- `storeFailed` with `tags.stage = config` (the existing op the check endpoint raises for a malformed value): fires once per process from `isLegalSurfaceEnabled` when the `approval-queue` flag is ON and `LEGAL_ACCEPTANCE_FOUNDER_ID` is unset or not a UUID (CTO ruling T4, 2026-11-08). Never carries the user id or the variable's value. This, not `kind_undeclared`, is the detector for a missing founder id: `kind_undeclared` fires only after the gate has passed.

```yaml
liveness_signal:
  what: the legal-acceptance copy, registry and surface guards run in CI on every PR touching apps/web-platform
  cadence: per PR (test-webplat shards)
  alert_target: CI check status on the PR
  configured_in: .github/workflows/ci.yml
error_reporting:
  destination: Sentry via reportLegalOp (feature legal-acceptance); ops kind_undeclared (warn, tags.key) and store_failed (stage config)
  fail_loud: the page calls notFound() after the Sentry mirror, so an undeclared key is a 404 plus an event, never a silent card; a closed surface with the flag on reports the config fault once per process
failure_modes:
  - mode: a registered text has no declared card kind
    detection: layer 2 (pino to Sentry breadcrumb mirror) and layer 5 (Sentry release context): the kind_undeclared event, tagged feature legal-acceptance and op; at build time registry-pins.test.ts red in CI
    alert_route: Sentry issue for feature legal-acceptance (unpaged by design: founder-only volume); CI red on the PR
  - mode: the flag is on but LEGAL_ACCEPTANCE_FOUNDER_ID is unset or malformed, so the founder gets a 404 and the surface looks dormant
    detection: layer 2 and layer 5: the store_failed event with tags.stage config, once per process (surface.test.ts pins the once-per-process report, the no-user-id payload and the silent flag-off case)
    alert_route: Sentry issue for feature legal-acceptance, op store_failed
  - mode: the null-kind guard or the founder gate hides the surface from the founder by mistake
    detection: surface.test.ts, routes.test.ts and page.test.tsx rows in CI (env unset, not a UUID, equal, flag off, live intent after the gate is off); a real fault is the two events above
    alert_route: CI red on the PR; Sentry issue for feature legal-acceptance
  - mode: text bytes changed with no pin or version change
    detection: registry-pins.test.ts red (loader hash and independent file hash)
    alert_route: CI red on the PR
logs:
  where: CI run logs; Sentry (feature legal-acceptance)
  retention: GitHub Actions default; Sentry plan default (90 days stated in the register, unmeasured for this organisation)
discoverability_test:
  command: grep -c kind_undeclared apps/web-platform/server/approval/ops.ts
  expected_output: "1"
```

## Encryption Posture

Not triggered: no persistent store, no new connection, no `.tf`, migration, cloud-init or compose file in the plan. The text only describes stores that already exist (migrations 184 and 185); their encryption posture is unchanged and not claimed in the text.

## Architecture Decision (ADR/C4)

### ADR
ONE dated amendment `## Amendment 2026-11-07 (#12197)` appended to ADR-319 (the pre-existing dated text is never edited; ADR-319 uses `## Considered Options`, not "Alternatives Considered", and dated amendments with a "Superseded by this amendment" list). Decisions: the retention period changes from "unconfirmed proposal (life of the instrument plus 5, cap 10)" to "5 years from the date of the decision, extended while a claim, complaint or inquiry is open; CLO-agent v1 ruling 2026-11-07, human-lawyer review owed"; the rejected variable-start period and the rejected front-matter `meaning:` option (Option B) are recorded here; a text with no declared card kind renders no card (stated as an amendment decision, not as a record Property, since Properties 1 to 3 are record invariants); the card surface is founder-only through `LEGAL_ACCEPTANCE_FOUNDER_ID` while the flag is global. The "Superseded by this amendment" list names exactly: Decision "Retention and erasure" (the period); Consequences (the counsel gate for wording and period); PR-C Decisions (the bullet saying the placeholder is "to be confirmed by counsel"), PR-C Enabling conditions ("Counsel's retention decision is made and the (c-2) notice placeholder is replaced") and PR-C Still open ("Retention and redaction", "Counsel review"); PR-D Still open (the retention clause in "Published documents"). It says the enabling condition is met ONLY by the CLO-agent stand-in as a v1 position, cites the persisted audit file (not chat), records the AP-009 deviation as a bounded, documented deviation (only expired `legal_acceptance` rows, one controlled database-owner action, hold-aware; modelled on ADR-119's carve-out), carries a `### Diagram` sub-heading "no change" and a `### Principle Alignment` note (AP-009 tension, AP-021 aligned), keeps status `adopting` and adds #12197, #12344 and #12080 to `related`. This is a Phase 5 task, not a follow-up issue.

### C4 views
No C4 impact: no new element. The architecture review in deepen-plan read `model.c4` and confirmed `platform.infra.legalAcceptanceStore` already names `legal_acceptance`, `legal_reauth_event` and `legal_acceptance_ack` with no retention period and that the `webapp -> legalAcceptanceStore` edge is unchanged; the hook branch and the founder gate add no element. Actors/systems/relationships enumerated for this change: the external human actor is the founder (already modeled as the approval-card user); external systems: none new (the email-code sender and Sentry were modeled for PR-C and PR-D); data stores: `legal_acceptance`, `legal_acceptance_ack`, `legal_reauth_event` (already modeled); access relationships: unchanged. `c4-count-parity` and the C4 validation tests run in CI and are not load-bearing for this change.

### Sequencing
None: the decision is true on merge (the deletion path is the honest "not yet built" qualifier, with #12080 as the hard stop).

## User-Brand Impact

- **If this lands broken, the user experiences:** the founder opens `/dashboard/approvals/legal` (flag on) and sees a card for the acknowledgement text that still says "these terms" or "Accept the updated Founder acceptance record?", or a retention period on the card that differs from the text, then gives a final Yes that cannot be taken back; or a card renders for a text with no declared meaning.
- **If this leaks, the user's data is exposed via:** the text holds no personal data; the exposure vector is the pseudonymous account uuid, the code-request records (which outlive erasure) and the Request-changes note (up to 1000 characters, may carry third-party personal data) that the text describes. A text that understated who can read them or how long they last would mislead the data subject. The period is a commitment with no enforcing code until #12080.
- **Who can answer (scope):** the `approval-queue` flag is global (identifier `role:prd`, no per-user targeting). This PR therefore adds a server-side founder gate (`LEGAL_ACCEPTANCE_FOUNDER_ID`, fails closed) so that only the founder can reach the card or the routes; the flag flip, the merge and widening the gate stay Operator-reserved.
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
**Agents invoked:** soleur:product:cpo, soleur:product:spec-flow-analyzer (deepen-plan, 2026-11-07)
**Skipped specialists:** none
**Pencil available:** N/A (no new layout; the change is copy strings and a null-render guard inside the existing screens covered by `knowledge-base/product/design/approvals/founder-approval-cards.pen` wireframes 10 to 16; the mechanical UI-surface override matches the edited `components/approvals/*.tsx` paths, so deepen-plan must decide whether the tier is raised to blocking and a wireframe note is needed; the `.pen` text still says "these terms", a design artifact, not blocking per CTO)

#### Findings
Copy-only change to an existing, wireframed flow; no new interactive surface. Flag for deepen-plan: the override match, and CPO review of the acknowledgement wording and the `Acknowledge "<title>"?` title shape.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Spawn the CLO to rule on (a) the final wording of apps/web-platform/server/legal-acceptance/texts/founder-acceptance-record.md" [brief] | Rulings, CLO A (edits A1 to A8); Phase 2; Files to Edit: the text file | mapped |
| 2 | "(b) the concrete retention period (the #12080 question); record it as \"Ruled by CLO agent, <date>\" in the PR" [brief] | Rulings, CLO B; PR body (CTO step 7) | mapped |
| 3 | "The card-copy \"terms\" problem in #12344 is a technical/legal-copy fork, not an operator question: the CTO (technical) and CLO (legal wording) rule on it, preferring making the Yes/accepted wording depend on the text key if it keeps the pinned deck test honest; fold it into this PR (close it via the PR body with Closes only if fully resolved)" [brief] | Rulings, CTO 1 and CLO C; Phase 3; PR body `Closes #12344` conditional | mapped |
| 4 | "replace the \"[period to be confirmed by counsel]\" placeholder in the text file AND in LEGAL_COPY.cardNotice with the ruled period" [brief] | Phase 2 (A4, card notice, request-changes notice, note (c)/(c-2)) | mapped |
| 5 | "delete the CI-only merge guard, its real-data control and the retention-clause test in apps/web-platform/test/legal-acceptance/founder-acceptance-record.test.ts" [brief] | Rulings, CTO 4; Phase 4.1 | mapped |
| 6 | "add the published {version: sha256} pin and the exact key set" [brief] | Rulings, CTO 2; Guard 1; Files to Create: `registry-pins.test.ts` | mapped |
| 7 | "bump version if the bytes changed after a first merge (it has not merged yet, so likely no bump; verify)" [brief] | Rulings, CTO 5; Research Reconciliation row 1 | mapped |
| 8 | "run the full CI battery (the local affected gate was never completed; rely on CI, NOT local full runs, due to memory pressure)" [brief] | Rulings, CTO 3 steps 3 to 5; Phase 7 | mapped |
| 9 | "only then mark the PR ready" [brief] | CTO 3 step 8; Phase 7.3; Operator Holds, rewritten | mapped |
| 10 | "Out of scope, stays with #12197 and the operator: the founder's first acceptance, the post-deploy registry smoke, the approval-queue flag. Before any flag: select count(*) from public.legal_acceptance; must be 0." [brief] | Overview; Non-goals; Operator Holds, rewritten; AC10 | mapped |
| 11 | "Put the rulings verbatim into the plan. Note: the CLO ruling stands in for counsel only because the operator said so; the plan must state that and flag residual risk plainly." [brief] | Rulings (verbatim); the opening note; Rulings, CLO D residual risks | mapped |
| 12 | "Persist every decision as a row of the `| Item | Class | Ruling |` table in knowledge-base/project/specs/feat-one-shot-12197-founder-acceptance-record-text-draft/decision-challenges.md" [brief] | `decision-challenges.md` rows appended in the planning phase; AC11 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Files to Edit: `founder-acceptance-record.md` | asks 1, 4 | asked |
| Files to Edit: `legal-acceptance-copy.ts` (notices) | "replace ... in LEGAL_COPY.cardNotice" (ask 4) | asked |
| Files to Edit: `founder-acceptance-record.test.ts` | ask 5 | asked |
| Files to Create: `registry-pins.test.ts` | ask 6 | asked |
| Files to Edit: the DSAR note sections (b), (c), (c-2) | ask 4 | inferred — justification: `legal-copy.test.ts` pins both notices byte for byte to that note, so the CI battery (ask 8) is red without the edit |
| Files to Edit: `legal-acceptance-copy.ts` (kind map, 16 moved members, `exactTextHeading`, `dialog.codeBody`), card, dialog, both pages | "making the Yes/accepted wording depend on the text key" (ask 3) | asked |
| Files to Create: `card-ack.test.tsx`; Files to Edit: `card.test.tsx`, `page.test.tsx`, `legal-copy.test.ts` | ask 3 ("keeps the pinned deck test honest") | asked |
| `legalDisplayLabel` and the `label` prop | ask 3 | inferred — justification: the CLO's acknowledgement titles quote the label and a key-derived label ("Founder acceptance record") reads as terms; CLO C asked for it and the CTO ruled it cheap |
| Fail-closed render for an undeclared key (null kind, 404, Sentry mirror) | ask 3 | inferred — justification: the CLO ruled "no default is permitted"; without it the deck would claim terms for a future text |
| `legal_reauth_event` column pin in the existing test | ask 5 ("retention-clause test" replaced) | inferred — justification: CLO edit A5 makes the text describe that table, and the existing pins exist so the text is reviewed whenever a described table changes |
| `signOff.clo` string and the test pin | "stands in for counsel sign-off" (ask 2 context, Standing) | inferred — justification: the deck test pins `signOff` to nulls; recording the stand-in is the CLO D ruling and avoids a record that contradicts itself |
| Files to Create: the CLO ruling audit file; Files to Edit: attestation, counsel-review pointer, LIA, register, compliance posture, ADR-319 | ask 2 ("record it as \"Ruled by CLO agent, <date>\"") | inferred — justification: CLO B and D name these records as superseded by the period; leaving "unconfirmed proposal" in the register and ADR contradicts the shipped text (Art. 5(2) accountability) |
| ADR-319 dated amendment | — | inferred — justification: plan Phase 2.10 makes the ADR amendment a deliverable of the plan that changes a recorded decision |
| Files to Edit: `texts/README.md`, `server/legal-acceptance/README.md`, `test/feature-map.md` | ask 5 | inferred — justification: CTO 4 requires the held-draft prose to be removed or the docs describe a guard that no longer exists |
| Files to Edit: the old plan's `## Operator Holds` and `## HOLD procedure` | ask 9 | inferred — justification: `hold-gate-eval.sh` treats any `Operator-reserved:` line in a plan of this branch as standing, so ship would refuse while the old holds read as unresolved (CTO 3) |
| Phase 5 follow-up issues S5 (published trio) and S6 (terms "updated" wording, base-SHA pin guard) | — | inferred — justification: `wg-when-deferring-a-capability-create-a` requires a tracking issue for every deferral the CLO and CTO named |
| Phase 7 (dispatch `ci.yml`, then ready) | asks 8, 9 | asked |
| Founder gate (`surface.ts`, route/page wiring) and the null-kind 404 in `guardLegalRequest` | "the approval-queue flag" stays out of scope (ask 10) | inferred — justification: the user-impact reviewer's BLOCKING finding 2: the flag cannot target one user, so merging a text that any signed-in user could answer defeats "Out of scope ... the approval-queue flag"; the gate keeps that flag untouched while making its exposure founder-only (CTO B) |
| `parked` label, hook branch in `ship-operator-step-gate.sh`, `triage-prs.sh` tier | "only then mark the PR ready" (ask 9) | inferred — justification: user-impact BLOCKING finding 1: after ready, AGENTS rule `wg-after-marking-a-pr-ready-run-gh-pr-merge` and a pre-allowed `gh pr merge` would merge it; merge is not part of the ask (CTO A) |
| `kindUndeclared` op and contract test, `LEGAL_OPS` README line | ask 3 | inferred — justification: the fail-closed render needs a Sentry mirror (`cq-silent-fallback-must-mirror-to-sentry`) and the op contract test enumerates `LEGAL_OPS` |
| Dated 2030-11-07 test, stored-`accept` sentence, #12080 acceptance criteria | ask 2 | inferred — justification: CLO 4 and 5 make these the safeguards that replace a build-state clause in the notices |

Note on S5 (published trio, NOT folded in): the CLO says the Privacy Policy 4.17, GDPR Policy 3.19 and Data Protection Disclosure 2.3(aj), 5.3(a), 10.3(l) (with mirrors, SHA pins and the DSAR lockstep gate) must change before the card is answerable. Five CI gates and public wording are a separate cycle, and the card is answerable only when the operator-controlled flag is on, so a tracking issue makes the trio a precondition of the flag being on for anyone but the operator. This is a scope call: the plan takes this default and records it in `decision-challenges.md` as an operator (scope) row the operator may redirect.

### Split Assessment

- Subsystems touched: 4 — `apps/web-platform`, `knowledge-base`, `.claude`, `plugins/soleur`
- Planned files: 40 (6 create, 34 edit) | Estimated changed lines: about 1700 (deck and consumers about 350, founder gate and routes about 150, tests about 700, hook and triage about 200, text and records about 300)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — over all three thresholds, kept whole on purpose. The brief orders #12344 folded in and the notice edits are byte-pinned to the deck test. The seam considered is the hold mechanism (`.claude` hook, `triage-prs.sh`, tests; about 8 files) as its own earlier PR. Rejected: the `parked` label is useless without its enforcement and the barrier must exist BEFORE `gh pr ready`, so splitting would put "ready" behind another full merge cycle the operator did not ask for. If the operator prefers the split, the hold mechanism is commit group 4 and moves out without touching the rest. Recorded as an operator (scope) row in `decision-challenges.md` with this default.

## Acceptance Criteria

- [ ] AC1: the text file contains each NEW of A1 to A8 exactly once and no OLD; `version: 2026-11-07`; LF-only printable ASCII; `markdownlint-cli2` on the committed path exits 0; `sha256sum` equals loader `textHash` and the `registry-pins.test.ts` pin (cite the value in the PR body).
- [ ] AC2: `grep -c '\[period to be confirmed by counsel\]'` over the text, `legal-acceptance-copy.ts`, the DSAR note and the tests prints 0 everywhere except inside superseded markers.
- [ ] AC3: `cardNotice` equals the final CLO string (rights sentence included) and `requestChangesNotice` ends "kept for 5 years from the date of the decision, even if you later delete your account."; both equal the note's (c-2) and (c) blockquotes byte for byte.
- [ ] AC4: the merge guard describe, "CI is visible", "real data control", "retention clause" and the registry tripwire are gone; the always-on unfinished-marker check, the retention token test, the 30-day tie test, the dated 2030-11-07 test, the `legal_reauth_event` 12-column pin and `registry-pins.test.ts` exist and pass in CI; no `skipIf(!process.env.CI)` remains in the file.
- [ ] AC5: `LEGAL_COPY` no longer exposes the 16 moved members (and no `accepted` key); `tsc` (CI) is clean; the consumers use `legalKindCopy`, `legalIndexState(kc, state)`, `legalDisplayLabel(kind, key, body)`; an undeclared key renders no card, 404s the page, mirrors `kindUndeclared` to Sentry after the surface gate, and 404s decide and reauth in `guardLegalRequest`.
- [ ] AC6: the acknowledgement variant and the shared deck have zero matches for `/\bterms?\b|\baccept(ed|s|ance)?\b|accept the|\bupdated\b/i` under the neutral probe set and in the DOM (`document.body`, every state, both dialog steps) with NO negation stripping and no allowlist; `dialog.codeBody` is the CLO string; the real-key card shows the retention notice, the finality clause and the exact-text region before the Yes row.
- [ ] AC7: `LEGAL_COPY.signOff` is `{cpo: null, clo: "Ruled by CLO agent, 2026-11-07: v1 internal sign-off, not external counsel"}`; `PROVISIONAL` is `true`; the attestation block cells are unchanged (blank); the addenda say "stand-in", never "counsel reviewed".
- [ ] AC8: scoped to what `FORBIDDEN_CLAIMS` walks (the text body, the shared deck, both kind variants, `signOff`): no match; records are exempt where they negate but make no "reviewed by counsel" or "legally binding" claim.
- [ ] AC9: a `workflow_dispatch` run of `ci.yml` on the final head SHA (discovered by `createdAt` and `headSha`, equal to `HEAD` and `origin/<branch>`) has `conclusion=success`, the `test-webplat` shards `success` (not `skipped`) and `test` `success`; `soleur:review` ran before the final push; then the PR is marked ready; the ready run's verdict is `full-decided` and green. No local full test or build was run.
- [ ] AC10: PR #12342 carries the `parked` label BEFORE it is marked ready (verified with `gh pr view 12342 --json labels`), a non-DRAFT/HOLD title, a body with the "Parked" banner, the stand-in statement and the 12 residual risks, the new sha256, the OTP scope-out line, the CP2 ceiling is NOT edited, `Closes #12344` only if every CLO C row landed, and the label "path verified with an acknowledgement text"; the PR is not merged and not enqueued; AGENTS rule `wg-after-marking-a-pr-ready-run-gh-pr-merge` is expressly overridden in the body.
- [ ] AC11: the old plan's `## Operator Holds` and `## HOLD procedure` are replaced by the two superseded banners; `hold-gate-eval.sh --plan` is rc 0 on the old plan and rc 3 on this one; `decision-challenges.md` carries a row for each ruling and each operator-reserved item; no flag, Doppler, Supabase production or `legal_acceptance` row was touched.
- [ ] AC12: tracking issues exist for S5 (published trio, a precondition for widening the flag beyond the operator) and S6 (terms "updated" wording, the "a few minutes" vs 10 minutes reconcile, the base-SHA pin guard), filed at the start of Phase 5 with re-evaluation criteria and a roadmap milestone; #12080 carries a comment restating its trigger (before the first non-Jikigai founder, or before any row is 4 years old) and CLO 4(b)(c).
- [ ] AC13: with `approval-queue` ON for role prd, a signed-in user whose id is not `LEGAL_ACCEPTANCE_FOUNDER_ID` receives 404 from the decide and reauth routes and notFound from both legal pages, including when the variable is unset or not a UUID (rows and `&&`-to-`||` mutation per CTO B1).
- [ ] AC14: `ship-operator-step-gate.test.sh` denies `gh pr merge` (plain, `--auto`, chained) and `--remove-label parked` while the PR carries `parked`, allows `--disable-auto` and an unlabelled PR, and denies on a label-read failure; the `triage-prs.sh` test puts a green ready `parked` PR in the `parked` tier.
- [ ] AC15: the persisted ruling file and `texts/README.md` both carry the stored-`accept` sentence (CLO 5); the ADR-319 amendment lists exactly what it supersedes (Decision "Retention and erasure"; Consequences counsel gate; PR-C decisions, enabling conditions and still-open items; PR-D still-open published-documents clause), records the AP-009 deviation, the declared-card-kind and founder-gate paragraph, a `### Diagram` sub-heading "no change", and keeps status `adopting`.

## Test Scenarios

1. Placeholder gone: the unfinished-marker check finds nothing in the text body, `cardNotice`, `requestChangesNotice`; planted `[x]`, `TBD`, `to be confirmed` strings are caught.
2. Retention single source: the phrase appears in the body, once in each notice; planting `7 years` in the body fails.
3. Pin: flipping a byte fails all three pin legs; a new key with no pin fails; a version bump with the same bytes fails.
4. Kind copy: the ack key renders acknowledgement wording; `customer-terms` (mocked as terms) renders today's wording; `constructor` renders nothing.
5. `[key]` page for an undeclared key: NotFound plus a Sentry event; the index omits it.
6. Third table: adding a column to `legal_reauth_event` in a later migration fails the pin with the A5 message.
7. Label: the first line `How your decisions are recorded and kept` is the card title; a first line over 120 characters falls back to the key-derived label.

## Operator Holds, rewritten

Authority and quote: the operator's 2026-11-07 instruction: "the company has no external counsel, so the CLO agent's ruling (soleur:legal:clo) stands in for counsel sign-off", and "run the full CI battery ... only then mark the PR ready". The CTO rewrites the old plan's three `Operator-reserved:` lines accordingly; the old plan keeps no hold line (CTO A6), so exactly one plan on this branch carries holds.

- **Sign-off record (replaces old Hold 1; not a `Hold:` line):** the CLO agent signed off the wording, the retention period (5 years from the date of the decision, extended while a claim, complaint or inquiry is open) and the card wording as a stand-in for counsel on the operator's instruction of 2026-11-07, with human-lawyer review still owed (residual risks 1 to 12).
- **Cleared (old Hold 2, first half):** marking PR #12342 ready after the full CI battery is green on the final head, with the `parked` label on first.
- Hold: Operator-reserved: merging or enqueuing PR #12342 (label `parked`; the operator removes it), and the `approval-queue` flag state in prd. Merge deploys the text; the card is answerable by the founder only (server-side founder gate) once the global flag is on; the flag state is read first (CPO condition B); the published trio (S5) and the human-lawyer review are preconditions for widening beyond the founder.
- Hold: Operator-reserved: the first real acceptance of this text, the registry smoke and the roadmap CP2 wording (#12197 stays open; this PR does not edit the roadmap, which says "Not started"; ceiling wording when the operator edits it: CLO 8). The non-vacuous pre-flag read is CTO B2 (structural plus the Sentry `accepted` count), not a founder-login SQL count.

Categories: irreversible / production-mutating authorization (merge, flag, first acceptance). The legal-risk category (wording) is discharged by the operator's stand-in ruling. Limit stated plainly: the `parked` hook and triage tier stop accidental merges by agent sessions and drain-prs; they do not stop a human or an admin UI merge. Auto-merge stays off.

## Non-goals

No flag change, no recorded decision, no merge or enqueue, no migration, no change to published legal documents (tracked S5), no deletion path (#12080 stays open; its trigger is restated), no external anchor, no change to the card layout.

## Risks

- The 5 years is a commitment with no enforcing code; Art. 5(1)(e) and the notice are both breached if #12080 is not built before any row is 4 years old. Mitigation: A4's plain statement, the restated #12080 trigger (4 years), no row exists.
- The stand-in is not a lawyer: residual risks 1 to 8; `PROVISIONAL` stays true.
- The shared `requestChangesNotice` and `cardNotice` now state a text-specific period for every text; a later text with a different period needs its own CLO ruling and a notice change (CLO B).
- Moving 16 deck strings touches the card, dialog and two pages; mitigated by `tsc` and the real-key DOM test, but the jsdom suites run only in CI.
- The A4 sentence promises a deletion step "before any record reaches that age"; if ownership of that commitment changes, it must be re-ruled.
- A ready run is a second full CI run on the same tree; accepted per the operator's order.
- The `parked` hook branch tightens a shared guardrail (`ship-operator-step-gate.sh`): a bug there could deny legitimate merges of other PRs. Mitigation: the branch denies only when the PR carries `parked`, fails closed only when a resolved PR number's label read fails, has the listed test rows and a mutation row, and goes through `soleur:review`.
- The founder gate fails closed when `LEGAL_ACCEPTANCE_FOUNDER_ID` is unset or malformed: the surface disappears for everyone including the founder. That is the intended direction; the prd value was checked to exist.
- The `parked` mechanism does not stop a human or admin UI merge.
- The pre-flag Sentry read may not be runnable by the work phase; then it is labelled unverified, and admin SQL stays a stated blind spot.
- Rendered-card review by the CPO happens after implementation, before any `signOff.cpo`, in a later PR.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this one is filled.
- The text is hashed as raw bytes: never let an editor, formatter or `markdownlint --fix` rewrite it. Apply edits with a script or exact-match Edit, then `cmp`/`sha256sum`.
- Two plans carry this `branch:`; the Phase 0.7 selector tie-break picks the later-sorting name (this one). Do not rename either.
- The note's blockquote lines are pinned byte for byte by `legal-copy.test.ts`: the note edit and the deck edit must be one commit or CI is red between them.
- The CLO's A5 paragraph and the `legal_reauth_event` column pin must land together: the pin's failure message points at the paragraph.
- The ack-ban regex must be applied to the DOM with the dialog open; `dialog.codeBody` is shared and the ban only holds after the CLO's "checked" rewrite.
- Cite code by function or constant name in every record, never by line number.
- The sha256 in the PR body from the first draft (`76d2d115...`) is stale after A1 to A8; replace it.
