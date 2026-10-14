---
title: "Every defect was in the verification, not the fix — and most were introduced by it"
date: 2026-09-07
category: test-failures
module: apps/web-platform/infra
issues: [7695, 7761, 7674, 6894]
tags: [guards, vacuity, mutation-testing, anti-vacuity-floor, verification, oci-pin]
---

# Every defect was in the verification, not the fix

## Problem

A one-line-ish change — re-pin an OCI image to a build that carries an emitter — produced
3 P0s and 6 P1s across a seven-agent review. **Not one of them was in the pin bump or in the
heredoc repair.** Those were correct from the first commit and survived every pass unchanged.

Every defect was in the guards written to prove them correct, in the comments written to explain
them, or in the plan written to justify them.

## The measurements

Each of these is a measured green over a broken property, not an inference.

1. **A fix's verification inherits the defect's framing.** The heredoc repair was right. Guard D,
   written to prove it, used ONE regex as both census and classifier — so a delimiter it could not
   read was subtracted from the inventory AND the population in one stroke. Measured:
   `cat > /usr/local/bin/soleur-injected.sh <<7EOF` with `$(id -un)` in the body left all 8 asserts
   green. Its own prose claimed to cover `tee`; `tee f <<C` was invisible too. Fix: a PERMISSIVE
   operator census plus a STRICT delimiter parse — the split Guard A already had, in the same file.

2. **A suite cannot see its own dispatcher.** `if eval "$condition"` -> `if true` produced a
   byte-identical `163/163 passed` WITH REAL DEFECTS PRESENT. All five section floors were
   themselves `assert` calls, so one edit disarmed the helper and every backstop simultaneously.
   The bucket-swap variant (`fail() { PASS=$((PASS+1)); }`) prints FAIL rows on screen while the
   summary says 0 failed.

3. **A section floor cannot see its own section deleted.** Removing the whole Guard A block
   reported `149/149 OK`; removing Guard A and Guard D reported `137/137 OK`. The floors live
   INSIDE the sections they guard.

4. **An exemption scoped by NAME, not by SITE.** `sort -u` collapsed two unquoted heredocs sharing
   a delimiter into one member, and the body extraction read only the FIRST occurrence — so a
   second `<<DOPPLEREOF` kept every count and redirected the content assertion onto the wrong body.

5. **A tag pinned to another tag's bytes passed everything.** Writing
   `v1.1.26@sha256:<v1.1.25's digest>` at all four sites: `161/161` green. Guard A resolves the
   TAG (whose tree does match HEAD); Guard B compares the sites to EACH OTHER. Neither binds the
   digest to the bytes.

6. **Deleting a true warning to install a false reassurance.** The comment at the pin used to say,
   correctly, that bumping the tag without re-resolving the digest silently pins one tag to
   another's bytes. It was replaced with "the guards catch it" — measured false by (5), and sitting
   at the exact line an operator reads while making that mistake.

## Key insight

**On a fix PR, review the new ASSERTIONS before the new code.** The fix is written while holding
the defect in mind; its verification is written fast, because it feels like bookkeeping rather than
authorship. That is where the defects are.

Two corollaries the session paid for:

- **A documented class recurring is a PROPAGATION failure, not a discovery.** Both sibling suites
  already carried the dispatcher self-test and the global floor; `inngest.test.sh`'s own floor
  comment records the exact failure verbatim. The disposition for a class already written down is
  a mechanical gate or an import — never another write-up. Cheapest gate: when you fix an instance,
  `grep -l` the SHAPE across `git diff --name-only origin/main...HEAD` before moving on.
- **Instrument yields are DISJOINT, and the cheap ones go first.** `shellcheck` found 2 (both mine,
  both then mutation-verified load-bearing); the deterministic template validator found 1 (a render
  break); the 7-agent panel found 9; my own mutation runs found 3. No instrument found more than a
  third of the total, and the two cheapest ran in seconds.

## Prevention

- Give every assertion helper a **dispatcher self-test** that drives it in both directions and
  reports with `printf` + `exit`, never through the helper it backstops.
- Give every suite a **global** assertion floor as well as per-section ones — a section floor
  dies with its section.
- For any guard that parses a grammar, keep a **permissive census** beside the strict parse, so an
  unreadable form reports `parsed N of M` instead of vanishing.
- Scope an exemption by **site**, not by name, and pin the site count before extracting from it.
- **Never let an assertion COUNT vary with the environment.** A no-comparable-base branch emitting
  one assert where the live path emits two made the mutation sandbox's BASELINE red, which voids
  every row and turns a real verdict into the unresolved class. Carry unavailability as a VALUE.
- For every causal or universal claim the diff's PROSE adds, name the falsifying command and run
  it. A correct fix with a false rationale teaches the next reader the thing a post-mortem exists
  to prevent.

## Session Errors

- **Guard B floor miscount (wrote 8, added 7).** Recovery: the exact-equality floor caught it on
  the first run. Prevention: derive the count from a green run, never from the number you expected.
- **`${IMAGE}@${DIGEST}` written into a cloud-init COMMENT broke the templatefile render**
  (`vars map does not contain key "IMAGE"`), inside a comment documenting the pin. Recovery:
  reworded to drop the sigils. Prevention: the trap is already documented — terraform's
  interpolation scanner does not skip prose. `validate-infra-templates.sh` caught it, which is why
  a non-zero exit gets investigated rather than skimmed.
- **Guard B row6's assertion count varied by environment**, redding both floors in the mutation
  sandbox. Recovery: made the count invariant. Prevention: see above.
- **`EXPECTED_FLAG` was `rolled-back` while the live flag is `aborted`.** The brief stated
  `aborted` is terminal and ADR-199's G19 already accepted both, and the constant was still not
  connected to it. Prevention: when a brief states a live value, grep the code for the constant
  that consumes it.
- **A lint "fix" turned a `random_password` + `doppler_secret` CONJUNCTION into a hyphen.**
  Recovery: reverted and reflowed. Prevention: after any mechanical markdown fix, read the DIFF
  for meaning, not just the linter's exit code.
- **The first byte-identity check was broken** — a heredoc inside a script sourced from stdin
  consumes the same stream. Prevention: execute extracted blocks as files, never via stdin.
- **The first exemption mutation was misplaced**, hitting a comment 480 lines above the target.
  Prevention: assert the intended CONSTRUCT changed (`s.count(old)==1`), not that the file did.
- **Stopped mid-pipeline after review**, and the operator had to ask why. Prevention: review
  completing and a battery running are both mid-pipeline states; the continuation gate says the
  next skill invocation is the next action in the SAME turn.
- Forwarded from `session-state.md`: deepen-plan not run in the first planning turn; Phase 4
  shipped pre-review; AC12 shipped incoherent; plan length regressed against its instruction.
