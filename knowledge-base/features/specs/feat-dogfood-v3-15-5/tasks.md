# Tasks: Dogfood v3.15.5 Changes (Deepened)

## Phase 1: Gemini Imagegen Quota Error Verification

### 1.1 Run Unit Tests
- [x] 1.1.1 Run `python3 -m unittest test_error_handling -v` from `plugins/soleur/skills/gemini-imagegen/scripts/` (pytest not installed, used unittest)
- [x] 1.1.2 Confirm all 16 tests pass (3 TestCheckQuota + 5 TestHandleApiError + 8 TestParseImageResponse)
- [x] 1.1.3 Verify test constructors use correct `ClientError(code, response_json)` signature (tests pass = constructors are correct)

### 1.2 Verify `--check-quota` Flag
- [x] 1.2.1 `GEMINI_API_KEY` was already set in environment (plan incorrectly reported "not set")
- [x] 1.2.2 `--check-quota` returned `[ok] Image generation quota available` (key has quota)
- [ ] 1.2.3 Verify exit code is 1 on failure — **not tested**: key has quota, cannot trigger failure path without a quota-less key
- [ ] 1.2.4 Run without `GEMINI_API_KEY` — **not tested**: key was present, would require unsetting it

### 1.3 Trigger Live Error Paths
- [ ] 1.3.1 Attempt image generation to trigger quota/permission error — **not tested**: key has quota
- [ ] 1.3.2 Verify error output starts with category prefix — covered by unit tests only
- [ ] 1.3.3 Verify error includes original API error message — covered by unit tests only

### 1.4 Verify Integration Across All Scripts
- [x] 1.4.1 Confirmed all 5 scripts import from `_error_handling` (grep returned 5 scripts + test file)
- [x] 1.4.2 Confirmed no script accesses `response.candidates[N].finish_reason` (grep found only a documentation comment in `_error_handling.py` line 72)
- [x] 1.4.3 Confirmed no script accesses `.candidates` in code
- [x] 1.4.4 Verified `multi_turn_chat.py` catches `NoImageError` at line 90 for text-only chat responses

### 1.5 Verify Edge Cases (New from deepening)
- [x] 1.5.1 Ran `test_raises_on_empty_list` individually — passed, confirms `parts=[]` triggers `NoImageError`
- [x] 1.5.2 Note: `UnknownApiResponseError` and `FunctionInvocationError` subclasses not tested — forward-compatibility guard exists but is untested (future work)

## Phase 2: Pencil Setup Three-Tier Detection Verification

### 2.1 Run `check_deps.sh` Interactive Mode
- [x] 2.1.1 Ran `bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh`
- [x] 2.1.2 **Deviation:** Tier 2 (Desktop binary) activated, not Tier 3 (IDE). Actual: `PREFERRED_MODE=desktop_binary`, `PREFERRED_APP=pencil`. Extracted AppImage at `~/Applications/squashfs-root/` was present.
- [x] 2.1.3 Verified MCP binary path contains `linux-x64` (not darwin/windows)
- [x] 2.1.4 Verified MCP binary at reported path is executable (ELF 64-bit LSB, x86-64)
- [ ] 2.1.5 Cursor vs VS Code priority — **not tested**: Desktop tier won before IDE tier was reached

### 2.2 Run `check_deps.sh --auto` Mode
- [x] 2.2.1 Ran with `--auto` flag
- [x] 2.2.2 Same tier detected (Desktop binary). `--auto` additionally attempted AppImage launch — crashed with SIGTRAP in headless terminal. Detection output still correct.

### 2.3 Verify Collision Guard
- [x] 2.3.1 Created realistic fake evolus/pencil binary (rejects unknown subcommands with exit 1)
- [x] 2.3.2 Ran `check_deps.sh` with fake binary in PATH
- [x] 2.3.3 Collision warning message appeared: `[info] pencil CLI found but is not pencil.dev (possible evolus/pencil)`
- [x] 2.3.4 Confirmed fallthrough to Desktop tier (Tier 2)
- [x] 2.3.5 Cleaned up fake binary
- Note: First attempt used naive fake (exit 0 on all args) which bypassed the guard. See learning: `2026-03-10-dogfood-collision-guard-requires-realistic-fakes.md`

### 2.4 Verify VS Code App Flag
- [x] 2.4.1 Confirmed `ide_to_app_value` maps `code` to `visual_studio_code` at line 115 of check_deps.sh
- [x] 2.4.2 Confirmed `detect_ide` returns `code` (binary name), distinct from `visual_studio_code` (app flag)

### 2.5 Verify MCP Binary Executability (New from deepening)
- [x] 2.5.1 Ran `file` on detected binary — confirmed ELF 64-bit LSB executable, x86-64
- [x] 2.5.2 Note: IDE tier `detect_extension` uses `ls -d` (no executability check) vs Desktop tier `detect_desktop_binary` uses `[[ -x ]]` — asymmetry noted

### 2.6 Full Pencil Setup Skill Flow
- [x] 2.6.1 Ran full flow: check deps → remove stale → register MCP → verify → cleanup
- [x] 2.6.2 Verified remove-then-add pattern (both `remove` and `add` succeeded)
- [x] 2.6.3 Verified `-s user` scope used for both `add` and `remove`
- [x] 2.6.4 `claude mcp list` showed pencil entry connected (`claude mcp list -s user` doesn't work — `-s` flag not supported for `list`)
- [x] 2.6.5 Cleaned up: `claude mcp remove pencil -s user` after verification

## Phase 3: Capture Findings

### 3.1 Document Results
- [x] 3.1.1 Recorded pass/fail for each acceptance criterion in plan
- [x] 3.1.2 No failures found — no GitHub issues needed
- [x] 3.1.3 Created 3 learnings: collision guard fakes, AppImage headless crashes, duplicate collision guard learning
- [x] 3.1.4 IDE tier executability check gap noted in plan (asymmetry between `ls -d` and `[[ -x ]]`)
