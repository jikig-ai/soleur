# Tasks: fix gemini-imagegen quota error detection

## Phase 1: Shared Error Handling

- [ ] 1.1 Create `plugins/soleur/skills/gemini-imagegen/scripts/_error_handling.py` helper module
  - [ ] 1.1.1 Import `google.genai.errors` (`ClientError`, `ServerError`, `APIError`) -- these are the correct exception classes (NOT `google.api_core.exceptions`)
  - [ ] 1.1.2 Define custom exception classes: `QuotaExhaustedError`, `PermissionDeniedError`, `SafetyFilterError`, `NoImageError`
  - [ ] 1.1.3 Implement `handle_api_error(e)` that inspects `ClientError.code` (429=quota, 403=permission, 400=invalid) and raises the appropriate custom exception
  - [ ] 1.1.4 Implement `check_response_for_image(response, output_path)` that parses response parts, detects safety filters via text keywords (NOT via `finish_reason` -- SDK hang bug #2024), and raises on missing image
  - [ ] 1.1.5 Implement `check_quota(client, model)` function for `--check-quota` dry-run

## Phase 2: Update Scripts

- [ ] 2.1 Update `generate_image.py`
  - [ ] 2.1.1 Import from `_error_handling`, wrap `generate_content()` call in `try/except errors.ClientError`
  - [ ] 2.1.2 Replace "No image was generated. Check your prompt" with `check_response_for_image()` call
  - [ ] 2.1.3 Add `--check-quota` argparse flag that calls `check_quota()` and exits
- [ ] 2.2 Update `edit_image.py`
  - [ ] 2.2.1 Import from `_error_handling`, wrap `generate_content()` call in `try/except errors.ClientError`
  - [ ] 2.2.2 Replace "No image was generated. Check your instruction" with `check_response_for_image()` call
- [ ] 2.3 Update `compose_images.py`
  - [ ] 2.3.1 Import from `_error_handling`, wrap `generate_content()` call in `try/except errors.ClientError`
  - [ ] 2.3.2 Replace "No image was generated." with `check_response_for_image()` call
- [ ] 2.4 Update `gemini_images.py` library class
  - [ ] 2.4.1 Wrap `generate_content()` in `generate()`, `edit()`, `compose()` with `try/except errors.ClientError` + `handle_api_error()`
  - [ ] 2.4.2 Wrap `send_message()` in `ImageChat.send()` with same error handling
  - [ ] 2.4.3 Raise `NoImageError` on missing image parts instead of silently returning `(output, None)`
- [ ] 2.5 Update `multi_turn_chat.py`
  - [ ] 2.5.1 Wrap `send_message()` in `ImageChat.send_message()` with `try/except errors.ClientError` + `handle_api_error()`
  - [ ] 2.5.2 Display differentiated error messages in the interactive loop's except block

## Phase 3: Verify

- [ ] 3.1 Run `python3 -m py_compile` on all 6 files (5 existing + `_error_handling.py`) to verify no syntax errors
- [ ] 3.2 Run `python3 generate_image.py --check-quota` to validate the flag (requires GEMINI_API_KEY)
- [ ] 3.3 Verify `--help` output includes `--check-quota` documentation
- [ ] 3.4 Verify no code accesses `response.candidates[N].finish_reason` (avoids SDK hang bug #2024)
