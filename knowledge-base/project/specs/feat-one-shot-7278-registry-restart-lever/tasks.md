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

## Phase 1 — Hook contract + scripts (RED first)

- [ ] 1.1 Write failing tests before implementation (`cq-write-failing-tests-before`):
  - [ ] 1.1.1 `tests/scripts/test-registry-control-hooks-shape.sh` — exactly 3 hooks;
        **zero** `pass-environment-to-command` entries across all three (the AC3 structural
        guarantee); every hook has an HMAC `trigger-rule` +
        `trigger-rule-mismatch-http-response-code: 403`; the 2 mutating hooks are async
        (`include-command-output-in-response: false`, `success-http-response-code: 202`).
  - [ ] 1.1.2 `recreate-zot.sh` refuses when `/var/lib/zot` is not backed by
        `/dev/mapper/registry` (feed it a non-mapper mount source).
  - [ ] 1.1.3 `hcloud_firewall.registry` still declares zero inbound rules.
- [ ] 1.2 Implement `restart-zot.sh` (`docker restart zot`).
- [ ] 1.3 Implement `recreate-zot.sh`: re-assert the `findmnt` gate → pull pinned digest →
      `docker rm -f zot` → re-run the **exact** baked run-line (memory cap, journald log
      driver, volume mounts, `-p 0.0.0.0:5000:5000`). Never a retyped variant.
      `docker restart` does NOT apply a new image — that is why this action exists.
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
- [ ] 3.7 Register the new token in `scripts/check-cloudflare-token-drift.sh` (#7071 trap),
      then run `scripts/followthroughs/token-drift-coverage-7159.sh` and require exit 0.
- [ ] 3.8 Add the fourth `connections` entry to `scripts/encryption-posture-ledger.json`
      (schema in the plan) and run `python3 scripts/lint-encryption-posture.py`.
- [ ] 3.9 Update `cloudflare_notification_policy.service_token_expiry`'s description to name
      the fourth token.
- [ ] 3.10 `terraform validate`; confirm the plan shows **no** create/replace/destroy of
      `hcloud_server.registry` or `hcloud_volume.registry`.

## Phase 4 — The workflow

- [ ] 4.1 `scripts/zot-restart-poll-classify.sh` — pure per-frame classifier mirroring
      `scripts/inngest-restart-poll-classify.sh`.
- [ ] 4.2 `tests/scripts/test-zot-restart-poll-classify.sh` — a fresh-`started_at` frame with
      a non-serving zot must classify `terminal_fail`; an `exit_code=0` frame whose
      `started_at < FRESH_FLOOR` must classify `predates`, never `success`.
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
- [ ] 6.2 `scripts/zot-restart-loop-alarm.sh`: re-point the crash-loop remediation from
      `registry-host-replace` to the lever, with the not-yet-activated caveat. Re-read first;
      cite content anchors, not line numbers.
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
