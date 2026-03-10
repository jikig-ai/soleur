# Tasks: Surface Parity Checks After Provisioning

## Phase 1: Community Skill Update

### 1.1 Add Platform Surface Check section to community SKILL.md

- [ ] Read `plugins/soleur/skills/community/SKILL.md`
- [ ] Add a new `## Platform Surface Check` section after the `## Important Guidelines` section
- [ ] Include a table listing the surface files to verify:
  - `plugins/soleur/docs/_data/site.json` -- platform URL entry
  - `plugins/soleur/docs/pages/community.njk` -- Connect card for the platform
  - `knowledge-base/overview/brand-guide.md` -- platform handle mention
- [ ] Specify that this check runs after a setup script confirms a new platform is enabled (not on every sub-command)
- [ ] Use angle-bracket placeholders (`<platform-name>`) -- NO `$()` or shell variable expansion
- [ ] Output is a warning listing missing surfaces, not a blocking error
- [ ] Include a suggested `gh issue create` command template for filing follow-up issues

## Phase 2: Ops-Provisioner Update

### 2.1 Add Public Surface Check phase to ops-provisioner.md

- [ ] Read `plugins/soleur/agents/operations/ops-provisioner.md`
- [ ] Add a new `## Public Surface Check` section after `## Verify + Record` and before `## Safety Rules`
- [ ] Frame the check as a semantic question: "Does this tool have a user-visible presence?"
- [ ] List the three files to check: `plugins/soleur/docs/_data/site.json`, docs pages, `knowledge-base/overview/brand-guide.md`
- [ ] If gaps found, suggest filing a follow-up issue with specific file paths
- [ ] If the tool has no public-facing presence (internal monitoring, CI tooling), skip silently
- [ ] Keep the check generic -- not limited to social platforms

## Phase 3: Verification

### 3.1 Review both changes for correctness

- [ ] Verify file paths in both checks match actual repo structure (`plugins/soleur/docs/`, not `docs/`)
- [ ] Verify neither check blocks the provisioning workflow (warning-only)
- [ ] Verify community skill check is scoped to social/community platforms
- [ ] Verify ops-provisioner check is generic (any SaaS with public presence)
- [ ] Verify no `$()` or shell variable expansion in SKILL.md additions
- [ ] Verify ops-provisioner section placement maintains the Setup > Configure > Verify+Record > Surface Check > Safety flow
- [ ] Run markdownlint on both modified files
