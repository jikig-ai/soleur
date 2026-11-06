---
title: Tasks — feat-one-shot-10664-inngest-user-notice
date: 2026-11-06
plan: knowledge-base/project/plans/2026-11-06-docs-inngest-store-total-loss-user-notice-plan.md
issue: 10664
---

# Tasks — pre-drafted user notice for a total loss of the Inngest store

Derived from `knowledge-base/project/plans/2026-11-06-docs-inngest-store-total-loss-user-notice-plan.md`.

## Phase 1 — Draft the notice runbook

- [ ] 1.1 Create `knowledge-base/engineering/operations/runbooks/inngest-store-total-loss-user-notice.md` with runbook frontmatter (`title`, `date`, `owners: engineering/ops`, `category: incident-communications`, `tags`, `applies_to`, `related_issues: [10664, 9927]`).
- [ ] 1.2 Section "What this file is": standing draft used when the loss-mode procedure lands on "After a total loss" (cite the loss-mode rows and the `fail_header` key-probe row).
- [ ] 1.3 Section "Send conditions are the CLO's call": states the draft decides nothing about whether/when/whom/channel — those are the incident owner's decisions with counsel; determination records land in `knowledge-base/legal/audits/` and `knowledge-base/legal/breach-register.md`.
- [ ] 1.4 Section "Constraints the notice text must keep": the five must-nots from the plan (all-active-users floor; no "no record survives"/"nothing identifies" claim; no armed-reminder restoration promise; external-sender carve-out; aggregate-only, no per-user identifiers or counts).
- [ ] 1.5 Section "The drafted notice": the copy-pasteable block built from the plan's skeleton, with clearly marked `[...]` fill fields naming what was lost, the window and the action to take.
- [ ] 1.6 Section "Fill fields": table mapping each placeholder to its supplier and source.

## Phase 2 — Cross-link

- [ ] 2.1 `inngest-luks-cutover-6894.md`: one sentence under `### After a total loss: who tells affected users` naming the new file and that its constraints bind the notice.
- [ ] 2.2 `inngest-server.md`: one Quick reference row naming the notice runbook.

## Phase 3 — Verify

- [ ] 3.1 AC1–AC5 greps all pass (existence, three required elements, CLO-call sentence, four constraints, both cross-links).
- [ ] 3.2 `bash scripts/markdown-lint.sh` clean on the three touched runbook files.
- [ ] 3.3 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0.
- [ ] 3.4 `npx markdownlint` over the plan file and this tasks.md is clean (no MD010 tabs, no MD032 list-after-heading).
- [ ] 3.5 PR body uses `Ref #10664` (never `Closes`) and records the stale-checkbox observation (orphan-sweep item shipped in PR #10936; issue body deliberately not edited).
