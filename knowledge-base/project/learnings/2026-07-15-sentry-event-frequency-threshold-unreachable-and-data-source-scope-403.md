---
title: Sentry event_frequency thresholds are unreachable when the message is high-cardinality; data.sentry_team 403s at plan time
date: 2026-07-15
category: integration-issues
module: apps/web-platform/infra/sentry, apps/web-platform/infra/ci-deploy.sh
issue: 6285
pr: 6424
problem_type: integration_issue
component: tooling
symptoms:
  - "sentry_issue_alert.zot_mirror_fallback_rate never fires despite matching events"
  - "terraform plan fails: Unable to read, got status 403 on data.sentry_team"
root_cause: config_error
resolution_type: config_change
severity: high
tags: [sentry, observability, terraform, zot, adr-096, adr-031, event-frequency, token-scope]
synced_to: [brainstorm]
---

# Learning: an alarm that cannot fire, and a data source that wedges every apply (#6285)

Three findings from the #6285 brainstorm. The first is a **live defect** — a safety control
ADR-096 calls load-bearing cannot fire on its primary signal. The second is a **trap** that
would have wedged an entire Terraform root. The third is the **workflow lesson** that nearly
made me ship the trap.

## Problem

#6285 asked to upgrade `sentry_issue_alert.zot_mirror_fallback_rate` to a `sentry_metric_alert`
(cross-signal aggregate) "once a resolvable numeric notify target exists". The premise was that
the alarm's per-issue-group thresholding misses a "fully-distributed thin spread".

The real defect was worse and elsewhere.

---

## Finding 1 — An `event_frequency` threshold >0 is unreachable when the emitter puts a high-cardinality value in the MESSAGE

`apps/web-platform/infra/sentry/issue-alerts.tf:1368` set:

```hcl
event_frequency = { comparison_type = "count", value = 3, interval = "1h" }
```

`value = 3` means **"seen more than 3 times"** → fires at **>=4 events in ONE issue-group**.

But `apps/web-platform/infra/ci-deploy.sh:607` builds the event as:

```bash
message: ("image pulled from " + $reg + " (" + $img + ":" + $t + ")")
```

**The unique deploy tag (`$t`) is inside the message** → Sentry groups on the message → **every
deploy mints a fresh issue-group**. And the pull fleet is **exactly 2 hosts**
(`var.web_hosts`: `web-1`/hel1, `web-2`/fsn1); the inngest image has 1 (`inngest-host.tf:181`).

**A total zot outage during a rolling deploy emits 2 events into a fresh group. 2 is not > 3.
The alarm cannot fire.**

The resource comment justified the threshold with *"a rolling-deploy zot miss drives many hosts
onto the SAME `ghcr-fallback (web:<tag>)` group → crosses 3/group"*. **False in both halves:**
there are no "many hosts", and the group is not shared across deploys.

### Key mechanic

**`filters_v2` (`tagged_event`) do NOT scope the count.** `event_frequency` counts the **whole
issue-group's total**. Filters only gate *whether the triggering event evaluates the rule* — they
never narrow what is counted. This is the crux: reading the rule as "count the filtered events"
makes `value = 3` look sane.

### Generalizable rule

> Before setting an `event_frequency` threshold >0, trace **(a)** the emitter's MESSAGE
> construction and **(b)** the emitting fleet size. The threshold must be **strictly less than
> (max events per group per interval)**. A high-cardinality value in the message (tag, sha, id,
> timestamp) gives each event its own group → **`value = 0` (fire-on-first) is the only reachable
> setting**.

### Corollary (subtle — cost real analysis)

`value = 1` fires on the first event **only for an always-hot shared-message group**
(`web_terminal_boot_fatal`, `:1462` — the shared `soleur-boot-emit` static message means the
group already holds >1 events, so any new event trips ">1").

**On a FRESH group, `value = 1` means ">1" and a single event does NOT fire.** `value = 0` and
`value = 1` are **not** interchangeable — which one fires-on-first depends entirely on the
grouping shape.

### Cross-reference

Extends [2026-07-09-sentry-fallback-rate-alarm-pre-bootstrap-emitter-and-issue-group-grouping.md](./2026-07-09-sentry-fallback-rate-alarm-pre-bootstrap-emitter-and-issue-group-grouping.md),
which documented the shared-message grouping asymmetry but did **not** catch that the threshold
was unreachable for the per-deploy-group signals.

---

## Finding 2 — `data "sentry_team"` 403s at PLAN time: resolving an id via endpoint A is not evidence the data source can read it

Verified with the real `iac-terraform-prd` token:

```
GET /api/0/organizations/jikigai-eu/teams/     → 200   (works via org:read)
                                                 → team id 4511404939411536, memberCount=3
GET /api/0/teams/jikigai-eu/jikigai-eu/        → 403   (team DETAIL — needs team:read)
```

And the decisive test — a real `terraform plan`:

```
data.sentry_team.notify: Reading...
Error: Client error
  Unable to read, got status 403: {"detail":"You do not have permission to perform this action."}
```

Token scopes (`GET /api/0/` → `.auth.scopes`):
`[alerts:read, alerts:write, event:read, org:read, project:admin, project:read, project:write]`
— **no `team:read`, no `member:read`**. Identity is an Internal Integration
(`user.email` ends `@proxy-user.sentry.io`).

**Blast radius:** `data` sources are read on **every plan**. Shipping this would 403 at plan time
on **every future `apply-sentry-infra` run**, wedging unrelated Sentry changes — not just the new
resource.

### Generalizable rule

> When a probe resolves an id via endpoint A, do **NOT** infer a Terraform data source can read
> it — the data source may hit endpoint B under a different scope. **Test the data source itself
> with `terraform plan`, never a sibling `curl`.**

Extends [2026-06-15-sentry-alert-routing-to-an-email-needs-member-target-not-an-iac-rule.md](./2026-06-15-sentry-alert-routing-to-an-email-needs-member-target-not-an-iac-rule.md)
from `data.sentry_organization_member` to `data.sentry_team`. Same root cause: **a token that
cannot read X must not gain an X-reading data source in shared IaC.**

### Provider facts (`jianyuan/sentry 0.15.0-beta2`, schema-probed)

- `sentry_metric_alert` **exists**. Required: `aggregate`, `name`, `organization`, `project`,
  `query`, **`threshold_type`**, `time_window`. `trigger` requires `alert_threshold`, `label`,
  **`threshold_type`**; `trigger.action` requires `target_type` (`target_identifier` optional).
  **#6285's scope list omitted `threshold_type`, which is required.**
- `data "sentry_team"` **exists** (args `organization` + `slug`, exposes `internal_id`) — it is
  *available* and still *unusable* here. Availability ≠ permission.
- `sentry_issue_alert` is **deprecated** in beta2 in favour of `sentry_alert`; **ADR-031 NG9
  forbids** adopting it until provider GA.

---

## Finding 3 (workflow) — A stale deferral's recorded REASON can be wrong while its VERDICT is right

#6285's deferral rested on two claims. **Both are false:**

- *"`SENTRY_IAC_AUTH_TOKEN` is CI-only (ADR-031, not in Doppler)"* — it **is** in Doppler
  `prd_terraform`, and **ADR-031:185 itself** says it is mirrored there "for runtime
  introspection convenience".
- *"zero resolvable numeric notify targets"* — team id `4511404939411536` resolves via `org:read`.

Falsifying both took minutes, and made the prior CTO's rejection of `data "sentry_team"` look
stale. **I asserted "that rejection reason is now dissolved" before testing it.** Then
`terraform plan` returned 403.

**The rejection was correct — for a reason nobody wrote down.** The recorded reason ("wrong/
member-less slug either fails apply or emails nobody; `terraform validate` catches neither") was
about *correctness*. The actual blocker is *scope*: no `team:read` → plan-time 403.

### Generalizable rule

> **Falsifying a deferral's stated rationale does NOT establish that its verdict was wrong.**
> Premise-probing correctly flags such an artifact as stale — which is exactly what makes it
> dangerous. **Re-derive the verdict's MECHANISM independently before acting on the re-frame.**
> A right answer recorded with a wrong reason is the highest-risk artifact class in a
> premise-probing workflow, because the probe's success manufactures confidence to reverse it.

---

## Solution

Re-scoped #6285 from *"upgrade to `sentry_metric_alert`"* to the real defect:

```diff
-  value = 3   # fires at >=4 — unreachable on a 2-host fleet with per-deploy groups
+  value = 0   # fires on the first event in ANY group
```

`value = 0` delivers **fingerprint-independence — the metric alert's entire selling point** — with
no new resource type, no numeric notify target, no guard artifacts, and no plan-time 403. It also
makes the alarm **agree with the gate it protects**: `zot-soak-6122.sh:69-73` FAILs on **>=1**
fallback. A healthy post-flip fleet emits zero fallback events, so `0` is not noisy;
`frequency = 23` still throttles re-notification.

**Unverified — the plan must check first:** there is **no in-repo precedent for `value = 0`**.
`terraform validate` passes (plain `number`, no minimum), but Sentry's server-side acceptance is
unproven. If rejected, escalate to the corrected metric alert (threshold **0**, pinned literal
team id + audit-gate drift check, plus the omitted `-target` artifact).

## Prevention

- **Alarm review:** for any `event_frequency` threshold >0, require the reviewer to state the
  max-events-per-group-per-interval and show the threshold is below it. The
  `observability-coverage-reviewer` agent is the natural home.
- **Data sources in shared IaC:** any new `data` block in a root applied by a scoped token must be
  proven with a real `terraform plan` under that exact token before merge — a `data` source failure
  is a whole-root outage, not a local one.

## Session Errors

1. **Asserted `data "sentry_team"` was viable before testing it.** I claimed the prior rejection
   "is dissolved" based on an id resolved via a *different* endpoint (`org:read` list), then a
   real `terraform plan` returned 403 (no `team:read`). Had it shipped, every future
   `apply-sentry-infra` run would have wedged.
   **Recovery:** empirical `terraform plan` test before any code was written; corrected in the
   brainstorm doc, spec NG2, and the #6285 comment.
   **Prevention:** routed to the `brainstorm` skill's Sharp Edges (Finding 3's rule) — falsifying
   a deferral's stated reason does not license reversing its verdict; test the mechanism.
2. **`gh issue create` blocked — missing `--milestone`.**
   **Recovery:** re-ran with `--milestone "Post-MVP / Later"`.
   **Prevention:** already hook-enforced — the hook caught it. No action needed.
3. **Roadmap reconcile reported `STALE_STATUS|phase 4` drift; not fixed.** Deliberate — unrelated
   to this scope, and the tool's own guidance routes the fix through the `roadmap-review` cron,
   which opens its own reviewed PR.
   **Prevention:** none needed (correct behaviour; recorded so a reader does not misread it as an
   oversight).
4. **Two leader agents asserted unverified infra facts.** The CTO claimed "`team:read` works
   today" (false — no such scope) and read the fleet as a single host (false — `for_each =
   var.web_hosts`, 2 hosts). The CTO self-flagged the first as UNVERIFIED.
   **Recovery:** both caught by direct probing before reaching any artifact.
   **Prevention:** already covered by the brainstorm skill's leader-substrate cross-check rule.
   This is a **second occurrence** — strengthen that rule's wording rather than adding a new one.

## Related

- Confirms (2nd occurrence) [2026-06-12-detector-cron-must-route-its-own-self-failure-ops-and-register-new-sentry-alert-in-apply-target.md](./2026-06-12-detector-cron-must-route-its-own-self-failure-ops-and-register-new-sentry-alert-in-apply-target.md)
  — #6285's "3 guard artifacts" list omitted `.github/workflows/apply-sentry-infra.yml`'s
  `-target=` allowlist. Without it CI **never applies** the resource.
- Spin-offs filed: #6427 (ADR-096 "load-bearing at Phase-5" is inverted — the window *closes* at
  5.3), #6428 (the real staleness vector — stale-but-signed image — is uncovered by any alarm),
  #6429 (audit sibling `sandbox_startup_failure` for the same unreachable-threshold class), and a
  comment on #4656 (the `N=1` accepted-risk premise is falsified by `memberCount=3`).
