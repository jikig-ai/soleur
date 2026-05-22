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

- [ ] **1.1** `docs/legal/privacy-policy.md` — add §8.1 bullet (departed-member Art. 15/17/20 disclosure + `workspace_member_removals` reference + 36-month retention).
- [ ] **1.2** `docs/legal/privacy-policy.md` — prepend `#4333 — …` segment to `**Last Updated:**` byline change-log; bump date to 2026-05-22.
- [ ] **1.3** `docs/legal/gdpr-policy.md` — add §5.3 inline disclosure (Art. 15 + Art. 17 cascade + `anonymise_workspace_member_removals` ordering + lineage preservation for Art. 5(2)). Use this doc's `(Added 2026-05-22: …)` paragraph-annotation convention.
- [ ] **1.4** `docs/legal/data-protection-disclosure.md` — add `- **(v)** Workspace member removal audit ledger:` sub-section under §2.3 (mirror §2.3(u) structural shape). Cross-reference PA-19.

## Phase 2 — Eleventy mirror edits

- [ ] **2.1** `plugins/soleur/docs/pages/legal/privacy-policy.md` — apply same body delta as 1.1; sync BOTH hero-banner `Last Updated May 22, 2026` (no colon) AND body `**Last Updated:** May 22, 2026` (with colon).
- [ ] **2.2** `plugins/soleur/docs/pages/legal/gdpr-policy.md` — apply same body delta as 1.3; verify Last-Updated convention via grep.
- [ ] **2.3** `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` — apply same body delta as 1.4; verify Last-Updated convention via grep.

## Phase 3 — Counsel-attestation audit

- [ ] **3.1** Create `knowledge-base/legal/audits/2026-05-counsel-review-PLACEHOLDER.md` with frontmatter (title, type, date, issue: 4333, pr: PLACEHOLDER, status: SIGNED-OFF (operator-attested), signed_off_at, signed_off_by, re_evaluation_triggers).
- [ ] **3.2** Write three artifact sections — Artifact 1 (Privacy Policy §8.1), Artifact 2 (GDPR Policy §5.3), Artifact 3 (DPD §2.3(v)). Each section: Scope of review + Particular attention requested + Sign-off table.
- [ ] **3.3** Carry-forward ADR-039 §Re-evaluation triggers into the audit frontmatter `re_evaluation_triggers` field.

## Phase 4 — Pre-PR verification (AC1–AC8, AC11)

- [ ] **4.1** AC1 — three independent greps on privacy-policy.md.
- [ ] **4.2** AC2 — three independent greps on gdpr-policy.md.
- [ ] **4.3** AC3 — `(v)` sub-section grep + Processing Activity 19 grep on data-protection-disclosure.md.
- [ ] **4.4** AC4 — mirror-parity diff for each canonical/mirror pair.
- [ ] **4.5** AC5 — `Last Updated[: *]+May 22, 2026` count ≥ 2 on privacy-policy.md mirror.
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
