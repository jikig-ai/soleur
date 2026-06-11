---
title: "feat: Harden waitlist Buttondown subscribe against firewall re-escalation by proxying the visitor's real IP"
type: feat
date: 2026-06-11
lane: cross-domain
---

# feat: Harden waitlist Buttondown subscribe against firewall re-escalation by proxying the visitor's real IP

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed; no `knowledge-base/project/specs/feat-one-shot-waitlist-buttondown-client-ip/spec.md` exists).

## Enhancement Summary

**Deepened on:** 2026-06-11 (inline pass — one-shot pipeline subagent, no Task fan-out available)
**Gates run:** 4.5 network-outage deep-dive (telemetry emitted), 4.6 User-Brand Impact (pass — `aggregate pattern`), 4.7 Observability (pass — 5/5 fields, no placeholder, no ssh), 4.8 PAT halt (pass — no matches), 4.9 UI wireframe (pass — no UI surface)

### Key Improvements

1. **Empirical validation of the prescribed `plausiblePublicIp` shape** — the exact regex + `node:net` `isIP` logic from Proposed Solution was live-executed on node v24.15.0 against 26 fixture cases (public v4/v6, `"unknown"`, garbage, empty/undefined, all private/reserved v4 ranges incl. CGNAT boundaries 100.64.0.1/100.127.255.255 reject + 100.128.0.1 accept and 172.31 vs 172.32, v6 loopback/unspecified/link-local/ULA, v4-mapped-v6 both public and private, leading/trailing whitespace): **ALL 26 PASS**. The /work phase implements a verified shape, not a hypothesis.
2. **Verify-the-negative pass** — every negative claim in the plan checked against current source: status-only logging confirmed (`waitlist.ts:115` logs `{status}` only; `route.ts:76` mirrors `{feature, op}` only); no `runtime = "edge"` export on the route (Node runtime, `node:net` available); `node:` builtin import precedent confirmed (`server/workspace-invitations.ts:1`); `bypass-firewall` token absent from `apps/**`.
3. **All cited AGENTS.md rule IDs verified active** (`cq-test-fixtures-synthesized-only`, `cq-write-failing-tests-before` — both in AGENTS.md index); all cited KB file paths Glob-verified (sole intentional exception: the spec.md the lane note declares absent).

### New Considerations Discovered

- Whitespace handling: `plausiblePublicIp` must `trim()` its input (empirically confirmed `" 1.2.3.4 "` → `"1.2.3.4"`); the route's extraction already trims, so this is defense-in-depth for direct callers.
- The rate-limit key and the forwarded IP intentionally share one extraction (`route.ts:41`) — do not fork them during implementation; a divergence would let the throttle and the Buttondown scoring disagree about who the visitor is.

## Overview

Prod waitlist signups failed with `subscriber_blocked` 400 from Buttondown (Sentry WEB-PLATFORM-2F, resolved 2026-06-11) because Buttondown's account-level Firewall was in `aggressive` auditing mode (blocks risk ≥ 0.5) and API-sourced subscribes from the Hetzner server IP score 0.6. The operator already remediated prod by PATCHing the newsletter's `auditing_mode` to `enabled` (blocks ≥ 1.0); prod `POST /api/waitlist` returns 200 end-to-end. **Root cause is diagnosed and closed — this plan does NOT re-litigate it.**

Residual risk this PR closes: Buttondown's "attack mode" can automatically flip the account back to `aggressive` when spam patterns are detected, which would silently re-break ALL signups (server-IP-sourced subscribes score 0.6 ≥ 0.5). Buttondown's documented mitigation is to include the subscriber's real `ip_address` in the `POST /v1/subscribers` body; when provided, Buttondown scores the visitor's (residential, < 0.5) IP instead of the server's. Verified against the live docs 2026-06-11 (see References):

> "You should proxy this directly from the request you receive, and if provided we'll use it rather than the IP address from which you make the API call."

Two production files plus one test file. No new dependencies, no schema, no infra, no UI.

## Premise Validation

No GitHub issue/PR cited by number in the feature description. All referenced artifacts verified against the worktree on 2026-06-11:

- `apps/web-platform/app/api/waitlist/waitlist.ts` — exists; `subscribeToWaitlist(email)` at line 84. ✓
- `apps/web-platform/app/api/waitlist/route.ts` — exists; client-IP extraction for the `SlidingWindowCounter` throttle at line 41 (`cf-connecting-ip` only, `"unknown"` fallback). ✓
- `apps/web-platform/test/api-waitlist-subscribe.test.ts` — exists; `makeRequest` already supports a `cfConnectingIp` param (line 44-55). ✓
- Egress claim — `api.buttondown.com` present at `apps/web-platform/infra/cron-egress-allowlist.txt:37` and asserted by `apps/web-platform/infra/cron-egress-firewall.test.sh:200`; corroborated by learning `knowledge-base/project/learnings/2026-06-10-terraform-remote-exec-gating-and-container-scoped-egress-allowlist.md`. The egress firewall is NOT involved in this change. ✓
- Buttondown `ip_address` contract — WebFetch of `https://docs.buttondown.com/api-subscribers-create` on 2026-06-11 confirms the field name `ip_address`, the proxy-it-directly guidance, and that the docs do **not** specify behavior for invalid values (motivates the fail-safe omit-when-implausible design below). ✓
- GDPR parity claim — verified across all three legal docs (see Domain Review → Legal). ✓

## Research Reconciliation — Spec vs. Codebase

| Spec/feature-description claim | Reality (verified) | Plan response |
|---|---|---|
| "the route already extracts client IP for the SlidingWindowCounter throttle — reuse that extraction" | `route.ts:41` — `const ip = req.headers.get("cf-connecting-ip")?.trim() \|\| "unknown"`; fail-closed, CF-only, never XFF | Pass the same `ip` variable through; the `"unknown"` sentinel and any direct-to-origin spoofed garbage are filtered by a plausibility check in `waitlist.ts` |
| "include `ip_address` only when a plausible public IP is available" | Docs do not specify Buttondown's behavior on invalid `ip_address`; an invalid value could 400 and break the very signups this hardens | Validate with `node:net` `isIP()` + private/reserved-range exclusion; omit the field when implausible (fail-safe = today's behavior) |
| "request body shape is unchanged otherwise (email_address, tags, no `type`)" | `waitlist.ts:100` body is exactly `{ email_address, tags: [WAITLIST_TAG] }`; existing test asserts no `type` (double opt-in preserved) | New tests assert exact key sets in both branches |
| "visitor IP already flows to Buttondown via the historical embed form … disclosed" | Article 30 PA6 lists "IP address … auto-collected by Buttondown at subscription" (Art. 6(1)(f)); privacy policy §4.6 + §5.3 and DPD §2.3(e) + §6.3 disclose it (SCCs Module 2) | GDPR note in PR body: restores parity, not a new disclosure surface; no legal-doc edits required |
| "Never log the IP+email pair" | Current logging is status-only (`waitlist.ts:115`); route mirrors errors via `warnSilentFallback` with `{feature, op}` only | No new log fields anywhere in the diff; AC enforces it |

## Hypotheses

(Network-outage checklist fired on keywords `firewall`/`502`/`400`. L3→L7 status — all layers verified or remediated; this plan addresses residual risk only, no outage is open.)

1. **L3 — egress firewall allowlist.** Verified: `api.buttondown.com` at `apps/web-platform/infra/cron-egress-allowlist.txt:37` (Tier-2 container egress allowlist, merged 2026-06-10). Artifact: allowlist line + `cron-egress-firewall.test.sh:200`. Not causal.
2. **L3 — DNS/routing.** Opt-out with artifact: prod `POST /api/waitlist` returned 200 and created the subscriber end-to-end on 2026-06-11 (operator-verified) — packets reach `api.buttondown.com`.
3. **L7 — TLS/proxy.** Same artifact as (2): live 200 through the full CF → origin → Buttondown chain. Not causal.
4. **L7 — application (Buttondown account firewall).** Root cause, already diagnosed AND remediated: account Firewall `auditing_mode` was `aggressive` (blocks ≥ 0.5); server-IP-sourced subscribes score 0.6 → `subscriber_blocked` 400. Operator PATCHed `auditing_mode` to `enabled` (blocks ≥ 1.0). **Residual risk:** Buttondown attack mode can auto-revert to `aggressive`; this PR's `ip_address` proxying makes signups survive that state.

### Network-Outage Deep-Dive (deepen-plan Phase 4.5)

Layer-by-layer verification status (checklist: `plugins/soleur/skills/plan/references/plan-network-outage-checklist.md`; telemetry emitted at both plan Phase 1.4 and deepen Phase 4.5):

| Layer | Status | Artifact |
|---|---|---|
| L3 egress firewall | verified | `cron-egress-allowlist.txt:37` (`api.buttondown.com`) + `cron-egress-firewall.test.sh:200` |
| L3 DNS/routing | opt-out w/ artifact | live prod 200 end-to-end on 2026-06-11 (operator-verified subscriber creation) |
| L7 TLS/proxy | opt-out w/ artifact | same live-200 artifact through CF → origin → Buttondown |
| L7 application | root cause, remediated | Buttondown `auditing_mode` PATCH `aggressive`→`enabled`; Sentry WEB-PLATFORM-2F resolved |

No open outage; no service-layer hypothesis precedes an unverified lower layer. Gap to close before implementation: none.

## Proposed Solution

### `apps/web-platform/app/api/waitlist/waitlist.ts`

1. Add a module-private plausibility helper (no new file — keep it next to its single consumer):

```ts
// apps/web-platform/app/api/waitlist/waitlist.ts
import { isIP } from "node:net"; // precedent: node: builtins used in server/workspace-invitations.ts:1

// Reserved/private prefixes that can only reach us via direct-to-origin spoofing
// (cf-connecting-ip from Cloudflare is always the public peer IP). Sending an
// implausible value to Buttondown risks a validation 400 — fail-safe is to omit.
const PRIVATE_V4 = /^(0\.|10\.|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.|127\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)/;

function plausiblePublicIp(raw: string | undefined): string | undefined {
  if (!raw) return undefined;
  let ip = raw.trim();
  if (ip.toLowerCase().startsWith("::ffff:")) ip = ip.slice(7); // v4-mapped v6
  const version = isIP(ip);
  if (version === 0) return undefined;           // "unknown", garbage, empty
  if (version === 4) return PRIVATE_V4.test(ip) ? undefined : ip;
  const v6 = ip.toLowerCase();
  // loopback/unspecified/link-local/unique-local
  if (v6 === "::1" || v6 === "::" || v6.startsWith("fe8") || v6.startsWith("fe9") ||
      v6.startsWith("fea") || v6.startsWith("feb") || v6.startsWith("fc") || v6.startsWith("fd")) {
    return undefined;
  }
  return ip;
}
```

2. Widen the signature and conditionally include the field:

```ts
export async function subscribeToWaitlist(
  email: string,
  clientIp?: string,
): Promise<{ ok: true }> {
  // ... unchanged key read ...
  const ipAddress = plausiblePublicIp(clientIp);
  const res = await fetch(BUTTONDOWN_SUBSCRIBE_URL, {
    // ... unchanged headers/signal ...
    body: JSON.stringify({
      email_address: email,
      tags: [WAITLIST_TAG],
      ...(ipAddress ? { ip_address: ipAddress } : {}),
    }),
  });
  // ... unchanged response handling ...
}
```

- `type` stays omitted (double opt-in + Art. 6(1)(a) consent step preserved).
- **No new logging.** The status-only error discipline stays; `plausiblePublicIp` never logs (a rejected-IP log line could be correlated with an email via timestamps). The IP+email pair never appears in any log/Sentry payload.
- Do **NOT** add the `X-Buttondown-Bypass-Firewall` header (rate-limited 5/hr/newsletter; kills spam protection).

### `apps/web-platform/app/api/waitlist/route.ts`

One-line change at the call site (`route.ts:70`):

```ts
await subscribeToWaitlist(email, ip);
```

`ip` is the existing throttle key from line 41. The `"unknown"` sentinel flows through and is rejected by `plausiblePublicIp` — single validation site, no branching in the route.

### `apps/web-platform/test/api-waitlist-subscribe.test.ts`

Extend the existing suite (vitest, node project — `test/**/*.test.ts` matches `vitest.config.ts:44` include glob):

1. **Extend the existing happy-path test** ("valid email POSTs v1 subscribers JSON…", no `cfConnectingIp`): add `expect(sent).not.toHaveProperty("ip_address")` and `expect(Object.keys(sent).sort()).toEqual(["email_address", "tags"])`.
2. **New: public IP forwarded.** `makeRequest({ origin: OK_ORIGIN, cfConnectingIp: "203.0.113.7", body: { email: ... } })` → `sent.ip_address === "203.0.113.7"`, `sent.email_address`/`sent.tags` unchanged, `expect(sent).not.toHaveProperty("type")`, `expect(Object.keys(sent).sort()).toEqual(["email_address", "ip_address", "tags"])`.
3. **New: public IPv6 forwarded.** `cfConnectingIp: "2001:db8::1"` → `sent.ip_address === "2001:db8::1"`.
4. **New: private IPv4 omitted.** `cfConnectingIp: "10.0.0.1"` → no `ip_address` property; subscribe still 200.
5. **New: garbage omitted.** `cfConnectingIp: "not-an-ip"` → no `ip_address` property; subscribe still 200 (regression guard: a spoofed direct-to-origin header must never turn a working subscribe into a Buttondown validation 400).
6. Existing rate-limit test already uses `cfConnectingIp: "9.9.9.9"` and does not inspect the body — unaffected.

## User-Brand Impact

- **If this lands broken, the user experiences:** a waitlist visitor submits their email on the pricing page / shared-doc CTA banner and gets the generic "something went wrong" 502 state — the lead is silently lost (the exact WEB-PLATFORM-2F failure mode this hardens against, now potentially triggered by a malformed `ip_address` instead of the server IP score).
- **If this leaks, the user's data is exposed via:** the visitor's IP+email pair appearing in logs/Sentry (the route currently never logs either; this plan adds zero new log fields), or the IP flowing to Buttondown — which is already a disclosed, SCC-covered processor flow (PA6, privacy policy §4.6/§5.3, DPD §2.3(e)/§6.3).
- **Brand-survival threshold:** `aggregate pattern` (lost leads across all signups when Buttondown attack mode re-escalates — not a single-user incident).

## Observability

```yaml
liveness_signal:
  what: "Sentry warn-level mirror via warnSilentFallback({feature: waitlist-subscribe, op: subscribe}) on every failed subscribe (pre-existing)"
  cadence: "per-request"
  alert_target: "Sentry web-platform project issue stream (WEB-PLATFORM-2F class)"
  configured_in: "apps/web-platform/app/api/waitlist/route.ts:76 + apps/web-platform/server/observability.ts"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN"
  fail_loud: "client receives 502 {error: upstream_unavailable}; server logs status-only warn 'Buttondown subscribe returned non-ok status' (waitlist.ts:115)"

failure_modes:
  - mode: "Buttondown attack mode re-escalates to aggressive AND visitor-IP scoring still blocks (residual residual risk)"
    detection: "Sentry event spike on feature:waitlist-subscribe (status 400 mirrored as upstream_unavailable)"
    alert_route: "Sentry issue alert -> operator email"
  - mode: "ip_address value rejected by Buttondown as invalid (docs unspecified)"
    detection: "same Sentry mirror; plausiblePublicIp omits implausible values so only CF-vetted public IPs are ever sent"
    alert_route: "Sentry issue alert -> operator email"
  - mode: "regression drops ip_address from the body (silent return to server-IP scoring)"
    detection: "vitest body-shape assertions (exact key-set) fail in CI"
    alert_route: "CI red on PR"

logs:
  where: "pino child logger 'waitlist-subscribe' -> docker logs (journald) on the Hetzner host"
  retention: "per host journald config (apps/web-platform/infra/journald-config.test.sh)"

discoverability_test:
  command: "gh api /repos/{owner}/{repo}/actions/runs --jq '.workflow_runs[0].conclusion' # CI green proves body-shape guards; Sentry stream readable at sentry.io web-platform project filtered on waitlist-subscribe"
  expected_output: "success"
```

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1 — `subscribeToWaitlist(email, clientIp?)` accepts an optional second param; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes. (NOT `npm run -w` — repo root declares no workspaces.)
- [x] AC2 — Buttondown POST body includes `ip_address: <client IP>` iff `clientIp` is a plausible public IP (passes `node:net` `isIP` and is not loopback/private/link-local/CGNAT/unspecified); otherwise the field is absent. Verified by the vitest scenarios below.
- [x] AC3 — Body shape otherwise unchanged: `email_address`, `tags: ["pricing-waitlist"]`, **no `type` field** (double opt-in preserved). Tests assert exact key sets: `["email_address","tags"]` (no IP) and `["email_address","ip_address","tags"]` (IP known).
- [x] AC4 — `route.ts` passes the existing line-41 `ip` variable through; no second extraction, no XFF fallback introduced. `grep -c 'cf-connecting-ip' apps/web-platform/app/api/waitlist/route.ts` returns `1`.
- [x] AC5 — No `X-Buttondown-Bypass-Firewall` header anywhere: `git grep -il 'bypass-firewall' -- 'apps/**'` returns no matches (exit 1).
- [x] AC6 — No new log/Sentry fields carrying IP or email: diff adds zero `log.*`/`warnSilentFallback` calls and zero new fields to existing ones (review-verified on the diff; `git diff main -- apps/web-platform/app/api/waitlist/ | grep -E '^\+.*(log\.|warnSilentFallback)'` returns no matches).
- [x] AC7 — Full suite green: `cd apps/web-platform && ./node_modules/.bin/vitest run test/api-waitlist-subscribe.test.ts` (all pre-existing tests pass unmodified except the documented happy-path extension).
- [ ] AC8 — PR body contains the GDPR parity note (visitor IP already disclosed as Buttondown-collected at subscription: Article 30 PA6, privacy policy §4.6/§5.3, DPD §2.3(e)/§6.3; SCCs Module 2 cover the US transfer; this restores embed-form parity, not a new disclosure surface) and uses `Ref`/context only — no legal-doc edits in this PR.

### Post-merge (operator)

- None. The `web-platform-release.yml` pipeline restarts the container on merge to main (path-filtered `apps/web-platform/**`); merge IS the deploy. Live verification is automatable: submit one probe signup via the pricing page after deploy and confirm 200 + confirmation email (can be driven via Playwright/agent-browser at postmerge time; no dashboard eyeballing).

## Test Scenarios

- Given a request with `cf-connecting-ip: 203.0.113.7`, when the email is valid and Buttondown returns 201, then the upstream body is exactly `{email_address, tags, ip_address: "203.0.113.7"}` and the route returns 200 `{ok:true}`.
- Given a request with `cf-connecting-ip: 2001:db8::1`, when subscribed, then `ip_address` is `"2001:db8::1"`.
- Given a request with no `cf-connecting-ip` header (throttle key `"unknown"`), when subscribed, then the upstream body is exactly `{email_address, tags}` — no `ip_address` key.
- Given a (direct-to-origin spoofed) `cf-connecting-ip: 10.0.0.1` or `not-an-ip`, when subscribed, then `ip_address` is absent and the subscribe still succeeds (200) — an implausible header must never break a signup.
- Given any of the above, then the body never contains a `type` key (regression: double opt-in / Art. 6(1)(a) consent step).
- Given Buttondown returns an unexpected status, when the route mirrors to Sentry, then the mirror payload remains `{feature, op}` only (no IP, no email) — unchanged assertions in existing tests.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (200 most recent) contains no issue body referencing `apps/web-platform/app/api/waitlist/waitlist.ts`, `route.ts`, or `test/api-waitlist-subscribe.test.ts` (checked 2026-06-11).

## Domain Review

**Domains relevant:** Engineering, Legal/Compliance

*(Pipeline note: this plan ran inside the one-shot planning subagent, which has no Task tool — domain assessments were performed inline against cited artifacts rather than via spawned domain-leader agents.)*

### Engineering

**Status:** reviewed (inline)
**Assessment:** Minimal blast radius — two files, one optional param, one conditional spread. Single validation site (`waitlist.ts`) keeps the route free of IP-shape branching. `node:net` import follows existing precedent (`server/workspace-invitations.ts:1` uses `node:crypto`); the route is Node-runtime (no `runtime = "edge"` export). Fail-safe design: any implausible value degrades to today's exact behavior (field omitted), so the change cannot make a currently-working signup worse. The rate-limit key derivation is untouched (fail-closed CF-only, per the anti-amplification test at test line 232).

### Legal/Compliance (GDPR)

**Status:** reviewed (inline; gdpr-gate advisory below)
**Assessment:** No new processing activity, data category, recipient, purpose, or transfer. Article 30 PA6 already lists "IP address … (auto-collected by Buttondown at subscription)" under Art. 6(1)(f) legitimate interest (abuse prevention — which is precisely this change's purpose); privacy policy §4.6 + §5.3 and Data Protection Disclosure §2.3(e) + §6.3 disclose the IP category and the SCC Module 2 transfer mechanism (Buttondown DPA, all tiers). The historical embed form sent the visitor IP directly; the server-side proxy (which replaced it) inadvertently substituted the server IP — this change restores the disclosed behavior. Data minimization: only the IP already extracted for rate limiting is forwarded; nothing new is collected; the IP+email pair is never logged. No legal-doc edits required; PR body carries the parity note (AC8).

### Product/UX Gate

Not applicable — no UI-surface file in Files to Edit/Create (mechanical override checked: no `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`); API-only hardening, NONE tier.

### Compliance Gate (gdpr-gate, Phase 2.7 — advisory)

**This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor` before merging.**

Ran 2026-06-11 against this plan + the two API-route surfaces (canonical-regex match: `apps/web-platform/app/api/.*\.ts$`). **Zero Critical, zero Important.** All five mandatory v1 checks pass (no migration, no new column/table/FK/RPC, no new vendor; Buttondown SCCs + IP category pre-recorded in PA6 / DPD §6.3). Two read-only Suggestions:

1. **AP-02 (Art. 13 transparency, Suggestion):** disclosures phrase the IP as "auto-collected by Buttondown"; post-change Jikigai actively proxies it. Data-subject position unchanged (same data/processor/purpose/basis) — no amendment required this PR; optionally clarify wording at the next scheduled counsel-review cycle.
2. **TS-01 (Art. 32, Suggestion):** test-fixture IPs are RFC 5737/3849 documentation ranges with mocked fetch — already compliant with `cq-test-fixtures-synthesized-only`.

Verdict: the no-new-disclosure-surface conclusion is **confirmed**.

## Files to Edit

1. `apps/web-platform/app/api/waitlist/waitlist.ts` — add `node:net` `isIP` import, `plausiblePublicIp()` helper, optional `clientIp` param, conditional `ip_address` in POST body, doc-comment update (mention firewall re-escalation rationale + never-log discipline).
2. `apps/web-platform/app/api/waitlist/route.ts` — pass `ip` to `subscribeToWaitlist(email, ip)`; update header comment one line.
3. `apps/web-platform/test/api-waitlist-subscribe.test.ts` — extend happy-path body assertions; add 4 new scenarios (public v4, public v6, private v4 omitted, garbage omitted).

## Files to Create

None.

## Dependencies & Risks

- **Buttondown behavior on invalid `ip_address` is undocumented** (verified 2026-06-11) → mitigated by omit-when-implausible; only CF-vetted public IPs are ever sent.
- **Direct-to-origin requests can spoof `cf-connecting-ip`** → already true for the rate-limit key; for Buttondown the spoofed value is at worst a different public IP scored by their firewall (their problem domain), and implausible values are dropped. No new attack surface: the attacker could already POST to Buttondown's public form with any IP.
- **`2001:db8::1` / `203.0.113.7` are documentation-reserved ranges** used as test fixtures — they pass the plausibility check by design (the check excludes only ranges that can never be a CF public peer: private/loopback/link-local/CGNAT/ULA). Acceptable: fixtures never reach the real Buttondown API (fetch is mocked).
- **Attack mode could still block residential IPs scoring ≥ threshold** → residual risk accepted; Sentry mirror (unchanged) surfaces any spike; threshold documented in Observability.

## References & Research

- Buttondown API docs (verified via WebFetch 2026-06-11): <https://docs.buttondown.com/api-subscribers-create> — `ip_address` field: "You should proxy this directly from the request you receive, and if provided we'll use it rather than the IP address from which you make the API call."
- Current implementation: `apps/web-platform/app/api/waitlist/waitlist.ts:84-117`, `apps/web-platform/app/api/waitlist/route.ts:41-47,69-81`.
- Legal parity: `knowledge-base/legal/article-30-register.md` (PA6, line 120-136), `plugins/soleur/docs/pages/legal/privacy-policy.md` (§4.6, §5.3), `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (§2.3(e), §6.3).
- Egress allowlist: `apps/web-platform/infra/cron-egress-allowlist.txt:37` (+ `cron-egress-firewall.test.sh:200`); learning `knowledge-base/project/learnings/2026-06-10-terraform-remote-exec-gating-and-container-scoped-egress-allowlist.md`.
- Buttondown GDPR transfer mechanism: `knowledge-base/project/learnings/2026-03-18-buttondown-gdpr-transfer-mechanism-sccs-only.md`.
- Waitlist pattern provenance: `knowledge-base/project/learnings/2026-03-25-waitlist-form-reuse-newsletter-pattern.md`.

## Research Insights (deepen-plan)

**Empirical validation (live-executed 2026-06-11, node v24.15.0):** the exact `plausiblePublicIp` implementation from Proposed Solution passed all 26 fixture cases:

```text
ALL 26 CASES PASS (node v24.15.0)
# accepts: 203.0.113.7, 2001:db8::1, 8.8.8.8, 172.32.0.1, 100.128.0.1, 2606:4700::1111, "::ffff:8.8.8.8"→8.8.8.8, " 1.2.3.4 "→1.2.3.4
# rejects: unknown, not-an-ip, "", undefined, 10.0.0.1, 172.16.5.5, 192.168.1.1, 127.0.0.1,
#          169.254.1.1, 100.64.0.1, 100.127.255.255, 0.1.2.3, ::1, ::, fe80::1, fd12::1, fc00::1, ::ffff:10.0.0.1
```

**Best practices applied:**

- Buttondown's own guidance is the load-bearing contract (verified WebFetch 2026-06-11): proxy the IP "directly from the request you receive" — no enrichment, no fallback to XFF.
- Fail-safe asymmetry: a false-negative (public IP wrongly omitted) costs only fallback-to-server-IP scoring (today's behavior); a false-positive (garbage forwarded) risks an undocumented Buttondown 400 on a real signup. The validator is therefore deliberately reject-biased.
- Single extraction point: throttle key and forwarded IP must come from the same `route.ts:41` variable so abuse-control and risk-scoring agree on visitor identity.

**Anti-patterns avoided:**

- `X-Buttondown-Bypass-Firewall` header (5/hr/newsletter rate limit; disables spam protection wholesale).
- XFF fallback for the forwarded IP (client-controllable; would reintroduce the amplification vector the rate-limit design explicitly closed — see anti-amplification test at `test/api-waitlist-subscribe.test.ts:232`).
- Logging rejected IPs (timestamp correlation with the email in adjacent log lines would reconstruct the IP+email pair this plan forbids).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Section is filled above — threshold `aggregate pattern`.)
- Typecheck/test invocations MUST be in-package (`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` / `./node_modules/.bin/vitest run …`) — the repo root has no `workspaces` field, so `npm run -w` aborts.
- Do not "improve" the rate-limit key while in the file — the CF-only fail-closed extraction is a deliberate anti-amplification control with its own test (test line 232).
- Keep `plausiblePublicIp` module-private in `waitlist.ts` (test through the route's observable body shape, not by exporting the helper) unless a second consumer appears.
