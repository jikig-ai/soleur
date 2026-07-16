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
| `[sources.docker_journald]` (`vector.toml:65-69`) | `CONTAINER_NAME` | Not a container. |
| `[sources.host_scripts_journald]` (`vector.toml:125-156`) | 12 exact `SYSLOG_IDENTIFIER` tags, **no PRIORITY filter** | No heartbeat tag. |

Compounding this: the unit sets **no `SyslogIdentifier=`** (`grep` → zero matches file-wide), so
systemd derives `SYSLOG_IDENTIFIER` from the ExecStart basename → **`doppler`**, not
`inngest-heartbeat`. A naive tag guess would match nothing.

`vector.toml:108-110` already warns: *"include_matches is `sd_journal_add_match` exact-value
equality, NOT prefix/regex — a tag typo silently matches nothing."* And
`2026-07-08-inngest-cutover-authoring-review-and-observability-allowlist.md:15`: *"'Rides the
shipper' is a claim to verify against the allowlist, never a fact."* The heartbeat is the
thirteenth un-enumerated case.

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
             or project unresolvable). The ONLY exit-0 branch is the scoped dark-host case,
             and it emits an explicit INFO naming the reason (never silent).

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
  command: >
    gh workflow run cutover-inngest.yml --field op=inventory   # no-SSH host state read
    # then query Better Stack for SYSLOG_IDENTIFIER=inngest-heartbeat over the last 5m
  expected_output: >
    At least one row tagged inngest-heartbeat per 60s fire, carrying
    `project=<name> url_present=<yes|no> flip=<armed|unarmed>` and, on failure, the underlying
    doppler/curl stderr. Pre-fix this query returns ZERO rows — that zero IS the AC1 baseline.
```

**Structured-probe discrimination (per §2.9.2 — this is a blind execution surface).** The single
event emitted before exec carries `project=`, `url_present=`, `flip=` **together**, so one row
discriminates H4 (`resolved=no`) from H5 (`url_present=no`) from a genuine ping failure
(`url_present=yes` + curl stderr) — rather than a single boolean that only fires for one shape.

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
   # Dark (pre-cutover) hosts have no INNGEST_HEARTBEAT_URL by design
   # (inngest-host.tf:137-151) — skip the ping and exit 0 so the unit's `failed`
   # state keeps meaning. ARMED + absent URL is a REAL fault and must still fail.
   if [ -z "$INNGEST_HEARTBEAT_URL" ]; then
     if [ "$INNGEST_CUTOVER_FLIP" = "armed" ]; then
       logger -t inngest-heartbeat "url_present=no flip=armed — ARMED but no heartbeat URL; failing"
       exit 1
     fi
     logger -t inngest-heartbeat "url_present=no flip=unarmed — dark host, skipping ping"
     exit 0
   fi
   exec /usr/bin/curl -fsS --max-time 10 "$INNGEST_HEARTBEAT_URL" >/dev/null
   ```

   The `flip` discriminator is what keeps this from being a silent fallback: it converts a
   blanket exit-0 into a *scoped, self-declaring* no-op that still fails loudly post-cutover.

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
- **AC3 (leak gate — load-bearing)** — the ping script and unit never echo the URL value:
  `grep -nE 'logger.*\$INNGEST_HEARTBEAT_URL|echo.*\$INNGEST_HEARTBEAT_URL' apps/web-platform/infra/inngest-bootstrap.sh`
  returns **zero**. Asserted as a test, not a one-off grep.
- **AC4** — `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` passes, including
  a new case proving the ping script exits **0** when the URL is absent and flip is unarmed, and
  **non-zero** when the URL is absent and flip is `armed`.
- **AC5** — *(removed — asserted the descoped FR1. See §Descoped.)*
- **AC5b (enum completeness)** — the FR3 branch classifies **every** `INNGEST_CUTOVER_FLIP` state,
  not just `armed`. `inngest-bootstrap.sh:416` names the FSM set `{armed, flipping, done}` and
  `cutover-inngest.yml` additionally writes `rollback`; the key is currently **absent** from
  `soleur-inngest/prd` (unset). The test asserts the exit code for each of:
  `unset`, `armed`, `flipping`, `done`, `rollback`. A single `= "armed"` comparison silently
  lumps `flipping`/`done` into the dark branch — during those states the dedicated host IS the
  intended pusher, so exit-0 there would be a **silent liveness hole**. Deepen-plan MUST settle
  the correct classification per state before /work.
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
- **AC12** — the recurring `Failed to start inngest-heartbeat.service` stream **stops**: zero new
  occurrences in the 30m after deploy (baseline ~1,240/day).
- **AC13** — `betteruptime_heartbeat.inngest_prd` remains **`up`** throughout (the co-located host
  keeps pushing; this change must not disturb the monitor).

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
3. **Sudoers dual-maintenance (CTO).** `cloud-init.yml:77-79` carries an inline **mirror** of
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

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Exit-0 masks a real post-cutover fault** (the #6536 harm, inverted). | FR3's `flip` discriminator: exit 0 **only** when unarmed. Armed + absent URL still exits non-zero. AC4 asserts both arms. |
| **The new log line leaks the bearer URL** to a third-party vendor, defeating the `sensitive=true` + script-indirection control (`inngest-bootstrap.sh:156-159`). | AC3 leak gate as a test; presence booleans only; PII-scrub drift guard extended (`vector-pii-scrub.test.sh`). |
| `INNGEST_CUTOVER_FLIP` is **not currently present** on `soleur-inngest/prd` (measured — names are `BETTERSTACK_LOGS_TOKEN, DOPPLER_CONFIG, DOPPLER_ENVIRONMENT, DOPPLER_PROJECT, INNGEST_EVENT_KEY, INNGEST_POSTGRES_URI, INNGEST_REDIS_PASSWORD, INNGEST_SIGNING_KEY`). An unset var makes `[ "$INNGEST_CUTOVER_FLIP" = "armed" ]` false → dark branch. | That is the **correct** default (unarmed ⇒ dark ⇒ no-op). Documented explicitly in FR3's comment so the fail-open direction is intentional and reviewable, not incidental. |
| Adding a Vector source row raises Better Stack quota. | Net **large decrease**: FR3 removes ~1,240 failure-noise rows/day; the new channel adds ~1,440 low-cardinality rows/day but the PID-1 `Failed to start` storm stops. Quota posture is a stated `vector.toml:114-117` constraint — deepen-plan to quantify. |
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
