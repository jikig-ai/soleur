---
title: "feat: first founder legal text draft, founder-acceptance-record (counsel-review draft, HOLD)"
date: 2026-11-07
slug: founder-acceptance-record-text-draft
branch: feat-one-shot-12197-founder-acceptance-record-text-draft
issue: 12197
type: feat
priority: p2
domain: legal
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: DRAFT pending counsel sign-off
---

# feat: first founder legal text draft, `founder-acceptance-record`

> **DRAFT, HOLD.** This plan produces a counsel-review draft only. The draft PR (#12342) is never marked ready, never merged and never enqueued until counsel signs off the wording and the retention period. Merging deploys the file to production, where it becomes answerable once the `approval-queue` flag is on. Refs #12197 and #12011; never `Closes`.

## Enhancement Summary

**Deepened on:** 2026-11-07. **Agents and gates used:** soleur:engineering:cto (two rounds), soleur:legal:clo (two rounds), soleur:product:cpo, soleur:engineering:review:user-impact-reviewer, soleur:product:spec-flow-analyzer, soleur:engineering:review:code-simplicity-reviewer, soleur:engineering:review:test-design-reviewer, soleur:gdpr-gate (plan mode); deepen-plan halts 4.6 to 4.13 run mechanically (Guard Contract lint green).

### Key improvements

1. Text corrected against the code and CLO review: Yes step described not guaranteed; the code "is not kept in this record"; readers described with "include" (database host and backups "may also hold"); the check is "once it is switched on" and "for Jikigai"; the ack marker is listed; the scope sentence "whoever signs in and gives an answer here" replaces any operator-only reading (the flag is global). New snapshot hash `acd38414...c9db`.
2. Test design settled by CTO ruling: one new text-specific test file, a `cross-layer-limits.test.ts` leg for both SQL 1000 literals, and a `CI`-only merge guard that makes an accidental ready or merge red while the placeholder stands, instead of a hand-flipped constant or a green-now tripwire.
3. Mechanical merge block, flag-scope exposure, `CI_DRAFT_LIGHT=on` reading of "CI green", and #12344 (card copy) as a merge precondition are now explicit in Operator Holds, AC8, AC10 and Risks.

### New considerations discovered

- markdownlint runs on `texts/*.md` (lists need blank lines, addresses need angle brackets); the proposal passes at rc=0.
- Migration 184 carries two 1000 literals (the CHECK and the RPC guard), not one.
- The LIA is `draft-requires-counsel-review`, so the Art. 6(1)(f) sentence is a draft position.

## Overview

Add the first committed text to the legal-acceptance registry (ADR-319, #12011): key `founder-acceptance-record`, file `apps/web-platform/server/legal-acceptance/texts/founder-acceptance-record.md`, front-matter `version: 2026-11-07`, no `valid_until`, LF only, ASCII only. The subject, chosen by the operator, is an acknowledgement of how the founder's decisions are recorded and kept. It says only what the shipped system does and binds the founder to nothing beyond the record itself.

The proposal is reproduced under "Exact file content" below as a labelled SNAPSHOT. The work phase copied it to the registry path unchanged; the committed file is the only authority afterwards (review deleted the separate `.proposed.md` copy, so there is one text file and one snapshot).

Nothing in this plan records an acceptance, touches the `approval-queue` flag, or acts on production.

## Research Reconciliation: spec vs. codebase

| Brief claim | Reality (checked) | Plan response |
|---|---|---|
| "check ... whether any test asserts the texts directory is empty" | No test asserts emptiness. One test reads the real directory: `test/legal-acceptance/canonical.test.ts` ("the committed registry loads without error (it is EMPTY until counsel signs off ...)"). It passes with one parseable file; only its title and comment go stale. | Rename the title (CTO ruling). |
| "Dockerfile COPY and registry-embedding test needs" | Dockerfile runner stage already has `COPY --from=builder /app/server/legal-acceptance/texts ./server/legal-acceptance/texts`; `.dockerignore` already has `!server/legal-acceptance/texts/*.md`; `registry-embedding.test.ts` uses its own fixture (`fixtures/hash-fixture.md`) and a temp tree, so it neither needs nor is affected by a real text. | No Dockerfile or `.dockerignore` change. |
| "which index/page tests change when the first key exists" | None. `page.test.tsx`, `routes.test.ts`, `verify-route.test.ts`, `ack-reconciliation.test.ts` mock `loadLegalTexts` / `getLegalText` or point at a fixture directory. The index page (`app/(dashboard)/dashboard/approvals/legal/page.tsx`) reads the real directory at runtime only: with the flag on it lists every key; with the flag off it lists only keys the founder already has a row for and is not-found when there are none. | No page test changes. Runtime exposure is covered by the HOLD. |
| "note up to 1000 characters" | True in all three layers, counted in code points: SQL `requested_edit ... char_length BETWEEN 1 AND 1000` (migration 184, plus a second literal in the RPC guard `char_length(p_requested_edit) > 1000`), `REQUEST_CHANGES_MAX = 1000` (`lib/legal-acceptance-wire.ts`), `normaliseNote` in `server/legal-acceptance/service.ts` (trims, counts the untrimmed code points). | Keep "up to 1000 characters"; the new test holds the text's number to `REQUEST_CHANGES_MAX`, and `cross-layer-limits.test.ts` holds the constant to both SQL literals. |
| "what is stored per decision" (the operator's list) | Matches DSAR note section (b). The table also holds `method`, `reauth_method`, `surface` (fixed labels) and `event_id` (the consumed intent). | One extra sentence in the text states them (CLO: otherwise "what is stored" would be untrue); flagged for the Art. 30 register (PA-40). |
| "who can read it" | Founder reads own rows via RLS with an `authenticated`-audience token; database-owner credential held by the operator and the production migration pipeline (a CI secret), rule not control; the check endpoint returns exactly `status`, `text_hash`, `decided_at`, `row_ok`, never the note; no `service_role` path returns the note. | Text says so, using "release process" (CLO: do not name the CI secret; ADR says what else that credential set can mint is not assessed). |
| "texts README forbids adding a text without counsel's sign-off" | True: `texts/README.md` "Do not add a text here without counsel's sign-off on its wording." The file is also not shown to be linted-exempt: `.markdownlintignore` has no entry for `apps/web-platform/server/legal-acceptance/texts/`, so markdownlint runs on it (lefthook and CI). | Draft PR and HOLD; proposal passes markdownlint (rc=0) after blank lines around lists and `<legal@jikigai.com>`. |
| Pipeline stop: "CI green" | `gh variable list` shows `CI_DRAFT_LIGHT=on` (ADR-276 Option R): on a draft push the heavy families are skipped and the `test` aggregator is RED by design. | CTO ruling: light-set green; local vitest and markdownlint output cited in the PR body (see Acceptance Criteria). |

## Research Insights

**Premise Validation (Phase 0.6).** Checked: #12197 OPEN (title "chore: first real legal acceptance verified by the hold gate and registry smoke"), #12011 OPEN, #12080 OPEN (retention/deletion path), PR #12342 OPEN and draft; collision pre-check reports only our own PR #12342. Cited files exist on this branch: `canonical.ts`, `texts/README.md`, `texts/.gitattributes` (`*.md text eol=lf`), `lib/legal-acceptance-copy.ts`, `test/legal-acceptance/legal-copy.test.ts`, the DSAR note, ADR-319. ADR corpus: ADR-319 is the only ADR on the mechanism; its PR-C/PR-D amendments already decided COPY (not embed), the dark flag, and "A recorded Yes authorizes no production act". Nothing here contradicts or re-opens it.

**Property List (Phase 0.6b).**

1. A committed, hash-stable text exists for key `founder-acceptance-record` that the loader parses and the hold gate can hash from the committed blob.
2. Every sentence in the text is true of the shipped system (ADR-319, migrations 184/185, DSAR note), and the text claims no legal identity, enforceability, compliance or tamper-proofness.
3. Nothing can be answered or recorded before counsel signs off (draft PR, HOLD, flag untouched).
4. An accidental ready or merge while the placeholder stands is blocked mechanically on a full-CI run, and a later edit that fills the retention period or changes any fact is a new, separately reviewed change (after the first merge, a byte change without a `version` bump fails a published `{version: sha256}` pin added at sign-off).

**Cut List.** (mechanism -> property -> what already covers it)

- Front-matter `status: draft` key in the file -> property 3 -> the in-body retention placeholder plus PR state already cover it; the parser ignores unknown keys and the card never shows front matter (CTO ruling).
- A pinned sha256 literal in a test now -> property 4 -> the hold gate hashes the committed blob; the literal would be rewritten at sign-off (CTO ruling). Pin lands in the sign-off PR. Also cut: a `COUNSEL_SIGNED_OFF` constant (an editable self-attestation) and a green-now "placeholder present" assertion, replaced by the `CI`-only merge guard; the simplicity reviewer's suggestion to cut the 7-row matrix is taken as about five `it` blocks.
- A `sha256sum` child process in the new test -> property 1 -> `registry-embedding.test.ts` already proves bundle and `sha256sum` parity.
- Any Dockerfile, `.dockerignore`, page, route, flag or migration change -> none of the properties -> already in place (see Reconciliation).
- Rewording the card copy deck -> property 2 -> pinned by `legal-copy.test.ts` and PROVISIONAL; deferred as #12344.

**Learnings applied.** Registry bytes are the hash input, so the file must be written exactly (no editor re-wrap, no BOM, final LF). `.gitattributes` pins LF in the working tree. markdownlint: lists need blank lines (MD032), bare addresses need angle brackets (MD034).

## Exact file content (what the work phase writes)

Target path: `apps/web-platform/server/legal-acceptance/texts/founder-acceptance-record.md`. The block between the fences is a SNAPSHOT of the whole file (the brief asks for the exact content in the plan; the operator's scope governs over the CTO's preference to link only, so it is embedded and the drift risk is closed by `cmp`, below). Authority: until the copy, this snapshot was the source (the separate `.proposed.md` copy was deleted at review); at copy time `cmp` between it and the committed file must exit 0; from then on the COMMITTED file is the only authority and counsel edits only it. (The separate `.proposed.md` was deleted at review, so it is not marked superseded; it no longer exists.) The plan snapshot and hash are not updated afterwards. the card renders only the part after the closing front-matter line, in a `whitespace-pre-wrap` block with no markdown rendering, so each paragraph is one line and lists are plain dashes.

```text
---
version: 2026-11-07
---
How your decisions are recorded and kept

This text describes how Soleur records and keeps the decisions you give on legal texts. Saying Yes here records that you acknowledge this description. Your answer covers this text only: it does not accept any other text and is not given for any other purpose. This record applies to whoever signs in and gives an answer here.

What is stored for each decision

- The identifier of your account. It is a random number, not your name or email address.
- The name (key) and the version of the text.
- A fingerprint of the exact text you were shown.
- Your choice: Yes, No or Request changes.
- The time of the decision.
- An identifier of the sign-in session you decided in.
- For a Yes, the time you confirmed the code sent to your email.
- A checksum of the record.
- If you chose Request changes, the note you wrote, up to 1000 characters.

The record also holds fixed technical labels (a web session, and for a Yes the email code method) and the identifier of the request the decision answers. A separate marker, linked to the record's identifier, notes the time the web service finished recording the decision.

How a decision is given

To give a Yes, you enter a code that Jikigai emails to your account address, in your signed-in web session. The code itself is not kept in this record. No and Request changes are given in your signed-in web session without a code. The record shows that a decision was submitted through a signed-in web session of your account.

An answer is final for this text. To change it, a new version of the text has to be published. Your answer to the earlier version stays on record as you gave it.

How long it is kept

The record is kept after you delete your account. Jikigai relies on its legitimate interest (Article 6(1)(f) GDPR) in being able to show later what was decided; Article 17(3)(e) GDPR lets it keep data that may be needed for legal claims. The account identifier is not anonymous: someone who holds other Jikigai records could link it to you, so Jikigai treats it as personal data. How long the record is kept: [period to be confirmed by counsel].

Who can read it

- You, for your own records, when you are signed in to the web app.
- Those who can read the stored records directly include the holders of the database administrator role (the operator and Jikigai's release process); the database host and its backups may also hold them. No automated agent session is meant to use that role; that is a rule, not a technical block.
- A Jikigai check that holds a step until a decision is recorded can ask whether a decision was made. It receives only the status, the text fingerprint, the time and the checksum result, never your note.

Once it is switched on, a Jikigai check can recompute the checksum and treat a record that no longer matches as damaged. This is for Jikigai; it is not shown to you. The checksum is not a seal and not proof of who acted: a holder of production credentials could write or change a record and its checksum.

Your note

If you choose Request changes, the note is saved with your decision and kept even if you later delete your account. Please do not write names, email addresses or private details about yourself or anyone else in it. The note is not sent anywhere; it can be read by those with direct access to the stored records, as described above.

Your rights

You can ask what Jikigai holds, or object, by writing to <legal@jikigai.com> (Articles 15 and 21 GDPR), and you can complain to the CNIL.
```

**sha256 of the final bytes (this draft):** `acd38414ce35e9aff7ccb1a0fee3719f9f65628cbfe4097d1a30dcffe465c9db` (3556 bytes). Verified two ways on the proposal: `sha256sum` and `loadLegalTexts()` / `textHash` over a temp directory returned the same value, `version` `2026-11-07`, `validUntil` null. This value is for review only. It is NOT pinned in a test, and the hash changes the moment counsel replaces the retention placeholder; the work phase recomputes it after copying and reports it in the PR body. The hold gate and the recorded `text_hash` always come from the committed blob.

### Sentence-by-sentence ground truth

| Text says | True because (source) |
|---|---|
| account identifier is a random number, not name or email | `founder_id` is a plain uuid, no foreign key (ADR-319 Decision; DSAR note (b)) |
| name (key) and version | `key`, `version` columns (migration 184) |
| fingerprint of the exact text | `text_hash`, sha256 of the file's raw bytes (`canonical.ts`) |
| choice Yes / No / Request changes | `choice` in `accept`, `decline`, `request_changes` |
| time of the decision | `created_at` |
| identifier of the sign-in session | `session_id` (1..128 chars) |
| for a Yes, time the emailed code was confirmed | `reauth_at`, set only for `accept` (constraints `legal_acceptance_reauth_only_for_yes`, `_yes_has_reauth`) |
| checksum of the record | `row_hash`, computed by the database (ADR-319 Checksum) |
| note up to 1000 characters for Request changes | `requested_edit` 1..1000 only with `request_changes`; code-point cap in `REQUEST_CHANGES_MAX` and `normaliseNote` |
| fixed technical labels and the request identifier | `method = 'web-session'`, `surface = 'web'`, `reauth_method = 'email-code'`, `event_id` |
| a Yes needs an emailed code in the signed-in web session; the code is not stored | ADR-319 Email-code step-up ("never stored here"); PR-C amendment |
| No and Request changes need no code, only a web session | `reauth_only_for_yes` constraint; ADR PR-C ("decline and request_changes have no email step") |
| the record shows a decision was submitted through a signed-in web session | ADR-319 property 3 and Context ("must not say who the person is in law") |
| answer is final; a change is a new version; earlier answer stays | ADR-319 Record ("A new version of a text is a new row ... terminal for its text hash"); deck `replaced.earlierAnswer` |
| kept after account deletion; Art. 6(1)(f) interest; Art. 17(3)(e) lets it keep data that may be needed for claims | ADR-319 Retention and erasure; DSAR note (b). CLO: 17(3)(e) is an exception to erasure, not a basis |
| identifier not anonymous, treated as personal data | DSAR note (b) ("do not describe the identifier as anonymous") |
| retention: `[period to be confirmed by counsel]` | same placeholder string as `LEGAL_COPY.cardNotice`; ADR "unconfirmed by counsel"; #12080 |
| founder reads own rows when signed in | RLS policy `legal_acceptance_founder_select`, `aud = authenticated` |
| DB administrator role held by the operator and the release process; agent use is a rule | ADR-319 PR-D "Residual risk" supersession: owner credential held by the operator and the production migration pipeline; "a rule and not a control" |
| a check can ask whether a decision was made; receives only status, fingerprint, time, checksum result, never the note | `GET /api/internal/legal-acceptance/[key]`: four keys `status`, `text_hash`, `decided_at`, `row_ok`; hold gate `web-acceptance` |
| the check recomputes the checksum and flags a mismatch; not a seal; a credential holder could write or change a record and its checksum | `verify_legal_acceptance` returns `invalid`; ADR-319 Residual risk |
| note not sent anywhere; readable by those with the DB admin credential | ADR-319 PR-D "Note delivery: pull-only"; no `service_role` path returns it |
| asks / object at the legal address; complain to the CNIL | `LEGAL_COPY.cardNotice`; DSAR note (b) |

Deliberate omissions (not in the text, listed for counsel): the short-lived code-request records (`legal_reauth_event`, purged when older than 30 days at the next request; DSAR note (b) has a bracketed sentence for them); the `legal_acceptance_ack` table (no founder id; pseudonymous through the row id); the five-minute window of a confirmed code; the retention proposal "life of the instrument plus five years, capped at ten" (unconfirmed, not quoted, per the DSAR note rule).

## Files to Create

- `apps/web-platform/server/legal-acceptance/texts/founder-acceptance-record.md` (copy of the proposal, byte for byte, `cmp` exit 0)
- `apps/web-platform/test/legal-acceptance/founder-acceptance-record.test.ts` (text-specific checks, about five `it` blocks; see Guard Contract). It lives in its own file because counsel's edit rewrites exactly these checks.
- Already created by planning: `knowledge-base/project/specs/feat-one-shot-12197-founder-acceptance-record-text-draft/{decision-challenges.md,tasks.md}` (the `.proposed.md` copy was deleted at review)

## Files to Edit

- `apps/web-platform/test/legal-acceptance/canonical.test.ts`: rename ONLY the test "the committed registry loads without error (it is EMPTY until ...)" so it says it proves the loader, the directory and that every committed text parses (CTO ruling); no new assertions here.
- `apps/web-platform/test/legal-acceptance/cross-layer-limits.test.ts`: add the SQL-versus-constant leg: extract BOTH note-limit literals from migration 184 (the `requested_edit` CHECK `char_length(requested_edit) BETWEEN 1 AND 1000` and the RPC guard `char_length(p_requested_edit) > 1000`) with that file's existing comment-stripping helpers, assert each equals `REQUEST_CHANGES_MAX` from `lib/legal-acceptance-wire.ts` (read from source and imported), and fail on an empty extraction. The new text test does not import from this file.
- `apps/web-platform/test/legal-acceptance/routes.test.ts`: refresh the comment "The registry directory is a fixture dir (the real one holds no legal text yet)".
- `apps/web-platform/server/legal-acceptance/README.md`: replace the sentence "no text is committed, so every key answers 404 and there is nothing to load (#12197)" with the draft-held state (a draft text is committed on a held PR; the smoke stays open until it is published and answered).

No change to: `Dockerfile`, `.dockerignore`, `canonical.ts`, `legal-acceptance-copy.ts`, any page or route, migrations, flags, workflows, ADR-319 (its dated "no text is committed" lines are history; status stays `adopting`). No C4 file changes, so no C4 gate run is added to the work phase.

## Test inventory (grep of `apps/web-platform/test`, `e2e`, `plugins/soleur/test`)

| Test / file | Reads the real `texts/`? | Effect of one real text |
|---|---|---|
| `canonical.test.ts` (committed registry loads) | yes, `loadLegalTexts()` | still passes if the file parses; title renamed |
| `registry-embedding.test.ts` | no, temp tree and `fixtures/hash-fixture.md`; one case asserts `TEXTS_DIR` exists | none |
| `page.test.tsx`, `routes.test.ts`, `verify-route.test.ts`, `ack-reconciliation.test.ts`, `service.test.ts` | no, mocked or fixture dir | none |
| `verify-route-census.test.ts`, `cross-layer-limits.test.ts`, `legal-copy.test.ts` | no | none |
| `plugins/soleur/test/hold-gate-eval.test.sh` | no, builds its own repo with `wa-key.md` | none |
| e2e | no reference to `approvals/legal` | none |
| Any "texts directory is empty" assertion | none found (grep `no texts`, `empty registry`, `no legal text`, `holds no legal text`) | not applicable |

## Guard Contract

### Guard 1 — founder-acceptance-record text test and merge guard

**Property.** The committed `founder-acceptance-record.md` reads through the production loader, holds only LF and ASCII bytes with no BOM, claims none of the forbidden words, states the same note limit the code enforces, and cannot reach a full-CI or merge-group run while an open item (any placeholder-shaped token: bracket, TBD/TODO/XX/___, "to be confirmed", "counsel") remains in its body or in the card notice and request-changes notice that state the same retention period. The guard is a detector of the DRAFT STATE, not proof of counsel's sign-off: an admin or UI merge bypasses it, and a numeric period written by anyone passes it.

**Assembly.** One chokepoint per leg. Format: an `auditDir(dir)` helper that reads the raw bytes of EVERY `<key>.md` in a registry directory (keys derived by `KEY_RE`, README skipped), called on the real `texts/` directory and on temp directories. Content: `getLegalText("founder-acceptance-record")` from `server/legal-acceptance/canonical.ts` (the production loader) and a shared `FORBIDDEN` regex. Limit: the single `up to (\d+) characters` match in the body against `REQUEST_CHANGES_MAX` in `lib/legal-acceptance-wire.ts`, and (in `cross-layer-limits.test.ts`) that constant against BOTH 1000 literals in migration 184. Merge guard: one `it.skipIf(!process.env.CI)` over the same body asserting no `\[[^\]\n]*\]` token remains.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a CR byte, a non-ASCII character (curly quote, em dash) or a BOM to the text, or to a second committed key after a compliant first | RED (the loop covers every key on raw bytes) |
| 2 | Run `auditDir` on an empty temp directory, or remove the file (a guard reporting "0 keys checked" and exiting 0 is vacuous) | RED (explicit `>= 1 key` and key-present assertion) |
| 3 | Add the word "compliant" or "legally binding" to the text | RED |
| 4 | Change "1000" in the text, in `REQUEST_CHANGES_MAX`, or in either SQL literal | RED (text vs constant in the new test; constant vs both SQL literals in `cross-layer-limits.test.ts`) |
| 5 | Run the suite with `CI=1` while the placeholder is present | RED (the merge guard); locally without `CI` the same test is skipped and the draft run stays green |
| 6 | Remove the version line or add `valid_until` | RED (loader assertion: version matches `^\d{4}-\d{2}-\d{2}$`, `validUntil === null`; the date is not pinned) |

**Harness rows:** a planted forbidden word in a string passed to the same `FORBIDDEN` regex must match (negative control for the word check), and a temp directory holding one compliant file and one with a CR must fail `auditDir` (negative control for the byte check). Run the new file RED (before the text is copied in) and once with `CI=1` after, and cite both outputs.

**Anchor.** No stored hash is pinned here, by ruling: the text will change at sign-off. The integrity anchor is outside the commit: the hold gate recomputes the hash from the committed blob, and `registry-embedding.test.ts` proves bundle and `sha256sum` parity. The sign-off PR adds a published `{version: sha256}` pin plus the exact key set, so a byte change after the first merge to main without a `version` bump fails mechanically (before the first merge bytes may change freely, because the hold means the first merge IS the sign-off version).

## Observability

Pure data and test change: the Files lists contain one markdown text under `server/legal-acceptance/texts/` and tests, no new code, route, job or infrastructure surface (Phase 2.9 skip: no code-class file edited). The existing signals already cover the registry read: `store_failed` with `stage=registry` (and `extra.code`) when a committed text cannot be read or is malformed, and `page_read_failed` for the founder pages. The file is under an `apps/` path, so the five-field schema is declared below with the existing signals (no new emitter is added).

```yaml
liveness_signal:
  what: "Sentry op `accepted` (feature=legal-acceptance), one per recorded decision; none is expected while the PR is on HOLD"
  cadence: "per recorded decision"
  alert_target: "not paged (liveness only), see apps/web-platform/server/approval/ops.ts"
  configured_in: "apps/web-platform/server/approval/ops.ts (LEGAL_OPS), alerts in apps/web-platform/infra/sentry"
error_reporting:
  destination: "Sentry web-platform via reportLegalOp, tag feature=legal-acceptance"
  fail_loud: "op store_failed with tag stage=registry and extra.code when the committed text cannot be read or is malformed; op page_read_failed for a founder page"
failure_modes:
  - mode: "committed text malformed or unreadable (bad bytes, no front matter, bad version)"
    detection: "Sentry store_failed stage=registry, extra.code names the LegalTextError code; the structural test fails before merge"
    alert_route: "no paging rule yet (tracked as #12195); read in Sentry"
  - mode: "text file missing from the production image (Dockerfile COPY or .dockerignore regression)"
    detection: "registry-embedding.test.ts at CI; the key answers 404 (unknown_key); the post-deploy registry smoke kept open in #12197"
    alert_route: "CI failure; smoke is a follow-up in #12197"
logs:
  where: "Sentry web-platform project (no text, note, code or address is logged)"
  retention: "the Sentry project retention setting"
discoverability_test:
  command: "grep -c 'period to be confirmed by counsel' apps/web-platform/server/legal-acceptance/texts/founder-acceptance-record.md"
  expected_output: "1"
```

The command prints how many retention placeholders remain in the committed draft: `1` while the HOLD stands, and the sign-off PR changes it to `0` together with the test tripwire. Hash check for the work phase: `sha256sum` of the committed file compared with the PR-body value, and the new vitest file.

## Encryption Posture

Skipped: no persistent store and no new connection are introduced. (The text describes the existing store; it does not alter it.)

## Architecture Decision (ADR/C4)

No architectural decision is made. ADR-319 already decided the registry, the COPY path and the dark flag; this adds data to the registry. C4 completeness check: read `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` scope for this feature: external actors (the founder, the operator) and the `legalAcceptanceStore` container with `webapp -> legalAcceptanceStore` are already modeled; no new vendor, store or access relationship appears; the cardinality gate `plugins/soleur/test/c4-count-parity.test.sh` is run in the work phase to confirm it stays green. No ADR amendment: status stays `adopting`.

## User-Brand Impact

- **If this lands broken, the user experiences:** the operator opens `/dashboard/approvals/legal` (flag on) and sees a card titled "Accept the updated Founder acceptance record?" whose text still contains the bracketed retention placeholder or misstates what is kept, then gives a Yes that is final for that version and cannot be taken back from the card; or the card copy's "treats these terms as accepted" line shows on a text that accepts no terms (#12344).
- **If this leaks, the user's data is exposed via:** the text itself holds no personal data; the exposure vector is the Request changes note and the pseudonymous account uuid described by the text. A text that understates who can read them (the database-owner credential held by the operator and the release pipeline; the check endpoint's four fields) would mislead the data subject about that exposure. The plan keeps the text conservative and records the residual (a credential holder can write a row and its checksum).
- **Who can answer (scope):** the `approval-queue` flag is effectively global (`workspaceId: null`, ADR-319 Flag scope): if it is on in prd when this text is merged, ANY signed-in user sees the card and can record a final, undeletable row (and a note of up to 1000 characters) against this text; the check endpoint only reads the one configured founder id. The text therefore says "whoever signs in and gives an answer here" and does not name the operator. The prd flag must be off, or counsel must have decided the non-operator case, before merge.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** carried from ADR-319 (`single-user incident`): the first and only reader is the operator, and a final, unretractable Yes on a text that misdescribes the record is a one-person data-protection (Art. 13) failure and a trust failure for the product's legal-acceptance feature; it is not `aggregate pattern` because there is no population yet, and not `none` because the text is a legal notice.

CPO plan-time sign-off, 2026-11-07: approved with conditions. (A) the PR stays draft; merging requires counsel's wording with the retention period filled in and a new version date if the text changes. (B) before any merge, confirm the `approval-queue` flag state in prd: if on, merging puts an unfinished text in front of the operator as "Needs your answer". (C) #12197 stays open; the roadmap CP2 wording stays "In progress (legal-acceptance slice)", never Done. (D) do not change the card in this PR; file a follow-up so the confirmation copy depends on the text key (filed as #12344) and note the mismatch in the PR description. Product note: the subject is sound as a first text but does not exercise a long, multi-clause terms text; label the #12197 outcome "path verified with an acknowledgement text", not "terms acceptance verified". `soleur:engineering:review:user-impact-reviewer` runs at review time.

## GDPR / compliance

Trigger (b) of Phase 2.7 fires (single-user incident declared). The substantive assessment was obtained from the CLO agent (Art. 6(1)(f) vs 17(3)(e) framing, over-disclosure of access paths, the retention placeholder) and is applied to the proposal; the deterministic `soleur:gdpr-gate` pass is run by deepen-plan. Register items to flag for counsel (not changed here): PA-40 gains the sentence listing `method`, `surface`, `reauth_method` and `event_id`; the text discloses access roles in more detail than DSAR note (b); the published Privacy Policy / GDPR Policy / Data Protection Disclosure remain owed in final form before any non-operator founder. This PR edits no published document.

**Gate result (soleur:gdpr-gate, plan mode, 2026-11-07).** This is not legal review. Findings are heuristic. Path scan: no planned file matches the canonical regulated-data regex (no migration, `.sql`, auth or API route file); the five v1 checks have nothing to fire on (no new column, PII table, FK, non-EEA vendor or Art. 9 column). No Critical finding, so no compliance-posture write and no issue. Substantive items stay with counsel: the LIA (`knowledge-base/legal/legitimate-interest-assessments/2026-11-founder-legal-acceptance-lia.md`) is `status: draft-requires-counsel-review`, so the Art. 6(1)(f) sentence rests on an unreviewed assessment (keep "draft position pending counsel"); the non-operator founder case (a non-operator account can record an undeletable row; DSAR note says Art. 13(4) does not carry over); how the database host, backups and the release-process credential set (ADR-319 "not assessed") are described. PA-40 already lists `legal_acceptance_ack`.

## Domain Review

**Domains relevant:** Legal, Product, Engineering

### Legal

**Status:** reviewed (CLO agent, advisory; real sign-off is counsel's)
**Assessment:** Sentence edits applied: describe the Yes step rather than guarantee it; "release process" instead of the CI secret; checksum sentence rewritten (only the check recomputes it; not a seal, not proof of who acted; production-credential holders can write a row and its checksum); Art. 17(3)(e) presented as an exception to erasure with 6(1)(f) as the basis, "may be needed"; "is not given for any other purpose" instead of "does not authorize" (the hold-gate lexical-binding residual means a hold naming this key could be discharged by a Yes, ADR-319 PR-D). The sentence "Saying Yes here records that you acknowledge this description" is the one counsel must approve: the stored value is `accepted`. Second round (applied): "The code itself is not kept in this record"; readers "include" the database administrator role holders, and the database host and its backups "may also hold them" (counsel item: how the processor and backup arrangements and the release-process credential set are described; ADR-319 says the latter is not assessed); "Once it is switched on, a Jikigai check can recompute the checksum ... This is for Jikigai; it is not shown to you"; the ack marker sentence "notes the time the web service finished recording the decision" (no vendor named); "This record applies to whoever signs in and gives an answer here" because the flag is global. The LIA is `draft-requires-counsel-review`, so the Art. 6(1)(f) sentence stays a draft position. No objection to the retention placeholder while the file sits in `specs/` as a proposal; objection would arise if it landed in the registry directory, got a hash pin, or went live with the bracket, which is exactly why the PR is on HOLD.

### Product

**Status:** reviewed (CPO agent). Conditions A to D recorded in User-Brand Impact. No UI file is created or edited (the existing card renders the body), so the Product/UX Gate is NONE and no wireframe is owed.

### Engineering

**Status:** reviewed (CTO agent). Rulings are in `decision-challenges.md`: no in-file marker, structural test without a hash pin, no CI gate keys on `texts/*.md`, draft-light CI reading.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Draft the first founder legal text for the legal-acceptance registry" | Exact file content; Files to Create (text) | mapped |
| 2 | "front-matter `version: 2026-11-07`, LF only, plain ASCII-safe wording, no `valid_until`" | Exact file content; Guard 1 rows 1, 7 | mapped |
| 3 | "It must say only what is true of the shipped system" | Sentence-by-sentence ground truth | mapped |
| 4 | "Do not claim legal identity, enforceability or compliance" | Guard 1 row 5; CLO edits | mapped |
| 5 | "Mark the file clearly as a DRAFT pending counsel sign-off in the PR and in the plan, and open the PR as DRAFT with a HOLD" | Plan banner; Operator Holds; the retention placeholder; PR body (work phase) | mapped (file marker ruled out by the CTO; the in-file marker is the placeholder) |
| 6 | "Check what tests and the Dockerfile COPY/registry-embedding test need" | Research Reconciliation; Test inventory | mapped |
| 7 | "sha256sum equals the recorded hash" | Exact file content (hash); AC 4 | mapped |
| 8 | "whether any test asserts the texts directory is empty" | Test inventory (none found; one title renamed) | mapped |
| 9 | "Ref #12197 and Ref #12011, never Closes" | AC 9 | mapped |
| 10 | "Do not record an acceptance, do not touch the approval-queue flag, no production actions" | Operator Holds; Non-goals | mapped |
| 11 | "stop after the draft PR is open with CI green; do not run ship's merge phase, do not mark ready, do not enqueue" | AC 8, 10; Operator Holds | mapped |
| 12 | "Include a ## User-Brand Impact section and `## Operator Holds`" | both sections | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| text file | "file `apps/web-platform/server/legal-acceptance/texts/founder-acceptance-record.md`" | asked |
| structural test `founder-acceptance-record.test.ts` | "Check what tests ... need so the new text loads and hashes correctly" | asked (CTO ruled structural, no pin) |
| rename of the `canonical.test.ts` title | "whether any test asserts the texts directory is empty" | asked (the one stale title found) |
| `cross-layer-limits.test.ts` SQL leg | "every number, e.g. the 1000-character note limit, is checked against the code/migration" | asked |
| refresh of two stale comments (routes test, server README) | "say only what is true of the shipped system" | inferred - justification: both state "no text is committed", which the PR makes false if merged; tiny, docs-only |
| follow-up issue #12344 (card copy) | "bind the founder to nothing beyond the record itself" | inferred - justification: CLO and CPO found the deck's "these terms" line contradicts it; the deck is test-pinned so it is deferred, per `wg-when-deferring-a-capability-create-a` |
| Guard Contract | "Check what tests ... need so the new text loads and hashes correctly" | inferred - justification: the structural test is an assertion-based check |

### Split Assessment

- Subsystems touched: 2 (`apps/web-platform`, `knowledge-base`)
- Planned files: 6 (3 product files + 1 new text + 1 new test counted once each; spec artifacts excluded) | Estimated changed lines: about 120
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Open Code-Review Overlap

None. Checked open `code-review` issues for `legal-acceptance/texts`, `legal-acceptance/canonical`, `test/legal-acceptance`, `legal-acceptance/README`, `legal-acceptance-copy`: no matches.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

- [ ] AC1: `apps/web-platform/server/legal-acceptance/texts/founder-acceptance-record.md` was byte-identical to the proposal at copy time (`cmp` exit 0; the `.proposed.md` was deleted at review, and review corrected the ack-marker sentence in the committed file, so the plan snapshot is history), starts with `---`, `version: 2026-11-07`, `---`, has no `valid_until`, ends with one LF. The committed file is the only authority.
- [ ] AC2: `LC_ALL=C grep -c -P '[^\x00-\x7F]'` and `grep -c $'\r'` on the committed file both print 0; `git check-attr eol` for the path reports `lf`; `cmp` (AC1) after the commit proves no hook rewrote it.
- [ ] AC3: `markdownlint` with the repo `.markdownlint.json` run on the committed path (not only on a copy) exits 0, and the same run is repeated on the changed `server/legal-acceptance/README.md`.
- [ ] AC4: `sha256sum` of the committed file equals `textHash` from `loadLegalTexts()` and the value printed in the PR body. The plan's value `acd38414...c9db` is a snapshot of the draft bytes; the PR body states the value of the bytes actually committed (they are identical unless counsel edited before the work phase).
- [ ] AC5: written RED first: `founder-acceptance-record.test.ts` fails before the text is copied in (cite the output); after the copy, `apps/web-platform/test/legal-acceptance/` passes locally under vitest (including `canonical.test.ts` and the extended `cross-layer-limits.test.ts`), and the merge guard is run once with `CI=1` and shown RED for the placeholder (the right reason), then skipped without `CI`. All three outputs are cited in the PR body.
- [ ] AC6: `canonical.test.ts` title renamed; `cross-layer-limits.test.ts` carries the two-literal SQL leg (an empty extraction fails); `routes.test.ts` comment and `server/legal-acceptance/README.md` sentence refreshed; no other source file changed (`git diff --stat` shows only the files listed above).
- [ ] AC7: no test, doc or text claims "verified", "reviewed", "legally binding", "audit-ready" or "compliant" about the text (the deck test and the new test both pass).
- [ ] AC8: PR #12342 is converted from `WIP:` to a real title (for example `feat(legal-acceptance): DRAFT founder-acceptance-record text, HOLD for counsel`; if a title-lint check objects, keep the `feat(...)` shape and the word DRAFT) and remains a DRAFT. Its body leads with a HOLD banner and lists the counsel items: the sentence "Saying Yes here records that you acknowledge this description"; the retention period; the card-copy mismatch #12344 (a merge precondition, not only a note); the PA-40 register note for the technical-labels and ack-marker sentences; the Art. 6(1)(f) / 17(3)(e) framing, with the LIA still `draft-requires-counsel-review`; how the database host, backups and the release-process credential set are described; the non-operator founder case under the global flag; the flag state in prd read-only before any merge. It states `Ref #12197` and `Ref #12011`.
- [ ] AC9: the PR body contains no `Closes`, `Fixes` or `Resolves`.
- [ ] AC10: "CI green" means, per the CTO ruling, every light-set check green on the draft (list them with `gh pr checks`) with the `test` aggregator red by design (ADR-276 Option R, `CI_DRAFT_LIGHT=on`); the PR body names the red aggregator as expected and carries the local vitest and markdownlint output. A light-set check that fails for a pre-existing reason is reported with its evidence, not hidden. The PR is never marked ready, never merged, never enqueued; `ship` merge phase is not run.
- [ ] AC11: `approval-queue` flag, Doppler, Supabase production, migrations and `legal_acceptance` rows are untouched (no command in the work phase targets them).

## Test Scenarios

1. Format: `auditDir` over the real `texts/` directory reads raw bytes of every key: no 0x0D, nothing above 0x7F, no BOM, at least one key. Negative control: a temp directory with a compliant file and one with a CR fails.
2. Forbidden words: the shared `FORBIDDEN` regex finds none in the text; a planted string is caught.
3. Limit: the body contains exactly one `up to (\d+) characters`, equal to `REQUEST_CHANGES_MAX`; in `cross-layer-limits.test.ts` both SQL literals equal the constant.
4. Loader: `getLegalText("founder-acceptance-record")` gives a version matching `^\d{4}-\d{2}-\d{2}$` and a null `validUntil`.
5. Merge guard (`it.skipIf(!process.env.CI)`): `heldFindings()` (text body, card notice, request-changes notice) finds no placeholder-shaped token; RED with `CI=1` while the placeholder stands. A non-CI control proves the detector finds the open items in the real data; a second text in the registry fails a tripwire until the guard is extended.

## Operator Holds

- Hold: Operator-reserved: counsel's sign-off of the wording of `founder-acceptance-record`, in particular the sentence "Saying Yes here records that you acknowledge this description", the Art. 6(1)(f) / 17(3)(e) framing, the access-role disclosures, and the retention period (#12080), before this text is merged, marked ready, enqueued or answered. [Text name (added by the plan's author): founder-acceptance-record]
- Hold: Operator-reserved: merging or marking PR #12342 ready (merge deploys the file to production, where it becomes answerable by any signed-in user once the global `approval-queue` flag is on; preconditions: counsel's sign-off above, #12344 resolved or the card copy accepted by counsel, and the prd flag state read first, CPO condition B).
- Hold: Operator-reserved: the first real acceptance of this text, the registry smoke and the roadmap CP2 wording (#12197 stays open; wording stays "In progress (legal-acceptance slice)").

These are Operator-reserved by category: legal-risk (the wording of a legal text is reserved for counsel) and irreversible / production-mutating authorization. No recorded Yes for any key discharges them (ADR-319: "A recorded Yes authorizes no production act").

## HOLD procedure

1. The draft PR #12342 stays DRAFT for its whole life in this pipeline. Do not run `gh pr ready`, `gh pr merge`, `gh pr merge --auto`, or enqueue it.
2. On sign-off (a separate, later change, by counsel's text): replace the placeholder with the confirmed period in the text AND in `LEGAL_COPY.cardNotice` (the guard stays red until both are done), delete the merge guard and its real-data control in that same PR (counsel's sign-off PR is the only change that may), pin a published `{version: sha256}` entry and the exact key set in the test, run the full CI battery on that PR, then decide the flag state (CPO condition B) before merge. After the first merge to main any byte change bumps `version` (CTO ruling); before it, bytes may change freely because the first merge is the sign-off version.
3. Do not touch the `approval-queue` flag or record any decision at any step.

## Non-goals

No change to the card, copy deck, routes, migrations, Dockerfile, flag, published legal documents, Art. 30 register or ADR-319. No retention decision (#12080). No hash pin yet. No acceptance recorded. The card-copy follow-up is #12344.

## Risks

- Counsel rewrites the text: expected; the hash changes; nothing is recorded yet so no recorded hash is invalidated. The new test file is the one thing counsel's edit rewrites; nothing is pinned yet.
- Someone merges the draft: now blocked mechanically on a full-CI or merge-group run by the `CI`-only merge guard (the placeholder fails it); draft-light CI skips tests on the draft, which is why the guard is also backed by the draft state, the `Operator-reserved:` holds and the PR banner. No CODEOWNERS entry was verified.
- If `CI_DRAFT_LIGHT` is ever switched off, full CI on the draft is RED because of the merge guard. That is the intended signal, not a defect; do not "fix" it by deleting the guard.
- Anyone signed in can record a row once merged with the flag on: see User-Brand Impact scope; the precondition is in Operator Holds.
- A Yes on this text is read as acceptance of terms: the text says it is not; the deck line is #12344.
- The text discloses access roles in more detail than DSAR note (b) and says the database host and backups "may also hold" the records: flagged for counsel; easy to cut.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one is filled.
- The text file is hashed as raw bytes: never let an editor, formatter or `markdownlint --fix` rewrite it (the repo says `--fix` corrupts prose). Copy with `cp`, then `cmp`; the lefthook markdown-lint hook lints and does not rewrite, but `cmp` after the commit proves it.
- The file name is the key and the card title (`legalTextLabel`): renaming it later is a new key and a new row set.
- Do not cite the `1000` limit from memory in any future edit: it is asserted against the code (text vs constant vs both SQL literals).
- With `CI_DRAFT_LIGHT=on` the new vitest file does not run in CI on the draft, so the PR body must carry the local output, including the `CI=1` run.
- The plan snapshot and the committed file were reconciled by `cmp` at copy time only; afterwards the committed file wins and the plan snapshot is never edited (so it is history, not the text counsel signs; review corrected the ack-marker sentence in the committed file only).
