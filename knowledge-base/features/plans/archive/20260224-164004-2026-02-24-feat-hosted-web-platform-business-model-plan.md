---
title: feat: Switch License from Apache-2.0 to BSL 1.1
type: feat
date: 2026-02-24
---

# Switch License from Apache-2.0 to BSL 1.1

## Overview

Transition the Soleur project from Apache-2.0 to BSL 1.1 (Business Source License) to protect the intellectual property of the agent orchestration architecture, 60+ agent definitions, and skill system, while keeping the source available for individual use.

**Brainstorm:** `knowledge-base/brainstorms/2026-02-24-business-model-brainstorm.md`
**Issue:** #287
**Follow-up:** #297 (Web Platform UX and Architecture)

## Problem Statement

Soleur is currently Apache-2.0, which allows anyone -- including well-funded competitors -- to fork the entire project and offer it as a competing hosted service. As the project moves toward a hosted web platform (#297), protecting the IP before launch is essential. The CLI plugin's orchestration architecture, 60+ agent definitions, and 50 skills represent significant intellectual property worth protecting.

## Proposed Solution

Switch to BSL 1.1 with an Additional Use Grant that allows individual self-hosting but blocks competing hosted services. Prior Apache-2.0 versions are grandfathered.

### BSL 1.1 Parameters

| Parameter | Value |
|-----------|-------|
| Licensor | Jikigai |
| Licensed Work | Soleur v3.1.0 and later |
| Additional Use Grant | Production use is permitted for any purpose except offering the Licensed Work as a hosted or managed service that competes with Licensor's commercial offerings |
| Change Date | 4 years from each version release |
| Change License | Apache License 2.0 |

### What This Means for Users

| Use Case | Permitted? |
|----------|-----------|
| Install and use the CLI plugin for personal projects | Yes |
| Use Soleur in your company internally | Yes |
| Fork and modify for personal/internal use | Yes |
| Study the source code and learn from it | Yes |
| Contribute back via pull requests | Yes |
| Offer a competing hosted Soleur-as-a-Service product | No (requires commercial license) |
| After 4 years, do anything (it becomes Apache-2.0) | Yes |

## Technical Approach

### Files to Update

| File | Change |
|------|--------|
| `LICENSE` (root) | Replace Apache-2.0 text with BSL 1.1 text |
| `plugins/soleur/LICENSE` | Replace Apache-2.0 text with BSL 1.1 text |
| `plugins/soleur/.claude-plugin/plugin.json` | Change `"license": "Apache-2.0"` to `"license": "BUSL-1.1"` |
| `plugins/soleur/README.md` | Update license badge and license section |
| Root `README.md` | Update license badge |
| `plugins/soleur/CHANGELOG.md` | Add entry under new version |
| `docs/legal/` | Update Terms of Service to reference BSL 1.1 |
| `plugins/soleur/docs/pages/legal/` | Sync legal page templates |

### What Does NOT Change

- `plugins/soleur/NOTICE` -- MIT attribution from third-party code (marketingskills) is unaffected by the root license change
- Agent .md files, skill SKILL.md files, command .md files -- content stays the same, only the license governing them changes
- Plugin functionality -- no behavioral changes

### Version Bump

MINOR bump (not MAJOR). Per Kieran's review: a license change is not a functional breaking change. It doesn't change how the plugin operates. Communicate the license change through CHANGELOG and README, not through version inflation.

Current version: 3.0.9 -> New version: 3.1.0

### Communication Plan

1. **CHANGELOG entry:** Clear explanation of what changed, why, and what it means for users
2. **README section:** "License" section updated with BSL 1.1 explanation and FAQ
3. **GitHub Discussion or issue comment:** Link to BSL 1.1 FAQ, explain grandfathering
4. **Note about grandfathering:** Prior versions (v3.0.9 and earlier) remain Apache-2.0. Existing forks at those versions keep their Apache-2.0 rights.

### BSL 1.1 License Template

The BSL 1.1 template is published at mariadb.com/bsl11/. Fill in the four parameters (Licensor, Licensed Work, Additional Use Grant, Change Date/License) and the license text is complete.

**Additional Use Grant wording is critical.** The grant must:
- Clearly allow individual and internal company use
- Clearly block competing hosted/managed services
- Not accidentally block users who deploy Soleur internally for their company

Reference implementations: HashiCorp Terraform, Sentry, CockroachDB all use similar Option A grants.

## Acceptance Criteria

- [ ] BSL 1.1 license text with correct parameters in both LICENSE files
- [ ] `plugin.json` license field updated to `BUSL-1.1`
- [ ] README badges and sections updated in both READMEs
- [ ] CHANGELOG entry under v3.1.0 explaining the change
- [ ] Legal docs on docs site updated to reference BSL 1.1
- [ ] Communication posted (GitHub Discussion or issue comment)
- [ ] NOTICE file reviewed (MIT attribution preserved)
- [ ] Version bumped to 3.1.0 across plugin.json, CHANGELOG.md, README.md

## Test Scenarios

- Given an existing Apache-2.0 fork (v3.0.9), when the license changes, then the fork retains Apache-2.0 rights for that version
- Given a new user installing v3.1.0+, when they read the LICENSE, then they see BSL 1.1 with clear Additional Use Grant
- Given the Claude Code plugin registry, when the license field is `BUSL-1.1`, then the plugin is still installable (registry has no license restrictions)

## Risk Analysis

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Community backlash (OpenTofu precedent) | Low (project has minimal external community) | Medium | Clear communication, grandfathering, 4-year conversion clause |
| Additional Use Grant wording too broad/narrow | Medium | High | Reference HashiCorp/Sentry implementations, consider external legal review |
| Plugin registry rejects BSL | Very Low | High | Verified: registry has no license restrictions |

## Dependencies

None. This is a standalone change with no external dependencies.

## References

- BSL 1.1 template: mariadb.com/bsl11/
- HashiCorp license FAQ (reference for communication): hashicorp.com/license-faq
- Existing learning on API key security: `knowledge-base/learnings/2026-02-10-api-key-leaked-in-git-history-cleanup.md`
- Related issues: #297 (Web Platform), #286 (Open Source Strategy)
