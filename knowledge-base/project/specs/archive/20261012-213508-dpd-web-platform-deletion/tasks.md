# Tasks: fix DPD Section 10.3 cross-reference error

## Phase 1: Fix Cross-Reference

- [ ] 1.1 Edit `docs/legal/data-protection-disclosure.md` Section 10.3: change "Section 13.1b" to "Section 14.1b"
- [ ] 1.2 Edit `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` Section 10.3: change "Section 13.1b" to "Section 14.1b"

## Phase 2: Verification

- [ ] 2.1 Verify both DPD files have identical Section 10.3 content
- [ ] 2.2 Verify T&C Section 14.1b exists and contains "Termination of Web Platform Account"
- [ ] 2.3 Run compound check

## Phase 3: Ship

- [ ] 3.1 Commit with message `fix(legal): correct DPD Section 10.3 cross-reference to T&C 14.1b`
- [ ] 3.2 Create PR with `Closes #906` in body
- [ ] 3.3 Merge and cleanup
