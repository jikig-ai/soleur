---
title: "Every instrument I verified was verified inside its own blind spot"
date: 2026-09-10
category: security-issues
module: inngest-probe
issues: [8017, 8015, 8013]
pr: 8019
tags: [observability, measurement, mutation-testing, privacy, destroy-gate]
---

# Every instrument I verified was verified inside its own blind spot

## Problem

Three issues shared one host replace: a recut gate whose mount pin was unreachable code (#8017),
a serving probe that passed vacuously (#8015), and a live ULID leaking to a third-party warehouse
(#8013). The implementation was straightforward. **Every serious defect was in the verification.**

## The five that matter

**1. A query flag that excluded the channel under test.** I measured "does the probe reach Better
Stack?" with `--raw-only`, got zero rows over 36h, and concluded the host does not deliver via its
`logger` line. `betterstack-query.sh` implements that flag as `raw NOT LIKE '%SYSLOG_IDENTIFIER%'`
— which excludes **every journald row by construction**, and Vector ships journald rows. Same
query: **57 rows without the flag, 0 with it.**

I *did* run two positive controls, and wrote that I had. Both used `--raw-only`. They proved the
transport worked and were structurally incapable of detecting a filter biased against the one
channel the question was about. **An instrument never shown to produce a positive FOR THE CLASS
UNDER TEST has not returned a negative about it.** The controls have to sit on the far side of the
suspect filter, not beside it.

Downstream: `vector_active=inactive` is a ~70-second BOOT RACE (all five instances at `uptime_s`
64–192 on distinct `boot_id`s), not a host state. The phone-home fallback exists for that window,
so the only rows `--raw-only` CAN return come from it — which made the artifact look like
corroboration rather than contradiction.

**2. An apostrophe closed an `awk '…'` block, and `bash -n` passed.** The comment explaining the
privacy fix said `Inngest's own keyspace`. That apostrophe terminated the awk program, so the
emitter shipped `redis_key_patterns=__UNREADABLE__` on every fire — the field destroyed entirely.
Syntax-checked clean. Only executing the extracted probe body caught it. The trap is documented in
this repo; I hit it while writing the comment that explains the fix.

**3. A fixture that measured control characters.** Verifying a reported P1, I built the forked-tree
`lsblk` stub with `printf` octal escapes under dash. Dash mangled them, the awk read
`244240sdc`, and I got `__UNREADABLE__` — which read as "the finding is wrong." Rebuilding the
stub with exact bytes reproduced the defect immediately. **A measurement that refutes a specific,
well-argued finding deserves the same scrutiny as one that confirms it.**

**4. A denylist where the field's destination is a third-party warehouse.** #8013's first fix
enumerated four identifier shapes (ULID / UUID / long hex / long digit run) and shipped everything
it failed to imagine. Six shapes escaped verbatim, including `estate:run_<ULID>` — one prefix
character defeats `length(s)==26`, `run_`/`sess_` is a near-universal Redis convention, and the
Inngest keyspace uses ULIDs. So the likeliest production shape was the one still leaking. My
fixtures contained exactly the four shapes the denylist knew, so no mutation of the implementation
could reach it: **the gap was in fixture SHAPE, an axis mutation testing structurally cannot see.**

**5. A guard whose fixtures were all one shape.** `lsblk -s` on md/RAID or multipath emits a FORKED
tree — two ancestors at the same depth — and the base resolution took the last row, picking one
ARBITRARILY. Measured: `data_mount_devid=scsi-0HC_Volume_777777777`, a confident pin naming a
volume the mount is not on, on a gate that authorizes destroying a volume. Every fixture I wrote
was a chain. The by-id half of the same function already COUNTED its matches; the lsblk half
asserted a single leaf as a premise.

## Solution

- Controls must sit on the far side of the suspect filter. Before believing a zero, run the query
  WITHOUT the narrowing flag and diff the counts.
- Execute the artifact, do not syntax-check it. `bash -n` cannot see a prematurely-closed quote.
- Build fixtures with exact bytes (`python3` writing UTF-8), never shell escape sequences whose
  interpretation varies by shell.
- For any field whose destination is outside your trust boundary, allowlist. A denylist ships what
  it failed to imagine, and what it fails to imagine is not random — it is whatever the author was
  not thinking about.
- When one half of a function COUNTS and the other ASSUMES single-valuedness, the asymmetry is the
  finding.

## Key Insight

**Verification is the least-audited surface in a fix PR.** The implementation gets read carefully
because it is the point; the instruments that grade it get written fast, because they feel like
bookkeeping. Of eight review findings here, three were P1 and **all three were in verification** —
a gate reporting "could not measure" as "mismatch", a privacy denylist, and a test suite one token
from reporting green over a live regression.

The compounding form: **ask what each check would say if the thing it measures were broken.** If
the answer is "the same thing", it is not a check.

## Session Errors

**1. `--raw-only` artifact read as a production fact** — Recovery: re-measured without the flag
(57 vs 0 rows); retracted append-only. Prevention: a positive control must exercise the same filter
path as the assertion; when a query narrows, run it unnarrowed and diff the counts before believing
a zero.

**2. Apostrophe closed an `awk '…'` block** — Recovery: reworded; verified by executing the probe.
Prevention: after editing any `awk '…'` region, `grep "'"` the block and require zero matches
besides the delimiters. `bash -n` does not catch it.

**3. A guarded filename written into a comment on a baked carrier** — Recovery: reworded, cost tag
v1.1.33. Prevention: before editing a carrier, grep the diff's filenames against every `grep -qF`
in the suites that gate it; a comment is bytes in the file.

**4. Fork fixture built with dash `printf` octal escapes** — Recovery: rebuilt with python-written
UTF-8. Prevention: write fixture bytes with a tool whose escape semantics you control, and print
`cat -A` before trusting the result.

**5. Uninitialized `maxd` made the first depth-0 line take `else if`** — Recovery: `cnt == 0 ||
d > maxd`. Prevention: run every shape, not the new one.

**6. Unanchored grep substring-matched a sibling filename** — Recovery: anchored re-check.
Prevention: `cq-assert-anchor-not-bare-token` applies to verification greps too, not just
assertions.

**7. `grep -c … || echo 0` emitted `0\n0`** — Recovery: dropped the redundant fallback. Prevention:
`grep -c` already prints 0.

**8. `PUSH_RC=0` read `tail`'s exit** — Recovery: captured `$?` directly. Prevention: never take a
verdict through a pipe.

**9–12. Four false prose claims** ("three-way collision" refuted by its own next line; an `lsblk`
comment citing a `-d` measurement for a command without `-d`, contradicting the phase-0 record;
"pins all three" when the pin covered two; an ADR amendment claiming a sweep it did not perform) —
Recovery: all four corrected; the drift pin was extended so the claim became true. Prevention: for
every causal or universal claim the diff ADDS, name the command that falsifies it and run it.

**13. #8013 shipped as a denylist** — Recovery: inverted to a fail-closed allowlist. Prevention:
for a field crossing a trust boundary, allowlist.

**14. Follow-through floor keyed on failure-inclusive `checks`** — Recovery: separate `passes`
counter + conservation check. Prevention: a floor must read a counter that DROPS when the
mechanism breaks.

**15. Mutation self-test reached only the first early-return** — Recovery: SELFTEST2 drives a
landed-but-inert mutation. Prevention: a self-test must reach the branch that SCORES.

**16. PASS(392) > TOTAL(391)** — Recovery: TOTAL moves with PASS on both arms. Prevention: roll
back both counters together.

**17. Tagged three minutes before the last review agent returned** — Recovery: build was still
queued and GHCR 404, so the tag was cancelled, deleted and re-cut at no cost. Prevention: wait for
the full panel before spending an irreversible artifact; disposability keys on the REGISTRY, not
the run's conclusion.

**18. `rm -rf` hit the protected-location guardrail** — Recovery: `mktemp -d`. Prevention: use
`mktemp -d` for scratch, always.

**Forwarded from session-state.md** (planning phase): a `replace_section` substring-index splice
fired twice; an acceptance-criteria renumber mangled by first-occurrence replace; the
`plugin:github:github` MCP server failed to connect (reads went through `gh`).

**19. The Incident-PIR gate fired on the word `outage` inside compound nouns naming a *gate* and a
design *window*** — Recovery: read all four matches (`network-outage gate`, `### Network-Outage
Deep-Dive`, and twice `the cron-outage window is ADR-100's known cost`) and all three issues; none
reports an event, and #8013's own body records "not customer PII … Real but low severity". No PIR
owed. Prevention: `scripts/ship-incident-pir-gate.sh` already boundary-guards `incident` (vs
`incidental`), `prod` (vs `produced`/`producer`) and `live` (vs `delivery`) for exactly this
substring class, and its header explains why each was needed — `outage` is the same class left
unfixed one line below them. The discriminator is not a boundary, though: `network outage` is
legitimate outage vocabulary, so a `\b`-style guard would delete a true positive. What separates
these four hits is that the noun they modify is a *gate*, a *deep-dive* section heading, or a
*window* — a mechanism, not an event. Anyone touching that regex should treat "the token names a
mechanism" as the case to exclude, and fixture it in both directions before believing the change.
