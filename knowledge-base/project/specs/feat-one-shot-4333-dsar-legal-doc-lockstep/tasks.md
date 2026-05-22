---
title: Tasks — DSAR departed-member legal-doc lockstep (#4333)
plan: knowledge-base/project/plans/2026-05-22-feat-dsar-departed-member-legal-doc-lockstep-plan.md
type: docs-only
lane: cross-domain
issue: 4333
date: 2026-05-22
---

# Tasks — feat-one-shot-4333-dsar-legal-doc-lockstep

Derived from `knowledge-base/project/plans/2026-05-22-feat-dsar-departed-member-legal-doc-lockstep-plan.md`.

## Phase 0 — Preconditions

- [ ] **0.1** Confirm worktree + branch — `pwd` returns the worktree path AND `git branch --show-current` returns `feat-one-shot-4333-dsar-legal-doc-lockstep`.
- [ ] **0.2** Re-verify DPD §2.3 next-free letter — `grep -nE '^- \*\*\(.{1,2}\)\*\*' docs/legal/data-protection-disclosure.md` and confirm `(v)` is unused. If taken, pick next letter and propagate to plan AC3.
- [ ] **0.3** Re-verify zero existing departed-member references — `grep -l 'workspace_member_removals\|workspace member removal\|departed.*member' docs/legal/*.md` returns empty.
- [ ] **0.4** Re-confirm AC8 invariant — `compliance-posture.md` and `article-30-register.md` are NOT in the planned diff (already updated by #4294).

## Phase 1 — Canonical doc edits

- [ ] **1.1** `docs/legal/privacy-policy.md` — add §8.1 bullet (departed-member Art. 15/17/20 disclosure + `workspace_member_removals` reference + 36-month retention + cross-reference §4.11 workspace co-members).
- [ ] **1.2** `docs/legal/privacy-policy.md` — PREPEND `#<PR> — added departed-workspace-member DSAR disclosure for the workspace_member_removals WORM ledger (PA-19 — distinct from PA-20 workspace_member_actions); Art. 15 / 17 / 20 over the ledger; 36-month retention floor; Art. 17 cascade via anonymise_workspace_member_removals step 3.905 in server/account-delete.ts BEFORE auth.admin.deleteUser; lineage columns (id, removed_at) preserved post-erasure for Art. 5(2) accountability; no new sub-processor engaged; ` segment AHEAD of the existing `#4287 — ...` segment in the line-11 byline. Date stays "May 22, 2026" (no bump).
- [ ] **1.3** `docs/legal/gdpr-policy.md` — add §5.3 paragraph (Art. 15 + Art. 17 cascade + `anonymise_workspace_member_removals` ordering + lineage preservation for Art. 5(2)). MUST explicitly name BOTH PA-19 (this PR's ledger) AND PA-20 (sibling, already disclosed earlier in the doc's existing line-13 byline) with their distinct retention floors (36-month vs 7-year) — see Risk-6 and AC5c.
- [ ] **1.4** `docs/legal/gdpr-policy.md` — PREPEND same `#<PR> — …` segment to the line-13 byline AHEAD of the existing `#4287` segment.
- [ ] **1.5** `docs/legal/data-protection-disclosure.md` — add `- **(v)** **Workspace member removal audit ledger:**` sub-section under §2.3 (verified next-free letter via `grep -oE '^- \*\*\([a-z]{1,2}\)\*\*' ... | sort -u`; mirror §2.3(u) structural shape: Data processed / Legal basis / Retention / Sub-processors / Article 30 cross-reference). Cross-reference PA-19. Explicitly disambiguate from PA-20 (the sibling `workspace_member_actions` ledger disclosed under a different §2.3 sub-section).
- [ ] **1.6** `docs/legal/data-protection-disclosure.md` — PREPEND same `#<PR> — …` segment to the line-12 byline AHEAD of the existing `#4287` segment.

## Phase 2 — Eleventy mirror edits

- [ ] **2.1** `plugins/soleur/docs/pages/legal/privacy-policy.md` — apply same body delta as 1.1 (incl. §8.1 bullet); apply same byline prepend as 1.2 to line-20 body byline; verify line-11 hero already reads "Last Updated May 22, 2026" (no change needed unless stale).
- [ ] **2.2** `plugins/soleur/docs/pages/legal/gdpr-policy.md` — apply same body delta as 1.3; apply same byline prepend as 1.4 to line-22 body byline; verify line-11 hero already reads "Last Updated May 22, 2026".
- [ ] **2.3** `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` — apply same body delta as 1.5; apply same byline prepend as 1.6 to line-21 body byline; verify line-11 hero already reads "Last Updated May 22, 2026".

## Phase 3 — Counsel-attestation audit

- [ ] **3.1** Create `knowledge-base/legal/audits/2026-05-counsel-review-PLACEHOLDER.md` with frontmatter (title, type, date, issue: 4333, pr: PLACEHOLDER, status: SIGNED-OFF (operator-attested), signed_off_at, signed_off_by, re_evaluation_triggers).
- [ ] **3.2** Write three artifact sections — Artifact 1 (Privacy Policy §8.1), Artifact 2 (GDPR Policy §5.3), Artifact 3 (DPD §2.3(v)). Each section: Scope of review + Particular attention requested + Sign-off table.
- [ ] **3.3** Carry-forward ADR-039 §Re-evaluation triggers into the audit frontmatter `re_evaluation_triggers` field.

## Phase 4 — Pre-PR verification (AC1–AC8, AC11)

- [ ] **4.1** AC1 — three independent greps on privacy-policy.md.
- [ ] **4.2** AC2 — three independent greps on gdpr-policy.md.
- [ ] **4.3** AC3 — `(v)` sub-section grep + Processing Activity 19 grep on data-protection-disclosure.md.
- [ ] **4.4** AC4 — mirror-parity diff for each canonical/mirror pair.
- [ ] **4.5** AC5 — `grep -cE 'Last Updated[: *]+May 22, 2026' plugins/soleur/docs/pages/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md` each returns ≥ 2.
- [ ] **4.5b** AC5b — `grep -nE '^\*\*Last Updated:\*\* May 22, 2026 \(#[0-9]+ —' docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md` returns 3 lines AND the leading `#N` in each is the new PR number (NOT `#4287`).
- [ ] **4.5c** AC5c — `grep -c 'PA-19\|Processing Activity 19\|workspace_member_removals' docs/legal/gdpr-policy.md` ≥ 2 AND `grep -c 'PA-20\|Processing Activity 20\|workspace_member_actions' docs/legal/gdpr-policy.md` ≥ 1 (PA-19 ⊥ PA-20 disambiguation).
- [ ] **4.6** AC6 — audit-file frontmatter shape + three-artifact count.
- [ ] **4.7** AC8 — `compliance-posture.md` and `article-30-register.md` NOT in diff.
- [ ] **4.8** AC11 — only `.md` files in diff.

## Phase 5 — PR creation + post-create rename

- [ ] **5.1** `gh pr create --title 'docs(legal): DSAR departed-member disclosure lockstep (closes #4333)' --body $(cat …) --label 'domain/legal,priority/p2-medium,type/feature'` — uses `Closes #4333` per AC7.
- [ ] **5.2** Capture returned PR number; `mv knowledge-base/legal/audits/2026-05-counsel-review-PLACEHOLDER.md knowledge-base/legal/audits/2026-05-counsel-review-<PR>.md` AND update `pr:` frontmatter field in same edit.
- [ ] **5.3** Re-commit and push the rename.
- [ ] **5.4** AC9 — `gh pr checks <PR>` confirms `enforce` job concludes `success` (trivial pass).
- [ ] **5.5** AC10 — local lockstep-simulation bash one-liner returns `4`.

## Phase 6 — Post-merge follow-up filing (AC13)

- [ ] **6.1** AFTER `/soleur:ship` merges this PR — file separate workflow-gate issue with `gh issue create --title 'workflow-gate: promote legal-doc-cross-document-gate to required-check on main ruleset' --body '…' --label 'domain/engineering,priority/p3-low,type/chore'`.
- [ ] **6.2** AC12 — verify `gh issue view 4333` shows state=closed (auto-closed by `Closes #4333` keyword at merge).

## Phase 7 — Learning capture

- [ ] **7.1** Run `skill: soleur:compound` to capture any session learnings (e.g., the auto-merge-around-failed-advisory-gate pattern is the headline class).
