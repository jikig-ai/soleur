---
module: web-platform release pipeline
date: 2026-10-19
problem_type: observability_gap
component: web-platform-release.yml + cat-deploy-state.sh peers merge
symptoms:
  - "~25 days of release runs reported success over a half-failed fleet: web-2's async exit-1 reached no channel"
  - "The deploy job's two verdicts are both web-1 answers — web-1's deploy-status file and the LB /health answered by weight-1 web-1; weight-0 web-2 is invisible to the run result"
  - "ADR-068 constraint (c)'s per-host verification was recorded months earlier and never built — a recorded-but-unimplemented design reads as decided until it fails"
root_cause: acceptance_read_as_verdict
related_issues: [8743]
related_prs: [10577]
related_learnings:
  - knowledge-base/engineering/operations/post-mortems/2026-10-19-web2-plugin-mount-fchmodat2-postmortem.md
  - knowledge-base/project/learnings/2026-03-21-async-webhook-deploy-cloudflare-timeout.md
  - knowledge-base/project/learnings/2026-08-20-the-channel-was-silent-on-the-path-it-was-built-for.md
tags: [async-fan-out, 202-accept, fail-closed, deploy-verdict, peers-merge, adr-068, transport-vs-credential]
---

# The fan-out proved acceptance, not the verdict — and the release gate read only web-1

## Problem

`deploy-peer` returns HTTP 202 on spawn-acceptance; the peer's ASYNC exit-1 went to no
channel, so for 25 days every release's web-2 leg aborted while the run reported
success. The two verdicts the `deploy` job reads — web-1's `/hooks/deploy-status` file
and the load balancer's `/health` — are both answered by web-1 (weight 1); a weight-0
standby's failure had no path to the run result by construction. ADR-068 constraint (c)
recorded the private-net peer-verification design and it was never built. The
notification pattern itself was born in #963/#967: webhooks go async precisely because
the Cloudflare edge cannot hold a synchronous deploy (2026-03-21 learning) — async
bought the timeout fix and silently dropped the verdict.

## Solution

Three parts, per CTO ruling 2026-10-19 (fail-closed — a warn-only arm reproduces the
exact silent-failure class this exists to kill; `ok_peer_fanout_degraded` precedent):

1. **Persist the effective peer set.** `ci-deploy.sh` `write_state`/`final_write_state`
   write `fanout_peers` = effective `SOLEUR_DEPLOY_PEERS` minus this host's own IPs —
   the SAME filter `fan_out_to_peers` applies. Absent on `deploy-peer`-received runs so
   the merge is inert on a peer and cannot recurse. Fail-safe: an EMPTY self-IP probe
   persists NO list rather than an unfiltered one (a persisted self makes the merge poll
   the host's own hook — self-slot recursion). The list is webhook-payload-derived and
   JSON-escaped via `jq -Rs`.
2. **Merge peer status on the existing edge.** `cat-deploy-state.sh` `peers_json()`:
   per peer, HMAC-signed GET `http://<peer>:9000/hooks/deploy-status` over the private
   net — empty-body signature, secret scoped to `id=="deploy-status"`'s
   `payload-hmac-sha256` rule (never a sibling hook's first-match secret),
   `curl --max-time 3 --max-filesize 1048576`. Fetches run in PARALLEL into per-peer
   slot files (serial N×3s exceeded the caller's `--max-time 10`). Slot taxonomy:
   `{"error":"unreachable"|"http_<code>"|"not_json"|"bad_peer"|"unsigned"}` — `bad_peer`
   for a non-`^[0-9.]+$` token (payload-derived state never reaches curl's URL position)
   and `unsigned` when web-1 could not sign. Merged as TOP-LEVEL `.peers`, absent when
   `fanout_peers` is absent; a mid-loop failure can never turn the hook non-200.
3. **Fail-closed gate.** New `verify-peer-deploy` job
   (`needs: [resolve-target, deploy]`, own `timeout-minutes: 90`,
   `if: always() && needs.deploy.result == 'success' &&
   needs.deploy.outputs.superseded != 'true'` — a superseded deploy completes green
   having shipped nothing and must not burn the peer budget). Expected peers =
   `WEB_HOST_PRIVATE_IPS` minus the ingress host `10.0.1.10` — DERIVED, never hardcoded,
   so a future web-N joins the guard automatically (two literal copies pinned identical
   by `web-hosts-fanout-parity.test.sh` + `web-platform-release-peer-gate.test.sh`).
   Each peer must reach `exit_code==0 && tag=="v$VERSION"` within the peer's own 4800s
   deploy window; single-host fleet is vacuously green (ADR-068 dormant path).

**The error taxonomy is the design.** A 13-seat panel converged on: *transport-class
errors are observations of the channel, not verdicts.* `unreachable`/`http_*`/`not_json`
and absent slots are web-1's observation of the read — a slow-but-healthy peer answering
inside `--max-time 3` mid-deploy would burn a good release on a first-glance transient —
so they read UNRESOLVED and poll to budget-exhaust, THEN `::error::`+exit 1. `unsigned`
is TERMINAL on first sight: a credential/hooks.json defect cannot heal inside the poll
budget. `PEERS_KEY` distinguishes "web-1's `cat-deploy-state.sh` predates the merge"
(key ABSENT — delivery pending, cold-start ordering) from "slots present but
unresolved" in the terminal message, so the first gated release names its own cause
instead of burning ~80m to an opaque red.

## Key Insight

A fan-out proves acceptance; the verdict is a second, asynchronous fact that someone
must collect — and a gate that verifies only the fan-out origin reads as green over a
half-failed fleet forever. For a fail-closed poll, classify every read failure before
writing the loop: channel-observation (poll it) vs identity/credential (exit on first
sight) vs exhaustion (the terminal catch-all). The panel's convergent phrasing —
transport errors are *observations of the channel*, and only the channel — is the rubric
to reuse.

## Session Errors

Topical subset (full inventory lives in the sibling docker-cp learning):

1. **Serial N×3s peer curls exceeded the caller's `--max-time 10` bound.** Recovery:
   parallel `_peer_fetch` into per-peer slot files under a mktemp dir. **Prevention:** a
   merge loop's serial worst case must fit its CALLER's budget — bound wall-clock by the
   slowest peer, never by the sum.
2. **A persisted `fanout_peers` could have contained self** (empty `ip -4 -o addr` probe
   → unfiltered list → the merge polls the host's own hook). Recovery: empty probe
   persists NO list. **Prevention:** a filter that depends on a probe must define the
   probe-empty case, not inherit it.
3. **Peer-supplied fields reached workflow annotations raw** — a `\n` in `.error`/`.tag`
   line-splits a forged `::error::`. Recovery: safe-alphabet strips at extraction
   (fix-round b9282ef3b0). **Prevention:** strip remote-supplied fields where they are
   read, before any workflow command line (full rule in the sibling admission-rules
   learning).
4. **The peer poll's first home was inside `deploy`'s 90m ceiling** — serial worst case
   ~160m. Recovery: separate `verify-peer-deploy` job. **Prevention:** a serial second
   wait gets its own job (`needs:` + `timeout-minutes`); sum serial predecessors before
   reusing an incumbent ceiling (sibling admission-rules learning).

## Recurring-vs-one-off triage

| item | recurring? | disposition |
|---|---|---|
| acceptance-read-as-verdict (202) | recurring | this learning + constitution promotion |
| self-in-peer-list on empty probe | recurring | fixed inline (empty probe → no list) |
| serial peer reads vs caller bound | recurring | fixed inline (parallel slot files) |
| unsigned static-HMAC trust (replayable empty-body token) | recurring, security-sensitive | file-tracked per panel DEFER+ISSUE; accepted private-net posture documented in code + ADR-068 note |
| cold-start: pre-merge peer lacks `.peers` | one-off (self-resolves at delivery) | terminal message distinguishes key-absent |

## Route to definition

No plugin edit applied — `knowledge-base/`-only write boundary. Candidate bullet for the
deploy skill/reference surface: "an async fan-out verdict needs a persisted expected-peer
set and a fail-closed per-peer gate; classify read failures as channel-observation
(poll) vs credential (terminal) before writing the loop." The reason taxonomy already
landed in `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`
(in-branch) and ADR-068's implementation note was amended in-branch.

## Related Issues

- Issue #8743, PR #10577; postmortem:
  `knowledge-base/engineering/operations/post-mortems/2026-10-19-web2-plugin-mount-fchmodat2-postmortem.md`
- Same defect class: `2026-08-20-the-channel-was-silent-on-the-path-it-was-built-for.md`;
  the async pattern's origin: `2026-03-21-async-webhook-deploy-cloudflare-timeout.md`.
