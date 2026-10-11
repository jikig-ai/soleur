---
title: "A credential guard modeled on the vendor's current format refused the vendor's next format — and a test that names a swept literal joins the sweep"
date: 2026-10-11
category: test-failures
module: .github/scripts/bump-inngest-bootstrap-pin.sh + .github/scripts/test/test-bump-inngest-bootstrap-pin.sh + scripts/lint-shell-trace-credential-refusal.test.sh
issues: [9972]
---

# The #9972 token-shape refusal: two failure modes, one root cause — a copy left outside the ring it described

## Problem

`bump-inngest-bootstrap-pin.sh`'s args-stage `GH_TOKEN` shape guard was written
during the argv-bearer sweep (merged 2026-10-10) with the class
`[A-Za-z0-9_]` — the alphabet of the *legacy* ~40-char `ghs_` base62
installation token. GitHub's issued installation tokens are now ~390 chars and
carry `.` and `-`; the first bump run after the sweep merged died with
`SOLEUR_CREDENTIAL_REFUSED reason=token_shape` on a perfectly valid credential,
and the `IREF`/`ZIREF` pins could not advance past the offending commit.

Two properties made it expensive rather than noisy-but-fast:

1. **The guard judged a vendor's format, not a property of the secret.** "What
   GitHub issues" is mutable vendor surface; `[A-Za-z0-9._~+/=-]` is RFC 6750's
   b64token grammar — the maximal alphabet a bearer value may occupy. Guarding
   by vendor shape made the pipeline's liveness hostage to a rotation the repo
   cannot observe, while guarding by canonical alphabet narrows the contract to
   exactly "no injection byte reaches the header channel."
2. **The fix site was a copy outside the copy ring.** The repo's drift defense
   for this alphabet is a byte-identical-copy census:
   `lint-shell-trace-credential-refusal.test.sh` greps `_bearer_ok() {` across
   `*.sh` and requires every stripped body to equal `_CANON_BODY`. A bespoke
   `case` glob — even a correct one — is invisible to that net. The repair
   therefore had to convert the guard to a canonical-body `_bearer_ok` call
   (call-site keeps the `token_shape`/`control_char` discrimination the bare
   `return 1` cannot carry), which puts the alphabet under the ring's pin by
   construction instead of by comment.

## The second-order failure: the test that pinned the ring joined the ring

The review fix-round added a bc_ok-parity row to the suite whose sed pattern
contained the literal `_bearer_ok() {`. The census's pathspec — `*.sh`,
excluding only `*.test.sh`/`tests/scripts/test-*`/`fixtures` — sweeps
`.github/scripts/test/*.sh` too, so the test's own text counted as a 74th,
off-canonical "copy" and turned the parity row red on a file that contained no
guard at all. The census's sed strips a leading `[A-Za-z0-9_]*_bearer_ok() `
prefix, so any line containing the contiguous literal — even a *comment naming
it* — counts.

Lesson: when a sweep is line-based over a broad glob, **anything that spells
the swept literal inside the swept tree is a member of the population** —
detector, comment, or code. The test-side pattern must be assembled split
(`'_bearer_''ok() {'`) and every comment must avoid the contiguous form;
self-documenting the rule in the comment keeps the next editor from
reintroducing it.

## Fixture-side durable patterns

- A synthetic token fixture must carry **every** newly-admitted byte in one
  value (`.` `-` `~` `+` `/` `=`), be guarded by a self-check that the fixture
  is out-of-class for the *legacy* alphabet, and be assembled only as far as
  the staged-index scanner requires (split the `ghs_` prefix — punctuation is
  not scanned).
- Derive per-row comparison needles from the row's own token
  (`SHIM_B64` from `$tok`, `tok_b64` likewise) — a needle pinned to a sibling
  constant certifies the wrong wire, and a derivation is only pinned if some
  assertion *reads* it on a path that can fail (the shim's `env=header-ok`
  conjunct now compares `Authorization: basic ${SHIM_B64}`, so a reverted
  constant reds the rows it would otherwise certify vacuously).
- Refuse-row enumeration comments rot — keep the comment's shape list
  structurally equal to the row list, not prose-adjacent.

## Verified measurement record

- Legacy-class refusal of a live-minted installation token: token_len=390,
  out-of-class bytes `.`/`-`; token revoked with HTTP 204 after the probe.
- Census with the unsplit pattern: 74 copies / 1 off-canonical; after the
  split: 73 / 0.
- Suite: 699 pass / 0 fail; pre-fix RED was 13 failures concentrated at the
  guard + wording needle.
