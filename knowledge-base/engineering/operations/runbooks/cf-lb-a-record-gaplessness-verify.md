---
category: infrastructure
tags: [cloudflare, load-balancer, dns, gaplessness, multi-host, ga, adr-068]
date: 2026-07-03
---

# Cloudflare A-record → Load Balancer gaplessness verification — ADR-068 §(b)

Operator runbook to **verify, before the multi-host GA maintenance window**, that putting a
**Cloudflare Load Balancer** in front of the live web origin is zero-downtime. ADR-068 §(b)
records this gaplessness as an **UNVERIFIED Cloudflare-behavior claim** and prescribes the
remedy verbatim:

> *"verify against CF docs + a staging convert before the GA window."*

This runbook is that verification. **Verdict: GAPLESS-ONLY-IF** — the swap is neither
intrinsically gapless nor intrinsically gapped; the outcome is decided entirely by *how the
Terraform is written*. A naive "delete A record, create LB" replace **has a gap**; an
**overlay-add** (retain the A record, add the LB on top) is **gapless**. The four conditions
and the concrete sequence are below.

**No SSH.** All verification is read from the Cloudflare API/dashboard and an operator
`curl` loop from a laptop, per `hr-no-ssh-fallback-in-runbooks`. You never SSH a host to
confirm continuity — you observe the hostname's HTTP answer from outside.

> **Verified via Cloudflare docs + read-only DNS/zone API (2026-07-03).** Items that could
> **not** be verified are called out explicitly under "Still unverified" — do not treat them
> as cleared.

---

## Live facts (read-only, established 2026-07-03)

| Fact | Value |
|---|---|
| Web hostname | **`app.soleur.ai`** (apex/`www` are GitHub Pages — out of scope) |
| Current record | **A**, content `135.181.45.178` (Hetzner web-1), **proxied=true**, TTL=1 (auto), id `f45920a35b3c184b3a70196cded45889` |
| Public resolution | `104.21.7.210` / `172.67.188.7` (Cloudflare anycast — origin IP hidden), answer TTL 299s |
| `/health` at edge | HTTP **200**, body keys `status, version, build_sha, supabase, sentry, uptime, memory` |
| Zone plan | **Free Website** — Load Balancing is a **separately-billed add-on** (see Blocker 1) |

---

## The claim under test

Fronting `app.soleur.ai` (currently `cloudflare_record.app` → web-1) with a Cloudflare Load
Balancer (v4 provider — the repo pins `cloudflare ~> 4.0`, **not** v5) **serves
continuously** — no NXDOMAIN, no empty answer, no 5xx window — for real user traffic.

### Why this is dangerous enough to gate

`cloudflare_record.app` is the **sole** origin for live traffic. web-1 is the only host in
rotation; a resolution gap on `app.soleur.ai` is a **full-site outage**, not a degraded one.

### The finding that flips the assumption — coexistence

A Load Balancer and a regular proxied A record **can coexist on the same hostname**.
Cloudflare: *"the LB record takes precedence when it is more or equally specific"* (same
hostname ⇒ LB wins while active), and the plain record *"will be served [when] a load
balancer is disabled."* So the correct cutover is an **in-place overlay ADD**, not a
destructive replace — and the retained A record becomes an automatic fallback for a disabled
LB.

> **⚠️ This corrects ADR-068 §(b) and the `dns.tf` comment.** Both currently frame the A→LB
> change as a **destroy+recreate of the live record** ("no `moved` block / stable import id on
> `cloudflare_record.app`"). That framing describes the **gapped** path. The **gapless** path
> does **not** migrate or destroy the record at all — it *keeps* `cloudflare_record.app` and
> adds a `cloudflare_load_balancer` on the same name, never modelling the two as a Terraform
> replace. The GA cutover PR must:
> 1. **retain** `cloudflare_record.app` (do not delete / convert it), and
> 2. rewrite the stale `dns.tf` comment (which still describes the *older* `for_each`
>    round-robin A-record design, itself superseded by the LB).
>
> **Decided (2026-07-03, PR #5968):** the overlay model is adopted — ADR-068 §(b) amended
> (correction b.1). The GA PR retains `cloudflare_record.app` and rewrites the `dns.tf` comment.

---

## Preconditions

- ADR-068 status `adopting`; you have read §(b) and §(c) (the hard invariant).
- Cloudflare access with **read** on the zone and **Load Balancing read** scope (the audit
  token used for the live facts above **lacked** LB scope — see "Still unverified").
- Write scoped to a **staging** hostname only for Part 2. Do **not** hold write on
  `cloudflare_record.app` during this runbook.
- You can run a `curl` loop from a network **outside** Cloudflare (operator laptop), so the
  observed answer is the real edge answer, not a same-host loopback.

---

## Part 1 — Static verification (resolved against CF docs + live zone)

| # | Question | Finding | Status |
|---|---|---|---|
| A | Can a proxied A record and an LB coexist on one hostname? | **Yes** — LB overrides while active; A record is the disabled-LB fallback. Cutover is an overlay ADD, not a replace. | ✅ verified (docs) |
| B | Replace ordering / the gap | Gap exists **only if** modelled destructively (destroy-record-first ⇒ authoritative-NXDOMAIN window, negatively cacheable). **Retain the record + add the LB** ⇒ no destroy, no gap. `create_before_destroy` is irrelevant (nothing is destroyed). | ✅ verified (docs) |
| C | Edge vs client caching | **Favors gapless.** Both current record and LB are **proxied**, so the public answer stays CF anycast; resolvers keep hitting the same edge. Only the edge's *internal* routing flips (proxy→origin ⇒ LB steering), propagating edge-wide in **seconds** (Quicksilver). **No client-side TTL wait.** The 299s TTL would matter only if grey-clouded — it is not. | ✅ verified (docs) |
| D | Cold-LB serve-while-unknown | **Real risk.** A monitored pool is "down" while health is still **unknown** (before the first probe, default interval 60s) ⇒ a bare LB would 5xx in that window. Neutralized **only** by a fallback pool: fallback-pool health is **not evaluated**, so it serves through the unknown window. **⇒ `fallback_pool` MUST = web-1 pool** (Blocker 3). | ✅ verified (docs) |
| E | `/health` info-disclosure as the monitor target | LOW-MED. `/health` publicly exposes `version` + `build_sha` (CVE/commit matching) and `supabase`/`sentry`. A *reachability* monitor needs only the status code. **Already public today** (the LB does not worsen it), so **not a gaplessness blocker** — track a bodyless `/healthz` / `HEAD /` as hardening (natural to add alongside #5966). | ✅ verified |
| F | Monitor probe path & origin firewall | Monitors probe the **origin IP:port DIRECTLY** (from CF data centers, UA `Cloudflare-Traffic-Manager/1.0`), **not** through the proxy. The Hetzner firewall must allow CF prober ranges to `135.181.45.178:<port>`. Because the origin already accepts proxied CF traffic (orange-clouded today), the CF ranges are **very likely already allowlisted** — but **verify against the actual Hetzner firewall** (Blocker 4). | ⚠️ verify live |

---

## Part 2 — Staging convert (empirical continuity + de-risk the one assumed step)

Docs say the overlay is gapless, but the **Terraform provider's** exact behavior when a
`cloudflare_load_balancer` is created while a same-name `cloudflare_dns_record` is *retained*
is **assumed, not verified** (see "Still unverified"). Part 2 de-risks precisely that on a
**throwaway hostname**, so a mistake cannot touch `app.soleur.ai`.

1. Create a staging proxied A record (e.g. `lb-staging.soleur.ai`) → web-1's IP, mirroring
   `cloudflare_record.app`. Let it settle.
2. Start a **continuity probe** from the operator laptop (outside Cloudflare) that records
   HTTP status + a millisecond timestamp each tick, so any gap is visible:

   ```bash
   while true; do
     printf '%s ' "$(date +%s%3N)"
     curl -s -o /dev/null -w '%{http_code}\n' --max-time 2 https://lb-staging.soleur.ai/health \
       || echo "CURL_FAIL"
     sleep 0.2
   done | tee /tmp/lb-staging-continuity.log
   ```

3. With the loop running, apply the **overlay-add** on the staging hostname using the **exact**
   v4 resource shapes the GA PR will use (Part 3): **retain** the `lb-staging` A record and
   **add** `cloudflare_load_balancer_monitor` + `_pool` + `cloudflare_load_balancer` (origin =
   web-1 weight 1, `fallback_pool` = that pool). Do **not** model the record and LB as a replace.
4. Stop the loop after the apply settles. Inspect `/tmp/lb-staging-continuity.log`:
   - **Zero** non-200 / `CURL_FAIL` ticks → gapless at 200 ms resolution. ✅
   - Any gap → count consecutive failures × 200 ms ≈ the outage window → decides GO / NO-GO.
5. Tear down the staging LB + record; confirm (read-only list) the zone is clean.

> If 200 ms sampling is too coarse to trust "gapless," tighten to `sleep 0.05` or run two
> offset loops. Record the actual sampling resolution with the verdict — do not claim "gapless"
> beyond what you measured.

---

## Part 3 — Monitor & steering design (from the platform-strategist pressure-test)

The GA LB monitor MUST be **reachability-only** and MUST NOT parse the response body.
**Verified (source):** `apps/web-platform/server/index.ts` returns HTTP **200
unconditionally** — Supabase state is body-only (`supabase: "connected"|"error"`), never the
status code. Both hosts share one Supabase, so a body-coupled monitor would mark **both**
origins down on a DB blip and eject the sole live origin → full ingress outage (ADR-068 §(b)).

```hcl
resource "cloudflare_load_balancer_monitor" "web" {
  account_id       = var.cf_account_id
  type             = "https"
  method           = "GET"          # or HEAD against a bodyless /healthz (Part 1-E hardening)
  path             = "/health"      # liveness today; see C1 / #5966 below
  expected_codes   = "2xx"          # reachability-only — do NOT set expected_body*
  interval         = 60             # T1
  timeout          = 5              # T1
  retries          = 2              # T1
  consecutive_down = 2              # T1 — 2 consecutive fails before "down" (absorbs a flap)
  consecutive_up   = 1              # T1 — recover on first success
  # check_regions  = ["WEU"]        # T1 — pin near Hetzner; fewer false-down votes than all-region
}
# * If expected_body is EVER set, match an always-present substring like "status":"ok".
#   Matching "supabase":"connected" reintroduces the DB-coupling ADR-068 §(b) forbids.

resource "cloudflare_load_balancer_pool" "web_1" {
  account_id = var.cf_account_id
  name       = "web-1-pool"
  monitor    = cloudflare_load_balancer_monitor.web.id
  origins {
    name    = "web-1"
    address = hcloud_server.web["web-1"].ipv4_address  # 135.181.45.178
    weight  = 1
  }
}

resource "cloudflare_load_balancer" "app" {
  zone_id         = var.cf_zone_id
  name            = "app.soleur.ai"
  default_pools   = [cloudflare_load_balancer_pool.web_1.id]  # web-2 pool ABSENT pre-GA (B2)
  fallback_pool   = cloudflare_load_balancer_pool.web_1.id    # B1 — CRITICAL
  steering_policy  = "off"                                    # T2 — failover-by-order while one live origin
  proxied         = true
  # session_affinity = "cookie"  # B3 — enable only AT/AFTER GA as defense-in-depth, never as "safety"
}
# NOTE: cloudflare_record.app is RETAINED (overlay), NOT part of this change. Do not replace it.
```

### HARD BLOCKERS (both pressure-tests converged)

- **B1 / condition D — `fallback_pool` MUST be the web-1 pool. The single most load-bearing
  knob (both agents, independently).** There is only one healthy origin and no second pool to
  fail over to. CF does **not** evaluate a fallback pool's health, so any transient probe miss on
  web-1 (GC pause, Supabase-induced event-loop latency spike, one bad probe region) would
  otherwise mark the only pool down and — with no fallback — return **530 / HTTP 1016 to every
  user**, a total outage *caused by the probe layer*, strictly worse than today's bare A record.
  `fallback_pool = web-1` keeps web-1 serving even while its own monitor reports down, and **also
  closes the cold-LB unknown-health window (D)** — no separate serve-while-unknown flag needed.
  Without B1 the LB is a net availability **regression**.

- **B2 — Drain web-2 structurally (`enabled = false` / omit from `default_pools`), NOT
  `weight = 0`.** ⚠️ **Refines ADR-068 §(b)** (which prescribes `weight = 0`). The ADR is right
  as a *v4-vs-v5 syntax* choice (v4 has no `endpoint_drain_duration`), but `weight = 0` is a
  **soft** signal: a session-affinity cookie overrides it (would pin a user onto weight-0 web-2),
  and weight lives inside `random_steering`/`origin_steering` blocks a refactor can silently drop.
  Expressing the drain as pool-absent-from-`default_pools` makes the "no live weight to web-2"
  **hard invariant** a *schema fact*. Reserve `weight` for post-GA traffic-proportioning.
  **Decided (2026-07-03, PR #5968):** structural drain adopted — ADR-068 §(b) amended
  (correction b.3). The GA PR drains web-2 via pool-absent-from-`default_pools`, not `weight = 0`.

- **B3 — The owner-side router relay (invariant item 3) is the correctness mechanism; LB
  session-affinity is ONLY defense-in-depth and must not be mistaken for cross-host safety.** CF
  affinity pins a user to an *arbitrary*, non-workspace-aware origin; worse, affinity **failover
  re-pins to another healthy origin**, so on a web-1 blip it would move a user whose `/workspaces`
  is on web-1 onto bare web-2 — a "workspace vanished" event. Until the relay is active AND
  git-data is cut over, the only safe state is B2 (web-2 gets **zero** user traffic). At/after GA,
  use `session_affinity = "cookie"` (never `ip` — CGNAT/mobile/corporate-egress flip hosts),
  `session_affinity_ttl` ≈ a working session (1800–3600 s), as defense-in-depth only.

### C1 / deep-readiness (#5966) — TWO monitor tiers, not one repointed monitor

`/health` is a **liveness lie** for a bare host (returns 200 with empty `/workspaces`, #5966).
Do **not** repoint the *live* monitor at deep-readiness — it checks Supabase / the mount, which
would reintroduce the "DB blip ejects the sole origin" failure. CF's per-pool monitor model
supports the clean split:

1. **Public reachability monitor** (T1) on the **web-1 pool** — DB-decoupled, never ejected.
2. **Deep-readiness (#5966) as the drain/undrain *gate* consulted by tooling** — before web-2's
   pool is ever enabled, the cutover tooling curls deep-readiness and refuses to undrain if not
   ready. web-2 is gated *into* the pool by readiness, not judged healthy *after* it serves.
3. **Post-cutover:** give the **web-2 pool its own monitor at deep-readiness** (per-pool monitors
   let hosts differ), optionally `monitoring_only` first to observe before it gates routing.

---

## Concrete gapless cutover sequence (for the GA PR)

1. **Verify the Load Balancing subscription exists** (Blocker 1 — the zone is Free plan).
2. **Retain** `cloudflare_record.app` (proxied A → `135.181.45.178`). Do **not** delete it or
   model it as a replace.
3. Create the **monitor** (Part 3; reachability-only, ideally a bodyless path per 1-E).
4. Create the **web-1 pool** (origin `135.181.45.178` weight 1; monitor attached). web-2 pool
   drained structurally (B2) — absent from `default_pools` until GA.
5. Create the **load balancer**: `name = app.soleur.ai`, `default_pools = [web-1 pool]`,
   **`fallback_pool = web-1 pool`** (B1), `proxied = true`. On create it overlays and overrides
   the A record; the fallback pool covers the unknown-health cold window; the first probe (≤~60s)
   then confirms healthy and normal steering resumes.
6. Confirm `curl -sI https://app.soleur.ai/health` stays 200 throughout.
7. Leave the A record in place as the disabled-LB fallback (or remove it later once proven).

---

## Verdict & decision gate

**GAPLESS-ONLY-IF** all four conditions hold; otherwise NO-GO on the naive path:

1. **[BLOCKER — verify] Load Balancing subscription** purchased for the zone (Free plan; LB is a
   separately-billed add-on available on all tiers *if* subscribed — an absent subscription fails
   the LB create outright). **Unverified** — audit token lacked LB/billing scope.
2. **[BLOCKER — model correctly] Overlay, not replace.** Retain `cloudflare_record.app`; add the
   LB. A destructive replace reintroduces the NXDOMAIN gap.
3. **[BLOCKER — configure] `fallback_pool = web-1`.** Without it, the cold-LB unknown-health
   window returns 5xx/530.
4. **[VERIFY live] Hetzner origin firewall** allows CF health-check prober ranges directly to
   `135.181.45.178:<port>`. Likely already satisfied (orange-clouded today); confirm.

- **GO** once 1–4 are confirmed **and** Part 2's staging convert shows zero gap at the stated
  sampling resolution → the GA PR may perform the overlay-add in the window.
- **NO-GO** if Part 2 shows a measurable window → do not run the swap; redesign / bounded
  maintenance banner, and re-verify.

### Instant-abort lever (during the real GA window)

1. **Seconds — abort button:** dashboard/API **disable the offending pool**, or toggle the LB
   `enabled = false` / set `default_pools` to web-1 only. One API call, propagates in seconds.
   (With the A record retained per the overlay model, a disabled LB **automatically falls back to
   the A record** → web-1 keeps serving.)
2. **Seconds — pre-staged bypass:** optionally keep a standby `origin-web-1.soleur.ai` A record
   *outside* the LB; the nuclear revert repoints `app` back to it, fully bypassing a broken LB.
3. **Do NOT use as the abort:** `terraform destroy` / flipping `cf_load_balancing_enabled` —
   code-speed, risks the DNS record mid-destroy. Terraform is the **cleanup** path *after* the
   incident, never during.

---

## Still unverified (do NOT record as verified)

- **LB subscription / account billing status** — out of the audit token's scope (Blocker 1).
- **Live absence of any existing LB / pool / monitor** at the CF edge — LB endpoints returned
  auth error 10000 (token lacked LB read scope). The "greenfield, no LB Terraform" ground truth
  is trusted but not independently confirmed at the edge.
- **Terraform provider behavior** creating `cloudflare_load_balancer` while a same-name
  `cloudflare_dns_record` is retained — coexistence/overlay is confirmed for the dashboard/API
  via docs, but the TF-path equivalence is **assumed**. Part 2 exists to confirm it empirically.
- **Exact CF health-check prober IP ranges** — general "direct from CF data centers" behavior
  confirmed; specific ranges not enumerated (Blocker 4).
- **Cloudflare MCP OAuth was not completed** in the headless verification (needs the operator's
  browser flow); all live facts came from the read-only `CF_API_TOKEN_AUDIT`.

---

## Expense

The Load Balancer is a **separately-billed add-on** (~$5/mo baseline; per-LB + per-pool +
DNS-query components). Per the recurring-vendor-expense gate, record it in the expense ledger
**before** the GA PR is marked ready — do not let the LB apply be the first place the cost
appears. Confirming the subscription (Blocker 1) is the same step that surfaces the price.

---

## References

- **Design:** ADR-068 §(b) Amendment (2026-07-03, #5887 blue-green ingress) —
  `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md`
- **Plan:** `knowledge-base/project/plans/2026-07-03-feat-multi-host-blue-green-ingress-prereqs-plan.md`
- **Deep-readiness prerequisite (C1):** #5966
- **Related cutover runbooks:** `git-data-luks-cutover-5274.md` (§ Multi-host DNS rewire),
  moved-block wedge cutover (PR #5946)
- **Code:** `apps/web-platform/infra/dns.tf` (`cloudflare_record.app`),
  `apps/web-platform/infra/main.tf` (provider pin `cloudflare ~> 4.0`),
  `apps/web-platform/server/index.ts` (`/health` always-200), `server/health.ts`
- **Cloudflare docs:** [LB & DNS records](https://developers.cloudflare.com/load-balancing/load-balancers/dns-records/),
  [health details](https://developers.cloudflare.com/load-balancing/understand-basics/health-details/),
  [traffic steering / fallback pool](https://developers.cloudflare.com/load-balancing/understand-basics/traffic-steering/steering-policies/standard-options/),
  [monitors](https://developers.cloudflare.com/load-balancing/monitors/)
