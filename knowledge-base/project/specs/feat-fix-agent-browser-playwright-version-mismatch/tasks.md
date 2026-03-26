# Tasks: Permanently fix recurring Playwright version mismatch in agent-browser

Source: `knowledge-base/project/plans/2026-03-26-fix-agent-browser-playwright-version-mismatch-recurring-plan.md`

## Phase 1: Remove stale system binary (manual -- requires sudo)

- [ ] 1.1 Instruct user to run: `sudo npm uninstall -g agent-browser`
- [ ] 1.2 Verify: `which agent-browser` resolves to `~/.local/bin/agent-browser`
- [ ] 1.3 Verify: `agent-browser --version` returns `0.21.4`
- [ ] 1.4 If `~/.local/bin/agent-browser` missing, run: `npm install --prefix ~/.local -g agent-browser@0.21.4 && agent-browser install`

## Phase 2: Add version guard to check_deps.sh

- [ ] 2.1 Read `plugins/soleur/skills/feature-video/scripts/check_deps.sh`
- [ ] 2.2 Replace the agent-browser check (lines 214-223) with version-aware guard:
  - [ ] 2.2.1 Check `agent-browser --version` output
  - [ ] 2.2.2 Parse major.minor version
  - [ ] 2.2.3 Reject versions < 0.21.1 with clear error message and fix instructions
  - [ ] 2.2.4 Update install instructions in error message to use `--prefix ~/.local`
- [ ] 2.3 Update the install message to use `npm install --prefix ~/.local -g agent-browser@0.21.4`

## Phase 3: Update SKILL.md install instructions

- [ ] 3.1 Read `plugins/soleur/skills/agent-browser/SKILL.md`
- [ ] 3.2 Update Setup Check install command to use `--prefix ~/.local`
- [ ] 3.3 Update "Install if needed" section to use `npm install --prefix ~/.local -g agent-browser@0.21.4`
- [ ] 3.4 Add "Troubleshooting: version mismatch" section with PATH shadowing diagnosis
- [ ] 3.5 Read `plugins/soleur/skills/test-browser/SKILL.md`
- [ ] 3.6 Update install instructions to use `--prefix ~/.local`
- [ ] 3.7 Update auto-install fallback command in verification step

## Phase 4: Update learning

- [ ] 4.1 Read `knowledge-base/project/learnings/2026-03-20-npm-global-install-without-sudo.md`
- [ ] 4.2 Add PATH shadowing insights to Key Insight section:
  - [ ] 4.2.1 System binary shadows local install in non-interactive shells
  - [ ] 4.2.2 Remove stale system binary as primary fix
  - [ ] 4.2.3 Version guards as defense-in-depth

## Phase 5: Verification

- [ ] 5.1 Verify `which agent-browser` resolves to `~/.local/bin/agent-browser`
- [ ] 5.2 Verify `agent-browser --version` returns 0.21.4
- [ ] 5.3 Verify `agent-browser open https://example.com` succeeds without mismatch error
- [ ] 5.4 Verify `agent-browser snapshot -i` returns refs
- [ ] 5.5 Verify `agent-browser close` works
- [ ] 5.6 Verify Playwright MCP tools work independently
- [ ] 5.7 Run compound (`skill: soleur:compound`)
