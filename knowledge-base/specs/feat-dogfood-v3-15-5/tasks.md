# Tasks: Dogfood v3.15.5 Changes (Deepened)

## Phase 1: Gemini Imagegen Quota Error Verification

### 1.1 Run Unit Tests
- [ ] 1.1.1 Run `python3 -m unittest test_error_handling -v` from `plugins/soleur/skills/gemini-imagegen/scripts/`
- [ ] 1.1.2 Confirm all 16 tests pass (3 TestCheckQuota + 5 TestHandleApiError + 8 TestParseImageResponse)
- [ ] 1.1.3 Verify test constructors use correct `ClientError(code, response_json)` signature (tests pass = constructors are correct)

### 1.2 Verify `--check-quota` Flag
- [ ] 1.2.1 Set `GEMINI_API_KEY` environment variable
- [ ] 1.2.2 Run `python3 generate_image.py --check-quota` and verify output matches expected category
- [ ] 1.2.3 Verify exit code is 1 on failure, 0 on success
- [ ] 1.2.4 Run without `GEMINI_API_KEY` and verify environment error message

### 1.3 Trigger Live Error Paths
- [ ] 1.3.1 Attempt image generation to trigger quota/permission error
- [ ] 1.3.2 Verify error output starts with category prefix (QUOTA EXHAUSTED, PERMISSION DENIED, etc.)
- [ ] 1.3.3 Verify error includes original API error message for debugging (chained via `from e`)

### 1.4 Verify Integration Across All Scripts
- [ ] 1.4.1 Confirm all 5 scripts import from `_error_handling` (grep check -- expect 5 matches plus test file)
- [ ] 1.4.2 Confirm no script accesses `response.candidates[N].finish_reason` (grep check)
- [ ] 1.4.3 Confirm no script accesses `.candidates` at all (grep check)
- [ ] 1.4.4 Verify `multi_turn_chat.py` intentionally catches `NoImageError` for text-only chat responses

### 1.5 Verify Edge Cases (New from deepening)
- [ ] 1.5.1 Run `test_raises_on_empty_list` individually to confirm `parts=[]` triggers `NoImageError`
- [ ] 1.5.2 Note: `UnknownApiResponseError` and `FunctionInvocationError` subclasses not tested -- forward-compatibility guard exists but is untested (future work)

## Phase 2: Pencil Setup Three-Tier Detection Verification

### 2.1 Run `check_deps.sh` Interactive Mode
- [ ] 2.1.1 Run `bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh`
- [ ] 2.1.2 Verify Tier 3 (IDE) detection: `PREFERRED_MODE=ide`, `PREFERRED_APP=cursor`
- [ ] 2.1.3 Verify MCP binary path contains `linux-x64` (not darwin/windows)
- [ ] 2.1.4 Verify MCP binary at reported path is actually executable (`test -x`)
- [ ] 2.1.5 Verify Cursor wins over VS Code (both available, Cursor checked first)

### 2.2 Run `check_deps.sh --auto` Mode
- [ ] 2.2.1 Run with `--auto` flag
- [ ] 2.2.2 Verify same output as interactive (no Desktop to auto-launch)

### 2.3 Verify Collision Guard
- [ ] 2.3.1 Create fake evolus/pencil binary in `/tmp/fake-pencil/`
- [ ] 2.3.2 Run `check_deps.sh` with fake binary in PATH
- [ ] 2.3.3 Confirm collision warning message appears
- [ ] 2.3.4 Confirm fallthrough to IDE tier
- [ ] 2.3.5 Clean up fake binary (unconditional -- not gated on test success)

### 2.4 Verify VS Code App Flag
- [ ] 2.4.1 Confirm `ide_to_app_value` maps `code` to `visual_studio_code` (not `code`)
- [ ] 2.4.2 Confirm `detect_ide` returns `code` (binary name) not `visual_studio_code` (app flag)

### 2.5 Verify MCP Binary Executability (New from deepening)
- [ ] 2.5.1 Run `file` on detected binary to confirm it is an ELF binary
- [ ] 2.5.2 Note: IDE tier `detect_extension` uses `ls -d` (no executability check) vs Desktop tier `detect_desktop_binary` uses `[[ -x ]]` -- asymmetry noted for future fix

### 2.6 Full Pencil Setup Skill Flow
- [ ] 2.6.1 Run full SKILL.md flow (check deps, remove stale, register MCP, verify)
- [ ] 2.6.2 Verify remove-then-add pattern is followed (claude mcp add is NOT idempotent)
- [ ] 2.6.3 Verify `-s user` scope is used (not local/default)
- [ ] 2.6.4 Verify `claude mcp list -s user` shows pencil entry after registration
- [ ] 2.6.5 Clean up: `claude mcp remove pencil -s user` after verification

## Phase 3: Capture Findings

### 3.1 Document Results
- [ ] 3.1.1 Record pass/fail for each acceptance criterion
- [ ] 3.1.2 File GitHub issues for any failures found
- [ ] 3.1.3 Create learning if new edge cases discovered
- [ ] 3.1.4 Note IDE tier executability check gap if confirmed (potential issue to file)
