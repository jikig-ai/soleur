---
title: "Deploy Skill Tasks"
feature: feat-deploy-skill
date: 2026-02-13
---

# Tasks: Deploy Skill (/soleur:deploy)

## Phase 1: Setup

- [ ] 1.1 Create skill directory structure (`plugins/soleur/skills/deploy/`, `scripts/`, `references/`)

## Phase 2: Core Implementation

- [ ] 2.1 Write `SKILL.md` with YAML frontmatter and four-phase workflow (validate, plan, execute, verify)
- [ ] 2.2 Adapt `deploy.sh` from `apps/telegram-bridge/scripts/deploy.sh` -- generalize env vars, add preflight checks, add health check
- [ ] 2.3 Write `references/hetzner-setup.md` first-time setup guide

## Phase 3: Version Bump and Docs

- [ ] 3.1 Bump `plugin.json` version 2.3.1 -> 2.4.0
- [ ] 3.2 Add CHANGELOG.md entry for v2.4.0
- [ ] 3.3 Update `plugins/soleur/README.md` skill count and table
- [ ] 3.4 Update root `README.md` version badge
- [ ] 3.5 Update `.github/ISSUE_TEMPLATE/bug_report.yml` version placeholder
