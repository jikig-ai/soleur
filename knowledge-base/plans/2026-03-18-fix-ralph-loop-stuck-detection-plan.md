---
title: "fix: harden ralph loop stuck detection thresholds and add similarity detection"
type: fix
date: 2026-03-18
---

# fix: harden ralph loop stuck detection thresholds and add similarity detection

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

### Change 2: Add response similarity detection (trigram/Jaccard)

**File:** `plugins/soleur/hooks/stop-hook.sh`

Add a similarity check between the current response and the previous response. When two consecutive responses are highly similar (but not identical), increment a similarity counter. Three consecutive similar responses trigger termination.

**Approach: Bigram overlap using bash word tokenization**

After the existing repetition detection block (line 194), add:

```bash
# --- Similarity Detection ---
# Catch loops producing minor variations of the same response.
# Tokenize into words, compute bigram set overlap (Jaccard-like).
SIMILARITY_COUNT=$(echo "$FRONTMATTER" | grep '^similarity_count:' | sed 's/similarity_count: *//' || true)
LAST_RESPONSE_WORDS=$(echo "$FRONTMATTER" | grep '^last_response_words:' | sed 's/last_response_words: *//' || true)

if [[ ! "$SIMILARITY_COUNT" =~ ^[0-9]+$ ]]; then
  SIMILARITY_COUNT=0
fi

# Extract normalized word set from current response
CURRENT_WORDS=$(echo "$LAST_OUTPUT" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//')

if [[ -n "$LAST_RESPONSE_WORDS" ]] && [[ -n "$CURRENT_WORDS" ]]; then
  # Count intersection and union using comm on sorted word lists
  PREV_SORTED=$(echo "$LAST_RESPONSE_WORDS" | tr ' ' '\n' | sort -u)
  CURR_SORTED=$(echo "$CURRENT_WORDS" | tr ' ' '\n' | sort -u)
  INTERSECTION=$(comm -12 <(echo "$PREV_SORTED") <(echo "$CURR_SORTED") | wc -l)
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

### Change 6: Update tests

**File:** `plugins/soleur/test/ralph-loop.test.sh`

Tests to update:
- **Test 5** (line 137): "Exactly 20 characters is substantive" -- change to 150 chars boundary
- **Test 6** (line 148): "19 characters is minimal" -- change to 149 chars boundary
- **Test 3** (line 117): Ensure test response exceeds 150 chars (currently ~70 stripped chars -- needs lengthening)

New tests to add:
- **Test N+1:** Similarity detection triggers on 3 consecutive similar-but-not-identical responses
- **Test N+2:** Dissimilar response resets similarity counter
- **Test N+3:** Pre-existing state file without similarity fields uses defaults (backward compat)
- **Test N+4:** setup-ralph-loop.sh includes similarity_count and last_response_words in state file

## Technical Considerations

### Bash process substitution and `set -euo pipefail`

The `comm` command with `<(...)` process substitution works under `set -euo pipefail` in bash. However, `comm` expects sorted input -- the plan sorts word lists before comparison. Edge case: if either word list is empty, `comm` still works correctly (empty file = no lines).

### Word tokenization limitations

The bigram approach using `tr -cs '[:alnum:]' '\n'` strips punctuation and treats numbers as words. This is intentional -- code-heavy responses will have variable names and numbers as tokens, which is appropriate for similarity comparison. Very short responses (< 5 unique words) may produce unreliable Jaccard scores; the 150-char length threshold mitigates this since responses under 150 chars are already caught by the length check.

### State file size growth

Adding `last_response_words` to frontmatter increases the state file by ~200-500 bytes per iteration (sorted unique words). This is acceptable -- the state file is ephemeral and cleaned up on loop termination or TTL expiry.

### Backward compatibility

Pre-existing state files without `similarity_count` and `last_response_words` are handled by the default-value pattern already established for `stuck_count`, `stuck_threshold`, `last_response_hash`, and `repeat_count`.

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
- [ ] All existing tests pass with updated thresholds (`plugins/soleur/test/ralph-loop.test.sh`)
- [ ] New tests cover similarity detection scenarios (`plugins/soleur/test/ralph-loop.test.sh`)
- [ ] Hard cap at 50 remains unchanged and tested (`plugins/soleur/hooks/stop-hook.sh`)

## Test Scenarios

- Given a response of 149 stripped chars (no idle pattern), when the hook runs, then stuck_count increments
- Given a response of exactly 150 stripped chars, when the hook runs, then stuck_count resets to 0
- Given 3 consecutive responses sharing >=80% words, when the hook runs on the 3rd, then the loop terminates with "similarity detection" stderr message
- Given 2 similar responses followed by a dissimilar one, when the hook runs, then similarity_count resets to 0
- Given a pre-existing state file without similarity_count/last_response_words, when the hook runs, then defaults to 0/empty without crashing
- Given setup-ralph-loop.sh runs with default args, when the state file is created, then it contains similarity_count: 0 and last_response_words: (empty)

## MVP

### plugins/soleur/hooks/stop-hook.sh

Changes at 3 locations:
1. Line 175: `$RESPONSE_LENGTH -lt 20` to `$RESPONSE_LENGTH -lt 150`
2. Lines 170-174: Update tier comments
3. After line 194: Insert similarity detection block (~30 lines)
4. Lines 216-223: Add similarity fields to awk state update

### plugins/soleur/scripts/setup-ralph-loop.sh

Changes at 2 locations:
1. Lines 144-158: Add `similarity_count: 0` and `last_response_words:` to state file template
2. Lines 52-58: Update help text for 150-char threshold and similarity detection

### plugins/soleur/test/ralph-loop.test.sh

Changes:
1. Update Test 5 boundary from 20 to 150 chars
2. Update Test 6 boundary from 19 to 149 chars
3. Ensure Test 3 response exceeds 150 stripped chars
4. Add 4 new similarity detection tests

## References

- `plugins/soleur/hooks/stop-hook.sh` -- main hook implementation
- `plugins/soleur/scripts/setup-ralph-loop.sh` -- loop setup and state file creation
- `plugins/soleur/test/ralph-loop.test.sh` -- existing test suite (41 tests)
- `knowledge-base/learnings/2026-03-18-stop-hook-toctou-race-fix.md` -- TOCTOU defense patterns
- `knowledge-base/learnings/2026-03-18-stop-hook-jq-invalid-json-guard.md` -- jq guard patterns
- PR #729 -- existing draft PR for this branch
