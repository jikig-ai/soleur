# Brainstorm — zot mirror-fallback alarm: unreachable threshold (#6285 re-scope)

**Date:** 2026-07-15
**Issue:** #6285 (re-scoped)
**Branch:** `feat-6285-zot-metric-alert`
**PR:** #6424 (draft)
**Lane:** cross-domain
**Leaders:** CPO, CLO, CTO (mandatory triad, `USER_BRAND_CRITICAL=true` per #5175)

## What We're Building

A one-line change to `apps/web-platform/infra/sentry/issue-alerts.tf`:

```hcl
# resource "sentry_issue_alert" "zot_mirror_fallback_rate", conditions_v2 (~:1380)
- value = 3    # fires at >3, i.e. >=4
+ value = 0    # fires at >0, i.e. on the first event in any group
```

Plus the comment correction that explains why, and retirement of the `sentry_metric_alert`
upgrade idea that #6285 originally asked for.

## Why This Approach

#6285 asked to upgrade the alarm to a `sentry_metric_alert` (cross-signal aggregate) once a
"resolvable numeric notify target" existed. **The premise was wrong on three counts, and the
proposed fix targeted the wrong defect.**

### The real defect: the threshold is arithmetically unreachable

- `ci-deploy.sh:607` builds the message as
  `"image pulled from " + $reg + " (" + $img + ":" + $t + ")"` — the **unique deploy tag is
  embedded in the message**, so every deploy mints a **fresh Sentry issue-group**.
- The pull fleet is **exactly two hosts** — `variables.tf` `var.web_hosts` = `web-1` (hel1) +
  `web-2` (fsn1). The inngest image has one host (`inngest-host.tf:181`).
- `event_frequency { comparison_type = "count", value = 3, interval = "1h" }` fires at **>3**,
  i.e. **>=4** events **in one group**.
- **A total zot outage during a rolling deploy emits 2 events into a fresh group. The alarm
  cannot fire.**

The resource comment justifies the threshold with *"a rolling-deploy zot miss drives many hosts
onto the SAME `ghcr-fallback (web:<tag>)` group → crosses 3/group"*. There are no "many hosts",
and the group is not shared across deploys. The premise is false in both halves.

This is not the "fully-distributed thin spread" tail the issue describes. The **dominant,
frequent path never pages at all.** The alarm ADR-096 calls load-bearing is, for its primary
signal, a decoration.

### Why `value = 0` and not a metric alert

`value = 0` means "seen more than 0 times" → **any group with >=1 event fires**. That delivers
**fingerprint-independence — the metric alert's entire selling point** — without:

- a new resource TYPE (and its 4 guard artifacts),
- a numeric notify target (and the "pages nobody" risk the deferral was built around),
- the plan-time 403 blast radius (see Key Decisions),
- a two-level `trigger[].action[]` jq guard clause with no precedent in the file.

It also makes the alarm **agree with the gate it exists to protect**: `zot-soak-6122.sh:69-73`
FAILs the Phase-5 gate on **>=1** fallback. An alarm tolerating 3/hour while the gate fails at 1
is incoherent. Post-flip a healthy fleet emits **zero** fallback events, so there is no benign
occurrence to suppress — `value = 0` is not noisy. `frequency = 23` still throttles
re-notification to 23 minutes.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | **Fix the threshold (`3` → `0`), do not build the metric alert** | The metric alert at the issue's own `alert_threshold=3` would be **equally dead** (total outage across web+inngest aggregates to 2). The gap is the threshold, not the aggregation. |
| 2 | **Close the `sentry_metric_alert` idea** | Its justification was the gap `value = 0` closes. Both CPO and CTO converged here independently. |
| 3 | **NEVER `data "sentry_team"`** | **Empirically 403s at plan time** (`terraform plan` run this session). The `iac-terraform-prd` token's scopes are `[alerts:read, alerts:write, event:read, org:read, project:admin, project:read, project:write]` — **no `team:read`**. It would wedge **every** future `apply-sentry-infra` run, including unrelated changes. Confirms `2026-06-15-sentry-alert-routing-to-an-email-needs-member-target-not-an-iac-rule.md`. |
| 4 | **The deferral's blocking rationale was factually false** | #6285 claims `SENTRY_IAC_AUTH_TOKEN` is "CI-only (ADR-031, not in Doppler)" — it **is** in Doppler `prd_terraform`, and **ADR-031:185 itself** says it's mirrored "for runtime introspection convenience". It claims "zero resolvable numeric notify targets" — team `jikigai-eu` id **`4511404939411536`** (memberCount=3) resolves via the `org:read` list endpoint. |
| 5 | **The real deadline is the `ZOT_ACTIVE=1` flip, not Phase-5 retirement** | ADR-096 task **5.3 removes the pull-site GHCR fallback branch** — after which no fallback event can be emitted and all four signals go **permanently dark**. The alarm's value window **closes** at 5.3. Filed as a spin-off. |
| 6 | Visual design | **N/A** — no UI surface (pure IaC). Phase 3.55 trigger does not fire. |
| 7 | Architecture decision | **No new ADR.** In-scope of ADR-031's existing root. **Amend ADR-096:103-106**, whose sensitivity note rests on the false "many hosts" premise. |

## Open Questions

1. **Does Sentry accept `value = 0` server-side?** `terraform validate` passes (provider-level
   OK, plain `number`, no minimum). **There is no in-repo precedent** — the only other
   fire-on-first rule (`web_terminal_boot_fatal`, `:1462`) uses `value = 1`, which works **only**
   because its group is always-hot (shared `soleur-boot-emit` message); on a **fresh** group
   `value = 1` means ">1" and a single event does **not** fire. **The plan must verify `value = 0`
   against the live API before relying on it.** If Sentry rejects 0, escalate to the corrected
   metric alert (threshold 0, pinned literal team id + audit-gate drift check, plus the omitted
   `-target` artifact).
2. **Live-fire verification poisons the soak gate.** A synthetic burst carrying
   `registry:"ghcr-fallback"` is counted by `zot-soak-6122.sh:57,71-73`, which FAILs on >=1 —
   manufacturing a false FAIL on the gate that decides GHCR retirement. Any synthetic
   verification **must run pre-cutover** (`START` is pinned post-cutover). Independent argument
   for landing this well before the flip.
3. `sentry_issue_alert` is **deprecated** in `0.15.0-beta2` in favour of `sentry_alert`
   (surfaced by `terraform validate`). ADR-031 **NG9 forbids** adopting `sentry_alert` until
   provider GA. Not blocking; worth recording.

## User-Brand Impact

**Artifact:** `sentry_issue_alert.zot_mirror_fallback_rate` (`issue-alerts.tf:1368`).

**Vector:** The alarm thresholds `event_frequency count > 3/1h` **per Sentry issue-group**. The
rolling-deploy message embeds the unique deploy tag (`ci-deploy.sh:607`), so every deploy mints a
fresh group, and the pull fleet is exactly two hosts (`var.web_hosts`). Two events can never
exceed three. Once `ZOT_ACTIVE=1`, a zot mirror that stops serving the current tag pushes the
whole fleet onto the GHCR fallback on every deploy, and the only real-time control on that path
**stays silent by construction**. **The harm terminates in the founder, not the user:** the fleet
keeps deploying successfully off the GHCR fallback throughout — which is exactly why the miss is
invisible — and the first signal is the 7-day soak sweeper failing at day 7, resetting the
Phase-5 cutover by a week.

**Threshold:** `single-user incident` (auto, per #5175).

> **CPO flag (recorded, not overridden):** the honest vector terminates in **migration-schedule
> integrity, not a single-user incident**. The GHCR fallback is by-design *safe* degradation —
> users get a working deploy either way. The threshold stays `single-user incident` per the
> unconditional #5175 posture, but `user-impact-reviewer` should receive the truthful narrow
> vector above rather than an inflated user-outage story.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

Headline: the proposed `alert_threshold=3` is miscalibrated past the reachable ceiling — the
upgrade would not close the gap it exists to close. Recommends fire-on-first. Flagged the
**4th guard artifact** (`apply-sentry-infra.yml` `-target=` allowlist) omitted from the issue:
without it CI **never applies** the resource — "pages nobody" arriving through a different door.
Also flagged that live verification poisons the soak gate. **Correction applied:** CTO recommended
`data "sentry_team"` and asserted "`team:read` works today" — **empirically false** (403 at plan);
CTO explicitly marked this UNVERIFIED (could not `terraform init` read-only). CTO also read the
fleet as a single host (`server.tf:99`); it is **two** (`for_each = var.web_hosts`, `:107`). The
conclusion holds either way.

### Product (CPO)

Independently reached the same headline via the sharper mechanism (unique tag in message → fresh
group per deploy). Recommends the one-line `value 3 → 0` as **strictly better** than the metric
alert. Argued the YAGNI case honestly: during the only window the signals fire, `zot-soak-6122.sh`
already queries Sentry directly with zero tolerance and is **strictly more sensitive** than any
threshold — so the metric alert's marginal value is real-time paging vs. batch, during the soak
only. Keep P3-low on timing; re-gate on the `ZOT_ACTIVE=1` flip.

### Legal (CLO)

**#6285 is legally uninteresting — ship it.** No GDPR gate. Team id `4511404939411536` is an
org-structural identifier, not Art. 4(1) personal data. No Article 30 update: same processor,
same EU cluster, no new sub-processor or egress path. Declined to import the #3861 §5(2)
"misleading accountability evidence" framing — the zot alarm is not cited in the Art. 30 register
or any TOM, so a broken alarm here is an ops-reliability bug, not misleading regulator-facing
evidence.

**Recorded boundary (Art. 5(1)(c) minimisation):** **Team targets in public IaC. Member-pinning
only if Team cannot express the routing, and never for a non-founder member id without notice
plus a minimisation justification.** A Sentry member id *is* Art. 4(1) personal data, and this
repo is public — a Team target achieves the same routing with zero personal data. Aligns with the
operational blocker (no `member:read`) — legal and ops point the same way.

## Capability Gaps

**None.** `soleur:engineering:infra:terraform-architect` covers the HCL;
`soleur:engineering:review:observability-coverage-reviewer` covers the alarm-coverage review.

## Session Errors

1. **I proposed `data "sentry_team"` before testing it.** I asserted the prior CTO's rejection of
   the slug lookup "is now dissolved". A `terraform plan` with the real token returned **403** —
   the token has no `team:read`; the team id I resolved came from the `org:read` **list**
   endpoint, while the **detail** endpoint the data source needs is forbidden. Shipping it would
   have wedged every future Sentry apply. **Lesson:** an endpoint that answers one shape of
   read is not evidence the provider's data source uses *that* endpoint — test the data source,
   don't infer from a sibling API call. The prior rejection was right; its recorded *reason* was
   wrong, which is what made it look stale.
2. **Two leaders asserted unverified infra facts with confidence** — CTO's "`team:read` works
   today" (false) and single-host fleet (false; two hosts). Both were caught only by direct
   probing. Reinforces the leader-substrate cross-check rule.
3. **The roadmap reconcile reports `STALE_STATUS|phase 4` drift.** Not touched — unrelated to
   this scope, and the tool's own guidance routes the fix through the `roadmap-review` cron
   (which opens its own reviewed PR) rather than a drive-by edit inside a Sentry-alarm PR.

## Spin-offs Filed

1. ADR-096 "load-bearing at Phase-5" is **inverted** — the window closes at 5.3.
2. The **real** staleness vector (stale-but-signed image, cosign passes, zero fallback events) is
   uncovered by any alarm and is not caught by #6129's WARN→ENFORCE flip.
3. #4656's `N=1` accepted-risk premise is **falsified** (team memberCount=3).
4. Audit sibling `sandbox_startup_failure` (`:1233`) for the same unreachable-threshold class.
