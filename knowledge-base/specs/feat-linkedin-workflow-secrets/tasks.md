# Tasks: feat-linkedin-workflow-secrets

## Phase 1: Setup

- [x] 1.1 Read `.github/workflows/scheduled-community-monitor.yml` to confirm current state
- [x] 1.2 Read `plugins/soleur/skills/community/scripts/community-router.sh` to verify LinkedIn env var names (`LINKEDIN_ACCESS_TOKEN`, `LINKEDIN_PERSON_URN`)

## Phase 2: Core Implementation

- [x] 2.1 Add `LINKEDIN_ACCESS_TOKEN: ${{ secrets.LINKEDIN_ACCESS_TOKEN }}` to the env block of the "Run community monitor" step in `.github/workflows/scheduled-community-monitor.yml`
- [x] 2.2 Add `LINKEDIN_PERSON_URN: ${{ secrets.LINKEDIN_PERSON_URN }}` to the env block, after the LinkedIn access token line
- [x] 2.3 Place LinkedIn env vars after the X/Twitter block, maintaining alphabetical platform grouping (Discord, X, LinkedIn)
- [x] 2.4 Add LinkedIn data collection instructions to the agent prompt Step 2 section, following the X/Twitter bullet pattern
  - [x] 2.4.1 Include explicit no-post guard ("do NOT post during monitoring runs")
  - [x] 2.4.2 Include graceful skip for fetch-metrics and fetch-activity stubs
  - [x] 2.4.3 Instruct agent to log LinkedIn as "enabled (posting only)" in digest platform status
  - [x] 2.4.4 Direct agent to note LinkedIn in Activity Summary rather than creating empty LinkedIn Metrics section
- [x] 2.5 Add `## LinkedIn Metrics` as optional heading in digest Step 4 section (aligns with digest file contract)

## Phase 3: Validation

- [x] 3.1 Verify the YAML is valid (no indentation errors in the modified workflow file)
- [x] 3.2 Verify the env vars match the community-router registry entry (`LINKEDIN_ACCESS_TOKEN,LINKEDIN_PERSON_URN`)
- [x] 3.3 Verify the prompt instructions do not reference `LINKEDIN_ORGANIZATION_ID` (incorrect variable from issue text)
- [x] 3.4 Verify no `LINKEDIN_ORGANIZATION_ID` appears anywhere in the file
- [ ] 3.5 Run compound skill before commit
