# frontmatter-strip — canonical contract

Single source of truth for stripping a **leading YAML frontmatter block** from a
Markdown sidecar before it is measured (byte budget) or injected (session
context). Issue #5999, ADR-094.

Two byte-identical implementations consume this contract:

- `strip.sh` — sourced by `.claude/hooks/session-rules-loader.sh` (defines
  `strip_frontmatter`, perl-backed).
- `strip.py` — imported by `scripts/lint-agents-rule-budget.py`
  (`strip_frontmatter(text)`).

Parity between the two is enforced mechanically by
`scripts/lib/frontmatter-strip.test.sh`, which feeds every fixture in
`fixtures/` to both and `diff`s the outputs. This replaces "keep two regexes
identical by hand."

## Contract

Let the input be a byte string decoded as UTF-8.

1. **Trigger.** The strip fires **iff** the input begins with the exact line
   `---` — i.e. the input starts with the 4 bytes `---\n`. A file whose first
   line is anything else (including a file that merely *contains* `---` on a
   later line, e.g. a Markdown horizontal rule or a fenced ```yaml example) is
   returned **unchanged**.

2. **Well-formed strip.** When triggered, remove everything from the start
   through the **next** line that is exactly `---`, **inclusive of that line's
   trailing newline**. Every byte after the closing delimiter is preserved
   verbatim (including the blank line that conventionally follows frontmatter
   and the file's trailing newline).

3. **Malformed (over-strip) case.** If the opening `---` has **no** matching
   closing `---` line, the entire input is consumed → **empty output**. This is
   intentional: it is the signal both consumers guard against.
   - The **loader** treats an empty/rule-losing strip as an over-strip and
     injects the RAW (unstripped) sidecar instead + a loud stamp note — rules
     are NEVER dropped from session context (under-strip / frontmatter-leak is
     benign; a governance blackout is not).
   - The **lint** treats a strip that removes any `- ...[id: ...]` rule line as
     a hard ERROR (exit 1), never a silently lower B_ALWAYS.

## Boundary invariant

The frontmatter block a caller adds to a sidecar MUST contain no `- ...[id: ...]`
rule line (frontmatter is `key: value` YAML). Both guards rely on this: a
correctly-formed strip removes only frontmatter, so the count of `- ...[id: ...]`
lines is invariant across the strip. A drop in that count ⇒ the strip consumed
body ⇒ malformed frontmatter or a broken strip.
