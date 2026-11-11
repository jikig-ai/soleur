---
title: "An egress-injector plan must read the env, the RPC and the auth scheme before drawing the topology"
date: 2026-11-09
category: integration-issues
module: apps/web-platform egress / approval
issue: 12517
tags: [egress, injector, approval, planning, sandbox]
---

# Learning: an egress-injector plan must read the env, the RPC and the auth scheme before drawing the topology

## Problem

Planning #12517 (a measured TLS-terminating credential injector for GitHub on the agent egress hop), the first full draft passed premise validation, domain review, an advisor consult and a flow analysis, and still carried six defects that a seven-seat plan review found by reading code the draft had only described:

- Production `buildAgentEnv` (`server/agent-env.ts`) lists `github.com,*.github.com` in `NO_PROXY`, so GitHub traffic from entitled sessions never reaches the proxy. An injector on the hop sees none of it until that changes.
- git authenticates to GitHub with HTTP Basic `x-access-token:<token>` via `GIT_ASKPASS`. A placeholder inside a base64 Basic header cannot be substituted literally.
- `consume_approval` takes a row id, not a hash; the working order is `create_approval_request` (returns the existing live row) then `consume_approval(id, hash, conversation)`, as `server/approval/service.ts` does. Rejected and expired rows are invisible to `create`, the TTL floor is 60 s, and a conversation holds at most 5 pending rows.
- A suite in `PRIVILEGED_WHY` must be a `sudo bash` step of `deploy-script-tests-fixed` (15-minute cap); a long privileged spike belongs under `apps/web-platform/test/infra/` with its own job.
- File tools (`Read`, `WebFetch`) run in the CLI process outside bwrap as the same uid, so "a file outside the sandbox's view" is readable by them unless the path is masked.
- The brainstorm's "about 41 files per gated write tool" was unsourced; `git show --name-only d6f590a14f` measures 36 (9 source).

## Solution

The plan was revised under 23 binding CTO rulings (`knowledge-base/project/specs/archive/20261110-211546-feat-agent-runtime-sandbox-eval/decision-challenges.md`): measure arm A with the exact `buildAgentEnv` output and arm B with the inject hosts removed from `NO_PROXY` (labelled #11637's change); replace the whole `Authorization` header on inject hosts rather than substituting inside it; follow `service.ts`'s create-then-consume order with a fresh conversation per arm; place the suite under `test/infra/` with a dedicated job; mask every secret's path and probe it from the CLI tier with scripted tool calls and a same-uid positive control; compare criterion 7 against the measured 9 source files.

## Key Insight

For a design that sits on an existing hop, the facts that decide feasibility live in four places the design document does not: the env the session actually gets, the exact signature of the RPC it must call, the auth scheme each client actually sends, and the gate that registers the test. Read each one (one grep or one file each) before drawing the topology. Descriptions of these surfaces in ADRs and brainstorms were accurate about intent and silent about these details.

## Session Errors

1. **Inherited an unsourced baseline (41 / 14 files) from the brainstorm.** Recovery: measured from git (36 / 42). Prevention: a count copied from a sibling artifact is re-derived with the command that produced it before it enters a criterion.
2. **Planned literal placeholder substitution without checking git's auth scheme.** Recovery: CTO R8, whole-header replacement; tracer item 5. Prevention: for any credential-carriage design, read how each client sends the credential today (`agent-env.ts` `GIT_ASKPASS`) before choosing the carrier.
3. **Prescribed `consume_approval` by hash.** Recovery: Kieran review; create-then-consume order. Prevention: read the RPC's signature and its existing caller (`service.ts`) before writing a call order.
4. **Placed a privileged suite outside the job the registration gate requires.** Recovery: CTO R12, suite under `test/infra/`. Prevention: run `.github/scripts/test/test-infra-suite-registration.sh` rules against the planned path at plan time.
5. **Missed that production `NO_PROXY` bypasses the proxy for GitHub.** Recovery: architecture review; CTO R11 arms A and B. Prevention: a hop design reads the session env builder for every host it intends to intercept.
6. **Missed same-uid file tools outside bwrap despite an existing learning.** Recovery: CTO R9/R10, masked paths and CLI-tier probes. Prevention: the learnings researcher surfaced the learning; the plan must turn each surfaced learning into a criterion, not a citation.
7. **Read of the sharp-edges catalogue exceeded the per-call token cap.** Recovery: smaller page limits. Prevention: page that file at about 60 lines.
8. **Ran `lint-encryption-posture.py` with a positional path it does not accept.** Recovery: none needed (section skipped). Prevention: read a lint's `--help` before invoking it.
9. **A research subagent left a downloaded file (`gitprotocol-http.adoc`) in the worktree root.** Recovery: inspected and removed before commit. Prevention: research agents save downloads under the session scratchpad, never the working tree (routed to the agent definition).
10. **ADR-323 was claimed on main the same day.** Recovery: probed all `origin/*` refs; ADR-325. Prevention: already covered by the ship ordinal gate.

## Tags

category: integration-issues
module: apps/web-platform egress / approval
