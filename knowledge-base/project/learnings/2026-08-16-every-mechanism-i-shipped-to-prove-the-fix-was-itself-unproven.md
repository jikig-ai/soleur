---
title: Every mechanism I shipped to prove the fix was itself unproven
date: 2026-08-16
issue: 7555
category: workflow-patterns
tags: [guards, mutation-testing, observability, fixtures, review]
---

# Every mechanism I shipped to prove the fix was itself unproven

The one-line fix was correct on the first try: zot v2.1.20 ships 60 s HTTP deadlines, a large layer
cannot finish inside them, set both to 1800 s. Everything built to *prove* that fix — three guards,
a soak probe, a delivery dispatcher — was broken, and every one of them was green.

## What was actually wrong

| Mechanism | Defect | How green it looked |
|---|---|---|
| The stage pointer (the PR's headline) | Nested behind a multi-line-detail arm; 8 of 9 live call sites pass single-line | emitted **0 times** in production; suite 21/21 |
| `is_cap_exempt` plaintext fallback | journald splits oversized lines into client-controlled fragments, so it classified attacker bytes | 164/164; 17 forged fragments starved a panic to zero |
| Exempt lane | FIFO, so one failing push filled it and dropped crash traces | the fixture tested the *opposite* mode (non-exempt rows) |
| #7556 soak probe | Rows are double-encoded and quote-stripped: `grep -c 'i/o timeout'` = **0** on data with 21 failures | both signals unreachable; fixing one would have *armed* a false auto-close of a P1 |
| The probe's delivery signal | zot's config line is 2273 chars, `ReadTimeout` at offset 1363, cap 800 | severed before shipping; also not cap-exempt |
| The dispatcher | `fetch-depth:1` → `git diff` exits 128 → every push fail-closed | only working route was the manual step it exists to remove |
| …and its trigger | Path-triggered on a 1000-line file, with no `environment:` gate and no `confirm` token anywhere | any future comment typo would replace the production host |
| Preflight P1 | Aborts on local-cache for 24 h — which a replace outage itself causes | the file's own header rejects this exact shape for D10's A4 |
| Preflight seams | "tests only" was a comment; `/bin/true` produced a verdict byte-identical to a clean read | on the sole gate before an irreversible host replace |

## The generalizable lesson

**A guard's fixture is a claim about production, and it is the claim nobody checks.** Each of these
passed because its fixture instantiated a shape production does not produce — a two-line detail, a
plain-text log row, a well-formed `/v2/` path, a config with both keys present. The assertions were
fine. The inputs were fiction.

The litmus that would have caught all of them, asked once per fixture: *does a real caller ever
produce this shape?* Not "is the assertion correct" — that question passes.

Three corollaries, each of which bit here:

1. **A guard whose deletion leaves the suite green pins nothing.** Reverting the PR's thesis is one
   axis; the axes that matter are the ones the author was not thinking about — fixture *shape*,
   fixture *direction*, population *growth* (add a member, don't edit one), and *dispatch* (neuter
   the assertion helpers).
2. **An anti-vacuity floor must not dispatch through the helper it backstops.** Three suites here
   called `fail()` to report a short count, so one no-op edit disarmed the assertions and their
   guard together — 21 assertions collapsed to 12, still green.
3. **A closure argument is a claim to grep, not to reason about.** The comment asserting the F-5
   bypass stayed closed was falsified 260 lines above it, in the same file, by text that had been
   there for months.

## And the instruments were wrong five times

The part worth keeping. While checking the above, five separate measurements returned confident
wrong answers:

- a mutation battery run against a **red baseline** (sandbox missing render deps) reported two
  KILLED verdicts that meant nothing;
- a `fail()`-neuter mutation **did not land** (regex mismatch) and reported SURVIVED;
- a QA verification grepped `pass:` where the suite emits `PASS:`, reporting two covered scenarios
  as missing;
- a gate-status check grepped `LOCK_WAITING` anywhere in the log, so it reported "queued" for a run
  that had acquired the lock ~400 KB earlier;
- an empty Better Stack query was nearly read as "the channel is dark" before a 72 h positive
  control proved the query path worked at all.

Every one presented as a result. The habit that caught them: **run the instrument against a known
positive AND a known negative before reading its verdict**, and treat a red control as voiding the
whole battery rather than as one bad row.

## Session Errors

- **Guard 1's pointer was inert in production.** Recovery: hoisted the pointer out of the
  multi-line-detail arm and rewrote the fixture to the single-line production shape.
  **Prevention:** when a fixture chooses an input shape, name the live call site it models.
- **The `_zclass` fallback reopened the #7444 F-5 bypass.** Recovery: narrowed the fallback to the
  four crash classes, which are the only ones with no JSON route. **Prevention:** grep the file for
  text that falsifies a closure argument before writing it.
- **The dispatcher could never deliver, and would have fired on comment edits.** Recovery: compare
  API + comment-stripped delta gate. **Prevention:** for any `github.event.before` consumer, check
  `fetch-depth` in the same edit.
- **The soak probe could not match real bytes.** Recovery: decode first, using the sibling's decode.
  **Prevention:** build probe fixtures from a captured real response, never from the shape the
  producer "should" emit.
- **Exempt-lane starvation, with a fixture testing the opposite mode.** Recovery: sub-quota +
  the missing fixture. **Prevention:** for any shared budget, fixture the saturating class itself.
- **Preflight P1 blocked its own recovery; seams were unguarded.** Recovery: manual arm skips P1;
  ported the sibling's `GITHUB_ACTIONS` seam refusal. **Prevention:** when a file's header rejects a
  pattern, check the file does not implement it.
- **`verify` was told an unmeasured cause inside the ADR-166 fix.** Recovery: own family, own
  wording. **Prevention:** a family split is a claim that the members fail the same way.
- **Mutation battery run against a red baseline.** Recovery: re-ran in the real tree with a pristine
  backup. **Prevention:** require a GREEN unmutated control before reading any row.
- **A mutation that did not land reported SURVIVED.** Recovery: asserted the anchor count before
  replacing. **Prevention:** `assert s.count(old) == 1` in every mutation script.
- **QA grep case-mismatched the suite's own output prefix.** Recovery: inspected the real prefixes.
  **Prevention:** derive the assertion prefix from the suite, never assume a house style.
- **Gate-status check reported "queued" for an executing run.** Recovery: read log growth instead.
  **Prevention:** anchor on a token that does not outlive the state it describes.
- **Launched the gate detached with no watcher armed.** Recovery: armed a Monitor covering rc,
  vanish, and stall. **Prevention:** a detached run without a watcher is an unmonitored run.
- **`PUSH_EXIT=0` read `tail`'s exit under a pipe.** Recovery: captured rc on its own line.
  **Prevention:** never read `$?` after a pipeline whose last stage is `tail`/`head`/`grep`.
- **A nested heredoc inside a Python triple-quote, and inline mutation quoting, mangled two
  patches.** Recovery: wrote mutations to files. **Prevention:** write mutation scripts to files
  rather than nesting them in a heredoc inside another quoting context. One-off.

## Related

- `2026-08-13-a-lower-bound-cannot-tell-a-measurement-from-a-constant.md`
- `2026-08-11-the-pr-that-fixed-narrow-guards-shipped-three-narrow-guards.md`
- `2026-07-26-an-existence-assertion-that-ran-before-the-file-existed-bricked-every-boot.md`
