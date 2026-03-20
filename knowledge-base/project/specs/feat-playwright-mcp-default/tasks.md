# Tasks: Default to Playwright MCP for browser interactions

Source: `knowledge-base/project/plans/2026-03-10-fix-default-playwright-mcp-browser-interactions-plan.md`
Closes: #485

## Phase 1: constitution.md browser hierarchy rule

- [ ] 1.1 Read `knowledge-base/overview/constitution.md`
- [ ] 1.2 Add Prefer rule to Architecture section establishing Playwright MCP as default for browser interactions
- [ ] 1.3 Update line 89 to list Playwright MCP tools as the preferred browser tool, with agent-browser as fallback
- [ ] 1.4 Verify no other constitution entries need updating for consistency

## Phase 2: ops-provisioner update

- [ ] 2.1 Read `plugins/soleur/agents/operations/ops-provisioner.md`
- [ ] 2.2 Remove the `agent-browser --help` availability check from the Setup section
- [ ] 2.3 Make Playwright MCP the default (unconditional) browser interaction path
- [ ] 2.4 Move agent-browser CLI to an explicit "Fallback" subsection
- [ ] 2.5 Rewrite "If neither is available" to "Last resort" with language indicating this path should rarely trigger
- [ ] 2.6 Update the Configure section to reference Playwright MCP as default (line 55 references agent-browser)
- [ ] 2.7 Update the Verify section (lines 64-65) to explicitly reference `browser_take_screenshot` and `browser_navigate`
- [ ] 2.8 Preserve all existing safety rules unchanged
- [ ] 2.9 Follow sharp-edges-only principle: keep instructions minimal, focus on hierarchy declaration not Playwright tutorials

## Phase 3: ops-research update

- [ ] 3.1 Read `plugins/soleur/agents/operations/ops-research.md`
- [ ] 3.2 Remove the `agent-browser --help` check from Browser Navigation section
- [ ] 3.3 Add Playwright MCP as the default browser navigation method with `browser_navigate` and `browser_snapshot`
- [ ] 3.4 Move agent-browser CLI to fallback position
- [ ] 3.5 Change "tell the user to navigate manually" to last-resort language
- [ ] 3.6 Preserve all existing safety rules unchanged

## Phase 4: Verification

- [ ] 4.1 Grep all agent files for remaining `agent-browser --help` checks that should use Playwright MCP first
- [ ] 4.2 Grep all agent files for "manually" or "manual instructions" to verify none remain as default paths (only as last resort)
- [ ] 4.3 Verify community-manager.md was NOT modified
- [ ] 4.4 Run `markdownlint` on all modified files
- [ ] 4.5 Run compound (`skill: soleur:compound`)
