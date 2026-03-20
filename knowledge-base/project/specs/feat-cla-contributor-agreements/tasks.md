# Tasks: feat-cla-contributor-agreements

## Phase 1: CLA Documents

- [x] 1.1 Draft Individual CLA (source + Eleventy site copy)
  - Adapt Apache ICLA for BSL 1.1 + Jikigai
  - Copyright license grant, patent grant, relicensing right, representations
  - French moral rights awareness in patent clause
  - No DRAFT banner; footer note about professional legal review
  - Eleventy copy: `layout: base.njk`, `description:` field, `permalink:`
  - Files: `docs/legal/individual-cla.md`, `plugins/soleur/docs/pages/legal/individual-cla.md`
- [x] 1.2 Draft Corporate CLA (source + Eleventy site copy)
  - Adapt Apache CCLA for BSL 1.1 + Jikigai
  - Same license/patent structure; corporate-specific: authorized representative, covered employees
  - Files: `docs/legal/corporate-cla.md`, `plugins/soleur/docs/pages/legal/corporate-cla.md`

## Phase 2: CLA Enforcement

- [x] 2.1 Create repo-based CLA signature storage (cla-signatures branch)
- [ ] 2.2 Add `PERSONAL_ACCESS_TOKEN` repository secret (manual)
- [x] 2.3 Create CLA Assistant GitHub Action workflow
  - File: `.github/workflows/cla.yml`
  - Trigger: `pull_request_target` + `issue_comment`
  - Pin action to commit SHA, explicit `permissions:` block
  - Bot allowlist, gist ID, CLA URL
  - Do NOT checkout PR code (security: `pull_request_target` has write access)
- [ ] 2.4 Smoke test: open throwaway PR to verify action triggers (post-merge)

## Phase 3: Contributor-Facing and Cross-Document Updates

- [x] 3.1 Update CONTRIBUTING.md with CLA section
  - Plain-language explanation, links, employed-contributor guidance
- [x] 3.2 Update privacy policy (both locations) -- CLA signature data processing, add CLA to Related Documents
- [x] 3.3 Update data protection disclosure (both locations) -- CLA as processing activity, add CLA to Related Documents
- [x] 3.4 Update T&C Section 5 (both locations) -- contributor IP framework, add CLA to Related Documents

## Phase 4: Docs Site and Versioning

- [x] 4.1 Update legal hub page (`legal.njk`) -- add 2 CLA cards, count 7 → 9
- [x] 4.2 Bump version 3.3.5 → 3.4.0 across all version locations
- [x] 4.3 Run cross-document consistency audit

## Post-Merge (manual)

- [ ] 5.1 Add branch ruleset requiring CLA status check on `main`
