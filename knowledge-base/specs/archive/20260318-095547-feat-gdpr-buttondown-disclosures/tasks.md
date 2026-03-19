# Tasks: fix GDPR Buttondown international transfers and data retention

## Phase 1: GDPR Policy Updates

- [ ] 1.1 Update `docs/legal/gdpr-policy.md` Section 6 (International Data Transfers)
  - [ ] 1.1.1 Add Buttondown bullet after GitHub bullet: US-based processor hosted on US infrastructure, SCCs (Module 2, Controller to Processor) as transfer mechanism, link to Buttondown DPA and privacy policy
- [ ] 1.2 Update `docs/legal/gdpr-policy.md` Section 8 (Data Retention)
  - [ ] 1.2.1 Add new subsection 8.3 "Newsletter Subscriber Data": retained until unsubscription, removed from active list on unsubscribe, Buttondown may retain anonymized aggregate data, DPA termination clause (delete or return at controller's option)
  - [ ] 1.2.2 Renumber existing Section 8.3 "Third-Party Retention" to 8.4
- [ ] 1.3 Update `docs/legal/gdpr-policy.md` "Last Updated" date to March 18, 2026 (Buttondown international transfers and data retention)

## Phase 2: Privacy Policy Updates

- [ ] 2.1 Update `docs/legal/privacy-policy.md` Section 10 (International Data Transfers)
  - [ ] 2.1.1 Add Buttondown paragraph after Anthropic paragraph: US-based, SCCs per DPA, link to Buttondown DPA and privacy policy
- [ ] 2.2 Update `docs/legal/privacy-policy.md` "Last Updated" date to March 18, 2026

## Phase 3: Eleventy Docs Site Copies

- [ ] 3.1 Mirror Phase 1 changes to `plugins/soleur/docs/pages/legal/gdpr-policy.md`
  - [ ] 3.1.1 Update Section 6 body content (same as 1.1.1)
  - [ ] 3.1.2 Update Section 8 body content (same as 1.2.1, 1.2.2)
  - [ ] 3.1.3 Update "Last Updated" in both hero `<p>` tag and body text
- [ ] 3.2 Mirror Phase 2 changes to `plugins/soleur/docs/pages/legal/privacy-policy.md`
  - [ ] 3.2.1 Update Section 10 body content (same as 2.1.1)
  - [ ] 3.2.2 Update "Last Updated" in both hero `<p>` tag and body text

## Phase 4: Verification

- [ ] 4.1 Diff `docs/legal/gdpr-policy.md` body against `plugins/soleur/docs/pages/legal/gdpr-policy.md` body to confirm Section 6 and 8 content matches
- [ ] 4.2 Diff `docs/legal/privacy-policy.md` body against `plugins/soleur/docs/pages/legal/privacy-policy.md` body to confirm Section 10 content matches
- [ ] 4.3 Verify DPD files are NOT modified (intentional -- Buttondown already disclosed in Section 2.3(e))
- [ ] 4.4 Grep for "Buttondown" across all legal docs to confirm consistent disclosure
- [ ] 4.5 Verify no references to EU-US Data Privacy Framework for Buttondown (Buttondown is not DPF-certified; only SCCs apply)
- [ ] 4.6 Verify Buttondown DPA link (`https://buttondown.com/legal/data-processing-agreement`) is valid
