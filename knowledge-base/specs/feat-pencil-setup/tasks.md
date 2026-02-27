# Tasks — feat-pencil-setup

## Phase 1: Core Implementation

### 1.1 Create `plugins/soleur/skills/pencil-setup/SKILL.md`

Single file, ~45 lines. YAML frontmatter + 4 inline bash steps:

1. **Check if registered** — `claude mcp list | grep pencil` + verify binary path exists
2. **Detect IDE** — `which cursor` / `which code`, set extension dir path
3. **Find or install extension** — glob for `highagency.pencildev-*-universal/out/mcp-server-*`, install via `<ide> --install-extension highagency.pencildev` if missing
4. **Register** — `claude mcp remove pencil -s user 2>/dev/null; claude mcp add -s user pencil -- <binary> --app <ide>`
5. **Verify** — `claude mcp list | grep pencil`, print restart instruction

Error messages: no IDE found, extension install failed, already configured.

### 1.2 Update `plugins/soleur/agents/product/design/ux-design-lead.md`

Replace lines 9-11: change manual install URL to "Run `/soleur:pencil-setup`" reference.

## Phase 2: Version Bump

### 2.1 Bump 3.5.1 → 3.6.0 across all 6 version locations

- `plugins/soleur/.claude-plugin/plugin.json`
- `plugins/soleur/CHANGELOG.md`
- `plugins/soleur/README.md` (skill count 52→53, add pencil-setup to table)
- `plugins/soleur/.claude-plugin/marketplace.json`
- Root `README.md` (badge, skill count)
- `.github/ISSUE_TEMPLATE/bug_report.yml`

## Phase 3: Verify

### 3.1 Test the skill

Run the inline bash steps from SKILL.md manually. Verify detection, registration, and verification work.

### 3.2 Verify plugin metadata

- `ls plugins/soleur/skills/*/SKILL.md | wc -l` → 53
- `jq .version plugins/soleur/.claude-plugin/plugin.json` → 3.6.0
