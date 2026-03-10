# Tasks: Surface Parity Checks After Provisioning

## Phase 1: Community Skill Update

### 1.1 Add Platform Surface Check section to community SKILL.md

- [ ] Read `plugins/soleur/skills/community/SKILL.md`
- [ ] Add a new `## Platform Surface Check` section after the `## Important Guidelines` section
- [ ] The section should instruct the agent to verify three files after a platform setup completes:
  - `plugins/soleur/docs/_data/site.json` -- platform URL entry
  - `plugins/soleur/docs/pages/community.njk` -- Connect card for the platform
  - `knowledge-base/overview/brand-guide.md` -- platform handle mention
- [ ] Specify that this check runs after any setup script completes (discord-setup.sh, x-setup.sh, or future setup scripts)
- [ ] Output is a warning listing missing surfaces, not a blocking error
- [ ] Optionally suggest filing a follow-up issue for missing surfaces

## Phase 2: Ops-Provisioner Update

### 2.1 Add Public Surface Check phase to ops-provisioner.md

- [ ] Read `plugins/soleur/agents/operations/ops-provisioner.md`
- [ ] Add a new `## Public Surface Check` section after the `## Verify + Record` section (before `## Safety Rules`)
- [ ] The check should ask: "Does this tool have a user-visible presence (social links, badges, embeds, landing page mentions)?"
- [ ] If yes, verify `plugins/soleur/docs/_data/site.json` and relevant docs pages reference it
- [ ] If gaps found, suggest filing a follow-up issue with specific file paths
- [ ] If the tool has no public-facing presence, skip silently
- [ ] Keep the check generic -- not limited to social platforms

## Phase 3: Verification

### 3.1 Review both changes for correctness

- [ ] Verify file paths in both checks match actual repo structure (`plugins/soleur/docs/`, not `docs/`)
- [ ] Verify neither check blocks the provisioning workflow (warning-only)
- [ ] Verify community skill check is scoped to social/community platforms
- [ ] Verify ops-provisioner check is generic (any SaaS with public presence)
- [ ] Run markdownlint on both modified files
