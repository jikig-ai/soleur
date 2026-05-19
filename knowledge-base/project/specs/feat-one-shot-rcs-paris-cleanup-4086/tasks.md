---
lane: single-domain
plan: knowledge-base/project/plans/2026-05-19-fix-legal-rcs-paris-cleanup-4086-plan.md
issue: 4086
---

# Tasks — fix(legal): RCS Paris cleanup #4086

## Phase 0 — Preconditions

- [ ] 0.1 — `git grep -nE 'RCS Luxembourg' -- docs/legal/ plugins/soleur/docs/pages/legal/ knowledge-base/legal/` returns exactly 7 lines matching the enumerated bug-class list. If count ≠ 7, halt and revisit scope.
- [ ] 0.2 — Verify `apps/web-platform/test/legal-doc-consistency.test.ts` exists and uses vitest (`apps/web-platform/package.json` declares `"test": "vitest"`). Confirm `loadSource` / `loadMirror` / `REPO_ROOT` helpers are present and reusable.
- [ ] 0.3 — Confirm `incorporated in France` substring exists in both `docs/legal/privacy-policy.md` line 21 AND `docs/legal/data-protection-disclosure.md` line 22.

## Phase 1 — RED: extend the CI assertion before any prose edit

- [ ] 1.1 — Add the 4th `test()` block to `apps/web-platform/test/legal-doc-consistency.test.ts` per plan "CI Smoke Check — Detailed Assertion Logic" section verbatim.
- [ ] 1.2 — Run `cd apps/web-platform && bun run test:ci -- test/legal-doc-consistency.test.ts`. The new test block MUST fail at the Set-size assertion AND/OR at the per-site `not.toMatch(/RCS Luxembourg/)` check. The existing 3 test blocks MUST continue to pass. **Halt and inspect if RED is not observed exactly as expected — assertion shape is the bug detector.**

## Phase 2 — GREEN: apply the 7 prose substitutions

- [ ] 2.1 — Edit `docs/legal/privacy-policy.md` line 158 — replace `RCS Luxembourg registration number` with `French commerce-registry number (RCS Paris 927 585 729)`.
- [ ] 2.2 — Edit `docs/legal/privacy-policy.md` line 289 — same substitution.
- [ ] 2.3 — Edit `docs/legal/data-protection-disclosure.md` line 113 — same substitution.
- [ ] 2.4 — Edit `docs/legal/data-protection-disclosure.md` line 173 — same substitution.
- [ ] 2.5 — Edit `plugins/soleur/docs/pages/legal/privacy-policy.md` line 162 — same substitution.
- [ ] 2.6 — Edit `plugins/soleur/docs/pages/legal/privacy-policy.md` line 293 — same substitution.
- [ ] 2.7 — Edit `knowledge-base/legal/article-30-register.md` line 273 — replace `RCS Luxembourg registration number` with `RCS Paris 927 585 729` (explicit-number form for internal Art. 30 register).

## Phase 3 — Verify GREEN

- [ ] 3.1 — `git grep -nE 'RCS Luxembourg' -- docs/legal/ plugins/soleur/docs/pages/legal/ knowledge-base/legal/` returns 0 matches.
- [ ] 3.2 — `git grep -nE 'RCS Paris 927 585 729' -- docs/legal/ plugins/soleur/docs/pages/legal/ knowledge-base/legal/` returns exactly 7 matches.
- [ ] 3.3 — `cd apps/web-platform && bun run test:ci -- test/legal-doc-consistency.test.ts` — all 4 test blocks green.
- [ ] 3.4 — Manually diff PP source §4.10+§5.13 vs mirror §4.10+§5.13 — identical substitution applied on both sides.

## Phase 4 — gdpr-gate invocation

- [ ] 4.1 — Run `/soleur:gdpr-gate` against the diff. Expected: factual-correction-within-existing-PA finding with no fold-in items. If fold-in items emerge, address inline per gate routing.

## Phase 5 — Ship

- [ ] 5.1 — `/soleur:ship` with `Closes #4086` in PR body.
- [ ] 5.2 — PR description cites compliance basis: Art. 13(1) GDPR transparency + Art. 5(1)(a) lawfulness/transparency + LinkedIn appeal CAS-11047602-Q2Y0M4 credibility + controller-to-controller integrity for K-bis transfer to Microsoft Ireland.
- [ ] 5.3 — Multi-agent review (DHH + Kieran + simplicity + user-impact + gdpr-gate carry-forward) green.
- [ ] 5.4 — Merge via `gh pr merge --squash --auto` after review evidence captured.

## Phase 6 — Compound

- [ ] 6.1 — If session errors occurred, file learning in `knowledge-base/project/learnings/`. Topic candidates: cross-corpus factual-consistency CI assertions, regex-shape-not-value invariants, structural Set-based drift detection.
