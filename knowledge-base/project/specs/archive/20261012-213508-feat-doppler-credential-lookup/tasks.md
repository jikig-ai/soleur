# Tasks: Doppler-First Credential Lookup

## Phase 1: Implementation

- [ ] 1.1 Read `AGENTS.md` and locate the "exhaust all automated options" rule in the Hard Rules section
- [ ] 1.2 Add the Doppler-first credential lookup rule as a new bullet immediately before the "exhaust all automated options" bullet
- [ ] 1.3 Run `npx markdownlint-cli2 --fix AGENTS.md` to verify markdown formatting

## Phase 2: Verification

- [ ] 2.1 Verify the new rule includes all required elements: `doppler secrets get` command, `2>/dev/null` suffix, multi-config guidance, `**Why:**` annotation
- [ ] 2.2 Verify the existing priority chain is preserved and the new rule is positioned as step 0
- [ ] 2.3 Run `grep -c 'doppler secrets get' AGENTS.md` to confirm the rule was added
