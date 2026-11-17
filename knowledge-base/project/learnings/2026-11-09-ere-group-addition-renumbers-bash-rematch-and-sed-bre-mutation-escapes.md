# Learning: widening a `=~` grammar pin with a new group silently renumbers `BASH_REMATCH` (POSIX ERE has no `(?:...)`), and a `sed`-BRE `mutate()` needs the driver's literal backslashes escaped

## Problem

Fixing #12509 (the `oracle-review-required` check's `PR_AUTHOR` regex
`^[A-Za-z0-9][A-Za-z0-9-]*$` rejected GitHub-App logins ending in the literal
suffix `[bot]`, failing every bot PR `verdict=fail reason=input` on a required
context — live victim PR #12489) surfaced two mechanics gotchas in
`scripts/ci-oracle-review.test.sh` that each made the whole suite go red while
the driver fix itself was correct:

1. The suite's `want()` pin reads `verdict`/`reason` out of `BASH_REMATCH[1]`/`[2]`.
   Widening the `author=` arm to `[A-Za-z0-9-]+(\[bot\])?` inserted a THIRD
   capturing group ahead of both. POSIX ERE (what bash `=~` compiles) has no
   non-capturing groups, so `(?:\[bot\])?` is not an option — the indices had
   to move to `[2]`/`[3]`. Until they did, every row reported
   `reason=pass`/`reason=fail` (the verdict token read as the reason), which
   looks like a driver regression, not a pin bug.
2. The suite's `mutate()` helper mutates the driver with `sed -i "s|$old|$new|"`,
   i.e. sed BRE. The driver's literal text is `(\[bot\])?` — with backslashes —
   so a `mutate` old-pattern of `(\[bot\])?` matches `([bot])?`, never lands,
   and trips the `[FATAL] mutation did not land` guard. The correct old-pattern
   is `(\\\[bot\\\])?` (`\\`→literal `\`, `\[`→literal `[`).

A second subtler one, caught by the fix-round seat: a wildcard mutant
`(.bot.)?` (brackets un-escaped) admits `alice(bot)` — but `alicexbotx` is a
VALID login in both worlds, so it can never be the rejection probe. The
load-bearing negative fixture is the one carrying a character outside
`[A-Za-z0-9-]` that only the wildcard accepts.

## Solution

- Driver: `^[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?$` — admit the literal suffix,
  emit `author=<login>[bot]` raw (never strip: `deruelle[bot]` must not
  compare equal to `deruelle` at the owner arm), and widen BOTH grammar pins
  (the driver's own comment and the suite's `want()` regex) in the same diff —
  an un-widened pin false-fails every future `[bot]` marker.
- Rows added: `row_bot_author` (bot + oracle diff → `review-required`, never
  `input`), `row_bot_not_oracle`, `row_bot_owner_spoof` (`deruelle[bot]` must
  not take the author arm), `row_bot_malformed_input` (`alice[bot]x`,
  `alice[bot][bot]`, `alice[BOT]`, `alice[bo]`, `[bot]`, `alice(bot)` all
  `reason=input`), plus two battery mutants (`bot-suffix-dropped`,
  `bot-bracket-unescaped`).
- `BASH_REMATCH` indices renumbered with a comment naming the new numbering.
- Sibling sweep (required by the brief) found exactly one instance of the
  shape; the merge_group arm validates no login, `ci.yml:644` reads only
  `reason=`, and the repo's one other login regex
  (`watch-lint-ratchet-reeval-10515.sh:179`) already carries `(\[bot\])?` —
  confirming the suffix is the canonical widening shape.

## Key Insight

- Any input-validation regex that judges GitHub logins must treat `<slug>[bot]`
  as first-class: sweep every same-shape regex AND every grammar pin that
  validates the emitted value, or the fix lands in one place and the pin
  keeps red.
- Adding a capture group to a `[[ =~ ]]` pin is never local: count every
  `BASH_REMATCH` read downstream of it. POSIX ERE gives no `(?:...)` escape
  hatch — renumber or restructure.
- A `mutate`-by-sed battery mutates FILE TEXT, not regex semantics: the
  old-pattern must match the file's literal bytes (`\\` for a literal
  backslash in the target), not the regex's logical shape.
- For a rejection-side fixture, pick the value that distinguishes the mutant
  from the truth: `alicexbotx` (valid in both) proves nothing; `alice(bot)`
  (rejected by the literal, admitted by the wildcard) is the probe.

## Tags
category: workflow-issues
module: scripts/ci-oracle-review
issue: #12509
