---
title: "A pyramid marker covers a file's tests, not its dominant signal"
date: 2026-10-09
tags: [test-pyramid, review, e2e, coverage]
issue: 9855
---

## What happened

During #9855 PR-1 marker backfill, the marker reasons were written from
per-file *signal tallies* (`page.*` vs `request.*` counts) rather than
per-test inventory. `otp-login.e2e.ts` showed dominant `page.*` signals
and got a "full OTP login flow through rendered UI" marker — but it also
carried two `request.get` `/callback` tests that were browser-free,
layer-inverted, and duplicated the tests being demoted out of
`oauth.e2e.ts`. A review seat caught it post-push; the fix was deleting
the two residual tests so the marker's claim became true.

## The rule

When backfilling `pyramid-justified:` on an existing file, enumerate the
file's `test()`/`it()` cases and classify each — never write the reason
from the file's dominant API signal. A marker that covers *most* tests
gives false cover to the residual inversion the convention exists to
surface. Same class as census-over-enumeration sharp edges: a count of
matches is not an audit of members.

Corollary surfaced by the same seat: an "accepted forwarded host"
assertion can be non-discriminating when the allowlist and the rejection
fallback are the same value (PRODUCTION_ORIGINS == `app.soleur.ai` ==
fallback). Choose a shape where accept and reject produce different
output (dev origins admit `http://localhost:3000`), or the test pins
nothing.

## Evidence

- Review finding → commit dc9e68e632 (otp-login residual tests removed)
- Discriminating rewrite → commit 63ec07a54c (csp-middleware.test.ts
  dev-mode forwarded-host arm)
