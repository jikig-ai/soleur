# Hosted Bash outage follow-ups: re-scope and sequence (2026-10-31)

Tracker: #10455 (open). Siblings: #10477, #5941, #10548, #10549, #10604, #11085. Draft PR: #11689.

## What We're Building

A re-scoped, sequenced plan for what is genuinely still open after the hosted Bash outage (#10445). The request listed 14 unchecked items on #10455. Verified against GitHub and main on 2026-10-31, most of the headline items have shipped, so the real remainder is smaller and differently ordered.

## Premise corrections (verified)

| Claim in the request | Reality |
|---|---|
| Runtime synthetic with dead-man arm is open (P2) | Shipped in #10697 (merged). Journal on web-1 and web-2: `verdict=pass reason=ok`. |
| Own AF_UNIX deny is open | Shipped as a second seccomp artifact behind flag `agent-sandbox-unix-deny` (default OFF) in #10546. Enabling is an operator-typed write (#10548). |
| Slack wake path unverified | Still true. Alerts, including `masked-dir-precreate-failed` (#10892), are email-only. |
| #5941 nested-unshare probe is open | Superseded. The deploy-time SDK Bash smoke (#10453, #10546) runs a real Bash call through the real SDK, shim and production tuple; the CLI performs the nested split. ADR-079 already calls #10453 "the successor to #5941". |
| #10477 waiting on the operator | Decided 2026-10-31 (below). |

## Key Decisions

1. **#10477: send nothing, no aggregate count (operator, 2026-10-31).** Advice was the narrow option (CPO, CLO: no legal duty to notify, aggregate count clearable, personal note only if real external users). The operator chose the lowest-effort option. Consequence accepted: we will not learn whether any external user was affected. Support requests are answered individually. Revisit only if hosted launches publicly (homepage CTA review #9588, 2026-11-03).
2. **Close #5941 as superseded by #10453/#10546** (CTO ruling). Comment the reasoning when closing.
3. **#10548 soak is met** (179 consecutive passes over 10 days, coverage `sdk_wrapper_shim_prodtuple`, 0 infra errors). Still owed before promotion: alert-flap review and canary `memory.peak`/`oom_kill` record.
4. **Batching (CTO ruling, `Ref` not `Closes` on #10455/#10548):**
   - PR 1 (highest user impact): measure what a sibling tenant can reach of persisted CLI output; fix the `op=tenant-deny` emit (Error first argument drops the tagged capture, #8629 class); derive the deny set from `agentEnv` with a test. A leak becomes a P1 Art. 32 finding routed to the CLO.
   - PR 2: promote the smoke to blocking (remove `|| true`, add red-verdict-to-rollback), delete the `faithful_canary_sandbox_broken` alert. Needs the flap review and memory record attached.
   - PR 3: plain-language Bash-failure message on top of `classifyBashSandboxFailure`; classify other helper steps (prctl/seccomp EPERM); test-hardening ride-alongs.
   - PR 4 (optional): verify the ADR-260 Slack wake path. Confirm `betterstack_paid_tier` first.
5. **Plain-language message is copy-only on the existing tool-error row** (CPO): no new screen, no wireframe required unless a Retry button is added. Map only sandbox-setup failures; keep raw text behind a details disclosure.
6. **Housekeeping (CLO):** add a negative-determination row for #10445 to `knowledge-base/legal/breach-register.md`. Basis: "commands never executed; no exposure mechanism identified". Do not write "no data affected".

## Parked (re-evaluation trigger)

- #10549 AF_UNIX deny for egress sessions: SDK bump turns vendored-argv pins red, an egress socket incident, or egress becoming the majority.
- #10604 flag cohort and variant-EPERM signal: first tenant AF_UNIX EPERM report, or a proposal to leave the flag ON unattended or default-on.
- Legacy agent-runner tool_result observer: when `agent-sandbox-unix-deny` goes ON.
- Page on 2+ distinct users: observed noisy-tenant suppression.
- SOCKS proxy-auth probe, peer-messaging auth, `--pids-limit`: no incident behind any; re-evaluate on an incident or an SDK change to proxy socket selection.
- #11085 (remove `agent-auth-failure` alert): independent, out of scope here.

## Operator authorizations still needed (actions only)

- Merge and ship PR 2 (changes the deploy rollback lane).
- Create and enable `agent-sandbox-unix-deny` in production (#10548, operator-typed write; do not bundle).
- Close #10455, #10548 and #5941; remove the `follow-through` label from #10548.
- Any user outreach if PR 1 finds a leak (brand and legal decision, CLO owns it).

## User-Brand Impact

- **Artifact:** the hosted agent Bash sandbox, its alerts, and the user-visible Bash failure message.
- **Vector:** a cross-tenant read of persisted CLI output, or a sandbox regression that goes unalerted and leaves users with a raw error again.
- **Threshold:** `single-user incident`.

## Lane

cross-domain (set unconditionally by Phase 0.1).

## Open Questions

- Does the tool-name field in conversation metadata allow a content-free Bash count? Moot while the count is declined.
- Is `betterstack_paid_tier` set? Determines whether PR 4 is code or a plan-tier question.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering

**Summary:** Close #5941 as superseded; soak for #10548 met; four-PR batching ordered by user impact; parked items carry triggers.

### Product

**Summary:** No broadcast; audience is probably zero to a handful (alpha is self-hosted). The plain-language message is the best user-facing item, small, copy-only.

### Legal

**Summary:** No Art. 33/34 duty (no personal data exposed); no SLA or credit commitment in the ToS (§10.2); an aggregate count was clearable; wording must avoid "no data affected".

## Session Errors

- The request's "14 unchecked items" and "synthetic open" were stale against the issue's own comment trail; caught by the premise probe.
