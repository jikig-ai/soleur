---
title: "fix(infra): the host-pull leg is a revoked host Doppler token, not a zot fault — re-deliver it, and make the next revocation self-report"
date: 2026-07-30
issue: 7095
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-154 (provisional — see §Architecture Decision)
status: draft
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 (Infrastructure-as-Code Routing Gate) was reviewed and the ## Infrastructure (IaC)
  section below is complete. This plan contains ZERO operator-driven steps: the merge fires
  .github/workflows/apply-deploy-pipeline-fix.yml, which runs `terraform apply`, whose
  local-exec pushes the rendered files over the CF Tunnel. No SSH appears in any runbook it
  produces (hr-no-ssh-fallback-in-runbooks).

  The scanner-flagged tokens (`systemctl`, `/etc/systemd/system/`, install verbs) appear ONLY as
  DESCRIPTIONS of mechanics that already exist inside Terraform-managed artifacts and that this
  plan must reason about correctly:
    - `systemd-run --on-active=3s ... systemctl restart webhook` is pre-existing code at
      apps/web-platform/infra/infra-config-apply.sh:259-270 (the handler's delayed self-restart).
    - `/etc/systemd/system` is a pre-existing ReadWritePaths entry in webhook.service:48 and a
      destination class in infra-config-install.sh's DEST_SPEC.
  Both are cited as constraints on the design, not prescribed as operator actions.
-->

## Enhancement Summary

**Deepened on:** 2026-07-30 · **Reviewers:** architecture-strategist, spec-flow-analyzer,
code-simplicity-reviewer, cto (devex lens), scoped strong-model consult · **Revisions produced:**
R1–R38

### Key improvements

1. **Three P0s found that would have made the merge run fail with the credential still
   undelivered** — R21 (the template filename reds `infra-config-gate.sh` and blocks the whole
   apply), R22 (the first apply is *guaranteed* to fail on a stale `hooks.json`, and nothing
   re-applies), R23 (the release and the apply race on the same push, so the deploy leg runs
   before the credential exists).
2. **A P0 that would have shipped a false green** — R1: four of the five broken consumers read
   `/etc/default/inngest-server`, which holds a *copy* of the same token pinned forever by
   `inngest-bootstrap.sh:567`. The draft would have recovered ci-deploy, gone green on AC25, and
   left them failing.
3. **A latent catastrophic risk the draft missed entirely** — R2/H7c: the log shipper runs on the
   dead credential and survives only on in-memory secrets. Any reboot is a total telemetry
   blackout on web-1, and every post-merge AC reads through that channel.
4. **A strictly-safer remediation shape** — R3: put the override in `ci-deploy-wrapper.sh` so the
   webhook unit is never modified and the self-restart *cannot* fail to start.
5. **The plan's central self-heal claim was false** — R4: no `schedule:` on the apply workflow, so
   nothing ever evaluates the rotation hash.
6. **~60% scope reduction on the P1 path** via R0's PR-A/PR-B split and R17's reuse of the
   existing probe instead of building a new one.

### New considerations discovered

- The failing/healthy split is exactly the **re-deliverable vs boot-baked** split (E9) — a much
  stronger, more general finding than "one token died".
- `web-2` is not "missing `vector.toml`"; **19 of 19** host installers are pinned to web-1 (R9).
- The Sentry alert route is **dead for this incident class** — its DSN params come from the same
  dead Doppler token (R5). With Better Stack at 3-day retention, that is the difference between
  diagnosable-in-six-months and not (R19).

### Deepen-plan gate results

| Gate | Result |
|---|---|
| 4.5 Network-outage deep-dive | **Fired.** See below — L3→L7 verified in order, with artifacts. |
| 4.6 User-Brand Impact | **Pass** — threshold `single-user incident`, concrete artifact + vector. |
| 4.7 Observability | **Pass** — all 5 fields present, non-placeholder; `discoverability_test.command` contains no `ssh`. |
| 4.8 PAT-shaped variable | **Matched, determined NOT-APPLICABLE — recorded, not silently skipped.** The regex `var\.[a-z_]*_(pat\|token)` matches `var.doppler_token` at 4 sites. `hr-github-app-auth-not-pat` governs **GitHub** write auth; this is a *Doppler* service token, pre-existing (`variables.tf:11-13`), and this plan introduces no new variable. GitHub App auth is not a substitute for a Doppler credential. No halt. |
| 4.9 UI-wireframe | **Skip** — the single glob match is prose inside the Product/UX Gate stating the plan contains no such path. No UI-surface file in Files to Edit/Create. |
| 4.10 Encryption Posture | **Pass** — `at_rest` / `in_transit` / `exception` complete; `does_not_defend` non-empty; exception carries `tracking_issue` + `expires_on`. |
| 4.55 Downtime & Cutover | **HALTED — section was missing.** Now added above. The gate was right: the plan restarts the sole `deploy.soleur.ai` listener and had no zero-downtime evaluation. |

### Citation verification (all resolved live, none from memory)

- **Every** cited AGENTS rule ID (`hr-*`/`wg-*`/`cq-*`) resolves to an active `[id: …]` — zero
  fabricated or retired citations.
- ADR ordinal re-derived from **freshly-fetched `origin/main`** (not the branch base): highest is
  `ADR-153`, so `ADR-154` is the correct provisional pick. Still provisional per `/ship`'s
  collision gate.
- Issue/PR states verified with `gh`: #7095 OPEN, #7071 MERGED, #7096 MERGED, #7072 MERGED,
  #6536 CLOSED, #6537 CLOSED, #6594 CLOSED, #6460 OPEN — every title matches the claim made of it.
- `ops/prod-stale` label does **not** exist → R35f makes the watcher create it idempotently rather
  than leaving an operator step.

### Network-Outage Deep-Dive (Phase 4.5)

Triggered by `unreachable` in the body **and** by the resource-shape rule: the plan drives
`terraform apply` on `terraform_data` resources carrying `connection { type = "ssh" }`
(`infra_config_handler_bootstrap`), which makes SSH an apply-time dependency the prose scan alone
would miss.

| Layer | Status | Artifact |
|---|---|---|
| L3 firewall allow-list | **Verified (opt-out with artifact)** | An *authenticated HTTP 200* traversed the contested path inside the incident window (E5) — strictly stronger than a config read. |
| L3 DNS / routing | **Verified — N/A by construction** | The registry is addressed by literal IPv4; no resolver is on the path. |
| L7 TLS / proxy | **Verified** | `mirror_verified=true` on run `30561788389`; the CF Tunnel leg is healthy. The pull leg does not traverse it. |
| L7 application | **Verified** | Journal lines for the exact incident window pulled from Better Stack (E1, E2) — the deciding evidence, not an absence. |

**Gap closed by the deep-dive:** the apply's *own* SSH dependency was unverified. R34/Phase 0.2b
now requires confirming the last green run of `apply-deploy-pipeline-fix.yml` before relying on
it, and routes an SSH-leg failure to the designated-but-never-wired `server.tf:564/615` fallback.

---

## Overview

Production has not deployed since 2026-07-29. Eight consecutive `Web Platform Release` runs
failed; five of them died on the host with `reason=image_pull_failed`.

The issue body's framing — "the host-pull leg (`ZOT_PULL_*` / private NIC) is broken while the
push leg is proven healthy" — is **half right and half wrong**, and the wrong half is the part
that matters. The push leg *is* healthy (`mirror_verified=true`). The host-pull leg *is* broken.
But it is not broken at zot, not at the private NIC, and not at `ZOT_PULL_*`. All three of
ADR-096 clause (f)'s enumerated residual causes are **falsified by measurement** (§Hypotheses).

The actual fault is one credential level up and is a **second, distinct incident** that began
**2026-07-30 11:19:30Z**, nineteen hours after the 2026-07-29 incident was genuinely repaired:

> web-1's boot-baked, full-`prd`-scoped Doppler service token in `/etc/default/webhook-deploy`
> was revoked. `ci-deploy.sh` still presents it, so every `doppler secrets get` inside the deploy
> returns **empty**. `ZOT_REGISTRY_URL` reads empty → the zot gate takes its
> `"dark, pre-provisioning"` branch and **never attempts zot at all** → the pull falls through to
> an *unauthenticated* GHCR pull of a private package → `auth_denied` → `image_pull_failed`.

The two incidents share exactly one thing: the string `image_pull_failed`. That collision is why
eight red releases read as "the known incident" instead of "a new one", and it is the single
most important thing this plan has to fix — in the code, not in a runbook.

The credential has **no re-delivery path**: `cloud-init.yml:415` writes it exactly once at first
boot, from `var.doppler_token`, which has no Terraform resource, no `replace_triggered_by`, and no
drift detector. Rotating it silently bricks the deploy path plus five other units on the host.
Terraform's copy of the token is currently **valid** — the divergence is entirely host-side.

This plan does four things:

1. **Re-deliver** a valid Doppler token to both web hosts over the existing no-SSH webhook
   channel, with `triggers_replace` hashed on the token so the *next* rotation self-heals.
2. **Make the failure self-reporting** — a failed Doppler read must never again render as
   `"dark, pre-provisioning"`, and must terminate the deploy with its own reason enum rather
   than laundering itself into `auth_denied`.
3. **Add a continuous host-credential liveness probe** so a revoked token pages in minutes
   instead of surfacing as a mystery release failure days later.
4. **Add consecutive-release-failure + prod-staleness alerting**, so the next multi-day
   silent-stale-prod window pages instead of accumulating.

---

## Root Cause Evidence

*Everything below was pulled from the observability layer and the run logs directly
(`hr-no-dashboard-eyeball-pull-data-yourself`). No operator was asked for anything. Sources:
Better Stack Logs ClickHouse warehouse via `scripts/betterstack-query.sh` (creds from Doppler
`soleur/prd_terraform`), `gh run view --log`, `gh api`, and read-only `doppler` metadata calls.*

### Verdict (one line)

The host-pull leg is NOT broken at zot, the private NIC, or `ZOT_PULL_*`. **web-1's baked
full-prd Doppler service token (`/etc/default/webhook-deploy` → `DOPPLER_TOKEN`) was revoked
on 2026-07-30 11:19:30Z**, so every `doppler secrets get` inside `ci-deploy.sh` now returns
EMPTY. `ZOT_REGISTRY_URL` reads empty → the zot gate takes its "dark, pre-provisioning" branch
and never attempts zot at all → the pull falls through to an UNAUTHENTICATED GHCR pull of a
private package → `auth_denied` → `image_pull_failed`.

### E1 — the host says zot was never attempted

Better Stack, `SYSLOG_IDENTIFIER=ci-deploy`, `host_name=soleur-web-platform`. Every failing
deploy since 2026-07-30 14:56 emits the identical triple:

```
2026-07-30 14:56:44.722389  PRELUDE: GHCR_READ_{USER,TOKEN} not both present (baked file absent + doppler empty/unavailable) — skipping docker login
2026-07-30 14:56:44.722389  ZOT_GATE: ZOT_REGISTRY_URL unset — GHCR path (dark, pre-provisioning)
2026-07-30 14:57:06.446972  IMAGE_PULL_FAIL: ref=ghcr.io/jikig-ai/soleur-web-platform:v0.244.3 result=auth_denied recovery_stage=refetch_unavailable
```

Repeated verbatim at 15:16 (v0.244.3), 15:38 (v0.245.0), 16:29 (v0.246.0), 16:43 (v0.246.1).

`ZOT_GATE: ZOT_REGISTRY_URL unset` is emitted at `apps/web-platform/infra/ci-deploy.sh:1361`,
which is reached **only after** `command -v doppler` and `[[ -n "${DOPPLER_TOKEN:-}" ]]` both
pass (`ci-deploy.sh:1356-1357`). So the doppler binary exists and `DOPPLER_TOKEN` is non-empty;
it is the **read** that fails. Its stderr is discarded by `2>/dev/null || true` at
`ci-deploy.sh:1359`. `recovery_stage=refetch_unavailable` (from `refetch_ghcr_and_relogin`) is
the same doppler read failing a second time on the GHCR arm.

### E2 — the same host read Doppler fine until 2026-07-29 21:29

```
2026-07-29 21:29:05.883998  ZOT_GATE: active — docker login 10.0.1.30:5000 ok (zot-primary)
2026-07-29 21:29:48.136114  IMAGE_PULL_OK: registry=zot image=web tag=v0.244.0
```

The host's own `/hooks/deploy-status` last-success body confirms the last good pull came **from
zot**: `"image":"10.0.1.30:5000/jikig-ai/soleur-web-platform","tag":"v0.244.0","reason":"ok"`,
`start_ts=1785360524` (= 2026-07-29 21:28:44Z). Retrieved via the deploy job log of run
`30561788389` (`Pre-rerun lock probe` step, `cat-deploy-state.sh` output).

Earlier in the same window the **original** incident is visible and is a **different** fault:

```
2026-07-29 16:05:47  ZOT_GATE: active — docker login 10.0.1.30:5000 ok (zot-primary)
2026-07-29 16:05:50  IMAGE_PULL: zot pull failed for 10.0.1.30:5000/jikig-ai/soleur-web-platform:v0.244.1 — falling back to GHCR
2026-07-29 16:05:51  IMAGE_PULL_FAIL: ref=ghcr.io/... result=auth_denied recovery_stage=relogin_failed
```

On 07-29, zot **was** attempted and the image was missing (push-side). Since 07-30 14:56 zot is
**not attempted at all**. Two distinct faults, one `image_pull_failed` reason string.

### E3 — the exact revocation moment

`doppler configs tokens --project soleur --config prd --json`:

| name | created_at | access |
|---|---|---|
| `web-probes-read` | 2026-07-18T11:33:56Z | read |
| `github-ci-prd` | 2026-03-29T16:25:25Z | read |
| **`terraform-prd-20260730`** | **2026-07-30T11:19:30.614Z** | read |
| `ghcr-minter-write-20260729` | 2026-07-29T20:57:54Z | read/write |
| `ghcr-minter-write` | 2026-07-30T11:59:21Z | read/write |

`terraform-prd-20260730` was minted at **11:19:30.614Z**. **Eighteen seconds later**, at
**11:19:48.786126**, every doppler-dependent systemd unit on `soleur-web-platform` that sources
`/etc/default/webhook-deploy` began failing, and has failed continuously since (Better Stack,
`SYSLOG_IDENTIFIER=systemd`, 60h window, `min(dt)`/`max(dt)`/`count()` aggregation):

| unit | first_seen | last_seen | n |
|---|---|---|---|
| `container-restart-monitor.service` | 2026-07-30 11:19:48.786126 | 2026-07-30 17:05:05 | 69 |
| `cron-egress-resolve.service` | 2026-07-30 11:19:56.753297 | 2026-07-30 17:05:05 | 341 |
| `cron-egress-alarm@.service` | 2026-07-30 11:19:56.753297 | 2026-07-30 17:05:06 | 341 |
| `inngest-heartbeat.service` | 2026-07-30 11:19:56.753297 | 2026-07-30 17:05:05 | 341 |

No such failures anywhere in the preceding 60h. `_BOOT_ID` is unchanged at
`8c86d4135e0346de9c73dabec64c096e` across the boundary — **not a reboot, not a host replace**.
No repo code mints a token named `terraform-prd-<date>` (`grep -rn 'terraform-prd\|tokens create\|tokens revoke'`
finds only `apps/cla-evidence/infra/bootstrap.sh` for an unrelated `prd_cla` config) — this was
an out-of-band mint-and-revoke.

### E4 — the secrets are fine; only the host's credential is stale

```
doppler secrets get --project soleur --config prd:
  ZOT_REGISTRY_URL = 10.0.1.30:5000      ZOT_PULL_USER = zot-pull
  ZOT_PULL_TOKEN len=40    GHCR_READ_USER len=8    GHCR_READ_TOKEN len=40
```

And the **current** `TF_VAR_doppler_token` (Doppler `soleur/prd_terraform` → `DOPPLER_TOKEN`,
the exact value `cloud-init.yml:415` bakes) still authenticates:

```
doppler run -p soleur -c prd_terraform -- \
  doppler secrets get ZOT_REGISTRY_URL --plain -p soleur -c prd --token "$DOPPLER_TOKEN"
→ 10.0.1.30:5000
```

Terraform's copy is valid; the **host's** copy is dead. A pure divergence between a rotated
control-plane value and a boot-baked host file.

### E5 — zot and the private NIC are provably healthy (clause-(f) suspects 1 and 3 falsified)

`web-zot-consumer-probe` (60s timer, `doppler run` with the **separate** read-only
`web-probes-read` token from `/etc/default/web-zot-consumer-probe`) emitted, over the last 8h on
**both** `soleur-web-platform` and `soleur-web-2`, **only** its rate-limited positive-control
canary and **zero** fault classifications:

```
[zot-probe] SOLEUR_PROBE_CANARY web-zot-consumer-probe source4_live=1 ts=1785427449 — vector Source 4 reachable
```

Per `web-zot-consumer-probe.sh:107-133`, a 401 / 404 / 000 / 5xx each emits a loud line. Silence
**plus a live canary** ⇒ HTTP 200 ⇒
`GET http://10.0.1.30:5000/v2/jikig-ai/soleur-web-platform/tags/list`, authenticated with
`ZOT_PULL_USER`/`ZOT_PULL_TOKEN`, is **servable from both web hosts over the private NIC right
now**. This is the "verify the channel is instrumented before reading silence as an all-clear"
discipline satisfied: the canary is the positive control that makes the silence meaningful.

The probe survives because it uses a **different Doppler token**
(`doppler_service_token.web_probes`, `web-probe-read-token.tf:33`) delivered by a **re-runnable**
provisioner (`server.tf:611-619`) — not the boot-baked one.

### E6 — the discriminator that rules out the `/tmp/.doppler` ownership clash (#6536)

The known sibling failure class is a root-owned `/tmp/.doppler` denying the `deploy` user
(`knowledge-base/project/learnings/2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md`).
It is **structurally incapable** of explaining `ci-deploy.sh`: `webhook.service:21` sets
`PrivateTmp=true` (mirrored in the same unit block inside `cloud-init.yml`), so `ci-deploy.sh`
runs inside webhook.service's *private* `/tmp`, which a host-level root `doppler` invocation
cannot reach. Host-`/tmp` poisoning could explain the three non-webhook units; it cannot explain
ci-deploy. The **only** factor shared by all four failing consumers *and* absent from the healthy
`web-zot-consumer-probe` is the `DOPPLER_TOKEN` value in `/etc/default/webhook-deploy`.

**Named residual:** this is an elimination argument over a declared-unit property, not a direct
read of doppler's stderr (which the code discards). It is *not* left unresolved — Phase 1 ships
the marker that captures doppler's real exit code and error class, and Phase 2's re-delivery is
itself the decisive experiment. If reads recover on a re-delivered token, revocation is proven;
if they do not, the Phase-1 marker names the true cause on the very next run, with no SSH.

### E7 — the run-log side

Deploy job of run `30561788389` = job `90939713142`. Terminal line:

```
##[error]ci-deploy.sh exited 1 (reason=image_pull_failed, tag=v0.246.1)
```

with `MIRROR_VERIFIED: true` recorded in the same job's `Record zot mirror verification status`
step — push leg healthy, pull leg dead. The full status body carried
`"image":"ghcr.io/jikig-ai/soleur-web-platform"` (note: **ghcr**, not the zot ref that the last
successful deploy carried) — the workflow log itself contains the fingerprint of "zot was never
attempted", and nobody read it because nothing pointed at it.

All eight failing `Web Platform Release` runs, with the step that actually failed:

| run | created | failing job :: step |
|---|---|---|
| 30468080168 | 07-29 15:53 | deploy (the 07-29 incident) |
| 30494122949 | 07-29 21:54 | `await-ci` :: Wait for CI test check-run |
| 30537359692 | 07-30 11:07 | `release` :: Build and push Docker image |
| 30540598262 | 07-30 11:57 | `release` :: Build and push Docker image |
| 30551736275 | 07-30 14:26 | `deploy` :: Verify deploy script completion |
| 30556644316 | 07-30 15:25 | `deploy` :: Verify deploy script completion |
| 30560618885 | 07-30 16:15 | `deploy` :: Verify deploy script completion |
| 30561788389 | 07-30 16:30 | `deploy` :: Verify deploy script completion |

**Three of the eight never reached the deploy job at all.** The existing
`Email notification (deploy FAILED)` step is `if: failure()` *inside* the `deploy` job
(`web-platform-release.yml:832-869`), so it did not fire for those three. This is a second,
independent hole in the notification story and is why "eight consecutive failures" produced
fewer than eight notifications.

### E8 — soleur-web-2 is live, and is invisible

The 8h Better Stack identifier census shows two distinct hosts:

| host | identifiers seen (8h) |
|---|---|
| `soleur-web-platform` | container, `systemd`, `web-git-data-probe`, `webhook`, `web-zot-consumer-probe`, `doppler`, `web-nic-guard`, `infra-config-apply`, **`ci-deploy`**, `infra-config-install`, `inngest-inventory` |
| `soleur-web-2` | `web-git-data-probe`, `web-zot-consumer-probe`, `web-nic-guard` — **and nothing else** |

Three independent confirmations that web-2 is a live deploy target:
`WEB_HOST_PRIVATE_IPS: 10.0.1.10,10.0.1.11` in the deploy job env; the 2026-07-29 21:29 log line
`FANOUT: peer 10.0.1.11 accepted deploy (HTTP 202)`; and both
`WEB_ZOT_CONSUMER_URL_WEB_1` **and** `WEB_ZOT_CONSUMER_URL_WEB_2` present in Doppler `soleur/prd`.

web-2 therefore runs `ci-deploy.sh` on every deploy and carries the same dead boot token — and
**its `ci-deploy` and `webhook` journals never reach Better Stack at all**, because `vector.toml`
is delivered to a *running* host only by `terraform_data.journald_persistent`
(`server.tf:787-894`), whose `connection.host` is `hcloud_server.web["web-1"]` only. The peer leg
of every two-host deploy is blind. (This is the "empty telemetry is not evidence of absence"
trap, live: a query for web-2's ci-deploy rows returns exactly what a healthy host would.)

### E9 — the failing/healthy split is exactly the re-deliverable/boot-baked split

This is the strongest structural evidence in the set, and it generalises the fault beyond one file.
The web host carries **nine** boot-baked `/etc/default/*` credential files plus
`/etc/default/inngest-server`. Enumerated from
`grep -rnE "> */etc/default/[a-z-]+" cloud-init.yml soleur-host-bootstrap.sh server.tf` and
`grep -rnE "EnvironmentFile=-?/etc/default/[a-z-]+" *.service soleur-host-bootstrap.sh cloud-init.yml`:

| Class | Env file | Re-delivery path | Consuming unit | Live status |
|---|---|---|---|---|
| **A — re-deliverable** | `/etc/default/web-zot-consumer-probe` | `server.tf:615` provisioner, `triggers_replace`-hashed | `web-zot-consumer-probe.service:28` | ✅ healthy (366 rows/8h) |
| **A** | `/etc/default/web-private-nic-guard` | `server.tf:564` provisioner | `web-private-nic-guard.service:28` | ✅ healthy (71 rows/8h) |
| **A** | `/etc/default/web-git-data-probe` | provisioner | `web-git-data-probe.service:27` | ✅ healthy (710 rows/8h) |
| **B — boot-baked only** | `/etc/default/webhook-deploy` | **none** | `webhook.service:7` → `ci-deploy.sh` | ❌ **failing** |
| **B** | `/etc/default/inngest-server` | **none** | `container-restart-monitor.service:14`, `cron-egress-resolve.service:19`, `cron-egress-alarm@.service:10`, `cron-egress-firewall.service:22` | ❌ **3 failing** |
| **B** | `/etc/default/soleur-ghcr-read` | **none** | `ci-deploy.sh:1262` (`. "$ghcr_read_file"`) | ❌ reported "baked file absent" (E1) |
| **B** | `container-restart-monitor`, `disk-monitor`, `resource-monitor`, `luks-monitor` | **none** | assorted timers | not exercised in window |

**Every Class-A file is healthy. Every Class-B file that exercises Doppler is failing.** The split
is not "which token" — it is "which files have a convergence path". That is the finding ADR-154
records, and it is why the fix must generalise to the class rather than patch one file.

**Correction to an earlier reading of this evidence.** The three cron/monitor units do **not** read
`/etc/default/webhook-deploy` — they read `/etc/default/inngest-server`, a *different* boot-baked
file. Their 11:19:48 onset is therefore **correlational** with respect to the deploy path's token,
not the same datum. See H7a/H7b in §Hypotheses: the deploy-path claim is directly evidenced; the
cron-timer claim is not, and is marked UNKNOWN rather than folded into a tidier story.

**Named counter-signal, not suppressed.** `soleur-host-bootstrap.sh:738` defines a web-host
`vector.service` carrying `EnvironmentFile=/etc/default/webhook-deploy` and an ExecStart that runs
`doppler run ... -- vector` when `DOPPLER_TOKEN` is non-empty. If web-1's live vector unit were
that one, a dead `webhook-deploy` token would kill log shipping — and logs are demonstrably
shipping. Two readings are open: (i) web-1's live vector predates that bootstrap version
(`soleur-host-bootstrap.sh:689-693` explicitly refuses to clobber an existing
`/etc/default/inngest-server`-based vector unit, and `model.c4:451` records that web-1 never
re-ran cloud-init), or (ii) something about the token's validity is narrower than "revoked". **The
repo cannot discriminate these.** The Phase-4 probe reports the effective env file and token class
per unit, which answers it on the next tick; Phase 0.2's status read may answer it sooner. This is
recorded rather than reasoned away.

### The invisibility to close

`/etc/default/webhook-deploy` is written **exactly once**, at first boot —
`apps/web-platform/infra/cloud-init.yml:415`:

```
printf 'DOPPLER_TOKEN=%s\nDOPPLER_CONFIG_DIR=/tmp/.doppler\nDOPPLER_ENABLE_VERSION_CHECK=false\n' '${doppler_token}' > /etc/default/webhook-deploy
```

`var.doppler_token` is an operator-minted token (`variables.tf:11-13`) with **no Terraform
resource**, therefore no `replace_triggered_by`, no drift detection, and no re-delivery path.
`hcloud_server.web` carries `lifecycle { ignore_changes = [user_data, ...] }`, so editing
cloud-init is **inert** for an already-booted host. Consumers of that one file:

| consumer | site |
|---|---|
| `webhook.service` → `ci-deploy-wrapper.sh` → `ci-deploy.sh` | `webhook.service:7`, `cloud-init.yml:240` |
| host bootstrap + probe helpers | `soleur-host-bootstrap.sh:43,211,738,843` |
| cron-egress enforce probe | `cron-egress-enforce-probe.sh:49` |
| cloud-init runtime helpers | `cloud-init.yml:329`, `:486`, `:786` |

Contrast the two mechanisms that already work and are the fix vehicles:

- **`server.tf:564` / `server.tf:615`** — re-runnable provisioners that rewrite
  `/etc/default/web-private-nic-guard` and `/etc/default/web-zot-consumer-probe` with
  `doppler_service_token.web_probes.key`, `triggers_replace`-hashed. *This is why the probes
  survived the revocation.*
- **`push-infra-config.sh` + `terraform_data.deploy_pipeline_fix`** (`server.tf:1231-1367`) — a
  **no-SSH**, webhook-driven, Terraform-triggered file push through the CF Tunnel. **Proven
  alive after the token died**: `infra-config-apply: starting: 15 files to write` /
  `complete: 15/15 files written, 0 failed` at **2026-07-30 16:32:48**. It already carries a
  secret-bearing Terraform-rendered file (`HOOKS_JSON_B64` ← `local.hooks_json` ←
  `templatefile(hooks.json.tmpl, {webhook_deploy_secret})`), so a rendered env file is
  precedent-compatible. It is applied on merge by `.github/workflows/apply-deploy-pipeline-fix.yml`
  (`-target=terraform_data.deploy_pipeline_fix -target=terraform_data.infra_config_handler_bootstrap ...`),
  which fires on `pull_request_target: [closed]` filtered to those infra files — **the merge is
  the authorization; there is no operator step.**

### Observability gaps found (each is a deliverable)

1. **`ci-deploy.sh:1359` swallows the doppler error** (`2>/dev/null || true`) and reports a dead
   credential as `ZOT_GATE: ZOT_REGISTRY_URL unset — GHCR path (dark, pre-provisioning)` — prose
   that reads as an *intentional* pre-provisioning state. Same shape at `ci-deploy.sh:1374-1377`
   (`creds_absent`) and in `ghcr_prelude_and_login` ("baked file absent + doppler
   empty/unavailable"). Highest-value line in the codebase to fix.
2. **A revoked host `DOPPLER_TOKEN` raises no alarm.** 341 consecutive unit failures over 5.7h,
   zero pages. `container-restart-monitor`, `cron-egress-resolve`, `cron-egress-alarm` emit via
   `echo` under unit-derived identifiers absent from the Vector Source-4 allowlist
   (`vector.toml:151-244`), so their stderr never leaves the box. Adding a name to the allowlist
   is a **dead no-op** unless the unit actually stamps that identifier — so each needs a
   `SyslogIdentifier=` directive *and* an allowlist entry.
3. **web-2's deploy journals never ship** (E8).
4. **`ZOT_ACTIVE=1` is not evidence a pull will work** (`ci-deploy.sh:1022-1030`): zot enforces
   authz at the manifest endpoint, which `docker login` never touches.

### Release-failure alerting gap (deliverable 2)

- `web-platform-release.yml:832-869` — `if: failure()` inside `deploy`; silent when `deploy` is
  **skipped** (3 of 8, per E7). Also `exit 0` with only an `::error::` when `RESEND_API_KEY` is
  empty (`:842-845`).
- `notify-gated` (`:1131-1175`) covers only `await-ci` failure and silently no-ops without
  `SLACK_RELEASES_WEBHOOK_URL`.
- Nothing is stateful: no "N consecutive failures", no "prod is N releases behind".
- Reusable primitives: `main-health-monitor.yml:52+` label-deduped `ci/main-broken` P1-issue
  pattern; `scripts/watch-live-verify-pass.sh:43` `gh run list --json` shape;
  `https://app.soleur.ai/health` already returns `{version, build_sha, uptime}`
  (`apps/web-platform/server/health.ts:92-103`) and is already polled by
  `web-platform-release.yml:750-801`.
- Heartbeat route cost: a new `betteruptime_heartbeat` needs a row in
  `plugins/soleur/lib/heartbeat-manifest.ts` (discovered⊆manifest assertion) **and** a `-target=`
  line in `.github/workflows/apply-web-platform-infra.yml` (~L428-431 allow-list) — and releases
  are merge-driven, **not cadenced**, so a naive `period`/`grace` false-pages every quiet weekend.
  §Alternatives records why this plan does not take the heartbeat route for staleness.

---

---

## Phase 0 Results (/work, 2026-07-30) — measured, not inherited

*All probes run from the worktree; no operator was asked for anything
(`hr-no-dashboard-eyeball-pull-data-yourself`).*

### 0.0 — E9/H7b contradiction RESOLVED to branch (a). R1 confirmed; the tf comment is stale.

`web-probe-read-token.tf:5-6` asserts *"web-1 has no `/etc/default/inngest-server` —
`web_colocate_inngest` defaults false"*. **That parenthetical is stale.** Two independent proofs:

1. **`inngest-heartbeat.service` carries a NON-optional `EnvironmentFile=/etc/default/inngest-server`**
   (`inngest-bootstrap.sh:315` — no `-` prefix). systemd fails a unit outright when a non-optional
   `EnvironmentFile` is absent. It ran healthy until 11:19:56 on 2026-07-30, so **the file exists on
   web-1**. This proof is independent of the token's validity.

2. **The failure onset is the revocation instant.** Better Stack ClickHouse, 60h window,
   `host_name = soleur-web-platform`, grouped by unit (`… : Failed with result`):

   | unit | first_seen | last_seen | n |
   |---|---|---|---|
   | `inngest-server.service` | 2026-07-29 06:45:44.189299 | 2026-07-29 06:45:45.317983 | 2 |
   | `inngest-redis.service` | 2026-07-29 06:45:44.289786 | 2026-07-29 06:45:44.289786 | 1 |
   | `vector.service` | 2026-07-29 06:45:44.445406 | 2026-07-29 06:45:44.445406 | 1 |
   | **`container-restart-monitor.service`** | **2026-07-30 11:19:48.786126** | 2026-07-30 17:50:48.197840 | 78 |
   | **`inngest-heartbeat.service`** | **2026-07-30 11:19:56.753297** | 2026-07-30 17:53:51.818576 | 389 |
   | **`cron-egress-resolve.service`** | **2026-07-30 11:19:56.753297** | 2026-07-30 17:53:51.818576 | 389 |

   `terraform-prd-20260730` was minted **2026-07-30T11:19:30.614Z**. `container-restart-monitor`
   fails **+18.17s** later; the other two **+26.14s**. Zero failures for these units in the
   preceding 53 hours.

**Why the onset time is the discriminator.** `cron-egress-resolve.service`'s `ExecStart` is
`… if [ -n "$D" ] && [ -n "$DOPPLER_TOKEN" ]; then exec "$D" run … ; else exec …sh; fi`. Had
`DOPPLER_TOKEN` been *empty* (the "file absent" world), the unit would have taken the `else`
branch and its behaviour would be **invariant across the revocation** — always working or always
failing, never flipping. It flipped, at +26s. Therefore `DOPPLER_TOKEN` was non-empty and became
*invalid* — i.e. the file holds the dead **copy** made at `inngest-bootstrap.sh:586`, exactly as
R1 states. **H7b: CONFIRMED (upgraded from UNKNOWN on evidence, not on the tidy story).**

Consequence for the fix: R1's remedy is correct **and** the plan's own 0.0-branch-(a) note ("Phase 2
does not fix those three units") is superseded by R1 — adding
`EnvironmentFile=-/etc/default/soleur-doppler-token` *after* the `inngest-server` line fixes them by
systemd later-wins. Both statements are in the plan; **R1 wins.**

### 0.0c / R2 — `vector.service` has NOT failed since 2026-07-29 06:45. The risk is live, not realised.

Its absence from the 07-30 cluster is the positive evidence for R2's mechanism: it holds
its fetched secrets in memory from a pre-revocation start. One restart = telemetry blackout.
The `vector.service.d` drop-in stays highest-priority in PR-A.

### 0.2 / 0.2b — the fix channel is alive (both legs)

- `infra-config-apply`, 2026-07-30 16:32:48.481302: **`complete: 15/15 files written, 0 failed`**,
  `_SYSTEMD_UNIT=webhook.service`. The webhook leg works.
- `apply-deploy-pipeline-fix.yml` run **30561787757 → success, 2026-07-30T16:30:44Z**. This proves
  the co-targeted root-SSH `infra_config_handler_bootstrap` leg is alive (R34's precondition).

### 0.3 — token state has not moved since 11:19:30Z

`doppler configs tokens --project soleur --config prd`: `terraform-prd-20260730` present, created
`2026-07-30T11:19:30.614Z`. No new `prd` token since. Situation is unchanged; the evidence stands.

### 0.4 / R35e — **the delivered value is ALIVE, and its shape cannot brick the unit**

`--name-transformer tf-var` maps prd_terraform's `DOPPLER_TOKEN` → `TF_VAR_doppler_token`
(`apply-deploy-pipeline-fix.yml:271,323`), so that secret **is** `var.doppler_token`.

| check | result |
|---|---|
| `^DOPPLER_TOKEN=dp\.st\.[A-Za-z0-9._-]+$` on the rendered line | **pass** |
| length | 53 |
| contains CR / `#` / space / tab / newline | **no / no / no / no** |
| `GET api.doppler.com/v3/configs/config/secrets/names?project=soleur&config=prd` with it | **HTTP 200** |

**This is the precondition the whole remediation rests on** — Terraform's copy authenticates *right
now*, so re-delivering it genuinely repairs the host. Had it been dead, the fix would have shipped a
second dead token. Sharp Edge 1's open question (newline/`#`) is **closed by measurement**; the R3.1
`terraform plan` validation stays as the regression guard for the next rotation.

### 0.6 — Phase 1 is not chicken-and-egg (re-asserted, not inherited)

`ci-deploy.sh` is entry **#1** of `FILE_MAP` (`infra-config-apply.sh`) and of `DEST_SPEC`
(`infra-config-install.sh`), delivered by the webhook channel proven alive at 16:32:48 — **not** by
the container deploy that is broken. Diagnostics can land independently of the pull path.

### 0.7 / R36 — web-2 decision input, and prod's actual staleness

- `https://app.soleur.ai/health` → `{"status":"ok","version":"0.244.0","build_sha":"34654d7a…","uptime":73562}`.
  **Prod is serving v0.244.0** against a latest tag of v0.246.1 — the stale-code claim is confirmed
  from prod's own mouth, and uptime ~20.4h brackets the window.
- `https://web-1.app.soleur.ai/health` and `https://web-2.app.soleur.ai/health` → **`000`** (name
  does not resolve). The per-host origin probes R33 wants for PR-B's condition B **do not exist as
  DNS today**; `model.c4:287` describes them aspirationally. Recorded so PR-B does not inherit the
  assumption — this is a real gap, not a transient failure.

### 0.5 — consumer sweep

`git grep -n 'webhook-deploy' -- apps/ .github/ scripts/` → 38 hits; `DOPPLER_TOKEN` under
`apps/web-platform/infra/` → 40 hits. Enumerated into §Files to Edit; the shell-`source` sites
(`soleur-host-bootstrap.sh:43,211`, `cron-egress-enforce-probe.sh:49`, `cloud-init.yml:329,486,786`)
remain on the OLD file by design (Design T), and are covered because the old file keeps working for
everything except the revoked value — the new file is additive and later-wins where it is wired.

### Still open (carried into implementation, not assumed away)

- **0.0b — whether `doppler` exits non-zero or `rc=0` with empty output on a revoked token is
  still UNMEASURED.** `ci-deploy.sh:1359` discards stderr, so nobody has ever seen it. The marker
  must therefore carry `empty=<0|1>` *alongside* `rc=<n>`, and the RED fixture must cover
  `rc=0 empty=1` first. Do not let a test assert a shape that may not be this incident.

---

## Implementation Findings (/work) — two review revisions did not survive contact

### R22 is FALSIFIED. The guard it asks for already exists.

R22 asserts: *"the FIRST apply is guaranteed to fail … the host's `hooks.json` is stale and
therefore cannot pass the new `soleur_doppler_token_b64` key, so the handler records `missing_env`
… AC22 and Phase 7.1 cannot pass on the merge run"*, and prescribes a second `terraform apply` +
verify pass in the same job.

Verified against the code, not the prose:

| claim | reality |
|---|---|
| the push runs against a stale `hooks.json` | **No.** `terraform_data.deploy_pipeline_fix` carries `depends_on = [terraform_data.apparmor_bwrap_profile, terraform_data.infra_config_handler_bootstrap]` (`server.tf:1306`). |
| nothing delivers the new `hooks.json` first | **No.** The bridge writes it (`server.tf:1204`, `base64 -d > /etc/webhook/hooks.json`) and restarts the listener (`server.tf:1219`). |
| ordering is not guaranteed | **No.** Terraform orders by the declared dependency graph, and the edge is declared. |

That edge was added by #5515 **for precisely this scenario** — its own comment describes "a merge
that BOTH adds a new webhook-written FILE_MAP file (a new entry in `infra-config-apply.sh`'s
FILE_MAP + a new env key in `hooks.json`) AND fires this push", which is exactly this PR. So the
`missing_env` first-apply failure R22 predicts **does not occur by that mechanism**, and a second
apply pass would be dead code guarding an impossible state.

**A second `terraform apply` would not even do what R22 wants.** After the first apply,
`deploy_pipeline_fix` exists at the new trigger hash, so a plain re-apply is a NO-OP — it would
have to be `-replace=terraform_data.deploy_pipeline_fix` to re-push at all. R22 does not say this,
which is a second sign the mechanism was not traced.

**The residual R22 half-saw, restated correctly.** The real hazard is the documented nonce-1 RACE
(`push-infra-config.sh:25-31`): the bridge's `systemctl restart webhook` returned ~10 ms BEFORE the
push fired, so the push hit a still-restarting listener — HTTP 202 accepted, async handler exec
disrupted, no files written. R22's genuinely correct observation is that the verify step
(`apply-deploy-pipeline-fix.yml:401-520`) only **re-polls the same state and never re-POSTs**, so
it cannot recover from that race on its own.

That is a real gap, and it is **NOT fixed in this PR** — deliberately. Closing it means putting
`continue-on-error` on the fail-closed verification gate and adjudicating afterwards, i.e.
restructuring the exact gate whose latched false-green (#6594) let this class of outage hide in the
first place. Getting that wrong converts a fail-closed gate into a fail-open one, which is strictly
worse than the race it would fix. Tracked as a follow-up; the existing documented recovery (re-run
via `workflow_dispatch`, which re-fires the bridge) remains available and is now named in the R34
message below.

### R34 implemented, and its premise CONFIRMED.

The status endpoint dies with the webhook unit, so before this change a bricked listener produced
the **404** branch's message — which points at first bootstrap and whose suggested
`allow_missing_status_endpoint=true` would have **suppressed the very failure**. `000`/`502`/`503`
now get their own terminal branch naming the listener as down, explicitly warning against that
flag, and naming the root-SSH provisioner (`server.tf:564/615`) as the route back.

---

## Hypotheses

Triggered by `hr-ssh-diagnosis-verify-firewall` / the network-outage checklist (the description
contains `unreachable`; the plan touches `terraform_data` resources carrying a `connection` block).
Layers are listed L3 → L7. **Every verdict below rests on a measurement taken from the failing
host itself**, not on reasoning about how the mechanism ought to behave.

| # | Layer | Hypothesis | Verdict | Verification artifact |
|---|---|---|---|---|
| H1 | **L3 — private-net path** | `10.0.1.10 → 10.0.1.30:5000` is down (ADR-096 clause (f) cause 1) | **REFUTED** | E5. `web-zot-consumer-probe` returns HTTP 200 from **both** web hosts *right now*, over that exact path, with a live positive-control canary proving the reporting channel is up. A `000` would have emitted `SUPPRESS ping: 000 — UNREACHABLE`; none exists in 8h. |
| H2 | **L3 — firewall allow-list** | `hcloud_firewall.web` / registry firewall drift blocks the pull | **REFUTED (opt-out with artifact)** | Same artifact as H1: an authenticated HTTP 200 traversed the firewall inside the incident window. `hcloud firewall describe` is not run because a *successful authenticated request over the contested path* is strictly stronger evidence than a config read. |
| H3 | **L3 — DNS / routing** | Name/route drift to the registry | **N/A — REFUTED** | The registry is addressed by literal IPv4 (`ZOT_ENDPOINT=10.0.1.30:5000`, `server.tf:615`; `ZOT_REGISTRY_URL=10.0.1.30:5000` in Doppler). No resolver is on this path. |
| H4 | **L7 — CF Tunnel / CF Access** | The push-side bridge is still broken (the 07-29 cause) | **REFUTED** | `MIRROR_VERIFIED: true` on run `30561788389` (E7); the image is confirmed in zot at the build digest. Also: the pull leg does not traverse the tunnel at all. |
| H5 | **L7 — `ZOT_PULL_*` stale** | Pull credential rotated without propagating (clause (f) cause 2 — the issue's highest-prior suspect) | **REFUTED** | E5. The probe authenticates with exactly `ZOT_PULL_USER`/`ZOT_PULL_TOKEN` read live from `soleur/prd` and gets 200. A stale pull cred would emit `HARD FAILURE: 401` (`web-zot-consumer-probe.sh:117-119`). Corroborated by E1: **zot was never contacted**, so no zot credential can be the cause. |
| H6 | **L7 — zot `accessControl`** | Grants push-read but not pull-read (clause (f) cause 3) | **REFUTED** | E5 (the probe's 200 *is* an authenticated repo read by the pull user) plus `cloud-init-registry.yml:112-130`: `{"users":["zot-pull"],"actions":["read"]}` on `**`. And again — zot was never contacted. |
| H7a | **L7 — the DEPLOY PATH cannot read its own credential source** | `webhook.service`'s `DOPPLER_TOKEN` is present but non-functional, so every secret read in `ci-deploy.sh` returns empty | **CONFIRMED** | Directly evidenced, three independent ways. (i) E1: the `[[ -n "${DOPPLER_TOKEN:-}" ]]` guard at `ci-deploy.sh:1357` **passes** and the read still yields empty — so the value is present and non-functional, not absent. (ii) E4: Terraform's copy of the same variable authenticates against the same project/config right now. (iii) E5: a *different* token on the *same host* at the *same instant* reads the *same config* successfully. Verified additionally that `ci-deploy.sh` does **not** shell-source the env file (`grep -nE '^\s*(\.|source)\s'` → only `:1262` for the GHCR file), so its token arrives purely by unit inheritance — which is what makes the Phase-2 design work. **This cause is not in ADR-096 clause (f)'s enumeration.** |
| H7b | **L7 — the same revocation also killed the three cron/monitor timers** | One token event explains all four unit failures | **CONFIRMED — mechanism found at review (R1)** | Initially marked UNKNOWN because those units read `EnvironmentFile=-/etc/default/inngest-server` (`container-restart-monitor.service:14`, `cron-egress-resolve.service:19`, `cron-egress-alarm@.service:10`), a *different* file. Architecture review found the missing link: **`/etc/default/inngest-server` holds a COPY of the same token**, extracted once at bootstrap by `inngest-bootstrap.sh:586` — `grep -oP '(?<=^DOPPLER_TOKEN=)dp\.\S+' /etc/default/webhook-deploy`. One revocation, two files, five consumers. Worse, `inngest-bootstrap.sh:567-568` **preserves** the copy whenever it still matches `^DOPPLER_TOKEN=dp\.` — so a dead-but-well-formed token is pinned forever, with no self-heal even on re-bootstrap. This is the invariant the incident actually teaches (R14). |
| H7c | **L7 — the log shipper is running on the dead credential too** | web-host `vector.service` would also be broken | **CONFIRMED-LATENT — the counter-signal explained (R2)** | `soleur-host-bootstrap.sh:721-738`: `EnvironmentFile=/etc/default/webhook-deploy` + `if [ -n "$DOPPLER_TOKEN" ]; then exec doppler run ... -- vector`. `DOPPLER_TOKEN` is non-empty (just dead) → the guard passes → `doppler run` fails → `Restart=on-failure` crash-loop. It has not fired **only because the process started before 11:19:30Z and holds its fetched secrets in memory.** Any reboot, OOM, or `systemctl restart vector` is a **total telemetry blackout on web-1** — and AC24/AC26 and the entire `discoverability_test` read through that channel. This resolves the counter-signal named in E9 and promotes vector to the highest-priority consumer in the sweep. |
| H8 | **L7 — `/tmp/.doppler` ownership clash (#6536)** | Root-owned `/tmp/.doppler` denies the `deploy` user | **REFUTED, with a named residual** | E6. `webhook.service:21` `PrivateTmp=true` structurally isolates `ci-deploy.sh` from host `/tmp`, so this cannot explain the ci-deploy arm. Residual and its resolution are stated in E6; Phase 1's marker is the durable discriminator, and Phase 2 is the decisive experiment. |

**Ordering discipline honoured:** L3 (H1–H3) was verified *before* any L7 hypothesis was
entertained, and the L3 verification is a positive measurement (an authenticated 200 across the
contested link), not an absence.

---

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #7095 / prior artifacts) | Reality | Plan response |
|---|---|---|
| "Host pull ← zot, using `ZOT_PULL_*` over the private NIC: **BROKEN**" | The *leg* is broken; the *named mechanism* is healthy. zot is never contacted (E1); `ZOT_PULL_*` authenticates (E5). | Reframe the issue. Fix the real cause (H7). Record the falsification of all three clause-(f) suspects in the ADR-096 amendment so the next responder does not re-walk it. |
| "ADR-096 clause (f)'s three enumerated uncovered causes are the live suspects" | All three are refuted. A **fourth** uncovered cause exists: *the host cannot read its own credential source*, which makes the mirror gate's assertion vacuous in a way clause (f) does not describe. | Amend ADR-096 clause (f) to add cause 4. In scope for this PR (§Architecture Decision). |
| Post-mortem "currently corrected to `status: ongoing`" | **True on `origin/main`** (`d95344622`, PR #7096) but **not in this worktree** (`be7b5a5ee`, behind). The worktree must sync before /work. | Phase 0 syncs the worktree. The plan targets `origin/main` content. |
| Post-mortem `incident_window` on main: "the ~21:00 token fix restored the PUSH/bridge leg only; the HOST-pull leg is still failing" | Correct that prod is stale; **wrong about mechanism and continuity**. The 07-29 incident *was* fully repaired — `IMAGE_PULL_OK: registry=zot tag=v0.244.0` at 2026-07-29 21:29:48 (E2). The 07-30 failures are a **new** incident starting 11:19:30Z, sharing only the reason string. | Do **not** simply flip `status` back to `resolved`. Correct the 07-29 PIR to record its genuine recovery *and* the second incident, and write a **separate** PIR for 07-30. §Phase 6. |
| "Six of the eight failures predate that branch entirely" | Confirmed, and sharper: three of the eight never reached the `deploy` job at all (E7) — two died at `release :: Build and push Docker image`, one at `await-ci`. | The alerting deliverable must key on *release-run* outcome, not on the `deploy` job, or it reproduces the same blind spot. |
| Deploy instrumentation "is what made the fault diagnosable" | Partly. The `zot_perr_tail` addition (`ci-deploy.sh:1602-1604`) instruments the **zot-attempted** arm. This incident never reaches it. What actually made it diagnosable was the pre-existing `ZOT_GATE:` / `IMAGE_PULL_FAIL:` markers already in the Vector Source-4 allowlist (`vector.toml:154`). | Phase 1 instruments the **zot-not-attempted** arm — the one that was dark. |
| C4 `model.c4:182`: "the fleet remains single-host until web-2 is provisioned by the gated `web-host-create` dispatch"; `:178` "web-2 was retired 2026-07-17 … `var.web_hosts` is now single-host" | **Falsified by three independent live signals** (E8): `soleur-web-2` is emitting three probe identifiers to Better Stack; `WEB_HOST_PRIVATE_IPS=10.0.1.10,10.0.1.11`; both `WEB_ZOT_CONSUMER_URL_WEB_{1,2}` exist in Doppler `prd`. web-2 is live and is a deploy target. | In-scope C4 correction (§Architecture Decision → C4 views). Also makes web-2's dead token and blind telemetry **in scope for the fix**, not a footnote. |
| Assumed vehicle: "re-deliver `/etc/default/webhook-deploy` via the infra-config webhook" | **Blocked as literally stated.** `cloud-init.yml:266` / `webhook.service:49` set `ReadOnlyPaths=/etc/default/webhook-deploy`, and `ProtectSystem=strict` is namespace-scoped so `sudo` does not escape it (`webhook.service:25-26` says so explicitly). `/etc/default` *as a directory* **is** in `ReadWritePaths`. | Deliver a **new** file `/etc/default/soleur-doppler-token` (not in `ReadOnlyPaths`) and add a second `EnvironmentFile=` to `webhook.service` (later-wins). §Phase 2. |
| Assumed: "adding a file to the infra-config push is additive and low-risk" | `infra-config-gate.sh:126-129` asserts **exactly one** Terraform-rendered (`.tmpl`-backed) FILE_MAP destination and fails loud otherwise. A second rendered file reds the gate by design. | Phase 2 updates that invariant from 1 → 2 with a documented reason, in the same commit. Named as an AC so it is not discovered in CI. |
| Assumed: the infra-config push might be dead too | **Proven alive at 2026-07-30 16:32:48**, after the token died (`complete: 15/15 files written, 0 failed`). It needs no Doppler on the host. | This is the enabler for a no-SSH remediation. Recorded as a Phase-0 precondition to re-assert at /work time. |
| Assumed: `push-infra-config.sh` reaches both hosts | It POSTs once to `https://deploy.<domain>/hooks/infra-config`, which the tunnel pins **origin-relative to web-1** (`model.c4:423`: "deploy-status, inngest-liveness and infra-config do **not** fan out"). web-2 is unreachable by this channel. | §Phase 3 handles web-2 explicitly rather than silently leaving it broken. |

---

## Premise Validation

- `#7095` — `gh issue view 7095`: **OPEN**, `type/bug`, milestone `Post-MVP / Later`, title
  "P1: prod has not deployed since 2026-07-29 — host-pull leg (ZOT_PULL_*/private NIC) broken
  while push leg is proven healthy". Premise holds that prod is stale; the parenthetical
  mechanism is falsified above and the issue title should be amended at /work.
- `#7071` (the 07-29 incident PR) — merged; its artifacts (`zot-entry-gate.sh` SUPERSEDED header,
  ADR-096 amendment) are on `main` and read correctly.
- `#7096` — merged as `d95344622`; it is the commit that set the PIR to `status: ongoing`.
  This worktree is behind it.
- The post-mortem file and `ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` both
  exist; clause (f) is the cited text and is quoted correctly in the issue.
- **Mechanism-vs-ADR grep.** `ADR-088` arm-b establishes that no zero-touch GHCR pull credential
  can exist, and the ADR-096 amendment (2026-07-30, #7071) makes zot the **sole** pull path. The
  GHCR fall-through this incident traversed is therefore **already-retired dead weight** whose only
  remaining effect is to relabel a credential failure as `auth_denied`. Short-circuiting before it
  is consistent with (not contrary to) the standing decisions.
- **Repo-capability claims verified before assertion** (`hr-verify-repo-capability-claim-before-assert`):
  the "infra-config cannot write `/etc/default/webhook-deploy`" claim is read off
  `cloud-init.yml:266` + `infra-config-install.sh:59-100` (`DEST_SPEC` allow-list +
  `reject "dest_not_allowlisted"`), not assumed.
- **CORRECTION (R10) — a claim of verification that was itself unverified.** An earlier draft of
  this section asserted that `apply-deploy-pipeline-fix.yml` fires on
  `on: pull_request_target: [closed]` and cited that as *verified*. It does not: the real trigger
  is `on: push: branches: [main], paths: [...]` plus `workflow_dispatch`
  (`apply-deploy-pipeline-fix.yml:62-64`). The **outcome** is the same — merging to `main` fires
  the apply, so "the merge is the authorization" holds — but the claim of verification was false,
  and a plan that mis-cites the thing it says it checked erodes the discipline everywhere else it
  invokes it. Recorded rather than quietly corrected. This error also has a consequence: see R4
  (the self-heal property depends on this trigger set and does **not** hold as originally claimed).

---

## User-Brand Impact

**If this lands broken, the user experiences:** production frozen on v0.244.0 indefinitely — no
bug fix, no security patch, and no feature reaches app.soleur.ai. A worse failure mode is
available: if the re-delivery lands a *wrong* token, or a partial write leaves
`/etc/default/soleur-doppler-token` truncated, `webhook.service` fails to start and the deploy
webhook itself goes down — taking the *remediation channel* offline with it, which converts a
recoverable outage into one that needs a gated host replace.

**If this leaks, the user's data is exposed via:** the credential being moved is a
**full-`prd`-scope Doppler service token**. `soleur/prd` holds the Supabase service-role key, the
Resend key, the GitHub App private key, the webhook HMAC secret, and every registry credential. A
leak of this one value is a total production-secret compromise and therefore a total user-data
compromise. Concrete exposure vectors this plan must close by construction: (a) the token echoed
into a GitHub Actions log by an unmasked `terraform output` or a `set -x`; (b) the token in
`terraform plan` human-readable output; (c) the token on a process argv on the host (`ps`
readable); (d) the token written world-readable in `/etc/default/`; (e) the token in the pushed
JSON payload persisted to a temp file that is never removed.

**Brand-survival threshold:** `single-user incident`

Consequences of that threshold, per the plan skill: `requires_cpo_signoff: true` is set in
frontmatter; `user-impact-reviewer` is invoked at review time; plan-review escalates to include
`architecture-strategist` and `spec-flow-analyzer`; and the GDPR/compliance gate fires on
trigger (b) (see §Compliance).

---

## Architecture Decision (ADR/C4)

This plan makes an architectural decision and therefore owns the record. Both items below are
**in-scope tasks of this PR**, not follow-ups.

### ADR

1. **New: ADR-154 (provisional) — "Every boot-baked host credential must have a Terraform-owned
   re-delivery path and a continuous liveness probe."**
   Decision: a secret written into a host by `cloud-init` at first boot is a *write-once* artifact
   on a resource carrying `lifecycle { ignore_changes = [user_data] }`; it therefore has no
   convergence path and its rotation is undetectable. Any such credential must both (a) be
   delivered by a re-runnable, `triggers_replace`-hashed mechanism (a provisioner or the
   infra-config channel), **and** (b) be exercised by a continuously-running probe whose absence
   alarms. Alternatives considered: host replace on every rotation (rejected — `hcloud_server.web`
   replace is a gated birth path and web-1's `cx33` is unorderable in all three EU DCs,
   `model.c4:182`); accepting a manual re-bake (rejected —
   `hr-all-infrastructure-provisioning-servers`).
   **The ordinal is provisional.** Highest existing is ADR-153; `/ship`'s ADR-Ordinal Collision
   Gate re-verifies against `origin/main` before merge. On renumber, sweep
   `grep -rn 'ADR-154' knowledge-base/project/{plans,specs}/feat-one-shot-7095-host-pull-leg/`
   *and* every AC that names the ordinal.

2. **Amend: ADR-096 clause (f).** Its three enumerated uncovered causes are individually refuted
   here by measurement. Add a fourth, and record the falsification so it is not re-litigated:
   > (f-4) The mirror gate also does not prove the host can **read its own credential source**. If
   > the host's Doppler service token is revoked, `ZOT_REGISTRY_URL` reads empty,
   > `zot_gate_and_login` takes its dark branch, and zot is never contacted — producing
   > `image_pull_failed` with a *zot-shaped* reason string and a *credential-shaped* cause.
   > Measured 2026-07-30 (#7095).
   Also record the consequence: since the 2026-07-30 amendment made zot the sole pull path, the
   GHCR fall-through no longer *is* a fallback — it only mislabels the failure.

3. **Cross-reference ADR-088 / ADR-096** — no decision change; add the pointer that the GHCR arm's
   `auth_denied` is now a **misleading terminal**, not a degraded success.

### C4 views

**Completeness enumeration performed against all three model files**
(`knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4`, `spec.c4`;
592/62/54 lines) — not a keyword grep for the feature's own noun.

- **External human actors:** none added or changed. The `founder` relationship is unchanged; this
  plan *removes* operator steps rather than adding any.
- **External systems:** `doppler`, `github`, `cloudflare`, `ghcr`, `zotRegistry`, `betterstack`,
  `sentry` — **all already modeled** (`model.c4:238,262,266,287,294` and the `system`
  enumeration). No new external system is introduced.
- **Containers / data stores:** `hetzner`, `tunnel`, `inngest` — already modeled. No new store.
- **Access relationships that change:** two, and both need an edit.
  - `model.c4:433` — `doppler -> hetzner "Injects the web-host boot credential."` The description
    reads as a steady-state injection. It is a **one-time, first-boot write with no convergence
    path**, which is the whole content of this incident. Amend it to say so, and to record the
    post-fix state (a `triggers_replace`-hashed re-delivery path plus a liveness probe).
  - `model.c4:182` / `:178` — both assert the fleet is single-host and that web-2 is
    retired/unborn. **Falsified by live measurement** (E8). Correct both, and promote `:423`'s
    note that "infra-config does NOT fan out" from an incidental aside to an explicit
    *limitation* (it is why web-2 cannot be repaired by that channel).
- **`views.c4`:** no new element ⇒ no new `include` line required. Verify by running
  `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after the edit — a
  `view include` referencing an undefined element fails there, not at `tsc`.

### Sequencing

The ADR-154 decision is true **on merge** (the re-delivery path and the probe ship in the same
PR), so it is authored `status: accepted`, not `adopting`.

---

## Infrastructure (IaC)

### Terraform changes

| File | Change |
|---|---|
| `apps/web-platform/infra/server.tf` | Render `webhook-doppler-token.env.tmpl` into a `local.*`; add its base64 to `terraform_data.deploy_pipeline_fix`'s `environment {}`; add the rendered content **and** `var.doppler_token` into `triggers_replace` so a token rotation re-fires delivery; extend `terraform_data.journald_persistent` (or add a guarded sibling) so `vector.toml` reaches web-2. |
| `apps/web-platform/infra/webhook-doppler-token.env.tmpl` *(new)* | `DOPPLER_TOKEN=${doppler_token}` only. Deliberately **does not** set `DOPPLER_CONFIG_DIR` (see Sharp Edges — #6536). |
| `apps/web-platform/infra/webhook.service` | Add a second `EnvironmentFile=-/etc/default/soleur-doppler-token` **after** the existing entry (later-wins). The `-` prefix keeps a fresh host bootable before the first push. Add the new path to `ReadOnlyPaths`. |
| `apps/web-platform/infra/web-probe.tf` | `betteruptime_heartbeat.web_deploy_cred` (`for_each = var.web_hosts`) fed by the new credential probe, plus `doppler_secret.web_deploy_cred_url_*`. |
| `apps/web-platform/infra/sentry/cron-monitors.tf` | `sentry_cron_monitor` dead-man's switch for the new release-health watcher, so the watcher's own silence pages. |
| `apps/web-platform/infra/sentry/issue-alerts.tf` | Issue alert for the new `op:deploy-cred-dead`, `op:release-consecutive-failure`, `op:prod-stale` tags. **Pick an unused `frequency`** — the taken set is documented at `issue-alerts.tf:1216-1220`. |
| `.github/workflows/apply-web-platform-infra.yml` | Append `-target=` lines for every new resource above (the allow-list is hand-maintained; L428-431 documents the obligation). |
| `.github/workflows/apply-deploy-pipeline-fix.yml` | Add every Phase-2 file to its `paths:` filter, or the merge will not fire the apply. |

**Providers:** no new provider; version pins unchanged.
**Sensitive variables:** no new `TF_VAR_*`. `var.doppler_token` already exists and is already
provisioned in Doppler `prd_terraform` (E4 verified it authenticates), so this plan does **not**
trip `hr-tf-variable-no-operator-mint-default` or the "no-default var on an auto-applied root"
sequencing hazard.

### Apply path

**Chosen: (b) — the existing Terraform-driven, no-SSH infra-config push, applied on merge.**

`.github/workflows/apply-deploy-pipeline-fix.yml` fires on `pull_request_target: [closed]` for the
touched infra paths and runs
`terraform apply -target=terraform_data.deploy_pipeline_fix -target=terraform_data.infra_config_handler_bootstrap ...`.
`terraform_data.deploy_pipeline_fix`'s `local-exec` runs `push-infra-config.sh`, which POSTs the
HMAC-signed, CF-Access-authenticated payload to `https://deploy.soleur.ai/hooks/infra-config`.
The on-host handler writes the files atomically via the sudo-escalated
`infra-config-install.sh`, then reloads the unit definitions and schedules a **delayed
self-restart** of the webhook service (pre-existing code at `infra-config-apply.sh:259-270`) so
the HTTP 202 is returned before the restart tears down the server that is answering it.

- **Expected downtime:** ~3–8s of `deploy.soleur.ai` webhook unavailability during the
  self-restart. No app downtime — `app.soleur.ai` does not traverse this path (`model.c4:178`).
- **Blast radius:** web-1's webhook unit plus the four doppler-dependent timers. If the new
  `EnvironmentFile` is malformed, systemd tolerates a *missing* file (the `-` prefix) but **not**
  a syntactically invalid one — hence AC6/AC7.
- **Why not (c) `-replace`:** `hcloud_server.web["web-1"]` is a `cx33`, orderable in **0 of 3 EU
  DCs** (`model.c4:182`, #6460). Destroy-then-create cannot be recreated on its current type. A
  host replace here is not a remediation, it is a second outage.
- **Why not the `server.tf:564/615` provisioner pattern as primary:** it is a legitimate second
  option and is CI-runnable via the CF Tunnel bridge; it is the designated **fallback** if
  Phase 0.2 shows the infra-config channel is no longer alive. The webhook channel is preferred
  because it is (i) measured alive *after* the fault, (ii) content-asserted byte-for-byte by
  `infra-config-gate.sh`, and (iii) touches no SSH at all, keeping the resulting runbook SSH-free
  (`hr-no-ssh-fallback-in-runbooks`).
- **`hr-prod-host-config-change-immutable-redeploy` compliance:** this is a Terraform-owned,
  IaC-declared, content-asserted delivery — the same class as the existing `/etc/default/web-*`
  deliveries. It is *not* an in-place SSH/rescue edit, which is what that rule forbids. The plan
  additionally updates `cloud-init.yml` in the same commit so a future host birth and a running
  host converge on identical state.

### Distinctness / drift safeguards

- `dev != prd`: this change touches `soleur/prd` and `soleur/prd_terraform` only. No dev Supabase
  or dev Doppler config is read or written.
- `lifecycle.ignore_changes` callout: `hcloud_server.web` carries
  `ignore_changes = [user_data, ssh_keys, image, placement_group_id]`, so the `cloud-init.yml`
  edit in this PR is **inert on running hosts** and reaches only future births. That is exactly
  why the infra-config push is the operative half; the cloud-init edit is the convergence half.
  **Both are required**; shipping only one leaves a permanent divergence.
- `terraform.tfstate`: `triggers_replace` is a **`sha256(...)`**, so hashing `var.doppler_token`
  into it stores a digest, never the value. Do **not** put the raw token in `triggers_replace`.
- No new `doppler_secret` with `ignore_changes = [value]` is introduced. The new heartbeat URL
  secrets follow the existing `web-probe.tf:77-95` shape (TF-owned value, no `ignore_changes`).

### Vendor-tier reality check

`betteruptime_heartbeat` is available on the current Better Stack tier (six already exist and are
live). `betteruptime_policy` is **not** — every existing policy carries
`count = var.betterstack_paid_tier ? 1 : 0` and the flag defaults `false` (`variables.tf:472`).
The new heartbeat must therefore rely on `email = true` (the `web-probe.tf:26-46` shape), **not**
on a policy. Sentry is the independent second paging vendor and carries no tier gate for issue
alerts or cron monitors. No new recurring vendor expense.

---

## Downtime & Cutover

*Added by deepen-plan Phase 4.55, which **halted** the pass: the plan takes a serving surface
offline (a restart of the sole `deploy.soleur.ai` webhook listener — the deploy/router trigger
class) and had no zero-downtime evaluation. Recorded here rather than treating the restart as the
baseline.*

### The offline-inducing operations, named

| # | Operation | Surface | Duration |
|---|---|---|---|
| D1 | `infra-config-apply.sh:259-270` schedules a delayed self-restart of the webhook listener after writing a new `hooks.json` | `deploy.soleur.ai` — the **management plane** | ~3–8s |
| D2 | Restart of the log shipper to pick up its new `EnvironmentFile` (R2) | web-1 telemetry ingestion | seconds |
| D3 | Restart of the four cron/monitor timers to pick up theirs (R1) | already failing every 60s — a restart is strictly an improvement | n/a |

### Zero-downtime evaluation (the default, per the gate)

**D1 — user-facing downtime is ZERO by construction, and this is verified, not assumed.**
`app.soleur.ai` does **not** traverse the tunnel; it is a direct CF-proxied A record (`dns.tf`,
`model.c4:178`). The webhook listener serves only `/hooks/deploy`, `/hooks/deploy-status`,
`/hooks/infra-config` — the management plane. No user request is dropped by D1 at any point. The
residual is **control-plane** availability, which matters here only because the control plane *is*
the remediation channel (Sharp Edge 1b).

Zero-downtime paths considered for D1:
- **Avoid the restart entirely** — the strongest option, and R3 gets most of the way there by
  moving the credential override into `ci-deploy-wrapper.sh` so the *unit definition* never
  changes. **But it does not fully eliminate D1**: `hooks.json` must change in PR-A to carry the
  new payload key, and a changed `hooks.json` is precisely what the handler's self-restart exists
  to load. D1 is therefore **irreducible for PR-A**. Named, not wished away.
- **Drain-then-act** — rejected as unnecessary: the listener holds no long-lived connections, and
  D1 is scheduled by `systemd-run --on-active` *after* the HTTP 202 is returned, so no request is
  cut mid-flight.
- **Blue-green a second listener** — rejected as disproportionate: a second port, a tunnel ingress
  change and a router cutover, to remove a 3–8s management-plane blip that costs no user request.

**Accepted residual for D1: ~3–8s of `deploy.soleur.ai` unavailability; no maintenance window and
no operator sign-off required** — the affected surface is the management plane, not a user-serving
one, and the blip is self-recovering (`Restart=on-failure`). What is **not** accepted is the
restart *failing*, which is a different risk with its own mitigations (R3.1–R3.4: plan-time regex
validation on the TF variable, installer-side env-file shape rejection, `systemd-analyze verify`
before scheduling, and a dead-man revert armed beforehand).

**D2 — stage it after D1, never with it.** Restarting the log shipper is the one operation that
blinds the instrument the rest of the cutover is verified through. Sequence: land the credential
file → verify via the status endpoint (which does not depend on the shipper) → *then* restart the
shipper → assert rows resume (A5.4's positive control). This restart is **not** optional deferral:
per H7c the shipper is already one restart away from a crash-loop, so a *controlled* restart under
observation is strictly safer than the uncontrolled one a reboot would cause.

**D3 — no cutover concern.** Those units fail every 60s already; a restart cannot make the surface
worse.

### Cutover ordering (the part that actually bites)

**R23 is a cutover-ordering defect, not merely an AC problem.** The merge fires
`web-platform-release.yml` and `apply-deploy-pipeline-fix.yml` **concurrently** — the
`terraform-apply-web-platform-host` concurrency group serializes the apply against
`apply-web-platform-infra.yml` only, **not** against the release. Without ordering, the deploy leg
runs before the credential exists and produces a ninth consecutive failure *caused by the fix
merge itself*. Required ordering:

1. Apply lands the credential file (payload 1) → verify via `/hooks/infra-config-status`.
2. Apply lands the `hooks.json`/unit change (payload 2) → `systemd-analyze verify` → self-restart.
3. **The apply's own post-apply redeploy** (`apply-deploy-pipeline-fix.yml:526`, gated on
   `reason ∈ {ok, ok_peer_fanout_degraded}`) is the cutover proof — **not** "the next release".
4. Only then is the concurrent release run's outcome meaningful. A failure before step 3 is
   *expected* and must not be read as a regression — nor counted by the new watcher (R30).

### Rollback

Per-stage, and genuinely available: the credential file is additive (removing it returns the host
to exactly today's broken-but-stable state), the wrapper change is a single guarded `source` line,
and every unit change is a drop-in that can be deleted. **Irreversible-operation count: zero.** No
migration, no data transformation, no host replace — the last not merely avoided but *impossible*
(Sharp Edge 7: `cx33`, orderable in 0 of 3 EU DCs), which is precisely why every operation above
had to be in-place and reversible.

---

## Observability

```yaml
liveness_signal:
  what: >
    SOLEUR_DEPLOY_CRED marker + a Better Stack heartbeat ping, emitted by a new
    `web-deploy-cred-probe` timer on EVERY web host. The probe sources the deploy credential
    exactly as ci-deploy.sh does and performs one real read
    (`doppler secrets get ZOT_REGISTRY_URL --plain -p soleur -c prd`). Non-empty => ping +
    `SOLEUR_DEPLOY_CRED ok=1`; empty/error => SUPPRESS the ping and emit
    `SOLEUR_DEPLOY_CRED ok=0 rc=<n> class=<enum>` loudly. Absence of ping alarms.
  cadence: every 300s (AccuracySec pinned to 1s, well inside the monitor deadline — #6537)
  alert_target: >
    betteruptime_heartbeat.web_deploy_cred[<host>] (period 900 / grace 300, email = true)
    AND the Sentry issue alert on tag op:deploy-cred-dead
  configured_in: >
    apps/web-platform/infra/web-deploy-cred-probe.{sh,service,timer};
    apps/web-platform/infra/web-probe.tf (heartbeat + doppler_secret URL);
    apps/web-platform/infra/vector.toml (Source-4 SYSLOG_IDENTIFIER allowlist)

error_reporting:
  destination: >
    Sentry (structured event, tags: feature=supply-chain, op=deploy-cred-dead, host_id,
    doppler_rc, doppler_class) + Better Stack Logs via Vector Source 4
    (SyslogIdentifier=web-deploy-cred-probe) + the deploy-status JSON reason enum.
  fail_loud: >
    YES, and this is the crux of the incident. ci-deploy.sh currently degrades a revoked
    credential into `GHCR path (dark, pre-provisioning)` and then into `auth_denied`. After
    this change a present-but-non-functional DOPPLER_TOKEN is a TERMINAL, DISTINCT failure:
    reason=`doppler_read_failed`, never `image_pull_failed`.

failure_modes:
  - mode: Host Doppler service token revoked / rotated out from under the host (THIS incident)
    detection: >
      IN-SURFACE. web-deploy-cred-probe runs ON the affected host under the affected
      credential and reports ok=0 with doppler's real rc plus a classified error enum within
      5 minutes. Independently, ci-deploy.sh emits SOLEUR_DEPLOY_CRED_FAIL with the same
      fields on the very next deploy and aborts with reason=doppler_read_failed.
    alert_route: >
      Better Stack heartbeat absence (email to ops@jikigai.com) + Sentry issue alert
      op:deploy-cred-dead. Neither requires SSH.
  - mode: Doppler API unreachable from the host (egress firewall / DNS / vendor outage)
    detection: >
      Same probe, different classified enum (`network` vs `auth`), derived from doppler's
      exit code plus a closed-vocabulary stderr keyword class. The two are DISCRIMINATED IN
      ONE EVENT — this is the field set that would have decided H7 vs H8 on day one.
    alert_route: same heartbeat + Sentry, with the class carried as a tag.
  - mode: /tmp/.doppler ownership clash (#6536 recurrence)
    detection: >
      Third enum value (`config_dir`) keyed off doppler's permission-denied stderr class,
      plus the probe emits the effective HOME and DOPPLER_CONFIG_DIR it ran under.
    alert_route: same.
  - mode: infra-config re-delivery silently no-ops (the #4804/#6594 latched-false-green class)
    detection: >
      infra-config-gate.sh content assertion — host-reported sha256 per delivered file compared
      byte-for-byte against the repo file, plus files_written == files_total and
      files_failed == 0. Already implemented; this plan extends it to the new file and updates
      the template-exclusion count invariant.
    alert_route: the apply workflow goes RED. No silent success is possible.
  - mode: N consecutive Web Platform Release failures / prod serving a version behind the latest tag
    detection: >
      New scheduled-release-health.yml watcher: `gh run list --workflow=web-platform-release.yml`
      leading-failure count, AND `curl https://app.soleur.ai/health | jq .version` compared to
      the newest `web-v*` tag. Cadence-free (a quiet weekend produces no new tag, hence no page).
    alert_route: >
      label-deduped P1 GitHub issue (ops/prod-stale, the main-health-monitor.yml pattern) plus a
      Sentry event tagged op:prod-stale, which routes to the existing email action.
  - mode: The watcher itself stops running (reporter death)
    detection: sentry_cron_monitor dead-man's switch on the watcher's own check-in.
    alert_route: Sentry issue on missed check-in. The reporter is not its own subject.
  - mode: web-2 fails a deploy while web-1 succeeds (peer-leg divergence)
    detection: >
      vector.toml delivered to web-2 so its ci-deploy and webhook identifiers reach Better
      Stack; plus per-host attribution from the existing web-N.app.soleur.ai/health origin
      probes (model.c4:287).
    alert_route: same Sentry / Better Stack routes, with host_name attribution.

logs:
  where: >
    Better Stack Logs source 2457081 (ClickHouse warehouse,
    remote(t520508_soleur_inngest_vector_prd_3_logs) UNION the s3 archive), queried by
    scripts/betterstack-query.sh. Sentry org jikigai-eu (DE ingest).
  retention: >
    Better Stack free tier: 3-day hot+archive retention (documented in
    knowledge-base/engineering/operations/post-mortems/betterstack-quota-near-miss-postmortem.md;
    NOT declared in Terraform). On-host journal bounded by journald-soleur.conf (SystemMaxUse=1G).
    CONSEQUENCE THIS PLAN RESPECTS: a fault older than 3 days is unreconstructable, which is why
    the probe cadence (5 min) and the watcher cadence (2h) are both far inside the window, and
    why the evidence above is transcribed verbatim into this plan rather than cited by query.

discoverability_test:
  command: |
    # 1. Is the deploy credential alive on every web host? (no ssh)
    doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
      --since 1h --grep SOLEUR_DEPLOY_CRED --limit 50
    # 2. Did the last deploy contact zot, or take the dark branch?
    doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
      --since 24h --grep ZOT_GATE --grep IMAGE_PULL --limit 50
    # 3. Is prod on the latest release?
    curl -s https://app.soleur.ai/health | jq -r '.version, .build_sha, .uptime'
  expected_output: |
    1. >= 12 rows/hour/host of `SOLEUR_DEPLOY_CRED ok=1 host=<...>`; ZERO rows with ok=0.
       Rows present for BOTH host_name=soleur-web-platform AND host_name=soleur-web-2.
    2. `ZOT_GATE: active — docker login 10.0.1.30:5000 ok (zot-primary)` followed by
       `IMAGE_PULL_OK: registry=zot image=web tag=v<latest>`. The string
       "dark, pre-provisioning" MUST NOT appear.
    3. .version equals the newest `web-v*` tag; .uptime is small (recent swap).
```

**Affected-surface note (§2.9.2).** `ci-deploy.sh` runs inside the webhook service's mount
namespace (`ProtectSystem=strict`, `PrivateTmp=true`) — an execution surface the operator cannot
inspect without SSH, and one where host-side reasoning is provably wrong (E6). The
`SOLEUR_DEPLOY_CRED` marker is therefore emitted **from inside that namespace**, and its field set
(`ok`, `rc`, `class`, `home`, `config_dir`, `host_id`) discriminates **all** the competing
hypotheses (H7 auth vs H8 config-dir vs network) **in a single event**, rather than being a
boolean that fires for only one shape.

---

## Encryption Posture

Detection fires (`\.tf$` and `cloud-init.*\.ya?ml$` in Files to Edit). No new persistent store is
introduced; one existing cross-component connection carries new content.

```yaml
at_rest:
  - store: /etc/default/soleur-doppler-token (new file, web-1 + web-2 root filesystem)
    mechanism: plaintext-exception (filesystem permissions only)
    evidence: >
      Delivered mode 0640 owner root:deploy by infra-config-install.sh's DEST_SPEC — the same
      shape as the existing /etc/webhook/hooks.json entry, which already carries the webhook
      HMAC secret. The Hetzner root volume is unencrypted ext4; the workspaces-volume LUKS
      apparatus (ADR-119) does not cover /.
    defends_against: >
      Non-root local users on the host; the `deploy` user reads but cannot write it; processes
      outside the webhook unit's namespace cannot reach it via that unit.
    does_not_defend: >
      Root compromise on web-1/web-2; Hetzner-side disk seizure or snapshot exfiltration; a
      backup of the root volume. This is the SAME exposure /etc/default/webhook-deploy already
      has — the plan adds no NEW at-rest exposure class, it splits one file into two with
      identical protection.
    disclosed_as: >
      No user personal data. Credential material only. Not an Art. 30 processing activity;
      relevant to Art. 32(1)(b) integrity/confidentiality of the processing environment.
    live_verification: >
      infra-config-gate.sh content assertion (sha256 match) plus the delivered mode/owner
      recorded in the /hooks/infra-config-status JSON, readable with no SSH.
  - store: terraform.tfstate (encrypted R2 backend)
    mechanism: provider-managed at rest (R2 SSE) + the value is NEVER stored
    evidence: >
      triggers_replace stores sha256(...) of the rendered content, not the content.
      var.doppler_token is an input variable, not a resource attribute, so it does not land in
      state as a stored value.
    defends_against: state-file exfiltration revealing the token.
    does_not_defend: >
      An apply run whose logs are captured — hence the masking AC below.
    disclosed_as: n/a
    live_verification: >
      AC17 asserts triggers_replace is a sha256 expression and that no `set -x` exists on the
      push path.

in_transit:
  - connection: CI runner (GitHub Actions) -> https://deploy.soleur.ai/hooks/infra-config
    tls: TLS 1.3 via the Cloudflare edge
    cert_verification: on (curl default; no -k anywhere in push-infra-config.sh)
    does_not_defend: >
      Cloudflare is a trusted intermediary and terminates TLS, so CF can read the payload. This
      is the SAME trust boundary already used for hooks.json, which carries the webhook HMAC
      secret. No new intermediary is introduced.
    disclosed_as: Art. 30 sub-processor Cloudflare, already recorded.
  - connection: web host -> api.doppler.com (secret reads)
    tls: TLS 1.2+ (doppler CLI default)
    cert_verification: on
    does_not_defend: Doppler as controller of the secret material (already disclosed).
    disclosed_as: existing.

exception:
  - store: /etc/default/soleur-doppler-token
    justification: >
      A systemd EnvironmentFile must be readable as plaintext by the init system at unit start;
      there is no at-rest encryption option for this delivery shape short of a sealed-secret
      agent, which the fleet does not run. The pre-existing /etc/default/webhook-deploy has the
      identical posture, so this is continuity, not regression.
    tracking_issue: >
      To be filed at /work: "host credential files are plaintext on an unencrypted root volume".
      The correct long-term answer is SCOPING (least-privilege per-unit tokens, the
      doppler_service_token.web_probes pattern) rather than at-rest encryption. §Alternatives
      records that re-scoping the deploy token down from full-prd is deliberately OUT of scope
      for this P1 fix.
    reevaluate_when: >
      The fleet gains a sealed-secret/agent mechanism, OR the deploy path is re-scoped to a
      least-privilege token (the tracking issue above).
    expires_on: 2026-10-31
```

---

## PR Split (revised after plan-review)

The single-PR shape was wrong, and the reviewer panel was unanimous on the reason: **the PR that
can take the remediation channel offline should be the smallest PR possible.** Phase 2 restarts
the webhook unit through the webhook, on a host with no SSH runbook and no orderable replacement.
Carrying 33 file touches on that PR adds failure surface to an outage fix for zero benefit *to the
outage fix*. It also couples the credential delivery to a **second** apply
(`apply-web-platform-infra.yml`, whose `-target=` allow-list is hand-maintained and whose omission
is silent) when the fix only needs `apply-deploy-pipeline-fix.yml`.

| | PR-A — restore prod | PR-B — harden |
|---|---|---|
| **Scope** | Phase 0 (all — it is diagnosis, no writes), Phase 1.2/1.3/1.3b, Phase 2 (all, incl. 2.0 probe), Phase 5.5, Phase 6.4, Phase 7.1–7.3 | Phase 1.5, Phase 3, Phase 4, Phase 5.1/5.2/5.4, Phase 6.1/6.2/6.3, ADR-154, the `model.c4` corrections |
| **Footprint** | ~13 file touches, 1 created | the remainder |
| **Applies via** | `apply-deploy-pipeline-fix.yml` only | `apply-web-platform-infra.yml` + `apply-sentry-infra.yml` |
| **Gate** | AC25 (a real deploy reaches prod) | the hardening ACs |

`## Acceptance Criteria` is annotated per-AC with its PR. **AC18 ("full infra suite green including
the seven orphan suites") is explicitly demoted to PR-B** — making an unrelated pre-existing red
suite a merge blocker during an outage is a self-inflicted gate.

**What does NOT move to PR-B:** the diagnosis (§Root Cause Evidence, §Hypotheses) and Phase 0.
Phase 0 is entirely read-only and its findings gate PR-A's design.

---

## Plan Review Revisions (R1–R20) — SUPERSEDING

> **Read this before the phases.** A five-agent panel (architecture-strategist, spec-flow-analyzer,
> code-simplicity-reviewer, cto/devex, plus a scoped strong-model consult) reviewed the draft.
> Where a revision below conflicts with the phase text that follows, **the revision wins.** Several
> findings falsified premises the draft was built on, including one of the plan's own
> premise-validation claims (R10) and its central self-heal claim (R4).

### The single most important structural change

**R0 — SPLIT INTO TWO PRs.** Three reviewers converged on this independently.

| | Contents | Rationale |
|---|---|---|
| **PR-A — restore production** | R1, R2, R3 (the credential path: the tmpl, `FILE_MAP`/`DEST_SPEC`, the wrapper-based override, the four unit edits/drop-ins, the vector drop-in), the minimum Phase-1.2 change so the dark branch stops lying, Phase 5.5, Phase 6.4, Phase 7.1–7.3 | The PR that can take the remediation channel offline (Sharp Edge 1b) must be as small as possible. It currently carries ~33 file touches. |
| **PR-B — harden** | `doppler_read_failed` terminal reason, Phase 1.5, Phase 3's generalisation, Phase 4, Phase 5.1–5.4, Phase 6.1–6.3, ADR-154, the C4 edits | None of it is required for prod to deploy. All of it is real. |

Two mechanical reasons beyond caution: (i) PR-A lands via `apply-deploy-pipeline-fix.yml`
(paths-filtered) while Phase 4/5's Terraform lands via `apply-web-platform-infra.yml`
(hand-maintained `-target=` allow-list whose omission is **silent**) — coupling the credential
delivery to a second, silently-failing apply adds a failure mode to the outage fix for zero
benefit; (ii) AC18 ("full infra suite green incl. the seven orphan suites") makes an unrelated
pre-existing red a P1 merge blocker. **Also note the phase-ordering argument in the draft was
inert**: "diagnostics before remediation" is not a property of a single PR — both land in the same
commit at the same instant. The ordering argument is an argument *for* two PRs.

### P0 — merge-blocking

- **R1 — The remediation was aimed at the wrong file for four of five broken consumers.**
  `cron-egress-resolve.service:19`, `cron-egress-alarm@.service:10`,
  `container-restart-monitor.service:14` and the generated `inngest-heartbeat.service`
  (`inngest-bootstrap.sh:315`) read `EnvironmentFile=-/etc/default/inngest-server` — which holds a
  **copy** of the same token (`inngest-bootstrap.sh:586`). As drafted, `webhook.service`/ci-deploy
  recovers, AC25 goes green, and four units stay red — **a false green baked into the plan's own
  observability**. Not a legitimate defer: each is one line, and the delivery channels already
  exist.
  | Unit | Edit | Vehicle (already exists) |
  |---|---|---|
  | `cron-egress-resolve.service`, `cron-egress-alarm@.service` | add `EnvironmentFile=-/etc/default/soleur-doppler-token` **after** the inngest-server line | `terraform_data.cron_egress_firewall` (`server.tf:1513`) — `file()`-hashed, auto-refires |
  | `container-restart-monitor.service` | same one-line add | `terraform_data.container_restart_monitor_install` (`server.tf:442`) |
  | `inngest-heartbeat.service` (heredoc, not a repo file) | push a drop-in `/etc/systemd/system/inngest-heartbeat.service.d/10-doppler-token.conf` | new `terraform_data` sibling, **or** a FILE_MAP entry — **blocker if FILE_MAP:** `infra-config-install.sh:110-131` does `mktemp "${dest_dir}/…"` and never `mkdir -p`, so a drop-in *directory* dest fails; add a guarded `mkdir -p` for allow-listed dests |
  **Do NOT rewrite `/etc/default/inngest-server` wholesale** — `inngest-bootstrap.sh:616-617`
  fail-closes the host if `DOPPLER_PROJECT=` goes missing, and per Sharp Edge 7 a host replace is
  impossible. Second file + later-wins is the only safe shape there.
  **Also correct §Alternatives:** it rejected "a unit drop-in directory" on the grounds that *"the
  other consumers read the file"* — inverted. They read it **via `EnvironmentFile=`**, which is
  exactly what a drop-in overrides. The correct mechanism was rejected on a false statement of fact.

- **R2 — `vector.service` runs on the dead credential, and it is the instrument every post-merge
  AC is read through.** See H7c. Deliver
  `/etc/systemd/system/vector.service.d/10-doppler-token.conf` **in PR-A**, ahead of the alerting
  phases. A latent total-telemetry blackout on the next reboot outranks every hardening item here.

- **R3 — A strictly-safer design than either Design S or Design T: never modify `webhook.service`
  at all.** Put `[[ -r /etc/default/soleur-doppler-token ]] && . /etc/default/soleur-doppler-token`
  in **`ci-deploy-wrapper.sh`** — already `FILE_MAP` → `/usr/local/bin/ci-deploy-wrapper.sh|755|root:root`.
  The unit definition then never changes, so **the self-restart cannot fail to start**; worst case
  is a bad token and a failed deploy, with the remediation channel alive. This supersedes Phase
  2.0's S-vs-T probe *for the deploy leg* (keep `EnvironmentFile=` additions only where genuinely
  needed — the four units in R1 and vector, none of which is the remediation channel).
  Three more layers, in value order:
  1. `variable "doppler_token" { validation { condition = can(regex("^dp\\.st\\.", var.doppler_token)) } }`
     — fails at `terraform plan`, before a byte reaches the host. This is the "provably
     non-bricking before it lands" answer.
  2. `infra-config-install.sh`: for `/etc/default/*` dests, reject unless every non-blank line
     matches `^[A-Za-z_][A-Za-z0-9_]*=` (`reject "envfile_shape"`). Refuse-to-install beats
     install-and-brick.
  3. `infra-config-apply.sh:265-270`: insert `systemd-analyze verify` before scheduling the
     self-restart, so a bad unit leaves the running in-memory unit untouched and reds CI instead.
  4. **Pre-merge proof, not just ACs:** a systemd-in-container rehearsal (`TEST_DESTDIR` +
     `systemd-analyze verify`), reusing the `fresh-boot-parity.test.sh` / rung-2 rehearsal
     precedent. That is the difference between "we believe it won't brick" and "we ran it".
  Note also: the `-` prefix covers *absent*, not *empty-valued*. A `DOPPLER_TOKEN=` empty render
  wins by later-wins and silently blanks the credential. R3.1's regex validation closes this.

- **R4 — The plan's central "the next rotation self-heals" claim is FALSE as drafted.**
  `triggers_replace` is only consulted when Terraform runs, and `apply-deploy-pipeline-fix.yml:62-64`
  is `on: push` + `paths:` + `workflow_dispatch` — **no `schedule:`**. A Doppler-only rotation
  changes zero repo paths, so nothing ever evaluates the hash. Additionally, an out-of-band
  rotation (exactly what happened at 11:19:30Z) does not update `soleur/prd_terraform` either.
  **Remedy:** add `schedule: - cron: "0 */12 * * *"` to that workflow, **and** state plainly in
  ADR-154 that the self-heal property holds only for rotations that write back to
  `soleur/prd_terraform`. Without both, Phase 4's probe is a pager, not a healer, and ADR-154's
  own clause (a) is unsatisfied by its reference implementation.

- **R5 — The Sentry alert route is dead for exactly the incident class it was built for.**
  `ci-deploy.sh` hydrates `SENTRY_INGEST_DOMAIN` / `SENTRY_PROJECT_ID` / `SENTRY_PUBLIC_KEY`
  **from Doppler, using the same token**, and every emitter is guarded on those being non-empty.
  Under a revoked token: **zero Sentry events.** Same for `container-restart-monitor.service`.
  This is why 341 unit failures produced no page, and it silently collapses the plan's
  two-vendor independence story to one vendor. **Remedy:** bake the three DSN params into the
  Terraform-rendered env file alongside `DOPPLER_TOKEN` and prefer the baked values over the
  Doppler prefetch — exact precedent: `server.tf` already bakes `BETTERSTACK_INGEST_URL` into
  `/etc/default/web-private-nic-guard` for this same reason. They are public DSN components, so
  this adds no exposure class. **New AC:** with `doppler` stubbed to fail, a Sentry POST is still
  attempted.

- **R6 — `infra-config-gate.sh` EXCLUDES `.tmpl`-backed dests from the sha256 comparison.** So
  Phase 2.6's `1 → 2` bump would **remove** the credential file from content checking, while
  §Apply path claims "content-asserted byte-for-byte" and AC23 asserts a matching sha256. The file
  that matters most would get the least verification — the exact latched-false-green class of
  Sharp Edge 4. **Remedy:** extend the gate to compare `host_sha` against the sha256 of the
  **rendered payload** the workflow already holds (decode `WEBHOOK_DOPPLER_TOKEN_B64`), not
  against a repo file. Do the same for `hooks.json`.

### P1

- **R7 — `§Files to Edit` is incomplete; parity guards will red the PR.** Adding a `.tmpl` to
  `triggers_replace`/`FILE_MAP` requires lockstep edits to
  `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` (`TRIGGER_FILES`, 19 entries),
  `plugins/soleur/skills/ship/SKILL.md` (`DEPLOY_PIPELINE_FIX_TRIGGERS` array + `DPF_REGEX`), and
  `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` — all three named as
  lockstep obligations at `server.tf:1291-1330`. Also `cron-egress-firewall.test.sh:467` pins
  `EnvironmentFile=-/etc/default/inngest-server` and needs the new assertion **added, not
  replaced**. Add all five to `§Files to Edit`.
- **R8 — Two renderings, no guard.** Phase 2.1 renders the `.tmpl`; Phase 2.8 hand-writes "the
  same" content via `printf` in `cloud-init.yml`. Nothing compares them, and the existing
  `webhook-deploy` printf already shows the divergence pattern (`600 deploy:deploy` there vs
  `640 root:deploy` in the new `DEST_SPEC` — **and that mode change is undiscussed; state the
  rationale inline: `webhook.service` runs as `deploy`, so group-read is required**).
  **Remedy — make drift structurally impossible:** render once in `server.tf` and inject the
  string into `cloud-init.yml` via `templatefile(..., { doppler_token_env_file = local.… })`.
  One source, zero drift, no test needed.
- **R9 — web-2 is not "missing vector.toml"; it is an unmanaged host serving production.**
  `grep -c 'hcloud_server.web\["web-1"\]' server.tf` → **19**. Every host installer is pinned to
  web-1. Consequences: (i) the finding belongs in ADR-154 (or a sibling) as *"every host-config
  `terraform_data` must be `for_each`-keyed over `var.web_hosts`, not pinned to web-1"*, with a
  follow-up issue for the other 18; (ii) **pre-decide Phase 3.2 as option (b)** — a guarded
  `terraform_data` sibling with `connection.host = hcloud_server.web["web-2"]` — because option
  (a) invents a new full-`prd`-credential transit path under P1 time pressure and widens what a
  compromised web-1 handler can do; (iii) **drop the blanket "no SSH" claim** — it is true for
  web-1 only. (Still compliant: Terraform-CI SSH is not an operator runbook step. But the plan
  must not assert a property it does not have.)
- **R10 — see §Premise Validation.** The `pull_request_target: [closed]` citation was wrong.
- **R11 — AC11 as written mechanically prescribes adding `server.tf` to the `paths:` filter**,
  which would make **every** `server.tf` edit auto-write production. Scope AC11 to host-delivered
  artifacts (the new `.tmpl`) and note that `server.tf` is deliberately excluded, as today.
- **R12 — the release-health watcher is on the wrong substrate.** `cron-terraform-drift.ts`
  documents GitHub scheduled-workflow jitter **up to 339 minutes late over a 58-day survey**,
  which forced a 480-min Sentry margin. A 2h cadence cannot carry that margin, so the monitor is
  structurally either noisy (false MISSED pages) or useless. Every false page is an unactionable
  email to a non-technical founder, and alert fatigue is the failure mode that let this incident
  run 26h. **Remedy:** the established **dispatch-hybrid** — an Inngest cron (`≤2-min` jitter)
  holding only a short-lived `actions: write` token fires `workflow_dispatch`; execution and
  credentials stay in the ephemeral runner; margin tightens to 60. The draft's rejection of
  Inngest ("needs a GitHub token on the host") misread the precedent. Correct the §Alternatives row.
  Also: §5.2's "label-deduped P1 GitHub issue" is **not a page** — route it through the same
  Resend email path as §5.5.
- **R13 — the staleness threshold is miscalibrated.** A `> 2h` staleness window on a 2h cron
  guarantees up to **4h** of real staleness before the first page. Likewise `period = 900 /
  grace = 300` against a 300s cadence (2 missed beats) and the `>= 2` consecutive threshold are
  unjustified magic numbers — 5.5 fires on the *first* failure, so state why 2 is right or drop it.

### P2

- **R14 — ADR-154 must cover credential *copies*, not just boot-baked originals.** The invariant
  this incident actually teaches, and the one that would have caught the four dark units, is:
  *"No secret may be copied into a second host file without the copy inheriting the original's
  re-delivery path."* `/etc/default/inngest-server` is a derived copy pinned forever by
  `inngest-bootstrap.sh:567`. (This also answers the n=1 objection to ADR-154: the evidence base
  is E9's nine files across two classes plus this copy mechanism, not one data point.)
- **R15 — Phase 4's probe must source the same file set as each subject it claims to cover**, or
  split into two probes (webhook leg / inngest-server leg). As drafted it monitors one credential
  path and is cited as evidence for five.
- **R16 — retarget the parity guard.** AC4 targets `FILE_MAP`↔`DEST_SPEC`, which is **already
  guarded** — `infra-config-install.sh` rejects `dest_not_allowlisted`/`mode_mismatch`/`owner_mismatch`
  at delivery, fail-loud. The pair that rots **silently** is *a new `betteruptime_heartbeat`
  without a matching `arm_one` line* in `apply-web-platform-infra.yml`: no `arm_one` ⇒
  `paused = true` + `ignore_changes = [paused]` ⇒ paused forever, green-but-inert, surfacing only
  via a 12h reconcile job that **emails the operator**. Write that guard instead. (Moot if R17 is
  taken — which is the point.)
- **R17 — drop the new `betteruptime_heartbeat` entirely.** It buys "the probe stopped running",
  already covered on the same host and timer subsystem by `web_zot_consumer` + `web_nic_guard`.
  It costs a `web-probe.tf` resource, a `doppler_secret`, a manifest row, a `-target=` line, an
  `arm_one` line, and a permanent row in the 12h reconcile's purview. The signal that matters —
  `SOLEUR_DEPLOY_CRED ok=0 rc=… empty=…` — is **affirmative and diagnostic**, strictly better than
  heartbeat absence. Route it through the Vector Source-4 line (which survives the fault) plus the
  Sentry alert (once R5 is fixed). This also dissolves an **arming-order hazard**: `arm_one` fails
  the apply if no beat lands within `period + grace − 10`; the two apply workflows share a
  concurrency group with **no guaranteed ordering**, so an infra apply that arms before the
  credential lands would correctly suppress the ping and **fail the P1 fix merge red**.
- **R18 — Phase 4's probe had no delivery vehicle named, and none at all for web-2.** Adding files
  to the image-baked set changes the combined content hash injected into `user_data` and
  re-verified at boot — a mismatch **aborts the boot loudly**. Name the vehicle in
  §Infrastructure; and either scope AC24 to web-1 (web-2 deferred to R9's tracking issue) or
  extend the web-2 provisioner to carry the probe.
- **R19 — durable diagnosability.** Better Stack retention is 3 days, so for anything older than
  72h **Sentry is the only durable layer** — which makes R5 the difference between "diagnosable in
  six months" and "not". Two additions: add `home` and `config_dir` to the Sentry field set (the
  H7a-vs-H8 discriminators, currently omitted), and have the watcher's `ops/prod-stale` issue body
  **embed the last `SOLEUR_DEPLOY_CRED` and `ZOT_GATE` lines at fire time** — transcribing the
  3-day evidence into a permanent artifact automatically, the same discipline §Root Cause Evidence
  applied by hand.
- **R20 — AC cuts (ceremony, not post-conditions).** Cut or fold: AC2 (fold into AC1), AC3
  (greps a string you just typed), AC6 (line-number assertion to verify systemd's documented
  semantics), AC9 + AC19 (that is CI), AC18 (turns unrelated pre-existing red into a P1 blocker),
  AC20 (a link-checker for the plan document, not a shipped artifact), AC21 (a workflow gate, not
  an AC), AC26 (blocks close on a 2h cron to assert a negative), AC12/AC13 (die with R17/5.3).
  **Keep and prioritise AC10 + AC11** — an omitted `-target=` or `paths:` entry fails *silently*,
  which is the exact bug class that produced this outage.
  Also cut **Phase 7.4** — it verifies an environment reviewer set "if the final cutover requires a
  gated `workflow_dispatch`", a path the plan elsewhere asserts does not exist ("zero operator
  steps"). Confirmed: the apply job carries an explicit "No `environment:` reviewer gate. PR #4220
  removed it".

### R21–R35 — flow-gap review (second block; all NEW findings)

**P0 — each of these makes the merge run fail with the token undelivered.**

- **R21 — THE FILENAME REDS THE GATE AND BLOCKS THE ENTIRE APPLY.**
  `infra_config_classify_files` (`infra-config-gate.sh:46-62`) derives a dest's class from
  **`basename(dest)`**: for dest `/etc/default/soleur-doppler-token` it looks for
  `<infra_dir>/soleur-doppler-token` **or** `soleur-doppler-token.tmpl`. The draft named the file
  `webhook-doppler-token.env.tmpl` — **neither exists** ⇒ class `missing` ⇒
  `content_gate_repo_file_missing`, rc=1 ⇒ merge apply red, token never lands. `template_count`
  also stays at 1, so AC5's `-ne 2` change fails too.
  **Fix:** rename to `apps/web-platform/infra/soleur-doppler-token.tmpl` (basename-of-dest +
  `.tmpl`). Update Phase 2.1, AC7, §Files to Create, §Infrastructure. *This is the single
  highest-value catch in the entire review: the plan as drafted could not have worked.*

- **R22 — the FIRST apply is guaranteed to fail, and nothing re-applies (#4804 recurrence).**
  The host's `hooks.json` is stale and therefore cannot pass the new `soleur_doppler_token_b64`
  key, so the handler records `missing_env` for the new dest (`infra-config-apply.sh:105-115`) →
  `exit_code=1`. The verify step (`apply-deploy-pipeline-fix.yml:401-520`) only re-**polls the
  same state**; it never re-POSTs. Documented recovery is a `workflow_dispatch` re-run — **an
  operator step, in a plan that asserts zero.** AC22 and Phase 7.1 cannot pass on the merge run.
  **Fix:** run a second `terraform apply` + verify pass inside the same job (the new `hooks.json`
  is active by then), record the first pass's `missing_env` as **expected**, and restate AC22
  against the second pass.

- **R23 — the merge fires the release and the apply concurrently, and the release loses.**
  This PR touches `apps/web-platform/**`, which is `web-platform-release.yml`'s push path filter,
  so both workflows trigger on the same push. The `terraform-apply-web-platform-host` concurrency
  group serializes the apply against `apply-web-platform-infra.yml` **only — not the release**. So
  `deploy` very likely runs *before* the credential file exists → **a ninth consecutive failure
  immediately after merging the fix**, plus a false page from the brand-new watcher on its first
  run. Phase 7.3's "let the next release run" never names this.
  **Fix:** make the apply workflow's **own post-apply redeploy** the subject of AC25 —
  `apply-deploy-pipeline-fix.yml:526` already redeploys and gates on `case "$REASON"` accepting
  only `ok|ok_peer_fanout_degraded` (`:758-772`). Require a `workflow_dispatch` re-release only if
  that step fails.

- **R24 — Phase 4's probe had no delivery mechanism at all** (independent confirmation of R18):
  `web-deploy-cred-probe.*` appears in §Files to Create and **nowhere else** — no `FILE_MAP`/
  `DEST_SPEC` row, no `hooks.json.tmpl` entry, no `push-infra-config.sh` payload key, no `paths:`
  entry, no `server.tf` provisioner. AC24 asserted rows that could never appear. Largely moot
  under R17/4.1's reuse of the existing probe, but the *lesson* stands: **a file in §Files to
  Create with no row in §Files to Edit that installs it is a dead artifact.** Apply that check to
  every remaining created file.

**P1**

- **R25 — Phase 1.3 flips a documented fail-OPEN contract to fail-CLOSED without scoping it.**
  `zot_gate_and_login` is annotated *"Fail-open: never aborts the deploy"* (`ci-deploy.sh:1344`).
  Making `doppler_read_failed` terminal for **all** failure shapes means a transient Doppler blip
  hard-aborts every deploy, and makes the #6090 cold-boot path unreachable —
  `cloud-init.yml:424-426` bakes `/etc/default/soleur-ghcr-read` *specifically* so a deploy can
  proceed when Doppler answers empty at boot.
  **Fix:** state the mapping explicitly — **terminal** when the read fails in a way consistent with
  a bad credential; **retry-then-degrade** on a transient/network shape — and add a network-class
  fixture asserting the deploy still completes on baked GHCR creds. (Note this reintroduces a
  *minimal* two-way discrimination, which is compatible with R-draft's rc/empty/tail marker: the
  branch keys on `rc` + retry outcome, not on a five-value taxonomy.)

- **R26 — AC2 is unsatisfiable with the existing test seam AND passes vacuously.**
  `ci-deploy.test.sh`'s only doppler-failure mode is `MOCK_DOPPLER_FAIL` (`:1416`, `:1465`), which
  fails `secrets download` and aborts at `:1530-1548` — **before `zot_gate_and_login` is ever
  reached**. The fixture AC2 requires (token set, `secrets get` fails) does not exist. And AC2's
  assertion is purely negative ("must NOT emit `dark, pre-provisioning`"), so it passes on *any*
  fixture that aborts early — **including unmodified `ci-deploy.sh`. It can pass on a broken
  system.**
  **Fix:** add a `MOCK_DOPPLER_GET_FAIL` mode (download OK, `get` non-zero) and pair every negative
  assertion with a **positive control**: the same fixture MUST emit
  `ZOT_GATE: doppler read FAILED rc=… empty=…`. Same treatment for AC1's RED artifact.

- **R27 — missing reason-enum consumer: the canonical taxonomy.**
  `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md:43-79` is the 35-row
  reason table that `ci-deploy.sh:18` and `web-platform-release.yml:513` name as **source of
  truth**. Not in §Files to Edit, not gated by any test — so the *operator runbook* for the new
  reason silently rots, which is exactly the "the log carried the fingerprint and nobody read it"
  failure this plan exists to fix. Also `apply-deploy-pipeline-fix.yml:771` hardcodes
  `"(e.g. image_pull_failed)"` and would print misleading remediation for a doppler abort.
  **Counter-finding — one of the draft's own claims is wrong:** `web-platform-release.yml`'s
  `case` at `:706` is on `$EXIT_CODE`, **not** on reason, and it already echoes the reason at
  `:728-732`. **No edit to that file is needed** for the reason enum; drop that line from Phase 1.3.
  (Good news, verified: `write_state` at `ci-deploy.sh:310-333` has no allow-list and
  `cat-deploy-state.sh:460` is pass-through, so nothing fails closed on a new reason value.)

- **R28 — AC16 cannot run pre-merge and asserts a proxy that passes on a broken system.**
  `terraform plan` in `apps/web-platform/infra/` needs Doppler `prd_terraform` credentials that
  only the apply workflows hold — not a PR-runnable gate. And "zero creates of `hcloud_server.web`"
  is satisfied whenever web-2 already exists in state, *regardless* of whether the `for_each`
  predicate is gated — which is the invariant it stands in for.
  **Fix:** (i) a pre-merge **static** test that the new `for_each` uses the identical existence
  predicate as its siblings; (ii) move the plan-output grep into the apply workflow's existing
  "Terraform plan" step (`apply-deploy-pipeline-fix.yml:263`), scoped to the applied `-target=` set.

- **R29 — AC14 EXECUTES the watcher instead of syntax-checking it.** `bash -c '<snippet>'` *runs*
  the code — including `gh issue create` and the Sentry POST — inside CI. **Use `bash -n`.**
  (The generic guidance this was copied from is right about *`bash -n <file.yml>` being wrong*; it
  is wrong to generalise to `bash -c` for a snippet with side effects.)

- **R30 — the watcher's `--json` field set cannot express its own filter ⇒ in-flight and cancelled
  runs false-page.** `--json conclusion,createdAt,databaseId,headSha` has **no `status`**; an
  in-progress run has `conclusion: ""`, which is non-`success` and counts toward the streak. Two
  queued releases ⇒ immediate false P1. `cancelled` (a `cancel-in-progress` supersession) also
  counts. **Fix:** add `status`, filter `status == "completed"`, and write the explicit table —
  `failure`/`timed_out` count; `cancelled`/`skipped`/`neutral`/`action_required` do not.

- **R31 — AC26 is ordered so it must fail, and it exercises only the branch that does nothing.**
  At merge time the leading runs *are* the eight failures, so the first execution **correctly**
  opens `ops/prod-stale` — making "reported no open issue" false by design until AC25 passes. And
  "no open issue" is equally satisfied by a watcher whose `gh` call errored, whose logic is
  inverted, or that does nothing.
  **Fix:** split into **AC26a** (the first run DOES fire — the positive control the plan lacks) and
  **AC26b** (after AC25, the next run evaluates healthy), plus a fixture-driven unit test of the
  streak counter.

- **R32 — no suppression path for an intentional rollback ⇒ a permanently-firing page.** Condition
  B stays true forever while prod is deliberately pinned older; label dedupe prevents duplicate
  issues but "create-or-comment" re-comments every 2h and the Sentry event re-fires. **Fix:** an
  `ops/prod-stale-ack` label (or a repo variable naming the expected pinned version) that
  suppresses both arms; comment only on **state change**.

- **R33 — Condition B reads one LB-fronted `/health` while the plan's own E8 says the hosts
  diverge.** A web-1-new / web-2-old split gives a flapping page or a missed one. §Observability
  already cites the per-host `web-N.app.soleur.ai/health` origin probes (`model.c4:287`) but
  Phase 5 does not use them. **Fix:** poll both origins; fire if **either** is behind.

- **R34 — if `webhook.service` fails to restart, the engineer gets a misleading error and no route
  out.** The status endpoint dies with the unit, so the verify loop's terminal message is the 404
  branch (`:502`) — *"the host's hooks.json predates the status endpoint… re-run with
  `allow_missing_status_endpoint=true`"* — which points at first-bootstrap, not a bricked unit,
  and whose suggested flag would **suppress** the very failure. Sharp Edge 1b names the risk;
  nothing detects or routes it. **Fix:** distinguish 404 (no endpoint) from 000/502 (webhook down)
  in the terminal message, and name the `server.tf:564/615` provisioner fallback as the recovery.
  Relatedly, the co-targeted `terraform_data.infra_config_handler_bootstrap` **is** a root-SSH
  provisioner over the CF Tunnel — so "touches no SSH at all" is false for the apply as a whole
  (it remains true that no *operator* SSHes). Add Phase 0.2b: confirm the last green run of
  `apply-deploy-pipeline-fix.yml`, which proves the SSH leg is alive, and add a Risks entry
  routing an SSH-leg failure to the designated-but-never-wired fallback.

**P2**

- **R35 — assorted AC hardening.** (a) **AC3** is a bare-token grep — passes on a comment and
  cannot fail if AC1 passes (`cq-assert-anchor-not-bare-token`); assert the deploy-state JSON
  `.reason == doppler_read_failed` under the failing-read fixture instead. (b) **AC10**'s grep
  cannot distinguish a `-target=` argument from a comment and misses transitive dependencies;
  parse the actual `terraform apply` argument list. (c) **AC17** leaves three of its five named
  vectors unasserted — and two are *already closed*: `push-infra-config.sh:55-56`
  (`mktemp` + `trap rm -f` EXIT) and `:105` (`--data-binary @file`) close (c) argv and (e)
  temp-file; cite them so AC17 becomes a regression guard rather than an open question, and fold
  (d) into AC23's mode/owner assertion. (d) **AC23** contradicts the gate's own design — it asks
  to compare host sha256 to "the repo render", but the repo file is unrendered and computing the
  rendered digest needs the token in CI, which AC17 forbids; restate as existence + `640
  root:deploy` + non-empty sha from the status JSON, and take the content proof from **behavior**
  (the post-apply redeploy reaching `reason=ok`). (e) **Sharp Edge 1's open question is a blocker
  hiding in a note** — "confirm the token cannot contain a newline or `#`" decides whether the
  delivery bricks the unit; move it into Phase 0.4 **and** add the Terraform `precondition` from
  R3.1. (f) **Phase 0.7's `gh label create` is an operator step in a plan claiming zero** — have
  the watcher run `gh label create --force` idempotently on first fire and delete AC15.
- **R36 — Phase 3.1 is read-only and belongs in Phase 0.** `curl https://web-2.app.soleur.ai/health`
  plus a CF/DNS read decides 3.2 before implementation rather than during it. Split AC24 into
  **24a** (web-1, unconditional) and **24b** (web-2, unconditional if 3.1 shows it serves;
  otherwise replaced by a named tracking issue). Keep 3.3 unconditional — that part is right.
- **R37 — the one AC that would have caught R1**, and which the draft lacked entirely: *zero
  `doppler run` unit failures on either web host in Better Stack 30 minutes post-apply.* Add it.
- **R38 — a known-and-accepted blind spot, recorded rather than fixed:** a release that is never
  *triggered* (no merge at all) leaves prod frozen with no new tag and no failing run — **both**
  watcher conditions stay silent. Closing it needs a third condition (time since last successful
  deploy), which is deliberately out of scope; recorded so the next responder does not assume
  coverage that does not exist.

### What survived review intact

§Root Cause Evidence (E1–E9) and the H1–H8 falsification table were endorsed by the panel as the
strongest part of the document and must survive verbatim into the PIR. Note the draft proposed
writing the evidence once in the PIR and citing it from the plan; **that is deliberately
rejected** — this planning phase's context is discarded on return, so the evidence lives in the
plan on disk, and the PIR cites *it*.

---

## Implementation Phases

*(Superseded where R1–R20 conflict. In particular: R0 splits these into PR-A/PR-B, R3 replaces
Phase 2.0's S-vs-T probe for the deploy leg, R17 removes Phase 4's heartbeat, and R12 moves
Phase 5.1's substrate.)*

### Phase 0 — Preconditions (no writes)

**0.0 — RESOLVE THE E9/H7b CONTRADICTION BEFORE WRITING ANY CODE. Blocking.**
The plan-review panel independently found, and `web-probe-read-token.tf:5-6` states, that
**web-1 has no `/etc/default/inngest-server`** (`web_colocate_inngest` defaults false). With
`EnvironmentFile=-` those three units would take their doppler-less `else` branch and exit 0 — so
on the repo's own account, a `webhook-deploy` revocation should not touch them at all, *and yet
they are failing 341 times*. Exactly one of these is true and it is cheap to find out:
 (a) the comment is stale and web-1 *does* carry `/etc/default/inngest-server` — then **Phase 2
     does not fix those three units**, because they will never read the new file, and 2.10's sweep
     must cover them explicitly;
 (b) the on-host units differ from the repo (web-1 never re-ran cloud-init, `model.c4:451`);
 (c) the 18-second correlation has a different upstream entirely, and H7b is not merely UNKNOWN
     but pointing somewhere else.
**Discriminator, no SSH:** query the actual stderr of those three units in Better Stack over the
onset window. They emit via `echo` under unit-derived identifiers **not** in the Vector allowlist,
so this may return nothing — in which case Phase 1.5's `SyslogIdentifier` stamp is *promoted into
PR-A* as the only way to answer it, and the answer arrives on the next tick.

**0.0b — Measure what `doppler` actually does on this token; do not assume it exits non-zero.**
`ci-deploy.sh:1359` discards stderr, so no one has ever seen the failure. Two independent signals
suggest the failure may be **`rc=0` with empty output** rather than a non-zero exit:
`soleur-host-bootstrap.sh:733-741` generates a `vector.service` that runs `doppler run … -- vector`
gated on `EnvironmentFile=/etc/default/webhook-deploy`, and Better Stack **kept receiving rows
throughout the incident** — evidence that `doppler run` still execs on this credential. If the
failure is `rc=0`+empty, then AC1's "stub doppler to exit non-zero" test asserts a scenario that
is **not this incident**. Phase 1's marker must therefore carry `empty=<0|1>` alongside `rc=<n>`,
and the test must cover the `rc=0 empty=1` case first.

**0.0c — `vector.service` is an unlisted Class-B consumer and the plan missed it.**
`soleur-host-bootstrap.sh:733-741` puts the **telemetry shipper itself** on
`EnvironmentFile=/etc/default/webhook-deploy`. No phase re-points it. If Design T is selected,
`vector.service` must be added to 2.10's sweep — otherwise the observability layer stays on the
dead credential, and the next occurrence goes dark in exactly the way this plan exists to prevent.
(Design S fixes it for free, which is a third argument for S.)

0.1 **Sync the worktree.** `git fetch origin main && git rebase origin/main`. The worktree is at
`be7b5a5ee`; `origin/main` is `d95344622` (PR #7096, which set the PIR to `status: ongoing`).
Planning against the stale copy would re-apply an edit that already landed.

0.2 **Re-assert the fix channel is still alive** (the evidence is time-sensitive):
```
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
  --since 12h --grep infra-config-apply --limit 20
```
Expect a `complete: N/N files written, 0 failed` line. If the channel is dead, switch to the
fallback vehicle (§Infrastructure → Apply path) and record the switch in the plan first.

0.3 **Re-read doppler token state** — `doppler configs tokens --project soleur --config prd --json`.
If a *new* token has appeared since 11:19:30Z, or `terraform-prd-20260730` is gone, the situation
has moved and Phase 1's evidence must be re-derived before proceeding.

0.4 **Verify the CLI forms this plan prescribes**, pinning outputs into the spec:
`doppler secrets get --help`; `gh run list --help` (confirm
`--json conclusion,createdAt,databaseId,headSha`); `curl -s https://app.soleur.ai/health | jq .`.

0.5 **Grep every consumer of the deploy credential** before changing its shape:
`git grep -n 'webhook-deploy' -- apps/ .github/ scripts/` and
`git grep -n 'DOPPLER_TOKEN' -- apps/web-platform/infra/`. Every hit is either updated or
explicitly scoped out with a reason.

0.6 **Confirm Phase 1 is not chicken-and-egg** (this validates the phase ordering). Phase 1 edits
`ci-deploy.sh`, which lives on the host at `/usr/local/bin/ci-deploy.sh`. If that file were
delivered by the *container* deploy — the very thing that is broken — Phase 1 could not reach the
host and would have to follow Phase 2. **It is not:** `ci-deploy.sh` is entry #1 of the
infra-config `FILE_MAP` (`infra-config-apply.sh:33-49`) and `DEST_SPEC`
(`infra-config-install.sh:59-75`), delivered by the same webhook channel proven alive at
2026-07-30 16:32:48. Phase 1 therefore lands independently of the broken pull path, and shipping
diagnostics first is safe. Re-assert this at /work rather than inheriting the claim.

0.7 **Create the labels the watcher needs** if absent:
`gh label list --limit 200 | grep -E '^ops/prod-stale\b'` — create it if missing, so AC15 is
satisfiable rather than aspirational.

### Phase 1 — Make the failure self-reporting (RED → GREEN; ships first)

*Ordering is load-bearing: the diagnostic contract must exist before the remediation, so that if
the remediation does not work the next run says why. This phase is independently valuable even if
Phase 2 needs a second attempt.*

1.1 **Write failing tests first** (`cq-write-failing-tests-before`) in
`apps/web-platform/infra/ci-deploy.test.sh`: stub `doppler` to exit non-zero and assert (a) the
emitted marker contains `SOLEUR_DEPLOY_CRED_FAIL` with `rc=` and `class=`, and (b) the deploy
terminates with `reason=doppler_read_failed`, **not** `image_pull_failed`.

1.2 `ci-deploy.sh` — replace the three silent reads. **Emit observation, not classification:**

```
SOLEUR_DEPLOY_CRED_FAIL rc=<n> empty=<0|1> err="<=200B, control-stripped, dp.st.-redacted>"
```

- `:1359` `ZOT_REGISTRY_URL="$(doppler secrets get ... 2>/dev/null || true)"` → capture the exit
  code **and** whether stdout was empty **and** a bounded, control-stripped stderr tail.
- `:1361` — when `DOPPLER_TOKEN` is non-empty but the read produced nothing, emit
  `ZOT_GATE: doppler read FAILED rc=<n> empty=<0|1> — the host cannot read its own credential source (NOT pre-provisioning)`
  and return a distinct status. Keep the `"dark, pre-provisioning"` wording **only** for the true
  unset-token case.
- `:1374-1377` — same treatment for `ZOT_PULL_{USER,TOKEN}`.
- `ghcr_prelude_and_login` — same treatment for the "baked file absent + doppler
  empty/unavailable" message.

**Why not a classified enum (design reversal, recorded).** An earlier draft specified a five-value
enum (`auth|network|config_dir|notfound|unknown`) derived by keyword-matching the stderr. That is
**classification before observation**: the code discards this stderr today
(`ci-deploy.sh:1359` `2>/dev/null`), so the taxonomy would be invented for messages nobody has
ever read. Three concrete defects followed from it:
1. The tail is a **superset** of the class — the class is *derived* from the tail, so emitting the
   tail and dropping the classifier loses nothing and removes a mapping table that silently
   degrades to `unknown` on the next doppler release.
2. `config_dir` is **provably dead on this surface** — E6 argues `PrivateTmp=true` makes the #6536
   class structurally impossible inside `ci-deploy.sh`. Shipping an enum value onto a surface
   where the plan has already proven it cannot fire is exactly the "test asserts a string that
   cannot exist" defect.
3. **The enum has no field for the most likely actual failure.** There is direct evidence that
   `doppler` may exit **0 with empty output** rather than non-zero: the web-host `vector.service`
   (`soleur-host-bootstrap.sh:733-741`) runs `doppler run ... -- vector` off the *same*
   `EnvironmentFile=/etc/default/webhook-deploy`, and Better Stack kept receiving rows throughout
   the incident — so `doppler run` evidently still **execs**. `empty=1 rc=0` is precisely the case
   the enum cannot express, and it may be *this* incident.
The secret-leak concern the enum was protecting against is handled directly and more cheaply:
bound the tail to 200 bytes, strip control characters, and redact any `dp.st.`-prefixed substring.

1.3 **New terminal reason.** Add `doppler_read_failed` to the deploy-state reason enum and abort
before the pull when it fires. Rationale: since the ADR-096 2026-07-30 amendment, GHCR is not a
fallback — falling through only relabels a credential fault as `auth_denied`. Update
`cat-deploy-state.sh` consumers and the release workflow's `case "$EXIT_CODE"` messaging so the
run log prints the real cause.

1.3b **The generalisable rule this incident teaches: absence of a value must never silently select
a code path.** The `"dark, pre-provisioning"` branch fired because `ZOT_REGISTRY_URL` was *empty*,
and empty was treated as a meaningful configuration state. Make that branch require an **explicit
positive sentinel** (a provisioning flag, or `ZOT_REGISTRY_URL` being genuinely unset *and*
`DOPPLER_TOKEN` also unset), and treat empty-when-a-token-was-present as terminal. Without this,
the next empty secret — any secret — re-enters the same silent fall-through with a different name.
This is the single highest-leverage line in the plan and it generalises past zot.

1.4 **Sentry mirror** for the new failure (`cq-silent-fallback-must-mirror-to-sentry`), tags
`feature=supply-chain, op=deploy-cred-dead, host_id, doppler_class`.

1.5 `vector.toml` — add Source-4 allowlist entries for the new probe and for
`container-restart-monitor`, `cron-egress-resolve`, `cron-egress-alarm`; **and** add a
`SyslogIdentifier=` directive to those three unit definitions, because an allowlist entry with no
matching stamped identifier is a dead no-op (`journald-config.test.sh:301-307` already guards this
trap for `inngest-boot-phone-home`). Add the two-sided drift guard for `ci-deploy` ↔
`vector.toml:154`, which today has none.

### Phase 2 — Re-deliver the credential (the remediation)

**2.0 — DECIDE THE SHAPE WITH A PROBE, NOT AN ASSUMPTION. This gates everything below.**

Two designs are viable and they have very different blast radii. Which one is correct is an
*empirical* question about how systemd implements `ReadOnlyPaths` on a **file**, and it must be
measured (locally, in a container that reproduces the unit's protections) before any Terraform is
written:

> Does `rename(2)` a new inode **over** `/etc/default/webhook-deploy` succeed from inside a mount
> namespace where that path is listed in `ReadOnlyPaths`? (systemd implements a file-level
> `ReadOnlyPaths` as a read-only **bind mount**; you cannot rename over a bind-mount target — but
> confirm, do not assume.)

- **Design S (single file) — PREFERRED if the probe succeeds.** Atomically replace
  `/etc/default/webhook-deploy` in place. **Zero unit edits.** Every consumer — unit-inheritance
  *and* the six shell-source sites — is fixed by one write. No split-brain, no second source of
  truth, no `EnvironmentFile=-` fallback hole, no four-consumer edit sweep. If the probe fails on
  the bind-mount, the fallback within Design S is to drop the path from `ReadOnlyPaths` via a
  systemd **drop-in directory** (which lives outside the protected path) rather than an in-place
  unit-file edit — an in-place unit edit is clobbered by the next render of that unit anyway.
- **Design T (two files) — only if Design S is proven impossible.** The shape described in
  2.1–2.9 below. It is **sufficient for the P1** — verified: `ci-deploy.sh` does not shell-source
  the env file (H7a), so unit inheritance with later-wins genuinely fixes the deploy path — but it
  leaves the six shell-source sites reading the stale file and therefore requires the explicit
  per-consumer sweep in 2.10.

**Three hazards of Design T that the plan must not paper over** (each is why S is preferred):
1. **A shell `.` source defeats later-wins.** Any consumer that runs
   `. /etc/default/webhook-deploy` re-imports the dead `DOPPLER_TOKEN` *after* systemd handed down
   the good one, clobbering it. Six such sites exist (`cloud-init.yml:329,486,786`,
   `cron-egress-enforce-probe.sh:49`, `soleur-host-bootstrap.sh:43,211`). They are **not** on the
   deploy path (verified), but they are on other paths.
2. **`EnvironmentFile=-` is a silent-fallback hole.** If the new file is missing or never
   delivered, the `-` prefix makes systemd ignore it and the unit silently keeps the dead token —
   reproducing the exact silent-stale-credential class this plan exists to kill. Design T
   therefore must **not** rely on `-` as the steady state: deliver the file first, verify it, and
   only then land a unit that requires it; or keep `-` and add a **startup assertion** that fails
   the unit loudly when the second file is absent.
3. **Split-brain by construction.** Two files, two truths, and "which token am I using" depends on
   whether the caller went through systemd or through `.`. The next rotation heals one and not the
   other.

**2.0b — Never carry the credential and a unit change in the same payload.** Whichever design
wins, split the delivery: (a) payload 1 writes the credential file only, and its success is
asserted by the content gate + the status read; (b) payload 2 makes any unit change, gated on a
systemd unit-file syntax verification *before* the restart is scheduled. Rationale: Phase 2 uses
the webhook channel to modify the webhook's own unit and then restarts it, on a host with no SSH
runbook and no orderable replacement (`cx33`, 0/3 EU DCs). A malformed unit or an unparseable
`EnvironmentFile` (quoting, an embedded newline, CRLF) makes the unit fail to start, and **the
tool needed to recover is the tool just broken.** That is strictly worse than the current outage.
Additionally, before scheduling the restart, arm a **dead-man revert**: a timer that restores the
prior state and restarts the unit unless a success sentinel appears within N minutes. Design S
makes most of this unnecessary, which is the second reason to prefer it.

**2.0c — Verify the rendered token value is `EnvironmentFile`-safe** before it is ever written:
no newline, no CR, no leading/trailing whitespace, no `#`. Doppler service tokens are
`dp.st.`-prefixed URL-safe strings — **verify with a length/charset assertion on the rendered
value, do not assume.** A single stray byte here is the bricking scenario in 2.0b.

---

*2.1–2.9 below describe **Design T**. If 2.0's probe selects Design S, replace 2.1–2.9 with the
single in-place write and keep only 2.2 (`triggers_replace`), 2.5 (destination allow-list), 2.8
(cloud-init convergence) and 2.9 (`paths:` filter).*

2.1 New `apps/web-platform/infra/webhook-doppler-token.env.tmpl` containing **only**
`DOPPLER_TOKEN=${doppler_token}`. It must not set `DOPPLER_CONFIG_DIR` (Sharp Edges).

2.2 `server.tf` — render it into a `local.*`, base64 it into
`terraform_data.deploy_pipeline_fix`'s `environment {}` (exact precedent: `HOOKS_JSON_B64`), and
add both the rendered content **and** `var.doppler_token` into the `sha256(join(...))`
`triggers_replace` list so the next rotation re-fires delivery automatically.

2.3 `push-infra-config.sh` — add `"webhook_doppler_token_b64": "${WEBHOOK_DOPPLER_TOKEN_B64}"` to
the payload (pre-rendered, exactly like `hooks_json_b64`).

2.4 `hooks.json.tmpl` — add the matching `pass-file-to-command` entry with `base64decode: true`.

2.5 `infra-config-apply.sh` `FILE_MAP` **and** `infra-config-install.sh` `DEST_SPEC` — add
`/etc/default/soleur-doppler-token` at `640` `root:deploy`. Both maps, or the installer rejects it
with `dest_not_allowlisted`.

2.6 `infra-config-gate.sh:126-129` — the template-exclusion invariant. Do **not** simply bump the
count `1 → 2`: a bare count stops meaning anything at the third file, and it cannot say *which*
destination was expected to be template-backed. Convert it to a **destination allow-list** (the
set of `.tmpl`-backed FILE_MAP dests, asserted by membership) and keep the fail-loud behaviour on
any dest outside it. This is a strictly better guard for the same edit cost.

2.7 `webhook.service` — add `EnvironmentFile=-/etc/default/soleur-doppler-token` after the
existing entry (later-wins), and add the new path to `ReadOnlyPaths`. Do **not** attempt to write
`/etc/default/webhook-deploy`: `cloud-init.yml:266` marks it read-only inside the unit's namespace
and `sudo` does not escape that namespace.

2.8 `cloud-init.yml` — write the same new file at first boot, so a fresh host and a running host
converge on identical state. (Inert for running hosts by `ignore_changes = [user_data]`; that is
expected, and is why 2.2–2.7 exist.)

2.9 `.github/workflows/apply-deploy-pipeline-fix.yml` — ensure the `paths:` filter includes every
file touched in 2.1–2.7, or the merge will not fire the apply.

**2.10 — Design-T-only: the Class-B consumer sweep.** Design T fixes the deploy path and nothing
else. Every remaining Class-B consumer (E9) must be explicitly either **fixed** or **scoped out
with a reason**; silence is not an option, because three of them are failing right now at 60s
cadence. Concretely:
- **Unit-inheritance consumers** (`container-restart-monitor.service:14`,
  `cron-egress-resolve.service:19`, `cron-egress-alarm@.service:10`,
  `cron-egress-firewall.service:22` — all reading `EnvironmentFile=-/etc/default/inngest-server`):
  add a later-wins `EnvironmentFile` for the re-delivered file. All four are `.service` files in
  `apps/web-platform/infra/`, deliverable to `/etc/systemd/system` — an allow-listed destination —
  so the channel **can** reach them.
- **Shell-source consumers** (`cron-egress-enforce-probe.sh:49`, `soleur-host-bootstrap.sh:43,211`,
  `cloud-init.yml:329,486,786`): each must source the re-delivered file **after** the legacy one,
  or the stale value wins. The three `.sh` files live under `/usr/local/bin` — also allow-listed.
  The three `cloud-init.yml` sites are inert on running hosts and are convergence-only.
- **`/etc/default/soleur-ghcr-read`**: E1 reports it "absent". Determine whether it is genuinely
  missing or merely unreadable, and scope accordingly.
This sweep is the concrete cost of Design T and is the strongest argument for spending the 2.0
probe first: **Design S makes all of 2.10 disappear.**

### Phase 3 — web-2 (the peer leg) — *promoted into the remediation, not sequenced after it*

**Ordering note (revised).** web-2 is a live deploy target (E8) carrying the same Class-B files.
Fixing web-1 alone does **not** make a release green end-to-end, and web-2's deploy journals do
not reach the warehouse — so declaring victory on a web-1-only fix would be declaring it blind.
Treat 3.1–3.3 as part of the same remediation slice, not a follow-on phase. The only part that may
legitimately defer is 3.2's *delivery* if 3.1 proves web-2 is a true weight-0 standby.

3.1 Establish web-2's role from live data before choosing: is it in the serving rotation, or a
standby at weight 0 (`model.c4:182` claims the latter for the ADR-143 rebirth, but E8 shows the
model is stale)? Probe `https://web-2.app.soleur.ai/health` and the CF/DNS records.

3.2 If web-2 serves traffic, its dead token is a **correctness** problem: the fan-out is
fire-and-forget HTTP 202, so web-1 can report a green deploy while web-2 serves stale bits.
Deliver to it. Two options, decided at /work with the 3.1 evidence:
 (a) extend the infra-config push with a peer fan-out mirroring the existing `/hooks/deploy-peer`
 private-net fan-out precedent in `hooks.json.tmpl`, or
 (b) add a guarded `terraform_data` sibling for web-2 mirroring the web-1 `*_install` pattern.

3.3 Deliver `vector.toml` to web-2 so its `ci-deploy` / `webhook` journals stop being invisible
(E8). **Sharp edge:** any resource with `for_each = var.web_hosts` referencing
`hcloud_server.web[each.key]` drags a `-target`-excluded host into the plan. Gate the `for_each`
on the same existence predicate the siblings use, and add an AC that `terraform plan` shows
**zero creates** of `hcloud_server.web`.

3.4 If 3.1 shows web-2 is a true weight-0 standby, 3.2 may be deferred to a tracking issue — but
3.3 (telemetry) ships regardless, because "web-2 is fine" is currently indistinguishable from
"web-2 is silent".

### Phase 4 — Continuous credential liveness signal (**reuse, do not build**)

**Design reversal, recorded.** An earlier draft created a whole new unit
(`web-deploy-cred-probe.{sh,service,timer,test.sh}`) plus a new `betteruptime_heartbeat`, a
`heartbeat-manifest.ts` row, and a `-target=` line. That is **cut.** The objection that originally
blocked reuse of the existing 60s `web-zot-consumer-probe` was `web-probe-read-token.tf:5-18`:
the probe must not source `/etc/default/webhook-deploy` because that file also carries
`DOPPLER_CONFIG_DIR=/tmp/.doppler` (the #6536 clash). **Phase 2.1 dissolves that objection by
construction** — the re-delivered file contains only `DOPPLER_TOKEN=` and deliberately no
`DOPPLER_CONFIG_DIR` (AC7). So the cheap version is now available and the expensive one is not
justified.

4.1 Add ~10 lines to `apps/web-platform/infra/web-zot-consumer-probe.sh`: read the **deploy**
token out of the re-delivered file and perform one
`doppler secrets get ZOT_REGISTRY_URL --plain --token "$t"`, emitting
`SOLEUR_DEPLOY_CRED ok=0|1 rc=<n> empty=<0|1>` on the existing stderr channel.

**Load-bearing constraint:** read the token *into a local variable* and pass it via `--token`.
Do **NOT** add the file to the unit's `EnvironmentFile` — that would override the probe's own
read-scoped `web_probes` token with the full-`prd` deploy token, silently widening the probe's
privilege. This is the one way to get this reuse wrong.

This reuses: the existing 60s timer, the existing `SyslogIdentifier=web-zot-consumer-probe`
(already in the Vector Source-4 allowlist, so **no `vector.toml` edit for this signal**), the
existing positive-control canary, and the existing per-host heartbeat.

4.2 **Accepted merge cost, named:** one heartbeat now suppresses for *either* a zot fault *or* a
credential fault. The discriminator is the stderr line, which ships. For a signal whose job is
"page within minutes", that trade is acceptable; if it later proves insufficient, splitting the
heartbeat is a follow-up, not a P1 concern.

4.3 **The cheapest signal of all, and it needs no probe code:** Phase 1.5's `SyslogIdentifier`
stamps. The failing units already produced **341 failure lines in 5.7h** — they simply never left
the host. Getting those off the box is the real 80% of the value here. It is gated on resolving
Phase 0.8's open question (which env file those units actually read), which is another reason
that question is a Phase-0 blocker rather than a footnote.

*Deleted from this plan by this reversal:* `web-deploy-cred-probe.{sh,service,timer,test.sh}`
(4 files), the `web-probe.tf` heartbeat + `doppler_secret` pair, the `heartbeat-manifest.ts` rows,
the `apply-web-platform-infra.yml` `-target=` lines for them, and old AC12.

### Phase 5 — Release-failure and prod-staleness alerting

5.1 `.github/workflows/scheduled-release-health.yml` (`cron: 0 */2 * * *` plus
`workflow_dispatch`). Two independent conditions, both **cadence-free**:
 - **A. Consecutive release failures.** `gh run list --workflow=web-platform-release.yml
   --branch main --limit 15 --json conclusion,createdAt,databaseId,headSha`; count leading
   non-`success` conclusions, ignoring `in_progress`/`queued`. Threshold `>= 2`.
   Keying on the *run*, not the `deploy` job, is required — 3 of 8 never reached `deploy` (E7).
 - **B. Prod is behind.** `curl -s https://app.soleur.ai/health | jq -r .version` vs the newest
   `web-v*` tag. If a newer release exists and prod has not taken it for `> 2h`, fire. A quiet
   weekend produces no new tag, hence no page — this is why a Better Stack heartbeat is *not*
   used for staleness (§Alternatives).
5.2 On fire: create-or-comment a label-deduped P1 GitHub issue (`ops/prod-stale`), reusing
`main-health-monitor.yml:52-70`'s `gh issue list --label ... --state open` dedupe; and POST a
Sentry event tagged `feature=deploy, op=prod-stale` / `op=release-consecutive-failure`.
5.3 `sentry/issue-alerts.tf` — an issue alert matching those tags, with an **unused `frequency`**
(taken set at `issue-alerts.tf:1216-1220`).
5.4 `sentry/cron-monitors.tf` — a `sentry_cron_monitor` for the watcher itself (crontab
`0 */2 * * *`), so the reporter's own death pages. This is the answer to "the reporter must not
be the subject": the watcher watches releases, Sentry watches the watcher, and the two vendors
are independent.
5.5 `web-platform-release.yml` — add a terminal `release-outcome` job with `if: always()` and
`needs: [release, await-ci, migrate, verify-migrations, verify-doppler-secrets, deploy, live-verify]`
that emails ops when **any** upstream result is `failure`/`cancelled`. This closes the
`deploy`-skipped hole without touching the existing in-job notifier. Handle the
empty-`RESEND_API_KEY` path as a hard `::error::` **plus** a Sentry event, not an `exit 0`.

### Phase 6 — Records

6.1 Correct
`knowledge-base/engineering/operations/post-mortems/2026-07-29-v0244-1-published-green-with-an-unpullable-image-postmortem.md`:
that incident **did** recover at 2026-07-29 21:29:48 (E2). Set `status: resolved` for *that*
incident, restore an accurate `recovery_at`, and add a prominent cross-link: "a SECOND, unrelated
incident began 2026-07-30 11:19:30Z — see the 07-30 PIR. The two share only the
`image_pull_failed` reason string, and that collision is why eight red releases read as one known
incident."
6.2 New PIR
`knowledge-base/engineering/operations/post-mortems/2026-07-30-web-host-doppler-service-token-revoked-prod-undeployable-postmortem.md`
carrying §Root Cause Evidence verbatim. `status: ongoing` until a real deploy lands, then
`resolved`.
6.3 ADR-154, the ADR-096 clause-(f) amendment, and the three `model.c4` edits
(§Architecture Decision).
6.4 Update issue #7095's title and body to name the real cause, so the next reader is not sent
at zot.
6.5 Follow-through enrollment is **not** required: no acceptance criterion here is soak-gated
(the close criterion is a single successful deploy, observable within minutes, not a multi-day
rate). Recorded explicitly so `/ship` Phase 5.5 does not have to infer it.

### Phase 7 — Prove it

7.1 The merge fires `apply-deploy-pipeline-fix.yml`; assert the infra-config gate is green with
`files_written == files_total`, `files_failed == 0`, and the per-file sha256 content assertion
passing for the new file.
7.2 Assert `SOLEUR_DEPLOY_CRED ok=1` rows appear for **both** hosts in Better Stack within 10 min.
7.3 Let the next release run (or dispatch one) and assert
`ZOT_GATE: active — docker login 10.0.1.30:5000 ok (zot-primary)` plus
`IMAGE_PULL_OK: registry=zot`, and that `curl -s https://app.soleur.ai/health | jq -r .version`
equals the new version.
7.4 If the final cutover requires a gated `workflow_dispatch`, verify the target environment's
required-reviewer set is **non-empty** before queueing
(`gh api repos/jikig-ai/soleur/environments/<env> --jq '.protection_rules'`) — a dispatch queued
against an environment with no reviewers never gets approved and never errors.

---

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/infra/ci-deploy.sh` | Phase 1.2–1.4 — classified doppler-read failure, `doppler_read_failed` terminal reason, Sentry mirror |
| `apps/web-platform/infra/ci-deploy.test.sh` | Phase 1.1 — failing-first tests |
| `apps/web-platform/infra/server.tf` | Phase 2.2, 3.3 — render + push the new env file; `triggers_replace`; vector.toml to web-2 |
| `apps/web-platform/infra/push-infra-config.sh` | Phase 2.3 — payload entry |
| `apps/web-platform/infra/hooks.json.tmpl` | Phase 2.4 — `pass-file-to-command` entry |
| `apps/web-platform/infra/infra-config-apply.sh` | Phase 2.5 — `FILE_MAP` entry |
| `apps/web-platform/infra/infra-config-install.sh` | Phase 2.5 — `DEST_SPEC` entry |
| `apps/web-platform/infra/infra-config-gate.sh` | Phase 2.6 — template-count invariant 1 → 2 |
| `apps/web-platform/infra/webhook.service` | Phase 2.7 — second `EnvironmentFile`, `ReadOnlyPaths` |
| `apps/web-platform/infra/cloud-init.yml` | Phase 2.8 — first-boot convergence |
| `apps/web-platform/infra/vector.toml` | Phase 1.5 — Source-4 allowlist entries |
| `apps/web-platform/infra/container-restart-monitor.service` | Phase 1.5 — identifier stamp |
| `apps/web-platform/infra/cron-egress-resolve.service` | Phase 1.5 — identifier stamp |
| `apps/web-platform/infra/cron-egress-alarm@.service` | Phase 1.5 — identifier stamp |
| `apps/web-platform/infra/journald-config.test.sh` | Phase 1.5 — two-sided drift guard for `ci-deploy` + new tags |
| `apps/web-platform/infra/web-probe.tf` | Phase 4.2 — new heartbeat + URL secrets |
| `apps/web-platform/infra/sentry/issue-alerts.tf` | Phase 5.3 — new issue alert (unused `frequency`) |
| `apps/web-platform/infra/sentry/cron-monitors.tf` | Phase 5.4 — watcher dead-man's switch |
| `.github/workflows/apply-web-platform-infra.yml` | Phase 4.4 — `-target=` allow-list additions |
| `.github/workflows/apply-deploy-pipeline-fix.yml` | Phase 2.9 — `paths:` filter additions |
| `.github/workflows/web-platform-release.yml` | Phase 5.5 — terminal `release-outcome` notifier |
| `plugins/soleur/lib/heartbeat-manifest.ts` | Phase 4.3 — manifest rows |
| `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` | Phase 6.3 — clause (f) amendment |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | Phase 6.3 — three edits (`:182`, `:423`, `:433`) |
| `knowledge-base/engineering/operations/post-mortems/2026-07-29-v0244-1-published-green-with-an-unpullable-image-postmortem.md` | Phase 6.1 |

## Files to Create

| File | Purpose |
|---|---|
| `apps/web-platform/infra/webhook-doppler-token.env.tmpl` | Terraform-rendered `DOPPLER_TOKEN=` env file |
| `apps/web-platform/infra/web-deploy-cred-probe.sh` | Phase 4.1 — in-surface credential liveness probe |
| `apps/web-platform/infra/web-deploy-cred-probe.service` | Phase 4.1 |
| `apps/web-platform/infra/web-deploy-cred-probe.timer` | Phase 4.1 |
| `apps/web-platform/infra/web-deploy-cred-probe.test.sh` | Phase 4.1 — classification branches under the test seam |
| `.github/workflows/scheduled-release-health.yml` | Phase 5.1 — consecutive-failure + staleness watcher |
| `knowledge-base/engineering/architecture/decisions/ADR-154-boot-baked-host-credentials-need-a-redelivery-path.md` | Phase 6.3 (ordinal provisional) |
| `knowledge-base/engineering/operations/post-mortems/2026-07-30-web-host-doppler-service-token-revoked-prod-undeployable-postmortem.md` | Phase 6.2 |

---

## Acceptance Criteria

### Pre-merge (PR)

1. `ci-deploy.test.sh` contains a test that stubs `doppler` to exit non-zero and asserts the
   emitted marker matches
   `SOLEUR_DEPLOY_CRED_FAIL .*rc=[0-9]+ .*class=(auth|network|config_dir|notfound|unknown)`.
   The test exists and **fails** on the pre-fix `ci-deploy.sh` (RED artifact recorded).
2. The `dark, pre-provisioning` phrase survives **only** on the genuinely-unset-token branch. This
   is asserted through the test seam (a `DOPPLER_TOKEN`-set + failing-read fixture must NOT emit
   it), **not** by a bare grep — the string is legitimately present in the file.
3. `doppler_read_failed` is a member of the deploy-state reason enum and is asserted by a test:
   `grep -n 'doppler_read_failed' apps/web-platform/infra/{ci-deploy.sh,ci-deploy.test.sh}`
   returns ≥ 1 in each.
4. Both `FILE_MAP` (`infra-config-apply.sh`) and `DEST_SPEC` (`infra-config-install.sh`) contain
   `/etc/default/soleur-doppler-token` with mode `640` and owner `root:deploy`. A test asserts the
   two maps agree on **every** destination (they are hand-synchronised today, with no guard).
5. `infra-config-gate.sh`'s template-exclusion invariant is `2` and its error string names both
   template-backed destinations. `bash apps/web-platform/infra/infra-config-gate.test.sh` passes.
6. `webhook.service` contains `EnvironmentFile=-/etc/default/soleur-doppler-token` **after** the
   existing `EnvironmentFile` entry, and does not attempt to write
   `/etc/default/webhook-deploy`. Verified by an ordering-aware assertion (line number of the new
   entry > line number of the existing one), not a bare presence grep.
7. `webhook-doppler-token.env.tmpl` contains exactly one line and does **not** contain
   `DOPPLER_CONFIG_DIR` (#6536 guard): `grep -c DOPPLER_CONFIG_DIR <file>` == 0.
8. `terraform_data.deploy_pipeline_fix`'s `triggers_replace` includes both the rendered template
   and `var.doppler_token`, inside the existing `sha256(join(...))` call — **the raw token must
   never be a bare trigger**. Asserted by a grep that both appear within the `sha256(` expression.
9. `terraform validate` passes in `apps/web-platform/infra/` and `apps/web-platform/infra/sentry/`.
10. Every new Terraform resource has a matching `-target=` line in
    `.github/workflows/apply-web-platform-infra.yml`. Verified by a script that extracts new
    resource addresses from the diff and greps the workflow — a hand-count is not acceptable.
11. Every file touched in Phase 2 appears in `.github/workflows/apply-deploy-pipeline-fix.yml`'s
    `paths:` filter. Same extract-and-grep shape as AC10.
12. `plugins/soleur/lib/heartbeat-manifest.ts` has a row per new heartbeat with a non-`none`
    `feeder`; `bun test plugins/soleur/test/heartbeat-reprovision-parity.test.ts` passes.
13. The new Sentry issue alert's `frequency` is not in the taken set documented at
    `issue-alerts.tf:1216-1220`. Verified by extracting all `frequency` values and asserting
    uniqueness across the file.
14. `scheduled-release-health.yml` passes `actionlint`, and each embedded `run:` block passes
    `bash -c '<extracted snippet>'`. (Do **not** run `actionlint` against composite-action files.)
15. The label the watcher uses exists:
    `gh label list --limit 200 | grep -E '^ops/prod-stale\b'` returns a match (created in
    Phase 0.7 if absent).
15a. **Phase 2.0's probe result is recorded in the PR body**, naming which design (S or T) was
    selected and the measured `rename(2)`/bind-mount outcome that selected it. A PR that
    implements Design T without the probe result is rejected — the probe is what makes the
    four-consumer sweep in 2.10 a considered cost rather than an accident.
15b. **The rendered token value is `EnvironmentFile`-safe** (Phase 2.0c): a test asserts the
    rendered file is exactly one line, matches `^DOPPLER_TOKEN=[A-Za-z0-9._-]+$`, and contains no
    CR, no trailing whitespace, and no `#`.
15c. **Credential delivery and unit changes are in separate payloads** (Phase 2.0b), and any unit
    change is preceded by a systemd unit-file syntax verification in the same handler run.
    Asserted by reading the handler's ordering, not by inspection of the diff alone.
15d. **If Design T is selected**, every Class-B consumer enumerated in E9 appears in
    `## Files to Edit` with an explicit fix, or in a scope-out list with a one-sentence reason.
    A test asserts the two sets together cover the E9 table with no remainder.
16. `terraform plan` in `apps/web-platform/infra/` shows **zero** creates of `hcloud_server.web`
    (the `for_each`-drags-an-excluded-host guard for Phase 3.3).
17. No secret material can reach a log:
    `grep -c 'set -x' apps/web-platform/infra/push-infra-config.sh` == 0; the new `environment {}`
    value is base64 of a rendered template (Terraform does not print `local-exec` env values); and
    any `terraform output` of a token value is `::add-mask::`'d.
18. The full infra test suite is green, including the seven orphan suites registered by #7072.
19. C4: `bun test apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts` pass
    after the `model.c4` edits.
20. Every `knowledge-base/` path cited in this plan resolves **at merge time** — i.e. after the
    two files this plan creates (`ADR-154-*.md` and the 07-30 PIR) exist:
    ```
    grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | sort -u \
      | while read -r f; do [[ -f "$f" ]] || echo "BROKEN: $f"; done
    ```
    prints nothing. **Note (found by running this AC against the plan at plan time):** the naive
    form of this check false-fails during planning because §Files to Create is, by definition,
    a list of paths that do not exist yet. The check is a *merge-time* gate, not a plan-time one.
    The same caveat applies to the `apps/web-platform/infra/web-deploy-cred-probe.*`,
    `webhook-doppler-token.env.tmpl`, and `.github/workflows/scheduled-release-health.yml`
    citations. Verified at plan time that **every other** cited path — 100% of the
    `Files to Edit` set and every evidence citation — resolves on disk today.
21. PR body uses `Closes #7095`. This is **not** an ops-remediation whose fix runs in a
    post-merge operator step — the merge itself applies the fix — so `Closes` is correct here.

### Post-merge (automated — no operator action)

22. The `apply-deploy-pipeline-fix.yml` run for the merge commit is **green**, and its
    infra-config verify step reports `exit_code == 0 && files_failed == 0 &&
    files_written == files_total`.
23. The `/hooks/infra-config-status` JSON (fetched over HMAC + CF Access, no SSH) reports
    `status: ok` and a `sha256` for `/etc/default/soleur-doppler-token` matching the repo render.
24. Within 15 minutes of the apply,
    `scripts/betterstack-query.sh --since 30m --grep SOLEUR_DEPLOY_CRED` returns rows with `ok=1`
    for `host_name=soleur-web-platform` **and** (per Phase 3's decision) for
    `host_name=soleur-web-2`; zero rows with `ok=0`.
25. The next `Web Platform Release` run reaches `IMAGE_PULL_OK: registry=zot image=web tag=v<N>`
    and is green end-to-end; `curl -s https://app.soleur.ai/health | jq -r .version` equals `<N>`.
    **This is the definition-of-done gate for "a real deploy reaches prod".**
26. `scheduled-release-health.yml` has executed at least once and reported **no** open
    `ops/prod-stale` issue (i.e. it evaluated the healthy branch and did not false-positive).
27. The Sentry cron monitor for the watcher shows a successful check-in.
28. Post-mortems: the 07-29 PIR is `status: resolved` with an accurate `recovery_at` and the
    cross-link; the 07-30 PIR exists and is flipped to `resolved` only after AC25 passes.

---

## Open Code-Review Overlap

Query: `gh issue list --label code-review --state open --json number,title,body --limit 200`
(60 open issues), matched against every path in §Files to Edit / §Files to Create.

| Match | Issue | Disposition |
|---|---|---|
| `apps/web-platform/infra/server.tf` | #2197 — *refactor(billing): SubscriptionStatus type + hoist single-instance throttle doc + Sentry breadcrumb UUID policy* | **Acknowledge.** The mention is incidental (a Sentry-breadcrumb policy note that cites the file); it concerns billing types, not the deploy provisioners this plan touches. Folding it in would mix a P1 outage fix with an unrelated type refactor. The scope-out remains open. |

No other planned path matches any open `code-review` issue.

---

## Domain Review

**Domains relevant:** Engineering (CTO), Operations (COO)

### Engineering

**Status:** reviewed
**Assessment:** This is an availability plus credential-lifecycle change on the production deploy
path. The architectural finding is that the fleet has **two classes** of host credential — one
with a Terraform-owned, `triggers_replace`-hashed re-delivery path
(`doppler_service_token.web_probes`) and one boot-baked with none (`var.doppler_token`) — and the
incident is precisely the second class failing in a way the first class is immune to. The right
fix is to move the second class into the first, which is what ADR-154 records. Sequencing risk is
real and is handled: diagnostics ship before remediation (Phase 1 before Phase 2), so a failed
remediation still self-reports. The highest residual engineering risk is the webhook self-restart
interacting with a malformed `EnvironmentFile`; mitigated by the `-` prefix, by the installer's
atomic `mktemp`+`chmod`+`mv`, and by AC6/AC7.

### Operations

**Status:** reviewed
**Assessment:** Operator burden is the point of this plan and it goes **down**, not up. There are
zero operator steps: the merge fires the apply, the apply pushes the file, the file is picked up
by the unit restart the handler already schedules. No SSH appears in any runbook this plan
produces. The lasting operational deliverable is that a revoked host credential becomes a paging
condition within 5 minutes instead of an un-attributed release failure days later, and that
"prod is stale" becomes a monitored condition at all. Vendor cost: no new recurring expense — the
new Better Stack heartbeats and Sentry monitors fit existing tiers (§Vendor-tier reality check),
so `wg-record-recurring-vendor-expense-before-ready` does not fire.

### Product/UX Gate

Skipped — the mechanical UI-surface override did not fire. §Files to Create / §Files to Edit
contain no path matching `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`, and the
Step-1 sweep judged Product NONE (an infrastructure/credential change with no user-facing
surface). The user-visible *consequence* — prod serving stale code — is an availability property,
not a UI one, and is covered by §User-Brand Impact.

**Brainstorm-recommended specialists:** none (no brainstorm preceded this plan; it was entered
directly from the one-shot pipeline).

---

## Compliance (GDPR / Art. 32)

The canonical regulated-data regex does **not** match: no schema, no migration, no `.sql`, no auth
flow, no API route is touched. Trigger **(b)** of the expanded gate *does* fire — the plan declares
`brand_survival_threshold: single-user incident`.

Scoped assessment: this change processes **no personal data**. It moves credential material and
adds telemetry. The relevant obligation is **Art. 32(1)(b)** — ongoing confidentiality and
integrity of the processing environment — and it is *strengthened*, not weakened: a revoked
production credential currently degrades silently, which is itself an Art. 32 availability defect
(the inability to ship a security patch). Two design constraints follow, both already ACs:
(i) the classified error enum uses a **closed vocabulary** so no secret substring can ride a
telemetry field; (ii) no token value may reach a log, state file, or process argv (AC17).

**Deferred to /work, deliberately and explicitly:** `/soleur:gdpr-gate` is not run at plan time
because it writes to the compliance-posture ledger on a Critical finding, and this planning phase
is scope-restricted to `plans/` and `specs/`. It **must** run at /work against the real diff,
where the regulated-surface regex actually applies. This is a recorded deferral, not a silent skip.

---

## Risks & Mitigations / Sharp Edges

1. **The remediation channel can take itself down.** The handler schedules a delayed self-restart
   of the webhook service (`infra-config-apply.sh:259-270`). If the new `EnvironmentFile` is
   syntactically invalid, the unit fails to start and `deploy.soleur.ai` — including
   `/hooks/infra-config` itself — is gone, leaving only the gated fallback. Mitigations: the `-`
   prefix (systemd tolerates *missing*, not *malformed*); a single-line template with no
   interpolation beyond the token; atomic install via `mktemp`+`mv`; AC6/AC7. /work must also
   confirm the token value cannot contain a newline or `#` (Doppler service tokens are
   `dp.st.`-prefixed URL-safe strings — **verify, do not assume**).
1b. **The delivery channel is being used to modify the delivery channel.** Phase 2 pushes a change
   to the webhook's own unit through the webhook, then restarts it — on a host with no SSH runbook
   and no orderable replacement. **The tool needed to recover is the tool being modified.**
   Phase 2.0b's two-payload split (credential first, unit change second, syntax-verified, with a
   dead-man revert armed before the restart) is not belt-and-braces; it is the difference between
   a stalled pipeline and an unrecoverable host. Do not collapse the two payloads "for
   atomicity".

1c. **`EnvironmentFile=-` is a silent-fallback hole, not a safety feature.** The `-` prefix makes
   systemd ignore a missing file — so an undelivered credential file leaves the unit running on
   the **dead** token with no error, which is precisely the silent-stale class this plan exists to
   kill. Use `-` only as a transitional state with a loud startup assertion, never as the steady
   state. This one is easy to get backwards because `-` *feels* defensive.

2. **`ReadOnlyPaths=/etc/default/webhook-deploy` is load-bearing and must not be casually
   removed.** It narrows what a compromised handler can rewrite. Design T avoids touching it at
   all. Design S may need to relax it — and if so, the relaxation must be scoped through a
   drop-in (not an in-place unit edit, which the next render clobbers) and the widened blast
   radius named explicitly rather than absorbed silently.

2b. **Design T's `EnvironmentFile` later-wins only covers unit inheritance, never a shell
   `.` source.** A consumer that runs `. /etc/default/webhook-deploy` re-imports the dead token
   *after* systemd handed down the good one. Six such sites exist (E9 / 2.10). Verified that
   `ci-deploy.sh` is **not** one of them — which is the only reason Design T fixes the P1 at all.
   Do not generalise "later-wins works" from the deploy path to the rest of the host.
3. **`DOPPLER_CONFIG_DIR=/tmp/.doppler` is a known landmine (#6536) and this PR must not touch
   it.** The existing value stays in the existing file. Changing it in the same PR would confound
   the remediation's own experiment (E6's residual) — if reads recover, we would not know which
   change did it. Any change to it is a separate PR.
4. **`terraform plan` cannot see this fix working.** `local-exec` is trigger-and-forget: a `202`
   from the webhook means "handler started", never "files written" (#4804). The **only** valid
   green is `infra-config-gate.sh`'s content assertion plus the post-merge
   `/hooks/infra-config-status` read. A green apply over a stale host is the exact latched
   false-green of #6594.
5. **`for_each = var.web_hosts` can drag a `-target`-excluded host into the plan.** Phase 3.3's
   web-2 telemetry work must be gated on the same existence predicate the siblings use, with AC16
   asserting zero `hcloud_server.web` creates. A routine merge-apply that births a host is the
   #6416 failure mode.
6. **Adding a `.tmpl`-backed file reds `infra-config-gate.sh` by design.** The
   `template_count -ne 1` assertion at `:126-129` is fail-loud on purpose. Update it in the same
   commit or CI blocks with a confusing "exclusion drift" error.
7. **A `-replace` of web-1 is not an option.** `cx33` is orderable in 0 of 3 EU DCs
   (`model.c4:182`, #6460). Anyone reaching for `hr-prod-host-config-change-immutable-redeploy`
   as a mandate to replace the host would destroy production with no path back.
8. **Do not "simplify" the GHCR arm away in the same PR.** Phase 1.3 short-circuits *before* the
   pull on `doppler_read_failed`; it does not delete the GHCR fall-through. Deleting that branch
   darkens `sentry_issue_alert.zot_mirror_fallback_rate`'s `registry:"ghcr-fallback"` signal
   (`ci-deploy.sh:1564-1588` documents the retirement tripwire). Retirement is ADR-096 task 5.3's
   job, not this PR's.
9. **ADR-154's ordinal is provisional.** ADR-153 is the highest on `origin/main` today; a sibling
   PR can claim 154 during this pipeline. On renumber, sweep the plan, `tasks.md`, and every AC
   that names the ordinal — a renumber that reaches only the ADR body leaves ACs asserting a
   nonexistent file.
10. **Better Stack retention is 3 days.** Any AC that asks for evidence from before 2026-07-27 is
    unsatisfiable. All evidence in §Root Cause Evidence was captured on 2026-07-30 and is
    transcribed verbatim here precisely because it will age out of the warehouse.
11. **`web-2`'s silence is not health.** Until Phase 3.3 lands, a query for web-2's `ci-deploy`
    rows returns exactly what a healthy host would. Do not read the absence of web-2 failures as
    evidence web-2 is fine.
12. **This plan's own evidence is time-sensitive.** Phase 0.2/0.3 re-assert the two facts the fix
    depends on (channel alive, token state unchanged) before any write. If either has moved, the
    apply path changes.

---

## Alternatives Considered

| Alternative | Why not |
|---|---|
| **Operator re-mints the token and pastes it into Doppler** | Violates the non-technical-founder constraint and `hr-never-label-any-step-as-manual-without`, and fixes the value without fixing the invisibility — the next rotation reproduces the outage exactly. |
| **`terraform apply -replace` of the web host** (immutable redeploy) | `cx33` unorderable in all three EU DCs (#6460). Destroy-then-create cannot be recreated. A second outage, not a remediation. |
| **The `server.tf:564/615` provisioner pattern as the primary vehicle** | A genuinely good option and the designated fallback (Phase 0.2). Not primary because the webhook channel is *measured alive after the fault*, is content-asserted byte-for-byte, and keeps SSH out of the resulting runbook entirely. |
| **Rewrite `/etc/default/webhook-deploy` in place via infra-config** | Structurally blocked: `ReadOnlyPaths` at `cloud-init.yml:266`, and `sudo` does not escape the mount namespace (`webhook.service:25-26`). |
| **A unit drop-in directory instead of a second env file** | Would fix the webhook unit's children only. The other four consumers read the *file*, so the host would stay half-broken and half-observable. |
| **Better Stack heartbeat for "prod has deployed recently"** | Releases are merge-driven, not cadenced. Any `period`+`grace` false-pages on a quiet weekend, and the fix for that (a long period) makes it useless during the week. The tag-vs-`/health` comparison is cadence-free and strictly better. It would also cost a `heartbeat-manifest.ts` row and a `-target=` line for a signal that would be ignored. |
| **Inngest cron as the release-health watcher (the `cron-main-health-monitor` precedent)** | Considered seriously — it is genuinely independent of GitHub Actions. Rejected for v1 because it needs a GitHub token on the host and the host is the *other* subject. The chosen shape gets the independence property more cheaply: a GHA watcher plus a Sentry cron dead-man's switch on the watcher, across two independent vendors. Revisit if GHA-wide outages become a real failure mode. |
| **Scope the deploy token down from full-`prd` to least-privilege** (the `web_probes` pattern) | Correct long-term, and the honest answer to §Encryption Posture's exception. Deliberately **out of scope** for a P1 outage fix: it changes what `ci-deploy.sh` can read, has a wide blast radius across six consumers, and would delay restoring production. Tracking issue filed at /work with re-evaluation criteria. |
| **Delete the GHCR fall-through now** | See Sharp Edge 8 — it darkens a live Sentry alert signal and belongs to ADR-096 task 5.3. |
| **Just flip the post-mortem to `resolved` when prod deploys** | Would record two distinct incidents as one, which is the exact confusion that let eight red releases accumulate. §Phase 6 splits them. |

---

## Plan Review Revisions (R1–R14) — SUPERSEDING

A 5-agent panel (architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer, CTO/devex,
plus a scoped strong-model consult) reviewed the draft above. **Where this section conflicts with
an earlier section, this section wins.** Each revision names what was wrong and the evidence.

### R1 (P0) — `/etc/default/inngest-server` is a *derived copy* of the dead token. H7b resolves to CONFIRMED.

The open question in E9/H7b is **answered**, with a mechanism:
`apps/web-platform/infra/inngest-bootstrap.sh:586` extracts the token *out of*
`/etc/default/webhook-deploy` —
`grep -oP '(?<=^DOPPLER_TOKEN=)dp\.\S+' /etc/default/webhook-deploy` — and writes it into
`/etc/default/inngest-server`. Worse, `inngest-bootstrap.sh:567-568` **preserves** that file
whenever its value still matches `^DOPPLER_TOKEN=dp\.`, so a **dead-but-well-formed token is
pinned forever** with no self-heal even on re-bootstrap.

So one revocation genuinely killed all four units — via two files, one of which is a copy.
**Upgrade H7b from UNKNOWN to CONFIRMED**, citing `inngest-bootstrap.sh:586` and `:567-568`.

**This is the invariant the incident actually teaches, and ADR-154 must carry it:**
> No secret may be copied into a second host file without the copy inheriting the original's
> re-delivery path.

Consequence for the fix: re-delivering only `webhook-deploy`'s replacement leaves four units red
while `ci-deploy` recovers — **a false green baked into the plan's own success criteria** (AC25
would pass). Each of the four needs one added line, and the delivery channels already exist:

| Unit | Edit | Existing delivery |
|---|---|---|
| `cron-egress-resolve.service`, `cron-egress-alarm@.service` | add `EnvironmentFile=-/etc/default/soleur-doppler-token` **after** the `inngest-server` line | `terraform_data.cron_egress_firewall` (`server.tf:1513`) — `file()`-hashed, auto-refires |
| `container-restart-monitor.service` | same one-line add | `terraform_data.container_restart_monitor_install` (`server.tf:442`) |
| `inngest-heartbeat.service` | unit is a heredoc in `inngest-bootstrap.sh`, not a repo file → push a **drop-in** `…/inngest-heartbeat.service.d/10-doppler-token.conf` | needs a new `terraform_data` sibling or a FILE_MAP entry — **blocker if FILE_MAP:** `infra-config-install.sh:110-131` does `mktemp "${dest_dir}/…"` with no `mkdir -p`, so a drop-in *directory* dest fails. Add a guarded `mkdir -p` for allow-listed dests. |

**Do NOT rewrite `/etc/default/inngest-server` wholesale** — `inngest-bootstrap.sh:616-617`
fail-closes the host if `DOPPLER_PROJECT=` goes missing, and per Sharp Edge 7 a host replace is
impossible. Second file + later-wins is the only safe shape there.

**Correction to §Alternatives:** the row rejecting "a unit drop-in directory" said the other
consumers "read the *file*". They read it via systemd `EnvironmentFile=` — which is exactly what a
drop-in overrides. **The correct mechanism was rejected on a false statement of fact.** Drop-ins
are now the prescribed mechanism for the two generated units.

### R2 (P0) — `vector.service` runs on the dead token. It is the instrument everything else is read through.

`soleur-host-bootstrap.sh:721-738` generates a web-host `vector.service` with
`EnvironmentFile=/etc/default/webhook-deploy` and `ExecStart=… if [ -n "$DOPPLER_TOKEN" ]; then exec doppler run … -- vector`.
`DOPPLER_TOKEN` is non-empty (just dead) → the guard passes → `doppler run` fails →
`Restart=on-failure` crash-loop.

It survives **only** because the process started before 11:19:30Z and holds its fetched secrets in
memory. **Any reboot, OOM, or `systemctl restart vector` is a total telemetry blackout** — and
AC24, AC26 and the entire `discoverability_test` read from that channel. This also explains the
E9 counter-signal cleanly, retiring that open item.

**Remedy:** ship a `vector.service.d/10-doppler-token.conf` drop-in in the same slice. Treat this
as *higher* priority than the alerting phases — it is the instrument, not the subject.

### R3 (P0) — The Sentry paging route is dead for exactly this fault class.

`ci-deploy.sh` hydrates its Sentry ingest parameters *from Doppler, with the same token*:
`for k in SENTRY_INGEST_DOMAIN SENTRY_PROJECT_ID SENTRY_PUBLIC_KEY; do … doppler secrets get … 2>/dev/null || true`,
and every emitter is guarded on those being non-empty. Under a revoked token all three read empty
→ **zero Sentry events**. Same for `container-restart-monitor.service`. This is why 341 unit
failures over 5.7h produced no page, and it means Phase 1.4's "Sentry mirror" and every
`alert_route: Sentry issue alert op:deploy-cred-dead` in §Observability **do not fire**.

The plan's two-vendor independence story silently collapses to one vendor (Better Stack via
Vector — which survives only because Vector uses its own token, and per R2 is itself fragile).

**Remedy:** bake `SENTRY_INGEST_DOMAIN` / `SENTRY_PROJECT_ID` / `SENTRY_PUBLIC_KEY` into the
Terraform-rendered env file alongside `DOPPLER_TOKEN`, and prefer the baked values over the
Doppler prefetch. Exact precedent: `server.tf:564` already bakes
`BETTERSTACK_INGEST_URL=${local.betterstack_logs_ingest_url}` into
`/etc/default/web-private-nic-guard` for this same reason. These are public DSN components, so
this adds no new exposure class. **New AC:** with `doppler` stubbed to fail, a Sentry POST is
still attempted — a test the current design fails.

### R4 (P0) — Do not modify `webhook.service` at all. Put the override in `ci-deploy-wrapper.sh`.

This dissolves the bricking risk (Sharp Edge 1 / 1b) rather than mitigating it.
`ci-deploy-wrapper.sh` is already `FILE_MAP` → `/usr/local/bin/ci-deploy-wrapper.sh|755|root:root`.
Add to it:

```
[ -r /etc/default/soleur-doppler-token ] && . /etc/default/soleur-doppler-token
```

The **unit definition then never changes**, so the delayed self-restart cannot fail to start.
Worst case is a bad token and a failed deploy — the remediation channel stays alive. Keep the
`EnvironmentFile=-` additions only where genuinely needed (R1's four units and R2's vector), none
of which is the remediation channel. This supersedes Phase 2.7 and most of 2.0b.

Three further hardening layers, in value order:
1. **Terraform variable validation** — `variable "doppler_token" { validation { condition = can(regex("^dp\\.st\\.", var.doppler_token)) … } }`. Fails at `terraform plan`, before a byte reaches the host. This is the "provably non-bricking before it lands" answer.
2. **Installer-side shape rejection** — in `infra-config-install.sh`, for `/etc/default/*` dests, reject unless every non-blank line matches `^[A-Za-z_][A-Za-z0-9_]*=` (`reject "envfile_shape"`). Refuse-to-install beats install-and-brick.
3. **Gate the self-restart** — insert `systemd-analyze verify /etc/systemd/system/webhook.service` before `infra-config-apply.sh:265-270` schedules the restart, so a bad unit leaves the running in-memory unit untouched and reds CI instead.
4. **Pre-merge rehearsal, not just ACs** — a systemd-in-container test (precedent: `fresh-boot-parity.test.sh`, and the rung-2 boot-rehearsal route at `be7b5a5ee`) that renders the tmpl, installs via `TEST_DESTDIR`, and asserts `systemd-analyze verify` passes.

**Note the `-` prefix gap R4 also closes:** `EnvironmentFile=-` covers *absent* and *unreadable*,
**not empty-valued**. `DOPPLER_TOKEN=` (an empty render) wins by later-wins and silently blanks a
good credential. Layer 1's regex validation is the fix.

### R5 (P0/P1) — SPLIT INTO TWO PRs. Both reviewers reached this independently.

The single-PR shape concentrates the one failure mode that can make the outage unrecoverable into
the largest possible change. Three concrete reasons: (i) Phase 2 lands via
`apply-deploy-pipeline-fix.yml` while Phases 4/5 land via `apply-web-platform-infra.yml`'s
hand-maintained `-target=` allow-list — coupling the credential fix to a second apply whose
omissions are silent; (ii) the plan itself names the channel-bricking risk, and that PR should be
as small as possible; (iii) old AC18 ("full infra suite green incl. the seven orphan suites")
turns unrelated pre-existing red into a P1 merge blocker.

Also: "diagnostics before remediation" is **inert as an intra-PR ordering** — both land in the
same commit at the same instant. It is an argument for two PRs, not for internal phase order.

- **PR-A (restore prod):** Phase 0.2/0.3/0.6 + R1 + R2 + R3 + R4 + Phase 2 (credential delivery)
  + the minimum Phase 1.2 change so the dark branch stops lying + Phase 5.5 + Phase 6.4 +
  Phase 7.1–7.3.
- **PR-B (harden):** the `doppler_read_failed` terminal abort, Phase 1.5, Phase 3, Phase 4,
  Phase 5.1–5.4, Phase 6.1–6.3, ADR-154, the C4 edits, both PIRs.

Rationale for putting the *terminal abort* in PR-B: it adds a new abort path **on the recovery
path itself**. A bug there breaks deploys for a reason unrelated to the credential.

### R6 (P1) — "The next rotation self-heals" is **false as designed**.

`triggers_replace` is only consulted **when Terraform runs**, and
`.github/workflows/apply-deploy-pipeline-fix.yml:62-64` is
`on: push: branches:[main] paths:[…]` + `workflow_dispatch` — **no `schedule:`**. A Doppler-only
rotation changes zero repo paths, so nothing ever evaluates the hash. Worse, an out-of-band
rotation (exactly what happened at 11:19:30Z) does not update `soleur/prd_terraform` either, so
even a scheduled apply would re-push the *same stale* value.

**Remedy:** add `schedule: - cron: "0 */12 * * *"` to that workflow (its header already references
a since-removed 12h cron), **and** state plainly in ADR-154 that the self-heal property holds only
for rotations that write back to `soleur/prd_terraform`. Otherwise the probe is a pager, not a
healer, and ADR-154 clause (a) is unsatisfied by its own reference implementation.

### R7 (P1) — AC23 is unsatisfiable: the gate *excludes* `.tmpl` dests from content assertion.

`infra-config-gate.sh` excludes template-backed dests from the byte-for-byte sha256 comparison —
that is exactly what the `template_count` invariant guards. So bumping the count (old Phase 2.6)
would **remove the credential file from content checking**, while §Apply path claims the channel
is "content-asserted byte-for-byte" and AC23 asserts a matching sha256. Delivery would be verified
only by `files_written == files_total` — the exact latched-false-green of Sharp Edge 4.

**Remedy:** extend the gate to compare `host_sha` against the sha256 of the **rendered payload**
the workflow already holds (`WEBHOOK_DOPPLER_TOKEN_B64` → decode → sha256), not against a repo
file. Do the same for `hooks.json` while there. This supersedes the 2.6 allow-list change (keep
the allow-list, but the content check is the load-bearing half).

### R8 (P1) — Render once, inject. Do not hand-write the same content twice.

Phase 2.1 renders a `.tmpl`; Phase 2.8 hand-writes "the same" content with a `printf` in
`cloud-init.yml`. Nothing compares them, and the existing pair already shows the divergence
pattern (`600 deploy:deploy` at `cloud-init.yml:416-417` vs the proposed `640 root:deploy`).

**Remedy:** render once in `server.tf` and inject —
`user_data = templatefile("cloud-init.yml", { …, doppler_token_env_file = local.webhook_doppler_token_env })`
— with cloud-init writing the injected string verbatim. One source, zero drift, no test needed.
Also: **state the mode change explicitly.** `webhook.service` runs as `User=deploy`, so the new
file needs group-read; `640 root:deploy` is deliberate and differs from the existing
`600 deploy:deploy`.

### R9 (P1) — `§Files to Edit` is incomplete; the parity guards will red the PR.

Adding a file to `triggers_replace` / `FILE_MAP` / `DEST_SPEC` is a **five-way** lockstep
obligation (named at `server.tf:1291-1330`). Missing from §Files to Edit:
- `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` (the `TRIGGER_FILES` fixture, 19 entries)
- `plugins/soleur/skills/ship/SKILL.md` (`DEPLOY_PIPELINE_FIX_TRIGGERS` array **and** `DPF_REGEX`)
- `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md`
- `apps/web-platform/infra/cron-egress-firewall.test.sh:467` (pins `EnvironmentFile=-/etc/default/inngest-server`; the new assertion is **added**, not replaced)
- for R2: `soleur-host-bootstrap.sh` (two file lists) and `server.tf`'s baked-file set

**Baked-set hazard:** the baked file list feeds a combined content hash injected into `user_data`
and re-verified at boot; a mismatch **aborts the boot loudly**. Adding files there without a
coordinated image rebuild makes the next host birth fail closed.

### R10 (P1) — web-2 is an *unmanaged* host, not a host missing one file.

`grep -c 'hcloud_server.web\["web-1"\]' server.tf` → **19**. Every host installer is pinned to
web-1. web-2 serves production traffic and no `terraform_data` reaches it. Framing Phase 3 as
"vector.toml to web-2" understates this by an order of magnitude.

- **Pre-decide option (b)** — a guarded `terraform_data` sibling with
  `connection.host = hcloud_server.web["web-2"]`. Option (a) (fanning a full-`prd` token to a peer
  over the private net) invents a new credential-transit path under P1 time pressure and widens
  what a compromised web-1 handler can do. Rejected.
- **Retract the blanket "SSH-free" claim.** It is true for web-1 only. Option (b) uses
  Terraform-CI SSH for web-2 — still compliant (`hr-no-ssh-fallback-in-runbooks` governs
  *operator runbooks*, not IaC provisioners), but the plan must not assert a property it lacks.
- Generalise into ADR-154 or a sibling: *every host-config `terraform_data` must be
  `for_each`-keyed over `var.web_hosts`, not pinned to web-1*, with a follow-up issue for the
  other 18.
- Phase 3.4's weight-0 defer is acceptable **only** if 3.1 proves weight-0 from LB/DNS config
  *and* web-2 is removed from `WEB_HOST_PRIVATE_IPS`. Otherwise `/hooks/deploy-peer`'s
  fire-and-forget 202 means a green deploy over a stale peer — a correctness bug.

### R11 (P1) — The release-health watcher is on the wrong scheduling substrate.

`cron-terraform-drift.ts` documents why GHA `schedule:` was retired here: **delivery jitter
observed up to 339 minutes late over a 58-day survey**, forcing an 480-min Sentry monitor margin.
A 2h cadence cannot carry a 480-min margin, so the monitor is structurally either noisy (false
MISSED pages) or useless (ambiguous). Every false page is an unactionable email to a
non-technical founder — and alert fatigue is the failure mode that let this incident run 26h.

The draft rejected Inngest because it "needs a GitHub token on the host". That misreads the
precedent: the established shape is **dispatch-hybrid** — Inngest is the *scheduler only*
(≤2-min jitter), fires `workflow_dispatch`, and holds only a short-lived `actions: write`-scoped
App installation token. Execution and credentials stay in the ephemeral runner; the margin
tightens to the standard 60.

**Remedy:** add `cron-release-health.ts` mirroring `cron-terraform-drift.ts`; keep
`scheduled-release-health.yml` as the executor with `workflow_dispatch` **only**. Correct the
§Alternatives row, which rejected Inngest on the misread. Also: §5.2's "create-or-comment a
GitHub issue" is **not a page** — route it through the same Resend email path as §5.5.

### R12 (P1) — Simplify: fold the credential probe into the existing one; cut the redundant alert channels.

Already applied above in Phase 4 (reuse `web-zot-consumer-probe.sh`) and partially in Phase 5.
Additionally:
- **Cut the new `betteruptime_heartbeat` entirely.** It buys "the probe stopped running", already
  covered on the same host by `web_zot_consumer` + `web_nic_guard` on the same timer subsystem. It
  costs a `web-probe.tf` resource, a `doppler_secret`, a manifest row, a `-target=` line, an
  `arm_one` line, and a permanent row in the 12h live-reconcile. The affirmative
  `SOLEUR_DEPLOY_CRED ok=0 rc=…` log line is strictly better than heartbeat absence.
- **The hidden operator step this removes (P0-3, CTO):** `arm_one` in
  `apply-web-platform-infra.yml` is a **hand-maintained list**. A new heartbeat with a `-target=`
  line but no `arm_one` line stays `paused` forever with **no CI failure**; the only backstop is
  the 12h `heartbeat-live-reconcile` job, which files an issue **and emails the operator** — a
  hidden operator step in exactly the shape the founder cannot action. Converse hazard: `arm_one`
  *fails the apply* if no beat lands within `period + grace − 10`; with two independently-ordered
  workflows, arming before the credential lands would **red the P1 fix merge**.
- **Cut Phase 5.3 (Sentry issue alert) and 5.1 condition A.** 5.5's terminal `release-outcome` job
  fires on the *first* failure, hours sooner than a 2h watcher on the second — it alone would have
  caught all eight. Keep 5.1 condition B (prod-behind-latest-tag), the only genuinely new signal,
  in PR-B. *Retain a consecutive-failure condition in PR-B* to satisfy Definition-of-Done #4
  explicitly, noting 5.5 subsumes its urgency.
- **Retarget AC4.** `FILE_MAP`↔`DEST_SPEC` is already fail-loud at delivery
  (`reject "dest_not_allowlisted"` / `mode_mismatch` / `owner_mismatch`). The pair that rots
  **silently** is heartbeat↔`arm_one`. Write *that* guard: every `betteruptime_heartbeat` in
  `*.tf` has a matching `arm_one` invocation or an `arming_pending` manifest row.
- **Cut ACs 2, 3, 6, 9, 12, 13, 18, 19, 20, 21, 26** as ceremony (restating CI, restating a
  workflow gate, or greps over strings just typed). Keep AC1 (rewritten), 5, 7, 8, 10, 11, 16, 17,
  22–25 — AC10/AC11 are the highest-value in the document because an omitted `-target=`/`paths:`
  entry fails **silently**, the same class as this outage.

### R13 (P2) — Two factual corrections to this plan's own text.

1. **§Premise Validation mis-cites the trigger.** It claims
   `apply-deploy-pipeline-fix.yml` fires on `on: pull_request_target: [closed]`. It is
   `on: push: branches:[main] paths:` (`:62-64`) plus `workflow_dispatch`. The outcome
   ("merge is the authorization") is unchanged; the *claim of verification* was wrong. A plan that
   mis-cites the thing it says it verified erodes `hr-verify-repo-capability-claim-before-assert`
   everywhere else it is invoked. **Corrected here.**
2. **AC11 as written would widen production auto-apply.** "Every file touched in Phase 2 appears
   in the `paths:` filter" mechanically prescribes adding `apps/web-platform/infra/server.tf` —
   which would make **every** `server.tf` edit auto-write production. Scope AC11 to
   *host-delivered artifacts* only, and note `server.tf`'s exclusion is deliberate and stays.

### R14 (P2) — Smaller items, folded.

- **Magic numbers need justification or removal:** `period=900/grace=300` (moot if R12 cuts the
  heartbeat); consecutive threshold `>= 2` (why not 1, given 5.5 fires on 1?); and a `> 2h`
  staleness window polled by a `*/2h` cron **guarantees up to 4h of real staleness** before the
  first page — decouple the threshold from the poll interval.
- **Sentry field-set parity:** the tag set omits `home` and `config_dir`, which §Observability
  itself names as discriminators. Assert parity between the log line and the Sentry event.
- **Durability:** Better Stack is 3-day; Sentry is 90-day but non-functional until R3. Have the
  watcher embed the last `SOLEUR_DEPLOY_CRED` and `ZOT_GATE` lines in the `ops/prod-stale` issue
  body — transcribing 3-day evidence into a permanent artifact automatically, the same discipline
  §Root Cause Evidence applied by hand.
- **Phase 7.4 is cut** — it verifies an environment-reviewer set "if the final cutover requires a
  gated `workflow_dispatch`", conditional on a path this plan asserts does not exist. If that path
  ever becomes load-bearing it must be re-planned, not deferred.
- `sha256(jsonencode([…]))` over `sha256(join(",", […]))` — free robustness against
  concatenation ambiguity, if the expression is touched anyway.
- **Probe scope honesty (P2-12):** Phase 4.1's probe covers the *webhook* credential leg. It must
  either source the same file set as every subject it is cited for, or the plan must stop citing
  one probe as evidence for five units. With R1's drop-ins all five converge on the same file, so
  this resolves — but state it rather than assume it.

### Deliberately NOT taken

- **"Move §Root Cause Evidence out of the plan and into the PIR only."** Rejected. The planning
  session's context is discarded on return; the evidence must survive on disk in the artifact
  `/work` reads. The PIR will cite the plan rather than duplicate it.
- **"ADR-154 is n=1, cut it."** Partially rejected. E9 plus R1 give a class of **nine** files
  across two convergence classes, not one data point — and R1's copy-of-a-copy is the sharpest
  instance. ADR-154 moves to PR-B (per R5) but is not cut.

---

## Definition of Done (mapped)

| # | Requirement | Where satisfied |
|---|---|---|
| 1 | Root cause named with evidence pulled from telemetry, not inferred | §Root Cause Evidence (E1–E8), §Hypotheses |
| 2 | Fix landed, invisibility closed | Phases 2 + 4; ADR-154 |
| 3 | A real deploy reaches prod | AC25 (plus 7.4's environment-reviewer check if a gated dispatch is used) |
| 4 | Consecutive-release-failure alerting in place | Phase 5; AC14, AC26, AC27 |
| 5 | Post-mortem updated | Phase 6.1–6.2; AC28 |
