---
feature: community-setup
date: 2026-02-18
issue: "#129"
---

# Tasks: Community Setup Wizard

## Phase 1: Setup Script

- [ ] 1.1 Create `discord-setup.sh` with validate-token command (API call, output app ID)
- [ ] 1.2 Add discover-guilds command (GET /users/@me/guilds, output JSON)
- [ ] 1.3 Add list-channels command (GET /guilds/{id}/channels, filter type=0, output JSON)
- [ ] 1.4 Add create-webhook command (POST /channels/{id}/webhooks, output URL)
- [ ] 1.5 Add write-env command (append three vars to .env)
- [ ] 1.6 Add verify command (source .env, run guild-info)

## Phase 2: Skill Update

- [ ] 2.1 Add `setup` sub-command section to SKILL.md with full flow
- [ ] 2.2 Add setup to sub-command table

## Phase 3: Agent Update

- [ ] 3.1 Add setup capability to community-manager.md

## Phase 4: Version Bump

- [ ] 4.1 Bump version in plugin.json (PATCH)
- [ ] 4.2 Update CHANGELOG.md
- [ ] 4.3 Verify README.md component counts
