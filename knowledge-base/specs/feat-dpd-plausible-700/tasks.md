# Tasks: DPD Section 6.3 Plausible EU-only hosting

## Phase 1: DPD Section 6.3 Update

- [ ] 1.1 Read `docs/legal/data-protection-disclosure.md` Section 6.3 (line ~168-170)
- [ ] 1.2 Append Plausible Analytics EU-only hosting sentence after the GitHub Pages paragraph in `docs/legal/data-protection-disclosure.md`
- [ ] 1.3 Update DPD "Last Updated" date to current date
- [ ] 1.4 Read `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` Section 6.3 (line ~177-179)
- [ ] 1.5 Apply identical change to the Eleventy source copy
- [ ] 1.6 Verify both DPD Section 6.3 copies are identical with `diff`

## Phase 2: Privacy Policy Section 10 Update

- [ ] 2.1 Read `docs/legal/privacy-policy.md` Section 10 (line ~170-178)
- [ ] 2.2 Append Plausible Analytics EU-only paragraph after the Buttondown paragraph
- [ ] 2.3 Read `plugins/soleur/docs/pages/legal/privacy-policy.md` Section 10 (line ~179-187)
- [ ] 2.4 Apply identical change to the Eleventy source copy
- [ ] 2.5 Verify both Privacy Policy Section 10 copies are identical with `diff`

## Phase 3: Validation

- [ ] 3.1 Confirm GDPR Policy Section 6 is unchanged (Plausible correctly absent from international transfer list)
- [ ] 3.2 Confirm Cookie Policy is unchanged (no international transfers section)
- [ ] 3.3 Run markdownlint on all 4 modified files
- [ ] 3.4 Run compound
