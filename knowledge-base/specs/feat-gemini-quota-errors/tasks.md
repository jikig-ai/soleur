# Tasks: fix gemini-imagegen quota error detection

## Phase 1: Shared Error Handling

- [ ] 1.1 Create `_error_handling.py` helper module (or add to `gemini_images.py`)
  - [ ] 1.1.1 Import `google.api_core.exceptions.ResourceExhausted` and `PermissionDenied` with try/except fallback
  - [ ] 1.1.2 Implement `wrap_generate_content(client_call, *args, **kwargs)` that catches quota/permission exceptions and raises differentiated errors
  - [ ] 1.1.3 Implement `parse_response_parts(response)` that checks for image parts and differentiates safety filter vs. empty response
  - [ ] 1.1.4 Implement `check_quota(client, model)` function for `--check-quota` dry-run

## Phase 2: Update Scripts

- [ ] 2.1 Update `generate_image.py`
  - [ ] 2.1.1 Replace bare `generate_content()` call with shared error-handling wrapper
  - [ ] 2.1.2 Replace "No image was generated. Check your prompt" with differentiated error messages
  - [ ] 2.1.3 Add `--check-quota` argparse flag that calls `check_quota()` and exits
- [ ] 2.2 Update `edit_image.py`
  - [ ] 2.2.1 Replace bare `generate_content()` call with shared error-handling wrapper
  - [ ] 2.2.2 Replace "No image was generated. Check your instruction" with differentiated error messages
- [ ] 2.3 Update `compose_images.py`
  - [ ] 2.3.1 Replace bare `generate_content()` call with shared error-handling wrapper
  - [ ] 2.3.2 Replace "No image was generated." with differentiated error messages
- [ ] 2.4 Update `gemini_images.py` library class
  - [ ] 2.4.1 Wrap `generate_content()` in `generate()`, `edit()`, `compose()` with error handling
  - [ ] 2.4.2 Wrap `send_message()` in `ImageChat.send()` with error handling
  - [ ] 2.4.3 Raise `RuntimeError` on missing image parts instead of silently returning
- [ ] 2.5 Update `multi_turn_chat.py`
  - [ ] 2.5.1 Wrap `send_message()` in `ImageChat.send_message()` with error handling
  - [ ] 2.5.2 Display differentiated error messages in the interactive loop

## Phase 3: Verify

- [ ] 3.1 Run `python3 -m py_compile` on all 5 scripts to verify no syntax errors
- [ ] 3.2 Run `python3 generate_image.py --check-quota` to validate the flag (requires GEMINI_API_KEY)
- [ ] 3.3 Verify `--help` output includes `--check-quota` documentation
