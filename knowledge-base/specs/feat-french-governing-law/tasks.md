# Tasks: Change Governing Law from Delaware to France

**Plan:** [2026-03-02-feat-french-governing-law-plan.md](../../plans/2026-03-02-feat-french-governing-law-plan.md)
**Branch:** feat-french-governing-law
**Issue:** #360

## Phase 1: Core Document Changes

### 1.1 Edit T&Cs (canonical copy)
- [ ] Replace Section 14 in `docs/legal/terms-and-conditions.md` with 3-subsection structure (Law, Jurisdiction, EU/EEA)
- [ ] Update frontmatter `jurisdiction: EU, US` to `jurisdiction: FR, EU`
- [ ] Update `Last Updated` date

### 1.2 Edit T&Cs (docs-site copy)
- [ ] Replace Section 14 in `plugins/soleur/docs/pages/legal/terms-and-conditions.md` with identical legal content
- [ ] Update `Last Updated` date

### 1.3 Edit Disclaimer (canonical copy)
- [ ] Replace Section 8 in `docs/legal/disclaimer.md` with 3-subsection structure (Law, Jurisdiction, EU/EEA)
- [ ] Fix entity attribution: "operated by Soleur" -> "operated by Jikigai"
- [ ] Update frontmatter `jurisdiction: EU, US` to `jurisdiction: FR, EU`
- [ ] Update `Last Updated` date

### 1.4 Edit Disclaimer (docs-site copy)
- [ ] Replace Section 8 in `plugins/soleur/docs/pages/legal/disclaimer.md` with identical legal content
- [ ] Fix entity attribution: "operated by Soleur" -> "operated by Jikigai"
- [ ] Update `Last Updated` date

## Phase 2: Verification

### 2.1 Grep verification
- [ ] Confirm zero "Delaware" references in `docs/legal/` directory
- [ ] Confirm zero "Delaware" references in `plugins/soleur/docs/pages/legal/` directory

### 2.2 Compliance audit
- [ ] Run legal-compliance-auditor agent against full legal document suite
- [ ] Address any flagged inconsistencies
