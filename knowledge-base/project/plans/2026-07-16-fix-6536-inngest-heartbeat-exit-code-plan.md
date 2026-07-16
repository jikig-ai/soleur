---
title: "fix(6536): inngest-heartbeat.service exits non-zero every 60s — two measured defects, and the premise that there is a post-ping step is false"
date: 2026-07-16
issue: 6536
branch: feat-one-shot-6536-inngest-heartbeat-exit-code
lane: cross-domain
type: bug-fix
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
component: infrastructure
module: apps/web-platform/infra
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 reviewed. This plan prescribes ZERO operator steps and ZERO SSH. Delivery is the
  existing automated path: merge -> deploy webhook -> ci-deploy.sh -> inngest-bootstrap.sh
  (idempotent always-reconcile contract, inngest-bootstrap.sh:86-92). The `systemctl` strings the
  guard matched are DESCRIPTIVE — they name what the bootstrap script already does on every run,
  and the surrounding prose ("no operator SSH, no manual restart") states the opposite of an
  operator instruction. See ## Infrastructure (IaC) for the apply path.
-->

# fix(#6536): the heartbeat unit's ping never lands — the monitor is green because a *different host* pushes it

## Overview

`inngest-heartbeat.service` on the **dedicated** Inngest host has exited non-zero every ~60s
since 2026-07-13 13:00:38Z (3,724 failures). The issue infers from `monitor=up` + `unit=failed`
that "the ping lands successfully; the unit then exits non-zero on a later step."

**That inference is refuted by measurement.** There is no later step, the failing unit's ping
never lands, and the monitor is green because the **co-located web host** is the sole pusher —
exactly as `inngest-host.tf:137-151` designs it. Two independent, separately-measured defects
each produce the exact symptom. Both are real; both are fixed here.

This plan therefore does **not** hunt for a post-ping step. It (1) ships the discriminating
probe first, (2) fixes both measured defects, (3) corrects the false comment that authorised
one of them.

## Research Reconciliation — Issue Premise vs. Measured Reality

| Issue claim | Measured reality | Plan response |
|---|---|---|
| "The ping lands successfully; the unit then exits non-zero on a **later step**." | **False.** `inngest-bootstrap.sh:160-164` is the whole script: `exec /usr/bin/curl -fsS --max-time 10 "$INNGEST_HEARTBEAT_URL" >/dev/null`. `exec` replaces the shell — curl's rc **is** the script's rc. There is no status write, no cleanup, no trailing command. | Do not chase a post-ping step. Reframe around the two measured defects below. |
| "Candidate: a trailing command whose rc leaks under `set -e`." | **Non-existent.** The script has no `set -e` and no trailing command. | Dropped. |
| Monitor `up` ⇒ this unit's curl succeeds. | **Decoupled signals.** `INNGEST_HEARTBEAT_URL` is **present** on `soleur/prd` (co-located web host) and **absent** on `soleur-inngest/prd` (dedicated host) — measured via `doppler secrets --only-names`. `inngest-host.tf:137-151` states the co-located host is the *sole intended pusher* pre-cutover. | The two signals are independent. Monitor greenness is **not** evidence about this unit. |
| Cited `inngest-bootstrap.sh:216-245` for the unit shape. | **Line drift.** 216-245 is the Doppler-token materialisation block. The unit is at **`inngest-bootstrap.sh:178-194`**; the ping script at **160-164**. | Cite corrected lines throughout. |
| Cited `cat-deploy-state.sh:344-352`. | **Holds.** `HEARTBEAT_STATUS` is at `cat-deploy-state.sh:344`. | Kept. |
| "`_SYSTEMD_UNIT='inngest-heartbeat.service'` returns zero rows" is a Better Stack retention/index gap. | **No — the events never leave the host.** The unit matches **zero** `vector.toml` sources (§Defect C). | Fix the shipper, not the query. |

## Hypotheses — and how each was falsified or confirmed

Per `hr-observability-as-plan-quality-gate` and the #6497 doctrine (*measure, don't infer*),
every hypothesis below was tested against a live artifact, not read off a config.

| # | Hypothesis | Verdict | Evidence |
|---|---|---|---|
| H1 | `doppler run` exits non-zero *after* the child succeeds (fallback-write failure) — the "later step". | **REFUTED** | Live probe, Doppler CLI **v3.75.3**: with an unwritable fallback dir, `doppler run -- sh -c 'echo CHILD_RAN; exit 0'` → `CHILD_RAN_count=0`, `rc=1`. **The child never runs.** Doppler exits *before* exec, so this class can never produce "ping lands, then fails" — it produces a **down** monitor. |
| H2 | Floating Doppler CLI install picked up a bad release ~2026-07-13. | **REFUTED** | `cloud-init-inngest.yml:184-188` pins `DOPPLER_VERSION="3.75.3"` + `sha256sum -c -` gate. A new release cannot reach the host. |
| H3 | `/tmp/.doppler` ownership/`PrivateTmp` clash with the sibling unit. | **REFUTED as cause** (real asymmetry, not firing) | `inngest-server.service` sets `PrivateTmp=true` (`inngest-bootstrap.sh:431`); the heartbeat sets none — so they use *different* `/tmp`s and cannot collide. Nothing `mkdir`s `/tmp/.doppler`; the CLI creates it lazily as `deploy`. |
| **H4** | **`DOPPLER_PROJECT` defaults to `soleur` on the existing-host redeploy path, so the unit is rewritten pointing at a project the host's token cannot read.** | **REFUTED as the live cause — latent defect on a path this host does not use** | The `:-soleur` default at `inngest-bootstrap.sh:47` is real, and `grep -c DOPPLER_PROJECT ci-deploy.sh` → **0**, `deploy-inngest-bootstrap.sudoers:16` `env_keep` omits it. **BUT** the dedicated host never traverses that path: `cloud-init-inngest.yml:396` **already** passes `"DOPPLER_PROJECT=soleur-inngest"` into the bootstrap at boot; `grep -c 'sudoers\|env_keep' cloud-init-inngest.yml` → **0**; and `cloud-init-inngest.yml:319-320` states the dedicated host has **no** `/etc/default/webhook-deploy`, so no ci-deploy/webhook redeploy reaches it. On the **web** host the `soleur` default is *correct*. H4 therefore fires **nowhere today**. |
| **H5** | **An absent `INNGEST_HEARTBEAT_URL` makes curl "no-op" (as `inngest-host.tf:148` asserts).** | **CONFIRMED — the sole live cause** | Live probe: `curl -fsS --max-time 10 ""` → **rc=2** (`curl: option : blank argument where content is expected`). Unset behaves identically. An absent URL is **not** a no-op; it fails the oneshot every 60s. Same class as #4116 (`curl` exit 3 on empty URL). Combined with the measured absence of `INNGEST_HEARTBEAT_URL` on `soleur-inngest/prd`, this alone explains every datum: 100% of fires fail, the co-located host keeps the monitor green, and the onset is the dedicated host's boot/replace. |

**H5 is the sole live cause.** H4 is a **latent trap**, not today's bug — it would fire only if the
dedicated host ever gained a ci-deploy/webhook redeploy path. Fixing it here would edit
`ci-deploy.sh` + `deploy-inngest-bootstrap.sudoers`, neither of which the failing host uses. That
work is therefore **descoped to a follow-up issue** (see §Descoped). FR2 (fail-closed on the
`:-soleur` default) is retained only if it costs no extra delivery risk — see §Delivery reality.

### What is NOT yet established — and why that is the first deliverable

The precise **13:00:38Z onset is not attributed.** The nearest live events are
`scheduled-inngest-health.yml` at 12:51:13Z (failure) / 12:55:40Z (success) and
`restart-inngest-server.yml` at 11:37:35Z (success) — none at 13:00. Commit `e62c1ddb`
(12:32:44Z, #6384) rewrote `scheduled-inngest-health.yml` 28 minutes before onset but touches no
unit file.

**We cannot close that gap from the repo — the deciding datum is the unit's own stderr, and it is
discarded at the source.** This is precisely the #6497 destroyed-datum class the issue names, and
the `2026-07-01-blind-surface-needs-structured-probe-before-nth-fix` learning: *do not ship the
Nth blind fix; ship the probe that discriminates the hypotheses in one event.*

The stderr **is** the discriminator, and it separates H4 from H5 cleanly:

- **H4 fires** → Doppler's project/auth error (exit 1, frequently no output — `2026-05-15` learning).
- **H5 fires** → `curl: option : blank argument where content is expected` (exit 2).

Phase 1 ships that probe **before** the fixes, so the next fire self-reports which defect was live
and the fix is verified against evidence rather than assumed.

## Defect C — why the stderr is invisible (three compounding filters)

`vector.toml` ships journald → Better Stack. The heartbeat matches **zero** of its sources:

| Source | Filter | Heartbeat outcome |
|---|---|---|
| `[sources.inngest_journald]` (`vector.toml:27-32`) | `include_units = ["inngest-server.service"]`, `PRIORITY 0-4` | Excluded by unit name (single-element allowlist). |
| `[sources.system_journald]` (`vector.toml:37-42`) | `include_matches.PRIORITY = ["0","1","2"]` | Reaches the source, then dropped: unit output is `SyslogLevel=info` → **PRIORITY 6**. |
| `[sources.app_container_journald]` (`vector.toml:65-69`) | `CONTAINER_NAME` | Not a container. |
| `[sources.host_scripts_journald]` (`vector.toml:125-156`) | **13** exact `SYSLOG_IDENTIFIER` tags (counted at `vector.toml:127-154`; the file's own "Twelve"/"all 12" comments at `:100`,`:114`,`:119` are **stale** — they predate `inngest-registry-probe`/`inngest-doublefire-probe`), **no PRIORITY filter** | No heartbeat tag. |

Compounding this: the unit sets **no `SyslogIdentifier=`** (`grep` → zero matches file-wide), so
systemd derives `SYSLOG_IDENTIFIER` from the ExecStart basename → **`doppler`**, not
`inngest-heartbeat`. A naive tag guess would match nothing.

`vector.toml:108-110` already warns: *"include_matches is `sd_journal_add_match` exact-value
equality, NOT prefix/regex — a tag typo silently matches nothing."* And
`2026-07-08-inngest-cutover-authoring-review-and-observability-allowlist.md:15`: *"'Rides the
shipper' is a claim to verify against the allowlist, never a fact."* The heartbeat would be the **fourteenth** — the array holds 13 today.

**Chosen fix: Source 4 (`SyslogIdentifier` allowlist).** It is the pattern the repo already
blesses, and it is the only one that works: Source 4 has **no PRIORITY filter**, so PRIORITY-6
lines survive. Adding the unit to Source 1 would **not** work (its `PRIORITY 0-4` cut still drops
level-6 lines) — an easy trap, explicitly rejected here. Widening Source 2's PRIORITY is rejected
at `vector.toml:114-117` on quota grounds.

## User-Brand Impact

**If this lands broken, the user experiences:** a production Inngest scheduler outage that no
longer pages. Making the absent-URL branch exit 0 unconditionally would blind
`betteruptime_heartbeat.inngest_prd` after cutover — every cron the founder depends on (reminders,
digests, reconciles) stops silently, for hours, with a green dashboard. The unit's failure state
is the only liveness signal the dedicated host has; spending it is the exact harm #6536 reports,
inverted.

**If this leaks, the user's infrastructure credentials are exposed via:** `INNGEST_HEARTBEAT_URL`
is a bearer-capability URL (anyone holding it can forge liveness). It is deliberately kept out of
the journal — `inngest-bootstrap.sh:156-159` indirects through a script file *specifically* so
systemd never logs a resolved `ExecStart=`, and it is `sensitive = true` in TF output. **This plan
adds logging to that unit**, and a naive `logger "url=$INNGEST_HEARTBEAT_URL"` would defeat that
control and ship the secret to a third-party vendor (Better Stack). The new log line MUST assert
*presence/absence only*, never the value.

**Consumer enumeration (CPO P2-1) — by host, not by surface.** `inngest-bootstrap.sh` is a
**shared image serving two hosts**, and v2 enumerated by *surface* (the dedicated host), which is
precisely what hid CPO P1-1. Every host that executes the ping script:

| Host (`DOPPLER_PROJECT`) | `INNGEST_CUTOVER_FLIP` defined? | URL today | FR3 on absent URL | Role |
|---|---|---|---|---|
| co-located web (`soleur`) | **No — by design** (`inngest-bootstrap.sh:287`) | **present** (`soleur/prd`) | **exit 1** — always a real fault | **TODAY'S live scheduler + sole monitor pusher** |
| dedicated (`soleur-inngest`) | Yes (absent today ⇒ `unset`) | **absent** (`soleur-inngest/prd`) | exit 0 only when not the intended pusher | dark / pre-cutover; inert |

Ask *"which hosts execute FR3?"* and the web host surfaces immediately; ask *"what does this do on
the dedicated host?"* and it never comes up. The exit-0 arm is **project-gated first** for exactly
this reason (§AC5b).

**Brand-survival threshold:** `single-user incident`

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Infrastructure-only change to a prod liveness path on a deny-all-public host.
Three concerns carried into the plan: (1) the exit-0 branch must be *scoped* so it cannot mask a
post-cutover regression (see FR3 discriminator); (2) the new journald channel must not leak the
bearer URL and must be covered by the existing PII-scrub drift guard; (3) H4's blast radius
exceeds the heartbeat — see Sharp Edges.

### Product/UX Gate

Not applicable — mechanical UI-surface scan over `## Files to Edit` matched no UI-surface path
(no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`). Product tier: **NONE**.

**CPO sign-off:** required at plan time per `brand_survival_threshold: single-user incident`.
`user-impact-reviewer` is invoked at review time by `review/SKILL.md`'s conditional-agent block.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200` cross-referenced against
every path in `## Files to Edit` (`inngest-bootstrap.sh`, `vector.toml`, `inngest-host.tf`,
`cat-deploy-state.sh`) returned zero matches.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/inngest-host.tf` — **comment-only** correction at lines 137-151 (the
false "curl no-ops" claim). No resource, provider, or variable changes. No new `TF_VAR_*`, no
operator mint, no vendor-tier gate.

### Apply path — **(c) replace: this is a host rebuild of the sole prod scheduler**

**This section was wrong in v1 and is corrected here.** v1 claimed "(b) cloud-init + idempotent
bootstrap, delivered by the webhook deploy path, zero operator steps." **That is false for the
failing host**, and the error mattered — it understated the plan's entire risk profile.

Measured reality for the **dedicated** Inngest host:

- `grep -c 'sudoers\|Cmnd_Alias\|env_keep' cloud-init-inngest.yml` → **0**. No sudoers gate exists;
  `/etc/sudoers.d/deploy-inngest-bootstrap` is delivered only to the **web** host
  (`cloud-init.yml:79`, `server.tf:793`).
- `cloud-init-inngest.yml:319-320`: the dedicated host has **no** `/etc/default/webhook-deploy`.
  There is no webhook, so `ci-deploy.sh` never reaches it.
- Its **only** `inngest-bootstrap.sh` invocation is `cloud-init-inngest.yml:394-398` — under
  `runcmd`, as root, **at boot**.
- `inngest-host.tf:244`: *"Deliberately NO `lifecycle.ignore_changes=[user_data]`"* — so any
  cloud-init/bootstrap edit produces a `user_data` diff that **forces a server replace**
  (`hr-prod-host-config-change-immutable-redeploy`).
- **ADR-100**: this host is the **SOLE** scheduler.

⇒ Delivering FR3/FR4 to the failing host means **replacing the dedicated Inngest host**, in the
middle of the in-flight #6178 cutover. That is a real operational event. It is Terraform-driven
(`terraform apply` on `inngest-host.tf`), so it stays inside IaC and needs no SSH, but the plan
must **not** pretend it is free.

### Delivery split — **CORRECTED again (v3), measured**

**v2's split is FALSE and would have broken /work.** v2 claimed "FR5 `vector.toml`, FR6, FR7 need
no host replace." Measured:

- `cloud-init-inngest.yml:337` pins **`IREF=ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.19`**.
- **Both** `inngest-bootstrap.sh` **and** `vector.toml` are extracted from that OCI image at boot
  (`cloud-init-inngest.yml:368` `docker cp …:/vector.toml`; `:370` `chmod +x $EXTRACT_DIR/inngest-bootstrap.sh`).
- The bootstrap runs **only** under `runcmd`, at boot. A running host never re-reads either file.

⇒ The replace trigger is **not** "editing `inngest-bootstrap.sh`" (that file is not in `user_data`
at all). It is the **`IREF` tag bump at `cloud-init-inngest.yml:337`**, which *is* templated into
`user_data` (`inngest-host.tf:200`) and, with no `ignore_changes=[user_data]` (`:244`), forces the
replace. Re-pushing a mutable `v1.1.19` would produce **no** `user_data` diff and **no** replace —
and the running host would keep the old units. Either way, **FR5 rides the same image as FR3/FR4**.

**Corrected split:**

| FR | Delivery | Replace? |
|---|---|---|
| FR3, FR4, **FR5** | OCI image `soleur-inngest-bootstrap` → `IREF` bump → `user_data` diff | **Yes** |
| FR6 (`inngest-host.tf` comment) | Terraform comment only | No |
| FR7 (`cat-deploy-state.sh`) | Not in `user_data`; verify its own delivery path | No |

**Risk reframe (measured).** `INNGEST_CUTOVER_FLIP` and `INNGEST_HEARTBEAT_URL` are **both absent**
from `soleur-inngest/prd` ⇒ the dedicated host is **dark/pre-cutover**; the **co-located** host is
the live scheduler and sole monitor pusher. `inngest-host.tf:244`'s "SOLE scheduler" is ADR-100's
**post-cutover** end-state, not today's. Replacing a dark, inert host does not interrupt prod
scheduling — AC13 (monitor stays `up`) holds precisely because the co-located host keeps pushing.
**Deepen-plan MUST confirm the #6178 cutover interaction and the `IREF` bump mechanics** (new tag
vs. digest pin) rather than let /work discover them.

**Verification** is `cat-deploy-state.sh` + Better Stack — no SSH (`hr-no-ssh-fallback-in-runbooks`).

### Distinctness / drift safeguards

`dev != prd` is not implicated (the dedicated host exists only in prd). The `soleur` vs
`soleur-inngest` project split **is** the distinctness boundary this plan repairs: FR1 makes the
project explicit end-to-end rather than defaulted, and FR2 fails closed if it is ever unresolvable.
No `lifecycle.ignore_changes` involved. No secret values enter `terraform.tfstate`.

## Downtime & Cutover

**Gate 4.55 fires** (deepen-plan): the plan produces a `must be replaced` on `hcloud_server`
(the dedicated Inngest host) via the `IREF` bump at `cloud-init-inngest.yml:337` → `user_data`
diff → no `ignore_changes=[user_data]` (`inngest-host.tf:244`). Zero-downtime must be evaluated
and defaulted to, not assumed away.

### The offline-inducing operation, and the surface it affects

- **Operation:** `terraform apply` replaces `hcloud_server` (dedicated Inngest host), detaching
  and re-attaching `hcloud_volume_attachment.inngest_redis` (`inngest-host.tf:272-273`).
- **Surface affected:** the **dedicated** host only.

### Zero-downtime evaluation — the default, and why it already holds

**This replace is zero-downtime for every serving surface, by measurement, not by mitigation.**

| Question | Measured answer |
|---|---|
| Is the replaced host serving prod scheduling? | **No.** `INNGEST_CUTOVER_FLIP` is **absent** from `soleur-inngest/prd` ⇒ the flip guard (`inngest-bootstrap.sh:414-418`, blocks a prod-URI start outside `{armed, flipping, done}`) holds the host inert. The **co-located** host is the live scheduler. |
| Is it pushing the prod liveness monitor? | **No.** `INNGEST_HEARTBEAT_URL` is **absent** from `soleur-inngest/prd` — by design (`inngest-host.tf:137-151`: one unambiguous pusher per monitor; the URL is provisioned only *at* cutover). The co-located host is the sole pusher — which is exactly why AC13 (monitor stays `up`) holds *through* the replace. |
| Does the AOF volume carry in-flight work? | **No.** A dark host runs no queue; `hcloud_volume.inngest_redis` is a separate resource that survives the replace (`inngest-host.tf:248-249`). Re-attach is still verified (git-data precedent) — see AC14. |

⇒ **No blue-green, drain, or maintenance window is required**, because the resource under replace
serves nothing. The zero-downtime path is not a *mitigation* we add; it is the *measured* state.
`inngest-host.tf:244`'s "SOLE scheduler ⇒ cron-outage window" is ADR-100's **post-cutover**
end-state and does **not** describe today. **Ship this before cutover, not after** — the same
replace after the flip is armed WOULD be a real outage needing the maintenance-window dispatch.

**Residual risk accepted:** none requiring sign-off. The dark host has no liveness push during
dark (a pre-existing, documented gap — `inngest-host.tf:149-151`), so a replace that bricked the
host would surface at the #6178 Phase-2 pre-flight registry-empty check, not by continuous
monitoring. FR3+FR4 **narrow** that gap: post-fix the dark host emits a positive
`url_present=no flip=unarmed` row every 60s, which is the first continuous dark-host liveness
evidence this host has ever had.

### Per-stage verification / rollback

| Stage | Verify (no SSH) | Rollback |
|---|---|---|
| Pre-apply | `terraform plan` shows exactly one `hcloud_server` replace + volume re-attach; **no** co-located resource in the diff | Do not apply |
| Post-apply | `cutover-inngest.yml --field op=inventory`; Better Stack `SYSLOG_IDENTIFIER=inngest-heartbeat` ≥1 row/60s (AC11) | Revert the `IREF` bump → re-apply (host is dark; a second replace is equally free) |
| Steady | AC12 (`Failed to start` stream stops) + AC13 (monitor still `up`) | As above |

**Ordering constraint (load-bearing):** this must land while `INNGEST_CUTOVER_FLIP` is unset. If
#6178 arms the flip first, re-run this gate — the zero-downtime conclusion inverts.

## Observability

```yaml
liveness_signal:
  what: betteruptime_heartbeat.inngest_prd ("soleur-inngest-server-prd"), pushed by
        inngest-heartbeat.service via inngest-heartbeat.timer
  cadence: 60s (OnUnitActiveSec=60s), period=60 grace=30
  alert_target: Better Stack heartbeat monitor -> existing notification policy
  configured_in: apps/web-platform/infra/inngest.tf:290 (monitor),
                 apps/web-platform/infra/inngest-bootstrap.sh:178-205 (unit + timer)

error_reporting:
  destination: journald (SYSLOG_IDENTIFIER=inngest-heartbeat) -> Vector
               [sources.host_scripts_journald] -> Better Stack
  fail_loud: true — the unit exits non-zero on every real fault (URL present but ping fails,
             or an intended pusher with no URL). The ONLY exit-0 branch is the dark case on the
             DEDICATED host, scoped by BOTH `DOPPLER_PROJECT=soleur-inngest` AND flip state, and
             it emits an explicit INFO naming the reason (never silent). The co-located web host
             has NO exit-0 branch — an absent URL there always exits non-zero (CPO P1-1; v2's
             flip-only form wrongly pinned the live pusher into the dark arm).

failure_modes:
  - mode: Doppler project unresolvable / token not scoped to it (H4 — the DOPPLER_PROJECT
          default-to-`soleur` regression on the redeploy path)
    detection: journald SYSLOG_IDENTIFIER=inngest-heartbeat carries doppler's stderr AND the
               explicit `project=<name> resolved=<yes|no>` field emitted by the unit before exec
    alert_route: Better Stack (host_scripts_journald) + unit enters `failed` -> cat-deploy-state
  - mode: INNGEST_HEARTBEAT_URL absent while cutover is ARMED (a real post-cutover regression)
    detection: unit exits non-zero and logs `url_present=no flip=armed` — the discriminating
               field pair; distinct from the legitimate dark case (`url_present=no flip=unarmed`)
    alert_route: Better Stack heartbeat goes down (no pusher) + unit `failed`
  - mode: INNGEST_HEARTBEAT_URL absent while dark/unarmed (legitimate, by design)
    detection: unit exits 0 and logs `url_present=no flip=unarmed skipping ping (dark host)`
    alert_route: none by design — this is the documented pre-cutover steady state
  - mode: URL present, ping fails (network, Better Stack outage, revoked URL)
    detection: curl stderr on the inngest-heartbeat channel + monitor goes down
    alert_route: Better Stack heartbeat monitor -> notification policy

logs:
  where: journald on the dedicated inngest host (persistent, /var/log/journal — asserted by
         cat-deploy-state.sh:111 journald_storage_json) -> Vector -> Better Stack
  retention: Better Stack source retention (existing); journald persistent on-host

discoverability_test:
  # CORRECTED (obs P2-4): v2's second line was prose ("then query Better Stack for ...") — an
  # instruction to eyeball a dashboard, which hr-no-dashboard-eyeball-pull-data-yourself forbids.
  # The repo ships the executable form (runbook: knowledge-base/engineering/operations/runbooks/
  # betterstack-log-query.md). `gh workflow run` also returns no output, so it could never have
  # produced the expected_output below. This command is the one that does.
  command: >
    doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 5m --grep inngest-heartbeat
  expected_output: >
    At least one row tagged inngest-heartbeat per 60s fire, carrying
    `project=<name> url_present=<yes|no> flip=<armed|unarmed>` and, on failure, the underlying
    doppler/curl stderr. Pre-fix this query returns ZERO rows — that zero IS the AC1 baseline.
```

**Structured-probe discrimination — CORRECTED (obs P1-1).** v2 claimed the row *"discriminates H4
(`resolved=no`) from H5 (`url_present=no`)"* and that a `project=… resolved=…` field is *"emitted
by the unit before exec."* **Both claims are false, and the plan refutes them itself:**

- The `logger` line lives in the **ping script**, which is `doppler run`'s **child**. H1's own
  measurement (§Hypotheses) proves *"the child never runs — Doppler exits before exec."* So on a
  Doppler-class failure the row count is **zero** — the exact branch it was meant to identify.
- `resolved=` appears **only** in `failure_modes`; FR4b and `discoverability_test.expected_output`
  prescribe `url_present=`/`flip=` with no `resolved=`. **Dropped** — the plan contradicted itself.
- `project=$DOPPLER_PROJECT` is **not** tautological *only because* FR3's project gate (AC5b row 1)
  now branches on it. Its value comes from Doppler's reserved-secret injection, so it can only ever
  print a project Doppler **already resolved** — it is a *branch-recording* field, **not** an H4
  discriminator. Retained on that honest basis alone.

**What actually discriminates, post-fix (no second row needed — quota, §Risks):**

| Observed | Meaning |
|---|---|
| dark-arm row (`url_present=no flip=unset`) every 60s | FR3 ran; host dark and healthy |
| `url_present=yes` row + curl stderr on the same tag | ping attempted and failed (real fault) |
| failure-arm row (`flip=armed\|flipping\|flushed\|done`, or `project=soleur`) | intended pusher with no URL — real fault |
| **no row at all** + unit `failed` | the child never ran ⇒ Doppler/env-class failure |

The last line is the H4 signature. It is diagnosable **only** because FR4's `SyslogIdentifier=`
retags the unit's own stderr (doppler's included) onto a shipping channel — which is why FR4, not
FR4b, is the load-bearing observability line. **H4 is refuted as the live cause and descoped
(§Descoped 1), so this plan does not owe an H4-positive probe** — it owes an honest account of what
its row can and cannot say. That is the correction.

## Architecture Decision (ADR/C4)

**No ADR required.** This plan makes no architectural decision: it repairs an
implementation against the decision ADR-100 / `inngest-host.tf:137-151` **already** records
(one unambiguous pusher per monitor; heartbeat URL provisioned out-of-band at cutover). The
dark-host no-op is the *documented intent* — the code simply never implemented it. Correcting the
comment restores the record to truth rather than changing it.

**C4 views — no impact, and here is what was checked.** Read all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`) rather than
grepping the feature noun. Enumerated for this change:

- **External human actors:** none added or changed (no operator-facing surface).
- **External systems / vendors:** Better Stack (heartbeat monitor **and** logs sink) — both
  already modelled; this plan adds no new vendor edge. The journald→Vector→Better Stack log edge
  already exists (Defect C widens an allowlist within it; it does not create it).
- **Containers / data stores:** the dedicated Inngest host and its units are already modelled; no
  new container or store.
- **Actor↔surface access relationships:** unchanged — no ownership, tenancy, or trust-boundary move.

No element description is falsified by this change. Therefore no `.c4` edit and no
`views.c4 include` line is in scope. **Deepen-plan MUST re-verify this enumeration against the
three `.c4` files directly** (the completeness mandate rejects an unsupported "None").

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/infra/inngest-bootstrap.sh` | **FR3** scoped dark-host branch in the ping script (160-164); **FR4** `SyslogIdentifier=inngest-heartbeat` + structured pre-exec log on the unit (178-194). *(Ships in the OCI image — replace class, see §Delivery split.)* |
| `apps/web-platform/infra/vector.toml` | **FR5** add `"inngest-heartbeat"` to `[sources.host_scripts_journald].include_matches.SYSLOG_IDENTIFIER` (125-156). *(Same OCI image as FR3/FR4 — replace class, NOT replace-free as v2 claimed.)* |
| `apps/web-platform/infra/cloud-init-inngest.yml` | **FR8** bump `IREF` (`:337`) to the new `soleur-inngest-bootstrap` tag — the actual `user_data` diff that delivers FR3/FR4/FR5. Deepen-plan to settle tag-vs-digest. |
| `apps/web-platform/infra/inngest-host.tf` | **FR6** correct the false "curl no-ops" comment (137-151) |
| `apps/web-platform/infra/cat-deploy-state.sh` | **FR7** add `service_journal_tail inngest-heartbeat.service` next to `HEARTBEAT_STATUS` (344) |
| `apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` | RED tests for FR1-FR4 |
| `apps/web-platform/infra/inngest-host.test.sh` | RED test for FR6 (guard the corrected claim) |
| `apps/web-platform/test/infra/vector-pii-scrub.test.sh` | FR5 allowlist fixture + **URL-never-logged** assertion |
| `apps/web-platform/infra/cat-deploy-state.test.sh` | FR7 assertion |

**Files to Create:** none.

## Implementation Phases

Phase order is load-bearing: the **probe ships before the fixes** so the next fire self-reports
which defect was live, and the fix is verified against evidence.

### Phase 1 — Observability first (the discriminating probe)

1. **FR4** — add `SyslogIdentifier=inngest-heartbeat` to the unit heredoc
   (`inngest-bootstrap.sh:178-194`). This retags **all** unit output (doppler's *and* curl's
   stderr), replacing the systemd-derived `doppler` basename tag.
1b. **FR4c (CPO P2-1)** — add `Environment=INTENDED_PUSHER_PROJECT=${DOPPLER_PROJECT}` to the
   unit's `[Service]` block, same heredoc. The unit heredoc is **unquoted** (`<<HEARTBEATEOF`,
   `:178`), so this expands at bootstrap from the *same* `${DOPPLER_PROJECT}` that renders the
   unit's `--project` flag (`:193`) — one source, no drift. It is the identity FR3's gate reads.
2. **FR4b** — emit one structured pre-exec line from the ping script:
   `logger -t inngest-heartbeat "project=$DOPPLER_PROJECT url_present=$(...) flip=$(...)"`.
   **Presence booleans only — never the URL value** (§User-Brand Impact).
3. **FR5** — add `"inngest-heartbeat"` to `vector.toml` Source 4's exact-match allowlist, with a
   comment citing #6536 in the style of the `webhook` / `inngest-cutover-flip` entries.
4. **FR7** — `cat-deploy-state.sh`: tail the heartbeat journal for no-SSH diagnosis.

### Phase 2 — *(removed — see §Descoped)*

v1's FR1/FR2 threaded `DOPPLER_PROJECT` through `ci-deploy.sh` + `deploy-inngest-bootstrap.sudoers`.
Both are on the **web-host** delivery path, which the failing dedicated host never traverses
(`cloud-init-inngest.yml:396` already supplies the right project at boot). Fixing a latent trap on
an unused path while replacing the sole prod scheduler is unjustified risk. **Descoped to a
follow-up issue.**

### Phase 3 — Fix the sole live defect (H5: the false no-op)

7. **FR3** — scoped dark-host branch in the ping script:

   ```sh
   #!/bin/sh
   # Posted to Better Stack every 60s by inngest-heartbeat.timer.
   #
   # LOG_TAG is a real assignment, NOT a literal in the logger calls: the drift fixture at
   # vector-pii-scrub.test.sh:404 derives the expected SYSLOG_IDENTIFIER set from
   # `^\s*(readonly\s+)?LOG_TAG="…"` in infra/*.sh. A bare `logger -t inngest-heartbeat`
   # pulls this file into the fixture's loop (grep is heredoc-blind) but yields NO tag,
   # so AC3's exact-set equality hard-fails. This line is what keeps FR5 and the fixture
   # in lockstep — and it is why the tag is typed ONCE, not once per call site.
   LOG_TAG="inngest-heartbeat"
   #
   # An ABSENT INNGEST_HEARTBEAT_URL is NOT a curl no-op — `curl -fsS --max-time 10 ""`
   # exits 2 (measured, #6536). Two hosts run this script (this file is ungated by
   # DOPPLER_PROJECT — see the `unit + heartbeat reconcile below always run` comment
   # above; the only project gate is the flip trio further down):
   #
   #   * dedicated (soleur-inngest): INNGEST_CUTOVER_FLIP is meaningful. A dark/reverted
   #     host legitimately has no URL (inngest-host.tf:137-151 — one unambiguous pusher
   #     per monitor; op=arm provisions the URL at cutover).
   #   * co-located web (soleur): has NO INNGEST_CUTOVER_FLIP *by design* (see the `web
   #     host's INNGEST_POSTGRES_URI is prod with no INNGEST_CUTOVER_FLIP` comment). It is
   #     TODAY'S live scheduler and sole monitor pusher, so an absent URL there is ALWAYS a
   #     real fault — never a dark steady state. Gate on the identity FIRST, or
   #     `${INNGEST_CUTOVER_FLIP:-unset}` pins the live host in the exit-0 arm.
   #
   # INTENDED_PUSHER_PROJECT (not $DOPPLER_PROJECT) is the host's AUTHORITATIVE identity:
   # the unit's [Service] bakes it from the same bootstrap-time ${DOPPLER_PROJECT} that
   # renders the unit's own `--project` flag, so the two cannot drift. $DOPPLER_PROJECT at
   # RUNTIME is a Doppler *secret* that `doppler run` injects — a separate, mutable source
   # (measured: it exists on BOTH soleur/prd and soleur-inngest/prd). The distinct name
   # also stops `doppler run` from shadowing it (it overrides same-named vars by default).
   # Unset/empty => != soleur-inngest => exit 1 => loud. Every default direction is safe.
   #
   # Arms mirror cutover-inngest.yml:703/706. FSM: armed -> flipping -> flushed -> done
   # (:764); op=arm writes the URL (G4, :760) BEFORE flip=armed (:665), so an intended
   # pusher with no URL is a REAL fault, never the dark steady state.
   if [ -z "$INNGEST_HEARTBEAT_URL" ]; then
     if [ "$INTENDED_PUSHER_PROJECT" != "soleur-inngest" ]; then
       logger -t "$LOG_TAG" "url_present=no project=${INTENDED_PUSHER_PROJECT:-unset} — live/unknown pusher has NO heartbeat URL; failing"
       exit 1
     fi
     case "${INNGEST_CUTOVER_FLIP:-unset}" in
       ""|unset|aborted|rollback|rolled-back)
         logger -t "$LOG_TAG" "url_present=no flip=${INNGEST_CUTOVER_FLIP:-unset} — not the intended pusher (dark/reverted); skipping ping"
         exit 0 ;;
       armed|flipping|flushed|done)
         logger -t "$LOG_TAG" "url_present=no flip=$INNGEST_CUTOVER_FLIP — intended pusher has NO heartbeat URL; failing"
         exit 1 ;;
       *)
         logger -t "$LOG_TAG" "url_present=no flip=$INNGEST_CUTOVER_FLIP — UNKNOWN flip state; failing closed"
         exit 1 ;;
     esac
   fi
   logger -t "$LOG_TAG" "url_present=yes flip=${INNGEST_CUTOVER_FLIP:-unset} — pinging"
   exec /usr/bin/curl -fsS --max-time 10 "$INNGEST_HEARTBEAT_URL" >/dev/null
   ```

   The **identity gate** is what keeps this from being a silent fallback on the live host, and the
   `flip` discriminator is what keeps it scoped on the dedicated one: together they convert a
   blanket exit-0 into a *scoped, self-declaring* no-op that still fails loudly whenever this host
   is the intended pusher. **Never `[ "$INNGEST_CUTOVER_FLIP" = "armed" ]`** — that lumps
   `flipping`/`flushed`/`done` into the dark branch (AC5b). The `*)` arm fails closed so a typo'd
   or future state can never silently no-op. `logger` asserts **presence only, never the URL
   value** (§User-Brand Impact / AC3).

### Phase 4 — Correct the record + guards

8. **FR6** — rewrite `inngest-host.tf:148`'s false claim to state the measured truth: an absent
   URL makes curl exit 2, so the no-op is implemented **explicitly in the ping script**, not
   assumed from curl's behaviour. Cite #6536 and the measured rc.
9. Tests per `## Files to Edit`; full suite exit gate.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** — `grep -c 'SyslogIdentifier=inngest-heartbeat' apps/web-platform/infra/inngest-bootstrap.sh` ≥ 1.
- **AC2** — `grep -c '"inngest-heartbeat",' apps/web-platform/infra/vector.toml` = 1, inside the
  `[sources.host_scripts_journald]` block. Verify block scoping with the flag-based awk form
  (`awk '/^\[sources.host_scripts_journald\]/{f=1} /^\[sources\./&&!/host_scripts_journald/{f=0} f'`),
  **not** an `/a/,/b/` range (self-match trap).
- **AC3 (leak gate — load-bearing) — REDESIGNED (CPO P1-2).** v2's source-grep
  (`grep -nE 'logger.*\$INNGEST_HEARTBEAT_URL|echo.*\$INNGEST_HEARTBEAT_URL'`) was **measured to
  catch 1 of 3 leak shapes**:

  | Leak shape | v2 AC3 |
  |---|---|
  | `logger … "url=$INNGEST_HEARTBEAT_URL"` | caught |
  | `logger … "url=${INNGEST_HEARTBEAT_URL}"` | **MISSED** — `\$INNGEST` needs `$` then `I`; the brace interposes |
  | `printf 'url=%s\n' "$INNGEST_HEARTBEAT_URL"` | **MISSED** |

  Brace form is this plan's own house style (`${INNGEST_CUTOVER_FLIP:-unset}`), i.e. the **most
  likely** way an implementer writes the leak is the shape v2 could not see. It also misses
  `set -x`, `curl -v`, and `--write-out '%{url}'`.

  **Replacement — a shape-independent value-absence assertion.** Run the ping script with
  `INNGEST_HEARTBEAT_URL=https://uptime.betterstack.com/api/v1/heartbeat/CANARY_SENTINEL`, capture
  the script's full stdout+stderr **and** its `logger` output (via the fixture's logger seam), and
  assert `CANARY_SENTINEL` appears **zero** times. This cannot be defeated by brace/`printf`/`-v`
  form. Keep a source-grep only as a cheap secondary.

  **The claimed second control does not exist — do not cite it.** v2's Risks table offered
  *"PII-scrub drift guard extended"* as defense-in-depth. `vector.toml:293-334`'s
  `pii_scrub_string` redacts `userid=`/`user_id=`, OAuth **query params**, emails,
  `Authorization: Bearer/Basic`, and control chars. The heartbeat URL carries its token as a
  **path segment** with no `Authorization:` prefix — it matches **none** of them. The scrub chain
  is a **no-op on this URL**. Source 4 is correctly wired into the chain (`vector.toml:200`), but
  the chain has nothing to say about this secret. **AC3 is therefore the sole control** — which is
  exactly why it must be value-based.

  **Measured mitigation (curl's own stderr is clean).** All four failure classes were tested:
  `rc=2` (blank arg), `rc=6` (`Could not resolve host: <host>` — host only), `rc=3` (URL rejected),
  `rc=22` (`The requested URL returned error: 404`). **None echo the URL or token.** So FR4's
  retag does not leak today; the exposure is the gate's durability, not a live leak.
- **AC4** — `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` passes, including
  a new case proving the ping script exits **0** when the URL is absent and flip is unarmed, and
  **non-zero** when the URL is absent and flip is `armed`.
- **AC5** — *(removed — asserted the descoped FR1. See §Descoped.)*
- **AC5b (enum completeness) — SETTLED by deepen-plan.** The FR3 branch classifies **every**
  `INNGEST_CUTOVER_FLIP` state. **v2's enum was incomplete and would have shipped the hole it
  warned about**: it listed `{unset, armed, flipping, done, rollback}` and **missed `flushed`,
  `aborted`, and `rolled-back`**.

  **Authoritative state set** (measured, not inferred):
  - `cutover-inngest.yml:764` — the on-host FSM is **`armed → flipping → flushed → done`**
    (ADR-100 Decision 6a). `inngest-bootstrap.sh:416`'s `{armed, flipping, done}` comment is
    **stale** — it omits `flushed`.
  - `cutover-inngest.yml:703` — G1's safe-pre-arm arm: `""|unset|aborted|rolled-back`.
  - `cutover-inngest.yml:706` — G1's refuse arm: `armed/flipping/flushed/done`.
  - `cutover-inngest.yml:668` — `op=rollback` writes the transitional literal `rollback`; the
    on-host FSM then settles at terminal `rolled-back` (`:133`).

  **Ordering fact that decides the `armed` arm** (`cutover-inngest.yml:760` then `:665`): `op=arm`
  writes `INNGEST_HEARTBEAT_URL` **first (G4)** and `INNGEST_CUTOVER_FLIP=armed` **LAST**. So
  *armed + absent URL is unreachable in a healthy arm* — if observed, it is a genuine fault
  (partial arm, or the URL was deleted underneath). This is what makes exit-1 correct there.

  **Settled classification — the rule is "is this host the intended pusher?", not "is it armed?":**

  | `INTENDED_PUSHER_PROJECT` | `INNGEST_CUTOVER_FLIP` | Intended pusher? | Exit when URL absent |
  |---|---|---|---|
  | `soleur` (co-located, **live**) | *(never set — by design)* | **Yes — today's sole pusher** | **1** (**CPO P1-1**) |
  | unset / empty | *(any)* | Unknown ⇒ **fail closed** | **1** (**CPO P2-1**) |
  | `soleur-inngest` | `""` / unset (**today**) | No — pre-arm dark | **0** (skip, log reason) |
  | `soleur-inngest` | `aborted` | No — arm aborted | **0** |
  | `soleur-inngest` | `rollback` (transitional) | No — reverting | **0** |
  | `soleur-inngest` | `rolled-back` (terminal) | No — reverted | **0** |
  | `soleur-inngest` | `armed` | **Yes** — URL written before this literal | **1** |
  | `soleur-inngest` | `flipping` | **Yes** — mid-FSM | **1** |
  | `soleur-inngest` | `flushed` | **Yes** — mid-FSM (**v2 missed this**) | **1** |
  | `soleur-inngest` | `done` | **Yes** — sole scheduler | **1** |
  | `soleur-inngest` | anything else (typo/unknown) | Unknown ⇒ **fail closed** | **1** |

  **Why `INTENDED_PUSHER_PROJECT` and not `$DOPPLER_PROJECT` (CPO P2-1).** The gate must read the
  host's *authoritative* identity. `$DOPPLER_PROJECT` at runtime is **not** that: the script
  heredoc is **quoted** (`<<'HEARTBEATSCRIPTEOF'`, `:160`), so the var resolves in the child env,
  where its only source is a Doppler **secret** coincidentally named `DOPPLER_PROJECT` —
  `EnvironmentFile=/etc/default/inngest-server` carries only `DOPPLER_TOKEN`/`DOPPLER_CONFIG_DIR`/
  `DOPPLER_ENABLE_VERSION_CHECK` (`:240-242`). Meanwhile the identity the unit actually
  authenticates against is the **bootstrap-baked** `--project` flag. Two independent sources, free
  to drift — a gate checking something adjacent to what it claims. FR4c collapses them to one.

  **Measured (closing CPO P2-1's unknown row):** `soleur/prd → DOPPLER_PROJECT=soleur` and
  `soleur-inngest/prd → DOPPLER_PROJECT=soleur-inngest`. Both correct **today**, so the gate would
  work as-written; FR4c removes the drift *class* rather than relying on that holding.

  **The project gate is load-bearing and must be evaluated FIRST (CPO P1-1).** This script is
  **ungated** by `DOPPLER_PROJECT`: `inngest-bootstrap.sh:144` states *"unit + heartbeat reconcile
  below always run"*, and the timer is enabled unconditionally at `:507` — the only project gate
  (`:291`) scopes the flip trio, not the heartbeat. Both hosts run it. The co-located web host has
  **no** `INNGEST_CUTOVER_FLIP` *by design* (`:287`), so a flip-only classification resolves it to
  `unset` and pins **today's live prod pusher** permanently in the exit-0 arm. It stays hidden only
  because that host's URL is present today; a rotation, a botched `op=arm` that moves rather than
  copies the URL, or a stale Doppler fallback snapshot would make the live host silently skip its
  ping while logging *"not the intended pusher"* — a sentence that is false for that host. That is
  AC5b's own hazard displaced one host over, and it would have shipped.

  **Prescribed shape — a `case`, mirroring the workflow's own arms at `:703`/`:706` (precedent
  diff), NOT a `= "armed"` equality:**

  ```sh
  case "${INNGEST_CUTOVER_FLIP:-unset}" in
    ""|unset|aborted|rollback|rolled-back)
      logger -t inngest-heartbeat "url_present=no flip=${INNGEST_CUTOVER_FLIP:-unset} — not the intended pusher (dark/reverted); skipping ping"
      exit 0 ;;
    armed|flipping|flushed|done)
      logger -t inngest-heartbeat "url_present=no flip=$INNGEST_CUTOVER_FLIP — intended pusher has NO heartbeat URL; failing"
      exit 1 ;;
    *)
      logger -t inngest-heartbeat "url_present=no flip=$INNGEST_CUTOVER_FLIP — UNKNOWN flip state; failing closed"
      exit 1 ;;
  esac
  ```

  The test asserts the exit code for **all nine** cases above (the eight literals + one unknown
  value). A single `= "armed"` comparison lumps `flipping`/`flushed`/`done` into the dark branch —
  during those states the dedicated host IS the intended pusher, so exit-0 there is precisely the
  **silent liveness hole** this AC exists to prevent.

  **Follow-up surfaced (out of scope, needs its own issue):** `op=rollback` writes `flip=rollback`
  but does **not** delete `INNGEST_HEARTBEAT_URL` from `soleur-inngest/prd`. After a rollback the
  URL is still present, so the ping proceeds and the dark host pushes the **same** monitor the
  re-enabled co-located host pushes — two pushers, the exact false-green the one-pusher-per-monitor
  design (`inngest-host.tf:137-151`) forbids. Pre-existing (today's URL-present path already execs
  curl unconditionally); FR3 neither causes nor worsens it. See §Descoped item 4.
- **AC6** — `inngest-host.tf` no longer asserts the no-op claim:
  `grep -ci 'curl no-ops' apps/web-platform/infra/inngest-host.tf` = 0. (Absence-grep is safe
  here: the corrected prose states the measured rc=2 behaviour and does not restate the phrase.)
- **AC7** — `bash apps/web-platform/infra/inngest-host.test.sh`,
  `bash apps/web-platform/infra/cat-deploy-state.test.sh`, and
  `bash apps/web-platform/test/infra/vector-pii-scrub.test.sh` all pass.
- **AC8** — `actionlint` clean for any touched workflow; `bash -n` on every touched shell script.
- **AC9** — Vector config validates: the existing `.github/workflows/validate-vector-config.yml`
  gate passes on the edited `vector.toml`.

### Post-merge (Terraform-driven host replace — NOT a quiet redeploy)

- **AC10** — **CORRECTED.** v1 asserted "the merge triggers the existing deploy path… no manual
  step". That is **false** for the dedicated host: it has no webhook and no sudoers, and
  `inngest-host.tf:244` omits `ignore_changes=[user_data]`, so a bootstrap edit forces a
  **server replace** of the **sole** scheduler (ADR-100). The AC is therefore: `terraform plan`
  on `apps/web-platform/infra` shows the `hcloud_server` inngest host **replacing**, and the
  replace is executed deliberately (IaC, no SSH) with the co-located host still pushing the
  monitor. Deepen-plan MUST size this and confirm the #6178 cutover interaction.
- **AC11** — Better Stack query `SYSLOG_IDENTIFIER=inngest-heartbeat` over 5m returns **≥1 row per
  fire** (pre-fix baseline: **0 rows** — the AC1 datum). The rows carry
  `project=… url_present=… flip=…`.
- **AC12 — RESTATED (obs P2-5).** v2 asserted the `Failed to start inngest-heartbeat.service`
  stream stops (zero new occurrences in 30m, baseline ~1,240/day). That row **does** ship today
  (measured — see §Risks), but by a mechanism the repo's `vector.toml` does not explain, so an AC
  built on it rests on an unexplained shipper. **Restated against the channel FR5 makes ship
  deterministically:** in the 30m after deploy, every `SYSLOG_IDENTIFIER=inngest-heartbeat` row
  from `host_name=soleur-inngest-prd` carries the **dark arm**
  (`url_present=no flip=unset — not the intended pusher`), and **zero** rows carry a failure arm.
  Query via `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 30m
  --grep inngest-heartbeat`. Secondary (advisory, not gating): the `Failed to start` stream stops.

  **Why the restatement matters beyond pedantry:** the deploy changes the shipper config *and* the
  fix in the same replace. An AC phrased against the `Failed to start` line therefore cannot
  distinguish *"FR3 works"* from *"the new config stopped shipping the evidence"* — it would pass
  vacuously in both worlds. The dark-arm assertion is positive evidence that the fixed code ran.
- **AC13** — `betteruptime_heartbeat.inngest_prd` remains **`up`** throughout (the co-located host
  keeps pushing; this change must not disturb the monitor).
- **AC14 (volume re-attach — replace safety)** — after the replace, `hcloud_volume.inngest_redis`
  is re-attached to the new host and the Redis AOF is intact (git-data precedent, cited at
  `inngest-host.tf:248-249`). Verified via `cutover-inngest.yml --field op=inventory` (no SSH).
  Dark-host caveat: the AOF is expected **empty** pre-cutover — assert *attachment*, not contents.
- **AC15 (dark-host ordering gate — load-bearing) — CORRECTED (CPO P1-3).** v2 gated on
  `INNGEST_CUTOVER_FLIP` alone — **the variable `op=arm` writes LAST**. §Downtime & Cutover rests
  on **two** premises: (1) the host is not scheduling (flip absent), and (2) it is not pushing the
  monitor (URL absent). v2 pinned only premise 1, and premise 2 is the one that breaks first:
  `cutover-inngest.yml:759` (G4) writes `INNGEST_HEARTBEAT_URL` — *"the URIs must land before
  `armed`"* — and `:669` (G5) writes `armed` last. This plan **cites that ordering to justify FR3's
  `armed` exit-1 arm**, then v2 failed to apply the same fact one section over.

  A failed arm is **durable, not a race**: G5's own error text is *"writing INNGEST_CUTOVER_FLIP=armed
  FAILED (both URIs already landed). Re-dispatch op=arm"* — leaving URL-present / flip-absent
  indefinitely. In that state v2's AC15 **passes** while premise 2 is **false** (the dark host is
  actively pushing the monitor). A gate that passes in the exact state it exists to catch is not a
  gate.

  **Corrected AC:** assert **both** keys absent from `soleur-inngest/prd` at apply time
  (`doppler secrets --only-names -p soleur-inngest -c prd`), with `INNGEST_HEARTBEAT_URL` as the
  **primary trip-wire** (written first ⇒ the leading indicator of an in-flight or failed arm):

  | Observed | Verdict |
  |---|---|
  | both absent | **proceed** — dark, both premises hold |
  | URL present, flip absent | **HALT** — failed/partial arm; premise 2 false |
  | flip present (any value) | **HALT** — arm in flight or complete |

  (The replace stays zero-downtime even in the middle row — the flip guard keeps the host inert and
  the co-located host keeps pushing — so this is gate integrity, not an outage. Halt anyway: the
  conclusion must rest on a checked premise, not a lucky one.)

## Descoped (each needs a tracking issue before /work)

1. **H4 — the `${DOPPLER_PROJECT:-soleur}` latent trap.** Real (`inngest-bootstrap.sh:47`;
   `ci-deploy.sh` 0 occurrences; sudoers `env_keep` omits it) but fires **nowhere today**: the
   dedicated host gets the project from `cloud-init-inngest.yml:396` and has no ci-deploy path;
   the web host's `soleur` default is correct. **Blast radius if it ever fires is large** — the
   same default feeds `inngest-server.service`'s ExecStart (`:418`) and gates cutover-flip
   rendering (`:283-304`) + `DEDICATED_FLIP` (`:475`). File as its own issue.
   *Preferred fix (CTO):* write `DOPPLER_PROJECT` into `/etc/default/inngest-server` at cloud-init
   — the unit **already** reads that file via `EnvironmentFile=` (`inngest-bootstrap.sh:186`), and
   `doppler run` reads `DOPPLER_PROJECT` from env, so the unit could drop `--project` entirely.
   That deletes the ci-deploy + sudoers threading outright.
2. **Systemic observability guard (CTO).** The recurring class is *units with no
   `SyslogIdentifier=` silently tag as their ExecStart basename* (here, `doppler`). A CI guard
   asserting every `logger -t` tag / unit `SyslogIdentifier=` under `infra/` appears in Source 4's
   allowlist (or is explicitly excluded) kills the class. Follow-up issue, not this PR.
4. **`op=rollback` leaves `INNGEST_HEARTBEAT_URL` in place → two pushers on one monitor.**
   `cutover-inngest.yml:668` writes `INNGEST_CUTOVER_FLIP=rollback` but never deletes the URL
   `op=arm` wrote at G4 (`:760`). After a rollback the dedicated host still has the URL, so its
   ping proceeds while the **re-enabled co-located** host pushes the same monitor — two pushers,
   violating the one-unambiguous-pusher-per-monitor invariant (`inngest-host.tf:137-151`) and
   re-creating the false-green that invariant exists to prevent. **Pre-existing** (today's
   URL-present path execs curl unconditionally); FR3 neither causes nor worsens it, and fixing it
   means editing cutover semantics mid-cutover. *Candidate fix:* have `op=rollback` delete the URL
   from `soleur-inngest/prd` (inverse of G4), which FR3's `rollback`/`rolled-back` arms then
   classify correctly with zero further change. File as its own issue.
5. **`inngest-bootstrap.sh:416`'s FSM comment is stale.** It names `{armed, flipping, done}`; the
   real FSM is `armed → flipping → flushed → done` (`cutover-inngest.yml:764`) — `flushed` is
   missing. This plan does not edit the flip guard, but the stale comment is what led v2's AC5b to
   an incomplete enum. Correct it in the same follow-up as item 4.
7. **The live shipper does not match the repo's `vector.toml` — unexplained (measured 2026-07-16).**
   A live Better Stack row from `host_name=soleur-inngest-prd` carries `PRIORITY=3`,
   `SYSLOG_IDENTIFIER=systemd`, `_SYSTEMD_UNIT=init.scope`, `shipper=vector` — yet **no source in
   the repo's `vector.toml` admits it** (Source 1 unit-scoped to `inngest-server.service`; Source 2
   cuts `PRIORITY 0-2`; Source 3 `CONTAINER_NAME`; Source 4 has no `systemd` tag). Not a stale-pin
   artifact: Source 2 was already `PRIORITY 0-2` at the IREF-pin commit `957350d82`. **Either the
   running host's config differs from the repo's, or a source ships more than its declaration
   says.** Both are serious for a repo whose observability doctrine is *"'rides the shipper' is a
   claim to verify against the allowlist, never a fact"* — here the allowlist says NO and the
   shipper says YES. Every quota estimate and every `vector.toml`-derived reachability claim in
   this repo inherits the uncertainty. Out of scope (this plan neither causes nor worsens it) but
   **file first** — it partially invalidates §Defect C's method, even though §Defect C's
   *conclusion* (the unit's own PRIORITY-6 output does not ship) is independently confirmed by the
   issue's zero-row `_SYSTEMD_UNIT='inngest-heartbeat.service'` query.
8. **The heartbeat proves the HOST is alive, not the SCHEDULER (CPO P3-1).**
   `inngest-heartbeat.service` curls Better Stack independently of `inngest-server.service`. If the
   scheduler OOMs against its `MemoryMax` guardrail, the heartbeat keeps the monitor **green**. So
   post-cutover a green `inngest_prd` monitor is **not** evidence that any cron ran — the same
   false-green class as item 4. Pre-existing; FR3 neither causes nor worsens it. Note: this makes
   §User-Brand Impact's framing (the heartbeat as what stands between the founder and silently-dead
   crons) somewhat **overstated** — worth its own issue.
9. **Sudoers dual-maintenance (CTO).** `cloud-init.yml:77-79` carries an inline **mirror** of
   `deploy-inngest-bootstrap.sudoers` ("keep the two in sync", `cloud-init.yml:106,125`). Any
   future FR1 work must edit both, and sudoers delivery needs `apply-deploy-pipeline-fix.yml`, not
   the deploy webhook (`server.tf:720-731`).

## Review Status — **reviewed (partial)**

**7 reviewers spawned; 6 died on API/infrastructure errors** (stream idle timeout / stalled
mid-stream), not on findings. Only **cto** completed. This is an honest record, not a pass:

| Reviewer | Status |
|---|---|
| cto | ✅ completed — findings folded in (delivery premise, host identity, allowlist debt, DX traps) |
| dhh, kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, cpo | ❌ API error — **no findings** |

The `cto` findings **materially corrected v1** (H4 demoted, FR1 descoped, AC10 falsified). Two
further risks were flagged in the dying agents' partial notes and **verified by hand** here:
AC10's delivery path (refuted → corrected) and FR3's enum literal (→ AC5b).

**Consequence:** the 5-agent panel that `brand_survival_threshold: single-user incident` mandates
did **not** run, and **CPO sign-off was not obtained** (`requires_cpo_signoff: true` is unmet).
**Re-run `plan-review` — in small batches, not 7-way parallel — before `/work`.** Do not treat this
plan as review-passed.

### Deepen-plan pass (v3) — what it changed

Run in small batches after the 7-way spawn failed. Gate results and findings:

| Gate | Result |
|---|---|
| 4.6 User-Brand Impact | **pass** — present, concrete, threshold `single-user incident` |
| 4.7 Observability (5 fields) | **pass** — all present, no `ssh` in `discoverability_test.command` |
| 4.8 PAT-shaped variable | **pass** — no matches |
| 4.9 UI wireframe | **pass** (not triggered) — the lone regex hit is the plan's own *negative* statement in §Product/UX Gate, not a UI path in Files-to-Edit |
| 4.5 Network-outage | **not triggered** — `inngest-host.tf` has no `provisioner "file"`/`"remote-exec"`/`connection { type = "ssh" }`; the prose `timeout` hits are `curl --max-time` and agent-API prose, not a connectivity symptom |
| **4.55 Downtime & Cutover** | **FIRED** — plan force-replaces an `hcloud_server` with no `## Downtime & Cutover` section. Section added; telemetry emitted. Conclusion: **zero-downtime already holds** (the replaced host is dark/inert), and the ordering constraint is now AC15. |

**Three v2 defects corrected — each would have surfaced inside `/work`:**

1. **Delivery split was false.** FR5 (`vector.toml`) rides the **same OCI image** as FR3/FR4
   (`cloud-init-inngest.yml:337` `IREF` pin; `:368`/`:370` docker-cp), so it is replace-class, not
   replace-free. The replace trigger is the `IREF` bump, not the bootstrap edit. New FR8.
2. **AC5b's enum was incomplete** — it missed **`flushed`**, **`aborted`**, **`rolled-back`**
   (`cutover-inngest.yml:764`, `:703`, `:706`). v2 would have shipped the very silent-liveness hole
   AC5b was written to prevent. Now settled as a 9-case `case` with a fail-closed `*)` arm.
3. **AC10's "replace the SOLE scheduler" risk framing was wrong for today.** Measured:
   `INNGEST_CUTOVER_FLIP` and `INNGEST_HEARTBEAT_URL` are both **absent** from `soleur-inngest/prd`
   ⇒ the host is dark and the co-located host serves prod. `inngest-host.tf:244`'s "SOLE scheduler"
   is ADR-100's post-cutover end-state. The replace is free **now** and expensive **after** the arm
   — hence AC15's ordering gate.

**Two follow-ups surfaced** (§Descoped 4 + 5): `op=rollback` never deletes the heartbeat URL (two
pushers on one monitor after a rollback), and `inngest-bootstrap.sh:416`'s FSM comment is stale
(omits `flushed`) — the stale comment is what led v2's enum astray.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Exit-0 masks a real post-cutover fault** (the #6536 harm, inverted). | **Two gates, identity FIRST (v4).** (1) `INTENDED_PUSHER_PROJECT != soleur-inngest` → exit 1 unconditionally, so the live co-located host — which has no flip *by design* — can never reach the exit-0 arm (CPO P1-1); unset/empty also exits 1 (CPO P2-1). (2) Only then the flip `case`: exit 0 solely for `""\|unset\|aborted\|rollback\|rolled-back`, exit 1 for `armed\|flipping\|flushed\|done`, `*)` fails closed. AC4 + AC5b assert all ten arms. |
| **The new log line leaks the bearer URL** to a third-party vendor, defeating the `sensitive=true` + script-indirection control (`inngest-bootstrap.sh:156-159`). | **AC3's CANARY_SENTINEL value-absence assertion is the SOLE control** (CPO P1-2) — presence booleans only, never the value. **Do NOT cite the PII scrub as defense-in-depth:** `vector.toml:293-334` redacts `userid=`/`user_id=`, OAuth **query params**, emails, and `Authorization:` headers; this URL carries its token as a **path segment**, so the scrub chain is a **no-op on it**. Measured: curl's own stderr is clean across rc=2/3/6/22 (no URL echoed). Second exposure — see §Sharp Edges: unquoting the script heredoc bakes the URL into a 0755 file, which AC3 structurally cannot catch. |
| `INNGEST_CUTOVER_FLIP` is **not currently present** on `soleur-inngest/prd` (measured — names are `BETTERSTACK_LOGS_TOKEN, DOPPLER_CONFIG, DOPPLER_ENVIRONMENT, DOPPLER_PROJECT, INNGEST_EVENT_KEY, INNGEST_POSTGRES_URI, INNGEST_REDIS_PASSWORD, INNGEST_SIGNING_KEY`). An unset var resolves via `${INNGEST_CUTOVER_FLIP:-unset}` to `unset` → dark arm. | That is the **correct** default on the dedicated host (unarmed ⇒ dark ⇒ no-op), and it is now reachable **only after** the identity gate has already excluded the live host. Documented in FR3's comment so the direction is intentional and reviewable, not incidental. **The `[ "$INNGEST_CUTOVER_FLIP" = "armed" ]` form this row used to reason through is FORBIDDEN** (§AC5b) — it lumps `flipping`/`flushed`/`done` into the dark branch. |
| Adding a Vector source row raises Better Stack quota. | **Both v2's "net large decrease" and the review's "net increase / phantom saving" are wrong. Measured, not inferred (`betterstack-query.sh`, 2026-07-16):** the storm **does** ship today — a live row carries `PRIORITY=3`, `SYSLOG_IDENTIFIER=systemd`, `_SYSTEMD_UNIT=init.scope`, `_PID=1`, `UNIT=inngest-heartbeat.service`, `host_name=soleur-inngest-prd`, `shipper=vector`. So FR3's saving is **real**, not phantom. But the honest delta is roughly **neutral**, not a large decrease: the storm stops (−) and the new 60s positive row adds ~1,440/day (+). **Accept the ~+1,440/day explicitly** — it buys the first continuous dark-host liveness evidence this host has ever had (§Downtime & Cutover), against a `vector.toml:166-171` posture engineered to sit ~20% under the 25k/day threshold after #5110's AC12 **FAIL** at 2.3x. `/work` MUST quantify the real steady-state count before merge and re-check headroom. |
| **UNRESOLVED — the live shipper does not match the repo's `vector.toml` (see §Sharp Edges).** | The measured row ships at `PRIORITY=3` with `SYSLOG_IDENTIFIER=systemd`, which **no source in the repo's `vector.toml` admits**: Source 1 is unit-scoped to `inngest-server.service`; Source 2 cuts `PRIORITY 0-2`; Source 3 is `CONTAINER_NAME`; Source 4 has no `systemd` tag. The same config held at the IREF-pin commit (`957350d82`), so this is **not** explained by a stale pin. **Do not build an AC on this mechanism** — AC12 is therefore restated against the `inngest-heartbeat` channel (which FR5 makes ship deterministically), and the discrepancy gets its own issue (§Descoped 7). |
| Fixing FR2 to fail closed could brick a redeploy if `DOPPLER_PROJECT` is genuinely unresolvable. | Fail closed **only** on the dedicated host (where a wrong project is already fatal); the co-located web host keeps the `soleur` default. A loud failure beats today's silent wrong-project rewrite. |
| H4's real trigger is unconfirmed, so a fix could be aimed at a dormant defect. | Phase 1 ships the probe **first**; AC11 proves which defect was live. Both defects are independently measured, so neither fix is speculative. |

## Sharp Edges

- **H4's blast radius exceeds the heartbeat.** The same `${DOPPLER_PROJECT:-soleur}` default feeds
  `inngest-server.service`'s ExecStart (`inngest-bootstrap.sh:418`) **and** gates the cutover-flip
  unit rendering (`inngest-bootstrap.sh:283-304`, `if [[ "$DOPPLER_PROJECT" == "soleur-inngest" ]]`)
  and `DEDICATED_FLIP` (`:475`). A redeploy that defaults to `soleur` therefore does not only break
  the heartbeat — it can point the **scheduler** at the wrong project and **silently skip the flip
  guard** on the dedicated host. FR1/FR2 fix the root, but the flip-guard interaction deserves its
  own verification and may warrant a separate tracking issue. Deepen-plan MUST size this.
- **NEVER unquote the ping-script heredoc to "bake in" the host identity — it writes the bearer URL
  to a world-readable file, and AC3 cannot see it (CPO P2-1).** `:160` is `<<'HEARTBEATSCRIPTEOF'`
  — **quoted, deliberately**. Unquoting it to expand `${DOPPLER_PROJECT}` at bootstrap would also
  expand `$INNGEST_HEARTBEAT_URL` into `/usr/local/bin/inngest-heartbeat.sh`, a **0755
  world-readable** file — writing the bearer capability to disk in plaintext and defeating the
  entire script-indirection control at `:156-159` (which exists precisely so systemd never journals
  a resolved `ExecStart=`). **AC3's canary asserts the script's runtime OUTPUT, not the script
  FILE's contents, so AC3 would pass while the secret sits on disk.** This is the natural way an
  implementer reaches for FR4c — do it via `Environment=` in the *unit* heredoc (`:178`, already
  unquoted) instead. The quoted script heredoc must stay quoted.
- **Adding the unit to `vector.toml` Source 1 does not work.** Source 1's `PRIORITY 0-4` filter
  still drops the unit's PRIORITY-6 output. Source 4 (no PRIORITY filter) is the only allowlist
  that ships level-6 lines. This is the trap the naive fix falls into.
- **`include_matches` is exact-value equality, not prefix/regex** (`vector.toml:108-110`). A tag
  typo silently matches nothing and the AC would pass vacuously — assert the tag against the
  **unit's** `SyslogIdentifier=` value, not a literal typed twice.
- **The "monitor is up" discriminator in the issue is not evidence about this unit.** Monitor
  greenness and this unit's rc are decoupled by design (one pusher per monitor). Any future
  reasoning about this unit must read the unit's own channel, never the monitor.
- **The `#4116` fix collapsed the env-injection gap but not the empty-URL-rc gap.** Wrapping in
  `doppler run` fixed *where the URL comes from*; it never made an absent URL safe. The gap stayed
  latent until a project without the URL (`soleur-inngest`) existed. Fixing the source of a value
  is not the same as handling its absence.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.** Fill it before requesting
  deepen-plan or `/work`.
