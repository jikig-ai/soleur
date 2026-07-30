---
title: The comment that named a cause was the cause of the misdiagnosis
date: 2026-07-30
issue: "#7071"
pr: 7071
tags: [incident, observability, documentation-drift, false-gate, tdd, vacuous-test]
category: bug-fixes
---

# The comment that named a cause was the cause of the misdiagnosis

## The headline

**A comment that names a root cause is a claim to verify, not a fact to route on.**

On 2026-07-29 the web-platform release for v0.244.1 built, pushed, and published green.
The deploy then died `image_pull_failed` and production sat undeployable for ~5h. The
investigation spent its entire diagnostic budget on a hypothesis it inherited from a
comment in this repo — a comment that had been *speculative when written* and was read as
*findings* months later.

The specific text, in `reusable-release.yml`'s zot-mirror step:

> "If the bridge keeps failing, the tunnel connector serving registry.soleur.ai may lack a
> private-net route to 10.0.1.30:5000 (#6416)."

Note the "may". It was a hypothesis. By the time it mattered, `#6416` had been closed —
web-2, the non-subnet-member connector that caused it, was retired 2026-07-17 (#6538) —
so the sentence described a mode that could no longer occur. But it was the only sentence
in the failing step that named a cause, so it became the diagnosis.

The actual cause was three minutes of timeline nobody looked at: a `terraform apply` in
the *same run* replaced the `github-actions-registry-push` CF Access service token at
15:57:52; the bridge ran at 16:01:14 with the stale value and got `websocket: bad
handshake`. Every `doppler_secret` carrying a token declares
`lifecycle { ignore_changes = [value] }`, so Terraform can replace a token and then report
"No changes" while the dead value keeps being served.

## Three ways the repo actively misled the investigation

### 1. A comment stated a refuted hypothesis as the likely cause

Covered above. The fix is not "write fewer comments" — it is that a cause-naming comment
carries an obligation. When the mode it describes is closed, the comment is a defect, and
closing the issue is not what closes the comment.

**Cheapest gate:** when closing an issue that a code comment names by number, `git grep`
that number and update or delete what it explains.

### 2. An empty `200` was read as a broken origin

`GET https://registry.soleur.ai/v2/` returns **HTTP 200 with an empty body**, and that is
**correct behaviour**. The tunnel ingress is `service: tcp://10.0.1.30:5000` — TCP-mode,
consumable only via `cloudflared access tcp`. A plain HTTPS GET is not the WebSocket
upgrade that stream requires, so nothing is ever proxied and Cloudflare answers alone. The
response says exactly one thing: whether CF Access accepted your credentials.

It was read as "Cloudflare is answering without a working origin", which pointed straight
at the refuted missing-route hypothesis and confirmed it. Two wrong signals agreeing feels
like corroboration.

The repo already documented this, in the bridge action's own header ("`tcp://`, NOT
`http://`"). It was one file away from the probe being run.

**The correct probe** bridges first, then speaks HTTP over the bridge — and a `401` is the
*healthy* answer, because it is zot's own auth challenge, which proves the request reached
the origin:

```bash
cloudflared access tcp --hostname registry.soleur.ai --url 127.0.0.1:15000 &
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:15000/v2/   # 401 or 200 = origin UP
```

### 3. The runbook instructed the operator to make it worse

`zot-registry-revert.md` told an operator, during an outage, to delete `ZOT_REGISTRY_URL`
so hosts fall through to GHCR — and reassured them the fallback registry is "always warm
and current". That was true when written. It is not now: GHCR's read PAT is revoked (401)
and the minter is disabled (403 `DENIED`). Following the runbook converts "zot is
degraded" into "nothing can pull at all".

**This is the sharpest class in the incident**, because a runbook is *instructions*, not
commentary, and it is read under time pressure by someone who has decided to stop thinking
and start following steps. A stale comment costs an hour; a stale runbook causes the
second outage.

**Generalisation:** when a capability is retired, the sweep is not "find code that calls
it". It is "find every document that *promises* it". Those live in runbooks, ADR mitigation
bullets, and principle registers — none of which any compiler or test suite reads.

## The structural lesson: a fallback nobody exercises is not a fallback

GHCR was still dual-pushed, so every dashboard showed images arriving. **Receiving is not
serving.** The read path had been dead since the PAT was revoked — **out-of-band, NOT as
the Phase-5 retirement step; Phase 5.5 has not run and #6122/#6500 are still open** — and
nothing noticed, because nothing read from GHCR while zot was healthy — a fallback is by
definition only exercised when the primary fails, which is exactly when you find out it
was dead.

The four-axis mitigation in ADR-096's cold-boot statement listed "automatic degrade to
GHCR" as axis 1. Of the four, it was the only one that provided *availability*; the other
three are all detection. So the moment axis 1 died, the mitigation was three ways of
finding out about an outage you cannot prevent — and nobody re-read the list.

**Gate:** an availability mitigation that is never exercised in the healthy path needs a
periodic liveness probe of its own, or it will be discovered dead at the moment it is
needed.

## Session errors — my own, in a PR about verifying claims

Recorded because all four are the same shape as the incident, and three were caught only
by machine, not by reading.

**1. I wrote the retracted claims into my own fix.** My first draft of the corrected bridge
message quoted both false claims verbatim in an explanatory comment ("the prior text said
X, which is wrong because Y"). That is well-intentioned and wrong: a false claim is
searchable from wherever it is written, and this step is precisely where a future reader
goes looking for a diagnosis. It also failed the PR's own AC10, which counts those
literals in that file. Fixed by describing the retracted claims without reproducing them.

**2. Two ACs counted bare tokens and failed against correct code.** AC5 asserted
`grep -cF 'needs.release.result' … == 2`; my implementation documents *why* that conjunct
is not redundant with `needs:` — the single most misreadable thing in the PR — so the
literal appears three times. Same for AC10. Both were re-anchored on syntax a comment
cannot produce (`^ +needs\.release\.result == 'success' &&`). This is
`cq-assert-anchor-not-bare-token` biting inside a plan whose own ACs were written to avoid
vacuity, which is the point: the discipline has to apply to the gate, not only to the code.

**3. My own regression test was vacuous, and only mutation found it.** The new post-copy
assertion has two arms: the tag resolves to the *wrong* digest, and the tag does not
resolve *at all*. My test for the second arm asserted rc + `mirror_reason=verify` — and
passed with the branch deleted, because an empty digest also fails the mismatch
comparison, so both arms produce the identical tuple. It went green for a property it
could not observe. Only the mutation battery (`if false` on that branch) exposed it. The
test now pins the *message*, which is the half with teeth — reporting "zot holds a
DIFFERENT image, zot has «empty»" when nothing is there is the same name-an-unmeasured-cause
defect this PR exists to remove.

**Rule: mutation-test any guard whose failure arms can produce the same observable.**

**4. The subshell trap, in a test I wrote to check a fail-closed property.** My detector
harness called `rc=$(run_sut ...)`, and `run_sut` set the artifact paths as globals.
Command substitution runs it in a subshell, so every effect except stdout was discarded:
all 8 cases "failed" with `grep: : No such file or directory` — a verdict about the SUT
produced by a harness that could not find its own output. A function that both returns a
value and sets caller-visible state cannot be called that way. This is a documented rule
in `AGENTS.rules.md` and I hit it anyway.

**5. I read a contention false-RED as a regression.** My first full `ci-deploy.test.sh` run
reported 9 failures. `/tmp` — a machine-global 4 GiB tmpfs shared with every sibling
worktree — was at **100%**, because a sibling session's mutation battery was holding
2.1 GB. Eight of the nine failures were that; a re-run with headroom gave 187/188 with only
my intended RED. Had I not re-run, I would have "fixed" eight phantom regressions.
`test-all.sh` now self-identifies this (`SIBLING_RUN_DETECTED` / `LOW_TMP_HEADROOM`
banners), but `ci-deploy.test.sh` invoked directly does not — so the discipline is on the
reader: **three runs of an unchanged tree giving three different failure sets is a harness
defect, never a result.**

Related: I nearly deleted the sibling's 2.1 GB directory to reclaim space. Checking first
showed it had been created *one minute earlier* — it was live, and its owner was already
cleaning it up. `/tmp` is shared; another session's scratch is not yours to reap.

## What shipped

- The CI zot mirror is release-blocking, with a positive `crane digest` assertion that the
  tag resolves to the digest this build pushed.
- `needs.release.result == 'success'` on `migrate` and `deploy` — without it the gate
  protected nothing, because both jobs lead with `always() &&` and gated only on outputs.
- `mirror_reason` per failure stage, and three operator messages that name a cause, a
  remedy, and the fact that a blocked release is an unpublished draft that is safe to
  re-run.
- The token-drift detector's enumeration fixed (it could not match the key its own header
  cited) and actually invoked — twice daily plus a release preflight.
- The false claims deleted from the code, the runbook, ADR-096, ADR-088, AP-016, and three
  `model.c4` descriptions.

## See also

- ADR-096 amendment 2026-07-30 (clauses a–h), especially (c) — why restoring a GHCR
  credential is *structurally* unavailable, not merely dispreferred.
- [[2026-07-27-my-refutation-measured-a-shim-and-my-safe-fixture-hid-12240-deletions]] —
  measuring with the wrong instrument and believing the result.
- [[2026-07-19-my-own-mutation-battery-was-the-false-confidence]] — the sibling of session
  error 3.
