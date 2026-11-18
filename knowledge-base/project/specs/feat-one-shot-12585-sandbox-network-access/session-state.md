# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-18-fix-sandbox-network-access-canusetool-arm-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- cto_spawns=0 (post-plan; planning-phase CTO rulings recorded in decision-challenges.md, gate PASS 44 rows)

### Errors
Planning hit technical-ruling-gate and filing-hook retries, all fixed (see plan subagent summary).

### Decisions
- One pure `decideSandboxNetworkAccess`, first branch of createCanUseTool; deny order not-entitled, egress-not-running, malformed-host, loopback-literal, no-proxy-match; else allow.
- Phase 1a hard go/no-go on SDK 0.3.321 that the allowed traffic transits the forwarder; on failure the arm denies all with `gateway-unverified`.
- Observability: pino on every deny, Sentry deduplicated per Query, Better Stack alert on granted-but-degraded denies.
- Toggle-off tears down forwarders on the serving host; cross-host handled in #12903. Deferred: #12902, #12904.

### Components Invoked
soleur:plan, soleur:gdpr-gate, soleur:plan-review, soleur:deepen-plan; CTO, CPO, CLO agents; review panel.

## Operator Constraints
- Never ask the operator technical questions; CTO rules technical forks, CLO legal, CPO product.
- Production dispatch (gh workflow run against prod, flag flip, writes to a production synthetic workspace) needs the operator's explicit go-ahead, named as one plain ACTION. Merging through normal ship gates is in scope.
- Hosted checks use a synthetic principal only; never ask the operator to look at a page or paste logs.

## Work Phase — Phase 1a go/no-go (2026-11-18, SDK 0.3.321, netns harness, allow-all tap)
- Result: NO-GO (per-host cached allow). Design = row 6' deny-all `gateway-unverified` for entitled sessions (AC22).
- control: allow-all with no egress env hit every decoy (198.51.100.1:443/:80/:22, 127.0.0.2:p, 169.254.169.254:80). Sandboxed NO_PROXY is SDK-set: localhost,127.0.0.1,::1,169.254.0.0/16,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16 (so decoy moved to TEST-NET-2 198.51.100.1). SOCKS bridge rides ftp_proxy=socks5h://...@localhost:1080.
- B PASS: 9/9 connections (HTTPS name/IP, plain HTTP absolute-URI, SOCKS name/IP :22, link-local IP and name) at recording gateway with session Basic workspaceId:token; 0 decoy hits. Input keys exactly ["host"], host bare (no port); EXAMPLE.TEST. reused the example.test allow (SDK normalizes).
- D PASS: CLI API traffic to api.anthropic.com (hosts-file 10.0.0.2) reached stub directly, 0 gateway records.
- E PASS: forwarder SIGKILLed before turn -> 502, 0 decoy, 0 gateway.
- F FAIL (criterion "re-ask after teardown"): within one command no re-ask after teardown (f-2/f-3 502, nothing left). F2: across commands of one session, the same host is NOT re-asked; a new host is. Cached allows fail closed at the dead forwarder (no leak), but the plan pre-decides caching => deny-all.
- CLO DPIA t4 re-screen and CPO copy for (reason, granted) spawned.

## Work Phase Complete (2026-11-18)
- Commits 76ac3b2672, cf4f439fe2 pushed; PR #12897 body set (Closes #12585).
- Issues filed: #12906 (real allow arm), #12907 (UNVERIFIED:hosted-entitled-sandboxed-egress).
- Local affected gate: timed out at 590 s (RC=124, NOT a pass); targeted suites green; CI is the gate.
- Next: soleur:review -> resolve -> qa -> compound -> ship.

## Review phase (in progress, 2026-11-18)
- PANEL_SHA=5272dd01fc1bd2ad7e5c6836268a3171c224f639. Seats are report-only; reports land in the session scratchpad as review-<seat>.md.
- Design pass (simplicity + architecture) done. Both found K1: toggle-off reports egress-not-running with granted=true, so the alert pages and the model gets false copy. Architecture also found K2: the globalThis registry is unpinned.
- K1 contests D2 and the CPO copy ruling. Send it to the CTO in ONE batched spawn at synthesis (cto_spawns used: 0 of 2).
- Panel of 11 spawned. Next: synthesis, then the coverage consult (single-user incident), CTO batch, inline fixes, the trailer, and Step 5.
