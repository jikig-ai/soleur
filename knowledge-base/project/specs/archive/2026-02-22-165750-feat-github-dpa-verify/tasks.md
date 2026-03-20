---
title: "Tasks: Verify GitHub DPA Acceptance"
issue: "#203"
date: 2026-02-21
---

# Tasks: Verify GitHub DPA Acceptance

## Phase 1: Document DPA Status

- [x] 1.1 Create DPA verification memo summarizing research findings
  - GitHub DPA only covers paid plans (Enterprise Cloud, Teams, Copilot)
  - Jikigai is on the free Organization plan (1 seat)
  - Free-plan processing governed by GitHub ToS + Privacy Statement
  - GitHub Privacy Statement acknowledges GDPR processor obligations

## Phase 2: Update Legal Documents

- [x] 2.1 Update GDPR policy Section 2.2 in `docs/legal/gdpr-policy.md`
  - Replace reference to GitHub DPA with accurate description of applicable terms
  - Note that GitHub's ToS + Privacy Statement provide substantive GDPR protections
  - Preserve existing EU-US DPF and SCC references
- [x] 2.2 Sync GDPR policy changes to `plugins/soleur/docs/pages/legal/gdpr-policy.md`
  - Verify both locations are identical in substance
- [x] 2.3 Verify no other legal documents reference the GitHub DPA incorrectly
  - Check `docs/legal/data-processing-agreement.md` (Data Protection Disclosure)
  - Check `docs/legal/privacy-policy.md`

## Phase 3: Risk Assessment

- [x] 3.1 Add counsel recommendations to the DPA verification memo
  - Option A: Accept current posture (low risk, minimal processing)
  - Option B: Upgrade to GitHub Teams for formal DPA
  - Option C: Alternative hosting provider

## Phase 4: Issue Closure

- [x] 4.1 Update issue #203 with findings and link to artifacts
- [x] 4.2 Mark acceptance criteria as verified
