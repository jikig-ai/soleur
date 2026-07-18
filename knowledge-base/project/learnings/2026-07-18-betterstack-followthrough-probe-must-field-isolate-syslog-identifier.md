---
title: A Better Stack log-content follow-through probe must isolate the journald SYSLOG_IDENTIFIER field, not a bare substring — the shared source is contaminated by inngest webhook logs
date: 2026-07-18
category: integration-issues
module: scripts/followthroughs
tags: [betterstack, followthrough, observability, false-positive, fixture-fidelity, ci-deploy]
issue: 6475
pr: 6652
---

## Problem

`#6475` D-6 shipped a Better Stack **soak follow-through** probe
(`scripts/followthroughs/ci-deploy-sentry-post-fail-6475.sh`) whose exit code
**auto-closes the tracker**: exit 0 (PASS) → sweeper closes; exit 1 (FAIL) →
alarm comment; exit 2 (TRANSIENT) → retry. To detect real ci-deploy "Sentry POST
failed" journald lines, the first implementation queried
`betterstack-query.sh --grep "Sentry POST failed"` and post-filtered the output
with a **bare `grep 'ci-deploy'`** — mirroring the `chardevice` precedent's
`denied_count()` shape and the plan's own design.

Against **live prod** the probe **false-FAILed (exit 1)**. `betterstack-query.sh`'s
`raw` column is the full journald JSON, and **inngest ships GitHub-webhook
processing logs to the same Better Stack source** (`SYSLOG_IDENTIFIER=doppler`).
Those rows embed branch names (`…-ci-deploy-…`) and issue/PR bodies — which quote
both marker strings **verbatim**, including this tracker's own body. A 14-day
window matched **2 rows** on the bare substring, **zero** of which were real
ci-deploy emissions. Worse: self-perpetuating — the sweeper's FAIL comment prints
the offending rows onto the issue, re-seeding the contamination.

The unit suite was **green** the whole time, because its fixtures modeled `raw`
as a bare syslog string (`<13>ci-deploy: …`) instead of the real **escaped
JSONEachRow** shape betterstack-query.sh emits. The detector matched the fixtures;
neither matched reality.

## Root cause

Two compounding gaps:

1. **Discriminator scoped to a payload SUBSTRING, not a journald FIELD.** `ci-deploy`
   appears in far more than ci-deploy emissions — any log line (from any producer on
   the shared Vector source) that mentions the string matches. The only reliable
   discriminator is the top-level journald field `SYSLOG_IDENTIFIER":"ci-deploy`.
2. **Fixtures modeled a convenient shape, not the real emission form.** The real
   `raw` is JSON with backslash-escaped inner quotes on stdout
   (`\"SYSLOG_IDENTIFIER\":\"ci-deploy\"`); the fixtures used bare syslog, so the
   test could never reproduce the live contamination (a doppler-tagged row carrying
   both markers).

The plan *anticipated* the field-spelling risk ("verify the `SYSLOG_IDENTIFIER`
field spelling in a real `raw` row before freezing the LIKE") and named a live
discoverability AC (AC9) — but that verification was deferred to post-merge instead
of run at `/work`, so nothing caught the shape/contamination before review.

## Solution

Isolate the journald field in **both byte-forms** (they differ by context):

- **Server-side** (`betterstack-query.sh --grep`, runs as `raw LIKE '%term%'` against
  the UNescaped ClickHouse column): `SYSLOG_IDENTIFIER":"ci-deploy`
- **Client-side** (grep over the JSONEachRow STDOUT, where inner quotes are
  backslash-escaped): `SYSLOG_IDENTIFIER\":\"ci-deploy\"`

POST-failure detection = server `--grep "Sentry POST failed"` + client
`grep -F` on the escaped field marker. Liveness = server `--grep` on the LIKE marker
+ client `grep -cF` on the escaped marker. FAIL is evaluated **before** the liveness
fetch so a liveness-query fault can't mask a real recurrence.

Fixtures rewritten to the real escaped JSON shape, plus a **contamination arm** (a
`doppler`-tagged webhook row embedding both markers → must PASS, not FAIL) and a
**FAIL-precedence arm**. Live probe now PASSes (569 real ci-deploy rows, 0 POST
failures in 14d). Both new arms mutation-proven non-vacuous.

## Key insight

**For any log-content follow-through probe over a SHARED Better Stack / Vector
source, the discriminator MUST match the journald SYSLOG_IDENTIFIER field, never a
bare payload substring — and the fixtures MUST reproduce the real escaped
JSONEachRow shape.** The source carries webhook/app logs that quote arbitrary text
(branch names, issue bodies, PR diffs), so any marker string a human might type
into GitHub will appear in the payload of a *different* producer's rows. A
bare-substring probe is self-contaminating when the tracker's own body quotes the
marker. Run the live discoverability query (AC9-class) **at /work, not post-merge**
— it is the only check that surfaces both the escaping and the contamination.

## Session Errors

- **Bare-substring discriminator false-FAILed against live prod** — Recovery:
  field-isolate on `SYSLOG_IDENTIFIER` (two byte-forms) + live-verify. **Prevention:**
  followthrough-convention runbook sharp edge (routed below); run the live AC at /work.
- **Fixtures modeled bare-syslog `raw` instead of real escaped JSON → false green** —
  Recovery: rewrote fixtures to the captured real shape + contamination arm.
  **Prevention:** capture one real (redacted) row and model fixtures on it before
  authoring; same routed sharp edge.
- **Commit body carried `closes #6475`** (auto-close bigram) — Recovery: history
  rewrite (soft-reset, no closing-keyword+#N adjacency). **Prevention:** already
  covered by ship Phase 6 `auto-close-scan.sh` + the documented
  `auto-closes-meta-content` class; use `Refs #N` in descriptive commit prose.
- **"eight" emitter overcount in docstring/plan** (one-off) — Recovery: corrected to
  seven Sentry sites.
- **AC3 grep matched my own `${VAR:?}` anti-pattern comment** (one-off, documented
  class `cq-assert-anchor-not-bare-token`) — Recovery: reworded the comment to drop
  the literal.
