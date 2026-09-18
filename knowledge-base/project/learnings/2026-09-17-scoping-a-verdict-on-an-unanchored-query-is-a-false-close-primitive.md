---
date: 2026-09-17
tags: [review, guards, telemetry, followthrough, security]
category: best-practices
refs: [7960, 7500, 8244]
---

# Narrowing a verdict's evidence base is only safe once the base is authenticated

## What happened

`#7960`'s probe graded a mixed-boot window wrong: it derived "which host am I
talking about" from the newest row, while counting leaks across the whole
window. After a host replace those two describe different hosts, so the first
post-replace sweep would have posted *"the redaction shipped and is not
working"* on the one run that first observes it working.

The fix — scope the graded rows to the delivered boot — was correct and
insufficient. An 8-seat review found it had **converted a false FAIL into a
false CLOSE**.

## The transferable shape

**Scoping a verdict to a key derived from the data is only sound if the data is
authenticated first.** Before scoping, a contaminating row could only *dilute*
the evidence — it added noise to a window-wide count. After scoping, the same
row *selects* the evidence base: it supplies the key, every genuine row is
excluded for not matching it, and the verdict is computed from the contaminant
alone.

The direction flips with the blast radius. Dilution pushes toward the noisy,
recoverable failure (a red someone investigates). Selection pushes toward the
quiet, irreversible one (an auto-close on a live leak tracker).

So: **when a change narrows what a verdict is computed over, ask what happens
if the narrowing key itself is attacker- or noise-supplied.** If the query
feeding it is unanchored, scoping makes it worse, not better.

Here the query was `--grep SOLEUR_ZOT_DISK`, which compiles to an unanchored
`raw LIKE '%…%'` over a source every host multiplexes into. The repo already
had `zot_envelope_anchor()` for precisely this, with three measured
GitHub-webhook rows recorded against it — and `User-Agent` is on the producer's
redaction keep-list, so the vector was an unauthenticated request header.

## Why one probe of four had the hole

The parse is centralised in three guards. This probe hand-rolled it,
implemented **one**, and cited the library in a comment as if it implemented
all three. The three siblings each use all three.

A citation covering a third of the named mechanism is worse than no citation: a
reader auditing on it concludes the invariant holds. If you cannot `source` a
shared guard, mirror every one of its invariants with a `MIRRORS <fn>` label —
the idiom a sibling already established — and file the divergence.

## The verification was worse than the code

The harness asserted **exit codes only**, against a probe with six distinct
`exit 2` sites, so four of six cases collapsed onto one integer. Measured:

- deleting the guard one case was *named for* → 6/0 green
- deleting the trusted-region cut another case was named for → 6/0 green
  **while the forge succeeded**
- replacing the probe invocation with the expected value → 6/0 green, subject
  never executed

The rebuilt suite asserts a **branch marker** per case. That is not belt-and-
braces: removing both `boot_id=unknown` guards leaves the exit code at `2` and
is caught *only* by the marker.

## A CONCUR dissent can be right about the verdict and wrong about the fix

The gate correctly rejected a scope-out: the trigger I proposed was **circular**
(a verdict emitted by the predicate under challenge), and the repo had already
run the design cycle. Both true.

Its prescribed inline fix — copy the sibling's two-key disjunction — rested on
`SOLEUR_ZOT_LOG_BOOT` being a Phase-B delivery key. It flagged that as a hidden
assumption. Checking it took one command: `git log -S` puts that marker in the
log-shipper PR, not the redaction PR, so it proves a *weaker* claim than the
probe makes. Copying the sibling would have shipped a key that does not answer
the question.

**Verify a dissent's premises with the same rigour as a finding's.** A gate's
authority attaches to its verdict, not to every clause supporting it.

## When no positive key exists, refuse rather than infer harder

There was no necessary-and-sufficient delivery key: the only Phase-B-exclusive
token appears on a sub-path, and the change added no always-present field. The
resolution was not a cleverer inference — it was to require **proof** for the
two authoritative outcomes (the one that closes a security tracker and the one
that publicly asserts a control is broken), and to report CANNOT ESTABLISH when
the evidence cannot distinguish a reboot from a replace.

The cost is explicit: the tracker will not auto-close on a host that never emits
the token. For a leak tracker that is the correct failure direction, and it is
the argument for a producer-side change rather than a reason to guess.
