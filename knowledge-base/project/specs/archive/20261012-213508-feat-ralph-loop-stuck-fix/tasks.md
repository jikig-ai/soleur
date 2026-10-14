# Tasks: fix ralph loop stuck detection

## Phase 1: Core Hook Changes

### 1.1 Raise stuck detection char threshold

- [ ] 1.1.1 Change `$RESPONSE_LENGTH -lt 20` to `$RESPONSE_LENGTH -lt 150` in `plugins/soleur/hooks/stop-hook.sh` (line 175)
- [ ] 1.1.2 Update tier comment block (lines 170-174) to reflect 150-char threshold

### 1.2 Add similarity detection to stop-hook.sh

- [ ] 1.2.1 Add `similarity_count` and `last_response_words` frontmatter parsing with `|| true` guards after existing `REPEAT_COUNT` parsing (around line 74)
- [ ] 1.2.2 Add default value blocks for `similarity_count` (same pattern as `STUCK_COUNT` default)
- [ ] 1.2.3 Insert similarity detection block after repetition detection (after line 194): word tokenization via `tr -cs '[:alnum:]' '\n' | sort -u`, Jaccard computation via `comm`, threshold check at >=80%
- [ ] 1.2.4 Add similarity threshold termination (3 consecutive) with stderr message and `rm -f` cleanup
- [ ] 1.2.5 Add `similarity_count` and `last_response_words` to the awk state update block (lines 216-223)

### 1.3 Update setup script

- [ ] 1.3.1 Add `similarity_count: 0` and `last_response_words:` to state file template in `plugins/soleur/scripts/setup-ralph-loop.sh` (lines 144-158)
- [ ] 1.3.2 Update help text stuck detection description: "< 150 chars" instead of "< 20 chars" and mention similarity detection (lines 52-58)

## Phase 2: Tests (scope is larger than originally planned -- 19 tests affected)

### 2.1 Add shared substantive response constant

- [ ] 2.1.1 Define `SUBSTANTIVE_RESPONSE` variable near top of test file (~220 stripped chars, well above 150 threshold)

### 2.2 Update existing tests for 150-char threshold

- [ ] 2.2.1 Replace response strings in Tests 3, 7, 12, 13, 14, 15, 17, 26, 30, 35 with `"$SUBSTANTIVE_RESPONSE"`
- [ ] 2.2.2 Update Test 5 boundary: generate exactly 150-char test string (was 20)
- [ ] 2.2.3 Update Test 6 boundary: generate exactly 149-char test string (was 19)
- [ ] 2.2.4 Update Test 5 and Test 6 echo descriptions to say "150 characters" / "149 characters"

### 2.3 Update `create_state_file` helper

- [ ] 2.3.1 Add `similarity_count` (param 9) and `last_response_words` (param 10) to `create_state_file()` function
- [ ] 2.3.2 Add those fields to the heredoc template in `create_state_file()`

### 2.4 Add similarity detection tests

- [ ] 2.4.1 Test: 3 consecutive similar (>=80% Jaccard word overlap) responses trigger termination
- [ ] 2.4.2 Test: dissimilar response resets similarity_count to 0
- [ ] 2.4.3 Test: pre-existing state file without similarity fields uses defaults (backward compat)
- [ ] 2.4.4 Test: setup-ralph-loop.sh includes similarity_count and last_response_words in state file

### 2.5 Add idle pattern isolation test

- [ ] 2.5.1 Test: idle pattern detected in 150-199 char response (above length threshold, below idle pattern gate)

### 2.6 Run full test suite

- [ ] 2.6.1 Run `bash plugins/soleur/test/ralph-loop.test.sh` and verify all tests pass (existing + new)

## Phase 3: Verification

### 3.1 Compound and commit

- [ ] 3.1.1 Run `soleur:compound` before commit
- [ ] 3.1.2 Commit changes
- [ ] 3.1.3 Push and update PR #729
