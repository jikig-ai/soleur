---
title: "fix: web-2 deploys abort at plugin-mount seeding (fchmodat2 EPERM) and the release workflow reports success anyway"
type: fix
date: 2026-10-19
slug: web2-plugin-mount-fchmodat2
branch: feat-one-shot-8743-web2-plugin-mount-fchmodat2
issue: 8743
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Overview

**Deepened:** 2026-10-19 via `soleur:deepen-plan` (sequential fallback — no
Task fan-out on this harness; halt gates 4.4–4.12 executed mechanically, all
green; verify-the-negative and self-audit passes run inline). Gate outcomes:
4.4 precedent-diff — `fan_out_to_peers` is the canonical HMAC/stdin-`--config`
precedent the `peers` merge mirrors; 4.45 — negative claims (`no re-fan`,
`no new privilege surface`, merge cannot recurse) grep-verified; 4.5 —
fired on token `unreachable` (error-slot label only), cleared per the
Network-Outage Note; 4.55 — `## Downtime & Cutover` added (zero-downtime by
construction); 4.6/4.7/4.10/4.11/4.12 — sections present and compliant.

Every web-platform deploy delivered to web-2 (soleur-web-2, 10.0.1.11) via the
`/hooks/deploy-peer` fan-out aborts in `apps/web-platform/infra/ci-deploy.sh`'s
plugin-mount seeding step: `docker cp soleur-plugin-seed:/opt/soleur/plugin/. "$PLUGIN_MOUNT_DIR/"`
fails with `fchmodat2 .claude-plugin: operation not permitted`. Onset
2026-09-24 07:19 UTC; **still live** — Better Stack rows through 2026-10-19
13:25 UTC (release v0.344.11, minutes before this plan was written). The
`deploy` job concludes `success` because it verifies `/health` through the
load balancer, answered by web-1 (weight 1); web-2 (weight 0) is invisible to
the run result.

**Root cause (repo-grounded):** `webhook.service` runs `ci-deploy.sh` as
`User=deploy` (uid 1000, `_UID=1000` on the failing journald rows). `docker cp`
untars client-side **as the invoking uid**, so it can only `fchmodat2` entries
the deploy user owns. A fresh-booted host seeds `/mnt/data/plugins/soleur` in
cloud-init **as root**, and `Dockerfile:387` (`RUN chown -R 1001:1001
/opt/soleur`) means the extracted tree lands **uid-1001-owned**. From that
boot onward, the deploy-user `docker cp` can neither delete the foreign-uid
entries (`find -mindepth 1 -delete` is silenced by `|| true`) nor re-chmod them
→ `fchmodat2` EPERM → `plugin_seed_copy_failed` → exit 1. web-1 is unaffected
because its mount tree predates the cloud-init seed block and is deploy-owned
(uid 1000). The defect is **systemic to every fresh-booted web host** — it
survived web-2's own 09-25 and 09-30 replacements, and will strike the next
`-replace` of any host.

This plan (a) makes the plugin-mount seed **ownership-agnostic and
self-healing**, and (b) closes the observability gap so a single-host deploy
failure reaches the release run result — realizing ADR-068 constraint (c),
which recorded per-host state verification as "private-net + peer-driven" but
was never built.

## Research Insights

### Premise Validation (Phase 0.6 — checked live 2026-10-19)

| Cited premise | Result |
|---|---|
| #8743 open | OPEN — labels `priority/p1-high`, `type/bug`, `domain/engineering`; milestone `Phase 4: Validate + Scale` |
| `apps/web-platform/infra/ci-deploy.sh` seed block | Present — `docker create`+`docker cp`+`docker rm` at the `Seeding plugin mount from image...` block; abort via `final_write_state 1 "plugin_seed_copy_failed"` |
| #8660 (fresh-boot zot-by-bake) | MERGED 2026-09-24T03:22Z — touched `cloud-init.yml` + `server.tf` user_data; correlated with a web-2 replace that morning (follow-through `web-fresh-boot-zot-8651.sh` exists for exactly that validation) |
| #8600 (retire host GHCR read path) | MERGED 2026-09-23T18:31Z |
| #8691 (watchdog dispatch clock) | MERGED 2026-09-24T14:31Z — runs its clock on every deployed web host; web-2's copy is stale because deploys abort |
| `scripts/betterstack-query.sh` | Present; needs `doppler run -p soleur -c prd_terraform` injection — ran live for this plan |
| Better Stack `fchmodat2` rows | 16 rows at filing; confirmed STILL FIRING on soleur-web-2 as of 2026-10-19T13:25Z (v0.344.11) — this is a chronic live outage, not a historical event |
| web-2 current server | `hcloud_server.web["web-2"]`, born 2026-09-25 (per #9151 plan), replaced again 2026-09-30 (run 36743565651 "re-pin web-2's SSH host key after the 2026-09-30 replacement") — same defect recurred each birth |
| Peer delivery channel | `terraform_data.deploy_pipeline_fix_web2` (SSH sibling via bastion forward through web-1) exists since #9151 (apply run 36646627695, 2026-09-29) — ci-deploy.sh updates DO reach web-2 |

### Property List (Phase 0.6b)

- P1: `ci-deploy.sh`'s plugin-mount seed succeeds regardless of the mount
  tree's existing ownership — a foreign-uid or root-seeded tree cannot wedge it.
- P2: the fix is self-healing — the next deploy after delivery repairs a
  wedged host with no host replace and no side-channel repair step.
- P3: the discriminating evidence (who owned the tree, what failed) lands in
  the observable channel (journald → Better Stack), because the true ownership
  on web-2 cannot be read directly without SSH.
- P4: a `deploy-peer` host's post-acceptance deploy verdict reaches the
  release workflow — a 202 (spawn-acceptance) followed by an async exit 1 must
  be visible in the run result.
- P5: no new credential or delivery surface — reuse the private-net
  `:9000` HMAC channel and the existing FILE_MAP/apply delivery.

### Mechanism minimality check (Phase 0.6b)

| Proposed mechanism | Property | Already covered by? | Verdict |
|---|---|---|---|
| `docker create`+`docker cp` unchanged + `sudo chown` pre-step | P1 | deploy's sudoers is exact-argv-pinned (`deploy-inngest-bootstrap.sudoers`); the chown grant pins `/usr/bin/chown 1001:1001 /mnt/data/workspaces` only; sudoers is root-managed (deliberately NOT in FILE_MAP) — a new grant is a terraform-delivered artifact | CUT — heavier than the alternative and adds a privilege surface |
| Seed via one `docker run --rm -u 0 --entrypoint /bin/sh -v $MOUNT:/plugin-mount` container-side | P1, P2, P3 | deploy is docker-group = documented root-equivalent (sudoers file's own canonical statement); the seed container can clear/copy/chmod/chown regardless of existing uid | KEEP — no new privilege surface, self-heals in place |
| cloud-init.yml post-seed `chown -R deploy:deploy` | P1 on FUTURE births only | cannot repair the running web-2 (`ignore_changes=[user_data]`) | CUT as a fix; noted as optional hygiene — the container-side seed makes it unnecessary |
| Peer's async verdict surfaced via `/hooks/deploy-status` peer merge on web-1 (private-net read, shared HMAC, bounded) | P4, P5 | ADR-068 constraint (c) pre-decided exactly this: "per-host state verification is private-net + peer-driven (query 10.0.1.11:9000)"; `fan_out_to_peers` already reads the same hooks.json secret as the deploy user | KEEP — the recorded design, never implemented |
| New tunnel ingress `deploy-web-2.` + CF Access app | P4 | adds the per-host-tunnel shape ADR-068 explicitly REJECTED (option A) | CUT |
| Better Stack query from the release workflow | P4 | async ingest latency + string-fragile + needs query creds in CI | CUT — the peer read is authoritative and synchronous |

### Key file map (verified against this worktree)

- `apps/web-platform/infra/ci-deploy.sh` — `PLUGIN_MOUNT_DIR` default
  `/mnt/data/plugins/soleur`; seed block at `Seeding plugin mount from
  image...`; `fan_out_to_peers()` (HMAC over shared `webhook_deploy_secret`
  read from `/etc/webhook/hooks.json`, curl via stdin `--config`); deploy arm
  calls `fan_out_to_peers` at the end, then `final_write_state 0 "ok"` /
  `"ok_peer_fanout_degraded"`; `write_state`/`final_write_state` own the state
  file (`/var/lock/ci-deploy.state`).
- `apps/web-platform/infra/cat-deploy-state.sh` — `/hooks/deploy-status`
  reporter (runs as deploy); merges state file + live probes into one JSON via
  final `jq -nc` block. New `peers` map lands here.
- `apps/web-platform/infra/cloud-init.yml` — runcmd seeds
  `/mnt/data/plugins/soleur` via root `docker cp` (birth path, works);
  `chown -R deploy:deploy /mnt/data` runs BEFORE the seed → the seed's
  1001-ownership survives. Stays unchanged.
- `apps/web-platform/Dockerfile` — `COPY _plugin-vendored /opt/soleur/plugin`;
  `RUN chown -R 1001:1001 /opt/soleur`; `USER soleur` (uid 1001); `CMD` (no
  ENTRYPOINT) — `docker run --entrypoint /bin/sh -u 0` works; image carries
  `/bin/sh`, `find`, `cp`, `stat`, `printf` (debian slim).
- `apps/web-platform/infra/webhook.service` — `User=deploy`, `ProtectSystem=strict`,
  `ReadWritePaths=/mnt/data ...` (bind mounts are daemon-side; unaffected).
- `apps/web-platform/infra/hooks.json.tmpl` — `deploy` hook passes `peers` →
  `SOLEUR_DEPLOY_PEERS`; `deploy-peer` hook deliberately does NOT (no re-fan);
  `deploy-status` is GET + `include-command-output-in-response-on-error`.
- `.github/workflows/web-platform-release.yml` — `Deploy via webhook` POSTs
  `{"command": ..., "peers": "10.0.1.10,10.0.1.11"}` to `deploy.soleur.ai`
  (→ web-1 only); `Verify deploy script completion` polls
  `/hooks/deploy-status` (web-1) for `exit_code==0 && tag==v$VERSION` with
  `-1/-2/-3` tolerances; `Verify deploy health and version` polls `app.soleur.ai/health`
  (LB → web-1). `STATUS_POLL_*` constants pinned to `IN_FLIGHT_CEILING_S=4800`
  by the `Pre-rerun lock probe` runtime assertion.
- `apps/web-platform/infra/ci-deploy.test.sh` — mock docker trace
  (`DOCKER_TRACE:*`) records `docker cp`; `PLUGIN_MOUNT_DIR` redirects under
  MOCK_DIR; `cloud-init-plugin-seed.test.sh` exercises the real `docker cp`
  seed (after this change it covers cloud-init.yml only — header comment
  updated).
- `apps/web-platform/infra/web-hosts-fanout-parity.test.sh` — pins
  `WEB_HOST_PRIVATE_IPS` == `var.web_hosts` private_ips (drift = web-2
  silently misses deploys).
- `scripts/betterstack-assert-absence.sh` — exit-0 `clean` only with a live
  positive-control read; the soak-probe shape the follow-through script mirrors.
- `scripts/followthroughs/` + directive convention `<!-- soleur:followthrough
  script=... earliest=... secrets=... -->` (precedent: `anthropic-double-bill-8611.sh`
  already carries `secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,
  BETTERSTACK_QUERY_PASSWORD` — the sweeper plumbing exists).

### Institutional learnings applied

- `2026-03-20-ci-deploy-reliability-and-mock-trace-testing.md` — the mock-trace
  harness is the test surface for ci-deploy.sh argv changes.
- ADR-068 §deploy fan-out amendment — constraints (a) no re-fan, (b) fold into
  response, (c) peer-driven private-net verification. This plan implements (b)+(c)
  for the async arm.
- `deploy-status-debugging.md` reason taxonomy — `plugin_seed_copy_failed` is
  absent from the table; added.
- `hr-observability-layer-citation` / `hr-no-ssh-fallback-in-runbooks` — all
  diagnosis + verification paths are no-SSH (Better Stack rows, deploy-status
  peers map, HMAC-gated hooks only).
- Incident → PIR mandatory (constitution; `ship` Phase 5.5 Incident-PIR Gate) —
  a 25-day half-fleet deploy outage IS a production incident; the post-mortem
  is a deliverable of THIS plan.
- `2026-09-24-the-gate-the-issue-blamed-was-never-reached.md` (landed by #8660)
  — verify which gate actually fires before blaming it; here the abort site IS
  confirmed by live rows, but the uid-1001 ownership is inferred from
  Dockerfile+cloud-init+systemd units, so the seed container emits the owning
  uid/gid of `/plugin-mount` and a sample entry BEFORE mutating (in-surface
  discriminating probe).

## Implementation Phases

### Phase 1 — Ownership-agnostic plugin-mount seed (root cause fix)

In `apps/web-platform/infra/ci-deploy.sh`, replace the `docker create` +
`docker cp` + `docker rm` seed block with ONE container-side seed:

- Keep the pre-flight `docker rm -f soleur-plugin-seed` (leftover container
  cleanup) and `mkdir -p "$PLUGIN_MOUNT_DIR"`.
- Replace the extract step with:

```bash
if ! docker run --rm -u 0 --entrypoint /bin/sh \
      -v "$PLUGIN_MOUNT_DIR":/plugin-mount \
      -e "SEED_TAG=$TAG" \
      "$VERIFIED_REF" -c '
        set -eu
        DST=/plugin-mount
        # In-surface discriminating probe BEFORE mutation (journald → Better
        # Stack): the uid/gid facts that adjudicate the fchmodat2 root cause
        # cannot be read off-box any other way.
        echo "PLUGIN_SEED_PROBE dst_owner=$(stat -c %u:%g "$DST" 2>/dev/null || echo unknown) marker=$(stat -c %u:%g "$DST/.claude-plugin" 2>/dev/null || echo absent) findmnt=$(findmnt -no SOURCE "$DST" 2>/dev/null || echo unknown)"
        find "$DST" -mindepth 1 -delete
        cp -a /opt/soleur/plugin/. "$DST"/
        printf "%s\n" "seeded $(date -u +%Y-%m-%dT%H:%M:%SZ) tag=$SEED_TAG" > "$DST/.seed-complete"
      '; then
  final_write_state 1 "plugin_seed_copy_failed"
  exit 1
fi
```

- `-u 0` overrides the image's `USER soleur` — the seed must clear/copy a tree
  of ANY ownership (root in container can). `--entrypoint /bin/sh` pins the
  interpreter so a future Dockerfile ENTRYPOINT cannot reinterpret the args.
- The sentinel moves INSIDE the container (same atomic-position semantics —
  written last; a killed run leaves it absent).
- `cp -a` preserves the image's 1001 ownership — now harmless: every future
  clear+copy is container-side root, and the app container only reads the
  `ro` mount (world-readable). Deploy-side `find -delete` + host-side
  `.seed-complete` write are deleted (superseded by the container).
- Update the stale comments (`"single POSIX-portable cleanup form shared with
  cloud-init.yml"`) to state the new contract: ci-deploy seeds container-side
  (ownership-agnostic, self-healing); cloud-init seeds host-side as root
  (works once at birth, unrepaired thereafter — acceptable because the next
  deploy's container-side seed rewrites it).
- `cloud-init-plugin-seed.test.sh` header comment notes it now pins
  cloud-init.yml's seed only.
- Delivery: `apply-deploy-pipeline-fix.yml` push arm + the
  `terraform_data.deploy_pipeline_fix_web2` bastion sibling deliver the new
  `ci-deploy.sh` to both hosts; the FIRST web-2 deploy after delivery
  self-heals the mount (no `-replace`, no SSH).

### Phase 2 — Persist the fan-out peer list (enables Phase 3)

- `ci-deploy.sh` `write_state`/`final_write_state` gains a `fanout_peers`
  field: the effective `SOLEUR_DEPLOY_PEERS` list (minus self, same filter as
  `fan_out_to_peers`) recorded when a deploy fans out. Absent on
  `deploy-peer`-received runs (no re-fan → no field → `peers` merge is
  inert on web-2, so the merge cannot recurse).
- `cat-deploy-state.sh` gains `peers_json()`: reads `fanout_peers` from the
  state file; for each peer, `curl --max-time 3` `GET http://<peer>:9000/hooks/
  deploy-status` signed with the shared secret read from hooks.json (identical
  HMAC-over-empty-body + stdin `--config` pattern as `fan_out_to_peers`);
  emits `peers: {"<ip>": <peer's JSON>} | {"<ip>": {"error":"unreachable|http_<code>|not_json"}}`.
  Bounded, fail-open for the merge (a peer error fills the slot, never fails
  the hook — the WORKFLOW decides the verdict).
- The peer slot embeds the peer's WHOLE status JSON — including its
  `ci_deploy_sha256` — so the same field answers "is web-2's script current"
  (the parity read `scripts/check-deploy-script-parity.sh` formalizes).

### Phase 3 — Per-host deploy verdict in the release run (observability gap)

In `.github/workflows/web-platform-release.yml`, add a `Verify peer deploy
completion` step AFTER `Verify deploy script completion`:

- Poll the SAME `deploy.soleur.ai/hooks/deploy-status` endpoint on the same
  `STATUS_POLL_MAX_ATTEMPTS`/`STATUS_POLL_INTERVAL_S` budget (peer's own
  wrapper is also 4800s; the lock-probe arithmetic is untouched).
- Expected peer set = `WEB_HOST_PRIVATE_IPS` minus the primary ingress IP
  (`10.0.1.10`, the host `deploy.` resolves to — pinned by
  `web-hosts-fanout-parity.test.sh`).
- Per expected peer IP: read `.peers["<ip>"]` —
  `exit_code==0 && tag=="v$VERSION"` → pass;
  `exit_code` ∈ {-1,-2,-3} or slot missing → keep polling (peer's deploy
  starts when web-1's ends; async by design);
  any other `exit_code` or `{"error":...}` slot → `::error::peer <ip>
  deploy failed (reason=<r>)` + `exit 1`.
- After the budget with any peer unresolved → `::error::peer <ip> did not
  report completion for v$VERSION` + `exit 1`.
- **Fail-closed on the verdict.** Ruled by CTO agent, 2026-10-19: the peer
  gate FAILS the step rather than warning — a warn-only arm reproduces the
  exact silent-failure class this issue exists to kill; the
  `ok_peer_fanout_degraded` precedent already treats a degraded peer as a
  report-worthy state, and a failed weight-0 standby is real (stale build,
  absent watchdog clock) even while serving impact is zero.

### Phase 4 — Post-incident report + follow-through enrollment

- PIR: `knowledge-base/engineering/operations/post-mortems/2026-10-19-web2-plugin-mount-fchmodat2-postmortem.md`
  (constitution: incident detected → PIR before merge; `ship` Phase 5.5
  Incident-PIR Gate enforces). Follow-ups filed as issues.
- Follow-through: `scripts/followthroughs/web2-plugin-seed-8743.sh` —
  mirrors `betterstack-assert-absence.sh` semantics: exit 0 only when (a) zero
  `fchmodat2` rows on soleur-web-2 since the fix deploy AND (b) a positive
  control (the host still ships `ci-deploy`/`webhook` rows) AND (c) a post-fix
  `PLUGIN_SEED_PROBE`/`Deploy succeeded`-class row exists for web-2. Exit 2/3
  sentinels per the sweep contract. Directive + `follow-through` label on
  #8743: `<!-- soleur:followthrough script=scripts/followthroughs/web2-plugin-seed-8743.sh earliest=<merge+2d> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->`
  (secrets already plumbed into `scheduled-followthrough-sweeper.yml` by
  precedent).
- ADR-068 amendment: one implementation note recording that constraint (b)'s
  fold-into-response semantics for the ASYNC peer verdict is realized by the
  `peers` status merge (the original text covered only synchronous accept).
- `deploy-status-debugging.md`: add `plugin_seed_copy_failed` row +
  `ok_peer_fanout_degraded`/`peers` field documentation.

## Files to Edit

- `apps/web-platform/infra/ci-deploy.sh` — container-side seed; `fanout_peers` state field.
- `apps/web-platform/infra/ci-deploy.test.sh` — trace assertions for the new `docker run` argv + regression pins (no `docker cp soleur-plugin-seed` survives; `-u 0`, `--entrypoint /bin/sh`, `-v` mount present).
- `apps/web-platform/infra/cat-deploy-state.sh` — `peers_json()` + merge into the response.
- `apps/web-platform/infra/cat-deploy-state.test.sh` — peers coverage (peer-ok, peer-failing, unreachable, absent-fanout_peers).
- `.github/workflows/web-platform-release.yml` — `Verify peer deploy completion` step.
- `apps/web-platform/infra/cloud-init-plugin-seed.test.sh` — header comment (cloud-init-only coverage).
- `apps/web-platform/infra/web-hosts-fanout-parity.test.sh` — pin the expected-peer-IP derivation the new step uses (or a sibling assertion file if the parity guard's scope doesn't fit).
- `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` — reason-taxonomy row + `peers` field.
- `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md` — implementation-note amendment.

## Files to Create

- `knowledge-base/engineering/operations/post-mortems/2026-10-19-web2-plugin-mount-fchmodat2-postmortem.md` — PIR.
- `scripts/followthroughs/web2-plugin-seed-8743.sh` + `scripts/followthroughs/web2-plugin-seed-8743.test.sh` — soak probe.

## Downtime & Cutover

Offline-inducing operation: none on the serving path. The `ci-deploy.sh` /
`cat-deploy-state.sh` changes ride the existing infra-config delivery channel
(`apply-deploy-pipeline-fix.yml` push arm + `deploy_pipeline_fix_web2` bastion
sibling) — file replacement only, no host replace, no container swap induced by
this change itself. The `docker run` seed runs inside the already-gated
canary→swap sequence on each host's own deploy; a broken seed aborts before
the swap, so the OLD container keeps serving (the existing downtime-safe abort
shape, `final_write_state 1` + exit 1, is preserved). Residual risk: the new
release-workflow peer gate FAILS future release runs until every expected peer
verifies — a deliberate gate, not downtime: serving is unaffected while the
run reports red. Rollback path: revert the two files and re-dispatch the same
apply workflow (the channel is self-describing; no host state to unwind).

## Network-Outage Note (gate 4.5 — fired on token `unreachable`)

Fired only on the error-slot label, not on a connectivity symptom — this is an
ownership/observability defect, not an SSH/network diagnosis. Layer status for
completeness: L3 firewall — `hcloud_firewall.web` default-denies :9000 public
(`firewall-9000-deny.test.sh` pins; private-net only by design, unchanged by
this plan); L3 DNS/routing — the peer GET uses literal private IPs, no DNS;
L7 TLS — n/a (plain HTTP + HMAC on private net, same as the existing POST);
L7 application — webhook already serves `deploy-status` on both hosts. No
network remediation is proposed or needed; nothing in this plan requires an
SSH-capable egress allowlist check. SOLEUR_RULE_APPLIED
rule=hr-ssh-diagnosis-verify-firewall — fired on label, cleared on inspection.

## User-Brand Impact

- **If this lands broken, the user experiences:** the deploy path wedges on
  BOTH hosts — every release reports failed or, worse, the same silent
  partial-deploy this issue exists to kill; users keep getting stale code with
  no surface telling anyone.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the
  `peers` status field adds peer IPs + deploy-state JSON to a response already
  carrying equivalent host data behind HMAC + CF-Access on the private net —
  no new exposure class; no user data flows on this path.
- **Brand-survival threshold:** aggregate pattern — the blast radius of a
  broken change is the whole deploy pipeline (fleet-wide stale code), not one
  user's data.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Find why `fchmodat2` returns EPERM on web-2's `$PLUGIN_MOUNT_DIR`. Candidates are the mount's ownership or mode, a read-only or `nosuid` remount, or a filesystem difference from web-1. Use the no-SSH infra-config status and inventory hooks, and determine whether the 07:19 onset coincides with the web-2 fresh-boot changes merged overnight (#8660 at 03:22 UTC, #8600)." | Overview root cause + Phase 1 + `PLUGIN_SEED_PROBE` in-surface emit + Research Insights premise table | mapped |
| 2 | "Make the release workflow fail, or at least report per host, when a `deploy-peer` host exits non-zero, so a single-host deploy failure is visible in the run result." | Phase 2 + Phase 3 + Guard Contract | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|---|---|---|
| Container-side `docker run` seed | ask 1 (the EPERM repair it enables) | inferred — justification: the minimal mechanism that satisfies P1+P2 without a new sudoers surface; the issue asks for root-cause and fix, mechanism is the planner's call |
| `fanout_peers` + `peers` status merge | ask 2 + ADR-068 constraint (c) | inferred — justification: pre-decided design recorded in the ADR, never built |
| PIR post-mortem | — | inferred — justification: constitution "incident → PIR always" + `ship` Phase 5.5 gate; 25-day production incident |
| Follow-through soak script | — | inferred — justification: `ship` soak-gated enrollment gate for the "rows stop" AC |
| ADR-068 amendment note + runbook row | — | inferred — justification: recorded-architecture accuracy (wg-architecture-decision-is-a-plan-deliverable) |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform`, `.github`, `knowledge-base`(+`scripts`)
- Planned files: ~11 | Estimated changed lines: ~450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Observability

```yaml
liveness_signal:    # what / cadence / alert_target / configured_in
  what: per-host deploy verdict — `.peers["<ip>"]` merged into /hooks/deploy-status by cat-deploy-state.sh; peer state written by each host's own ci-deploy.sh
  cadence: every release's `deploy` job (poll loop) + any manual /hooks/deploy-status read
  alert_target: `Verify peer deploy completion` step fails the GitHub release run; PLUGIN_SEED_PROBE rows → Better Stack
  configured_in: .github/workflows/web-platform-release.yml + apps/web-platform/infra/cat-deploy-state.sh
error_reporting:
  destination: /var/lock/ci-deploy.state (per host) → deploy-status `.peers`; journald → Vector → Better Stack soleur-inngest-vector-prd (tags ci-deploy, webhook)
  fail_loud: peer `exit_code` non-zero, `error` slot, or missing slot fails the release step
failure_modes:
  - mode: foreign-uid plugin mount (fchmodat2 EPERM on the old path); detection: PLUGIN_SEED_PROBE dst_owner/marker fields + peers exit!=0; alert_route: release deploy job fail + Better Stack
  - mode: peer webhook down / peer not fanned; detection: peers["<ip>"].error=unreachable or absent slot; alert_route: release deploy job fail
  - mode: stale ci-deploy.sh on web-2; detection: peers map carries the peer's ci_deploy_sha256 vs repo sha256; alert_route: scripts/check-deploy-script-parity.sh
logs:
  where: journald on each host → Vector → Better Stack (source soleur-inngest-vector-prd); deploy state JSON at /var/lock/ci-deploy.state
  retention: vendor-managed
discoverability_test:
  command: git grep -l "fanout_peers" -- apps/web-platform/infra/ci-deploy.sh
  expected_output: "apps/web-platform/infra/ci-deploy.sh"
```

## Encryption Posture

```yaml
at_rest: no new persistent store — the `peers` merge reads an existing state
  file served by an existing hook.
in_transit: new GET on an EXISTING edge — web-1 → `http://<peer>:9000/hooks/
  deploy-status` over the private net (10.0.1.0/24), HMAC-signed (shared
  `webhook_deploy_secret`), same posture as the deploy-peer POST it mirrors;
  `hcloud_firewall.web` default-denies :9000 on the public interface
  (firewall-9000-deny.test.sh pins it). does_not_defend: passive on-net
  observer could read the status JSON (same exposure as the POSTs it joins —
  accepted by ADR-068). disclosed_as: private-net internal.
exception: not applicable — no new mechanism, no plaintext downgrade vs the
  existing edge.
```

## Guard Contract

### Guard 1 — Per-host deploy verdict gate (`Verify peer deploy completion`)

**Property.** For every IP in `WEB_HOST_PRIVATE_IPS` other than the deploy.
ingress host, the release run fails unless that peer's `deploy-status`
reports `exit_code==0` and `tag==v$VERSION` for THIS release.

**Assembly.** Chokepoint: `cat-deploy-state.sh`'s `peers` merge (the only path
peer verdicts take into the polled response) + the new workflow step (the only
consumer that must interpret it). Members: every IP in the workflow's
`WEB_HOST_PRIVATE_IPS` env minus `10.0.1.10` — the parity assertion
(`web-hosts-fanout-parity.test.sh`) binds that env to `var.web_hosts`, so a
future web-3 joins the guard automatically.

**Mutation matrix.**

| Mutation | Expected |
|---|---|
| Peer exits non-zero (e.g. `plugin_seed_copy_failed`) | gate RED |
| Peer slot absent from `.peers` at budget end (fanout_peers unwritten — stale ci-deploy.sh on web-1) | gate RED (fail-closed drift surfacing) |
| Second peer added (`web-3`) that never deploys | gate RED — a gate that stops at the first member is itself the defect class |
| Guard's own dispatch neutered (step reads `.peers` as `{}` unconditionally) | RED — every expected IP fails the missing-slot arm |
| Suite mutation: assertion counts `-1/-2/-3` as terminal-fail | RED — would break the sanctioned async-poll contract |

**Harness rows.** Must-PASS: all expected peers `exit_code==0`+tag → GREEN;
single-peer fleet (`WEB_HOST_PRIVATE_IPS` = one IP) → GREEN vacuously (the
dormant single-host path ADR-068 requires byte-identical).

**Anchor.** The gate compares the peer's self-reported state — a peer that
lies about its own exit_code is out of scope by design (integrity of the
channel is the HMAC + private net + read-only hook); what the gate pins is
that the verdict is DELIVERED, not that it is truthful.

## Architecture Decision (ADR/C4)

### ADR

Amend `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md`
— add an implementation-note amendment recording that the async peer-verdict
half of constraint (b) ("the forward result folds into the webhook's HTTP
response") is realized by the `peers` status merge + the release-workflow
per-host gate (the original text only realized synchronous 202-acceptance).
No new ordinal — this is recorded-decision completion, not a new decision.

### C4 views

No `.c4` change. Enumeration checked against `model.c4`: the web-2 host, its
workspaces volume, the deploy/webhook path and the zot-registry edge are all
already modeled (model.c4 descriptions cover `hcloud_server.web["web-2"]`,
the deploy fan-out, and the webhook listener). No new external actor, external
system, container, or access relationship is introduced — the peer GET is a
new verb on an existing private-net edge (`web-1 → web-2:9000` already carries
the deploy-peer POST). `views.c4`/`spec.c4` unaffected.

## Test Scenarios

- ci-deploy.test.sh: seed arm emits `docker run --rm -u 0 --entrypoint /bin/sh`
  argv; `docker cp soleur-plugin-seed` absent from the script (grep pin);
  seed failure path still writes `plugin_seed_copy_failed`.
- cat-deploy-state.test.sh: `fanout_peers` absent → no `peers` key;
  peer ok → slot carries peer JSON; peer curl fails → `error` slot (never hook
  failure); peer non-JSON body → `not_json`.
- Workflow: a sibling assertion pins the step name + the jq field paths it
  reads (`web-hosts-fanout-parity.test.sh` or a new `web-platform-release`
  assertion file).
- Live (post-merge, no-SSH): next release → `PLUGIN_SEED_PROBE` row on
  soleur-web-2 (Better Stack), `peers["10.0.1.11"].exit_code == 0` in the
  deploy-status body, zero new `fchmodat2` rows.

## Acceptance Criteria

- [ ] AC1: `ci-deploy.sh` seeds the plugin mount via a single `docker run -u 0 --entrypoint /bin/sh` container-side step; no `docker cp soleur-plugin-seed` remains; `.seed-complete` is written inside the container, last.
- [ ] AC2: `PLUGIN_SEED_PROBE` emits dst ownership + `.claude-plugin` ownership + mount source before mutating (journald → Better Stack).
- [ ] AC3: A deploy whose mount tree is foreign-uid-owned (root/1001) completes the seed — i.e., the mechanism never shells the copy out to the deploy uid.
- [ ] AC4: `write_state` persists `fanout_peers`; `cat-deploy-state.sh` emits a `peers` map with bounded (≤3s) per-peer fetches and discriminating error slots.
- [ ] AC5: `web-platform-release.yml` fails `Verify peer deploy completion` on any expected peer not reporting `exit_code==0` + `tag==v$VERSION`; `-1/-2/-3`/absent are polled, everything else is terminal.
- [ ] AC6: PIR committed at `knowledge-base/engineering/operations/post-mortems/2026-10-19-web2-plugin-mount-fchmodat2-postmortem.md`.
- [ ] AC7: `scripts/followthroughs/web2-plugin-seed-8743.sh` + test committed; `<!-- soleur:followthrough ... -->` directive + `follow-through` label land on #8743.
- [ ] AC8: ADR-068 carries the implementation-note amendment; `deploy-status-debugging.md` gains `plugin_seed_copy_failed` + `peers` rows.
- [ ] AC9 (live, post-delivery): a release run after `apply-deploy-pipeline-fix` delivery shows web-2 `peers["10.0.1.11"].exit_code==0` AND Better Stack shows zero new `fchmodat2` rows for soleur-web-2 — verified via `scripts/betterstack-query.sh`, not SSH.

## Domain Review

**Domains relevant:** engineering (infrastructure/deploy pipeline)

### Engineering

**Status:** reviewed (inline — no Task fan-out on this harness; sequential fallback)
**Assessment:** Deploy-pipeline defect + observability gap on an existing
surface. No architectural fork: ADR-068 already decided private-net peer
verification; this completes it. CTO rulings applied inline (fail-closed peer
gate; container-side seed over a new sudoers grant).

**Domains not triggered:** marketing/legal/sales/finance/support — none;
operations — no vendor/procurement change; product — no UI.

### Product/UX Gate

**Tier:** none — Files-to-Edit/Create contain no UI-surface path (mechanical
scan of `components/**`, `app/**/page.tsx`, `*.njk`, `*.html` → zero matches).
**Pencil available:** N/A (no UI surface)

## Enhancement Summary

Deepen-plan (sequential fallback) added: `## Downtime & Cutover` (gate 4.55),
`## Network-Outage Note` (gate 4.5 label-fire), the Deepened provenance line,
and frontmatter threshold normalization to the `aggregate pattern` enum.

### Key Improvements

- Live-confirmed the incident is still firing (Better Stack rows through
  2026-10-19T13:25Z) — elevated from "historic report" to chronic outage.
- Identified the systemic root cause (root-run cloud-init seed → uid-1001
  tree vs uid-1000 deploy) and chose the self-healing container-side seed
  over a new sudoers grant (no new privilege surface).
- Grounded ask #2 in ADR-068 constraint (c) — the recorded-but-unbuilt
  private-net peer verification — rather than inventing a new channel.

## Non-Goals / Deferred

- Re-architecting fan-out ordering (parallel peer deploys) — rejected here;
  serial fan-out is the recorded design; the peer poll budget covers it.
- A generic "any host surfaces any state" introspection API — YAGNI; the
  `peers` map is scoped to the deploy verdict the issue needs.
- cloud-init.yml seed-path rewrite — cut by mechanism minimality (the
  container-side seed makes birth-time ownership moot).
