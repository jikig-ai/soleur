# Tasks: fix ralph loop idle detection

## Phase 1: Core Implementation

### 1.1 Add idle pattern detection to stop-hook.sh
- [ ] 1.1.1 Add response length gate: only apply idle pattern detection when `RESPONSE_LENGTH < 200` (prevents false positives on substantive responses containing idle substrings)
- [ ] 1.1.2 Add whitespace normalization and case-folding of `LAST_OUTPUT` to `NORMALIZED_OUTPUT` (inside the length gate)
- [ ] 1.1.3 Add `grep -iqE` check against idle patterns (all done/complete/finished, nothing left/pending/remaining, no active/running/pending commands, session complete/finished, already done/complete/finished). Use `if` wrapping (NOT `|| true`) to absorb grep exit 1 under `set -euo pipefail`
- [ ] 1.1.4 Set `IS_IDLE=true` when any pattern matches
- [ ] 1.1.5 Update stuck counter logic: increment on `IS_IDLE=true` OR `RESPONSE_LENGTH < 20`, reset to 0 only when neither condition holds

### 1.2 Add repetition detection to stop-hook.sh
- [ ] 1.2.1 Parse `last_response_hash` and `repeat_count` from frontmatter (with `|| true` guards for `set -euo pipefail` safety)
- [ ] 1.2.2 Default `repeat_count` to 0 if missing or non-numeric (backward compatibility with pre-existing state files)
- [ ] 1.2.3 Compute `CURRENT_HASH` via `md5sum` on lowercased stripped output (only when `STRIPPED_OUTPUT` is non-empty)
- [ ] 1.2.4 Compare `CURRENT_HASH` to `LAST_RESPONSE_HASH`: increment `repeat_count` if same, reset to 0 if different
- [ ] 1.2.5 Add repetition threshold check (`repeat_count >= 3`): terminate with diagnostic message to stderr, remove state file, exit 0
- [ ] 1.2.6 Update the awk frontmatter persistence block to include `last_response_hash` and `repeat_count` (with `c==1` guard to prevent prompt body corruption per awk-scoping learning)

### 1.3 Update setup-ralph-loop.sh
- [ ] 1.3.1 Add `last_response_hash:` (empty) and `repeat_count: 0` to state file frontmatter template
- [ ] 1.3.2 Update help text DESCRIPTION to document idle pattern detection and repetition detection

## Phase 2: Testing

### 2.1 Update test helpers
- [ ] 2.1.1 Update `create_state_file` helper to include `last_response_hash` and `repeat_count` parameters

### 2.2 Add idle pattern detection tests
- [ ] 2.2.1 Test: "All slash commands are finished" (<200 chars) increments stuck counter (idle pattern match despite >20 chars)
- [ ] 2.2.2 Test: "Nothing left to do" increments stuck counter
- [ ] 2.2.3 Test: "Session already complete" increments stuck counter
- [ ] 2.2.4 Test: 3 consecutive idle-pattern responses trigger termination
- [ ] 2.2.5 Test: Non-idle substantive response still resets stuck counter
- [ ] 2.2.6 Test: Long response (>= 200 chars stripped) containing idle substring is NOT treated as idle (length gate prevents false positive)
- [ ] 2.2.7 Test: Response of 199 chars stripped with idle pattern IS treated as idle (under length gate)

### 2.3 Add repetition detection tests
- [ ] 2.3.1 Test: 3 identical responses trigger repetition detection termination
- [ ] 2.3.2 Test: 2 identical responses followed by different response resets repeat counter
- [ ] 2.3.3 Test: Pre-existing state file without `last_response_hash` / `repeat_count` works (backward compatibility)

### 2.4 Regression tests
- [ ] 2.4.1 Test: Original empty-response stuck detection still works (existing tests pass)
- [ ] 2.4.2 Run full test suite: `bash plugins/soleur/test/ralph-loop-stuck-detection.test.sh`

## Phase 3: Validation

### 3.1 Final checks
- [ ] 3.1.1 Verify all existing tests pass (backward compatibility)
- [ ] 3.1.2 Verify new tests pass
- [ ] 3.1.3 Run compound skill before commit
