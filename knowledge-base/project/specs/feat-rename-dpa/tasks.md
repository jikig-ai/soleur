# Tasks: Rename data-processing-agreement.md to data-protection-disclosure.md

## Phase 1: File Rename

- [x] 1.1 `git add docs/legal/data-processing-agreement.md` (ensure tracked before mv)
- [x] 1.2 `git mv docs/legal/data-processing-agreement.md docs/legal/data-protection-disclosure.md`
- [x] 1.3 Verify `git log --follow docs/legal/data-protection-disclosure.md` shows history

## Phase 2: Frontmatter Update

- [x] 2.1 Edit `docs/legal/data-protection-disclosure.md` -- change `type: data-processing-agreement` to `type: data-protection-disclosure`

## Phase 3: Agent and Skill Updates

- [x] 3.1 Edit `plugins/soleur/agents/legal/legal-document-generator.md` line 11 -- change "Data Processing Agreement" to "Data Protection Disclosure" in supported types list
- [x] 3.2 Edit `plugins/soleur/agents/legal/legal-document-generator.md` line 39 -- change `data-processing-agreement` to `data-protection-disclosure` in kebab-case type values
- [x] 3.3 Edit `plugins/soleur/agents/legal/legal-document-generator.md` line 50 -- change "Data Processing Agreement" to "Data Protection Disclosure" in cross-reference hint
- [x] 3.4 Edit `plugins/soleur/skills/legal-generate/SKILL.md` line 17 -- change "Data Processing Agreement" to "Data Protection Disclosure"
- [x] 3.5 Edit `docs/legal/acceptable-use-policy.md` line 232 -- change "Data Processing Agreement" to "Data Protection Disclosure" in cross-reference hint
- [x] 3.6 Edit `docs/legal/disclaimer.md` line 202 -- change "Data Processing Agreement" to "Data Protection Disclosure" in cross-reference hint
- [x] 3.7 Edit `plugins/soleur/docs/pages/legal/acceptable-use-policy.md` line 241 -- mirror AUP cross-reference update
- [x] 3.8 Edit `plugins/soleur/docs/pages/legal/disclaimer.md` line 211 -- mirror Disclaimer cross-reference update

## Phase 4: Active Knowledge-Base Reference Updates

- [x] 4.1 Update `knowledge-base/project/learnings/2026-03-19-dpa-vendor-response-verification-lifecycle.md` -- lines 16, 25: replace `data-processing-agreement.md` with `data-protection-disclosure.md`
- [x] 4.2 Update `knowledge-base/project/plans/2026-03-18-fix-dpd-section-6-3-plausible-eu-hosting-plan.md` -- lines 57, 70, 111: replace path refs
- [x] 4.3 Update `knowledge-base/project/plans/2026-03-18-fix-buttondown-legal-basis-plan.md` -- lines 43, 88, 97, 106, 109: replace path refs
- [x] 4.4 Update `knowledge-base/project/plans/2026-03-18-chore-vendor-ops-legal-web-platform-services-plan.md` -- lines 24, 189, 232, 407: replace path refs
- [x] 4.5 Update `knowledge-base/project/plans/2026-03-18-fix-dpd-intro-paragraph-links-plan.md` -- lines 40, 79, 102, 122: replace path refs
- [x] 4.6 Update `knowledge-base/project/specs/feat-gdpr-buttondown-legal-basis-666/spec.md` -- line 51: replace path
- [x] 4.7 Update `knowledge-base/project/specs/feat-gdpr-buttondown-legal-basis-666/tasks.md` -- line 27: replace path
- [x] 4.8 Update `knowledge-base/project/specs/feat-dpd-plausible-700/tasks.md` -- lines 5-6: replace path
- [x] 4.9 Update `knowledge-base/project/specs/feat-vendor-ops-legal/tasks.md` -- line 43: replace path
- [x] 4.10 Update `knowledge-base/project/specs/feat-dpd-links-701/tasks.md` -- line 11: replace path
- [x] 4.11 Update `knowledge-base/project/plans/2026-03-18-legal-dpd-section-4-missing-processors-plan.md` -- lines 30, 45, 78, 103-104, 156: replace path
- [x] 4.12 Update `knowledge-base/project/learnings/2026-03-18-dpd-processor-table-dual-file-sync.md` -- line 5: replace path
- [x] 4.13 Update `knowledge-base/project/plans/2026-03-10-feat-newsletter-email-capture-plan.md` -- line 135: replace path and note
- [x] 4.14 Update `knowledge-base/project/specs/feat-newsletter/tasks.md` -- line 21: replace path and note

## Phase 5: Verification

- [x] 5.1 Run `grep -r "docs/legal/data-processing-agreement" --include="*.md" | grep -v "/archive/"` -- expect zero matches
- [x] 5.2 Run `grep -r "data-processing-agreement" plugins/soleur/agents/ plugins/soleur/skills/ --include="*.md"` -- expect only external vendor DPA URL matches
- [x] 5.3 Run `git log --follow docs/legal/data-protection-disclosure.md | head -5` -- verify history preserved
- [x] 5.4 Run compound before committing
