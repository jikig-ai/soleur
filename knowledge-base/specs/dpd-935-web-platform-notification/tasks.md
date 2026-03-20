# Tasks: DPD Section 13.2 Web Platform Notification Channel

## Phase 1: Setup

- [x] 1.1 Merge origin/main to get latest DPD state
- [x] 1.2 Verify Section 13.2 current text matches expected baseline

## Phase 2: Core Implementation

- [x] 2.1 Update Section 13.2 in `docs/legal/data-protection-disclosure.md`
- [x] 2.2 Update Section 13.2 in `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- [x] 2.3 Update "Last Updated" header in `docs/legal/data-protection-disclosure.md` (line 12)
- [x] 2.4 Update "Last Updated" header in `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` HTML hero (line 11)
- [x] 2.5 Update "Last Updated" header in `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` markdown (line 21)

## Phase 3: Validation

- [x] 3.1 Diff both DPD copies to verify only expected differences (frontmatter, HTML wrapper, link paths)
- [x] 3.2 Verify no other sections modified beyond 13.2 and Last Updated headers
- [x] 3.3 Run full test suite (940 pass, 0 fail)
- [ ] 3.4 Browser-verify rendered page on local dev server (deferred to /test-browser)
