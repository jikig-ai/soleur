# Tasks: Fix Playwright version mismatch between agent-browser and Playwright MCP

Source: `knowledge-base/project/plans/2026-03-20-fix-playwright-version-mismatch-agent-browser-plan.md`

## Phase 1: Update agent-browser

- [ ] 1.1 Run `npm install -g agent-browser@0.21.4` to update from 0.5.0
- [ ] 1.2 Verify installation: `agent-browser --version` or `npm list -g agent-browser`

## Phase 2: Verify CLI API compatibility

- [ ] 2.1 Run `agent-browser open https://example.com` -- confirm no version mismatch error
- [ ] 2.2 Run `agent-browser snapshot -i` -- confirm ref output format unchanged
- [ ] 2.3 Run `agent-browser screenshot test.png` -- confirm screenshot capture works
- [ ] 2.4 Run `agent-browser close` and clean up test screenshot
- [ ] 2.5 Test `--headed` flag if available: `agent-browser --headed open https://example.com`
- [ ] 2.6 Verify Playwright MCP tools still work independently (`browser_navigate`, `browser_snapshot`)

## Phase 3: Update documentation (if API changed)

- [ ] 3.1 Compare 0.5.0 vs 0.21.4 CLI help output for command differences
- [ ] 3.2 Update `plugins/soleur/skills/agent-browser/SKILL.md` if commands changed
- [ ] 3.3 Update `plugins/soleur/skills/test-browser/SKILL.md` if commands changed
- [ ] 3.4 Update `plugins/soleur/skills/feature-video/scripts/check_deps.sh` if install command changed
- [ ] 3.5 Update `plugins/soleur/skills/feature-video/SKILL.md` if referenced commands changed
- [ ] 3.6 Grep all files for `agent-browser install` -- this command may no longer be needed (bundled browser)

## Phase 4: Create learning

- [ ] 4.1 Create `knowledge-base/project/learnings/2026-03-20-playwright-shared-cache-version-coupling.md`
- [ ] 4.2 Document: shared `~/.cache/ms-playwright/` cache causes version coupling; self-contained packages eliminate it
- [ ] 4.3 Document: pin global npm installs to specific versions per learning `2026-03-19-npm-global-install-version-pinning.md`

## Phase 5: Verification

- [ ] 5.1 Run compound (`skill: soleur:compound`)
- [ ] 5.2 Verify no remaining references to chromium-1200 or playwright-core@1.57.0
- [ ] 5.3 Verify Playwright MCP and agent-browser can both operate without conflicts
