# Learning: a single TCP-open probe right after `docker run`/`restart` raced Squid's bind

## Problem
`egress-gateway-bootstrap.sh` probed `:8443` once, 1-5 ms after `docker run -d` / `docker restart`
returned. Both gateway terraform resources (`egress_gateway` on web-1, `..._web2`) failed every push
apply with `did not answer a TCP open post-bring-up`. The issue (#10003) framed web-2 as a port-22
timeout; that no longer reproduced, so the inherited framing was stale.

## Solution
Replace the one-shot probe (and the sibling 18 s retry from #10109, which merged first and was
rebased over) with a bounded poll, `wait_for_gw_tcp` (30 s, 1 s interval, 2 s per-attempt timeout).
On timeout `gw_diag` prints container state and the last 20 log lines. The log tail is written to a
PUBLIC Actions log, so it drops per-request decision lines (workspace id, requested host), masks
session-token paths and strips control bytes. The success line records `(attempt N)`, which measures
the real bind time on every green apply instead of guessing it.

## Key Insight
- `docker run -d` / `docker restart` returning means the container started, not that the service
  bound. Any readiness check after them must poll with a deadline.
- A diagnostic that dumps container logs into a public CI log is a data-exposure surface; redact by
  allowlisting what the service itself emits, not by hoping the log is benign.
- A 30 s budget is a ceiling, not a measurement; emit the attempt count so the next green run
  replaces the guess with data.
- Test by extracting the shipped function and running it against a loopback listener that opens after
  N seconds, rather than re-implementing the loop in the test.

## Session Errors
1. **Soleur skills were not loaded in the implementation session, so compound/ship were skipped** — Recovery: resumed via `/soleur:go` with compound then ship — Prevention: pipeline entry already mandates `soleur:go`; resume prompts should name the skill chain.
2. **Issue framing (web-2 port-22 timeout) was stale** — Recovery: re-measured from apply logs; only the TCP-open failure reproduced — Prevention: re-derive an issue's causal claim from the latest run log before planning on it.
3. **Brief premise stale: run 38229123048 had already finished failure, and the next apply takes the docker-restart arm, so no `egress_gw_bridge action=rebuilt` line** — Recovery: evidence criteria changed to two `OK: gateway up` lines plus `egress_gw_probe result=ok` per host — Prevention: check `gh run view` before copying evidence expectations from a brief.
4. **`scripts/test-all.sh --capacity` not executable** — Recovery: ran with `bash` — Prevention: invoke repo scripts through `bash` in plans.
5. **Ratchet count written as 62 -> 63 in plan and commit message; correct is 63 -> 64 (`BASELINE_DECLARED_PROBES=64`)** — Recovery: plan fixed, PR body states 63 -> 64, commit is not rewritten — Prevention: read the ratchet value from the file at commit time, not from the plan.
6. **Test-design review seat died** — Recovery: recorded as degraded coverage 11/12; a 47-row mutation battery stood in (45 killed, 2 equivalent survivors) — Prevention: none beyond recording degraded coverage honestly.
7. **Full test gate showed contention-only reds (git-data-runcmd-rehearsal apt budget, test-all-weight-drift C8 rc=4)** — Recovery: re-run alone if CI shows them — Prevention: run those two in isolation before blaming the change.
8. **Sibling PR #10109 merged first with a competing retry loop** — Recovery: rebased; the poll replaced its loop — Prevention: `gh pr list` for sibling PRs on the same file before starting.

## Tags
category: integration-issues
module: apps/web-platform/infra/egress-gateway-bootstrap.sh
