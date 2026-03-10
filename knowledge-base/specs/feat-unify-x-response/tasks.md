# Tasks: Unify X Response Handling

## Phase 1: Extract handle_response

- [ ] 1.1 Read `x-community.sh` and identify the exact lines of the duplicated case/esac in `x_request` (lines 203-250) and `get_request` (lines 302-355)
- [ ] 1.2 Create `handle_response` function above both helpers, accepting `http_code`, `body`, `endpoint`, and retry callback args
- [ ] 1.3 Implement the unified case/esac in `handle_response` with the richer 403 `reason` parsing from `get_request`
- [ ] 1.4 Include attempt counter in 429 log message by accepting depth as a parameter or extracting from retry args

## Phase 2: Refactor callers

- [ ] 2.1 Rename `x_request` to `post_request` in `x-community.sh`
- [ ] 2.2 Remove POST-specific method arg (it is always POST) -- simplify to `post_request endpoint [json_body] [depth]`
- [ ] 2.3 Replace duplicated case/esac in `post_request` with `handle_response` delegation
- [ ] 2.4 Replace duplicated case/esac in `get_request` with `handle_response` delegation
- [ ] 2.5 Update `cmd_post_tweet` call site from `x_request` to `post_request` (line 552)
- [ ] 2.6 Verify function ordering: `handle_response` must be defined before `post_request` and `get_request`

## Phase 3: Testing

- [ ] 3.1 Run existing tests (`bun test test/x-community.test.ts`) to verify no regressions
- [ ] 3.2 Add `handle_response` unit tests for each HTTP status code (2xx, 401, 403 with reason variants, 429 clamping, default)
  - [ ] 3.2.1 Test 2xx with valid JSON echoes body
  - [ ] 3.2.2 Test 2xx with malformed JSON exits 1
  - [ ] 3.2.3 Test 401 exits 1 with credential instructions
  - [ ] 3.2.4 Test 403 with `client-not-enrolled` reason gives paid access guidance
  - [ ] 3.2.5 Test 403 with `official-client-forbidden` reason gives permissions guidance
  - [ ] 3.2.6 Test 403 with no reason gives generic message
  - [ ] 3.2.7 Test default status code exits 1 with parsed error detail
- [ ] 3.3 Add regression test: `post_request` 403 with `client-not-enrolled` gives same rich message as GET (the divergence fix)
- [ ] 3.4 Update script header comment to list `post-tweet` using `post_request` (not `x_request`)

## Phase 4: Validation

- [ ] 4.1 Run `bun test` for full test suite
- [ ] 4.2 Verify no references to `x_request` remain in the codebase (grep check)
- [ ] 4.3 Run compound before commit
