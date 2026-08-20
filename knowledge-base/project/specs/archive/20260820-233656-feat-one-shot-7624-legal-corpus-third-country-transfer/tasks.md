---
title: "Tasks — reconcile the published legal corpus to Art. 30 PA-7 (#7624)"
branch: feat-one-shot-7624-legal-corpus-third-country-transfer
lane: cross-domain
issue: 7624
plan: knowledge-base/project/plans/2026-08-20-fix-legal-corpus-third-country-transfer-plan.md
date: 2026-08-20
---

# Tasks — #7624

Derived from the plan's Implementation Phases. **The plan's `## CLO Advisory — Binding Rulings`
section carries the exact replacement wording for every correction.** Apply it verbatim with ONE
exception, recorded in the plan's `## Deviations from the CLO wording`: **D1 — every
`*(Corrected …, ref #7624: …)*` marker paraphrases the superseded sentence instead of quoting it**
(e.g. "previously described the archive as intra-EU with no third-country transfer", not the
quoted literal). This is what removes the collision with the anti-regression guard; without it the
guard reds on the CLO's own marker. The
plan's `## Enumerated Inventory` is the work-list (64 rows / 55 anchors / 16 files); AC10's
residual sweep is the closure criterion.

## Phase 0 — Preconditions and the sign-off record

- [ ] 0.1 Write the plan's `## CLO Advisory — Binding Rulings` verbatim to
      `knowledge-base/legal/audits/2026-08-20-clo-review-7624-corpus-transfer-reconciliation.md`,
      frontmatter matching the `2026-08-counsel-review-7349.md` precedent.
- [ ] 0.2 Re-read PA-7 §§(d)(e)(f)(g) at HEAD; re-derive if the register moved past `28612e8cd`.
- [ ] 0.3 Confirm a clean start: `lint-legal-mirror-drift-baseline.sh --base origin/main` → 0,
      `apps/web-platform/scripts/check-tc-document-sha.sh` → 0.
- [ ] 0.4 Re-anchor all **64** inventory rows on their verbatim sentences at HEAD (55 distinct
      anchors; nine rows share an anchor, and `data-protection-disclosure.md:172` carries three).
- [ ] 0.5 Read `.github/workflows/cla-evidence.yml` "Compute CLA doc hash at PR base SHA"; confirm
      per-PR-base hashing before editing any CLA instrument.
- [ ] 0.6 File the retention-ceiling issue (CLO Fork 2D). Record its number for every `[#NNNN]`.
      Labels `domain/legal` + `type/chore` + `priority/p2-medium`.

## Phase 1 — Balancing-test re-derivation (`gdpr-policy.md` §3.4)

- [ ] 1.1 Apply CLO 2A (preamble, row C4) — keeps the pinned sentinel verbatim.
- [ ] 1.2 Apply CLO 2B (limb (2) full replacement, rows A9 + C5). Substitute the 0.6 issue number.
- [ ] 1.3 Apply CLO 2C (limb (3) addition). **Do not touch limb (1).** This phase does NOT apply
      CLO 1B — row A10 belongs to Phase 2.
- [ ] 1.4 Mirror all three, byte-identically, same commit.
- [ ] 1.5 Confirm `/Three-part balancing test \(off-site evidence archive\)/` still matches both.

## Phase 2 — Class A + Class G

- [ ] 2.1 CLO 1A: split the `privacy-policy.md` §5.11 storage-location bullet into two.
- [ ] 2.1b **CLO 1B (row A10)** — the `gdpr-policy.md` §3.4 closing sentence. Owned here, not by
      Phase 1; an earlier draft left it owned by no phase.
- [ ] 2.2 CLO 1C template table: rows A1, A2/C1, A4, A5, A6, A7, A8, C2.
- [ ] 2.3 Row G1: "Governance mode" → "Cloudflare R2 Lock Rule (age-based, ten (10) year
      retention floor)". S3 terminology for a mechanism the infrastructure does not use.
- [ ] 2.4 Mirror every edit, same position, same commit.

## Phase 3 — Class B + Class D

- [ ] 3.1 CLO 3(a): DPD §2.3(n) closing line (row B1).
- [ ] 3.2 CLO 3(b): re-frame the DPD §4.2 FreeTSA row **in place** (do not move it) + the
      clarifying line beneath the table.
- [ ] 3.3 CLO 3(c): DPD §6.4 FreeTSA bullet (row B3).
- [ ] 3.4 Rows B4/B4′: **verify only, change nothing** (CLO 3(d)).
- [ ] 3.5 CLO 5(b): new `privacy-policy.md` §10 paragraph + new `gdpr-policy.md` §6 bullet.
      **Placement: adjacent to the GitHub/repository material, NOT under "For the Web Platform".**
      Mirrors use `/legal/<slug>/` link form; match the surrounding autolink convention.

## Phase 4 — Class C remainder + Class J + Class H

- [ ] 4.1 Rows C1, C3: retention as an indefinite period with a ten-year WORM floor.
- [ ] 4.2 CLO 4(a): rows C6/C7 in the two CLA §0 preambles + mirrors. Elevate the
      cross-reference-specificity recommendation to required (closes the layered-notice hop).
- [ ] 4.3 Row C8: `data-protection-disclosure.md:155` §2.3(d) + mirror `:164`.
- [ ] 4.4 Class J: J1 (a §4.5 pointer to §5.11 and §10) and J2 (a CLA bullet in §7 Data
      Retention) + mirrors. Bullets and sentences only — no new headings.
- [ ] 4.5 Rows H1 (Art. 17 erasure runbook), H2 (`apps/cla-evidence/infra/README.md`),
      H3 (`knowledge-base/operations/expenses.md`).

## Phase 5 — Class E + Class I + Class F

- [ ] 5.1 CLO 4(b): DPA template §11.1 (E1), §11.2 covered-list addition, Schedule 2 row split
      (E2 + E3 — `chat-attachments/*` folded into the **Supabase Inc** row) + the correction note,
      and E4 at §8.
- [ ] 5.2 Rows I1/I2: **verify, do not edit** — both stay true under re-characterise-in-place.
- [ ] 5.3 CLO register discharge block (F1). **Append**; leave the existing CORPUS DIVERGENCE
      block byte-for-byte. Substitute the 0.6 issue number. Confirm §(c) is untouched.

## Phase 6 — Anti-regression sentinels

- [ ] 6.1 Add a **new `test()` block** to `apps/web-platform/test/legal-doc-consistency.test.ts`
      with the `FORBIDDEN` / `REQUIRED` arrays, the `>= 8` dispatch floor and the loop — all
      written out in full in the plan's `## Guard Contract`.
- [ ] 6.2 **Do NOT widen the existing `checks` tuple**; leave all 15 pinned rows byte-unchanged
      (AC4). Plain strings via `toContain` / `not.toContain` — no regex escaping.
- [ ] 6.3 Execute mutation rows 1-3 and harness row H1; record each verdict (AC13).

## Phase 7 — Re-pin and verify

- [ ] 7.1 `sha256sum` the five edited canonical docs; paste into `legal-doc-shas.ts`. **Last
      content change**; redo after any review-fix commit.
- [ ] 7.2 Run the local battery: `check-tc-document-sha.sh`, `lint-legal-scope-block-placement.sh`,
      `lint-legal-mirror-drift-baseline.sh`, then
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/legal-doc-consistency.test.ts test/legal-doc-shas-guard.test.ts`.
      **Never set `SOLEUR_LEGAL_DRIFT_ACCEPT`.**
- [ ] 7.3 Run AC10 / AC10a / AC11; paste the classified output into the PR body.
- [ ] 7.4 `git diff origin/main | grep -n '#NNNN'` → nothing.
- [ ] 7.5 File the availability/DR tracking issue (AC19 — the `chat-attachments` DR claim, NOT the
      attribution, which is in scope as row E3) and confirm AC14/AC15/AC16. AC14 uses
      `grep -c '^-[^-]'` and `git diff -U0` — the bare `'^-'` form can never return 0 because the
      `--- a/<path>` header matches it.
- [ ] 7.6 File the register-binding follow-up issue from the plan's `## Follow-Up: the divergence
      class this guard does not cover`. Carry the #7622 counterfactual verbatim into the body.

## Post-merge

- [ ] PM1 Fetch all three published mirrors; assert the negative literals return 0 and
      `EU-US Data Privacy Framework` returns ≥1 on each.
- [ ] PM2 Confirm both deferred items exist: the register's Outstanding-items entry, and both
      issues `OPEN` (the retention-ceiling issue from 0.6, and the AC19 DR issue).
- [ ] PM3 `gh issue close 7624`.
