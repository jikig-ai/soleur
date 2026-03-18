# Tasks: fix stop-hook.sh TOCTOU race (#709)

## Phase 1: Setup

- [ ] 1.1 Read `plugins/soleur/hooks/stop-hook.sh` to confirm current line numbers match plan

## Phase 2: Core Implementation -- Strategy A (suppress stderr)

- [ ] 2.1 Add `2>/dev/null` to the TTL loop awk call (line 30)
- [ ] 2.2 Add `2>/dev/null` to the main frontmatter awk call (line 51)
- [ ] 2.3 Add `2>/dev/null` to the prompt extraction awk call (line 190)
- [ ] 2.4 Add `2>/dev/null` to the state update awk call (line 210)

## Phase 3: Core Implementation -- Strategy B (re-check existence)

- [ ] 3.1 Add `[[ -f "$RALPH_STATE_FILE" ]] || exit 0` between lines 48-51 (after stdin read, before frontmatter parse)
- [ ] 3.2 Add `[[ -f "$RALPH_STATE_FILE" ]] || exit 0` before the prompt extraction (before line 190)

## Phase 4: Core Implementation -- Strategy C (empty FRONTMATTER guard)

- [ ] 4.1 Add `if [[ -z "$FRONTMATTER" ]]; then exit 0; fi` after the frontmatter extraction (after line 51)

## Phase 5: Core Implementation -- Strategy D (guard rm calls)

- [ ] 5.1 Change `rm "$RALPH_STATE_FILE"` to `rm -f "$RALPH_STATE_FILE"` on lines 80, 86, 93, 103, 121, 174, 182, 194 (8 occurrences)

## Phase 6: Core Implementation -- Strategy E (guard mv and temp file)

- [ ] 6.1 Replace bare `mv "$TEMP_FILE" "$RALPH_STATE_FILE"` with `-s` guarded version that cleans up empty temp files

## Phase 7: Testing

- [ ] 7.1 Run `bash -n plugins/soleur/hooks/stop-hook.sh` to verify syntax
- [ ] 7.2 Trace `set -euo pipefail` compatibility -- verify no unguarded exit-code-nonzero paths remain
- [ ] 7.3 Run compound and commit
