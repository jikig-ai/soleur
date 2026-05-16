---
title: "TC_VERSION Bump Policy"
status: draft
custodian: clo
last_reviewed: 2026-05-15
related:
  - apps/web-platform/lib/legal/tc-version.ts
  - apps/web-platform/scripts/check-tc-document-sha.sh
  - knowledge-base/legal/article-30-register.md
  - knowledge-base/project/plans/2026-05-15-feat-oauth-tc-consent-residual-audit-plan.md
---

# TC_VERSION Bump Policy

When `docs/legal/terms-and-conditions.md` is edited, the operator MUST
classify the change into one of three tiers and act accordingly.
The CI guardrail (`.github/workflows/ci.yml :: tc-document-sha-guard`)
will fail the build unless the operator updates `TC_DOCUMENT_SHA` and
— for material/clarifying tiers — also bumps `TC_VERSION`.

A `TC_VERSION` bump forces every existing user to re-accept the Terms
on their next page load (middleware redirects on version mismatch),
and causes any live WebSocket session to be closed on the next gated
inbound message (`recheckTcMidSession` returns true).

## Tier 1 — Material change → BUMP REQUIRED

Examples (non-exhaustive):

- New processing purpose or new category of personal data collected.
- New or removed lawful basis.
- New sub-processor disclosed in the running text (in addition to the
  Article 30 register update, which is required regardless).
- New disclaimer-of-warranty or limitation-of-liability text not
  previously present, or material narrowing of the user's rights.
- New retention period or shortened existing retention.
- New jurisdiction or choice-of-law / forum-selection clause.
- New restriction on permitted use (e.g., tightening the BSL terms).
- Subscription, refund, cancellation, or auto-renewal terms changed.
- New EU consumer-rights provisions (Right of Withdrawal, ODR link,
  etc.) added or removed.

### Operator actions

1. Compute `sha256sum docs/legal/terms-and-conditions.md`.
2. Paste the value into `TC_DOCUMENT_SHA` in
   `apps/web-platform/lib/legal/tc-version.ts`.
3. **Bump `TC_VERSION`** per [semver-for-legal-docs](#semver-for-legal-docs).
4. Add a corresponding "Last Updated:" line at the top of
   `docs/legal/terms-and-conditions.md` summarising the change.
5. Sync the plugin docs-site mirror at
   `plugins/soleur/docs/pages/legal/terms-and-conditions.md`.
6. Update `knowledge-base/legal/article-30-register.md` if the change
   affects any Art. 30(1) limb of an existing Processing Activity, OR
   if a new Processing Activity is introduced.
7. Open a PR. Tag CLO for sign-off. PR title pattern:
   `legal(tc): TC_VERSION → <new-version> — <one-sentence rationale>`.

## Tier 2 — Clarifying change → BUMP REQUIRED

Examples:

- Re-wording a provision to make a previously-implicit user obligation
  explicit (no new obligation, but the user's understanding shifts).
- Renumbering of sections (because users may cite by section number).
- Splitting a single bullet into multiple bullets that materially
  re-frame the same point.
- Reordering enumerated items in a way that changes apparent priority.
- Adding examples that illustrate an existing rule.
- Cross-reference fixes that change which document governs a given
  scenario.

### Operator actions

Same as Tier 1 (steps 1-7). Use a `PATCH` bump under the
[semver-for-legal-docs](#semver-for-legal-docs) scheme.

## Tier 3 — Cosmetic change → NO BUMP (literal still requires update)

Examples:

- Typo corrections that do not change meaning.
- Whitespace/formatting changes (single-line vs paragraph, indentation,
  blank-line separators).
- Markdown-syntax fixes (e.g., link target normalisation, header level
  changes that do not change section numbering).
- Pure presentation changes to the plugin docs-site mirror that do not
  affect the canonical document body.

### Operator actions

1. Compute `sha256sum docs/legal/terms-and-conditions.md`.
2. Paste the value into `TC_DOCUMENT_SHA` in
   `apps/web-platform/lib/legal/tc-version.ts`.
3. **Do NOT bump `TC_VERSION`.** The previous version's acceptance
   record is still valid for the cosmetic-equivalent document.
4. The "Last Updated:" line MAY be touched only if the date is the
   classification axis users would inspect; cosmetic changes typically
   leave it unchanged.
5. Sync the plugin docs-site mirror.
6. Open a PR. CLO sign-off NOT required for purely cosmetic changes;
   reviewer signs off on the classification itself.

If you are unsure whether a change is cosmetic or clarifying, **treat
it as clarifying** (Tier 2). Over-bumping is recoverable (users re-
accept); under-bumping leaks demonstrability gaps.

## Semver for legal docs

`TC_VERSION` follows a constrained semver scheme:

- `MAJOR.MINOR.PATCH` (e.g., `1.0.0`, `1.1.0`, `2.0.0`).
- **MAJOR bump:** Material change that the operator anticipates will
  cause a non-trivial percentage of users to abandon rather than
  re-accept (e.g., a new license restriction, a new jurisdiction).
- **MINOR bump:** Material change that is consistent with the user's
  prior expectations (e.g., new sub-processor disclosure for a sub-
  processor the user could reasonably expect).
- **PATCH bump:** Clarifying change.

The middleware does string-equality comparison against `TC_VERSION` —
any bump triggers re-acceptance regardless of which limb moved.

## Demonstrability guarantees

Every acceptance writes a row to `public.tc_acceptances` with
`(user_id, version, document_sha, accepted_at)`. The
`UNIQUE(user_id, version)` constraint prevents duplicate rows; the
WORM trigger prevents UPDATE/DELETE except via the Art. 17 anonymise
RPC. The `document_sha` column is the content fingerprint at
acceptance time — if the canonical doc is edited after acceptance and
`TC_VERSION` is bumped, the ledger preserves the prior `(version,
document_sha)` pair as the demonstrable record.

## Operator pre-flight checklist

Before merging a PR that touches `docs/legal/terms-and-conditions.md`:

- [ ] Classified the change into Tier 1 / Tier 2 / Tier 3.
- [ ] Ran `sha256sum docs/legal/terms-and-conditions.md` and updated
      `TC_DOCUMENT_SHA` in `apps/web-platform/lib/legal/tc-version.ts`.
- [ ] Bumped `TC_VERSION` per the tier (skip only for Tier 3).
- [ ] Synced `plugins/soleur/docs/pages/legal/terms-and-conditions.md`
      so the CI mirror check passes.
- [ ] Updated `knowledge-base/legal/article-30-register.md` if a new
      Processing Activity was introduced or any Art. 30(1) limb of an
      existing PA changed.
- [ ] Confirmed `tc-document-sha-guard` CI job passes (green).
- [ ] Tagged CLO for sign-off (Tier 1 + Tier 2 only).
- [ ] PR body explicitly states which tier applies and the
      classification reasoning.

## CLO sign-off

CLO sign-off is captured in the PR comment thread. The CLO confirms:

1. The tier classification is correct.
2. The semver bump (if any) is appropriate for the tier.
3. The Article 30 register entry, if updated, accurately reflects the
   change.
4. The "Last Updated:" line accurately summarises the substantive delta.

CLO sign-off is the gating signal for merge of any Tier 1 or Tier 2 PR
that touches the canonical T&C document.

---

> **DRAFT — This document was generated by AI and requires professional
> legal review before use. It does not constitute legal advice.**
