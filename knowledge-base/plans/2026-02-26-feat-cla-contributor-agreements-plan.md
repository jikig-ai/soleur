---
title: Add Contributor License Agreement System
type: feat
date: 2026-02-26
---

# Add Contributor License Agreement System

## Overview

Add Individual and Corporate CLAs to the Soleur repository with automated enforcement via the CLA Assistant GitHub Action. This enables safe acceptance of external contributions while supporting Jikigai's BSL 1.1 + dual licensing strategy.

## Problem Statement / Motivation

Soleur uses BSL 1.1 and plans dual licensing (commercial + BSL). No mechanism exists defining what IP rights Jikigai receives when contributors submit PRs. Without a CLA:

- Contributor code cannot be relicensed under commercial terms
- The BSL 1.1 → Apache 2.0 change-date conversion has legal ambiguity
- No patent grant protects users from contributor-asserted patents

One contributor is interested but hasn't submitted yet -- timing is ideal to get this in place before the first external contribution.

## Proposed Solution

### Architecture Decisions

1. **CLA type:** Copyright license grant (not assignment). Contributor retains copyright; Jikigai gets perpetual, irrevocable license including relicensing rights. Industry standard for BSL projects (CockroachDB, Elastic, HashiCorp).

2. **Integration mechanism:** `cla-assistant/cla-assistant-action` GitHub Action (not the hosted App). Stores signatures in a GitHub gist, keeping data within GitHub. Consistent with the existing "no external servers" privacy stance. Requires a new workflow file.

3. **Enforcement:** Add a repository ruleset requiring the CLA status check to pass before merge on the `main` branch. Without this, the CLA is advisory only.

4. **DRAFT status:** Remove DRAFT banner from CLA documents specifically. A document contributors digitally sign should not be marked DRAFT. Note in the document footer that professional legal review is still recommended.

5. **Entity name:** "Jikigai" (the incorporated company) as the receiving entity, "Soleur" as the project name. Consistent with T&C wording.

6. **Bot exemptions:** Allow `dependabot[bot]`, `github-actions[bot]`, `renovate[bot]` in CLA config.

7. **CLA versioning:** Contributions made under CLA v1 remain covered by v1 terms. New contributors and re-signing on the next PR after a version change.

8. **Two separate documents:** Individual CLA and Corporate CLA as separate files, matching industry convention (Apache, Google, Microsoft).

### Template Source

Adapt Apache ICLA/CCLA as starting templates:
- Replace Apache License 2.0 references with "any license terms selected by Jikigai"
- Add express patent grant clause
- Include "Representations" section (signer warrants authority)
- Address French moral rights in patent clause (droits moraux are inalienable)
- Scope to `jikig-ai/soleur` repository initially

## Technical Considerations

- **Dual-location legal docs:** Both `docs/legal/` (source markdown) and `plugins/soleur/docs/pages/legal/` (Eleventy site) must be updated in lockstep. Different frontmatter formats.
- **Cross-document consistency:** Entity: "Jikigai, incorporated in France", Contact: legal@jikigai.com, Jurisdiction: "EU, US". All 7 existing docs use these values.
- **Privacy policy update required:** CLA signatures collect personal data (GitHub username, timestamp). Current privacy policy says "no personal data collected on external servers." Must add CLA disclosure. Ship in same PR.
- **GitHub Actions security:** Pin to commit SHAs, declare explicit `permissions:` block.
- **Legal hub page is hardcoded:** Count "7" and card entries in `legal.njk` must be manually updated to 9.
- **SHA pinning inconsistency:** Existing workflows use tags (`@v4`), not SHAs. Apply SHA pinning to the new CLA workflow only; retrofitting existing workflows is out of scope.

## Implementation Phases

### Phase 1: CLA Documents (Core)

Draft both CLA documents using Apache ICLA/CCLA as templates adapted for BSL 1.1.

**Create:**
- `docs/legal/individual-cla.md` -- source markdown with `type: individual-cla` frontmatter
- `docs/legal/corporate-cla.md` -- source markdown with `type: corporate-cla` frontmatter
- `plugins/soleur/docs/pages/legal/individual-cla.md` -- Eleventy page with `layout: base.njk`, `permalink: pages/legal/individual-cla.html`
- `plugins/soleur/docs/pages/legal/corporate-cla.md` -- Eleventy page with `layout: base.njk`, `permalink: pages/legal/corporate-cla.html`

**Key CLA clauses:**
- Copyright license grant: perpetual, irrevocable, non-exclusive, worldwide, royalty-free
- Patent grant: express grant covering contributed code
- Relicensing right: "under any license terms selected by Jikigai"
- Representations: signer warrants authority, original work, not encumbered
- No DRAFT banner (footer note: "This document should be reviewed by qualified legal counsel")

### Phase 2: CLA Enforcement

**Create:**
- `.github/workflows/cla.yml` -- CLA Assistant Action workflow
  - Trigger: `pull_request_target` (opened, synchronize, reopened) + `issue_comment` (for re-check)
  - Pin `cla-assistant/cla-assistant-action` to commit SHA
  - Declare explicit `permissions: actions: write, contents: read, pull-requests: write, statuses: write`
  - Configure: `path-to-signatures: signatures/cla.json` (gist-based) or inline gist ID
  - Allowlist: `dependabot[bot],github-actions[bot],renovate[bot]`
  - Point to CLA text: Individual CLA URL on docs site

**Configure (manual, post-merge):**
- Add branch ruleset or branch protection rule requiring "CLA" status check on `main`
- Document this manual step in the PR description

### Phase 3: Contributor-Facing Updates

**Modify:**
- `CONTRIBUTING.md` -- add "Contributor License Agreement" section after "Getting Started":
  - Plain-language explanation: what the CLA is, why it's needed (BSL + dual licensing), what it means (you keep copyright, Jikigai gets license)
  - Link to Individual CLA and Corporate CLA on docs site
  - Guidance for employed contributors: "If your employer owns your work, ask them to sign the Corporate CLA"
  - Link to CLA Assistant signing flow

- `.github/PULL_REQUEST_TEMPLATE.md` -- add informational notice (not checkbox):
  ```markdown
  ## CLA
  By submitting this PR, you confirm you have signed the [Contributor License Agreement](https://soleur.ai/pages/legal/individual-cla.html). First-time contributors will be prompted automatically.
  ```

### Phase 4: Cross-Document Updates

**Modify:**
- `docs/legal/privacy-policy.md` + `plugins/soleur/docs/pages/legal/privacy-policy.md` -- add section on CLA signature data processing (GitHub username, timestamp, legal basis: legitimate interest under GDPR Art. 6(1)(f))
- `docs/legal/data-processing-agreement.md` + `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` -- add CLA as a processing activity
- `docs/legal/terms-and-conditions.md` + `plugins/soleur/docs/pages/legal/terms-and-conditions.md` -- update Section 5 to acknowledge contributor IP framework via CLA
- All 7 existing legal docs: update "Related documents" sections to include CLA references (14 files total -- 7 source + 7 site)

### Phase 5: Docs Site and Versioning

**Modify:**
- `plugins/soleur/docs/pages/legal.njk` -- add 2 new card entries (Individual CLA, Corporate CLA), update count from 7 to 9, category: "Agreement"
- `plugins/soleur/.claude-plugin/plugin.json` -- bump version `3.3.5` → `3.4.0`
- `plugins/soleur/CHANGELOG.md` -- add `[3.4.0]` entry under `### Added`
- `plugins/soleur/README.md` -- update version reference
- `README.md` (root) -- update version badge from `3.3.5` to `3.4.0`
- `.github/ISSUE_TEMPLATE/bug_report.yml` -- update placeholder from `3.3.5` to `3.4.0`

## Acceptance Criteria

- [ ] Individual CLA document exists in both `docs/legal/` and `plugins/soleur/docs/pages/legal/`
- [ ] Corporate CLA document exists in both locations
- [ ] CLA documents do NOT carry DRAFT banner
- [ ] CLA Assistant GitHub Action workflow exists and runs on PRs
- [ ] Bot accounts (dependabot, github-actions, renovate) are exempt
- [ ] CONTRIBUTING.md has CLA section with plain-language explanation
- [ ] PR template has CLA notice
- [ ] Privacy policy updated to disclose CLA signature collection
- [ ] Data protection disclosure updated with CLA processing activity
- [ ] T&C Section 5 references contributor CLA framework
- [ ] All existing legal docs have CLA in "Related documents"
- [ ] Legal hub page shows 9 documents with both CLA cards
- [ ] Plugin version bumped to 3.4.0 across triad
- [ ] Cross-document consistency verified (entity name, jurisdiction, contact)

## Test Scenarios

- Given a first-time contributor opens a PR, when CLA check runs, then the PR is blocked with a signing prompt
- Given the contributor signs via GitHub OAuth, when the check re-runs, then the PR passes
- Given a returning contributor who already signed opens a new PR, when CLA check runs, then it passes immediately
- Given dependabot opens an automated PR, when CLA check runs, then it passes (exempt)
- Given a corporate contributor whose employer has signed the Corporate CLA, when CLA check runs, then it passes

## Success Metrics

- CLA check blocks all external PRs from unsigned contributors
- First external contributor successfully signs and merges
- No legal ambiguity about IP ownership of contributed code
- Privacy policy accurately reflects data processing activities

## Dependencies & Risks

| Risk | Mitigation |
|---|---|
| CLA deters contributors | Clear plain-language explanation in CONTRIBUTING.md; industry-standard approach |
| French moral rights complicate patent grant | Draft patent clause aware of inalienable moral rights; note for legal review |
| Branch protection rule must be set manually | Document in PR description; add to acceptance criteria checklist |
| CLA Assistant action may change API | Pin to commit SHA; monitor for updates |
| GDPR right-to-erasure vs irrevocable license grant | CLA text clarifies license survives withdrawal of signature record |

## References & Research

### Internal References
- Brainstorm: `knowledge-base/brainstorms/2026-02-26-cla-contributor-agreements-brainstorm.md`
- Spec: `knowledge-base/specs/feat-cla-contributor-agreements/spec.md`
- BSL migration learning: `knowledge-base/learnings/2026-02-24-bsl-license-migration-pattern.md`
- Cross-doc consistency learning: `knowledge-base/learnings/2026-02-20-dogfood-legal-agents-cross-document-consistency.md`
- GH Actions security learning: `knowledge-base/learnings/2026-02-21-github-actions-workflow-security-patterns.md`
- Private doc generation: `knowledge-base/learnings/2026-02-21-private-document-generation-pattern.md`

### External References
- Apache ICLA template: https://www.apache.org/licenses/icla.pdf
- Apache CCLA template: https://www.apache.org/licenses/cla-corporate.pdf
- CLA Assistant Action: https://github.com/cla-assistant/cla-assistant-action
- BSL 1.1 text: https://mariadb.com/bsl11/

### Related Work
- Issue: #320
- PR: #319 (draft)
- Prior brainstorm: community contributor audit (2026-02-10, archived)
