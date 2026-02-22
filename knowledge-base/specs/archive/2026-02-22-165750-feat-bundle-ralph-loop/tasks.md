---
title: Bundle ralph-loop Tasks
feature: feat-bundle-ralph-loop
date: 2026-02-22
---

# Tasks

## Phase 1: Setup

- [ ] 1.1 Create `plugins/soleur/hooks/` directory
- [ ] 1.2 Create `plugins/soleur/scripts/` directory

## Phase 2: Port Hook and Script

- [ ] 2.1 Port `hooks/stop-hook.sh` with attribution header
- [ ] 2.2 Create `hooks/hooks.json` with Stop hook configuration
- [ ] 2.3 Port `scripts/setup-ralph-loop.sh` with attribution header

## Phase 3: Port Commands

- [ ] 3.1 Create `commands/soleur/ralph-loop.md` (namespace: `soleur:ralph-loop`)
- [ ] 3.2 Create `commands/soleur/cancel-ralph.md` (namespace: `soleur:cancel-ralph`)
- [ ] 3.3 Update `commands/soleur/help.md` with ralph-loop documentation
- [ ] 3.4 Update `commands/soleur/one-shot.md` to reference `/soleur:ralph-loop`

## Phase 4: Version and Documentation

- [ ] 4.1 Bump `plugin.json` to 2.24.0, update description counts
- [ ] 4.2 Add CHANGELOG.md entry for v2.24.0
- [ ] 4.3 Update README.md command count and commands table
