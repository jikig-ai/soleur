# Tasks: DPD Section 13.2 Web Platform Notification Channel

## Phase 1: Setup

- [ ] 1.1 Merge origin/main to get latest DPD state
- [ ] 1.2 Verify Section 13.2 current text matches expected baseline

## Phase 2: Core Implementation

- [ ] 2.1 Update Section 13.2 in `docs/legal/data-protection-disclosure.md`
- [ ] 2.2 Update Section 13.2 in `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- [ ] 2.3 Update "Last Updated" header in `docs/legal/data-protection-disclosure.md` (line 12)
- [ ] 2.4 Update "Last Updated" header in `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` HTML hero (line 11)
- [ ] 2.5 Update "Last Updated" header in `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` markdown (line 21)

## Phase 3: Validation

- [ ] 3.1 Diff both DPD copies to verify only expected differences (frontmatter, HTML wrapper, link paths)
- [ ] 3.2 Verify no other sections modified beyond 13.2 and Last Updated headers
- [ ] 3.3 Run full test suite
- [ ] 3.4 Browser-verify rendered page on local dev server (if available)
