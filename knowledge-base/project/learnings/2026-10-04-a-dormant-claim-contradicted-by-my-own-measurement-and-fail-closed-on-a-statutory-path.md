# Learning: "dormant in prod" was contradicted by my own Phase 0 measurement, and fail-closed on a statutory path was the wrong default

## Problem

PR #9456 (ADR-269 inbound email routing table) shipped a plan, ADR, resolver comments and
C4 text asserting the change was "dormant / byte-identical for production traffic" because
the routing table ships empty. The 12-seat review (architecture, user-impact, code-quality,
simplicity, all independently) refuted it: the plan's own Phase 0 result recorded that
Sieve-forwarded `ops@` mail arrives as `to: ["triage@inbound.soleur.ai"]`, so `recipients`
is non-empty on EVERY real event and every mail issues one routes query. "Empty table" is
a property of the data, not of the code path.

The same design chose fail-closed: a routes-query error threw. On a `retries: 1` Inngest
function whose webhook already returned 200 (Resend will not redeliver), a PostgREST
schema-cache miss after migrate, a rollback or a blip would have dropped the operator's
statutory mail (DSAR / breach notice). A second gap: "safe only while every route resolves
to the operator" was documented in the ADR but nothing enforced it.

## Solution

- Resolver enforces the invariant: every matched route must be the operator pair; otherwise
  the mail is claimed under the env owner and reported (`op: route-degraded`, pg code only).
  A lookup error degrades the same way. Because every branch now yields the operator, a
  fail-open arm is safe. Two aliases of the operator are not ambiguous.
- Claims rewritten at every site (ADR, ADR-066 amendment, PA-27, C4, `.env.example`, DSAR
  exclusion, plan Review Revisions): only an event with EMPTY recipients skips the query.
- `received_for` (envelope) listed before `to` (sender-written), cap on VALID addresses.

## Key Insight

1. Before writing "dormant / unchanged in prod", list every prod INPUT the change touches
   using the plan's own measured fixtures, and ask whether each reaches the new branch.
   A measured fact in the same document is the cheapest falsifier.
2. On a path where the producer will not redeliver and the payload is statutory, the default
   for an unexpected lookup failure is degrade-and-report, not throw. Fail-closed is correct
   only when the fallback would misdeliver (the non-operator tenant case, #9459).
3. A safety invariant stated in an ADR is a hypothesis until a line of code refuses the
   violating input.
4. An applied migration's content hash is in the ledger; editing it (the review-driven FK
   guard) needs the dev `content_sha` re-synced in the same session, or the parity probe
   flags drift.

## Session Errors

- **Asserted "dormant / byte-identical in prod" against my own Phase 0 data** — Recovery:
  restated everywhere; resolver now operator-only. **Prevention:** plan-sharp-edges bullet:
  enumerate prod inputs vs the new branch before claiming dormancy.
- **Chose fail-closed for a lookup error on a retries:1 statutory path** — Recovery:
  degrade-to-operator plus Sentry. **Prevention:** same bullet (name the redelivery
  contract of the producer when choosing throw vs degrade).
- **Edited an already-applied migration** — Recovery: re-ran verify 8/8 on dev, synced the
  ledger `content_sha`. **Prevention:** change an applied migration only with a same-session
  ledger resync; prefer review fixes before first apply.
- **Filing hook blocked `gh issue create` (variable body path, chained filings)** —
  Recovery: literal absolute `--body-file`, one filing per call (brainstorm SKILL updated).
- **Repo-research agent asserted the webhook lacks `to`/`cc`** — Recovery: refuted via the
  SDK type, the example payload and the live API. **Prevention:** verify agent claims about
  external payload shape against the vendor type.
- **Plan `Write` "modified since read"; push rejected after rebase** — one-off; re-Read /
  `--force-with-lease` on my own branch.
- **`psql -c` does not interpolate `:'addr'`** — moved the query to stdin.
- **Affected gate: TOM-4 posture and credentials_required baseline (42/43/44)** — fixed in
  code; the baseline is a repo-global ratchet a file-selected set cannot see.
- **Monitor re-emitted failures; stop hook flagged unkept promises; miscounted remaining
  review seats** — bounded wait loops; state the true count.
- **`scripts/test-all.sh` not executable; a python multi-replace aborted on a wrapped
  comment** — ran with `bash`; the script writes only after all replacements match.

## Tags
category: logic-errors
module: email-triage
