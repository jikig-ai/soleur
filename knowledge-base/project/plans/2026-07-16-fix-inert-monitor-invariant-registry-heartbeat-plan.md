---
title: 'fix: arm the registry liveness heartbeat with a private-IP self-ping, then unpause — and make every arming claim executable'
date: 2026-07-16
type: fix
issue: 6537
related: ['#6438', '#6497', '#6400', '#6415', '#6242', '#6238', '#6210', '#6122']
related_adrs: [ADR-096, ADR-103, ADR-115, ADR-116]
lane: cross-domain
brand_survival_threshold: aggregate pattern
status: draft
revision: v3 (post 7-agent plan-review — see ## Plan-Review Consolidation)
---

# fix: arm the registry heartbeat, then unpause

## Enhancement Summary

**Deepened on:** 2026-07-16 · **Review panel:** 7 agents (`dhh`, `kieran`, `code-simplicity`,
`architecture-strategist`, `spec-flow-analyzer`, `cto`, `cpo`) · **Revisions:** v1 → v3

### Key improvements

1. **Reversed the central decision.** v1 refused #6537's ask and built a nightly gate *around* the
   refusal. v3 builds the missing feeder and **then unpauses** — answering the ask in the order
   ask #1 demanded. Every panel independently called v1's swap a substitution.
2. **Corrected an inherited false premise.** #6537's *"the host can die silently"* is **false** —
   the disk cron already alarms host death in ≤25 min. The real gap is narrower (zot-process-death)
   and is what v3 closes.
3. **Private IP, not localhost.** The load-bearing implementation choice: zot binds `0.0.0.0`, so a
   `localhost` probe is structurally blind to #6400 — the repo says so verbatim.
4. **Zero Terraform resource changes.** `registry_prd` is an `OPERATOR_APPLIED_EXCLUSION`; v2's
   `period` widening could never have applied. v3 meets the existing `60/30` with a systemd timer —
   the proven `inngest_prd` shape.
5. **Bidirectional feeder grep.** Forward-only (v1) could not prove an *undeclared* feeder absent —
   it would have gone silent through a probe ship, then false-fired at the operator doing the right
   thing.
6. **Cut ~50% of v1**: no new workflow, no new Sentry monitor, no live reconcile, no ADR-033
   override, no `gh issue` call inside a monitoring gate.

### Gates run

| Gate | Verdict |
| --- | --- |
| 4.5 Network-outage | **Skip** — no SSH provisioner on `zot-registry.tf` (`:9-14`); the plan's `ssh` hits are "no-SSH host" descriptors, not a connectivity diagnosis. |
| 4.55 Downtime & Cutover | **FIRED** (`hcloud_server.registry` `-replace`) → `## Downtime & Cutover` added; telemetry emitted. |
| 4.6 User-Brand Impact | **Pass** — section present, threshold `aggregate pattern`. |
| 4.7 Observability | **Pass** — all 5 fields populated, no placeholder, no `ssh` in `discoverability_test`. |
| 4.8 PAT-shaped variable | **Pass** — no PAT-shaped refs. |
| 4.9 UI-wireframe | **Skip** — no UI-surface file in Files to Edit/Create. |

### Verification performed

Rule IDs (all active, zero fabricated) · every cited issue/PR resolved live via `gh` with its
title cross-checked against the narrative claim · KB paths resolve (only ADR-116 absent — this
plan's own Phase 6 deliverable) · live Better Stack state self-pulled · `-target` allow-lists and
`OPERATOR_APPLIED_EXCLUSIONS` read from source · GHCR-fallback warmth confirmed from ADR-096
status + `cloud-init.yml`.

## Overview

Issue #6537 asks us to unpause `soleur-registry-prd`. Its ask #1 —
*"VERIFY A PING ACTUALLY LANDS BEFORE UNPAUSING … if the probe cron is not in fact shipping
pings, that is the real finding"* — is the branch that fires. **The probe was never built**
(`ZOT_HEARTBEAT_URL` has zero consumers repo-wide). Unpausing today would page the founder every
90s forever — this repo already ran that exact experiment (#6210 →
`registry-disk-heartbeat-false-positive-postmortem.md`).

So we do not unpause *today*. **We build the missing feeder first, then unpause** — which answers
#6537 literally, in the order ask #1 demanded.

The feeder is ~20 lines in `cloud-init-registry.yml` — a file that already ships a working,
tested heartbeat pinger (`zot-disk-heartbeat`, `:148`) — delivered by the sanctioned
`registry-host-replace` path. Two choices in it are load-bearing, and both were **reversed under
review**:

- It pings the registry's **own private IP** (`10.0.1.30:5000/v2/`), never `localhost` — the repo
  documents that a `localhost` probe is *structurally blind* to #6400.
- It is a **systemd timer**, not a `cron.d` entry, and it changes **no Terraform resource** —
  because `registry_prd` is an `OPERATOR_APPLIED_EXCLUSION`, so a `period` edit could never apply.

See *The feeder* and *The cadence constraint* below.

Second, the reason this sat dark for 9 days: a heartbeat's *"what feeds this?"* answer lived in a
**code comment**, and comments rot. Two of ours have been **flatly false for months** — inside the
very guard built to prevent this class (#6242). So we make the arming claim **executable**.

**This is v3, and v1 is unrecognisable in it.** A 7-agent panel cut ~50% of v1 and reversed its
central choice: v1 refused the operator's ask and shipped a nightly gate *around* the refusal —
every panel independently called that a substitution, and its own quadrant table would have stayed
**silent** on the very monitor #6537 reported. v3 then dropped v1's remaining Terraform edits once
the `OPERATOR_APPLIED_EXCLUSIONS` ruling surfaced. See `## Plan-Review Consolidation`.

## Premise Validation

Checked against live state and `origin/main`. **Two premises are false — one in the issue, one
in v1 of this plan.**

| # | Premise | Verdict |
| --- | --- | --- |
| 1 | Issue #6537 is OPEN | ✅ `gh issue view 6537` → `OPEN`, milestone **Phase 4: Validate + Scale**. |
| 2 | Live: `registry_prd` paused=True, period=60 | ✅ Self-pulled `/api/v2/heartbeats`. `created_at == updated_at == paused_at == 2026-07-07T13:36:26Z` — **never touched in 9 days**. |
| 3 | *"The probe shipped; the unpause never happened."* | ❌ **FALSE.** `git grep -c "ZOT_HEARTBEAT_URL" -- ':!knowledge-base'` → **1 line**, its own `doppler_secret` definition (`zot-registry.tf:441`). Zero consumers. The probe was **never written**. |
| 4 | **"The registry is a deny-all host, so the PUSH heartbeat is its ONLY liveness signal — paused means the host can die silently."** | ❌ **FALSE — and v1 accepted it unexamined.** `zot-disk-heartbeat.sh` runs **on the registry host** every 5 min and pings `registry_disk_prd` (live, `paused=false`, 900/600). Its ping is **absence-based**, gated only on `df < 85%` (`cloud-init-registry.yml:152-155`). **Host death ⇒ cron stops ⇒ alarm in ≤25 min, today.** See *What is actually uncovered*. |
| 5 | *"`inngest_prd` was unpaused; the registry never got that step."* | ⚠️ **Misleading.** `inngest_prd` was unpausable *because it has a working feeder* (`inngest-bootstrap.sh:163`). The missing step is the **feeder**, not the unpause. |
| 6 | *"Audit the sibling `paused=true` monitors (`git_data_prd`, and any others)"* | ⚠️ **Wider than stated.** HCL has **5**; live has **1** paused. `git_data_prd` is **absent live despite having no `count` gate** — unexplained apply-drift (see Risks). The two `alerts-github-webhook.tf` monitors are `count = 0` (`betterstack_paid_tier=false`). |
| 7 | Work is not already tracked | ⚠️ **#6438 §1** tracks the *off-host* L3 probe. This plan does **not** duplicate it — it ships the **on-host** layer, which #6438 does not cover. #6438 stays open for the consumer-perspective probe. |
| 8 | `ignore_changes = [paused]` ⇒ an unpause is durable | ✅ Holds — and it means a source flip is a **no-op**, so arming is a one-time **API** call (precedent: `apply-web-platform-infra.yml:1908-1919` reads the same API). |

**Own-capability claims** (`hr-verify-repo-capability-claim-before-assert`):
`scripts/betterstack-query.sh` is a **ClickHouse Logs** reader — it **cannot** read the
uptime/heartbeats API. The task brief's instruction to use it here is a capability mismatch; the
correct surface is `https://uptime.betterstack.com/api/v2/heartbeats` with `BETTERSTACK_API_TOKEN`.
Verified by reading both. No dashboard consulted (`hr-no-dashboard-eyeball-pull-data-yourself`).

### What is actually uncovered

Premise 4's correction narrows the real gap. The honest coverage table:

| Failure mode | Covered today? |
| --- | --- |
| Registry host dead / off-network | ✅ `registry_disk_prd` absence (≤25 min) |
| Disk fills > 85% | ✅ same |
| Private NIC absent at boot (#6400) | ✅ since #6415 — L1 on-host converger + L2 alarm |
| **zot process dead, host alive, disk fine** | ❌ **nothing** — the disk cron pings regardless of zot |
| **Private net reachable *from a consumer*** | ❌ #6438 §1 — genuinely greenfield, stays deferred |

This plan closes **row 4**, and — because of the private-IP choice — hardens row 3 with a second,
independent signal. It does **not** close row 5, and says so.

## The feeder (why private IP, not localhost)

`cloud-init-registry.yml:324-328` already documents, in the repo's own words, why every existing
signal missed #6400:

> *"a NIC-less host keeps PUBLIC egress, so the disk heartbeat kept pinging green; and the boot
> readiness poll targets `localhost:5000` … which succeeds because zot binds `0.0.0.0:5000`
> (its `-p 0.0.0.0:5000:5000` publish). **Every existing signal is structurally blind to this** —
> hence a NEW signal, not a re-thresholded old one."*

So a **`localhost` self-ping would inherit that exact blindness** and be worthless for #6400. A
ping to the host's **own private IP** (`10.0.1.30:5000/v2/`) succeeds only if the host *holds*
`10.0.1.30` — i.e. it fails closed on NIC absence. `private_ip` is **already baked** into
`user_data` (`zot-registry.tf:321`; `local.registry_private_ip` at `:40`), so this is free.

**Why the four #6438 §1 blockers do not apply** (CTO ruling — see Plan-Review Consolidation):

| #6438 §1 blocker (for the *off-host* probe) | Status for a **registry-host** self-ping |
| --- | --- |
| Delivery site — web hosts carry `ignore_changes=[user_data]` ⇒ needs bake-and-extract | **Dissolved.** `zot-registry.tf:324-326`: *"Deliberately NO `lifecycle.ignore_changes=[user_data]` … preserves a clean replace-to-reprovision path."* `registry-host-replace` exists and ships `zot-disk-heartbeat` **today**. |
| Arming — `ignore_changes=[paused]` ⇒ a source flip is a no-op | **Dissolved.** One API `PATCH`, durable *because of* `ignore_changes`. |
| Cadence — `period=60/grace=30` needs ≤90s vs a 60s cron floor ⇒ flapping | **Dissolved — but NOT by widening `period`.** See *The cadence constraint* below: a **systemd timer** mirrors `inngest_prd`, which carries the **identical** `period=60/grace=30` and is live/`up` today. **Zero Terraform resource change.** |
| No escalation — free tier ⇒ email-only | **Non-differential.** Applies to any option, including doing nothing. |

### The cadence constraint (why NO Terraform resource change)

**`betteruptime_heartbeat.registry_prd` is an `OPERATOR_APPLIED_EXCLUSION`** — a deliberate CTO
ruling (2026-07-06), codified at `plugins/soleur/test/terraform-target-parity.test.ts:584` and
restated at `apply-web-platform-infra.yml:1710-1713`: *"zot-registry.tf resources are
OPERATOR_APPLIED_EXCLUSIONS … deliberately NOT in the per-PR `-target=` allow-list."*

Verified: `registry_prd`, `registry_disk_prd`, and `doppler_secret.zot_heartbeat_url_prd` have
**zero** `-target=` lines; `inngest_prd` has one.

Two consequences that **reshaped this plan**:

1. **Widening `period` 60→900 would silently never apply.** It would require an operator-local
   full apply — a manual step, forbidden by `hr-never-label-any-step-as-manual-without` and this
   task's constraint. Adding a `-target=` line would violate the CTO ruling **and** fail
   `terraform-target-parity.test.ts`.
2. **So the feeder must satisfy the heartbeat as it already is (`60/30`), with no resource change.**

The repo already solved this exact problem. `inngest_prd` is **also** `period=60/grace=30`, also
armed at boot on a dedicated host, and is **live and `up`** — fed by a **systemd timer**
(`inngest-bootstrap.sh:196-207`):

```ini
[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
```

A `/etc/cron.d` entry **cannot** do this — cron's floor is 60s with no boot offset, leaving no
margin against a 90s deadline, so a single transient POST failure pages the founder. A timer is
the host-appropriate, **proven-at-this-exact-cadence** primitive. This deviates from the registry
host's `cron.d` convention (`zot-disk-heartbeat`) **for a reason**: the disk beat is 900/600 and
tolerates cron's floor; a 60/30 beat does not.

*(This is not the `Type=oneshot` liveness trap ADR-115 warns about — that concerns a boot-only
one-shot whose `inactive` state reads as healthy. A `.timer` is recurring, and its liveness is the
heartbeat itself.)*

**Scope boundary vs #6438 §1:** this is the **on-host** layer (does zot answer on the private
NIC *from the host*). #6438 §1 is the **off-host** layer (does the route work *from a web host*).
The self-ping does **not** subsume it; #6438 stays open.

## Executable arming (the durable half)

`heartbeat-reprovision-parity.test.ts` (ADR-103, #6242) types `arming` / `exempt_reason` as
**free prose** (`:57-79`) — unenforceable by construction. The cost is measurable: two entries
claim `arming: "app-emit"` — *"webhook route pings on sig-failure"* — and it is **false**.
`grep -rn -iE "heartbeat|betteruptime|better-?stack" apps/web-platform/app/api/webhooks/github/ apps/web-platform/server/github/`
returns **zero hits**. That lie has sat inside the anti-rot guard for months.

So: replace the prose claim with a **bidirectional, grep-derived** one.

```ts
feeder:
  | { kind: "cron" | "timer"; evidence: { file: string; pattern: string } }
  | { kind: "none"; url_secret: string; tracking_issue: number };
```

Two assertions, both **static, offline, no secrets**:

1. **Forward** — `kind ∈ {cron,timer}` ⇒ `evidence.file` MUST exist **and**
   `grep -F -c <pattern> <file>` ≥ 1. *(File-existence is asserted **separately**, with its own
   message: `grep -F` exits **2** on a missing file and **1** on no-match — collapsing them makes
   a typo'd path and an absent feeder indistinguishable.)*
2. **Inverse** — `kind === "none"` ⇒ `url_secret` MUST have **zero consumers** repo-wide
   (`git grep` outside `.tf` / `knowledge-base/`).

The **inverse** assertion is the one that closes the loop, and v1 lacked it. Without it,
`feeder_shipped` is *manifest-declared*, not grep-derived — a one-directional check that proves a
*declared* feeder exists but **structurally cannot prove an undeclared one doesn't**. That is the
same "prose in a guard is not a guard" hole this plan exists to kill, one level up. With it, the
day #5274 PR C ships a `GIT_DATA_HEARTBEAT_URL` consumer, **CI goes red**: *"you shipped a feeder;
re-declare `feeder` in the manifest in this PR."* That is the forcing function.

## User-Brand Impact

**If this lands broken, the user experiences:** a false-fed heartbeat — the self-ping cron ships
but pings unconditionally (e.g. the `curl` guard is inverted), so `registry_prd` reads green while
zot is dead. That is strictly worse than today: it converts an *acknowledged* gap into a *false
assurance*, and false assurance is what made #6400 last 14 days. T2/T3 below exist to prevent
exactly this. Second mode: the `registry-host-replace` dispatch (Phase 4) boots a fresh host —
if it boots NIC-less (#6400's shape), the fleet's primary image-pull path degrades to the GHCR
fallback (`model.c4:380`) until #6415's L1 converger heals it.

**If this leaks, the user's data/workflow/money is exposed via:** nothing. No personal data is on
this path. The sensitive values are `BETTERSTACK_API_TOKEN` (Doppler `prd_terraform`, masked, used
only for the arming `PATCH`) and the heartbeat URL — which, per the established pattern, is baked
into `user_data` as **non-secret host routing** (`zot-registry.tf:87-96, :310-312`), exactly as
`disk_heartbeat_url` already is.

**Brand-survival threshold:** `aggregate pattern`

*Rationale:* no per-user data surface; harm accrues as a **pattern** of undelivered fixes behind a
silently-degraded registry. Not `none` — this touches `apps/web-platform/infra/**` and replaces a
prod host.

## Architecture Decision (ADR/C4)

### ADR

- **Create `ADR-116` — "A heartbeat's arming claim must be executable, and an unfed heartbeat must
  stay paused."** The cross-cutting invariant: `feeder` is grep-derived **bidirectionally**
  (forward evidence + inverse zero-consumer); an unfed heartbeat is `paused` and names an open
  tracking issue; `paused` in source is only a **lower bound** on liveness. Alternatives Considered
  MUST record: *unpause without a feeder* (rejected — #6210), *prose `arming`/`exempt_reason`*
  (rejected — false for months, #6242), *forward-only grep* (rejected — cannot prove an undeclared
  feeder absent), *a nightly live-reconcile gate* (**deferred**, see Deferred Items).
- **Amend `ADR-096`** — it currently records the #6285 correction that the zot-liveness layer
  *"does not exist yet"* and that `sentry_issue_alert.zot_mirror_fallback_rate` is the only
  coverage. **That is now stale**: this PR ships the on-host self-ping. Record the new layer, its
  private-IP rationale, and that the **consumer-perspective** probe remains #6438 §1. Also fix its
  stale citation — `ADR-096:94` cites `zot-registry.tf:359` for `ZOT_HEARTBEAT_URL`; actual is
  `:441`.
- **Amend `ADR-103`** — its static guard is a **lower bound**; record the `feeder` field as the
  executable upgrade to its prose `arming` axis.
- **`ADR-115`** (private-NIC convergence) — no change; the self-ping is a *second, independent*
  signal for NIC absence, not a replacement for L1. Cross-reference only.
- Ordinal is **provisional** — `/ship`'s ADR-Ordinal Collision Gate re-verifies against
  `origin/main` (highest today: ADR-115). On renumber, sweep
  `grep -rn 'ADR-116' knowledge-base/project/{plans,specs}/feat-one-shot-6537-*/` **in the same
  edit** (#5990 orphan trap).

### C4 views

All three model files read in full (`model.c4` 491L, `views.c4` 62L, `spec.c4` 54L) — not a
keyword grep. Enumeration per the completeness mandate:

- **External human actors:** `founder` — modeled; reached via existing `betterstack -> founder` /
  `sentry -> founder` exits. **No new actor.**
- **External systems:** `betterstack`, `github`, `sentry`, `zotRegistry`, `hetzner` — all modeled.
  **No new system.**
- **Containers / data stores:** none new.
- **Access relationships that change:** **one** — `zotRegistry -> betterstack` (`:420`) today
  describes only the **Logs** POST (`SOLEUR_ZOT_DISK` / `SOLEUR_PRIVATE_NIC`) and the disk
  heartbeat. It gains the **liveness heartbeat ping**. That edge must be extended.

**Edits to `model.c4`:**

1. `:420` `zotRegistry -> betterstack` — add the `registry_prd` liveness ping (private-IP-gated),
   distinct from the disk heartbeat already described.
2. `:264` `betterstack` description — *"Apex + inngest/git-data heartbeats"* is **false**
   (`git_data_prd` is not provisioned and has no feeder). Correct to the live set: apex monitor +
   `inngest` + `registry` (liveness, armed by this PR) + `registry-disk`.
3. `:450` `betterstack -> founder` — *"the inngest/git-data heartbeats alert on downtime/missed
   beats"* — same false git-data claim. Correct.

`views.c4` needs **no** edit — `betterstack`, `zotRegistry`, `github`, `sentry` are already
`include`d in both views (`:14`, `:36`); no element is added. Validation:
`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

**Note on citation style:** `model.c4:437` states the repo's own rule — *"Anchored on grep-able
tokens, not line numbers."* The `:264`/`:420`/`:450` cites above are for **navigation in this
plan**; the edits themselves must anchor on tokens, and no new line-number citation may be written
*into* the model.

## Infrastructure (IaC)

### Terraform / cloud-init changes

**No Terraform *resource* change at all** — the only `.tf` edits are a `templatefile` var and
comments. This is forced by the `OPERATOR_APPLIED_EXCLUSIONS` ruling (see *The cadence
constraint*) and is a **feature**: it removes every apply-path risk from this PR.

- `apps/web-platform/infra/cloud-init-registry.yml` — the feeder: `zot-liveness-heartbeat.sh` +
  a **systemd `.service` + `.timer`** (`OnBootSec=30s`, `OnUnitActiveSec=60s`), mirroring
  `inngest-bootstrap.sh:196-207`. The liveness URL is templatefile-interpolated as **non-secret
  host routing**, exactly like `disk_heartbeat_url` (`zot-registry.tf:87-96, :310-312`).
- `apps/web-platform/infra/zot-registry.tf` — (a) pass `liveness_heartbeat_url` into
  `templatefile` (mirrors `disk_heartbeat_url` at `:310`) — **a `locals`/`user_data` change on
  `hcloud_server.registry`, which IS in the replace path, not on the heartbeat resource**;
  (b) rewrite the false present-tense comment at `:406-413` **and** the second false
  forward-reference at `:435-436`. **`period`, `grace`, and `paused` are UNTOUCHED.**
- `apps/web-platform/infra/alerts-github-webhook.tf` — delete the false claim at `:50-54`
  (*"the webhook route deliberately pings"*). It attaches **only** to
  `github_webhook_sig_failures`; `github_api_429_sustained` has **no** corresponding comment.
- **`doppler_secret.zot_heartbeat_url_prd` (`:438-444`) — KEEP.** *(v2 proposed deleting it;
  reversed.)* Three reasons: it is an `OPERATOR_APPLIED_EXCLUSION`, so the deletion would **never
  apply**; it lives in project `soleur`/config `prd`, which the registry host **cannot read** (it
  holds only the isolated `soleur-registry/prd` token with 3 admitted secrets — `model.c4:411`),
  so it was always for the **web-host** off-host probe; and #6438 §1 still needs it. The inverse
  assertion only governs `kind:"none"` entries, so a `kind:"cron"` `registry_prd` leaves no
  exemption behind.
- **No new Terraform variables**, **no new `sentry_cron_monitor`**, **no new workflow.**

### Apply path

All automated, no human step:

1. **Merge** → `apply-web-platform-infra.yml` fires on `apps/web-platform/infra/**`, but the
   `user_data` change reaches the host **only on a fresh boot** (cloud-init is per-instance).
   Nothing in this PR needs the per-PR apply to succeed at anything.
2. **Dispatch `registry-host-replace`** (`gh workflow run apply-web-platform-infra.yml -f
   apply_target=registry-host-replace -f reason="arm the zot liveness heartbeat (#6537)"`) →
   the sanctioned non-SSH reprovision path (`:1710-1730`): a scoped 6-target `-replace` that
   re-runs the registry cloud-init and installs the new timer. The zot OCI store volume is
   **preserved** by its destroy-guard (size-update-only, never delete/replace).
3. **Verify a ping landed** (measured, not assumed), then **arm** via
   `PATCH /api/v2/heartbeats/<id> {"paused": false}`, then **confirm `status == up`** within
   `period + grace` (60 + 30s + margin).

**Blast radius:** step 2 replaces a prod host. Mitigations: the store volume is preserved; the
registry is a disposable GHCR mirror that re-fills; the GHCR fallback (`model.c4:380`) covers
image pulls throughout; #6415's L1 converger handles a NIC-less boot. This is the **same** path
used routinely (#6122, #6247, #6288).

### Distinctness / drift safeguards

- `dev != prd`: not engaged — one Better Stack prd team.
- `ignore_changes = [paused]` **retained** — it is why arming is an API call and why it is durable.
- **`git_data_prd` drift**: it has **no `count` gate** (`git-data.tf:243`) yet is **absent live**.
  This is unexplained apply-drift, **out of scope** here and delegated to
  `scheduled-terraform-drift.yml`. It is called out so a future reader does not mistake its
  absence for a `count` gate (the two webhook heartbeats *are* `count`-gated; `git_data_prd` is
  not).

### Vendor-tier reality check

`betterstack_paid_tier` defaults **false** (`variables.tf:341-344`) ⇒ `betteruptime_policy` is
`count = 0` and every heartbeat gets `policy_id = null` ⇒ **email-only, no escalation**. Unchanged
by this PR and non-differential across options. `registry_prd` already has `email = true`.

## Downtime & Cutover

**Gate fired** (deepen-plan Phase 4.55, infra reboot/replace class): Phase 4.2 dispatches a scoped
`-replace` of `hcloud_server.registry`. A serving resource is powered off, so a zero-downtime path
must be evaluated and defaulted to.

**The offline operation:** `registry-host-replace` destroys and recreates `hcloud_server.registry`
to re-run cloud-init (the only delivery path — cloud-init is per-instance). zot is unreachable for
roughly one fresh boot (~5-10 min, per #6122/#6247/#6288 precedent).

**Affected surface:** container **image pulls** by the web + inngest hosts. **Not** the user-facing
app — already-running containers are untouched; only a deploy or a host restart pulls.

**Zero-downtime path — the automatic degrade, already shipped and live (DEFAULT):**

The serving surface does **not** go offline, because the GHCR fallback absorbs the outage
*automatically*. Verified, not assumed:

- `cloud-init.yml:516-526` — the pull-site probes `http://$ZURL/v2/` (`--max-time 3`) and, on any
  miss, falls through to the GHCR ref, emitting a `stage=app_ghcr_fallback` breadcrumb.
- `model.c4:400` — `hetzner -> ghcr`: *"Atomic fallback pull when zot is unconfigured/unreachable
  … immutable @sha256 digest, offline cosign verify."*
- **The fallback is still warm.** ADR-096's status is **`Adopting`** — the Phase-5 GHCR retirement
  has **not** run (`ADR-096:66-67`: *"retire GHCR push + egress … GHCR stays break-glass warm
  through the entire soak"*; `:52`: *"live as break-glass until the Phase-5 GHCR retirement"*).
  This is a **load-bearing precondition**: once Phase-5 retires GHCR, a registry replace stops
  being latency-only, and this plan's downtime analysis expires with it.

So, in ADR-096's own words, *"a zot outage degrades latency, not availability."* **AC19** asserts
the precondition still holds at run time rather than trusting this paragraph.

**Alternatives evaluated and rejected:**

| Path | Verdict |
| --- | --- |
| **Blue-green** (stand up a second registry, cut over, retire the old) | **Rejected — higher blast radius than the outage it prevents.** The registry is pinned to a fixed private IP `10.0.1.30` (`local.registry_private_ip`, `zot-registry.tf:40`) that is **baked into every consumer's `user_data`**. Blue-green needs an IP move or a re-bake + reboot of *all* consumers — trading a 5-min latency degrade on one disposable host for a fleet-wide reprovision. (#6453 also records the 5-server cap this ran into.) |
| **Drain-then-act** | **Not applicable.** zot is a read-through mirror with no in-flight state to drain; the OCI store volume is preserved by the dispatch's destroy-guard and re-fills from GHCR. |
| **Avoid the replace entirely** (patch the running host) | **Rejected — impossible by design and by rule.** The host is deny-all/no-SSH with no `remote-exec` provisioner (`zot-registry.tf:9-14`), and `hr-prod-host-config-change-immutable-redeploy` forbids in-place mutation. `registry-host-replace` **is** the sanctioned path. |

**Residual downtime:** ~5-10 min of zot unavailability, fully absorbed by the automatic fallback.
**No maintenance window or sign-off required** — the degrade is automatic, already live, and
self-describing (a deploy in the window takes the GHCR path and emits its own breadcrumb).

**Per-stage verification / rollback:** the dispatch's own destroy-guard aborts unless the plan is
*exactly* the scoped 6-target recreate, and **preserves** the OCI store volume (size-update-only —
never delete/forget/replace). Rollback is a re-dispatch. AC15 gates arming on a **measured** ping,
so a failed boot can never leave an armed-but-unfed heartbeat.

## Observability

```yaml
liveness_signal:
  what: betteruptime_heartbeat.registry_prd — a PUSH beat from the registry host, gated on
        `curl -fsS http://10.0.1.30:5000/v2/` (the host's OWN private IP, never localhost:
        zot binds 0.0.0.0 so localhost is blind to NIC absence — cloud-init-registry.yml:324-328)
  cadence: systemd timer, OnBootSec=30s / OnUnitActiveSec=60s — mirroring inngest-heartbeat.timer,
           the PROVEN feeder for the identical period=60 / grace=30. NOT cron.d: cron's 60s floor
           leaves no margin against the 90s deadline. period/grace are UNCHANGED (registry_prd is
           an OPERATOR_APPLIED_EXCLUSION — a resource edit could never apply)
  alert_target: Better Stack missed-heartbeat -> email to the managed recipient (free tier,
                policy_id=null); independent of Sentry by design (model.c4:446-450)
  configured_in: apps/web-platform/infra/cloud-init-registry.yml (script + .service + .timer)
                 + apps/web-platform/infra/zot-registry.tf (templatefile URL bake — user_data only)

error_reporting:
  destination: Better Stack (absence -> email). The co-located SOLEUR_ZOT_DISK self-report carries
               structured fields (pcent / fs_size_gb / resize_ok / zot_restarts / zot_last_err /
               ping_rc) to Better Stack Logs, queryable via
               scripts/betterstack-query.sh --grep SOLEUR_ZOT_DISK (#6244)
               [corrected at review: an earlier draft named a `zot_health` field. No such field
                exists — a fabricated identifier, in the Observability block of the PR whose thesis
                is that unverified claims rot. Fields above are read from the emit, not recalled.]
  fail_loud: true — absence-based. A dead timer, a dead host, a dead zot, or an absent private NIC
             all STOP the ping. There is no "ping anyway" path: the probe guard is the ping's
             precondition, not a logged side-effect (this is the T2/T3 invariant)

failure_modes:
  - mode: zot process dead, host alive, disk fine (THE gap this PR closes)
    detection: probe to 10.0.1.30:5000/v2/ returns no HTTP response (000) or 5xx -> ping withheld
    alert_route: Better Stack missed-heartbeat email (<= 90s once armed)
  - mode: zot alive but its htpasswd has diverged from the pull credential (#6497)
    detection: NOT DETECTED BY THIS BEAT — an auth-gated 401 is accepted as liveness (it proves zot
               is up and enforcing auth), so a zot whose htpasswd no longer matches the pull user
               answers 401 and this beat stays GREEN while no client can actually pull.
    alert_route: the disk beat's htpasswd_pull_matches field (#6497) is the layer that owns this.
                 Declared here rather than elided: accepting 401 is required (a -f probe treats
                 every healthy response as dead — see The feeder), and this is the edge it buys.
  - mode: private NIC absent at boot (#6400) — second, independent signal
    detection: host holds no 10.0.1.30 -> curl fails -> ping withheld
    alert_route: same. (L1 converger + L2 alarm from #6415 remain the primary.)
  - mode: registry host dead / off-network
    detection: unchanged — registry_disk_prd absence
    alert_route: Better Stack (<= 25 min)
  - mode: a heartbeat's declared feeder does not exist (the app-emit lie class)
    detection: STATIC — forward grep: evidence.file missing OR grep -F count == 0
    alert_route: CI red on the PR (no secrets, offline)
  - mode: a feeder ships but the manifest still declares kind:"none" (would false-fire on unpause)
    detection: STATIC — inverse grep: url_secret has non-zero consumers
    alert_route: CI red on the PR
  - mode: the self-ping cron itself never installs (the #6238 class)
    detection: registry_prd never reaches `up` after the replace -> AC13's bounded poll FAILS
               pre-close; thereafter absence alarms
    alert_route: Better Stack + the AC13 gate
  - mode: consumer-perspective private-net failure
    detection: NOT COVERED — #6438 §1, explicitly deferred
    alert_route: n/a

logs:
  where: Better Stack Logs source 2457081 (SOLEUR_ZOT_DISK self-report, 5-min cadence)
  retention: Better Stack plan default

discoverability_test:
  command: |
    doppler run -p soleur -c prd_terraform -- bash -c 'curl -fsS --max-time 30 \
      -H "Authorization: Bearer $BETTERSTACK_API_TOKEN" \
      https://uptime.betterstack.com/api/v2/heartbeats' \
      | jq -r ".data[] | [.attributes.name, .attributes.status, (.attributes.paused|tostring)] | @tsv"
  expected_output: |
    soleur-inngest-server-prd	up	false
    soleur-registry-prd	up	false
    soleur-registry-disk-prd	up	false
  # NO ssh. This exact command produced the evidence in this plan; today registry_prd reads
  # `paused true` — the post-merge assertion is that it reads `up false`.
```

### Soak follow-through enrollment

**Not required.** AC13's bounded poll (`status == up` within 900+600s) is deterministic and runs
in-session post-dispatch. No time-gated close criterion.

## Implementation Phases

Dependency-directed: the feeder must exist before the manifest can declare it, and both must land
before the arming.

### Phase 0 — Preconditions (verify; do not assume)

1. Re-pull `/api/v2/heartbeats`; confirm `registry_prd` still `paused`, and capture its **id**
   (`470365` today) for the arming `PATCH`.
2. `git grep -c "ZOT_HEARTBEAT_URL" -- ':!knowledge-base' | cut -d: -f2` → confirm still **1**
   (definition only). If a feeder landed meanwhile, **stop and re-plan**.
3. Re-confirm `betteruptime_heartbeat.registry_prd` is still in `OPERATOR_APPLIED_EXCLUSIONS`
   (`terraform-target-parity.test.ts:584`). **If it ever becomes targeted, this plan's "no
   resource change" constraint relaxes** and widening `period` becomes available — re-plan.
4. `bun test plugins/soleur/test/heartbeat-reprovision-parity.test.ts` → green baseline.
5. Confirm a cloud-init assertion suite exists for the registry (`ls apps/web-platform/infra/*registry*test*`
   / `git grep -l cloud-init-registry -- '*test*'`). **If none exists, Phase 1's RED step lands in
   the parity test instead** — do not invent a new suite.
6. Re-verify the next free ADR ordinal against `origin/main` (highest today: ADR-115).

### Phase 1 — The feeder (RED first)

Per `cq-write-failing-tests-before`: write T1–T4 **before** the script, against the suite Phase 0.5
identified.

- `zot-liveness-heartbeat.sh` — mirror `zot-disk-heartbeat.sh:148-157`:
  ```sh
  # Ping ONLY if zot answers on the host's OWN PRIVATE IP. NEVER localhost:
  # zot binds 0.0.0.0, so localhost:5000 answers even on a NIC-less host — which is
  # precisely why every existing signal missed #6400 (cloud-init-registry.yml:324-328).
  if curl -fsS -m 10 -o /dev/null "http://${private_ip}:5000/v2/"; then
    curl -fsS -m 10 "${liveness_heartbeat_url}" >/dev/null 2>&1 || true
  fi
  ```
  *(`${private_ip}` is already a templatefile var — `zot-registry.tf:321`.)*
- **systemd `.service` + `.timer`**, mirroring `inngest-bootstrap.sh:196-207`:
  `OnBootSec=30s`, `OnUnitActiveSec=60s`, enabled in `runcmd`. **NOT `/etc/cron.d`** — cron's 60s
  floor leaves no margin against the 90s deadline (see *The cadence constraint*).
- **No `doppler run` wrapper** — the URL is baked, so there is no empty-variable failure mode.
  *(inngest's Doppler-read shape failed exactly that way in #4116 — `inngest-bootstrap.sh:146-152`.)*

### Phase 2 — Wire the URL through `user_data`

- `zot-registry.tf` — add `liveness_heartbeat_url = betteruptime_heartbeat.registry_prd.url` to
  the `templatefile` vars, mirroring `disk_heartbeat_url` (`:310`). This mutates
  `hcloud_server.registry`'s `user_data` only — the host has **deliberately no
  `ignore_changes=[user_data]`** (`:324-326`), which is what makes replace-to-reprovision clean.
- **No `period` / `grace` / `paused` change.** **No resource deleted.** See *The cadence
  constraint*.

### Phase 3 — Executable arming (the manifest)

- Extract `MANIFEST` + `Arming` + `ManifestEntry` (`heartbeat-reprovision-parity.test.ts:57-79`)
  into `plugins/soleur/lib/heartbeat-manifest.ts` (dir exists; 6-file precedent). Move the
  `:30-43` header semantics with it — do not orphan them.
- Add the `feeder` field. Populate:

| Heartbeat | `feeder` |
| --- | --- |
| `registry_prd` | `{kind:"timer", evidence:{file:"apps/web-platform/infra/cloud-init-registry.yml", pattern:"zot-liveness-heartbeat.timer"}}` |
| `registry_disk_prd` | `{kind:"cron", evidence:{file:"apps/web-platform/infra/cloud-init-registry.yml", pattern:"/etc/cron.d/zot-disk-heartbeat"}}` |
| `inngest_prd` | `{kind:"timer", evidence:{file:"apps/web-platform/infra/inngest-bootstrap.sh", pattern:"INNGEST_HEARTBEAT_URL"}}` |
| `git_data_prd` | `{kind:"none", url_secret:"GIT_DATA_HEARTBEAT_URL", tracking_issue:<new>}` |
| `github_webhook_sig_failures` | `{kind:"none", url_secret:"<none — no URL secret exists>", tracking_issue:<new>}` |
| `github_api_429_sustained` | `{kind:"none", url_secret:"<none>", tracking_issue:<new>}` |

  *(The two webhook heartbeats have **no** `doppler_secret` URL — the inverse assertion needs a
  `url_secret: null` arm meaning "no secret to check"; specify it explicitly rather than letting
  it fall through.)*
- **`registry_prd`'s `arming` changes `web-host-cron` → `dedicated-host-boot`** — it is now armed
  by the registry host's own cloud-init. That makes it subject to ADR-103's `replace_target`
  requirement, which `registry-host-replace` already satisfies. The parity test enforces this;
  **this is a feature, not a workaround.** Its `exempt_reason` is deleted.
- Assertions (all static/offline): forward grep (+ **separate** file-existence check with its own
  message — `grep -F` exits 2 on missing file vs 1 on no-match); inverse zero-consumer grep;
  `tracking_issue` is a positive integer.

### Phase 4 — Ship, reprovision, verify, arm

1. Merge (auto-applies the TF `period`/`grace` via the `-target` allow-list).
2. `gh workflow run apply-web-platform-infra.yml -f apply_target=registry-host-replace -f reason="arm the zot liveness heartbeat (#6537)"`.
3. Poll Better Stack until `registry_prd.status` leaves `paused`-with-no-ping — i.e. **confirm a
   ping actually landed** (ask #1, satisfied by measurement, not assumption).
4. **Arm:** `PATCH /api/v2/heartbeats/<id> {"paused": false}` with `BETTERSTACK_API_TOKEN` (masked).
5. Bounded poll until `status == up` (≤ 60 + 30s + margin).

### Phase 5 — Correct the false comments

`zot-registry.tf:406-413` (the present-tense probe claim) **and** `:435-436` (the second forward
reference). Delete the dangling by-hand unpause sentence — that instruction, with no owner and no
forcing function, is the proximate cause of this bug. `alerts-github-webhook.tf:50-54` — delete
the false pings claim. `git-data.tf:271-274` — the TODO is honest; add the ADR-116 pointer only.

### Phase 6 — ADR + C4

ADR-116 (create), ADR-096 + ADR-103 (amend, incl. the `:359`→`:441` citation fix), `model.c4` ×3.
Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Phase 7 — Close the loop

- Comment on **#6438** with this plan's evidence (zero consumers; the on-host layer now ships;
  §1's remaining scope is the **consumer-perspective** probe only).
- File the deferred tracking issues (below).
- **Close #6537** — legitimately: asks #1 (verified), #2 (unpaused, armed), #3 (class gate) are
  all delivered. Use `Closes #6537`; `Ref #6438`.

## Files to Edit

- `apps/web-platform/infra/cloud-init-registry.yml` — the liveness script + systemd `.service`/`.timer` + `runcmd` enable
- `apps/web-platform/infra/zot-registry.tf` — `templatefile` var (`user_data` only) + 2 false comments (`:406-413`, `:435-436`). **No resource change.**
- `apps/web-platform/infra/alerts-github-webhook.tf` — false claim at `:50-54`
- `apps/web-platform/infra/git-data.tf` — ADR-116 pointer
- `plugins/soleur/test/heartbeat-reprovision-parity.test.ts` — import manifest; `feeder` assertions
- the registry cloud-init assertion suite identified in Phase 0.5 (T1–T4)
- `knowledge-base/engineering/architecture/diagrams/model.c4` — 3 edits

*Deliberately NOT edited:* `.github/workflows/apply-web-platform-infra.yml` and
`.github/workflows/apply-sentry-infra.yml` — v3 adds no `-target`-requiring resource, so neither
allow-list moves. Editing them would break the `OPERATOR_APPLIED_EXCLUSIONS` ruling.
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`
- `knowledge-base/engineering/architecture/decisions/ADR-103-dedicated-host-boot-heartbeats-require-guarded-reprovision-path.md`

## Files to Create

- `plugins/soleur/lib/heartbeat-manifest.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-116-executable-heartbeat-arming.md`

## Open Code-Review Overlap

`gh issue list --label code-review --state open --json number,title,body --limit 200`, matched
against every path above. **None.**

## Acceptance Criteria

### Pre-merge (PR)

1. **The heartbeat resource is untouched** — `git diff origin/main -- apps/web-platform/infra/zot-registry.tf`
   shows **no** change to `period`, `grace`, or `paused`, and **no** deleted resource:
   `git diff origin/main -- apps/web-platform/infra/zot-registry.tf | grep -cE '^[-+]\s*(period|grace|paused)\s*='` == **0**.
   *(This is the AC that keeps the PR inside the `OPERATOR_APPLIED_EXCLUSIONS` ruling. v2 proposed
   a `period` widening + a secret deletion that could never apply.)*
2. Forward assertion is **non-vacuous**: flipping `registry_prd`'s `evidence.pattern` to a
   nonexistent literal makes `bun test plugins/soleur/test/heartbeat-reprovision-parity.test.ts`
   **FAIL** with the feeder-absent message; flipping `evidence.file` to a nonexistent path fails
   with the **distinct** file-missing message.
3. Inverse assertion is **non-vacuous**: adding a dummy `GIT_DATA_HEARTBEAT_URL` consumer under
   `apps/` makes the suite **FAIL** with the "feeder shipped — re-declare `feeder`" message.
4. `grep -c "webhook route deliberately pings" apps/web-platform/infra/alerts-github-webhook.tf`
   == **0**, and `grep -c "exempt_reason" plugins/soleur/lib/heartbeat-manifest.ts` for the two
   webhook entries no longer asserts an `app-emit` feeder.
   *(v1's `grep -c "app-emit" … == 0` was **broken**: `app-emit` legitimately remains as the
   `Arming` union member (`:60`) and in the enum-documenting comments (`:36`, `:285`), and Phase 3
   keeps `arming` as-is. It would have false-failed a correct implementation.)*
5. `bun test plugins/soleur/test/heartbeat-reprovision-parity.test.ts` green — including ADR-103's
   `replace_target` requirement now firing on `registry_prd` (`arming: dedicated-host-boot`),
   which is satisfied by the existing `registry-host-replace` choice.
6. `bun test plugins/soleur/test/terraform-target-parity.test.ts` green — proves the PR did not
   disturb the `OPERATOR_APPLIED_EXCLUSIONS` contract.
7. Cloud-init T1–T4 pass (below), asserting the **private-IP** guard and that **no ping is emitted
   when the guard fails**.
8. `grep -c "localhost:5000" apps/web-platform/infra/cloud-init-registry.yml` is **unchanged** from
   baseline — the new feeder introduces **zero** new `localhost` probes. *(The existing boot
   readiness poll legitimately uses localhost; this asserts we did not add another.)*
9. `c4-code-syntax.test.ts` + `c4-render.test.ts` green; `grep -c "git-data heartbeats" knowledge-base/engineering/architecture/diagrams/model.c4` == **0**.
   *(v1 grepped a bare `model.c4` — no such path at repo root; grep would exit 2 and the AC never
   evaluate.)*
10. `ADR-116-*.md` exists, `status: accepted`, Alternatives Considered records the four rejected
    options. ADR-096's `zot-registry.tf:359` citation is corrected to `:441`.
11. Tracking issues for `git_data_prd` + the two webhook heartbeats exist, are OPEN, and their
    numbers are in the manifest.
12. `bash scripts/test-all.sh` green (catches orphan suites).
13. Every `knowledge-base/` path cited resolves (evaluated at PR time, after this plan's own
    `## Files to Create` land):
    `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | sort -u | while read -r f; do [[ -f "$f" ]] || echo "BROKEN: $f"; done` → empty.

*Deliberately NOT an AC:* v1's `terraform plan` "0 to add/change/destroy" on comment-only edits —
Terraform does not parse comments; it is `0/0/0` **by construction** and cannot fail. Replaced by
AC6, which asserts the real invariant (the `-target` line exists).

### Post-merge (automated — no human steps)

14. `registry-host-replace` dispatch succeeds; its existing scoped destroy-guard passes.
15. **A ping lands before arming** (ask #1, by measurement): Better Stack shows `registry_prd`
    received a beat while still `paused`, **or** the equivalent — the beat is observable within
    2 cron periods (10 min) of boot. *If no ping lands, STOP — do not arm.* Diagnose via
    `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep SOLEUR_ZOT_DISK`
    (the disk cron's co-located self-report proves whether cron.d is running at all).
16. `PATCH /api/v2/heartbeats/<id> {"paused":false}` returns 2xx.
17. Bounded poll: `registry_prd.status == "up"` and `paused == false` within 60 + 30s + margin,
    self-pulled via the discoverability_test command. **This is the literal answer to #6537.**
18. `gh issue close 6537` only **after** AC17 passes.
19. **Downtime precondition re-asserted at run time, BEFORE the Phase 4.2 dispatch** (not trusted
    from this plan's prose): the GHCR fallback is still warm — `grep -q 'status.*Adopting'` on
    ADR-096 **and** `grep -c 'app_ghcr_fallback' apps/web-platform/infra/cloud-init.yml` ≥ 1.
    **If ADR-096 has advanced to Phase-5 (GHCR retired), STOP** — the replace is no longer
    latency-only and this plan's `## Downtime & Cutover` analysis must be redone with a real
    maintenance window.
20. Post-replace, confirm the fallback either did not fire or fired benignly:
    `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep ghcr-fallback --limit 20`
    — informational; a fallback event during the window is **expected and correct**, not a defect.

## Test Scenarios

| # | Scenario | Expected |
| --- | --- | --- |
| **T1** | zot answers on `10.0.1.30:5000/v2/` | ping emitted |
| **T2** | **zot dead**, host alive, disk <85% | **NO ping** (the gap this PR closes — today this state pings green via the disk cron) |
| **T3** | **private NIC absent** (#6400 shape); zot bound `0.0.0.0`, `localhost:5000` answers | **NO ping** — proves the guard is not `localhost`. *The single most important test here.* |
| T4 | zot slow (> 10s) | `curl -m 10` fails → no ping; no hang, no partial |
| T5 | `evidence.pattern` absent from its file | static CI **RED** (feeder-absent message) |
| T6 | `evidence.file` path does not exist | static CI **RED** — **distinct** file-missing message |
| T7 | `kind:"none"` + its `url_secret` gains a consumer | static CI **RED** ("re-declare `feeder`") |
| T8 | `kind:"none"` + `tracking_issue` missing/non-integer | static CI **RED** |
| T9 | `registry_prd` declared `dedicated-host-boot` with no `replace_target` | static CI **RED** (existing ADR-103 check) |
| T10 | Post-replace, the timer never installs (unit not enabled) | AC15 measures **no ping** → **do not arm**; #6238 class caught before it can false-fire |

Cloud-init tests are **synthesized fixtures** (`cq-test-fixtures-synthesized-only`) — T1–T4 run
the script body against a stubbed `curl`; **no live mutation, no prod host in the test path.**

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| **A localhost self-ping would be blind to #6400** — the single highest-risk implementation slip | T3 is a dedicated test; AC8 asserts zero new `localhost:5000` probes. The repo documents the trap verbatim at `cloud-init-registry.yml:324-328`. |
| **`registry-host-replace` boots a NIC-less host** (#6400 recurrence) | #6415's L1 converger + L2 alarm; GHCR fallback (`model.c4:380`) covers pulls; store volume preserved. Same path used in #6122/#6247/#6288. |
| **A resource change that can never apply** — `registry_prd` is an `OPERATOR_APPLIED_EXCLUSION`, so any `period`/`grace`/delete edit is a silent no-op: the inert-monitor class, one level up, inside this very plan | **Designed out.** v3 changes **no** heartbeat resource; the feeder meets the existing `60/30` via a systemd timer (the proven `inngest_prd` shape). AC1 asserts the diff touches no `period`/`grace`/`paused`; Phase 0.3 re-confirms the exclusion. |
| **Timer misses the 90s deadline** → flapping → alarm fatigue on the one channel that must stay credible | `OnUnitActiveSec=60s` + `OnBootSec=30s` — the **exact** shape feeding `inngest_prd` at the **identical** `60/30`, live and `up` today. `curl -m 10` bounds both hops; the private-IP hop is LAN-local (~ms). If flapping is observed post-arm, the fix is the timer interval (cloud-init, replace-delivered), **not** the heartbeat resource. |
| **Cron ships but pings unconditionally** → false green, worse than today | T2/T3 + the guard-is-the-precondition shape. AC15 will not arm without a measured ping. |
| **Arming (`PATCH`) succeeds but nothing feeds** | Impossible by AC15's ordering: ping is **measured first**, arm second. This is ask #1 encoded as a gate. |
| **`git_data_prd` absent live with no `count` gate** — unexplained drift | Out of scope; delegated to `scheduled-terraform-drift.yml` and called out in Distinctness so its absence is not mistaken for a `count` gate. |
| **The self-ping is mistaken for consumer-perspective coverage** | ADR-096 amendment + Overview state plainly: this is the **on-host** layer. #6438 §1 stays open for the off-host probe. |
| **Free tier ⇒ email-only, no escalation** | Recorded; non-differential across all options including the status quo. |
| ADR-116 ordinal collision | `/ship`'s gate re-verifies vs `origin/main`; renumber sweeps plan+tasks+ACs in one edit (#5990). |

## Alternative Approaches Considered

| Option | Verdict |
| --- | --- |
| **Unpause now** (#6537's literal ask #2, taken literally) | **Rejected — evidence-backed.** Zero feeder ⇒ guaranteed false alarm. #6210 precedent. Ask #1 mandates this branch. **v2 satisfies the ask properly by building the feeder first, then unpausing.** |
| **v1: a nightly live-reconcile gate + its own workflow + Sentry monitor, and NO feeder** | **Rejected at plan-review — unanimous across 4 independent panels.** It left the registry unmonitored, stayed **silent** on `registry_prd` by its own T3 (feeder:none + paused + issue OPEN = OK), and cost more scope than the fix it declined. See Consolidation. |
| **`localhost:5000` self-ping** | **Rejected — structurally blind.** zot binds `0.0.0.0`, so localhost answers on a NIC-less host; `cloud-init-registry.yml:324-328` names this as why #6400 went unseen 14 days. |
| **Off-host L3 probe now** (#6438 §1) | **Correctly deferred.** Genuinely greenfield: web hosts carry `ignore_changes=[user_data]` ⇒ needs bake-and-extract. It is the **consumer-perspective** layer and remains valuable *after* this PR. |
| **Nightly live-reconcile as a step in `scheduled-terraform-drift.yml`** | **Deferred → tracking issue.** Genuinely cheap (~30 lines in a workflow that already has Doppler `prd_terraform`, a dedup-issue path, a Sentry monitor, and drift semantics) — but it catches **bookkeeping** drift, not infrastructure failure, and this PR removes its most valuable target by arming `registry_prd`. Ship after. |
| **A standalone `scheduled-inert-monitor-gate.yml` + `sentry_cron_monitor`** | **Cut.** `apply-sentry-infra.yml` applies via an explicit **71-entry `-target=` allow-list**; a monitor forgotten there ships inert. **v1's own watchdog would have been an inert monitor** — the exact class it existed to gate. |
| **`gh issue view` OPEN-check inside a live monitoring gate** | **Cut.** It does not catch the motivating case (a probe ship flips `feeder.kind` → the SILENT-GAP quadrant catches it), and it makes a monitor's verdict depend on issue-tracker state — a `gh` blip, a transfer, or a close-as-duplicate becomes a nightly false FIRE on the one channel that must stay credible. The static `tracking_issue` integer check survives. |
| **Forward-only feeder grep** (v1) | **Rejected.** One-directional: proves a *declared* feeder exists; cannot prove an *undeclared* one absent. Would have gone silent through a probe ship, then false-fired at the operator doing the right thing. The **inverse** zero-consumer assertion closes it. |
| **Keep `doppler_secret.zot_heartbeat_url_prd`** | **Rejected.** Zero consumers; keeping it forces a permanent inverse-grep exemption. #6438 §1 re-adds it if the off-host probe needs the Doppler-read shape. |

## Plan-Review Consolidation

Seven agents (`dhh`, `kieran`, `code-simplicity`, `architecture-strategist`, `spec-flow-analyzer`,
`cto`, `cpo`). **Both the simplification panel (dhh + code-simplicity) and the correctness panel
(kieran + spec-flow + architecture) fired on the same scope — Phases 4-5 of v1.** Per the
plan-review rule, that convergence means **delete, not fix**; the cut dissolved most of the P0s.

**Applied — Mechanical (auto-applied):**

| Finding | Source | Resolution |
| --- | --- | --- |
| **Premise 4 is false** — host death is already alarmed (disk cron, ≤25 min); the real gap is zot-process-death | cpo (Finding C), cto (0a) | **Verified independently** (`cloud-init-registry.yml:152-155`). Premise table + coverage table rewritten. v1 disbelieved the issue's *probe* claim but swallowed its *impact* claim. |
| **The 4 #6438 blockers all dissolve for a registry-host self-ping** | cto (explicit CTO ruling on the deferred architectural call) | **Self-ping adopted.** Blocker-by-blocker table added. |
| **A `localhost` self-ping is blind to #6400** (zot binds `0.0.0.0`) | cto | **Private IP adopted.** T3 + AC8 added. Repo documents the trap at `:324-328`. |
| **Forward-only grep can't prove an undeclared feeder absent** → gate goes silent through a probe ship, then false-fires at the operator | spec-flow (P0-1) | **Inverse zero-consumer assertion added** (T7, AC3). |
| **v1's `sentry_cron_monitor` would itself be inert** — `apply-sentry-infra.yml` uses a 71-entry `-target` allow-list | kieran (P0-3) | **Dissolved by the cut.** The lesson generalises: AC6 now guards the `period` widening the same way. |
| **AC1 unrunnable** — `git grep -c` emits `path:N`, not a scalar | kieran (P0-1) | Rewritten (AC1). |
| **AC5 self-contradictory** — `app-emit` is a live union member (`:60`) + enum comments (`:36`, `:285`); Phase 1 keeps `arming` as-is | kieran (P0-2), spec-flow (P1-4) | **Verified**; AC dropped, replaced with a narrow claim-scoped grep (AC4). |
| **AC12 grepped a nonexistent `model.c4`** at repo root | kieran (P1-4) | Path fixed (AC9). |
| **AC10 is a tautology; AC11 a proxy that passes in the failure world** | kieran (P1-6), dhh | Both cut; replaced by AC6. |
| **"Fires only on changed verdict" was a paper resolution** (no state store; precedent is create-only) | spec-flow (P1-1) | Dissolved with the cut. |
| **`git_data_prd` has no `count` gate yet is absent live** → v1's AC10 falsified; T7's "count-gated" rationale never covered it | spec-flow (P1-5) | **Verified** (`git-data.tf:243`). Recorded as drift; delegated. |
| **The ADR-033 override argued a straw man** — `scheduled-terraform-drift.yml:7-11` is already Inngest-*dispatched* + GHA-*executed*, which ADR-033's scope note blesses verbatim | cto (0b), code-simplicity | Dissolved with the cut. **v1's substrate reasoning was wrong.** |
| Second false comment at `zot-registry.tf:435-436`; `alerts-github-webhook.tf` citation drift (`:50-54`, and only 1 of 2 entries has a comment); `ADR-096:94` cites `:359` not `:441` | kieran (P2) | All folded into Phase 5 / Phase 6. |
| `grep -F` exits **2** on a missing file vs **1** on no-match — collapsing them misleads the debugger | code-simplicity | Separate file-existence assertion (T6, AC2). |
| **`registry_prd` / `registry_disk_prd` / `zot_heartbeat_url_prd` are `OPERATOR_APPLIED_EXCLUSIONS`** — untargeted by deliberate CTO ruling (2026-07-06). **v2's `period` widening and secret deletion could never apply**, and forcing them would need an operator-local apply (a forbidden manual step) | architecture (P0-2) | **Verified** (`terraform-target-parity.test.ts:584`; `apply-web-platform-infra.yml:1710-1713`; 0 `-target` hits vs 1 for `inngest_prd`). **v3 removes every resource change** and meets `60/30` with a systemd timer — the proven `inngest_prd` shape. This is the single largest v2→v3 correction. |
| **ADR-116 must not depend on `ignore_changes=[paused]`** — source ≠ live is *independently* guaranteed by the untargeted apply path, so the attribute-specific claim is weaker and more fragile than the truth | architecture (P0-2.2) | **Applied** — ADR-116's Decision now rests on the general property. |
| **#6438 §1's arming blocker is wrong on the merits** — its option (a) ("drop `ignore_changes=[paused]`") does **not** work: the heartbeat stays untargeted, so a source unpause is still a CI no-op | architecture (P0-2.3) | **Folded into Phase 7's #6438 comment.** Found by this plan; #6438's own analysis never checked the apply path. |
| **v1's `sentry_cron_monitor` would never be applied** — `apply-sentry-infra.yml` is `-target`-scoped (71 lines) with **zero** parity enforcement; AC11 (untargeted local plan) would go green while CI applied 0 | architecture (P0-1), kieran (P0-3) | **Dissolved by the cut** — v3 adds no monitor and no workflow. |
| **`evidence.file` unconstrained**: a pattern in a `.tf` comment or doc satisfies the gate; and `feeder.evidence` is never joined to `replace_target`, so a feeder in cloud-init on a host with no reprovision path passes | architecture (P1-a/b) | **Closed by construction**: `registry_prd` becomes `arming: dedicated-host-boot`, which ADR-103 already *requires* to carry a `replace_target`. AC5 asserts that check now fires. |
| **`model.c4:444`'s "49 cron monitors / 6 check in from here"** would go stale | architecture (P1-6) | **Moot** — v3 adds no monitor and no workflow. Counts unchanged. |
| "Delete the heartbeat" was a missing Alternative (the invariant admits *feed it* **or** *remove it*) | architecture (P1-5) | **Moot for `registry_prd`** — v3 feeds it. Recorded in ADR-116 as the second legal resolution, which is what the deferred `git_data_prd`/webhook entries may take. |
| ADR-096 pointer + `decision-challenges.md` were decoration / a 3rd representation | code-simplicity | ADR-096 amendment **kept** (it is now substantive — the self-ping supersedes its "does not exist yet" note); `decision-challenges.md` **cut** (the CTO ruled; there is no open challenge). |

**Applied — User-Challenge (the operator's stated scope):**

> **v1 dropped operator-requested scope (the unpause) and substituted unrequested work (a gate).**
> cpo put it bluntly: v1 rejected building the probe as *"out of scope for a plan whose premise was
> 'just unpause it'"* and then shipped a lib module, a script, a nightly workflow, a Sentry
> monitor, an ADR, 2 amendments, 3 C4 edits, 3 issues, 10 scenarios and 20 ACs. *"'Too big for
> this plan' cannot be true of the small thing and false of the large thing in the same
> document."*
>
> **Resolution: the challenge dissolves — v2 delivers the ask.** Build the feeder (small, proven
> path), then unpause. Asks #1, #2, #3 are all satisfied. No `decision-challenges.md` entry is
> needed because there is no longer a live disagreement with the operator's direction.

**Deliberately NOT applied:**

- **dhh: "move the `gh issue` check into the static CI test."** Rejected — it would make an
  offline unit test network-dependent; `gdpr-gate.test.ts:391-400` deliberately neutralises
  `GH_TOKEN` for exactly this reason. The static check stays a positive-integer assertion; the
  live issue-state check is cut entirely rather than relocated.
- **cpo: "do not close #6537 while its substance sits in Post-MVP/Later" (#6438's milestone).**
  Correct **for v1**, moot for v2 — v2 closes the substance here. #6438 retains only the off-host
  layer.
- **dhh: "merge ADR-116 into an ADR-103 amendment."** Rejected — ADR-116 is a cross-cutting
  invariant over *all* heartbeats; ADR-103 is specifically the dedicated-host-boot reprovision
  path. Folding them would repeat the conflation that produced the false `app-emit` claim.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO)

### Engineering (CTO)

**Status:** reviewed (full advisory in Consolidation)
**Assessment:** Made the **decisive architectural ruling** v1 deferred: all four #6438 §1 blockers
are L3-specific and dissolve for a registry-host self-ping, so the deferral was unjustified.
Supplied the load-bearing technical correction (private IP, not localhost — verified against
`cloud-init-registry.yml:324-328`) and corrected two of v1's own claims (the "no liveness alarm"
framing; the ADR-033 substrate straw man). Net: **small complexity, closes the one uncovered
row, answers #6537 literally.**

### Product (CPO)

**Status:** reviewed
**Assessment:** Confirmed refusing the *naked* unpause is correct and well-evidenced, but ruled
v1's swap a **substitution** of agent-preferred work for the operator's ask, and surfaced that
v1's gate was **silent on the very monitor #6537 reported** (its own T3). Also caught that #6537
sits in **Phase 4: Validate + Scale** while #6438 is **Post-MVP / Later (804 open)** — so v1's
"tracked at #6438" was, in roadmap terms, a demotion. v2's founder-facing framing follows CPO's
recommendation (lead with *"you told me to check first"*, own the premise correction, state the
residual gap).

### Product/UX Gate

**Not applicable.** No path in `## Files to Edit` / `## Files to Create` matches the UI-surface
term list or glob superset. Mechanical override did **not** fire. Product surface = **NONE**
(the CPO review above is a *scope* advisory, not a UX gate).

### GDPR / Compliance Gate (Phase 2.7)

**Skipped — no regulated-data surface.** No schema, migration, auth flow, API route, or `.sql`.
Expansion triggers (a)–(d) negative: no LLM/external-API processing of operator data; threshold is
`aggregate pattern`; no cron reads `learnings/` or `specs/`; no new artifact distribution surface.

## Deferred Items — Tracking Issues Required

1. **Off-host consumer-perspective probe** → **#6438 §1** (exists). Comment this plan's evidence;
   note its scope is now **only** the consumer-perspective layer.
2. **`git_data_prd` feeder** (`git-data.tf:271-274`, #5274 PR C) → new issue; number goes in the
   manifest's `tracking_issue`. Re-eval: when the git-data probe ships. **Also note its
   unexplained live absence** (no `count` gate) for `scheduled-terraform-drift.yml`.
3. **Both `alerts-github-webhook.tf` heartbeats** → **one** new issue (they share a re-eval
   trigger: `betterstack_paid_tier` flips true). Records the corrected finding: **no route pings
   them today** — the `app-emit` claim was false.
4. **Nightly live-reconcile as a step in `scheduled-terraform-drift.yml`** → new issue. Re-eval:
   after this PR. Scope: `live ⊆ manifest` + `live_paused == (feeder.kind === "none")`. Must
   define a `live_name` join key (manifest `name` is the **TF resource name** `registry_prd`; the
   API returns `soleur-registry-prd`), a per-heartbeat **and** per-class dedup title, and
   **create-only** issue semantics (`scheduled-zot-restart-loop.yml:267-277`).

## Founder-Facing Summary (for the PR body / `/ship`)

> **You asked me to switch the registry alarm on. I checked first, like you said to — and the
> alarm had nothing wired to it.** Nobody ever built the part that sends the heartbeat. Switching
> it on would have paged you every 90 seconds, forever. We did exactly that to ourselves on 7 July
> (#6210).
>
> **One correction to the report:** the registry was *not* unmonitored. If the machine dies, the
> disk alarm already tells you within ~25 minutes. The real gap was narrower — **if the registry
> *software* died while the machine stayed up, everything looked green.**
>
> **What I did:** built the missing piece (~20 lines, in the same file as the alarm that already
> works), then switched your alarm on. `soleur-registry-prd` is live — the thing you asked for,
> working.
>
> **Why it sat dark for 9 days:** a monitor's "what feeds this?" answer lived in a code comment,
> and comments can lie. Two of ours had been lying for months. That answer is now checked by the
> build, so it can't rot again.
>
> **Still open (#6438):** proving the private network works from another machine's point of view.
> Deeper problem, tracked, not urgent now that the above is live.

## AI-Era Notes

- Research: `Explore` (feeder trace — the decisive zero-consumer evidence + the false `app-emit`
  finding). Review: 7-agent panel. Live evidence self-pulled via `curl` + `jq` against
  `/api/v2/heartbeats`, creds from Doppler `prd_terraform`. **No dashboard, no SSH.**
- **The highest-leverage finding came from disbelieving the issue body** — one grep
  (`ZOT_HEARTBEAT_URL` → 1 hit, its own definition) inverted "unpause it" into "the probe was never
  built." #6537's ask #1 named its own falsifier; that is a well-written ask.
- **The second-highest came from disbelieving *this plan*.** v1 applied that skepticism to the
  issue's probe claim and then swallowed its impact claim (*"the host can die silently"*) — which
  the disk cron falsifies. The same reviewer pass caught v1 deferring a fix it had already proven
  cheap. **Verify the premise you inherit *and* the premise you write.**
- **Prose in a guard is not a guard.** The `app-emit` claim was false for months *inside the guard
  built to prevent that class* (#6242). That observation shaped `feeder.evidence` — and its
  bidirectional form, which only surfaced under review.
