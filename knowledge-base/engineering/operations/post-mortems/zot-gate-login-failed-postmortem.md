---
title: "zot gate login_failed — the boot-baked htpasswd has no Terraform edge to the credential it bakes; 90 days of absent registry redundancy under a green fleet"
date: 2026-07-15
incident_pr: 6484
incident_window: "Latent since the registry host was introduced (#6122) — zot served ZERO pulls in 90 days (E2); nothing ever degraded from a working state. Observable window: first Sentry WEB-PLATFORM-5B 2026-07-14T21:11:28Z → last 2026-07-15T15:10:07Z (14 events, 100% zot_gate_reason=login_failed)."
recovery_at: "PENDING — the code fix is complete and multi-agent-reviewed in #6484, but merging applies NOTHING here (every zot-registry.tf resource is an OPERATOR_APPLIED_EXCLUSION, CTO ruling 2026-07-06). The gap closes only when the registry-host-replace dispatch applies and AC11 reports the first successful zot pull in the system's history."
suspected_change: "Latent since #6122 — no single change caused it. hcloud_server.registry's templatefile() passes only the non-secret usernames and ZERO references to random_password.*.result (the token values are deliberately kept out of user_data), and no replace_triggered_by existed. Terraform therefore has no data edge from the password to the host and cannot know the boot-baked /etc/zot/htpasswd is stale. Surfaced now only because #6424 (merged 2026-07-15T11:11:56Z) fixed an alarm threshold that could never fire."
brand_survival_threshold: aggregate pattern
status: ongoing
triggers:
  - availability (registry redundancy / self-hosted zot pull path — never realized as USER impact; but see the
    live-counterfactual note below: the redundancy's absence is being felt on the deploy path RIGHT NOW via #6400)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
# Classification rationale: availability/redundancy-only, and NOT REALIZED — this is a latent
# redundancy gap, not an outage. The ADR-096 GHCR fallback is atomic; every host booted the correct
# signed digest throughout and the pull path is dark (ZOT_ACTIVE=0 fleet-wide, E2). No user-facing
# path is reachable from this defect, so brand_survival_threshold is `aggregate pattern` (the
# fleet-wide loss of registry redundancy), NOT `single-user incident` — operator-confirmed at /go
# routing time. GDPR Art. 33/34 do NOT apply (both false, rationale `n/a`): this is an
# availability/redundancy gap with no personal-data dimension whatsoever. No personal data was
# exposed, accessed, altered, or lost. The zot host holds only OCI image blobs — no customer PII, no
# auth material for user accounts, no schema. The two credentials involved (zot-pull / zot-push) are
# machine registry tokens in an isolated Doppler config, and the Phase-1 probe added here emits a
# BOOLEAN and an HTTP status code only — never a token, never a hash of a token.
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

**This is not an outage. It is a latent redundancy gap, and the honest framing matters more than the
severity.**

The self-hosted zot OCI registry (Hetzner host, deny-all ingress, no SSH) exists to be the redundant
pull path for the platform's container images — the thing that keeps hosts deployable and
recoverable when GHCR is unavailable (ADR-096). Sentry `WEB-PLATFORM-5B` — `zot gate degraded
(login_failed) — configured but inactive, using GHCR` — fired on every deploy: 14 events, 100%
`zot_gate_reason=login_failed`. The `docker login` against zot was rejected every time, the gate
correctly declined to activate, and every host fell through to GHCR.

Three facts define the blast radius, and each is evidence-backed rather than asserted:

1. **zot served ZERO pulls in 90 days (E2).** It never worked. Nothing degraded from a working
   state — there is no "before" to have regressed from. This was a first-activation defect wearing
   the costume of a credential regression.
2. **ZERO user impact ever occurred.** The ADR-096 GHCR fallback is atomic; every host booted the
   correct signed digest throughout. `ZOT_ACTIVE=0` fleet-wide is the steady state, so the failing
   path was carrying no traffic to lose.
3. **What was actually absent is the redundancy itself.** Had GHCR degraded at any point in those
   90 days — the exact scenario zot was built to survive — every host would have failed to pull and
   the platform could not have deployed or recovered. **The fleet reported green the entire time.**

That third point is the incident. A registry mirror that has never served a pull is not redundancy;
it is a comment about redundancy. And the harm class is not hypothetical in kind: GHCR *did* deny
pulls on 2026-07-13/14, freezing the deploy pipeline for ~10+ hours
(`2026-07-14-web-platform-deploy-ghcr-pull-denial-outage-postmortem.md`, #6408) — roughly four hours
before the current registry host was even created. That outage is not attributable to this gap (see
§Where we got lucky for the honest accounting), but it settles the question of whether "GHCR
degrades" is a real event worth carrying redundancy for. It is, and the redundancy was not there.

## Why a no-user-impact gap gets a PIR

Stated explicitly so a future reader does not read this as severity inflation, and does not
mistake the precedent for "we write a PIR for every latent bug":

- **The operator's standing rule is "incident detected → PIR always"** — including one found
  incidentally, and including one with no realized impact. Detection is the trigger, not damage.
- **The `/ship` Incident-PIR gate fails-toward-PIR on ambiguity.** When the class is arguable, the
  cheap and correct move is to write the report.
- **The harm class is the one #6421's postmortem already records**
  (`2026-07-14-zot-registry-private-nic-absent-silent-outage-postmortem.md`): a redundant path that
  is silently absent while every dashboard is green. Recording it once and not the next time is how
  a pattern becomes invisible — and this is the *fourth consecutive* PR in this surface.

### The counterfactual is not hypothetical (updated at /ship, 2026-07-15)

This report was drafted arguing the harm was **latent**: "if GHCR degraded, every host would fail
to pull." That framing was already out of date when it was written.

**GHCR is degrading right now.** #6400 (P1, open) has the web host failing `image_pull_failed`
against GHCR: prod pinned to 0.214.7 / `e333a938` since **14:49Z**, two consecutive releases
(`v0.214.8`, `v0.214.9`) failed to cut over, and the next runtime PR is blocked. The images publish
to GHCR fine — the host cannot pull them. GHCR also denied pulls on 2026-07-13/14 (#6408), freezing
the pipeline ~10h, roughly four hours before this registry host was even created.

So "GHCR degrades" is a **live, recurring event class**, and the redundancy built to survive exactly
that has never once been armed. `pull_image_with_fallback` pulls **zot-primary** when
`ZOT_ACTIVE=1` and only falls through to GHCR otherwise — a working zot would have served those
pulls and #6400 would not have blocked a deploy.

Three honest caveats, because the temptation to overclaim here is exactly what this PR is about:

1. **This is not a fix for #6400.** That is a GHCR-side auth defect. Fixing the zot login does not
   touch it, and this report must not be read as closing it.
2. **Fixing the login is condition 1 of 3.** zot serves a pull only if (1) login works ← this
   incident; (2) zot holds the tag ← #6416; (3) the host reaches zot on the private net ←
   #6415 / ADR-115. Conditions 2 and 3 are open.
3. **It does not retroactively make this a user-impacting outage.** No user was reachable at any
   point; the deploy *pipeline* stalled, prod stayed up on the prior version. The severity
   classification (`aggregate pattern`, Art. 33/34 `false`) is unchanged.

What it does change is the reading of "latent". The gap was not waiting for a hypothetical failure —
it was already failing to cover a real one, silently, while the fleet reported green.

## Status

`ongoing` — deliberately, and this is the one status claim in the report worth reading twice. The
code fix is complete, multi-agent-reviewed, and green in #6484. **Merging it changes nothing on the
registry host.** Every `zot-registry.tf` resource is an `OPERATOR_APPLIED_EXCLUSION` (CTO ruling
2026-07-06, contract at `zot-registry.tf:15-21`), deliberately excluded from the per-PR CI `-target`
list because that path bridges over SSH to the existing web host and cannot provision a dedicated
one. The gap remains open until the sanctioned `registry-host-replace` dispatch applies and **AC11**
— zero new `WEB-PLATFORM-5B` events plus at least one `registry:zot` pull, the first successful zot
pull in the system's history — reports green. That is why #6484 carries `Ref`, not `Closes`.

## Symptom

- Sentry `WEB-PLATFORM-5B` on every deploy: 14 events, first `2026-07-14T21:11:28Z`, last
  `2026-07-15T15:10:07Z`, **100% `zot_gate_reason=login_failed`** (E1).
- `ZOT_ACTIVE` never becomes 1; every host silently takes the GHCR path and boots correctly.
- **Zero `registry:zot` and zero `registry:ghcr-fallback` issues in 90 days** (E2) — the absence
  that says zot has never served anything, and the reason "regression" was the wrong frame.
- The `login_failed` beacon could not say *why*: one undifferentiated bucket for bad-credential,
  authz-denial, transport, and TLS (see §The detection gap).

## Incident Timeline

- **Start time (detected):** 2026-07-15 ~15:2x UTC (operator, via the Sentry alert)
- **End time (recovered):** PENDING — gated on the `registry-host-replace` dispatch + AC11
- **Duration (MTTR):** open. The *latent* window is ≥90 days (E2); the code fix was authored,
  reviewed, and green the same day it was detected.

Order of events (load-bearing: the redaction sentinel scans this table; the Actor key feeds the Actor column):

| Actor | Time (UTC) | Action |
|---|---|---|
| system | ≥90 d prior | zot registry stood up (#6122) and has served **zero** pulls ever since (E2). The redundancy ADR-096 exists to provide does not exist; the fleet reports green throughout. |
| system | 2026-07-14 16:42:24 | Registry host `soleur-registry` created (Hetzner API, E6) — `status=running`, `private_net 10.0.1.30`. `/etc/zot/htpasswd` is baked **exactly once, here**, by cloud-init's `runcmd`, from the two Doppler tokens read via the Doppler CLI. Nothing ever rebuilds it. |
| system | 2026-07-14 21:11:28 | First `WEB-PLATFORM-5B` — 4 h 29 m after host creation (E1/E6). The beacon fires on every deploy from here on. **Nothing routes it to a human:** `sentry_issue_alert.zot_mirror_fallback_rate` carries `event_frequency value = 3`, which can never fire. |
| agent | 2026-07-15 11:11:56 | **#6424 merges — `event_frequency value 3 → 0`.** The rule's `filter_match = "any"` set includes `registry = zot-gate-degraded` (`issue-alerts.tf:1403-1410`), so the beacon can finally page. **This is the only reason the gap became detectable.** |
| agent | 2026-07-15 11:22:43 | #6421 merges (guard per-PR host creation + un-mask the silently-skipped zot mirror, ADR-114). Adjacent; does not reach the login. |
| agent | 2026-07-15 13:48:00 | #6452 merges (count all four fallback signals in the zot soak gate). Adjacent; does not reach the login. |
| system | 2026-07-15 14:31:01 | zot logs an HTTP-API access line (`session.go:137`, `User-Agent: docker/29.6.1`) at the **exact second** of a 5B event (E3) — zot is running, reachable, and *receiving* the login. Excludes firewall/route/TLS. |
| system | 2026-07-15 14:59:48 / 15:00:46 | `crane/0.20.2` and `cosign/v3.1.1` **authenticate successfully** to zot against the SAME `/etc/zot/htpasswd`, in the same window the pull credential is rejected (E4). **This is the discriminator.** |
| system | 2026-07-15 15:10:07 | Last (14th) `WEB-PLATFORM-5B` event. |
| human | 2026-07-15 ~15:2x | **Operator surfaces the Sentry alert** — the first human-visible signal in 90 days. |
| agent | 2026-07-15 | Evidence E1–E8 self-pulled (`hr-no-dashboard-eyeball-pull-data-yourself`); no step asked a human to fetch a log or open a dashboard. Root cause proven **structurally**, not inferred: `templatefile()` at `zot-registry.tf:248-279` (pre-fix) passes zero references to `random_password.*.result`, and `grep -n replace_triggered_by` → **zero hits**. |
| agent | 2026-07-15 | Fix implemented in #6484 (Phases 1/2/3 — probe first, in the same PR). Multi-agent review found **three P1s** the plan, the deepen pass, and a green suite all missed; mutation testing found **three guards vacuous while 22/22 green**. All fixed inline. |
| agent | 2026-07-15 | PENDING: `registry-host-replace` dispatch → AC10 (probe wired) → AC11 (the fix gate). |

## Participants and Systems Involved

- **Systems:** self-hosted zot OCI registry (Hetzner `soleur-registry`, `10.0.1.30:5000`, deny-all
  ingress, no SSH); `/etc/zot/htpasswd` (boot-baked, `cloud-init-registry.yml`); the two
  `random_password.zot_{pull,push}` credentials and their four `doppler_secret` copies
  (`soleur/prd` + `soleur-registry/prd`); `ci-deploy.sh`'s `zot_gate_and_login()`; Sentry EU
  (`jikigai-eu/web-platform`, `WEB-PLATFORM-5B`, `sentry_issue_alert.zot_mirror_fallback_rate`);
  Better Stack Logs (`SOLEUR_ZOT_DISK` self-report, source 2457081); the `registry-host-replace` CI
  dispatch and its destroy-guard.
- **Participants:** `agent` (Claude Code — evidence, diagnosis, fix, review); `human` (operator —
  surfaced the Sentry alert, confirmed the `aggregate pattern` threshold at /go routing). No end-user
  reporter, because no end user could have noticed.

## Detection (+ MTTD)

- **How detected:** monitoring — the operator surfaced Sentry `WEB-PLATFORM-5B` via the alert. Not
  an end-user report (no user-facing surface is reachable from this path).
- **MTTD (mean time to detect):** **≥90 days** against the true latent window (E2) — and this is the
  number the report exists to make legible. Against the *routable* signal it is ~4 h: the alarm that
  caught it was itself only fixed **hours** earlier.

**Give #6424 the credit it is owed.** Before it merged at 2026-07-15T11:11:56Z,
`sentry_issue_alert.zot_mirror_fallback_rate` carried `event_frequency value = 3`, which — given
Sentry's new-group short-circuit (`is_new and value > 1` → `False`) and a strict `>` comparison —
**could never fire**. #6424 changed one integer, `3 → 0`. The rule covers
`registry = zot-gate-degraded` in its `filter_match = "any"` set, so 5B became pageable on the first
event in the interval. **The alarm then worked exactly as designed, on a pre-existing gap it did not
cause, within hours of being repaired.** That is the good news in this report, and it is the whole
argument for fixing dead alarms *before* you have a reason to.

> **Precision worth keeping, because this report's own thesis demands it.** It is tempting to say
> "the gate was silent before #6424." It was not. The **beacon** was emitting from
> 2026-07-14T21:11:28Z — 14 hours of events sat *recorded* in Sentry before #6424 merged. What was
> missing was not the signal but the **route**: nothing turned a recorded event into a page. A
> recorded-but-unrouted signal is indistinguishable from silence to the only person who could act on
> it, and the distinction matters because the two have different fixes.

## Triggered by

system — a self-inflicted latent defect (a missing Terraform data edge, present since #6122) that
was never *triggered* at all in the user-facing sense. No user action, market movement, or provider
outage. It was *revealed* by a monitoring repair.

## Root-cause hypothesis (triage)

Triage-time competing hypotheses; the post-resolution final root cause lives in the 5-Whys section below.

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| H0 — firewall / private-net route to `10.0.1.30:5000` | deny-all host; the #6416/#6421 private-NIC class is live and adjacent | E3: zot logs a well-formed HTTP request from the deploying host's docker at the **exact failing second** | **EXCLUDED** (reachability established before any auth hypothesis, per `hr-ssh-diagnosis-verify-firewall`) |
| H1 — `insecure-registries` missing → docker attempts HTTPS | plausible on a fresh host | E8 (both web hosts have it) + E3 — an HTTPS ClientHello to an HTTP port does not produce a clean access log with a `docker/29.6.1` User-Agent | **EXCLUDED** |
| H2 — Doppler / tfstate credential drift | the obvious first guess for `login_failed` | E5: all three planes agree (tfstate == `soleur/prd` == `soleur-registry/prd`, sha256 `922cf93d…`, len 40) | **EXCLUDED** |
| H3 — **htpasswd `zot-pull` entry stale vs the current token** | uniquely explains **E2 + E4 + E5 together**; confirmed structurally by the absent `replace_triggered_by` and the token-free `templatefile()` | none | **CONFIRMED (structurally); AC11 is the behavioural gate** |
| H4 — zot `accessControl` denies `zot-pull` at `/v2/` (403 authz, not 401 authn) | the config *looks* like it gates `/v2/` | **FALSIFIED by measurement** — see below | **DEAD — never a live hypothesis** |

**H2 deserves a callout, because "verified" was doing no work.** Comparing Doppler to Doppler proves
nothing: both copies derive from the same `random_password`, so they agree **by construction** even
when both have drifted away from the host's baked htpasswd. The only credential comparison with
evidentiary value is *host-htpasswd vs Doppler* — which is exactly what no signal in the system could
answer, and exactly what the Phase-1 probe adds.

**H4 was falsified by running the thing.** Measured at /work against the *pinned* zot digest
(v2.1.2, `zot-registry.tf:55`) with this repo's exact `accessControl`: `docker login` issues exactly
one request — `GET /v2/` — and zot answers it **200 or 401, never 403**. A user with **zero**
accessControl policies still gets `Login Succeeded`; zot enforces authz at
`/v2/<repo>/manifests/<tag>` (measured: 403), which the login path never touches. So a broken
accessControl does not produce `login_failed` at all. The entire H3-vs-H4 apparatus — a conditional
Phase 2b, an enum arm, and two tests — was derived from **reading zot's config instead of measuring
zot**. One `docker run` settled it, and cost less than the apparatus did to write.

## Resolution

PR #6484 (fix-forward; no rollback exists or is needed — the path serves nothing). **The probe ships
in the same PR as the fix, not after** — see §The detection gap for why that ordering is the single
most load-bearing decision in this report.

1. **Phase 1 — make the failure discriminating (ships FIRST).**
   - `ci-deploy.sh`: the `docker login` stderr discard is gone. Stderr is captured to a **0600 temp,
     classified to a fixed enum, and destroyed**; only the enum and an HTTP status code cross the
     boundary (`zot_login_class`, `zot_login_http` on `zot_gate_degraded_event`). Raw stderr **never**
     reaches the payload — a registry error string can echo a username, so the enum is the only thing
     permitted out.
   - `authz_denied` narrowed to a literal `403` as a defensive tripwire; `transport` **widened** to
     the arms that actually fire on this fleet (`network is unreachable` from the private-NIC class,
     `connection reset` from zot OOM) — those were falling through to `unclassified`, the very bucket
     this PR exists to drain.
   - `host_id` threaded into the beacon (it had **none** — "which host" was unanswerable across 14
     events), reusing the `pull_failure_event` precedent from #6396/#6401.
   - `cloud-init-registry.yml`: the in-surface **htpasswd-divergence probe** in `zot-disk-heartbeat.sh`
     — `htpasswd -vb` verifies without printing, emitting `htpasswd_pull_matches` /
     `htpasswd_push_matches` as booleans on the existing `SOLEUR_ZOT_DISK` line. `unknown` is the
     **default**, and only exit code **3** maps to `false`: on `ubuntu:24.04`, `htpasswd -vb` returns
     `0`=match, `3`=mismatch, `6`=user absent, `1`=file unreadable, `127`=binary missing, and only 3
     is a real divergence. Collapsing every non-zero into `false` would report a confident "the
     credential diverged" when a cloud-init edit merely renamed the user — the exact inverse of the
     probe's job.
2. **Phase 2 — close the credential-convergence gap (the H3 fix).**
   - `zot-registry.tf:309-313`: `lifecycle.replace_triggered_by = [random_password.zot_pull,
     random_password.zot_push]` — **the missing edge**. Rotating either password now replaces the
     host, which re-bakes the htpasswd from the new value in the same apply. Safe by verification, not
     assertion: `random_password` has **no `keepers`** (zero grep hits), so it cannot fire on a routine
     apply — confirmed empirically by a real `terraform plan` in which `random_password.*` is absent.
   - `zot-registry.tf:324-328`: `depends_on` **generalized** to `doppler_secret.zot_pull_token_registry`
     and `doppler_secret.zot_push_token_registry`. The same missing-edge class had a second live
     instance: #6244 added this edge for *one* secret (`registry_betterstack_logs_token`) and never
     generalized it to the two that actually gate the bake. Without it a fresh stand-up races the
     htpasswd bake against the token write.
   - **The false comment was deleted, not contradicted.** `grep -c 're-propagates htpasswd + Doppler
     in ONE apply'` → **0**.
   - **Phase 2b (the H4 arm) was STRUCK** — it was gated on a verdict (`zot_login_http=403`) the probe
     can never emit. Phase 2's edges shipped regardless; they are proven latent defects whose
     justification never depended on the H3/H4 outcome.
3. **Phase 3 — regression tests.** Per-enum classification cases; a `tls_mismatch`/`403` must-not-
   collapse-into-`authn_rejected` assertion; a "stderr never reaches the payload" assertion; and
   attribute-scoped Terraform drift guards (see §What went wrong — the first drafts were vacuous).
4. **ADR-115 amended** — plus a **second normative blocker** bounding the *replace* primitive, an
   explicit git-data exclusion, and a new requirement that an ADR naming an edge must also name the
   apply that fires it (see §What went wrong).

## Recovery verification

**Not yet available, and the report will not pretend otherwise.** Verification rides the
`registry-host-replace` dispatch — a `gh workflow run` call this pipeline makes itself; it is **not**
an operator handoff (`hr-exhaust-all-automated-options-before`):

```
gh workflow run apply-web-platform-infra.yml \
  -f apply_target=registry-host-replace -f reason='<zot gate login_failed — …>'
```

- **AC10 (probe wiring / liveness — NOT fix-confirmation).** The next `SOLEUR_ZOT_DISK` self-report
  carries `htpasswd_pull_matches` / `htpasswd_push_matches` as well-formed booleans. No SSH:
  `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 30m --grep SOLEUR_ZOT_DISK --limit 1`.
- **AC11 (THE fix gate).** The next deploy emits **zero** new `WEB-PLATFORM-5B` events and **at least
  one** `registry:zot` pull — *the first successful zot pull in the system's history* (E2). Verified
  via the Sentry EU org-scoped issues API.
- **AC12 (do not conflate).** AC11 requires the mirror to actually **hold** the image. A 404 rather
  than a 401 is #6416 (mirror backfill), not this defect.

**Pre-merge green:** `terraform validate`; a read-only `terraform plan` piped through the **real**
sourced destroy-guard returned `out_of_scope=0 store_destroyed=0 secret_destroyed=0
volume_bad_update=0 server_replaced=1 nic_recreated=1 attachment_recreated=1 firewall_ok=1` →
`registry_host_replace_gate: PASS`. That single read-only run settled AC8, the new `depends_on`
interaction with the 6-member allow-set, **and** the "no spurious rotation" claim — empirically,
in one shot, instead of by argument.

> **Why AC10 is NOT the proof, stated plainly because the plan got this wrong.** The probe lives in
> `cloud-init-registry.yml` → `user_data`, so **shipping the probe IS the change that forces the
> replace that re-bakes the htpasswd**. `htpasswd_pull_matches=true` is the expected post-replace
> reading under *both* H3 and H4 — it discriminates nothing. There is **no pre-fix reading of
> `false` to be had**: the instrument ships inside the mutation's own payload, so its first
> observation is post-mutation by construction. The probe's enduring value is prospective — it is
> what makes a **future** rotation's divergence visible within 5 minutes instead of never.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the zot gate report `login_failed` on every deploy?** zot rejected the `docker login`
   presented by `zot_gate_and_login()` — the `zot-pull` credential the host's `/etc/zot/htpasswd`
   accepts is not the `zot-pull` credential Doppler hands the client.
2. **Why did the htpasswd and Doppler disagree, when all three credential planes agree (E5)?**
   `/etc/zot/htpasswd` is baked **exactly once**, at boot, by cloud-init's `runcmd`. Nothing —
   no Terraform edge, no convergence loop, no cron — ever rebuilds it. Once baked, it is frozen for
   the life of the host while the control plane moves on without it.
3. **Why did Terraform not replace the host when the credential changed?** Because **it cannot know
   the bake is stale.** `hcloud_server.registry`'s `templatefile()` passes only the non-secret
   *usernames* (`zot_pull_user`, `zot_push_user`) and **zero references to
   `random_password.*.result`** — the token values are deliberately kept out of `user_data`, and the
   code says so explicitly. That isolation is *correct*. Its unintended consequence is that Terraform
   has **no data edge** from the password to the host — and no `replace_triggered_by` existed to
   supply one (`grep` → zero hits). The password and the host that bakes it were, to Terraform, two
   unrelated resources.
4. **Why did nobody notice for 90 days?** Two independent blinds, both of which had to hold:
   the **alarm** covering the beacon carried `event_frequency value = 3` and could never fire
   (#6424), so the signal was recorded but never routed; and the **beacon itself could not say why**
   — `docker login … >/dev/null 2>&1` destroyed the deciding datum at the source (see §The detection
   gap). The fleet was green because nothing was asking a question that could come back false.
5. **Why did three consecutive fixes in this exact area (#6452, #6424, #6421) never look here?**
   Because a comment said they did not need to. `zot-registry.tf:78-80` (pre-fix) claimed rotation
   *"re-propagates htpasswd + Doppler in ONE apply."* **The first half was true; the second half
   described an edge no resource declares.** Anyone auditing the rotation story read that sentence
   and stopped — three times.

**Final root cause:** the boot-baked `/etc/zot/htpasswd` had **no Terraform edge to the credential it
bakes** (`templatefile()` carries only usernames; no `replace_triggered_by`; `depends_on` naming one
secret out of three), so a per-entry credential divergence was structurally invisible and permanent.
**A false comment asserting that edge is what let it ship, and is why three prior fixes in this area
never looked here.** The discriminator that proves the shape is E4: crane/cosign **PUSH**
authenticates against the *same* htpasswd in the *same window* the pull credential is rejected — one
entry current, one stale, which is the shape only a per-entry divergence produces. (A wholesale-stale
or missing htpasswd would have broken both.)

> **Scope note, kept honest.** The *structural* cause is proven; the *provenance* of this particular
> host's divergence is not fully discriminable from outside, and the report does not claim it is.
> Both live instances of the missing edge — a rotation that never replaced the host, and a fresh
> stand-up that raced the bake against the token write (the `depends_on` gap) — produce exactly this
> signature, and **both are closed by the same fix**. AC11b renders the behavioural verdict after the
> replace, not before it.

## Versions of Components

- **Version(s) that triggered the outage:** `zot-registry.tf` as of the pre-#6484 `main` — no
  `lifecycle.replace_triggered_by`; `depends_on` naming only `doppler_secret.registry_betterstack_logs_token`;
  the false rotation comment at `:78-80`; `ci-deploy.sh`'s `docker login … >/dev/null 2>&1`;
  `cloud-init-registry.yml` with no htpasswd probe. Latent since the registry host was introduced
  (#6122).
- **Version(s) that restored the service:** PR #6484 — `replace_triggered_by` on both
  `random_password.zot_{pull,push}`; `depends_on` generalized to all three secrets; the false comment
  deleted; login stderr captured + classified to an enum with `host_id`; the `htpasswd -vb`
  divergence probe; ADR-115 amended with a second normative blocker. **Not yet applied** — pending the
  `registry-host-replace` dispatch.

## Impact details

### Services Impacted

- **Registry redundancy (ADR-096): ABSENT for ≥90 days.** This is the entire impact. The self-hosted
  zot mirror — the platform's answer to "what if GHCR is down" — has never served a pull. The
  capability was on the architecture diagram and not in the world.
- **The ADR-096 Phase-5 cutover:** the sharpest consequence, and the one that would have hurt. The
  cutover flips the fleet's **primary** pull path onto zot. It would have been made onto a path that
  had **never once worked**, on the strength of a green fleet.
- **Image serving to running hosts:** **NOT impacted.** GHCR fallback is atomic and covered every
  pull; prod `/health` stayed 200; every host booted the correct signed digest.
- **The deploy pipeline:** not impacted by *this* defect. The gate correctly declines to activate and
  falls through — the gate's *logic* is sound; the gap is that its failure was undiagnosable and the
  credential could silently diverge.

### Customer Impact (by role)

Per learning `2026-05-06-user-impact-section-by-role-not-surface.md` — enumerate by USER ROLE, not by surface.

- Prospect: **none** — no customer-facing surface is reachable from this path.
- Authenticated app user: **none** — serving fully covered by the atomic GHCR fallback; no downtime.
- Legal-document signer: **none**.
- Admin via Access: **none**.
- Billing customer: **none**.
- OAuth installation owner: **none**.

**Zero user impact ever occurred, and none was reachable.** The blast radius is the internal
registry-redundancy layer (an aggregate pattern), not any single named user — which is precisely why
`brand_survival_threshold` is `aggregate pattern` and not `single-user incident`. The risk this
report records is **counterfactual**: it is what would have happened had GHCR degraded, not what did
happen to anyone.

### Revenue Impact

None. No customer-facing outage, no billing surface touched, no SLA breach.

### Team Impact

**Three consecutive fixes landed in this surface (#6452, #6424, #6421) without reaching the login** —
each authored while the deciding signal sat discarded at `ci-deploy.sh`, and each waved past the
rotation story by the same false comment. Cost: three cycles that improved the neighbourhood and left
the defect. The fourth cycle (this one) spent significant effort on an H3-vs-H4 apparatus that a
single `docker run` dissolved, and on three drift guards that were green and vacuous.

## Lessons Learned

### Where we got lucky

- **GHCR did not fail while zot was the redundancy — but the near-miss is real and recent.** GHCR
  denied pulls on 2026-07-13/14 and froze the deploy pipeline for ~10+ hours (#6408), roughly four
  hours before the current registry host was created. **This report does not claim that outage is
  attributable to this gap** — the deploy path pulls from GHCR by design pre-cutover, and whether a
  working zot would have covered it also depends on the mirror actually holding the image (#6416).
  What it does establish is that "GHCR degrades" is a *live, recent, ~10-hour* event class, not a
  hypothetical — and for 90 days the redundancy built to answer it did not exist.
- **The gap was found before the Phase-5 cutover, not after.** Cutting over would have moved the
  fleet's primary pull path onto a registry that had never served a pull. Found now, the fix costs a
  host replace on a path serving zero traffic — *"the cheapest possible moment to make this change."*
  Found after, it is a fleet-wide deploy outage.
- **The store volume is disposable by design** (`model.c4:260` — a GHCR mirror that re-fills from CI's
  dual-push), which is the entire reason `replace_triggered_by` is *safe* here. The same primitive on
  `random_password.git_data_luks` would permanently brick the fleet's most irreplaceable data. Same
  primitive, opposite blast radius — and the ADR amendment nearly mandated the lethal one.

### What went well

- **The alarm caught it, and the alarm had been broken until hours earlier.** #6424 (merged
  2026-07-15T11:11:56Z) changed `event_frequency value 3 → 0`; the rule fired on a pre-existing gap it
  did not cause, within hours of being repaired, and did so **exactly as designed**. Fixing a dead
  alarm paid for itself the same day. If there is one thing to carry forward from this report, it is
  that a threshold that can never fire is not a monitor — and you cannot know what it is hiding until
  you fix it.
- **The probe shipped in the same PR as the fix, not after** — breaking the three-blind-fixes streak
  by construction rather than by intention.
- **Every real catch was an execution, not a reading.** A `docker run` of the pinned image killed H4;
  a mutation battery that *relocated* attributes killed three vacuous guards; a real `terraform plan`
  through the real destroy-guard settled AC8 and the `depends_on` interaction; review agents prompted
  to **re-derive** rather than confirm found three P1s a green suite had blessed.
- **All evidence was self-pulled** (`hr-no-dashboard-eyeball-pull-data-yourself`). No step asked a
  human to fetch a log, open a dashboard, or run a probe.

### What went wrong

- **A comment documented a guarantee the code did not provide — and that comment *is* the bug.**
  `zot-registry.tf:78-80` claimed rotation *"re-propagates htpasswd + Doppler in ONE apply"* against
  an edge no resource declared. It is why three prior fixes never looked here. The fix **deletes** it
  rather than contradicting it.
- **`docker login … >/dev/null 2>&1` destroyed the one datum that decides the incident** — a
  silent-fallback anti-pattern on a diagnostic path (`cq-silent-fallback-must-mirror-to-sentry` in
  spirit). See §The detection gap.
- **The plan reasoned about a vendored service's response codes from its config file.** H4, Phase 2b,
  an enum arm, and two tests were built on a 403 the pinned zot never returns. Worse, the
  `authz_denied` arm as first written had **zero** true positives and one real false positive — bare
  `denied` stole `connect: permission denied` (a *socket* error) from `transport`, while the arms that
  actually fire on this fleet fell through to `unclassified`, **the exact bucket the PR existed to
  drain**.
- **The observability probe would have taken the telemetry line it rode on dark.** `zot-disk-heartbeat.sh`
  runs `set -u`; the first draft expanded `"$ZOT_PULL_TOKEN"` bare, so an unset token raises `unbound
  variable` and **exits before `$LINE` is built** — killing the entire `SOLEUR_ZOT_DISK` self-report
  (disk, OOM, boot_id, everything) and bypassing the trailing `exit 0` that exists so the cron can
  never wedge. `|| HTP_PULL=false` does not rescue an expansion error. Since heartbeat **absence** is
  itself an alarm, it would have paged *"host down"* when only the probe broke. The `unknown` guards
  written for exactly that case sat **eight lines too late** — dead code that reads as coverage.
- **The ADR amendment would have mandated a git-data data-loss landmine.** A class-wide MUST inside an
  ADR whose Status says *"registry host only"*, it would have required `replace_triggered_by =
  [random_password.git_data_luks]` — replacing the host on a passphrase rotation and `luksOpen`-ing
  the **new** key against volumes encrypted with the **old** one, permanently bricking the fleet's
  most irreplaceable data. **The PR's own comment pointed straight at it** (*"Mirrors
  `random_password.git_data_luks`"*), and the existing normative blocker did not reach the replace
  primitive.
- **Three drift guards were vacuous while the suite was 22/22 green.** (a) Each assertion grepped the
  whole ~90-line `hcloud_server.registry` block, so moving `random_password.zot_pull` from
  `replace_triggered_by` into `depends_on` — a plausible tidy-up — left the suite green while the
  assertion literally named *"replace_triggered_by names random_password.zot_pull"* was **FALSE**, and
  rotating the pull token no longer replaced the host: **the bug the file exists to guard, fully
  reintroduced, under a green guard.** (b) The comment strip was full-line only, so with zero
  `lifecycle`/`depends_on` and the tokens named in *trailing* comments the suite passed with **zero
  HCL** — under a comment claiming it could not. (c) `grep '"host_id":'` matches `"host_id":""`
  because jq always emits the key.
- **`git grep -n 'target='` answered the wrong question, and the plan's apply path was backwards
  because of it.** The grep *passed* while its conclusion was false: both hits are inside
  `workflow_dispatch`-gated jobs, and every `zot-registry.tf` resource is an
  `OPERATOR_APPLIED_EXCLUSION`. **Merging applies nothing.** AC10/AC11 would have "verified" a fix
  that had never been applied.

> **The through-line, and the reason this report is worth its length.** Every one of these was a
> **claim that a green signal appeared to support** — a comment claiming an edge, a hypothesis
> claiming a response code, an ADR claiming a scope, a test claiming an invariant, a grep claiming an
> apply path. The plan's own thesis — *"a comment that documents a guarantee the code does not
> provide is what let this ship"* — turned out to describe the plan, the implementation, the ADR, and
> the tests **as much as it described the original bug**. An artifact authored to fix a false claim is
> **primed to make one**: the author is deep in a corrected model, writing confident replacement
> prose, and the green signal in front of them is measuring a neighbour of the property they mean.
> This is the **fourth consecutive session** to ship this class (#6421, #6424, #6452, now this one),
> every one authored with the prior learnings in context. **The prose control does not work.** What
> caught all of these was mechanical: an execution, not a reading.

## The detection gap

**The most valuable section in this report, because it is the part that generalizes.** The
90-day invisibility was not bad luck. It was designed in, one reasonable-looking decision at a time.

**The one datum that decides this incident was destroyed at the source.** `ci-deploy.sh` ran:

```sh
docker login "$ZOT_REGISTRY_URL" … >/dev/null 2>&1
```

zot answers a failed login with a specific status and a specific reason. That answer — the single
fact that separates *bad credential* from *authz denial* from *transport* from *TLS mismatch* — was
written to `/dev/null` before anything could read it. `login_failed` was therefore **one
undifferentiated bucket for four unrelated failure classes**, and the beacon fired 14 times saying
precisely nothing beyond "it didn't work."

The discard was not careless — it was *justified in a comment*, as a **security** rationale: `so no
trace/secret leaks`. That is the trap worth naming. A defensible-sounding privacy instinct silently
bought 90 days of undiagnosability, and the comment made the tradeoff look settled to every reader
who came after. **The real answer was never "discard or leak" — it was `classify`:** capture stderr
to a 0600 temp, map it to a fixed enum, destroy the temp, and let only the enum and a status code
cross the boundary. Both properties, at once. Nobody asked the question because the comment had
already answered it. *(And in the purest instance of this report's through-line: the first draft of
this very fix left that stale comment in place, still asserting a security property the diff had just
falsified.)*

Three more blinds compounded it, and **all four had to hold**:

- **The beacon carried no `host_id`.** Across 14 events, "which host" was unanswerable. The tag
  precedent (`pull_failure_event`, #6396/#6401) already existed in the same file and was not reused.
- **The registry host is deny-all / no-SSH**, so zot's own auth log — which *does* record the answer
  — is never shipped. The one place the truth existed was the one place nothing could read
  (`hr-no-ssh-fallback-in-runbooks` forbids the shortcut, correctly).
- **The alarm could not fire.** `event_frequency value = 3` meant even a perfect beacon paged nobody.

**The compounding is the lesson.** Any *one* of these would have been survivable: a discarding beacon
that still pages, a paging alarm over a beacon that can say why, an unattributed event on a
diagnosable host. Together they made a fleet-wide capability absent for 90 days and left the fleet
reporting green — because **a system with no signal that can come back false will always look
healthy.** Green was not evidence of health; it was the absence of a question.

**Three consecutive fixes (#6452, #6424, #6421) landed in this surface while the deciding signal
stayed discarded.** That is why the fix ships the discriminating probe in the **same PR**, not after
it — per `2026-07-01-blind-surface-needs-structured-probe-before-nth-fix.md`, a fourth blind fix
would have repeated the exact pattern the first three established. The ordering is not tidiness. It
is the only thing that makes the fix *confirmable* rather than *asserted*, and it is the one
structural change here that would have prevented this incident had it been in place 90 days ago.

## Action Items & Follow-ups

Every action item and follow-up so this incident cannot recur.

The missing Terraform edges (`replace_triggered_by`, the generalized `depends_on`), the deleted false
comment, the login-stderr classifier + `host_id`, the `htpasswd -vb` divergence probe, the ADR-115
amendment + second normative blocker, and the attribute-scoped drift guards **all shipped in the
source PR (#6484)**.

**The post-apply proof is deliberately NOT a tracked row**, and the reason is worth stating rather
than filing: it is the pipeline's own next step, not a hand-off. This pipeline fires the
`registry-host-replace` dispatch itself (`gh workflow run`) and then reads AC10/AC11 back out of
Better Stack and Sentry with no SSH and no human — per `hr-exhaust-all-automated-options-before`, an
action the agent performs is not a follow-up. **AC11b's H3/H4 verdict is only evaluable after that
dispatch applies**, which is exactly why #6484 carries `Ref` rather than `Closes`: closure is gated
on the post-apply proof, and this PIR's `status: ongoing` stays honest until it lands.

The residual tracked items are follow-ups this session **discovered** but deliberately did not fold
in — each is a design task with its own false-positive profile, not a line to bolt on:

| Issue | Action | Status |
|---|---|---|
| #6416 | Restore the redundancy this incident is about: web-2 has no private-net IP, so the zot mirror **push** is unreachable and the store may not hold the image a pull needs. AC11 (the first successful zot pull) requires both a working login **and** a populated mirror — this defect closes the login half only. AC12 encodes the discriminator (a pull 404 is #6416, not a recurrence of this) so the two are never conflated. | open (blocks full ADR-096 redundancy) |
| #6495 | The one-shot Step 0a.5 collision gate has **no `MERGED` branch**, so `gh issue view` on a PR number returns `state=MERGED`, matches neither the CLOSED-abort nor the OPEN-probe arm, and **every PR-number reference falls through silently**. This session's citations passed that gate **only by accident**. Until fixed, pass issue numbers, never PR numbers, and never rely on this gate to catch a contextual citation. | open (tracked) |
| #6496 | `md-to-mrkdwn` ReDoS test 39 is a **wall-clock** assertion (*"well under 1s"*), which reds `test-all.sh` under load (6 agents + docker + terraform concurrently); 45/45 in isolation — not a regression. A timing threshold measures the host, not the code; re-assert on input-size scaling or a step/backtrack budget. | open (tracked) |
