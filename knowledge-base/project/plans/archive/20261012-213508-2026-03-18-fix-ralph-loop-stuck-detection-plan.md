---
title: "fix: harden ralph loop stuck detection thresholds and add similarity detection"
type: fix
date: 2026-03-18
deepened: 2026-03-18
---

# fix: harden ralph loop stuck detection thresholds and add similarity detection

## Enhancement Summary

**Deepened on:** 2026-03-18
**Sections enhanced:** 6
**Research methods:** Manual code analysis, bash correctness testing, test coverage audit

### Key Improvements from Deepening

1. **Critical test scope correction:** Original plan identified 3 tests needing updates; deepening found **12 must-update** and **7 semantically affected** tests (19 total). Every "substantive" test response is under 150 stripped chars.
2. **`comm` union correctness verified:** The `comm | sort -u | wc -l` approach for Jaccard union is correct (each word appears in exactly one `comm` column), confirmed by empirical testing.
3. **`awk -v` safety verified:** The word tokenizer strips all non-alphanumeric chars, so `awk -v` backslash-escape interpretation is a non-issue. Confirmed by testing.
4. **Idle pattern test isolation gap:** Tests 22 and 24 test idle patterns on <150-char strings. After the threshold change, these strings are caught by both the length check AND the idle pattern. To truly test idle detection in isolation, need one test with a 150-199 char idle response.

### New Considerations Discovered

- State file `last_response_words` field grows to ~200-1700 bytes depending on response vocabulary. Empirically verified up to 200 unique words (1718 bytes) with successful grep/awk round-trip.
- `create_state_file` helper in tests needs new parameters for `similarity_count` and `last_response_words`.

## Overview

Harden the ralph loop's stuck detection to catch loops that produce non-trivial but unproductive output. The current 20-char threshold is too low -- responses between 20-149 chars that don't match idle patterns slip through as "substantive." Additionally, add response similarity detection (not just exact hash matching) to catch loops producing minor variations of the same response.

## Problem Statement

Three operational gaps in the current ralph loop stuck detection:

1. **Char threshold too low (20 chars):** Responses like "I'll check on that." (20 chars stripped) pass the length check as substantive. Real productive work generates 150+ chars. The gap between 20 and 150 chars contains many formulaic non-productive responses that currently reset the stuck counter.

2. **No similarity detection across iterations:** The existing repetition detector uses exact md5 hashing -- only byte-identical responses (case-insensitive) trigger it. A loop producing slight variations ("I'll check on that." / "Let me check on that." / "Checking on that now.") evades detection indefinitely.

3. **TTL discrepancy:** The user request specifies reducing TTL from 4 hours to 2 hours, but the current code already has `TTL_HOURS=1`. This plan keeps the TTL at the current 1-hour value unless the intent was to increase it to 2 hours. **Needs clarification before implementation.**

## Proposed Solution

### Change 1: Raise stuck detection char threshold from 20 to 150

**File:** `plugins/soleur/hooks/stop-hook.sh` (line 175)

Current:

```bash
if [[ "$IS_IDLE" == "true" ]] || [[ $RESPONSE_LENGTH -lt 20 ]]; then
```

Proposed:

```bash
if [[ "$IS_IDLE" == "true" ]] || [[ $RESPONSE_LENGTH -lt 150 ]]; then
```

Also update the comment tiers (lines 170-174):

```bash
# Three tiers:
#   < 150 chars: definitely minimal (raised from 20)
#   150-199 chars + idle pattern: semantically idle
#   >= 200 chars: always substantive (long enough to contain real work)
```

**Impact on idle pattern detection:** The idle pattern check (lines 149-155) already gates at `< 200` chars. With the new 150-char length threshold, the idle pattern check only adds value for responses between 150-199 chars that match idle phrases. This is correct -- responses in that range that are NOT idle phrases should still be treated as substantive.

### Research Insights: Threshold Choice

**Why 150 and not 100 or 200?**

- Empirical analysis of the test corpus shows "substantive" test strings (intended to simulate real work) range from 45-128 stripped chars. The longest non-substantive responses in production are formulaic acknowledgments like "I'll check on that and get back to you shortly" (~40 chars stripped).
- 100 would still allow many formulaic responses through ("I've reviewed the codebase and everything looks good" = 45 chars).
- 200 would be too aggressive -- a single sentence of genuine work output can be 150-199 chars.
- 150 is the sweet spot: nearly all formulaic non-work responses fall below it, and genuine work output (describing changes, listing files modified, explaining decisions) consistently exceeds it.

### Change 2: Add response similarity detection (Jaccard word overlap)

**File:** `plugins/soleur/hooks/stop-hook.sh`

Add a similarity check between the current response and the previous response. When two consecutive responses are highly similar (but not identical), increment a similarity counter. Three consecutive similar responses trigger termination.

**Approach: Word-set Jaccard similarity via `comm`**

After the existing repetition detection block (line 194), add:

```bash
# --- Similarity Detection ---
# Catch loops producing minor variations of the same response.
# Tokenize into unique words, compute Jaccard similarity via comm.
SIMILARITY_COUNT=$(echo "$FRONTMATTER" | grep '^similarity_count:' | sed 's/similarity_count: *//' || true)
LAST_RESPONSE_WORDS=$(echo "$FRONTMATTER" | grep '^last_response_words:' | sed 's/last_response_words: *//' || true)

if [[ ! "$SIMILARITY_COUNT" =~ ^[0-9]+$ ]]; then
  SIMILARITY_COUNT=0
fi

# Extract normalized word set from current response (alphanumeric only, lowercase, sorted, unique)
CURRENT_WORDS=$(echo "$LAST_OUTPUT" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//')

if [[ -n "$LAST_RESPONSE_WORDS" ]] && [[ -n "$CURRENT_WORDS" ]]; then
  # Count intersection and union using comm on sorted word lists
  PREV_SORTED=$(echo "$LAST_RESPONSE_WORDS" | tr ' ' '\n' | sort -u)
  CURR_SORTED=$(echo "$CURRENT_WORDS" | tr ' ' '\n' | sort -u)
  INTERSECTION=$(comm -12 <(echo "$PREV_SORTED") <(echo "$CURR_SORTED") | wc -l)
  # Union via comm: each word appears in exactly one column, so total line count = |A union B|
  UNION=$(comm <(echo "$PREV_SORTED") <(echo "$CURR_SORTED") | sort -u | wc -l)

  if [[ $UNION -gt 0 ]]; then
    # Jaccard similarity: intersection / union, scaled to 0-100
    SIMILARITY=$((INTERSECTION * 100 / UNION))
  else
    SIMILARITY=0
  fi

  if [[ $SIMILARITY -ge 80 ]]; then
    SIMILARITY_COUNT=$((SIMILARITY_COUNT + 1))
  else
    SIMILARITY_COUNT=0
  fi
else
  SIMILARITY_COUNT=0
fi
LAST_RESPONSE_WORDS="$CURRENT_WORDS"

# Check similarity threshold (3 consecutive similar responses)
SIMILARITY_THRESHOLD=3
if [[ $SIMILARITY_COUNT -ge $SIMILARITY_THRESHOLD ]]; then
  echo "Ralph loop: terminated after $((SIMILARITY_COUNT + 1)) consecutive similar responses (similarity detection)" >&2
  rm -f "$RALPH_STATE_FILE"
  exit 0
fi
```

**New frontmatter fields** in state file:

- `similarity_count: 0` -- consecutive similar (>=80% Jaccard) responses
- `last_response_words:` -- space-delimited sorted unique words from previous response

**State update awk:** Add `similarity_count` and `last_response_words` to the awk update block (line 216-223).

### Research Insights: Similarity Detection

**`comm` union correctness (verified empirically):**
The plan's approach of `comm <(A) <(B) | sort -u | wc -l` for computing Jaccard union is correct. `comm` outputs each word in exactly one of three tab-indented columns (only-in-A, only-in-B, in-both). Since no word can appear in multiple columns, the total line count equals `|A union B|`. Verified with test cases: `{alpha,bravo,charlie,delta,echo}` vs `{alpha,bravo,delta,echo,foxtrot}` yields union=6, intersection=4, Jaccard=66%.

**Alternative (cleaner) union formula:** `UNION = A_COUNT + B_COUNT - INTERSECTION`. This avoids the `sort -u` pipe and is more idiomatic. However, the `comm` approach is already correct and adding `wc -l` calls introduces the same shell overhead. Either approach works; the plan's version is fine.

**`awk -v` escape sequence safety:** `awk -v var="$value"` interprets C-style escape sequences in `$value` (e.g., `\n` becomes newline). Since the word tokenizer (`tr -cs '[:alnum:]' '\n'`) strips all non-alphanumeric characters, the word list can never contain backslashes. Verified by testing with `abc\ndef ghi` -- the tokenizer strips it to `abc def ghi`.

**Frontmatter storage size:** Empirical testing shows `last_response_words` ranges from ~50 bytes (short response, ~10 unique words) to ~1700 bytes (very long response, ~200 unique words). Grep/awk round-trip parsing works correctly at all tested sizes.

**Edge cases to handle:**

- Empty `LAST_OUTPUT` (tool-use-only responses): `CURRENT_WORDS` will be empty, similarity_count resets to 0. Correct behavior -- we should not penalize tool-use responses.
- Very short responses (< 5 unique words): Jaccard on tiny sets is unreliable (removing/adding 1 word swings the score dramatically). Mitigated because responses under 150 chars are already caught by the length threshold.
- First iteration (empty `last_response_words`): Falls into the `else` branch, similarity_count stays 0. Correct.

### Change 3: Hard max iterations ceiling (50) -- already implemented

The hard cap is already at line 110-115 of `stop-hook.sh`:

```bash
HARD_CAP=50
if [[ $ITERATION -ge $HARD_CAP ]]; then
  echo "Ralph loop: Hard safety cap ($HARD_CAP iterations) reached. Auto-removing." >&2
  rm -f "$RALPH_STATE_FILE"
  exit 0
fi
```

Test 18 and Test 19 already verify this. **No changes needed.**

### Change 4: TTL hours -- needs clarification

Current: `TTL_HOURS=1` (line 26). User request says "reduce from 4 to 2." The value is already 1. **No change proposed** unless user confirms they want to increase to 2.

### Change 5: Update setup script and help text

**File:** `plugins/soleur/scripts/setup-ralph-loop.sh`

1. Add `similarity_count: 0` and `last_response_words:` to the state file template (line 144-158)
2. Update help text to mention similarity detection (lines 52-58)
3. Update stuck detection description: "Short responses (< 150 chars)" instead of "< 20 chars"

### Change 6: Update tests [CRITICAL -- scope much larger than initially assessed]

**File:** `plugins/soleur/test/ralph-loop.test.sh`

#### Blast radius analysis

The 150-char threshold change affects **19 of 41 existing tests**. Every "substantive" response string in the test suite is under 150 stripped chars. Detailed breakdown:

**12 tests that MUST be updated** (response string must be >=150 stripped chars):

| Test | Current stripped chars | Why it breaks |
|------|----------------------|---------------|
| 3 | 66 | Asserts `stuck_count=0` (requires substantive response) |
| 5 | 20 | Boundary test -- must change to 150 chars |
| 7 | 56 | Asserts loop continues without crash -- but `stuck_count` would be 1 not 0 |
| 12 | 56 | Asserts `stuck_count=0` after corrupted field default |
| 13 | 66 | Asserts `stuck_count=0` and iteration updated |
| 14 | 66 | Asserts iteration updated (loop continues) |
| 15 | 66 | Asserts `stuck_count=0` in frontmatter |
| 17 | 66 | Asserts iteration updated from subdirectory |
| 26 | 128 | Asserts `stuck_count=0` for non-idle substantive -- **CRITICAL**, this is the core stuck-reset test |
| 30 | 59 | Asserts `repeat_count=0` -- technically passes but semantically incomplete |
| 35 | 66 | Asserts loop continues and prompt text preserved |

**6 tests must also change boundary value:**

| Test | Change |
|------|--------|
| 5 | Change from exactly 20 chars to exactly 150 chars |
| 6 | Change from 19 chars to 149 chars |

**7 tests that still pass but test a weaker assertion:**

| Test | Concern |
|------|---------|
| 9 | Promise matches before length check -- still passes, but fragile |
| 19 | Under hard cap -- stuck_count=1 but threshold=3, loop continues |
| 22 | Idle pattern on 27-char string -- caught by BOTH length AND idle pattern |
| 24 | Same as 22 |
| 25 | Idle termination still triggers |
| 31 | No-crash test -- stuck_count=1 but loop continues |
| 38 | Fresh foreign PID preserved -- loop continues despite stuck_count=1 |

#### Recommended approach: define a shared substantive response constant

To avoid updating 12+ individual test strings, define a shared `SUBSTANTIVE_RESPONSE` variable at the top of the test file:

```bash
# Response string guaranteed to exceed the 150-char stripped threshold.
# Used by any test that needs a "substantive" response to reset the stuck counter.
SUBSTANTIVE_RESPONSE="I have completed the refactoring of the authentication module including updating the middleware layer to support JWT token validation and refresh logic and also updated all twelve integration test files to cover the new authentication flow paths"
# Stripped length: ~220 chars (well above 150 threshold)
```

Then replace all individual "substantive" strings with `"$SUBSTANTIVE_RESPONSE"`.

#### New idle pattern isolation test

Add one test with a 150-199 char response containing an idle phrase, to verify idle detection works independently of the length check:

```bash
# Test N: Idle pattern detected in 150-199 char response (above length gate, below idle gate)
IDLE_LONG_RESPONSE="All the slash commands are already done and complete. I have verified every single one of them and confirmed that nothing is pending or remaining to be executed in this entire session right now."
# Stripped: ~170 chars, contains "all done" and "nothing remaining"
```

#### New tests to add

- **Similarity detection triggers on 3 consecutive similar responses:** Build responses sharing >80% words
- **Dissimilar response resets similarity counter**
- **Pre-existing state file without similarity fields uses defaults (backward compat)**
- **setup-ralph-loop.sh includes similarity_count and last_response_words in state file**
- **Idle pattern detected in 150-199 char response (isolation test)**

#### `create_state_file` helper update

Add two new parameters to `create_state_file()`:

```bash
create_state_file() {
  local dir="$1"
  local iteration="${2:-1}"
  local max="${3:-0}"
  local promise="${4:-null}"
  local stuck_count="${5:-0}"
  local stuck_threshold="${6:-3}"
  local last_response_hash="${7:-}"
  local repeat_count="${8:-0}"
  local similarity_count="${9:-0}"       # NEW
  local last_response_words="${10:-}"    # NEW
  ...
  cat > "$dir/.claude/ralph-loop.${TEST_PID}.local.md" <<EOF
---
...
similarity_count: $similarity_count
last_response_words: $last_response_words
...
---
```

## Technical Considerations

### Bash process substitution and `set -euo pipefail`

The `comm` command with `<(...)` process substitution works under `set -euo pipefail` in bash. However, `comm` expects sorted input -- the plan sorts word lists before comparison. Edge case: if either word list is empty, `comm` still works correctly (empty file = no lines).

### Research Insights: set -euo pipefail interactions

Per learning `2026-03-18-stop-hook-toctou-race-fix.md`, every `grep` in a command substitution under `set -euo pipefail` needs `|| true` to handle the "no match" exit code 1. The similarity detection code correctly includes `|| true` on both `grep` calls for `similarity_count` and `last_response_words` parsing.

The `comm` command itself exits 0 on success, even with empty input. Process substitution `<(...)` inherits `set -e` but `comm` does not fail on sorted empty input. No additional guards needed.

Per learning `2026-03-18-stop-hook-jq-invalid-json-guard.md`, the `jq` call already has `2>/dev/null || true`. No new `jq` calls are added.

### Word tokenization limitations

The approach using `tr -cs '[:alnum:]' '\n'` strips punctuation and treats numbers as words. This is intentional -- code-heavy responses will have variable names and numbers as tokens, which is appropriate for similarity comparison. Very short responses (< 5 unique words) may produce unreliable Jaccard scores; the 150-char length threshold mitigates this since responses under 150 chars are already caught by the length check.

### State file size growth

Adding `last_response_words` to frontmatter increases the state file by ~50-1700 bytes per iteration depending on response vocabulary (empirically verified). This is acceptable -- the state file is ephemeral and cleaned up on loop termination or TTL expiry. The word list never grows unbounded because it is replaced each iteration (not accumulated).

### Backward compatibility

Pre-existing state files without `similarity_count` and `last_response_words` are handled by the default-value pattern already established for `stuck_count`, `stuck_threshold`, `last_response_hash`, and `repeat_count`. The `awk` state update for legacy files (without the new field lines) is a no-op for the new fields -- they will not be written, and the next iteration will re-default them. This is the same acceptable degradation documented for `stuck_count` in the existing code comment at line 214.

### Performance

The `comm`/`sort` pipeline adds ~5ms per iteration on a modern machine. The ralph loop hook already does md5 hashing, jq parsing, and awk processing -- this is within budget.

## Acceptance Criteria

- [ ] Responses under 150 stripped chars (non-idle-pattern) increment stuck counter (`plugins/soleur/hooks/stop-hook.sh`)
- [ ] Responses at exactly 150 stripped chars reset stuck counter (`plugins/soleur/hooks/stop-hook.sh`)
- [ ] Three consecutive responses with >=80% word overlap (but not identical) trigger termination (`plugins/soleur/hooks/stop-hook.sh`)
- [ ] Dissimilar response resets similarity counter to 0 (`plugins/soleur/hooks/stop-hook.sh`)
- [ ] State file includes `similarity_count` and `last_response_words` fields (`plugins/soleur/scripts/setup-ralph-loop.sh`)
- [ ] Pre-existing state files without new fields work without errors (backward compat) (`plugins/soleur/hooks/stop-hook.sh`)
- [ ] Help text updated to reflect 150-char threshold and similarity detection (`plugins/soleur/scripts/setup-ralph-loop.sh`)
- [ ] All 41 existing tests pass with updated thresholds (`plugins/soleur/test/ralph-loop.test.sh`)
- [ ] New tests cover similarity detection scenarios (`plugins/soleur/test/ralph-loop.test.sh`)
- [ ] New test covers idle pattern detection in 150-199 char range (`plugins/soleur/test/ralph-loop.test.sh`)
- [ ] Hard cap at 50 remains unchanged and tested (`plugins/soleur/hooks/stop-hook.sh`)
- [ ] Shared `SUBSTANTIVE_RESPONSE` constant used across tests to prevent future threshold breakage

## Test Scenarios

- Given a response of 149 stripped chars (no idle pattern), when the hook runs, then stuck_count increments
- Given a response of exactly 150 stripped chars, when the hook runs, then stuck_count resets to 0
- Given 3 consecutive responses sharing >=80% words, when the hook runs on the 3rd, then the loop terminates with "similarity detection" stderr message
- Given 2 similar responses followed by a dissimilar one, when the hook runs, then similarity_count resets to 0
- Given a pre-existing state file without similarity_count/last_response_words, when the hook runs, then defaults to 0/empty without crashing
- Given setup-ralph-loop.sh runs with default args, when the state file is created, then it contains similarity_count: 0 and last_response_words: (empty)
- Given a 170-char response matching an idle pattern (e.g., "All commands are already done..."), when the hook runs, then stuck_count increments (idle pattern detection works independently of length threshold)

## MVP

### plugins/soleur/hooks/stop-hook.sh

Changes at 4 locations:

1. Line 175: `$RESPONSE_LENGTH -lt 20` to `$RESPONSE_LENGTH -lt 150`
2. Lines 170-174: Update tier comments
3. After line 194: Insert similarity detection block (~30 lines) including frontmatter parsing, word tokenization, Jaccard computation, and threshold check
4. Lines 216-223: Add `similarity_count` and `last_response_words` to awk state update

### plugins/soleur/scripts/setup-ralph-loop.sh

Changes at 2 locations:

1. Lines 144-158: Add `similarity_count: 0` and `last_response_words:` to state file template
2. Lines 52-58: Update help text for 150-char threshold and similarity detection

### plugins/soleur/test/ralph-loop.test.sh

Changes (significant scope):

1. Add `SUBSTANTIVE_RESPONSE` constant near top of file (~220 stripped chars)
2. Replace response strings in Tests 3, 7, 12, 13, 14, 15, 17, 26, 30, 35 with `"$SUBSTANTIVE_RESPONSE"`
3. Update Test 5 boundary from 20 chars to 150 chars
4. Update Test 6 boundary from 19 chars to 149 chars
5. Update `create_state_file` helper with `similarity_count` and `last_response_words` parameters
6. Add 5 new tests: similarity trigger, similarity reset, backward compat, setup script fields, idle pattern isolation

## References

- `plugins/soleur/hooks/stop-hook.sh` -- main hook implementation (250 lines)
- `plugins/soleur/scripts/setup-ralph-loop.sh` -- loop setup and state file creation (211 lines)
- `plugins/soleur/test/ralph-loop.test.sh` -- existing test suite (41 tests, 712 lines)
- `knowledge-base/project/learnings/2026-03-18-stop-hook-toctou-race-fix.md` -- TOCTOU defense patterns (apply to new code paths)
- `knowledge-base/project/learnings/2026-03-18-stop-hook-jq-invalid-json-guard.md` -- jq guard patterns (no new jq calls, but validates existing guards)
- PR #729 -- existing draft PR for this branch
