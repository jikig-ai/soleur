---
title: "fix(cloudflare): Phase 5 p5-mint.js sends the token-create POST Node-side"
date: 2026-11-28
slug: fix-p5-mint-node-side-token-create
branch: feat-one-shot-p5-mint-node-post
issue: 12931
---

# fix(cloudflare): Phase 5 p5-mint.js sends the token-create POST Node-side

## Overview

The committed Phase 5 mint body creates each Cloudflare token with an in-page `fetch` POST. In a signed-in
Soleur-account dashboard session on 2026-11-28 that request came back as an HTML 403 from the dashboard edge on two
keys in a row, while the body's in-page GETs succeeded. The body's own cleanup DELETE already goes through the
Playwright request context for the same reason. This plan moves the create POST onto that Node-side path, re-pins the
body, and teaches the runbook what an HTML 403 on a mint means.

## Research Insights

**Premise Validation.** #12931 is the open Phase 5 epic (Ref only). The body on `origin/main` hashes to
`6a8a8999d69158a5924408c87f1db0c300165b774312c58df6aeb4bb90a51898`, the value the failing sitting checked. The
collision pre-check names PR #12958 (the tunnel re-home); its file list carries no p5 body, so it is not a duplicate.
`p5-revoke.js` was read: its only in-page call is the GET list (`listInPage`); its DELETE is already
`page.request.delete`. So the defect is confined to one call site in `p5-mint.js`.

**Evidence.**

- Live, 2026-11-28 ~15:55Z, Soleur-account login, owner `account`: `{"refused":"mint","status":403,"contentType":"text/html","success":true,"matches":0}`
  for the PAGERULES key, then the AUDIT key. The permission-group GET and the token-list GET in the same run answered
  JSON 200 (the body got past both), so the session and its atok were good.
- `cloudflare-account-migration.md` `## Revoke recipe` step 3 (2026-11-26): an in-page `fetch` DELETE got an HTML 403
  from the dashboard edge, while the in-page user-token mint POST did not; `page.request.delete` with `x-atok` and
  `x-cross-site-security: dash` answered 200. The p5 bodies inherited that DELETE form.
- What differs between the 2026-11-26 POST that worked and today's: the endpoint (`/user/tokens` then,
  `/accounts/<acct>/tokens` now). The edge's reason is not observable from today's return (status and content type
  only).

**Files.**

- `knowledge-base/project/specs/archive/20261127-221105-feat-one-shot-12931-phase5-token-remint/p5-mint.js`, step 3
  (`posted = true; const mr = await call('POST', base, …)`): the only in-page write in any p5 body.
- `…/p5-browser.sha256`: the four-file pin manifest.
- `knowledge-base/engineering/operations/runbooks/cloudflare-old-login-token-remint.md`: the section 5 pin block
  (`p5-mint.js sha256=`), the section 6 PAGERULES hold (the one hold quoting the mint sha; the other two say
  "same sha256"), and the section 5 browser-returns row for `refused:"mint"`.
- `tests/scripts/test-cf-old-login-token-remint-browser.sh`: the run_code emulation. Its fake page answers an in-page
  DELETE with `html(403)` and has `page.request.delete` only; an in-page POST to a token endpoint succeeds there, which
  is why the suite was green on a body that fails live.

**Learnings.** `2026-11-28-my-late-atok-stub-could-not-see-a-wait-placed-before-the-goto.md`: a stub must model the
real page's behaviour or it cannot see the defect; the same lesson applies to the in-page POST here.
`2026-06-15-api-403-triggers-browser-not-operator-only.md`: a 403 is a reason to try another automated route, not a
reason to hand the step to the operator. No learning covers the dashboard edge's write refusals; this PR's compound
step adds one.

**Property List.**

1. A mint from a signed-in dashboard session reaches the token-create endpoint without the edge refusing it.
2. The token value still reaches only the 127.0.0.1 sink, and no return or log line carries it.
3. Every return shape, the read-back and the cleanup behave as today.
4. The suite fails on a body that writes in-page.
5. The runbook tells the next session what an HTML 403 on a mint means and what to do.

**Cut List.** None: the ask names one mechanism (Node-side POST) and it buys property 1, which no existing mechanism
covers for the create call.

## Files to Edit

- `knowledge-base/project/specs/archive/20261127-221105-feat-one-shot-12931-phase5-token-remint/p5-mint.js`: step 3
  reads the atok from the page, then sends the create POST with `page.request.post`; header comment updated.
- `knowledge-base/project/specs/archive/20261127-221105-feat-one-shot-12931-phase5-token-remint/p5-browser.sha256`:
  the new `p5-mint.js` hash.
- `knowledge-base/engineering/operations/runbooks/cloudflare-old-login-token-remint.md`: the section 5 pin, the
  section 6 PAGERULES hold's sha, the section 5 `refused:"mint"` browser-returns row.
- `tests/scripts/test-cf-old-login-token-remint-browser.sh`: the fake page refuses an in-page token write with an HTML
  403 and gains `page.request.post`; M1 asserts the POST went Node-side; a mutant restores the in-page POST; the
  exact floors move by the counts this adds.

## Files to Create

None (the plan and its spec directory only).

## Open Code-Review Overlap

None.

## Scope Check

| Ask | Plan item | Provenance |
|---|---|---|
| Route the create POST Node-side | p5-mint.js step 3 | stated |
| Check p5-revoke.js for in-page writes | Research Insights: none found, no edit | stated |
| CTO ruling on the value passing through Node | Decision Challenges | stated |
| Re-pin sha256 file, runbook, test | Files to Edit | stated |
| Runbook row for an HTML 403 mint | Files to Edit | stated |
| Test case: create POST is Node-side | M1 assertion + mutant | stated |

No split: one call site, one pin chain.

## Decision Challenges

Recorded in `knowledge-base/project/specs/feat-one-shot-p5-mint-node-post/decision-challenges.md` (N1-N5, ruled by
the CTO agent 2026-11-28). The one ruling not implemented is the `edge` return field: the directive keeps every
return shape unchanged.

## Implementation

1. `p5-mint.js`: a `postNode(path, body)` helper beside `inPage` (origin and atok read by one `page.evaluate`, then
   `page.request.post` with the two headers, `content-type: application/json`, `data`, `failOnStatusCode: false`,
   `maxRedirects: 0`, `timeout: 30000`; `json()` only on a JSON content-type; `dispose()` in a `finally`), same
   return shape as `inPage`. Step 3 calls it. The cleanup DELETE gains `failOnStatusCode: false, maxRedirects: 0`.
   Header FLOW, the header note on which requests are Node-side, and the `mint` RETURN line updated.
2. Re-pin `p5-browser.sha256` and the runbook's two `p5-mint.js` sha citations (section 5 block, PAGERULES hold).
   `p5-revoke.js` is unchanged, so the section 12 lines stay.
3. Runbook section 5 "after the POST" table: HTML 403 (edge refused the write; stop and post), JSON 403 (the login
   lacks the role; stop), other refusals (new sink, re-mint).
4. `cloudflare-account-migration.md` Revoke recipe step 3: one sentence recording the 2026-11-28 POST refusal.

## Test Strategy (Guard Contract)

The stub page answers an in-page POST or DELETE with `html(403)`, the edge's measured answer, and gains a
`page.request.post` that records the via, headers, `maxRedirects`, `failOnStatusCode`, `text()` reads and
`dispose()`. `nodeSidePost(w)` asserts all of them in M1, M10, M10b (new: a Node-side HTML 403 returns
`{refused:"mint",status:403,contentType:"text/html",matches:0,success:true}`) and M18a. M1 joins the scored rows.
Mutants XM12 (POST in-page again), XM13 (`maxRedirects` dropped), XM14 (answer read as text) each turn M1 RED.
Review round: M19 (the atok gone just before the POST -> `{atok:false}`, no POST; XM15 deletes postNode's atok guard) and a stub that refuses a body read after `dispose()` (XM16). Floors: full 250 -> 262, mutants 94 -> 104. Only this suite runs locally; CI runs the rest.

## Acceptance Criteria

- `bash tests/scripts/test-cf-old-login-token-remint-browser.sh` and `--mutants` exit 0 at the new floors.
- `sha256sum -c p5-browser.sha256` passes; every runbook `p5-mint.js` citation equals the new sha.
- No in-page write remains in any p5 body (`grep -n "call('POST'\|call('DELETE'" p5-*.js` is empty).
- The archived 2026-11-27 plan is untouched.

## User-Brand Impact

Brand-survival threshold: none. Operator-only runbook tooling; no user-facing surface. The one risk is a token value
escaping the sink path, which P-leak and the N2 must-haves guard.
