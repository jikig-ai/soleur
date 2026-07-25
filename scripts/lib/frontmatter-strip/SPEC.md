# frontmatter-strip — canonical contract

Single source of truth for stripping a **leading YAML frontmatter block** from a
Markdown sidecar before it is measured (byte budget) or injected (session
context). Issue #5999, ADR-094.

Three byte-identical implementations consume this contract:

- `strip.sh` — sourced by `.claude/hooks/session-rules-loader.sh` (defines
  `strip_frontmatter`, perl-backed).
- `strip.py` — imported by `scripts/lint-agents-rule-budget.py`
  (`strip_frontmatter(text)`).
- `strip.ts` — imported by
  `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`, and
  used (via `strip.sh`) by `scripts/compound-promote.sh`, so the always-loaded
  byte budget is measured on the frontmatter-stripped basis — the same basis the
  commit gate uses (#6794, closing the raw-vs-stripped skew #6461 accepted
  knowingly).

Parity across all three is enforced mechanically by
`scripts/lib/frontmatter-strip.test.sh`, which feeds every fixture in
`fixtures/` to each and asserts byte-identical output. This replaces "keep the
regexes identical by hand." (The `strip.ts` arm skip-gates when `bun` is absent,
so the suite is registered in `scripts/test-all.sh`'s `want_bun` block where bun
is guaranteed; the sh↔py arms also run in the scripts shard via glob.)

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
