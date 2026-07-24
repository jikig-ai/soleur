# ADR-096: Migrate the container registry off GHCR to a self-hosted zot (Hetzner, volume-backed)

- **Status:** Adopting
- **Date:** 2026-07-07
- **Issue:** [#6122](https://github.com/jikig-ai/soleur/issues/6122)
- **Supersedes:** [ADR-088](./ADR-088-control-plane-installation-token-minter-for-private-ghcr-reads.md) (the GHCR App installation-token minter — GHCR refuses App tokens for `docker pull`, confirmed platform limitation)
- **Lineage:** [ADR-068](./ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md) (dedicated-host + private-network precedent this mirrors) · [ADR-087](./ADR-087-cosign-deploy-verify-host-net-ephemeral-verifier-over-private-ghcr.md) (cosign keyless sign + offline verify, preserved unchanged) · [ADR-052](./ADR-052-container-egress-firewall-docker-user-allowlist.md) (restricted-egress firewall the registry must live within)

## Status

**Adopting.** The IaC foundations (Phase 1), dual-push (Phase 2), and the dark-launch pull-site
flip (Phase 3) are merged. The flip is inert until the operator provisions (1.8) + backfills
(1.9) zot and the entry gate (`zot-entry-gate.sh`) passes. This ADR flips to **accepted** after
the Phase-5 soak (`zot-soak-6122.sh`: ≥7 days, zero fallback events across all four watched
signals, sufficient zot sample — necessary but not sufficient; see the alarm-parity note below)
and GHCR-push retirement (5.3–5.5).

## Context

Hetzner hosts must `docker pull` the private platform images (`soleur-web-platform`,
`soleur-inngest-bootstrap`) at boot and on every rolling deploy, using a **zero-touch,
control-plane-minted credential** (no human PAT on the pull path). The chosen mechanism —
ADR-088's Inngest minter issuing a GitHub App installation token — is **infeasible**: GHCR does
not accept App installation tokens for `docker pull` (GitHub platform limitation, community
discussion #171423, no ETA; verified in #6073). The only GHCR credentials that pull are a user
**classic PAT** (browser-only creation → not machine-automatable) and the Actions
**`GITHUB_TOKEN`** (workflow-scoped, absent at host boot). GHCR therefore *structurally cannot*
deliver a zero-touch machine identity. The system currently runs on an interim classic PAT with
the minter disabled — the exact fragility this migration removes.

## Decision

Stand up **zot** (the CNCF OCI-native registry) on a **dedicated Hetzner host** (`cax11`, ARM64),
**volume-backed** local-fs storage, on the existing private network (`10.0.1.30:5000`), behind
the deny-all-public firewall — mirroring the **git-data** dedicated-host model (ADR-068), NOT a
managed registry. Then:

1. **Push (Phase 2):** CI dual-pushes both images GHCR → zot. The web image is `crane copy`d
   runner-side (digest-preserving) after the GHCR push; the inngest image is `docker tag`+push.
   The zot digest is cosign-signed (same digest, same keyless identity). CI reaches the
   private-net registry over a **Cloudflare Tunnel + Access** bridge on the existing web tunnel
   (no public port opens; no cloudflared on the registry host) — see the CTO's second ruling.
2. **Pull (Phase 3):** every pull site prefers zot, **dark-launch gated** — it attempts zot only
   when `ZOT_REGISTRY_URL` is configured AND a `/v2/` probe answers AND the pull login succeeds,
   else it falls straight through to the unchanged private-GHCR path. Image ref + docker auth +
   cosign `.sig` target move **atomically** (whichever registry serves the pull, verify and run
   follow it). zot is plain-HTTP on the private net, so a zot-pulled digest needs
   `insecure-registries` (Edge A) + cosign `--allow-insecure-registry` (Edge B); cosign
   digest-pinning is the integrity guard, not TLS.

   > **Interim-GHCR pull-recovery contract (normative, #6400).** On the interim GHCR
   > pull path (live as break-glass until the Phase-5 GHCR retirement), **`docker login`
   > success is NOT proof of `docker pull` capability.** A credential that logs in but
   > cannot pull — a GitHub App installation token (the exact ADR-088 limitation), or
   > any login/pull capability split (a rotated/revoked baked snapshot that still
   > login-succeeds) — makes login-outcome-gated recovery a **false gate**: the login
   > passes, recovery is skipped, and the pull denies. The host therefore MUST re-fetch
   > the `prd` GHCR credential, `docker login` again, and **retry the pull once on a
   > `docker pull` auth-denial**, not only on a login **failure**. Implemented at the
   > pull site (`ci-deploy.sh` `_ghcr_pull_or_recover`), fail-open (a recovery miss leaves
   > the unchanged `image_pull_failed` terminal state), retry exactly once. This contract
   > retires with the GHCR pull path at Phase 5.
   >
   > **Transient-retry co-tenant (#6525).** The same `_ghcr_pull_or_recover` gate also
   > absorbs a **transient/network** first-attempt pull failure (timeout, connection reset,
   > EOF, no-such-host, registry 5xx) with a bounded capped backoff
   > (`PULL_TRANSIENT_RETRY_SLEEPS`, default 2 retries, ≤6 s/leg), emitting
   > `recovery_stage=transient_recovered` on a save and `transient_exhausted` on a
   > fail-closed exhaustion. It is a sibling of the auth recovery above — same one-level
   > retry, same fail-open both-registries semantics — and **retires together with it at
   > Phase 5** (the retirement structurally subsumes both by deleting the GHCR pull leg).
3. **cosign (Phase 4):** unchanged trust anchor — same pinned cosign SHA, same offline
   `trusted_root.json`, same GitHub-Actions-OIDC identity regexp. Registry-agnostic (Phase-0
   proved a read-only user fetches a zot-stored `.sig` and gc does not reap it).
4. **Cutover (Phase 5):** dual-push → validate zot pull E2E → flip (dark) → soak → retire GHCR
   push + egress + the interim PAT. GHCR stays break-glass warm through the entire soak.

### Registry-choice alternatives (7)

| # | Option | Verdict | Why |
|---|--------|---------|-----|
| 1 | GHCR App installation-token minter (ADR-088) | **Rejected** | GHCR refuses App tokens for `docker pull` — the whole premise is impossible. |
| 2 | GHCR user classic PAT (make it permanent) | **Rejected** | Browser-only creation, no machine rotation → not zero-touch; this is the fragility we are escaping (TR5 exposed PAT). |
| 3 | GHCR Actions `GITHUB_TOKEN` | **Rejected** | Workflow-scoped only; unavailable at host boot/deploy, which is exactly the pull path that needs a credential. |
| 4 | **Self-hosted zot, dedicated Hetzner host, volume-backed (CHOSEN)** | **Chosen** | OCI-native single binary; control-plane-minted htpasswd/JWT cred; lives inside the restricted-egress private net (G4); mirrors git-data (ADR-068); Phase-0 proved read-only ACL + cosign gc-safety + `crane` backfill. |
| 5 | Self-hosted zot with Cloudflare R2 / S3 backend | **Deferred** | FR1's original intent; local-fs won for v1 — durability = CI-reproducibility (images rebuildable, backfill re-runnable), and an R2 spike + host-side S3 creds expand blast radius for no v1 benefit. Revisit at scale (NG3). |
| 6 | Managed registry (Docker Hub / ECR / GCP AR / Quay) | **Rejected** | Introduces a new external vendor + public egress dependency (violates ADR-052), still leaves a machine-credential-delivery problem, and adds recurring cost + a new outage surface on the boot path. |
| 7 | Harbor (or other heavyweight self-hosted registry) | **Rejected** | Multi-service (DB, Redis, job service) — far heavier to run + patch than zot's single binary for a 2-image fleet; zot is OCI-native and cosign-gc-safe as proven in Phase 0. |

### Cold-boot-dependency statement

zot becomes a **boot-path dependency**: a fresh host (or a rolling deploy) that must pull an
image now depends on zot being reachable. This is a deliberately-accepted SPOF, mitigated on four
independent axes so it never silently gates a host:

- **Automatic degrade:** the dark-launch gate falls through to the still-dual-pushed GHCR path on
  any zot miss (probe fail / login fail / pull fail) — a zot outage degrades latency, not
  availability, for the entire soak + break-glass period.
- **Loud, no-SSH signal:** every fallback emits a Sentry `registry:"ghcr-fallback"` /
  `stage:"inngest_ghcr_fallback"` event (the fallback-rate alarm pages on the first one).
  **Correction (#6285):** zot liveness was assigned here to a `betteruptime_heartbeat.registry_prd`
  push beat "that pages if zot stops beating — before it can gate a boot (TR3)". **That layer did
  not exist:** `ZOT_HEARTBEAT_URL` (`zot-registry.tf`, the `doppler_secret.zot_heartbeat_url_prd`
  definition) had **zero consumers** repo-wide — no pinger cron was ever written — and the resource
  ships `paused = true`. Live evidence: 31 `zot-gate-degraded (probe_unreachable)` events over the 4
  days to 2026-07-15, none of which paged anything. Until the pinger shipped,
  `sentry_issue_alert.zot_mirror_fallback_rate` was the **only** zot-liveness coverage — which is why
  its threshold being unreachable (#6285) mattered. (`paused` is under `ignore_changes`, so the live
  pause state is not verifiable from the repo.)

  **Feeder shipped (#6537, 2026-07-16 — [ADR-117](./ADR-117-executable-heartbeat-arming.md)):** the
  layer now exists, but **not** as the web-host probe cron assumed above. It is an **on-host** systemd
  timer shipped in the registry's own cloud-init (`zot-liveness-heartbeat.timer`), pinging only while
  zot answers on the host's **private IP** — never loopback, because zot binds `0.0.0.0` and a
  loopback probe answers on a host holding no private NIC (#6400's blindness). It bakes the URL via
  `templatefile`, so `ZOT_HEARTBEAT_URL` still has zero consumers by design; that secret is reserved
  for the off-host probe.

  **NOT YET ARMED as of this edit.** The feeder reaches the host only on a fresh boot (cloud-init is
  per-instance), so `registry_prd` stays **paused** until #6537's post-merge phase reprovisions the
  host, measures a real beat, and *then* unpauses via a one-time API PATCH — never before (#6210).
  Until that lands, zot liveness coverage is **unchanged** from the paragraph above. This sentence is
  deliberately in the future tense: writing "is armed" before the beat is measured would be the same
  species of false arming claim that #6537 exists to correct — and no static check would catch it
  (the guard reads source `paused`, which `ignore_changes` decouples from live).

  Two scoping corrections to the note above, both of which read as coverage and are not:
  `registry_disk_prd` pings on `df` alone, so it alarms **host** death by absence but stays green
  with zot dead; and the **consumer-perspective** probe (can a client reach zot over the private
  net?) is still unbuilt — it remains #6438 §1. The on-host beat closes "zot dead, host alive", and
  nothing more.
  - *CI push side (#6274):* the CI dual-push mirror step is **explicitly non-blocking**
    (`continue-on-error: true` + an `exit 0` inner shell + a bounded retry to self-heal a transient
    CF-tunnel reset) — a mirror failure degrades zot redundancy, never the release/build verdict
    (consistent with "latency, not availability" above). A persistent miss is loud via a CI-level
    degraded signal: `mirror_status=degraded` → `::warning::` + step summary (both workflows) + a
    ⚠️ line on the Slack release message (`reusable-release.yml`; #6278 added the same ⚠️ to
    `build-inngest-bootstrap-image.yml`). The *live* fallback-rate Sentry alarm the bullet above
    references is now **provisioned in #6278** — `sentry_issue_alert.zot_mirror_fallback_rate`
    (`issue-alerts.tf`), an `event_frequency` count > 0/1h (fire-on-first) over `filter_match="any"`
    across the four runtime signals (`registry:{ghcr-fallback,zot-gate-degraded}`,
    `stage:{inngest_ghcr_fallback,app_ghcr_fallback}`). **Its threshold shipped as > 3/1h and could
    never fire** — the count is per Sentry issue-group, `registry_pull_event` mints a fresh group per
    deploy (the tag is in the message), so the per-group count is bounded by fleet size, not a rate;
    #6285 corrected it to 0, the only fleet-independent setting (see the resource comment). Parity:
    `zot-soak-6122.sh` FAILs on ≥1 event across the **same five signals** this alarm matches, pinned
    by `sentry-zot-mirror-fallback-alert-op-contract.test.ts`. **This parity claim was FALSE from
    #6278 until #6435:** the soak queried only `registry:"ghcr-fallback"` and
    `stage:"inngest_ghcr_fallback"` — `registry:"zot-gate-degraded"` and `stage:"app_ghcr_fallback"`
    were counted by nothing, so an intermittently-degraded fleet could PASS the soak. Corrected there;
    recorded rather than silently edited, because the earlier text asserted the coverage it lacked.
    **Scope of the corrected claim — do NOT restate this as "the gate matches the alarm" and stop:**
    window/threshold parity is **not** pinned (the alarm is a 1h-rolling per-issue-group count; the
    soak is a flat count over `START..now`); the soak's FAIL set covers **five of the seven KNOWN** ways
    the fleet can end up GHCR-served. ⚠ *Known*, not total — the count went **6 → 7 by discovery inside
    #6462** (nobody had looked at the dedicated inngest host until then), which is direct evidence the
    enumeration is **not closed**. Treat 7 as a lower bound and the ratio as *what we can currently see*,
    never *what exists*. For the same reason "machine-enforced" (below) means enforced against **accident**
    — a deliberate close of #6500 with the code still GHCR-only is caught by the soak's code-corroboration
    conjunct, but nothing defends against an 8th path nobody has found.

    **Amended by #6462 — read the RATIO, not the delta.** #6462 added `stage:"app_ghcr_served"` (a
    5th FAIL signal, covering the fresh-boot `/v2/` probe-miss path that previously emitted nothing)
    and `stage:"app_zot"` (the missing **denominator** — a liveness beacon that makes "0 fallbacks"
    distinguishable from "no fresh boot happened"). It also **surfaced a seventh path**. So coverage
    moved **4-of-6 → 5-of-7**: the numerator and the denominator both rose, and the count of
    known-uncovered paths is **unchanged at 2**. This is deliberately NOT restated as "COVERED" —
    the passage above records that this ADR already asserted coverage it lacked once, and a reader
    must be able to see the residual count without inferring it from "+1 signal".

    The two remaining uncovered paths:
    - **Sentry-dark** (#6437) — `ci-deploy.sh` returns early before every `zot_gate_degraded_event`
      call site when doppler / `DOPPLER_TOKEN` / `ZOT_REGISTRY_URL` is absent: the fleet emits
      nothing at all. Caught ONLY by the soak's insufficient-sample arm, which is why that arm must
      keep `exit 1`.
    - **The dedicated inngest host** (#6500, surfaced by #6462) — a **live** host
      (`hcloud_server.inngest` is unconditional, `inngest-host.tf:181`) whose
      `cloud-init-inngest.yml:337` hard-pins a `ghcr.io` ref with no zot path, no `/v2/` probe and
      no fallback, and whose pull is **fail-closed** (`:349`). It reports via
      `inngest-boot-phone-home.sh` to Better Stack, not the Sentry `stage:` schema, so every query
      in the soak is structurally blind to it. **Task 5.3 revokes the PAT ⇒ its next fresh boot
      401s ⇒ the host never comes up.** Unlike #6437 this residual is **machine-enforced, not
      merely disclosed**: the soak's blocker arm reads #6500's state via `gh` and refuses `exit 0`
      while it is OPEN. Closing #6500 is therefore an **authorization act** — see the pinned note
      on that issue.

    The soak remains **necessary but not sufficient** to authorize 5.3–5.5, and this ADR stays
    **Adopting**.

    *Debt recorded and TRACKED (#6510):* the **Sentry plane is unmodelled in C4**
    (`hetzner -> sentry`, `webapp -> sentry`). The edge is already true on `main` — `_emit` has
    POSTed from the boot path for the `on_err` fatals (`stage:"pull"`, `stage:"ghcr_login"`), and
    #6462 adds a 5th call site on that same emitter rather than a new edge — so this is
    pre-existing debt, not #6462's. It should be modelled **whole** in a docs-only PR; shipping
    `sentry` with a single inbound edge would assert a falsehood (that the webapp does not report
    to Sentry) where silence asserts nothing.

    *Expected pages between merge and cutover:* a web-host recreate that misses the `/v2/` probe
    now fires `zot_mirror_fallback_rate` via `app_ghcr_served`. That is **expected** and shares a
    root cause with #6416 / #6288 — do not investigate it separately. ⚠ But do **not** mute the
    `app_ghcr_served` issue to quiet it: unlike `ghcr-fallback` (which regroups per deploy, so a
    mute self-expires) it is stable-grouped on a static message, so a mute is permanent and would
    blind the dominant GHCR-served path — the exact hole #6462 closes. See the mute-safety
    carve-out in `issue-alerts.tf`.
    ⚠ **The soak is also not yet ENROLLED, and #6435 did not enroll it.** `sweep-followthroughs.sh`
    enumerates `--label follow-through --state open` and reads a `soleur:followthrough` directive from
    the issue body; #6122 carries neither, and no issue references `zot-soak-6122.sh`, so the sweeper
    never invokes it. (It was additionally committed mode 100644 — a latent second defect, fixed in
    #6435 and now class-guarded by `scripts/followthrough-exec-bit.test.sh`.) This is deliberate: the
    cutover has not happened (`registry:"zot"` = 0 events/30d) and the soak's `START` is an unpinned
    placeholder, so enrolling early would emit a daily TRANSIENT that never converges. **Enrolling the
    soak — label + directive + a pinned `START` — is a precondition of Phase 5 that 5.3 must not
    proceed without.** Until then the gate's verdict is not merely insufficient; it is absent. **Window — opens at task 1.8, for 3 of the 4 signals:**
    `zot-gate-degraded` fires precisely where `ZOT_ACTIVE` stays 0 (probe_unreachable /
    creds_absent / login_failed, `ci-deploy.sh:790/799/807`), and the two cloud-init fresh-boot
    signals gate on `ZURL` + a `/v2/` probe with **no** `ZOT_ACTIVE` at all (`ZOT_ACTIVE` does not
    occur in `cloud-init.yml`) — so all three go live as soon as `ZOT_REGISTRY_URL` is set in
    Doppler `prd`, *before* the flip. Only `registry:ghcr-fallback` (`ci-deploy.sh:857`) requires
    `ZOT_ACTIVE=1`. Note the 1.8→1.9 window (URL set, creds not yet backfilled) therefore pages on
    `app_ghcr_fallback` as well as `zot-gate-degraded`. Each signal is additionally gated on the
    emitting host having Doppler + `DOPPLER_TOKEN` + a resolved `SENTRY_*` prefetch
    (`ci-deploy.sh:707,776-777`); a host missing either is Sentry-dark and reports only via
    `logger -t ci-deploy` → Better Stack (#6437).
    > **Amendment reference (#6512, 2026-07-17):** `ci-deploy.sh`'s `pull_image_with_fallback` grew a
    > THIRD, last-resort tier below the zot→GHCR chain: on both-registries-fail for a same-version
    > `web` reload it reuses the RUNNING container's local image (emitting `registry:"local-cache"`,
    > watched by a DEDICATED `local_cache_reload_rate` alert — NOT folded into
    > `zot_mirror_fallback_rate`, so the §5.3 retirement gate below is unaffected). A future §5.3
    > editor should note the third tier exists but touches only the local-store rescue, not the GHCR
    > push/pull path this task retires. See ADR-079 `(#6512)` amendment.
    **Closes:** task 5.3 deletes the pull-site
    fallback **branches** — three of them across two files, not one: the `ZOT_ACTIVE` branch in
    `ci-deploy.sh` (emits `registry:"ghcr-fallback"`), plus the two fresh-boot branches in
    `cloud-init.yml` (emitting `app_ghcr_fallback` and `inngest_ghcr_fallback`) — darkening those
    three signals. Anchored on emit names, not line numbers: this enumeration is the claim 5.3
    acts on, and a line-number citation into `cloud-init.yml` rots on the next insertion above it
    (#6447 is that failure in the wild). `zot-gate-degraded`
    survives 5.3 (gate-emitted). **Do NOT retire the alarm at 5.3 — narrow its `filters_v2` to the
    surviving signal(s);** retiring it blinds `zot-gate-degraded`. Two post-cutover boot-gating
    shapes the degraded signal must remain loud for: a **missing** copy (crane-copy failure) AND a
    **present-but-unsigned** copy (cosign-sign succeeded-copy-then-failed-sign) — the latter is NOT a
    clean miss, since the pull side would pull the present zot copy and *bypass* the atomic GHCR
    fallback, then hard-fail signature verify. During soak `ZOT_ACTIVE=0`, so both are latent and the
    pre-flip zot-entry-gate/soak-gate catch them; the mirror step's cosign-failure path emits a
    re-sign-specific remediation (a bare `crane copy` backfill does not re-sign).
- **Instant revert:** unset `ZOT_REGISTRY_URL` in Doppler `prd` → all sites revert to GHCR-primary
  with no deploy, no SSH (`zot-registry-revert.md`).
- **Durability = reproducibility:** zot's content is 100% rebuildable (CI re-pushes) + re-backfillable
  (`crane copy` GHCR→zot); a lost volume is a re-run, not data loss — which is why a host-side
  snapshot cron (1.5) was deferred rather than expanding the host's blast radius with an hcloud token.

<!-- lint-infra-ignore start -->
### Apply path (binding — see `apply-path-cto-ruling.md`)

The registry host follows the **ADR-068 git-data model**: all 24 new resources (18 host-stack + 6
CF-Tunnel ingress) are **operator-applied** via `OPERATOR_APPLIED_EXCLUSIONS` + the 12h drift
detector — **zero** added to the per-PR CI `-target=` list. An unattended per-PR apply must not
provision a production host / mint a push credential for a host that does not yet exist
(`hr-fresh-host-provisioning-reachable-from-terraform-apply`). Two load-bearing conditions: (1) the
registry host is **cloud-init-only** (an SSH-provisioned `terraform_data` would hit the first
parity guard); (2) no zot cred is a `github_actions_secret` (CI reads `ZOT_PUSH_*` from Doppler at
runtime). The **one** exception is `terraform_data.registry_insecure_config` — the running-host
`insecure-registries` SSH delivery — which, being SSH-provisioned, **must** be in the CI `-target`
list + the terraform-target-parity SSH set (condition #1 the other way).

<!-- lint-infra-ignore end -->

## Consequences

- **Positive:** a genuine zero-touch machine identity on the pull path (G1); the interim exposed
  PAT is retired (TR5, after soak); GHCR removed from the boot critical path once soak completes;
  cosign chain preserved end-to-end (G3); registry lives inside the restricted-egress net (G4);
  zero-downtime dark-launch cutover with no credential gap (G5).
- **Negative / residual:** a new dedicated host to run + patch (~€4/mo); a boot-path dependency
  (mitigated above); a plain-HTTP-on-private-net registry (integrity via cosign digest-pinning,
  not TLS); local-fs (single-datacenter) durability until an R2/snapshot revisit (NG3).
- **Retirement (post-soak):** remove the pull-site GHCR fallback branch (5.3), stop GHCR push +
  egress allow (5.3), retire `cron-ghcr-token-minter.ts` + `ghcr-*-credential.tf` + the
  `GHCR_MINTER_DISABLED` gate (5.4), then rotate + revoke the exposed classic PAT (5.5).
- **Host sizing + region (factual, #6288):** `cax11`(planned, arm64)→`cx23`(live nbg1, provisioned
  during an Ampere+cx stock outage, #6122)→**`cx33`(4 vCPU / 8 GB, `hel1`, #6288)**. The 4 GB cx23
  restart-looped zot ~4/min OOM-ing during the boot scan of the ~35 GB store (disk-independent —
  disk sat at 58–63%, not ENOSPC). #6288 first targeted **`cx32`, which is not a real Hetzner
  type** — that phantom `registry-host-replace` destroyed the nbg1 host then failed `server type
  cx32 not found` (GHCR-masked). Resolution: **migrate nbg1→hel1** (the store volume is ForceNew on
  location → destroyed + recreated fresh; the 35 GB store is a disposable GHCR mirror that re-fills
  from GHCR) and use **`cx33`** — the real 8 GB CX-Intel type, offered in hel1 (€8.49/mo) but NOT
  nbg1, where the cheapest 8 GB is cpx32 ~€35/mo (~6×). Applied via the guarded
  `registry-region-migrate` dispatch (its `registry_region_migrate_gate` permits the registry's OWN
  store-volume replace but forbids any out-of-scope destroy + preserves the logs-token secret). cx33
  adopts the **ADR-062** container `--memory`/`--memory-swap` cap (7168m), now enforceable on 8 GB.
  NOTE the cap already equals host RAM minus the ~1 GB OS reserve, so — unlike ADR-062's web host
  where `PROD_MEMORY_CAP` is a *tunable* with headroom to raise on OOM — here the cap is a *ceiling*:
  a working-set overrun's only remediation is a bigger host (cx43/16 GB), not a higher cap. OOM
  confirmation keys on the MONOTONIC `memory.events oom_kill` container-cgroup counter
  (`zot_oom_kills`, survives the 4/min point-sampling race) + `exit_code=137` + the journald
  `oom_kills_5m` backstop — not the page-cache-confounded host `mem_used` nor a point-sampled anon
  gauge. Applied via the guarded `registry-host-replace` dispatch (server_type is `ForceNew`; the
  60 GB store volume is preserved + re-attached). The GHCR atomic fallback masks the brief replace outage.

### Credential isolation (amendment 2026-07-07, #6122)

The registry host's boot credential is scoped to a **dedicated Doppler project `soleur-registry`**
whose own `prd` root config holds ONLY `ZOT_PULL_TOKEN` + `ZOT_PUSH_TOKEN` — **not** a `prd` branch
config. The original design placed the host token in a `prd_registry` **branch config under the
`prd` environment** and claimed it isolated the host. That claim was **structurally impossible**:
in Doppler, every config within an environment resolves that environment's ROOT config as its base,
so a token scoped to a `prd` branch config reads the full `prd` secret set — empirically verified to
return all 116 secrets including `SUPABASE_SERVICE_ROLE_KEY`. Provisioning as-designed would have
handed a new CF-tunnel-reachable private-net host read access to every production secret.

True isolation requires a boundary that does not share the `prd` root. A **separate project** was
chosen over a standalone `registry` **environment** because the `soleur` project is at the
4-environment tier cap (dev/prd/ci/cli) — a 5th environment needs a Doppler Team-plan upgrade,
whereas project creation is unrestricted at the current tier. `doppler_project.registry` is
TF-created in the operator's full apply (`var.doppler_token_tf` is workplace-scoped); fallback is a
one-time operator-created project. Verified by a boot-time self-assertion (cloud-init refuses to
launch unless its own shipped token resolves exactly 2 non-`DOPPLER_*` secrets, both `ZOT_*`) plus a
provisioning-gate scoped-token count/identity assert. The identical branch-config non-isolation
affects `prd_git_data`, `prd_kb_drift_walker`, and `prd_cla` (a **live** over-read) — audited
separately in **#6167**; status stays **Adopting**.

### Reprovisioning path + alert recipient (amendment 2026-07-08)

Two gaps surfaced when the 2026-07-08 zot capacity-management merge (`storage.retention` pruning +
10→30 GB volume grow + `betteruptime_heartbeat.registry_disk_prd`) created a disk-full heartbeat in
Better Stack but the registry **host was never redeployed** with the cloud-init that installs the
`zot-disk-heartbeat.sh` self-ping cron — so the heartbeat never pinged, Better Stack alerted on the
absence (`soleur-registry-disk-prd | Missed heartbeat`), and the same missing redeploy left the disk
mitigations un-live. Both are structural, not one-off:

- **Reprovisioning / apply-path.** The per-PR CI path bridges over SSH to the *existing* web host and
  cannot provision a fresh host; the registry resources stay `OPERATOR_APPLIED_EXCLUSIONS` (the
  binding apply-path ruling above is **unchanged**). The registry host now has a sanctioned
  **dispatch-only `registry-host-replace`** path (`apply_target=registry-host-replace` in
  `apply-web-platform-infra.yml`), mirroring ADR-100's `inngest-host-replace`: a scoped
  `terraform apply -replace='hcloud_server.registry'` over a **5-target** set (server +
  `hcloud_server_network.registry` + `hcloud_volume_attachment.registry` +
  `hcloud_firewall_attachment.registry` + `hcloud_volume.registry`) to re-run cloud-init + apply any
  pending storage-volume resize **without SSH**. *(Grew to a **6-target** set — the isolated
  `doppler_secret.registry_betterstack_logs_token` — under the #6240/#6244 amendment below.)* *(Grew to a **6-target** set — + `doppler_secret.registry_betterstack_logs_token` —
  in the #6240/#6244 amendment below.)* A sourced destroy-guard
  (`tests/scripts/lib/registry-host-replace-gate.sh`, no `[ack-destroy]` bypass —
  `hr-menu-option-ack-not-prod-write-auth`) PRESERVES the zot OCI store volume (size-update-only,
  never delete/forget/replace) and positively asserts the new host re-attaches to its private NIC +
  deny-all firewall. It is a **larger, stricter** gate than inngest's (5-member allow-set vs 3;
  positive NIC/firewall assertions; the storage volume in-scope so its size update rides in — the
  4-target scope would have aborted the very fix). The dispatch job is stripped from the per-merge
  parity coverage anchor (`stripDispatchJobs`).
- **Alert recipient (free-tier IaC path).** Recipients were not managed in Terraform at all, so only
  the account owner was emailed and the incident stayed unacknowledged.
  `betteruptime_team_member.ops` (email `ops@jikigai.com`, `role = "responder"`,
  `team_name = "Your team"`) is now the IaC-managed recipient in `uptime-alerts.tf`, auto-applied
  per-merge via `-target=betteruptime_team_member.ops`. It authenticates via the existing global
  `var.betterstack_api_token` (no new variable). Escalation `betteruptime_policy` stays paid-gated
  (`var.betterstack_paid_tier`, unchanged). The member is **inert until ops@ accepts the one-time
  invite** (its own inbox); if free-tier non-owner routing proves owner-only the documented fallback
  is a `betteruptime_outgoing_webhook` forward or a Responder-tier upgrade (expense-gated, out of
  scope). Status stays **Adopting**.

### Disk-full root cause + blind-host observability (amendment 2026-07-08, #6240/#6244)

The 2026-07-08 17:20 UTC `registry-host-replace` (fresh host, PRESERVED 30 GB volume) did **not**
fix the crane 500-on-blob-upload; the disk heartbeat still never pinged. A disk-full condition that
survives a fresh host on a preserved volume is a **filesystem**, not a host, fault: the on-boot
`resize2fs` was wrapped in `|| true`, so it **silently failed** and the ext4 fs on `/var/lib/zot`
never grew to fill the 30 GB block device — it filled, zot 500'd every push with `ENOSPC`, and the
absence-based heartbeat (pings only while `<85%`) never fired. The prior post-mortem read the Hetzner
volume API ("~30 GB") as "not full", but that API reports the **block-device** size, never the
**filesystem** size, and there was no `df` observability to tell them apart. Three coupled remedies:

- **Boot isolation-guard cardinality 2 → 3.** The `cloud-init-registry.yml` self-check now admits a
  third secret **`BETTERSTACK_LOGS_TOKEN`** by name (asserting `n_total == 3 && n_admitted == 3` over
  the exact set `{ZOT_PULL_TOKEN, ZOT_PUSH_TOKEN, BETTERSTACK_LOGS_TOKEN}`), mirroring the ADR-100
  `cloud-init-inngest.yml` precedent. Deleting the logs token post-cutover FATALs the bootstrap (loud
  fail > silent observability blind spot); the check keys on the NAME, so value rotation is safe. The
  token is provisioned by `doppler_secret.registry_betterstack_logs_token` (isolated `soleur-registry/prd`,
  exact mirror of `inngest-betterstack-token.tf`, value from the no-default `var.betterstack_logs_token`)
  and **MUST ride the SAME `registry-host-replace` dispatch** as the host replace — so the dispatch
  `-target` set + the destroy-guard allow-set both grew 5 → 6 to include it (a 2-secret config now
  FATALs the boot, a worse outage — the ordering is load-bearing).

- **Blind-host disk observability (#6244).** The deny-all-ingress, no-SSH registry host now
  self-reports its disk state as ONE structured **`SOLEUR_ZOT_DISK`** event
  (`pcent`, `fs_size_gb`, `block_size_gb`, `resize_ok`, `zot_restarts`, `ping_rc`) to the **existing**
  isolated Better Stack Logs source **2457081** (reused via the same token + region-bound ingest URL
  `s2457081.eu-fsn-3` that `vector.toml` ships to — no new source), queryable via
  `scripts/betterstack-query.sh --grep SOLEUR_ZOT_DISK` with NO SSH. The `#6244`-suggested
  journald-`logger` interim was rejected (journald needs SSH to read — `hr-no-ssh-fallback-in-runbooks`).
  The event's fields discriminate all three competing root causes in one line: fs-not-grown
  (`resize_ok=false` OR `fs_size_gb ≪ block_size_gb`), gc-too-slow (`resize_ok=true`, `fs≈28 GiB`,
  `pcent≥85`), and zot-mid-write-crash (`pcent<85`, `fs≈28 GiB`, `zot_restarts>0`). Delivered by folding
  the report into `zot-disk-heartbeat.sh` under a `doppler run --project soleur-registry --config prd`
  cron wrapper (token injected at run time, never baked into user_data). This adds the
  `zotRegistry → betterstack` edge in `model.c4`.

- **resize2fs fail-loud + gc/retention remediation (#6240).** The resize path drops `|| true`
  (silent-swallow), waits for the volume device node (attach race), re-ensures `e2fsprogs` (the
  cloud-init `packages:` stage is non-fatal), asserts the ext4-on-raw-device (no-partition) invariant,
  and captures `df` before/after + the resize2fs exit code into `/var/lib/zot/.resize-result` for the
  reporter to ship. A genuine resize failure is LOUD in telemetry (`resize_ok=false`) but does NOT
  wedge the boot — zot still launches on the existing fs so the host stays reachable to self-report
  (fail-loud, not fail-dark). `config.json` gc/retention tightened `gcInterval` 24h → 1h and
  `retention.delay` 24h → 2h (keep-set + `gcDelay` unchanged) so a filling store reclaims within ~1h;
  no on-boot gc trigger is issued (zot v2.1.2 exposes no sanctioned on-demand gc endpoint —
  `hr-verify-repo-capability-claim`). Status stays **Adopting**.

- **Capacity-vs-retention recurrence (2026-07-09, #6247).** The #6240 fix tightened gc/retention
  **timing** but deliberately left the keep-**set** unchanged. A recurrence followed: `SOLEUR_ZOT_DISK`
  showed the 30 GB ext4 fs **genuinely full** (`pcent=100`, `resize_ok=true`,
  `fs_size_gb=30=block_size_gb`, `zot_restarts` climbing) — NOT a resize regression, but the exact
  telemetry-gated *grow-the-volume* contingency #6244 pre-registered as #6247. Root cause: the
  `storage.retention` keep-set (`latest` + **unbounded** `sha256-.*` sig referrers + **10** `v*` + **10**
  commit-sha, **per repo across 2 platform-image repos**, each image ~1.5–2 GB) legitimately **exceeded
  30 GB**, and gc cannot reclaim a blob the policy says to KEEP. Resolution — **both levers, one PR, one
  `registry-host-replace` dispatch**: (1) grow `var.registry_volume_size` **30 → 60 GB** (Hetzner
  in-place volume resize preserving data; the fail-loud `resize2fs` grows the ext4 on the next boot);
  (2) tighten the keep-set — `mostRecentlyPushedCount` **10 → 5** for `v*` and commit-sha, and **bound
  the previously-absolute "ALWAYS keep every `sha256-*`" rule** at `mostRecentlyPushedCount` **50**.
  The `sha256-.*` bound revises the prior invariant and is coupled to deploy-time `cosign verify`
  (ADR-087): `mostRecentlyPushedCount` is push-ORDER heuristic and can evict out of order under the
  backfill/re-sign path above, and GHCR does NOT rescue a zot-pruned sig on a **kept** image (atomic-move
  fetches the `.sig` from whichever registry serves the pull). 50 sits far above the true keep
  requirement (~12–18 sig-tags/repo) so it never prunes a kept image's sig at current scale; blast
  radius today is WARN-mode (`ci-deploy.sh`), becoming blocking at the WARN→ENFORCE flip (#6129). No
  gate/workflow change: the `registry-host-replace` destroy-guard already permits a volume `["update"]`.
  Status stays **Adopting**.

### Durable restart-loop recurrence alarm (amendment 2026-07-10, #6291)

The #6244 `SOLEUR_ZOT_DISK` self-report closed the *disk*-observability gap, but nothing stood
watch on it continuously once #6288's one-shot soak follow-through
(`zot-restart-plateau-6288.sh`) auto-closes. The disk-absence heartbeat `soleur-registry-disk-prd`
pings **only while `/var/lib/zot < 85%`**, so a **disk-independent** OOM restart-loop (the #6288
failure mode — zot OOM-restart-looping ~4/min during the boot scan of the ~35 GB store) leaves the
heartbeat **GREEN** throughout. A durable, continuous recurrence alarm now closes that liveness gap:

- **Mechanism = an in-repo GitHub-Actions scheduled-cron poller**
  (`.github/workflows/scheduled-zot-restart-loop.yml`, `*/30 * * * *`) that reads the
  `SOLEUR_ZOT_DISK` stream from Better Stack Logs source 2457081 via `betterstack-query.sh`
  (ClickHouse SQL), evaluates three firing conditions in `scripts/zot-restart-loop-alarm.sh`
  (scoped to the newest `boot_id`: `exit_code=137` seen, OR `zot_restarts` climbs across ≥3
  consecutive events, OR `oom_kills_5m > 0`), and routes a fire to a deduped **`action-required`**
  `[ci/zot-restart-loop]` GitHub issue carrying the decoded cause (host/kernel OOM vs cgroup-cap
  contained vs non-OOM `zot_last_err`). On recovery it auto-closes. A distinct
  `[ci/zot-telemetry-silent]` issue fires if the token-gated reporter goes dark while the
  token-free disk heartbeat + Sentry monitor stay GREEN (the GREEN-while-broken blind spot, one
  layer up). Its own liveness is a Sentry cron monitor (`sentry_cron_monitor.zot_restart_loop_alarm`,
  slug `scheduled-zot-restart-loop`) so a *dark* alarm also alerts. The trusted-region parse
  (strip the free-text `zot_last_err` tail before any key=value parse; scope to the newest
  `boot_id`; filter `-1` inspect-miss sentinels) is extracted into one sourced helper
  (`scripts/lib/zot-telemetry-parse.sh`) that BOTH the alarm and the #6288 soak probe consume — one
  home for the spoof-resistance invariant.

#### Pattern: Better Stack log-content alarms

**A recurring, reusable precedent** (grep-findable here + cross-linked from
`knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`): a **log-*content*
recurrence alarm over a Better Stack Logs source is an in-repo GH-Actions cron poller** (query via
`betterstack-query.sh` → decode/threshold in a `scripts/` checker → deduped `action-required`
GitHub issue → Sentry self-liveness heartbeat), **NOT** a native Better Stack alert. This alarm
(#6291) and the `scheduled-followthrough-sweeper.yml` soak probes both recur this shape. The
`BetterStackHQ/better-uptime` Terraform provider has **no** log-alert resource (only
`betteruptime_monitor`/`_heartbeat`/`_policy`), and even the programmatic **Telemetry v2 SQL-alert
API** (which *does* exist — see §Alternatives) is rejected for this signal class because: (1) the
stateful consecutive-climb condition + newest-`boot_id` scoping are not faithfully expressible as a
single `{{time}}`-bucketed threshold; (2) the operator surface must be a digest-visible GitHub
`action-required` issue, not an ops@ email; (3) it is not a first-class TF resource, so it would
split the decode source-of-truth off from the reporter's decode semantics. Choose the GH-cron poller
for future log-content alarms unless a signal is a pure stateless per-bucket count with an
email-acceptable surface.

### Reprovisioning path + alert recipient — restart-loop alarm cross-ref (amendment 2026-07-10, #6291)

The restart-loop alarm is fully automated post-merge: `apply-sentry-infra.yml` auto-applies the new
`sentry_cron_monitor` on merge, and the workflow schedule fires the first run — no operator step.

### Guest-side LUKS at-rest for the store volume (amendment 2026-07-24, #6895)

`hcloud_volume.registry` was a **plaintext ext4** block volume (ADR-140 recorded it as a
`plaintext-exception` row in the encryption-posture ledger). It now carries **guest-side LUKS**,
mirroring the `git_data_luks` apparatus (there is no hcloud `encrypted` volume attribute — ADR-140):
the volume is a **raw** device (no `format`), cryptsetup luksFormats/luksOpens it in the guest at
cloud-init (`cloud-init-registry.yml`) unlocked by `REGISTRY_LUKS_KEY`, a `random_password` published
to the isolated `soleur-registry/prd` Doppler config and read at boot via the existing scoped service
token (no new token). The store mounts from `/dev/mapper/registry` at `/var/lib/zot`; a boot-time
oneshot (`registry-luks-open.service`) reopens the mapper after a reboot (the host self-`reboot`s via
the private-NIC guard). The ledger row flips `plaintext-exception → luks`. This is **defense-in-depth
on a disposable mirror** — the store holds only OCI blobs + cosign signatures (our own images),
re-fills from GHCR, and carries no user/repo data.

<!-- lint-infra-ignore start -->
<!-- Deferred-orchestrator prose: this describes a SANCTIONED, gated operator recut that runs OUTSIDE
     any per-PR apply (an OPERATOR_APPLIED_EXCLUSION `-replace` / the deferred guarded dispatch #6929),
     not a human-run step prescribed inside a runbook this PR executes. Grandfathered per the lint's
     own escape hatch; the recommended fully-automated vehicle is the guarded dispatch (#6929). -->

**Recut vehicle (the operator step, OUTSIDE the landing PR).** Encrypting the *live* volume is a
destroy+recreate: a scoped **`terraform apply -replace` of the volume + its attachment + the host,
all three together** (a fresh raw volume ⇒ cloud-init luksFormats it ⇒ zot re-fills from GHCR). The
recommended vehicle is a guarded, typed-confirm `registry-luks-recut` `workflow_dispatch` mirroring
`workspaces-luks-recut`/`registry-region-migrate`; that guarded dispatch is **deferred to a follow-up**
(#6929; the landing PR is cloud-init + Terraform + ledger only) — until it ships, the sanctioned
`OPERATOR_APPLIED_EXCLUSION` `-replace` path is the vehicle, with all three resources targeted together.

**FOOTGUN — do NOT use `registry-host-replace` for the recut.** That existing dispatch **preserves**
the volume, so it boots cloud-init against the still-**plaintext** ext4 volume, which hits the D1/B
`blkid TYPE` discriminator's **else → FATAL refuse** arm (a plaintext volume must be recut, never
silently wiped) and **darks the registry**. Forgetting the `-replace` on the volume has the same
effect. The refuse is the *safe* failure (it never mounts plaintext / never certifies a false-green
posture), but it takes zot down — the only correct first apply is the three-way recut on a fresh volume.

**Escrow deliberately omitted.** Unlike `workspaces_luks` (#6649 R2 LUKS-header escrow), there is **no**
header escrow and **no** dedicated at-rest monitor here: passphrase loss ⇒ recreate + re-fill from
GHCR, so escrow buys nothing for a disposable, born-fresh store (matches `git_data_luks`). Rotation is
therefore a volume **recut**, not a bare host replace (`random_password.registry_luks` is deliberately
absent from the host's `replace_triggered_by`, or cloud-init would luksOpen the old-key volume with the
new key and FATAL).
<!-- lint-infra-ignore end -->

## Alternatives Considered

The 7 registry-choice options are tabled above. The **apply-path** alternatives (per-PR `-target`
the whole stack; a `workflow_dispatch` warm-standby job; split-cred two-writer choreography) were
routed to the CTO agent and rejected in `apply-path-cto-ruling.md` §"Rejected alternatives"; the
**push-ingress** alternatives (public `/v2/` endpoint; cloudflared on the registry host) were
rejected in the CTO's second ruling in favour of the CF-Tunnel-on-the-web-tunnel bridge.

For the **restart-loop recurrence alarm (#6291)**, the **Better Stack Telemetry v2 SQL-alert API**
was evaluated and rejected *on merits* (not on absence — the endpoints exist):
`POST /api/v2/dashboards/{id}/charts/{cid}/alerts` and `.../explorations/{id}/alerts`, with
`check_period` as the recurring schedule (docs `betterstack.com/docs/logs/api/…`). It can faithfully
express the stateless conditions (`countIf(exit_code=137) > 0`, `oom_kills_5m > 0`) as
`{{time}}`-bucketed thresholds, but it **cannot** faithfully express the stateful `zot_restarts`
consecutive-climb scoped to the *newest* `boot_id` (a `max-min>tol` approximation false-fires on a
single legitimate restart, and `{{time}}`-bucketing loses the newest-`boot_id` discriminator the
hostname-reusing immutable replace requires). It is also **not** a first-class TF resource (provider
gap confirmed) — it would be a REST-provisioned resource whose state lives in Better Stack, needing
a bootstrap + drift handling, with its decode SQL divorced from the reporter's decode semantics; and
its notify surface (ops@ email on the free tier) is weaker than a deduped, digest-visible
`action-required` GitHub issue for a non-technical operator. The **dashboard** manual-config path was
rejected outright (not version-controlled/testable; `hr-exhaust-all-automated-options-before`). See
the `scheduled-zot-restart-loop.yml` gate-override header for the ADR-033-anchored GH-cron-vs-Inngest
substrate rationale.
