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

Current environment:
- `GEMINI_API_KEY`: **not set** -- must be set for live quota verification
- `google-genai` SDK: installed system-wide (confirmed: `google.genai.errors` module has `APIError`, `ClientError`, `ServerError`, `UnknownApiResponseError`, `FunctionInvocationError`)
- Pencil Desktop: **not installed**
- Pencil CLI: **not in PATH**
- Cursor: available at `/usr/bin/cursor` with Pencil extension at `~/.cursor/extensions/highagency.pencildev-0.6.28-universal/`
- VS Code: available at `/snap/bin/code`
- Pencil MCP: **not registered** with Claude Code

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

**Expected output** (given environment: no CLI, no Desktop, Cursor with extension):

```
=== Pencil Setup Dependency Check ===

  [ok] IDE: cursor
  [ok] Pencil extension

=== Check Complete ===

PREFERRED_MODE=ide
PREFERRED_BINARY=/home/jean/.cursor/extensions/highagency.pencildev-0.6.28-universal/out/mcp-server-linux-x64
PREFERRED_APP=cursor
```

**Key verifications:**
- [ ] Tier 1 (CLI) is skipped silently (no `pencil` in PATH)
- [ ] Tier 2 (Desktop) is skipped silently (no Desktop installed)
- [ ] Tier 3 (IDE) succeeds with Cursor and extension
- [ ] `PREFERRED_APP` is `cursor` (not `code`)
- [ ] MCP binary path points to the actual extension binary
- [ ] MCP binary at the reported path is actually executable (`test -x <path>`)

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

**Expected:** Same as 2.1 (no Desktop to auto-launch, extension already installed).

#### Research Insights

**`--auto` flag scope (from learning: check-deps-pattern-for-gui-apps.md):**
> `--auto` flag scope is narrower: Only applies to IDE extension install (`cursor --install-extension`), not to the Desktop app itself.

In the three-tier cascade, `--auto` additionally gates `auto_launch_desktop()`. Since no Desktop is installed, this code path is not exercised. The only observable difference from non-auto mode is that the extension install prompt would be auto-accepted (but the extension is already installed, so no difference).

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
# Simulate: create a fake pencil binary
mkdir -p /tmp/fake-pencil && printf '#!/bin/bash\necho "Evolus Pencil 3.0"\n' > /tmp/fake-pencil/pencil && chmod +x /tmp/fake-pencil/pencil
PATH="/tmp/fake-pencil:$PATH" bash plugins/soleur/skills/pencil-setup/scripts/check_deps.sh
rm -rf /tmp/fake-pencil
```

**Expected:**
- `[info] pencil CLI found but is not pencil.dev (possible evolus/pencil)` message appears
- Tier 1 (CLI) is skipped, falls through to Tier 3 (IDE)

#### Research Insights

**Collision guard mechanism (from code inspection):**
`detect_pencil_cli()` first checks `command -v pencil`, then verifies with two checks:
1. `pencil --version 2>&1 | grep -qi "pencil\.dev\|pencil v"` -- version string
2. `pencil mcp-server --help` -- subcommand existence

Both must fail for the collision guard to trigger. The fake binary outputs "Evolus Pencil 3.0" which does not match "pencil.dev" or "pencil v", and the `mcp-server` subcommand will fail. The main flow then prints the collision warning because `! detect_pencil_cli && command -v pencil` is true.

**Cleanup safety:**
The `rm -rf /tmp/fake-pencil` cleanup should run even if the test command fails. Consider using a subshell or trap to ensure cleanup. The plan step as written runs cleanup unconditionally after the test (sequential with no error gating), which is correct.

### 2.5 Run Full `pencil-setup` Skill Flow

Execute the full SKILL.md flow:

1. Run `check_deps.sh` to get `PREFERRED_MODE`, `PREFERRED_BINARY`, `PREFERRED_APP`
2. Check if `pencil` MCP is already registered: `claude mcp list -s user 2>&1 | grep -q "pencil"`
3. If not registered, first remove any stale entry: `claude mcp remove pencil -s user 2>/dev/null`
4. Register with: `claude mcp add -s user pencil -- <PREFERRED_BINARY> --app <PREFERRED_APP>`
5. Verify registration: `claude mcp list -s user 2>&1 | grep pencil`

**Expected:** Pencil MCP registered in IDE mode with the Cursor extension binary.

#### Research Insights

**`claude mcp add` is NOT idempotent (from learning: pencil-mcp-auto-registration-via-skill.md):**
> `claude mcp add` exits 1 on duplicate name. Always `remove` then `add`.

The SKILL.md Step 2 correctly runs `claude mcp remove pencil -s user 2>/dev/null` before `claude mcp add`. Verify this remove-then-add pattern is followed. If step 3 is skipped and a stale registration exists, step 4 will fail with exit 1.

**`-s user` scope (from learning):**
> Use `-s user` scope -- default is `local` (project-level). Global scope ensures Pencil works across all projects.

Verify the registration uses `-s user`, not `-s local` or no scope flag.

**Post-dogfood cleanup:**
After verifying registration, clean up with `claude mcp remove pencil -s user` to avoid leaving dogfood state in the user's global MCP config. This is especially important because the extension binary path may change on extension updates.

### 2.6 Verify Desktop Binary Detection (Negative)

With no Desktop installed, the `detect_desktop_binary` function should return empty:

The script does not support sourcing (it runs main flow on source), so verify via code inspection that:
- macOS checks `/Applications/Pencil.app/Contents/Resources/app.asar.unpacked/out/mcp-server-darwin-*`
- Linux checks `/usr/lib/pencil/resources/app.asar.unpacked/out/mcp-server-linux-*` (deb) and extracted AppImage paths via `find_extracted_mcp_binary`

#### Research Insights

**AppImage MCP binary accessibility (from learning: pencil-desktop-ships-mcp-binary.md):**
> Linux AppImage: Binary is trapped inside the AppImage; only accessible if the user runs `--appimage-extract` to create `squashfs-root/`.

The `find_extracted_mcp_binary()` function checks for extracted AppImage in `$HOME/Applications`, `$HOME/.local/bin`, and `/opt`. This is correct -- the binary is at `<dir>/squashfs-root/resources/app.asar.unpacked/out/mcp-server-linux-${MCP_SUFFIX}`. Since no Desktop or extracted AppImage exists in this environment, this function returns 1 and the tier falls through.

**`APPIMAGE_DIRS` single source of truth:**
Both `find_appimage()` and `find_extracted_mcp_binary()` use the shared `APPIMAGE_DIRS` array. Verify these are consistent by code inspection (they are -- both iterate the same array).

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

- [ ] All 16 unit tests in `test_error_handling.py` pass
- [ ] `--check-quota` flag works and prints actionable message for each error category
- [ ] `--check-quota` exits with code 1 on failure (not 0)
- [ ] All 5 gemini-imagegen scripts import from `_error_handling`
- [ ] No script accesses `response.candidates[N].finish_reason` or `.candidates`
- [ ] `multi_turn_chat.py` correctly catches `NoImageError` for text-only responses
- [ ] `check_deps.sh` detects Cursor + extension as IDE tier correctly
- [ ] `check_deps.sh` outputs correct `PREFERRED_MODE=ide`, `PREFERRED_BINARY`, `PREFERRED_APP=cursor`
- [ ] Detected MCP binary path is executable and is an ELF binary
- [ ] Detected binary path contains `linux-x64` platform suffix (not darwin/windows)
- [ ] VS Code `--app` value is `visual_studio_code` (not `code`)
- [ ] Evolus/pencil collision guard prints info message and falls through
- [ ] Full pencil-setup skill flow completes MCP registration with remove-then-add pattern
- [ ] Post-dogfood cleanup removes pencil MCP registration

## Test Scenarios

- Given no GEMINI_API_KEY, when running `generate_image.py`, then exit with "GEMINI_API_KEY environment variable not set"
- Given a valid key with no image quota, when running `--check-quota`, then print QUOTA EXHAUSTED with the original API error and exit code 1
- Given a valid key with quota, when running `--check-quota`, then print `[ok] Image generation quota available` and exit code 0
- Given a valid key and a prompt that triggers safety filter, when running `generate_image.py`, then print SAFETY FILTER with rephrase suggestion
- Given no Pencil CLI or Desktop, when running `check_deps.sh`, then detect IDE tier (Cursor + extension)
- Given a fake evolus/pencil in PATH, when running `check_deps.sh`, then print collision warning and fall through to IDE
- Given `--auto` flag, when running `check_deps.sh` with no Desktop installed, then skip auto-launch gracefully
- Given a stale pencil MCP registration, when running the full skill flow, then remove-then-add succeeds
- Given both Cursor and VS Code are available, when running `check_deps.sh`, then Cursor wins (checked first)

## Non-Goals

- Writing new code or modifying existing implementations
- Testing on macOS or with Pencil Desktop installed (not available in this environment)
- Testing the Gemini Pro model (quota may not cover it)
- Registering Pencil MCP permanently (this is verification only -- clean up after)
- Adding unit tests for `UnknownApiResponseError` and `FunctionInvocationError` (noted for future work)

## References

- PR #498: fix(gemini-imagegen): add quota-specific error detection and actionable messages
- PR #499: feat(pencil-setup): use Pencil Desktop as standalone MCP target (#493)
- PR #493: Original issue for Pencil Desktop standalone MCP
- Learning: `knowledge-base/learnings/2026-03-10-gemini-sdk-error-handling-patterns.md`
- Learning: `knowledge-base/learnings/2026-03-10-pencil-desktop-standalone-mcp-three-tier-detection.md`
- Learning: `knowledge-base/learnings/2026-02-27-pencil-mcp-auto-registration-via-skill.md`
- Learning: `knowledge-base/learnings/2026-02-27-pencil-desktop-ships-mcp-binary.md`
- Learning: `knowledge-base/learnings/2026-02-27-pencil-editor-operational-requirements.md`
- Learning: `knowledge-base/learnings/2026-02-27-check-deps-pattern-for-gui-apps.md`
- Error handling module: `plugins/soleur/skills/gemini-imagegen/scripts/_error_handling.py`
- Check deps script: `plugins/soleur/skills/pencil-setup/scripts/check_deps.sh`
- Test file: `plugins/soleur/skills/gemini-imagegen/scripts/test_error_handling.py`
- SKILL.md (pencil-setup): `plugins/soleur/skills/pencil-setup/SKILL.md`
- SKILL.md (gemini-imagegen): `plugins/soleur/skills/gemini-imagegen/SKILL.md`
