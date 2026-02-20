---
title: "feat: Add Legal Agents & Skills"
type: feat
date: 2026-02-19
issue: "#114"
version-bump: MINOR
---

# feat: Add Legal Agents & Skills

## Overview

Add a new Legal top-level agent domain with two agents (`legal-document-generator`, `legal-compliance-auditor`) and two skills (`legal-generate`, `legal-audit`) for generating and auditing legal documents. Supports 7 document types: Terms & Conditions, Privacy Policy, Cookie Policy, GDPR Policy, Acceptable Use Policy, Data Processing Agreement, Disclaimer / Limitation of Liability. All output clearly marked as drafts requiring professional legal review.

## Problem Statement / Motivation

The Soleur plugin has no legal domain. Users building products need legal documents but must draft them manually or use external tools. The soleur.ai website itself has no legal pages. Adding legal as a first-class domain lets users generate comprehensive draft legal documents from their company context and audit existing documents for gaps and compliance issues.

## Proposed Solution

4 new plugin components organized into a 5th top-level domain:

| Component | Type | Path | Purpose |
|-----------|------|------|---------|
| `legal-document-generator` | Agent | `agents/legal/legal-document-generator.md` | Generate draft legal documents from company context |
| `legal-compliance-auditor` | Agent | `agents/legal/legal-compliance-auditor.md` | Audit existing legal documents for gaps and compliance |
| `legal-generate` | Skill | `skills/legal-generate/SKILL.md` | User-facing generation workflow |
| `legal-audit` | Skill | `skills/legal-audit/SKILL.md` | User-facing audit workflow |

Plus docs integration, versioning updates, and optional CSS variable addition.

## Non-Goals

- Providing actual legal advice or replacing professional legal counsel
- Automated cookie consent banners or GDPR consent management UI
- Legal document version tracking or diff tooling
- Jurisdiction-specific legal database or case law references
- A dedicated publishing agent for Eleventy pages
- Eleventy .njk output format (v1 outputs markdown only; .njk wrapping is a follow-up)
- Batch generation of all 7 documents in one command (run the skill per document type)
- Persistent company context config file (gather interactively each time; config file is v2 if users request it)

## Technical Approach

### File Changes

**New files (4):**

1. `plugins/soleur/agents/legal/legal-document-generator.md`
2. `plugins/soleur/agents/legal/legal-compliance-auditor.md`
3. `plugins/soleur/skills/legal-generate/SKILL.md`
4. `plugins/soleur/skills/legal-audit/SKILL.md`

**Modified files (8):**

5. `plugins/soleur/docs/_data/agents.js` -- Add `legal` to `DOMAIN_LABELS`, `DOMAIN_CSS_VARS`, `domainOrder`
6. `plugins/soleur/docs/_data/skills.js` -- Add `legal-generate` and `legal-audit` to `SKILL_CATEGORIES`
7. `plugins/soleur/docs/css/style.css` -- Add `--cat-legal` CSS variable in `@layer tokens`
8. `plugins/soleur/.claude-plugin/plugin.json` -- MINOR bump, update description counts (35 agents, 44 skills)
9. `plugins/soleur/CHANGELOG.md` -- Add version entry
10. `plugins/soleur/README.md` -- Add Legal domain section, update component counts
11. Root `README.md` -- Update version badge and agent/skill counts
12. `.github/ISSUE_TEMPLATE/bug_report.yml` -- Update version placeholder

### Agent: `legal-document-generator`

```markdown
# plugins/soleur/agents/legal/legal-document-generator.md
```

**Frontmatter:**
- `name: legal-document-generator`
- `description:` Third-person with 2 inline `<example>` blocks (generate a privacy policy, generate terms & conditions)
- `model: inherit`

**Body -- sharp-edges-only (3 instructions):**
1. Mandatory "DRAFT - Requires professional legal review" disclaimer as blockquote at top and bottom of every document
2. Output format: markdown with YAML frontmatter (`title`, `type`, `jurisdiction`, `generated-date`)
3. Cross-reference hints: when generating a document that references another type (e.g., privacy policy mentions cookies), note the reference and suggest generating the companion document

The model already knows legal document structure, GDPR requirements, standard sections, and jurisdiction-specific clauses. Do not duplicate that knowledge in the prompt.

### Agent: `legal-compliance-auditor`

```markdown
# plugins/soleur/agents/legal/legal-compliance-auditor.md
```

**Frontmatter:**
- `name: legal-compliance-auditor`
- `description:` Third-person with 2 inline `<example>` blocks (audit a privacy policy, audit all legal docs for cross-consistency)
- `model: inherit`

**Body -- sharp-edges-only (3 instructions):**
1. Finding output format: `[SEVERITY] Section > Issue > Recommendation` with summary counts
2. Cross-document consistency: when multiple documents are provided, check that references between them are consistent (e.g., privacy policy mentions cookies --> cookie policy must exist and align)
3. Never persist audit findings to files -- output inline in conversation only (constitution requirement for open-source repos)

The model already knows GDPR/CCPA/UK GDPR requirements, standard audit methodology, and common compliance gaps. Do not duplicate that knowledge in the prompt.

### Skill: `legal-generate`

```markdown
# plugins/soleur/skills/legal-generate/SKILL.md
```

**Frontmatter:**
- `name: legal-generate`
- `description:` "This skill should be used when generating draft legal documents..."

**Phases:**

1. **Phase 0: Context Gathering** -- Use AskUserQuestion to gather company context interactively: company name, product description, data practices, jurisdiction, contact info.

2. **Phase 1: Document Selection** -- Use AskUserQuestion to select which document type to generate from the 7 supported types.

3. **Phase 2: Generation** -- Invoke `legal-document-generator` agent via Task tool with company context and selected document type.

4. **Phase 3: Output** -- Write markdown to user-specified path or default `docs/legal/<type>.md`. Display file path and remind user the document is a draft requiring legal review.

### Skill: `legal-audit`

```markdown
# plugins/soleur/skills/legal-audit/SKILL.md
```

**Frontmatter:**
- `name: legal-audit`
- `description:` "This skill should be used when auditing existing legal documents for compliance gaps..."

**Phases:**

1. **Phase 0: Discovery** -- Scan project for existing legal documents in common locations. Present found documents and ask user to confirm scope.

2. **Phase 1: Context** -- Use AskUserQuestion for jurisdiction context (US, EU/GDPR, UK, or multiple). Read each document.

3. **Phase 2: Audit** -- Invoke `legal-compliance-auditor` agent via Task tool with all documents and jurisdiction context. The agent performs per-document analysis plus cross-document consistency checks.

4. **Phase 3: Report** -- Display findings inline in conversation (never persist security/compliance findings to files in open-source repos per constitution). Offer to generate fix suggestions for Critical and High findings.

### Docs Integration

- **`agents.js`:** Add `legal: "Legal"` to `DOMAIN_LABELS`, `legal: "var(--cat-legal)"` to `DOMAIN_CSS_VARS`, and `"legal"` to the end of `domainOrder` array.
- **`skills.js`:** Add `"legal-generate": "Content & Release"` and `"legal-audit": "Content & Release"` to `SKILL_CATEGORIES`. Both skills operate on legal content at different lifecycle stages (create vs validate), matching the pattern of content-writer and seo-aeo both being in Content & Release.
- **`style.css`:** Add `--cat-legal: #6C8EBF` (steel blue) to `@layer tokens :root`. Verify visual distinctness from existing category colors.

### Version Bump

- Current version: `2.19.0`
- Bump type: MINOR (2 new agents + 2 new skills)
- New version: `2.20.0`
- New counts: 35 agents, 8 commands, 44 skills

**Note:** Specify intent (MINOR) not exact version number. If another PR merges first, adjust accordingly.

## Open Questions to Resolve During Implementation

1. **Soleur.ai dogfooding:** Generating soleur.ai's own legal pages should be a follow-up PR after the tools are merged. The current site is static with no cookies/analytics, which simplifies the content significantly.

2. **CSS variable:** `--cat-legal: #6C8EBF` is a suggestion. May need adjustment to fit the existing palette's visual balance.

## Acceptance Criteria

- [x] `legal-document-generator` agent generates all 7 document types with jurisdiction-aware content
- [x] `legal-compliance-auditor` agent produces structured findings reports with severity ratings
- [x] `legal-generate` skill gathers context interactively and writes markdown output files
- [x] `legal-audit` skill discovers legal documents, invokes auditor, and displays findings inline
- [x] All generated documents include "DRAFT - Requires professional legal review" disclaimers
- [x] Agent descriptions use third-person with inline `<example>` blocks
- [x] Skill descriptions use third-person ("This skill should be used when...")
- [x] Agent prompts follow sharp-edges-only principle
- [x] Legal domain appears on docs site agents page with correct styling
- [x] Legal skills appear on docs site skills page under "Content & Release"
- [x] Plugin version bumped (MINOR) with changelog entry
- [x] Root README.md version badge and component counts match plugin.json
- [x] `.github/ISSUE_TEMPLATE/bug_report.yml` version placeholder updated
- [x] Legal CSS variable visually distinct from existing category colors
- [x] Audit findings displayed inline only, never written to files (constitution compliance)
- [ ] All 12 new/modified files committed together

## Test Scenarios

### Generation Flow

- Given the user runs `/legal-generate`, when they provide company context and select "Privacy Policy" with EU/GDPR jurisdiction, then a markdown file is written with GDPR-specific sections and a "DRAFT" disclaimer blockquote at top and bottom
- Given the user runs `/legal-generate`, when they provide company context and select "Terms & Conditions" with US jurisdiction, then the output includes standard US terms sections (acceptance, IP, liability, termination)

### Audit Flow

- Given a project has `docs/legal/privacy-policy.md` and `docs/legal/cookie-policy.md`, when the user runs `/legal-audit` with EU/GDPR jurisdiction, then the auditor checks both documents individually AND cross-references them for consistency
- Given a privacy policy mentions cookie tracking but no cookie policy exists, when audited, then a Critical finding is reported for missing cross-referenced document
- Given no legal documents are found in the project, when the user runs `/legal-audit`, then the skill reports "No legal documents found" with suggestions for where to create them

### Edge Cases

- Given the user requests a Data Processing Agreement (B2B document), when generated, then the output includes sub-processor obligations and audit rights sections not present in consumer-facing documents
- Given multiple jurisdictions are selected (US + EU/GDPR), when a document is generated, then jurisdiction-specific sections are clearly labeled and separated
- Given a legal document contains outdated references (e.g., EU-US Privacy Shield instead of Data Privacy Framework), when audited, then a High finding is raised with the current correct reference

### Constitution Compliance

- Given the user runs `/legal-audit`, when findings are generated, then the report is displayed inline in conversation and NOT written to any file in the repository

### Plugin Integration

- Given the new agents are committed, when the Eleventy docs site is built, then the Legal domain appears with correct count, label, and CSS color
- Given the new skills are committed and registered in `skills.js`, when the docs site is built, then both `legal-generate` and `legal-audit` appear under "Content & Release"

## Dependencies & Risks

- **No external dependencies.** All components are markdown files with no runtime requirements.
- **Risk: Agent prompt bloat.** Legal documents have extensive requirements per jurisdiction. Keep prompts to sharp edges only -- the model already knows legal document structures and GDPR requirements.
- **Risk: Dogfooding scope creep.** Generating soleur.ai legal pages should be a separate follow-up, not part of this PR.

## References & Research

### Internal References

- Agent pattern: `plugins/soleur/agents/marketing/brand-architect.md`
- Skill pattern: `plugins/soleur/skills/content-writer/SKILL.md`
- Docs agent data: `plugins/soleur/docs/_data/agents.js:5` (DOMAIN_LABELS)
- Docs skill data: `plugins/soleur/docs/_data/skills.js:8` (SKILL_CATEGORIES)
- CSS tokens: `plugins/soleur/docs/css/style.css:41` (category color vars)
- Plugin config: `plugins/soleur/.claude-plugin/plugin.json`

### Key Learnings Applied

- Skills must be flat at `skills/<name>/SKILL.md` -- loader does not recurse (learning: plugin-loader-agent-vs-skill-recursion)
- Skills need manual registration in `docs/_data/skills.js` SKILL_CATEGORIES -- silent failure if missed (learning: growth-strategist-agent-skill-development)
- Agent prompts: sharp-edges-only, ~65% reduction from typical first drafts (learning: growth-strategist-agent-skill-development)
- New agents not loadable mid-session -- use `general-purpose` agent type for live testing (learning: growth-strategist-agent-skill-development)
- Version bump is MINOR for new agents/skills (learning: version-bump-for-wiring-existing-agents)
- Compliance findings must not be persisted to files in open-source repos (constitution: security-sentinel pattern)

### Related

- Issue: #114
- Brainstorm: `knowledge-base/brainstorms/2026-02-19-legal-agents-brainstorm.md`
- Spec: `knowledge-base/specs/feat-legal-agents/spec.md`
