# My fixture shared the bug, so the test could not see it — and then it blocked the fix

**Date:** 2026-08-11 · **PR:** #7435 · **Issues:** #7341, #7436, #7437, #7440, #7447, #7448

## Problem

Two verification obligations from the 2026-08-10 zot registry recut had no mechanism behind them:
#7431's invoice reconciliation (an external event weeks away) and the post-recut fill rate (the
measurement that decides #7341). Both were session-local and would have died at the context
boundary.

Building the two sweeper probes produced **fourteen defects in the probes themselves**. Every one
was green. Seven I found by running the code; the other seven were found by a six-agent review
panel *after* my own inline review had passed the diff and CI was fully green.

## Key insight

The previous session's lesson was *a check certified something other than what it named*. This
session produced two sharper variants, and the second is the one I had no defence against.

> **1. A fixture that shares the code's wrong assumption cannot see the bug — the errors cancel.**

Better Stack emits `dt` naive in UTC. `.timestamp()` on a naive datetime assumes **local**, so on
this UTC+2 host every sample read two hours old and the staleness gate called a live heartbeat 124
minutes stale. The harness passed throughout, because the stub built its fixtures with
`datetime.now()` — the same assumption. Only a live run revealed it.

The rule "one fixture must be transcribed from a measured response" was **satisfied and did not
help**. I transcribed the marker's field shape from a real line. A field shape is visible in a
sample; a timezone convention is not.

> **2. A wrong fixture does not merely fail to catch the bug. It can make the fix look like a
> regression.**

The stub emitted `raw` as a bare string. A genuine Better Stack row stores it as a JSON-encoded
object, `{"message":"SOLEUR_ZOT_DISK …"}` — which is exactly what the envelope anchor keys on. So
the fixture could not express a contaminating row at all, and a reviewer who hardened the parser to
the repo's own shared invariants measured **3/11**. Eight red. The natural response to that signal
is to revert the hardening. A fixture in this state is worse than no fixture: it actively defends
the defect.

The generalisation for both: **a fixture can only falsify assumptions its author did not share.**
For time bases, encodings, units, ordering, locale and envelope shape, the harness is structurally
blind, and the only instruments that resolve it are a live run and a reviewer who did not write it.

## What my review missed, and why

I reviewed inline, found seven defects, fixed them, and judged the diff ready. The panel then found
seven more. The two criticals share one omission: **I never asked who can write to the inputs.**

| | Defect | Consequence |
|---|---|---|
| C1 | Invoice probe read `.comments[].body` with no author filter | `jikig-ai/soleur` is PUBLIC with issues open. **Any GitHub user could close a financial-ledger tracker with one HTTP POST.** Self-sealing: the sweeper's own `### Sweeper run: PASS` comment then satisfied the closed-set reopen guard, so the forgery disabled the mechanism built to catch it. |
| C2 | No envelope anchor on a multiplexed log stream | One GitHub comment quoting a marker line — routine triage during a disk incident — turned a measured `FAIL pcent=78, breaches in 0.4d` into `PASS pcent=6`. The pasted `pcent` became the current reading; the pasted row, being newest, seized which boot got scoped. |

Both inputs *look* internal. Issue comments feel like operator input; a log query feels like machine
telemetry. Neither is: one is world-writable by construction, the other is a shared stream every
host multiplexes into. I checked what the data *meant* and never what the data was *made of*.

The remaining five, each demonstrated rather than argued:

- **In-boot reclaim.** `boot_id` is the KERNEL boot id, but gc reclaiming, the `.uploads/` cleanup
  succeeding, a container restart and an operator delete all free the volume **without rebooting**.
  A store cleaned at 95% then refilling at +20pp/day — precisely the zot#4235 signature the probe is
  named for — reported `PASS slope=-31.15pp/day`. My fix for the original defect did not reach the
  case that actually matters.
- **`boot_id=unknown`** is cloud-init's `/proc` fallback. Treated as an identity it merges every
  boot and reproduces the original wipe-as-trend defect verbatim. Both sibling consumers filter it.
- **One bad reading flipped the verdict.** `df` resolves `/var/lib/zot` to the ROOT filesystem when
  the volume is detached or mid-remount. A single such sample turned `FAIL pcent=95` into
  `PASS pcent=8`.
- **FAIL-absorbing was unrecoverable and self-poisoning.** The probe echoes the matched verdict, the
  sweeper posts its stdout back as a comment, and the next run reads that echo as a verdict — so one
  FAIL latched the issue permanently unclosable. The stated justification ("verdicts are
  append-only") was also false: GitHub comments are editable.
- **The `\b` the header claimed was never in the code.** `RESULT: PASSing on this for now, invoice
  not here yet` exited 0 — closing the tracker on a comment that explicitly declines to verify.

## The deeper pattern: fixes introduce defects at an undiminished rate

Of the fourteen, at least six were introduced by fixes for earlier ones. That was true in the
previous session too. What changed the outcome was not care — it was the number of independent
readers. The panel was told to *hunt the vacuity the harness missed rather than re-run its
mutations*, and that instruction produced both criticals.

One nuance worth keeping: **the panel disagreed with itself productively.** One agent proposed
FAIL-absorbing as correct; another showed a case where it wedges the tracker permanently red. The
resolution (last-member-verdict-wins) came from neither alone.

## Prevention

- **For any input, name who can write to it before deciding how much to trust it.** "Issue comment"
  and "log stream" both read as internal and neither is. A probe whose exit code mutates state must
  authenticate the identity of any third-party-writable input it reads. No rule in `AGENTS.rules.md`
  said this; #7448 proposes it.
- **When a shared library encodes an invariant, use it or state why you cannot.** Here the library
  genuinely could not be sourced — `zot_trusted_region` is a line-oriented `sed` that cuts to
  end-of-line, which on a JSONEachRow row also removes the closing brace and silently drops every
  sample (n=0 from 144 rows). The right move is to mirror each invariant with a comment naming the
  function it mirrors, and file the divergence — not to quietly hand-roll.
- **For any value with an implicit convention — timezone, encoding, unit, ordering, envelope shape —
  the fixture cannot be the only witness.** Ask of each: *which of my assumptions could this fixture
  not contradict, because I generated it from those assumptions?*
- **When hardening makes an existing harness go red, suspect the fixture before reverting.** 8/11
  red was the fixture defending the bug, not the fix breaking anything.
- **A probe deciding an incident must reject staleness explicitly**, and **a count from a sampler is
  a lower bound** — write it as one.
- **Order verdict arms so the recoverable outcome is reachable.** In an append-only-ish channel,
  prefer "latest authenticated verdict" over "one verdict absorbs forever", which cannot be undone.
- **A harness that is not registered does not exist**, and **stubs must assert their argv** —
  without it, dropping `--grep`, adding `--no-archive` or shrinking `--limit` all stayed green while
  wedging the probe at TRANSIENT forever, which is #6288 verbatim.
- **Inline review is not a substitute for independent readers on anything that mutates state.**
  Mine was thorough, found seven real defects, and still passed two criticals. #7447 exists because
  nothing downstream recorded that only one reviewer had looked.

## Session Errors

1. **Shipped a probe whose first live run reported a wipe as a trend** (`PASS slope=-58.48pp/day`).
   **Prevention:** scope any time series to the identity of the thing measured; a replacement is a
   discontinuity, never a data point.
2. **Wrote a character class that silently prefix-matched** — `([0-9a-f-]+)` against `bootOLD-aaaa`
   captured `b` for both and collapsed two boots. **Prevention:** capture whole tokens with `(\S+)`
   unless the class is the assertion.
3. **Built a fixture that shared the code's timezone assumption.** Covered above.
4. **Let a dead host pass.** **Prevention:** a freshness gate beside every threshold gate.
5. **Shipped a count floor with no span floor** — twelve 5-minute samples span one hour.
   **Prevention:** a slope needs a baseline; assert the span, not the row count.
6. **Read `.comments[].body` unfiltered on a PUBLIC repo**, letting any user close a financial
   tracker. **Prevention:** name the writer set for every input.
7. **Parsed an unanchored multiplexed log stream**, letting a pasted comment overturn a real FAIL.
   **Prevention:** anchor on the emission envelope; both siblings already did.
8. **Scoped to `boot_id` and assumed that covered wipes** — it does not cover an in-boot reclaim,
   which is what every #7341 remediation actually produces. **Prevention:** enumerate the mechanisms
   that produce the discontinuity, not just the one that produced it last time.
9. **Trusted a single trailing sample as current state.** **Prevention:** median the trailing window.
10. **Wrote three comments describing controls the code did not implement** — a `\b` that was not
    there, an "append-only" property GitHub does not provide, and a claim that peers use
    `^RESULT: PASS$` when only one of three does. **Prevention:** before writing "the regex is X",
    grep for X in the same file.
11. **Twice, an apostrophe in a comment terminated the single-quoted python block it sat inside**
    ("runner's", "probe's"). **Prevention:** treat single-quoted `-c` bodies as apostrophe-free and
    say so in the block.
12. **Designed the invoice probe to take the issue number as `$1`** when the sweeper passes none.
    **Prevention:** read the caller's invocation line before designing the callee's interface.
13. **Captured `$?` inside `if ! cmd; then`**, which reads the negated test rather than the command,
    making the rc=3 credential branch unreachable. **Prevention:** capture rc on its own line.
14. **Used `json.dumps` defaults in a fixture** (`", "` / `": "` separators) where production emits
    compact JSON, so the envelope anchor could never match. **Prevention:** byte-compare one fixture
    against a real captured row.
15. **Filed an issue with an inline `--body` containing quotes**, which the directive gate's
    extractor truncates at the first inner quote. **Prevention:** `--body-file` for any issue body
    carrying a directive — the documented pattern.
16. **Four bad measurements while attributing the disk consumption**: two greps that matched
    heartbeat markers instead of log lines; a regex whose `[^,]+` returned 0 of 289 because the
    message contains a comma; and a near-miss filing of `zot_last_err` as a defect when it has a
    working `_src` discriminator. **Prevention:** before reading a count, confirm the grep matched
    the stream you meant and not a marker echoing it.
17. **Claimed FAIL-before-PASS as a rule this session derived** when `inngest-doublefire-reading-6617.sh`
    already had it. **Prevention:** grep the sibling directory before claiming a pattern is new.
18. **Asserted three unverifiable things in this document's first draft** — a defect-table/error-list
    mismatch, "defects 3-6 were introduced by fixes for 1-2" (defect 6 was in the initial commit,
    checked with `git show`), and "the 11-case harness passed throughout" (it had 8 assertions and
    `MIN_CHECKS=9` at that commit). **Prevention:** a learning's whole value is that its accounting
    can be trusted; verify its own claims with the same rigour as the code's.

## Tags

category: test-design
module: followthrough-probes
