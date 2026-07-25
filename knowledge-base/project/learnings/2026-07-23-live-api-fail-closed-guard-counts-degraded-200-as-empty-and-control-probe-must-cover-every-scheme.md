---
date: 2026-07-23
category: security-issues
module: infra/ci-gates
issue: 6767
pr: 6833
tags: [fail-open, jq, cloudflare, terraform, control-probe, default-deny, mutation-testing]
---

# A live-API fail-closed guard counted a degraded `200` body as "empty", and a single-scheme control probe left the other scheme's `404` seam open

## Problem

The #6767 pre-apply gate (`tests/scripts/lib/preapply-entrypoint-gate.sh`) is a
**default-deny, fail-closed** CI guard: it GETs a Cloudflare ruleset phase
entrypoint over the live API and must **fail the apply** unless it can *prove*
the entrypoint is empty, so a first `terraform apply` cannot whole-list-clobber
a dashboard-created rule (the outage-class #6746 hazard on `app.soleur.ai`).

It passed its own 31-assertion suite green and shipped from `/work` with **two
live fail-open seams and three vacuous fail-closed test branches** — all caught
only by the 6-agent `/review` panel (security-sentinel, user-impact-reviewer,
test-design-reviewer independently converged; architecture mutation-proved a
third).

## Root cause — two concrete, greppable mechanisms

### 1. `jq '.result.rules | length'` reads a degraded `200` body as `0 == empty == PASS`

The decision was `rulecount=$(jq -e '.result.rules | length' <<<"$body")` then
`[[ $rulecount -gt 0 ]] && fail`. But:

- jq evaluates `null | length` to **`0`**, not an error — so `{"result":null}`,
  `{"success":false,...}`, or any 200 body lacking a `rules` **array** yields `0`.
- `jq -e` exits **0** on a numeric `0` (it only exits non-zero on `false`/`null`/
  no-output), so the intended "unparseable → fail-closed" branch never fires.

Cloudflare *does* return `200` with `{"success":false,"result":null}` on some
surfaces, so a populated entrypoint behind such a response read as "proven-empty
→ safe to create" — a fail-open clobber, in the exact guard built to prevent it.

**Fix:** assert the shape is an array *before* trusting the count, so every
null/missing/non-array `rules` routes to the existing fail-closed branch:

```bash
rulecount=$(jq -e '.result.rules | if type=="array" then length else error("rules not an array") end' <<<"$body")
```

### 2. A control probe that validates "`404` means empty" must exercise *every* URL scheme it will trust a `404` from

The gate proved "a `404` provably means empty (not a mis-built URL / bad token)"
with a control probe against a **known-populated zone phase**, requiring `200`.
But it built two target URL schemes — `zones/$z/...` (kind=zone) **and**
`accounts/$a/...` (kind=root, e.g. the in-scope `bulk_redirects`). The control
probe only ever touched the **zone** scheme. So a `kind=root` target `404` was
trusted as empty with **zero proof** the account path / token account-scope /
`account_id` was valid — a `404` from a mis-built account URL is indistinguishable
from an empty account phase. The zone control closed the zone `404` seam and left
the account `404` seam wide open.

**Fix:** add a per-scheme control (once per `account_id`, memoized) —
`GET accounts/$a/rulesets` (the list endpoint, always `200` with read scope),
require `200`, else fail-closed with a distinct message — before any `kind=root`
`404` may PASS. Also strengthen the zone control to require `rules.length > 0` on
the known-populated phase (a `200` with 0/null rules there proves a degraded
body, not an empty phase).

### 3. The fail-closed branches for `known-after-apply` URL fields were untested (mutate-to-fail-open green)

A zone/account created *in the same apply* serializes `zone_id`/`account_id` as
**`null`** in the plan JSON (value sits in `after_unknown`) — a *common*
create-from-absent shape. The guards for null `zone_id`/`account_id`/`phase`
existed but **no fixture exercised any of them**, so deleting each left the suite
green and the row fell through to a stub-`404` → PASS. A default-deny gate must
have a fixture whose *only* trigger is each fail-closed branch, mutation-proven RED.

## Key insight

For a fail-closed guard that decides on a **live API response**, the response is
adversarial input: a `200` is not proof of the happy-path shape, and a `404` is
only trustworthy per-scheme once a control probe has proven that scheme's
path+auth. Two litmus questions to run at authoring/review time:

1. **"What non-array/degraded body makes my count read as 0?"** — any `count`
   over `.result.<field>` must gate on `type=="array"` first, never bare `length`.
2. **"Every URL scheme I trust a `404` from — did the control probe touch that
   exact scheme?"** — a control probe validates the *scheme it ran against*,
   nothing else.

And for the tests: every fail-closed branch needs an isolating fixture that goes
RED when *only* that guard is neutered — mutation-prove it, because the passing
suite is evidence about the assertions you wrote, not about the branches you
didn't cover. (Sibling of `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`
and the review catalogue's "guard certifies placement not correctness".)

## Session Errors

1. **`iac-plan-write-guard.sh` blocked the plan write on the phrase `out-of-band`**
   (pattern b) — Recovery: reworded to "outside Terraform" + reviewed-ack comment.
   Prevention: one-off; the guard's ack-escape is the documented path. No change.
2. **No real `terraform show -json` capture obtainable** (no CF creds / R2 backend
   locally) — Recovery: fixtures synthesized against the documented JSON-plan format;
   disclosed as a residual in plan + PR, CI is authoritative. Prevention: expected
   env limitation; keep disclosing rather than overclaiming a live capture.
3. **`/work` shipped a fail-closed guard with 2 fail-open seams + 3 vacuous
   fail-closed tests, green locally** — Recovery: 6-agent `/review` caught all;
   fixed inline with mutation-proof. Prevention: this learning + the two litmus
   questions above; a live-API guard PR must run the security + test-design + user-impact
   lenses (it did — the panel is the control that worked).
4. **Fix-subagent misattributed its own edits as "already present uncommitted from a
   prior session"** — Recovery: independently verified the committed state via
   `git log`/`git grep`/re-running the suite; the narrative was false. Prevention:
   trust the git-verified artifact, never a subagent's prose about provenance.
