# Tasks: Unify X Response Handling

## Phase 1: Extract handle_response

- [ ] 1.1 Read `x-community.sh` and identify the exact lines of the duplicated case/esac in `x_request` (lines 203-250) and `get_request` (lines 302-355)
- [ ] 1.2 Create `handle_response` function accepting `http_code`, `body`, `endpoint`, `depth`, and retry callback varargs
- [ ] 1.3 Implement the unified case/esac in `handle_response` with the richer 403 `reason` parsing from `get_request`
- [ ] 1.4 Include `depth` as the 4th parameter so the 429 log message preserves `(attempt N/3)` format
- [ ] 1.5 Add source guard at bottom of script: replace bare `main "$@"` with `[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"` to enable test harness sourcing

## Phase 2: Refactor callers

- [ ] 2.1 Rename `x_request` to `post_request` in `x-community.sh`
- [ ] 2.2 Remove the `method` parameter (always POST) -- simplify to `post_request endpoint [json_body] [depth]`
- [ ] 2.3 Replace duplicated case/esac in `post_request` with `handle_response "$http_code" "$body" "$endpoint" "$depth" post_request "$endpoint" "$json_body" "$((depth + 1))"`
- [ ] 2.4 Replace duplicated case/esac in `get_request` with `handle_response "$http_code" "$body" "$endpoint" "$depth" get_request "$endpoint" "$query_params" "$((depth + 1))"`
- [ ] 2.5 Update `cmd_post_tweet` call site from `x_request "POST"` to `post_request` (line 552)
- [ ] 2.6 No function ordering constraint needed -- bash resolves function names at call time, not definition time

## Phase 3: Testing

- [ ] 3.1 Run existing tests (`bun test test/x-community.test.ts`) to verify no regressions
- [ ] 3.2 Create test harness `test/helpers/test-handle-response.sh` that sources x-community.sh and exposes handle_response for direct invocation
- [ ] 3.3 Add `handle_response` unit tests for each HTTP status code:
  - [ ] 3.3.1 Test 2xx with valid JSON echoes body
  - [ ] 3.3.2 Test 2xx with malformed JSON exits 1
  - [ ] 3.3.3 Test 401 exits 1 with credential instructions
  - [ ] 3.3.4 Test 403 with `client-not-enrolled` reason gives paid access guidance
  - [ ] 3.3.5 Test 403 with `official-client-forbidden` reason gives permissions guidance
  - [ ] 3.3.6 Test 403 with no reason gives generic message
  - [ ] 3.3.7 Test default status code exits 1 with parsed error detail
- [ ] 3.4 Add regression test: `post_request` 403 with `client-not-enrolled` gives same rich message as GET (the divergence fix from #492)
- [ ] 3.5 Update script header comment to document `post_request` (not `x_request`)

## Phase 4: Validation

- [ ] 4.1 Run `bun test` for full test suite
- [ ] 4.2 Verify no references to `x_request` remain: `grep -rn 'x_request' plugins/soleur/skills/community/scripts/x-community.sh` returns zero matches
- [ ] 4.3 Run compound before commit
