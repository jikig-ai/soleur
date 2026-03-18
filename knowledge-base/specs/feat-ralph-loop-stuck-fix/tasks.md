# Tasks: fix ralph loop stuck detection

## Phase 1: Core Changes

### 1.1 Raise stuck detection char threshold
- [ ] 1.1.1 Change `$RESPONSE_LENGTH -lt 20` to `$RESPONSE_LENGTH -lt 150` in `plugins/soleur/hooks/stop-hook.sh` (line 175)
- [ ] 1.1.2 Update tier comment block (lines 170-174) to reflect 150-char threshold

### 1.2 Add similarity detection
- [ ] 1.2.1 Add `similarity_count` and `last_response_words` frontmatter parsing with `|| true` guards after existing `REPEAT_COUNT` parsing (around line 74)
- [ ] 1.2.2 Add default value blocks for `similarity_count` (same pattern as `STUCK_COUNT` default)
- [ ] 1.2.3 Insert similarity detection block after repetition detection (after line 194): word tokenization, Jaccard computation via `comm`, threshold check at 80%
- [ ] 1.2.4 Add similarity threshold termination with stderr message and `rm -f` cleanup
- [ ] 1.2.5 Add `similarity_count` and `last_response_words` to the awk state update block (lines 216-223)

### 1.3 Update setup script
- [ ] 1.3.1 Add `similarity_count: 0` and `last_response_words:` to state file template in `plugins/soleur/scripts/setup-ralph-loop.sh` (lines 144-158)
- [ ] 1.3.2 Update help text stuck detection description: "< 150 chars" instead of "< 20 chars" and mention similarity detection

## Phase 2: Tests

### 2.1 Update existing threshold tests
- [ ] 2.1.1 Update Test 5 boundary: 20 chars to 150 chars (generate a 150-char test string)
- [ ] 2.1.2 Update Test 6 boundary: 19 chars to 149 chars (generate a 149-char test string)
- [ ] 2.1.3 Ensure Test 3 response exceeds 150 stripped chars (currently ~70 chars)
- [ ] 2.1.4 Audit all other tests using short "substantive" responses and ensure they exceed 150 chars

### 2.2 Add similarity detection tests
- [ ] 2.2.1 Test: 3 consecutive similar (>=80% word overlap) responses trigger termination
- [ ] 2.2.2 Test: dissimilar response resets similarity_count to 0
- [ ] 2.2.3 Test: pre-existing state file without similarity fields uses defaults
- [ ] 2.2.4 Test: setup-ralph-loop.sh includes similarity_count and last_response_words in state file

### 2.3 Run full test suite
- [ ] 2.3.1 Run `bash plugins/soleur/test/ralph-loop.test.sh` and verify all tests pass

## Phase 3: Verification

### 3.1 Compound and commit
- [ ] 3.1.1 Run `soleur:compound` before commit
- [ ] 3.1.2 Commit changes
- [ ] 3.1.3 Push and update PR #729
