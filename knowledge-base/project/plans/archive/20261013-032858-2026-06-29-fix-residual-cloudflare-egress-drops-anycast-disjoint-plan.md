---
title: "fix: residual container egress drops to Cloudflare 104.16.x.34:443 (anycast-disjoint / allowlist-gap)"
date: 2026-06-29
issue: 5676
type: bug
classification: ops-remediation
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
relates_to: [5413, 5089, "ADR-052"]
status: draft
---

# fix: Residual container egress drops to Cloudflare `104.16.x.34:443` persist after the #5413 grace-window fix 🐛

> **NEVER CODE FROM THIS PLAN UNTIL `/work`.** This is a research/plan artifact.

## Enhancement Summary

**Deepened on:** 2026-06-29
**Agents:** network-outage deep-dive (Explore), security-sentinel, architecture-strategist, observability-coverage-reviewer, code-simplicity-reviewer + a verify-the-negative grep pass (all line citations confirmed against `cron-egress-resolve.sh`).

### Key improvements
1. **Hypothesis reframed (arch P1/P2/P3).** Branch A (a Cloudflare host absent from BOTH the 23 static lines AND the 3 dynamic env hosts) is now the most-likely branch, on the discriminator that #5413 retention would have captured a *resolved* host's rotating `.34` pool within 24h — steady non-convergence ⇒ unresolved host. The Sentry-ingest "leading hypothesis" was demoted: dynamic hosts resolve on the unified path (line 174, proven by the arriving events POSTed to `SENTRY_INGEST_DOMAIN`), so a dynamic-host culprit *requires* Branch B by construction and is lower-prior for resolver-stable Cloudflare anycast. Supabase *siblings* added as a co-equal candidate.
2. **Security P1 closed.** Branch B2's retention-seed pinned to `getent`-of-named-host (host-revalidated), never observed-dialed destinations (would be a default-drop bypass).
3. **B1 fail-loud = alert-not-abort/widen (security P2)**; added the sustained-container-down (#5417) failure mode B1b that B1 alone misses (observability F2), with an AC11 caveat that convergence is blocked on #5417 if that is the driver (arch P4).
4. **Observability irony made explicit (observability F1):** detection survives a Sentry blackhole because `egress-blocked` is emitted host-side; `discoverability_test` made runnable via `scripts/sentry-issue.sh`.
5. **Simplified (simplicity review):** collapsed B2's three sub-options to an ADR-052 §4 pointer + the security constraint; made the runbook/learning Branch-B-conditional; dropped the redundant `openssl` SNI step; cut LARP AC2; split AC7's Ref/Closes reminder out to Risks. Fixed the 22→23 static-host count (arch P5).

### New considerations discovered
- A dynamic host (Sentry/Supabase) dropped *despite being resolved every tick* is a genuinely distinct class from both LB-rotation (#5413) and a static allowlist gap — it points at resolver-view divergence (B1) or a sustained container-view skip (#5417), not at the allowlist.
- The blackholed-Sentry case is a **security** observability hole (swallows auth/RLS/BYOK/exfil signal), not merely availability — it justifies the `single-user incident` threshold the worst-case framing already set.

## Overview

The ADR-052 DOCKER-USER container egress firewall is **still** default-dropping
container traffic (`SRC=172.17.0.2 → DST 104.16.x.34:443 SYN`) to a tight
Cloudflare anycast pool (`AS13335`), firing the Sentry `egress-blocked` issue
(id `126858085`) at ~9–57 hits per 3-min window — ongoing as of 2026-06-29
10:44Z. The #5413 grace-window retention fix (merged, commit `f743bc263`) did
**not** clear it, so the post-mortem's recovery criterion ("`egress-blocked`
104.x DST hits trend to zero within one grace window") is **unmet**.

This is a **residual, separate** failure from the one #5413 fixed. #5413 cured
LB-rotation drops on the 23 static allowlisted hosts (IPs `getent` *does*
eventually return, just not within one 1-min tick). This residual is
structurally different: the blocked pool (`104.16.{1,2,3,4,7,8,10}.34` — a
**constant `.34` host-octet, rotating 3rd octet**, all in `104.16.0.0/13`) is a
**single Cloudflare zone's anycast fingerprint**, and the issue reporter already
proved (DoH against `8.8.8.8`) that **none of the 23 static allowlisted hosts
resolve into `104.16.x.34`**. Grace-window retention can only ever accumulate
IPs a `getent` view returns; if the dialed host's IPs are never returned by the
resolver's `getent`, retention is structurally unable to converge — no amount of
window-widening helps.

The fix is **diagnosis-first**. The entire weight of this plan is **identifying
the `104.16.x.34` hostname** (Cloudflare anycast hides it from the IP), then
taking exactly one of three pre-specified branches. The plan does NOT pre-commit
to a remediation; it specifies the deterministic diagnosis that *selects* the
branch and fully specifies each branch's edits.

**Most-likely branch — A (allowlist gap), with a structural discriminator
(architecture review, P1/P2).** The single strongest argument is one the issue
body under-uses: **#5413's grace-window retention was purpose-built to accumulate
exactly this kind of rotating CDN pool** (`104.16.{1,2,3,4,7,8,10}.34`) for any
host the resolver resolves. If the dialed host were in the resolver's resolved
set, retention would have captured its full rotating `.34` pool within one 24h
window. **Persistent, *steady* (non-intermittent) non-convergence is therefore
strong evidence the host is not in the resolved set at all** — i.e. absent from
**both** the 23 static allowlist lines **and** the 3 dynamically-resolved env
hosts (`SENTRY_INGEST_DOMAIN`, `NEXT_PUBLIC_SUPABASE_URL`, `SUPABASE_URL`). The
likely culprit is a Cloudflare-fronted host nobody enumerated: a `*.supabase.co`
*sibling* (Edge Functions / Storage on a distinct subdomain), an OAuth host
(`accounts.google.com`), an avatar/image CDN, or a redirect target.

**Why the dynamic-host hypotheses are *lower* prior, and excluded-by-construction
from Branch A (corrects the issue body).** `SENTRY_INGEST_DOMAIN` and the Supabase
URLs are gathered at line 149 but **resolved on the *same* unified path as static
hosts (line 174)** — there is no separate *resolution* code path, only separate
*gathering*. Proof they resolve fine in the resolver's context: the
`egress-blocked` events themselves are POSTed to `SENTRY_INGEST_DOMAIN` (line 109)
and are arriving. So if a dynamic host were the culprit, its IPs would already be
in both `getent` views and retained — it would **not** be dropped — *unless* a
resolver-view divergence holds (root cause 1 / Branch B). Net: **a dynamic host as
culprit *requires* Branch B by construction; it can never be Branch A.** And
divergence is itself *lower* prior for a **Cloudflare** destination: Cloudflare's
shared anycast (`104.16.0.0/13`) returns **stable, resolver-independent** A records
(geo-routing is at BGP, not DNS), so the host-view `getent` (line 175, always
contributing to `DESIRED_ALLOW`) would already capture a resolved host's IP — the
"CDN/geo answers diverge per resolver" rationale in ADR-052 §4 is real for
DNS-geo CDNs (Akamai/Fastly), not Cloudflare anycast. **Ordering: A ≫ B1 > B2.**
The deterministic Phase-0 enumeration finds the host regardless of branch, so the
*method* is robust even though the *prior* now favors A. (Supabase-sibling and
Sentry remain the two dynamic candidates to resolve *first* in Phase 0.2 — both
Cloudflare-plausible — but landing on either means Branch B, not A.)

## Premise Validation (Phase 0.6)

| Cited reference | Check | Result |
|---|---|---|
| Issue `#5676` | `gh issue view 5676` | OPEN, `p3-low`, `type/bug`, `domain/engineering`. Title + body match the feature description. Premise holds. |
| `#5413` grace-window fix "merged 2026-06-23" | `git log -- cron-egress-resolve.sh` | Merged as commit `f743bc263` (`fix(infra): grace-window IP retention …`). Present on `origin/main`. The retention code (`SEEN_DIR`, `GRACE_WINDOW_SECS`, lines 52–243 of `cron-egress-resolve.sh`) is live. Premise holds. |
| `ADR-052` | `Read` ADR file | Accepted 2026-06-09, amended 2026-06-16 (grace-window). §3 "grep-enumerated allowlist", §4 amendment, §"CDN shared-IP broadening (named honestly)" all directly relevant. Premise holds. |
| Sentry issue `egress-blocked` (id `126858085`) | issue body evidence | Cited as firing continuously; will be re-confirmed live in Phase 0 via the incident skill Sentry toolchain (not assumed). |
| Post-mortem status "ended" | `Read` post-mortem frontmatter | Currently `status: unresolved but ended`. Per the issue, must flip back to active — a plan deliverable (Phase 3). |
| Mechanism "add host vs reconsider IP-allowlist per ADR-052" | grep ADR corpus | ADR-052 §4 amendment + "CDN shared-IP broadening" already weighed the SNI-proxy escalation and explicitly **rejected wholesale provider CIDRs** for non-GitHub LB hosts. So Branch-B option (ii)/(iii) is an *amendment to an existing decision*, not a novel one — handled in the ADR/C4 gate below. |

No stale premises. The issue is a genuine, currently-firing residual.

## User-Brand Impact

**If this lands broken, the user experiences:** a silently-dropped egress to a
needed host. If the host is a dynamic ingest host like `SENTRY_INGEST_DOMAIN`
(Branch B), the operator's *own* production error-reporting is partially
blackholed — failures elsewhere in the app stop surfacing in Sentry, defeating
the no-SSH observability contract the whole platform depends on. **This is a
security exposure, not merely an availability one (security review, P2):** a
blackholed app-Sentry silently swallows auth anomalies, RLS-denial logs,
BYOK-validation failures, and suspected-exfil app errors — an attacker who can
induce app errors benefits from the blind window. If the host fronts a
user-facing flow (waitlist→Buttondown, email→Resend, push, billing→Stripe), a
single user's action (signup, email receipt, push delivery) **silently fails**
with no error the operator can see.

**If this leaks, the user's data/workflow is exposed via:** N/A for a
*tightening* change. The risk axis here is the inverse — an over-broad fix
(allowlisting a Cloudflare provider CIDR) would **widen** egress so a compromised
spawn-bash cron could exfiltrate to *any* tenant co-resident on Cloudflare
`104.16.0.0/13`, defeating ADR-052's default-drop boundary. The plan forbids
this (Branch-B option (i) is rejected for shared-cloud LBs per the #5413
learning).

**Brand-survival threshold:** `single-user incident`. The dialed host is unknown
until diagnosis; the worst plausible case (blackholed Sentry, or a user-facing
flow silently failing) is single-user-incident class, so the threshold is set
for the worst case until diagnosis narrows it. **CPO sign-off required at plan
time before `/work` begins** (carry-forward from parent post-mortem
`brand_survival_threshold: single-user incident`; or confirm CPO has reviewed).
`user-impact-reviewer` will be invoked at review time (review/SKILL.md
conditional-agent block).

**Post-diagnosis outcome (recorded at /work — the worst case was VERIFIED FALSE).**
Diagnosis named the dominant host as `registry.npmjs.org` (intended-by-design drop,
#5199) and proved the app's own Sentry ingest (`SENTRY_INGEST_DOMAIN` → `34.160.81.0`)
is **never** in the blocked DST set — so the Branch-B blackholed-Sentry security hole
that set this threshold does not exist. The shipped remediation is a source-silence
(`npm_config_prefer_offline` on the cron-spawned npx), whose sole operator-facing
failure mode (the monthly `cron-ux-audit` breaking on a cold image cache) is
fail-safe by construction: `prefer-offline` (not the hard `offline`) degrades to the
existing drop+baked-dep fallback. Per the §Risks downgrade clause, the `single-user
incident` threshold is satisfied as a benign Branch-A-class outcome; the still-blocked
sporadic GCP/MCP telemetry hosts are off-allowlist by design and tracked in #5691.

## Hypotheses (L3→L7, firewall-first — `hr-ssh-diagnosis-verify-firewall`)

> Network-outage checklist (`plan-network-outage-checklist.md`) triggered on
> `firewall` / `unreachable` / `timeout` / drops. Per `hr-ssh-diagnosis-verify-firewall`
> the L3 firewall + DNS/routing layers MUST be verified **before** any
> service-layer hypothesis. This is a containment firewall doing a *drop*, so the
> L3 layer is not "is the firewall blocking us" (it provably is — that is the
> alert) but "**which allowlist line is the dialed host missing from, and why**".

### L3 — Egress firewall allowlist (the drop itself)

- **Explicit L3 exception (network deep-dive gap):** the standard L3 step
  (`hcloud firewall describe` + diff against operator egress IP) is **deliberately
  N/A** here — this is a *containment* firewall whose drop IS the alert. L3 is
  confirmed via the Sentry drop event; the open question is *which allowlist entry
  the host is missing from*, not firewall health. Stating this so a reader does
  not mistake the skipped vendor-CLI check for an unverified layer.
- **Verified-by-design:** the `egress-blocked` Sentry event IS the firewall
  dropping `DST=104.16.x.34`. The DOCKER-USER default-drop is working correctly;
  the question is allowlist coverage, not firewall health.
- **Artifact:** Phase 0 reads the live Sentry event (`extra.sample`,
  `extra.hits`) via the incident skill `SENTRY_ISSUE_RW_TOKEN` toolchain and
  groups events over 14d to confirm the DST pool is exactly `104.16.x.34` and
  stable (one zone) vs spreading.

### L3 — DNS / routing (the crux — which host owns `104.16.x.34`)

The anycast IP hides the customer. **Two independent identification paths; the
codebase enumeration (path 2) is the deterministic one that does NOT depend on
the broken cron-stdout observability surface:**

1. **App-side fetch error (Better Stack).** The Next.js app's `pino` stream
   ships to Better Stack (Vector Source 3). Query the drop windows for
   `ECONNREFUSED|ETIMEDOUT|EHOSTUNREACH|fetch failed|UND_ERR|getaddrinfo`. If the
   dialer is the **Next.js app**, this names the host directly.
   **Caveat (from the issue):** claude-eval / spawn-bash cron stdout is currently
   dropped (separate observability gap) — so if the dialer is a cron, Better
   Stack will NOT have it. Hence path 2 is load-bearing.
2. **Deterministic codebase egress-host enumeration + DoH (no SSH, no cron
   stdout).** `grep` every outbound hostname in `apps/web-platform/` — every
   `https://<host>`, `fetch(`, SDK base URL, env-derived endpoint, **including
   the dynamic hosts the reporter's sweep skipped** (`SENTRY_INGEST_DOMAIN`,
   `NEXT_PUBLIC_SUPABASE_URL`, `SUPABASE_URL`) and any redirect/CDN sub-host —
   then resolve each via DoH from **both** `8.8.8.8` (the container's resolver,
   per ADR-052 §4 "Docker substitutes 8.8.8.8/8.8.4.4") **and** `1.1.1.1`,
   matching for the `104.16.0.0/13` + constant `.34` host-octet fingerprint.
   Because the fingerprint is so specific, this enumeration is bounded and
   pinpoints the host. **Resolve the two Cloudflare-plausible dynamic candidates
   first** — `SENTRY_INGEST_DOMAIN` AND the **Supabase siblings** (Edge Functions
   `*.functions.supabase.co`, Storage, the Management API `api.supabase.com` —
   `*.supabase.co` is *definitively* Cloudflare-fronted; the reporter checked only
   the base `SUPABASE_URL` host → `104.20.x`, not the siblings). Pull values via
   `doppler secrets get <VAR> -p soleur -c prd --plain`. **Routing note (arch +
   security review):** if the match lands on ANY of the 3 dynamically-resolved
   env hosts, the branch is **B** (anycast-disjoint), NOT A — those hosts are
   resolved every tick (line 174), so a Branch-A static line would just pin
   whatever the mutable env currently resolves to (an env-trust widening).
   - **Success criterion (network deep-dive gap):** the DoH match must return the
     **same** `104.16.x.34` pool from **both** `8.8.8.8` and `1.1.1.1` for the
     named host. If the two resolvers disagree (one returns `.34`, the other does
     not), that resolver-divergence IS the root-cause-1 signal — record it and
     route to Branch B regardless of allowlist membership.
3. **Recurrence / distribution.** Group the Sentry issue events over time
   (runbook §"Deeper diagnosis"): a single stable `.34` zone ⇒ one host (gap or
   anycast-disjoint); a spreading set ⇒ broader. **Steady, continuous** volume
   (the observed 9–57/3min for days) ⇒ a host *structurally never resolved*
   (Branch A) rather than an *intermittent* B1 resolver gap — an intermittent
   container-view failure would produce drops with GAPS, and the 24h window would
   paper over them (arch review). Background-poll/SDK cadence, not a user click.

- **Verification artifact:** the resolved IP set per candidate host (DoH output,
  both resolvers) pasted into Phase 0's findings, with the matching host named.
  **"Obvious" is not a verification — the host MUST be named by a resolved-IP
  match.**

### L3 — Resolver internal coverage (root-cause-1 mechanism — LOWER prior)

Even for an **already-allowlisted** (or dynamically-resolved) host, retention can
fail to converge if the resolver's `getent` views never return the app's anycast
subset. **Prior caveat (arch review):** this is *lower* prior than Branch A for a
Cloudflare destination — Cloudflare anycast is resolver-stable, so the host-view
`getent` (line 175, which always contributes to `DESIRED_ALLOW` at line 194) would
already capture a resolved host's IP. Verify these two mechanisms only after the
L3-DNS enumeration names a host that IS in the resolved set:

- **B1a — Container-view `getent` silently empty (container *running*).**
  `cron-egress-resolve.sh` line 167-171 runs `docker exec -i "$CONTAINER" … getent
  ahostsv4` with `2>/dev/null … || true` (**fail-silent**). If that exec returns
  nothing (docker exec failure/timeout, musl-vs-glibc `getent` quirk), the allow
  set pins **only the HOST resolver's** answers. Real but lower-prior for a
  resolver-stable Cloudflare host.
- **B1b — Container *not running* for N sustained ticks (#5417 restart-loop —
  observability review F2).** A distinct silent path: `container_running()` false
  for many consecutive ticks sets `CONTAINER_VIEW=""` *every* tick with **no
  consecutive-tick escalation** (contrast the per-host `FAILCOUNT_ESCALATE`
  path). A crash-looping container ⇒ host-view-only allowlist every tick ⇒ exactly
  this residual, **unpaged**. Distinguish from B1a/Branch-A by checking whether the
  `egress-blocked` burst windows align with `container-restart-monitor.sh`'s
  `container_restart_burst` Sentry timestamps. **If #5417 is the driver,
  convergence (AC11) is blocked on #5417 — B1's fail-loud surfaces it but does not
  fix it; the post-mortem stays active and #5676 does NOT auto-close** (arch P4).
- **Verification artifact:** the resolver's OK-log line
  (`[cron-egress-resolve] OK: allow=N addrs, retained=M …`) read via the
  `apply-web-platform-infra.yml` post-apply probe or the resolve Sentry check-in
  — confirm `allow=` is non-trivially > the host-only count (i.e. the container
  view is contributing). No SSH (the post-apply probe runs the command host-side
  and surfaces the line in the Actions log).

### L7 — TLS / proxy (OPTIONAL corroboration — the DoH match is already definitive)

- The DoH fingerprint match (L3-DNS path 2) deterministically identifies the host;
  L7 is corroboration only, not load-bearing (simplicity + network review — the
  `openssl s_client -servername` SNI step was dropped as verify-the-verification
  gold-plating). If any corroboration is wanted, one lightweight call:
  `curl -sIv --max-time 10 https://<candidate-host>/` → inspect `Server:
  cloudflare` / `CF-Ray`.
- **Artifact:** (if run) the `curl -Iv` headers. **Pin every network call**
  (`curl --max-time`, `dig +time=2 +tries=2`) — unbounded CI network calls are a
  Sharp Edge.

### L7 — Application / flow layer (which feature dials it)

- Only AFTER L3 names the host: map host → flow (Sentry SDK / waitlist / email /
  push / billing / a specific cron). If the app RESPONDED (a 4xx in logs), the
  firewall is NOT the cause (runbook §5 — "upstream 4xx ≠ egress").
- **Circular-Sentry caveat (network + observability review).** If the host IS the
  app's Sentry ingest, you CANNOT verify resumption *via Sentry* (it is the
  blackholed channel). Use the **independent** Better Stack pino stream (app fetch
  errors disappearing) and the host-side `egress-blocked` hit count → 0 as the
  resumption signals — never "Sentry events resumed" as the sole criterion.
- **Artifact:** the named flow + the runtime `file:line` that dials the host.

## Implementation Phases

### Phase 0 — Diagnose & name the host (NO code change)

0.1 Read the live `egress-blocked` Sentry event (id `126858085`) via the
incident skill Sentry toolchain; group 14d to confirm the DST pool shape.
0.2 Run the **deterministic enumeration** (L3-DNS path 2): grep all
`apps/web-platform/` egress hostnames; resolve each (Sentry ingest + Supabase
*siblings* first) via DoH `8.8.8.8` + `1.1.1.1`; find the host whose **both**
resolvers return `104.16.x.34`.
0.3 Query Better Stack for the app-side fetch error in the drop windows
(L3-DNS path 1) — corroborate the host and name the flow.
0.4 Verify the resolver container-view `getent` is contributing (L3-resolver),
AND check whether the `egress-blocked` burst windows align with
`container-restart-monitor.sh`'s `container_restart_burst` timestamps (the B1b
#5417-driver tell — distinguishes a sustained-container-down cause from a true
allowlist gap).
0.5 **Decide the branch** from the evidence:
- Host **absent from BOTH the 23 static lines AND the 3 dynamic env hosts**,
  legitimately needed → **Branch A**.
- Host **already resolved by the resolver** — i.e. a static allowlist line OR one
  of the 3 dynamically-resolved env hosts (`SENTRY_INGEST_DOMAIN`,
  `NEXT_PUBLIC_SUPABASE_URL`, `SUPABASE_URL`) — yet still dropped (anycast-disjoint)
  → **Branch B** (sub-select B1a/B1b/B2). Routing a dynamic host to Branch B (not
  A) is load-bearing: adding it as a static line would pin whatever the mutable env
  currently resolves to (env-trust widening — security review).
- Host **not needed** (no legitimate flow) → **Branch C** (exfil/stray path).

### Phase 1 — Remediate (exactly one branch)

#### Branch A — Allowlist gap (most likely)

1A.1 Add the host to `apps/web-platform/infra/cron-egress-allowlist.txt`, one
line, **with an evidence comment** (`file:line` of the runtime code that dials
it — sweep-class discipline, ADR-052 §3).
1A.2 In `apps/web-platform/infra/cron-egress-firewall.test.sh`: bump the
exact-set guard `HOST_COUNT -eq 23` → `24` (line ~507, update the count + the
FAIL message text) AND add the host to the explicit per-host presence loop
(lines 487-492). Both, or the build stays red (intended exact-set guard).
1A.3 If the host is a **new external system** not already in the C4 model →
see the ADR/C4 gate (add the element). If it is an existing/Cloudflare-fronted
system → no C4 change.

#### Branch B — Anycast-disjoint, already-resolved host (root cause 1)

- **B1 — container-view `getent` silently empty (resolver bug; no ADR
  amendment).** Make the container-view resolution **fail-loud** in
  `cron-egress-resolve.sh`: distinguish "container not running" (legitimately
  skip) from "container running but `getent` returned nothing" (a real coverage
  gap — log + `sentry_event op=resolve_container_view_empty`). **Fail-loud means
  ALERT, never ABORT and never WIDEN (security review, P2):** emit the Sentry
  event and **continue the reconcile additive-only with the host view** — do NOT
  wire it to `fail()`/`exit 1` (a transient `docker exec` timeout would freeze the
  whole ruleset every tick) and do NOT fall back to any broader set. Also (B1b,
  observability F2) add a **sustained-skip** escalation: when `container_running()`
  is false for ≥ a failcount threshold of consecutive ticks, emit
  `sentry_event op=resolve_container_view_skipped_sustained` (mirrors the existing
  per-host `FAILCOUNT_ESCALATE`) — a crash-looping container otherwise reproduces
  this exact residual unpaged. Add test scenarios to `cron-egress-firewall.test.sh`
  asserting BOTH (event fires AND the tick still completes additive-only, no
  `exit 1`, no widened set). Consistent with ADR-052 — it *restores* the §4 "BOTH
  RESOLVER VIEWS" invariant that was silently degrading (**no amendment**; note the
  fail-loud hardening in §4 prose).
- **B2 — genuinely per-query-randomised pool the resolver can never see (ADR
  amendment).** If B1a/B1b are ruled out and `getent` provably cannot ever see the
  app's subset, **re-open the ADR-052 §4 escalation decision — the options are
  already enumerated there** (the chosen escalation is selected at that time, not
  pre-committed now). **Two hard constraints carry into that decision:** (1) NOT a
  provider CIDR (rejected for shared-cloud LBs, #5413 learning); (2) **if a
  retention-seed option is chosen, the seed MUST be the container running `getent
  ahostsv4 <named-allowlisted-host>` and reporting the A-records, host-revalidated
  through the existing IPv4 `/32` regex before any union into `SEEN_DIR` — NEVER
  sourced from the container's observed-dialed destinations (conntrack/socket
  scrape)** (security review, P1: an observed-dialed seed lets a compromised
  container self-authorize egress to arbitrary IPs — a direct default-drop bypass;
  the contained container is the lower-trust party and must not become authoritative
  over which IPs are legitimate). B2 **amends ADR-052** (see ADR/C4 gate) and the
  amendment must name this constraint.

#### Branch C — Host not needed (stray / exfil)

1C.1 Do **NOT** widen the allowlist. Treat per runbook §"suspected exfil":
capture the Sentry event, identify the dialing cron via timing + `extra.sample`,
pause it via `TIER2_DEFERRED_CRONS` (`_cron-shared.ts`) pending forensics, and
escalate via `/soleur:incident`. (Low prior given steady first-party volume, but
the branch must exist.)

### Phase 2 — Verify (no SSH, no dashboard-eyeball)

2.1 Merge (Branch A/B): the allowlist/resolver hash folds into
`terraform_data.cron_egress_firewall.triggers_replace`;
`apply-web-platform-infra.yml`'s SSH block re-provisions on push to `main` (live
positive+negative container probes; **no manual apply**).
2.2 Confirm the apply is green (no `ASSERT-FAILED` —
`gh run view <id> --log | grep -E 'ASSERT-FAILED|cron-egress-nftables\] ERROR'`).
2.3 Confirm `egress-blocked` `104.16.x.34` DST hits **trend to zero within one
grace window** (read the Sentry issue event volume directly — the unmet
post-mortem recovery criterion). For Branch B confirm the resolver OK-log shows
the host's IPs now retained (`retained=` includes the `.34` set).
2.4 Re-validate the named flow (Sentry: confirm app events arrive; or
`/soleur:trigger-cron <event>` for a cron; or the user-facing flow).

### Phase 3 — Docs / lifecycle

3.1 **(all branches)** Flip the post-mortem
(`cron-egress-lb-rotation-outage-postmortem.md`) `status:` from
`unresolved but ended` back to **active** while this is open, then to resolved
once 2.3 confirms zero — and add this residual to its Action Items table with
issue `#5676`.
3.2 **(Branch B only — the retention-cannot-converge mechanism only *happened*
under Branch B; documenting it for a Branch-A allowlist-gap outcome would record a
non-event as root cause — simplicity review).** Extend the runbook
(`cron-egress-blocked.md`): add an **"anycast-disjoint host (retention cannot
converge)"** sub-section distinguishing it from the LB-rotation-window class (which
IS self-healing) — the key tell is "host's IPs never appear in any `getent` view"
vs "appear, just not within one tick". For a **Branch-A** outcome the runbook touch
is just a one-line note that the missing host was a CDN-anycast allowlist gap.
3.3 **(Branch B only)** Capture a learning
(`knowledge-base/project/learnings/bug-fixes/<topic>.md`, author picks date at
write-time): *grace-window retention is bounded by what `getent` observes; an
anycast subset the resolver never sees (or a dynamic host dropped despite being
resolved) is a distinct class from LB-rotation.* (Branch A needs no learning —
it is ADR-052 §3's allowlist-add process working as designed.)

## Files to Edit

- `apps/web-platform/infra/cron-egress-allowlist.txt` — **(Branch A)** add the
  identified host + evidence comment.
- `apps/web-platform/infra/cron-egress-firewall.test.sh` — **(Branch A)**
  `HOST_COUNT` 23→24 + per-host loop entry; **(Branch B1)** assert fail-loud
  container-view path.
- `apps/web-platform/infra/cron-egress-resolve.sh` — **(Branch B only)**
  fail-loud container-view resolution (B1) and/or host-pinned retention seed (B2).
- `apps/web-platform/infra/cloud-init.yml` (the fresh-host mirror referenced
  by the test's `$CLOUD_INIT`) — **(Branch B, if resolver/allowlist content the
  cloud-init mirror embeds changes)** keep the fresh-host mirror in sync (the
  test asserts cloud-init carries the artifacts).
- `knowledge-base/engineering/architecture/decisions/ADR-052-container-egress-firewall-docker-user-allowlist.md`
  — **(Branch B)** amendment; **(Branch B1)** §4 fail-loud note.
- `knowledge-base/engineering/operations/post-mortems/cron-egress-lb-rotation-outage-postmortem.md`
  — status flip + Action Items row (all branches).
- `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`
  — anycast-disjoint sub-section (all branches).
- `knowledge-base/engineering/architecture/diagrams/{model,views}.c4`
  — **(Branch A, only if the host is a NEW external system)**.

## Files to Create

- `knowledge-base/project/learnings/bug-fixes/<topic>.md` — Phase 3.3 learning.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — **Host named with evidence.** Phase 0 names the `104.16.x.34` host
  via a resolved-IP DoH match (path 2) AND/OR a Better Stack fetch error (path
  1); the PR body pastes the resolved-IP artifact. No branch is taken without a
  named host (Branch C included — "no flow dials it" is itself an evidenced
  finding).
  (AC2 was cut — the branch is self-evident from the diff shape: an allowlist line
  = Branch A, a resolver fail-loud edit = B1; a `session-state.md` "branch
  recorded" AC is process bookkeeping, not a checkable post-condition — simplicity
  review.)
- [ ] AC2 (Branch B, dynamic-host outcome) — **blind-window scoped.** The PR body
  states *when* the app-Sentry (or other dynamic-host) drop began, from the same
  Phase-0.1 14d event grouping — so the interval over which app-origin security
  events may have been lost is recorded (security review, P2).
- [ ] AC3 (Branch A) — `grep -Fxq '<host>' cron-egress-allowlist.txt` succeeds
  AND the line above it is an evidence comment (`file:line`).
- [ ] AC4 (Branch A) — `cron-egress-firewall.test.sh` passes: `HOST_COUNT` guard
  is `24`, the per-host loop includes `<host>`, and the whole suite is green
  (`bash apps/web-platform/infra/cron-egress-firewall.test.sh`).
- [ ] AC5 (Branch B1) — `cron-egress-resolve.sh` no longer swallows a
  container-running-but-empty `getent`; test scenarios assert BOTH (a) the
  `op=resolve_container_view_empty` event fires AND (b) the tick still completes
  **additive-only** (no `exit 1`, no widened set) — fail-loud is alert-not-abort
  (security P2). A sustained-skip scenario asserts
  `op=resolve_container_view_skipped_sustained` fires after the failcount threshold
  (observability F2).
- [ ] AC6 (Branch B) — ADR-052 carries the amendment (new dated amendment block
  under §4 or §Consequences) describing the chosen escalation, why a provider
  CIDR was NOT used, AND (if a retention-seed is chosen) that the seed is
  `getent`-of-named-host only, host-revalidated, never observed-dialed (security P1).
- [ ] AC7 — Post-mortem `status:` flipped (active while open) and an Action-Items
  row cites `#5676`. *(The `Ref #5676`-not-`Closes` convention is a PR-mechanics
  reminder, demoted to Risks/Sharp Edges — not an acceptance criterion — simplicity
  review.)*
- [ ] AC8 (Branch B) — Runbook carries the anycast-disjoint sub-section. (Branch A:
  one-line allowlist-gap note only — see Phase 3.2.)
- [ ] AC9 (Branch A, new external system only) — the `.c4` element + `#external`
  tag + edge + `views.c4 include` line are added; `c4-code-syntax.test.ts` +
  `c4-render.test.ts` green.

### Post-merge (operator-automatable — verified via CI/MCP, NOT SSH)

- [ ] AC10 — `apply-web-platform-infra.yml` apply is green (no `ASSERT-FAILED`);
  verified via `gh run view`.
- [ ] AC11 — `egress-blocked` `104.16.x.34` DST hits trend to **zero** within one
  grace window (≤24h); verified by reading the Sentry issue event volume (no
  dashboard-eyeball — pull the count). Then `gh issue close 5676`. **Caveat (arch
  P4 + observability F2):** if Phase-0.4 identified the B1b #5417 restart-loop as
  the driver, convergence is BLOCKED on #5417 — do NOT close #5676; keep the
  post-mortem active and record the #5417 dependency.
- [ ] AC12 — (Branch B) resolver OK-log shows the host's `.34` IPs now retained.
- [ ] AC13 — named flow re-validated. **If the host is Sentry ingest, the
  resumption signal is the host-side `egress-blocked` count → 0 + Better Stack app
  fetch-errors disappearing — NOT "Sentry events resumed" (circular).**

## Domain Review

**Domains relevant:** none (cross-cutting infra / security-control change;
CTO-owned). No Product/UI surface — Files to Edit are `*.sh`, `*.txt`, `*.c4`,
`*.md` only; the mechanical UI-surface override does NOT fire (no
`components/**`, `app/**/page.tsx`, or `app/**/layout.tsx` path). No
Marketing/Sales/Finance/Legal/Support/Operations business implication beyond
availability of an internal egress control. CTO/architecture concerns are
carried in `## Hypotheses`, `## Infrastructure (IaC)`, and the ADR/C4 gate. No
domain-leader Task spawned (single-domain engineering infra; `lane:
cross-domain` reflects the doc-surface span, not a business-domain span).

### Product/UX Gate

NONE — no user-facing surface created or modified.

## Infrastructure (IaC)

The change edits files under `apps/web-platform/infra/` that **auto-apply** — no
new infrastructure, no operator SSH, no new vendor/secret. Documented per
Phase 2.8 because infra files change.

### Terraform changes

- No new `*.tf` resource. The edited artifacts (`cron-egress-allowlist.txt`,
  `cron-egress-resolve.sh`, `cron-egress-firewall.test.sh`, cloud-init mirror)
  are hashed into `terraform_data.cron_egress_firewall.triggers_replace`
  (`apps/web-platform/infra/server.tf`); the resource taints + re-fires its SSH
  `remote-exec` provisioner on merge.
- No new `TF_VAR_*` / sensitive variable.

### Apply path

(b) cloud-init mirror + idempotent re-provision: `apply-web-platform-infra.yml`'s
SSH block re-runs the provisioner on push to `main` touching
`apps/web-platform/infra/**`. Expected downtime: none (additive allowlist edit;
atomic `nft -f`). Branch B's resolver change is also additive and timer-driven.
Blast radius: the egress firewall only (no app deploy).

### Distinctness / drift safeguards

`dev` has no egress firewall (prd-only host infra); no `dev != prd` precondition
needed. The fresh-host **cloud-init mirror** must stay in sync with any resolver
edit (the test asserts cloud-init carries the artifacts — Branch B must update
both). Secret values: none touched.

### Vendor-tier reality check

N/A — no paid-tier resource creation. (Cloudflare is the *destination*, not a
provisioned resource here.)

## Observability

```yaml
liveness_signal:
  what: "cron-egress-resolve Sentry Crons check-in (slug cron-egress-resolve), 1-min cadence; OK-log carries allow=/retained=/blocked_3m= counts"
  cadence: "every 1 min (cron-egress-resolve.timer)"
  alert_target: "Sentry Crons monitor cron-egress-resolve (missed check-in = dead resolver)"
  configured_in: "apps/web-platform/infra/cron-egress-resolve.sh (sentry_checkin); ADR-052 §5"
error_reporting:
  destination: "Sentry error event feature=cron-egress-firewall, op=egress_blocked (the egress-blocked issue 126858085); Branch B1 adds op=resolve_container_view_empty + op=resolve_container_view_skipped_sustained. CRITICAL: these events are POSTed HOST-side by sentry_event() (cron-egress-resolve.sh:94-118, line 109) on the host systemd timer — OUTSIDE the docker0 egress boundary — so detection survives even when the container->Sentry-ingest path is itself blackholed (the leading-candidate failure). The control's own forensics channel is provably disjoint from the failure it reports (observability F1, ADR-052 §5)."
  fail_loud: true
failure_modes:
  - mode: "dialed host not in allow set (this bug)"
    detection: "kernel journal egress-blocked: line counted each tick → Sentry op=egress_blocked with extra.sample DST + extra.hits"
    alert_route: "Sentry issue alert cron-egress-blocked (paging) → runbook cron-egress-blocked.md"
  - mode: "container-view getent silently empty, container RUNNING (Branch B1a)"
    detection: "Branch B1 fail-loud: op=resolve_container_view_empty event when container runs but getent returns nothing (today swallowed by 2>/dev/null || true at line 167-171)"
    alert_route: "Sentry (new op) → runbook anycast-disjoint sub-section"
  - mode: "container NOT running for N sustained ticks (#5417 restart-loop, B1b — observability F2)"
    detection: "op=resolve_container_view_skipped_sustained after a failcount threshold (mirrors per-host FAILCOUNT_ESCALATE); correlate with container-restart-monitor.sh container_restart_burst timestamps"
    alert_route: "Sentry (new op) → #5417; convergence blocked on #5417 until fixed"
  - mode: "resolver timer dead (allowlist frozen)"
    detection: "missed cron-egress-resolve Sentry Crons check-in"
    alert_route: "Sentry Crons monitor + OnFailure= cron-egress-alarm (Resend email)"
logs:
  where: "host journald (kernel egress-blocked/egress-dns-exfil lines; resolver OK-log). These kernel lines do NOT ship to Better Stack (Vector journald sources are unit-scoped) — the host-side direct-Sentry-envelope event (ADR-052 §5, distinct from the Vector journald layer) is the no-SSH forensics channel, and it is emitted host-side so it survives a container-egress blackhole."
  retention: "journald default on host; Sentry event retention for the issue history"
discoverability_test:
  command: "gh run view <apply-run-id> --log | grep -E 'ASSERT-FAILED|cron-egress-nftables\\] ERROR'  ;  doppler run -p soleur -c prd -- scripts/sentry-issue.sh --latest-event 126858085"
  expected_output: "zero ASSERT-FAILED after apply; sentry-issue.sh shows the egress-blocked latest-event hit count trending → 0 within one grace window"
```

No `ssh ` in any discoverability command (verification is `gh run view` +
`scripts/sentry-issue.sh` Sentry API read — both no-SSH).

## Architecture Decision (ADR/C4)

**Detection fires** (the issue explicitly offers "reconsider the IP-allowlist
approach for that host per ADR-052"). The ADR work is a **deliverable of this
plan**, branch-conditional — never a deferred follow-up.

### ADR

- **Branch A (allowlist gap):** no architectural change — adding a
  grep-enumerated host with evidence IS the ADR-052 §3 process working as
  designed. No ADR edit beyond, optionally, noting the host in §3's example list.
- **Branch B1 (resolver fail-loud):** **amend ADR-052 §4** with a dated note —
  the "BOTH RESOLVER VIEWS" invariant was silently degrading (fail-silent
  container `getent`); the fix makes it fail-loud. Restores, not reverses, the
  decision.
- **Branch B2 (anycast-disjoint escalation):** **amend ADR-052 §4 / §Consequences**
  with a dated amendment naming the chosen escalation (host-pinned retention seed
  / per-host SNI proxy / accepted residual) and explicitly recording why a
  provider CIDR was rejected for a shared-cloud LB (carry the #5413 learning's
  reasoning). Status note `adopting` if soak-gated.

### C4 views

**Read all three model files** (`model.c4`, `views.c4`, `spec.c4`). The egress
firewall is an infra-level detail **not** modeled in C4 (no element today —
confirmed: `grep -niE 'egress|firewall|allowlist'` over the three `.c4` files
returns only the unrelated `cloudflared` tunnel container and the `cloudflare`
external system). Enumeration for this change:

- **External human actors:** none new (no inbound correspondent/recipient).
- **External systems:** the platform's external systems are already modeled
  (`anthropic`, `github`, `cloudflare`, `doppler`, `discord`, `stripe`,
  `plausible`, `resend` — `model.c4:166-214`, included in `views.c4:14,34`).
  **Verify whether BOTH `sentry` AND `supabase` are modeled** (arch P6 — both are
  equally-likely dynamic candidates; the grep above did not confirm either). If
  Phase 0 names a host whose external system is absent (e.g. Sentry ingest →
  `sentry = system "Sentry" { #external }`; a Supabase sibling → confirm/add
  `supabase`), add the element + `#external` tag + the `webapp -> <sys> "…" {
  technology "HTTPS" }` edge + the `views.c4 include`. If the host is an
  already-modeled vendor (Cloudflare is), **no C4 change**.
- **Containers / data stores touched:** none.
- **Access relationships changed:** none (egress containment is not a C4
  relationship).

**"No C4 impact" is asserted only for the already-modeled-vendor outcome**, on
the enumeration above (actors: none; systems: all current egress vendors already
in `model.c4`; relationships: unchanged). A Sentry-ingest OR Supabase-sibling
outcome is the case that MAY require a `sentry`/`supabase` external-system
addition — a Phase-0 deliverable, not deferred. After any `.c4` edit, run
`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Sequencing

The ADR amendment (Branch B) is authored in the SAME PR as the resolver/runbook
edits — not postponed.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` checked; no open
scope-out names `cron-egress-allowlist.txt`, `cron-egress-resolve.sh`,
`cron-egress-firewall.test.sh`, or the ADR-052 / runbook / post-mortem paths.
(The contributing container restart-loop #5417 is tracked separately and is NOT
code-review-labeled; it is a *contributing* factor, out of scope here.)

## Test Scenarios

- **T1 (Branch A)** — `cron-egress-firewall.test.sh` green with `HOST_COUNT==24`
  and the new host in the per-host loop; deliberately omit the loop entry → FAIL
  (proves the exact-set guard bites).
- **T2 (Branch B1)** — resolver scenarios: (a) container running + `getent`
  returns empty → `op=resolve_container_view_empty` fires AND the tick still
  completes **additive-only** (assert no `exit 1`, no widened set — alert-not-abort,
  security P2); (b) container not running for ONE tick → legitimately skipped (no
  false page); (c) container not running for ≥ threshold consecutive ticks →
  `op=resolve_container_view_skipped_sustained` fires (observability F2).
- **T3** — resolver retention regression intact (existing #5413 scenarios still
  green — atomic add-then-prune, fail-safe-on-empty, additive-only on partial
  failure, eviction gated on prune tick).
- **T4 (negative containment, unchanged)** — a non-allowlisted host stays
  dropped (do NOT regress ADR-052's default-drop; the apply's
  `egress-probe-negative` assert proves it).

## Risks & Sharp Edges

- **Observability dependency on the very thing that's broken — and it is a
  SECURITY hole, not just availability (security P2).** If the host IS
  `SENTRY_INGEST_DOMAIN`, the app's Sentry is partially blackholed; diagnosis
  must lean on the **deterministic codebase enumeration (path 2)**, which does
  NOT depend on Sentry or cron stdout. The blackhole silently swallows auth
  anomalies, RLS-denial logs, BYOK-validation failures, and suspected-exfil app
  errors — so in *security* terms this residual is above p3 even though its
  *availability* class is p3. Detection survives only because `egress-blocked` is
  emitted host-side (outside docker0). Do not stall waiting for a Better Stack
  fetch error that the dropped-cron-stdout gap may never surface.
- **B2 retention-seed must never be observed-dialed (security P1).** If Branch B2
  chooses a retention-seed escalation, the seed MUST be the container running
  `getent ahostsv4 <named-host>` (host-revalidated through the IPv4 regex), NEVER
  the container's observed connection destinations (conntrack/socket scrape) — the
  latter lets a compromised container self-authorize egress to arbitrary IPs, a
  direct default-drop bypass. The contained container must not become authoritative
  over which IPs are legitimate.
- **Do NOT "fix" with a provider CIDR.** Allowlisting Cloudflare `104.16.0.0/13`
  would let a compromised spawn-bash cron egress to any Cloudflare tenant —
  defeats ADR-052's default-drop. This is the explicit anti-pattern from the
  #5413 learning; a provider-CIDR escalation is rejected for shared-cloud LBs.
- **Governance is worst-case-driven (arch + simplicity review).** `requires_cpo_signoff`
  + `single-user incident` threshold are set for the worst plausible (blackholed
  Sentry / silently-failing user flow) BEFORE diagnosis. If Phase 0 confirms a
  benign Branch-A host with no user- or security-facing flow, the threshold can be
  downgraded at review and the CPO sign-off treated as satisfied — do not let the
  worst-case framing block a one-line allowlist fix.
- **A `.34`-constant pool is a single-zone fingerprint, not a broadening.** Do
  not conclude "Cloudflare is huge, untrackable"; the constant host-octet means
  ONE customer zone — bounded and identifiable by enumeration.
- **`Ref #5676`, not `Closes #5676`.** Ops-remediation: the merge does not fix
  prod; the apply + grace-window does. Auto-closing at merge = false-resolved.
- **Pin every network call** (`curl --max-time`, `dig +time=2 +tries=2`) in any
  diagnostic/CI step — unbounded calls hang CI on flake.
- **Cloud-init mirror sync (Branch B).** The fresh-host cloud-init mirror embeds
  the resolver; the test asserts it carries the artifacts. A resolver edit that
  forgets the mirror fails the test (intended).
- **`## User-Brand Impact` is filled (not placeholder)** — required or
  deepen-plan Phase 4.6 halts.
- **Empty-section guard:** all gate sections above are populated; do not let
  deepen-plan see a `TODO`/`TBD` field value (Observability/IaC schemas are
  filled).

## Rollback

Revert the allowlist/resolver commit → `terraform_data.cron_egress_firewall`
re-fires on the revert merge and restores the prior ruleset (additive edits
revert cleanly; the default-drop boundary is never weakened by this plan, so a
rollback cannot open egress). The post-mortem status flip and runbook/ADR edits
are docs — revert with the same commit.
