---
title: "Rewriting a line-linter's quote model: carry a context stack, not flag pairs"
date: 2026-09-25
category: engineering
module: scripts/lint-shell-capture-exit
tags: [lint, shell, quote-parsing, state-machine, baseline-triage, test-invariants]
issue: 8884
---

# Learning: a shell quote/depth model must be a carried context stack — flag pairs desync on real code

## Problem

`lint-shell-capture-exit.py` grew a "carried `in_s`/`in_d`" quote model to fix
#8884's multi-line-string blind spots. The review panel and live-tree triage
then surfaced a chain of desync bugs the flag model could never have expressed:

- `"$(awk … 'single' …)"` — a `$(` inside `"` re-lexes as fresh code; its
  `'…'`/`"…"` are real toggles, not string content. A two-flag model read them
  as outer-string toggles and swallowed `|| true` tails whole.
- `"$(a "$(b)")"` — substitution-in-dquote-in-substitution-in-dquote needs a
  stack; one `dsubst` int + `sub_s`/`sub_d` flags were not enough.
- `payload="$(jq '{\n…}')"` — the single-quoted jq program spans LINES inside
  the subst inside the dquote: sub-quote state must carry across logical
  lines too, not reset per line.
- `# don't` — an apostrophe in a comment tail opened a phantom single-quote
  and blanked the rest of the file.
- `${#arr[@]}` — `#` after `{` is a length expansion, not a comment; treating
  it as comment hid a closing `))` and leaked paren depth permanently.
- `vis`-mask double-append: one branch consumed two chars but appended three
  mask entries — every positional index (segment alignment, `sq` lookups,
  `close_info` keys) skewed by +1 for the rest of the file.

Each bug silently *suppressed* findings — the worst direction for a lint gate,
because a green run is indistinguishable from a working model.

## Solution

`_quote_scan` is now a stack machine: `qstack` frames `sq`/`dq`/`sub`/`paren`,
pushed/popped per char, carried across lines. A `sub` frame's interior lexes as
code (real quote toggles, `(` pushes `paren`, `)` pops) even under `dq`, which
is exactly bash's rule. Per-position masks `vis` (quoted → blank),
`sq` (single-quoted → literal data), `sub` (`$(` interior → subst-scoped) are
emitted at 1:1 positional alignment so downstream tools index by raw position.

Rules that fell out, each verified by a live-tree symptom:

1. Delimiters are masked too — a `"` left visible in `vis` re-opens a phantom
   quote in `_segments`.
2. `)`/`}` closers on a carried-quote line are processed normally after the
   quote closes — never skip the whole line.
3. `${#` is exempt from comment detection; `#` only comments at a word
   boundary AND never inside quotes.
4. Frame tracking records WHICH construct a closer popped (`close_info`):
   a `}` ending a function DEFINITION is not an executed-command antecedent,
   and the closer segment's index must be the seg containing the closer, not
   `len(pairs)-1` (`f() { a; }; rc=$?` puts `}` mid-seg-list).
5. `set` verdicts are per-segment: `x=1; set +e` disarms, `set +u; }` still
   closes the def, `set -e` inside `(` is subshell-scoped.
6. Statement semantics: a substitution's status is its LAST `;`-statement's;
   every `|`/`||`/`&&` operand of that statement is a stage (`x=$(a; grep)`,
   `x=$({ p|grep|wc; } | tr)` under pipefail).
7. Command-position tracking distinguishes `if { …; }; then` introducers from
   operand groups: `! { …; }` is errexit-exempt (live read), `guard && { …; }`
   is not (dead read).

## Key Insight

The diff was green against the old baseline the whole time the model was
desynced — baseline suppression hid the misses. The reliable signals were:

- **Length invariant**: `len(vis) == len(text)` on every line — run it over
  all ~1,275 tracked scripts; one off-by-one breaks every position index.
- **Baseline-drop triage**: every entry a regenerated baseline LOSES must be
  explained individually (this branch: 9 drops, all verified as spoofed-`set`
  or unarmed findings the old model fabricated) — never assume drops are
  cleanups; one in this diff was a real regression until the rejoin fix.
- **Seat-repro batteries**: every review-panel claim got a standalone repro
  checked against real bash (`!` on a group returns 0 → live read; `&&`-group
  aborts → dead read) before the fix was written.

## Prevention

- When a position-preserving mask feeds other code, add the length invariant
  (`assert len(mask) == len(text)` or a fixture asserting it) BEFORE writing
  features on top — it catches the append-per-char bugs the diff view cannot
  see.
- When a flag model fails twice (`in_s` → `dsubst` → `sub_s`), stop adding
  flags — the formalism wanted was a stack.
- Full-tree baseline diffs need per-entry triage with quoted-state dumps
  (`armed`/`vis` at the dropped line), not bulk acceptance.

## Session Errors

1. **`substituted_commands` last-operand regression**: switching to the LAST
   `;`-statement dropped the `x=$(grep -c || echo)` S2 case — the fix inspects
   every `|`/`||`/`&&` operand of the last statement, not just the last
   operand. **Prevention:** semantics changes get a repro for each arm before
   committing the split rule; the suite caught this one immediately.
2. **`close_info` wrong seg index**: recorded against `len(pairs)-1`, so
   `f() { a; }; rc=$?` flagged S3 on a definition close. **Prevention:** key
   positional bookkeeping on the seg that CONTAINS the token, derived via a
   `_seg_index_of` search — never index by "last".
3. **vis overshoot (+1 append in the `$(`-in-`"` branch)**: desynced every
   downstream index. **Prevention:** the whole-tree `len(vis)==len(text)`
   invariant check; run it after every scanner change, not once.
4. **Delimiter openers unmasked in `vis`**: a `"`/`'` pushed a stack frame but
   stayed visible, so `_segments` phantom-reopened the quote. **Prevention:**
   push the frame BEFORE emitting the mask cell; assert the delimiter's
   `sq`/`vis` value in a unit fixture.
5. **Back-walk skipped `set +u; }` wholesale**: the antecedent resolver
   dropped the closer-bearing line and landed on a command inside the
   definition. **Prevention:** "skip set lines" predicates must test the LAST
   segment (`_SET_SEG_RE`), not the line head (`SET_RE`).
6. **`st=(…)` inside `"$(…)"` flagged**: parity counting can't see parens
   inside `"` — the `sub` position mask was added. **Prevention:** reads
   inside substitutions are a POSITION property (mask bit), not a PAREN-PARITY
   property (counting).
7. **Fixture line-number off-by-ones** (three times) and unescaped
   `${#A[@]}`/backtick quoting in assert strings. **Prevention:** derive
   asserted line numbers from a dry run; keep `$`, backticks, and
   `${#arr[@]}` out of double-quoted assertion messages.
8. **`_quote_scan` rewrites drifted faster than the docstring**: two stale
   descriptions shipped before the final pass. **Prevention:** re-read the
   function's own docstring as part of the diff review, not just the code.

## Tags

lint-shell-capture-exit, set-e, errexit, quote-tracking, bash-parser,
command-substitution, pipeline-modeling, review-driven-rework
