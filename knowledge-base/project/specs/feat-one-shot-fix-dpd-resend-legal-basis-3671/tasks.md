---
title: "Tasks: fix(legal) DPD §4.2 Resend Legal-Basis cleanup (#3671)"
date: 2026-05-12
lane: procedural
plan: knowledge-base/project/plans/2026-05-12-fix-dpd-resend-legal-basis-cleanup-plan.md
issue: 3671
---

# Tasks — DPD §4.2 Resend Legal-Basis cleanup

## 1. Setup

- [ ] 1.1 Confirm branch `feat-one-shot-fix-dpd-resend-legal-basis-3671` is current (`git branch --show-current`).
- [ ] 1.2 Read the plan: `knowledge-base/project/plans/2026-05-12-fix-dpd-resend-legal-basis-cleanup-plan.md`.
- [ ] 1.3 Verify both files exist and clauses are present:
  - `grep -c "consent (Article 6(1)(a)) for push subscriptions" docs/legal/data-protection-disclosure.md` → `1`
  - `grep -c "consent (Article 6(1)(a)) for push subscriptions" plugins/soleur/docs/pages/legal/data-protection-disclosure.md` → `1`

## 2. Core Implementation

### 2.1 Canonical edit — `docs/legal/data-protection-disclosure.md`

- [ ] 2.1.1 Trim line 156 Resend row Legal Basis column (drop `; consent (Article 6(1)(a)) for push subscriptions`).
- [ ] 2.1.2 Replace line 12 Last-Updated annotation with the new cleanup note (see plan Phase 1).

### 2.2 Plugin-mirror edit — `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`

- [ ] 2.2.1 Trim line 165 Resend row Legal Basis column (identical to 2.1.1).
- [ ] 2.2.2 Replace line 21 body `**Last Updated:**` annotation with the new cleanup note (see plan Phase 2).
- [ ] 2.2.3 Verify line 11 hero `<p>` Last-Updated date is still `May 12, 2026` — NO edit needed (date unchanged); only confirm.

## 3. Testing / Verification (14 ACs from plan)

- [ ] 3.1 AC1: `grep -c "consent (Article 6(1)(a)) for push subscriptions" docs/legal/data-protection-disclosure.md` → `0`.
- [ ] 3.2 AC2: same grep on mirror → `0`.
- [ ] 3.3 AC3: `grep -c "| Resend Inc.*Legitimate interest (Article 6(1)(f)) for transactional notifications |" docs/legal/data-protection-disclosure.md` → `1`.
- [ ] 3.4 AC4: same on mirror → `1`.
- [ ] 3.5 AC5: `grep -c "consent (Article 6(1)(a) GDPR)" docs/legal/data-protection-disclosure.md` → `2` (corrected from `1` at deepen-pass — Buttondown §2.3(e) and push §2.3(j) both match).
- [ ] 3.6 AC6: same on mirror → `2`.
- [ ] 3.7 AC7: `diff <(grep '| Resend Inc' docs/legal/data-protection-disclosure.md) <(grep '| Resend Inc' plugins/soleur/docs/pages/legal/data-protection-disclosure.md)` → empty.
- [ ] 3.8 AC8: `grep -c "trimmed Section 4.2 Resend row Legal Basis" docs/legal/data-protection-disclosure.md` → `1`.
- [ ] 3.9 AC9: same on mirror → `1`.
- [ ] 3.10 AC10: `grep -cE "Effective February 20, 2026 \| Last Updated May 12, 2026" plugins/soleur/docs/pages/legal/data-protection-disclosure.md` → `1`.
- [ ] 3.11 AC11: `grep -nE "Last Updated[: *]+May 12, 2026" plugins/soleur/docs/pages/legal/data-protection-disclosure.md` → 2 matches (hero + body).
- [ ] 3.12 AC12: `grep -c "^| Resend Inc"` on each file → `1`.
- [ ] 3.13 AC13 (OPTIONAL): Eleventy build smoke `cd plugins/soleur/docs && npx @11ty/eleventy --quiet` → exit `0`.
- [ ] 3.14 AC14: commit message uses `docs(legal): trim DPD §4.2 Resend Legal-Basis column — remove orphan push-subscription clause (#3671)`; PR body uses `Closes #3671`.

## 4. PR

- [ ] 4.1 Stage both files: `git add docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md`.
- [ ] 4.2 Commit with the conventional title (see 3.14).
- [ ] 4.3 Push branch.
- [ ] 4.4 Open PR with `Closes #3671` in body, labels: `domain/legal`, `priority/p3-low`, `code-review`.
- [ ] 4.5 Pre-merge: confirm all 14 ACs green; reviewer eyeballs rendered DPD if Eleventy ran locally.

## 5. Post-merge

None — no operator action. GitHub render + docs-deploy workflow handle publication.

## Learnings to write at /ship time

- Capture in `knowledge-base/project/learnings/best-practices/<topic>.md`: paper-quality of forward-port audits — pre-existing inconsistencies caught by legal-compliance-auditor during a forward-port PR review should be filed and cleaned up immediately as a separate atomic edit (per `wg-when-an-audit-identifies-pre-existing`), and the cleanup PR should re-run the auditor against the canonical-mirror pair to confirm no NEW inconsistency was introduced.
