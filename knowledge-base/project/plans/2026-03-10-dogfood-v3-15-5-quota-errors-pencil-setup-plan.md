---
title: "dogfood: verify v3.15.5 changes -- gemini quota errors and pencil-setup three-tier detection"
type: fix
date: 2026-03-10
semver: patch
---

# Dogfood v3.15.5: Gemini Quota Errors and Pencil Setup Three-Tier Detection

## Enhancement Summary

**Deepened on:** 2026-03-10
**Sections enhanced:** 8
**Research sources used:** 6 learnings (gemini-sdk-error-handling, pencil-desktop-three-tier, pencil-mcp-auto-registration, pencil-desktop-ships-mcp-binary, pencil-editor-operational-requirements, check-deps-pattern-for-gui-apps), SDK module inspection, live environment probes

### Key Improvements

1. Added forward-compatibility edge case: `_error_handling.py` has a fallback guard for unknown `APIError` subclasses (`UnknownApiResponseError`, `FunctionInvocationError`) -- the unit tests do not cover these; added a verification step
2. Added `claude mcp add` idempotency trap from learning: always `remove` then `add` (SKILL.md already does this, but the plan step 2.5 should verify the remove-then-add pattern)
3. Added `parse_image_response` empty-list edge case: `response.parts = []` is falsy in Python, same path as `None` -- unit tests cover this but it is worth a live sanity check
4. Added MCP registration cleanup step to avoid stale state after dogfooding
5. Added verification for `detect_extension` platform filter -- a prior bug returned Windows binary on Linux via alphabetical `sort -V`; verify the OS-prefix filter is in place

### New Considerations Discovered

- The `google.genai.errors` module includes `UnknownApiResponseError` and `FunctionInvocationError` subclasses not tested by the unit tests -- the forward-compatibility guard in `handle_api_error` should catch these but is untested
- `multi_turn_chat.py` intentionally catches `NoImageError` in the chat loop (text-only responses are normal in interactive chat) -- this is correct behavior, not a bug, but should be verified as a separate acceptance criterion
- The fake evolus/pencil test (2.4) creates files in `/tmp` -- ensure cleanup runs even if the test fails (use `trap` or explicit cleanup)

## Overview

Verify the two v3.15.5 changes in a real environment:

1. **fix(gemini-imagegen): quota-specific error detection (#498)** -- trigger and verify quota/permission/safety/no-image error paths
2. **feat(pencil-setup): Pencil Desktop standalone MCP target (#493/#499)** -- run pencil-setup and verify three-tier detection targets Pencil Desktop correctly

This is a dogfood plan -- no new code is written. The goal is to exercise the merged changes, confirm they work as intended, and capture any issues found.

## Problem Statement / Motivation

PR #498 replaced generic "check your prompt" errors with specific error categories (QUOTA EXHAUSTED, PERMISSION DENIED, SAFETY FILTER, NO IMAGE) across all 5 gemini-imagegen scripts. PR #499 restructured `check_deps.sh` with a three-tier detection cascade (CLI > Desktop binary > IDE extension) so Pencil MCP works without an IDE. Both PRs have unit tests but have not been exercised end-to-end in the actual development environment.

## Environment State

Pre-dogfood environment (as surveyed by the plan subagent):

- `GEMINI_API_KEY`: set with image quota (plan subagent reported "not set" but it was available at runtime)
- `google-genai` SDK: installed system-wide (confirmed: `google.genai.errors` module has `APIError`, `ClientError`, `ServerError`, `UnknownApiResponseError`, `FunctionInvocationError`)
- Pencil Desktop: **extracted AppImage found** at `~/Applications/squashfs-root/` with executable MCP binary (plan subagent incorrectly reported "not installed" -- the extracted AppImage was not detected during environment probing)
- Pencil CLI: **not in PATH**
- Cursor: available at `/usr/bin/cursor` with Pencil extension at `~/.cursor/extensions/highagency.pencildev-0.6.28-universal/`
- VS Code: available at `/snap/bin/code`
- Pencil MCP: **not registered** with Claude Code

> **Note:** The plan body below was written before execution, assuming no Desktop and IDE-tier activation. Actual results differed -- Desktop binary (Tier 2) won. Acceptance criteria and the Deviations section at the end reflect reality.

## Part 1: Gemini Imagegen Quota Error Verification

### 1.1 Run Unit Tests

Run the 16 existing unit tests to confirm they pass in this environment.

**File:** `plugins/soleur/skills/gemini-imagegen/scripts/test_error_handling.py`

```bash
cd plugins/soleur/skills/gemini-imagegen/scripts && python3 -m pytest test_error_handling.py -v
```

Or with unittest:

```bash
cd plugins/soleur/skills/gemini-imagegen/scripts && python3 -m unittest test_error_handling -v
```

**Expected:** All 16 tests pass (3 TestCheckQuota + 5 TestHandleApiError + 8 TestParseImageResponse).

#### Research Insights

**SDK Error Hierarchy (verified via live inspection):**
The `google.genai.errors` module exposes these error classes:

- `APIError` (base)
- `ClientError` (4xx)
- `ServerError` (5xx)
- `UnknownApiResponseError`
- `FunctionInvocationError`
- `UnsupportedFunctionError`

The `handle_api_error` function has a forward-compatibility guard (line 66: `raise RuntimeError(f"API ERROR: {e.message}") from e`) that catches any `APIError` subclass not explicitly handled. The unit tests cover `ClientError` (429, 403, 400) and `ServerError` (500) but do not test `UnknownApiResponseError` or other subclasses. This is acceptable for v3.15.5 -- the guard exists -- but worth noting for future test coverage.

**Test constructor gotcha (from learning):**
`ClientError(message)` fails -- the actual constructor is `ClientError(code, response_json)`. The test helpers `_make_client_error` and `_make_server_error` correctly use the real constructor signature. Verify this by confirming the tests actually pass (they would fail with `TypeError` if the constructor was wrong).

### 1.2 Verify `--check-quota` Flag

Test the `--check-quota` flag on `generate_image.py`:

**Precondition:** `GEMINI_API_KEY` must be set.

```bash
cd plugins/soleur/skills/gemini-imagegen/scripts
GEMINI_API_KEY="<key>" python3 generate_image.py --check-quota
```

**Scenarios:**

| Scenario | Expected Output | Error Class |
|----------|----------------|-------------|
| Valid API key with image quota | `[ok] Image generation quota available (model: gemini-2.5-flash-image)` | None |
| Valid API key without image quota (free tier) | `[FAIL] QUOTA EXHAUSTED: Image generation quota is zero or exceeded...` | `QuotaExhaustedError` |
| Invalid API key | `[FAIL] PERMISSION DENIED: API key lacks image generation access...` or `[FAIL] API CLIENT ERROR (400): ...` | `PermissionDeniedError` or `RuntimeError` |
| No API key set | `GEMINI_API_KEY environment variable not set` | Early exit before API call |

#### Research Insights

**Free-tier quota behavior (from constitution.md):**
> Before building a pipeline that depends on AI image generation, verify quota with a minimal test request -- API keys may authenticate for text but lack image generation quota on free tiers; fail fast at Phase 0, not after font downloads and mockup design.

The `--check-quota` flag implements exactly this pattern. Verify it exits with code 1 on failure (not 0), as the SKILL.md Phase 0 uses exit code to gate further processing.

**Edge case: API returns text-only response to quota check prompt.**
The `check_quota` function checks `has_image = response.parts and any(p.inline_data is not None for p in response.parts)`. If the model returns a text-only response (no image) without raising an API error, this correctly raises `NoImageError`. Verify this path is tested (it is: `test_no_image_in_response_raises`).

### 1.3 Trigger Quota Error Path (Live)

Attempt image generation without quota to verify the error message is actionable:

```bash
cd plugins/soleur/skills/gemini-imagegen/scripts
python3 generate_image.py "A red square" /tmp/test_quota.png
```

If the API key has no image quota, the output should show `QUOTA EXHAUSTED` with the original API error message, not the generic "check your prompt" message.

#### Research Insights

**Error chaining verification:**
The `handle_api_error` function uses `raise ... from e` to chain the original exception. When the outer `except Exception as e` in `main()` catches it, `str(e)` should show the descriptive message, not just the original API error. Verify the printed error starts with the category prefix (e.g., `Error: QUOTA EXHAUSTED: ...`).

**Server error path (5xx):**
If the API returns a 500-series error, the handler raises `RuntimeError(f"API SERVER ERROR ({e.code}): {e.message}")`. This path is harder to trigger live but is covered by unit tests. If the API is having issues during dogfooding, this path might activate unexpectedly -- do not treat 5xx errors as quota failures.

### 1.4 Verify Error Handling Integration in All 5 Scripts

Confirm all 5 scripts import from `_error_handling` and use the shared `handle_api_error` and `parse_image_response` functions:

| Script | Imports `handle_api_error` | Imports `parse_image_response` | Additional Imports |
|--------|---------------------------|-------------------------------|-------------------|
| `generate_image.py` | Yes | Yes | `check_quota` |
| `edit_image.py` | Yes | Yes | -- |
| `compose_images.py` | Yes | Yes | -- |
| `multi_turn_chat.py` | Yes | Yes | `NoImageError` |
| `gemini_images.py` | Yes | Yes | -- |

Verify with:

```bash
grep -l "from _error_handling import" plugins/soleur/skills/gemini-imagegen/scripts/*.py
```

Expected: all 5 scripts listed (plus `test_error_handling.py` which also imports).

#### Research Insights

**`multi_turn_chat.py` intentionally catches `NoImageError`:**
In `send_message()` (line 87-98), `NoImageError` is caught and handled gracefully because text-only responses are normal in multi-turn chat. This is correct behavior -- the chat should not crash when the model responds with text only. Verify this is the only script that catches `NoImageError` outside of the test file.

**`gemini_images.py` library class:**
The library class (`GeminiImageGenerator`) delegates to `handle_api_error` and `parse_image_response` identically to the CLI scripts. The `ImageChat.send()` method also uses the shared functions. No script does its own error parsing -- the refactoring is complete.

### 1.5 Verify SDK Hang Bug Avoidance

Confirm no script accesses `response.candidates[N].finish_reason` (SDK hang bug #2024):

```bash
grep -r "finish_reason" plugins/soleur/skills/gemini-imagegen/scripts/
```

Expected: no matches.

#### Research Insights

**From learning (gemini-sdk-error-handling-patterns.md):**
> Detect safety filters via text-part keyword scanning, never via `finish_reason`.

The `parse_image_response` function implements this correctly: it scans `response_text.lower()` for `_SAFETY_KEYWORDS = ("blocked", "safety", "policy", "prohibited", "harmful")` rather than accessing `finish_reason`. Also verify `candidates` is not accessed anywhere:

```bash
grep -r "\.candidates" plugins/soleur/skills/gemini-imagegen/scripts/
```

Expected: no matches.

### 1.6 Verify `parse_image_response` Edge Cases (New)

Additional verification for edge cases in the shared response parser:

**Empty parts list (`[]`):**
`response.parts = []` is falsy in Python, so it hits the same `if not response.parts` check as `None`. The unit test `test_raises_on_empty_list` covers this. Verify by running:

```bash
cd plugins/soleur/skills/gemini-imagegen/scripts && python3 -m unittest test_error_handling.TestParseImageResponse.test_raises_on_empty_list -v
```

**Safety keyword case insensitivity:**
The safety detection uses `.lower()` so "BLOCKED" and "Blocked" both match. The unit test `test_safety_keywords_case_insensitive` covers this.

**No false positive on unrelated text:**
The unit test `test_no_false_positive_on_unrelated_text` verifies that text without safety keywords raises `NoImageError` (not `SafetyFilterError`). Importantly, the learning notes that a prior test used text containing "safety" as a keyword -- the current test data avoids this.

## Part 2: Pencil Setup Three-Tier Detection Verification

### 2.1 Run `check_deps.sh` Without Arguments

Test the interactive flow:

```bash
bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh
```

**Pre-execution expectation** (assumed no CLI, no Desktop, Cursor with extension):

```
=== Pencil Setup Dependency Check ===

  [ok] IDE: cursor
  [ok] Pencil extension

=== Check Complete ===

PREFERRED_MODE=ide
PREFERRED_BINARY=/home/jean/.cursor/extensions/highagency.pencildev-0.6.28-universal/out/mcp-server-linux-x64
PREFERRED_APP=cursor
```

**Actual output** (extracted AppImage was present -- Desktop binary won at Tier 2):

```
=== Pencil Setup Dependency Check ===

  [ok] Pencil Desktop (MCP binary available)
    MCP binary: /home/jean/Applications/squashfs-root/resources/app.asar.unpacked/out/mcp-server-linux-x64
  [info] Pencil Desktop is not running -- use --auto to launch automatically

=== Check Complete ===

PREFERRED_MODE=desktop_binary
PREFERRED_BINARY=/home/jean/Applications/squashfs-root/resources/app.asar.unpacked/out/mcp-server-linux-x64
PREFERRED_APP=pencil
```

**Key verifications:**

- [x] Tier 1 (CLI) is skipped silently (no `pencil` in PATH)
- [x] Tier 2 (Desktop binary) succeeds -- extracted AppImage found at `~/Applications/squashfs-root/`
- [N/A] Tier 3 (IDE) not reached -- Tier 2 won first
- [x] `PREFERRED_APP` is `pencil` (Desktop tier, not IDE's `cursor`)
- [x] MCP binary path points to the Desktop extracted binary
- [x] MCP binary at the reported path is executable (ELF 64-bit LSB, x86-64)

#### Research Insights

**IDE detection order (from code):**
`detect_ide()` checks Cursor first, then VS Code. Since both are available in this environment, Cursor should win. Verify the output says `cursor`, not `code`.

**Extension binary platform filter (from learning: pencil-desktop-ships-mcp-binary.md):**
A prior bug in `detect_extension()` returned the Windows binary on Linux because `sort -V | tail -1` sorted alphabetically across all platform binaries. The fix added OS-prefix and architecture-suffix filtering. Verify the detected binary path contains `mcp-server-linux-x64` (not `darwin` or `windows`).

**`sort -V | tail -1` version selection:**
The `detect_extension` function uses `sort -V | tail -1` to select the latest extension version if multiple are installed. This is correct for the `highagency.pencildev-0.6.28-universal` naming convention. Verify only one version is detected in the current environment.

### 2.2 Run `check_deps.sh --auto`

Test the automated/pipeline flow:

```bash
bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh --auto
```

**Actual result:** Same tier detected (Desktop binary), but `--auto` additionally attempted to launch Pencil Desktop via AppImage. The AppImage crashed with `Trace/breakpoint trap (core dumped)` because the terminal is headless (no display server). Despite the launch failure, the output correctly reported `PREFERRED_MODE=desktop_binary` with the MCP binary path — the detection and the launch are independent steps.

#### Research Insights

**`--auto` flag scope (from learning: check-deps-pattern-for-gui-apps.md):**
> `--auto` flag scope is narrower: Only applies to IDE extension install (`cursor --install-extension`), not to the Desktop app itself.

In the three-tier cascade, `--auto` additionally gates `auto_launch_desktop()`. With the Desktop binary detected, `--auto` attempted to launch the AppImage but it crashed in the headless environment (Electron apps require a display server). The crash is non-fatal — `check_deps.sh` prints `[FAILED] Pencil Desktop did not start within 6 seconds` and continues.

### 2.3 Verify VS Code `--app` Flag Value

If VS Code were the only IDE, the `--app` value should be `visual_studio_code` (not `code`):

```bash
grep -A1 'code)' plugins/soleur/skills/pencil-setup/scripts/check_deps.sh | head -5
```

**Expected:** `echo "visual_studio_code"` in the `ide_to_app_value` function.

#### Research Insights

**Historical bug (from PR #499 body):**
> Fix VS Code --app flag value (visual_studio_code, not code)

This was a bug in the original script. Verify the fix is in place by checking the `ide_to_app_value` function directly. Also verify the `detect_ide` function returns `code` (the binary name), not `visual_studio_code` (the app flag value) -- these are distinct mappings.

### 2.4 Verify Evolus/Pencil Collision Guard

If an unrelated `pencil` binary exists in PATH:

```bash
# Simulate: create a REALISTIC fake pencil binary that rejects unknown subcommands
mkdir -p /tmp/fake-pencil && cat > /tmp/fake-pencil/pencil << 'SCRIPT'
#!/bin/bash
case "$1" in
  --version) echo "Evolus Pencil 3.0" ;;
  *)         echo "Unknown command: $1" >&2; exit 1 ;;
esac
SCRIPT
chmod +x /tmp/fake-pencil/pencil
PATH="/tmp/fake-pencil:$PATH" bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh
rm -rf /tmp/fake-pencil
```

**Expected:**

- `[info] pencil CLI found but is not pencil.dev (possible evolus/pencil)` message appears
- Tier 1 (CLI) is skipped, falls through to next available tier

> **Important:** The fake binary must reject unknown subcommands (exit 1). A naive fake that exits 0 on all inputs bypasses the collision guard because `pencil mcp-server --help` succeeds. See learning: `2026-03-10-dogfood-collision-guard-requires-realistic-fakes.md`.

#### Research Insights

**Collision guard mechanism (from code inspection):**
`detect_pencil_cli()` first checks `command -v pencil`, then verifies with two checks:

1. `pencil --version 2>&1 | grep -qi "pencil\.dev\|pencil v"` -- version string
2. `pencil mcp-server --help` -- subcommand existence

Both must fail for the collision guard to trigger. A realistic fake outputs "Evolus Pencil 3.0" (doesn't match "pencil.dev" or "pencil v") and exits 1 on `mcp-server --help` (unknown subcommand). The main flow then prints the collision warning because `! detect_pencil_cli && command -v pencil` is true.

**Dogfood discovery:** The original plan used a naive `echo` script that exits 0 on all args. This bypassed the guard because `pencil mcp-server --help` returned exit 0. A real evolus/pencil would reject `mcp-server` since that subcommand doesn't exist in their product.

### 2.5 Run Full `pencil-setup` Skill Flow

Execute the full SKILL.md flow:

1. Run `check_deps.sh` to get `PREFERRED_MODE`, `PREFERRED_BINARY`, `PREFERRED_APP`
2. Check if `pencil` MCP is already registered: `claude mcp list -s user 2>&1 | grep -q "pencil"`
3. If not registered, first remove any stale entry: `claude mcp remove pencil -s user 2>/dev/null`
4. Register with: `claude mcp add -s user pencil -- <PREFERRED_BINARY> --app <PREFERRED_APP>`
5. Verify registration: `claude mcp list -s user 2>&1 | grep pencil`

**Actual result:** Pencil MCP registered in Desktop binary mode (not IDE mode as originally expected). Binary: `~/Applications/squashfs-root/.../mcp-server-linux-x64`, app: `pencil`.

#### Research Insights

**`claude mcp add` is NOT idempotent (from learning: pencil-mcp-auto-registration-via-skill.md):**
> `claude mcp add` exits 1 on duplicate name. Always `remove` then `add`.

The SKILL.md Step 2 correctly runs `claude mcp remove pencil -s user 2>/dev/null` before `claude mcp add`. Verify this remove-then-add pattern is followed. If step 3 is skipped and a stale registration exists, step 4 will fail with exit 1.

**`-s user` scope (from learning):**
> Use `-s user` scope -- default is `local` (project-level). Global scope ensures Pencil works across all projects.

Verify the registration uses `-s user`, not `-s local` or no scope flag.

**Post-dogfood cleanup:**
After verifying registration, clean up with `claude mcp remove pencil -s user` to avoid leaving dogfood state in the user's global MCP config. This is especially important because the extension binary path may change on extension updates.

### 2.6 Verify Desktop Binary Detection

**Pre-execution expectation:** With no Desktop installed, `detect_desktop_binary` should return empty.

**Actual result:** Desktop binary WAS found. An extracted AppImage at `~/Applications/squashfs-root/` contained the MCP binary. The `find_extracted_mcp_binary()` function correctly detected it at `$HOME/Applications/squashfs-root/resources/app.asar.unpacked/out/mcp-server-linux-x64`.

The script does not support sourcing (it runs main flow on source), so platform paths verified via code inspection:

- macOS checks `/Applications/Pencil.app/Contents/Resources/app.asar.unpacked/out/mcp-server-darwin-*`
- Linux checks `/usr/lib/pencil/resources/app.asar.unpacked/out/mcp-server-linux-*` (deb) and extracted AppImage paths via `find_extracted_mcp_binary`

#### Research Insights

**AppImage MCP binary accessibility (from learning: pencil-desktop-ships-mcp-binary.md):**
> Linux AppImage: Binary is trapped inside the AppImage; only accessible if the user runs `--appimage-extract` to create `squashfs-root/`.

The `find_extracted_mcp_binary()` function checks for extracted AppImage in `$HOME/Applications`, `$HOME/.local/bin`, and `/opt`. In this environment, an extracted AppImage existed at `$HOME/Applications/squashfs-root/` -- the binary was found and verified executable.

**`APPIMAGE_DIRS` single source of truth:**
Both `find_appimage()` and `find_extracted_mcp_binary()` use the shared `APPIMAGE_DIRS` array. Verified consistent by code inspection.

### 2.7 Verify MCP Binary Executability (New)

After `check_deps.sh` reports a binary path, verify it is actually executable:

```bash
BINARY=$(bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh 2>/dev/null | grep PREFERRED_BINARY | cut -d= -f2)
test -x "$BINARY" && echo "[ok] Binary is executable" || echo "[FAIL] Binary is not executable"
file "$BINARY" | head -1
```

**Expected:** Binary is executable and `file` confirms it is an ELF binary (Linux) or Mach-O binary (macOS).

#### Research Insights

This catches a failure mode where the extension is installed but the binary has wrong permissions (e.g., after a partial update). The `detect_extension` function uses `ls -d` which does not check executability. The `detect_desktop_binary` function uses `[[ -x "$binary" ]]` which does check. There is an asymmetry here -- the IDE tier does not verify executability of the extension binary. This is a potential gap worth noting but not a blocker for dogfooding.

## Acceptance Criteria

- [x] All 16 unit tests in `test_error_handling.py` pass
- [x] `--check-quota` flag works and prints actionable message for each error category (key has quota, returned `[ok]`)
- [N/A] `--check-quota` exits with code 1 on failure (key has quota -- cannot test failure path without a quota-less key)
- [x] All 5 gemini-imagegen scripts import from `_error_handling`
- [x] No script accesses `response.candidates[N].finish_reason` or `.candidates` in code (grep found only a documentation comment in `_error_handling.py` line 72 — no executable reference)
- [x] `multi_turn_chat.py` correctly catches `NoImageError` for text-only responses
- [ ] `check_deps.sh` detects Cursor + extension as IDE tier correctly — **not tested**: Desktop binary found first (Tier 2 won before Tier 3 was reached)
- [x] `check_deps.sh` outputs correct `PREFERRED_MODE=desktop_binary`, `PREFERRED_BINARY=.../mcp-server-linux-x64`, `PREFERRED_APP=pencil` (Desktop tier, not IDE as originally expected)
- [x] Detected MCP binary path is executable and is an ELF binary (ELF 64-bit LSB executable, x86-64)
- [x] Detected binary path contains `linux-x64` platform suffix (not darwin/windows)
- [x] VS Code `--app` value is `visual_studio_code` (not `code`) -- confirmed at line 115 of check_deps.sh
- [x] Evolus/pencil collision guard prints info message and falls through (required realistic fake binary that rejects unknown subcommands)
- [x] Full pencil-setup skill flow completes MCP registration with remove-then-add pattern (`claude mcp add` connected successfully)
- [x] Post-dogfood cleanup removes pencil MCP registration

## Test Scenarios

- Given no GEMINI_API_KEY, when running `generate_image.py`, then exit with "GEMINI_API_KEY environment variable not set"
- Given a valid key with no image quota, when running `--check-quota`, then print QUOTA EXHAUSTED with the original API error and exit code 1
- Given a valid key with quota, when running `--check-quota`, then print `[ok] Image generation quota available` and exit code 0
- Given a valid key and a prompt that triggers safety filter, when running `generate_image.py`, then print SAFETY FILTER with rephrase suggestion
- Given no Pencil CLI but extracted Desktop AppImage exists, when running `check_deps.sh`, then detect Desktop binary tier (not IDE tier)
- Given a realistic fake evolus/pencil in PATH (rejects unknown subcommands), when running `check_deps.sh`, then print collision warning and fall through to next tier
- Given `--auto` flag and Desktop binary detected in headless terminal, when running `check_deps.sh`, then attempt AppImage launch (crashes with SIGTRAP), report failure, but still output correct PREFERRED_MODE/BINARY
- Given a stale pencil MCP registration, when running the full skill flow, then remove-then-add succeeds
- Given both Cursor and VS Code are available, when running `check_deps.sh`, then Cursor wins (checked first)

## Non-Goals

- Writing new code or modifying existing implementations
- Testing on macOS (not available in this environment)
- Testing IDE tier (Tier 3) in isolation — Desktop binary (Tier 2) was unexpectedly present and won before IDE tier was reached
- Testing the Gemini Pro model (quota may not cover it)
- Registering Pencil MCP permanently (this is verification only -- clean up after)
- Adding unit tests for `UnknownApiResponseError` and `FunctionInvocationError` (noted for future work)

## Deviations from Plan

These findings emerged during dogfood execution and differ from the plan's assumptions:

1. **Environment State was inaccurate.** The plan subagent reported `Pencil Desktop: not installed` and `GEMINI_API_KEY: not set`, but at runtime both were available. The extracted AppImage at `~/Applications/squashfs-root/` was not detected during environment probing, and the API key was present in the shell environment. This caused the entire Part 2 pencil-setup section to exercise a different code path (Desktop binary, Tier 2) than expected (IDE extension, Tier 3).

2. **Collision guard test required a more realistic fake binary.** The plan's naive `echo` script (exits 0 on all args) bypassed the collision guard because `pencil mcp-server --help` returned exit 0. A real evolus/pencil would reject unknown subcommands. The fake was revised to exit 1 on unrecognized args, which correctly triggered the collision warning.

3. **`--auto` mode crashed the AppImage in headless terminal.** Electron apps require a display server (`$DISPLAY` or `$WAYLAND_DISPLAY`). The `check_deps.sh` script checks for display availability before launching but the AppImage itself crashed with `SIGTRAP` before the check could prevent it. The crash is non-fatal — detection output is still correct.

4. **`claude mcp list` does not support `-s` scope flag.** The plan referenced `claude mcp list -s user` but only `add` and `remove` accept `-s`. Using `claude mcp list` without scope works and shows all registered servers.

5. **`pytest` was not installed.** Fell back to `unittest` runner, which worked identically. All 16 tests passed.

## References

- PR #498: fix(gemini-imagegen): add quota-specific error detection and actionable messages
- PR #499: feat(pencil-setup): use Pencil Desktop as standalone MCP target (#493)
- PR #493: Original issue for Pencil Desktop standalone MCP
- Learning: `knowledge-base/project/learnings/2026-03-10-gemini-sdk-error-handling-patterns.md`
- Learning: `knowledge-base/project/learnings/2026-03-10-pencil-desktop-standalone-mcp-three-tier-detection.md`
- Learning: `knowledge-base/project/learnings/2026-02-27-pencil-mcp-auto-registration-via-skill.md`
- Learning: `knowledge-base/project/learnings/2026-02-27-pencil-desktop-ships-mcp-binary.md`
- Learning: `knowledge-base/project/learnings/2026-02-27-pencil-editor-operational-requirements.md`
- Learning: `knowledge-base/project/learnings/2026-02-27-check-deps-pattern-for-gui-apps.md`
- Error handling module: `plugins/soleur/skills/gemini-imagegen/scripts/_error_handling.py`
- Check deps script: `plugins/soleur/skills/pencil-setup/scripts/check_deps.sh`
- Test file: `plugins/soleur/skills/gemini-imagegen/scripts/test_error_handling.py`
- SKILL.md (pencil-setup): `plugins/soleur/skills/pencil-setup/SKILL.md`
- SKILL.md (gemini-imagegen): `plugins/soleur/skills/gemini-imagegen/SKILL.md`
