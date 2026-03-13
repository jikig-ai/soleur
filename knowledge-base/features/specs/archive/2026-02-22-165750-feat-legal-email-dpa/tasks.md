---
title: "Tasks: Clarify email provider DPA for legal@jikigai.com"
issue: "#204"
date: 2026-02-21
---

# Tasks: Clarify Email Provider DPA

## Phase 1: Verify Provider

- [x] 1.1 Run DNS MX lookup for jikigai.com to confirm Proton Mail

## Phase 2: Update Documents

- [x] 2.1 Update Article 30 register Treatment N.3 -- replace placeholders with Proton AG details and fill `[DATE]` values
- [x] 2.2 Update GDPR policy Section 11.2 in both `docs/legal/gdpr-policy.md` and `plugins/soleur/docs/pages/legal/gdpr-policy.md`
- [x] 2.3 Mark audit report Recommendation 3 as resolved

## Phase 3: Verification

- [x] 3.1 Grep all legal files for "fournisseur email" -- expect zero matches
- [x] 3.2 Verify both GDPR policy locations match
- [x] 3.3 Run markdownlint on modified files
