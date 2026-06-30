---
title: "Residual egress-blocked drops were an intended-by-design drop; identify anycast hosts by exact-IP, not the default TLS cert"
date: 2026-06-29
category: bug-fixes
module: cron-egress-firewall
issue: 5676
related: [5199, 5413, 5691, "ADR-052"]
tags: [egress, observability, anycast, dns, diagnosis, intended-drop, false-premise]
---

# Learning: a "residual drops persist" bug was the firewall working as designed — and IP→host on shared anycast must be exact-IP-matched, never default-cert-inferred

## Problem

Issue #5676 reported that the ADR-052 container egress firewall kept firing
`egress-blocked` to a Cloudflare `104.16.x.34` pool after the #5413 grace-window
retention fix, and framed the remediation as: identify the one missing host, then
**either allowlist it (Branch A) or reconsider the IP-allowlist per ADR-052**. The
plan (5 deepen agents) adopted Branch A (allowlist the host) as most-likely.

Both the issue and the plan were wrong about the shape of the bug.

## Root cause (two independent mistakes the framing baked in)

1. **The dominant drop was INTENDED.** `104.16.x.34` = `registry.npmjs.org`. The
   cron-spawned `npx @playwright/mcp` does a spawn-time registry-metadata dial, and
   #5199 *deliberately* keeps `registry.npmjs.org` OFF the allowlist so the package
   resolves to the image-baked dep instead of a runtime supply-chain fetch. The
   firewall dropping that dial is the control working as designed; the cron proceeds
   on baked deps. The plan's Branch A (allowlist it) would have **reversed** #5199 and
   widened the supply-chain boundary. The post-mortem's "104.x hits trend to zero"
   recovery criterion was **unsatisfiable by design** — npx always attempts the dial.

2. **The single Sentry issue grouped MULTIPLE distinct hosts.** The emitter
   (`cron-egress-resolve.sh`) tags every drop `op=egress_blocked` with no per-DST
   grouping, so one issue conflated the intended npm probe with sporadic
   un-enumerated telemetry/MCP hosts (`mcp.vercel/cloudflare/stripe`, a GCP Datadog
   vhost). "The one residual host" never existed.

## Solution

- **Diagnosis, not a code-from-plan.** Read the LIVE Sentry event — the issue body's
  IP list was stale (it said `104.16.x.34`; the latest event was a GCP `34.x` IP).
  Pull the DST distribution across ~100 events to see the real grouped set. Identify
  each anycast host by **exact-IP DoH match** (resolve every codebase egress host via
  `8.8.8.8` + `1.1.1.1`, match the blocked IP) + **TLS-SNI cert** — `registry.npmjs.org`
  → the exact `104.16.{0..11}.34` pool; SNI on `104.16.1.34` → `CN=npmjs.org`.
- **Silence at source, don't allowlist.** Add `env: { npm_config_prefer_offline: "true" }`
  to the cron's npx MCP config so npx uses the baked cache and skips the dial when
  cache-warm. `prefer-offline` (not `offline`) degrades gracefully on a cold cache.
- **Reframe the health criterion per-identified-host**, and REJECT emitter DST-IP
  suppression (a `104.16.0.0/13` mute would self-blind a genuine future gap to another
  Cloudflare-fronted host). Amended ADR-052; #5691 tracks the still-blocked sporadic
  hosts (correct posture: blocked).
- **Route the binding call to the CTO agent.** The plan-vs-code contradiction +
  security-boundary trade-off is an architecture decision (per the /work hard gate),
  not an operator or solo call.

## Key Insight

**On shared anycast / global-LB ranges (Cloudflare `104.x`, GCP `*.bc.googleusercontent.com`),
the IP does NOT identify the customer, and the DEFAULT TLS cert returned for a
non-matching SNI is whatever zone is primary on that shared IP — NOT proof of who
dialed it.** I attributed `34.149.66.137` to "Datadog" from its default `*.logs.us5.datadoghq.com`
cert; review correctly challenged it. The sound disambiguation is:
(a) resolve each *candidate* host (especially allowlisted ones) and confirm whether its
pool contains the exact blocked IP, and (b) send the *candidate's own* SNI and check
the returned cert is that host's. Proof here: `api.stripe.com` (allowlisted) →
`.21/.101/.221` only, never the blocked `.161/.231` (those are `mcp.stripe.com`);
`hn.algolia.com` → `34.160.168.181` only, never `34.149.x`. Apply the same
shared-anycast caution to GCP that you already apply to Cloudflare.

Corollaries:
- **A "residual drops persist" report is not automatically an allowlist gap.** A
  default-drop control firing steadily can be *correct* (an intended probe that
  falls back gracefully). Before adding a host, grep for why it's *deliberately* off
  the allowlist (`#5199`-style comments) — the fix may be to silence the dialer, not
  widen egress.
- **A grouped observability alert (no per-DST grouping) conflates classes;** recovery
  criteria must be per-identified-host, never a raw count→zero on the grouped issue.
- **Don't trust an issue body's "current" telemetry values** — read the live event.

## Session Errors

- **Plan/issue mis-framed an intended drop as an allowlist gap** — Recovery: read the
  #5199 comment in `cron-ux-audit.ts` proving the drop is deliberate; routed the
  binding fork to the CTO agent. Prevention: for "residual drops" reports, grep the
  dialer for a deliberate-off-allowlist rationale before adopting a "Branch A
  allowlist" plan (now in the `cron-egress-blocked.md` runbook §"Intended-by-design drops").
- **Attributed a shared-LB IP by its default TLS cert** — Recovery: re-probed with
  per-host SNI + exact-IP DoH of the allowlisted candidates; review agents flagged it
  first. Prevention: never identify an anycast/global-LB host by the default vhost
  cert; exact-IP-match or per-host SNI only (now in the runbook).
- **(one-off) Test co-location regex `{0,400}` span too tight** — Recovery: switched to
  exact-literal, then a whitespace-tolerant regex per test-design review. Prevention:
  prefer whitespace-tolerant structural regexes over fixed-distance spans when a
  comment can sit between anchors.
- **(one-off) Residual table self-referenced #5676 instead of the #5691 tracker** —
  Recovery: code-quality review agent caught + fixed. Prevention: when a doc both *is*
  issue #N and *files* follow-up #M, cite #M for the open work.

## Tags
category: bug-fixes
module: cron-egress-firewall
