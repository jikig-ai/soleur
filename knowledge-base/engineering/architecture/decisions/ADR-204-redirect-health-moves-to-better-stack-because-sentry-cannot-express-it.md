---
title: "ADR-204 — redirect-health moves to Better Stack, because Sentry cannot express it"
status: accepted
date: 2026-09-07
tags: [observability, uptime-monitoring, sentry, better-stack, terraform, redirects, single-vendor]
related_adrs: [ADR-194, ADR-175]
related_runbooks:
  - knowledge-base/engineering/operations/runbooks/www-redirect-alarm.md
---

# ADR-204: Redirect-health moves to Better Stack, because Sentry cannot express it

- **Status:** Accepted
- **Date:** 2026-09-07
- **Issue:** [#7798](https://github.com/jikig-ai/soleur/issues/7798)
- **Ordinal note:** re-derived across all **74** `origin/*` refs, not `origin/main`
  alone — the corpus topped out at ADR-203. Re-derive again at ship: the ref count
  moves, and this note is the kind of number that rots silently (it read 71 when
  first written, hours earlier).

## Related

- Amends [ADR-194](./ADR-194-migrate-marketing-docs-site-off-github-pages-to-cloudflare-pages.md)
  in two places (its third, 526-related passage is deliberately untouched — a 2xx
  assertion fails on a 526 exactly as the old one would have).
- Operator destination: [the www-redirect alarm runbook](../../operations/runbooks/www-redirect-alarm.md).

## Context

`sentry_uptime_monitor.soleur_www` asserted `equals 301` on
`https://www.soleur.ai/` from 2026-05-29 (#4577) to 2026-09-07. It never passed a
single check.

The declared config was correct, and the live config matched it byte for byte, so
this was not drift. The assertion is **structurally unsatisfiable**:

- `getsentry/uptime-checker`'s `reqwest_checker.rs` builds its client with no
  `.redirect(...)` override, inheriting `Policy::limited(10)`. There is no
  `CheckConfig` field and no API parameter to disable redirect-following.
- In the same file the assertion is evaluated as
  `compiled_assertion.eval(r.status(), r.headers(), &body_bytes, …)`, where `r` is
  the response from `client.execute()` — the **terminal** response.
- Sentry's own documentation states it: *"Sentry will follow redirects … and
  verify that the final destination URL returns a successful response."*

So the checker followed www's 301 to the apex's 200 and compared `equals 301`
against `200`. Measured 2026-09-07: 10/10 most recent checks failing, every row
carrying `httpStatusCode: 301` beside an `assertionFailureData` naming the
`equals 301` assertion.

Two facts initially read as counter-evidence and both resolve:

- The sibling ACME probe asserts `equals 404` and succeeds — but its URL returns
  404 with no `Location`, so the chain terminates at hop 0. It never exercises
  redirect-following.
- The `httpStatusCode: 301` on the failing rows looks like a contradiction. It is
  a per-hop artifact: `src/types/result.rs` builds one `RequestInfo` per redirect
  hop, and the EAP converter stamps the check-level verdict — computed once, from
  the final response — onto every hop's row.

The whole assertion catalog in the pinned provider (`jianyuan/sentry 0.15.7`)
reads the terminal response: `op_status_code_check`, `op_header_check` and
`op_jsonpath` alike. That kills the fix that looked most attractive —
`op_header_check` on `Location` — because the final response is the apex's 200
and carries no `Location`. **There is no way to express "www must 301 to apex" as
a Sentry uptime assertion.**

Meanwhile the property was load-bearing without anyone noticing. `dns.tf`'s
"WHY www STAYS A CNAME" ruling (Camp B) accepts a real failure mode — *"if the
Bulk Redirect ever stops firing, www SERVES the site (duplicate content for one
monitor interval) rather than returning a 522"* — and the bound in that sentence
was supplied by this monitor. The accepted bound was never one interval. It was
unbounded.

## Decision

**Move redirect-health to Better Stack, and narrow the Sentry monitor to what it
can actually assert.**

1. `betteruptime_monitor.soleur_www_redirect` (`uptime-alerts.tf`) asserts
   `expected_status_codes = [301]` with `follow_redirects = false` — the only knob
   in the stack that can see a pre-redirect hop. 180s cadence, 1200s confirmation.
2. `sentry_uptime_monitor.soleur_www` is retargeted to `local.uptime_assertion_2xx`
   and **renamed** `soleur_www_reachability` / `"soleur-ai-www-reachability"`. A
   retargeted assertion under the old name would reproduce, deliberately, the trap
   documented one resource away on `soleur_acme_probe`: a name that outlives the
   property it names.
3. The `deploy-docs.yml` pause/resume bracket is removed. Its purpose was to hide
   a deploy-window false page under the old assertion; a transient 200 passes a
   2xx assertion. The window is absorbed by `confirmation_period = 1200` instead —
   a timer, not a vendor mutation.

### The "vendor isolation, not URL coverage" principle is amended, narrowly

`uptime-alerts.tf`'s header says Better Stack exists for **vendor isolation**, not
URL coverage — one probe to prove `soleur.ai` is reachable when Sentry is the
thing that is broken. That still governs every other monitor in the file.

It does not govern a property Sentry **cannot represent at all**. This monitor is
added on capability grounds, not coverage grounds, and the amendment extends no
further.

### Consequence: redirect-health is single-vendor, and that is recorded, not implied

Apex reachability is deliberately second-sourced across Sentry and Better Stack,
so a Sentry outage is survivable. **The www 301 is watched by Better Stack alone.**

This is a gain — the property went from zero working alarms to one, not from two
to one — but a future engineer must not infer second-sourcing from the apex
pattern. A Better Stack outage leaves this property uncovered.

## Measurement, before the code

The design rested on one claim taken from vendor documentation rather than
measured: that `follow_redirects = false` + `expected_status_codes = [301]`
evaluates the pre-redirect 301. If wrong, the new monitor would be as vacuous as
the one it replaced, and the change would have reproduced this issue's own defect
on a second vendor.

Three transient monitors were created against the live URL with
`confirmation_period = 0`, observed, and deleted:

| Probe | Config | Result |
|---|---|---|
| main | `[301]`, no-follow | **up** against the live 301, all four regions |
| control A | `[200]`, no-follow | **down** — differs by one token |
| control B | `[301]`, follow | **HTTP 422, refused at create** |

Control A is what makes the result mean anything: a monitor reporting `up` proves
nothing on its own, since a vacuous one reports `up` too.

Control B is a stronger outcome than expected. Better Stack refuses the vacuous
combination outright — `"Cannot follow redirects when expecting a 3xx status
code"` — so the defect this ADR exists to fix is **unrepresentable** on the new
substrate.

The same probe surfaced a required attribute the design did not have.
`remember_cookies` is `computed` in the pinned provider, so omitting it lets the
API default (`true`) apply, and the create fails: `"Cannot keep cookies when
redirecting when expecting a 3xx status code"`. Without `remember_cookies = false`
the resource would have merged and never applied.

## Alternatives considered

| Approach | Why not |
|---|---|
| Dispatch an apply to converge the monitor (the issue's own primary remediation) | Live config already equalled declared config. Measured, not assumed |
| Recreate / `-replace` it (the issue's fallback) | Reproduces byte-identical config against an unsatisfiable assertion. Also unreachable: `assertion_json` is an in-place attribute in the pinned provider |
| `op_header_check` on `Location` in Sentry | Header ops read the terminal response, which is the apex's 200 and carries no `Location` |
| Assert `equals 200` on www and call it redirect-health | Passes equally when www serves its own 200 — the exact regression under guard. Vacuous |
| A scheduled GitHub Actions probe checking in to a Sentry cron monitor | Rejected on minimality and MTTD: a workflow, a script, a cron monitor and a test battery for ~2 h detection — which would have silently widened the `dns.tf` Camp B acceptance from "one monitor interval" to two hours |
| Delete `sentry_uptime_monitor.soleur_www` outright | Better Stack carries no www monitor today, so www would lose **all** reachability coverage — DNS, TLS and 5xx detection on a distinct CNAME surface, not merely the already-lost redirect-health |

## Residual gap

No uptime vendor can assert the redirect's **target**. "www 301s, but to the wrong
host" and "the 301 is served by a stale origin" remain runtime-undetected. They
are covered at PR time by `www-apex-canonicalizer.test.sh` (source and target
hosts, `status_code = 301`), at cutover time by `cutover-verify.sh` CUT3/CUT4, and
on demand by `cutover-verify.sh --check-www-redirect`.

Reaching that state requires a change made **outside** Terraform, which the
declared-config gate blocks on the only path Terraform owns. A runtime target
assertion is deliberately not built here. Re-evaluation trigger: any evidence of a
Cloudflare-side change reaching production without a Terraform apply. Tracked on
[#7883](https://github.com/jikig-ai/soleur/issues/7883).

### Intermittent failure is not covered, and that is an assumption, not a measurement

`confirmation_period = 1200` opens an incident only on **sustained** failure, and
`recovery_period = 60` is shorter than the 180 s cadence. So a redirect that fails
on *some* fraction of checks — partial edge propagation, a regional Bulk Redirect
fault — plausibly dismisses the pending incident on every green check and never
opens one, at any duration.

Stated as an assumption because it was not measured: the Phase 0 harness (a
transient monitor at `confirmation_period = 0`, created, observed and deleted) can
answer it, but doing so needs a URL that flaps on demand, which we do not have.
Confidence is moderate, not high. **Re-evaluation trigger:** any observed www
redirect fault that the alarm did not report.

Separately, the Better Stack workspace holds an **unmanaged** fourth monitor
(`app.soleur.ai/health`, id 4226366) that is not declared in any root — found only
because the free-tier quota was measured live rather than counted from `.tf`
blocks. Tracked on [#7884](https://github.com/jikig-ai/soleur/issues/7884).

## Consequences

- The www 301 has a working alarm for the first time since the assertion landed.
- `dns.tf`'s Camp B acceptance has a real bound (~23 min) for the first time. Do
  not widen `confirmation_period` without revisiting that ruling — and the value is
  now pinned by `www-apex-canonicalizer.test.sh`, so that sentence cannot rot.
- Worst-case detection of a genuine regression is **~23 min** — up to one 180 s
  check interval to observe the first failure, plus the 1200 s confirmation window
  (1380 s). Not "~20 min rather than ~15": the prior bound was not 15 minutes, it
  was UNBOUNDED, because the assertion supplying it could not fire. Comparing the
  two as though both were delivered would restate the very claim this ADR retracts.
  The cadence term is additive and is easy to drop — this ADR did drop it in draft;
  the repo's own precedent grades `soleur_apex`'s 180 + 60 as "~4 min".
  900 s was rejected as having exactly zero margin over the observed 15-minute
  rebuild window.
- `deploy-docs.yml` no longer holds a Sentry credential of any kind — `jq` and
  every `SENTRY_*` secret were used only by the removed steps.
- Better Stack usage goes to 4 monitors of 10 on the free tier. No recurring cost:
  the monitor is ungated and policy-less, riding the existing email path.
