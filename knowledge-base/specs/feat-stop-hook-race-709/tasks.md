# Tasks: fix stop-hook.sh TOCTOU race (#709)

## Phase 1: Setup

- [ ] 1.1 Read `plugins/soleur/hooks/stop-hook.sh` to confirm current line numbers match plan

## Phase 2: Core Implementation

- [ ] 2.1 Add `2>/dev/null` to the TTL loop awk call (line 30) and add `|| continue` guard
- [ ] 2.2 Add re-check `[[ -f "$RALPH_STATE_FILE" ]] || exit 0` before the frontmatter parse (between current lines 48-51)
- [ ] 2.3 Add `2>/dev/null` to the main frontmatter awk call (line 51)
- [ ] 2.4 Add empty-FRONTMATTER guard after the frontmatter extraction
- [ ] 2.5 Add re-check `[[ -f "$RALPH_STATE_FILE" ]] || exit 0` before the prompt extraction (before line 190)
- [ ] 2.6 Add `2>/dev/null` to the prompt extraction awk call (line 190)
- [ ] 2.7 Add `2>/dev/null` to the state update awk call (line 210) and guard the mv

## Phase 3: Testing

- [ ] 3.1 Run `bash -n plugins/soleur/hooks/stop-hook.sh` to verify syntax
- [ ] 3.2 Verify `set -euo pipefail` compatibility by tracing exit codes of modified lines
- [ ] 3.3 Run compound and commit
