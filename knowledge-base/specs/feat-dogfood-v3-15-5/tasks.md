# Tasks: Dogfood v3.15.5 Changes

## Phase 1: Gemini Imagegen Quota Error Verification

### 1.1 Run Unit Tests
- [ ] 1.1.1 Run `python3 -m unittest test_error_handling -v` from `plugins/soleur/skills/gemini-imagegen/scripts/`
- [ ] 1.1.2 Confirm all 16 tests pass (3 TestCheckQuota + 5 TestHandleApiError + 8 TestParseImageResponse)

### 1.2 Verify `--check-quota` Flag
- [ ] 1.2.1 Set `GEMINI_API_KEY` environment variable
- [ ] 1.2.2 Run `python3 generate_image.py --check-quota` and verify output matches expected category
- [ ] 1.2.3 Run without `GEMINI_API_KEY` and verify environment error message

### 1.3 Trigger Live Error Paths
- [ ] 1.3.1 Attempt image generation to trigger quota/permission error
- [ ] 1.3.2 Verify error output contains specific category prefix (QUOTA EXHAUSTED, PERMISSION DENIED, etc.)
- [ ] 1.3.3 Verify error includes original API error message for debugging

### 1.4 Verify Integration Across All Scripts
- [ ] 1.4.1 Confirm all 5 scripts import from `_error_handling` (grep check)
- [ ] 1.4.2 Confirm no script accesses `response.candidates[N].finish_reason` (grep check)

## Phase 2: Pencil Setup Three-Tier Detection Verification

### 2.1 Run `check_deps.sh` Interactive Mode
- [ ] 2.1.1 Run `bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh`
- [ ] 2.1.2 Verify Tier 3 (IDE) detection: `PREFERRED_MODE=ide`, `PREFERRED_APP=cursor`
- [ ] 2.1.3 Verify MCP binary path is correct

### 2.2 Run `check_deps.sh --auto` Mode
- [ ] 2.2.1 Run with `--auto` flag
- [ ] 2.2.2 Verify same output as interactive (no Desktop to auto-launch)

### 2.3 Verify Collision Guard
- [ ] 2.3.1 Create fake evolus/pencil binary in PATH
- [ ] 2.3.2 Run `check_deps.sh` with fake binary
- [ ] 2.3.3 Confirm collision warning and fallthrough to IDE tier
- [ ] 2.3.4 Clean up fake binary

### 2.4 Verify VS Code App Flag
- [ ] 2.4.1 Confirm `ide_to_app_value` maps `code` to `visual_studio_code`

### 2.5 Full Pencil Setup Skill Flow
- [ ] 2.5.1 Run full SKILL.md flow (check deps, register MCP, verify)
- [ ] 2.5.2 Verify `claude mcp list -s user` shows pencil entry
- [ ] 2.5.3 Clean up: `claude mcp remove pencil -s user` (optional)

## Phase 3: Capture Findings

### 3.1 Document Results
- [ ] 3.1.1 Record pass/fail for each acceptance criterion
- [ ] 3.1.2 File GitHub issues for any failures found
- [ ] 3.1.3 Create learning if new edge cases discovered
