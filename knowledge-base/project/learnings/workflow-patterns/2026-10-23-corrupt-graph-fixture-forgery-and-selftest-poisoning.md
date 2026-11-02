---
date: 2026-10-23
category: workflow-patterns
title: Corrupt-graph fixture forgery replaces rm-fail-open; selftests must never stream exercised markers
pr: 10953
issue: 10921
---

# Corrupt-graph fixture forgery + selftest-poisoning pattern

**Root cause.** `rm -f .git/objects/<fanout>` fixture corruption fails open on packed stores:
the object survives in a pack, `cat-file -e` still reads it, preconditions read false and the
suite reports broken-fixture FAILs — the observed g1b.B7 CI flake. `ubuntu-latest` moves git
versions, so which runs get packed fixtures is uncontrollable.

**Fix shape.** Never-written-oid forgery: `dead_oid` = `hash-object` of a constant nonce as a
BLOB (`-t commit` is fsck-refused on nonce bytes, `missingTree` — measured git 2.56), never
written; `corrupt_walk_break` forges a commit whose parent is the dead oid via `update-ref`.
Layout-immune on loose AND packed stores. Corollary: `repack -ad` AFTER forging fails
(`Failed to traverse parents` — repack traverses reflogs which record the forged tip), so any
packed arm repacks the healthy graph BETWEEN seed and forge.

**Selftest-poisoning class (new).** A selftest that exercises `SKIP (loud):`/`::warning::`
emission on the suite's real streams puts markers in the job log of every green run — the
standing monitor files real alerts on the instrument's own exercises. Forced exercises must
CAPTURE emitted lines (`$LAST_OUT`/`STEP_OUT` pattern) and grep the capture.

**Skip-producer contract.** A `corrupt_skip` producer must: emit `SKIP (loud): <probe-greppable
name>` on stderr + `::warning::` on STDOUT (GH scans commands on stdout only), take an explicit
numeric cost validated at entry (`arm_skip` parity), charge via `10#$cost` (octal trap), and be
covered by per-source `observed` accounting (never pooled — a blind source must TRANSIENT, not
inherit another source's clean).

**Review-panel yield.** 4-seat plan review + 11-seat code panel + 5-seat fix round on a CI
fixture diff surfaced: mint selftest verdict inside snapshot window (fail-open), repack rc
ignored (packed arm silently loose), sanitizer narrower than log-injection rule, unscoped force
knob, octal charge, start-banner vs completion discriminator. Fix everything in the same PR —
the fix-round verifier confirmed 27/27 closed.

Ref #10921, #10953, ADR-188 (counted-skip verdict shape).
