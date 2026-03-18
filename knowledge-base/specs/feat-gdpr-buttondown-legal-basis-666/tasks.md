# Tasks: Clarify Legal Basis for Buttondown Data (#666)

## Phase 1: Setup

- [x] 1.1 Merge origin/main into feature branch
- [x] 1.2 Verify all 6 target files exist

## Phase 2: Privacy Policy Updates (2 files)

- [x] 2.1 Update `docs/legal/privacy-policy.md` Last Updated date
- [x] 2.2 Update Section 4.6 — expand data collected, split lawful basis
- [x] 2.3 Update Section 5.3 — mention technical metadata in Buttondown description
- [x] 2.4 Update Section 6 — newsletter legal basis paragraph
- [x] 2.5 Update Section 7 — split retention for email vs technical metadata
- [x] 2.6 Mirror all changes to `plugins/soleur/docs/pages/legal/privacy-policy.md`

## Phase 3: GDPR Policy Updates (2 files)

- [x] 3.1 Update `docs/legal/gdpr-policy.md` Last Updated date
- [x] 3.2 Update Section 3.6 — split basis with balancing test
- [x] 3.3 Update Section 4.2 table — Buttondown row with full data types
- [x] 3.4 Update Section 10 — processing register activity #6
- [x] 3.5 Mirror all changes to `plugins/soleur/docs/pages/legal/gdpr-policy.md`

## Phase 4: DPD Updates (2 files)

- [x] 4.1 Update `docs/legal/data-processing-agreement.md` — Section 2.3(e), Last Updated
- [x] 4.2 Update `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` — Section 2.3(e), Last Updated

## Phase 5: Verification

- [x] 5.1 Grep: no remaining "Email address only" across all legal docs
- [x] 5.2 Grep: all files mention legitimate interest for newsletter metadata
- [x] 5.3 Diff: both Privacy Policy copies match
- [x] 5.4 Diff: both GDPR Policy copies match
- [x] 5.5 Diff: both DPD copies match
- [ ] 5.6 Commit all 6 files atomically
