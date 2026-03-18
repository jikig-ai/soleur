# Tasks: DPD Section 4.2 Missing Processors

## Phase 1: Eleventy Source Update

- [ ] 1.1 Read `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- [ ] 1.2 Add GitHub Pages row to Section 4.2 table (processor, processing activity, data processed, legal basis, sub-processor list link)
- [ ] 1.3 Add Plausible Analytics row to Section 4.2 table with explicit anonymous-data note
- [ ] 1.4 Update cross-reference paragraph below table to include "Section 2.3(a) and Section 2.3(e)"
- [ ] 1.5 Bump "Last Updated" date in both the hero section and the metadata line

## Phase 2: Root Source Copy Sync

- [ ] 2.1 Read `docs/legal/data-processing-agreement.md`
- [ ] 2.2 Replace Section 4.1 "No Sub-processors" with "Plugin Sub-processors" (scoped to Plugin, cross-ref Section 2.1)
- [ ] 2.3 Replace Section 4.2 with "Docs Site Processors" containing the full three-row table (GitHub Pages, Plausible, Buttondown)
- [ ] 2.4 Add cross-reference paragraph: "This disclosure is consistent with Section 2.3(a) and Section 2.3(e)."
- [ ] 2.5 Add Section 4.3 "Third-Party Services Used by Users" with user-initiated services table (Anthropic, GitHub, npm -- without Buttondown)
- [ ] 2.6 Bump "Last Updated" date

## Phase 3: Verification

- [ ] 3.1 Cross-reference DPD Section 4.2 with Section 2.3(a) -- confirm GitHub Pages and Plausible are described consistently
- [ ] 3.2 Cross-reference DPD Section 4.2 with GDPR Policy Article 30 register (Section 10.1) -- confirm all Docs Site processing activities are represented
- [ ] 3.3 Verify `docs/legal/` Section 4 structure matches Eleventy source
- [ ] 3.4 Run markdownlint on both files
- [ ] 3.5 Run compound and commit
