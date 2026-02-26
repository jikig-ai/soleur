# Tasks: feat-cla-contributor-agreements

## Phase 1: CLA Documents

- [ ] 1.1 Fetch Apache ICLA template text via `curl`
- [ ] 1.2 Fetch Apache CCLA template text via `curl`
- [ ] 1.3 Draft Individual CLA adapted for BSL 1.1 + Jikigai
  - Copyright license grant (perpetual, irrevocable, non-exclusive, worldwide, royalty-free)
  - Patent grant covering contributed code
  - Relicensing right under any license terms selected by Jikigai
  - Representations section (authority, original work)
  - French moral rights awareness in patent clause
  - No DRAFT banner; footer note about professional legal review
  - Files: `docs/legal/individual-cla.md`
- [ ] 1.4 Draft Corporate CLA adapted for BSL 1.1 + Jikigai
  - Same license/patent structure as Individual CLA
  - Corporate-specific: authorized representative, covered employees/GitHub usernames
  - Files: `docs/legal/corporate-cla.md`
- [ ] 1.5 Create Eleventy site copies of both CLAs
  - Match existing legal page format (layout: base.njk, page-hero section, prose div)
  - Files: `plugins/soleur/docs/pages/legal/individual-cla.md`, `plugins/soleur/docs/pages/legal/corporate-cla.md`
- [ ] 1.6 Verify cross-document consistency (entity name, jurisdiction, contact) against existing legal docs

## Phase 2: CLA Enforcement

- [ ] 2.1 Create CLA Assistant GitHub Action workflow
  - File: `.github/workflows/cla.yml`
  - Trigger: `pull_request_target` + `issue_comment`
  - Pin action to commit SHA
  - Explicit `permissions:` block
  - Bot allowlist: `dependabot[bot]`, `github-actions[bot]`, `renovate[bot]`
  - Point to Individual CLA URL
- [ ] 2.2 Document manual step: add branch ruleset requiring CLA check (post-merge)

## Phase 3: Contributor-Facing Updates

- [ ] 3.1 Update CONTRIBUTING.md with CLA section
  - Plain-language explanation (what, why, what it means)
  - Links to CLA documents
  - Guidance for employed contributors
- [ ] 3.2 Update PR template with CLA notice
  - File: `.github/PULL_REQUEST_TEMPLATE.md`
  - Informational notice with link (not checkbox)

## Phase 4: Cross-Document Updates

- [ ] 4.1 Update privacy policy (both locations) -- add CLA signature data processing section
- [ ] 4.2 Update data protection disclosure (both locations) -- add CLA processing activity
- [ ] 4.3 Update T&C Section 5 (both locations) -- acknowledge contributor CLA framework
- [ ] 4.4 Update "Related documents" sections in all existing legal docs (14 files: 7 source + 7 site)

## Phase 5: Docs Site and Versioning

- [ ] 5.1 Update legal hub page (`plugins/soleur/docs/pages/legal.njk`) -- add 2 CLA cards, count 7 → 9
- [ ] 5.2 Bump version 3.3.5 → 3.4.0 in `plugin.json`
- [ ] 5.3 Add CHANGELOG.md entry for 3.4.0
- [ ] 5.4 Update README.md (plugin) version reference
- [ ] 5.5 Update root README.md version badge
- [ ] 5.6 Update `.github/ISSUE_TEMPLATE/bug_report.yml` placeholder
- [ ] 5.7 Run cross-document consistency audit (legal-compliance-auditor)
