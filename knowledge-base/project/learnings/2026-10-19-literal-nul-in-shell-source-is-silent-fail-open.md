# A literal NUL in a shell script is a silent fail-open, three ways at once

## Problem

The jq config decoder in `affected-tests.sh` embedded literal NUL bytes in its
program string to emit `\0` field separators. Three independent failures fell
out of the same byte:

1. **Bash silently strips NULs when parsing script files.** jq received a
   program whose separators were empty strings, produced delimiter-free
   output, and `read -r -d ''` parsed ZERO records — a valid
   `.soleur-test-gate.json` was silently ignored on jq-only hosts, including
   unknown keys the contract required refusing (`bad-config`). The least-used
   decoder arm was the most broken, and nothing in the 1300-line suite
   reached it.
2. **The file registered as binary.** `file` reported "binary data" and plain
   `grep`/`rg` skipped it — searches for `inert`, `GATE_`, and other tokens
   in the very file being debugged returned empty, which read as "the logic
   isn't there" and cost a debugging detour.
3. **A NUL in a future first-read chunk yields "cannot execute binary file".**

## Prevention

- Never embed a literal NUL in a script source — always use an escape the
  consumer interprets (`jq` accepts `"\u0000"`; `printf '\0'` in shell;
  `String.fromCharCode(0)` in JS).
- When `grep` inexplicably returns nothing for a token you can see with
  `head`, check `file <path>` or `LC_ALL=C grep -a` FIRST — binary detection
  is a silent-search failure mode, not a no-match.
- Multi-engine decoders (python3/node/jq fallbacks) need a suite row PER
  ENGINE, not per "a decoder exists" — the fallback's distinct failure shape
  is exactly where fail-open lives.

Tags: bash, fail-open, testing, jq
