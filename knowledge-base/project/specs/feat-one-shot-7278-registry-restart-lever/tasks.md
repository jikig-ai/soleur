---
feature: feat-one-shot-7278-registry-restart-lever
issue: 7278
lane: cross-domain
plan: knowledge-base/project/plans/2026-08-04-feat-registry-zot-restart-lever-plan.md
created: 2026-08-04
---

# Tasks — registry zot restart lever (#7278)

Derived from the plan. Ordering is dependency-directed: contract-defining changes precede
their consumers. Do not reorder phases 1→3 — the hook contract defines what the workflow
polls, and the `-target=` allowlist must land with the resources it admits.

## Phase 0 — Preconditions (verify, never assume)

- [ ] 0.1 Re-derive the next-free ADR ordinal against freshly-fetched `origin/main`
      (`git fetch origin main && git ls-tree -r --name-only origin/main -- knowledge-base/engineering/architecture/decisions/ | grep -oE 'ADR-[0-9]+' | sort -u | tail -3`).
      Plan assumes **169** (168 is the max, 167 absent) — PROVISIONAL.
- [ ] 0.2 Confirm PR #7279 status. If merged, rebase; either way **do not edit the recut
      runbook's blocked-state banner**.
- [ ] 0.3 Read the admitted-secret self-check cardinality in `cloud-init-registry.yml`
      (`n_admitted=…`, currently 4) and record it — the new HMAC secret changes it.
- [ ] 0.4 Determine the exact `webhook` binary acquisition method used for web-1 and reuse
      it verbatim; do not invent a new install path.
- [ ] 0.5 Re-pull `SOLEUR_ZOT_DISK` (`doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 2h --grep SOLEUR_ZOT_DISK`).
      Record `pcent` and `zot_restarts`. **If the store has filled and the registry is hard
      down, STOP and re-scope** — the activation story changes materially.
- [ ] 0.6 Re-run the allowlist artifact sweep: `git grep -ln -- '-target=' tests/ scripts/ .github/`.
      The plan found 3 relevant artifacts; confirm the set has not grown.

## Phase 0.5 — BLOCKING PREREQUISITE: user_data under the cap (deepen R1)

**Nothing below can be provisioned until this lands.** Measured 2026-08-04:
`gzip -9 -c apps/web-platform/infra/cloud-init-registry.yml | base64 -w0 | wc -c` = **34320**
against Hetzner's **32768** cap — already over, before this plan adds anything. This also
blocks #7277; surface it to the operator independently of this PR.

- [ ] 0.5a Measure the baseline on the **substituted** render, not the raw file.
- [ ] 0.5b Adopt/generalise `apps/web-platform/infra/modules/git-data-userdata/`
      (rationale-strip). Do NOT hand-roll a second stripper.
- [ ] 0.5c Port the parity test (`git-data-render-strip-parity.test.sh`).
- [ ] 0.5d Assert `base64gzip` length `< 32768` **with margin** for what this plan adds.
- [ ] 0.5e If it cannot be made to fit → STOP and re-scope; the lever is undeliverable.

## Phase 1 — Hook contract + scripts (RED first)

- [ ] 1.1 Write failing tests before implementation (`cq-write-failing-tests-before`):
  - [ ] 1.1.1 **(deepen R13/R14 — HARDENED)** `tests/scripts/test-registry-control-hooks-shape.sh`:
        exactly 3 hooks; every hook object's key set is a **subset of a permitted-key allowlist**
        excluding **all three** forwarding keys (`pass-environment-to-command`,
        `pass-arguments-to-command`, `pass-file-to-command` — v1 pinned only the first, and the
        precedent `infra-config` hook uses `pass-file-to-command` 20×); `trigger-rule`
        **PRESENT** on every hook (a hook without one fires unconditionally, and the 403
        mismatch code is inert without it); the 3 hooks reference **3 DISTINCT secrets**;
        `http-methods` pinned (mutating hooks POST-only); the 2 mutating hooks are async
        (`include-command-output-in-response: false`, `success-http-response-code: 202`) and set
        `include-command-output-in-response-on-error: false`.
  - [ ] 1.1.2 `recreate-zot.sh` refuses when `/var/lib/zot` is not backed by
        `/dev/mapper/registry` (feed it a non-mapper mount source).
  - [ ] 1.1.3 `hcloud_firewall.registry` still declares zero inbound rules.
- [ ] 1.2 Implement `restart-zot.sh` (`docker restart zot`).
- [ ] 1.3 Implement `recreate-zot.sh`: re-assert the `findmnt` gate → pull pinned digest →
      **(deepen R16) `docker image inspect <digest>` as a HARD precondition** with a named
      `reason=image_unavailable` verdict → **only then** `docker rm -f zot` → re-run the
      **exact** baked run-line (memory cap, journald log driver, volume mounts,
      `-p 0.0.0.0:5000:5000`). Never a retyped variant. Without the image gate, a failed pull
      (GHCR is dead as a fallback) followed by `rm -f` destroys the registry with its own
      repair lever, mid-outage. Take a `flock` (workflow `concurrency` does not bind a direct
      hook caller). `docker restart` does NOT apply a new image — that is why this action exists.
- [ ] 1.4 Implement `zot-status.sh` — read-only; returns `container_id`, `started_at`,
      `restart_count`, `image_digest`, `mount_source`.
- [ ] 1.5 Implement the `SOLEUR_ZOT_RESTART` emitter (same `doppler run` + `curl` idiom as
      `zot-disk-heartbeat.sh`), emitted on both success and failure.
- [ ] 1.6 Comment the async-hook rationale (sync execution would exceed Cloudflare's ~120 s
      edge timeout → 524 on a successful restart).

## Phase 2 — Host half (cloud-init)

- [ ] 2.1 Add `webhook` install + `/etc/webhook/registry-hooks.json` render +
      `zot-control.service` (hardened: `ProtectSystem=strict`, minimal `ReadWritePaths`,
      `Restart=on-failure`) to `cloud-init-registry.yml`.
- [ ] 2.1a **(deepen R15 — the service must not run as root)** systemd defaults to root and v1
      never named a `User=`. `cloud-init-registry.yml` has **no `users:` block at all**, so the
      user must be CREATED. Add a `zotctl` user **not** in the `docker` group (web-1's `deploy`
      IS in `docker`, which is itself root-equivalent — "mirror web-1" buys nothing), plus
      `User=`/`Group=` on the unit and a wildcard-free `/etc/sudoers.d/zotctl` pinning the fixed
      helper-script paths, following the `Cmnd_Alias INFRA_CONFIG_INSTALL` precedent. A
      `docker run *` wildcard would equal full docker access — pin scripts, not docker commands.
- [ ] 2.1b **(deepen R13)** Render THREE distinct HMAC secrets into the hooks file, one per hook.
- [ ] 2.1c **(deepen)** `/etc/webhook/registry-hooks.json` mode `0640`, owned by the control user
      (it holds HMAC secrets in plaintext; precedent `chmod 600 /etc/default/webhook-deploy`).
- [ ] 2.1d **(deepen)** Bind the listener to the registry's **private IP**, not `0.0.0.0`, and
      add a host-local nftables rule restricting `tcp/9000` to the web-host private IPs — only
      web hosts run cloudflared connectors, and git-data/inngest have no reason to reach it.
      Confirm `-verbose` does not log the `X-Signature-256` header before keeping it (this host
      has no journald reader).
- [ ] 2.2 Update the admitted-secret cardinality self-check (from 0.3).
- [ ] 2.3 Guarantee the install is **non-fatal to boot** — it must never `exit 1` in
      `runcmd`. A failed control plane must never be a new reason the data plane stays dark.
- [ ] 2.4 Add the `SOLEUR_ZOT_CONTROL` activation heartbeat to the existing 5-min cron.
- [ ] 2.5 Cloud-init render test.

## Phase 3 — Edge half (Terraform) + the ordering invariant

- [ ] 3.1 `tunnel.tf`: fourth `ingress_rule` for `registry-ctl.${var.app_domain_base}` →
      `http://${local.registry_private_ip}:9000`, **above** the `http_status:404` catch-all.
- [ ] 3.2 `tunnel.tf`: `cloudflare_zero_trust_access_application.registry_ctl`
      (`session_duration = "15m"`), `..._service_token.registry_ctl` with
      `lifecycle { create_before_destroy = true }` (the 12139 trap),
      `..._policy.registry_ctl_service_token`.
- [ ] 3.3 `dns.tf`: `cloudflare_record.registry_ctl` CNAME → `<tunnel-id>.cfargotunnel.com`.
- [ ] 3.4 `zot-registry.tf`: `random_password.registry_ctl_webhook_secret` +
      `doppler_secret`s (HMAC secret into `soleur-registry/prd`; Access token id/secret for
      the workflow). No no-default TF variable.
- [ ] 3.5 **P0 — extend the `-target=` allowlist** in
      `.github/workflows/apply-web-platform-infra.yml` with all four new resources, so the
      Access policy is created in the SAME apply as the ingress rule. Without this the
      merge publishes an unprotected control hostname.
- [ ] 3.6 Sweep the sibling allowlist assertions:
      `tests/scripts/test-destroy-guard-counter-web-platform.sh` and
      `.github/workflows/infra-validation.yml`.
- [ ] 3.7 **(deepen R5 — corrected target)** `check-cloudflare-token-drift.sh` has NO
      hardcoded token list. Add an `access_hostname_for()` case arm mapping
      `REGISTRY_CTL_ACCESS_TOKEN` → `registry-ctl.<base>`, and pin it with a case in
      `scripts/check-cloudflare-token-drift.test.sh`. An enumerated token with no mapping is
      reported UNVERIFIABLE and **fails** the scheduled drift run — so shipping the
      `doppler_secret` without this arm turns the fleet-wide detector red. Then run
      `scripts/followthroughs/token-drift-coverage-7159.sh` and require exit 0.
- [ ] 3.11 **(deepen R4)** Widen the cloud-init admitted-secret self-check to accept
      `n_total ∈ {4,5}` with the 5th admitted BY NAME, so the `doppler_secret` and the
      cloud-init edit can land in either order without a boot-fatal window. Unit-test both
      cardinalities. (Alternative recorded in the ADR: drop the HMAC secret and rely on the CF
      Access token alone.)
- [ ] 3.12 **(deepen R8)** Write the registry-ctl Access token to the SCOPED Doppler config,
      never `soleur/prd` root — the release workflow token reads root and could otherwise fire
      `recreate-zot`.
- [ ] 3.13 **(deepen R3)** Add a comment at the cloud-init edit site disclosing that
      `hcloud_server.registry` has no `ignore_changes=[user_data]` and `user_data` is ForceNew,
      so this edit arms a pending REPLACE in any untargeted plan — fatal against the current
      plaintext volume. Ensure no untargeted apply is prescribed anywhere.
- [ ] 3.14 **(deepen R12)** Before applying, dump the live tunnel ingress list and assert the
      plan preserves all three existing rules verbatim and in order (whole-list replacement).
- [ ] 3.15 **(deepen)** `depends_on` from `cloudflare_record.registry_ctl` to the Access policy
      so DNS cannot resolve ahead of admission control.
- [ ] 3.8 Add the fourth `connections` entry to `scripts/encryption-posture-ledger.json`
      (schema in the plan) and run `python3 scripts/lint-encryption-posture.py`.
- [ ] 3.9 Update `cloudflare_notification_policy.service_token_expiry`'s description to name
      the fourth token.
- [ ] 3.10 `terraform validate`; confirm the plan shows **no** create/replace/destroy of
      `hcloud_server.registry` or `hcloud_volume.registry`.

## Phase 4 — The workflow

- [ ] 4.1 `scripts/zot-restart-poll-classify.sh` — pure per-frame classifier mirroring
      `scripts/inngest-restart-poll-classify.sh`.
- [ ] 4.2 **(deepen R2 — success contract REWRITTEN)** `started_at` alone is disqualified
      (`--restart unless-stopped` advances it every ~17 s) and `container_id` alone is
      disqualified for `restart-zot` (`docker restart` reuses the container). Capture
      `{container_id, restart_count}` at trigger time and compare deltas:
      - `restart-zot` success ⟺ serving AND `restart_count` **stable** across the settle window.
      - `recreate-zot` success ⟺ `container_id` **changed** AND serving AND counter stable.
      - `restart_count` still advancing ⟹ `terminal_fail` (the loop is unfixed).
      `tests/scripts/test-zot-restart-poll-classify.sh` must cover all three.
- [ ] 4.3 `.github/workflows/restart-zot-registry.yml`: `workflow_dispatch` with a `choice`
      input (`restart-zot` | `recreate-zot`) selecting the **hook**; `push` registration
      trigger scoped to the file **plus** `if: github.event_name == 'workflow_dispatch'` on
      the job (#6425 — without it, editing the file on main restarts production);
      `concurrency` group; `timeout-minutes` > poll budget.
- [ ] 4.4 `TRIGGER_TS` / `FRESH_FLOOR` anchor; poll `zot-status`; settle-window re-read;
      corroborating reachability probe that treats **200 AND 401** as serving (no `curl -f`).
- [ ] 4.5 Distinct `lever_not_activated` verdict, never reported as a restart failure.

## Phase 5 — ADR + C4

<!-- lint-infra-ignore start -->
<!-- 5.1 enumerates the SSH/reboot alternatives the ADR REJECTS. Naming a rejected path
     in an Alternatives-Considered list is not prescribing a human-run step. -->

- [ ] 5.1 Write `ADR-169-…` (ordinal from 0.1): the R1 refutation, the Docker-socket
      root-equivalence disclosure, and all four rejected alternatives (web-1 relay, SSH
      ingress, Hetzner reboot, operator-key ProxyJump break-glass). Status `adopting`.

<!-- lint-infra-ignore end -->
- [ ] 5.2 `model.c4` — four edits: tunnel "THREE ingress rules" → four; the new control
      edge; `zotRegistry` description (add control plane, **fix cx33/8 GB → cx23/4 GB**,
      **retire the stale unorderable-type claim** with the 2026-08-04 probe);
      `zotRegistry -> betterstack` gains `SOLEUR_ZOT_RESTART`.
- [ ] 5.3 Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] 5.4 If the ordinal moved in 0.1, sweep plan + tasks + AC7 in the same edit.

## Phase 6 — Runbook + triage pointers

- [ ] 6.1 `registry-luks-recut-6929.md`: "try the restart lever first" pointer + `## Related`
      entry + **the activation-vehicle constraint** (this recut activates the lever; confirm
      the lever's code is on `main` before firing). **Banner untouched.**
- [ ] 6.2 **(deepen R9 — premise CORRECTED)** `scripts/zot-restart-loop-alarm.sh`: the
      crash-loop arm sets only `CAUSE=` and has NO remediation text; the
      `registry-host-replace` routing lives in the **`NIC_CAUSE`** arms, a different failure
      class a container restart cannot fix. Edit ONLY the crash-loop arm; leave every
      `NIC_CAUSE` arm untouched.
- [ ] 6.2b **(deepen R9)** `.github/workflows/scheduled-zot-restart-loop.yml` — the FIRE issue
      body is what the responder actually reads. Name the lever there.
- [ ] 6.2c **(deepen R10)** The `lever_not_activated` message must name its escalation path
      (recut = activation vehicle, #7277 = its blocker, #7247 = live crash-loop/disk). Assert
      on the message string in a test.
- [ ] 6.3 `zot-registry-revert.md`: name the lever as the "fix it as a zot problem" how.
- [ ] 6.4 Verify no `ssh ` appears in any runbook text added, and no human-executed step.

## Phase 7 — Follow-through enrollment

- [ ] 7.1 `scripts/followthroughs/registry-restart-lever-7278.sh` — passes only once
      `SOLEUR_ZOT_CONTROL` appears (provisioning-gated, not date-gated).
- [ ] 7.2 Add the `<!-- soleur:followthrough script=… earliest=… secrets=… -->` directive +
      `follow-through` label to the tracker.
- [ ] 7.3 Wire any new `secrets=` into `.github/workflows/scheduled-followthrough-sweeper.yml`.

## Phase 8 — Exit gate

- [ ] 8.1 Full `tests/scripts/` suite (the counter test fails loudest on a partial sweep).
- [ ] 8.2 Walk every Pre-merge AC (AC1-AC10, AC5a, AC5b) and record evidence per AC.
- [ ] 8.3 Confirm the `iac-routing-ack` comment survived plan edits.
