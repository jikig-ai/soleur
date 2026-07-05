#!/usr/bin/env python3
"""frontmatter-strip contract — Python implementation (byte-exact with strip.sh).

Canonical contract lives in SPEC.md; strip.sh is the byte-identical bash twin.
`scripts/lib/frontmatter-strip.test.sh` feeds shared fixtures to BOTH and asserts
parity (issue #5999, ADR-085).

Imported by scripts/lint-agents-rule-budget.py as `strip_frontmatter`; also
runnable as a stdin->stdout filter: `python3 strip.py < file`.

Behavior: iff the text BEGINS with the exact line `---` (starts with `---\\n`),
drop from the start through the next line that is exactly `---` (inclusive);
everything after is verbatim. Opening `---` with NO matching close consumes the
whole text (empty output) — the malformed/over-strip signal. No leading `---\\n`
-> unchanged. `\\n` boundaries are ASCII 0x0A and never occur inside a multibyte
UTF-8 sequence, so line splitting is byte-safe and matches strip.sh exactly.
"""

from __future__ import annotations

import sys


def strip_frontmatter(text: str) -> str:
    if not text.startswith("---\n"):
        return text
    lines = text.split("\n")
    for i in range(1, len(lines)):
        if lines[i] == "---":
            return "\n".join(lines[i + 1:])
    # Opening delimiter with no close — malformed; consume everything.
    return ""


if __name__ == "__main__":
    data = sys.stdin.buffer.read().decode("utf-8")
    sys.stdout.buffer.write(strip_frontmatter(data).encode("utf-8"))
