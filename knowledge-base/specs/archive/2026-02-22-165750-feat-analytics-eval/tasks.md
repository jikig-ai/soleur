---
title: "Analytics Evaluation Tasks"
feature: feat-analytics-eval
issue: "#198"
date: 2026-02-21
---

# Analytics Evaluation Tasks

## Phase 1: Analytics Integration

- [ ] 1.1 Add analytics script tag to `plugins/soleur/docs/_includes/base.njk` in `<head>` section
- [ ] 1.2 Verify script loads on local dev with `npm run docs:dev`
- [ ] 1.3 Verify no cookies are set by the analytics script

## Phase 2: Legal Document Updates (Docs Site Copies)

- [ ] 2.1 Update `plugins/soleur/docs/pages/legal/cookie-policy.md` sections 3.2, 4.2
- [ ] 2.2 Update `plugins/soleur/docs/pages/legal/privacy-policy.md` sections 4.3, 12
- [ ] 2.3 Update `plugins/soleur/docs/pages/legal/gdpr-policy.md` sections 4.1, 10 (Article 30 register)

## Phase 3: Legal Document Updates (Root Copies)

- [ ] 3.1 Mirror cookie policy changes to `docs/legal/cookie-policy.md`
- [ ] 3.2 Mirror privacy policy changes to `docs/legal/privacy-policy.md`
- [ ] 3.3 Mirror GDPR policy changes to `docs/legal/gdpr-policy.md`

## Phase 4: Verification and Cleanup

- [ ] 4.1 Diff docs-site and root legal copies to confirm they match
- [ ] 4.2 Run Eleventy build to verify no template errors
- [ ] 4.3 Verify analytics script loads with agent-browser after deployment
- [ ] 4.4 Close issue #188 with rationale (cookie-free analytics removes consent banner need)
