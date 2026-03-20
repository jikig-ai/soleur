# Tasks: infra-security agent

**Plan:** `knowledge-base/plans/2026-02-16-feat-infra-security-agent-plan.md`
**Issue:** #100
**Branch:** feat-infra-security

## Phase 1: Core Implementation

- [x] 1.1 Create agent file at `plugins/soleur/agents/engineering/infra/infra-security.md`
  - YAML frontmatter (name, description with 3 examples, model: inherit)
  - Environment Setup section (CF_API_TOKEN, CF_ZONE_ID, graceful degradation)
  - Audit Protocol section (Cloudflare API queries, dig/openssl fallback, severity grading)
  - Configure Protocol section (CRUD DNS records, toggle settings, confirmation gate)
  - GitHub Pages wire recipe (CNAME, apex A records, SSL Full, user instructions for GitHub side)
  - Scope section (boundaries with sibling agents)

## Phase 2: Version Bump and Documentation

- [x] 2.1 Bump `plugins/soleur/plugin.json` version 2.10.2 -> 2.11.0
- [x] 2.2 Add v2.11.0 entry to `plugins/soleur/CHANGELOG.md`
- [x] 2.3 Update `plugins/soleur/README.md` agent count (27 -> 28), add to Infra table

## Phase 3: Quality Gates

- [ ] 3.1 Code review, compound, stage all artifacts, commit, push, PR
