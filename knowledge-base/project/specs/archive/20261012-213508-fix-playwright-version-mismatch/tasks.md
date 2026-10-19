# Tasks: Fix Playwright version mismatch between agent-browser and Playwright MCP

Source: `knowledge-base/project/plans/2026-03-20-fix-playwright-version-mismatch-agent-browser-plan.md`

## Phase 1: Update agent-browser

- [ ] 1.1 Run `npm install -g agent-browser@0.21.4` to update from 0.5.0
- [ ] 1.2 Verify installation: `npm list -g agent-browser` shows 0.21.4
- [ ] 1.3 Run `agent-browser install` to download Chrome for Testing (required -- this is NOT Playwright's Chromium)
- [ ] 1.4 On Linux: if system deps missing, run `agent-browser install --with-deps`

## Phase 2: Verify CLI API compatibility

- [ ] 2.1 Run `agent-browser open https://example.com` -- confirm no version mismatch error
- [ ] 2.2 Run `agent-browser snapshot -i` -- confirm `@e1` ref output format unchanged
- [ ] 2.3 Run `agent-browser screenshot test.png` -- confirm screenshot capture works
- [ ] 2.4 Run `agent-browser close` and clean up test screenshot (`rm -f test.png`)
- [ ] 2.5 Test `--headed` flag: `agent-browser --headed open https://example.com` then `agent-browser close`
- [ ] 2.6 Verify `--session-name` flag works (replaces old `--session`): `agent-browser --session-name test open https://example.com`
- [ ] 2.7 Verify Playwright MCP tools still work independently (`browser_navigate`, `browser_snapshot`)
- [ ] 2.8 Verify agent-browser does NOT write to `~/.cache/ms-playwright/` (uses its own Chrome for Testing path)

## Phase 3: Update SKILL.md documentation

- [ ] 3.1 Read and update `plugins/soleur/skills/agent-browser/SKILL.md`:
  - [ ] 3.1.1 Change `--session` to `--session-name` in Sessions section
  - [ ] 3.1.2 Change `session list` to `state list`
  - [ ] 3.1.3 Update "vs Playwright MCP" table -- agent-browser now uses Chrome for Testing (Rust native)
  - [ ] 3.1.4 Update install instructions -- `agent-browser install` downloads Chrome for Testing, not "Chromium"
  - [ ] 3.1.5 Pin version in install: `npm install -g agent-browser@0.21.4`
- [ ] 3.2 Read `plugins/soleur/skills/test-browser/SKILL.md` -- verify no `--session` references need updating (core commands are unchanged)
- [ ] 3.3 Read `plugins/soleur/skills/feature-video/SKILL.md` -- verify no `--session` references
- [ ] 3.4 Read `plugins/soleur/skills/feature-video/scripts/check_deps.sh` -- install instruction (`npm install -g agent-browser && agent-browser install`) is still correct; consider adding `--with-deps` for Linux
- [ ] 3.5 Grep all files for `--session` references to agent-browser that need `--session-name` rename

## Phase 4: Create learning

- [ ] 4.1 Create `knowledge-base/project/learnings/2026-03-20-playwright-shared-cache-version-coupling.md`
- [ ] 4.2 Document: shared `~/.cache/ms-playwright/` cache causes version coupling between Playwright-based tools
- [ ] 4.3 Document: agent-browser@0.21.1+ uses Chrome for Testing instead of Playwright, eliminating the coupling
- [ ] 4.4 Document: Playwright browser lookup is exact-match on revision number (no forward compatibility)
- [ ] 4.5 Document: pin global npm installs per learning `2026-03-19-npm-global-install-version-pinning.md`

## Phase 5: Verification

- [ ] 5.1 Run compound (`skill: soleur:compound`)
- [ ] 5.2 Verify no remaining references to `playwright-core` or chromium-1200 in agent-browser context
- [ ] 5.3 Verify Playwright MCP and agent-browser can both operate without conflicts
- [ ] 5.4 Verify `agent-browser` SKILL.md passes markdownlint
